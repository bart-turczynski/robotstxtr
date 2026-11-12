# ROBO-xuusttbp: the validator reads a NUL-bearing line as the google backend
# does since ROBO-pvqrfvol, ending it at its first NUL, and names that engine:
# the Bing and Yandex matchers read the NUL as an ordinary byte.
# 1. The group checks run on a body with a NUL, on Google's lines.
# 2. A NUL that cuts a rule value is `rule_cut_by_nul`, as `#` is
#    `rule_cut_by_comment`.
# 3. The UTF-8 check reads the line as written, NULs included.
# Only bytes can carry a NUL (an R string cannot), so each body is raw.

xn_nul <- as.raw(0)

xn_bytes <- function(...) {
  unlist(lapply(list(...), function(part) {
    if (is.character(part)) charToRaw(part) else as.raw(part)
  }), use.names = FALSE)
}

xn_codes <- function(bytes) {
  d <- robots_validate_text(bytes)$diagnostics
  paste0(d$code, "@", d$line)
}

xn_message <- function(bytes, code) {
  d <- robots_validate_text(bytes)$diagnostics
  d$message[d$code == code]
}

test_that("a NUL-shortened Disallow tied by an Allow is reported", {
  body <- xn_bytes("User-agent: *\nDisallow: /a", xn_nul, "b\nAllow: /a\n")
  expect_identical(
    xn_codes(body),
    c("nul_byte@2", "rule_cut_by_nul@2", "disallow_tied_by_allow@2")
  )
  tie <- xn_message(body, "disallow_tied_by_allow")
  expect_match(tie, "Allow on line 3", fixed = TRUE)
  expect_match(tie, paste0("This is Google's reading, which ends each line ",
                           "at its first NUL; Bing and Yandex read the NUL ",
                           "as an ordinary byte."), fixed = TRUE)
  # Google's matcher agrees: the tie goes to the Allow.
  expect_identical(
    match_google_v1(body, "https://example.com/a", "FooBot")$url_decision,
    "allow"
  )
})

test_that("a NUL that cuts a rule value widens it, on Google's reading", {
  body <- xn_bytes("User-agent: *\nDisallow: /private", xn_nul, "-drafts/\n")
  expect_identical(xn_codes(body), c("nul_byte@2", "rule_cut_by_nul@2"))
  cut <- robots_validate_text(body)$diagnostics[2L, ]
  expect_identical(cut$severity, "warning")
  expect_identical(cut$directive, "disallow")
  expect_identical(cut$raw_text, "Disallow: /private\\x00-drafts/")
  expect_match(cut$message, "Google's matcher ends this line at its first NUL",
               fixed = TRUE)
  expect_match(cut$message, "Bing and Yandex read the NUL", fixed = TRUE)
  # The matchers split as the message says.
  url <- "https://example.com/private-notes"
  expect_identical(match_google_v1(body, url, "FooBot")$url_decision,
                   "disallow")
  expect_identical(match_bing_v1(list(body), url, "bingbot")$url_decision,
                   "allow")
  # An Allow is cut the same way.
  allow <- xn_bytes("User-agent: *\nDisallow: /\nAllow: /pub", xn_nul, "x\n")
  expect_identical(xn_codes(allow), c("nul_byte@3", "rule_cut_by_nul@3"))
})

test_that("a NUL that leaves the value whole is no rule_cut_by_nul", {
  # In a comment the parser already cut away.
  expect_identical(
    xn_codes(xn_bytes("User-agent: *\nDisallow: /a #x", xn_nul, "y\n")),
    "nul_byte@2"
  )
  # At the end of the value.
  expect_identical(
    xn_codes(xn_bytes("User-agent: *\nDisallow: /a", xn_nul, "\n")),
    "nul_byte@2"
  )
  # Right after the colon: the value is empty, which empty_rule_value says.
  expect_identical(
    xn_codes(xn_bytes("User-agent: *\nDisallow:", xn_nul, "/a\n")),
    c("nul_byte@2", "empty_rule_value@2")
  )
  # Past the parser's line buffer, which never reads it.
  long <- strrep("a", 17000L)
  expect_false("rule_cut_by_nul" %in% robots_validate_text(
    xn_bytes("User-agent: *\nDisallow: /", long, xn_nul, "zz\n")
  )$diagnostics$code)
  # A NUL in a User-agent line cuts no rule.
  expect_false("rule_cut_by_nul" %in% robots_validate_text(
    xn_bytes("User-agent: Foo", xn_nul, "Bot\nDisallow: /x\n")
  )$diagnostics$code)
})

test_that("a NUL before a glued # cuts at the NUL, not the #", {
  body <- xn_bytes("User-agent: *\nDisallow: /a", xn_nul, "b#c\n")
  expect_identical(xn_codes(body), c("nul_byte@2", "rule_cut_by_nul@2"))
})

test_that("a NUL splitting a UTF-8 sequence is invalid UTF-8", {
  body <- xn_bytes("User-agent: *\nDisallow: /", 0xc3, xn_nul, 0xa9, "\n")
  x <- robots_validate_text(body)
  expect_identical(
    paste0(x$diagnostics$code, "@", x$diagnostics$line),
    c("nul_byte@2", "invalid_utf8@2", "rule_cut_by_nul@2")
  )
  expect_identical(x$documents$encoding, "invalid-utf-8")
})

test_that("invalid UTF-8 after a NUL and a # stays a comment warning", {
  body <- xn_bytes("User-agent: *\nDisallow: /a", xn_nul, "# ", 0xff, "\n")
  x <- robots_validate_text(body)$diagnostics
  expect_identical(x$code, c("nul_byte", "invalid_utf8_comment"))
  expect_identical(x$severity, c("error", "warning"))
  expect_identical(x$message[[2L]], paste0(
    "Only bytes after the line's first NUL are not well-formed UTF-8, in a ",
    "comment as Bing and Yandex read the line; Google's matcher ends the ",
    "line at the NUL and never reads them; no rule changes."
  ))
  # Bing and Yandex cut a rule at `#`, which is why the code stays.
  glued <- charToRaw("User-agent: *\nDisallow: /a#b\n")
  url <- "https://example.com/a"
  expect_identical(match_bing_v1(list(glued), url, "bingbot")$url_decision,
                   "disallow")
  expect_identical(match_yandex_v1(list(glued), url, "Yandex")$url_decision,
                   "disallow")
})

test_that("well-formed runs around NULs keep the encoding valid", {
  body <- xn_bytes("User-agent: *\nDisallow: /caf", 0xc3, 0xa9, xn_nul,
                   0xc3, 0xa9, "\n")
  x <- robots_validate_text(body)
  expect_identical(x$documents$encoding, "utf-8")
  expect_false(any(startsWith(x$diagnostics$code, "invalid_utf8")))
})

test_that("a body with no NUL names no engine in its group findings", {
  d <- robots_validate_text(
    "User-agent: *\nDisallow: /a\nAllow: /a\nAllow: /a\n"
  )$diagnostics
  expect_identical(d$code, c("disallow_tied_by_allow", "duplicate_rule"))
  expect_false(any(grepl("Google's reading", d$message, fixed = TRUE)))
})
