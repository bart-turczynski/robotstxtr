# ROBO-ctdkqawi: rules a NUL hides from the validation parser while other
# rules still parse. Google's matcher drops the NUL bytes and reads on
# (R/body-decode.R); the parser ends a line at its first NUL.

ch_nul <- as.raw(0)

# Google's matcher decision on `bytes`, decoded as the fetch path decodes it
# (NULs dropped), for FooBot on example.com.
ch_allowed <- function(bytes, path) {
  url <- paste0("https://example.com", path)
  Encoding(url) <- "UTF-8"
  robotstxtr_allowed_text_(decode_matcher_body(bytes), url, "FooBot")
}

# `code@line` for each row of `x`, in emission order.
ch_rows <- function(x) {
  d <- x$diagnostics
  paste0(d$code, "@", d$line)
}

ch_raw0_message <- function(n) {
  sprintf(
    paste0(
      "With its NUL bytes removed, as Google's matcher reads it, the ",
      "document has %d Allow or Disallow rule(s); if this is a UTF-16 ",
      "file, re-save it as UTF-8 (RFC 9309 section 2.3)."
    ),
    n
  )
}

# NUL at the start of a line, behind a rule the parser reads.
ch_line_start <- c(charToRaw("User-agent: *\nDisallow: /private\n"), ch_nul,
                   charToRaw("Disallow: /\n"))
# NUL inside the User-agent key.
ch_agent_key <- c(charToRaw("User-"), ch_nul,
                  charToRaw("agent: *\nDisallow: /x\n"))

ch_hidden_message <- function(n) {
  sprintf(
    paste0(
      "With its NUL bytes removed, as Google's matcher reads it, the ",
      "document has %d Allow or Disallow rule(s) that the parser, which ",
      "ends a line at its first NUL, does not read or reads in another ",
      "group; remove the NUL bytes."
    ),
    n
  )
}

# The one rules_after_nul_removal row of `x`: a lineless warning naming `n`
# hidden rules, and no no_rules.
expect_hidden_rules <- function(x, n, label = NULL) {
  d <- x$diagnostics
  found <- d[d$code == "rules_after_nul_removal", , drop = FALSE]
  expect_identical(nrow(found), 1L, label = label)
  expect_identical(found$severity, "warning", label = label)
  expect_identical(found$line, NA_integer_, label = label)
  expect_identical(found$directive, NA_character_, label = label)
  expect_identical(found$raw_text, NA_character_, label = label)
  expect_identical(found$message, ch_hidden_message(n), label = label)
  expect_false("no_rules" %in% d$code, label = label)
}

test_that("a NUL at line start behind a parsed rule is reported", {
  expect_false(ch_allowed(ch_line_start, "/"))
  x <- robots_validate_text(ch_line_start)
  expect_identical(ch_rows(x), c("nul_byte@3", "rules_after_nul_removal@NA"))
  expect_hidden_rules(x, 1L)
})

test_that("a NUL in the User-agent key is reported beside the raw rows", {
  expect_false(ch_allowed(ch_agent_key, "/x"))
  x <- robots_validate_text(ch_agent_key)
  # The raw reading stays: Bing and Yandex read the bytes as written.
  expect_identical(
    ch_rows(x),
    c("nul_byte@1", "malformed_line@1", "rule_without_user_agent@2",
      "missing_user_agent@NA", "rules_after_nul_removal@NA")
  )
  expect_hidden_rules(x, 1L)
})

test_that("the new message names Google's matcher alone", {
  d <- robots_validate_text(ch_line_start)$diagnostics
  message <- d$message[d$code == "rules_after_nul_removal"]
  expect_match(message, "Google's matcher", fixed = TRUE)
  expect_no_match(message, "Bing|Yandex|matchers")
})

test_that("a NUL mid-directive or in a User-agent value is counted", {
  # `Dis\0allow` is no directive to the parser.
  mid_key <- c(charToRaw("User-agent: *\nDisallow: /a\nDis"), ch_nul,
               charToRaw("allow: /b\n"))
  expect_false(ch_allowed(mid_key, "/b"))
  expect_hidden_rules(robots_validate_text(mid_key), 1L, "mid-directive")

  # `Foo\0Bot` names FooBot only NUL-free, so the group changes.
  agent_value <- c(charToRaw("User-agent: *\nDisallow: /a\nUser-agent: Foo"),
                   ch_nul, charToRaw("Bot\nDisallow: /b\n"))
  expect_false(ch_allowed(agent_value, "/b"))
  expect_hidden_rules(robots_validate_text(agent_value), 1L, "agent value")

  # Two hidden lines in one body are counted together.
  two <- c(ch_line_start, ch_nul, charToRaw("Allow: /private/x\n"))
  expect_hidden_rules(robots_validate_text(two), 2L, "two lines")
})

test_that("a hidden rule after a long NUL line keeps its line", {
  # The NUL line is longer than the parser's line buffer; the next line
  # numbers the same in both reads.
  long <- c(charToRaw("User-agent: *\nDisallow: /a\n# "), ch_nul,
            charToRaw(strrep("x", 20000L)), charToRaw("\n"), ch_nul,
            charToRaw("Disallow: /\n"))
  expect_hidden_rules(robots_validate_text(long), 1L, "long line")
})

test_that("a body cut after a hidden rule still reports it", {
  body <- c(ch_line_start, charToRaw(paste0("# ", strrep("x", 200L), "\n")))
  local_fake_ssrfr(function(req) fake_response(200L, body = body))
  x <- robots_validate_url("http://example.com/", max_bytes = 60L)
  expect_true(x$documents$body_truncated)
  expect_hidden_rules(x, 1L, "cut body")
})

test_that("invalid UTF-8 beside a hidden rule keeps its row", {
  bytes <- c(ch_line_start, charToRaw("Disallow: /"), as.raw(0xff),
             charToRaw("\n"))
  x <- robots_validate_text(bytes)
  expect_identical(x$diagnostics$line[x$diagnostics$code == "invalid_utf8"],
                   4L)
  expect_hidden_rules(x, 1L, "invalid UTF-8")
})

test_that("a raw-rule-free body keeps today's count, grouped or not", {
  # The NUL-free rule sits in no group; it is still counted.
  bytes <- c(ch_nul, charToRaw("Disallow: /x\n"))
  x <- robots_validate_text(bytes)
  expect_identical(ch_rows(x), c("nul_byte@1", "rules_after_nul_removal@NA"))
  expect_identical(x$diagnostics$message[[2L]], ch_raw0_message(1L))
})

test_that("NUL lines that hide no rule stay silent", {
  cases <- list(
    "NUL in a comment" = c(charToRaw("User-agent: *\nDisallow: /a # x"),
                           ch_nul, charToRaw("y\n")),
    "NUL mid-value" = c(charToRaw("User-agent: *\nDisallow: /a"), ch_nul,
                        charToRaw("b\n"))
  )
  for (case in names(cases)) {
    expect_identical(ch_rows(robots_validate_text(cases[[case]])),
                     "nul_byte@2", label = case)
  }
  expect_identical(
    ch_rows(robots_validate_text(as.raw(c(0, 0x0a, 0, 0x0a)))),
    c("nul_byte@1", "nul_byte@2", "no_rules@NA")
  )
})

# Bytes from strings, with a NUL between each two.
ch_join <- function(...) {
  parts <- list(...)
  out <- charToRaw(parts[[1L]])
  for (part in parts[-1L]) {
    out <- c(out, ch_nul, charToRaw(part))
  }
  out
}

test_that("a NUL between CR and LF does not renumber later lines", {
  # Dropped from the whole body, `\r\0\n` would become one CRLF and every
  # later line would move up by one.
  bytes <- ch_join("User-agent: *\r\nDisallow: /a\r",
                   "\nDisallow: /b\r\nDisallow: /c\r\nAllow: /d\r\n")
  expect_identical(ch_rows(robots_validate_text(bytes)), "nul_byte@3")

  many <- c(ch_join("User-agent: *\r\nDisallow: /a\r", "\n"),
            charToRaw(paste0("Disallow: /p", seq_len(100L), "\r\n",
                             collapse = "")))
  expect_identical(ch_rows(robots_validate_text(many)), "nul_byte@3")
})

test_that("a CR-NUL-LF body that hides a rule counts it alone", {
  bytes <- ch_join("User-agent: *\r\nDisallow: /a\r",
                   "\nDisallow: /b\r\n", "Allow: /x\r\n")
  x <- robots_validate_text(bytes)
  expect_identical(ch_rows(x),
                   c("nul_byte@3", "nul_byte@5", "rules_after_nul_removal@NA"))
  expect_hidden_rules(x, 1L, "CR-NUL-LF")
})

test_that("a lone-CR body keeps its line numbers", {
  bytes <- ch_join("User-agent: *\rDisallow: /a\r", "\rDisallow: /b\r",
                   "Allow: /x\r")
  x <- robots_validate_text(bytes)
  expect_identical(ch_rows(x),
                   c("nul_byte@3", "nul_byte@5", "rules_after_nul_removal@NA"))
  expect_hidden_rules(x, 1L, "lone CR")
})

test_that("a hidden rule outside any group is not counted", {
  # Google's matcher ignores a rule before the first User-agent too.
  bytes <- ch_join("", "Disallow: /x\nUser-agent: *\nDisallow: /y\n")
  expect_identical(ch_rows(robots_validate_text(bytes)), "nul_byte@1")
})
