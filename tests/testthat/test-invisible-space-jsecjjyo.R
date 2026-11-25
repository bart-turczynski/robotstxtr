# ROBO-jsecjjyo: a no-break space, another non-ASCII space or a zero-width
# character in a User-agent value or before a directive key. The text looks
# right, but Google's parser strips ASCII whitespace only. The rows name the
# character by code point and byte and state Google's reading only, then at
# most that Bing and Yandex may read the value or the following lines
# differently. Fixtures are synthetic and written as \u escapes, so the
# source stays ASCII.

iv_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")
iv_text <- function(...) robots_validate_text(iv_lines(...))
iv_rows <- function(x, code) {
  d <- x$diagnostics
  d[d$code == code, , drop = FALSE]
}
iv_codes <- function(x) {
  d <- x$diagnostics
  paste(d$line, d$severity, d$code)
}
iv_count <- function(message, pattern) {
  lengths(regmatches(message, gregexpr(pattern, message)))
}

# Google's decision for `token` on `path`, the reading the rows state.
iv_google <- function(body, token, path) {
  r <- robots_evaluate_text_v1(body, paste0("https://example.com", path),
                               token, "google", "google")$results
  paste(r$url_decision, r$matched_line)
}

iv_plain <- "Directive is not recognized by this validation profile."
iv_value_clause <- " Bing and Yandex may read this value differently."
iv_lines_clause <- " Bing and Yandex may read the following lines differently."
iv_line_clause <- " Bing and Yandex may read the line differently."
iv_nbsp <- "U+00A0 NO-BREAK SPACE at byte 8, which is a no-break space"

# The ticket's example: three no-break spaces pad the value before a comment.
iv_ticket <- iv_lines("User-agent: *", "Allow: /", "",
                      "User-agent: bingbot\u00a0\u00a0\u00a0 # Microsoft",
                      "Disallow: /private/")
iv_key <- iv_lines("User-agent: *", "\u200bDisallow: /private/")
iv_agent <- iv_lines("User-agent: a", "Disallow: /a", "\u200bUser-agent: x",
                     "Disallow: /b")

test_that("Google's reading of the ticket's examples", {
  # Google cuts the value at the first no-break space and reads `bingbot`.
  expect_identical(iv_google(iv_ticket, "bingbot", "/private/x"),
                   "disallow 5")
  # A zero-width space before the key: Google does not read the rule.
  expect_identical(iv_google(iv_key, "ExampleBot", "/private/x"), "allow NA")
  # A zero-width space before User-agent: Google starts no group, so the
  # rule after it stays with the group above.
  expect_identical(iv_google(iv_agent, "a", "/b"), "disallow 4")
  expect_identical(iv_google(iv_agent, "x", "/b"), "allow NA")
})

test_that("Google's reading of the hidden User-agent shapes", {
  # Between User-agent lines: the run goes on, so `a` shares line 3's group.
  body <- iv_lines("User-agent: a", "\u200bUser-agent: x", "User-agent: b",
                   "Disallow: /b")
  expect_identical(iv_google(body, "a", "/b"), "disallow 4")
  # Before the first User-agent line: the rule is in no group.
  body <- iv_lines("\u200bUser-agent: x", "Disallow: /b", "User-agent: c",
                   "Disallow: /c")
  expect_identical(iv_google(body, "x", "/b"), "allow NA")
  expect_identical(iv_google(body, "c", "/b"), "allow NA")
})

test_that("the ticket's value names U+00A0 on its user_agent_cut row", {
  x <- robots_validate_text(iv_ticket)
  expect_identical(iv_codes(x),
                   c("4 warning user_agent_cut", "4 info rule_slash_split"))
  message <- iv_rows(x, "user_agent_cut")$message
  expect_true(startsWith(message, paste0(
    "User-agent value is read as 'bingbot' by Google's matcher"
  )))
  expect_true(grepl(paste0(
    "The value holds ", iv_nbsp, "; written in ASCII the value is ",
    "'bingbot   ', which no byte compare matches to this value."
  ), message, fixed = TRUE))
  expect_true(endsWith(message, iv_value_clause))
  expect_identical(iv_count(message, "Bing|Yandex"), 2L)
  expect_false(grepl("The package's", message, fixed = TRUE))
})

test_that("a hidden line's directive_in_value row names the character", {
  x <- iv_text("User-agent: bingbot\u00a0Disallow: /x", "User-agent: b",
               "Disallow: /y")
  expect_identical(iv_codes(x), "1 warning directive_in_value")
  message <- iv_rows(x, "directive_in_value")$message
  note <- paste0("The value holds ", iv_nbsp, "; written in ASCII the value ",
                 "is 'bingbot Disallow: /x', which no byte compare matches ",
                 "to this value.")
  at <- regexpr(note, message, fixed = TRUE)
  expect_gt(at, 0L)
  # After Google's reading, before the stack.
  expect_lt(regexpr("Google's matcher reads the User-agent value", message,
                    fixed = TRUE), at)
  expect_gt(regexpr("Google joins the User-agent line after it", message,
                    fixed = TRUE), at)
  # Only the row's own clause names the engines.
  expect_true(endsWith(message, iv_line_clause))
  expect_identical(iv_count(message, "Bing|Yandex"), 2L)
  expect_false(grepl("The package's", message, fixed = TRUE))
})

test_that("a lower-case key after U+00A0 keeps user_agent_cut", {
  # The spaced form of directive_in_value needs an ASCII space or tab.
  x <- iv_text("User-agent: bingbot\u00a0disallow: /x", "Disallow: /y")
  expect_identical(iv_codes(x), "1 warning user_agent_cut")
  message <- iv_rows(x, "user_agent_cut")$message
  expect_true(grepl(iv_nbsp, message, fixed = TRUE))
  expect_true(endsWith(message, iv_value_clause))
})

test_that("a zero-width space before Disallow names it and the rule", {
  x <- robots_validate_text(iv_key)
  expect_identical(iv_rows(x, "unknown_directive")$message, paste0(
    iv_plain, " The key holds U+200B ZERO WIDTH SPACE at byte 1, which is ",
    "invisible; without it the key is 'Disallow'. Without it, this is a ",
    "Disallow line; Google does not read it as Disallow, so Google does not ",
    "apply this rule."
  ))
  x <- iv_text("User-agent: *", "\u00a0\u00a0Allow: /x")
  expect_true(endsWith(
    iv_rows(x, "unknown_directive")$message,
    paste0("Without them, this is an Allow line; Google does not read it ",
           "as Allow, so Google does not apply this rule.")
  ))
  x <- iv_text("User-agent: *", "Disallow: /",
               "\u2060Sitemap: https://example.com/s.xml")
  expect_true(endsWith(
    iv_rows(x, "unknown_directive")$message,
    "Without it, this is a Sitemap line; Google does not read it as Sitemap."
  ))
  # Before the colon: Google reads `Disallow<U+00A0>` as Disallow by
  # prefix, so the line is no unknown key.
  x <- iv_text("User-agent: *", "Disallow\u00a0: /x")
  expect_identical(nrow(iv_rows(x, "unknown_directive")), 0L)
  # Google reads `User-agent<U+200B>` as User-agent too (it accepts the key
  # by its start), so that line is no unknown key either.
  x <- iv_text("User-agent: *", "Disallow: /", "User-agent\u200b: b",
               "Disallow: /b")
  expect_identical(nrow(iv_rows(x, "unknown_directive")), 0L)
})

test_that("a zero-width space before User-agent gets Google's group reading", {
  x <- robots_validate_text(iv_agent)
  expect_identical(iv_rows(x, "unknown_directive")$message, paste0(
    iv_plain, " The key holds U+200B ZERO WIDTH SPACE at byte 1, which is ",
    "invisible; without it the key is 'User-agent'. Without it, this is a ",
    "User-agent line; Google does not read it as User-agent, so on Google it ",
    "starts no group. The rules after it, up to the next User-agent line ",
    "(line 4), stay with the group above it on Google, for `a`.",
    iv_lines_clause
  ))
  x <- iv_text("User-agent: a", "\u200bUser-agent: x", "User-agent: b",
               "Disallow: /b")
  expect_true(grepl(paste0(
    "Google keeps the User-agent run across it, so the rules after the next ",
    "User-agent line (line 3) apply to the agents above it too (`a`)."
  ), iv_rows(x, "unknown_directive")$message, fixed = TRUE))
  x <- iv_text("\u200bUser-agent: x", "Disallow: /b", "User-agent: c",
               "Disallow: /c")
  message <- iv_rows(x, "unknown_directive")$message
  expect_true(grepl(paste0(
    "The rules after it, up to the next User-agent line (line 2), are in no ",
    "group on Google, so Google applies none of them."
  ), message, fixed = TRUE))
  expect_true(endsWith(message, iv_lines_clause))
  expect_identical(iv_count(message, "Bing|Yandex"), 2L)
  # Over 512,000 bytes the effect on the lines after it is not stated.
  body <- paste0(iv_agent, "# ", strrep("c", 520000L), "\n")
  message <- iv_rows(robots_validate_text(body), "unknown_directive")$message
  expect_true(grepl("The file is over 512,000 bytes", message, fixed = TRUE))
  expect_false(grepl("stay with the group", message, fixed = TRUE))
  expect_true(endsWith(message, iv_lines_clause))
})

test_that("each listed character is named by code point and kind", {
  points <- c(0x00A0, 0x2000:0x200A, 0x202F, 0x205F, 0x3000,
              0x200B:0x200D, 0x2060, 0xFEFF)
  table <- validation_lookalike_code_points
  for (point in points) {
    name <- table$name[match(point, table$point)]
    x <- iv_text(paste0("User-agent: a", intToUtf8(point), "b"),
                 "Disallow: /")
    message <- iv_rows(x, "user_agent_cut")$message
    what <- if (point %in% c(0x200B:0x200D, 0x2060, 0xFEFF)) {
      "invisible; without it the value is 'ab'"
    } else if (point %in% c(0x00A0, 0x2007, 0x202F)) {
      "a no-break space; written in ASCII the value is 'a b'"
    } else {
      "a space character; written in ASCII the value is 'a b'"
    }
    expect_true(grepl(sprintf("The value holds U+%04X %s at byte 2, which %s",
                              point, name, paste("is", what)), message,
                      fixed = TRUE), label = name)
    expect_identical(x$diagnostics$severity, "warning", label = name)
    expect_true(endsWith(message, iv_value_clause), label = name)
  }
  # A 3-byte space moves the byte offsets after it.
  x <- iv_text("User-agent: Yandex\u3000x\u00a0", "Disallow: /")
  expect_true(grepl(paste0(
    "characters that are non-ASCII spaces: U+3000 IDEOGRAPHIC SPACE at byte ",
    "7 (a space character), U+00A0 NO-BREAK SPACE at byte 11 (a no-break ",
    "space); written in ASCII the value is 'Yandex x '"
  ), iv_rows(x, "user_agent_cut")$message, fixed = TRUE))
  # Two zero-width characters, and a look-alike beside a space.
  x <- iv_text("User-agent: a\u200b\u2060b", "Disallow: /")
  expect_true(grepl(paste0(
    "characters that are invisible: U+200B ZERO WIDTH SPACE at byte 2 ",
    "(invisible), U+2060 WORD JOINER at byte 5 (invisible); without them ",
    "the value is 'ab'"
  ), iv_rows(x, "user_agent_cut")$message, fixed = TRUE))
  x <- iv_text("User-agent: b\u043e\u00a0x", "Disallow: /")
  expect_true(grepl(paste0(
    "characters that look like ASCII or are non-ASCII spaces: U+043E ",
    "CYRILLIC SMALL LETTER O at byte 2 (looks like 'o'), U+00A0 NO-BREAK ",
    "SPACE at byte 4 (a no-break space); written in ASCII the value is 'bo x'"
  ), iv_rows(x, "user_agent_cut")$message, fixed = TRUE))
  # A value that is only U+00A0: Google reads no token.
  x <- iv_text("User-agent: \u00a0", "Disallow: /")
  message <- iv_rows(x, "user_agent_cut")$message
  expect_true(startsWith(message, "User-agent value names no crawler"))
  expect_true(grepl("U+00A0 NO-BREAK SPACE at byte 1", message, fixed = TRUE))
})

test_that("the package's matcher sentence is withheld for these kinds", {
  # Spelled `bingbot`, a token the Bing backend evaluates: the look-alike
  # kind names the backend, the invisible kind does not.
  x <- iv_text("User-agent: bingb\u043et", "Disallow: /")
  expect_true(grepl("The package's Bing matcher",
                    iv_rows(x, "user_agent_cut")$message, fixed = TRUE))
  x <- iv_text("User-agent: bing\u200bbot", "Disallow: /")
  message <- iv_rows(x, "user_agent_cut")$message
  expect_true(grepl("U+200B ZERO WIDTH SPACE at byte 5", message,
                    fixed = TRUE))
  expect_false(grepl("The package's", message, fixed = TRUE))
  expect_true(endsWith(message, iv_value_clause))
  expect_identical(iv_count(message, "Bing|Yandex"), 2L)
  # The same on a hidden line, with the row's own clause only.
  x <- iv_text("User-agent: bing\u200bbot Disallow: /x")
  message <- iv_rows(x, "directive_in_value")$message
  expect_true(grepl("U+200B ZERO WIDTH SPACE at byte 5", message,
                    fixed = TRUE))
  expect_false(grepl("The package's", message, fixed = TRUE))
  expect_identical(iv_count(message, "Bing|Yandex"), 2L)
})

test_that("no row states what Bing or Yandex does", {
  bodies <- list(
    iv_ticket, iv_key, iv_agent,
    iv_lines("User-agent: bingbot\u00a0Disallow: /x", "Disallow: /y"),
    iv_lines("User-agent: Yandex\u3000x", "Disallow: /"),
    iv_lines("User-agent: bing\u200bbot", "Disallow: /")
  )
  for (body in bodies) {
    messages <- robots_validate_text(body)$diagnostics$message
    expect_false(any(grepl("(Bing|Yandex) (gives|reads|does not|matches)",
                           messages)), label = body)
  }
})

test_that("ASCII padding and other checks' characters draw nothing new", {
  x <- iv_text("User-agent: bingbot    # c", "Disallow: /")
  expect_identical(nrow(x$diagnostics), 0L)
  # A U+FEFF that starts a line is misplaced_byte_order_mark's.
  x <- iv_text("User-agent: a", "Disallow: /", "\ufeffDisallow: /b")
  expect_identical(iv_codes(x), c("3 warning misplaced_byte_order_mark",
                                  "3 warning unknown_directive"))
  expect_identical(iv_rows(x, "unknown_directive")$message, iv_plain)
  # A U+FEFF after a zero-width space is not.
  x <- iv_text("User-agent: a", "Disallow: /", "\u200b\ufeffDisallow: /b")
  expect_true(grepl(paste0(
    "characters that are invisible: U+200B ZERO WIDTH SPACE at byte 1 ",
    "(invisible), U+FEFF ZERO WIDTH NO-BREAK SPACE at byte 4 (invisible)"
  ), iv_rows(x, "unknown_directive")$message, fixed = TRUE))
  # U+00AD keeps its look-alike wording and leads to no hidden key.
  x <- iv_text("User-agent: *", "\u00adDisallow: /x")
  message <- iv_rows(x, "unknown_directive")$message
  expect_true(grepl("U+00AD SOFT HYPHEN at byte 1, which is invisible",
                    message, fixed = TRUE))
  expect_false(grepl("this is a Disallow line", message, fixed = TRUE))
  # A character inside the key is named, and no hidden key is read.
  x <- iv_text("User-agent: *", "Dis\u200ballow: /x")
  message <- iv_rows(x, "unknown_directive")$message
  expect_true(grepl("U+200B ZERO WIDTH SPACE at byte 4", message,
                    fixed = TRUE))
  expect_false(grepl("this is a Disallow line", message, fixed = TRUE))
  expect_false(grepl("resembles", message, fixed = TRUE))
})

test_that("bytes that are not a listed UTF-8 character stay silent", {
  # A Latin-1 A0 byte is invalid UTF-8, which invalid_utf8 reports.
  x <- robots_validate_text("User-agent: a\xa0b\nDisallow: /\n")
  expect_true("invalid_utf8" %in% x$diagnostics$code)
  expect_false(any(grepl("U+00A0", x$diagnostics$message, fixed = TRUE)))
  # After a NUL, Google's parser reads nothing.
  body <- c(charToRaw("User-agent: a"), as.raw(0),
            charToRaw("\u00a0b\nDisallow: /x\n"))
  x <- robots_validate_text(body)
  expect_false(any(grepl("U+00A0", x$diagnostics$message, fixed = TRUE)))
  # In a comment.
  x <- iv_text("User-agent: a #\u00a0b", "Disallow: /")
  expect_false(any(grepl("U+00A0", x$diagnostics$message, fixed = TRUE)))
})

test_that("CR-only line endings read the same", {
  body <- gsub("\n", "\r", iv_ticket, fixed = TRUE)
  message <- iv_rows(robots_validate_text(body), "user_agent_cut")$message
  expect_true(grepl(iv_nbsp, message, fixed = TRUE))
  body <- gsub("\n", "\r", iv_key, fixed = TRUE)
  expect_true(endsWith(
    iv_rows(robots_validate_text(body), "unknown_directive")$message,
    "so Google does not apply this rule."
  ))
})

test_that("a character split by the line buffer is dropped first", {
  # The line buffer keeps 16,663 bytes: the U+3000 at the end loses its
  # last bytes, and the U+00A0 at byte 8 is still named.
  head <- "User-agent: bingbot\u00a0x"
  body <- paste0(head, strrep("A", 16663L - nchar(head, "bytes") - 1L),
                 "\u3000B\nDisallow: /x\n")
  x <- robots_validate_text(body)
  expect_true("line_too_long" %in% x$diagnostics$code)
  message <- iv_rows(x, "user_agent_cut")$message
  expect_true(grepl(iv_nbsp, message, fixed = TRUE))
  expect_false(grepl("U+3000", message, fixed = TRUE))
})

test_that("a repeated hidden key is read once per key", {
  body <- iv_lines("User-agent: *", rep("\u200bDisallow: /x", 200L))
  rows <- iv_rows(robots_validate_text(body), "unknown_directive")
  expect_identical(nrow(rows), 200L)
  expect_true(all(endsWith(rows$message,
                           "so Google does not apply this rule.")))
})

# Consistency with the package's backends: optional, not proof, and no
# message depends on them.
test_that("consistency with the package's backends on the key case", {
  for (backend in c("bing", "yandex")) {
    token <- if (backend == "bing") "bingbot" else "Yandex"
    r <- robots_evaluate_text_v1(iv_key, "https://example.com/private/x",
                                 token, "google", backend)$results
    expect_identical(r$url_decision, "allow", label = backend)
  }
})
