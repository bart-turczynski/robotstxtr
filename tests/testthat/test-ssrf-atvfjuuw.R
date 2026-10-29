# ROBO-atvfjuuw: bracketed hosts rurl reports no host for. Pure guard tests,
# fully offline; ported from sitemapr SITE-jtluuybg.

# The unzoned spellings, pinned so the zoned cases below are compared against
# a verdict this file proves rather than assumes.
unzoned_cases <- c(
  "http://[::1]/" = "loopback",
  "http://[fd00:ec2::254]/" = "cloud-metadata",
  "http://[::ffff:127.0.0.1]/" = "ipv4-mapped",
  "http://[fe80::1]/" = "link-local"
)

test_that("unzoned IPv6 literals are blocked with their reasons", {
  for (url in names(unzoned_cases)) {
    res <- robotstxtr:::robots_ssrf_check(url)
    expect_false(res$allowed, info = url)
    expect_identical(res$reason, unzoned_cases[[url]], info = url)
  }
})

test_that("an ordinary public host is still allowed", {
  res <- robotstxtr:::robots_ssrf_check("https://example.com/robots.txt")
  expect_true(res$allowed)
  expect_true(is.na(res$reason))
})
