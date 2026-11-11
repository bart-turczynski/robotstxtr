# ROBO-pvqrfvol: on the Google backend a line ends at its first NUL byte.
#
# Google's open-source parser (src/robots.cc, RobotsTxtParser::Parse()) hands
# each line on as a NUL-terminated C string, so the bytes from a line's first
# NUL to its end are never read. decode_matcher_body() (R/body-decode.R) gives
# the matcher the same lines: each cut at its first NUL, joined with LF so
# that every line keeps its number. The answers below are upstream's.
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

test_that("a NUL inside a value ends the rule there", {
  body <- pv_bytes("User-agent: *\nDisallow: /a", pv_nul, "b\n")
  expect_identical(
    pv_decoded(body), pv_bytes("User-agent: *\nDisallow: /a\n")
  )
  pv_expect(pv_google(body, c("/a", "/ab", "/ac")),
            c(FALSE, FALSE, FALSE), c(2L, 2L, 2L), c("/a", "/a", "/a"))
})

test_that("a NUL at the start of a line leaves an empty line", {
  body <- pv_bytes("User-agent: *\n", pv_nul, "Disallow: /x\n")
  expect_identical(pv_decoded(body), pv_bytes("User-agent: *\n\n"))
  pv_expect(pv_google(body, "/x"), TRUE, NA, NA_character_)
})

test_that("a NUL as the body's first byte empties the first line", {
  # The Disallow then precedes every User-agent line, so no group holds it.
  body <- pv_bytes(pv_nul, "User-agent: *\nDisallow: /x\n")
  expect_identical(pv_decoded(body), pv_bytes("\nDisallow: /x\n"))
  pv_expect(pv_google(body, "/x"), TRUE, NA, NA_character_)
})

test_that("a NUL before the colon leaves a key with no value", {
  body <- pv_bytes("User-agent: *\nDisallow", pv_nul, ": /x\n")
  pv_expect(pv_google(body, "/x"), TRUE, NA, NA_character_)
})

test_that("a NUL between CR and LF is an empty line of its own", {
  # Upstream: CR ends line 1, the NUL starts line 2 (so the LF is no CRLF
  # continuation) and the LF ends it; the rule is on line 3.
  body <- pv_bytes("User-agent: *\r", pv_nul, "\nDisallow: /x\n")
  expect_identical(
    pv_decoded(body), pv_bytes("User-agent: *\n\nDisallow: /x\n")
  )
  pv_expect(pv_google(body, "/x"), FALSE, 3L, "/x")
})

test_that("a NUL in a User-agent value ends the name there", {
  body <- pv_bytes("User-agent: Foo", pv_nul, "Bot\nDisallow: /x\n")
  pv_expect(pv_google(body, "/x"), TRUE, NA, NA_character_)
  pv_expect(pv_google(body, "/x", token = "Foo"), FALSE, 2L, "/x")
})

test_that("a BOM before a NUL-bearing body is kept for the matcher", {
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  body <- pv_bytes(bom, "User-agent: *\nDisallow: /a", pv_nul, "b\n")
  expect_identical(
    pv_decoded(body), pv_bytes(bom, "User-agent: *\nDisallow: /a\n")
  )
  pv_expect(pv_google(body, c("/a", "/ab")),
            c(FALSE, FALSE), c(2L, 2L), c("/a", "/a"))
})

test_that("a NUL inside a BOM prefix empties the first line", {
  body <- pv_bytes(as.raw(0xef), pv_nul, "User-agent: *\nDisallow: /x\n")
  expect_identical(
    pv_decoded(body), pv_bytes(as.raw(0xef), "\nDisallow: /x\n")
  )
  pv_expect(pv_google(body, "/x"), TRUE, NA, NA_character_)
})

test_that("UTF-16LE text without a BOM reads as lines with no rule", {
  text <- charToRaw("User-agent: *\nDisallow: /a\n")
  body <- as.vector(rbind(text, pv_nul))
  # Each line keeps its first letter or nothing: "U", then lines that start
  # with the NUL after an LF.
  expect_identical(pv_decoded(body), pv_bytes("U\n\n"))
  pv_expect(pv_google(body, "/a"), TRUE, NA, NA_character_)
})

test_that("an empty body and a body of NULs decode to nothing", {
  expect_identical(pv_decoded(raw()), raw())
  expect_identical(pv_decoded(rep(pv_nul, 3L)), raw())
  pv_expect(pv_google(raw(), "/x"), TRUE, NA, NA_character_)
  pv_expect(pv_google(rep(pv_nul, 3L), "/x"), TRUE, NA, NA_character_)
})

test_that("several NULs on one line end it at the first", {
  body <- pv_bytes("User-agent: *\nDisallow: /a", pv_nul, "b", pv_nul, "c\n")
  expect_identical(
    pv_decoded(body), pv_bytes("User-agent: *\nDisallow: /a\n")
  )
  pv_expect(pv_google(body, c("/a", "/abc")),
            c(FALSE, FALSE), c(2L, 2L), c("/a", "/a"))
})

test_that("a NUL on an unterminated last line leaves it unterminated", {
  body <- pv_bytes("User-agent: *\nDisallow: /a", pv_nul, "b")
  expect_identical(pv_decoded(body), pv_bytes("User-agent: *\nDisallow: /a"))
  pv_expect(pv_google(body, c("/a", "/ab")),
            c(FALSE, FALSE), c(2L, 2L), c("/a", "/a"))
})

test_that("CR, LF and CRLF lines keep their numbers around a NUL", {
  body <- pv_bytes(
    "User-agent: *\r\nAllow: /q\rDisallow: /a", pv_nul, "b\n",
    "Disallow: /c\r\n"
  )
  expect_identical(
    pv_decoded(body),
    pv_bytes("User-agent: *\nAllow: /q\nDisallow: /a\nDisallow: /c\n")
  )
  pv_expect(pv_google(body, c("/a", "/ab", "/c", "/q")),
            c(FALSE, FALSE, FALSE, TRUE), c(3L, 3L, 4L, 2L),
            c("/a", "/a", "/c", "/q"))
})

test_that("a body with no NUL reaches the matcher byte for byte", {
  body <- pv_bytes("User-agent: *\r\nDisallow: /a\r\r\n", as.raw(0xff), "\r")
  expect_identical(pv_decoded(body), body)
})

test_that("bytes before a NUL reach the matcher as written, none after it", {
  body <- pv_bytes(
    "User-agent: *\nDisallow: /", as.raw(0xff), pv_nul, as.raw(0xfe), "\n"
  )
  expect_identical(
    pv_decoded(body),
    pv_bytes("User-agent: *\nDisallow: /", as.raw(0xff), "\n")
  )
})

test_that("a NUL past the parser's line buffer changes no rule", {
  # The parser keeps 16,662 bytes of a line; a NUL past them was never read.
  long <- strrep("a", 17000L)
  body <- pv_bytes("User-agent: *\nDisallow: /", long, pv_nul, "zz\n")
  expect_identical(
    pv_decoded(body), pv_bytes("User-agent: *\nDisallow: /", long, "\n")
  )
  got <- pv_google(body, "/aaa")
  expect_true(got$allowed)
  expect_identical(got$v1, "allow")
})

test_that("Bing and Yandex read the NUL as an ordinary byte", {
  # Their bindings take the raw body: the rule is "/a\0b", which /a misses,
  # while Google's matcher reads the rule "/a".
  body <- pv_bytes("User-agent: *\nDisallow: /a", pv_nul, "b\n")
  url <- "https://example.com/a"
  expect_identical(match_bing_v1(list(body), url, "bingbot")$url_decision,
                   "allow")
  expect_identical(match_yandex_v1(list(body), url, "Yandex")$url_decision,
                   "allow")
  expect_identical(match_google_v1(body, url, "FooBot")$url_decision,
                   "disallow")
})

test_that("the body preview still removes NUL bytes", {
  body <- pv_bytes("User-agent: *\nDisallow: /a", pv_nul, "b\n")
  local_fake_ssrfr(function(req) fake_response(200L, body = body))
  x <- allowed_by_robots_url("https://example.com/a", "FooBot")
  expect_identical(robots_body(x, n = Inf), "User-agent: *\nDisallow: /ab\n")
  expect_identical(robots_body(x, raw = TRUE), body)
})
