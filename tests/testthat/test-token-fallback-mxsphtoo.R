# ROBO-mxsphtoo: the google matcher binding calls the single-agent
# `OneAgentAllowedByRobots`, so a caller token obeys a group that names it
# exactly and otherwise the `*` group, in both directions: Googlebot-Image
# never reads a Googlebot group, and Googlebot never reads a Googlebot-Image
# group. Google's common-crawlers page lists two tokens for Googlebot-Image
# (`Googlebot-Image`, `Googlebot`) and GoogleOther-Image (`GoogleOther-Image`,
# `GoogleOther`), and a rule applies when either matches, so the first and
# last tests pin a known divergence from that listing, not Google's
# behavior, on the legacy path. The v1 `google` ruleset with the `google`
# backend models the fallback (ROBO-fbbmvbob, design/engine-profiles.md §5a
# Decision; test-crawler-tokens-fbbmvbob.R); the last test here contrasts
# the two paths on the same bodies.

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

test_that("the v1 google ruleset falls back where the legacy path does not", {
  v1 <- function(body, token, ruleset = "google") {
    robots_evaluate_text_v1(body, tf_urls, token, ruleset, "google")$results
  }
  # Googlebot-Image with no own group: the Googlebot group on v1 google.
  r <- v1(tf_parent_and_star, "Googlebot-Image")
  expect_identical(r$url_decision, c("disallow", "allow", "allow"))
  expect_identical(r$group_token, rep("Googlebot", 3L))
  # Under another ruleset, the legacy answer.
  r <- v1(tf_parent_and_star, "Googlebot-Image", ruleset = "rfc9309")
  expect_identical(r$url_decision, c("allow", "disallow", "allow"))
  # Its own group still wins, and Googlebot never reads a child's group.
  r <- v1(tf_own_group, "Googlebot-Image")
  expect_identical(r$url_decision, c("allow", "allow", "disallow"))
  body <- tf_lines(
    "User-agent: Googlebot-Image",
    "Disallow: /i/",
    "",
    "User-agent: *",
    "Disallow: /s/"
  )
  r <- v1(body, "Googlebot")
  expect_identical(r$url_decision, c("allow", "disallow", "allow"))
  expect_identical(r$group_token, rep("*", 3L))
})
