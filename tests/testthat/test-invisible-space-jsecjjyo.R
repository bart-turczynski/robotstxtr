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
  # Two kinds before the key: both named, so "them".
  x <- iv_text("User-agent: *", "\u00a0\u2060Allow: /x")
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
  points <- c(0x00A0, 0x1680, 0x2000:0x200A, 0x202F, 0x205F, 0x3000,
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
  # The parser calls a body makes: a hidden key adds one per distinct key,
  # however often it repeats, over the same body with an ASCII-led key.
  calls <- new.env(parent = emptyenv())
  parse <- robotstxtr_validation_parse_
  local_mocked_bindings(robotstxtr_validation_parse_ = function(...) {
    assign("n", calls$n + 1L, envir = calls)
    parse(...)
  })
  extra <- function(n) {
    count <- function(key) {
      assign("n", 0L, envir = calls)
      robots_validate_text(iv_lines("User-agent: *",
                                    rep(paste0(key, "Disallow: /x"), n)))
      calls$n
    }
    count("\u200b") - count("x")
  }
  expect_identical(extra(1L), 1L)
  expect_identical(extra(200L), 1L)
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

test_that("a cut value led by `*` is not `*` on Google", {
  star <- paste0("User-agent value names no crawler for Google's matcher, ",
                 "which reads a product token only from a leading run of ",
                 "letters, '_' and '-', so there this line matches no ",
                 "crawler. Google does not read this line as ",
                 "`User-agent: *`, so on Google no crawler, Google's ",
                 "included, gets this group through it; ")
  no_rules <- paste0(star, "a crawler that no group names gets no rules.")
  star_row <- function(body) iv_rows(robots_validate_text(body),
                                     "user_agent_cut")
  # Padded before a comment: on Google no crawler gets the group, while
  # ASCII padding keeps `*` and draws no row.
  body <- iv_lines("User-agent: *\u00a0  # all", "Disallow: /x")
  for (token in c("ExampleBot", "Googlebot", "GPTBot")) {
    expect_identical(iv_google(body, token, "/x"), "allow NA", label = token)
  }
  ascii <- iv_lines("User-agent: *   # all", "Disallow: /x")
  expect_identical(iv_google(ascii, "Googlebot", "/x"), "disallow 2")
  expect_identical(nrow(robots_validate_text(ascii)$diagnostics), 0L)
  row <- star_row(body)
  expect_identical(row$severity, "warning")
  expect_true(startsWith(row$message, paste0(no_rules, " The value holds ",
                                             "U+00A0 NO-BREAK SPACE")))
  expect_true(endsWith(row$message, iv_value_clause))
  expect_identical(iv_count(row$message, "Bing|Yandex"), 2L)
  # Any kind after `*`, one before it, ASCII after it, or a character
  # outside the table (U+2028, named by no row here): the same reading.
  for (value in c("*\u3000", "*\u200b", "*\u0430", "\u00a0*", "*foo", "**",
                  "*/1.0", "*\u2028")) {
    body <- iv_lines(paste0("User-agent: ", value), "Disallow: /x")
    for (token in c("ExampleBot", "Googlebot")) {
      expect_identical(iv_google(body, token, "/x"), "allow NA",
                       label = paste(value, token))
    }
    row <- star_row(body)
    expect_true(startsWith(row$message, no_rules), label = value)
    expect_false(grepl("nothing changes", row$message, fixed = TRUE),
                 label = value)
    expect_false(grepl("the file has no", row$message, fixed = TRUE),
                 label = value)
    expect_identical(row$severity, "warning", label = value)
  }
  # U+2028 right after `*`, then a space: every crawler loses the rule,
  # which applies once the character is removed.
  body <- "User-agent: *\u2028 \nDisallow: /private/ \n"
  for (token in c("Googlebot", "GPTBot", "ExampleBot")) {
    expect_identical(iv_google(body, token, "/private/x"), "allow NA",
                     label = token)
    expect_identical(iv_google(gsub("\u2028", "", body, fixed = TRUE),
                               token, "/private/x"), "disallow 2",
                     label = token)
  }
  row <- star_row(body)
  expect_identical(row$message, no_rules)
  expect_identical(row$severity, "warning")
  # Beside another User-agent line: that line keeps the group.
  body <- iv_lines("User-agent: *\u00a0", "User-agent: foo", "Disallow: /x")
  expect_identical(iv_google(body, "foo", "/x"), "disallow 3")
  expect_identical(iv_google(body, "Googlebot", "/x"), "allow NA")
  expect_true(startsWith(star_row(body)$message, no_rules))
  # Beside a clean `*` group: crawlers no group names get that one.
  body <- iv_lines("User-agent: *", "Disallow: /y", "", "User-agent: *bot",
                   "Disallow: /x")
  expect_identical(iv_google(body, "Googlebot", "/x"), "allow NA")
  expect_identical(iv_google(body, "Googlebot", "/y"), "disallow 2")
  row <- star_row(body)
  expect_identical(row$message, paste0(
    star, "a crawler that no group names gets the other `User-agent: *` ",
    "group."
  ))
  expect_identical(row$severity, "warning")
  # In a group that also names `*`: that line gives the group to all, so no
  # crawler loses it and the row stays info.
  body <- iv_lines("User-agent: *", "User-agent: *bot", "Disallow: /x")
  for (token in c("ExampleBot", "Googlebot")) {
    expect_identical(iv_google(body, token, "/x"), "disallow 3", label = token)
  }
  # Google's crawlers that ignore `*` are not reached through it.
  for (token in c("AdsBot-Google", "AdsBot-Google-Mobile",
                  "Mediapartners-Google", "APIs-Google")) {
    expect_identical(iv_google(body, token, "/x"), "allow NA", label = token)
  }
  row <- star_row(body)
  expect_identical(row$message, paste0(
    star, "the group still reaches every crawler that no other group names, ",
    "as another of its lines ",
    "is `User-agent: *`, except Google's crawlers that ignore `*` ",
    "(AdsBot-Google, AdsBot-Google-Mobile, Mediapartners-Google and ",
    "APIs-Google)."
  ))
  expect_identical(row$severity, "info")
  # A token before the `*` keeps the other wording.
  message <- star_row(iv_lines("User-agent: a\u00a0*", "Disallow: /x"))$message
  expect_false(grepl("Google does not read this line", message, fixed = TRUE))
})

test_that("the hidden key needs ASCII between the characters it drops", {
  # A key that is only a zero-width space: named, no directive, no error.
  x <- iv_text("User-agent: *", "\u200b: x")
  message <- iv_rows(x, "unknown_directive")$message
  expect_true(grepl("U+200B ZERO WIDTH SPACE at byte 1", message,
                    fixed = TRUE))
  expect_false(grepl("this is a", message, fixed = TRUE))
  # ASCII blanks between the character and the key are dropped too.
  x <- iv_text("User-agent: *", "\u200b  Disallow: /x")
  expect_true(endsWith(
    iv_rows(x, "unknown_directive")$message,
    paste0("Without it, this is a Disallow line; Google does not read it ",
           "as Disallow, so Google does not apply this rule.")
  ))
  expect_identical(iv_google(iv_lines("User-agent: *", "\u200b  Disallow: /x"),
                             "ExampleBot", "/x"), "allow NA")
  # And between two such characters.
  x <- iv_text("User-agent: *", "\u200b \u00a0Disallow: /x")
  expect_true(endsWith(
    iv_rows(x, "unknown_directive")$message,
    paste0("Without them, this is a Disallow line; Google does not read it ",
           "as Disallow, so Google does not apply this rule.")
  ))
  # A key still holding a non-ASCII letter hides no key, and is never
  # parsed or kept as a cache key.
  x <- iv_text("User-agent: *", "\u200bDisallow\u0430: /x")
  expect_false(grepl("this is a", iv_rows(x, "unknown_directive")$message,
                     fixed = TRUE))
  cache <- new.env(parent = emptyenv())
  expect_null(validation_hidden_key("\u200bDisallow\u0430", cache))
  expect_identical(ls(cache), character())
  expect_null(validation_hidden_key("\u200b", cache))
  expect_identical(validation_hidden_key("\u200bDisallow", cache)$type,
                   "disallow")
  expect_identical(ls(cache), "Disallow")
})

test_that("a misplaced U+FEFF before a zero-width space", {
  body <- iv_lines("User-agent: *", "\ufeff\u200bDisallow: /p")
  # Google does not apply the rule.
  expect_identical(iv_google(body, "ExampleBot", "/p"), "allow NA")
  x <- robots_validate_text(body)
  expect_identical(iv_codes(x), c("2 warning misplaced_byte_order_mark",
                                  "2 warning unknown_directive",
                                  "NA info no_rules"))
  message <- iv_rows(x, "unknown_directive")$message
  expect_true(endsWith(message, paste0(
    "Without it and the byte-order mark, this is a Disallow line; Google ",
    "does not read it as Disallow, so Google does not apply this rule."
  )))
  # U+FEFF is named once, by its own row.
  expect_false(grepl("U+FEFF", message, fixed = TRUE))
  expect_true(grepl("U+200B ZERO WIDTH SPACE at byte 4", message,
                    fixed = TRUE))
})

test_that("the spelling and it/them follow what the sentence names", {
  spell <- function(value) {
    iv_rows(iv_text(paste0("User-agent: ", value), "Disallow: /"),
            "user_agent_cut")$message
  }
  # Other non-ASCII text kept, so the spelling says what was done to each.
  expect_true(grepl(paste0("; with ASCII for the space and the invisible ",
                           "ones dropped the value is"),
                    spell("\u00e9\u00a0\u200b\u2060x"), fixed = TRUE))
  expect_true(grepl(paste0("; with ASCII for the space and the invisible one ",
                           "dropped the value is"),
                    spell("\u00e9\u00a0\u200bx"), fixed = TRUE))
  expect_true(grepl(paste0("; with ASCII for the look-alike and the spaces ",
                           "and the invisible ones dropped the value is"),
                    spell("\u00e9\u0430\u00a0\u3000\u200b\u2060x"),
                    fixed = TRUE))
  expect_true(grepl(paste0("; with ASCII for the look-alike and the space ",
                           "and the invisible one dropped the value is"),
                    spell("\u00e9\u0430\u00a0\u200bx"), fixed = TRUE))
  expect_true(grepl(paste0("; with ASCII for the look-alikes and the space ",
                           "and the invisible one dropped the value is"),
                    spell("\u00e9\u0430\u043e\u00a0\u200bx"), fixed = TRUE))
  # One character, repeated: named once, so "it".
  key_end <- function(...) iv_rows(iv_text("User-agent: *", ...),
                                   "unknown_directive")$message
  message <- key_end("\u200b\u200bAllow: /q")
  expect_true(grepl("at byte 1, which is invisible; without it the key",
                    message, fixed = TRUE))
  expect_true(grepl("Without it, this is an Allow line", message,
                    fixed = TRUE))
  message <- key_end("\u200bDisallow\u200b\u200b: /x")
  expect_true(grepl("at byte 1, which is invisible; without it the key",
                    message, fixed = TRUE))
  expect_true(grepl("Without it, this is a Disallow line", message,
                    fixed = TRUE))
  # Two characters: named both, so "them".
  message <- key_end("\u200bDisallow\u00a0: /x")
  expect_true(grepl("characters that are invisible or are non-ASCII spaces",
                    message, fixed = TRUE))
  expect_true(grepl("Without them, this is a Disallow line", message,
                    fixed = TRUE))
})

# Best of five runs of robots_validate_text().
iv_time <- function(body) {
  min(vapply(1:5, function(i) {
    system.time(robots_validate_text(body))[["elapsed"]]
  }, 0))
}

test_that("listed characters keep validation linear in lines", {
  # Groups whose value is cut by a no-break space and whose rule and second
  # User-agent line hide behind a zero-width space, beside the same body
  # cut by `/` and with `x` before the keys: about the same time (a check
  # that scans the lines again per row: many times over).
  body <- function(pad, key) {
    name <- chartr("0123456789", "abcdefghij", seq_len(1500L))
    paste0("User-agent: bot", name, pad, " # c\n", key, "Disallow: /p", name,
           "\n", key, "User-agent: x", name, "\n", collapse = "")
  }
  expect_lt(iv_time(body("\u00a0", "\u200b")),
            2.75 * max(iv_time(body("/", "x")), 0.05))
})

# Review 2 (ROBO-jsecjjyo): the `*`-led reading on bytes, each cut row's own
# tail, and the misplaced U+FEFF read only where it leads the line.
iv_star <- paste0("User-agent value names no crawler for Google's matcher, ",
                  "which reads a product token only from a leading run of ",
                  "letters, '_' and '-', so there this line matches no ",
                  "crawler. Google does not read this line as ",
                  "`User-agent: *`, so on Google no crawler, Google's ",
                  "included, gets this group through it; ")

test_that("a `*`-led value that is not valid UTF-8 is not `*` on Google", {
  # Google reads bytes: `*` then a Latin-1 A0 or E9 is not `*`.
  for (tail in c("\xa0 # all", "\xe9")) {
    body <- paste0("User-agent: *", tail, "\nDisallow: /x\n")
    for (token in c("Googlebot", "ExampleBot")) {
      expect_identical(iv_google(body, token, "/x"), "allow NA",
                       label = paste(tail, token))
    }
    x <- robots_validate_text(body)
    expect_identical(iv_codes(x), c("1 error invalid_utf8",
                                    "1 warning user_agent_cut"))
    expect_identical(iv_rows(x, "user_agent_cut")$message,
                     paste0(iv_star, "a crawler that no group names gets ",
                            "no rules."))
    # Beside a clean `*` group: crawlers no group names get that one.
    body <- paste0("User-agent: *\nDisallow: /y\n\nUser-agent: *", tail,
                   "\nDisallow: /x\n")
    expect_identical(iv_google(body, "Googlebot", "/x"), "allow NA")
    expect_identical(iv_google(body, "Googlebot", "/y"), "disallow 2")
    row <- iv_rows(robots_validate_text(body), "user_agent_cut")
    expect_identical(row$message, paste0(
      iv_star, "a crawler that no group names gets the other ",
      "`User-agent: *` group."
    ))
    expect_identical(row$severity, "warning")
  }
  # Invalid UTF-8 inside a token value keeps a severity.
  x <- robots_validate_text("User-agent: a\xa0b\nDisallow: /\n")
  expect_identical(iv_codes(x), c("1 error invalid_utf8",
                                  "1 info user_agent_cut"))
})

test_that("each cut row of a document gets its own tail", {
  body <- iv_lines("User-agent: a/1", "Disallow: /a", "", "User-agent: *",
                   "User-agent: *bot", "Disallow: /x")
  expect_identical(iv_google(body, "ExampleBot", "/x"), "disallow 6")
  rows <- iv_rows(robots_validate_text(body), "user_agent_cut")
  expect_identical(rows$line, c(1L, 5L))
  expect_identical(rows$message[[2L]], paste0(
    iv_star, "the group still reaches every crawler that no other group ",
    "names, as another of its lines ",
    "is `User-agent: *`, except Google's crawlers that ignore `*` ",
    "(AdsBot-Google, AdsBot-Google-Mobile, Mediapartners-Google and ",
    "APIs-Google)."
  ))
  expect_identical(rows$severity, c("info", "info"))
})

test_that("ASCII blanks between the leading characters and `*` are skipped", {
  for (value in c("\u00a0\t*", "\u00a0\v*", "\u00a0\f*")) {
    body <- iv_lines(paste0("User-agent: ", value), "Disallow: /x")
    expect_identical(iv_google(body, "Googlebot", "/x"), "allow NA",
                     label = value)
    row <- iv_rows(robots_validate_text(body), "user_agent_cut")
    expect_true(startsWith(row$message, paste0(
      iv_star, "a crawler that no group names gets no rules."
    )), label = value)
    expect_identical(row$severity, "warning", label = value)
  }
})

test_that("a listed character beside a plain `*` keeps the warning", {
  # Only a `*`-led value holding no listed character is info there.
  for (value in c("*\u200b", "*\u00a0", "*\u0430")) {
    body <- iv_lines("User-agent: *", paste0("User-agent: ", value),
                     "Disallow: /x")
    expect_identical(iv_google(body, "Googlebot", "/x"), "disallow 3",
                     label = value)
    row <- iv_rows(robots_validate_text(body), "user_agent_cut")
    expect_true(startsWith(row$message, paste0(
      iv_star, "the group still reaches every crawler that no other group ",
      "names, as another of its lines is `User-agent: *`, except Google's ",
      "crawlers that ignore `*`"
    )), label = value)
    expect_identical(row$severity, "warning", label = value)
  }
})

test_that("only the U+FEFF leading the line is the byte-order mark's", {
  # A second U+FEFF is named like any listed character and counted.
  body <- iv_lines("User-agent: *", "\ufeff\ufeffDisallow: /x")
  expect_identical(iv_google(body, "ExampleBot", "/x"), "allow NA")
  message <- iv_rows(robots_validate_text(body), "unknown_directive")$message
  expect_identical(message, paste0(
    iv_plain, " The key holds U+FEFF ZERO WIDTH NO-BREAK SPACE at byte 4, ",
    "which is invisible; without it the key is '\\xEF\\xBB\\xBFDisallow'. ",
    "Without it and the byte-order mark, this is a Disallow line; Google ",
    "does not read it as Disallow, so Google does not apply this rule."
  ))
  body <- iv_lines("User-agent: *", "\ufeff\u200b\ufeffDisallow: /p")
  expect_identical(iv_google(body, "ExampleBot", "/p"), "allow NA")
  message <- iv_rows(robots_validate_text(body), "unknown_directive")$message
  expect_true(grepl(paste0(
    "characters that are invisible: U+200B ZERO WIDTH SPACE at byte 4 ",
    "(invisible), U+FEFF ZERO WIDTH NO-BREAK SPACE at byte 7 (invisible)"
  ), message, fixed = TRUE))
  expect_true(endsWith(message, paste0(
    "Without them and the byte-order mark, this is a Disallow line; Google ",
    "does not read it as Disallow, so Google does not apply this rule."
  )))
})

# Round 4: one fact record per cut value and one decision table. A value
# that without its spaces and invisible characters reads as a Google token
# Google does not read here never says that nothing changes for Google's
# crawlers.
iv_cut <- function(body) iv_rows(robots_validate_text(body), "user_agent_cut")
iv_meant <- function(token) {
  sprintf(paste0("If this line was meant as `%s`, Google's %s does not get ",
                 "this group through it."), token, token)
}
iv_meant_weak <- function(token) {
  sprintf("If this line was meant as `%s`, Google does not read it so.",
          token)
}

test_that("a Google token behind a listed character is lost on Google", {
  cases <- list(c("\u200bGooglebot", "Googlebot"),
                c("\u00a0Googlebot", "Googlebot"),
                c("\u3000Googlebot-Image", "Googlebot-Image"),
                c("Google\u00adbot", "Googlebot"),
                c("Googlebot-\u2060Image", "Googlebot-Image"))
  for (case in cases) {
    body <- iv_lines(paste0("User-agent: ", case[[1L]]), "Disallow: /x")
    expect_identical(iv_google(body, case[[2L]], "/x"), "allow NA",
                     label = case[[1L]])
    row <- iv_cut(body)
    expect_identical(row$severity, "warning", label = case[[1L]])
    expect_true(grepl(iv_meant(case[[2L]]), row$message, fixed = TRUE),
                label = case[[1L]])
    expect_false(grepl("nothing changes", row$message, fixed = TRUE),
                 label = case[[1L]])
  }
  # The whole row for the first case: the effect sentence gives way to the
  # conditional one, and the rest stays.
  row <- iv_cut(iv_lines("User-agent: \u200bGooglebot", "Disallow: /x"))
  expect_identical(row$message, paste0(
    "User-agent value names no crawler for Google's matcher, which reads a ",
    "product token only from a leading run of letters, '_' and '-', so ",
    "there this line matches no crawler. Unless another group names it, a ",
    "crawler going by the full value gets no rules from Google's matcher: ",
    "the file has no `User-agent: *` group. ", iv_meant("Googlebot"),
    " The value holds U+200B ZERO WIDTH SPACE at byte 1, which is ",
    "invisible; without it the value is 'Googlebot', which no byte compare ",
    "matches to this value.", iv_value_clause
  ))
  # A Google token that is not documented as one keeps today's sentence.
  body <- iv_lines("User-agent: \u200bExampleBot", "Disallow: /x")
  row <- iv_cut(body)
  expect_true(grepl("so nothing changes for them", row$message, fixed = TRUE))
  expect_false(grepl("If this line", row$message, fixed = TRUE))
})

test_that("the conditional sentence says less where the group still reaches", {
  # Another line of the group is `*`.
  body <- iv_lines("User-agent: *", "User-agent: \u200bGooglebot-Image",
                   "Disallow: /x")
  expect_identical(iv_google(body, "Googlebot-Image", "/x"), "disallow 3")
  row <- iv_cut(body)
  expect_true(grepl(iv_meant_weak("Googlebot-Image"), row$message,
                    fixed = TRUE))
  expect_false(grepl("does not get this group", row$message, fixed = TRUE))
  expect_identical(row$severity, "warning")
  # Another line of the group names the parent token.
  body <- iv_lines("User-agent: Googlebot", "User-agent: \u200bGooglebot-Image",
                   "Disallow: /x")
  expect_identical(iv_google(body, "Googlebot-Image", "/x"), "disallow 3")
  row <- iv_cut(body)
  expect_true(grepl(iv_meant_weak("Googlebot-Image"), row$message,
                    fixed = TRUE))
  # Another line of the group names the token itself.
  body <- iv_lines("User-agent: Googlebot", "User-agent: \u00a0Googlebot",
                   "Disallow: /x")
  expect_identical(iv_google(body, "Googlebot", "/x"), "disallow 3")
  expect_true(grepl(iv_meant_weak("Googlebot"), iv_cut(body)$message,
                    fixed = TRUE))
  # The line itself reads the parent token: Googlebot-Image falls back to it.
  body <- iv_lines("User-agent: Googlebot\u200b-Image", "Disallow: /x")
  expect_identical(iv_google(body, "Googlebot-Image", "/x"), "disallow 2")
  message <- iv_cut(body)$message
  expect_true(grepl(paste0(
    "'Googlebot' is a Google crawler token, so that Google crawler follows ",
    "this group. ", iv_meant_weak("Googlebot-Image")
  ), message, fixed = TRUE))
  # Parent elsewhere, not in the group: the strong sentence holds.
  body <- iv_lines("User-agent: Googlebot", "Disallow: /y", "",
                   "User-agent: \u200bGooglebot-Image", "Disallow: /x")
  expect_identical(iv_google(body, "Googlebot-Image", "/x"), "allow NA")
  expect_true(grepl(iv_meant("Googlebot-Image"), iv_cut(body)$message,
                    fixed = TRUE))
})

test_that("a value that names its token without the character says so", {
  # `Googlebot<U+00A0># g` names Googlebot: nothing changes for it.
  for (value in c("Googlebot\u00a0# g", "Googlebot\u200b",
                  "Googlebot\u00a0/2.1", "Mediapartners-Google\u200b*")) {
    token <- sub("[^A-Za-z_-].*$", "", value, useBytes = TRUE)
    body <- iv_lines(paste0("User-agent: ", value), "Disallow: /x")
    expect_identical(iv_google(body, token, "/x"), "disallow 2",
                     label = value)
    row <- iv_cut(body)
    expect_true(grepl(sprintf(paste0(
      "'%s' is the Google crawler token the value names, so nothing changes ",
      "for that crawler."
    ), token), row$message, fixed = TRUE), label = value)
    expect_false(grepl("follows this group", row$message, fixed = TRUE),
                 label = value)
    # Still a warning: the character is matched by no byte compare.
    expect_identical(row$severity, "warning", label = value)
  }
  # A version after an ASCII space keeps today's text; one glued on is not
  # meant.
  row <- iv_cut(iv_lines("User-agent: Googlebot\u00a0Image", "Disallow: /x"))
  expect_true(grepl("so that Google crawler follows this group",
                    row$message, fixed = TRUE))
})

test_that("`*` after any non-ASCII byte is not `*` on Google", {
  for (value in list("\u00ad*", "\xa0* # all", "\u2028*", "\xc2*",
                     rawToChar(as.raw(c(0xc2, 0xa0, 0xc2, 0x2a))),
                     "\ufeff*", "\u200b*", "\u0430*")) {
    body <- paste0("User-agent: ", value, "\nDisallow: /x\n")
    for (token in c("Googlebot", "ExampleBot")) {
      expect_identical(iv_google(body, token, "/x"), "allow NA",
                       label = paste(value, token))
    }
    row <- iv_cut(body)
    expect_true(startsWith(row$message, paste0(
      iv_star, "a crawler that no group names gets no rules."
    )), label = value)
    expect_false(grepl("nothing changes", row$message, fixed = TRUE),
                 label = value)
    expect_identical(row$severity, "warning", label = value)
  }
  # An ASCII character other than a blank before `*` is not `*`-led.
  row <- iv_cut(iv_lines("User-agent: /*", "Disallow: /x"))
  expect_false(grepl("User-agent: *`, so", row$message, fixed = TRUE))
})

test_that("an invalid UTF-8 `*`-led value stays a warning beside `*`", {
  body <- "User-agent: *\nUser-agent: *\xe9\nDisallow: /x\n"
  expect_identical(iv_google(body, "ExampleBot", "/x"), "disallow 3")
  row <- iv_cut(body)
  expect_true(grepl("the group still reaches every crawler", row$message,
                    fixed = TRUE))
  expect_identical(row$severity, "warning")
  # A valid character this row does not name keeps it info there.
  body <- iv_lines("User-agent: *", "User-agent: *\u2028", "Disallow: /x")
  expect_identical(iv_cut(body)$severity, "info")
})

test_that("an unknown repaired reading claims nothing about intent", {
  # A Latin-1 A0 before Googlebot: the bytes are not UTF-8, so the row
  # names no character and states no conditional reading.
  row <- iv_cut("User-agent: \xa0Googlebot\nDisallow: /x\n")
  expect_false(grepl("If this line", row$message, fixed = TRUE))
  expect_false(grepl("U+00A0", row$message, fixed = TRUE))
})

test_that("the fact record reads each value once, on bytes", {
  facts <- user_agent_cut_facts(c("\u200bGooglebot", "*\xa0", "\xc2*",
                                  "a\u00adb", "\u00a0 \u00a0*bot", "Foo Bot",
                                  "\u00ad"))
  expect_identical(facts$repaired,
                   c("Googlebot", NA, NA, "ab", "", "Foo", ""))
  expect_identical(facts$repaired_value,
                   c("Googlebot", NA, NA, "ab", "*bot", "Foo Bot", ""))
  expect_identical(facts$star_led,
                   c(FALSE, TRUE, TRUE, FALSE, TRUE, FALSE, FALSE))
  # The repaired `*` reading needs the value's end or a blank after `*`.
  expect_identical(user_agent_cut_facts("\u200b* x")$repaired, "*")
  decided <- user_agent_cut_decide(
    facts, ascii_lower(c("", "", "", "a", "", "Foo", "")),
    kept = c(FALSE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE),
    effect_warn = logical(7L), lookalike = logical(7L)
  )
  expect_identical(decided$case, c("meant", "star", "star", "plain", "star",
                                   "plain", "plain"))
  expect_identical(decided$warn, c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE,
                                   FALSE))
})

test_that("\"nothing changes for them\" is printed only where proven", {
  # Bytes the repair does not drop, before a Google token: Googlebot loses
  # the group on Google, so the row states Google's reading only, at
  # today's severity.
  for (value in list("\u2028Googlebot", "\xa0Googlebot", "\xc2Googlebot",
                     "\u00e9 Googlebot")) {
    body <- paste0("User-agent: ", value, "\nDisallow: /x\n")
    expect_identical(iv_google(body, "Googlebot", "/x"), "allow NA")
    row <- iv_cut(body)
    expect_identical(row$message, paste0(
      "User-agent value names no crawler for Google's matcher, which reads ",
      "a product token only from a leading run of letters, '_' and '-', so ",
      "there this line matches no crawler. Unless another group names it, ",
      "a crawler going by the full value gets no rules from Google's ",
      "matcher: the file has no `User-agent: *` group."
    ))
    expect_identical(row$severity, "info")
  }
  # A look-alike letter in place of an ASCII one: its ASCII spelling names
  # the Google token.
  for (value in c("G\u043eoglebot", "Googl\u0435bot", "\u0410dsBot-Google",
                  "\u200bG\u043eoglebot")) {
    body <- iv_lines(paste0("User-agent: ", value), "Disallow: /x")
    token <- if (grepl("dsBot", value, fixed = TRUE)) "AdsBot-Google" else
      "Googlebot"
    expect_identical(iv_google(body, token, "/x"), "allow NA", label = value)
    row <- iv_cut(body)
    expect_false(grepl("nothing changes", row$message, fixed = TRUE),
                 label = value)
    expect_true(grepl("which no byte compare matches", row$message,
                      fixed = TRUE), label = value)
  }
  # A Google token split by a byte Google does not read counts as named.
  for (value in list("Google\xadbot", "Googl\u2028ebot", "Google\xc2bot")) {
    body <- paste0("User-agent: ", value, "\nDisallow: /x\n")
    expect_identical(iv_google(body, "Googlebot", "/x"), "allow NA",
                     label = value)
    row <- iv_cut(body)
    expect_true(endsWith(row$message, paste0(
      "gets no rules from Google's matcher: the file has no ",
      "`User-agent: *` group."
    )), label = value)
    expect_false(grepl("nothing changes", row$message, fixed = TRUE),
                 label = value)
    expect_identical(row$severity, "info", label = value)
  }
  # Bytes naming no Google token, ASCII or not: printed, valid UTF-8 or
  # not. An ASCII value naming one is left out (ROBO-ipzkxzhg).
  row <- iv_cut(iv_lines("User-agent: My Googlebot clone", "Disallow: /x"))
  expect_false(grepl("nothing changes", row$message, fixed = TRUE))
  for (value in c("Foo Bot", "\u200bExampleBot",
                  "\u2028ExampleBot", "bingb\u043et", "a\xa0b")) {
    row <- iv_cut(iv_lines(paste0("User-agent: ", value), "Disallow: /x"))
    expect_true(grepl("so nothing changes for them", row$message,
                      fixed = TRUE), label = value)
  }
  # An ASCII control is not ASCII clean; with no Google token name, printed.
  row <- iv_cut(iv_lines("User-agent: Exa\tmple", "Disallow: /x"))
  expect_true(grepl("so nothing changes for them", row$message, fixed = TRUE))
  facts <- user_agent_cut_facts(c("Foo Bot", "Exa\tmple", "\u2028Googlebot",
                                  "x GOOGLEBOT"))
  expect_identical(facts$clean, c(TRUE, FALSE, FALSE, TRUE))
  expect_identical(facts$named, c(FALSE, FALSE, TRUE, TRUE))
  expect_identical(user_agent_cut_facts(c("Google\xadbot", "Exa\xadmple",
                                          "Googl\u2028ebot"))$named,
                   c(TRUE, FALSE, TRUE))
})

# ROBO-ipzkxzhg: the fallback and effect sentences against Google's reading
# of the shapes that review 4 of ROBO-jsecjjyo left open.
test_that("Google's reading of the ipzkxzhg shapes", {
  # A crawler that ignores `*` is not reached through the group's `*` line.
  body <- iv_lines("User-agent: *", "User-agent: \u200bAdsBot-Google",
                   "Disallow: /x")
  expect_identical(iv_google(body, "AdsBot-Google", "/x"), "allow NA")
  expect_identical(iv_google(body, "Googlebot", "/x"), "disallow 3")
  expect_identical(iv_google(body, "ZzSweepBot", "/x"), "disallow 3")
  # A clean ASCII value holding a Google token's name: Googlebot gets no
  # rules.
  for (value in c("\"Googlebot\"", "Google bot", "My Googlebot clone")) {
    body <- iv_lines(paste0("User-agent: ", value), "Disallow: /x")
    expect_identical(iv_google(body, "Googlebot", "/x"), "allow NA",
                     label = value)
  }
  # A no-break space inside or after the token.
  body <- iv_lines("User-agent: Google\u00a0bot", "Disallow: /x")
  expect_identical(iv_google(body, "Googlebot", "/x"), "allow NA")
  body <- iv_lines("User-agent: Googlebot\u00a01.0", "Disallow: /x")
  expect_identical(iv_google(body, "Googlebot", "/x"), "disallow 2")
  # The token in another case behind a zero-width space.
  body <- iv_lines("User-agent: \u200bGOOGLEBOT", "Disallow: /x")
  expect_identical(iv_google(body, "Googlebot", "/x"), "allow NA")
})

test_that("ipzkxzhg leaves severity and non-Google wording as they were", {
  # A value naming no Google token keeps "nothing changes for them".
  for (value in c("Foo Bar", "Foo Bot", "\u200bExampleBot")) {
    row <- iv_cut(iv_lines(paste0("User-agent: ", value), "Disallow: /x"))
    expect_true(grepl("so nothing changes for them", row$message,
                      fixed = TRUE), label = value)
  }
  # A space or invisible character in a cut value keeps warning
  # (ROBO-wtixhwlo, ROBO-jsecjjyo), whatever its repair reads.
  for (value in c("Google\u00a0bot", "Googlebot\u00a01.0",
                  "\u200bGOOGLEBOT", "\u200bExampleBot")) {
    row <- iv_cut(iv_lines(paste0("User-agent: ", value), "Disallow: /x"))
    expect_identical(row$severity, "warning", label = value)
  }
  # Clean ASCII values keep their severity.
  for (value in c("\"Googlebot\"", "Google bot", "Foo Bar", "Foo Bot")) {
    row <- iv_cut(iv_lines(paste0("User-agent: ", value), "Disallow: /x"))
    expect_identical(row$severity, "info", label = value)
  }
  # The note spells a no-break space as an ASCII space.
  row <- iv_cut(iv_lines("User-agent: Google\u00a0bot", "Disallow: /x"))
  expect_true(grepl("written in ASCII the value is 'Google bot'",
                    row$message, fixed = TRUE))
})

iv_ignore_star <- paste0(
  " Google's crawlers that ignore `*` (AdsBot-Google, AdsBot-Google-Mobile, ",
  "Mediapartners-Google and APIs-Google) do not get it through its ",
  "`User-agent: *` line."
)
iv_kept <- paste0(
  "Unless another group names it, a crawler going by the full value still ",
  "gets this group from Google's matcher, since the group also names ",
  "`User-agent: *`.", iv_ignore_star
)

test_that("a crawler that ignores `*` is not reached through the group's `*`", {
  body <- iv_lines("User-agent: *", "User-agent: \u200bAdsBot-Google",
                   "Disallow: /x")
  row <- iv_cut(body)
  expect_identical(row$message, paste0(
    "User-agent value names no crawler for Google's matcher, which reads a ",
    "product token only from a leading run of letters, '_' and '-', so ",
    "there this line matches no crawler. ", iv_kept, " ",
    iv_meant("AdsBot-Google"), " The value holds U+200B ZERO WIDTH SPACE at ",
    "byte 1, which is invisible; without it the value is 'AdsBot-Google', ",
    "which no byte compare matches to this value.", iv_value_clause
  ))
  expect_identical(row$severity, "warning")
  # A crawler that follows `*` still gets the weak sentence there.
  body <- iv_lines("User-agent: *", "User-agent: \u200bGooglebot",
                   "Disallow: /x")
  expect_identical(iv_google(body, "Googlebot", "/x"), "disallow 3")
  expect_true(grepl(iv_meant_weak("Googlebot"), iv_cut(body)$message,
                    fixed = TRUE))
  # Every cut row in a `*` group carries the exception, a non-Google one
  # too; each crawler it names is allow there.
  body <- iv_lines("User-agent: *", "User-agent: Foo Bar", "Disallow: /x")
  row <- iv_cut(body)
  expect_true(grepl(iv_kept, row$message, fixed = TRUE))
  expect_true(grepl("so nothing changes for them", row$message,
                    fixed = TRUE))
  for (token in c("AdsBot-Google", "AdsBot-Google-Mobile",
                  "Mediapartners-Google", "APIs-Google")) {
    expect_identical(iv_google(body, token, "/x"), "allow NA", label = token)
  }
  expect_identical(iv_google(body, "ZzSweepBot", "/x"), "disallow 3")
})

test_that("a clean ASCII value naming a Google token claims nothing", {
  for (value in c("\"Googlebot\"", "Google bot")) {
    row <- iv_cut(iv_lines(paste0("User-agent: ", value), "Disallow: /x"))
    expect_false(grepl("nothing changes", row$message, fixed = TRUE),
                 label = value)
    expect_true(endsWith(row$message, paste0(
      "gets no rules from Google's matcher: the file has no ",
      "`User-agent: *` group."
    )), label = value)
  }
})

test_that("a space-kind character repairs to an ASCII space", {
  facts <- user_agent_cut_facts(c("Google\u00a0bot", "Googlebot\u00a01.0",
                                  "\u3000Googlebot", "Google\u200bbot",
                                  "Google\u202f\u200bbot"))
  expect_identical(facts$repaired_value,
                   c("Google bot", "Googlebot 1.0", "Googlebot", "Googlebot",
                     "Google bot"))
  expect_identical(facts$repaired,
                   c("Google", "Googlebot", "Googlebot", "Googlebot",
                     "Google"))
  # Google<U+00A0>bot reads as `Google bot` does: no conditional reading,
  # beside the note's 'Google bot'.
  row <- iv_cut(iv_lines("User-agent: Google\u00a0bot", "Disallow: /x"))
  expect_false(grepl("If this line was meant", row$message, fixed = TRUE))
  expect_false(grepl("nothing changes", row$message, fixed = TRUE))
  # Googlebot<U+00A0>1.0 names Googlebot as `Googlebot 1.0` does; the
  # no-break space keeps the row a warning.
  row <- iv_cut(iv_lines("User-agent: Googlebot\u00a01.0", "Disallow: /x"))
  expect_true(grepl(paste0(
    "'Googlebot' is the Google crawler token the value names, so nothing ",
    "changes for that crawler."
  ), row$message, fixed = TRUE))
  expect_false(grepl("follows this group", row$message, fixed = TRUE))
  expect_identical(row$severity, "warning")
})

test_that("the conditional sentence names the crawler as Google spells it", {
  body <- iv_lines("User-agent: \u200bGOOGLEBOT", "Disallow: /x")
  row <- iv_cut(body)
  expect_true(grepl(paste0(
    "If this line was meant as `GOOGLEBOT`, Google's Googlebot does not get ",
    "this group through it."
  ), row$message, fixed = TRUE))
  body <- iv_lines("User-agent: \u200badsbot-google-mobile", "Disallow: /x")
  expect_identical(iv_google(body, "AdsBot-Google-Mobile", "/x"), "allow NA")
  expect_true(grepl("Google's AdsBot-Google-Mobile does not get",
                    iv_cut(body)$message, fixed = TRUE))
})

# ROBO-ipzkxzhg review 1: a `*` line does not reach the crawler a "meant"
# row names when another group names that crawler, or names its parent
# where no group names the crawler; and a group's own lines reach a crawler
# that ignores `*`.
iv_other_named <- function(meant) {
  iv_lines("User-agent: Googlebot", "Disallow: /a", "", "User-agent: *",
           paste0("User-agent: ​", meant), "Disallow: /x")
}
iv_other_none <- iv_lines("User-agent: Bingbot", "Disallow: /a", "",
                          "User-agent: *", "User-agent: ​Googlebot",
                          "Disallow: /x")
iv_all_exact <- iv_lines("User-agent: *", "User-agent: AdsBot-Google",
                         "User-agent: AdsBot-Google-Mobile",
                         "User-agent: Mediapartners-Google",
                         "User-agent: APIs-Google", "User-agent: Foo Bar",
                         "Disallow: /x")

test_that("Google's reading where another group or the group reaches it", {
  # Another group names Googlebot: it leaves the `*` group.
  expect_identical(iv_google(iv_other_named("Googlebot"), "Googlebot", "/x"),
                   "allow NA")
  # Googlebot-Image falls back to its parent's group.
  body <- iv_other_named("Googlebot-Image")
  expect_identical(iv_google(body, "Googlebot-Image", "/x"), "allow NA")
  expect_identical(iv_google(body, "Googlebot-Image", "/a"), "disallow 2")
  # No other group names it: the `*` line still reaches Googlebot.
  expect_identical(iv_google(iv_other_none, "Googlebot", "/x"), "disallow 6")
  # A group's own lines reach the crawlers that ignore `*`.
  body <- iv_lines("User-agent: *", "User-agent: Mediapartners-Google*",
                   "Disallow: /x")
  expect_identical(iv_google(body, "Mediapartners-Google", "/x"),
                   "disallow 3")
  expect_identical(iv_google(body, "AdsBot-Google", "/x"), "allow NA")
  body <- iv_lines("User-agent: *", "User-agent: AdsBot-Google 1.0",
                   "Disallow: /x")
  expect_identical(iv_google(body, "AdsBot-Google", "/x"), "disallow 3")
  expect_identical(iv_google(body, "AdsBot-Google-Mobile", "/x"), "allow NA")
  for (token in c("AdsBot-Google", "AdsBot-Google-Mobile",
                  "Mediapartners-Google", "APIs-Google")) {
    expect_identical(iv_google(iv_all_exact, token, "/x"), "disallow 7",
                     label = token)
  }
  # Severity stays: the meant rows warn, the clean ones are info.
  expect_identical(iv_cut(iv_other_named("Googlebot"))$severity, "warning")
  expect_identical(iv_cut(iv_other_none)$severity, "warning")
  expect_identical(iv_cut(iv_all_exact)$severity, "info")
  # The control keeps today's weak sentence.
  expect_true(grepl(iv_meant_weak("Googlebot"), iv_cut(iv_other_none)$message,
                    fixed = TRUE))
})

test_that("a `*` line does not reach a crawler another group names", {
  for (meant in c("Googlebot", "Googlebot-Image")) {
    row <- iv_cut(iv_other_named(meant))
    expect_true(grepl(iv_meant(meant), row$message, fixed = TRUE),
                label = meant)
    expect_false(grepl(iv_meant_weak(meant), row$message, fixed = TRUE),
                 label = meant)
  }
  expect_false(grepl("does not get this group", iv_cut(iv_other_none)$message,
                     fixed = TRUE))
})

test_that("the exception leaves out crawlers the group's lines read", {
  row <- iv_cut(iv_lines("User-agent: *", "User-agent: Mediapartners-Google*",
                         "Disallow: /x"))
  expect_true(grepl(paste0(
    "`User-agent: *`. Google's crawlers that ignore `*` (AdsBot-Google, ",
    "AdsBot-Google-Mobile and APIs-Google) do not get it through its ",
    "`User-agent: *` line."
  ), row$message, fixed = TRUE))
  row <- iv_cut(iv_lines("User-agent: *", "User-agent: AdsBot-Google 1.0",
                         "Disallow: /x"))
  expect_true(grepl(paste0(
    "`User-agent: *`. Google's crawlers that ignore `*` ",
    "(AdsBot-Google-Mobile, Mediapartners-Google and APIs-Google) do not ",
    "get it through its `User-agent: *` line."
  ), row$message, fixed = TRUE))
  row <- iv_cut(iv_all_exact)
  expect_true(grepl(paste0(
    "since the group also names `User-agent: *`. Only Google's parser"
  ), row$message, fixed = TRUE))
  expect_false(grepl("ignore `*`", row$message, fixed = TRUE))
})
