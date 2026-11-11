# ROBO-xglcoagv: Google's parser reads any key that starts with `disallow`
# or `allow` (ASCII case-insensitive) as that directive (`KeyIsDisallow`,
# `KeyIsAllow`, src/robots.cc), so `DisallowAITraining: /` blocks the group
# for Google. The validator warns with `accepted_directive_prefix`, naming
# the key as written. The key is derived from the line's bytes the way
# GetKeyAndValueFrom cuts it (BOM on line 1, whitespace, separator); the
# parser's NUL and `#` cuts never fall before its separator, so the tests
# below only confirm they change nothing.

pk_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

pk_codes <- function(body) robots_validate_text(body)$diagnostics$code

pk_rows <- function(body) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == "accepted_directive_prefix", , drop = FALSE]
}

pk_disallow_message <- function(key) {
  paste0(
    "Google reads key `", key, "` as Disallow (prefix match), so for Google ",
    "this line is a Disallow rule; Bing and Yandex ignore it, and RFC 9309 ",
    "defines no such record. For an AI-training opt-out, use a separate ",
    "`User-agent: __usage_ai-training` group, not stacked under another ",
    "User-agent line."
  )
}

test_that("a DisallowAITraining key warns and names the training token", {
  body <- pk_lines("User-agent: *", "DisallowAITraining: /")
  x <- robots_validate_text(body)
  expect_identical(x$documents$validation_status, "warning")
  d <- x$diagnostics
  expect_identical(d$code, "accepted_directive_prefix")
  expect_identical(d$severity, "warning")
  expect_identical(d$line, 2L)
  expect_identical(d$directive, "disallow")
  expect_identical(d$raw_text, "DisallowAITraining: /")
  expect_identical(d$message, pk_disallow_message("DisallowAITraining"))
  # Google does read the line as Disallow: /.
  r <- allowed_by_robots_text(body, "https://example.com/a",
                              "Googlebot")$results
  expect_false(r$allowed)
  expect_identical(r$decision_source, "rule_disallow")
  expect_identical(r$matched_line, 2L)
})

test_that("the message names no group for a key before any User-agent", {
  d <- pk_rows(pk_lines("DisallowAITraining: /", "User-agent: *"))
  expect_identical(d$line, 1L)
  expect_identical(d$message, pk_disallow_message("DisallowAITraining"))
  expect_no_match(d$message, "group's")
})

test_that("a training token stacked under User-agent: * still blocks Google", {
  # Why the advice says a separate group: stacked, the Disallow is the `*`
  # group's too.
  body <- pk_lines("User-agent: *", "User-agent: __usage_ai-training",
                   "Disallow: /")
  r <- allowed_by_robots_text(body, "https://example.com/a",
                              "Googlebot")$results
  expect_false(r$allowed)
  expect_identical(r$matched_line, 3L)
})

test_that("an Allow-prefixed key warns without the training sentence", {
  d <- pk_rows(pk_lines("User-agent: *", "Disallow: /", "AllowAITraining: /x"))
  expect_identical(d$line, 3L)
  expect_identical(d$directive, "allow")
  expect_identical(d$message, paste0(
    "Google reads key `AllowAITraining` as Allow (prefix match), so for ",
    "Google this line is an Allow rule; Bing and Yandex ignore it, and ",
    "RFC 9309 defines no such record."
  ))
})

test_that("exact allow and disallow keys never warn", {
  for (rule in c("Disallow: /", "allow: /", "DISALLOW: /", "Disallow : /",
                 "Disallow\t:/", "  Allow:/x", "Disallow: /a # note",
                 "Disallow: /a:b", "Disallow /", "Allow\t/x")) {
    codes <- pk_codes(pk_lines("User-agent: *", rule))
    expect_false("accepted_directive_prefix" %in% codes, label = rule)
  }
})

test_that("a prefix key without a colon warns after accepted_missing_colon", {
  expect_identical(
    pk_codes(pk_lines("User-agent: *", "DisallowX /")),
    c("accepted_missing_colon", "accepted_directive_prefix")
  )
  expect_identical(pk_rows(pk_lines("User-agent: *", "DisallowX /"))$message,
                   pk_disallow_message("DisallowX"))
})

test_that("the key ends at the separator, trailing whitespace trimmed", {
  d <- pk_rows(pk_lines("User-agent: *", "  Disallow-x \t: /a#b: c"))
  expect_identical(d$message, pk_disallow_message("Disallow-x"))
  # A colon inside a comment is no separator: the key runs to the space.
  d <- pk_rows(pk_lines("User-agent: *", "Disallowed /a # x: y"))
  expect_identical(d$message, pk_disallow_message("Disallowed"))
})

test_that("an accepted typo is reported as a typo only", {
  for (rule in c("Dissallow: /", "Dissallowfoo: /", "disalowAI: /")) {
    expect_identical(
      pk_codes(pk_lines("User-agent: *", rule)),
      "accepted_directive_typo",
      label = rule
    )
  }
})

test_that("a leading BOM is not part of the first key", {
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  x <- robots_validate_text(c(bom, charToRaw("Disallow: /\n")))
  expect_identical(x$diagnostics$code,
                   c("byte_order_mark", "rule_without_user_agent",
                     "missing_user_agent"))
  # The parser also skips a partial BOM prefix at the body's start.
  x <- robots_validate_text(c(bom[1:2], charToRaw("Allow: /\n")))
  expect_false("accepted_directive_prefix" %in% x$diagnostics$code)
  # A BOM on a later line stays in the key, which is then unknown; the BOM
  # itself is reported too (misplaced_byte_order_mark, ROBO-atkmqcov).
  body <- c(charToRaw("User-agent: *\n"), bom, charToRaw("Disallow: /\n"))
  expect_identical(robots_validate_text(body)$diagnostics$code,
                   c("misplaced_byte_order_mark", "unknown_directive",
                     "no_rules"))
  # A BOM on line 1 before a prefix key still lets the key warn.
  d <- pk_rows(c(bom, charToRaw("Disallowx: /\nUser-agent: *\n")))
  expect_identical(d$line, 1L)
  expect_identical(d$message, pk_disallow_message("Disallowx"))
})

test_that("invalid UTF-8 in the key is escaped in a valid UTF-8 message", {
  body <- c(charToRaw("User-agent: *\nDisallow"), as.raw(0xff),
            charToRaw(": /\n"))
  x <- robots_validate_text(body)
  expect_identical(x$diagnostics$code,
                   c("invalid_utf8", "accepted_directive_prefix"))
  d <- pk_rows(body)
  expect_identical(d$message, pk_disallow_message("Disallow\\xFF"))
  expect_true(validUTF8(d$message))
})

test_that("a latin1 key is converted once and its bytes escaped", {
  rule <- "Disallow\u00e9: /"
  body <- iconv(paste0("User-agent: *\n", rule, "\n"), "UTF-8", "latin1")
  expect_identical(Encoding(body), "latin1")
  d <- pk_rows(body)
  expect_identical(d$message, pk_disallow_message("Disallow\\xC3\\xA9"))
  expect_true(validUTF8(d$message))
})

test_that("a NUL on the line leaves the key and the warning unchanged", {
  body <- c(charToRaw("User-agent: *\nDisallow-x: /a"), as.raw(0),
            charToRaw("b\n"))
  expect_identical(robots_validate_text(body)$diagnostics$code,
                   c("nul_byte", "accepted_directive_prefix"))
  body <- c(charToRaw("User-agent: *\nDisallow-x"), as.raw(0),
            charToRaw(": /\n"))
  # The line ends at its first NUL, for Google's matcher too, so the rule it
  # spells out NUL-free is hidden (ROBO-igrkabdb, ROBO-pvqrfvol).
  expect_identical(robots_validate_text(body)$diagnostics$code,
                   c("nul_byte", "malformed_line", "rules_after_nul_removal"))
  # An exact key whose line holds a NUL after the colon does not warn.
  body <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0),
            charToRaw("x: y\n"))
  expect_identical(robots_validate_text(body)$diagnostics$code, "nul_byte")
})

test_that("an oversized prefix line warns as well as line_too_long", {
  rule <- paste0("DisallowX: ", strrep("a", 17000L))
  codes <- pk_codes(pk_lines("User-agent: *", rule))
  expect_true(all(c("line_too_long", "accepted_directive_prefix") %in% codes))
})

test_that("an empty body draws no prefix warning", {
  expect_false("accepted_directive_prefix" %in% pk_codes(""))
})

for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("the key fold is ASCII-only under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    expect_identical(
      pk_codes(pk_lines("USER-AGENT: *", "DISALLOWAITRAINING: /")),
      "accepted_directive_prefix"
    )
    expect_identical(
      pk_codes(pk_lines("USER-AGENT: *", "DISALLOW: /", "ALLOW: /I")),
      character()
    )
  })
}

test_that("robots_validate_url reports the prefix key too", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, body = "User-agent: *\nDisallowAITraining: /\n")
  })
  x <- robots_validate_url("http://a/")
  expect_identical(x$diagnostics$code, "accepted_directive_prefix")
  expect_identical(x$diagnostics$message,
                   pk_disallow_message("DisallowAITraining"))
})
