# ROBO-mtmkpwuf: a robots product token outside the RFC 9309 grammar
# (section 2.2.1: ASCII letters, `_` and `-`) on the google and rfc9309
# backends.
#
# Google's matcher cuts each `User-agent` value in the file at its first
# character outside that grammar and compares the cut value with the
# caller's token as given, so a token outside the grammar can never name a
# group: it reads `*`, or allows by default.
#
# PIN (before the change): these assertions describe today's behavior.

pt_body <- paste0(
  "User-agent: archive.org_bot\nDisallow: /\n\n",
  "User-agent: Googlebot/2.1\nDisallow: /g\n\n",
  "User-agent: *\nDisallow: /star\n"
)

pt_text <- function(token, ruleset = "google", backend = "google",
                    url = "https://example.com/g") {
  n <- length(token)
  robots_evaluate_text_v1(
    pt_body, rep(url, n), token, ruleset, backend
  )$results
}

test_that("PIN: Googlebot/2.1 on google/google reads the * group", {
  r <- pt_text("Googlebot/2.1")
  expect_identical(r$matcher_status, "evaluated")
  expect_identical(r$url_decision, "allow")
  expect_identical(r$group_token, "*")
  r <- pt_text("archive.org_bot", url = "https://example.com/star")
  expect_identical(r$url_decision, "disallow")
  expect_identical(r$group_token, "*")
})

test_that("PIN: an rfc9309-backend row is capability_unavailable", {
  r <- pt_text("Googlebot/2.1", "rfc9309", "rfc9309")
  expect_identical(r$matcher_status, "capability_unavailable")
})

test_that("PIN: the legacy functions read Googlebot/2.1 as today", {
  x <- allowed_by_robots_text(pt_body, "https://example.com/g",
                              "Googlebot/2.1")$results
  expect_identical(x$allowed, TRUE)
  x <- allowed_by_robots_text(pt_body, "https://example.com/star",
                              "Googlebot/2.1")$results
  expect_identical(x$allowed, FALSE)
  local_fake_ssrfr(function(req) fake_response(200L, body = pt_body))
  x <- allowed_by_robots_url("http://example.test/g", "Googlebot/2.1")$results
  expect_identical(x$allowed, TRUE)
})

test_that("PIN: the bounded backends keep their own refusals", {
  r <- pt_text("Yandex/1.0", "yandex", "yandex")
  expect_identical(r$reason, "unsupported_product_token")
  r <- pt_text("Bingbot/2.0", "bing", "bing")
  expect_identical(r$reason, "unsupported_profile")
})

test_that("PIN: a 404 origin reads allow_all for an invalid token", {
  local_fake_ssrfr(function(req) fake_response(404L))
  r <- robots_evaluate_url_v1(
    "http://example.test/g", "Googlebot/2.1", "google", "google"
  )$results
  expect_identical(r$reason, "policy_allow_all")
})
