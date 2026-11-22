# ROBO-zqyqbudf: Google's matcher reads only a product token from a cut
# User-agent value (ROBO-zvhrayhx), and rows that name such a value as an
# agent name it as written (ROBO-txnzyugl). Each such row keeps that text
# (`cn_*_today`) and adds one sentence: Google's matcher reads only a product
# token from the values, which are named as written with their lines, and the
# user_agent_cut rows say what follows. Uncut controls keep today's text.
# Fixtures are synthetic.

cn_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

cn_rows <- function(body, code) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == code, , drop = FALSE]
}

# The added sentence, for values given as "`Value` (line N)", with `more`
# values left out.
cn_note <- function(values, more = 0L) {
  several <- length(values) + more > 1L
  if (more > 0L) {
    values <- c(values, sprintf("%d more", more))
  }
  k <- length(values)
  listed <- if (k == 1L) values else
    paste(toString(values[-k]), "and", values[[k]])
  sprintf(paste0(" Google's matcher reads only a product token from %s and ",
                 "takes %s; see the user_agent_cut %s."),
          listed,
          if (several) "each agent to be its token" else
            "the agent to be that token",
          if (several) "rows" else "row")
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
  expect_identical(d$message, paste0(
    cn_peer_today, cn_note(c("`Peer39_Crawler` (line 4)", "`Peer42` (line 7)"))
  ))
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
  # Only the cut agent of the merged row is named in the sentence.
  expect_identical(d$message, paste0(
    cn_merged_today, cn_note("`Peer39_Crawler` (line 4)")
  ))
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
  expect_identical(d$message, paste0(cn_reopen_today,
                                     cn_note("`GPT.Bot` (line 4)")))
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
  expect_identical(d$message, paste0(cn_blank_today,
                                     cn_note("`Foo Bar` (line 1)")))
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
  expect_identical(d$message, paste0(cn_directive_today,
                                     cn_note("`Foo Bar` (line 1)")))
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
  expect_identical(d$message, paste0(cn_empty_today,
                                     cn_note("`Spinn3r` (line 1)")))
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
  expect_identical(d$message, paste0(cn_stacked_today,
                                     cn_note("`Foo Bar` (line 1)")))
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
  # groups. The v1 facade refuses the full value as input, since it is
  # outside the RFC 9309 identifier rule (ROBO-mtmkpwuf); the legacy path shows the
  # matcher's reading.
  decide <- function(token) {
    robots_evaluate_text_v1(
      robots_txt = cn_peer, url = "https://example.com/a",
      robots_product_token = token, robots_policy_ruleset = "google",
      matcher_backend = "google"
    )$results
  }
  expect_identical(decide("Peer39_Crawler")$reason, "input_invalid")
  expect_identical(decide("Peer")$url_decision, "allow")
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

test_that("the sentence names five values at most, then a count", {
  body <- cn_lines("User-agent: *", "Disallow: /a", "",
                   sprintf("User-agent: Peer%d\nDisallow: /b\n", 1:7))
  d <- cn_rows(body, "wildcard_disallows_not_inherited")
  expect_identical(d$line, 4L)
  shown <- sprintf("`Peer%d` (line %d)", 1:5, seq(4L, 16L, by = 3L))
  expect_true(endsWith(d$message, cn_note(shown, more = 2L)))
})

test_that("a joined row names its cut opener and earlier agents", {
  # Peer39_Crawler opens the group (line 1); Zork.Bot and Spinbot join it;
  # Baz (line 5) joins across the Crawl-delay and gets the warning naming
  # all three.
  body <- cn_lines("User-agent: Peer39_Crawler", "User-agent: Zork.Bot",
                   "User-agent: Spinbot", "Crawl-delay: 1",
                   "User-agent: Baz", "Disallow: /")
  d <- cn_rows(body, "user_agent_joined_across_directive")
  expect_identical(d$line, 5L)
  expect_true(endsWith(d$message, cn_note(c("`Peer39_Crawler` (line 1)",
                                            "`Zork.Bot` (line 2)"))))
})

test_that("the sentence comes before the NUL note", {
  bytes <- charToRaw(cn_peer)
  at <- grepRaw("Disallow: /a", bytes) + nchar("Disallow: /a") - 1L
  body <- c(bytes[seq_len(at)], as.raw(0), charToRaw("x"),
            bytes[-seq_len(at)])
  d <- robots_validate_text(body)$diagnostics
  d <- d[d$code == "wildcard_disallows_not_inherited", , drop = FALSE]
  expect_identical(d$message, paste0(
    cn_peer_today,
    cn_note(c("`Peer39_Crawler` (line 4)", "`Peer42` (line 7)")),
    " This is Google's reading, which ends each line at its first NUL; ",
    "Bing and Yandex read the NUL as an ordinary byte."
  ))
})

test_that("a cut value with invalid UTF-8 is named as rendered", {
  body <- c(charToRaw("User-agent: *\nDisallow: /a\n\nUser-agent: Peer"),
            as.raw(0xe9), charToRaw("x\nDisallow: /b\n"))
  d <- robots_validate_text(body)$diagnostics
  d <- d[d$code == "wildcard_disallows_not_inherited", , drop = FALSE]
  expect_length(d$message, 1L)
  expect_match(d$message, "^[ -~]*$")
  expect_true(endsWith(d$message, cn_note("`Peer\\xE9x` (line 4)")))
})

test_that("a value naming no token draws no wildcard row to annotate", {
  # `*bot` reads no token, so Google names no crawler and the line is left
  # out of the wildcard check.
  body <- cn_lines("User-agent: *", "Disallow: /a", "", "User-agent: *bot",
                   "Disallow: /b")
  d <- robots_validate_text(body)$diagnostics
  expect_false(any(grepl("^wildcard_", d$code)))
  expect_false(any(grepl("product token from", d$message, fixed = TRUE)))
})

test_that("a body cut at max_bytes still annotates joined and stacked rows", {
  body <- charToRaw(paste0(cn_lines(
    "User-agent: Foo.Bot", "Crawl-delay: 1", "User-agent: Baz",
    "Disallow: /", "", "User-agent: Spinn3r", "Crawl-delay: 1",
    "User-agent: __usage_ai-training", "Disallow: /"
  ), "Disallow: /more"))
  d <- validate_document_bytes(body, "s", "supplied",
                               body_truncated = TRUE)$diagnostics
  joined <- d[d$code == "user_agent_joined_across_directive", ]
  stacked <- d[d$code == "ai_training_token_stacked", ]
  expect_true(endsWith(joined$message, cn_note("`Foo.Bot` (line 1)")))
  expect_true(endsWith(stacked$message, cn_note("`Spinn3r` (line 6)")))
  expect_false(any(grepl("^wildcard_|^empty_disallow", d$code)))
})

test_that("a cut policy token is not named as an agent", {
  # The opener is the policy token, which Google reads as
  # `__usage_ai-training`; it is no crawler, so no sentence names it.
  d <- cn_rows(cn_lines("User-agent: __usage_ai-training/1.0",
                        "User-agent: Spinbot", "Crawl-delay: 1",
                        "User-agent: Baz", "Disallow: /"),
               "user_agent_joined_across_directive")
  expect_length(d$message, 1L)
  expect_no_match(d$message, "product token from", fixed = TRUE)
})

test_that("a cut value written in two cases names each line", {
  # The row names `Foo Bar` once; each line has its own user_agent_cut row.
  body <- cn_lines("User-agent: *", "Disallow: /a", "",
                   "User-agent: Foo Bar", "Disallow: /b", "", "",
                   "User-agent: foo bar", "Disallow: /c")
  d <- cn_rows(body, "wildcard_disallows_not_inherited")
  expect_identical(d$line, 4L)
  expect_match(d$message, "^Foo Bar obeys only the groups that name it,")
  expect_true(endsWith(d$message, cn_note(c("`Foo Bar` (line 4)",
                                            "`foo bar` (line 8)"))))
  empty <- cn_rows(cn_lines("User-agent: Foo Bar", "Disallow:", "",
                            "User-agent: foo bar", "Disallow: /"),
                   "empty_disallow_with_full_block")
  expect_true(endsWith(empty$message, cn_note(c("`Foo Bar` (line 1)",
                                                "`foo bar` (line 4)"))))
})

test_that("a merged row names its cut values in line order", {
  # The crawlers come in key order (`peer` at lines 4 and 10, then `zork` at
  # line 7); the sentence lists the lines in file order.
  body <- cn_lines("User-agent: *", "Allow: /x", "",
                   "User-agent: Peer1", "Disallow: /b", "",
                   "User-agent: Zork.Bot", "Disallow: /c", "",
                   "User-agent: Peer2", "Disallow: /d")
  d <- cn_rows(body, "wildcard_rules_not_inherited")
  expect_length(d$message, 1L)
  expect_true(endsWith(d$message, cn_note(c(
    "`Peer1` (line 4)", "`Zork.Bot` (line 7)", "`Peer2` (line 10)"
  ))))
})

test_that("a cut policy token stacked beside the token is not named", {
  # `__usage_foo/1` is another policy token, no crawler, so the stacked row
  # on line 3 names it without the sentence.
  d <- cn_rows(cn_lines("User-agent: __usage_foo/1", "Crawl-delay: 1",
                        "User-agent: __usage_ai-training", "Disallow: /"),
               "ai_training_token_stacked")
  row <- d[d$line == 3L, , drop = FALSE]
  expect_match(row$message, "`User-agent: __usage_foo/1` (line 1)",
               fixed = TRUE)
  expect_no_match(row$message, "product token from", fixed = TRUE)
})

test_that("a cut value on the joining line is named", {
  # The row is anchored on `Foo Bar` (line 3), the agent that joins.
  for (between in c("Crawl-delay: 1", "")) {
    code <- if (nzchar(between)) "user_agent_joined_across_directive" else
      "user_agent_joined_across_blank"
    d <- cn_rows(cn_lines("User-agent: Baz", between, "User-agent: Foo Bar",
                          "Disallow: /x"), code)
    expect_identical(d$line, 3L, label = code)
    expect_true(endsWith(d$message, cn_note("`Foo Bar` (line 3)")),
                label = code)
  }
})

test_that("a cut opener sharing the joining agent's key is named", {
  # `Foo/1` (line 1) and `Foo` (line 4) share the key `foo`, so `Foo/1` is
  # not among the earlier agents; the message names it as the opener.
  d <- cn_rows(cn_lines("User-agent: Foo/1", "User-agent: Bar",
                        "Crawl-delay: 1", "User-agent: Foo", "Disallow: /x"),
               "user_agent_joined_across_directive")
  expect_identical(d$line, 4L)
  expect_match(d$message, "`User-agent: Foo/1` opened", fixed = TRUE)
  expect_true(endsWith(d$message, cn_note("`Foo/1` (line 1)")))
})

test_that("an opener Google reads no token from is not named as an agent", {
  # `1bot` and `*bot` name no crawler for Google's matcher (their
  # user_agent_cut rows say so), so the sentence does not name them.
  for (opener in c("1bot", "*bot")) {
    body <- sprintf(paste0("User-agent: %s\nUser-agent: Bar\n",
                           "Sitemap: https://e.com/s.xml\nUser-agent: Foo\n",
                           "Disallow: /x\n"), opener)
    d <- cn_rows(body, "user_agent_joined_across_directive")
    expect_identical(d$line, 4L, label = opener)
    expect_no_match(d$message, "product token from", fixed = TRUE)
  }
})

# A cut-heavy file: every row family that names an agent, on values whose
# tokens (`Peer`, `Zork`, `Spinn`, `GPT`) are never a word of the written
# value.
cn_heavy <- cn_lines(
  "User-agent: *", "Disallow: /a", "Allow: /x", "",
  "User-agent: Peer39_Crawler", "Crawl-delay: 1", "User-agent: Baz",
  "Disallow: /b", "",
  "User-agent: Peer42", "", "User-agent: Qux", "Disallow: /c", "",
  "User-agent: Zork.Bot", "Disallow:", "Disallow: /", "",
  "User-agent: Spinn3r", "Crawl-delay: 1",
  "User-agent: __usage_ai-training", "Disallow: /", "",
  "User-agent: Peer7", "Disallow: /b", "", "User-agent: GPT.Bot",
  "Disallow: /a", "Allow: /a/b"
)

cn_named_codes <- c(
  "wildcard_disallows_not_inherited", "allow_reopens_wildcard_disallow",
  "wildcard_rules_not_inherited", "user_agent_joined_across_directive",
  "user_agent_joined_across_blank", "empty_disallow_with_full_block",
  "ai_training_token_stacked"
)

test_that("no row but user_agent_cut names a cut token as an agent", {
  d <- robots_validate_text(cn_heavy)$diagnostics
  expect_true(all(cn_named_codes %in% d$code))
  # The token as a word of its own: not `Zork.Bot`, which is the value. A
  # quoted token (duplicate_rule's `as one token, 'Peer'`) names it as a
  # token, and the quote keeps it out of the pattern.
  for (token in c("Peer", "Zork", "Spinn", "GPT")) {
    word <- sprintf("(^|[ (`*])%s([ ,;:)`]|[.]( |$)|$)", token)
    hit <- grepl(word, d$message) & d$code != "user_agent_cut"
    expect_false(any(hit), label = paste(token, toString(d$code[hit])))
  }
  # A row naming a cut value ends with the sentence; one naming none (Qux
  # alone) has none.
  family <- d[d$code %in% cn_named_codes, , drop = FALSE]
  cut <- grepl("Peer39_Crawler|Peer42|Peer7|Zork[.]Bot|Spinn3r|GPT[.]Bot",
               family$message)
  expect_false(all(cut))
  expect_identical(grepl("see the user_agent_cut rows?\\.$", family$message),
                   cut)
})

# Timing guards (ROBO-dbvmxcfw keeps the validator linear). Each builder is
# timed on its own, best of five, so one slow run under machine load does
# not count.
cn_prepare <- function(body) {
  parsed <- as.data.frame(robotstxtr_validation_parse_(charToRaw(body)),
                          stringsAsFactors = FALSE)
  list(groups = validation_groups(parsed), parsed = parsed)
}

cn_time <- function(body, check) {
  x <- cn_prepare(body)
  min(vapply(1:5, function(i) {
    system.time(check(x$groups, x$parsed))[["elapsed"]]
  }, 0))
}

# The same input timed with and without the sentence, runs interleaved so
# both see the same load: c(with, without), each the best of five.
cn_time_share <- function(body, check) {
  x <- cn_prepare(body)
  runs <- vapply(1:5, function(i) {
    with_note <- system.time(check(x$groups, x$parsed))[["elapsed"]]
    without <- system.time(with_mocked_bindings(
      check(x$groups, x$parsed),
      cut_agent_note = function(...) ""
    ))[["elapsed"]]
    c(with_note, without)
  }, numeric(2L))
  apply(runs, 1L, min)
}

# Letter-only tokens: Ta, Tb, ..., Tba, ...
cn_letters <- function(n) {
  paste0("T", chartr("0123456789", "abcdefghij", seq_len(n)))
}

# Each shape at `n`: `n` groups of cut agents, every row of the family
# carrying the sentence.
cn_shapes <- list(
  # One merged wildcard row naming `n` cut values of one token.
  wildcard = list(
    body = function(n) {
      cn_lines("User-agent: *", "Disallow: /a", "Allow: /x",
               sprintf("User-agent: Peer%d\nDisallow: /b", seq_len(n)))
    },
    check = function(groups, parsed) wildcard_inheritance_diagnostics(groups)
  ),
  # `n` joined warnings, each naming a cut opener.
  joined = list(
    body = function(n) {
      tokens <- cn_letters(n)
      cn_lines(sprintf(
        "User-agent: %s 1\nCrawl-delay: 1\nUser-agent: U%s\nDisallow: /",
        tokens, tokens
      ))
    },
    check = function(groups, parsed) {
      joined_user_agent_diagnostics(groups, parsed)
    }
  ),
  # One empty_disallow_with_full_block row naming `n` cut values.
  empty = list(
    body = function(n) {
      cn_lines(sprintf("User-agent: Peer%d\nDisallow:\nDisallow: /",
                       seq_len(n)))
    },
    check = function(groups, parsed) {
      empty_disallow_full_block_diagnostics(groups)
    }
  ),
  # `n` stacked policy tokens, each beside a cut crawler.
  stacked = list(
    body = function(n) {
      cn_lines(sprintf(paste0("User-agent: %s 1\nCrawl-delay: 1\n",
                              "User-agent: __usage_ai-training\nDisallow: /"),
                       cn_letters(n)))
    },
    check = function(groups, parsed) ai_training_diagnostics(groups, parsed)
  ),
  # `n` distinct cut crawlers, each its own wildcard row. The check itself
  # is not linear in them (each crawler scans the agent and rule lines,
  # before this sentence too), so only the share guard below covers it.
  wildcard_rows = list(
    body = function(n) {
      cn_lines("User-agent: *", "Disallow: /a", "Allow: /x",
               sprintf("User-agent: %s 1\nDisallow: /b", cn_letters(n)))
    },
    check = function(groups, parsed) wildcard_inheritance_diagnostics(groups),
    share_n = 2000L
  )
)

for (shape in setdiff(names(cn_shapes), "wildcard_rows")) {
  test_that(paste("the sentence costs time linear in the file:", shape), {
    skip_on_cran()
    # Four times the file: linear is about four times the time, quadratic
    # sixteen; 8x and a 0.05 s floor leave room for noise.
    x <- cn_shapes[[shape]]
    small <- cn_time(x$body(1000L), x$check)
    large <- cn_time(x$body(4000L), x$check)
    expect_lt(large, 8 * max(small, 0.05))
  })
}

for (shape in names(cn_shapes)) {
  test_that(paste("the sentence adds a small share of the time:", shape), {
    skip_on_cran()
    # The same input with and without the sentence: load moves both alike,
    # and a sentence costing time per row in the file would dominate.
    x <- cn_shapes[[shape]]
    n <- if (is.null(x$share_n)) 4000L else x$share_n
    times <- cn_time_share(x$body(n), x$check)
    expect_lt(times[[1L]], 1.5 * times[[2L]] + 0.05)
  })
}
