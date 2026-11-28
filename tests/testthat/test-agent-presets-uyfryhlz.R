# ChatGPT-User and Claude-User presets on the v1 facades (ROBO-uyfryhlz).
#
# Every body is synthetic, on example.com, rebuilt from the prose of the
# agent-view-research records the preset table cites (converters/openai.md,
# access-and-blocklists/claude-blocklist.md and robots-parser-ports.md); the
# byte-pinned lab files are not in this repository.

ap_text <- function(body, url, ...) {
  robots_evaluate_text_v1(body, url, ...)$results
}

ap_google <- function(body, url, token, url_normalization = "none") {
  ap_text(
    body, url,
    robots_product_token = token, robots_policy_ruleset = "google",
    matcher_backend = "google", url_normalization = url_normalization
  )
}

# ---- The plain google facade, which a NULL preset must keep -----------------

test_that("the plain google facade reads every group the preset bodies hold", {
  star <- ap_google("User-agent: *\nDisallow: /\n",
                    "https://example.com/a", "ChatGPT-User")
  expect_identical(star$url_decision, "disallow")
  expect_identical(star$group_token, "*")
  own <- ap_google("User-agent: ChatGPT-User\nDisallow: /\n",
                   "https://example.com/a", "ChatGPT-User")
  expect_identical(own$url_decision, "disallow")
  expect_identical(own$group_token, "ChatGPT-User")
})

test_that("the plain google facade keeps the index.html shortcut and raw `/`", {
  body <- "User-agent: *\nAllow: /dir/index.html\nDisallow: /\n"
  dir <- ap_google(body, "https://example.com/dir/", "Claude-User")
  expect_identical(dir$url_decision, "allow")
  query <- ap_google(
    "User-agent: *\nAllow: /c13?q=/index.html\nDisallow: /\n",
    "https://example.com/c13?q=/", "Claude-User"
  )
  expect_identical(query$url_decision, "allow")
  expect_identical(query$matcher_url, "https://example.com/c13?q=/")
})

test_that("the plain google facade under \"none\" keeps the escape case", {
  row <- ap_google("User-agent: *\nDisallow: /esc1/%3cb\n",
                   "https://example.com/esc1/%3cb", "Claude-User")
  # Google escapes the rule to `%3Cb` and reads the target as given.
  expect_identical(row$url_decision, "allow")
  expect_identical(row$matcher_url, "https://example.com/esc1/%3cb")
  expect_true(is.na(row$url_preprocessing_note))
})

test_that("the public url_normalization value set is unchanged", {
  expect_identical(
    robots_engine_contract_v1()$url_normalizations,
    c("rfc3986", "whatwg", "none")
  )
  expect_error(
    ap_google("User-agent: *\n", "https://example.com/", "a",
              url_normalization = "claude_user"),
    class = "robotstxtr_invalid_url_normalization"
  )
})
