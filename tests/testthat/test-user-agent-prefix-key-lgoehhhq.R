# ROBO-lgoehhhq: Google's parser reads any key that starts with `user-agent`
# (ASCII case-insensitive) as a User-agent line (`KeyIsUserAgent`,
# src/robots.cc), so `User-agents: *` heads a group for Google. RFC 9309
# defines no such record. The validator warns with
# `accepted_directive_prefix`, naming the key as written and stating
# Google's reading only, then the generic clause about Bing and Yandex. The
# typo forms `useragent` and `user agent` keep `accepted_directive_typo`
# only. Fixtures are synthetic.

ua_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

ua_codes <- function(body) robots_validate_text(body)$diagnostics$code

ua_rows <- function(body) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == "accepted_directive_prefix", , drop = FALSE]
}

ua_others <- "Bing and Yandex may read this line differently."

ua_message <- function(key) {
  paste0(
    "Google reads key `", key, "` as User-agent (prefix match), so for ",
    "Google this line is a User-agent line; RFC 9309 defines no such ",
    "record. ", ua_others
  )
}

# The message's only Bing or Yandex text is the generic clause.
ua_expect_no_claim <- function(message, info = NULL) {
  rest <- sub(ua_others, "", message, fixed = TRUE)
  expect_true(endsWith(message, ua_others), info = info)
  expect_no_match(rest, "Bing|Yandex", info = info)
}

# Google's decision for `token` on `path`, the reading the row states.
ua_google <- function(body, token, path = "/private/x") {
  r <- robots_evaluate_text_v1(body, paste0("https://example.com", path),
                               token, "google", "google")$results
  paste(r$url_decision, r$matched_line)
}

ua_ticket <- ua_lines("User-agents: *", "Disallow: /private/")

# Class 14's keys (design/engine-disagreements.md) and the ticket's.
ua_keys <- c("User-agents", "User-agentfoo", "User-agent-x", "USER-AGENTS")

ua_bare <- function(key) ua_lines(paste0(key, ": *"), "Disallow: /private")
ua_stacked <- function(key) {
  ua_lines("User-agent: bingbot", paste0(key, ": x"), "User-agent: *",
           "Disallow: /private")
}
ua_after_rule <- function(key) {
  ua_lines("User-agent: Yandex", "User-agent: bingbot", "Disallow: /a",
           paste0(key, ": Other"), "Disallow: /private")
}

test_that("the ticket's example warns once on line 1", {
  x <- robots_validate_text(ua_ticket)
  expect_identical(x$documents$validation_status, "warning")
  d <- ua_rows(ua_ticket)
  expect_identical(d$line, 1L)
  expect_identical(d$severity, "warning")
  expect_identical(d$directive, "user-agent")
  expect_identical(d$raw_text, "User-agents: *")
  expect_identical(d$message, ua_message("User-agents"))
  ua_expect_no_claim(d$message)
  # The slash-split row on the same line is unrelated and stays.
  expect_identical(ua_codes(ua_ticket),
                   c("accepted_directive_prefix", "rule_slash_split"))
})

test_that("Google reads the ticket's key as User-agent", {
  expect_identical(ua_google(ua_ticket, "Googlebot"), "disallow 2")
})

test_that("class 14's three shapes warn on the key line", {
  for (key in ua_keys) {
    for (shape in list(list(ua_bare(key), 1L), list(ua_stacked(key), 2L),
                       list(ua_after_rule(key), 4L))) {
      d <- ua_rows(shape[[1L]])
      expect_identical(d$line, shape[[2L]], info = key)
      expect_identical(d$directive, "user-agent", info = key)
      expect_identical(d$message, ua_message(key), info = key)
      expect_identical(ua_codes(shape[[1L]]), "accepted_directive_prefix",
                       info = key)
    }
  }
})

test_that("Google reads each prefix key as a User-agent line", {
  for (key in ua_keys) {
    # Bare: line 2 has the key's group.
    expect_identical(ua_google(ua_bare(key), "Googlebot", "/private"),
                     "disallow 2", info = key)
    # Stacked: the key joins bingbot's run to the `*` line, so line 4 is
    # bingbot's rule.
    expect_identical(ua_google(ua_stacked(key), "bingbot", "/private"),
                     "disallow 4", info = key)
    # After a rule: the key starts an `Other` group, so line 5 leaves the
    # Yandex and bingbot group.
    for (token in c("Yandex", "bingbot")) {
      expect_identical(ua_google(ua_after_rule(key), token, "/private"),
                       "allow NA", info = paste(key, token))
    }
  }
})

test_that("exact User-agent keys and the typo forms draw no prefix row", {
  for (key in c("User-agent", "USER-AGENT", "user-agent", "User-agent ",
                "  User-agent\t")) {
    expect_false("accepted_directive_prefix" %in% ua_codes(ua_bare(key)),
                 label = key)
  }
  expect_identical(ua_codes(ua_lines("User-agent *", "Disallow: /private")),
                   "accepted_missing_colon")
  for (key in c("Useragent", "Useragents", "User agent", "User agents",
                "USERAGENTS")) {
    expect_identical(ua_codes(ua_bare(key)), "accepted_directive_typo",
                     label = key)
  }
})

test_that("a padded prefix key is trimmed to the key", {
  d <- ua_rows(ua_lines("  User-agents \t: *", "Disallow: /private"))
  expect_identical(d$message, ua_message("User-agents"))
})

test_that("a prefix key without a colon warns after accepted_missing_colon", {
  body <- ua_lines("User-agents *", "Disallow: /private")
  expect_identical(ua_codes(body),
                   c("accepted_missing_colon", "accepted_directive_prefix"))
  expect_identical(ua_rows(body)$message, ua_message("User-agents"))
})

test_that("a prefix key hiding a directive draws both rows", {
  body <- ua_lines("User-agents: * Disallow: /x", "Disallow: /y")
  d <- robots_validate_text(body)$diagnostics
  expect_identical(d$code,
                   c("accepted_directive_prefix", "directive_in_value"))
  expect_identical(d$line, c(1L, 1L))
  expect_identical(d$message[[1L]], ua_message("User-agents"))
  # Each row holds one generic clause and no other Bing or Yandex text.
  ua_expect_no_claim(d$message[[1L]])
  hidden <- sub(" Bing and Yandex may read the line differently.", "",
                d$message[[2L]], fixed = TRUE)
  expect_false(identical(hidden, d$message[[2L]]))
  expect_no_match(hidden, "Bing|Yandex")
})

test_that("a prefix key whose value Google cuts draws both rows", {
  body <- ua_lines("User-agents: Foo Bot", "Disallow: /y")
  d <- robots_validate_text(body)$diagnostics
  expect_identical(d$code, c("accepted_directive_prefix", "user_agent_cut"))
  expect_identical(d$line, c(1L, 1L))
  expect_identical(d$message[[1L]], ua_message("User-agents"))
})

test_that("edge inputs around a prefix key keep the row", {
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  # Line 1's BOM is skipped before the key; a plain key after it is silent.
  body <- c(bom, charToRaw("User-agents: *\nDisallow: /private\n"))
  expect_identical(ua_codes(body),
                   c("byte_order_mark", "accepted_directive_prefix"))
  expect_identical(ua_rows(body)$message, ua_message("User-agents"))
  expect_identical(
    ua_codes(c(bom, charToRaw("User-agent: *\nDisallow: /private\n"))),
    "byte_order_mark"
  )
  # A NUL after the key: the key is found before it.
  body <- c(charToRaw("User-agents: x"), as.raw(0),
            charToRaw("y\nDisallow: /private\n"))
  expect_identical(ua_codes(body), c("nul_byte", "accepted_directive_prefix",
                                     "rules_after_nul_removal"))
  expect_identical(ua_rows(body)$message, ua_message("User-agents"))
  # An oversized value leaves the key alone.
  body <- ua_lines(paste0("User-agents: ", strrep("a", 16700L)),
                   "Disallow: /private")
  expect_identical(ua_codes(body),
                   c("line_too_long", "accepted_directive_prefix"))
  # CR-only endings are Google's line breaks.
  body <- "User-agents: *\rDisallow: /private\r"
  expect_identical(ua_rows(body)$line, 1L)
  expect_identical(ua_google(body, "Googlebot", "/private"), "disallow 2")
  # Invalid UTF-8 in the value: the key is still ASCII.
  body <- c(charToRaw("User-agents: Bot"), as.raw(0xff),
            charToRaw("\nDisallow: /private\n"))
  expect_identical(ua_codes(body), c("invalid_utf8",
                                     "accepted_directive_prefix",
                                     "user_agent_cut"))
  expect_identical(ua_rows(body)$message, ua_message("User-agents"))
})

test_that("the Allow and Disallow prefix rows make no Bing or Yandex claim", {
  for (rule in c("DisallowAITraining: /", "AllowAITraining: /x")) {
    d <- ua_rows(ua_lines("User-agent: *", rule))
    expect_no_match(d$message, "Bing and Yandex ignore", label = rule)
    rest <- sub(ua_others, "", d$message, fixed = TRUE)
    expect_false(identical(rest, d$message), label = rule)
    expect_no_match(rest, "Bing|Yandex", label = rule)
  }
})

for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("the User-agent key fold is ASCII-only under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    expect_identical(ua_codes(ua_bare("USER-AGENTS")),
                     "accepted_directive_prefix")
    expect_identical(ua_codes(ua_bare("USER-AGENT")), character())
    expect_identical(ua_codes(ua_bare("user-agent")), character())
  })
}
