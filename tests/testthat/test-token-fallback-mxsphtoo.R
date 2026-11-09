# ROBO-mxsphtoo: the google matcher binding calls the single-agent
# `OneAgentAllowedByRobots`, so a caller token obeys a group that names it
# exactly and otherwise the `*` group, in both directions: Googlebot-Image
# never reads a Googlebot group, and Googlebot never reads a Googlebot-Image
# group. Google's common-crawlers page lists two tokens for Googlebot-Image
# (`Googlebot-Image`, `Googlebot`) and GoogleOther-Image (`GoogleOther-Image`,
# `GoogleOther`), and a rule applies when either matches, so the first and
# last tests pin a known divergence from that listing, not Google's
# behavior. They pin current behavior only; whether to model the fallback is
# a recommendation for the maintainer in design/engine-profiles.md §5a.

tf_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

tf_parent_and_star <- tf_lines(
  "User-agent: Googlebot",
  "Disallow: /g/",
  "",
  "User-agent: *",
  "Disallow: /s/"
)

tf_own_group <- tf_lines(
  "User-agent: Googlebot",
  "Disallow: /g/",
  "",
  "User-agent: Googlebot-Image",
  "Disallow: /i/",
  "",
  "User-agent: *",
  "Disallow: /s/"
)

tf_urls <- c("https://x.com/g/a.jpg", "https://x.com/s/a.jpg",
             "https://x.com/i/a.jpg")

test_that("Googlebot-Image with no own group follows *, not Googlebot", {
  x <- allowed_by_robots_text(tf_parent_and_star, tf_urls, "Googlebot-Image")
  expect_identical(x$results$allowed, c(TRUE, FALSE, TRUE))
  expect_identical(
    x$results$decision_source,
    c("default_allow", "rule_disallow", "default_allow")
  )
})

test_that("Googlebot itself follows its own group on the same body", {
  x <- allowed_by_robots_text(tf_parent_and_star, tf_urls, "Googlebot")
  expect_identical(x$results$allowed, c(FALSE, TRUE, TRUE))
})

test_that("Googlebot-Image with its own group follows only that group", {
  x <- allowed_by_robots_text(tf_own_group, tf_urls, "Googlebot-Image")
  expect_identical(x$results$allowed, c(TRUE, TRUE, FALSE))
  expect_identical(
    x$results$decision_source,
    c("default_allow", "default_allow", "rule_disallow")
  )
})

test_that("Googlebot ignores a Googlebot-Image group and follows *", {
  body <- tf_lines(
    "User-agent: Googlebot-Image",
    "Disallow: /i/",
    "",
    "User-agent: *",
    "Disallow: /s/"
  )
  x <- allowed_by_robots_text(body, tf_urls, "Googlebot")
  expect_identical(x$results$allowed, c(TRUE, FALSE, TRUE))
  expect_identical(
    x$results$decision_source,
    c("default_allow", "rule_disallow", "default_allow")
  )
})

test_that("GoogleOther-Image with no own group follows *, not GoogleOther", {
  body <- tf_lines(
    "User-agent: GoogleOther",
    "Disallow: /g/",
    "",
    "User-agent: *",
    "Disallow: /s/"
  )
  x <- allowed_by_robots_text(body, tf_urls, "GoogleOther-Image")
  expect_identical(x$results$allowed, c(TRUE, FALSE, TRUE))
})
