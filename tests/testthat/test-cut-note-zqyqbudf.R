# ROBO-zqyqbudf: Google's matcher reads only a product token from a cut
# User-agent value (ROBO-zvhrayhx), and rows that name such a value as an
# agent name it as written (ROBO-txnzyugl). These pins fix today's text of
# each row that names a cut value, and of uncut controls. Fixtures are
# synthetic.

cn_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

cn_rows <- function(body, code) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == code, , drop = FALSE]
}

# `*` Disallows /a; Peer39_Crawler (line 4) and Peer42 (line 7) are both read
# as `Peer` by Google's matcher.
cn_peer <- cn_lines(
  "User-agent: *", "Disallow: /a", "",
  "User-agent: Peer39_Crawler", "Disallow: /b", "",
  "User-agent: Peer42", "Disallow: /c"
)

cn_disallows_tail <- paste0(
  "A named group replaces `User-agent: *` for the crawlers it names instead ",
  "of adding to it (RFC 9309 section 2.2.1). If the groups were meant to ",
  "add to `User-agent: *`, repeat this Disallow in them."
)

cn_peer_today <- paste(
  "Peer39_Crawler and Peer42 obey only the groups that name them, so this",
  "`User-agent: *` Disallow does not apply to them: Disallow: /a (line 2).",
  cn_disallows_tail
)

test_that("wildcard_disallows_not_inherited names cut values as written", {
  d <- cn_rows(cn_peer, "wildcard_disallows_not_inherited")
  expect_identical(d$line, 4L)
  expect_identical(d$message, cn_peer_today)
})

# A merged info row: a cut agent (line 4) and an uncut one (line 7).
cn_merged <- cn_lines(
  "User-agent: *", "Allow: /x", "",
  "User-agent: Peer39_Crawler", "Disallow: /b", "",
  "User-agent: Spinbot", "Disallow: /c"
)

cn_inherit_tail <- paste0(
  "A crawler obeys only the groups that name it and ignores `User-agent: *` ",
  "once any group does; `User-agent: *` applies only to crawlers no group ",
  "names."
)

cn_merged_today <- paste(
  "Peer39_Crawler (line 4); and Spinbot (line 7) each obey only the groups",
  "that name them, so this `User-agent: *` rule does not apply to them:",
  "Allow: /x (line 2).", cn_inherit_tail
)

test_that("a merged wildcard_rules_not_inherited row names both groups", {
  d <- cn_rows(cn_merged, "wildcard_rules_not_inherited")
  expect_identical(d$line, 4L)
  expect_identical(d$message, cn_merged_today)
})

cn_reopen <- cn_lines(
  "User-agent: *", "Disallow: /private", "",
  "User-agent: GPT.Bot", "Disallow: /private", "Allow: /private/public"
)

cn_reopen_today <- paste(
  paste0("GPT.Bot obeys only this group, so Allows there reopen this path, ",
         "which `User-agent: *` disallows: /private/public (allowed by ",
         "Allow: /private/public on line 6; disallowed for `*` by ",
         "Disallow: /private on line 2)."),
  paste0("A named group replaces `User-agent: *` for the crawlers it names ",
         "instead of adding to it (RFC 9309 section 2.2.1). If this path ",
         "was meant to stay blocked for it, add a Disallow to this group ",
         "longer than the Allow matching the path.")
)

test_that("allow_reopens_wildcard_disallow names a cut value as written", {
  d <- cn_rows(cn_reopen, "allow_reopens_wildcard_disallow")
  expect_identical(d$line, 4L)
  expect_identical(d$message, cn_reopen_today)
})

cn_blank <- cn_lines("User-agent: Foo Bar", "", "User-agent: Baz",
                     "Disallow: /")

cn_blank_today <- paste(
  "`User-agent: Baz` (line 3) shares a group with `User-agent: Foo Bar`",
  "(line 1): only blank or comment lines come between them, and a",
  "`User-agent` line starts a new group only after an `Allow` or `Disallow`",
  "line. Google and Bing read one group, so the rules on line 4 apply to",
  "both, including a full block (`Disallow: /`, line 4). Yandex ends a group",
  "at every blank or comment line, as at line 2, and gives Foo Bar no rules.",
  "If both are meant to share these rules, remove the blank or comment",
  "lines; if not, give Foo Bar its own rules before line 3."
)

test_that("user_agent_joined_across_blank names a cut value as written", {
  d <- cn_rows(cn_blank, "user_agent_joined_across_blank")
  expect_identical(d$line, 3L)
  expect_identical(d$message, cn_blank_today)
})

cn_directive <- cn_lines("User-agent: Foo Bar", "Crawl-delay: 1",
                         "User-agent: Baz", "Disallow: /")

cn_directive_today <- paste(
  "`User-agent: Baz` (line 3) joins the group that `User-agent: Foo Bar`",
  "opened on line 1. For Google, a `User-agent` line starts a new group only",
  "after an `Allow` or `Disallow` line, and lines 1-3 have none; the",
  "`Crawl-delay` on line 2 does not end a group. So the rules on line 4",
  "apply to Foo Bar as well as to Baz, including a full block (`Disallow:",
  "/`, line 4). Bing and Yandex end the group at line 2, so neither gives",
  "these rules to Foo Bar. If `Foo Bar` was not meant to get these rules,",
  "end its group before line 3 with an empty `Disallow:` line, which blocks",
  "nothing."
)

test_that("user_agent_joined_across_directive names a cut value as written", {
  d <- cn_rows(cn_directive, "user_agent_joined_across_directive")
  expect_identical(d$line, 3L)
  expect_identical(d$message, cn_directive_today)
})

cn_empty <- cn_lines("User-agent: Spinn3r", "Disallow:", "Disallow: /")

cn_empty_today <- paste(
  "`Disallow: /` (line 3) blocks every path for Spinn3r, and the empty",
  "`Disallow:` on line 2 is in the same group. Google and Bing ignore an",
  "empty `Disallow:` and block every path; Yandex reads it as allowing every",
  "path and blocks nothing. If Spinn3r is meant to be let in, delete line 3;",
  "if it is meant to be kept out, delete line 2."
)

test_that("empty_disallow_with_full_block names a cut value as written", {
  d <- cn_rows(cn_empty, "empty_disallow_with_full_block")
  expect_identical(d$line, 3L)
  expect_identical(d$message, cn_empty_today)
})

cn_stacked <- cn_lines("User-agent: Foo Bar", "Crawl-delay: 1",
                       "User-agent: __usage_ai-training", "Disallow: /")

cn_stacked_today <- paste(
  "`User-agent: __usage_ai-training` shares a group with `User-agent: Foo",
  "Bar` (line 1): Google's and Yandex's parsers join User-agent lines that",
  "no Allow or Disallow line separates, so this group's rules also apply to",
  "Foo Bar. Bing's parser ends the group at the directive line between the",
  "two. Give the policy token a separate group, after a group that ends in",
  "an Allow or Disallow line."
)

test_that("ai_training_token_stacked names a cut value as written", {
  d <- cn_rows(cn_stacked, "ai_training_token_stacked")
  expect_identical(d$line, 3L)
  expect_identical(d$message, cn_stacked_today)
})

# Uncut controls: their text must not change.
cn_uncut <- cn_lines(
  "User-agent: *", "Disallow: /a", "",
  "User-agent: Spinbot", "Disallow: /b", "",
  "User-agent: Baz", "Disallow: /c"
)

cn_uncut_today <- function(agent) {
  paste(
    agent, "obeys only this group, so this `User-agent: *` Disallow does not",
    "apply to it: Disallow: /a (line 2). A named group replaces",
    "`User-agent: *` for the crawlers it names instead of adding to it (RFC",
    "9309 section 2.2.1). If the group was meant to add to `User-agent: *`,",
    "repeat this Disallow in it."
  )
}

test_that("uncut agents keep today's wildcard text", {
  d <- cn_rows(cn_uncut, "wildcard_disallows_not_inherited")
  expect_identical(d$line, c(4L, 7L))
  expect_identical(d$message, c(cn_uncut_today("Spinbot"),
                                cn_uncut_today("Baz")))
})

test_that("a cut value beside its uncut name keeps today's text", {
  # written_agent_names() names `googlebot`, the value the token spells
  # whole, so the row names no cut value.
  d <- cn_rows(cn_lines("User-agent: *", "Disallow: /a", "",
                        "User-agent: googlebot", "User-agent: Googlebot/2.1",
                        "Disallow: /b"),
               "wildcard_disallows_not_inherited")
  expect_identical(d$message, sub("^Spinbot", "googlebot",
                                  cn_uncut_today("Spinbot")))
})

test_that("a merged row of uncut agents keeps today's text", {
  d <- cn_rows(cn_lines("User-agent: *", "Allow: /x", "",
                        "User-agent: Spinbot", "Disallow: /b", "",
                        "User-agent: Baz", "Disallow: /c"),
               "wildcard_rules_not_inherited")
  expect_identical(d$message, paste(
    "Spinbot (line 4); and Baz (line 7) each obey only the groups that name",
    "them, so this `User-agent: *` rule does not apply to them: Allow: /x",
    "(line 2).", cn_inherit_tail
  ))
})

test_that("uncut joined and stacked rows keep today's text", {
  blank <- cn_rows(sub("Foo Bar", "Spinbot", cn_blank, fixed = TRUE),
                   "user_agent_joined_across_blank")
  expect_identical(blank$message,
                   gsub("Foo Bar", "Spinbot", cn_blank_today, fixed = TRUE))
  stacked <- cn_rows(sub("Foo Bar", "Spinbot", cn_stacked, fixed = TRUE),
                     "ai_training_token_stacked")
  expect_identical(stacked$message, gsub("Foo Bar", "Spinbot",
                                         cn_stacked_today, fixed = TRUE))
  empty <- cn_rows(sub("Spinn3r", "Spinbot", cn_empty, fixed = TRUE),
                   "empty_disallow_with_full_block")
  expect_identical(empty$message,
                   gsub("Spinn3r", "Spinbot", cn_empty_today, fixed = TRUE))
})

test_that("on Google a cut value is read as its token", {
  # The premise: a crawler going by the full value `Peer39_Crawler` gets the
  # `*` rule on Google's matcher; one whose token is `Peer` gets the named
  # groups.
  decide <- function(token) {
    robots_evaluate_text_v1(
      robots_txt = cn_peer, url = "https://example.com/a",
      robots_product_token = token, robots_policy_ruleset = "google",
      matcher_backend = "google"
    )$results$url_decision
  }
  expect_identical(decide("Peer39_Crawler"), "disallow")
  expect_identical(decide("Peer"), "allow")
  allowed <- function(token) {
    allowed_by_robots_text(cn_peer, "https://example.com/a",
                           token)$results$allowed
  }
  expect_false(allowed("Peer39_Crawler"))
  expect_true(allowed("Peer"))
  # Bing and Yandex: not testable here. Their backends evaluate only their
  # own crawlers' tokens, and the sentence speaks of Google's reading only.
  for (backend in c("bing", "yandex")) {
    x <- robots_evaluate_text_v1(cn_peer, "https://example.com/a",
                                 "Peer39_Crawler", backend, backend)$results
    expect_false(identical(x$matcher_status, "evaluated"), label = backend)
  }
})
