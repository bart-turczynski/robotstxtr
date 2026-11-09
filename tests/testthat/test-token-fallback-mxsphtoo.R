# ROBO-mxsphtoo: the google matcher binding calls the single-agent
# `OneAgentAllowedByRobots`, so a caller token obeys a group that names it
# exactly and otherwise the `*` group. It never falls back to a parent
# token's group (Googlebot-Image to Googlebot, GoogleOther-Image to
# GoogleOther). These tests pin that current behavior; whether to model a
# fallback is an open recommendation in design/engine-profiles.md §5a.

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
