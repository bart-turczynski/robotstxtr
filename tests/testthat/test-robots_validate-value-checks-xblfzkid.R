# ROBO-xblfzkid: value checks on Sitemap and Allow/Disallow lines.

vc_codes <- c(
  "invalid_sitemap_url", "unsupported_sitemap_scheme",
  "rule_missing_leading_slash", "rule_inner_dollar"
)

vc_validate <- function(line) {
  robots_validate_text(paste0("user-agent: *\n", line, "\n"))
}

test_that("bad sitemap and pattern values are not yet diagnosed", {
  for (line in c(
    "Sitemap: not a url", "Sitemap: mailto:a@b.c",
    "Disallow: private", "Disallow: /a$b"
  )) {
    x <- vc_validate(line)
    expect_false(any(vc_codes %in% x$diagnostics$code), label = line)
    expect_identical(x$documents$validation_status, "valid", label = line)
  }
})

test_that("the matcher never matches a slashless pattern or an inner '$'", {
  slashless <- allowed_by_robots_text(
    "user-agent: *\nDisallow: private\n", "https://x.com/private", "bot"
  )
  expect_true(slashless$results$allowed)
  inner_dollar <- allowed_by_robots_text(
    "user-agent: *\nDisallow: /a$b\n", "https://x.com/ab", "bot"
  )
  expect_true(inner_dollar$results$allowed)
})
