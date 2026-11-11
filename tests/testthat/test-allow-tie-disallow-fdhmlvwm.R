# ROBO-fdhmlvwm: a Disallow whose pattern an Allow repeats never applies.

at_block_all <- "User-agent: *\nAllow: /\nDisallow: /\n"

at_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

at_tied <- function(body) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == "disallow_tied_by_allow", , drop = FALSE]
}

at_message <- function(allow_line, root = FALSE) {
  message <- sprintf(
    paste0(
      "Disallow never takes effect: the Allow on line %d has the identical ",
      "pattern, and Allow wins ties (RFC 9309 section 2.2.2)."
    ),
    allow_line
  )
  if (root) {
    message <- paste(message, "With Allow: / this Disallow: / blocks nothing.")
  }
  message
}

test_that("a block-all file with Allow: / warns on the Disallow", {
  x <- robots_validate_text(at_block_all)
  expect_identical(x$documents$validation_status, "warning")
  expect_identical(x$documents$warning_count, 1L)
  d <- x$diagnostics
  expect_identical(d$code, "disallow_tied_by_allow")
  expect_identical(d$severity, "warning")
  expect_identical(d$line, 3L)
  expect_identical(d$directive, "disallow")
  expect_identical(d$raw_text, "Disallow: /")
  expect_identical(d$message, at_message(2L, root = TRUE))
  expect_no_match(d$message, "crawlable", fixed = TRUE)
})

test_that("the matcher lets the identical Allow win the tie", {
  x <- allowed_by_robots_text(
    at_block_all, c("http://e/", "http://e/a/b"), "Googlebot"
  )
  expect_identical(x$results$allowed, c(TRUE, TRUE))
  expect_identical(x$results$decision_source, c("rule_allow", "rule_allow"))
  expect_identical(x$results$matched_line, c(2L, 2L))
})

test_that("a deeper identical pair warns without the / sentence", {
  x <- robots_validate_text(at_lines(
    "User-agent: *", "Allow: /x/", "Disallow: /private", "Disallow: /x/"
  ))
  expect_identical(x$diagnostics$code, "disallow_tied_by_allow")
  expect_identical(x$diagnostics$line, 4L)
  expect_identical(x$diagnostics$message, at_message(2L))
})

test_that("an Allow under a different agent cancels nothing", {
  x <- robots_validate_text(at_lines(
    "User-agent: a", "Allow: /x", "", "User-agent: b", "Disallow: /x"
  ))
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(nrow(x$diagnostics), 0L)
})

test_that("groups naming the same agent merge, as Google does", {
  d <- at_tied(at_lines(
    "User-agent: *", "Allow: /", "", "User-agent: *", "Disallow: /"
  ))
  expect_identical(d$line, 5L)
  expect_identical(d$message, at_message(2L, root = TRUE))
  d <- at_tied(at_lines(
    "User-agent: Googlebot", "Disallow: /x", "",
    "User-agent: googlebot/2.1", "Allow: /x"
  ))
  expect_identical(d$line, 2L)
  expect_identical(d$message, at_message(5L))
})

test_that("a Disallow dead for only some of its agents is not reported", {
  d <- at_tied(at_lines(
    "User-agent: a", "User-agent: b", "Disallow: /x", "",
    "User-agent: a", "Allow: /x"
  ))
  expect_identical(nrow(d), 0L)
})

test_that("a * Allow never cancels a named agent's Disallow", {
  d <- at_tied(at_lines(
    "User-agent: *", "Allow: /x", "", "User-agent: bot", "Disallow: /x"
  ))
  expect_identical(nrow(d), 0L)
  d <- at_tied(at_lines(
    "User-agent: bot", "Allow: /x", "", "User-agent: *", "Disallow: /x"
  ))
  expect_identical(nrow(d), 0L)
})

test_that("a group naming * and an agent needs the Allow for both", {
  d <- at_tied(at_lines(
    "User-agent: *", "User-agent: bot", "Allow: /x", "Disallow: /x"
  ))
  expect_identical(d$line, 4L)
  d <- at_tied(at_lines(
    "User-agent: *", "User-agent: bot", "Disallow: /x", "",
    "User-agent: *", "Allow: /x"
  ))
  expect_identical(nrow(d), 0L)
})

test_that("values compare in the parser's canonical form", {
  d <- at_tied(at_lines("User-agent: *", "Allow: /%aa", "Disallow: /%AA"))
  expect_identical(d$line, 3L)
  d <- at_tied(at_lines(
    "User-agent: *", "Allow: /é", "Disallow: /%C3%A9"
  ))
  expect_identical(d$line, 3L)
  latin1 <- c(
    charToRaw("User-agent: *\nAllow: /"), as.raw(0xe9),
    charToRaw("\nDisallow: /"), as.raw(0xe9), charToRaw("\n")
  )
  x <- robots_validate_text(latin1)
  expect_identical(x$diagnostics$code,
                   c("invalid_utf8", "invalid_utf8", "disallow_tied_by_allow"))
  expect_identical(x$diagnostics$line, c(2L, 3L, 3L))
})

test_that("no stripping beyond the parser's canonical form", {
  for (pair in list(
    c("Allow: /a", "Disallow: /a*"),
    c("Allow: /a*", "Disallow: /a"),
    c("Allow: *", "Disallow: /"),
    c("Allow: /*", "Disallow: /"),
    c("Allow: /a$", "Disallow: /a"),
    c("Allow: /a", "Disallow: /a$"),
    c("Allow: /%61", "Disallow: /a"),
    c("Allow: /A", "Disallow: /a")
  )) {
    d <- at_tied(at_lines("User-agent: *", pair))
    expect_identical(nrow(d), 0L, label = toString(pair))
  }
  d <- at_tied(at_lines("User-agent: *", "Allow: /a*", "Disallow: /a*"))
  expect_identical(d$line, 3L)
  d <- at_tied(at_lines("User-agent: *", "Allow: /a$", "Disallow: /a$"))
  expect_identical(d$line, 3L)
})

test_that("several identical Allows name the first one", {
  d <- at_tied(at_lines(
    "User-agent: *", "Disallow: /x", "Allow: /x", "Allow: /x"
  ))
  expect_identical(d$line, 2L)
  expect_identical(d$message, at_message(3L))
})

test_that("several identical Disallows get one warning each", {
  d <- at_tied(at_lines(
    "User-agent: *", "Allow: /x", "Disallow: /x", "Disallow: /x"
  ))
  expect_identical(d$line, c(3L, 4L))
  expect_identical(d$message, rep(at_message(2L), 2L))
})

test_that("agents tied by different Allows name the smallest line", {
  d <- at_tied(at_lines(
    "User-agent: b", "Allow: /x", "", "User-agent: a", "Allow: /x", "",
    "User-agent: a", "User-agent: b", "Disallow: /x"
  ))
  expect_identical(d$line, 9L)
  expect_identical(d$message, at_message(2L))
})

test_that("empty values and rules outside any group are skipped", {
  x <- robots_validate_text(at_lines("User-agent: *", "Allow:", "Disallow:"))
  expect_identical(x$diagnostics$code, rep("empty_rule_value", 2L))
  x <- robots_validate_text(at_lines(
    "Allow: /", "Disallow: /", "User-agent: *", "Disallow: /x"
  ))
  expect_identical(
    x$diagnostics$code, rep("rule_without_user_agent", 2L)
  )
  x <- robots_validate_text(at_lines("Allow: /", "Disallow: /"))
  expect_identical(
    x$diagnostics$code,
    c(rep("rule_without_user_agent", 2L), "missing_user_agent")
  )
})

test_that("a group naming no usable agent is skipped", {
  x <- robots_validate_text(at_lines("User-agent:", "Allow: /", "Disallow: /"))
  expect_identical(
    x$diagnostics$code,
    c("empty_user_agent", rep("rule_without_user_agent", 2L),
      "missing_user_agent")
  )
  d <- at_tied(at_lines("User-agent: *bot", "Allow: /x", "Disallow: /x"))
  expect_identical(nrow(d), 0L)
})

test_that("a pattern that never matches is left to its own warning", {
  x <- robots_validate_text(at_lines(
    "User-agent: *", "Allow: private", "Disallow: private"
  ))
  expect_identical(x$diagnostics$code,
                   rep("rule_missing_leading_slash", 2L))
})

test_that("a tie on an inner-dollar pattern keeps both warnings", {
  x <- robots_validate_text(at_lines(
    "User-agent: *", "Allow: /a$b", "Disallow: /a$b"
  ))
  expect_identical(
    x$diagnostics$code,
    c("rule_inner_dollar", "rule_inner_dollar", "disallow_tied_by_allow")
  )
})

# The parser stops a value at a NUL; Google's matcher drops the NUL and reads
# on, so the group checks are skipped on any NUL.
at_nul <- function(...) {
  parts <- list(...)
  out <- charToRaw(parts[[1L]])
  for (part in parts[-1L]) {
    out <- c(out, as.raw(0), charToRaw(part))
  }
  out
}

test_that("a NUL anywhere skips the tie check", {
  for (body in list(
    at_nul("User-agent: *\nAllow: /\nDisallow: /", "x\n"),
    at_nul("User-agent: *\nAllow: /", "x\nDisallow: /\n"),
    at_nul("User-agent: bot\nAllow: /x\n\nUser-agent: bot", "x\n",
           "Disallow: /x\n"),
    at_nul("User-agent: *\nAllow: /a\nDisallow: /a", "b\n")
  )) {
    x <- robots_validate_text(body)
    expect_true("nul_byte" %in% x$diagnostics$code)
    expect_false("disallow_tied_by_allow" %in% x$diagnostics$code)
    expect_false("wildcard_rules_not_inherited" %in% x$diagnostics$code)
  }
})

test_that("a NUL in a User-agent skips wildcard_rules_not_inherited", {
  # Without the NUL the second group is `botx`, which drops the * rule.
  plain <- robots_validate_text(
    "User-agent: *\nDisallow: /a\n\nUser-agent: botx\nAllow: /b\n"
  )
  expect_identical(plain$diagnostics$code, "wildcard_rules_not_inherited")
  x <- robots_validate_text(at_nul(
    "User-agent: *\nDisallow: /a\n\nUser-agent: bot", "x\nAllow: /b\n"
  ))
  expect_identical(x$diagnostics$code, c("nul_byte", "rules_after_nul_removal"))
})

test_that("edge inputs compare without error", {
  x <- robots_validate_text("")
  expect_identical(x$diagnostics$code, "no_rules")

  # Both lines are cut at the same byte, so the read values tie.
  long <- paste0("/", strrep("a", 16652L))
  x <- robots_validate_text(at_lines(
    "User-agent: *", paste0("Allow:    ", long, "tail"),
    paste("Disallow:", long)
  ))
  expect_identical(x$diagnostics$code[x$diagnostics$code != "line_too_long"],
                   "disallow_tied_by_allow")
  expect_identical(x$diagnostics$line[x$diagnostics$code != "line_too_long"],
                   3L)
  # Cut at different lengths, they do not.
  long <- paste0("/", strrep("a", 17000L))
  x <- robots_validate_text(at_lines(
    "User-agent: *", paste("Allow:", long), paste("Disallow:", long)
  ))
  expect_true("line_too_long" %in% x$diagnostics$code)
  expect_false("disallow_tied_by_allow" %in% x$diagnostics$code)

  body <- c(charToRaw("User-agent: *\nAllow: /\nDisallow: /\n# "),
            as.raw(0xff), charToRaw("\n"))
  x <- robots_validate_text(body)
  expect_identical(x$diagnostics$code,
                   c("invalid_utf8_comment", "disallow_tied_by_allow"))
})

test_that("a body cut at max_bytes is still checked", {
  body <- charToRaw(paste0(
    at_block_all, "Disallow: /later-", strrep("x", 200L), "\n"
  ))[seq_len(60L)]
  x <- validate_document_bytes(
    body, "s", "supplied", max_bytes = 60L, body_truncated = TRUE
  )
  expect_identical(x$diagnostics$code,
                   c("disallow_tied_by_allow", "body_truncated"))
  expect_identical(x$diagnostics$line, c(3L, NA_integer_))
})

test_that("the tie warning sits beside wildcard_rules_not_inherited", {
  x <- robots_validate_text(at_lines(
    "User-agent: *", "Allow: /", "Disallow: /",
    "User-agent: Bingbot", "Disallow: /x"
  ))
  expect_identical(x$diagnostics$code,
                   c("wildcard_rules_not_inherited", "disallow_tied_by_allow"))
  expect_identical(x$diagnostics$line, c(4L, 3L))
  expect_identical(x$documents$validation_status, "warning")
})

for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("agent tokens merge the same under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    d <- at_tied(at_lines(
      "User-agent: ID-Bot", "Allow: /x", "", "User-agent: id-bot",
      "Disallow: /x"
    ))
    expect_identical(d$line, 5L)
  })
}
