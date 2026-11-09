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

# --- the robots frame -------------------------------------------------------

test_that("ROBO-bsloeclp: the robots frame has no terminal redirect reason", {
  x <- bsl_fetch(bsl_cases$over_budget$handler)
  expect_false("terminal_redirect_reason" %in% names(x$robots))
  expect_false("safety_block_reason" %in% names(x$robots))
})

# --- the validator ----------------------------------------------------------

test_that("ROBO-bsloeclp: each outcome class is acquisition_failed", {
  for (name in names(bsl_cases)) {
    case <- bsl_cases[[name]]
    x <- bsl_validate(case$handler, url = case$url)
    expect_identical(x$documents$fetch_outcome, case$outcome, label = name)
    expect_identical(x$diagnostics$code, "acquisition_failed", label = name)
    expect_identical(x$diagnostics$severity, "error", label = name)
  }
})
