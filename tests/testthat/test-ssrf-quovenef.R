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

test_that("ssrf_check decodes every documented IPv6->IPv4 embedding", {
  # Each spelling below carries a blocked IPv4 address in its low 32 bits.
  # Left undecoded, any one of them walks straight past the IPv4 matrix, so
  # the guard must report the embedding form as the reason code.
  # IPv4-translated ::ffff:0:0:0/96 — 7f00:1 is 127.0.0.1.
  expect_identical(reason_of("[::ffff:0:7f00:1]"), "ipv4-translated")
  expect_identical(reason_of("[::ffff:0:127.0.0.1]"), "ipv4-translated")
  # NAT64 well-known 64:ff9b::/96.
  expect_identical(reason_of("[64:ff9b::7f00:1]"), "nat64")
  expect_identical(reason_of("[64:ff9b::10.0.0.1]"), "nat64")
  # IPv4-compatible ::/96 (deprecated SIIT).
  expect_identical(reason_of("[::7f00:1]"), "ipv4-compatible")
  expect_identical(reason_of("[::127.0.0.1]"), "ipv4-compatible")
  # a9fe:a9fe is 169.254.169.254, the cloud-metadata endpoint.
  expect_identical(reason_of("[::a9fe:a9fe]"), "ipv4-compatible")
  expect_false(ssrf_check("[64:ff9b::7f00:1]", "http")$allowed)
})

test_that("the NAT64 local-use /48 unpacks the u-byte-split IPv4", {
  # RFC 6052 s2.2: behind a 64:ff9b:1::/48 prefix the embedded IPv4 straddles
  # the reserved u-byte — octets 1-2 in hextet 4, octet 3 in the LOW byte of
  # hextet 5, octet 4 in the HIGH byte of hextet 6. Reading the last 32 bits
  # instead (as the /96 forms do) would miss these entirely.
  # 7f00 / 00 / 0100 -> 127.0.0.1.
  expect_identical(reason_of("[64:ff9b:1:7f00:0:100::]"), "nat64")
  # 0a00 / 00 / 0100 -> 10.0.0.1.
  expect_identical(reason_of("[64:ff9b:1:a00:0:100::]"), "nat64")
  # A public embedded address behind the same prefix stays allowed, matching
  # the IPv4-literal policy: 5db8 / d8 / 2200 -> 93.184.216.34.
  expect_true(ssrf_check("[64:ff9b:1:5db8:d8:2200::]", "http")$allowed)
})

test_that("IPv6 literals with no blocked embedding are allowed", {
  # No embedding prefix matches at all — the detector falls through.
  expect_true(ssrf_check("[2001:db8::1]", "http")$allowed)
  expect_true(is.na(reason_of("[2001:db8::1]")))
  # An embedding prefix matches but the embedded address is public
  # (5db8:d822 is 93.184.216.34), so it is allowed like the bare IPv4.
  expect_true(ssrf_check("[64:ff9b::5db8:d822]", "http")$allowed)
})

test_that("ssrf_expand_zero_run resolves every :: placement to 8 hextets", {
  # Fully written, no "::" at all.
  expect_identical(
    ssrf_expand_zero_run("0:0:0:0:0:ffff:7f00:1"),
    c("0", "0", "0", "0", "0", "ffff", "7f00", "1")
  )
  # Empty left side of the "::".
  expect_identical(ssrf_expand_zero_run("::1"), c(rep("0", 7L), "1"))
  # Empty right side of the "::".
  expect_identical(ssrf_expand_zero_run("fe80::"), c("fe80", rep("0", 7L)))
  # Both sides populated.
  expect_identical(
    ssrf_expand_zero_run("64:ff9b::7f00:1"),
    c("64", "ff9b", "0", "0", "0", "0", "7f00", "1")
  )
  # And the fully written form still classifies: it is ::ffff:127.0.0.1.
  expect_identical(reason_of("[0:0:0:0:0:ffff:7f00:1]"), "ipv4-mapped")
})

test_that("ssrf_expand_zero_run rejects malformed IPv6 shapes", {
  # A literal without "::" must carry exactly 8 groups.
  expect_null(ssrf_expand_zero_run("1:2:3"))
  # A second "::" makes the zero run ambiguous, so nothing is expanded.
  expect_null(ssrf_expand_zero_run("::ffff::1"))
  # Nothing left to fill: 8 groups are already written around the "::".
  expect_null(ssrf_expand_zero_run("1:2:3:4:5:6:7:8::"))
  # A shape the expander rejects is simply not an IP literal. It never
  # becomes a *decoded* address, so it can never match a blocked range by
  # accident — it falls through to the registered-name path.
  expect_true(is.na(reason_of("[1:2:3]")))
  expect_true(is.na(reason_of("[::ffff::1]")))
  expect_true(is.na(reason_of("[1:2:3:4:5:6:7:8::]")))
})

test_that("ssrf_check blocks IPv6 unspecified, link-local, and metadata", {
  expect_identical(reason_of("[::]"), "unspecified")
  # fe80::/10 spans fe80..febf in the leading hextet.
  expect_identical(reason_of("[fe80::1]"), "link-local")
  expect_identical(reason_of("[febf::1]"), "link-local")
  expect_identical(reason_of("[fe80::]"), "link-local")
  # AWS IPv6 metadata endpoint and anything under its fd00:ec2: prefix.
  expect_identical(reason_of("[fd00:ec2::254]"), "cloud-metadata")
  expect_identical(reason_of("[fd00:ec2:1::5]"), "cloud-metadata")
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

test_that("robots_ssrf_check recovers the scheme when rurl cannot parse", {
  # rurl errors outright on a bare-integer authority, so `parsed` is NULL and
  # both host and scheme come back empty. Without the raw-string fallback the
  # scheme gate would see "" and report "scheme", masking the real finding —
  # and a future gate reordering could let the numeric literal through. The
  # fallback must recover "http" so the numeric-literal rule is what fires.
  obf <- robots_ssrf_check("http://2130706433/robots.txt")
  expect_false(obf$allowed)
  expect_identical(obf$reason, "numeric-literal")
  expect_identical(
    robots_ssrf_check("http://0x7f000001/x")$reason, "numeric-literal"
  )
  # The recovered scheme is still gated: an unparseable authority behind a
  # non-http(s) scheme is rejected on the scheme, not silently allowed.
  expect_identical(robots_ssrf_check("ftp://2130706433/x")$reason, "scheme")
  # No scheme at all in the raw string either — nothing to recover.
  expect_identical(robots_ssrf_check("2130706433/x")$reason, "scheme")
})

test_that("robots_ssrf_check defers on a URL it cannot classify at all", {
  # Nothing structural to match, so the guard stays out of the way and lets
  # the fetch layer report the real input error rather than a bogus block.
  expect_true(robots_ssrf_check(NA_character_)$allowed)
  expect_true(robots_ssrf_check("")$allowed)
  expect_true(robots_ssrf_check(character(0L))$allowed)
  expect_true(robots_ssrf_check(2130706433)$allowed)
  expect_true(is.na(robots_ssrf_check(NA_character_)$reason))
})

test_that("ssrf_raw_scheme_of lowercases and only matches a real scheme", {
  expect_identical(ssrf_raw_scheme_of("HTTP://example.com/x"), "http")
  expect_identical(ssrf_raw_scheme_of("hTtPs://a/b"), "https")
  expect_identical(ssrf_raw_scheme_of("ftp://a/b"), "ftp")
  # Without the "://" authority marker there is no scheme to recover; a bare
  # "mailto:" must not be mistaken for one and pass the http/https gate.
  expect_identical(ssrf_raw_scheme_of("example.com/x"), NA_character_)
  expect_identical(ssrf_raw_scheme_of("mailto:a@b"), NA_character_)
  expect_identical(ssrf_raw_scheme_of(NA_character_), NA_character_)
  expect_identical(ssrf_raw_scheme_of(""), NA_character_)
  expect_identical(ssrf_raw_scheme_of(character(0L)), NA_character_)
})

test_that("ssrf_raw_host_of slices the pre-normalization host", {
  # Userinfo and port are dropped, so credentials cannot hide the literal
  # (http://example.com@127.0.0.1/ must still expose 127.0.0.1).
  expect_identical(
    ssrf_raw_host_of("http://u:p@127.0.0.1:8080/x"), "127.0.0.1"
  )
  expect_identical(
    ssrf_raw_host_of("http://example.com@2130706433/x"), "2130706433"
  )
  # Bracketed IPv6 keeps its brackets: the colon test downstream needs them
  # to tell an IPv6 literal from a host:port pair.
  expect_identical(ssrf_raw_host_of("http://[::1]:8080/x"), "[::1]")
  expect_identical(ssrf_raw_host_of("http://example.com?q=1"), "example.com")
  expect_identical(ssrf_raw_host_of("http://example.com#f"), "example.com")
  expect_identical(ssrf_raw_host_of(NA_character_), NA_character_)
  expect_identical(ssrf_raw_host_of(character(0L)), NA_character_)
})

test_that("the IPv6 helpers reject non-scalar, NA, and malformed input", {
  expect_false(ssrf_is_dotted_quad(c("1.2.3.4", "5.6.7.8")))
  expect_false(ssrf_is_dotted_quad(character(0L)))
  expect_false(ssrf_is_dotted_quad(NA_character_))
  expect_false(ssrf_is_dotted_quad(""))
  expect_null(ssrf_ipv6_candidate(NULL))
  expect_null(ssrf_ipv6_candidate(NA_character_))
  expect_null(ssrf_ipv6_candidate(""))
  expect_null(ssrf_ipv6_candidate(character(0L)))
  # No colon at all: a registered name is not an IPv6 candidate.
  expect_null(ssrf_ipv6_candidate("example.com"))
  # A percent-encoded zone id falls outside the hex/colon/dot alphabet.
  expect_null(ssrf_ipv6_candidate("::1%25eth0"))
  # Brackets are stripped upstream, so a bracketed literal is not a candidate.
  expect_null(ssrf_ipv6_candidate("[::1]"))
  expect_identical(ssrf_ipv6_candidate("::FFFF:1"), "::ffff:1")
})

test_that("a malformed IPv4 tail makes the whole literal unparseable", {
  # 999.1.1.1 and 256.0.0.1 are not canonical dotted-quads. The fold refuses
  # rather than folding out-of-range octets into hextets, which would
  # silently shift the address out of the range it should have matched.
  expect_null(ssrf_fold_ipv4_tail("::ffff:999.1.1.1"))
  expect_null(ssrf_fold_ipv4_tail("::ffff:256.0.0.1"))
  expect_null(ssrf_ipv6_hextets("::ffff:999.1.1.1"))
  # No tail at all: returned unchanged.
  expect_identical(ssrf_fold_ipv4_tail("::1"), "::1")
  expect_identical(ssrf_fold_ipv4_tail("::ffff:127.0.0.1"), "::ffff:7f00:1")
  # Not an IPv6 candidate at all.
  expect_null(ssrf_ipv6_hextets("example.com"))
  # Groups that do not expand to 8, and a group wider than 4 hex digits.
  expect_null(ssrf_ipv6_numeric_groups("1:2:3"))
  expect_null(ssrf_ipv6_numeric_groups("1:2:3:4:5:6:7:abcde"))
  expect_identical(ssrf_ipv6_numeric_groups("::1"), c(rep(0, 7L), 1))
})

test_that("ssrf_check allows an absent host and defers to downstream rules", {
  # Nothing to range-match: the guard must not invent a block, and must not
  # error on an NA, empty, or zero-length host.
  na_host <- ssrf_check(NA_character_, "http", raw_host = NA_character_)
  expect_true(na_host$allowed)
  expect_true(is.na(na_host$reason))
  empty_host <- ssrf_check("", "http", raw_host = "")
  expect_true(empty_host$allowed)
  zero_len <- ssrf_check(character(0L), "http", raw_host = NA_character_)
  expect_true(zero_len$allowed)
})

test_that("rurl canonicalization catches dotted spellings of ::1 and ::", {
  # ::0.0.0.1 and ::0.0.0.0 are the SAME 128-bit addresses as ::1 and ::.
  # ssrf_classify_ipv6() only special-cases the exact strings "::1" and "::",
  # and ssrf_embedded_ipv4() deliberately skips tail32 <= 1, so the pure
  # matcher does not catch these spellings on its own. In the real path rurl
  # normalizes them first, which is what must keep holding.
  expect_identical(
    robots_ssrf_check("http://[::0.0.0.1]/x")$reason, "loopback"
  )
  expect_identical(
    robots_ssrf_check("http://[::0.0.0.0]/x")$reason, "unspecified"
  )
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

test_that("ssrf_guard = FALSE opts out and a private host is fetched", {
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
