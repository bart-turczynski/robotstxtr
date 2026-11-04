# Slice R7: decoded-byte `max_bytes` enforcement plus strict `max_bytes`
# call-level validation (PRD 6.4 streaming note, 6.6 shared fetch controls).
#
# Since ROBO-jbralthm the bytes are counted by ssrfr, after any gzip or deflate
# decoding, as they arrive, so a compressed body cannot pass a limit its
# decoded form exceeds. These cases fetch from a loopback webfakes server
# through the real ssrfr, with loopback reopened on the server's port for the
# test only (local_loopback_policy(), helper-fake-ssrfr.R). No external network
# is used.

# --- Loopback server harness ---------------------------------------------------

# Serve `body_raw` with `headers` at every path, and return the robots URL.
local_body_server <- function(body_raw, headers = list(),
                              env = parent.frame()) {
  skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$locals$body <- body_raw
  app$locals$headers <- headers
  app$get(webfakes::new_regexp("^/"), function(req, res) {
    for (name in names(req$app$locals$headers)) {
      res$set_header(name, req$app$locals$headers[[name]])
    }
    res$set_type("text/plain")
    res$send(req$app$locals$body)
  })
  server <- webfakes::local_app_process(app, .local_envir = env)
  url <- server$url("/robots.txt")
  port <- as.integer(sub("^http://127\\.0\\.0\\.1:([0-9]+)/.*$", "\\1", url))
  local_loopback_policy(port, env = env)
  url
}

# --- Tracer bullet: gzip body under the limit, decoded body over it ---------

test_that("gzip body under limit but decoded over limit is body_too_large", {
  # Highly compressible ~100 KB decoded body; its gzip encoding is a few hundred
  # bytes. With max_bytes between the two, a compressed Content-Length or
  # compressed-byte check would wrongly pass; only decoded counting fails it.
  decoded <- charToRaw(strrep("user-agent: *\ndisallow: /private\n", 3000L))
  gz <- memCompress(decoded, type = "gzip")
  expect_lt(length(gz), 50000L)
  expect_gt(length(decoded), 50000L)

  url <- local_body_server(gz, list("Content-Encoding" = "gzip"))
  x <- robots_fetch(url, max_bytes = 50000L, timeout = 5)

  expect_identical(x$robots$fetch_outcome, "body_too_large")
  # No body is stored and none is matched: NULL body, NA size.
  expect_null(x$robots$body[[1]])
  expect_true(is.na(x$robots$body_size))
  # Response-stage error metadata for body_too_large.
  expect_identical(x$robots$error_stage, "response")
  expect_identical(x$robots$error_class, "robots_body_too_large")
  # The real final status and effective URL are still recorded.
  expect_identical(x$robots$http_status, 200L)
  expect_identical(x$robots$effective_url, url)
  # And the per-input map row reflects the same outcome/metadata.
  expect_identical(x$map$fetch_outcome, "body_too_large")
  expect_identical(x$map$error_class, "robots_body_too_large")
})

# --- Boundary: exactly at the limit vs one byte over ------------------------

test_that("a body exactly at the limit is fetched and stored", {
  limit <- 4096L
  body <- charToRaw(strrep("a", limit)) # decoded length == limit
  url <- local_body_server(body)
  x <- robots_fetch(url, max_bytes = limit, timeout = 5)

  expect_identical(x$robots$fetch_outcome, "fetched")
  expect_identical(x$robots$body[[1]], body)
  expect_identical(x$robots$body_size, limit)
  expect_true(is.na(x$robots$error_class))
})

test_that("a body one byte over the limit is body_too_large", {
  limit <- 4096L
  body <- charToRaw(strrep("a", limit + 1L)) # one byte over
  url <- local_body_server(body)
  x <- robots_evaluate_url_v1(
    url, "Googlebot", "google", "google", max_bytes = limit, timeout = 5
  )
  evidence <- x$evidence

  expect_identical(evidence$legacy_fetch_outcome, "body_too_large")
  expect_identical(evidence$evidence_status, "incomplete")
  expect_identical(evidence$termination_reason, "ceiling")
  # ROBO-jbralthm: ssrfr returns none of an oversized body, so nothing was
  # truncated and nothing is stored.
  expect_false(evidence$body_truncated)
  expect_false(evidence$body_present)
  expect_identical(evidence$stored_bytes, 0L)
  expect_gt(evidence$observed_bytes, limit)
  expect_identical(evidence$final_http_status, 200L)
})

# --- A small uncompressed body under the limit fetches normally -------------

test_that("a small uncompressed body under the limit is fetched", {
  body <- charToRaw("user-agent: *\ndisallow: /admin")
  url <- local_body_server(body)
  x <- robots_fetch(url, timeout = 5) # default max_bytes = 524288

  expect_identical(x$robots$fetch_outcome, "fetched")
  expect_identical(x$robots$body[[1]], body)
  expect_identical(x$robots$body_size, length(body))
})

test_that("the fetch sends the package user agent over the wire", {
  skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$get("/robots.txt", function(req, res) {
    res$set_type("text/plain")
    res$send(paste0("# ", req$get_header("User-Agent")))
  })
  server <- webfakes::local_app_process(app)
  url <- server$url("/robots.txt")
  local_loopback_policy(
    as.integer(sub("^http://127\\.0\\.0\\.1:([0-9]+)/.*$", "\\1", url))
  )
  x <- robots_fetch(url, timeout = 5)
  expect_identical(
    rawToChar(x$robots$body[[1]]), paste0("# ", package_fetch_user_agent())
  )
})

test_that("a redirect is followed over the wire", {
  skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$get("/robots.txt", function(req, res) {
    res$redirect("/moved.txt", 301L)
  })
  app$get("/moved.txt", function(req, res) {
    res$set_type("text/plain")
    res$send("user-agent: *\ndisallow: /")
  })
  server <- webfakes::local_app_process(app)
  url <- server$url("/robots.txt")
  local_loopback_policy(
    as.integer(sub("^http://127\\.0\\.0\\.1:([0-9]+)/.*$", "\\1", url))
  )
  x <- robots_fetch(url, timeout = 5)
  expect_identical(x$robots$fetch_outcome, "fetched")
  expect_identical(x$robots$redirect_count, 1L)
  expect_identical(x$robots$effective_url, server$url("/moved.txt"))
  expect_identical(x$robots$robots_url, url)
})

# --- Strict max_bytes validation (PRD 6.6) ----------------------------------

test_that("validate_max_bytes accepts whole-number doubles as integer", {
  expect_identical(validate_max_bytes(524288L), 524288L)
  expect_identical(validate_max_bytes(524288), 524288L)
  expect_identical(validate_max_bytes(1e5), 100000L)
  expect_type(validate_max_bytes(1e5), "integer")
})

test_that("a fractional max_bytes is a call-level error", {
  expect_error(
    robots_fetch("http://a/x", max_bytes = 0.5),
    class = "robotstxtr_invalid_max_bytes"
  )
  expect_error(
    robots_fetch("http://a/x", max_bytes = 100.25),
    class = "robotstxtr_invalid_max_bytes"
  )
})

test_that("a non-positive max_bytes is a call-level error", {
  expect_error(
    robots_fetch("http://a/x", max_bytes = 0),
    class = "robotstxtr_invalid_max_bytes"
  )
  expect_error(
    robots_fetch("http://a/x", max_bytes = -1),
    class = "robotstxtr_invalid_max_bytes"
  )
})

test_that("an out-of-range max_bytes (> integer.max) is a call-level error", {
  expect_error(
    robots_fetch("http://a/x", max_bytes = .Machine$integer.max + 1),
    class = "robotstxtr_invalid_max_bytes"
  )
})

test_that("a non-scalar, NA, Inf, or non-numeric max_bytes is an error", {
  expect_error(
    robots_fetch("http://a/x", max_bytes = c(1, 2)),
    class = "robotstxtr_invalid_max_bytes"
  )
  expect_error(
    robots_fetch("http://a/x", max_bytes = NA_integer_),
    class = "robotstxtr_invalid_max_bytes"
  )
  expect_error(
    robots_fetch("http://a/x", max_bytes = Inf),
    class = "robotstxtr_invalid_max_bytes"
  )
  expect_error(
    robots_fetch("http://a/x", max_bytes = "1000"),
    class = "robotstxtr_invalid_max_bytes"
  )
})
