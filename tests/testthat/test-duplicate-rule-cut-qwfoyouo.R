# ROBO-qwfoyouo: Google's matcher cuts a User-agent value at its first
# character outside letters, `_` and `-`, so `Foo web spider` and `Foo blog`
# both name `Foo` there and their groups merge. A duplicate_rule row that
# exists only through that merge says so; a duplicate across groups naming
# the same uncut crawler keeps today's row. Fixtures are synthetic.

dc_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

dc_rows <- function(body, code = "duplicate_rule") {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == code, , drop = FALSE]
}

dc_plain <- function(first_line, type = "Disallow") {
  sprintf("Rule has no effect: line %d already has the same %s.",
          first_line, type)
}

# Three groups whose values Google reads as `Foo`, sharing two rules.
dc_cut_shape <- dc_lines(
  "User-agent: Foo web spider", "Disallow: /a", "Disallow: /b", "",
  "User-agent: Foo blog", "Disallow: /a", "Disallow: /b", "",
  "User-agent: Foo News Spider", "Disallow: /a", "Disallow: /b"
)

test_that("groups merged by a cut draw duplicate_rule rows", {
  d <- dc_rows(dc_cut_shape)
  expect_identical(d$line, c(6L, 7L, 10L, 11L))
  expect_identical(d$severity, rep("info", 4L))
})

# `read_as` is the written values and the token, as the message lists them.
dc_cut <- function(first_line, read_as, type = "Disallow") {
  sprintf(paste0(
    "This %s repeats line %d only for Google's matcher, which reads %s ",
    "and merges their groups. The package's Bing and Yandex matchers ",
    "compare the whole value and keep the groups apart, so there it is not ",
    "a repeat; see the user_agent_cut rows."
  ), type, first_line, read_as)
}

test_that("a repeat only through the cut merge says so", {
  d <- dc_rows(dc_cut_shape)
  two <- "'Foo web spider' and 'Foo blog' as one token, 'Foo',"
  three <- paste("'Foo web spider', 'Foo blog' and 'Foo News Spider' as",
                 "one token, 'Foo',")
  expect_identical(d$message, c(dc_cut(2L, two), dc_cut(3L, two),
                                dc_cut(2L, three), dc_cut(3L, three)))
  for (message in d$message) {
    expect_no_match(message, "no effect|delete|remove")
    expect_match(message, "^[ -~]*$")
  }
})

test_that("an Allow names its own directive", {
  d <- dc_rows(dc_lines(
    "User-agent: Foo/1.0", "Allow: /a", "Disallow: /", "",
    "User-agent: Foo/2.0", "Allow: /a", "Disallow: /"
  ))
  read_as <- "'Foo/1.0' and 'Foo/2.0' as one token, 'Foo',"
  expect_identical(d$line, c(6L, 7L))
  expect_identical(d$message, c(dc_cut(2L, read_as, "Allow"),
                                dc_cut(3L, read_as)))
})

test_that("at most five written values are named, then a count", {
  d <- dc_rows(dc_lines(
    sprintf("User-agent: Foo %d\nDisallow: /a\nDisallow: /b\n", 1:7)
  ))
  last <- d[d$line == max(d$line), , drop = FALSE]
  expect_identical(last$message, dc_cut(
    3L, paste("'Foo 1', 'Foo 2', 'Foo 3', 'Foo 4', 'Foo 5' and 2 more as",
              "one token, 'Foo',")
  ))
  five <- d[d$line == 19L, , drop = FALSE]
  expect_identical(five$message, dc_cut(
    3L, paste("'Foo 1', 'Foo 2', 'Foo 3', 'Foo 4' and 'Foo 5' as",
              "one token, 'Foo',")
  ))
})

test_that("only the values of a token the cut merges are named", {
  # Both groups name `Bar` whole, so a whole-value reader merges them too:
  # the plain text.
  d <- dc_rows(dc_lines(
    "User-agent: Foo a", "User-agent: Bar", "Disallow: /a", "Disallow: /z",
    "", "User-agent: Foo b", "User-agent: Bar", "Disallow: /a"
  ))
  expect_identical(d$message, dc_plain(3L))
  # Both tokens are named when the cut merges both.
  d <- dc_rows(dc_lines(
    "User-agent: Foo a", "User-agent: Bar a", "Disallow: /a", "Disallow: /z",
    "", "User-agent: Foo b", "User-agent: Bar b", "Disallow: /a"
  ))
  expect_identical(d$message, dc_cut(3L, paste(
    "'Foo a', 'Bar a', 'Foo b' and 'Bar b' as the tokens 'Foo' and 'Bar'"
  )))
})

test_that("a written value is named as raw_text renders it", {
  body <- c(charToRaw("User-agent: Foo"), as.raw(0xe9),
            charToRaw("\nDisallow: /a\nDisallow: /z\n\nUser-agent: Foo bar\n"),
            charToRaw("Disallow: /a\n"))
  d <- dc_rows(body)
  expect_identical(d$line, 6L)
  expect_identical(d$message,
                   dc_cut(2L, "'Foo\\xE9' and 'Foo bar' as one token, 'Foo',"))
  # A value written as the text `\xE9` is another value than the byte.
  body <- c(charToRaw("User-agent: Foo"), as.raw(0xe9),
            charToRaw("\nDisallow: /a\nDisallow: /z\n\n"),
            charToRaw("User-agent: Foo\\xE9\nDisallow: /a\n"))
  expect_identical(dc_rows(body)$message,
                   dc_cut(2L, "'Foo\\xE9' and 'Foo\\xE9' as one token, 'Foo',"))
  # Values differing only in ASCII case are one whole value: the groups
  # share it and merge for a whole-value reader too.
  d <- dc_rows(dc_lines(
    "User-agent: Foo a", "Disallow: /a", "Disallow: /z", "",
    "User-agent: FOO A", "User-agent: Foo b", "Disallow: /a", "Disallow: /y",
    "", "User-agent: Foo a", "User-agent: Foo b", "Disallow: /a"
  ))
  expect_identical(d$line, c(7L, 12L))
  expect_identical(d$message, dc_plain(c(2L, 2L)))
})

test_that("a NUL in the file keeps Google's reading note", {
  body <- c(charToRaw(dc_cut_shape), as.raw(0), charToRaw("x\n"))
  d <- dc_rows(body)
  expect_identical(d$line, c(6L, 7L, 10L, 11L))
  expect_true(all(endsWith(d$message, paste0(
    "see the user_agent_cut rows. This is Google's reading, which ends each ",
    "line at its first NUL; Bing and Yandex read the NUL as an ordinary byte."
  ))))
})

test_that("a body cut at max_bytes is still checked", {
  body <- charToRaw(paste0(dc_cut_shape, "Disallow: /later-",
                           strrep("x", 200L), "\n"))
  n <- length(charToRaw(dc_cut_shape)) + 10L
  x <- validate_document_bytes(body[seq_len(n)], "s", "supplied",
                               max_bytes = n, body_truncated = TRUE)
  d <- x$diagnostics[x$diagnostics$code == "duplicate_rule", , drop = FALSE]
  expect_identical(d$line, c(6L, 7L, 10L, 11L))
  expect_match(d$message, "^This Disallow repeats line [23] only")
})

test_that("a large file of cut agents names every repeat", {
  rules <- sprintf("Disallow: /r%d", seq_len(20L))
  body <- dc_lines(unlist(lapply(seq_len(50L), function(i) {
    c(sprintf("User-agent: Foo %d", i), rules, "")
  })))
  d <- dc_rows(body)
  expect_identical(nrow(d), 49L * 20L)
  expect_match(d$message, "^This Disallow repeats line ")
  expect_identical(sum(grepl("and 45 more as one token, 'Foo',", d$message,
                             fixed = TRUE)), 20L)
})

test_that("the user_agent_cut rows do not depend on the repeated rules", {
  apart <- dc_lines(
    "User-agent: Foo web spider", "Disallow: /a", "Disallow: /b", "",
    "User-agent: Foo blog", "Disallow: /c", "Disallow: /d", "",
    "User-agent: Foo News Spider", "Disallow: /e", "Disallow: /f"
  )
  expect_identical(nrow(dc_rows(apart)), 0L)
  cut <- dc_rows(dc_cut_shape, "user_agent_cut")
  expect_identical(cut$line, c(1L, 5L, 9L))
  rownames(cut) <- NULL
  expect_identical(cut, dc_rows(apart, "user_agent_cut"))
})

test_that("a duplicate across uncut groups keeps today's text", {
  d <- dc_rows(dc_lines(
    "User-agent: Foo", "Disallow: /a", "", "User-agent: foo", "Disallow: /a"
  ))
  expect_identical(d$line, 5L)
  expect_identical(d$message, dc_plain(2L))
  # Within one group a cut value changes nothing: the line repeats there.
  d <- dc_rows(dc_lines("User-agent: Foo bar", "Disallow: /a",
                        "Disallow: /a"))
  expect_identical(d$line, 3L)
  expect_identical(d$message, dc_plain(2L))
  # The same cut value twice is the same crawler, cut or not.
  d <- dc_rows(dc_lines(
    "User-agent: Foo bar", "Disallow: /a", "", "User-agent: foo BAR",
    "Disallow: /a"
  ))
  expect_identical(d$line, 5L)
  expect_identical(d$message, dc_plain(2L))
})

test_that("a rule an uncut group already gives is a real duplicate", {
  # Line 9 repeats line 2 for `foo` with no cut, though the merge of
  # `Foo bar` into `foo` covers it too; line 5 repeats line 2 only through
  # that merge.
  d <- dc_rows(dc_lines(
    "User-agent: foo", "Disallow: /a", "", "User-agent: Foo bar",
    "Disallow: /a", "Disallow: /z", "", "User-agent: foo", "Disallow: /a"
  ))
  expect_identical(d$line, c(5L, 9L))
  expect_identical(d$message, c(
    dc_cut(2L, "'foo' and 'Foo bar' as one token, 'foo',"), dc_plain(2L)
  ))
})

test_that("a group sharing a whole value merges for every matcher", {
  # The repeat's group also names `bingbot` (`Yandex`) whole, so the Bing
  # (Yandex) backend merges it with the earlier group: line 6 is a repeat
  # there too, and keeps the plain text. Without line 2's rule, line 6
  # decides.
  for (case in list(c("bingbot", "bingbot/2.0", "bing"),
                    c("Yandex", "Yandex 2.0", "yandex"))) {
    body <- function(first_rule) {
      dc_lines(paste("User-agent:", case[[1L]]), first_rule, "",
               paste("User-agent:", case[[1L]]),
               paste("User-agent:", case[[2L]]), "Disallow: /a")
    }
    d <- dc_rows(body("Disallow: /a"))
    expect_identical(d$line, 6L, label = case[[3L]])
    expect_identical(d$message, dc_plain(2L), label = case[[3L]])
    for (rule in c("Disallow: /a", "Disallow: /zz")) {
      x <- robots_evaluate_text_v1(body(rule), "http://e.com/a", case[[1L]],
                                   case[[3L]], case[[3L]])$results
      expect_identical(x$url_decision, "disallow", label = case[[3L]])
      expect_identical(x$matched_line,
                       if (rule == "Disallow: /a") 2L else 6L,
                       label = case[[3L]])
    }
  }
})

test_that("a cut value Google reads no token from is a whole value", {
  d <- dc_rows(dc_lines(
    "User-agent: Foo", "Disallow: /a", "Disallow: /b", "", "User-agent: Foo",
    "User-agent: 1bot", "Disallow: /a"
  ))
  expect_identical(d$line, 7L)
  expect_identical(d$message, dc_plain(2L))
  # Shared only by `1bot`, the groups still merge for a whole-value reader.
  d <- dc_rows(dc_lines(
    "User-agent: Foo a", "User-agent: 1bot", "Disallow: /a", "Disallow: /b",
    "", "User-agent: Foo b", "User-agent: 1bot", "Disallow: /a"
  ))
  expect_identical(d$line, 8L)
  expect_identical(d$message, dc_plain(3L))
})

# The matchers, unchanged by this ticket. Each probe file has a second group
# whose value Google cuts to the first group's token and a rule only that
# group holds: `/y` is disallowed where the groups merge. The probed crawler
# token is letters only, as the Bing and Yandex backends accept only their
# own crawlers' tokens and refuse a value such as `bingbot/2.0`.
dc_probe <- function(first, second, token, backend) {
  body <- dc_lines(paste("User-agent:", first), "Disallow: /x", "",
                   paste("User-agent:", second), "Disallow: /y")
  robots_evaluate_text_v1(body, c("http://e.com/x", "http://e.com/y"),
                          token, backend, backend)$results
}

test_that("Google's matcher merges groups whose values cut to one token", {
  for (pair in list(c("Googlebot", "Googlebot/2.1"),
                    c("bingbot", "bingbot/2.0"),
                    c("Yandex", "Yandex 2.0"))) {
    x <- dc_probe(pair[[1L]], pair[[2L]], pair[[1L]], "google")
    expect_identical(x$url_decision, c("disallow", "disallow"),
                     label = toString(pair))
    expect_identical(x$matched_line, c(2L, 5L), label = toString(pair))
  }
  x <- allowed_by_robots_text(dc_cut_shape, "http://e.com/a", "Foo")
  expect_false(x$results$allowed)
  expect_identical(x$results$matched_line, 2L)
})

test_that("the Bing and Yandex matchers keep those groups apart", {
  for (second in c("bingbot/2.0", "bingbot spider", "bingbot*")) {
    x <- dc_probe("bingbot", second, "bingbot", "bing")
    expect_identical(x$url_decision, c("disallow", "allow"), label = second)
    expect_identical(x$matched_line, c(2L, NA), label = second)
  }
  for (second in c("Yandex 2.0", "Yandex/2.0", "Yandex spider")) {
    x <- dc_probe("Yandex", second, "Yandex", "yandex")
    expect_identical(x$url_decision, c("disallow", "allow"), label = second)
    expect_identical(x$matched_line, c(2L, NA), label = second)
  }
  # Neither backend evaluates a crawler going by the full cut value.
  x <- dc_probe("bingbot", "bingbot/2.0", "bingbot/2.0", "bing")
  expect_identical(x$matcher_status, rep("unsupported_profile", 2L))
  x <- dc_probe("Yandex", "Yandex 2.0", "Yandex 2.0", "yandex")
  expect_identical(x$matcher_status, rep("not_evaluated", 2L))
})

for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("whole values compare the same under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    same <- dc_rows(dc_lines(
      "User-agent: ID-Bot i", "Disallow: /x", "", "User-agent: id-bot I",
      "Disallow: /x"
    ))
    expect_identical(same$message, dc_plain(2L))
    apart <- dc_rows(dc_lines(
      "User-agent: ID-Bot i", "Disallow: /x", "", "User-agent: id-bot j",
      "Disallow: /x"
    ))
    expect_identical(apart$message, dc_cut(
      2L, "'ID-Bot i' and 'id-bot j' as one token, 'ID-Bot',"
    ))
  })
}
