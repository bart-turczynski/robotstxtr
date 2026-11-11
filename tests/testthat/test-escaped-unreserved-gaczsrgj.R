# ROBO-gaczsrgj: a rule that percent-escapes an unreserved character.

eu_validate <- function(line) {
  robots_validate_text(paste0("user-agent: *\n", line, "\nallow: /\n"))
}

eu_found <- function(x) {
  x$diagnostics[x$diagnostics$code == "rule_escaped_unreserved", ,
                drop = FALSE]
}

# Letters, digits and the four marks of RFC 3986 section 2.3; lower-case hex
# guards the parser seam, which upper-cases it today.
eu_flagged <- c(
  "/%7Ejoe", "/%7ejoe", "/%41", "/%7A", "/%30", "/%2D", "/%2E", "/%5F",
  "/%7E%7E"
)

# Reserved or non-ASCII escapes, an escaped '%' before "7E", and text that is
# no escape at all.
eu_clean <- c(
  "/~joe", "/%2F", "/%25", "/%3C", "/%20", "/%E2%80%8B", "/%257E", "/%7",
  "/%zz", "/*.pdf$"
)

test_that("an escaped unreserved character is one rule_escaped_unreserved", {
  for (value in eu_flagged) {
    for (directive in c("disallow", "allow")) {
      line <- paste0(directive, ": ", value)
      x <- eu_validate(line)
      # Filtered to this code: a lower-case escape also draws
      # rule_lowercase_escape (ROBO-kormmfyg), pinned in its own file.
      found <- eu_found(x)
      expect_identical(found$code, "rule_escaped_unreserved", label = line)
      expect_identical(found$severity, "warning", label = line)
      expect_identical(found$line, 2L, label = line)
      expect_identical(found$directive, directive, label = line)
      expect_identical(x$documents$validation_status, "warning", label = line)
    }
  }
})

test_that("the check reads lower-case hex a raw value would carry", {
  # The parser upper-cases hex today, so only the helper sees '%7e'.
  found <- rule_escaped_unreserved_diagnostic("/%7ejoe")
  expect_identical(found$code, "rule_escaped_unreserved")
  expect_match(found$message, "^'%7e' escapes the unreserved character '~'")
  expect_null(rule_escaped_unreserved_diagnostic("/%2f%257e"))
})

test_that("the message names the escape, the character and the RFC", {
  x <- eu_validate("Disallow: /%7Ejoe")
  expect_identical(
    x$diagnostics$message,
    paste0(
      "'%7E' escapes the unreserved character '~'. Google matches it only ",
      "against '%7E' in the URL, never against '~', though RFC 9309 ",
      "section 2.2.2 decodes it."
    )
  )
  # A repeated escape is named once.
  expect_identical(
    eu_validate("Disallow: /%7E%7E")$diagnostics$message,
    x$diagnostics$message
  )
  y <- eu_validate("Disallow: /%7E/%41/%2F")
  expect_identical(nrow(eu_found(y)), 1L)
  expect_identical(
    y$diagnostics$message,
    paste0(
      "These escapes stand for unreserved characters: '%7E' for '~', '%41' ",
      "for 'A'. Google matches each only against the same escape in the URL, ",
      "never against the character, though RFC 9309 section 2.2.2 decodes ",
      "them."
    )
  )
})

test_that("more than ten distinct escapes are capped in the message", {
  value <- "/%41%42%43%44%45%46%47%48%49%4A%4B%4C"
  x <- eu_validate(paste0("Disallow: ", value))
  expect_identical(nrow(eu_found(x)), 1L)
  expect_match(x$diagnostics$message, "'%4A' for 'J', and 2 more.",
               fixed = TRUE)
  expect_no_match(x$diagnostics$message, "'%4B'", fixed = TRUE)
})

test_that("unescaped, reserved and non-escape values stay clean", {
  for (value in eu_clean) {
    line <- paste0("Disallow: ", value)
    x <- eu_validate(line)
    expect_identical(nrow(x$diagnostics), 0L, label = line)
  }
  x <- eu_validate("Disallow:")
  expect_identical(x$diagnostics$code, "empty_rule_value")
  expect_identical(robots_validate_text("")$diagnostics$code, "no_rules")
})

test_that("a slashless pattern gets the slash finding first", {
  x <- eu_validate("Disallow: private%7E")
  expect_identical(
    x$diagnostics$code,
    c("rule_missing_leading_slash", "rule_escaped_unreserved")
  )
  expect_identical(x$diagnostics$line, c(2L, 2L))
})

test_that("malformed bytes beside the escape raise no R error", {
  body <- as.raw(c(
    charToRaw("user-agent: *\nDisallow: /"), 0xe9, charToRaw("%7E\n")
  ))
  x <- expect_no_error(robots_validate_text(body))
  expect_true(all(c("invalid_utf8", "rule_escaped_unreserved") %in%
                    x$diagnostics$code))
  expect_identical(eu_found(x)$line, 2L)
  text <- rawToChar(body)
  Encoding(text) <- "bytes"
  y <- expect_no_error(robots_validate_text(text))
  expect_identical(x$diagnostics, y$diagnostics)
})

test_that("NUL bytes and over-long lines do not break the check", {
  for (body in list(
    as.raw(c(charToRaw("user-agent: *\nDisallow: /"), 0x00,
             charToRaw("%7E\n"))),
    as.raw(c(charToRaw("user-agent: *\nDisallow: /%7E"), 0x00,
             charToRaw("x\n")))
  )) {
    x <- expect_no_error(robots_validate_text(body))
    expect_true("nul_byte" %in% x$diagnostics$code)
  }
  long <- sprintf("user-agent: *\ndisallow: /%s%%7E", strrep("x", 17000L))
  y <- expect_no_error(robots_validate_text(long))
  expect_true("line_too_long" %in% y$diagnostics$code)
})

test_that("the matcher still keeps %7E and ~ apart", {
  body <- "user-agent: *\nDisallow: /%7Ejoe\n"
  tilde <- allowed_by_robots_text(body, "https://example.com/~joe", "bot")
  expect_true(tilde$results$allowed)
  escaped <- allowed_by_robots_text(body, "https://example.com/%7Ejoe", "bot")
  expect_false(escaped$results$allowed)
})
