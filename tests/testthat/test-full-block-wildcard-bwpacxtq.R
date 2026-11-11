# ROBO-bwpacxtq: under a named group that disallows `/` (a full block), the
# `User-agent: *` Disallows it lacks add nothing, so the check lists only the
# lost Allow rules. This file pins the behavior before that change: every lost
# `*` rule is listed.

bp_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

# The wildcard_rules_not_inherited rows of a document's validation.
bp_rows <- function(body) {
  x <- robots_validate_text(body)
  x$diagnostics[x$diagnostics$code == "wildcard_rules_not_inherited", ,
                drop = FALSE]
}

test_that("a named full block lists its lost * Allow and Disallow", {
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Allow: /a", "Disallow: /b",
    "User-agent: x", "Disallow: /"
  ))
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$line, 4L)
  expect_match(rows$message, paste0(
    "x obeys only this group, so these `User-agent: *` rules do not apply ",
    "to it: Allow: /a (line 2), Disallow: /b (line 3)."
  ), fixed = TRUE)
})

test_that("the ExampleBot reproduction lists the lost * Disallow", {
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Disallow: /admin/",
    "User-agent: ExampleBot", "Disallow: /"
  ))
  expect_identical(nrow(rows), 1L)
  expect_match(rows$message, "Disallow: /admin/ (line 2).", fixed = TRUE)
})
