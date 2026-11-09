# ROBO-bsloeclp: redirect, transport and safety outcomes of
# robots_validate_url(), and the terminal redirect reason on the robots frame.
# Responses are scripted at the ssrfr boundary (helper-fake-ssrfr.R).

bsl_validate <- function(handler, url = "http://a/", ...,
                         env = parent.frame()) {
  local_fake_ssrfr(handler, env = env)
  robots_validate_url(url, ...)
}

bsl_fetch <- function(handler, url = "http://a/", ..., env = parent.frame()) {
  local_fake_ssrfr(handler, env = env)
  robots_fetch(url, ...)
}

# A 301 to /r1, /r2, ... forever: the sixth 3xx is over the budget.
bsl_chain <- function(req) {
  hop <- suppressWarnings(as.integer(sub("^https?://a/r", "", req$url)))
  hop <- if (is.na(hop)) 1L else hop + 1L
  fake_response(301L, url = req$url,
                headers = list(Location = paste0("/r", hop)))
}

bsl_redirect_to <- function(location, status = 301L) {
  function(req) {
    if (identical(req$url, "http://a/robots.txt") ||
          identical(req$url, "https://a/robots.txt")) {
      return(fake_response(status, url = req$url,
                           headers = list(Location = location)))
    }
    fake_response(200L, url = req$url, body = "user-agent: *\n")
  }
}

# One scripted fetch per outcome class: the URL, the handler, and the
# fetch_outcome, terminal_redirect_reason and safety_block_reason it yields.
bsl_cases <- list(
  over_budget = list(
    url = "http://a/", handler = bsl_chain,
    outcome = "redirect_error", terminal = "over_budget", safety = NA
  ),
  no_location = list(
    url = "http://a/",
    handler = function(req) fake_response(301L, url = req$url),
    outcome = "redirect_error", terminal = "no_location", safety = NA
  ),
  loop = list(
    url = "http://a/",
    handler = function(req) {
      fake_response(301L, url = req$url, headers = list(Location = req$url))
    },
    outcome = "redirect_error", terminal = "loop", safety = NA
  ),
  downgrade = list(
    url = "https://a/", handler = bsl_redirect_to("http://a/robots.txt"),
    outcome = "redirect_error", terminal = "downgrade",
    safety = "https_downgrade"
  ),
  non_http_target = list(
    url = "http://a/", handler = bsl_redirect_to("ftp://a/robots.txt"),
    outcome = "redirect_error", terminal = "non_http_target",
    safety = "scheme"
  ),
  ssrf_origin = list(
    url = "http://127.0.0.1/",
    handler = function(req) stop("never fetched"),
    outcome = "ssrf_blocked", terminal = "none", safety = "loopback"
  ),
  ssrf_target = list(
    url = "http://a/", handler = bsl_redirect_to("http://10.0.0.1/robots.txt"),
    outcome = "ssrf_blocked", terminal = "none", safety = "private"
  ),
  timeout = list(
    url = "http://a/", handler = function(req) fake_failure("timeout"),
    outcome = "timeout", terminal = "none", safety = NA
  ),
  tls_error = list(
    url = "http://a/", handler = function(req) fake_failure("tls-failed"),
    outcome = "tls_error", terminal = "none", safety = NA
  ),
  network_error = list(
    url = "http://a/", handler = function(req) fake_failure("unresolvable"),
    outcome = "network_error", terminal = "none", safety = NA
  )
)

bsl_see <- " See robots_engine_contract_v1()."
bsl_gaps <- "Google: not documented; Yandex: not documented; Bing: not documented."
bsl_refusal <- "robotstxtr's safety refusal"

# The code and the full message robots_validate_url() gives each case.
bsl_expected <- list(
  over_budget = list(
    code = "acquisition_redirect_over_budget",
    message = paste0(
      "Exceeded the maximum of five redirects: Google: may stop and treat it ",
      "as a 404, which places no restrictions on crawling; Yandex: not ",
      "documented; Bing: not documented.", bsl_see
    )
  ),
  no_location = list(
    code = "acquisition_redirect_no_location",
    message = paste0(
      "HTTP 301 redirect without a usable Location header: ", bsl_gaps, bsl_see
    )
  ),
  loop = list(
    code = "acquisition_redirect_loop",
    message = paste0("Redirect loop detected: ", bsl_gaps, bsl_see)
  ),
  downgrade = list(
    code = "acquisition_redirect_downgrade",
    message = paste0(
      "Rejected an HTTPS-to-HTTP downgrade redirect: ", bsl_refusal,
      " under safety_level \"strict\", not an engine reading; Google: no ",
      "source says it refuses one (inferred to follow it); Yandex: no source ",
      "says it refuses one (inferred to follow it); Bing: not documented.",
      bsl_see
    )
  ),
  non_http_target = list(
    code = "acquisition_redirect_non_http",
    message = paste0(
      "Redirect to a non-HTTP(S) target: ", bsl_refusal,
      " (safety_block_reason \"scheme\"), not an engine reading; ", bsl_gaps,
      bsl_see
    )
  ),
  ssrf_origin = list(
    code = "acquisition_safety_refused",
    message = paste0(
      "Blocked by SSRF guard (loopback): ", bsl_refusal,
      " (safety_block_reason \"loopback\"); nothing was requested there, so ",
      "no engine reading applies.", bsl_see
    )
  ),
  ssrf_target = list(
    code = "acquisition_safety_refused",
    message = paste0(
      "Blocked by SSRF guard (private): ", bsl_refusal,
      " (safety_block_reason \"private\"); nothing was requested there, so ",
      "no engine reading applies.", bsl_see
    )
  )
)
bsl_transport <- paste0(
  ": Google: context-dependent (may pause crawling or use its last cached ",
  "copy); Yandex: not documented; Bing: not documented.", bsl_see
)
bsl_expected$timeout <- list(
  code = "acquisition_transport_failed",
  message = paste0("Fetch failed (timeout)", bsl_transport)
)
bsl_expected$tls_error <- list(
  code = "acquisition_transport_failed",
  message = paste0("Fetch failed (tls-failed)", bsl_transport)
)
bsl_expected$network_error <- list(
  code = "acquisition_transport_failed",
  message = paste0("Fetch failed (unresolvable)", bsl_transport)
)

# --- the robots frame -------------------------------------------------------

test_that("ROBO-bsloeclp: the robots frame ends with the two new columns", {
  x <- bsl_fetch(bsl_cases$over_budget$handler)
  n <- ncol(x$robots)
  expect_identical(
    names(x$robots)[(n - 2L):n],
    c("terminal_redirect_reason", "safety_block_reason", "body")
  )
  expect_type(x$robots$terminal_redirect_reason, "character")
  expect_type(x$robots$safety_block_reason, "character")
})

test_that("ROBO-bsloeclp: robots_fetch() records each terminal reason", {
  for (name in names(bsl_cases)) {
    case <- bsl_cases[[name]]
    x <- bsl_fetch(case$handler, url = case$url)
    expect_identical(x$robots$fetch_outcome, case$outcome, label = name)
    expect_identical(x$robots$terminal_redirect_reason, case$terminal,
                     label = name)
    expect_identical(x$robots$safety_block_reason,
                     as.character(case$safety), label = name)
  }
})

test_that("ROBO-bsloeclp: a body, or a redirect followed, is none and NA", {
  fetched <- bsl_fetch(bsl_redirect_to("/elsewhere.txt"))
  expect_identical(fetched$robots$fetch_outcome, "fetched")
  expect_identical(fetched$robots$redirect_count, 1L)
  expect_identical(fetched$robots$terminal_redirect_reason, "none")
  expect_identical(fetched$robots$safety_block_reason, NA_character_)

  missing <- bsl_fetch(function(req) fake_response(404L, url = req$url))
  expect_identical(missing$robots$terminal_redirect_reason, "none")
  expect_identical(missing$robots$safety_block_reason, NA_character_)

  empty <- robots_fetch(character())
  expect_identical(empty$robots$terminal_redirect_reason, character())
  expect_identical(empty$robots$safety_block_reason, character())
})

test_that("ROBO-bsloeclp: allowed_by_robots_*() carry the same columns", {
  local_fake_ssrfr(bsl_redirect_to("ftp://a/robots.txt"))
  url <- allowed_by_robots_url("http://a/x", "bot")
  fetch <- robots_fetch("http://a/x")
  expect_identical(url$robots, fetch$robots)
  expect_identical(url$robots$terminal_redirect_reason, "non_http_target")
  expect_identical(url$robots$safety_block_reason, "scheme")

  text <- allowed_by_robots_text("user-agent: *\n", "http://a/x", "bot")
  expect_named(text$robots, names(url$robots))
  expect_identical(text$robots$terminal_redirect_reason, "none")
  expect_identical(text$robots$safety_block_reason, NA_character_)
})

test_that("ROBO-bsloeclp: the legacy v1 frame carries the evidence values", {
  for (name in c("loop", "downgrade", "ssrf_target", "timeout")) {
    case <- bsl_cases[[name]]
    local({
      local_fake_ssrfr(case$handler)
      fetch <- robots_fetch(case$url)
      legacy <- as_legacy_robots_decisions_v1(robots_evaluate_url_v1(
        case$url, "bot", "google", "google"
      ))
      expect_named(legacy$robots, names(fetch$robots))
      expect_identical(legacy$robots$terminal_redirect_reason,
                       fetch$robots$terminal_redirect_reason, label = name)
      expect_identical(legacy$robots$safety_block_reason,
                       fetch$robots$safety_block_reason, label = name)
    })
  }
})

# --- the validator ----------------------------------------------------------

test_that("ROBO-bsloeclp: each outcome class has its own code and message", {
  expect_setequal(names(bsl_expected), names(bsl_cases))
  for (name in names(bsl_cases)) {
    case <- bsl_cases[[name]]
    want <- bsl_expected[[name]]
    x <- bsl_validate(case$handler, url = case$url)
    expect_identical(x$documents$fetch_outcome, case$outcome, label = name)
    expect_identical(x$documents$validation_status, "not_validated",
                     label = name)
    expect_identical(x$documents$error_count, 1L, label = name)
    expect_identical(x$diagnostics$code, want$code, label = name)
    expect_identical(x$diagnostics$severity, "error", label = name)
    expect_identical(x$diagnostics$message, want$message, label = name)
  }
})

test_that("ROBO-bsloeclp: no class falls back to acquisition_failed", {
  for (name in names(bsl_cases)) {
    case <- bsl_cases[[name]]
    x <- bsl_validate(case$handler, url = case$url)
    expect_false(identical(x$diagnostics$code, "acquisition_failed"),
                 label = name)
  }
})

test_that("ROBO-bsloeclp: the code comes from the columns, not the message", {
  source <- data.frame(
    fetch_outcome = "redirect_error", terminal_redirect_reason = "loop",
    safety_block_reason = NA_character_, error_message = "Something else.",
    stringsAsFactors = FALSE
  )
  diagnosis <- acquisition_diagnosis(source)
  expect_identical(diagnosis$code, "acquisition_redirect_loop")
  expect_true(startsWith(diagnosis$message, "Something else: Google: "))

  source$error_message <- NA_character_
  expect_true(startsWith(
    acquisition_diagnosis(source)$message,
    "Acquisition outcome 'redirect_error': Google: "
  ))

  # A redirect error with no terminal reason is not one of the classes.
  source$terminal_redirect_reason <- "none"
  expect_null(acquisition_diagnosis(source))
})

test_that("ROBO-bsloeclp: engine readings follow engine_policy_table_v1()", {
  real <- engine_policy_table_v1
  local_mocked_bindings(engine_policy_table_v1 = function() {
    table <- real()
    rows <- table$ruleset == "google" &
      table$category %in% c("redirect_over_budget", "transport")
    table$policy_status[rows] <- "documentation_gap"
    table$policy_action[rows] <- NA_character_
    table
  })
  for (name in c("over_budget", "timeout")) {
    case <- bsl_cases[[name]]
    message <- bsl_validate(case$handler, url = case$url)$diagnostics$message
    expect_true(grepl(": Google: not documented; Yandex: not documented;",
                      message, fixed = TRUE), label = message)
  }
})

test_that("ROBO-bsloeclp: every cell the validator reads has a phrase", {
  table <- engine_policy_table_v1()
  for (category in c("redirect_over_budget", "transport", "protocol_error")) {
    for (ruleset in c("google", "yandex", "bing")) {
      row <- table[table$category == category & table$ruleset == ruleset, ,
                   drop = FALSE]
      expect_identical(nrow(row), 1L, label = paste(category, ruleset))
      phrase <- status_policy_phrase(
        ruleset, category, row$policy_status[[1L]], row$policy_action[[1L]]
      )
      expect_true(nzchar(phrase), label = paste(category, ruleset))
    }
  }
})

test_that("ROBO-bsloeclp: two URLs on one refused origin give one diagnostic", {
  x <- bsl_validate(
    bsl_cases$loop$handler, url = c("http://a/x", "http://a/y")
  )
  expect_identical(nrow(x$documents), 1L)
  expect_identical(nrow(x$diagnostics), 1L)
  expect_identical(x$diagnostics$code, "acquisition_redirect_loop")
})
