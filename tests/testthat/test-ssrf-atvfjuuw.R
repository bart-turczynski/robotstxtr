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

# rurl reports no host for an IPv6 literal carrying a zone ID, in both its
# default and WHATWG views, while the fetch drops the zone and dials the bare
# address. Each zoned spelling must get its unzoned verdict.

test_that("a zone ID does not hide a blocked IPv6 literal", {
  zoned <- list(
    c("http://[::1%25lo0]/", "http://[::1]/"),
    c("http://[fd00:ec2::254%25lo0]/", "http://[fd00:ec2::254]/"),
    c("http://[::ffff:127.0.0.1%25lo0]/", "http://[::ffff:127.0.0.1]/"),
    c("http://[fe80::1%25eth0]/", "http://[fe80::1]/"),
    c("http://[::1%lo0]/", "http://[::1]/"),
    c("http://[fe80::1%eth0]/", "http://[fe80::1]/")
  )
  for (pair in zoned) {
    res <- robotstxtr:::robots_ssrf_check(pair[[1L]])
    expect_false(res$allowed, info = pair[[1L]])
    expect_identical(res$reason, unzoned_cases[[pair[[2L]]]], info = pair[[1L]])
  }
})

test_that("a zone ID survives a port and userinfo, and spares public addresses", {
  for (url in c(
    "http://[::1%25lo0]:8080/",
    "http://user:pw@[::1%25lo0]/",
    "http://u@[fe80::1%25eth0]:80/x"
  )) {
    res <- robotstxtr:::robots_ssrf_check(url)
    expect_false(res$allowed, info = url)
  }
  res <- robotstxtr:::robots_ssrf_check("http://[2606:4700::1%25eth0]/")
  expect_true(res$allowed)
})

test_that("a bracketed host that is no IPv6 literal is refused", {
  for (url in c("http://[not-an-address%25x]/", "http://[v1.foo]/")) {
    res <- robotstxtr:::robots_ssrf_check(url)
    expect_false(res$allowed, info = url)
    expect_identical(res$reason, "malformed-address", info = url)
  }
  res <- robotstxtr:::ssrf_check(
    host = NA_character_, scheme = "http", raw_host = "[not-an-address]"
  )
  expect_false(res$allowed)
  expect_identical(res$reason, "malformed-address")
})
