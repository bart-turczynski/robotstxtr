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

# ---- The presets ------------------------------------------------------------

ap_preset <- function(body, url, preset, ...) {
  ap_text(body, url, preset = preset, ...)
}

ap_decision <- function(body, url, preset) {
  ap_preset(body, url, preset)$url_decision
}

test_that("chatgpt_user binds only an OAI-SearchBot group", {
  url <- "https://example.com/dc/x"
  for (group in c("ChatGPT-User", "*", "GPTBot")) {
    row <- ap_preset(
      paste0("User-agent: ", group, "\nDisallow: /\n"), url, "chatgpt_user"
    )
    expect_identical(row$url_decision, "allow", info = group)
    expect_identical(row$reason, "default_allow", info = group)
    expect_identical(row$group_token, NA_character_, info = group)
    expect_identical(row$robots_product_token, "ChatGPT-User", info = group)
  }
  own <- ap_preset("User-agent: OAI-SearchBot\nDisallow: /dc/\n", url,
                   "chatgpt_user")
  expect_identical(own$url_decision, "disallow")
  expect_identical(own$group_token, "OAI-SearchBot")
  both <- ap_preset(
    paste0(
      "User-agent: *\nAllow: /\n\n",
      "User-agent: ChatGPT-User\nUser-agent: OAI-SearchBot\nDisallow: /dc/\n"
    ),
    url, "chatgpt_user"
  )
  expect_identical(both$url_decision, "disallow")
  expect_identical(both$group_token, "OAI-SearchBot")
})

test_that("claude_user selects its own group, else `*`", {
  star <- ap_preset("User-agent: *\nDisallow: /d/\n",
                    "https://example.com/d/x", "claude_user")
  expect_identical(star$url_decision, "disallow")
  expect_identical(star$group_token, "*")
  expect_identical(star$robots_product_token, "Claude-User")
  own <- ap_preset(
    "User-agent: *\nDisallow: /d/\n\nUser-agent: Claude-User\nAllow: /\n",
    "https://example.com/d/x", "claude_user"
  )
  expect_identical(own$url_decision, "allow")
  expect_identical(own$group_token, "Claude-User")
  # The OAI-SearchBot binding is ChatGPT-User's alone.
  oai <- ap_preset("User-agent: OAI-SearchBot\nDisallow: /\n",
                   "https://example.com/d/x", "claude_user")
  expect_identical(oai$url_decision, "allow")
  expect_identical(oai$group_token, "*")
})

test_that("an index.html Allow allows /dir/ on ChatGPT-User, not Claude-User", {
  rules <- "Allow: /dir/index.html\nDisallow: /\n"
  chatgpt <- paste0("User-agent: OAI-SearchBot\n", rules)
  claude <- paste0("User-agent: *\n", rules)
  dir <- "https://example.com/dir/"
  index <- "https://example.com/dir/index.html"
  expect_identical(ap_decision(chatgpt, dir, "chatgpt_user"), "allow")
  expect_identical(ap_decision(claude, dir, "claude_user"), "disallow")
  expect_identical(ap_decision(chatgpt, index, "chatgpt_user"), "allow")
  expect_identical(ap_decision(claude, index, "claude_user"), "allow")
  row <- ap_preset(claude, dir, "claude_user")
  expect_identical(row$matcher_url, "https://example.com/dir")
  expect_identical(row$url_preprocessing_note, "trailing / removed")
  expect_identical(row$url, dir)
})

test_that("claude_user keeps the root `/`", {
  body <- "User-agent: *\nAllow: /index.html\nDisallow: /\n"
  row <- ap_preset(body, "https://example.com/", "claude_user")
  expect_identical(row$url_decision, "allow")
  expect_identical(row$matcher_url, "https://example.com/")
  expect_true(is.na(row$url_preprocessing_note))
  expect_identical(ap_preset(body, "/", "claude_user")$matcher_url, "/")
})

test_that("claude_user encodes a query `/`, chatgpt_user keeps it", {
  rules <- "Allow: /c13?q=/index.html\nDisallow: /\n"
  url <- "https://example.com/c13?q=/"
  chatgpt <- ap_preset(paste0("User-agent: OAI-SearchBot\n", rules), url,
                       "chatgpt_user")
  claude <- ap_preset(paste0("User-agent: *\n", rules), url, "claude_user")
  expect_identical(chatgpt$url_decision, "allow")
  expect_identical(chatgpt$matcher_url, url)
  expect_identical(claude$url_decision, "disallow")
  expect_identical(claude$matcher_url, "https://example.com/c13?q=%2F")
  expect_identical(claude$url_preprocessing_note,
                   "/ in the query encoded as %2F")
  # The path and the fragment keep their `/`.
  expect_identical(
    ap_preset("User-agent: *\n", "https://example.com/a/b?x=/y/#f/g",
              "claude_user")$matcher_url,
    "https://example.com/a/b?x=%2Fy%2F#f/g"
  )
})

test_that("both presets uppercase escape digits; plain google does not", {
  body <- "User-agent: *\nUser-agent: OAI-SearchBot\nDisallow: /esc1/%3cb\n"
  url <- "https://example.com/esc1/%3cb"
  for (preset in c("chatgpt_user", "claude_user")) {
    row <- ap_preset(body, url, preset)
    expect_identical(row$url_decision, "disallow", info = preset)
    expect_identical(row$matcher_url, "https://example.com/esc1/%3Cb",
                     info = preset)
    expect_identical(row$url_preprocessing_note,
                     "percent-escape hex digits uppercased", info = preset)
  }
  expect_identical(ap_google(body, url, "Claude-User")$url_decision, "allow")
})

test_that("escape uppercasing never decodes or double-encodes", {
  for (preset in c("chatgpt_user", "claude_user")) {
    pre <- function(u) ap_preset("User-agent: *\n", u, preset)$matcher_url
    expect_identical(pre("/caf%c3%a9"), "/caf%C3%A9", info = preset)
    expect_identical(pre("/a?b=%2f"), "/a?b=%2F", info = preset)
    expect_identical(pre("/%2e%2e/x"), "/%2E%2E/x", info = preset)
    for (edge in c("/a%zz", "/a%", "/a%3", "/a%%", "/a%g1")) {
      expect_identical(pre(edge), edge, info = paste(preset, edge))
    }
    expect_identical(pre("/a%%3c"), "/a%%3C", info = preset)
  }
})

test_that("a trailing `/` before a query or fragment is kept on claude_user", {
  pre <- function(u) ap_preset("User-agent: *\n", u, "claude_user")
  query <- pre("https://example.com/c1/?q=1")
  expect_identical(query$matcher_url, "https://example.com/c1/?q=1")
  expect_match(query$url_preprocessing_note,
               "trailing / before a query or fragment", fixed = TRUE)
  expect_identical(pre("https://example.com/c1/#x")$matcher_url,
                   "https://example.com/c1/#x")
  expect_identical(pre("https://example.com/a/b/")$matcher_url,
                   "https://example.com/a/b")
  expect_identical(pre("example.com/a/")$matcher_url, "example.com/a")
})

test_that("unmeasured inputs pass as given, and the note names them", {
  invalid <- rawToChar(as.raw(c(0x2f, 0x61, 0xff, 0x62)))
  cases <- list(
    list(url = "/café", unmeasured = "raw byte outside ASCII"),
    list(url = "/a b", unmeasured = "raw space"),
    list(url = "/a/../b", unmeasured = "dot segment"),
    list(url = "/a/./b", unmeasured = "dot segment"),
    list(url = "/a//b", unmeasured = "empty path segment (//)"),
    list(url = "https://u:p@example.com/x", unmeasured = "userinfo"),
    list(url = invalid, unmeasured = "raw byte outside ASCII")
  )
  for (preset in c("chatgpt_user", "claude_user")) {
    for (case in cases) {
      row <- ap_preset("User-agent: *\n", case$url, preset)
      expect_identical(row$matcher_url, case$url, info = case$url)
      expect_match(
        row$url_preprocessing_note,
        paste0("left as given, unmeasured for ", preset, ": "),
        fixed = TRUE, info = case$url
      )
      expect_match(row$url_preprocessing_note, case$unmeasured,
                   fixed = TRUE, info = case$url)
    }
  }
  # ChatGPT-User's trailing slash and query slash are unmeasured too.
  row <- ap_preset("User-agent: *\n", "/d/?q=/", "chatgpt_user")
  expect_identical(row$matcher_url, "/d/?q=/")
  expect_match(row$url_preprocessing_note,
               "trailing / on a non-root path, / in the query", fixed = TRUE)
})

test_that("a latin1-marked URL keeps its bytes and its mark", {
  latin <- "/caf\xe9/"
  Encoding(latin) <- "latin1"
  chatgpt <- ap_preset("User-agent: *\n", latin, "chatgpt_user")$matcher_url
  expect_identical(Encoding(chatgpt), "latin1")
  expect_identical(charToRaw(chatgpt), charToRaw(latin))
  claude <- ap_preset("User-agent: *\n", latin, "claude_user")$matcher_url
  expect_identical(Encoding(claude), "latin1")
  expect_identical(charToRaw(claude), charToRaw(latin)[1:5])
})

test_that("NA and empty URLs follow the existing input refusal", {
  for (preset in c("chatgpt_user", "claude_user")) {
    rows <- ap_preset("User-agent: *\n", c(NA, ""), preset)
    expect_identical(rows$reason, c("input_invalid", "input_invalid"))
    expect_identical(rows$matcher_url, c(NA, ""))
    expect_identical(rows$url_preprocessing_note, c(NA_character_, NA))
    expect_identical(rows$preprocessing_disagreement, c(FALSE, FALSE))
  }
})

test_that("a preset row is not compared for disagreement", {
  row <- ap_preset("User-agent: *\nDisallow: /a/b\n", "/a/./b", "claude_user")
  expect_identical(row$url_decision, "allow")
  expect_identical(row$preprocessing_disagreement, NA)
  expect_identical(row$disagreement_clients,
                   "not compared under an agent preset")
})

test_that("a preset fixes the google ruleset and backend", {
  row <- ap_preset("User-agent: *\n", "/x", "claude_user")
  expect_identical(row$robots_policy_ruleset, "google")
  expect_identical(row$matcher_backend, "google")
  expect_identical(row$policy_body_limit_bytes, 512000L)
  agree <- ap_text(
    "User-agent: *\n", "/x", robots_product_token = "claude-user",
    robots_policy_ruleset = "google", matcher_backend = "google",
    preset = "claude_user"
  )
  expect_identical(agree$robots_product_token, "claude-user")
  expect_identical(agree$url_decision, "allow")
})

test_that("a preset aborts on a conflicting argument or an unknown id", {
  body <- "User-agent: *\n"
  conflict <- function(...) {
    expect_error(
      robots_evaluate_text_v1(body, "/x", ..., preset = "chatgpt_user"),
      class = "robotstxtr_preset_conflict"
    )
  }
  conflict(robots_product_token = "OAI-SearchBot")
  conflict(robots_product_token = "Googlebot")
  conflict(robots_product_token = NA_character_)
  conflict(robots_policy_ruleset = "bing")
  conflict(matcher_backend = "rfc9309")
  conflict(url_normalization = "rfc3986")
  conflict(url_normalization = "none")
  for (bad in list("ChatGPT-User", "claudebot", c("claude_user", "x"),
                   NA_character_, 1)) {
    expect_error(
      robots_evaluate_text_v1(body, "/x", preset = bad),
      class = "robotstxtr_invalid_preset"
    )
  }
  expect_error(
    robots_evaluate_url_v1("http://a/x", matcher_backend = "bing",
                           preset = "claude_user"),
    class = "robotstxtr_preset_conflict"
  )
})

test_that("a NULL preset is byte-identical to leaving it out", {
  body <- "User-agent: *\nAllow: /dir/index.html\nDisallow: /\n"
  urls <- c("https://example.com/dir/", "https://example.com/esc1/%3cb")
  plain <- robots_evaluate_text_v1(body, urls, "Claude-User", "google",
                                   "google")
  null <- robots_evaluate_text_v1(body, urls, "Claude-User", "google",
                                  "google", preset = NULL)
  expect_identical(null, plain)
})

test_that("the batch path equals the row path under a preset", {
  body <- paste0(
    "User-agent: *\nDisallow: /d/\n\n",
    "User-agent: OAI-SearchBot\nAllow: /dir/index.html\nDisallow: /\n"
  )
  urls <- c("https://example.com/dir/", "https://example.com/d/x",
            "https://example.com/esc/%3cb")
  for (preset in c("chatgpt_user", "claude_user")) {
    batch <- ap_preset(body, urls, preset)
    matcher <- agent_preset_matcher_v1(preset, length(urls))
    for (k in seq_along(urls)) {
      row <- match_google_v1(
        charToRaw(body), batch$matcher_url[[k]], matcher$tokens[[k]],
        as.list(matcher$profiles[k, , drop = FALSE])
      )
      expect_identical(batch$url_decision[[k]], row$url_decision,
                       info = paste(preset, urls[[k]]))
      expect_identical(batch$group_token[[k]], row$group_token,
                       info = paste(preset, urls[[k]]))
    }
  }
})

# ---- Through the URL facade -------------------------------------------------

test_that("a 2xx body is read under a preset (fake ssrfr)", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, body = "User-agent: *\nDisallow: /d/\n")
  })
  claude <- robots_evaluate_url_v1(
    c("http://a/d/x/", "http://a/d/", "http://a/e"), preset = "claude_user"
  )$results
  expect_identical(claude$policy_reason, rep("http_200_use_rules", 3L))
  # `/d/` loses its trailing `/`, so `Disallow: /d/` no longer covers it.
  expect_identical(claude$url_decision, c("disallow", "allow", "allow"))
  expect_identical(claude$matcher_url,
                   c("http://a/d/x", "http://a/d", "http://a/e"))
  chatgpt <- robots_evaluate_url_v1("http://a/d/x", preset = "chatgpt_user")
  expect_identical(chatgpt$results$url_decision, "allow")
  expect_identical(chatgpt$results$group_token, NA_character_)
})

test_that("a non-2xx cell is documentation_gap under a preset (fake ssrfr)", {
  for (status in c(404L, 429L, 503L)) {
    local_fake_ssrfr(function(req) fake_response(status, body = "x"))
    for (preset in c("chatgpt_user", "claude_user")) {
      row <- robots_evaluate_url_v1("http://a/x", preset = preset)$results
      info <- paste(preset, status)
      expect_identical(row$policy_status, "documentation_gap", info = info)
      expect_identical(row$policy_reason, "policy_documentation_gap",
                       info = info)
      expect_identical(row$policy_source,
                       "design/engine-contract-v1.md#agent-presets",
                       info = info)
      expect_identical(row$url_decision, NA_character_, info = info)
    }
  }
  # Google's own cells, which the presets do not inherit.
  google <- c(`404` = "evaluated", `503` = "context_required")
  for (status in names(google)) {
    local_fake_ssrfr(function(req) {
      fake_response(as.integer(status), body = "x")
    })
    row <- robots_evaluate_url_v1(
      "http://a/x", "Claude-User", "google", "google"
    )$results
    expect_identical(row$policy_status, google[[status]], info = status)
  }
})
