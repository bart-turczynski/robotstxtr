# ROBO-wtixhwlo: a cut User-agent value, or an unknown directive key, that
# holds a Unicode look-alike of an ASCII hyphen, underscore or letter names
# the character by code point and gives the ASCII spelling it resembles.
# `Perplexity<U+2011>User` is read as `Perplexity` by Google's matcher, and
# no byte compare matches it to `Perplexity-User`. Fixtures are synthetic.

la_text <- function(...) robots_validate_text(paste0(paste(..., sep = "\n"),
                                                     "\n"))

la_rows <- function(x, code = "user_agent_cut") {
  d <- x$diagnostics
  d[d$code == code, , drop = FALSE]
}

la_no_star <- paste0("Unless another group names it, a crawler going by the ",
                     "full value gets no rules from Google's matcher: the ",
                     "file has no `User-agent: *` group.")
la_star <- paste0("Unless another group names it, a crawler going by the ",
                  "full value gets the `User-agent: *` group from Google's ",
                  "matcher.")
la_other <- paste0("Only Google's parser shortens the value, and Google's ",
                   "crawlers do not go by it, so nothing changes for them; ",
                   "how the named crawler's own parser reads it is unknown.")

# Today's user_agent_cut text for a value read as `token`.
la_read_as <- function(token, fallback = la_no_star, tail = la_other) {
  paste(
    sprintf(paste0(
      "User-agent value is read as '%s' by Google's matcher, which stops at ",
      "the first character outside letters, '_' and '-'. There the full ",
      "written value does not match this record, and a crawler whose token ",
      "is '%s' matches it instead."
    ), token, token),
    fallback, tail
  )
}

la_none <- function(fallback = la_no_star) {
  paste(
    paste0("User-agent value names no crawler for Google's matcher, which ",
           "reads a product token only from a leading run of letters, '_' ",
           "and '-', so there this line matches no crawler."),
    fallback, la_other
  )
}

la_unknown <- "Directive is not recognized by this validation profile."

la_perplexity <- "User-agent: Perplexity\u2011User"

test_that("a look-alike cut row keeps today's text as its start", {
  x <- la_text(la_perplexity, "Disallow: /x")
  row <- la_rows(x)
  # No byte compare matches a look-alike value, so the row warns
  # (maintainer decision, ROBO-wtixhwlo); before it, this row was info.
  expect_identical(row$severity, "warning")
  expect_true(startsWith(row$message, la_read_as("Perplexity")))
  expect_true(validUTF8(row$message))
  expect_identical(Encoding(row$message), "unknown")
  expect_false(grepl("[^ -~]", row$message))

  x <- la_text(la_perplexity, "Disallow: /x", "", "User-agent: *",
               "Disallow: /a")
  expect_true(startsWith(la_rows(x)$message,
                         la_read_as("Perplexity", la_star)))
})

test_that("the cut pointer on the wildcard row is unchanged", {
  x <- la_text("User-agent: *", "Disallow: /a", "", la_perplexity,
               "Disallow: /x")
  wild <- x$diagnostics[x$diagnostics$code != "user_agent_cut", ,
                        drop = FALSE]
  pointer <- paste0(
    "Google's matcher reads only a product token from ",
    "`Perplexity\\xE2\\x80\\x91User` (line 4) and takes the agent to be that ",
    "token; see the user_agent_cut row."
  )
  named <- wild[grepl("Perplexity", wild$message, fixed = TRUE), ,
                drop = FALSE]
  expect_gt(nrow(named), 0L)
  expect_true(all(endsWith(named$message, pointer)))
  expect_false(any(grepl("U+2011", wild$message, fixed = TRUE)))
})

test_that("other look-alike cuts keep today's text as their start", {
  cases <- list(
    list("User-agent: Perplexity\u2212User", la_read_as("Perplexity")),
    list("User-agent: Bingb\u043et", la_read_as("Bingb")),
    list("User-agent: \u0430bcbot", la_none()),
    list("User-agent: google\uff3fextended", la_read_as("google")),
    list("User-agent: Perplexity\u00adUser", la_read_as("Perplexity"))
  )
  for (case in cases) {
    row <- la_rows(la_text(case[[1L]], "Disallow: /x"))
    expect_identical(nrow(row), 1L, label = case[[1L]])
    expect_identical(row$severity, "warning", label = case[[1L]])
    expect_true(startsWith(row$message, case[[2L]]), label = case[[1L]])
  }
  x <- la_text("Dis\u0430llow: /a")
  row <- la_rows(x, "unknown_directive")
  expect_true(startsWith(row$message, la_unknown))
})

test_that("inputs without a look-alike keep today's text exactly", {
  latin <- "User-agent: Caf\xe9\nDisallow: /x\n"
  Encoding(latin) <- "latin1"
  cases <- list(
    list("User-agent: dotbot/1.0\nDisallow: /x\n", la_read_as("dotbot")),
    list("User-agent: Foo Bot\nDisallow: /x\n", la_read_as("Foo")),
    list("User-agent: Googlebot/2.1\nDisallow: /x\n", la_read_as(
      "Googlebot", tail = paste0(
        "'Googlebot' is the Google crawler token the value names, so ",
        "nothing changes for that crawler."
      )
    )),
    list("User-agent: *bot\nDisallow: /x\n", la_none()),
    list("User-agent: B\xE4r\nDisallow: /x\n", la_read_as("B")),
    list("User-agent: Bingb\xf6t\nDisallow: /x\n", la_read_as("Bingb")),
    list(latin, la_read_as("Caf")),
    list("User-agent: __usage_a\u00ef-training\nDisallow: /x\n",
         la_read_as("__usage_a"))
  )
  for (case in cases) {
    row <- la_rows(robots_validate_text(case[[1L]]))
    expect_identical(row$message, case[[2L]], label = case[[1L]])
    # A cut without a look-alike keeps its severity.
    expect_identical(row$severity, "info", label = case[[1L]])
  }
  for (body in c("Caf\u00e9: /x\n",
                 "User-agent: a\nDisallow: /x\n\ufeffUser-agent: b\n")) {
    row <- la_rows(robots_validate_text(body), "unknown_directive")
    expect_identical(row$message, la_unknown, label = body)
  }
  x <- robots_validate_text("User-agent:\nDisallow: /x\n")
  expect_false(any(grepl("U+", x$diagnostics$message, fixed = TRUE)))
})

test_that("a look-alike Google's parser never reads stays silent", {
  nul <- c(charToRaw("User-agent: Perplexity"), as.raw(0),
           charToRaw("\u2011User\nDisallow: /x\n"))
  hash <- "User-agent: Perplexity #\u2011User\nDisallow: /x\n"
  for (body in list(nul, hash)) {
    x <- robots_validate_text(body)
    expect_identical(nrow(la_rows(x)), 0L)
    expect_false(any(grepl("U+2011", x$diagnostics$message, fixed = TRUE)))
  }
})

test_that("Google gives the ASCII spelling the `*` group", {
  body <- paste0(la_perplexity, "\nDisallow: /x\n\nUser-agent: *\n",
                 "Disallow: /a\n")
  x <- robots_evaluate_text_v1(body, c("http://e.com/x", "http://e.com/a"),
                               "Perplexity-User", "google", "google")$results
  expect_identical(x$group_token, c("*", "*"))
  expect_identical(x$url_decision, c("allow", "disallow"))
})

test_that("Bing and Yandex give their crawler's ASCII spelling `*`", {
  # Each backend evaluates only its own selectors (duplicate_rule_cut_
  # engines()), so only those look-alikes are checked there.
  cases <- list(c("Bingb\u043et", "bingbot", "bing"),
                c("Yande\u0445", "Yandex", "yandex"))
  for (case in cases) {
    body <- paste0("User-agent: ", case[[1L]], "\nDisallow: /x\n\n",
                   "User-agent: *\nDisallow: /a\n")
    x <- robots_evaluate_text_v1(body, c("http://e.com/x", "http://e.com/a"),
                                 case[[2L]], case[[3L]], case[[3L]])$results
    expect_identical(x$matcher_status, c("evaluated", "evaluated"),
                     label = case[[3L]])
    expect_identical(x$url_decision, c("allow", "disallow"),
                     label = case[[3L]])
    expect_identical(x$matched_line, c(NA, 5L), label = case[[3L]])
  }
})

# The look-alike sentence a user_agent_cut row ends with.
la_sentence <- function(held, spelled, how = "written in ASCII") {
  sprintf(paste0("The value holds %s; %s the value is '%s', which no byte ",
                 "compare matches to this value."), held, how, spelled)
}

test_that("a cut value names its look-alike and the ASCII spelling", {
  row <- la_rows(la_text(la_perplexity, "Disallow: /x"))
  expect_identical(row$message, paste(
    la_read_as("Perplexity"),
    la_sentence("U+2011 NON-BREAKING HYPHEN at byte 11, which looks like '-'",
                "Perplexity-User")
  ))
  # Perplexity is no crawler the Bing or Yandex backend evaluates.
  expect_false(grepl("Bing|Yandex", row$message))
  expect_identical(row$severity, "warning")
  expect_false(grepl("[^ -~]", row$message))

  row <- la_rows(la_text("User-agent: Perplexity\u2212User", "Disallow: /x"))
  expect_true(endsWith(row$message, la_sentence(
    "U+2212 MINUS SIGN at byte 11, which looks like '-'", "Perplexity-User"
  )))
  row <- la_rows(la_text("User-agent: google\uff3fextended", "Disallow: /x"))
  expect_true(endsWith(row$message, la_sentence(
    "U+FF3F FULLWIDTH LOW LINE at byte 7, which looks like '_'",
    "google_extended"
  )))
})

test_that("a look-alike that leads the value names no crawler", {
  row <- la_rows(la_text("User-agent: \u0430bcbot", "Disallow: /x"))
  expect_identical(row$message, paste(la_none(), la_sentence(
    "U+0430 CYRILLIC SMALL LETTER A at byte 1, which looks like 'a'", "abcbot"
  )))
})

test_that("a soft hyphen is named as invisible and dropped", {
  row <- la_rows(la_text("User-agent: Perplexity\u00adUser", "Disallow: /x"))
  expect_true(endsWith(row$message, la_sentence(
    "U+00AD SOFT HYPHEN at byte 11, which is invisible", "PerplexityUser",
    "without it"
  )))
})

test_that("other non-ASCII text is kept escaped in the spelling", {
  row <- la_rows(la_text("User-agent: Perplexity\u2011Us\u00e9r",
                         "Disallow: /x"))
  expect_true(endsWith(row$message, la_sentence(
    "U+2011 NON-BREAKING HYPHEN at byte 11, which looks like '-'",
    "Perplexity-Us\\xC3\\xA9r", "with ASCII in its place"
  )))
})

test_that("each wording branch for several look-alikes is pinned", {
  ends <- function(value, held, spelled, how = "written in ASCII") {
    row <- la_rows(la_text(paste0("User-agent: ", value), "Disallow: /x"))
    expect_true(endsWith(row$message, la_sentence(held, spelled, how)),
                label = value)
  }
  # Nothing invisible: no "or are invisible".
  ends("a‐b‑c", paste0(
    "characters that look like ASCII: U+2010 HYPHEN at byte 2 (looks ",
    "like '-'), U+2011 NON-BREAKING HYPHEN at byte 6 (looks like '-')"
  ), "a-b-c")
  # A soft hyphen beside a hyphen: dropped and replaced, all ASCII after.
  ends("a­b‑c", paste0(
    "characters that look like ASCII or are invisible: U+00AD SOFT HYPHEN ",
    "at byte 2 (invisible), U+2011 NON-BREAKING HYPHEN at byte 5 (looks ",
    "like '-')"
  ), "ab-c")
  # Other non-ASCII text kept: replaced only, then replaced and dropped.
  ends("a‐b‑cé", paste0(
    "characters that look like ASCII: U+2010 HYPHEN at byte 2 (looks ",
    "like '-'), U+2011 NON-BREAKING HYPHEN at byte 6 (looks like '-')"
  ), "a-b-c\\xC3\\xA9", "with ASCII in their place")
  ends("a­b‑cé", paste0(
    "characters that look like ASCII or are invisible: U+00AD SOFT HYPHEN ",
    "at byte 2 (invisible), U+2011 NON-BREAKING HYPHEN at byte 5 (looks ",
    "like '-')"
  ), "ab-c\\xC3\\xA9",
  "with ASCII for the look-alikes and the invisible one dropped")
  # One invisible character beside other non-ASCII text.
  ends("a­bé", "U+00AD SOFT HYPHEN at byte 2, which is invisible",
       "ab\\xC3\\xA9", "without it")
})

test_that("a Google token cut by a look-alike still warns", {
  row <- la_rows(la_text("User-agent: Googlebot\u2011Image", "Disallow: /x"))
  expect_identical(row$severity, "warning")
  expect_true(endsWith(row$message, la_sentence(
    "U+2011 NON-BREAKING HYPHEN at byte 10, which looks like '-'",
    "Googlebot-Image"
  )))
})

test_that("Bing or Yandex is named only for its own crawler", {
  row <- la_rows(la_text("User-agent: Bingb\u043et", "Disallow: /x"))
  expect_identical(row$message, paste0(
    la_read_as("Bingb"), " ",
    la_sentence(paste0("U+043E CYRILLIC SMALL LETTER O at byte 6, which ",
                       "looks like 'o'"), "Bingbot"),
    " The package's Bing matcher compares the whole value as written, so ",
    "there 'Bingbot' does not match this line either."
  ))
  row <- la_rows(la_text("User-agent: Yande\u0445", "Disallow: /x"))
  expect_true(endsWith(row$message, paste0(
    "The package's Yandex matcher compares the whole value as written, so ",
    "there 'Yandex' does not match this line either."
  )))
  expect_false(grepl("Bing", row$message, fixed = TRUE))
  # A spelling that is not exactly a selector names no engine.
  row <- la_rows(la_text("User-agent: Bingb\u043et-Image", "Disallow: /x"))
  expect_false(grepl("Bing matcher|Yandex", row$message))
})

test_that("an unknown key names its look-alike and the ASCII spelling", {
  row <- la_rows(la_text("Dis\u0430llow: /a"), "unknown_directive")
  expect_identical(row$message, paste(
    la_unknown,
    paste0("The key holds U+0430 CYRILLIC SMALL LETTER A at byte 4, which ",
           "looks like 'a'; written in ASCII the key is 'Disallow'.")
  ))
  expect_false(grepl("[^ -~]", row$message))
  x <- la_text("User-\u0430gent: foo", "Disallow: /a")
  expect_true(endsWith(la_rows(x, "unknown_directive")$message,
                       "written in ASCII the key is 'User-agent'."))
  # Not valid UTF-8: today's text.
  key <- c(charToRaw("Dis\u0430llow"), as.raw(0xE4), charToRaw(": /a\n"))
  expect_identical(la_rows(robots_validate_text(key),
                           "unknown_directive")$message, la_unknown)
})

test_that("only a cut value that is valid UTF-8 is read", {
  bytes <- c(charToRaw("User-agent: Perplexity\u2011User"), as.raw(0xE4),
             charToRaw("\nDisallow: /x\n"))
  x <- robots_validate_text(bytes)
  expect_true("invalid_utf8" %in% x$diagnostics$code)
  expect_identical(la_rows(x)$message, la_read_as("Perplexity"))
})

test_that("at most ten look-alikes are named, then a count", {
  eleven <- c(0x0430, 0x0435, 0x043E, 0x0440, 0x0441, 0x0443, 0x0445,
              0x0456, 0x0458, 0x0455, 0x0501)
  value <- paste0("X", intToUtf8(eleven))
  row <- la_rows(la_text(paste0("User-agent: ", value), "Disallow: /x"))
  expect_true(grepl(paste0(
    "U+0455 CYRILLIC SMALL LETTER DZE at byte 20 (looks like 's'), and ",
    "1 more; written in ASCII the value is 'Xaeopcyxijsd'"
  ), row$message, fixed = TRUE))
  expect_false(grepl("KOMI DE", row$message, fixed = TRUE))
  expect_identical(lengths(regmatches(row$message, gregexpr(
    "U\\+[0-9A-F]{4}", row$message
  ))), 10L)
})

test_that("a character split by the line buffer is dropped first", {
  # The line buffer keeps 16,663 bytes: the U+2011 at the end loses its
  # last byte, and the one at byte 11 is still named.
  head <- paste0("User-agent: Perplexity\u2011User",
                 strrep("A", 16663L - 29L - 2L))
  body <- paste0(head, "\u2011B\nDisallow: /x\n")
  x <- robots_validate_text(body)
  expect_true("line_too_long" %in% x$diagnostics$code)
  row <- la_rows(x)
  expect_identical(nrow(row), 1L)
  expect_true(grepl(paste0(
    "The value holds U+2011 NON-BREAKING HYPHEN at byte 11, which looks ",
    "like '-'; written in ASCII the value is 'Perplexity-UserAAA"
  ), row$message, fixed = TRUE))
})

test_that("a long line whose value ends before the buffer keeps its tail", {
  # A comment or trailing blanks make the line long, but the value ends
  # well before the buffer: its own E2 80 is invalid UTF-8, not a cut, so
  # today's handling stays and no look-alike sentence misquotes it.
  value <- c(charToRaw("User-agent: Bingbоt"), as.raw(c(0xE2, 0x80)))
  tails <- list(comment = c(charToRaw(" #"), rep(charToRaw("c"), 17000L)),
                blanks = rep(charToRaw(" "), 17000L))
  for (name in names(tails)) {
    body <- c(value, tails[[name]], charToRaw("\nDisallow: /x\n"))
    x <- robots_validate_text(body)
    expect_true("line_too_long" %in% x$diagnostics$code, label = name)
    expect_true("invalid_utf8" %in% x$diagnostics$code, label = name)
    row <- la_rows(x)
    expect_identical(nrow(row), 1L, label = name)
    expect_identical(row$message, la_read_as("Bingb"), label = name)
    expect_identical(row$severity, "info", label = name)
  }
})

# Timing guards (ROBO-dbvmxcfw keeps the validator linear), in the
# load-robust pattern of test-cut-note-zqyqbudf.R: each check is timed best
# of five, so one slow run under machine load does not count.
la_best <- function(f) {
  min(vapply(1:5, function(i) system.time(f())[["elapsed"]], 0))
}

la_values <- function(n) {
  sprintf("Peer%s\u2011\u0430gent",
          chartr("0123456789", "abcdefghij", seq_len(n)))
}

test_that("the look-alike notes grow linearly with the cut lines", {
  skip_on_cran()
  small <- la_values(1000L)
  large <- la_values(4000L)
  t_small <- la_best(function() user_agent_lookalike_notes(small))
  t_large <- la_best(function() user_agent_lookalike_notes(large))
  expect_lt(t_large, 8 * max(t_small, 0.05))
})

test_that("one look-alike value's note grows linearly with its length", {
  skip_on_cran()
  small <- strrep("a\u2011\u0430", 4000L)
  large <- strrep("a\u2011\u0430", 16000L)
  t_small <- la_best(function() lookalike_note(small, "value"))
  t_large <- la_best(function() lookalike_note(large, "value"))
  expect_lt(t_large, 8 * max(t_small, 0.05))
})

test_that("the look-alike notes are a small share of the validator", {
  skip_on_cran()
  body <- paste0(paste0("User-agent: ", la_values(2000L), "\nDisallow: /x",
                        collapse = "\n"), "\n")
  runs <- vapply(1:5, function(i) {
    with_note <- system.time(robots_validate_text(body))[["elapsed"]]
    without <- system.time(with_mocked_bindings(
      robots_validate_text(body),
      user_agent_lookalike_notes = function(values) {
        character(length(values))
      }
    ))[["elapsed"]]
    c(with_note, without)
  }, numeric(2L))
  best <- apply(runs, 1L, min)
  expect_lt(best[[1L]], 1.5 * best[[2L]] + 0.05)
})
