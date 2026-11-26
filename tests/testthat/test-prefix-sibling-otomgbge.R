# ROBO-otomgbge: a literal rule with no trailing `/` or `$` matches every
# path that starts with it, so `Disallow: /feed` also matches `/feeds`.
# When the same crawlers' rules also list such a sibling, with the same
# type, the row notes that the shorter rule already matches it
# (`rule_prefix_sibling`, info). Every fixture is synthetic and generic.

ps_diag <- function(body) {
  robots_validate_text(body)$diagnostics
}

ps_codes <- function(body) {
  ps_diag(body)$code
}

ps_code <- "rule_prefix_sibling"

# Each fixture: a body and `today`, the codes it got before ROBO-otomgbge.
ps_fixtures <- list(
  one = list(body = "User-agent: *\nDisallow: /feed\nDisallow: /feeds\n",
             today = character(0)),
  login = list(
    body = "User-agent: *\nDisallow: /login\nDisallow: /login.php\n",
    today = character(0)
  ),
  allow_pair = list(body = "User-agent: Foo\nAllow: /about\nAllow: /aboutx\n",
                    today = character(0)),
  # Two groups naming different crawlers: no pair.
  split_other = list(
    body = paste0("User-agent: Foo\nDisallow: /feed\n\n",
                  "User-agent: Bar\nDisallow: /feeds\n"),
    today = character(0)
  ),
  # Two groups naming the same crawler merge into one.
  split_same = list(
    body = paste0("User-agent: Foo\nDisallow: /feed\n\n",
                  "User-agent: Foo\nDisallow: /feeds\n"),
    today = "user_agent_repeated_group"
  ),
  # With line 3 left out, the Allow on line 4 decides `/feeds`.
  allow_beside = list(
    body = paste0("User-agent: *\nDisallow: /feed\nDisallow: /feeds\n",
                  "Allow: /feeds\n"),
    today = "disallow_tied_by_allow"
  ),
  # With line 3 left out, the wildcard Allow on line 4 decides `/feedsx`.
  allow_takes_over = list(
    body = paste0("User-agent: *\nDisallow: /feed\nDisallow: /feedsx\n",
                  "Allow: /fe*sx\n"),
    today = character(0)
  ),
  opposite = list(body = "User-agent: *\nDisallow: /search\nAllow: /searchx\n",
                  today = character(0)),
  sub_path = list(
    body = "User-agent: *\nDisallow: /feed\nDisallow: /feed/rss\n",
    today = character(0)
  ),
  query = list(body = "User-agent: *\nDisallow: /feed\nDisallow: /feed?x\n",
               today = "rule_query_crawl_not_index"),
  star = list(body = "User-agent: *\nDisallow: /feed\nDisallow: /feeds*\n",
              today = character(0)),
  dollar = list(body = "User-agent: *\nDisallow: /feed\nDisallow: /feeds$\n",
                today = character(0)),
  percent = list(body = "User-agent: *\nDisallow: /a\nDisallow: /a%2F\n",
                 today = character(0)),
  stem_slash = list(body = "User-agent: *\nDisallow: /x/\nDisallow: /x/y\n",
                    today = "rule_slash_split"),
  stem_dollar = list(body = "User-agent: *\nDisallow: /x$\nDisallow: /xy\n",
                     today = "rule_end_anchor_query"),
  stem_star = list(body = "User-agent: *\nDisallow: /x*\nDisallow: /xy\n",
                   today = character(0)),
  stem_query = list(body = "User-agent: *\nDisallow: /a?b\nDisallow: /a?bc\n",
                    today = "rule_query_crawl_not_index"),
  root = list(body = "User-agent: *\nDisallow: /\nDisallow: /x\n",
              today = character(0)),
  empty = list(body = "User-agent: *\nDisallow:\nDisallow: /x\n",
               today = "allow_all_disallow"),
  # The comment cut leaves `/feed`, which pairs with `/feeds`.
  comment = list(
    body = "User-agent: *\nDisallow: /feed#x\nDisallow: /feeds\n",
    today = "rule_cut_by_comment"
  ),
  ai = list(
    body = paste0("User-agent: __usage_ai-training\nDisallow: /feed\n",
                  "Disallow: /feeds\n"),
    today = "ai_training_preference"
  ),
  # Google cuts `Foo/1.0` to `Foo`, so only its merge joins the groups.
  cut_agent = list(
    body = paste0("User-agent: Foo/1.0\nDisallow: /feed\n\n",
                  "User-agent: Foo\nDisallow: /feeds\n"),
    today = c("user_agent_cut", "user_agent_repeated_group")
  ),
  # An `=` draws the crawl-not-index note (ROBO-jnnnkyat) as well.
  equals = list(body = "User-agent: *\nDisallow: /a=b\nDisallow: /a=bc\n",
                today = "rule_query_crawl_not_index"),
  seven = list(
    body = paste0("User-agent: *\nDisallow: /feed\n",
                  paste0("Disallow: /feed", letters[1:7], "\n",
                         collapse = "")),
    today = character(0)
  )
)

# The fixtures that get the row, last, after the codes they got before.
ps_rows <- c("one", "login", "allow_pair", "split_same", "comment", "equals",
             "seven")

test_that("ROBO-otomgbge: the row joins today's codes, nothing else moves", {
  for (name in names(ps_fixtures)) {
    want <- ps_fixtures[[name]]$today
    if (name %in% ps_rows) {
      want <- c(want, ps_code)
    }
    expect_identical(ps_codes(ps_fixtures[[name]]$body), want, label = name)
  }
})

# The row's text for one `P` and its siblings, as the check writes it.
ps_one <- function(line, value, siblings, noun = "Disallow") {
  listed <- if (grepl("), '|and", siblings)) "which are" else "which is"
  paste0(
    "The ", noun, " on line ", line, " ('", value, "') also matches ",
    siblings, ", ", listed, " listed separately for the same crawlers. ",
    "A rule with no trailing '/' or '$' matches every path that starts ",
    "with it (RFC 9309 section 2.2.2)."
  )
}

ps_message <- function(body) {
  d <- ps_diag(body)
  d$message[d$code == ps_code]
}

ps_line <- function(body) {
  d <- ps_diag(body)
  d$line[d$code == ps_code]
}

test_that("ROBO-otomgbge: the row names both lines", {
  body <- ps_fixtures$one$body
  expect_identical(ps_line(body), 2L)
  expect_identical(ps_message(body), ps_one(2L, "/feed", "'/feeds' (line 3)"))
  expect_identical(ps_message(ps_fixtures$login$body),
                   ps_one(2L, "/login", "'/login.php' (line 3)"))
  expect_identical(ps_message(ps_fixtures$allow_pair$body),
                   ps_one(2L, "/about", "'/aboutx' (line 3)", "Allow"))
  # Merged groups: the row sits on the `P` line of the first group.
  expect_identical(ps_line(ps_fixtures$split_same$body), 2L)
  expect_identical(ps_message(ps_fixtures$split_same$body),
                   ps_one(2L, "/feed", "'/feeds' (line 5)"))
  # The comment cut leaves `/feed`.
  expect_identical(ps_message(ps_fixtures$comment$body),
                   ps_one(2L, "/feed", "'/feeds' (line 3)"))
  # Five siblings, then a count.
  expect_identical(
    ps_message(ps_fixtures$seven$body),
    ps_one(2L, "/feed", paste0(
      "'/feeda' (line 3), '/feedb' (line 4), '/feedc' (line 5), ",
      "'/feedd' (line 6), '/feede' (line 7) and 2 more"
    ))
  )
  # The sibling may come first; the row sits on the `P` line.
  later <- "User-agent: *\nDisallow: /feeds\nDisallow: /feed\n"
  expect_identical(ps_line(later), 3L)
  expect_identical(ps_message(later), ps_one(3L, "/feed", "'/feeds' (line 2)"))
  # A sibling ending in `/` that goes on from `P` without one still counts.
  expect_identical(
    ps_message("User-agent: *\nDisallow: /feed\nDisallow: /feeds/\n"),
    ps_one(2L, "/feed", "'/feeds/' (line 3)")
  )
})

test_that("ROBO-otomgbge: one row per group, pairs across rules", {
  body <- paste0("User-agent: Foo\nUser-agent: Bar\nDisallow: /feed\n",
                 "Disallow: /feeds\nAllow: /login\nAllow: /login.php\n")
  d <- ps_diag(body)
  expect_identical(d$code, ps_code)
  expect_identical(d$line, 3L)
  expect_identical(d$message, paste0(
    "Rules for the same crawlers also match paths listed separately: line 3 ",
    "('/feed') matches '/feeds' (line 4) and line 5 ('/login') matches ",
    "'/login.php' (line 6). A rule with no trailing '/' or '$' matches every ",
    "path that starts with it (RFC 9309 section 2.2.2). This holds for ",
    "every crawler the group names: 'Foo' and 'Bar'."
  ))
  # Two groups of different crawlers: one row each.
  two <- paste0("User-agent: Foo\nDisallow: /feed\nDisallow: /feeds\n\n",
                "User-agent: Bar\nDisallow: /feed\nDisallow: /feeds\n")
  expect_identical(ps_line(two), c(2L, 6L))
  # A chain: each sibling pairs with the longest rule that leads it, and a
  # subpath of `/ab` pairs with none.
  chain <- paste0("User-agent: *\nDisallow: /a\nDisallow: /ab\n",
                  "Disallow: /abc\nDisallow: /ab/x\n")
  expect_identical(ps_message(chain), paste0(
    "Rules for the same crawlers also match paths listed separately: line 2 ",
    "('/a') matches '/ab' (line 3) and line 3 ('/ab') matches '/abc' ",
    "(line 4). A rule with no trailing '/' or '$' matches every path that ",
    "starts with it (RFC 9309 section 2.2.2)."
  ))
  # A repeat of the sibling is not named; duplicate_rule reports it.
  dup <- "User-agent: *\nDisallow: /feed\nDisallow: /feeds\nDisallow: /feeds\n"
  expect_identical(ps_codes(dup), c("duplicate_rule", ps_code))
  expect_identical(ps_message(dup), ps_one(2L, "/feed", "'/feeds' (line 3)"))
})

test_that("ROBO-otomgbge: every crawler of the sibling's group needs `P`", {
  # `P`'s group names more crawlers than the sibling's: every crawler of
  # the sibling's group has both.
  wider <- paste0("User-agent: Foo\nUser-agent: Bar\nDisallow: /feed\n\n",
                  "User-agent: Foo\nDisallow: /feeds\n")
  expect_identical(ps_codes(wider),
                   c("user_agent_repeated_group", ps_code))
  expect_identical(ps_line(wider), 3L)
  # The sibling's group names a crawler that lacks `P`.
  narrower <- paste0("User-agent: Foo\nDisallow: /feed\n\n",
                     "User-agent: Foo\nUser-agent: Bar\nDisallow: /feeds\n")
  expect_identical(ps_codes(narrower), "user_agent_repeated_group")
  # Google's merge joins `Foo/1.0` and `Foo`; the whole-value merge does
  # not, so the merges disagree and there is no row.
  expect_false(ps_code %in% ps_codes(ps_fixtures$cut_agent$body))
})

test_that("ROBO-otomgbge: one row per `P` line, narrower siblings named", {
  # `P`'s group names `a` and `b`; each sibling sits in a group of one.
  body <- paste0("User-agent: a\nUser-agent: b\nDisallow: /feed\n\n",
                 "User-agent: a\nDisallow: /feeds\n\n",
                 "User-agent: b\nDisallow: /feeds\n")
  expect_identical(ps_line(body), 3L)
  expect_identical(ps_message(body), ps_one(
    3L, "/feed", "'/feeds' (line 6, for 'a') and '/feeds' (line 9, for 'b')"
  ))
  # The sibling's group names fewer crawlers than `P`'s: it names them, and
  # the row names no group.
  wider <- paste0("User-agent: Foo\nUser-agent: Bar\nDisallow: /feed\n\n",
                  "User-agent: Foo\nDisallow: /feeds\n")
  expect_identical(ps_message(wider),
                   ps_one(3L, "/feed", "'/feeds' (line 6, for 'Foo')"))
})

test_that("ROBO-otomgbge: long values print apart", {
  # Past 40 bytes `P` keeps its head and the sibling its tail, so the two
  # never print alike.
  p <- paste0("/", strrep("a", 52L))
  body <- paste0("User-agent: *\nDisallow: ", p, "\nDisallow: ", p, "b\n")
  head <- paste0("/", strrep("a", 35L), "...")
  tail <- paste0("...", strrep("a", 35L), "b")
  expect_identical(ps_message(body),
                   ps_one(2L, head, paste0("'", tail, "' (line 3)")))
})

test_that("ROBO-otomgbge: a repeat of `P` that Google's merge joins", {
  # Google cuts `Bot1`..`Bot3` to `Bot`, so its merge joins the groups and
  # the first group's `/d1` decides each group's `/d10`: it has `P`'s type
  # and value, so every group gets its row.
  body <- paste0("User-agent: Bot", 1:3, "\n",
                 paste0("Disallow: /d", 1:11, "\n", collapse = ""),
                 collapse = "\n")
  expect_identical(ps_line(body), c(2L, 15L, 28L))
  # One `P` line for every class of the sibling's group: here each class
  # has its own, so no row names one line for both.
  apart <- paste0("User-agent: Foo\nDisallow: /feed\n\n",
                  "User-agent: Bar\nDisallow: /feed\n\n",
                  "User-agent: Foo\nUser-agent: Bar\nDisallow: /feeds\n")
  expect_false(ps_code %in% ps_codes(apart))
})

# The Google, Bing and Yandex decisions and deciding lines for `paths`.
ps_engines <- list(google = "Googlebot", bing = "bingbot", yandex = "Yandex")

ps_read <- function(body, paths, backend) {
  token <- ps_engines[[backend]]
  robots_evaluate_text_v1(
    gsub("%s", token, body, fixed = TRUE),
    paste0("https://example.com", paths), token, backend, backend
  )$results[, c("url_decision", "matched_line")]
}

test_that("ROBO-otomgbge: with the sibling left out, `P` decides its path", {
  # Each reported pair on every backend: the sibling's line written empty,
  # `P`'s line decides the sibling's path with the same decision.
  cases <- list(
    list("User-agent: %s\nDisallow: /feed\nDisallow:\n", "/feeds", 2L,
         "disallow"),
    list("User-agent: %s\nDisallow: /login\nDisallow:\n", "/login.php", 2L,
         "disallow"),
    list("User-agent: %s\nDisallow: /\nAllow: /about\nAllow:\n", "/aboutx",
         3L, "allow"),
    list("User-agent: %s\nDisallow: /a\nDisallow: /ab\nDisallow:\n", "/abc",
         3L, "disallow")
  )
  for (case in cases) {
    for (backend in names(ps_engines)) {
      read <- ps_read(case[[1L]], case[[2L]], backend)
      expect_identical(read$url_decision, case[[4L]], label = backend)
      expect_identical(read$matched_line, case[[3L]], label = backend)
    }
  }
  # The fixtures that stay silent: another rule decides the path.
  silent <- list(
    list("User-agent: %s\nDisallow: /feed\nDisallow:\nAllow: /feeds\n",
         "/feeds", 4L),
    list("User-agent: %s\nDisallow: /feed\nDisallow:\nAllow: /fe*sx\n",
         "/feedsx", 4L)
  )
  for (case in silent) {
    read <- ps_read(case[[1L]], case[[2L]], "google")
    expect_identical(read$url_decision, "allow")
    expect_identical(read$matched_line, case[[3L]])
  }
  # Allow under a full block: the pair reads under `Disallow: /`.
  body <- "User-agent: Foo\nDisallow: /\nAllow: /about\nAllow: /aboutx\n"
  expect_identical(ps_message(body),
                   ps_one(3L, "/about", "'/aboutx' (line 4)", "Allow"))
})

ps_groups <- function(body) {
  if (is.character(body)) {
    body <- charToRaw(body)
  }
  validation_groups(as.data.frame(robotstxtr_validation_parse_(body),
                                  stringsAsFactors = FALSE))
}

test_that("ROBO-otomgbge: the candidate scans make each exclusion", {
  rules <- ps_groups(paste0(
    "User-agent: *\nDisallow: /feed\nDisallow: /feeds\nDisallow: /feed/rss\n",
    "Disallow: /x/\nDisallow: /x/y\nAllow: /feedz\nDisallow: /feeds*\n",
    "Disallow: /fe%41\nDisallow: /\nDisallow: /a\nDisallow: /a/./b\n"
  ))$rules
  cand <- prefix_sibling_candidates(rules)
  # `/feeds` and `/feed/rss` (led by `/feed`); `/x/y` is led by `/x/` only,
  # which ends in `/`; the Allow has no Allow to lead it.
  expect_identical(rules$value[cand$at], c("/feeds", "/feed/rss"))
  # The prefix chain: the longest pushed proper prefix, in byte order.
  chain <- prefix_sibling_chain(c("/a", "/ab", "/abc", "/b", "/a-"),
                                c(TRUE, TRUE, FALSE, TRUE, TRUE))
  expect_identical(chain$top, c(NA, 1L, 2L, NA, 1L))
  expect_identical(chain$depth, c(0L, 1L, 2L, 0L, 1L))
  # Passes: depth among the candidates' values, then type.
  rules <- ps_groups(paste0(
    "User-agent: *\nDisallow: /a\nDisallow: /ab\nDisallow: /abc\n",
    "Allow: /a\nAllow: /ab\n"
  ))$rules
  cand <- prefix_sibling_candidates(rules)
  expect_identical(prefix_sibling_passes(rules, cand$at),
                   c("0 disallow", "1 disallow", "0 allow"))
})

ps_cut_text <- paste0("User-agent: *\nDisallow: /feed\nDisallow: /feeds\n",
                      "Allow: /feeds", strrep("x", 200L), "\n")

test_that("ROBO-otomgbge: a cut body is skipped, a NUL body is Google's", {
  body <- charToRaw(ps_cut_text)[seq_len(55L)]
  x <- validate_document_bytes(body, "s", "supplied", max_bytes = 55L,
                               body_truncated = TRUE)
  expect_false(ps_code %in% x$diagnostics$code)
  x <- validate_document_bytes(body, "s", "supplied")
  expect_identical(x$diagnostics$message[x$diagnostics$code == ps_code],
                   ps_one(2L, "/feed", "'/feeds' (line 3)"))
  # `P` a NUL cuts takes part as Google cuts it, and the row says so.
  cut <- c(charToRaw("User-agent: *\nDisallow: /feed"), as.raw(0),
           charToRaw("zz\nDisallow: /feeds\n"))
  d <- ps_diag(cut)
  expect_identical(d$code, c("nul_byte", "rule_cut_by_nul", ps_code))
  expect_identical(d$message[[3L]], paste0(
    ps_one(2L, "/feed", "'/feeds' (line 3)"),
    " This is Google's reading, which ends each line at its first NUL; ",
    "Bing and Yandex read the NUL as an ordinary byte."
  ))
  # A gzip body is reported as compressed and never read as rules.
  gz <- c(as.raw(c(0x1f, 0x8b, 0x08, 0x00)),
          charToRaw("\nUser-agent: *\nDisallow: /feed\nDisallow: /feeds\n"))
  expect_false(ps_code %in% ps_codes(gz))
})

test_that("ROBO-otomgbge: info only, a valid file stays valid", {
  x <- robots_validate_text(ps_fixtures$one$body)
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$diagnostics$severity, "info")
})

# The counts a check that stopped hands out, as slash_stop() builds them.
ps_stopped <- function(found, checked, value) {
  list(found = found, checked = checked, skipped = found - checked,
       value = value)
}

test_that("ROBO-otomgbge: candidates past the work budget get no row", {
  # The lookup costs 2 (`P`'s class row, one step of the walk), the pass
  # the file's 2 rules, the reading 3: from 7 the row.
  groups <- ps_groups("User-agent: Foo\nDisallow: /feed\nDisallow: /feeds\n")
  for (budget in list(NULL, 7)) {
    found <- prefix_sibling_diagnostics(groups, budget = budget)
    expect_identical(found$line, 2L)
    expect_null(attr(found, "stopped"))
  }
  for (budget in 0:6) {
    found <- prefix_sibling_diagnostics(groups, budget = budget)
    expect_identical(nrow(found), 0L, label = budget)
    expect_identical(attr(found, "stopped"), ps_stopped(1L, 0L, "/feeds"),
                     label = budget)
  }
  expect_identical(
    slash_stop_message("prefix_sibling", ps_stopped(1L, 0L, "/feeds")),
    paste0(
      "This file has 1 rule whose path starts with a shorter rule of the ",
      "same type, such as '/feeds'. For each one, the validator checks ",
      "whether the shorter rule already matches its path for the same ",
      "crawlers. This file is too large to check it quickly, so it was not ",
      "checked. It was skipped, and it may be matched that way."
    )
  )
  # Candidates are checked in line order: the second runs out.
  groups <- ps_groups(paste0("User-agent: Foo\nDisallow: /feed\n",
                             "Disallow: /feeds\nDisallow: /login\n",
                             "Disallow: /login.php\n"))
  found <- prefix_sibling_diagnostics(groups, budget = 13)
  expect_identical(found$message, ps_one(2L, "/feed", "'/feeds' (line 3)"))
  stop <- attr(found, "stopped")
  expect_identical(stop, ps_stopped(2L, 1L, "/login.php"))
  expect_identical(slash_stop_message("prefix_sibling", stop), paste0(
    "This file has 2 rules whose paths start with a shorter rule of the ",
    "same type, such as '/login.php'. For each one, the validator checks ",
    "whether the shorter rule already matches its path for the same ",
    "crawlers. This file is too large to check them all quickly, so only ",
    "the first was checked, in line order. The other 1 was skipped, and it ",
    "may be matched that way."
  ))
  expect_null(attr(prefix_sibling_diagnostics(groups, budget = 14),
                   "stopped"))
  # A pass the budget cannot pay for reads nothing: the lookup costs 2 and
  # the pass the file's 2 rules, so at 3 no reading is made.
  groups <- ps_groups("User-agent: Foo\nDisallow: /feed\nDisallow: /feeds\n")
  calls <- new.env()
  calls$n <- 0L
  real <- witness_pair_readings
  local_mocked_bindings(witness_pair_readings = function(...) {
    calls$n <- calls$n + 1L
    real(...)
  })
  found <- prefix_sibling_diagnostics(groups, budget = 3)
  expect_identical(calls$n, 0L)
  expect_identical(attr(found, "stopped"), ps_stopped(1L, 0L, "/feeds"))
  found <- prefix_sibling_diagnostics(groups, budget = 7)
  expect_identical(calls$n, 1L)
  # A long chain of prefixes stops at the default budget with one row and
  # one stop row, in bounded time.
  chain <- paste0("User-agent: *\n",
                  paste0("Disallow: /", strrep("a", 1:400), "\n",
                         collapse = ""))
  d <- ps_diag(chain)
  expect_identical(sum(d$code == ps_code), 1L)
  found <- prefix_sibling_diagnostics(ps_groups(chain))
  stop <- attr(found, "stopped")
  if (!is.null(stop)) {
    expect_identical(sum(d$code == "rule_check_stopped"), 1L)
    expect_gt(stop$checked, 0L)
  }
})
