# ROBO-vnhirero: a crawler named in two or more groups follows all of them
# merged. Google merges them (src/robots.cc; RFC 9309 section 2.2.1), and so
# do Bing (tester, bing-corpus `body-sel-bingbot-repeated-tier`) and Yandex
# (tester, yandex-corpus ydx-02). When a crawler's rules hold an empty
# `Disallow:` and a full block (`Disallow: /`), the engines answer opposite
# ways: Google ignores the empty value and Bing does too (tester,
# bing-corpus `body-ea-bingbot-empty-disallow-before-rule`), so both block,
# while Yandex reads it as allowing every path (tester, ydx-11). An
# every-path Allow with `Disallow: /` is no such split: all three allow. The
# shapes come from news-ai-access's stored files (NEWS-caacyart):
# jornaldiabo.com and timeschronicle.ca, quoted line for line.

rg_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

rg_rows <- function(body, code) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == code, , drop = FALSE]
}

rg_answer <- function(body, backend, token) {
  robots_evaluate_text_v1(body, "https://example.com/x", token,
                          "assumed_rfc9309", backend)$results$url_decision
}

rg_jornaldiabo <- rg_lines(
  "# START YOAST BLOCK", "# ---------------------------",
  "User-agent: *", "Disallow:", "",
  "Sitemap: https://jornaldiabo.com/sitemap_index.xml",
  "# ---------------------------", "# END YOAST BLOCK", "", "",
  "User-agent: *", "Disallow: /", "",
  "User-agent: bingbot", "Allow: /", "",
  "User-agent: Applebot", "Allow: /", "",
  "User-agent: Googlebot", "Allow: /", "",
  "User-agent: sentibot", "Disallow: /"
)

# The head of timeschronicle.ca and its DotBot pair. For Google, line 16
# joins line 13's group (a Crawl-delay ends no group), and line 23 joins
# line 20's (ROBO-xepnhfgs), so the later `*` groups open on lines 13 and 20.
rg_timeschronicle <- rg_lines(
  "User-agent: *", "Disallow: /wp-admin/",
  "Allow: /wp-admin/admin-ajax.php", "",
  "# GoogleBot", "User-agent: Googlebot", "Allow: /", "",
  "User-agent: Twitterbot", "Allow: /", "",
  "# Slow down bots", "User-agent: *", "Crawl-delay: 10", "",
  "User-agent: *", "Disallow: /?blackhole", "",
  "# Slow down bots", "User-agent: *", "Crawl-delay: 10", "",
  "User-agent: OAI-SearchBot", "Disallow: /", "",
  "# http://www.opensiteexplorer.org/dotbot",
  "User-agent: DotBot", "Disallow: /", "User-agent: dotbot", "Disallow: /"
)

rg_control <- rg_lines(
  "User-agent: *", "Disallow:", "",
  "User-agent: FooBot", "Disallow: /", "",
  "User-agent: BarBot", "Allow: /"
)

test_that("jornaldiabo.com: the second `*` group is reported as merged", {
  r <- rg_rows(rg_jornaldiabo, "user_agent_repeated_group")
  expect_identical(r$line, 11L)
  expect_identical(r$severity, "info")
  expect_identical(r$directive, "user-agent")
  expect_identical(r$raw_text, "User-agent: *")
  expect_identical(r$message, paste0(
    "`User-agent: *` (line 11) names every crawler without a group of its ",
    "own, as line 3 in an earlier group already does. Google, Bing and ",
    "Yandex merge every group that names the same crawler, so those ",
    "crawlers follow the rules of both groups together. If the groups came ",
    "from separate blocks, put their rules in one group."
  ))
})

test_that("jornaldiabo.com: an empty Disallow with a full block warns", {
  r <- rg_rows(rg_jornaldiabo, "empty_disallow_with_full_block")
  expect_identical(r$line, 12L)
  expect_identical(r$severity, "warning")
  expect_identical(r$directive, "disallow")
  expect_identical(r$raw_text, "Disallow: /")
  expect_identical(r$message, paste0(
    "`Disallow: /` (line 12) blocks every path for every crawler without a ",
    "group of its own, and the empty `Disallow:` on line 4 reaches the same ",
    "crawlers through the group merge. Google and Bing ignore an empty ",
    "`Disallow:` and block every path; Yandex reads it as allowing every ",
    "path and blocks nothing. If these crawlers are meant to be let in, ",
    "delete line 12; if they are meant to be kept out, delete line 4."
  ))
})

test_that("the warning's premise is the engines' reading", {
  expect_identical(rg_answer(rg_jornaldiabo, "google", "SomeBot"),
                   "disallow")
  body <- rg_lines("User-agent: *", "Disallow:", "", "User-agent: *",
                   "Disallow: /")
  expect_identical(rg_answer(body, "bing", "bingbot"), "disallow")
  expect_identical(rg_answer(body, "yandex", "Yandex"), "allow")
})

test_that("timeschronicle.ca: each later group of a crawler is reported", {
  r <- rg_rows(rg_timeschronicle, "user_agent_repeated_group")
  expect_identical(r$line, c(13L, 20L, 29L))
  expect_match(r$message[[2L]], paste0(
    "`User-agent: *` (line 20) names every crawler without a group of its ",
    "own, as lines 1 and 13 in earlier groups already do."
  ), fixed = TRUE)
  expect_match(r$message[[2L]], "follow the rules of all these groups",
               fixed = TRUE)
  # Letter case aside, `dotbot` is DotBot.
  expect_match(r$message[[3L]], paste0(
    "`User-agent: dotbot` (line 29) names DotBot, as line 27 in an earlier ",
    "group already does."
  ), fixed = TRUE)
  expect_match(r$message[[3L]], "so DotBot follows the rules of both groups",
               fixed = TRUE)
  # No empty Disallow here: no warning.
  expect_identical(
    nrow(rg_rows(rg_timeschronicle, "empty_disallow_with_full_block")), 0L
  )
})

test_that("one group per crawler draws neither code", {
  d <- robots_validate_text(rg_control)$diagnostics
  expect_false(any(d$code %in% c("user_agent_repeated_group",
                                 "empty_disallow_with_full_block")))
})

test_that("a crawler named twice in one group is no repeated group", {
  d <- robots_validate_text(rg_lines(
    "User-agent: FooBot", "User-agent: foobot", "Disallow: /a"
  ))$diagnostics
  expect_false("user_agent_repeated_group" %in% d$code)
})

test_that("a token that joins a group counts as named there", {
  # FooBot's line 6 joins BarBot's group across the Sitemap (Google's
  # reading), so FooBot is named in groups 1 and 2. The join warning owns
  # line 6 (one line, one report), and line 6 still counts for line 9.
  body <- rg_lines(
    "User-agent: FooBot", "Disallow: /a", "", "User-agent: BarBot",
    "Sitemap: https://example.com/s.xml", "User-agent: FooBot",
    "Disallow: /b", "", "User-agent: FooBot", "Disallow: /c"
  )
  d <- robots_validate_text(body)$diagnostics
  expect_identical(d$code[d$line == 6L], "user_agent_joined_across_directive")
  r <- rg_rows(body, "user_agent_repeated_group")
  expect_identical(r$line, 9L)
  expect_match(r$message, "names FooBot, as lines 1 and 6 in earlier groups",
               fixed = TRUE)
})

test_that("a later group naming two repeated crawlers reports each line", {
  r <- rg_rows(rg_lines(
    "User-agent: a", "Disallow: /a", "", "User-agent: b", "Disallow: /b", "",
    "User-agent: a", "User-agent: b", "Disallow: /c"
  ), "user_agent_repeated_group")
  expect_identical(r$line, c(7L, 8L))
  expect_match(r$message[[1L]], "names a, as line 1 in an earlier group",
               fixed = TRUE)
  expect_match(r$message[[2L]], "names b, as line 4 in an earlier group",
               fixed = TRUE)
})

test_that("a long run of repeats keeps each message bounded", {
  body <- rg_lines(unlist(rep(list(c("User-agent: a", "Disallow: /x", "")),
                              40L)))
  r <- rg_rows(body, "user_agent_repeated_group")
  expect_identical(nrow(r), 39L)
  expect_match(r$message[[39L]], "lines 1, 4, 7, 10, 13 and 34 more in",
               fixed = TRUE)
})

test_that("policy-token lines are left to their own report", {
  d <- robots_validate_text(rg_lines(
    "User-agent: __usage_ai-training/1.0", "Disallow: /", "",
    "User-agent: __usage_ai-training/1.0", "Disallow: /"
  ))$diagnostics
  expect_false("user_agent_repeated_group" %in% d$code)
})

test_that("the full-block warning reads the merged rules in either order", {
  r <- rg_rows(rg_lines(
    "User-agent: FooBot", "Disallow: /", "", "User-agent: FooBot",
    "Disallow:"
  ), "empty_disallow_with_full_block")
  expect_identical(r$line, 2L)
  expect_match(r$message, paste0(
    "`Disallow: /` (line 2) blocks every path for FooBot, and the empty ",
    "`Disallow:` on line 5 reaches FooBot through the group merge."
  ), fixed = TRUE)
})

test_that("one group holding both rules warns as well", {
  # ydx-11's own body: the engines split the same way.
  body <- rg_lines("User-agent: FooBot", "Disallow:", "Disallow: /")
  r <- rg_rows(body, "empty_disallow_with_full_block")
  expect_identical(r$line, 3L)
  expect_match(r$message, paste0(
    "`Disallow: /` (line 3) blocks every path for FooBot, and the empty ",
    "`Disallow:` on line 2 is in the same group."
  ), fixed = TRUE)
  yandex_body <- sub("FooBot", "Yandex", body, fixed = TRUE)
  expect_identical(rg_answer(yandex_body, "yandex", "Yandex"), "allow")
})

test_that("a longer Disallow still blocks on Yandex, and the message says so", {
  body <- rg_lines("User-agent: *", "Disallow:", "", "User-agent: *",
                   "Disallow: /*", "Disallow: /private")
  r <- rg_rows(body, "empty_disallow_with_full_block")
  expect_identical(r$line, 5L)
  expect_match(r$message, paste0(
    "Yandex reads it as allowing every path that no longer `Disallow` ",
    "matches."
  ), fixed = TRUE)
})

test_that("agents sharing the full-block line get one warning", {
  r <- rg_rows(rg_lines(
    "User-agent: a", "Disallow:", "", "User-agent: b", "Disallow:", "",
    "User-agent: a", "User-agent: b", "Disallow: /"
  ), "empty_disallow_with_full_block")
  expect_identical(r$line, 9L)
  expect_match(r$message, paste0(
    "blocks every path for a and b, and the empty `Disallow:` on lines 2 ",
    "and 5 reaches a and b through the group merge."
  ), fixed = TRUE)
  expect_match(r$message, "delete lines 2 and 5.", fixed = TRUE)
})

test_that("a non-empty Allow, or an empty Allow, draws no full-block warning", {
  # A non-empty Allow makes it no full block.
  expect_identical(nrow(rg_rows(rg_lines(
    "User-agent: a", "Disallow:", "", "User-agent: a", "Disallow: /",
    "Allow: /pub"
  ), "empty_disallow_with_full_block")), 0L)
  # An empty Allow is a no-op on every engine: they all block.
  expect_identical(nrow(rg_rows(rg_lines(
    "User-agent: a", "Allow:", "", "User-agent: a", "Disallow: /"
  ), "empty_disallow_with_full_block")), 0L)
})

test_that("an every-path Allow with a full block is no engine split", {
  # Allow: / ties Disallow: / and Allow wins on all three engines; Allow: /*
  # is the longer match. Every engine allows, so the warning stays quiet.
  for (allow in c("Allow: /", "Allow: /*")) {
    body <- rg_lines("User-agent: *", allow, "", "User-agent: *",
                     "Disallow: /")
    expect_identical(
      nrow(rg_rows(body, "empty_disallow_with_full_block")), 0L
    )
    expect_identical(rg_answer(body, "google", "Googlebot"), "allow")
    expect_identical(rg_answer(body, "bing", "bingbot"), "allow")
    expect_identical(rg_answer(body, "yandex", "Yandex"), "allow")
  }
})
