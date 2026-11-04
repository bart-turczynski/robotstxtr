# ROBO-atvfjuuw: an IPv6 literal with a zone ID. rurl reports no host for one,
# while libcurl drops the zone and dials the bare address. Since ROBO-jbralthm
# there is no second parse to reconcile: robots_origin() refuses a zoned
# literal as input_invalid, and a redirect Location carrying one is refused by
# ssrfr as "parse", the WHATWG and libcurl parsers disagreeing on the host.
# Offline: the fake at the ssrfr boundary checks each hop with the real ssrfr.

zoned <- c(
  "http://[::1%25lo0]/",
  "http://[fd00:ec2::254%25lo0]/",
  "http://[::ffff:127.0.0.1%25lo0]/",
  "http://[fe80::1%25eth0]/",
  "http://[::1%lo0]/",
  "http://[fe80::1%eth0]/",
  "http://[::1%25lo0]:8080/",
  "http://user:pw@[::1%25lo0]/",
  # A public address gains nothing from a zone either.
  "http://[2606:4700::1%25eth0]/",
  # Bracketed hosts that are no IPv6 literal.
  "http://[not-an-address%25x]/",
  "http://[v1.foo]/"
)

test_that("a zoned literal is never a fetch origin", {
  local_mocked_bindings(
    acquire_prepare_hop = function(...) stop("must not prepare")
  )
  for (url in zoned) {
    x <- robots_fetch(url)
    expect_identical(x$map$fetch_outcome, "input_invalid", info = url)
    expect_identical(nrow(x$robots), 0L, info = url)
  }
})

test_that("a redirect to a zoned literal is refused as parse", {
  for (location in zoned) {
    local_fake_ssrfr(function(req) {
      if (!identical(req$url, "http://a/robots.txt")) {
        stop(sprintf("unexpected request URL in fake: %s", req$url))
      }
      fake_response(301L, headers = list(Location = location))
    })
    x <- robots_evaluate_url_v1("http://a/x", "Googlebot", "google", "google")
    expect_identical(x$evidence$legacy_fetch_outcome, "ssrf_blocked",
                     info = location)
    expect_identical(x$evidence$safety_block_reason, "parse", info = location)
    expect_identical(x$evidence$evidence_status, "safety_refused",
                     info = location)
  }
})
