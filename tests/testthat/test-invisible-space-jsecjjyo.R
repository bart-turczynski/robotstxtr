# ROBO-jsecjjyo: a no-break space, another non-ASCII space or a zero-width
# character in a User-agent value or before a directive key. The text looks
# right, but Google's parser strips ASCII whitespace only. Fixtures are
# synthetic and written as \u escapes, so the source stays ASCII.

iv_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")
iv_text <- function(...) robots_validate_text(iv_lines(...))
iv_rows <- function(x, code) {
  d <- x$diagnostics
  d[d$code == code, , drop = FALSE]
}
iv_codes <- function(x) {
  d <- x$diagnostics
  paste(d$line, d$severity, d$code)
}

# Google's decision for `token` on `path`, the reading the rows state.
iv_google <- function(body, token, path) {
  r <- robots_evaluate_text_v1(body, paste0("https://example.com", path),
                               token, "google", "google")$results
  paste(r$url_decision, r$matched_line)
}

iv_plain <- "Directive is not recognized by this validation profile."

# The ticket's example: three no-break spaces pad the value before a comment.
iv_ticket <- iv_lines("User-agent: *", "Allow: /", "",
                      "User-agent: bingbot    # Microsoft",
                      "Disallow: /private/")

test_that("Google's reading of the ticket's examples", {
  # Google cuts the value at the first no-break space and reads `bingbot`.
  expect_identical(iv_google(iv_ticket, "bingbot", "/private/x"),
                   "disallow 5")
  # A zero-width space before the key: Google does not read the rule.
  expect_identical(
    iv_google(iv_lines("User-agent: *", "​Disallow: /private/"),
              "ExampleBot", "/private/x"),
    "allow NA"
  )
  # A zero-width space before User-agent: Google starts no group, so the
  # rule after it stays with the group above.
  body <- iv_lines("User-agent: a", "Disallow: /a", "​User-agent: x",
                   "Disallow: /b")
  expect_identical(iv_google(body, "a", "/b"), "disallow 4")
  expect_identical(iv_google(body, "x", "/b"), "allow NA")
})

test_that("today's rows name no invisible character", {
  x <- robots_validate_text(iv_ticket)
  expect_identical(iv_codes(x),
                   c("4 info user_agent_cut", "4 info rule_slash_split"))
  expect_false(grepl("U+00A0", iv_rows(x, "user_agent_cut")$message,
                     fixed = TRUE))
  x <- iv_text("User-agent: *", "​Disallow: /private/")
  expect_identical(iv_rows(x, "unknown_directive")$message, iv_plain)
  x <- iv_text("User-agent: a", "Disallow: /a", "​User-agent: x",
               "Disallow: /b")
  expect_identical(iv_rows(x, "unknown_directive")$message, iv_plain)
  x <- iv_text("User-agent: bingbot Disallow: /x", "Disallow: /y")
  expect_identical(iv_codes(x), "1 warning directive_in_value")
  expect_false(grepl("U+00A0", iv_rows(x, "directive_in_value")$message,
                     fixed = TRUE))
})

test_that("ASCII padding before a comment draws no row", {
  x <- iv_text("User-agent: bingbot    # c", "Disallow: /")
  expect_identical(nrow(x$diagnostics), 0L)
})
