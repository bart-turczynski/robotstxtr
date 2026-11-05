# ROBO-quovenef: the SSRF guard on the fetch policy, which ssrfr enforces since
# ROBO-jbralthm. The address and name classification is ssrfr's, and its own
# tests pin it; these pin what robotstxtr publishes for it: each refusal's
# `safety_block_reason`, that a refused origin is never fetched, that a refused
# redirect target is `ssrf_blocked`, and the deprecated `ssrf_guard = FALSE`.
#
# Every refusal here is decided by the real ssrfr before any resolution or
# connection (address literals, the metadata names, the port), so the file is
# offline. acquire_fetch() is replaced by a stub that fails the test if a
# refused hop is ever fetched.

local_no_fetch <- function(env = parent.frame()) {
  local_mocked_bindings(
    acquire_fetch = function(binding) stop("must not fetch: ", binding$url),
    .env = env
  )
}

safety_reason_of <- function(url) {
  evidence <- robots_evaluate_url_v1(url, "Googlebot", "google", "google")
  evidence$evidence$safety_block_reason
}

# Requested origin -> the published safety_block_reason.
refused_origins <- c(
  "http://127.0.0.1/" = "loopback",
  "http://10.0.0.1/" = "private",
  "http://172.16.0.1/" = "private",
  "http://192.168.1.1/" = "private",
  "http://169.254.169.254/" = "cloud-metadata",
  "http://169.254.0.1/" = "link-local",
  "http://0.0.0.0/" = "unspecified",
  "http://0.1.2.3/" = "this-network",
  "http://100.64.0.1/" = "shared",
  "http://[::1]/" = "loopback",
  "http://[::]/" = "unspecified",
  "http://[::ffff:127.0.0.1]/" = "ipv4-mapped",
  "http://[::ffff:0:7f00:1]/" = "ipv4-translated",
  "http://[::7f00:1]/" = "ipv4-compatible",
  "http://[64:ff9b::7f00:1]/" = "nat64",
  "http://[2002:7f00:1::]/" = "6to4",
  "http://[2001:0:0:0:0:0:f5ff:fffe]/" = "teredo",
  "http://[2001:db8::5efe:a00:1]/" = "isatap",
  "http://[fe80::1]/" = "link-local",
  "http://[fd00:ec2::254]/" = "cloud-metadata",
  "http://[fd00:0ec2::254]/" = "cloud-metadata",
  # ROBO-xzbyxipg: GCP's IPv6 metadata endpoint, now a provider endpoint.
  "http://[fd20:ce::254]/" = "cloud-metadata",
  # Unique local addresses, which the old guard let through, are private.
  "http://[fd00::1]/" = "private",
  "http://metadata.google.internal/" = "cloud-metadata",
  "http://metadata.google.internal./" = "cloud-metadata",
  "http://METADATA.google.internal./" = "cloud-metadata",
  "http://metadata/" = "cloud-metadata",
  # Three of the five codes the 2026-11-05.1 schema revision admits; parse
  # and userinfo can only come from a redirect Location (test-acquire).
  "http://224.0.0.1/" = "multicast",
  "http://240.0.0.1/" = "reserved",
  "http://a:0/" = "port"
)

test_that("each refused origin publishes its safety_block_reason", {
  local_no_fetch()
  for (url in names(refused_origins)) {
    expect_identical(
      safety_reason_of(url), refused_origins[[url]], info = url
    )
  }
})

test_that("a refused origin is ssrf_blocked in robots_fetch(), unfetched", {
  local_no_fetch()
  x <- robots_fetch(c("http://169.254.169.254/x", "http://[fd00::1]/y"))
  expect_identical(x$robots$fetch_outcome, c("ssrf_blocked", "ssrf_blocked"))
  expect_identical(x$robots$http_status, c(NA_integer_, NA_integer_))
  expect_identical(
    x$robots$error_class, c("robots_ssrf_blocked", "robots_ssrf_blocked")
  )
  expect_identical(
    x$robots$error_message,
    c(
      "Blocked by SSRF guard (cloud-metadata).",
      "Blocked by SSRF guard (private)."
    )
  )
})

test_that("a refusal is evidence_status safety_refused", {
  local_no_fetch()
  x <- robots_evaluate_url_v1(
    "http://224.0.0.1/x", "Googlebot", "google", "google"
  )
  expect_identical(x$evidence$evidence_status, "safety_refused")
  expect_identical(x$evidence$legacy_fetch_outcome, "ssrf_blocked")
  expect_identical(x$evidence$redirect_count, 0L)
})

test_that("the metadata name is refused under a Turkish locale", {
  # ROBO-dxrljrde: tolower() follows LC_CTYPE, and tr_TR maps "I" to dotless
  # "ı". robots_origin() and ssrfr both fold ASCII only.
  old <- Sys.getlocale("LC_CTYPE")
  on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
  set <- suppressWarnings(Sys.setlocale("LC_CTYPE", "tr_TR.UTF-8"))
  skip_if(!nzchar(set), "tr_TR.UTF-8 locale not installed")
  local_no_fetch()
  expect_identical(
    safety_reason_of("http://METADATA.GOOGLE.INTERNAL/x"), "cloud-metadata"
  )
})

test_that("a redirect to a private target is blocked as ssrf_blocked", {
  local_fake_ssrfr(function(req) {
    if (identical(req$url, "http://a/robots.txt")) {
      fake_response(
        status_code = 301L, url = req$url,
        headers = list(Location = "http://169.254.169.254/robots.txt")
      )
    } else {
      stop(sprintf("unexpected request URL in fake: %s", req$url))
    }
  })

  x <- robots_fetch("http://a/x")

  expect_identical(x$robots$fetch_outcome, "ssrf_blocked")
  expect_identical(x$robots$redirect_count, 1L)
})

test_that("allowed_by_robots_url maps ssrf_blocked to fetch_unknown/NA", {
  local_no_fetch()

  x <- allowed_by_robots_url("http://169.254.169.254/x", "bot")

  expect_true(is.na(x$results$allowed))
  expect_identical(x$results$decision_source, "fetch_unknown")
})

test_that("validate_ssrf_guard rejects non-logical / non-scalar / NA input", {
  expect_error(
    validate_ssrf_guard("yes"),
    class = "robotstxtr_invalid_ssrf_guard"
  )
  expect_error(
    validate_ssrf_guard(c(TRUE, FALSE)),
    class = "robotstxtr_invalid_ssrf_guard"
  )
  expect_error(
    validate_ssrf_guard(NA),
    class = "robotstxtr_invalid_ssrf_guard"
  )
  expect_invisible(validate_ssrf_guard(TRUE))
})

test_that("ssrf_guard = FALSE is deprecated and reopens private ranges", {
  # ROBO-jbralthm: ssrfr has no off switch, so FALSE selects a permissive
  # policy. The fake stands in for the intranet host that would answer.
  local_fake_ssrfr(function(req) {
    fake_response(
      status_code = 200L, url = req$url,
      body = charToRaw("user-agent: *\ndisallow: /private\n")
    )
  })

  guarded <- robots_fetch("http://10.0.0.1/robots.txt")
  expect_identical(guarded$robots$fetch_outcome, "ssrf_blocked")

  expect_warning(
    opted_out <- robots_fetch("http://10.0.0.1/robots.txt", ssrf_guard = FALSE),
    class = "robotstxtr_deprecated_ssrf_guard"
  )
  expect_identical(opted_out$robots$fetch_outcome, "fetched")

  # It also threads through the URL-first path, warning once per call.
  expect_warning(
    decided <- allowed_by_robots_url(
      "http://10.0.0.1/private", "bot",
      ssrf_guard = FALSE
    ),
    class = "robotstxtr_deprecated_ssrf_guard"
  )
  expect_false(decided$results$allowed)
  expect_identical(decided$results$decision_source, "rule_disallow")
})

test_that("ssrf_guard = FALSE still refuses provider endpoints", {
  # Exact provider endpoints stay refused under the permissive policy, and so
  # do the transition forms ssrfr refuses whatever the policy says.
  local_no_fetch()
  for (url in c(
    "http://169.254.169.254/", "http://[fd00:ec2::254]/",
    "http://[2002:7f00:1::]/"
  )) {
    expect_warning(
      x <- robots_fetch(url, ssrf_guard = FALSE),
      class = "robotstxtr_deprecated_ssrf_guard"
    )
    expect_identical(x$robots$fetch_outcome, "ssrf_blocked", info = url)
  }
})

test_that("robots_evaluate_url_v1 warns once on ssrf_guard = FALSE", {
  local_no_fetch()
  expect_warning(
    x <- robots_evaluate_url_v1(
      c("http://169.254.169.254/a", "http://169.254.169.254/b"),
      "Googlebot", "google", "google",
      ssrf_guard = FALSE
    ),
    class = "robotstxtr_deprecated_ssrf_guard"
  )
  expect_false(x$evidence$ssrf_guard)
})
