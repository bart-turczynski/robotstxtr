# ROBO-xexjgecr: an Allow or Disallow that repeats an earlier identical rule
# for the same crawlers has no effect.
#
# Not flagged on purpose (ticket comment of 2026-11-09): `Allow: /` with no
# Disallow (harmless and common), a redundant trailing `*` (`/x` beside
# `/x*`, about a fifth of files; the canonical value is compared, never the
# stripped key) and a Disallow a shorter Disallow already covers (a style
# question, not a no-op the matcher proves).

dr_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

dr_duplicate <- dr_lines("User-agent: *", "Disallow: /x", "Disallow: /x")

dr_rows <- function(body) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == "duplicate_rule", , drop = FALSE]
}

dr_message <- function(first_line, type = "Disallow") {
  sprintf(
    "Rule has no effect: line %d already has the same %s for the same %s",
    first_line, type, "crawlers."
  )
}

test_that("an exact duplicate Disallow is one info on the repeat", {
  x <- robots_validate_text(dr_duplicate)
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$documents$warning_count, 0L)
  d <- x$diagnostics
  expect_identical(d$code, "duplicate_rule")
  expect_identical(d$severity, "info")
  expect_identical(d$line, 3L)
  expect_identical(d$directive, "disallow")
  expect_identical(d$raw_text, "Disallow: /x")
  expect_identical(d$message, dr_message(2L))
  expect_no_match(d$message, "probably|meant|intend")
  expect_match(d$message, "^[ -~]*$")
})

test_that("the matcher decides on the first copy, with or without the second", {
  for (body in list(dr_duplicate, dr_lines("User-agent: *", "Disallow: /x"))) {
    x <- allowed_by_robots_text(body, "http://e/x", "Googlebot")
    expect_false(x$results$allowed)
    expect_identical(x$results$matched_line, 2L)
  }
})

test_that("each extra copy gets one info naming the first", {
  d <- dr_rows(dr_lines(
    "User-agent: *", "Disallow: /x", "Disallow: /x", "Disallow: /x"
  ))
  expect_identical(d$line, c(3L, 4L))
  expect_identical(d$message, rep(dr_message(2L), 2L))
})

test_that("a duplicate Allow names its own directive", {
  d <- dr_rows(dr_lines("User-agent: *", "Allow: /a", "Allow: /a"))
  expect_identical(d$line, 3L)
  expect_identical(d$directive, "allow")
  expect_identical(d$message, dr_message(2L, "Allow"))
})

test_that("values compare in the parser's canonical form", {
  d <- dr_rows(dr_lines("User-agent: *", "Disallow: /%aa", "Disallow: /%AA"))
  expect_identical(d$line, 3L)
  d <- dr_rows(dr_lines(
    "User-agent: *", "Disallow: /é", "Disallow: /%C3%A9"
  ))
  expect_identical(d$line, 3L)
  latin1 <- c(
    charToRaw("User-agent: *\nDisallow: /"), as.raw(0xe9),
    charToRaw("\nDisallow: /"), as.raw(0xe9), charToRaw("\n")
  )
  x <- robots_validate_text(latin1)
  expect_identical(x$diagnostics$code, c("invalid_utf8", "duplicate_rule"))
  expect_identical(x$diagnostics$line, c(NA_integer_, 3L))
})

test_that("no stripping beyond the parser's canonical form", {
  for (pair in list(
    c("Disallow: /a", "Disallow: /a*"),
    c("Disallow: /a*", "Disallow: /a"),
    c("Disallow: *", "Disallow: /"),
    c("Disallow: /*", "Disallow: /"),
    c("Disallow: /a$", "Disallow: /a"),
    c("Disallow: /a", "Disallow: /a$"),
    c("Disallow: /%61", "Disallow: /a"),
    c("Disallow: /a", "Disallow: /%61"),
    c("Disallow: /A", "Disallow: /a"),
    c("Disallow: /a", "Disallow: /A")
  )) {
    d <- dr_rows(dr_lines("User-agent: *", pair))
    expect_identical(nrow(d), 0L, label = toString(pair))
  }
  d <- dr_rows(dr_lines("User-agent: *", "Disallow: /a*", "Disallow: /a*"))
  expect_identical(d$line, 3L)
  d <- dr_rows(dr_lines("User-agent: *", "Disallow: /a$", "Disallow: /a$"))
  expect_identical(d$line, 3L)
})

test_that("an Allow and a Disallow with one value are not duplicates", {
  d <- dr_rows(dr_lines("User-agent: *", "Allow: /x", "Disallow: /x"))
  expect_identical(nrow(d), 0L)
  d <- dr_rows(dr_lines("User-agent: *", "Disallow: /x", "Allow: /x"))
  expect_identical(nrow(d), 0L)
})

test_that("groups naming the same agent merge, as Google does", {
  d <- dr_rows(dr_lines(
    "User-agent: *", "Disallow: /x", "", "User-agent: *", "Disallow: /x"
  ))
  expect_identical(d$line, 5L)
  expect_identical(d$message, dr_message(2L))
  d <- dr_rows(dr_lines(
    "User-agent: Googlebot", "Disallow: /x", "",
    "User-agent: googlebot/2.1", "Disallow: /x"
  ))
  expect_identical(d$line, 5L)
  expect_identical(d$message, dr_message(2L))
})

test_that("the same rule for different agents is not a duplicate", {
  for (agents in list(c("a", "b"), c("*", "bot"), c("bot", "*"))) {
    x <- robots_validate_text(dr_lines(
      paste("User-agent:", agents[[1L]]), "Disallow: /x", "",
      paste("User-agent:", agents[[2L]]), "Disallow: /x"
    ))
    expect_false("duplicate_rule" %in% x$diagnostics$code,
                 label = toString(agents))
  }
})

test_that("every agent of the repeat's group must already have the rule", {
  d <- dr_rows(dr_lines(
    "User-agent: *", "User-agent: bot", "Disallow: /x", "",
    "User-agent: *", "Disallow: /x"
  ))
  expect_identical(d$line, 6L)
  expect_identical(d$message, dr_message(3L))
  d <- dr_rows(dr_lines(
    "User-agent: *", "Disallow: /x", "",
    "User-agent: *", "User-agent: bot", "Disallow: /x"
  ))
  expect_identical(nrow(d), 0L)
  d <- dr_rows(dr_lines(
    "User-agent: a", "User-agent: b", "Disallow: /x", "",
    "User-agent: a", "Disallow: /x"
  ))
  expect_identical(d$line, 6L)
  d <- dr_rows(dr_lines(
    "User-agent: a", "Disallow: /x", "",
    "User-agent: a", "User-agent: b", "Disallow: /x"
  ))
  expect_identical(nrow(d), 0L)
})

test_that("agents covered by different lines name the smallest line", {
  d <- dr_rows(dr_lines(
    "User-agent: b", "Allow: /x", "", "User-agent: a", "Allow: /x", "",
    "User-agent: a", "User-agent: b", "Allow: /x"
  ))
  expect_identical(d$line, 9L)
  expect_identical(d$message, dr_message(2L, "Allow"))
  # The first copy in a shared group makes both later ones repeats.
  d <- dr_rows(dr_lines(
    "User-agent: a", "User-agent: b", "Allow: /x", "",
    "User-agent: a", "Allow: /x", "", "User-agent: b", "Allow: /x"
  ))
  expect_identical(d$line, c(6L, 9L))
  expect_identical(d$message, rep(dr_message(3L, "Allow"), 2L))
})

test_that("the info sits beside disallow_tied_by_allow", {
  x <- robots_validate_text(dr_lines(
    "User-agent: *", "Allow: /x", "Disallow: /x", "Disallow: /x"
  ))
  d <- x$diagnostics
  expect_identical(
    d$code,
    c("disallow_tied_by_allow", "disallow_tied_by_allow", "duplicate_rule")
  )
  expect_identical(d$line, c(3L, 4L, 4L))
  expect_identical(d$message[[3L]], dr_message(3L))
  expect_identical(x$documents$validation_status, "warning")
  x <- robots_validate_text(dr_lines(
    "User-agent: *", "Disallow: /x", "Allow: /x", "Allow: /x"
  ))
  d <- x$diagnostics
  expect_identical(d$code, c("disallow_tied_by_allow", "duplicate_rule"))
  expect_identical(d$line, c(2L, 4L))
  expect_identical(d$message[[2L]], dr_message(3L, "Allow"))
  expect_identical(x$documents$warning_count, 1L)
})

test_that("empty values, never-matching patterns and stray rules are skipped", {
  x <- robots_validate_text(dr_lines("User-agent: *", "Disallow:", "Disallow:"))
  expect_identical(x$diagnostics$code, rep("empty_rule_value", 2L))
  x <- robots_validate_text(dr_lines("User-agent: *", "Allow:", "Allow:"))
  expect_identical(x$diagnostics$code, rep("empty_rule_value", 2L))
  x <- robots_validate_text(dr_lines(
    "User-agent: *", "Disallow: private", "Disallow: private"
  ))
  expect_identical(x$diagnostics$code,
                   rep("rule_missing_leading_slash", 2L))
  x <- robots_validate_text(dr_lines("Disallow: /x", "Disallow: /x"))
  expect_identical(
    x$diagnostics$code,
    c(rep("rule_without_user_agent", 2L), "missing_user_agent")
  )
  x <- robots_validate_text(dr_lines(
    "User-agent:", "Disallow: /x", "Disallow: /x"
  ))
  expect_identical(
    x$diagnostics$code,
    c("empty_user_agent", rep("rule_without_user_agent", 2L),
      "missing_user_agent")
  )
  d <- dr_rows(dr_lines("User-agent: *bot", "Disallow: /x", "Disallow: /x"))
  expect_identical(nrow(d), 0L)
})

dr_nul <- function(...) {
  parts <- list(...)
  out <- charToRaw(parts[[1L]])
  for (part in parts[-1L]) {
    out <- c(out, as.raw(0), charToRaw(part))
  }
  out
}

test_that("a NUL anywhere skips the duplicate check", {
  for (body in list(
    dr_nul("User-agent: *\nDisallow: /x\nDisallow: /x", "y\n"),
    dr_nul("User-agent: *\nDisallow: /x", "y\nDisallow: /x\n"),
    dr_nul("User-agent: bot\nDisallow: /x\n\nUser-agent: bot", "x\n",
           "Disallow: /x\n"),
    dr_nul("# a", "\nUser-agent: *\nDisallow: /x\nDisallow: /x\n")
  )) {
    x <- robots_validate_text(body)
    expect_true("nul_byte" %in% x$diagnostics$code)
    expect_false("duplicate_rule" %in% x$diagnostics$code)
  }
})

test_that("a body cut at max_bytes is still checked", {
  body <- charToRaw(paste0(
    dr_duplicate, "Disallow: /later-", strrep("x", 200L), "\n"
  ))[seq_len(60L)]
  x <- validate_document_bytes(
    body, "s", "supplied", max_bytes = 60L, body_truncated = TRUE
  )
  expect_identical(x$diagnostics$code, c("duplicate_rule", "body_truncated"))
  expect_identical(x$diagnostics$line, c(3L, NA_integer_))
  # A copy that crosses the cut is not read, so nothing repeats.
  body <- charToRaw(paste0(
    "User-agent: *\nDisallow: /x", strrep("y", 30L), "\n",
    "Disallow: /x", strrep("y", 30L), "\n"
  ))[seq_len(60L)]
  x <- validate_document_bytes(
    body, "s", "supplied", max_bytes = 60L, body_truncated = TRUE
  )
  expect_identical(x$diagnostics$code, "body_truncated")
})

test_that("edge inputs compare without error", {
  expect_identical(robots_validate_text("")$diagnostics$code, "no_rules")
  expect_identical(robots_validate_text("# only\n")$diagnostics$code,
                   "no_rules")

  # Both lines are cut at the same byte, so the read values repeat.
  long <- paste0("/", strrep("a", 16652L))
  x <- robots_validate_text(dr_lines(
    "User-agent: *", paste0("Allow:    ", long, "tail"),
    paste0("Allow:    ", long)
  ))
  kept <- x$diagnostics$code != "line_too_long"
  expect_identical(x$diagnostics$code[kept], "duplicate_rule")
  expect_identical(x$diagnostics$line[kept], 3L)
  # Cut at different lengths, they do not.
  long <- paste0("/", strrep("a", 17000L))
  x <- robots_validate_text(dr_lines(
    "User-agent: *", paste("Allow:", long), paste("Allow:  ", long)
  ))
  expect_true("line_too_long" %in% x$diagnostics$code)
  expect_false("duplicate_rule" %in% x$diagnostics$code)
})

test_that("a large file is checked in one pass", {
  # Agent tokens must be letters: bot-b, bot-c, ..., bot-ba, ...
  agents <- paste0(
    "User-agent: bot-", chartr("0123456789", "abcdefghij", seq_len(200L))
  )
  rules <- sprintf("Disallow: /r%d", seq_len(500L))
  body <- dr_lines(agents, rules, rules)
  elapsed <- system.time(d <- dr_rows(body))[["elapsed"]]
  expect_identical(d$line, 700L + seq_len(500L))
  expect_lt(elapsed, 5)
})

for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("agent tokens merge the same under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    d <- dr_rows(dr_lines(
      "User-agent: ID-Bot", "Disallow: /x", "", "User-agent: id-bot",
      "Disallow: /x"
    ))
    expect_identical(d$line, 5L)
  })
}
