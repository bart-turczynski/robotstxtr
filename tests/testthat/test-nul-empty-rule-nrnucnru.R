# ROBO-nrnucnru: a NUL right after an Allow or Disallow colon leaves the
# validation parser an empty value, which empty_rule_value reports as ignored.
# Since ROBO-pvqrfvol Google's matcher, like the parser, ends the line at its
# first NUL (R/body-decode.R), so the path after it is never read. The row
# says, on that line, that the first NUL ends it, the value is empty, the
# directive imposes no restriction and the text after the NUL is ignored. It
# quotes no value, names no decision and keeps its raw_text. A plain empty
# rule keeps today's message.

nr_nul <- as.raw(0)

# Google's matcher decision on `bytes` for FooBot on example.com, each line
# cut at its first NUL as the fetch path decodes it.
nr_allowed <- function(bytes, path) {
  url <- paste0("https://example.com", path)
  Encoding(url) <- "UTF-8"
  robotstxtr_allowed_text_(decode_matcher_body(bytes), url, "FooBot")
}

# `code@line` for each row of `x`, in emission order.
nr_codes <- function(x) {
  d <- x$diagnostics
  paste0(d$code, "@", d$line)
}

# The one empty_rule_value row of `x`, checked for its line and severity.
nr_empty_row <- function(x, line) {
  d <- x$diagnostics
  found <- d[d$code == "empty_rule_value", , drop = FALSE]
  expect_identical(nrow(found), 1L)
  expect_identical(found$line, line)
  expect_identical(found$severity, "warning")
  found
}

nr_hidden_message <- paste0(
  "The first NUL ends this line, so the value is empty and the directive ",
  "imposes no restriction; the text after the NUL is ignored."
)

nr_plain_message <- "Empty Allow or Disallow value is ignored by the matcher."

test_that("a NUL after the colon says the line ends there, no decision", {
  bytes <- c(charToRaw("User-agent: *\nDisallow: "), nr_nul,
             charToRaw("/private\n"))
  expect_true(nr_allowed(bytes, "/private"))
  x <- robots_validate_text(bytes)
  expect_identical(nr_codes(x), c("nul_byte@2", "empty_rule_value@2"))
  row <- nr_empty_row(x, 2L)
  expect_identical(row$directive, "disallow")
  expect_identical(row$raw_text, "Disallow: \\x00/private")
  expect_identical(row$message, nr_hidden_message)
  expect_no_match(row$message, "/private", fixed = TRUE)
  expect_no_match(row$message, "Bing|Yandex|matchers")
  # It announces no overall decision.
  expect_no_match(row$message, "allow|block|crawl", ignore.case = TRUE)
  expect_false("rules_after_nul_removal" %in% x$diagnostics$code)
})

test_that("the NUL may sit directly after the colon, and Allow counts too", {
  cases <- list(
    "Disallow, no space" = c(charToRaw("User-agent: *\nDisallow:"), nr_nul,
                             charToRaw("/private\n")),
    "Allow, one space" = c(charToRaw("User-agent: *\nAllow: "), nr_nul,
                           charToRaw("/private\n"))
  )
  for (case in names(cases)) {
    x <- robots_validate_text(cases[[case]])
    expect_identical(nr_codes(x), c("nul_byte@2", "empty_rule_value@2"),
                     label = case)
    expect_identical(nr_empty_row(x, 2L)$message, nr_hidden_message,
                     label = case)
    expect_false("rules_after_nul_removal" %in% x$diagnostics$code,
                 label = case)
  }
})

test_that("a NUL that hides no path keeps today's message", {
  # Nothing after the NUL, or only blanks or a comment: the NUL-free value is
  # empty too, so the rule stays an empty one.
  cases <- list(
    "NUL alone" = c(charToRaw("User-agent: *\nDisallow:"), nr_nul,
                    charToRaw("\n")),
    "NUL then blank" = c(charToRaw("User-agent: *\nDisallow: "), nr_nul,
                         charToRaw(" \n")),
    "NUL then comment" = c(charToRaw("User-agent: *\nDisallow: "), nr_nul,
                           charToRaw("# c\n"))
  )
  for (case in names(cases)) {
    x <- robots_validate_text(cases[[case]])
    expect_identical(nr_codes(x), c("nul_byte@2", "empty_rule_value@2"),
                     label = case)
    expect_identical(nr_empty_row(x, 2L)$message, nr_plain_message,
                     label = case)
  }
})

test_that("a plain empty Disallow keeps today's message", {
  x <- robots_validate_text(charToRaw("User-agent: *\nDisallow:\n"))
  expect_identical(nr_codes(x), "empty_rule_value@2")
  expect_identical(nr_empty_row(x, 2L)$message, nr_plain_message)
})

test_that("a NUL in the middle of a path is not hidden", {
  # The value is cut, not emptied: rule_cut_by_nul (ROBO-xuusttbp).
  bytes <- c(charToRaw("User-agent: *\nDisallow: /a"), nr_nul,
             charToRaw("b\n"))
  x <- robots_validate_text(bytes)
  expect_identical(nr_codes(x), c("nul_byte@2", "rule_cut_by_nul@2"))
  expect_false(any(x$diagnostics$code == "empty_rule_value"))
})

test_that("a NUL inside the key is no empty rule, so no reworded row", {
  # The parser reads `Disallow` then the NUL as a malformed line, not as an
  # empty rule: there is no empty_rule_value row to reword, and the hidden
  # path is counted by rules_after_nul_removal as before.
  bytes <- c(charToRaw("User-agent: *\nDisallow"), nr_nul,
             charToRaw(": /x\n"))
  expect_true(nr_allowed(bytes, "/x"))
  x <- robots_validate_text(bytes)
  expect_identical(
    nr_codes(x),
    c("nul_byte@2", "malformed_line@2", "rules_after_nul_removal@NA")
  )
  expect_false("empty_rule_value" %in% x$diagnostics$code)
})

test_that("a hidden rule with no group keeps its row order", {
  bytes <- c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("Disallow: "), nr_nul,
             charToRaw("/private\n"))
  x <- robots_validate_text(bytes)
  expect_identical(
    nr_codes(x),
    c("byte_order_mark@1", "nul_byte@1", "rule_without_user_agent@1",
      "empty_rule_value@1", "missing_user_agent@NA")
  )
  expect_identical(nr_empty_row(x, 1L)$message, nr_hidden_message)
})

test_that("CRLF and lone-CR endings name the same line", {
  crlf <- c(charToRaw("User-agent: *\r\nDisallow: "), nr_nul,
            charToRaw("/private\r\n"))
  lone <- c(charToRaw("User-agent: *\rDisallow: "), nr_nul,
            charToRaw("/private\r"))
  for (case in list(crlf = crlf, lone = lone)) {
    x <- robots_validate_text(case)
    expect_identical(nr_codes(x), c("nul_byte@2", "empty_rule_value@2"))
    expect_identical(nr_empty_row(x, 2L)$message, nr_hidden_message)
  }
})

test_that("a hidden path past the line buffer keeps the reworded row", {
  bytes <- c(charToRaw("User-agent: *\nDisallow: "), nr_nul,
             charToRaw("/private"), charToRaw(strrep("x", 20000L)),
             charToRaw("\n"))
  x <- robots_validate_text(bytes)
  expect_identical(nr_codes(x),
                   c("nul_byte@2", "line_too_long@2", "empty_rule_value@2"))
  row <- nr_empty_row(x, 2L)
  expect_identical(row$message, nr_hidden_message)
  expect_true(startsWith(row$raw_text, "Disallow: \\x00/private"))
})

test_that("invalid UTF-8 after the NUL keeps invalid_utf8, ASCII message", {
  bytes <- c(charToRaw("User-agent: *\nDisallow: "), nr_nul,
             charToRaw("/"), as.raw(0xff), charToRaw("\n"))
  x <- robots_validate_text(bytes)
  expect_identical(
    nr_codes(x),
    c("nul_byte@2", "invalid_utf8@2", "empty_rule_value@2")
  )
  message <- nr_empty_row(x, 2L)$message
  expect_identical(message, nr_hidden_message)
  expect_true(all(as.integer(charToRaw(message)) < 128L))
})
