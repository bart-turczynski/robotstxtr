# ROBO-fbbmvbob: Google crawler tokens on the v1 `google` ruleset with the
# `google` matcher backend.
#
# These pins hold the behavior before the crawler-token layer: the binding
# reads the caller's one token, so a crawler with no group of its own obeys
# `*`, whatever parent token Google's common-crawlers page lists for it, and
# an AdsBot-family crawler obeys `*` although Google says it ignores `*`.

ct_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

ct_parent_and_star <- ct_lines(
  "User-agent: Googlebot",
  "Disallow: /g/",
  "",
  "User-agent: *",
  "Disallow: /s/"
)

ct_star_only <- ct_lines("User-agent: *", "Disallow: /")

ct_eval <- function(body, url, token, ruleset = "google",
                    backend = "google") {
  robots_evaluate_text_v1(
    body, url,
    robots_product_token = token,
    robots_policy_ruleset = ruleset,
    matcher_backend = backend
  )$results
}

test_that("Googlebot-Image with only a Googlebot group follows *", {
  r <- ct_eval(
    ct_parent_and_star, c("https://x.com/g/a.jpg", "https://x.com/s/a.jpg"),
    "Googlebot-Image"
  )
  expect_identical(r$url_decision, c("allow", "disallow"))
  expect_identical(r$matched_line, c(NA_integer_, 5L))
  expect_false("group_token" %in% names(r))
})

test_that("AdsBot-Google with only a * group obeys *", {
  r <- ct_eval(ct_star_only, "https://x.com/page", "AdsBot-Google")
  expect_identical(r$url_decision, "disallow")
  expect_identical(r$matched_line, 2L)
  expect_identical(r$reason, "rule_disallow")
})
