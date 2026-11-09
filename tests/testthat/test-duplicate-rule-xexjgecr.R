# ROBO-xexjgecr: an Allow or Disallow that repeats an earlier identical rule
# for the same crawlers has no effect.

dr_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

dr_duplicate <- dr_lines("User-agent: *", "Disallow: /x", "Disallow: /x")

test_that("an exact duplicate Disallow validates clean today", {
  x <- robots_validate_text(dr_duplicate)
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(nrow(x$diagnostics), 0L)
})

test_that("the matcher decides on the first copy, with or without the second", {
  for (body in list(dr_duplicate, dr_lines("User-agent: *", "Disallow: /x"))) {
    x <- allowed_by_robots_text(body, "http://e/x", "Googlebot")
    expect_false(x$results$allowed)
    expect_identical(x$results$matched_line, 2L)
  }
})
