# ROBO-gfjotdrr: a named User-agent group does not inherit the
# `User-agent: *` rules. A crawler obeys only the group that names it.

wi_tidio <- paste0(
  "User-agent: *\n",
  "Disallow: /wp-admin/*\n",
  "Disallow: /tickets/satisfaction/*\n",
  "Disallow: /conversations/satisfaction/*\n",
  "Disallow: /a/*\n",
  "Disallow: /b/*\n",
  "\n",
  "User-agent: Bingbot\n",
  "Disallow: /blog/search/\n"
)

test_that("the matcher lets Bingbot ignore the * rules", {
  x <- allowed_by_robots_text(
    wi_tidio, rep("https://x.com/wp-admin/x", 2L), c("TestBot", "Bingbot")
  )
  expect_identical(x$results$allowed, c(FALSE, TRUE))
  expect_identical(
    x$results$decision_source, c("rule_disallow", "default_allow")
  )
})

test_that("a named group dropping the * rules validates clean today", {
  x <- robots_validate_text(wi_tidio)
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(nrow(x$diagnostics), 0L)

  x <- robots_validate_text(
    "User-agent: *\nDisallow: /x\nUser-agent: Bingbot\n"
  )
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(nrow(x$diagnostics), 0L)
})
