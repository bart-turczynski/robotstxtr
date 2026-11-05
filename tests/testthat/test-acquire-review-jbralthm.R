# ROBO-jbralthm, review of MR !78: how ssrfr's limits and its
# duplicate-Location rule reach robotstxtr's outcomes. The fake cases drive
# the hop loop through helper-fake-ssrfr.R; the wire cases fetch a loopback
# webfakes server through the real ssrfr, so the fake is held to what ssrfr
# does. No external network.

# --- Loopback harness ---------------------------------------------------------

# Serve `handler(req, res)` at every path; reopen loopback on its port in the
# acquisition policy for this test only. Returns the robots URL.
local_wire_server <- function(handler, env = parent.frame()) {
  skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$get(webfakes::new_regexp("^/"), handler)
  server <- webfakes::local_app_process(app, .local_envir = env)
  url <- server$url("/robots.txt")
  port <- as.integer(sub("^http://127\\.0\\.0\\.1:([0-9]+)/.*$", "\\1", url))
  local_loopback_policy(port, env = env)
  url
}

big_body <- function(n = 2000L) strrep("x", n)

fake_router <- function(routes) {
  function(req) {
    handler <- routes[[req$url]]
    if (is.null(handler)) {
      stop(sprintf("unexpected request URL in fake: %s", req$url))
    }
    handler(req)
  }
}

redirect_to <- function(location, status = 301L) {
  force(location)
  force(status)
  function(req) fake_response(status, headers = list(Location = location))
}

evidence_of <- function(url = "http://a/x") {
  robots_evaluate_url_v1(url, "Googlebot", "google", "google")$evidence
}

# --- Finding 1: a non-2xx over max_bytes keeps its status outcome ------------

test_that("a non-2xx body over max_bytes is classified by its status", {
  cases <- list(
    list(status = 404L, outcome = "missing"),
    list(status = 410L, outcome = "missing"),
    list(status = 403L, outcome = "http_error"),
    list(status = 503L, outcome = "http_error")
  )
  for (case in cases) {
    local_fake_ssrfr(function(req) {
      fake_response(case$status, body = big_body())
    })
    x <- robots_fetch("http://a/x", max_bytes = 1000L)
    info <- as.character(case$status)
    expect_identical(x$robots$fetch_outcome, case$outcome, info = info)
    expect_identical(x$robots$http_status, case$status, info = info)
    expect_identical(x$robots$effective_url, "http://a/robots.txt",
                     info = info)
  }
})

test_that("a large 404 is missing, and so allowed, as a small one is", {
  local_fake_ssrfr(function(req) fake_response(404L, body = big_body()))
  e <- robots_evaluate_url_v1(
    "http://a/x", "Googlebot", "google", "google", max_bytes = 1000L
  )$evidence
  expect_identical(e$legacy_fetch_outcome, "missing")
  expect_identical(e$evidence_status, "http_status")
  expect_identical(e$final_http_status, 404L)
  expect_identical(e$termination_reason, "none")
})

test_that("a large 404 over the wire is missing", {
  url <- local_wire_server(function(req, res) {
    res$set_status(404L)$set_type("text/html")$send(big_body(5000L))
  })
  x <- robots_fetch(url, max_bytes = 1000L, timeout = 5)
  expect_identical(x$robots$fetch_outcome, "missing")
  expect_identical(x$robots$http_status, 404L)
})

test_that("a large 503 over the wire is http_error", {
  url <- local_wire_server(function(req, res) {
    res$set_status(503L)$set_type("text/html")$send(big_body(5000L))
  })
  x <- robots_fetch(url, max_bytes = 1000L, timeout = 5)
  expect_identical(x$robots$fetch_outcome, "http_error")
  expect_identical(x$robots$http_status, 503L)
})

# --- Finding 2: several Location fields --------------------------------------

test_that("a 3xx with several Location fields is no_location", {
  local_fake_ssrfr(function(req) {
    two <- stats::setNames(list("/a", "/b"), c("Location", "Location"))
    fake_response(302L, headers = two)
  })
  e <- evidence_of()
  expect_identical(e$legacy_fetch_outcome, "redirect_error")
  expect_identical(e$terminal_redirect_reason, "no_location")
  expect_identical(e$final_http_status, 302L)
  hops <- e$redirect_hops[[1L]]
  expect_length(hops, 1L)
  expect_identical(hops[[1L]]$status, 302L)
})

test_that("several Location fields on a later hop count the redirects", {
  local_fake_ssrfr(fake_router(list(
    "http://a/robots.txt" = redirect_to("/next"),
    "http://a/next" = function(req) {
      two <- stats::setNames(list("/a", "/b"), c("Location", "Location"))
      fake_response(301L, headers = two)
    }
  )))
  e <- evidence_of()
  expect_identical(e$terminal_redirect_reason, "no_location")
  expect_identical(e$redirect_count, 1L)
  expect_length(e$redirect_hops[[1L]], 2L)
})

test_that("a 2xx with several Location fields is a network_error", {
  # ssrfr refuses the whole response, so there is no body to match.
  local_fake_ssrfr(function(req) {
    two <- stats::setNames(list("/a", "/b"), c("Location", "Location"))
    fake_response(200L, headers = two, body = "user-agent: *")
  })
  x <- robots_fetch("http://a/x")
  expect_identical(x$robots$fetch_outcome, "network_error")
})

test_that("a 302 with two Location fields over the wire is no_location", {
  url <- local_wire_server(function(req, res) {
    res$set_status(302L)
    res$add_header("Location", "/a")
    res$add_header("Location", "/b")
    res$send("")
  })
  e <- robots_evaluate_url_v1(
    url, "Googlebot", "google", "google", timeout = 5
  )$evidence
  expect_identical(e$legacy_fetch_outcome, "redirect_error")
  expect_identical(e$terminal_redirect_reason, "no_location")
  expect_identical(e$final_http_status, 302L)
})

test_that("a 200 with two Location fields over the wire is a network_error", {
  url <- local_wire_server(function(req, res) {
    res$add_header("Location", "/a")
    res$add_header("Location", "/b")
    res$set_type("text/plain")$send("user-agent: *\ndisallow: /")
  })
  x <- robots_fetch(url, timeout = 5)
  expect_identical(x$robots$fetch_outcome, "network_error")
})

# --- Finding 3: header limits sized for real sites ---------------------------

test_that("the policy allows 64 KiB and 256 fields of response header", {
  policy <- acquire_policy(10, "bot/1", 4096L)
  expect_identical(policy$max_header_bytes, 65536)
  expect_identical(policy$max_header_fields, 256)
})

test_that("200 header fields are fetched", {
  local_fake_ssrfr(function(req) {
    fields <- stats::setNames(
      as.list(rep("1", 200L)), sprintf("X-F-%03d", 1:200)
    )
    fake_response(200L, headers = fields, body = "user-agent: *")
  })
  x <- robots_fetch("http://a/x")
  expect_identical(x$robots$fetch_outcome, "fetched")
})

test_that("a 20 KB header over the wire is fetched", {
  url <- local_wire_server(function(req, res) {
    for (i in 1:20) {
      res$set_header(sprintf("X-Pad-%02d", i), strrep("a", 1000L))
    }
    res$set_type("text/plain")$send("user-agent: *\ndisallow: /")
  })
  x <- robots_fetch(url, timeout = 5)
  expect_identical(x$robots$fetch_outcome, "fetched")
})

test_that("150 header fields over the wire are fetched", {
  url <- local_wire_server(function(req, res) {
    for (i in 1:150) {
      res$set_header(sprintf("X-F-%03d", i), "1")
    }
    res$set_type("text/plain")$send("user-agent: *\ndisallow: /")
  })
  x <- robots_fetch(url, timeout = 5)
  expect_identical(x$robots$fetch_outcome, "fetched")
})

# --- The downgrade refusal wins over the loop check --------------------------

test_that("an http -> https -> http cycle is a downgrade, not a loop", {
  local_fake_ssrfr(fake_router(list(
    "http://a/robots.txt" = redirect_to("https://a/robots.txt"),
    "https://a/robots.txt" = redirect_to("http://a/robots.txt")
  )))
  e <- evidence_of()
  expect_identical(e$legacy_fetch_outcome, "redirect_error")
  expect_identical(e$terminal_redirect_reason, "downgrade")
  expect_identical(e$safety_block_reason, "https_downgrade")
  expect_identical(e$evidence_status, "safety_refused")
})
