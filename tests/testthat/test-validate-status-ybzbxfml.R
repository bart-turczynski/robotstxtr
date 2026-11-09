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

# The phrases each engine's policy cell turns into.
ybz_no_robots <- paste0(
  "may treat it as no robots.txt, which places no restrictions on crawling"
)
ybz_firewall <- "often a firewall or bot filter answering this client"

# One case per status class: code, severity, and the document's counts.
ybz_cases <- list(
  list(status = 400L, code = "acquisition_http_4xx", severity = "warning"),
  list(status = 401L, code = "acquisition_http_4xx", severity = "warning"),
  list(status = 403L, code = "acquisition_http_4xx", severity = "warning"),
  list(status = 404L, code = "acquisition_missing", severity = "info"),
  list(status = 410L, code = "acquisition_missing", severity = "info"),
  list(status = 429L, code = "acquisition_http_429", severity = "error"),
  list(status = 500L, code = "acquisition_http_5xx", severity = "error"),
  list(status = 503L, code = "acquisition_http_5xx", severity = "error"),
  list(status = 102L, code = "acquisition_http_protocol", severity = "error"),
  list(status = 600L, code = "acquisition_http_protocol", severity = "error")
)

ybz_at <- function(pattern, text) {
  as.integer(regexpr(pattern, text, fixed = TRUE))
}

# --- each status class ------------------------------------------------------

test_that("ROBO-ybzbxfml: each status class has its own code and severity", {
  for (case in ybz_cases) {
    label <- paste("HTTP", case$status)
    x <- ybz_status(case$status)
    expect_identical(x$documents$http_status, case$status, label = label)
    expect_identical(x$diagnostics$code, case$code, label = label)
    expect_identical(x$diagnostics$severity, case$severity, label = label)
    expect_identical(x$documents$validation_status, "not_validated",
                     label = label)
    expect_identical(x$map$validation_status, "not_validated", label = label)
    expect_identical(x$documents$diagnostic_count, 1L, label = label)
    expect_identical(
      x$documents$warning_count, as.integer(case$severity == "warning"),
      label = label
    )
    expect_identical(
      x$documents$error_count, as.integer(case$severity == "error"),
      label = label
    )
  }
})

test_that("ROBO-ybzbxfml: each message names the status and every engine", {
  for (case in ybz_cases) {
    label <- paste("HTTP", case$status)
    message <- ybz_status(case$status)$diagnostics$message
    expect_true(startsWith(message, paste0("HTTP ", case$status, ": ")),
                label = label)
    google <- ybz_at("Google: ", message)
    yandex <- ybz_at("Yandex: ", message)
    bing <- ybz_at("Bing: not documented", message)
    expect_gt(google, 0L, label = label)
    expect_gt(yandex, google, label = label)
    expect_gt(bing, yandex, label = label)
    expect_true(endsWith(message, "See robots_engine_contract_v1()."),
                label = label)
    expect_false(grepl("will be crawled", message, fixed = TRUE),
                 label = label)
    expect_false(grepl("Retry-After", message, fixed = TRUE), label = label)
  }
})

test_that("ROBO-ybzbxfml: a 4xx may place no restrictions", {
  for (status in c(400L, 401L, 403L, 404L, 410L)) {
    message <- ybz_status(status)$diagnostics$message
    expect_true(
      grepl(paste0("Google: ", ybz_no_robots, ";"), message, fixed = TRUE),
      label = message
    )
    expect_true(
      grepl("Yandex: places no restrictions on crawling;", message,
            fixed = TRUE),
      label = message
    )
  }
  expect_identical(
    ybz_status(403L)$diagnostics$message,
    paste0(
      "HTTP 403: Google: ", ybz_no_robots, "; Yandex: places no restrictions ",
      "on crawling; Bing: not documented. A 401 or 403 is ", ybz_firewall,
      ", not the site's own robots.txt. See robots_engine_contract_v1()."
    )
  )
})

test_that("ROBO-ybzbxfml: only a 401 or 403 names a firewall or bot filter", {
  for (status in c(401L, 403L)) {
    message <- ybz_status(status)$diagnostics$message
    expect_true(grepl(ybz_firewall, message, fixed = TRUE), label = message)
  }
  for (status in c(400L, 404L, 410L, 429L, 503L)) {
    message <- ybz_status(status)$diagnostics$message
    expect_false(grepl(ybz_firewall, message, fixed = TRUE), label = message)
  }
})

test_that("ROBO-ybzbxfml: Google's reading of a 429 is not documented", {
  expect_identical(
    ybz_status(429L)$diagnostics$message,
    paste0(
      "HTTP 429: Google: not documented for robots.txt (Google excludes ",
      "429 from its 4xx rule); Yandex: places no restrictions on crawling; ",
      "Bing: not documented. See robots_engine_contract_v1()."
    )
  )
})

test_that("ROBO-ybzbxfml: Google's reading of a 5xx depends on context", {
  for (status in c(500L, 503L)) {
    message <- ybz_status(status)$diagnostics$message
    expect_true(
      grepl(paste0(
        "Google: context-dependent (may pause crawling or use its last ",
        "cached copy); Yandex: places no restrictions on crawling;"
      ), message, fixed = TRUE),
      label = message
    )
  }
})

test_that("ROBO-ybzbxfml: a 1xx or out-of-range status is not documented", {
  expect_identical(
    ybz_status(102L)$diagnostics$message,
    paste0(
      "HTTP 102: Google: not documented; Yandex: not documented; ",
      "Bing: not documented. See robots_engine_contract_v1()."
    )
  )
})

# --- derived from the policy table ------------------------------------------

test_that("ROBO-ybzbxfml: the message follows engine_policy_table_v1()", {
  real <- engine_policy_table_v1
  local_mocked_bindings(engine_policy_table_v1 = function() {
    table <- real()
    flip <- table$category == "status_4xx" & table$ruleset == "google"
    table$policy_status[flip] <- "documentation_gap"
    table$policy_action[flip] <- NA_character_
    table
  })
  message <- ybz_status(403L)$diagnostics$message
  expect_true(grepl("HTTP 403: Google: not documented; Yandex: places no",
                    message, fixed = TRUE))
  expect_false(grepl(ybz_no_robots, message, fixed = TRUE))
})

test_that("ROBO-ybzbxfml: every status cell the validator reads has a phrase", {
  table <- engine_policy_table_v1()
  categories <- c("status_4xx", "status_429", "status_5xx", "protocol_error")
  for (category in categories) {
    for (ruleset in c("google", "yandex", "bing")) {
      row <- table[table$category == category & table$ruleset == ruleset, ,
                   drop = FALSE]
      expect_identical(nrow(row), 1L, label = paste(category, ruleset))
      phrase <- status_policy_phrase(
        ruleset, category, row$policy_status[[1L]], row$policy_action[[1L]]
      )
      expect_type(phrase, "character")
      expect_true(nzchar(phrase), label = paste(category, ruleset))
    }
  }
  expect_error(
    status_policy_phrase("google", "status_4xx", "evaluated", "use_rules"),
    "No status phrase for policy (evaluated, use_rules).", fixed = TRUE
  )
})

test_that("ROBO-ybzbxfml: http_status_category_v1() maps a final status", {
  statuses <- c(200L, 204L, 403L, 404L, 429L, 500L, 102L, 600L, NA_integer_)
  expect_identical(
    vapply(statuses, http_status_category_v1, character(1L)),
    c(
      "status_200", "status_other_2xx", "status_4xx", "status_4xx",
      "status_429", "status_5xx", "protocol_error", "protocol_error",
      "protocol_error"
    )
  )
  # A double status maps as its integer does.
  expect_identical(http_status_category_v1(429), "status_429")
  expect_identical(http_status_category_v1(200), "status_200")
})

# --- Retry-After ------------------------------------------------------------

test_that("ROBO-ybzbxfml: a Retry-After delay is appended", {
  for (status in c(429L, 503L)) {
    with_header <- ybz_status(status, headers = list(`Retry-After` = "120"))
    expect_true(
      grepl(
        "Bing: not documented. Retry-After: 120 seconds. See robots_engine",
        with_header$diagnostics$message, fixed = TRUE
      ),
      label = with_header$diagnostics$message
    )
    without <- ybz_status(status)
    expect_false(grepl("Retry-After", without$diagnostics$message,
                       fixed = TRUE))
  }
})

test_that("ROBO-ybzbxfml: a Retry-After delay is whole seconds", {
  delay <- function(seconds) {
    sub("^.*(Retry-After: [^.]*\\.).*$", "\\1",
        status_diagnosis(503L, seconds)$message)
  }
  expect_identical(delay(119.4), "Retry-After: 119 seconds.")
  expect_identical(delay(1), "Retry-After: 1 second.")
  expect_identical(delay(0), "Retry-After: 0 seconds.")
  expect_identical(delay(99999999999), "Retry-After: 99999999999 seconds.")
  for (seconds in c(Inf, NaN, NA_real_)) {
    expect_false(grepl("Retry-After", status_diagnosis(503L, seconds)$message,
                       fixed = TRUE), label = format(seconds))
  }
  old <- options(OutDec = ",")
  comma <- tryCatch(delay(119.4), finally = options(old))
  expect_identical(comma, "Retry-After: 119 seconds.")
})

test_that("ROBO-ybzbxfml: an invalid Retry-After is left out", {
  # robots_fetch() keeps the raw value but no delay (ROBO-cthdyvlk).
  x <- ybz_status(429L, headers = list(`Retry-After` = "soon"))
  expect_identical(x$diagnostics$code, "acquisition_http_429")
  expect_false(grepl("Retry-After", x$diagnostics$message, fixed = TRUE))
  expect_false(grepl("soon", x$diagnostics$message, fixed = TRUE))
})

test_that("ROBO-ybzbxfml: a past HTTP-date Retry-After is zero seconds", {
  local_mocked_bindings(
    acquire_now = function() {
      as.double(as.POSIXct("2026-11-05 12:00:00", tz = "UTC"))
    }
  )
  x <- ybz_status(
    503L, headers = list(`Retry-After` = "Thu, 05 Nov 2026 11:00:00 GMT")
  )
  expect_true(grepl("Retry-After: 0 seconds.", x$diagnostics$message,
                    fixed = TRUE))
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
  codes <- c(
    `403` = "acquisition_http_4xx", `503` = "acquisition_http_5xx"
  )
  for (status in c(403L, 503L)) {
    small <- ybz_status(status)
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
    expect_identical(x$diagnostics$code, codes[[as.character(status)]])
    # Its headers are lost, so no Retry-After is reported.
    expect_identical(x$diagnostics$severity, small$diagnostics$severity)
    expect_identical(x$diagnostics$message, small$diagnostics$message)
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
  expect_identical(x$diagnostics$code, "acquisition_http_4xx")
  expect_identical(x$documents$warning_count, 1L)
})
