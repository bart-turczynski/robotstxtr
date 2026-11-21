# Evaluator URL preprocessing (ROBO-bnvdmdjr; design/adr/0002). These pins
# record what the v1 facades read today, before `url_normalization` exists:
# the URL as given, dot segments and userinfo included.

pp_body <- paste0(
  "User-agent: *\nDisallow: /account/\nAllow: /latam\nDisallow: /x\n",
  "Disallow: /a/b\n"
)

# One engine's rows under today's reading.
pp_today <- function(url, backend, token, body = pp_body) {
  robots_evaluate_text_v1(body, url, token, backend, backend)$results
}

pp_engines <- list(
  google = "Googlebot", bing = "bingbot", yandex = "Yandex"
)

test_that("today: dot segments are read as given on every backend", {
  for (backend in names(pp_engines)) {
    r <- pp_today(
      c(
        "https://example.com/latam/../account/x",
        "https://example.com/latam/%2e%2e/account/x",
        "https://example.com/a/./b"
      ),
      backend, pp_engines[[backend]]
    )
    expect_identical(
      r$url_decision, c("allow", "allow", "allow"),
      label = backend
    )
    expect_identical(r$matched_rule_value[1:2], c("/latam", "/latam"))
  }
})

test_that("today: Google slices a raw `;` in userinfo, Bing and Yandex do not", {
  urls <- c("https://u;v@example.com/x", "https://u%3Bv@example.com/x")
  expect_identical(
    pp_today(urls, "google", "Googlebot")$url_decision,
    c("allow", "disallow")
  )
  expect_identical(
    pp_today(urls, "bing", "bingbot")$url_decision, c("disallow", "disallow")
  )
  expect_identical(
    pp_today(urls, "yandex", "Yandex")$url_decision, c("disallow", "disallow")
  )
})

test_that("today: a path-only URL reaches Google as given", {
  r <- pp_today(c("/a/../b", "example.com/a/../b"), "google", "Googlebot")
  expect_identical(r$url_decision, c("allow", "allow"))
  expect_identical(r$reason, c("default_allow", "default_allow"))
})

test_that("the extractors are byte-transparent: dot segments kept", {
  expect_identical(
    robotstxtr_extract_request_target_("https://example.com/a/../b"),
    "/a/../b"
  )
  expect_identical(
    bing_extract_request_target("https://example.com/a/../b"), "/a/../b"
  )
  expect_identical(
    google_request_target_v1("https://example.com/a/../b"),
    "https://example.com/a/../b"
  )
})

test_that("the legacy functions read dot segments as given", {
  legacy <- allowed_by_robots_text(
    pp_body, "https://example.com/latam/../account/x", "Googlebot"
  )
  expect_true(legacy$results$allowed)
  expect_identical(legacy$results$decision_source, "rule_allow")

  local_fake_ssrfr(function(req) fake_response(200L, body = pp_body))
  fetched <- allowed_by_robots_url(
    "http://a/latam/../account/x", "Googlebot"
  )
  expect_true(fetched$results$allowed)
  expect_identical(fetched$results$matched_rule_value, "/latam")
})
