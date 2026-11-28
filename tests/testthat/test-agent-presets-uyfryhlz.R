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
  expect_identical(chatgpt$url_preprocessing_note, NA_character_)
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
    note <- function(u) {
      ap_preset("User-agent: *\n", u, preset)$url_preprocessing_note
    }
    # The uppercased `%2e%2e` segment is still named as unmeasured.
    expect_identical(
      note("/%2e%2e/x"),
      paste0("percent-escape hex digits uppercased; left as given, ",
             "unmeasured for ", preset, ": percent-encoded dot segment"),
      info = preset
    )
    # A valid escape and an encoded dot inside a longer segment are measured.
    expect_identical(note("/a%41b/x%2Ey"), NA_character_, info = preset)
  }
  expect_identical(
    ap_preset("User-agent: *\n", "https://example.com/a\\b/",
              "claude_user")$url_preprocessing_note,
    "trailing / removed; left as given, unmeasured for claude_user: backslash"
  )
})

test_that("a query step leaves a URL ending in `?` as given", {
  for (url in c("/a?", "/a?#f/g", "/a?x=1")) {
    row <- ap_preset("User-agent: *\n", url, "claude_user")
    expect_identical(row$matcher_url, url, info = url)
    expect_identical(row$url_preprocessing_note, NA_character_, info = url)
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
    list(url = invalid, unmeasured = "raw byte outside ASCII"),
    list(url = "/a\\b", unmeasured = "backslash"),
    list(url = "/a\tb", unmeasured = "control byte"),
    list(url = "/a\001b", unmeasured = "control byte"),
    list(url = "/a\177b", unmeasured = "control byte"),
    list(url = "/a%zz", unmeasured = "% without two hex digits"),
    list(url = "/a%", unmeasured = "% without two hex digits"),
    list(url = "/a%3", unmeasured = "% without two hex digits"),
    list(url = "/a/%2E/b", unmeasured = "percent-encoded dot segment"),
    list(url = "/a/.%2E/b", unmeasured = "percent-encoded dot segment"),
    list(url = "/%2E%2E/x", unmeasured = "percent-encoded dot segment")
  )
  for (char in strsplit("\"<>^`{|}", "", fixed = TRUE)[[1L]]) {
    cases[[length(cases) + 1L]] <- list(
      url = paste0("/a", char, "b"),
      unmeasured = "character RFC 3986 excludes (\"<>^`{|})"
    )
  }
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
    # A literal dot segment is not named as an encoded one.
    expect_identical(
      ap_preset("User-agent: *\n", "/a/../b", preset)$url_preprocessing_note,
      paste0("left as given, unmeasured for ", preset, ": dot segment")
    )
  }
  # Brackets outside the host, a second `#` and an encoded `/` in the path
  # (review round 2, M2), with review-2's four probe inputs first.
  more <- list(
    list(url = "https://e.com/a[1]/x", unmeasured = "[ or ] outside the host"),
    list(url = "https://e.com/x#a#b", unmeasured = "a second #"),
    list(url = "https://e.com/x/%2e%2e%2fy",
         unmeasured = "encoded / (%2F) in the path"),
    list(url = "https://e.com/x/..%2f",
         unmeasured = "encoded / (%2F) in the path"),
    list(url = "https://e.com/p?a[]=1", unmeasured = "[ or ] outside the host"),
    list(url = "https://e.com/p#x]", unmeasured = "[ or ] outside the host"),
    list(url = "/a%2Fb", unmeasured = "encoded / (%2F) in the path")
  )
  for (preset in c("chatgpt_user", "claude_user")) {
    for (case in more) {
      row <- ap_preset("User-agent: *\n", case$url, preset)
      note <- row$url_preprocessing_note
      expect_match(note, paste0("unmeasured for ", preset, ": "),
                   fixed = TRUE, info = paste(preset, case$url))
      expect_match(note, case$unmeasured, fixed = TRUE,
                   info = paste(preset, case$url))
    }
    # Controls: a bracketed IPv6 host, one `#`, and `%2f` only in the query.
    controls <- c(
      "https://[::1]/x", "https://e.com/x#a", "https://e.com/x?q=%2F"
    )
    for (url in controls) {
      expect_identical(
        ap_preset("User-agent: *\n", url, preset)$url_preprocessing_note,
        NA_character_, info = paste(preset, url)
      )
    }
  }
  # ChatGPT-User's trailing slash is unmeasured too; its query `/` is
  # observed kept (converters/openai.md), so it is not named.
  row <- ap_preset("User-agent: *\n", "/d/?q=/", "chatgpt_user")
  expect_identical(row$matcher_url, "/d/?q=/")
  expect_identical(
    row$url_preprocessing_note,
    "left as given, unmeasured for chatgpt_user: trailing / on a non-root path"
  )
  # Several unmeasured inputs are joined by ", ", the parts by "; ".
  both <- ap_preset("User-agent: *\n", "/a b/%3c\\x/", "claude_user")
  expect_identical(
    both$url_preprocessing_note,
    paste0("percent-escape hex digits uppercased; trailing / removed; ",
           "left as given, unmeasured for claude_user: raw space, backslash")
  )
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
  # `group_token` is the preset's matcher token as the contract spells it.
  own <- ap_text(
    "User-agent: claude-user\nDisallow: /x\n", "/x",
    robots_product_token = "claude-user", preset = "claude_user"
  )
  expect_identical(own$url_decision, "disallow")
  expect_identical(own$group_token, "Claude-User")
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
  # A token of the wrong length, or one that is not ASCII (invalid UTF-8
  # included), is a conflict too, never another error class.
  expect_error(
    robots_evaluate_text_v1(body, c("/x", "/y", "/z"),
                            c("ChatGPT-User", "ChatGPT-User"),
                            preset = "chatgpt_user"),
    class = "robotstxtr_preset_conflict"
  )
  conflict(robots_product_token = "ChatGPT-Usér")
  conflict(robots_product_token = rawToChar(as.raw(c(0x43, 0xff))))
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

# ---- The contract -----------------------------------------------------------

test_that("the contract publishes the presets at the moved revision", {
  v1 <- robots_engine_contract_v1()
  v2 <- robots_engine_contract_v2()
  expect_identical(v1$schema_revision, "2026-11-28.1")
  expect_identical(v2$schema_revision, "2026-11-28.1")
  expect_identical(v1$agent_presets, v2$agent_presets)
  expect_identical(setdiff(names(v2), names(v1)), "matcher_status_set")
  presets <- v1$agent_presets$presets
  expect_identical(presets$preset, c("chatgpt_user", "claude_user"))
  expect_identical(presets$robots_product_token,
                   c("ChatGPT-User", "Claude-User"))
  expect_identical(presets$matcher_token, c("OAI-SearchBot", "Claude-User"))
  expect_identical(presets$group_selection,
                   c("exact_only", "exact_else_wildcard"))
  # The contract's profile selection modes, not the Google crawler modes.
  expect_true(all(
    presets$group_selection %in% supported_profile_selection_modes_v1()
  ))
  expect_identical(presets$robots_policy_ruleset, c("google", "google"))
  expect_identical(presets$matcher_backend, c("google", "google"))
  expect_identical(
    presets$url_steps,
    c("uppercase_escapes",
      "uppercase_escapes, strip_trailing_slash, encode_query_slash")
  )
  expect_identical(presets$body_limit_bytes, c(512000L, 512000L))
  expect_identical(presets$body_limit_source, c("google", "google"))
  # The surface names no date: each behavior carries its own.
  expect_identical(
    presets$surface,
    c("OpenAI Responses API web_search tool",
      "Claude API web_fetch tool (web_fetch_20260309)")
  )
})

test_that("every preset behavior carries a tier and a source", {
  contract <- robots_engine_contract_v1()$agent_presets
  behaviors <- contract$behaviors
  expect_identical(contract$evidence_tiers,
                   c("observed", "inferred", "unmeasured"))
  expect_true(all(behaviors$evidence_tier %in% contract$evidence_tiers))
  expect_true(all(behaviors$preset %in% contract$presets$preset))
  expect_true(all(nzchar(behaviors$source)))
  expect_true(all(nzchar(behaviors$note)))
  expect_false(anyDuplicated(behaviors[c("preset", "behavior")]) > 0L)
  # A source is an agent-view record, or "none" for an unmeasured row
  # that no record measures.
  none <- behaviors$source == "none"
  expect_true(all(grepl("^agent-view(-research)?:", behaviors$source[!none])))
  expect_true(all(behaviors$evidence_tier[none] == "unmeasured"))
  # An observed or inferred row carries the dates its record gives.
  dated <- behaviors$evidence_tier != "unmeasured"
  expect_true(all(grepl(
    "^2026-11-[0-9]{2}( to 2026-11-[0-9]{2})?$", behaviors$measured[dated]
  )))
  expect_true(all(is.na(behaviors$measured[none])))
  # An unmeasured behavior is never modeled.
  expect_false(any(behaviors$modeled & behaviors$evidence_tier == "unmeasured"))
  # The record-keeping rows (review round 1): ChatGPT's query `/` is
  # observed kept, Claude's stored copies are recorded, and the other
  # access paths say what the record has, not "unprobed".
  pick <- function(preset, behavior) {
    behaviors[behaviors$preset == preset & behaviors$behavior == behavior, ]
  }
  query <- pick("chatgpt_user", "query_slash")
  expect_identical(query$evidence_tier, "observed")
  expect_true(query$modeled)
  expect_identical(pick("claude_user", "stored_copy")$evidence_tier,
                   "observed")
  expect_identical(pick("claude_user", "shared_copy")$evidence_tier,
                   "inferred")
  expect_identical(pick("chatgpt_user", "group_binding")$measured,
                   "2026-11-13 to 2026-11-16")
  expect_identical(pick("claude_user", "body_limit")$measured, "2026-11-12")
  for (preset in contract$presets$preset) {
    other <- pick(preset, "other_access_paths")
    expect_match(other$note, "no complete probe matrix", fixed = TRUE)
    expect_false(grepl("unprobed|not measured", other$note))
  }
  # Each URL step a preset applies is a modeled behavior with its tier.
  tier <- function(preset, behavior) {
    behaviors$evidence_tier[
      behaviors$preset == preset & behaviors$behavior == behavior &
        behaviors$modeled
    ]
  }
  for (preset in contract$presets$preset) {
    for (step in agent_preset_url_steps_v1(preset)) {
      expect_length(tier(preset, step), 1L)
    }
  }
  expect_identical(tier("chatgpt_user", "uppercase_escapes"), "inferred")
  expect_identical(tier("claude_user", "uppercase_escapes"), "observed")
  expect_identical(tier("claude_user", "strip_trailing_slash"), "observed")
  expect_identical(tier("claude_user", "encode_query_slash"), "observed")
  # Claude's 500,000-byte refusal is recorded, not modeled.
  cap <- behaviors[behaviors$preset == "claude_user" &
                     behaviors$behavior == "body_limit", ]
  expect_false(cap$modeled)
  expect_match(cap$note, "500,000 bytes refuses the whole host", fixed = TRUE)
  # Each byte class a note can name has an unmeasured row on both presets.
  classes <- c(
    "raw_non_ascii", "raw_space", "control_bytes", "backslash",
    "rfc3986_excluded", "stray_percent", "dot_segments",
    "encoded_dot_segments", "empty_path_segments", "userinfo",
    "status_policy", "brackets_outside_host", "second_hash",
    "encoded_slash_in_path"
  )
  for (preset in contract$presets$preset) {
    rows <- behaviors[behaviors$preset == preset &
                        behaviors$behavior %in% classes, ]
    expect_setequal(rows$behavior, classes)
    expect_true(all(rows$evidence_tier == "unmeasured"), info = preset)
    # No agent-view record measures the round-2 classes.
    added <- rows[rows$behavior %in% c("brackets_outside_host", "second_hash",
                                       "encoded_slash_in_path"), ]
    expect_identical(added$source, rep("none", 3L), info = preset)
  }
  # `measured` (review round 2, m2): dated for every observed or inferred
  # row and for ChatGPT's partly seen trailing slash; NA exactly where the
  # record dates no observation of the row's behavior.
  undated <- c(
    paste0(behaviors$preset, ":", behaviors$behavior)[
      behaviors$source == "none" | grepl("(not run)", behaviors$source,
                                         fixed = TRUE)
    ],
    "claude_user:trailing_slash_before_query",
    "chatgpt_user:other_access_paths", "claude_user:other_access_paths"
  )
  key <- paste0(behaviors$preset, ":", behaviors$behavior)
  expect_setequal(key[is.na(behaviors$measured)], undated)
  expect_identical(pick("chatgpt_user", "trailing_slash")$measured,
                   "2026-11-26")
  # The other access paths name the record each claim lives in (m1).
  expect_match(pick("chatgpt_user", "other_access_paths")$note,
               "Codex are not covered (converters/openai.md", fixed = TRUE)
  expect_match(pick("claude_user", "other_access_paths")$note,
               "access-and-blocklists/claude-blocklist.md", fixed = TRUE)
})

test_that("a named preset value reads as the plain one (review round 2, M1)", {
  body <- "User-agent: Claude-User\nDisallow: /x\n"
  for (url in c("https://e.com/a/?q=1", "https://e.com/d/")) {
    for (preset in c("claude_user", "chatgpt_user")) {
      plain <- ap_preset(body, url, preset)
      named <- ap_preset(body, url, stats::setNames(preset, "p"))
      expect_identical(named, plain, info = paste(preset, url))
    }
  }
  # The case review-2 probed: Claude's own class, not ChatGPT's.
  named <- ap_preset(body, "https://e.com/a/?q=1", c(p = "claude_user"))
  expect_match(named$url_preprocessing_note,
               "trailing / before a query or fragment", fixed = TRUE)
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
  # Another 2xx than 206 reads Google's use_rules cell too.
  local_fake_ssrfr(function(req) {
    fake_response(203L, body = "User-agent: *\nDisallow: /d/\n")
  })
  other <- robots_evaluate_url_v1("http://a/d/x", preset = "claude_user")
  expect_identical(other$results$policy_reason, "http_2xx_use_rules")
  expect_identical(other$results$url_decision, "disallow")
})

test_that("a non-2xx cell is documentation_gap under a preset (fake ssrfr)", {
  for (status in c(206L, 404L, 410L, 429L, 503L)) {
    local_fake_ssrfr(function(req) fake_response(status, body = "x"))
    for (preset in c("chatgpt_user", "claude_user")) {
      x <- robots_evaluate_url_v1("http://a/x", preset = preset)
      row <- x$results
      info <- paste(preset, status)
      expect_identical(row$policy_status, "documentation_gap", info = info)
      expect_identical(row$policy_action, NA_character_, info = info)
      expect_identical(row$policy_reason, "policy_documentation_gap",
                       info = info)
      expect_identical(row$policy_provenance, "documentation_gap",
                       info = info)
      expect_identical(row$policy_source,
                       "design/engine-profiles.md#agent-presets",
                       info = info)
      expect_identical(row$url_decision, NA_character_, info = info)
      # The legacy adapter keeps the row undecided: never Google's
      # missing_allow for a 404 or 410.
      legacy <- as_legacy_robots_decisions_v1(x)$results
      expect_identical(legacy$allowed, NA, info = info)
      expect_identical(legacy$decision_source, "policy_documentation_gap",
                       info = info)
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

test_that("the legacy adapter keeps Google's 404 and 410 without a preset", {
  for (status in c(404L, 410L)) {
    local_fake_ssrfr(function(req) fake_response(status, body = "x"))
    x <- robots_evaluate_url_v1(
      c("http://a/x", "http://a/y"), c("Claude-User", "Googlebot/2.1"),
      "google", "google"
    )
    legacy <- as_legacy_robots_decisions_v1(x)$results
    info <- as.character(status)
    expect_identical(legacy$allowed, c(TRUE, NA), info = info)
    expect_identical(legacy$decision_source,
                     c("missing_allow", "input_unknown"), info = info)
    expect_identical(legacy$matched_rule_type, c("unknown", "unknown"),
                     info = info)
    expect_identical(legacy$http_status, c(status, NA), info = info)
    expect_identical(legacy$fetch_outcome, c("missing", "input_invalid"),
                     info = info)
    # The adapter refuses bing and yandex rows, preset or not.
    for (engine in list(c("bingbot", "bing"), c("Yandex", "yandex"))) {
      other <- robots_evaluate_url_v1(
        "http://a/x", engine[[1L]], engine[[2L]], engine[[2L]]
      )
      expect_error(as_legacy_robots_decisions_v1(other),
                   class = "robotstxtr_incompatible_legacy_adapter")
    }
  }
})
