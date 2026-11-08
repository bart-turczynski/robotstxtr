# ROBO-vxrzcqpe: how a robots.txt with no Allow or Disallow rules validates.

nr_rule_free <- list(
  "zero bytes" = raw(),
  "blank lines" = "\n\n  \n\t\n",
  "CRLF blank lines" = "\r\n\r\n",
  "comments only" = "# only a comment\n# another",
  "Sitemap only" = "Sitemap: https://example.com/s.xml\n",
  "comments and sitemaps" = paste0(
    "# c\nSitemap: https://example.com/s.xml\n",
    "Sitemap: https://example.com/t.xml"
  )
)

test_that("a rule-free document without a User-agent is an error today", {
  for (case in names(nr_rule_free)) {
    x <- robots_validate_text(nr_rule_free[[case]])
    expect_identical(x$documents$validation_status, "error", label = case)
    expect_identical(x$diagnostics$code, "missing_user_agent", label = case)
    expect_identical(x$documents$error_count, 1L, label = case)
  }
})

test_that("a User-agent with no rules is valid with no diagnostics today", {
  x <- robots_validate_text("User-agent: *\n")
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(nrow(x$diagnostics), 0L)
})

test_that("a 200 with an empty body is an error today", {
  local_fake_ssrfr(function(req) fake_response(200L, body = raw()))
  x <- robots_validate_url("http://a/")
  expect_identical(x$map$validation_status, "error")
  expect_identical(x$documents$validation_status, "error")
  expect_identical(x$diagnostics$code, "missing_user_agent")
})
