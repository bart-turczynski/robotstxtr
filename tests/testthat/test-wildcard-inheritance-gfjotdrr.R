# ROBO-gfjotdrr: a named User-agent group does not inherit the
# `User-agent: *` rules. A crawler obeys only the group that names it.

wi_tidio <- paste0(
  "User-agent: *\n",
  "Disallow: /wp-admin/*\n",
  "Disallow: /tickets/satisfaction/*\n",
  "Disallow: /conversations/satisfaction/*\n",
  "Disallow: /a/*\n",
  "Disallow: /b/*\n",
  "\n",
  "User-agent: Bingbot\n",
  "Disallow: /blog/search/\n"
)

wi_tail <- paste0(
  " A crawler follows the one group that names it; groups do not combine, ",
  "and `User-agent: *` applies only to crawlers with no group of their own."
)

# The wildcard_rules_not_inherited rows of a document's validation.
wi_rows <- function(body) {
  x <- robots_validate_text(body)
  x$diagnostics[x$diagnostics$code == "wildcard_rules_not_inherited", ,
                drop = FALSE]
}

wi_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

wi_found <- function(...) {
  wildcard_inheritance_diagnostics(validation_groups(as.data.frame(
    robotstxtr_validation_parse_(charToRaw(wi_lines(...))),
    stringsAsFactors = FALSE
  )))
}

test_that("the matcher lets Bingbot ignore the * rules", {
  x <- allowed_by_robots_text(
    wi_tidio, rep("https://x.com/wp-admin/x", 2L), c("TestBot", "Bingbot")
  )
  expect_identical(x$results$allowed, c(FALSE, TRUE))
  expect_identical(
    x$results$decision_source, c("rule_disallow", "default_allow")
  )
})

test_that("a named group dropping the * rules gets one info", {
  x <- robots_validate_text(wi_tidio)
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$documents$warning_count, 0L)
  expect_identical(x$documents$error_count, 0L)
  expect_identical(x$diagnostics$code, "wildcard_rules_not_inherited")
  expect_identical(x$diagnostics$severity, "info")
  expect_identical(x$diagnostics$line, 8L)
  expect_identical(x$diagnostics$directive, "user-agent")
  expect_identical(x$diagnostics$raw_text, "User-agent: Bingbot")
  expect_identical(x$diagnostics$message, paste0(
    "Bingbot obeys only this group, so 5 of the 5 `User-agent: *` rules ",
    "do not apply to it: Disallow: /wp-admin/* (line 2), ",
    "Disallow: /tickets/satisfaction/* (line 3), ",
    "Disallow: /conversations/satisfaction/* (line 4), ",
    "Disallow: /a/* (line 5), Disallow: /b/* (line 6).", wi_tail
  ))
  expect_false(any(grepl("probably|meant|intend", x$diagnostics$message)))
})

test_that("a rule-free named group lists every * rule", {
  rows <- wi_rows("User-agent: *\nDisallow: /x\nUser-agent: Bingbot\n")
  expect_identical(rows$line, 3L)
  expect_identical(rows$message, paste0(
    "Bingbot obeys only this group, so 1 of the 1 `User-agent: *` rule ",
    "does not apply to it: Disallow: /x (line 2).", wi_tail
  ))
  # Directly before `User-agent: *` it is a mixed group, not a rule-free one.
  expect_identical(
    nrow(wi_rows("User-agent: Bingbot\nUser-agent: *\nDisallow: /x\n")), 0L
  )
})

test_that("a named group holding every * rule gets no row", {
  for (body in c(
    wi_lines("User-agent: *", "Disallow: /a", "Allow: /a/b",
             "User-agent: Bingbot", "Disallow: /a", "Allow: /a/b"),
    wi_lines("User-agent: *", "Disallow: /a",
             "User-agent: Bingbot", "Disallow: /a", "Disallow: /extra"),
    wi_lines("User-agent: Bingbot", "Disallow: /a",
             "User-agent: msnbot", "Disallow: /b")
  )) {
    expect_identical(nrow(wi_rows(body)), 0L, label = body)
  }
})

test_that("a missing Allow is listed", {
  rows <- wi_rows(wi_lines(
    "User-agent: *", "Disallow: /a", "Allow: /a/b",
    "User-agent: Bingbot", "Disallow: /a"
  ))
  expect_match(rows$message, "1 of the 2 `User-agent: *` rules does not ",
               fixed = TRUE)
  expect_match(rows$message, "to it: Allow: /a/b (line 3).", fixed = TRUE)
})

test_that("agents of one group with the same loss share one row", {
  rows <- wi_rows(wi_lines(
    "User-agent: *", "Disallow: /a",
    "User-agent: Bingbot", "User-agent: msnbot", "User-agent: Slurp",
    "Disallow: /x"
  ))
  expect_identical(rows$line, 3L)
  expect_match(rows$message, "^Bingbot, msnbot and Slurp obey only this ")
  expect_match(rows$message, "does not apply to them: Disallow: /a",
               fixed = TRUE)
  expect_match(wi_rows(wi_lines(
    "User-agent: *", "Disallow: /a",
    "User-agent: Bingbot", "User-agent: msnbot", "Disallow: /x"
  ))$message, "^Bingbot and msnbot obey ")
})

test_that("groups naming the same agent merge", {
  together <- wi_lines(
    "User-agent: *", "Disallow: /a", "Disallow: /b",
    "User-agent: Bingbot", "Disallow: /a",
    "User-agent: Other", "Disallow: /a", "Disallow: /b",
    "User-agent: Bingbot", "Disallow: /b"
  )
  expect_identical(nrow(wi_rows(together)), 0L)

  partial <- wi_rows(wi_lines(
    "User-agent: *", "Disallow: /a", "Disallow: /b", "Disallow: /c",
    "User-agent: Bingbot", "Disallow: /a",
    "User-agent: Bingbot", "Disallow: /b"
  ))
  expect_identical(partial$line, 5L)
  expect_identical(partial$message, paste0(
    "Bingbot obeys only the groups that name it, so 1 of the 3 ",
    "`User-agent: *` rules does not apply to it: Disallow: /c (line 4).",
    wi_tail
  ))
})

test_that("agents first named together with different losses get a row each", {
  found <- wi_found(
    "User-agent: *", "Disallow: /a", "Disallow: /b",
    "User-agent: Bingbot", "User-agent: msnbot", "Disallow: /x",
    "User-agent: msnbot", "Disallow: /a"
  )
  expect_length(found, 2L)
  expect_identical(vapply(found, `[[`, 1L, "line"), c(4L, 4L))
  expect_identical(vapply(found, `[[`, "", "agents"), c("Bingbot", "msnbot"))
  expect_identical(found[[1L]]$missing, 2:3)
  expect_identical(found[[2L]]$missing, 3L)
})

test_that("a mixed group gives its rules to the named agent too", {
  rows <- wi_rows(wi_lines(
    "User-agent: *", "User-agent: Bingbot", "Disallow: /a",
    "User-agent: *", "Disallow: /b"
  ))
  expect_identical(rows$line, 1L)
  expect_identical(rows$raw_text, "User-agent: *")
  expect_match(rows$message, "1 of the 2 `User-agent: *` rules does not ",
               fixed = TRUE)
  expect_match(rows$message, "to it: Disallow: /b (line 5).", fixed = TRUE)
})

test_that("global and named lines follow the Google matcher", {
  # `* foo` is global; `*bot` names no crawler, so its group is skipped.
  rows <- wi_rows(wi_lines(
    "User-agent: * foo", "Disallow: /a",
    "User-agent: *bot", "Disallow: /z",
    "User-agent: Googlebot/2.1", "Disallow: /x",
    "User-agent: googlebot", "Disallow: /y"
  ))
  expect_identical(rows$line, 5L)
  expect_match(rows$message, "^Googlebot obeys only the groups that name it")
  expect_match(rows$message, "1 of the 1 `User-agent: *` rule does not ",
               fixed = TRUE)
})

test_that("case folds under ascii_lower and a non-ASCII token is skipped", {
  rows <- wi_rows(wi_lines(
    "User-agent: *", "Disallow: /a",
    "User-agent: BINGBOT", "Disallow: /x",
    "User-agent: bingbot", "Disallow: /a"
  ))
  expect_identical(nrow(rows), 0L)

  body <- c(charToRaw("User-agent: *\nDisallow: /a\nUser-agent: "),
            as.raw(0xff), charToRaw("bot\nDisallow: /x\n"))
  expect_no_warning(x <- robots_validate_text(body))
  expect_false("wildcard_rules_not_inherited" %in% x$diagnostics$code)

  body <- c(charToRaw("User-agent: *\nDisallow: /a\nUser-agent: Bot"),
            as.raw(0xff), charToRaw("\nDisallow: /x\n"))
  expect_no_warning(x <- robots_validate_text(body))
  rows <- x$diagnostics[x$diagnostics$code == "wildcard_rules_not_inherited",
                        , drop = FALSE]
  expect_match(rows$message, "^Bot obeys only this group")
})

test_that("a latin1 agent name is cut where the matcher cuts it", {
  body <- "User-agent: *\nDisallow: /a\nUser-agent: Bingb\xf6t\nDisallow: /x\n"
  Encoding(body) <- "latin1"
  rows <- wi_rows(body)
  expect_match(rows$message, "^Bingb obeys only this group")
  x <- allowed_by_robots_text(body, "https://x.com/a", "Bingb")
  expect_true(x$results$allowed)
})

test_that("an explicit allow-all group is exempt", {
  for (rules in list("Disallow:", "Allow: /", c("Disallow:", "Allow: /"),
                     "Allow: /*")) {
    body <- wi_lines("User-agent: *", "Disallow: /a", "User-agent: Bingbot",
                     rules)
    expect_identical(nrow(wi_rows(body)), 0L, label = body)
  }
  for (rules in list("Allow:", "Allow: /$", "Allow: *")) {
    body <- wi_lines("User-agent: *", "Disallow: /a", "User-agent: Bingbot",
                     rules)
    expect_identical(nrow(wi_rows(body)), 1L, label = body)
  }
  x <- robots_validate_text(
    wi_lines("User-agent: *", "Disallow: /a", "User-agent: Bingbot", "Allow:")
  )
  expect_true("empty_rule_value" %in% x$diagnostics$code)
  # The exemption looks at the merged rules.
  rows <- wi_rows(wi_lines(
    "User-agent: *", "Disallow: /a", "Disallow: /b",
    "User-agent: Bingbot", "Disallow:",
    "User-agent: Bingbot", "Disallow: /a"
  ))
  expect_identical(rows$line, 4L)
  expect_match(rows$message, "Disallow: /b (line 3).", fixed = TRUE)
})

test_that("a trailing * is ignored in the comparison and $ is not", {
  for (value in c("/x*", "/x**")) {
    body <- wi_lines("User-agent: *", "Disallow: /x", "User-agent: Bingbot",
                     paste("Disallow:", value))
    expect_identical(nrow(wi_rows(body)), 0L, label = body)
  }
  rows <- wi_rows(wi_lines("User-agent: *", "Disallow: /x",
                           "User-agent: Bingbot", "Disallow: /x$"))
  expect_match(rows$message, "Disallow: /x (line 2).", fixed = TRUE)
  rows <- wi_rows(wi_lines("User-agent: *", "Disallow: *",
                           "User-agent: Bingbot", "Disallow:",
                           "Disallow: /y"))
  expect_match(rows$message, "Disallow: * (line 2).", fixed = TRUE)
  expect_identical(nrow(wi_rows(wi_lines(
    "User-agent: *", "Disallow: *", "User-agent: Bingbot", "Disallow: **"
  ))), 0L)
})

test_that("excluded rules are never listed", {
  rows <- wi_rows(wi_lines(
    "Disallow: /before", "User-agent: *", "Disallow:", "Disallow: /a",
    "Disallow: /a*", "User-agent: Bingbot", "Disallow: /x"
  ))
  expect_match(rows$message, "1 of the 1 `User-agent: *` rule does not ",
               fixed = TRUE)
  expect_match(rows$message, "to it: Disallow: /a (line 4).", fixed = TRUE)
  # A * group with only empty rules has nothing to lose.
  expect_identical(nrow(wi_rows(wi_lines(
    "User-agent: *", "Disallow:", "User-agent: Bingbot", "Disallow: /x"
  ))), 0L)
})

test_that("at most ten rules are listed", {
  star <- sprintf("Disallow: /r%02d", 1:12)
  found <- wi_found("User-agent: *", star, "User-agent: Bingbot",
                    "Disallow: /x")
  expect_length(found, 1L)
  expect_identical(found[[1L]]$missing, 2:13)
  expect_identical(found[[1L]]$agents, "Bingbot")
  expect_identical(found[[1L]]$line, 14L)
  expect_identical(found[[1L]]$message, paste0(
    "Bingbot obeys only this group, so 12 of the 12 `User-agent: *` rules ",
    "do not apply to it: ",
    toString(sprintf("Disallow: /r%02d (line %d)", 1:10, 2:11)),
    ", and 2 more.", wi_tail
  ))
})

test_that("a body cut at max_bytes is not checked", {
  x <- validate_document_bytes(
    charToRaw(wi_tidio), "s", "supplied", max_bytes = 100L,
    body_truncated = TRUE
  )
  expect_identical(x$diagnostics$code, "body_truncated")
})

test_that("the check sits beside no_rules without overlapping it", {
  x <- robots_validate_text("User-agent: *\nDisallow: /x\nUser-agent: b\n")
  expect_identical(x$diagnostics$code, "wildcard_rules_not_inherited")
  x <- robots_validate_text("User-agent: Bingbot\n\nUser-agent: *\n")
  expect_identical(x$diagnostics$code, "no_rules")
  for (body in list(raw(), "# only a comment\n")) {
    x <- robots_validate_text(body)
    expect_identical(x$diagnostics$code, "no_rules")
  }
})

test_that("a NUL inside a * rule still compares", {
  body <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0),
            charToRaw("b\nUser-agent: Bingbot\nDisallow: /x\n"))
  x <- robots_validate_text(body)
  expect_true("nul_byte" %in% x$diagnostics$code)
  rows <- x$diagnostics[x$diagnostics$code == "wildcard_rules_not_inherited",
                        , drop = FALSE]
  expect_match(rows$message, "Disallow: /a (line 2).", fixed = TRUE)
})

test_that("a large document keeps every message capped", {
  star <- sprintf("Disallow: /s%03d", 1:500)
  tokens <- paste0("bot", outer(letters[1:20], letters[1:10], paste0))
  named <- as.vector(rbind(paste("User-agent:", tokens), "Disallow: /x"))
  found <- wi_found("User-agent: *", star, named)
  expect_length(found, 200L)
  for (item in found) {
    expect_length(item$missing, 500L)
    expect_match(item$message, ", and 490 more.", fixed = TRUE)
  }
})

for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("agent names merge the same under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    rows <- wi_rows(wi_lines(
      "User-agent: *", "Disallow: /a", "Disallow: /b",
      "User-agent: ID-Bot", "Disallow: /a",
      "User-agent: id-bot", "Disallow: /b"
    ))
    expect_identical(nrow(rows), 0L)
  })
}
