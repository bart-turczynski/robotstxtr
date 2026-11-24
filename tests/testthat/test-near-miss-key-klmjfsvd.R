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
  "the group above it, for `*`, including a full block (`Disallow: /`, line",
  "5)."
)

test_that("the ticket's example names User-agent, the group and the block", {
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
    "(`ExampleBot`, `bingbot` and `Yandex`); Bing ends the run here, so for",
    "Bing they do not. See the user_agent_joined_across_directive row on",
    "line 5."
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
    "(`a`); Bing ends the run here, so for Bing they do not."
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
    "Bing ends the run here, so for Bing they do not. See the",
    "user_agent_joined_across_directive row on line 4."
  ))
  x <- nm_text("User-agent: Yandex", "Crawl-delay: 1", "User-agnet: x",
               "User-agent: Other", "Disallow: /")
  expect_true(grepl("(`Yandex`); Bing ends", nm_rows(x)$message,
                    fixed = TRUE))
  expect_true(grepl(" Google keeps the", nm_rows(x)$message, fixed = TRUE))
})

test_that("a near miss followed by a rule keeps the stacked group", {
  x <- nm_text("User-agent: ExampleBot", "User-agent: bingbot",
               "User-agent: Yandex", "User-agnet: Other", "Disallow: /*")
  expect_identical(nm_rows(x)$message, paste(
    nm_no_group("User-agnet"),
    "The rules after it, up to the next User-agent line (line 5), stay with",
    "the group above it, for `ExampleBot`, `bingbot` and `Yandex`, including",
    "a full block (`Disallow: /*`, line 5)."
  ))
})

test_that("the full block is named only when no Allow opens a path", {
  x <- nm_text("User-agent: *", "Allow: /x", "User-agnet: B", "Disallow: /")
  expect_identical(nm_rows(x)$message, paste(
    nm_no_group("User-agnet"),
    "The rules after it, up to the next User-agent line (line 4), stay with",
    "the group above it, for `*`."
  ))
  x <- nm_text("User-agent: *", "Disallow: /a", "User-agnet: B",
               "Disallow: /b", "Allow:", "Disallow: /c", "", "User-agent: C",
               "Disallow: /")
  expect_identical(nm_rows(x)$message, paste(
    nm_no_group("User-agnet"),
    "The rules after it, up to the next User-agent line (lines 4-6), stay",
    "with the group above it, for `*`."
  ))
})

test_that("the group's agents are capped at five", {
  agents <- sprintf("User-agent: bot%d", 1:7)
  x <- nm_text(agents, "Disallow: /a", "User-agnet: B", "Disallow: /b")
  expect_true(grepl(paste0("for `bot1`, `bot2`, `bot3`, `bot4`, `bot5` and ",
                           "2 more."),
                    nm_rows(x)$message, fixed = TRUE))
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
    "the group above it, for `*`, including a full block (`Disallow: /`,",
    "line 4). These are Google's lines: the body has a CR not directly",
    "before an LF, where Bing and Yandex do not end a line."
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
