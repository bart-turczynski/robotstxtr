# A robots.txt fetched with a 2xx status other than 200 (ROBO-yvhqvthd). Its
# body is validated as a 200's is, and the validator adds an info code for the
# status class, whose message names how each ruleset reads that status.

yv_body <- "User-agent: *\nDisallow: /\n"
yv_cut_body <- paste0(
  "User-agent: *\n", paste0("Disallow: /p", seq_len(40L), "\n", collapse = "")
)
yv_code <- "acquisition_http_other_2xx"
yv_readings <- paste(
  "Google: reads the body's rules as for a 200;",
  "Yandex: places no restrictions on crawling; Bing: not documented"
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

test_that("ROBO-yvhqvthd: a 203 or 204 body is validated, with its code", {
  for (status in c(203L, 204L)) {
    x <- yv_fetch(status)
    label <- paste("HTTP", status)
    d <- x$diagnostics
    expect_identical(x$documents$http_status, status, label = label)
    expect_identical(x$documents$fetch_outcome, "fetched", label = label)
    expect_identical(x$documents$validation_status, "valid", label = label)
    expect_identical(x$documents$disallow_directives, 1L, label = label)
    expect_identical(x$documents$diagnostic_count, 1L, label = label)
    expect_identical(x$documents$warning_count, 0L, label = label)
    expect_identical(d$code, yv_code, label = label)
    expect_identical(d$severity, "info", label = label)
    expect_identical(d$line, NA_integer_, label = label)
    expect_identical(
      d$message,
      paste0("HTTP ", status, ": ", yv_readings,
             ". See robots_engine_contract_v1()."),
      label = label
    )
  }
})

test_that("ROBO-yvhqvthd: a 204 with no body gets no_rules, then the code", {
  x <- yv_fetch(204L, body = raw())
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$diagnostics$code, c("no_rules", yv_code))
})

test_that("ROBO-yvhqvthd: a 200 body gets no status code", {
  x <- yv_fetch(200L)
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$diagnostics$code, character())
})

test_that("ROBO-yvhqvthd: a 206 keeps its partial-response code", {
  x <- yv_fetch(206L, body = "User-agent: *\nDisallow: /\n")
  expect_identical(x$documents$validation_status, "not_validated")
  expect_false(x$documents$body_truncated)
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
  expect_identical(x$diagnostics$code, yv_code)
  expect_true(startsWith(x$diagnostics$message, "HTTP 203: "))
})

test_that("ROBO-yvhqvthd: a cut 203 gets body_truncated and the code", {
  x <- yv_fetch(203L, body = yv_cut_body, max_bytes = 200L)
  d <- x$diagnostics
  expect_true(x$documents$body_truncated)
  expect_identical(x$documents$validation_status, "warning")
  expect_identical(d$code, c("body_truncated", yv_code))
  expect_identical(d$severity, c("warning", "info"))
})

test_that("ROBO-yvhqvthd: a 203 with a NUL byte gets nul_byte and the code", {
  body <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0L), as.raw(10L))
  x <- yv_fetch(203L, body = body)
  expect_identical(x$documents$validation_status, "error")
  expect_identical(x$diagnostics$code, c("nul_byte", yv_code))
})

test_that("ROBO-yvhqvthd: validate_document_bytes() fires on a fetched 2xx", {
  for (status in c(203L, 204L, 299L)) {
    d <- yv_document(http_status = status)
    expect_identical(d$code, yv_code, label = paste("fetched", status))
    expect_identical(d$severity, "info", label = paste("fetched", status))
  }
  d <- yv_document(http_status = 203L, body_truncated = TRUE,
                   bytes = charToRaw(yv_cut_body))
  expect_identical(d$code, c("body_truncated", yv_code))
})

test_that("ROBO-yvhqvthd: validate_document_bytes() gates on the fetched 2xx", {
  # Not 2xx other than 200 (200, 404, 429, 500, 102, 600, a missing status),
  # and a row that was not fetched: no code.
  for (status in c(200L, 404L, 429L, 500L, 102L, 600L, NA_integer_)) {
    expect_identical(
      yv_document(http_status = status)$code, character(),
      label = paste("fetched", status)
    )
  }
  expect_identical(
    yv_document(http_status = 203L, fetch_outcome = "partial_response")$code,
    character()
  )
})

test_that("ROBO-yvhqvthd: robots_validate_text() has no status code", {
  x <- robots_validate_text(yv_body)
  expect_identical(x$documents$http_status, NA_integer_)
  expect_identical(x$diagnostics$code, character())
})

test_that("ROBO-yvhqvthd: the readings come from the status table", {
  expect_identical(status_engine_readings("status_other_2xx"), yv_readings)
  # The wording follows the cell's action, whichever engine holds it.
  for (ruleset in c("google", "yandex", "bing", "rfc9309", "assumed_rfc9309")) {
    expect_identical(
      status_policy_phrase(ruleset, "status_other_2xx", "evaluated",
                           "use_rules"),
      "reads the body's rules as for a 200",
      label = ruleset
    )
  }
  # A table edit that gives Bing use_rules here still yields a message.
  real <- engine_policy_table_v1
  local_mocked_bindings(engine_policy_table_v1 = function() {
    table <- real()
    bing <- table$category == "status_other_2xx" & table$ruleset == "bing"
    table$policy_status[bing] <- "evaluated"
    table$policy_action[bing] <- "use_rules"
    table
  })
  expect_identical(
    status_engine_readings("status_other_2xx"),
    paste(
      "Google: reads the body's rules as for a 200;",
      "Yandex: places no restrictions on crawling;",
      "Bing: reads the body's rules as for a 200"
    )
  )
})
