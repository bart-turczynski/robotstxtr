# A robots.txt fetched with a 2xx status other than 200 (ROBO-yvhqvthd). Its
# body is validated as a 200's is, and the validator adds a code for the status
# class. Every 203 and 204 pin here starts as today's silence: no status code.

yv_body <- "User-agent: *\nDisallow: /\n"
yv_cut_body <- paste0(
  "User-agent: *\n", paste0("Disallow: /p", seq_len(40L), "\n", collapse = "")
)

yv_fetch <- function(status, body = yv_body, max_bytes = 524288L) {
  local_fake_ssrfr(function(req) fake_response(status, body = body))
  robots_validate_url("http://example.com/", max_bytes = max_bytes)
}

# validate_document_bytes() called as a fetch row calls it, with the status
# and outcome given, so the gate is pinned on its own.
yv_document <- function(http_status = 203L, fetch_outcome = "fetched",
                        bytes = charToRaw(yv_body), body_truncated = FALSE) {
  validate_document_bytes(
    bytes = bytes, source_id = "example.com", source_type = "fetched",
    robots_url = "http://example.com/robots.txt",
    effective_url = "http://example.com/",
    http_status = http_status, fetch_outcome = fetch_outcome,
    max_bytes = 524288L, body_truncated = body_truncated
  )$diagnostics
}

test_that("ROBO-yvhqvthd: a 203 or 204 body is validated, with no status code", {
  for (status in c(203L, 204L)) {
    x <- yv_fetch(status)
    label <- paste("HTTP", status)
    expect_identical(x$documents$http_status, status, label = label)
    expect_identical(x$documents$fetch_outcome, "fetched", label = label)
    expect_identical(x$documents$validation_status, "valid", label = label)
    expect_identical(x$documents$disallow_directives, 1L, label = label)
    expect_identical(x$diagnostics$code, character(), label = label)
  }
})

test_that("ROBO-yvhqvthd: a 204 with no body gets only no_rules", {
  x <- yv_fetch(204L, body = raw())
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$diagnostics$code, "no_rules")
})

test_that("ROBO-yvhqvthd: a 200 body gets no status code", {
  x <- yv_fetch(200L)
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$diagnostics$code, character())
})

test_that("ROBO-yvhqvthd: a 206 keeps its partial-response code", {
  x <- yv_fetch(206L, body = "User-agent: *\nDisallow: /\n")
  expect_identical(x$documents$validation_status, "not_validated")
  expect_identical(x$documents$body_truncated, FALSE)
  expect_identical(x$diagnostics$code, "acquisition_partial_response")
})

test_that("ROBO-yvhqvthd: a 203 reached through a redirect is keyed on 203", {
  local_fake_ssrfr(function(req) {
    if (grepl("/final$", req$url)) {
      return(fake_response(203L, body = yv_body))
    }
    fake_response(
      301L, url = req$url,
      headers = list(Location = "http://example.com/final")
    )
  })
  x <- robots_validate_url("http://example.com/")
  expect_identical(x$documents$http_status, 203L)
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$diagnostics$code, character())
})

test_that("ROBO-yvhqvthd: a cut 203 gets body_truncated only", {
  x <- yv_fetch(203L, body = yv_cut_body, max_bytes = 200L)
  expect_identical(x$documents$body_truncated, TRUE)
  expect_identical(x$documents$validation_status, "warning")
  expect_identical(x$diagnostics$code, "body_truncated")
})

test_that("ROBO-yvhqvthd: a 203 with a NUL byte gets nul_byte only", {
  body <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0L), as.raw(10L))
  x <- yv_fetch(203L, body = body)
  expect_identical(x$documents$validation_status, "error")
  expect_identical(x$diagnostics$code, "nul_byte")
})

test_that("ROBO-yvhqvthd: validate_document_bytes() gates on the fetched 2xx", {
  # Statuses other than 200 and 2xx, a 206 and a missing status: no code.
  for (status in c(200L, 206L, 404L, 429L, 500L, 102L, 600L, NA_integer_)) {
    expect_identical(
      yv_document(http_status = status)$code, character(),
      label = paste("fetched", status)
    )
  }
  expect_identical(
    yv_document(http_status = 206L, fetch_outcome = "partial_response")$code,
    character()
  )
})

test_that("ROBO-yvhqvthd: robots_validate_text() has no status code", {
  x <- robots_validate_text(yv_body)
  expect_identical(x$documents$http_status, NA_integer_)
  expect_identical(x$diagnostics$code, character())
})
