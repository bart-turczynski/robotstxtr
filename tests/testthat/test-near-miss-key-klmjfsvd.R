# ROBO-klmjfsvd: an unknown key that is a near miss of `User-agent`, `Allow`
# or `Disallow` (a small edit distance, a stray leading non-letter, or
# `Deny`). A rule near miss is applied by no engine; for a User-agent near
# miss the message states Google's reading only, then that Bing and Yandex
# may read the following lines differently. Fixtures are synthetic.

nm_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")
nm_text <- function(...) robots_validate_text(nm_lines(...))
nm_rows <- function(x, code = "unknown_directive") {
  d <- x$diagnostics
  d[d$code == code, , drop = FALSE]
}
nm_plain <- "Directive is not recognized by this validation profile."
nm_others <- " Bing and Yandex may read the following lines differently."

# One "decision line" string per backend, for one path on example.com: each
# backend answers for its own crawler token (as dg_outcome() does).
nm_outcome <- function(body, path, google_token = "ExampleBot") {
  url <- paste0("https://example.com", path)
  run <- function(backend, token) {
    r <- robots_evaluate_text_v1(body, url, token, "google", backend)$results
    paste(r$url_decision, r$matched_line)
  }
  c(google = run("google", google_token), bing = run("bing", "bingbot"),
    yandex = run("yandex", "Yandex"))
}

# Google's decision for `token` on /page, the reading the User-agent
# sentence states.
nm_google <- function(lines, token, path = "/page") {
  r <- robots_evaluate_text_v1(nm_lines(lines),
                               paste0("https://example.com", path), token,
                               "google", "google")$results
  paste(r$url_decision, r$matched_line)
}

nm_ticket <- nm_lines("User-agent: *", "Disallow: /tmp/", "",
                      "User-agnet: ExampleBot", "Disallow: /")

# Keys within range, by the directive they resemble.
nm_near <- list(
  "User-agnet" = "user-agent", "USER-AGNET" = "user-agent",
  "Usr-agent" = "user-agent", "User--agent" = "user-agent",
  "user_agent" = "user-agent", "Usr-agnt" = "user-agent",
  "Allwo" = "allow", "Alow" = "allow", "//Allow" = "allow",
  "Disaloow" = "disallow", "DISALLOOW" = "disallow", "Disallw" = "disallow",
  "Dsalow" = "disallow", "/Disallow" = "disallow", "Disavow" = "disallow",
  "///Disallow" = "disallow", "1Disallow" = "disallow", "Deny" = "disallow",
  "DENY" = "disallow"
)

# Consistency checks with the package's backends, for the shapes whose
# reading on Bing and Yandex has a source (Bing:
# design/robotstxtbing-v2-spec.md §9.3 and robotstxt-cpp-bing's field-name
# decisions, 2026-11-23; Yandex: robotstxtyandex ydx-parser-user-agent-space
# and its field-name typo closure, 2026-08-05). The message states Google's
# reading only.
test_that("the backends ignore a near-miss User-agent line after a rule", {
  # The ticket's example: line 5 joins the `*` group.
  expect_identical(
    nm_outcome(nm_ticket, "/page"),
    c(google = "disallow 5", bing = "disallow 5", yandex = "disallow 5")
  )
})

test_that("the backends leave rules after a near miss at the start ungrouped", {
  body <- nm_lines("User-agnet: ExampleBot", "Disallow: /", "",
                   "User-agent: *", "Disallow: /tmp/")
  expect_identical(
    nm_outcome(body, "/page"),
    c(google = "allow NA", bing = "allow NA", yandex = "allow NA")
  )
})

test_that("the backends apply no near-miss rule", {
  for (key in c("Disaloow", "Deny", "Disallw", "Alow")) {
    body <- nm_lines("User-agent: *", "Disallow: /tmp/", paste0(key, ": /"))
    expect_identical(
      nm_outcome(body, "/page"),
      c(google = "allow NA", bing = "allow NA", yandex = "allow NA"),
      info = key
    )
  }
})

test_that("Google keeps a stacked run across a near miss", {
  # The near miss between the stacked lines, then a rule or a User-agent
  # line: Google keeps every agent above it in the group.
  lines <- c("User-agent: ExampleBot", "User-agent: Other", "User-agnet: q",
             "Disallow: /")
  expect_identical(nm_google(lines, "ExampleBot"), "disallow 4")
  lines <- c("User-agent: ExampleBot", "User-agnet: q", "User-agent: Other",
             "Disallow: /")
  expect_identical(nm_google(lines, "ExampleBot"), "disallow 4")
})

test_that("a near-miss key keeps unknown_directive as its only key row", {
  for (key in names(nm_near)) {
    x <- nm_text("User-agent: *", "Disallow: /tmp/", paste0(key, ": /x"))
    row <- nm_rows(x)
    expect_identical(row$line, 3L, label = key)
    expect_identical(row$severity, "warning", label = key)
    expect_identical(row$directive, ascii_lower(key), label = key)
    expect_false(any(c("accepted_directive_typo", "accepted_directive_prefix")
                     %in% x$diagnostics$code), label = key)
  }
})

nm_labels <- c("user-agent" = "User-agent", allow = "Allow",
               disallow = "Disallow")

# The message's start for `key` resembling `target`.
nm_lead <- function(key, target, reader = "no engine reads") {
  sprintf("%s The key `%s` resembles `%s`, but %s it as %s", nm_plain, key,
          nm_labels[[target]], reader, nm_labels[[target]])
}
nm_rule <- function(key, target) {
  paste0(nm_lead(key, target), ", so no engine applies this rule.")
}
nm_no_group <- function(key) {
  paste0(nm_lead(key, "user-agent", "Google does not read"),
         ", so on Google it starts no group.")
}
# A User-agent near miss's message: its lead, `middle`, the generic clause.
nm_agent <- function(middle = "", key = "User-agnet") {
  paste0(nm_no_group(key), middle, nm_others)
}
nm_stay <- function(rules, named) {
  sprintf(paste0(" The rules after it, up to the next User-agent line (%s), ",
                 "stay with the group above it on Google, for %s."),
          rules, named)
}

test_that("the ticket's example names User-agent and Google's group", {
  x <- robots_validate_text(nm_ticket)
  row <- nm_rows(x)
  expect_identical(row$line, 4L)
  expect_identical(row$severity, "warning")
  expect_identical(row$message, nm_agent(nm_stay("line 5", "`*`")))
})

test_that("each near-miss key names the directive it resembles", {
  for (key in names(nm_near)) {
    target <- nm_near[[key]]
    x <- nm_text("User-agent: *", "Disallow: /tmp/", paste0(key, ": /x"))
    expected <- if (identical(target, "user-agent")) {
      nm_agent(key = key)
    } else {
      nm_rule(key, target)
    }
    expect_identical(nm_rows(x)$message, expected, label = key)
  }
})

test_that("the ticket's rule near misses name Disallow", {
  x <- nm_text("User-agent: *", "Disaloow: /private/", "Deny: /")
  expect_identical(nm_rows(x)$message,
                   c(nm_rule("Disaloow", "disallow"),
                     nm_rule("Deny", "disallow")))
  # The only rule dropped: no_rules still says so.
  expect_true("no_rules" %in% x$diagnostics$code)
})

test_that("the generic clause follows every User-agent shape, no rule", {
  bodies <- list(
    after_rule = c("User-agent: *", "Disallow: /a", "User-agnet: b",
                   "Disallow: /"),
    nothing_after = c("User-agent: *", "Disallow: /a", "User-agnet: b"),
    no_group = c("User-agnet: b", "Disallow: /"),
    alone = "User-agnet: b",
    stacked = c("User-agent: a", "User-agnet: b", "User-agent: c",
                "Disallow: /"),
    stacked_empty = c("User-agent:", "User-agnet: b", "User-agent: c")
  )
  for (shape in names(bodies)) {
    message <- nm_rows(nm_text(bodies[[shape]]))$message
    expect_true(endsWith(message, nm_others), info = shape)
    expect_identical(lengths(gregexpr("Bing", message, fixed = TRUE)), 1L,
                     info = shape)
  }
  for (key in c("Deny", "Allwo", "Disaloow")) {
    message <- nm_rows(nm_text("User-agent: *", paste0(key, ": /")))$message
    expect_false(grepl("Bing|Yandex", message), info = key)
  }
})

test_that("a near miss before any User-agent leaves its rules ungrouped", {
  lines <- c("User-agnet: ExampleBot", "Disallow: /", "Allow: /a", "",
             "User-agent: *", "Disallow: /tmp/")
  expect_identical(nm_google(lines, "ExampleBot"), "allow NA")
  x <- nm_text(lines)
  expect_identical(nm_rows(x)$message, nm_agent(paste(
    "", "The rules after it, up to the next User-agent line (lines 2-3), are",
    "in no group on Google, so Google applies none of them."
  )))
  expect_identical(
    x$diagnostics$line[x$diagnostics$code == "rule_without_user_agent"],
    2:3
  )
  # After a rule that is itself in no group, the same.
  x <- nm_text("Disallow: /a", "User-agnet: ExampleBot", "Disallow: /")
  expect_identical(nm_rows(x)$message, nm_agent(paste(
    "", "The rules after it, up to the next User-agent line (line 3), are in",
    "no group on Google, so Google applies none of them."
  )))
  # Nothing after it: the line's own effect only.
  expect_identical(nm_rows(nm_text("User-agnet: b"))$message, nm_agent())
})

test_that("a near miss between stacked User-agent lines states Google's run", {
  lines <- c("User-agent: ExampleBot", "User-agent: bingbot",
             "User-agent: Yandex", "User-agnet: Other", "User-agent: Other",
             "Disallow: /")
  expect_identical(nm_google(lines, "ExampleBot"), "disallow 6")
  x <- nm_text(lines)
  expect_identical(nm_rows(x)$message, nm_agent(paste(
    "", "Google keeps the User-agent run across it, so the rules after the",
    "next User-agent line (line 5) apply to the agents above it too",
    "(`ExampleBot`, `bingbot` and `Yandex`). See the",
    "user_agent_joined_across_directive row on line 5."
  )))
  expect_identical(
    x$diagnostics$line[x$diagnostics$code ==
                         "user_agent_joined_across_directive"],
    5L
  )
  # No rule after the next User-agent line: no rules are named, and no
  # joined row fires, so no pointer.
  x <- nm_text("User-agent: a", "User-agnet: b", "User-agent: c")
  expect_identical(nm_rows(x)$message, nm_agent(paste(
    "", "Google keeps the User-agent run across it, so the agents above it",
    "(`a`) share the group of the next User-agent line (line 3)."
  )))
  # The agents above it only empty values: none named (and no joined row).
  x <- nm_text("User-agent:", "User-agnet: b", "User-agent: c", "Disallow: /")
  expect_identical(nm_rows(x)$message, nm_agent(paste(
    "", "Google keeps the User-agent run across it, to the next User-agent",
    "line (line 3)."
  )))
  # A blank or Crawl-delay line in the run: Google's run is the same.
  for (mid in c("", "Crawl-delay: 1", "# c")) {
    lines <- c("User-agent: ExampleBot", mid, "User-agnet: x",
               "User-agent: Other", "Disallow: /")
    expect_identical(nm_google(lines, "ExampleBot"), "disallow 5", info = mid)
    expect_identical(nm_rows(nm_text(lines))$message, nm_agent(paste(
      "", "Google keeps the User-agent run across it, so the rules after the",
      "next User-agent line (line 4) apply to the agents above it too",
      "(`ExampleBot`). See the user_agent_joined_across_directive row on",
      "line 4."
    )), info = mid)
  }
})

test_that("a rule after a near miss below a User-agent line keeps the group", {
  lines <- c("User-agent: ExampleBot", "User-agent: B", "User-agnet: b",
             "Disallow: /", "", "User-agent: c", "Disallow: /y")
  expect_identical(nm_google(lines, "ExampleBot"), "disallow 4")
  expect_identical(nm_rows(nm_text(lines))$message,
                   nm_agent(nm_stay("line 4", "`ExampleBot` and `B`")))
})

test_that("after a rule, the agents named are Google's group", {
  # Google joins `ExampleBot` and `B` across line 2 whatever it holds.
  for (mid in c("Foo: 1", "Crawl-delay: 1", "User-agnet: q", "", "# c",
                "Sitemap: https://example.com/s.xml")) {
    lines <- c("User-agent: ExampleBot", mid, "User-agent: B", "Disallow: /x",
               "User-agnet: c", "Disallow: /")
    expect_identical(nm_google(lines, "ExampleBot"), "disallow 6", info = mid)
    row <- nm_rows(nm_text(lines))
    expect_identical(row$message[row$line == 5L],
                     nm_agent(nm_stay("line 6", "`ExampleBot` and `B`")),
                     info = mid)
  }
  # A User-agent line Google reads in a typo form, and an empty value.
  x <- nm_text("User-agent: A", "Useragent: B", "User-agent:", "Disallow: /x",
               "User-agnet: c", "Disallow: /")
  expect_identical(nm_rows(x)$message,
                   nm_agent(nm_stay("line 6", "`A` and `B`")))
  # Rules Google reads in a typo, prefix or colonless form count.
  for (rule in c("Diasllow: /", "Disallowed: /", "Disallow /")) {
    lines <- c("User-agent: ExampleBot", "Disallow: /x", "User-agnet: c",
               rule)
    expect_identical(nm_google(lines, "ExampleBot"), "disallow 4", info = rule)
    expect_identical(nm_rows(nm_text(lines))$message,
                     nm_agent(nm_stay("line 4", "`ExampleBot`")), info = rule)
  }
})

test_that("the agents are counted from the group's first User-agent line", {
  # The near miss in a later group: `X` is in the first group only.
  lines <- c("User-agent: X", "Disallow: /a", "", "User-agent: Y",
             "Disallow: /b", "User-agnet: c", "Disallow: /")
  expect_identical(nm_google(lines, "X"), "allow NA")
  expect_identical(nm_google(lines, "Y"), "disallow 7")
  expect_identical(nm_rows(nm_text(lines))$message,
                   nm_agent(nm_stay("line 7", "`Y`")))
  # The same in the stacked shape.
  x <- nm_text("User-agent: X", "Disallow: /a", "User-agent: Y",
               "User-agnet: c", "User-agent: Z", "Disallow: /")
  expect_true(grepl("apply to the agents above it too (`Y`).",
                    nm_rows(x)$message, fixed = TRUE))
})

test_that("the group's agents are capped at five and each named once", {
  agents <- sprintf("User-agent: bot%d", 1:7)
  x <- nm_text(agents, "Disallow: /a", "User-agnet: B", "Disallow: /b")
  expect_true(grepl(paste0("for `bot1`, `bot2`, `bot3`, `bot4`, `bot5` and ",
                           "2 more."),
                    nm_rows(x)$message, fixed = TRUE))
  # A global line is named `*`, and a repeated agent once, in any case.
  x <- nm_text("User-agent: * bot", "User-agent: a", "User-agent: a",
               "User-agent: A", "Disallow: /a", "User-agnet: B",
               "Disallow: /b")
  expect_identical(nm_rows(x)$message,
                   nm_agent(nm_stay("line 7", "`*` and `a`")))
  # Empty User-agent values name no crawler.
  x <- nm_text("User-agent:", "User-agnet: B", "Disallow: /b")
  expect_identical(nm_rows(x)$message, nm_agent(paste(
    "", "The rules after it, up to the next User-agent line (line 3), stay",
    "with the group above it on Google."
  )))
})

test_that("agent names are escaped and cut in the code span", {
  x <- nm_text("User-agent: a`b", "Disallow: /x", "User-agnet: q",
               "Disallow: /")
  expect_identical(nm_rows(x)$message,
                   nm_agent(nm_stay("line 4", "`a\\x60b`")))
  long <- strrep("b", 200L)
  x <- nm_text(paste("User-agent:", long), "Disallow: /x", "User-agnet: q",
               "Disallow: /")
  expect_identical(nm_rows(x)$message, nm_agent(nm_stay(
    "line 4", paste0("`", strrep("b", 60L), "...`")
  )))
})

test_that("a near miss with nothing after it says only that", {
  x <- nm_text("User-agent: *", "Disallow: /a", "User-agnet: B",
               "User-agent: C", "Disallow: /")
  expect_identical(nm_rows(x)$message, nm_agent())
})

test_that("a lone CR body: Google's lines, Google's reading", {
  x <- robots_validate_text(
    "User-agent: *\rDisallow: /a\rUser-agnet: x\rDisallow: /\r"
  )
  expect_identical(nm_rows(x)$message, nm_agent(nm_stay("line 4", "`*`")))
  # A rule near miss speaks for Google only there.
  x <- robots_validate_text("User-agent: *\rDeny: /\r")
  expect_identical(nm_rows(x)$message, paste0(
    nm_lead("Deny", "disallow", "Google does not read"),
    ", so Google does not apply this rule."
  ))
})

test_that("a CRLF body keeps the wording for every engine", {
  x <- robots_validate_text("User-agent: a\r\nDeny: /\r\n")
  expect_identical(nm_rows(x)$message, nm_rule("Deny", "disallow"))
})

test_that("a cut body says lines past the cut were not read", {
  body <- charToRaw(paste0(nm_ticket, "Disallow: /partial"))
  x <- validate_document_bytes(body, "s", "supplied",
                               max_bytes = length(body),
                               body_truncated = TRUE)
  expect_identical(nm_rows(x)$message, nm_agent(paste0(
    nm_stay("line 5", "`*`"),
    " The body was cut, and lines past the cut were not read."
  )))
})

test_that("an upper-case key folds the same under every locale", {
  # ascii_lower(), not tolower(): under tr_TR `I` would not fold to `i`.
  x <- nm_text("User-agent: *", "DISALLOOW: /x", "USER-AGNET: y")
  expect_identical(nm_rows(x)$message, c(
    nm_rule("DISALLOOW", "disallow"), nm_agent(key = "USER-AGNET")
  ))
})

test_that("accepted typos and prefix keys get no unknown_directive row", {
  for (key in c("Dissallow", "Useragent", "Disalow", "Dissalow", "Diasllow")) {
    x <- nm_text("User-agent: *", paste0(key, ": /x"))
    expect_identical(nrow(nm_rows(x)), 0L, label = key)
    expect_true("accepted_directive_typo" %in% x$diagnostics$code,
                label = key)
  }
  for (key in c("Allows", "Disallowed", "User-agents")) {
    x <- nm_text("User-agent: *", paste0(key, ": /x"))
    expect_identical(nrow(nm_rows(x)), 0L, label = key)
  }
})

test_that("keys out of range keep the plain message", {
  # Alwo is two edits from allow (bound 1); Dsalw three from disallow and
  # Usr-agt three from user-agent (bound 2); Below and Follow are two from
  # allow; Foo, Agent and Denyall resemble none.
  for (key in c("Foo", "Alwo", "Dsalw", "Usr-agt", "Denyall", "Agent",
                "Below", "Follow")) {
    x <- nm_text("User-agent: *", "Disallow: /tmp/", paste0(key, ": 1"))
    expect_identical(nm_rows(x)$message, nm_plain, label = key)
  }
})

test_that("non-ASCII keys are left to other checks", {
  # A misplaced BOM (ROBO-atkmqcov owns the line), a look-alike
  # (ROBO-wtixhwlo), an invisible character and invalid UTF-8.
  # No warning under any locale: a non-ASCII key never becomes the name of
  # an R object, which R would translate to the native encoding.
  expect_no_warning(x <- robots_validate_text(
    "User-agent: a\nDisallow: /x\n﻿User-agnet: b\n"
  ))
  expect_identical(nm_rows(x)$message, nm_plain)
  x <- nm_text("User-agent: *", "Disаllow: /x")
  expect_true(startsWith(nm_rows(x)$message, paste0(nm_plain, " ")))
  expect_false(grepl("resembles", nm_rows(x)$message, fixed = TRUE))
  # The invisible character gets ROBO-jsecjjyo's sentence, not this one.
  x <- nm_text("User-agent: *", "\u200bDisallow: /x")
  expect_true(startsWith(nm_rows(x)$message, paste0(nm_plain, " ")))
  expect_false(grepl("resembles", nm_rows(x)$message, fixed = TRUE))
  x <- robots_validate_text("User-agent: *\nDis\xffallow: /x\n")
  expect_identical(nm_rows(x)$message, nm_plain)
})

test_that("the rules after the line are listed up to five, then counted", {
  x <- nm_text("User-agent: *", "User-agnet: x", "Disallow: /a", "Allow: /b",
               "Disallow: /c")
  expect_true(grepl("User-agent line (lines 3-5), stay", nm_rows(x)$message,
                    fixed = TRUE))
  x <- nm_text("User-agent: *", "User-agnet: x",
               sprintf("Disallow: /p%d", 1:6), "User-agent: b", "Disallow: /")
  expect_true(grepl("User-agent line (lines 3-8 (6 rules)), stay",
                    nm_rows(x)$message, fixed = TRUE))
})

test_that("a key in range of both Allow and Disallow resembles neither", {
  # One edit from allow, two from disallow: which was meant is unknown.
  for (key in c("Dallow", "Sallow", "Iallow")) {
    x <- nm_text("User-agent: *", "Disallow: /tmp/", paste0(key, ": /x"))
    expect_identical(nm_rows(x)$message, nm_plain, label = key)
  }
  # Three edits from disallow: Allow only.
  for (key in c("Callow", "Hallow")) {
    x <- nm_text("User-agent: *", "Disallow: /tmp/", paste0(key, ": /x"))
    expect_identical(nm_rows(x)$message, nm_rule(key, "allow"), label = key)
  }
})

test_that("a body over 512,000 bytes leaves out the effect after the line", {
  # Past what Google reads, so the effect on the rules after it is not
  # stated, and the message says why.
  body <- paste0("User-agent: *\nDisallow: /tmp/\n",
                 strrep("# filler\n", 57000L), "User-agnet: x\nDisallow: /\n")
  expect_gt(nchar(body, "bytes"), 512000L)
  expect_identical(nm_rows(robots_validate_text(body))$message, nm_agent(paste(
    "", "The file is over 512,000 bytes, past what Google reads, so what the",
    "line does to the rules after it is not stated."
  )))
  # Over 500,000 but inside Google's window: Google's reading is stated.
  body <- paste0("User-agent: *\nDisallow: /tmp/\n",
                 strrep("# filler\n", 56000L), "User-agnet: x\nDisallow: /\n")
  expect_gt(nchar(body, "bytes"), 500000L)
  expect_lt(nchar(body, "bytes"), 512000L)
  expect_identical(nm_rows(robots_validate_text(body))$message,
                   nm_agent(nm_stay("line 56004", "`*`")))
})

test_that("a backtick in the key cannot end the code span", {
  x <- nm_text("User-agent: *", "User`agnet: x")
  expect_identical(nm_rows(x)$message, nm_agent(key = "User\\x60agnet"))
})

# Best of five; the near-miss key against a key that resembles nothing, in
# the same body, so only the sentence's own cost is compared. The limit is
# over twice today's ratio (about 1.4 stacked and 1.2 for pairs), and under
# the quadratic code's (5.5 and 3.3, 4231bd2).
nm_time <- function(body) {
  min(vapply(1:5, function(i) {
    system.time(robots_validate_text(body))[["elapsed"]]
  }, 0))
}

# The sentences of `near` near misses above one run of `rules` rules, timed
# on their own, best of five: each sentence names the same run, so its cost
# must not grow with the run.
nm_time_sentences <- function(rules, near = 2000L) {
  bytes <- charToRaw(paste0(
    "User-agent: *\n", strrep("User-agnet: x\n", near),
    paste0("Disallow: /p", seq_len(rules), "\n", collapse = "")
  ))
  parsed <- as.data.frame(robotstxtr_validation_parse_(bytes),
                          stringsAsFactors = FALSE)
  groups <- validation_groups(parsed, split_validation_lines(bytes))
  neighbors <- near_miss_neighbors(parsed, groups, integer())
  rows <- which(parsed$type == "unknown")
  min(vapply(1:5, function(k) {
    system.time(for (i in rows) {
      near_miss_sentence("user-agent", i, parsed, neighbors, FALSE, FALSE,
                         FALSE)
    })[["elapsed"]]
  }, 0))
}

test_that("the near-miss sentence stays linear (ROBO-dbvmxcfw)", {
  skip_on_cran()
  # Stacked User-agent and near-miss pairs, all one group on Google.
  stacked <- function(key) {
    paste0(paste0("User-agent: a", 1:6000, "\n", key, ": x\n",
                  collapse = ""), "Disallow: /\n")
  }
  expect_lt(nm_time(stacked("User-agnet")),
            2.75 * max(nm_time(stacked("Foo")), 0.05))
  # One group of near-miss and rule pairs.
  pairs <- function(key) {
    paste0("User-agent: *\n", paste0(key, ": x\nDisallow: /p", 1:6000, "\n",
                                     collapse = ""))
  }
  expect_lt(nm_time(pairs("User-agnet")),
            2.75 * max(nm_time(pairs("Foo")), 0.05))
  # Many near misses above one long run of rules: 32 times the rules, about
  # the same time (a sentence listing the run's rules one by one: over 5).
  expect_lt(nm_time_sentences(16000L),
            2.5 * max(nm_time_sentences(500L), 0.05))
})
