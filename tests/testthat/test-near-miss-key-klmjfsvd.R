# ROBO-klmjfsvd: an unknown key that is a near miss of `User-agent`, `Allow`
# or `Disallow` (a small edit distance, a stray leading non-letter, or
# `Deny`) is ignored by every engine. Fixtures are synthetic.

nm_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")
nm_text <- function(...) robots_validate_text(nm_lines(...))
nm_rows <- function(x, code = "unknown_directive") {
  d <- x$diagnostics
  d[d$code == code, , drop = FALSE]
}
nm_plain <- "Directive is not recognized by this validation profile."

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

# As nm_outcome(), with `User-agent: A` in `lines` written as each backend's
# own crawler token, so the slot's agent is the one asked about.
nm_slot <- function(lines, path = "/page") {
  tokens <- c(google = "ExampleBot", bing = "bingbot", yandex = "Yandex")
  vapply(names(tokens), function(backend) {
    body <- nm_lines(sub("^User-agent: A$", paste("User-agent:",
                                                  tokens[[backend]]), lines))
    r <- robots_evaluate_text_v1(body, paste0("https://example.com", path),
                                 tokens[[backend]], "google", backend)$results
    paste(r$url_decision, r$matched_line)
  }, "")
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
  "Dsalow" = "disallow", "/Disallow" = "disallow",
  "///Disallow" = "disallow", "Deny" = "disallow", "DENY" = "disallow"
)

test_that("the backends ignore a near-miss User-agent line after a rule", {
  # The ticket's example: line 5 joins the `*` group on every backend.
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

test_that("the backends keep a stacked run when a rule follows a near miss", {
  body <- nm_lines("User-agent: ExampleBot", "User-agent: bingbot",
                   "User-agent: Yandex", "User-agnet: Other", "Disallow: /")
  expect_identical(
    nm_outcome(body, "/page"),
    c(google = "disallow 5", bing = "disallow 5", yandex = "disallow 5")
  )
})

test_that("bing alone ends a stacked run at a near miss before User-agent", {
  body <- nm_lines("User-agent: ExampleBot", "User-agent: bingbot",
                   "User-agent: Yandex", "User-agnet: Other",
                   "User-agent: Other", "Disallow: /")
  expect_identical(
    nm_outcome(body, "/page"),
    c(google = "disallow 6", bing = "allow NA", yandex = "disallow 6")
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
nm_no_group <- function(key) paste0(nm_lead(key, "user-agent"),
                                    ", so it starts no group.")

nm_full_ticket <- paste(
  nm_no_group("User-agnet"),
  "The rules after it, up to the next User-agent line (line 5), stay with",
  "the group above it, for `*`."
)
nm_unsure <- function(rules) paste0(
  nm_no_group("User-agnet"),
  " The rules after it, up to the next User-agent line (", rules, "), join ",
  "the group above it on Google; Bing and Yandex may have ended that group ",
  "earlier."
)

test_that("the ticket's example names User-agent and the group", {
  x <- robots_validate_text(nm_ticket)
  row <- nm_rows(x)
  expect_identical(row$line, 4L)
  expect_identical(row$severity, "warning")
  expect_identical(row$message, nm_full_ticket)
})

test_that("each near-miss key names the directive it resembles", {
  for (key in names(nm_near)) {
    target <- nm_near[[key]]
    x <- nm_text("User-agent: *", "Disallow: /tmp/", paste0(key, ": /x"))
    expected <- if (identical(target, "user-agent")) {
      nm_no_group(key)
    } else {
      paste0(nm_lead(key, target), ", so no engine applies this rule.")
    }
    expect_identical(nm_rows(x)$message, expected, label = key)
  }
})

test_that("the ticket's rule near misses name Disallow", {
  x <- nm_text("User-agent: *", "Disaloow: /private/", "Deny: /")
  expect_identical(nm_rows(x)$message, c(
    paste0(nm_lead("Disaloow", "disallow"), ", so no engine applies this ",
           "rule."),
    paste0(nm_lead("Deny", "disallow"), ", so no engine applies this rule.")
  ))
  # The only rule dropped: no_rules still says so.
  expect_true("no_rules" %in% x$diagnostics$code)
})

test_that("a near miss before any User-agent leaves its rules ungrouped", {
  x <- nm_text("User-agnet: ExampleBot", "Disallow: /", "Allow: /a", "",
               "User-agent: *", "Disallow: /tmp/")
  expect_identical(nm_rows(x)$message, paste(
    nm_no_group("User-agnet"),
    "The rules after it, up to the next User-agent line (lines 2-3), are in",
    "no group, so no engine applies them."
  ))
  expect_identical(
    x$diagnostics$line[x$diagnostics$code == "rule_without_user_agent"],
    2:3
  )
  # After a rule that is itself in no group, the same.
  x <- nm_text("Disallow: /a", "User-agnet: ExampleBot", "Disallow: /")
  expect_identical(nm_rows(x)$message, paste(
    nm_no_group("User-agnet"),
    "The rules after it, up to the next User-agent line (line 3), are in no",
    "group, so no engine applies them."
  ))
})

test_that("a near miss between stacked User-agent lines names the split", {
  x <- nm_text("User-agent: ExampleBot", "User-agent: bingbot",
               "User-agent: Yandex", "User-agnet: Other", "User-agent: Other",
               "Disallow: /")
  expect_identical(nm_rows(x)$message, paste(
    nm_no_group("User-agnet"),
    "Google and Yandex keep the User-agent run across it, so the rules after",
    "the next User-agent line (line 5) apply to the agents above it too",
    "(`ExampleBot`, `bingbot` and `Yandex`); Bing has ended the run by here,",
    "so for Bing they do not. See the user_agent_joined_across_directive row",
    "on line 5."
  ))
  expect_identical(
    x$diagnostics$line[x$diagnostics$code ==
                         "user_agent_joined_across_directive"],
    5L
  )
  # No joined row (the later group has no rule): no pointer.
  x <- nm_text("User-agent: a", "User-agnet: b", "User-agent: c")
  expect_identical(nm_rows(x)$message, paste(
    nm_no_group("User-agnet"),
    "Google and Yandex keep the User-agent run across it, so the rules after",
    "the next User-agent line (line 3) apply to the agents above it too",
    "(`a`); Bing has ended the run by here, so for Bing they do not."
  ))
})

test_that("a blank line in the stacked run leaves Yandex out", {
  body <- nm_lines("User-agent: Yandex", "", "User-agnet: x",
                   "User-agent: Other", "Disallow: /")
  # Google joins and Bing seals. The yandex backend joins too, but the
  # Yandex tester ends a run at a blank line (Y5, ROBO-bpywsjwv; see
  # joined_user_agent_diagnostics()), so the message says nothing of Yandex.
  expect_identical(
    nm_outcome(body, "/page", google_token = "Yandex"),
    c(google = "disallow 5", bing = "allow NA", yandex = "disallow 5")
  )
  x <- robots_validate_text(body)
  expect_identical(nm_rows(x)$message, paste(
    nm_no_group("User-agnet"),
    "Google keeps the User-agent run across it, so the rules after the next",
    "User-agent line (line 4) apply to the agents above it too (`Yandex`);",
    "Bing has ended the run by here, so for Bing they do not. See the",
    "user_agent_joined_across_directive row on line 4."
  ))
  x <- nm_text("User-agent: Yandex", "Crawl-delay: 1", "User-agnet: x",
               "User-agent: Other", "Disallow: /")
  expect_true(grepl("(`Yandex`); Bing has ended", nm_rows(x)$message,
                    fixed = TRUE))
  expect_true(grepl(" Google keeps the", nm_rows(x)$message, fixed = TRUE))
})

test_that("a near miss followed by a rule keeps the stacked group", {
  x <- nm_text("User-agent: ExampleBot", "User-agent: bingbot",
               "User-agent: Yandex", "User-agnet: Other", "Disallow: /*")
  expect_identical(nm_rows(x)$message, paste(
    nm_no_group("User-agnet"),
    "The rules after it, up to the next User-agent line (line 5), stay with",
    "the group above it, for `ExampleBot`, `bingbot` and `Yandex`."
  ))
})

test_that("the group's agents are capped at five", {
  agents <- sprintf("User-agent: bot%d", 1:7)
  x <- nm_text(agents, "Disallow: /a", "User-agnet: B", "Disallow: /b")
  expect_true(grepl(paste0("for `bot1`, `bot2`, `bot3`, `bot4`, `bot5` and ",
                           "2 more."),
                    nm_rows(x)$message, fixed = TRUE))
  # A global line is named `*`, and a repeated agent once.
  x <- nm_text("User-agent: * bot", "User-agent: a", "User-agent: a",
               "Disallow: /a", "User-agnet: B", "Disallow: /b")
  expect_true(grepl("for `*` and `a`.", nm_rows(x)$message, fixed = TRUE))
  # Empty User-agent values name no crawler.
  x <- nm_text("User-agent:", "User-agnet: B", "Disallow: /b")
  expect_identical(nm_rows(x)$message, nm_no_group("User-agnet"))
})

test_that("a near miss with nothing after it says only that", {
  x <- nm_text("User-agent: *", "Disallow: /a", "User-agnet: B",
               "User-agent: C", "Disallow: /")
  expect_identical(nm_rows(x)$message, nm_no_group("User-agnet"))
})

test_that("a lone CR body speaks for Google only", {
  x <- robots_validate_text(
    "User-agent: *\rDisallow: /a\rUser-agnet: x\rDisallow: /\r"
  )
  expect_identical(nm_rows(x)$message, paste(
    paste0(nm_lead("User-agnet", "user-agent", "Google does not read"),
           ", so it starts no group."),
    "The rules after it, up to the next User-agent line (line 4), stay with",
    "the group above it, for `*`. These are Google's lines: the body has a",
    "CR not directly before an LF, where Bing and Yandex do not end a line."
  ))
  x <- robots_validate_text("User-agent: *\rDeny: /\r")
  expect_identical(nm_rows(x)$message, paste(
    paste0(nm_lead("Deny", "disallow", "Google does not read"),
           ", so Google does not apply this rule."),
    "These are Google's lines: the body has a CR not directly before an LF,",
    "where Bing and Yandex do not end a line."
  ))
  x <- robots_validate_text(
    "User-agent: a\rUser-agnet: b\rUser-agent: c\rDisallow: /\r"
  )
  expect_true(grepl(paste0("Google keeps the User-agent run across it, so ",
                           "the rules after the next User-agent line (line ",
                           "3) apply to the agents above it too (`a`). See"),
                    nm_rows(x)$message, fixed = TRUE))
})

test_that("a cut body says lines past the cut were not read", {
  body <- charToRaw(paste0(nm_ticket, "Disallow: /partial"))
  x <- validate_document_bytes(body, "s", "supplied",
                               max_bytes = length(body),
                               body_truncated = TRUE)
  expect_identical(nm_rows(x)$message, paste(
    nm_full_ticket,
    "The body was cut, and lines past the cut were not read."
  ))
})

test_that("an upper-case key folds the same under every locale", {
  # ascii_lower(), not tolower(): under tr_TR `I` would not fold to `i`.
  x <- nm_text("User-agent: *", "DISALLOOW: /x", "USER-AGNET: y")
  expect_identical(nm_rows(x)$message, c(
    paste0(nm_lead("DISALLOOW", "disallow"), ", so no engine applies this ",
           "rule."),
    nm_no_group("USER-AGNET")
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
  x <- nm_text("User-agent: *", "​Disallow: /x")
  expect_identical(nm_rows(x)$message, nm_plain)
  x <- robots_validate_text("User-agent: *\nDis\xffallow: /x\n")
  expect_identical(nm_rows(x)$message, nm_plain)
})

test_that("agents a line splits on Bing are not named after a rule", {
  # Google joins `A` and `B` across line 2; Bing ends the run there, so `A`
  # gets none of the rules after the near miss on Bing.
  for (mid in c("Foo: 1", "Crawl-delay: 1", "User-agnet: q")) {
    lines <- c("User-agent: A", mid, "User-agent: B", "Disallow: /x",
               "User-agnet: c", "Disallow: /")
    expect_identical(
      nm_slot(lines),
      c(google = "disallow 6", bing = "allow NA", yandex = "disallow 6"),
      info = mid
    )
    row <- nm_rows(nm_text(lines))
    expect_identical(row$message[row$line == 5L], nm_unsure("line 6"),
                     info = mid)
  }
  # A blank or comment line in the run: no agents named either.
  for (mid in c("", "# c")) {
    x <- nm_text("User-agent: A", mid, "User-agent: B", "Disallow: /x",
                 "User-agnet: c", "Disallow: /")
    expect_identical(nm_rows(x)$message, nm_unsure("line 6"), info = mid)
  }
  # A run of plain lines: every backend keeps both agents.
  lines <- c("User-agent: A", "User-agent: B", "Foo: 1", "Disallow: /x",
             "User-agnet: c", "Disallow: /")
  expect_identical(
    nm_slot(lines),
    c(google = "disallow 6", bing = "disallow 6", yandex = "disallow 6")
  )
  expect_identical(nm_rows(nm_text(lines))$message[[2L]], paste(
    nm_no_group("User-agnet"),
    "The rules after it, up to the next User-agent line (line 6), stay with",
    "the group above it, for `A` and `B`."
  ))
  # A User-agent line Google reads but not in the plain form.
  x <- nm_text("User-agent: A", "Useragent: B", "Disallow: /x",
               "User-agnet: c", "Disallow: /")
  expect_identical(nm_rows(x)$message, nm_unsure("line 5"))
})

test_that("an empty User-agent value ends the group on Yandex", {
  # Stacked: Google keeps `Yandex` in the run, the yandex backend does not.
  lines <- c("User-agent: A", "User-agent:", "User-agnet: x",
             "User-agent: Other", "Disallow: /")
  expect_identical(
    nm_slot(lines),
    c(google = "disallow 5", bing = "allow NA", yandex = "allow NA")
  )
  expect_identical(nm_rows(nm_text(lines))$message, paste(
    nm_no_group("User-agnet"),
    "Google keeps the User-agent run across it, so the rules after the next",
    "User-agent line (line 4) apply to the agents above it too (`A`); Bing",
    "has ended the run by here, so for Bing they do not. See the",
    "user_agent_joined_across_directive row on line 4."
  ))
  # The next User-agent line empty: Bing skips it, so keeps `A` with the
  # rule, and the message names neither Bing nor Yandex.
  lines <- c("User-agent: A", "User-agnet: x", "User-agent:", "Disallow: /")
  expect_identical(
    nm_slot(lines),
    c(google = "disallow 4", bing = "disallow 4", yandex = "allow NA")
  )
  expect_identical(nm_rows(nm_text(lines))$message, paste(
    nm_no_group("User-agnet"),
    "Google keeps the User-agent run across it, so the rules after the next",
    "User-agent line (line 3) apply to the agents above it too (`A`)."
  ))
  # After a rule: no agents named.
  lines <- c("User-agent: A", "User-agent:", "User-agnet: b", "Disallow: /")
  expect_identical(
    nm_slot(lines),
    c(google = "disallow 4", bing = "disallow 4", yandex = "allow NA")
  )
  expect_identical(nm_rows(nm_text(lines))$message, nm_unsure("line 4"))
})

test_that("stacked lines outside the plain form leave Bing or Yandex out", {
  # The next line a form Bing does not read: Bing keeps `A` with the rule.
  lines <- c("User-agent: A", "User-agnet: x", "Useragent: B", "Disallow: /")
  expect_identical(
    nm_slot(lines),
    c(google = "disallow 4", bing = "disallow 4", yandex = "disallow 4")
  )
  expect_identical(nm_rows(nm_text(lines))$message, paste(
    nm_no_group("User-agnet"),
    "Google keeps the User-agent run across it, so the rules after the next",
    "User-agent line (line 3) apply to the agents above it too (`A`). See",
    "the user_agent_joined_across_directive row on line 3."
  ))
  # The earlier line a form Yandex does not read.
  lines <- c("Useragent: A", "User-agnet: x", "User-agent: B", "Disallow: /")
  tokens <- c(google = "ExampleBot", bing = "bingbot", yandex = "Yandex")
  expect_identical(
    vapply(names(tokens), function(backend) {
      body <- nm_lines(sub(" A$", paste0(" ", tokens[[backend]]), lines))
      r <- robots_evaluate_text_v1(body, "https://example.com/page",
                                   tokens[[backend]], "google",
                                   backend)$results
      paste(r$url_decision, r$matched_line)
    }, ""),
    c(google = "disallow 4", bing = "allow NA", yandex = "allow NA")
  )
  expect_true(grepl(" Google keeps the User-agent run across it",
                    nm_rows(nm_text(lines))$message, fixed = TRUE))
})

test_that("Yandex is named only when its run reaches the group's start", {
  # The blank is before the line just above the near miss: Yandex ends the
  # run there (Y5), so the message names Google alone.
  x <- nm_text("User-agent: A", "", "User-agent: B", "User-agnet: x",
               "User-agent: C", "Disallow: /")
  expect_true(grepl(paste0(" Google keeps the User-agent run across it, so ",
                           "the rules after the next User-agent line (line ",
                           "5) apply to the agents above it too (`A` and ",
                           "`B`); Bing has ended"),
                    nm_rows(x)$message, fixed = TRUE))
})

test_that("a rule after a near miss below a User-agent line keeps the group", {
  # No stacked wording: a rule follows before the next User-agent line.
  lines <- c("User-agent: A", "User-agnet: b", "Disallow: /", "",
             "User-agent: c", "Disallow: /y")
  expect_identical(
    nm_slot(lines),
    c(google = "disallow 3", bing = "disallow 3", yandex = "disallow 3")
  )
  expect_identical(nm_rows(nm_text(lines))$message, paste(
    nm_no_group("User-agnet"),
    "The rules after it, up to the next User-agent line (line 3), stay with",
    "the group above it, for `A`."
  ))
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

test_that("a CRLF body keeps the wording for every engine", {
  x <- robots_validate_text("User-agent: a\r\nDeny: /\r\n")
  expect_identical(nm_rows(x)$message,
                   paste0(nm_lead("Deny", "disallow"),
                          ", so no engine applies this rule."))
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
    expect_identical(nm_rows(x)$message,
                     paste0(nm_lead(key, "allow"),
                            ", so no engine applies this rule."), label = key)
  }
})

test_that("a body over 500,000 bytes gets the line's own effect only", {
  # Yandex allows everything in it, and Google reads 512,000 bytes.
  filler <- strrep("# filler\n", 56000L)
  body <- paste0("User-agent: *\nDisallow: /tmp/\n", filler,
                 "User-agnet: x\nDisallow: /\n")
  expect_gt(nchar(body, "bytes"), 500000L)
  x <- robots_validate_text(body)
  expect_identical(nm_rows(x)$message, nm_no_group("User-agnet"))
  # Just under: the group is named.
  body <- paste0("User-agent: *\nDisallow: /tmp/\n", strrep("# filler\n", 100L),
                 "User-agnet: x\nDisallow: /\n")
  expect_true(grepl("for `*`.", nm_rows(robots_validate_text(body))$message,
                    fixed = TRUE))
})

test_that("a backtick in the key cannot end the code span", {
  x <- nm_text("User-agent: *", "User`agnet: x")
  expect_identical(nm_rows(x)$message, nm_no_group("User\\x60agnet"))
})

# Best of three; the near-miss key against a key that resembles nothing, in
# the same body, so only the sentence's own cost is compared.
nm_time <- function(body) {
  min(vapply(1:3, function(i) {
    system.time(robots_validate_text(body))[["elapsed"]]
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
            2.5 * max(nm_time(stacked("Foo")), 0.05))
  # One group of near-miss and rule pairs.
  pairs <- function(key) {
    paste0("User-agent: *\n", paste0(key, ": x\nDisallow: /p", 1:6000, "\n",
                                     collapse = ""))
  }
  expect_lt(nm_time(pairs("User-agnet")),
            2.5 * max(nm_time(pairs("Foo")), 0.05))
})
