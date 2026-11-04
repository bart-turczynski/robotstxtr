# Slice R9 regression: a transport failure occurring DURING the final body
# (e.g. the server drops the connection mid-body) must be classified as a
# transport outcome (timeout / tls_error / network_error, PRD 6.4) and MUST NOT
# abort the whole robots_fetch()/allowed_by_robots_url() call.
#
# Since ROBO-jbralthm ssrfr reads the whole response before ssrf_fetch()
# returns, so a mid-body drop reaches robotstxtr as an operational failure, not
# as a condition: a truncated or undecodable response is "protocol-error", a
# stall past the chain's budget "timeout". Offline through the fake at the
# ssrfr boundary, which returns those failures as ssrfr would.

body_then <- function(cause, ...) {
  detail <- list(...)
  function(req) do.call(fake_failure, c(list(cause), detail))
}

test_that("a mid-stream transport drop is classified, not aborted", {
  local_fake_ssrfr(body_then("protocol-error", step = 12L))

  # The call must return normally (no uncaught abort), with one robots row.
  x <- robots_fetch("http://a/x")

  expect_s3_class(x, "robots_fetches")
  expect_identical(nrow(x$robots), 1L)
  expect_identical(x$robots$fetch_outcome, "network_error")
  expect_identical(x$robots$error_stage, "request")
  expect_identical(x$robots$error_class, "robots_network_error")
  expect_true(nzchar(x$robots$error_message))
  # A mid-stream failure means the fetch did not complete: no body/status/URL.
  expect_null(x$robots$body[[1]])
  expect_true(is.na(x$robots$body_size))
  expect_true(is.na(x$robots$http_status))
  expect_true(is.na(x$robots$effective_url))
})

test_that("a mid-stream drop does not abort allowed_by_robots_url()", {
  local_fake_ssrfr(body_then("protocol-error"))

  # The transport outcome propagates as a fetch-stage classification; the call
  # completes rather than erroring out. A failed fetch yields no body to match,
  # so the decision is fetch_unknown (allowed NA), never a crash.
  x <- allowed_by_robots_url("http://a/private", "bot")
  expect_s3_class(x, "robots_decisions")
  expect_identical(nrow(x$results), 1L)
  expect_identical(x$results$fetch_outcome, "network_error")
  expect_identical(x$results$decision_source, "fetch_unknown")
  expect_true(is.na(x$results$allowed))
})

test_that("mid-stream tls and timeout failures classify accordingly", {
  local_fake_ssrfr(body_then("tls-failed"))
  x_tls <- robots_fetch("https://a/x")
  expect_identical(x_tls$robots$fetch_outcome, "tls_error")
  expect_identical(x_tls$robots$error_class, "robots_tls_error")

  local_fake_ssrfr(body_then(
    "timeout", step = 12L, check = "total", limit = "total_timeout"
  ))
  x_to <- robots_fetch("https://a/x")
  expect_identical(x_to$robots$fetch_outcome, "timeout")
  expect_identical(x_to$robots$error_class, "robots_timeout")
})
