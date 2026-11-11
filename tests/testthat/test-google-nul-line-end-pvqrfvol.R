# ROBO-pvqrfvol: how the Google backend reads a NUL byte in a fetched body.
#
# Only a fetched body can carry a NUL (an R string cannot), so each case is
# served at the ssrfr boundary (helper-fake-ssrfr.R) and read through
# allowed_by_robots_url() and robots_evaluate_url_v1() with the google
# backend; the decoded matcher string is pinned too.

pv_nul <- as.raw(0)

# Raw bytes from strings and raw vectors, in order.
pv_bytes <- function(...) {
  unlist(lapply(list(...), function(part) {
    if (is.character(part)) charToRaw(part) else part
  }), use.names = FALSE)
}

# The bytes the Google matcher is handed.
pv_decoded <- function(...) {
  charToRaw(decode_matcher_body(pv_bytes(...)))
}

# One row per path: the legacy decision, line and value, and the v1 facade's
# decision and line, with the body served as the site's robots.txt.
pv_google <- function(body, paths, token = "FooBot") {
  urls <- paste0("https://example.com", paths)
  local_fake_ssrfr(function(req) fake_response(200L, body = body))
  u <- allowed_by_robots_url(urls, token)$results
  v <- robots_evaluate_url_v1(urls, token, "google", "google")$results
  data.frame(
    path = paths, allowed = u$allowed, line = u$matched_line,
    value = u$matched_rule_value, v1 = v$url_decision, v1_line = v$matched_line,
    stringsAsFactors = FALSE
  )
}

pv_expect <- function(got, allowed, line, value) {
  expect_identical(got$allowed, allowed)
  expect_identical(got$line, as.integer(line))
  expect_identical(got$value, value)
  expect_identical(got$v1, ifelse(allowed, "allow", "disallow"))
  expect_identical(got$v1_line, as.integer(line))
}

test_that("a NUL inside a value is removed", {
  body <- pv_bytes("User-agent: *\nDisallow: /a", pv_nul, "b\n")
  expect_identical(
    pv_decoded(body), pv_bytes("User-agent: *\nDisallow: /ab\n")
  )
  pv_expect(pv_google(body, c("/a", "/ab", "/ac")),
            c(TRUE, FALSE, TRUE), c(NA, 2L, NA), c(NA, "/ab", NA))
})

test_that("a NUL at the start of a line is removed", {
  body <- pv_bytes("User-agent: *\n", pv_nul, "Disallow: /x\n")
  pv_expect(pv_google(body, "/x"), FALSE, 2L, "/x")
})

test_that("a NUL as the body's first byte is removed", {
  body <- pv_bytes(pv_nul, "User-agent: *\nDisallow: /x\n")
  pv_expect(pv_google(body, "/x"), FALSE, 2L, "/x")
})

test_that("a NUL before the colon is removed", {
  body <- pv_bytes("User-agent: *\nDisallow", pv_nul, ": /x\n")
  pv_expect(pv_google(body, "/x"), FALSE, 2L, "/x")
})

test_that("a NUL between CR and LF joins them into one CRLF", {
  body <- pv_bytes("User-agent: *\r", pv_nul, "\nDisallow: /x\n")
  expect_identical(
    pv_decoded(body), pv_bytes("User-agent: *\r\nDisallow: /x\n")
  )
  pv_expect(pv_google(body, "/x"), FALSE, 2L, "/x")
})

test_that("a NUL in a User-agent value is removed", {
  body <- pv_bytes("User-agent: Foo", pv_nul, "Bot\nDisallow: /x\n")
  pv_expect(pv_google(body, "/x"), FALSE, 2L, "/x")
})

test_that("a BOM before a NUL-bearing body is kept", {
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  body <- pv_bytes(bom, "User-agent: *\nDisallow: /a", pv_nul, "b\n")
  expect_identical(
    pv_decoded(body), pv_bytes(bom, "User-agent: *\nDisallow: /ab\n")
  )
  pv_expect(pv_google(body, c("/a", "/ab")),
            c(TRUE, FALSE), c(NA, 2L), c(NA, "/ab"))
})

test_that("a NUL inside a BOM prefix is removed", {
  body <- pv_bytes(as.raw(0xef), pv_nul, "User-agent: *\nDisallow: /x\n")
  pv_expect(pv_google(body, "/x"), FALSE, 2L, "/x")
})

test_that("UTF-16LE text without a BOM is read as its ASCII letters", {
  text <- charToRaw("User-agent: *\nDisallow: /a\n")
  body <- as.vector(rbind(text, pv_nul))
  expect_identical(pv_decoded(body), text)
  pv_expect(pv_google(body, "/a"), FALSE, 2L, "/a")
})

test_that("an empty body and a body of NULs decode to nothing", {
  expect_identical(pv_decoded(raw()), raw())
  expect_identical(pv_decoded(rep(pv_nul, 3L)), raw())
  pv_expect(pv_google(raw(), "/x"), TRUE, NA, NA_character_)
  pv_expect(pv_google(rep(pv_nul, 3L), "/x"), TRUE, NA, NA_character_)
})

test_that("several NULs on one line are all removed", {
  body <- pv_bytes("User-agent: *\nDisallow: /a", pv_nul, "b", pv_nul, "c\n")
  pv_expect(pv_google(body, c("/a", "/abc")),
            c(TRUE, FALSE), c(NA, 2L), c(NA, "/abc"))
})

test_that("a NUL on an unterminated last line is removed", {
  body <- pv_bytes("User-agent: *\nDisallow: /a", pv_nul, "b")
  expect_identical(
    pv_decoded(body), pv_bytes("User-agent: *\nDisallow: /ab")
  )
  pv_expect(pv_google(body, c("/a", "/ab")),
            c(TRUE, FALSE), c(NA, 2L), c(NA, "/ab"))
})

test_that("CR, LF and CRLF lines keep their numbers around a NUL", {
  body <- pv_bytes(
    "User-agent: *\r\nAllow: /q\rDisallow: /a", pv_nul, "b\n",
    "Disallow: /c\r\n"
  )
  pv_expect(pv_google(body, c("/a", "/ab", "/c", "/q")),
            c(TRUE, FALSE, FALSE, TRUE), c(NA, 3L, 4L, 2L),
            c(NA, "/ab", "/c", "/q"))
})

test_that("bytes on both sides of a NUL reach the matcher as written", {
  body <- pv_bytes(
    "User-agent: *\nDisallow: /", as.raw(0xff), pv_nul, as.raw(0xfe), "\n"
  )
  expect_identical(
    pv_decoded(body),
    pv_bytes("User-agent: *\nDisallow: /", as.raw(c(0xff, 0xfe)), "\n")
  )
})
