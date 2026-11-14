# ROBO-xepnhfgs: Google's parser starts a new group only after an Allow or
# Disallow line (src/robots.cc, RobotsMatcher::HandleUserAgent and
# seen_separator_), so a User-agent line after a Sitemap, Crawl-delay or
# blank line joins the open group, and that group's rules reach the earlier
# agents too. Bing ends the run at any directive and Yandex at a blank,
# comment or Crawl-delay line (design/engine-disagreements.md class 1;
# Yandex tester Y5, ROBO-bpywsjwv). The shapes come from news-ai-access's
# stored files (NEWS-caacyart): internetcom.jp, www.rro.ch,
# timeschronicle.ca and www.almeredezeweek.nl, quoted line for line.

uaj_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

uaj_rows <- function(body, code) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == code, , drop = FALSE]
}

uaj_internetcom <- uaj_lines(
  "",
  "User-agent: *", "Disallow: /click/", "Disallow: /ad/",
  "Disallow: /smartnews_prs/", "",
  "User-agent: *", "Sitemap: https://internetcom.jp/xml/sitemap_index.xml", "",
  "User-agent: bingbot", "Disallow: /news/", "Allow: /news/article/"
)

uaj_rro <- uaj_lines(
  "User-agent: *", "Crawl-delay: 10", "", "User-agent: AhrefsBot", "Disallow: /"
)

test_that("internetcom.jp: a Sitemap between the lines warns on bingbot", {
  x <- robots_validate_text(uaj_internetcom)
  d <- x$diagnostics
  r <- d[d$code == "user_agent_joined_across_directive", , drop = FALSE]
  expect_identical(r$line, 10L)
  expect_identical(r$severity, "warning")
  expect_identical(r$directive, "user-agent")
  expect_identical(r$raw_text, "User-agent: bingbot")
  expect_identical(r$message, paste0(
    "`User-agent: bingbot` (line 10) joins the group that `User-agent: *` ",
    "opened on line 7. For Google, a `User-agent` line starts a new group ",
    "only after an `Allow` or `Disallow` line, and lines 7-10 have none; the ",
    "`Sitemap` on line 8 does not end a group. So the rules on lines 11-12 ",
    "apply to every crawler without a group of its own as well as to ",
    "bingbot. Bing ends the group at line 8, and Yandex by line 9, so ",
    "neither gives these rules to every crawler without a group of its own. ",
    "If `*` was not meant to get these rules, end its group before line 10 ",
    "with an empty `Disallow:` line, which blocks nothing, or delete line 7 ",
    "if it is there only to hold the `Sitemap`; if it was meant to, move ",
    "line 8 out from between the `User-agent` lines, so Bing reads one ",
    "group too."
  ))
  # One report per line: no blank-line info on bingbot as well.
  expect_false("user_agent_joined_across_blank" %in% d$code)
  # The inheritance info is unchanged (ROBO-gfjotdrr): it anchors on the
  # joined group's first User-agent line, the `*` on line 7.
  expect_identical(d$line[d$code == "wildcard_rules_not_inherited"], 7L)
})

test_that("www.rro.ch: a Crawl-delay before a full block names both engines", {
  r <- uaj_rows(uaj_rro, "user_agent_joined_across_directive")
  expect_identical(r$line, 4L)
  expect_identical(r$message, paste0(
    "`User-agent: AhrefsBot` (line 4) joins the group that `User-agent: *` ",
    "opened on line 1. For Google, a `User-agent` line starts a new group ",
    "only after an `Allow` or `Disallow` line, and lines 1-4 have none; the ",
    "`Crawl-delay` on line 2 does not end a group. So the rules on line 5 ",
    "apply to every crawler without a group of its own as well as to ",
    "AhrefsBot, including a full block (`Disallow: /`, line 5). Bing and ",
    "Yandex end the group at line 2, so neither gives these rules to every ",
    "crawler without a group of its own. If `*` was not meant to get these ",
    "rules, end its group before line 4 with an empty `Disallow:` line, ",
    "which blocks nothing."
  ))
})

test_that("the joined reading is the matcher's", {
  # The warning's premise, on the vendored Google parser: `*` gets AhrefsBot's
  # full block.
  r <- allowed_by_robots_text(uaj_rro, "https://example.com/a",
                              user_agent = "SomeBot")
  expect_false(r$results$allowed)
  expect_identical(r$results$matched_line, 5L)
})

test_that("a Sitemap with no blank line names Bing only", {
  r <- uaj_rows(uaj_lines(
    "User-agent: *", "Sitemap: https://example.com/s.xml",
    "User-agent: bingbot", "Disallow: /news/"
  ), "user_agent_joined_across_directive")
  expect_identical(r$line, 3L)
  expect_match(r$message, paste0(
    "Bing ends the group at line 2, so it does not give these rules to ",
    "every crawler without a group of its own."
  ), fixed = TRUE)
  expect_no_match(r$message, "Yandex", fixed = TRUE)
})

test_that("www.almeredezeweek.nl: the policy token keeps its own warning", {
  # One line gets one report: ai_training_token_stacked (ROBO-kzyfejcv)
  # already covers a token line stacked across a directive.
  d <- robots_validate_text(uaj_lines(
    "User-agent: Googlebot", "Allow: /", "",
    "User-agent: facebookexternalhit", "Allow: /", "",
    "User-agent: *",
    "Content-Signal: ai-train=no, search=yes, ai-input=yes",
    "Sitemap: https://www.almeredezeweek.nl/sitemap", "", "", "",
    "User-agent: __usage_ai-training", "Disallow: /"
  ))$diagnostics
  expect_identical(d$line[d$code == "ai_training_token_stacked"], 13L)
  expect_false(any(startsWith(d$code, "user_agent_joined")))
  # Nor is a crawler line joined after a token line reported: the token's
  # warning already names the stack.
  d <- robots_validate_text(uaj_lines(
    "User-agent: __usage_ai-training", "Crawl-delay: 5",
    "User-agent: GPTBot", "Disallow: /"
  ))$diagnostics
  expect_false(any(startsWith(d$code, "user_agent_joined")))
})

test_that("timeschronicle.ca: a repeat of the same agent is silent", {
  d <- robots_validate_text(uaj_lines(
    "User-agent: *", "Disallow: /wp-admin/", "",
    "# Slow down bots", "User-agent: *", "Crawl-delay: 10", "",
    "User-agent: *", "Disallow: /?blackhole", "",
    "# Slow down bots", "User-agent: *", "Crawl-delay: 10", "",
    "User-agent: OAI-SearchBot", "Disallow: /"
  ))$diagnostics
  r <- d[d$code == "user_agent_joined_across_directive", , drop = FALSE]
  # Line 8 joins `*` to `*`, which changes nothing; line 15 gives `*` the
  # full block.
  expect_identical(r$line, 15L)
  expect_match(r$message, "including a full block (`Disallow: /`, line 16)",
               fixed = TRUE)
})

test_that("a blank-line stack draws the info, naming Yandex's split", {
  x <- robots_validate_text(uaj_lines(
    "User-agent: Googlebot", "", "User-agent: Bingbot", "Disallow: /private"
  ))
  d <- x$diagnostics
  expect_identical(d$code, "user_agent_joined_across_blank")
  expect_identical(d$severity, "info")
  expect_identical(d$line, 3L)
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(d$message, paste0(
    "`User-agent: Bingbot` (line 3) shares a group with ",
    "`User-agent: Googlebot` (line 1): only blank or comment lines come ",
    "between them, and a `User-agent` line starts a new group only after an ",
    "`Allow` or `Disallow` line. Google and Bing read one group, so the rules ",
    "on line 4 apply to both. Yandex ends a group at every blank or comment ",
    "line, as at line 2, and gives Googlebot no rules. If both are meant to share these rules, remove the ",
    "blank or comment lines; if not, give Googlebot its own rules before ",
    "line 3."
  ))
})

test_that("a comment line alone draws the info too", {
  r <- uaj_rows(uaj_lines(
    "# Google", "User-agent: Googlebot", "# Bing", "User-agent: Bingbot",
    "Disallow: /"
  ), "user_agent_joined_across_blank")
  expect_identical(r$line, 4L)
  expect_match(r$message, "comment line, as at line 3,", fixed = TRUE)
  expect_match(r$message, "including a full block (`Disallow: /`, line 5)",
               fixed = TRUE)
})

test_that("consecutive User-agent lines stay silent", {
  d <- robots_validate_text(uaj_lines(
    "User-agent: Googlebot", "User-agent: Bingbot", "Disallow: /private"
  ))$diagnostics
  expect_identical(nrow(d), 0L)
})

test_that("a run with no rules is silent", {
  d <- robots_validate_text(uaj_lines(
    "User-agent: *", "Disallow: /x", "",
    "User-agent: a", "Crawl-delay: 5", "User-agent: b"
  ))$diagnostics
  expect_false(any(startsWith(d$code, "user_agent_joined")))
})

test_that("several earlier agents and directives are all named", {
  r <- uaj_rows(uaj_lines(
    "User-agent: a", "User-agent: *", "Crawl-delay: 5",
    "Sitemap: https://example.com/s.xml", "User-agent: c",
    "Disallow: /1", "Disallow: /2", "Disallow: /4", "Disallow: /5",
    "Disallow: /6", "Disallow: /7"
  ), "user_agent_joined_across_directive")
  expect_identical(r$line, 5L)
  expect_match(r$message, paste0(
    "`User-agent: c` (line 5) joins the group that `User-agent: a` opened ",
    "on line 1."
  ), fixed = TRUE)
  expect_match(r$message, paste0(
    "the `Crawl-delay` on line 3 and the `Sitemap` on line 4 do not end a ",
    "group. So the rules on lines 6-11 (6 rules) apply to a and every ",
    "crawler without a group of its own as well as to c."
  ), fixed = TRUE)
  expect_match(r$message, paste0(
    "If `a` and `*` were not meant to get these rules, end their group ",
    "before line 5"
  ), fixed = TRUE)
})

test_that("the joined agent is not named among the agents it joins", {
  r <- uaj_rows(uaj_lines(
    "User-agent: a", "User-agent: b", "Sitemap: https://example.com/s.xml",
    "User-agent: a", "Disallow: /"
  ), "user_agent_joined_across_directive")
  expect_identical(r$line, 4L)
  expect_match(r$message, paste0(
    "apply to b as well as to a, including a full block (`Disallow: /`, ",
    "line 5)."
  ), fixed = TRUE)
  # Two lines before the break: deleting one would not unjoin the other.
  expect_match(r$message, paste0(
    "If `b` was not meant to get these rules, end its group before line 4 ",
    "with an empty `Disallow:` line, which blocks nothing; if it was meant ",
    "to, move line 3 out"
  ), fixed = TRUE)
})

test_that("each break in a run is reported on its own line", {
  d <- robots_validate_text(uaj_lines(
    "User-agent: a", "Crawl-delay: 1", "User-agent: b", "",
    "User-agent: c", "Disallow: /"
  ))$diagnostics
  j <- d[startsWith(d$code, "user_agent_joined"), , drop = FALSE]
  expect_identical(j$line, c(3L, 5L))
  expect_identical(j$code, c("user_agent_joined_across_directive",
                             "user_agent_joined_across_blank"))
  # Bing ended `a`'s group at the Crawl-delay; the warning on line 3 names it.
  expect_match(j$message[[2L]],
               "shares a group with `User-agent: b` (line 3):", fixed = TRUE)
})

test_that("the info names only the agents since the last directive", {
  # Bing ends `a`'s group at the Sitemap, so only `b` shares `c`'s group on
  # Bing; the warning on line 3 already says `a` gains the rules on Google.
  d <- robots_validate_text(uaj_lines(
    "User-agent: a", "Sitemap: https://example.com/s.xml", "User-agent: b",
    "", "User-agent: c", "Disallow: /"
  ))$diagnostics
  j <- d[startsWith(d$code, "user_agent_joined"), , drop = FALSE]
  expect_identical(j$line, c(3L, 5L))
  expect_match(j$message[[2L]], paste0(
    "`User-agent: c` (line 5) shares a group with `User-agent: b` (line 3):"
  ), fixed = TRUE)
  expect_match(j$message[[2L]], "gives b no rules", fixed = TRUE)
})

test_that("moving a Sitemap out is offered only to agents meant to share", {
  # Moving it out of the run makes the User-agent lines adjacent, which
  # every engine joins (branch review): it is the fix for sharing, never
  # for keeping the rules away.
  r <- uaj_rows(uaj_internetcom, "user_agent_joined_across_directive")
  expect_no_match(r$message, "not meant to get these rules, move",
                  fixed = TRUE)
  # A group-level line such as Crawl-delay keeps its group, so moving it is
  # not offered at all.
  r <- uaj_rows(uaj_rro, "user_agent_joined_across_directive")
  expect_no_match(r$message, "move line", fixed = TRUE)
})

test_that("a blank-line join before a later directive is left to its warning", {
  # Bing ends `a` and `b`'s group at the Sitemap, so an info saying Google
  # and Bing give them line 6 would be wrong; the warning on line 5 names
  # them.
  d <- robots_validate_text(uaj_lines(
    "User-agent: a", "", "User-agent: b",
    "Sitemap: https://example.com/s.xml", "User-agent: c", "Disallow: /"
  ))$diagnostics
  j <- d[startsWith(d$code, "user_agent_joined"), , drop = FALSE]
  expect_identical(j$code, "user_agent_joined_across_directive")
  expect_identical(j$line, 5L)
  expect_match(j$message, "apply to a and b as well as to c", fixed = TRUE)
})

test_that("rules that restrict nothing are not reported as shared", {
  d <- robots_validate_text(uaj_lines(
    "User-agent: *", "Crawl-delay: 10", "User-agent: b", "Disallow:"
  ))$diagnostics
  expect_false(any(startsWith(d$code, "user_agent_joined")))
})

test_that("an opening line that names no crawler is not quoted", {
  r <- uaj_rows(uaj_lines(
    "User-agent: 123", "User-agent: a", "Crawl-delay: 1", "User-agent: b",
    "Disallow: /"
  ), "user_agent_joined_across_directive")
  expect_match(r$message, "joins the group that opened on line 1.",
               fixed = TRUE)
})

test_that("a long run keeps each message bounded", {
  n <- 2000L
  body <- uaj_lines(
    # Digits end a product token, so each name spells its number in letters.
    unlist(lapply(seq_len(n), function(i) {
      c(paste0("User-agent: bot", chartr("0123456789", "abcdefghij", i)), "")
    })),
    "Disallow: /"
  )
  r <- uaj_rows(body, "user_agent_joined_across_blank")
  expect_identical(nrow(r), n - 1L)
  expect_lt(max(nchar(r$message)), 1000L)
  expect_match(r$message[[n - 1L]], "and 1994 more", fixed = TRUE)
})
