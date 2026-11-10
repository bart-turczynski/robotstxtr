# ROBO-xglcoagv: Google's parser reads any key that starts with `disallow`
# or `allow` (ASCII case-insensitive) as that directive (`KeyIsDisallow`,
# `KeyIsAllow`, src/robots.cc), so `DisallowAITraining: /` blocks the group
# for Google. Pin of today's behavior: the validator says nothing.

pk_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

test_that("today a DisallowAITraining key validates clean", {
  body <- pk_lines("User-agent: *", "DisallowAITraining: /")
  x <- robots_validate_text(body)
  expect_identical(nrow(x$diagnostics), 0L)
  expect_identical(x$documents$validation_status, "valid")
  r <- allowed_by_robots_text(body, "https://example.com/a",
                              "Googlebot")$results
  expect_false(r$allowed)
  expect_identical(r$decision_source, "rule_disallow")
  expect_identical(r$matched_line, 2L)
})
