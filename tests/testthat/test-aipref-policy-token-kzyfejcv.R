# ROBO-kzyfejcv: draft-kelley-aipref-training-preference-signal-00 (an
# Internet-Draft dated 2026-10-30) keys an AI-training preference on the
# policy token `__usage_ai-training` in a User-agent line, matched exactly
# apart from case, and a `User-agent: *` group never applies to it. The
# validator recognizes the token (ai_training_preference), warns on near
# misses, on lines the token group cannot use and on a token line stacked
# onto another crawler's group, and drops the token from
# wildcard_rules_not_inherited. Vendor statements on the token:
# design/engine-profiles.md section 7a. All fixtures are synthesized on
# example.com.

ai_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

ai_diags <- function(body) robots_validate_text(body)$diagnostics

ai_rows <- function(body, code) {
  d <- ai_diags(body)
  d[d$code == code, , drop = FALSE]
}

ai_new_codes <- function(d) d$code[startsWith(d$code, "ai_training_")]

ai_exempt <- ai_lines(
  "User-agent: *", "Disallow: /private", "",
  "User-agent: __usage_ai-training", "Disallow: /", "Allow: /press-kit/"
)

ai_stacked <- ai_lines(
  "User-agent: *", "Content-Signal: ai-train=no",
  "User-agent: __usage_ai-training", "Disallow: /"
)

test_that("a token group draws the info and no wildcard info", {
  x <- robots_validate_text(ai_exempt)
  d <- x$diagnostics
  expect_identical(d$code, "ai_training_preference")
  expect_identical(d$severity, "info")
  expect_identical(d$line, 4L)
  expect_identical(d$directive, "user-agent")
  expect_identical(d$raw_text, "User-agent: __usage_ai-training")
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(d$message, paste0(
    "`User-agent: __usage_ai-training` states an AI-training preference ",
    "(draft-kelley-aipref-training-preference-signal-00, an Internet-Draft): ",
    "a disallowed path is a preference against training on it, an allowed ",
    "one a preference for it. This group's rules: Disallow: / (line 5), ",
    "Allow: /press-kit/ (line 6). `User-agent: *` rules never apply to the ",
    "token."
  ))
})

test_that("a named crawler beside the token keeps its wildcard info", {
  d <- ai_diags(ai_lines(
    "User-agent: *", "Disallow: /private", "",
    "User-agent: GPTBot", "User-agent: __usage_ai-training", "Disallow: /"
  ))
  expect_identical(d$code,
                   c("ai_training_preference", "wildcard_rules_not_inherited"))
  expect_identical(d$line, c(5L, 4L))
  expect_match(d$message[[2L]], "^GPTBot obeys only this group")
  expect_no_match(d$message[[2L]], "__usage", fixed = TRUE)
})

test_that("the info lists the group's own rules only, never the * rules", {
  d <- ai_rows(ai_lines(
    "User-agent: __usage_ai-training", "Disallow: /drafts/", "Disallow:",
    "User-agent: *", "Disallow: /private"
  ), "ai_training_preference")
  expect_identical(d$line, 1L)
  expect_match(d$message, paste0(
    "This group's rules: Disallow: /drafts/ (line 2), ",
    "Disallow: (empty; no restriction) (line 3)."
  ), fixed = TRUE)
  expect_no_match(d$message, "/private", fixed = TRUE)
  d <- ai_rows(ai_lines("User-agent: __usage_ai-training", "Allow:",
                        "Disallow: /x"), "ai_training_preference")
  expect_match(d$message, "Allow: (empty; ignored) (line 2), Disallow: /x",
               fixed = TRUE)
  d <- ai_rows(ai_lines("User-agent: __usage_ai-training"),
               "ai_training_preference")
  expect_match(d$message, "This group has no Allow or Disallow rule.",
               fixed = TRUE)
  rules <- sprintf("Disallow: /p%d", 1:12)
  d <- ai_rows(ai_lines("User-agent: __usage_ai-training", rules),
               "ai_training_preference")
  expect_match(d$message, "Disallow: /p10 (line 11), and 2 more.",
               fixed = TRUE)
})

test_that("each group naming the token gets one info, on its first line", {
  d <- ai_rows(ai_lines(
    "User-agent: __usage_ai-training", "User-agent: __USAGE_AI-TRAINING",
    "Disallow: /a", "User-agent: __usage_ai-training", "Disallow: /b"
  ), "ai_training_preference")
  expect_identical(d$line, c(1L, 4L))
  expect_match(d$message[[1L]], paste0(
    "never apply to the token. Groups naming the token merge (also see ",
    "line 4)."
  ), fixed = TRUE)
  expect_match(d$message[[2L]], "(also see line 1).", fixed = TRUE)
  d <- ai_rows(ai_lines(
    "User-agent: __usage_ai-training", "Disallow: /a",
    "User-agent: __usage_ai-training", "Disallow: /b",
    "User-agent: __usage_ai-training", "Disallow: /c"
  ), "ai_training_preference")
  expect_match(d$message[[2L]], "(also see lines 1, 5).", fixed = TRUE)
  d <- ai_rows(ai_exempt, "ai_training_preference")
  expect_no_match(d$message, "also see", fixed = TRUE)
})

test_that("the token is matched apart from ASCII case only", {
  for (value in c("__USAGE_AI-TRAINING", "__Usage_AI-Training")) {
    d <- ai_diags(ai_lines("User-agent: *", "Disallow: /private",
                           paste("User-agent:", value), "Disallow: /"))
    expect_identical(d$code, "ai_training_preference", info = value)
  }
})

for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("the token is recognized the same under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    d <- ai_diags(ai_lines("User-agent: *", "Disallow: /private",
                           "User-agent: __USAGE_AI-TRAINING", "Disallow: /"))
    expect_identical(d$code, "ai_training_preference")
  })
}

test_that("the token draws no user_agent_cut", {
  for (value in c("__usage_ai-training", "__USAGE_AI-Training",
                  "__usage_ai-training   # trailing comment")) {
    codes <- ai_diags(ai_lines(paste("User-agent:", value),
                               "Disallow: /"))$code
    expect_identical(codes, "ai_training_preference", info = value)
  }
})

test_that("each near miss draws one warning and no info", {
  for (value in c("__usage_ai_training", "usage_ai-training",
                  "__usage-ai-training", "__USAGE-AI_TRAINING")) {
    x <- robots_validate_text(ai_lines(paste("User-agent:", value),
                                       "Disallow: /"))
    d <- x$diagnostics
    expect_identical(d$code, "ai_training_token_near_miss", info = value)
    expect_identical(d$severity, "warning", info = value)
    expect_identical(d$line, 1L, info = value)
    expect_identical(x$documents$validation_status, "warning")
    expect_match(d$message, paste0(
      "is not the AI-training policy token `__usage_ai-training`, which ",
      "matches only exactly, apart from ASCII case ",
      "(draft-kelley-aipref-training-preference-signal-00, an ",
      "Internet-Draft)"
    ), fixed = TRUE, info = value)
    expect_no_match(d$message, "still reads", fixed = TRUE, info = value)
  }
})

test_that("a token with a suffix is a near miss that Google still reads", {
  for (value in c("__usage_ai-training/1.0", "__usage_ai-training x")) {
    d <- ai_diags(ai_lines("User-agent: *", "Disallow: /private",
                           paste("User-agent:", value), "Disallow: /"))
    expect_identical(d$code,
                     c("user_agent_cut", "ai_training_token_near_miss"),
                     info = value)
    expect_identical(d$line, c(3L, 3L), info = value)
    expect_match(d$message[[2L]],
                 "Google's matcher still reads it as `__usage_ai-training`.",
                 fixed = TRUE, info = value)
  }
})

test_that("a value that only starts with the token is not the token", {
  # Neither exact nor a near miss: an unknown crawler name.
  d <- ai_diags(ai_lines("User-agent: __usage_ai-trainingx", "Disallow: /"))
  expect_identical(nrow(d), 0L)
  d <- ai_diags(ai_lines("User-agent: __usage_ai-training-extra",
                         "Disallow: /"))
  expect_identical(nrow(d), 0L)
})

test_that("non-ASCII or invalid UTF-8 values draw no near miss", {
  latin1 <- c(charToRaw("User-agent: __usage"), as.raw(0xe9),
              charToRaw("ai-training\nDisallow: /\n"))
  d <- robots_validate_text(latin1)$diagnostics
  expect_identical(d$code, c("invalid_utf8", "user_agent_cut"))
  utf8 <- ai_lines("User-agent: __usage_aï-training", "Disallow: /")
  expect_identical(ai_new_codes(ai_diags(utf8)), character())
})

ai_extra_message <- paste0(
  "Line has no defined meaning in a group that names only the AI-training ",
  "policy token `__usage_ai-training`: ",
  "draft-kelley-aipref-training-preference-signal-00 (an Internet-Draft) ",
  "adds no directive and keeps RFC 9309's group structure, so only Allow ",
  "and Disallow state the preference."
)

test_that("a token-only group warns on each line it cannot use", {
  d <- ai_diags(ai_lines(
    "User-agent: __usage_ai-training", "Crawl-delay: 5", "Foo: bar",
    "Sitemap: https://example.com/sitemap.xml",
    "Content-Signal: ai-train=no", "Host: example.com", "Clean-param: ref",
    "Disallow: /", "Allow: /press-kit/"
  ))
  extra <- d[d$code == "ai_training_group_extra_line", , drop = FALSE]
  expect_identical(extra$line, c(2L, 3L, 5L))
  expect_identical(extra$directive, c("crawl-delay", "foo", "content-signal"))
  expect_identical(unique(extra$severity), "warning")
  expect_identical(unique(extra$message), ai_extra_message)
  # The per-line codes stay.
  per_line <- d$line %in% c(2L, 3L, 5L) &
    d$code != "ai_training_group_extra_line"
  expect_identical(
    d$code[per_line],
    c("unsupported_directive", "unknown_directive", "content_signal_directive")
  )
})

test_that("a line that may head the next group draws no extra-line", {
  # Trailing file-level lines stay silent; at the end of the file nothing
  # follows, so a Crawl-delay there is the token group's.
  d <- ai_diags(ai_lines(
    "User-agent: __usage_ai-training", "Disallow: /",
    "Host: example.com", "Clean-param: ref", "Crawl-delay: 5"
  ))
  expect_identical(d$line[d$code == "ai_training_group_extra_line"], 5L)
  d <- ai_diags(ai_lines(
    "User-agent: __usage_ai-training", "Disallow: /",
    "Content-Signal: ai-train=no", "User-agent: *", "Allow: /"
  ))
  expect_identical(ai_new_codes(d), "ai_training_preference")
  d <- ai_diags(ai_lines(
    "User-agent: __usage_ai-training", "Disallow: /", "",
    "Content-Signal: ai-train=no", "User-agent: *", "Allow: /"
  ))
  expect_identical(ai_new_codes(d), "ai_training_preference")
  # A rule-less token group is the last group: its lines are its own.
  d <- ai_diags(ai_lines("User-agent: __usage_ai-training", "Crawl-delay: 5"))
  expect_identical(d$line[d$code == "ai_training_group_extra_line"], 2L)
  # A trailing line before a later group's User-agent line may head it.
  d <- ai_diags(ai_lines(
    "User-agent: __usage_ai-training", "Disallow: /", "Crawl-delay: 5",
    "User-agent: GPTBot", "Disallow: /x"
  ))
  expect_identical(ai_new_codes(d), "ai_training_preference")
})

test_that("a value Google reads as the token keeps a group token-only", {
  d <- ai_diags(ai_lines(
    "User-agent: __usage_ai-training", "User-agent: __usage_ai-training/1.0",
    "Crawl-delay: 5", "Disallow: /"
  ))
  expect_identical(d$line[d$code == "ai_training_group_extra_line"], 3L)
})

test_that("lines outside a token-only group draw no extra-line warning", {
  d <- ai_diags(ai_lines(
    "Crawl-delay: 1",
    "User-agent: GPTBot", "Crawl-delay: 2", "Disallow: /x",
    "User-agent: __usage_ai-training", "User-agent: Foo", "Crawl-delay: 3",
    "Disallow: /",
    "User-agent: __usage_ai-training", "Disallow: /",
    "User-agent: Bar", "Crawl-delay: 4", "Disallow: /y"
  ))
  expect_identical(ai_new_codes(d),
                   c("ai_training_preference", "ai_training_preference"))
})

test_that("a line before the first group is in no group", {
  d <- ai_diags(ai_lines(
    "Crawl-delay: 1", "User-agent: __usage_ai-training", "Disallow: /",
    "User-agent: GPTBot", "Crawl-delay: 2", "Disallow: /x"
  ))
  expect_identical(ai_new_codes(d), "ai_training_preference")
  d <- ai_diags(ai_lines(
    "Crawl-delay: 1", "User-agent: __usage_ai-training", "Crawl-delay: 9",
    "Disallow: /"
  ))
  expect_identical(d$line[d$code == "ai_training_group_extra_line"], 3L)
})

test_that("a User-agent line naming no crawler keeps a group token-only", {
  for (agent in c("User-agent:", "User-agent: 123bot")) {
    d <- ai_rows(ai_lines("User-agent: __usage_ai-training", agent,
                          "Crawl-delay: 5", "Disallow: /"),
                 "ai_training_group_extra_line")
    expect_identical(d$line, 3L, info = agent)
  }
})

test_that("the issue's stacked shape warns on the token line", {
  x <- robots_validate_text(ai_stacked)
  d <- x$diagnostics
  expect_identical(
    d$code,
    c("content_signal_directive", "ai_training_token_stacked",
      "ai_training_preference")
  )
  expect_identical(d$line, c(2L, 3L, 3L))
  expect_identical(x$documents$validation_status, "warning")
  expect_identical(d$message[[2L]], paste0(
    "`User-agent: __usage_ai-training` shares a group with ",
    "`User-agent: *` (line 1): Google's and Yandex's parsers join ",
    "User-agent lines that no Allow or Disallow line separates, so this ",
    "group's rules also apply to every crawler no group names. Bing's ",
    "parser ends the group at the directive line between the two. Give the ",
    "policy token a separate group, after a group that ends in an Allow or ",
    "Disallow line."
  ))
  # Nothing but blank lines between: Bing joins the lines too.
  d <- ai_rows(ai_lines("User-agent: *", "", "User-agent: __usage_ai-training",
                        "Disallow: /"), "ai_training_token_stacked")
  expect_match(d$message, paste0(
    "every crawler no group names. Bing's parser joins them too. Give"
  ), fixed = TRUE)
  # Why: under Google the token's Disallow reaches every crawler.
  r <- allowed_by_robots_text(ai_stacked, "https://example.com/a",
                              "Googlebot")$results
  expect_false(r$allowed)
})

test_that("every class 1b fixture warns on its token line", {
  # design/engine-disagreements.md class 1b, all three fixtures.
  for (between in list(
    c("Content-Signal: ai-train=no",
      "Sitemap: https://example.com/sitemap.xml", "", ""),
    c("Content-Signal: ai-train=no", "", ""),
    c("", "")
  )) {
    body <- ai_lines("User-agent: *", between,
                     "User-agent: __usage_ai-training", "Disallow: /")
    d <- ai_rows(body, "ai_training_token_stacked")
    expect_identical(d$line, length(between) + 2L, info = body)
  }
})

test_that("User-agent lines a blank or comment separates stay silent", {
  for (body in list(
    ai_lines("User-agent: GPTBot", "User-agent: __usage_ai-training",
             "Disallow: /"),
    ai_lines("User-agent: __usage_ai-training", "User-agent: GPTBot",
             "Disallow: /"),
    ai_lines("User-agent: GPTBot", "", "User-agent: __usage_ai-training",
             "Disallow: /"),
    # The comment-headed per-vendor layout.
    ai_lines("User-agent: *", "Disallow: /private", "",
             "# OpenAI", "User-agent: GPTBot", "",
             "# AI training preference (aipref draft)",
             "User-agent: __usage_ai-training", "", "# Rules",
             "Disallow: /")
  )) {
    expect_false("ai_training_token_stacked" %in% ai_diags(body)$code,
                 info = body)
  }
})

test_that("a named crawler with a directive between it and the token warns", {
  for (between in c("Crawl-delay: 5",
                    "Sitemap: https://example.com/sitemap.xml",
                    "Foo: bar")) {
    d <- ai_rows(ai_lines("User-agent: GPTBot", "", between, "# c",
                          "User-agent: __usage_ai-training", "Disallow: /"),
                 "ai_training_token_stacked")
    expect_identical(d$line, 5L, info = between)
    expect_match(d$message, paste0(
      "shares a group with `User-agent: GPTBot` (line 1)"
    ), fixed = TRUE, info = between)
    expect_match(d$message, paste0(
      "also apply to GPTBot. Bing's parser ends the group at the directive ",
      "line between the two."
    ), fixed = TRUE, info = between)
  }
  # After the token too, and the nearest crawler is named.
  d <- ai_rows(ai_lines("User-agent: FarBot", "Crawl-delay: 1",
                        "User-agent: __usage_ai-training", "Crawl-delay: 2",
                        "User-agent: NearBot", "Disallow: /"),
               "ai_training_token_stacked")
  expect_identical(d$line, 3L)
  expect_match(d$message, "`User-agent: FarBot` (line 1)", fixed = TRUE)
  d <- ai_rows(ai_lines("User-agent: __usage_ai-training", "Crawl-delay: 1",
                        "User-agent: GPTBot", "Disallow: /"),
               "ai_training_token_stacked")
  expect_identical(d$line, 1L)
  expect_match(d$message, "`User-agent: GPTBot` (line 3)", fixed = TRUE)
  d <- ai_rows(ai_lines("User-agent: FarBot", "Crawl-delay: 1",
                        "User-agent: CloseBot", "Crawl-delay: 2",
                        "User-agent: __usage_ai-training", "Crawl-delay: 3",
                        "User-agent: AfterBot", "Disallow: /"),
               "ai_training_token_stacked")
  expect_match(d$message, "`User-agent: CloseBot` (line 3)", fixed = TRUE)
})

test_that("a * line is named before any crawler", {
  d <- ai_rows(ai_lines("User-agent: GPTBot", "",
                        "User-agent: __usage_ai-training", "User-agent: *",
                        "Disallow: /"), "ai_training_token_stacked")
  expect_identical(d$line, 3L)
  expect_match(d$message, paste0(
    "^`User-agent: __usage_ai-training` shares a group with ",
    "`User-agent: \\*` \\(line 4\\): .* also apply to every crawler no ",
    "group names\\."
  ))
  d <- ai_rows(ai_lines("User-agent: GPTBot", "Crawl-delay: 5",
                        "User-agent: __usage_ai-training", "User-agent: *",
                        "Disallow: /"), "ai_training_token_stacked")
  expect_match(d$message, "shares a group with `User-agent: *` (line 4)",
               fixed = TRUE)
})

test_that("a User-agent line naming no crawler is never named", {
  for (agent in c("User-agent:", "User-agent: 123bot")) {
    d <- ai_diags(ai_lines(agent, "Crawl-delay: 5",
                           "User-agent: __usage_ai-training", "Disallow: /"))
    expect_false("ai_training_token_stacked" %in% d$code, info = agent)
  }
})

test_that("a * line in the token's group warns even with nothing between", {
  for (body in list(
    ai_lines("User-agent: *", "User-agent: __usage_ai-training",
             "Disallow: /"),
    ai_lines("User-agent: __usage_ai-training", "User-agent: GPTBot",
             "User-agent: *", "Disallow: /")
  )) {
    d <- ai_rows(body, "ai_training_token_stacked")
    expect_identical(nrow(d), 1L, info = body)
    expect_match(d$message, "shares a group with `User-agent: *`",
                 fixed = TRUE, info = body)
  }
})

test_that("the stacked warning is keyed on the __usage_ prefix", {
  d <- ai_diags(ai_lines("User-agent: *", "User-agent: __usage_ai_training",
                         "Disallow: /"))
  expect_identical(
    d$code, c("ai_training_token_near_miss", "ai_training_token_stacked")
  )
  d <- ai_rows(ai_lines("User-agent: *", "User-agent: __usage_search",
                        "Disallow: /"), "ai_training_token_stacked")
  expect_match(d$message, "^`User-agent: __usage_search` shares a group")
  # Two policy tokens a directive separates merge under Google and Yandex,
  # so each is stacked onto the other.
  d <- ai_rows(ai_lines("User-agent: __usage_search", "Crawl-delay: 5",
                        "User-agent: __usage_ai-training", "Disallow: /"),
               "ai_training_token_stacked")
  expect_identical(d$line, c(1L, 3L))
  expect_match(d$message[[1L]], paste0(
    "`User-agent: __usage_search` shares a group with ",
    "`User-agent: __usage_ai-training` (line 3)"
  ), fixed = TRUE)
  expect_match(d$message[[2L]],
               "shares a group with `User-agent: __usage_search` (line 1)",
               fixed = TRUE)
  # Consecutive, they share a group by choice.
  d <- ai_diags(ai_lines("User-agent: __usage_search",
                         "User-agent: __usage_ai-training", "Disallow: /"))
  expect_identical(ai_new_codes(d), "ai_training_preference")
})

test_that("the same token repeated across a directive is not stacking", {
  d <- ai_diags(ai_lines("User-agent: __usage_ai-training", "Crawl-delay: 5",
                         "User-agent: __USAGE_AI-TRAINING", "Disallow: /"))
  expect_false("ai_training_token_stacked" %in% d$code)
  # A repeat is skipped when naming the nearest crawler.
  d <- ai_rows(ai_lines("User-agent: GPTBot", "Crawl-delay: 1",
                        "User-agent: __usage_ai-training", "Crawl-delay: 2",
                        "User-agent: __usage_ai-training", "Crawl-delay: 3",
                        "User-agent: ClaudeBot", "Crawl-delay: 4",
                        "User-agent: __usage_ai-training", "Disallow: /"),
               "ai_training_token_stacked")
  expect_identical(d$line, c(3L, 5L, 9L))
  expect_match(d$message[[1L]], "`User-agent: GPTBot` (line 1)", fixed = TRUE)
  expect_match(d$message[[2L]], "`User-agent: ClaudeBot` (line 7)",
               fixed = TRUE)
  expect_match(d$message[[3L]], "`User-agent: ClaudeBot` (line 7)",
               fixed = TRUE)
})

test_that("a near miss without the __usage_ prefix is a policy token too", {
  # Stacked under GPTBot it warns, and it is never named as a crawler.
  d <- ai_rows(ai_lines("User-agent: GPTBot", "Crawl-delay: 5",
                        "User-agent: usage_ai-training", "Disallow: /"),
               "ai_training_token_stacked")
  expect_identical(d$line, 3L)
  expect_match(d$message, "^`User-agent: usage_ai-training` shares a group")
  d <- ai_diags(ai_lines("User-agent: usage_ai-training", "Crawl-delay: 5",
                         "User-agent: __usage_ai-training", "Disallow: /"))
  expect_false("ai_training_token_stacked" %in% d$code)
})

test_that("a file without the token draws no new code", {
  bodies <- list(
    ai_lines("User-agent: *", "Disallow: /private", "User-agent: b",
             "Disallow: /x"),
    ai_lines("User-agent: GPTBot", "Crawl-delay: 5", "User-agent: Foo",
             "Disallow: /"),
    ai_lines("User-agent: *", "Content-Signal: ai-train=no", "Disallow: /x"),
    ""
  )
  for (body in bodies) {
    expect_identical(ai_new_codes(ai_diags(body)), character(), info = body)
  }
})

test_that("a body with a NUL gets no AI-training code", {
  body <- c(charToRaw(paste0(
    "User-agent: *\nContent-Signal: x\nUser-agent: __usage_ai_training\n",
    "Crawl-delay: 5\nUser-agent: __usage_ai-training\nDisallow: /"
  )), as.raw(0), charToRaw("a\n"))
  d <- robots_validate_text(body)$diagnostics
  expect_true("nul_byte" %in% d$code)
  expect_identical(ai_new_codes(d), character())
})

test_that("a cut body keeps every check and says the info may be partial", {
  body <- ai_lines(
    "User-agent: *", "User-agent: __usage_ai_training", "Disallow: /x",
    "User-agent: __usage_ai-training", "Crawl-delay: 5", "Disallow: /"
  )
  x <- validate_document_bytes(charToRaw(body), "s", "supplied",
                               max_bytes = 200L, body_truncated = TRUE)
  d <- x$diagnostics
  expect_identical(
    ai_new_codes(d),
    c("ai_training_token_near_miss", "ai_training_token_stacked",
      "ai_training_preference", "ai_training_group_extra_line")
  )
  info <- d[d$code == "ai_training_preference", , drop = FALSE]
  expect_match(info$message, "Lines past the max_bytes cut were not read.",
               fixed = TRUE)
  d <- robots_validate_text(body)$diagnostics
  expect_no_match(d$message[d$code == "ai_training_preference"],
                  "max_bytes", fixed = TRUE)
  plain <- ai_lines("User-agent: *", "Disallow: /x")
  x <- validate_document_bytes(charToRaw(plain), "s", "supplied",
                               max_bytes = 200L,
                               body_truncated = TRUE)
  expect_identical(x$diagnostics$code, "body_truncated")
})

test_that("a group of thousands of agents is checked in one pass", {
  skip_on_cran()
  agents <- paste0("User-agent: Bot-", outer(letters, LETTERS, paste0))
  agents <- rep(agents, 5L)
  body <- ai_lines("User-agent: *", "Content-Signal: x", agents,
                   "User-agent: __usage_ai-training", "Disallow: /")
  elapsed <- system.time(d <- ai_diags(body))[["elapsed"]]
  expect_identical(
    ai_new_codes(d), c("ai_training_token_stacked", "ai_training_preference")
  )
  expect_lt(elapsed, 30)
})

test_that("the stacked check is linear: 4000 crawlers and 4000 tokens", {
  skip_on_cran()
  # A pair table here is 16 million rows; the check must stay linear.
  named <- rep(paste0("User-agent: Bot-", outer(letters, LETTERS, paste0)),
               length.out = 4000L)
  body <- ai_lines(named, "Crawl-delay: 5",
                   rep("User-agent: __usage_ai-training", 4000L),
                   "Disallow: /")
  elapsed <- system.time(d <- ai_diags(body))[["elapsed"]]
  stacked <- d[d$code == "ai_training_token_stacked", , drop = FALSE]
  expect_identical(nrow(stacked), 4000L)
  expect_identical(stacked$line, 4002:8001)
  expect_match(stacked$message[[1L]], "`User-agent: Bot-",
               fixed = TRUE)
  expect_lt(elapsed, 30)
})

test_that("the info names at most three other token groups", {
  body <- ai_lines(rep(c("User-agent: __usage_ai-training", "Disallow: /"),
                       5L))
  d <- ai_rows(body, "ai_training_preference")
  expect_identical(d$line, c(1L, 3L, 5L, 7L, 9L))
  expect_match(d$message[[1L]],
               "(also see lines 3, 5, 7, and 1 more).", fixed = TRUE)
  expect_match(d$message[[5L]],
               "(also see lines 1, 3, 5, and 1 more).", fixed = TRUE)
  d <- ai_rows(ai_lines(rep(c("User-agent: __usage_ai-training",
                              "Disallow: /"), 4L)), "ai_training_preference")
  expect_match(d$message[[2L]], "(also see lines 1, 5, 7).", fixed = TRUE)
})

test_that("info messages grow linearly with the number of token groups", {
  # Each info names at most three others, so the total text per group is
  # bounded however many groups repeat the token.
  for (n in c(10L, 3000L)) {
    body <- ai_lines(rep(c("User-agent: __usage_ai-training", "Disallow: /"),
                         n))
    d <- ai_rows(body, "ai_training_preference")
    expect_identical(nrow(d), n)
    expect_lt(max(nchar(d$message)), 500)
    expect_lt(sum(nchar(d$message)), 500 * n)
  }
})
