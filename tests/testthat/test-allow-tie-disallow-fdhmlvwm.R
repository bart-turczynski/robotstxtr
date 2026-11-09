# ROBO-fdhmlvwm: a Disallow whose pattern an Allow repeats never applies.

at_block_all <- "User-agent: *\nAllow: /\nDisallow: /\n"

test_that("today a block-all file with Allow: / validates clean", {
  x <- robots_validate_text(at_block_all)
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(nrow(x$diagnostics), 0L)
})

test_that("the matcher lets the identical Allow win the tie", {
  x <- allowed_by_robots_text(
    at_block_all, c("http://e/", "http://e/a/b"), "Googlebot"
  )
  expect_identical(x$results$allowed, c(TRUE, TRUE))
  expect_identical(x$results$decision_source, c("rule_allow", "rule_allow"))
  expect_identical(x$results$matched_line, c(2L, 2L))
})
