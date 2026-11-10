# ROBO-kbrzbccu: precedence ties between an Allow and a Disallow that only
# tie after Google's rule normalization, through wildcards, or across two
# groups for one agent. Each test pins the four rows of
# test-engine-disagreements-glssaxva.R: the google backend with the Yandex
# and the bingbot token, the yandex backend (Yandex) and the bing backend
# (bingbot), all under the google ruleset, where a supplied body is
# `use_rules`, so any difference is the backend's. Every shape runs in both
# source orders, so a winner picked by line order rather than by "Allow wins
# a tie" turns a row red, and the matched line moves with the order.
#
# The Google rows are the vendored matcher, which design/engine-profiles.md
# §5b checks against the pinned upstream; none of these shapes falls in a
# §5b difference class. Re-deriving them from the upstream binary is a
# maintainer step: design/engine-disagreements.md "Precedence ties".
# These pin current behavior; none is a known bug of ours.

pt_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

# One "decision reason line" string per row. `body` is a string, or a
# function of the product token that builds the body for that row's token.
pt_outcome <- function(body, path) {
  url <- paste0("https://example.com", path)
  run <- function(backend, token) {
    text <- if (is.function(body)) body(token) else body
    r <- robots_evaluate_text_v1(text, url, token, "google", backend)$results
    paste(r$url_decision, r$reason, r$matched_line)
  }
  c(
    google_yandex = run("google", "Yandex"),
    yandex = run("yandex", "Yandex"),
    google_bingbot = run("google", "bingbot"),
    bing = run("bing", "bingbot")
  )
}

pt_expect <- function(google_yandex, yandex, google_bingbot, bing) {
  c(
    google_yandex = google_yandex, yandex = yandex,
    google_bingbot = google_bingbot, bing = bing
  )
}

pt_all <- function(outcome) pt_expect(outcome, outcome, outcome, outcome)
pt_disallow <- function(line) paste("disallow rule_disallow", line)
pt_allow <- function(line) paste("allow rule_allow", line)
pt_default <- "allow default_allow NA"

pt_ua <- "User-agent: *"
pt_e_acute <- "/é"

test_that("scope 1: a raw e-acute Allow ties an escaped Disallow on google", {
  # Google escapes the rule's non-ASCII bytes (MaybeEscapePattern), so both
  # rules are /%C3%A9 and Allow wins. Yandex and bing compare raw bytes
  # (class 6): only the escaped Disallow matches the escaped path.
  allow_raw <- paste0("Allow: ", pt_e_acute)
  body <- pt_lines(pt_ua, allow_raw, "Disallow: /%C3%A9")
  expect_identical(
    pt_outcome(body, "/%C3%A9"),
    pt_expect(pt_allow(2), pt_disallow(3), pt_allow(2), pt_disallow(3))
  )
  body <- pt_lines(pt_ua, "Disallow: /%C3%A9", allow_raw)
  expect_identical(
    pt_outcome(body, "/%C3%A9"),
    pt_expect(pt_allow(3), pt_disallow(2), pt_allow(3), pt_disallow(2))
  )
  # A raw path: google never escapes the URL, so neither rule matches; on
  # yandex and bing only the raw Allow does.
  expect_identical(
    pt_outcome(body, pt_e_acute),
    pt_expect(pt_default, pt_allow(3), pt_default, pt_allow(3))
  )
  # Control: a Disallow one byte longer wins on every row.
  body <- pt_lines(pt_ua, allow_raw, "Disallow: /%C3%A9x")
  expect_identical(pt_outcome(body, "/%C3%A9x"), pt_all(pt_disallow(3)))
})

test_that("scope 1: escapes differing in case tie on google and bing", {
  # Google and bing upper-case a rule's escape, so /a%3cb and /a%3Cb are one
  # rule and Allow wins; yandex keeps the lower-case rule as written
  # (class 11), so it does not match /a%3Cb.
  body <- pt_lines(pt_ua, "Allow: /a%3cb", "Disallow: /a%3Cb")
  expect_identical(
    pt_outcome(body, "/a%3Cb"),
    pt_expect(pt_allow(2), pt_disallow(3), pt_allow(2), pt_allow(2))
  )
  body <- pt_lines(pt_ua, "Disallow: /a%3Cb", "Allow: /a%3cb")
  expect_identical(
    pt_outcome(body, "/a%3Cb"),
    pt_expect(pt_allow(3), pt_disallow(2), pt_allow(3), pt_allow(3))
  )
  # A lower-case path: google and bing compare it as given and match
  # neither rule; yandex matches its lower-case Allow.
  expect_identical(
    pt_outcome(body, "/a%3cb"),
    pt_expect(pt_default, pt_allow(3), pt_default, pt_default)
  )
  # The case on the other side: yandex then disallows the lower-case path.
  body <- pt_lines(pt_ua, "Allow: /a%3Cb", "Disallow: /a%3cb")
  expect_identical(pt_outcome(body, "/a%3Cb"), pt_all(pt_allow(2)))
  expect_identical(
    pt_outcome(body, "/a%3cb"),
    pt_expect(pt_default, pt_disallow(3), pt_default, pt_default)
  )
  body <- pt_lines(pt_ua, "Allow: /a%3cb", "Disallow: /a%3Cbx")
  expect_identical(pt_outcome(body, "/a%3Cbx"), pt_all(pt_disallow(3)))
})

test_that("scope 2: /a* ties /ab on google and bing, not on yandex", {
  # Google and bing count `*` (3 bytes each); yandex does not (2 against 3,
  # class 10), so its Disallow wins.
  body <- pt_lines(pt_ua, "Allow: /a*", "Disallow: /ab")
  expect_identical(
    pt_outcome(body, "/ab"),
    pt_expect(pt_allow(2), pt_disallow(3), pt_allow(2), pt_allow(2))
  )
  body <- pt_lines(pt_ua, "Disallow: /ab", "Allow: /a*")
  expect_identical(
    pt_outcome(body, "/ab"),
    pt_expect(pt_allow(3), pt_disallow(2), pt_allow(3), pt_allow(3))
  )
  # The wildcard on the Disallow side: a tie on google and bing, and the
  # longer Allow on yandex; every row allows.
  body <- pt_lines(pt_ua, "Disallow: /a*", "Allow: /ab")
  expect_identical(pt_outcome(body, "/ab"), pt_all(pt_allow(3)))
  body <- pt_lines(pt_ua, "Allow: /a*", "Disallow: /abc")
  expect_identical(pt_outcome(body, "/abc"), pt_all(pt_disallow(3)))
})

test_that("scope 2: a $ pattern with a * ties a literal on google and bing", {
  # A `$` pattern without `*` matches only a path one byte shorter than
  # itself, and a literal of the pattern's length cannot match that path,
  # so the literal-only form never ties: `Allow: /ab$` against
  # `Disallow: /abc` leaves the Disallow unmatched on `/ab`.
  body <- pt_lines(pt_ua, "Allow: /ab$", "Disallow: /abc")
  expect_identical(pt_outcome(body, "/ab"), pt_all(pt_allow(2)))
  # With a `*` in the `$` side, both rules are 4 bytes on google and bing;
  # yandex counts /*b$ as 2 and /xyb as 4 (class 10).
  body <- pt_lines(pt_ua, "Allow: /*b$", "Disallow: /xyb")
  expect_identical(
    pt_outcome(body, "/xyb"),
    pt_expect(pt_allow(2), pt_disallow(3), pt_allow(2), pt_allow(2))
  )
  body <- pt_lines(pt_ua, "Disallow: /xyb", "Allow: /*b$")
  expect_identical(
    pt_outcome(body, "/xyb"),
    pt_expect(pt_allow(3), pt_disallow(2), pt_allow(3), pt_allow(3))
  )
  body <- pt_lines(pt_ua, "Allow: /*b$", "Disallow: /xyb$")
  expect_identical(pt_outcome(body, "/xyb"), pt_all(pt_disallow(3)))
})

test_that("scope 2: a $ pattern ties a * pattern on every backend", {
  # The literal-only form cannot tie here either (see above). `/a$` and
  # `/a*` are 3 bytes on google and bing and 2 on yandex, so all four rows
  # tie and Allow wins.
  body <- pt_lines(pt_ua, "Allow: /a$", "Disallow: /a*")
  expect_identical(pt_outcome(body, "/a"), pt_all(pt_allow(2)))
  body <- pt_lines(pt_ua, "Disallow: /a*", "Allow: /a$")
  expect_identical(pt_outcome(body, "/a"), pt_all(pt_allow(3)))
  # A second `*` makes the Disallow longer on google and bing only: yandex
  # still counts 2 and keeps the tie.
  body <- pt_lines(pt_ua, "Allow: /a$", "Disallow: /a**")
  expect_identical(
    pt_outcome(body, "/a"),
    pt_expect(pt_disallow(3), pt_allow(2), pt_disallow(3), pt_disallow(3))
  )
})

# Scope 3: two groups for the row's own token (Yandex on the Yandex rows,
# bingbot on the bingbot rows), one with the Allow and one with the Disallow.
pt_groups <- function(first, second) {
  function(token) {
    ua <- paste("User-agent:", token)
    pt_lines(ua, first, "", ua, second)
  }
}

test_that("scope 3: a tie across two groups for one agent goes to Allow", {
  expect_identical(
    pt_outcome(pt_groups("Allow: /p", "Disallow: /p"), "/p"),
    pt_all(pt_allow(2))
  )
  expect_identical(
    pt_outcome(pt_groups("Disallow: /p", "Allow: /p"), "/p"),
    pt_all(pt_allow(5))
  )
  expect_identical(
    pt_outcome(pt_groups("Allow: /p", "Disallow: /px"), "/px"),
    pt_all(pt_disallow(5))
  )
})

test_that("scope 3: google merges two FooBot groups the same way", {
  run <- function(body) {
    url <- "https://example.com/p"
    r <- robots_evaluate_text_v1(body, url, "FooBot", "google", "google")
    paste(r$results$url_decision, r$results$reason, r$results$matched_line)
  }
  make <- pt_groups("Allow: /p", "Disallow: /p")
  expect_identical(run(make("FooBot")), pt_allow(2))
  make <- pt_groups("Disallow: /p", "Allow: /p")
  expect_identical(run(make("FooBot")), pt_allow(5))
})

test_that("scope 4: an inner $ counts as a byte; yandex ties, google doesn't", {
  # Only a final `$` anchors; an inner one is a literal byte everywhere.
  # Yandex counts /a$b as 4 and /a*bx as 4 (no `*`), a tie for Allow;
  # google and bing count 4 against 5, so the Disallow wins.
  body <- pt_lines(pt_ua, "Allow: /a$b", "Disallow: /a*bx")
  expect_identical(
    pt_outcome(body, "/a$bx"),
    pt_expect(pt_disallow(3), pt_allow(2), pt_disallow(3), pt_disallow(3))
  )
  body <- pt_lines(pt_ua, "Disallow: /a*bx", "Allow: /a$b")
  expect_identical(
    pt_outcome(body, "/a$bx"),
    pt_expect(pt_disallow(2), pt_allow(3), pt_disallow(2), pt_disallow(2))
  )
  # Both sides with an inner `$`: /a$b$ ends in an anchor that yandex does
  # not count (4), and /a$b* a `*` (4); google and bing count 5.
  body <- pt_lines(pt_ua, "Disallow: /a$b$", "Allow: /a$b")
  expect_identical(
    pt_outcome(body, "/a$b"),
    pt_expect(pt_disallow(2), pt_allow(3), pt_disallow(2), pt_disallow(2))
  )
  body <- pt_lines(pt_ua, "Allow: /a$b", "Disallow: /a$b*")
  expect_identical(
    pt_outcome(body, "/a$b"),
    pt_expect(pt_disallow(3), pt_allow(2), pt_disallow(3), pt_disallow(3))
  )
  body <- pt_lines(pt_ua, "Allow: /a$b", "Disallow: /a$bx")
  expect_identical(pt_outcome(body, "/a$bx"), pt_all(pt_disallow(3)))
})
