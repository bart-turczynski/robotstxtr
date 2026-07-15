# ROBO-quovenef: structural SSRF guard on the fetch policy. Pure-matcher unit
# tests (ssrf_check / robots_ssrf_check, fully offline) plus integration tests
# proving a blocked initial origin or redirect target yields the `ssrf_blocked`
# outcome and a fetch_unknown (NA) decision, with no socket opened.

# ssrf_check() is exercised directly (no rurl, no network) so the reason codes
# and range matrix are pinned deterministically, independent of how rurl might
# normalize a given literal.
reason_of <- function(host, scheme = "http", raw_host = host) {
  ssrf_check(host, scheme, raw_host = raw_host)$reason
}

test_that("ssrf_check blocks the documented IPv4 ranges with stable reasons", {
  expect_identical(reason_of("127.0.0.1"), "loopback")
  expect_identical(reason_of("10.0.0.1"), "private")
  expect_identical(reason_of("172.16.0.1"), "private")
  expect_identical(reason_of("192.168.1.1"), "private")
  expect_identical(reason_of("169.254.169.254"), "cloud-metadata")
  expect_identical(reason_of("169.254.0.1"), "link-local")
  expect_identical(reason_of("0.0.0.0"), "unspecified")
  expect_false(ssrf_check("127.0.0.1", "http")$allowed)
})

test_that("ssrf_check blocks IPv6 loopback, embeddings, and metadata names", {
  expect_identical(reason_of("[::1]"), "loopback")
  expect_identical(reason_of("[::ffff:127.0.0.1]"), "ipv4-mapped")
  expect_identical(reason_of("metadata.google.internal"), "cloud-metadata")
})

test_that("ssrf_check rejects non-http(s) schemes and numeric-literal hosts", {
  expect_identical(ssrf_check("example.com", "ftp")$reason, "scheme")
  expect_identical(
    ssrf_check(NA_character_, "http", raw_host = "0x7f000001")$reason,
    "numeric-literal"
  )
  expect_identical(
    ssrf_check(NA_character_, "http", raw_host = "2130706433")$reason,
    "numeric-literal"
  )
})

test_that("ssrf_check allows ordinary public hosts and public IPs", {
  pub_name <- ssrf_check("example.com", "https")
  expect_true(pub_name$allowed)
  expect_true(is.na(pub_name$reason))
  expect_true(ssrf_check("93.184.216.34", "http")$allowed)
})

test_that("robots_ssrf_check blocks reserved hosts via the rurl parse path", {
  expect_false(robots_ssrf_check("http://127.0.0.1/robots.txt")$allowed)
  expect_false(robots_ssrf_check("http://10.0.0.1/robots.txt")$allowed)
  expect_false(robots_ssrf_check("http://192.168.1.1/robots.txt")$allowed)
  expect_identical(
    robots_ssrf_check("http://169.254.169.254/x")$reason, "cloud-metadata"
  )
  expect_false(robots_ssrf_check("http://[::1]/robots.txt")$allowed)
})

test_that("robots_ssrf_check allows ordinary public hosts", {
  expect_true(robots_ssrf_check("https://example.com/some/page")$allowed)
  expect_true(robots_ssrf_check("http://93.184.216.34/robots.txt")$allowed)
})

test_that("an initial private origin is blocked before any request", {
  # The guard returns before build_fetch_request(), so this mock (which errors
  # on any request) must never be invoked; the outcome is ssrf_blocked, not a
  # network_error from a stopped request.
  httr2::local_mocked_responses(function(req) stop("must not fetch"))

  x <- robots_fetch("http://169.254.169.254/x")

  expect_identical(x$robots$fetch_outcome, "ssrf_blocked")
  expect_identical(x$robots$http_status, NA_integer_)
  expect_identical(x$robots$error_class, "robots_ssrf_blocked")
})

test_that("a redirect to a private target is blocked as ssrf_blocked", {
  httr2::local_mocked_responses(function(req) {
    if (identical(req$url, "http://a/robots.txt")) {
      httr2::response(
        status_code = 301L, url = req$url,
        headers = list(Location = "http://169.254.169.254/robots.txt")
      )
    } else {
      stop(sprintf("unexpected request URL in mock: %s", req$url))
    }
  })

  x <- robots_fetch("http://a/x")

  expect_identical(x$robots$fetch_outcome, "ssrf_blocked")
  expect_identical(x$robots$redirect_count, 1L)
})

test_that("allowed_by_robots_url maps ssrf_blocked to fetch_unknown/NA", {
  httr2::local_mocked_responses(function(req) stop("must not fetch"))

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

test_that("ssrf_guard = FALSE opts out: a private host is fetched, not blocked", {
  # The caller escape hatch (ROBO-quovenef): with the guard disabled the private
  # target is fetched normally instead of short-circuiting to ssrf_blocked. The
  # mock stands in for the intranet host that would answer in production.
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      status_code = 200L, url = req$url,
      body = charToRaw("user-agent: *\ndisallow: /private\n")
    )
  })

  guarded <- robots_fetch("http://169.254.169.254/robots.txt")
  expect_identical(guarded$robots$fetch_outcome, "ssrf_blocked")

  opted_out <- robots_fetch(
    "http://169.254.169.254/robots.txt",
    ssrf_guard = FALSE
  )
  expect_identical(opted_out$robots$fetch_outcome, "fetched")

  # It also threads through the URL-first path to a real allow/deny decision.
  decided <- allowed_by_robots_url(
    "http://169.254.169.254/private", "bot",
    ssrf_guard = FALSE
  )
  expect_false(decided$results$allowed)
  expect_identical(decided$results$decision_source, "rule_disallow")
})
