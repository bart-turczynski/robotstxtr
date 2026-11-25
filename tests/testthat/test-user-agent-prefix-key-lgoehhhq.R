# ROBO-lgoehhhq: Google's parser reads any key that starts with `user-agent`
# (ASCII case-insensitive) as a User-agent line (`KeyIsUserAgent`,
# src/robots.cc), so `User-agents: *` heads a group for Google. RFC 9309
# defines no such record. The typo forms `useragent` and `user agent` keep
# `accepted_directive_typo` only. Fixtures are synthetic.

ua_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

ua_codes <- function(body) robots_validate_text(body)$diagnostics$code

ua_rows <- function(body) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == "accepted_directive_prefix", , drop = FALSE]
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

test_that("the ticket's example draws no prefix row today", {
  expect_identical(nrow(ua_rows(ua_ticket)), 0L)
  expect_identical(ua_codes(ua_ticket), "rule_slash_split")
})

test_that("Google reads the ticket's key as User-agent", {
  expect_identical(ua_google(ua_ticket, "Googlebot"), "disallow 2")
})

test_that("class 14's three shapes draw no prefix row today", {
  for (key in ua_keys) {
    expect_identical(nrow(ua_rows(ua_bare(key))), 0L, info = key)
    expect_identical(nrow(ua_rows(ua_stacked(key))), 0L, info = key)
    expect_identical(nrow(ua_rows(ua_after_rule(key))), 0L, info = key)
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

test_that("a prefix key without a colon draws accepted_missing_colon only", {
  expect_identical(ua_codes(ua_lines("User-agents *", "Disallow: /private")),
                   "accepted_missing_colon")
})

test_that("a prefix key hiding a directive draws directive_in_value only", {
  body <- ua_lines("User-agents: * Disallow: /x", "Disallow: /y")
  d <- robots_validate_text(body)$diagnostics
  expect_identical(d$code, "directive_in_value")
  expect_identical(d$line, 1L)
})

test_that("a prefix key whose value Google cuts draws user_agent_cut only", {
  body <- ua_lines("User-agents: Foo Bot", "Disallow: /y")
  d <- robots_validate_text(body)$diagnostics
  expect_identical(d$code, "user_agent_cut")
  expect_identical(d$line, 1L)
})

test_that("edge inputs around a prefix key draw no prefix row today", {
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  expect_identical(
    ua_codes(c(bom, charToRaw("User-agents: *\nDisallow: /private\n"))),
    "byte_order_mark"
  )
  expect_identical(
    ua_codes(c(charToRaw("User-agents: x"), as.raw(0),
               charToRaw("y\nDisallow: /private\n"))),
    c("nul_byte", "rules_after_nul_removal")
  )
  expect_identical(
    ua_codes(ua_lines(paste0("User-agents: ", strrep("a", 16700L)),
                      "Disallow: /private")),
    "line_too_long"
  )
  expect_identical(ua_codes("User-agents: *\rDisallow: /private\r"),
                   character())
  expect_identical(
    ua_codes(c(charToRaw("User-agents: Bot"), as.raw(0xff),
               charToRaw("\nDisallow: /private\n"))),
    c("invalid_utf8", "user_agent_cut")
  )
})

for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("the User-agent key fold is ASCII-only under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    expect_identical(ua_codes(ua_bare("USER-AGENTS")), character())
    expect_identical(ua_codes(ua_bare("USER-AGENT")), character())
    expect_identical(ua_codes(ua_bare("user-agent")), character())
  })
}
