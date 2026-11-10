# ROBO-ctdkqawi: rules a NUL hides from the validation parser while other
# rules still parse. Google's matcher drops the NUL bytes and reads on
# (R/body-decode.R); the parser ends a line at its first NUL.

ch_nul <- as.raw(0)

# Google's matcher decision on `bytes`, decoded as the fetch path decodes it
# (NULs dropped), for FooBot on example.com.
ch_allowed <- function(bytes, path) {
  url <- paste0("https://example.com", path)
  Encoding(url) <- "UTF-8"
  robotstxtr_allowed_text_(decode_matcher_body(bytes), url, "FooBot")
}

# `code@line` for each row of `x`, in emission order.
ch_rows <- function(x) {
  d <- x$diagnostics
  paste0(d$code, "@", d$line)
}

ch_raw0_message <- function(n) {
  sprintf(
    paste0(
      "With its NUL bytes removed, as Google's matcher reads it, the ",
      "document has %d Allow or Disallow rule(s); if this is a UTF-16 ",
      "file, re-save it as UTF-8 (RFC 9309 section 2.3)."
    ),
    n
  )
}

# NUL at the start of a line, behind a rule the parser reads.
ch_line_start <- c(charToRaw("User-agent: *\nDisallow: /private\n"), ch_nul,
                   charToRaw("Disallow: /\n"))
# NUL inside the User-agent key.
ch_agent_key <- c(charToRaw("User-"), ch_nul,
                  charToRaw("agent: *\nDisallow: /x\n"))

test_that("a NUL at line start behind a parsed rule: today's rows", {
  expect_false(ch_allowed(ch_line_start, "/"))
  expect_identical(ch_rows(robots_validate_text(ch_line_start)), "nul_byte@3")
})

test_that("a NUL in the User-agent key: today's rows", {
  expect_false(ch_allowed(ch_agent_key, "/x"))
  expect_identical(
    ch_rows(robots_validate_text(ch_agent_key)),
    c("nul_byte@1", "malformed_line@1", "rule_without_user_agent@2",
      "missing_user_agent@NA")
  )
})

test_that("a raw-rule-free body keeps today's count, grouped or not", {
  # The NUL-free rule sits in no group; it is still counted.
  bytes <- c(ch_nul, charToRaw("Disallow: /x\n"))
  x <- robots_validate_text(bytes)
  expect_identical(ch_rows(x), c("nul_byte@1", "rules_after_nul_removal@NA"))
  expect_identical(x$diagnostics$message[[2L]], ch_raw0_message(1L))
})

test_that("NUL lines that hide no rule stay silent", {
  cases <- list(
    "NUL in a comment" = c(charToRaw("User-agent: *\nDisallow: /a # x"),
                           ch_nul, charToRaw("y\n")),
    "NUL mid-value" = c(charToRaw("User-agent: *\nDisallow: /a"), ch_nul,
                        charToRaw("b\n"))
  )
  for (case in names(cases)) {
    expect_identical(ch_rows(robots_validate_text(cases[[case]])),
                     "nul_byte@2", label = case)
  }
  expect_identical(
    ch_rows(robots_validate_text(as.raw(c(0, 0x0a, 0, 0x0a)))),
    c("nul_byte@1", "nul_byte@2", "no_rules@NA")
  )
})
