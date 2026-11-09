# ROBO-ybzbxfml: an HTTP status that leaves robots_validate_url() no body.
# Responses are scripted at the ssrfr boundary (helper-fake-ssrfr.R).

ybz_validate <- function(handler, url = "http://a/", ...,
                         env = parent.frame()) {
  local_fake_ssrfr(handler, env = env)
  robots_validate_url(url, ...)
}

ybz_status <- function(status, headers = list(), body = raw(),
                       env = parent.frame()) {
  ybz_validate(
    function(req) {
      fake_response(status, url = req$url, headers = headers, body = body)
    },
    env = env
  )
}

# --- today: one acquisition_failed error per status class -------------------

test_that("ROBO-ybzbxfml: a status without a body is acquisition_failed", {
  for (status in c(102L, 400L, 401L, 403L, 429L, 500L, 503L, 600L)) {
    x <- ybz_status(status)
    expect_identical(x$documents$http_status, status)
    expect_identical(x$documents$fetch_outcome, "http_error")
    expect_identical(x$diagnostics$code, "acquisition_failed")
    expect_identical(x$diagnostics$severity, "error")
    expect_identical(
      x$diagnostics$message,
      "Acquisition outcome 'http_error' supplied no document body."
    )
    expect_identical(x$documents$validation_status, "not_validated")
    expect_identical(x$documents$error_count, 1L)
    expect_identical(x$documents$warning_count, 0L)
  }
})

test_that("ROBO-ybzbxfml: a 404 or 410 is acquisition_missing", {
  for (status in c(404L, 410L)) {
    x <- ybz_status(status)
    expect_identical(x$documents$fetch_outcome, "missing")
    expect_identical(x$diagnostics$code, "acquisition_missing")
    expect_identical(x$diagnostics$severity, "info")
    expect_identical(
      x$diagnostics$message,
      "No robots.txt body was acquired because the resource is absent."
    )
    expect_identical(x$documents$error_count, 0L)
  }
})

# --- outcomes that are not a status class -----------------------------------

test_that("ROBO-ybzbxfml: transport failures keep their verbatim message", {
  timeout <- ybz_validate(function(req) fake_failure("timeout"))
  expect_identical(timeout$diagnostics$code, "acquisition_failed")
  expect_identical(timeout$diagnostics$message, "Fetch failed (timeout).")

  dns <- ybz_validate(function(req) fake_failure("unresolvable"))
  expect_identical(dns$documents$fetch_outcome, "network_error")
  expect_identical(dns$diagnostics$code, "acquisition_failed")
  expect_identical(dns$diagnostics$message, "Fetch failed (unresolvable).")
})

test_that("ROBO-ybzbxfml: redirect errors keep their verbatim message", {
  loop <- ybz_validate(function(req) {
    fake_response(301L, url = req$url, headers = list(Location = req$url))
  })
  expect_identical(loop$documents$fetch_outcome, "redirect_error")
  expect_identical(loop$diagnostics$code, "acquisition_failed")
  expect_identical(loop$diagnostics$message, "Redirect loop detected.")

  budget <- ybz_validate(function(req) {
    hop <- suppressWarnings(as.integer(sub("^http://a/r", "", req$url)))
    hop <- if (is.na(hop)) 1L else hop + 1L
    fake_response(301L, url = req$url,
                  headers = list(Location = paste0("http://a/r", hop)))
  })
  expect_identical(budget$documents$fetch_outcome, "redirect_error")
  expect_identical(budget$diagnostics$code, "acquisition_failed")
  expect_identical(
    budget$diagnostics$message, "Exceeded the maximum of five redirects."
  )
})

test_that("ROBO-ybzbxfml: a 206 and an oversized 3xx keep their codes", {
  partial <- ybz_status(206L, body = charToRaw("partial"))
  expect_identical(partial$diagnostics$code, "acquisition_partial_response")
  expect_identical(partial$documents$error_count, 1L)

  large <- ybz_validate(
    function(req) {
      fake_response(301L, url = req$url,
                    headers = list(Location = "http://b/robots.txt"),
                    body = strrep("x", 100L))
    },
    max_bytes = 10L
  )
  expect_identical(large$documents$fetch_outcome, "body_too_large")
  expect_identical(large$diagnostics$code, "acquisition_limit_exceeded")
  expect_true(large$documents$limit_exceeded)
})

test_that("ROBO-ybzbxfml: an invalid input URL is acquisition_input_invalid", {
  x <- robots_validate_url("")
  expect_identical(nrow(x$documents), 0L)
  expect_identical(x$diagnostics$code, "acquisition_input_invalid")
  expect_identical(x$diagnostics$severity, "error")
})

# --- edge inputs ------------------------------------------------------------

test_that("ROBO-ybzbxfml: an oversized 403 or 503 is reported as a small one", {
  for (status in c(403L, 503L)) {
    x <- ybz_validate(
      function(req) {
        fake_response(status, url = req$url,
                      headers = list(`Retry-After` = "120"),
                      body = strrep("x", 100L))
      },
      max_bytes = 10L
    )
    expect_identical(x$documents$http_status, status)
    expect_identical(x$documents$fetch_outcome, "http_error")
    expect_identical(x$diagnostics$code, "acquisition_failed")
    expect_false(grepl("Retry-After", x$diagnostics$message, fixed = TRUE))
  }
})

test_that("ROBO-ybzbxfml: two URLs on one 403 origin give one diagnostic", {
  x <- ybz_validate(
    function(req) fake_response(403L, url = req$url),
    url = c("http://a/x", "http://a/y")
  )
  expect_identical(nrow(x$documents), 1L)
  expect_identical(nrow(x$diagnostics), 1L)
  expect_identical(x$map$validation_status, rep("not_validated", 2L))
  expect_identical(x$diagnostics$code, "acquisition_failed")
})
