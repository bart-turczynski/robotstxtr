# ROBO-kormmfyg: a lower-case percent-escape in an Allow or Disallow value.
# Google's parser upper-cases the escapes in a rule value but never the URL
# path, so `Disallow: /a%3cb` does not block the path `/a%3cb` the owner wrote.

lc_validate <- function(line) {
  robots_validate_text(paste0("user-agent: *\n", line, "\nallow: /\n"))
}

lc_found <- function(x) {
  x$diagnostics[x$diagnostics$code == "rule_lowercase_escape", ,
                drop = FALSE]
}

# Values the parser keeps with a lower-case escape: either hex digit counts,
# a '%' before another '%' is not an escape of its own, and a raw non-ASCII
# byte before the escape is no bar.
lc_flagged <- c(
  "/a%3cb", "/a%c3", "/a%aB", "/a%Ab", "/%%3c", "/café%3c", "/a%3cb%3C"
)

test_that("a lower-case escape in a rule is one rule_lowercase_escape", {
  for (value in lc_flagged) {
    for (directive in c("disallow", "allow")) {
      line <- paste0(directive, ": ", value)
      x <- lc_validate(line)
      found <- lc_found(x)
      expect_identical(nrow(found), 1L, label = line)
      expect_identical(found$severity, "warning", label = line)
      expect_identical(found$line, 2L, label = line)
      expect_identical(found$directive, directive, label = line)
      expect_identical(x$documents$validation_status, "warning", label = line)
    }
  }
})

test_that("the rule_lowercase_escape message names the escape and its form", {
  x <- lc_validate("Disallow: /a%3cb")
  expect_identical(
    lc_found(x)$message,
    paste0(
      "Google upper-cases the escape '%3c' in a pattern but not in the URL, ",
      "so a URL written with '%3c' does not match this rule; write it as ",
      "'%3C'."
    )
  )
  # One escape, however often it repeats, is named once.
  expect_match(
    lc_found(lc_validate("Disallow: /a%3c%3cb"))$message,
    "^Google upper-cases the escape '%3c' in a pattern"
  )
})

test_that("several lower-case escapes on one line are one finding", {
  x <- lc_validate("Disallow: /a%3cb%aa%3C")
  found <- lc_found(x)
  expect_identical(nrow(found), 1L)
  expect_identical(
    found$message,
    paste0(
      "These escapes are lower-case: '%3c' for '%3C', '%aa' for '%AA'. ",
      "Google upper-cases each escape in a pattern but not in the URL, so a ",
      "URL written with a lower-case escape does not match this rule; write ",
      "them in upper case."
    )
  )
  # Twelve distinct escapes: the first ten are named, the other two counted.
  escapes <- sprintf("%%a%x", 0:11)
  value <- paste(escapes, collapse = "")
  found <- lc_found(lc_validate(sprintf("Disallow: /%s", value)))
  expect_identical(nrow(found), 1L)
  expect_match(found$message, "'%a9' for '%A9', and 2 more", fixed = TRUE)
  expect_false(grepl("%aa", found$message, fixed = TRUE))
})

test_that("a missing colon or a typo key still carries the finding", {
  for (line in c("Disallow /a%3cb", "Dissallow: /a%3cb", "Allow /a%3cb")) {
    x <- lc_validate(line)
    found <- lc_found(x)
    expect_identical(nrow(found), 1L, label = line)
    expect_identical(found$line, 2L, label = line)
  }
  expect_identical(
    lc_found(lc_validate("Dissallow: /a%3cb"))$directive, "disallow"
  )
})

test_that("the rule's line-ending, BOM and encoding forms each carry it", {
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  bodies <- list(
    crlf = charToRaw("User-agent: *\r\nDisallow: /a%3cb\r\n"),
    bom_start = c(bom, charToRaw("User-agent: *\nDisallow: /a%3cb\n")),
    invalid_utf8 = c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0xff),
                     charToRaw("%3cb\n")),
    nul_after = c(charToRaw("User-agent: *\nDisallow: /a%3cb"), as.raw(0x00),
                  charToRaw("\n"))
  )
  for (name in names(bodies)) {
    found <- lc_found(robots_validate_text(bodies[[name]]))
    expect_identical(nrow(found), 1L, label = name)
    expect_identical(found$line, 2L, label = name)
  }
})

test_that("an escape inside the parser's 16,663-byte line buffer is flagged", {
  # The escape ends at byte 16,663, the last one the parser keeps; the 'b'
  # after it is cut, so the line is also line_too_long.
  body <- paste0("User-agent: *\nDisallow: /", strrep("a", 16649L), "%3cb\n")
  x <- robots_validate_text(body)
  found <- lc_found(x)
  expect_identical(nrow(found), 1L)
  expect_identical(found$line, 2L)
  expect_true("line_too_long" %in% x$diagnostics$code)
})

test_that("an escape outside a rule's value draws no finding", {
  for (line in c(
    "Disallow: /a%3Cb", "Disallow: /a%Zb", "Disallow: /a%3", "Disallow: /a%",
    "Disallow: /a #%3c", "Disallow%3c: /x", "Disallow:"
  )) {
    expect_identical(nrow(lc_found(lc_validate(line))), 0L, label = line)
  }
  # The parser does not escape a User-agent or Sitemap value.
  x <- robots_validate_text(
    "User-agent: %3c\nSitemap: https://example.com/%3c.xml\n"
  )
  expect_identical(nrow(lc_found(x)), 0L)
})

test_that("a NUL or a buffer cut before the escape is no finding", {
  # The parser stops a value at the NUL, so the escape after it is not kept.
  nul_before <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0x00),
                  charToRaw("%3cb\n"))
  expect_identical(nrow(lc_found(robots_validate_text(nul_before))), 0L)
  # The escape starts at byte 16,664, past the 16,663 bytes the parser keeps.
  past_cut <- paste0("User-agent: *\nDisallow: /", strrep("a", 16652L),
                     "%3cb\n")
  expect_identical(nrow(lc_found(robots_validate_text(past_cut))), 0L)
})

test_that("a key escape with a missing colon is no finding", {
  # The parser strips the blanks before the key, so the key is `Disallow%3c`
  # and the value is `/x`: the escape is in the key only. On line 1 a
  # byte-order mark is skipped before the blanks.
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  body <- c(bom, charToRaw("  Disallow%3c /x\n"))
  expect_identical(nrow(lc_found(robots_validate_text(body))), 0L)
  body <- charToRaw("User-agent: *\n  Disallow%3c /x\n")
  expect_identical(nrow(lc_found(robots_validate_text(body))), 0L)
})

test_that("a rule with an escape and a rule_escaped_unreserved both report", {
  # Both are value warnings on the line, in the order the value checks run.
  x <- lc_validate("Disallow: /%7ejoe%3c")
  expect_identical(
    x$diagnostics$code[x$diagnostics$line == 2L],
    c("rule_escaped_unreserved", "rule_lowercase_escape")
  )
})
