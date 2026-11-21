# ROBO-syoccfej: robots_compare_fetches(), an audit that fetches robots.txt
# for explicitly supplied variants under a hard request budget and reports how
# the responses differ. Offline: every request goes through the fake at the
# ssrfr boundary (helper-fake-ssrfr.R), and the recorder below counts them.

# --- Test helpers (file-local copies of test-robots_fetch-r6.R's) ------------

# Record every requested URL and the sent user agent, and route to a per-URL
# handler; an unexpected URL fails the test, so "no extra request" is free.
mock_router <- function(routes, recorder = NULL) {
  function(req) {
    if (!is.null(recorder)) {
      ua <- req$user_agent
      if (is.null(ua)) {
        ua <- NA_character_
      }
      recorder$urls <- c(recorder$urls, req$url)
      recorder$agents <- c(recorder$agents, ua)
      recorder$reqs <- c(recorder$reqs, list(req))
    }
    handler <- routes[[req$url]]
    if (is.null(handler)) {
      stop(sprintf("unexpected request URL in mock: %s", req$url))
    }
    handler(req)
  }
}

new_recorder <- function() {
  e <- new.env(parent = emptyenv())
  e$urls <- character(0)
  e$agents <- character(0)
  e$reqs <- list()
  e
}

ok_body <- function(body = "user-agent: *\ndisallow: /") {
  force(body)
  function(req) {
    fake_response(status_code = 200L, url = req$url, body = charToRaw(body))
  }
}

raw_body <- function(bytes) {
  force(bytes)
  function(req) fake_response(status_code = 200L, url = req$url, body = bytes)
}

status_resp <- function(code) {
  force(code)
  function(req) fake_response(status_code = code, url = req$url)
}

redirect_to <- function(location, status = 301L) {
  force(location)
  force(status)
  function(req) fake_response(status, headers = list(Location = location))
}

# A two-redirect chain ending in a 200: a -> b -> c.
chain_routes <- function() {
  list(
    "http://a/robots.txt" = redirect_to("http://b/robots.txt"),
    "http://b/robots.txt" = redirect_to("http://c/robots.txt"),
    "http://c/robots.txt" = ok_body()
  )
}

# The outcomes robots_fetch() can publish: every row of the translation
# tables, every final status, and the hop loop's own outcomes.
published_fetch_outcomes <- function() {
  refusal <- acquire_refusal_table()
  cause <- acquire_cause_table()
  statuses <- vapply(100:599, classify_status, character(1L))
  out <- unique(c(
    refusal$fetch_outcome, refusal$redirect_fetch_outcome,
    cause$fetch_outcome, statuses, "body_too_large", "redirect_error",
    "input_invalid"
  ))
  out[!is.na(out)]
}

# --- Pins: the unbudgeted acquisition is unchanged ---------------------------

test_that("acquire_robots() without a budget follows a chain hop by hop", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(chain_routes(), recorder = rec))

  r <- acquire_robots(
    "http://a/robots.txt", 10, package_fetch_user_agent(), 524288L
  )

  expect_identical(rec$urls, c(
    "http://a/robots.txt", "http://b/robots.txt", "http://c/robots.txt"
  ))
  expect_identical(r$fetch_outcome, "fetched")
  expect_identical(r$http_status, 200L)
  expect_identical(r$effective_url, "http://c/robots.txt")
  expect_identical(r$redirect_count, 2L)
  expect_length(r$redirect_hops, 2L)
  expect_identical(r$body, charToRaw("user-agent: *\ndisallow: /"))
})

test_that("robots_fetch() still makes one request per origin", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(chain_routes(), recorder = rec))

  x <- robots_fetch(c("http://a/x", "http://a/y"))

  expect_length(rec$urls, 3L)
  expect_identical(x$robots$fetch_outcome, "fetched")
  expect_identical(x$robots$redirect_count, 2L)
})

test_that("the published fetch_outcome set is pinned", {
  expect_setequal(published_fetch_outcomes(), c(
    "ssrf_blocked", "redirect_error", "timeout", "tls_error",
    "network_error", "http_error", "fetched", "partial_response", "missing",
    "body_too_large", "input_invalid"
  ))
})
