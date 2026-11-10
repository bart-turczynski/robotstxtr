# ROBO-gaczsrgj: a rule that percent-escapes an unreserved character.

eu_validate <- function(line) {
  robots_validate_text(paste0("user-agent: *\n", line, "\nallow: /\n"))
}

eu_flagged <- c(
  "/%7Ejoe", "/%7ejoe", "/%41", "/%7A", "/%30", "/%2D", "/%2E", "/%5F",
  "/%7E%7E"
)

eu_clean <- c(
  "/~joe", "/%2F", "/%25", "/%3C", "/%20", "/%E2%80%8B", "/%257E", "/%7",
  "/%zz", "/*.pdf$"
)

test_that("known gap: an escaped unreserved character goes unflagged", {
  for (value in eu_flagged) {
    for (directive in c("Disallow", "Allow")) {
      line <- paste0(directive, ": ", value)
      x <- eu_validate(line)
      expect_identical(nrow(x$diagnostics), 0L, label = line)
    }
  }
})

test_that("unescaped, reserved and non-escape values stay clean", {
  for (value in eu_clean) {
    line <- paste0("Disallow: ", value)
    x <- eu_validate(line)
    expect_identical(nrow(x$diagnostics), 0L, label = line)
  }
  x <- eu_validate("Disallow:")
  expect_identical(x$diagnostics$code, "empty_rule_value")
  expect_identical(nrow(robots_validate_text("")$diagnostics), 1L)
  expect_identical(robots_validate_text("")$diagnostics$code, "no_rules")
})

test_that("the matcher still keeps %7E and ~ apart", {
  body <- "user-agent: *\nDisallow: /%7Ejoe\n"
  tilde <- allowed_by_robots_text(body, "https://example.com/~joe", "bot")
  expect_true(tilde$results$allowed)
  escaped <- allowed_by_robots_text(body, "https://example.com/%7Ejoe", "bot")
  expect_false(escaped$results$allowed)
})
