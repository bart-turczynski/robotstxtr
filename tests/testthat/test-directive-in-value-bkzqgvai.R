# ROBO-bkzqgvai: a line whose value holds a second directive key, after a
# blank (`User-agent: * Disallow: /`) or glued on (`ExampleBotAllow: /`),
# from line breaks lost when the file was saved. `directive_in_value` states
# Google's reading only, then that Bing and Yandex may read the line
# differently. Fixtures are synthetic.

dv_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")
dv_text <- function(...) robots_validate_text(dv_lines(...))
dv_codes <- function(x) {
  d <- x$diagnostics
  paste(d$line, d$code)
}
dv_rows <- function(x, code = "directive_in_value") {
  d <- x$diagnostics
  d[d$code == code, , drop = FALSE]
}

# Google's decision for `token` on `path`, the reading the rows state.
dv_google <- function(body, token, path) {
  r <- robots_evaluate_text_v1(body, paste0("https://example.com", path),
                               token, "google", "google")$results
  paste(r$url_decision, r$matched_line)
}

dv_ex1 <- dv_lines("User-agent: * Disallow: /private/",
                   "User-agent: ExampleBot", "Disallow: /")
dv_a <- dv_lines("User-agent: *", "Disallow: /", "",
                 "User-agent: ExampleBotAllow: /")
dv_b <- dv_lines("User-agent: *Disallow: /private/")
dv_c <- dv_lines("User-agent: *", "Disallow: /admin/Crawl-delay: 10")

dv_others <- " Bing and Yandex may read the line differently."
dv_lead <- function(key, column, rest, apply = TRUE) {
  sprintf(paste0("The value holds the directive key `%s` at byte column %d. ",
                 "Google reads the text from `%s` on as part of this line's ",
                 "value, so Google does not %s."), key, column, key,
          if (apply) sprintf("apply `%s`", rest) else
            sprintf("read `%s` as a line of its own", rest))
}
dv_star <- " Google reads this line as `User-agent: *`."
dv_path <- function(whole) {
  sprintf(" Google reads the whole value, `%s`, as the rule's path.", whole)
}
dv_stack <- function(line, rules, who) {
  sprintf(paste0(" Google joins the User-agent line after it (line %d) to ",
                 "this group, so the group's rules (%s) apply to %s."),
          line, rules, who)
}
dv_every <- "`*` too, so to every crawler without a group of its own"

# The Google claims each message makes, on the Google backend.
test_that("Google's reading of the ticket's examples", {
  # Line 1 is `User-agent: *` with no rule of its own; line 2 joins its
  # group, so line 3 applies to every crawler.
  expect_identical(dv_google(dv_ex1, "OtherBot", "/private/x"), "disallow 3")
  expect_identical(dv_google(dv_ex1, "ExampleBot", "/private/x"),
                   "disallow 3")
  # The hidden rule is not applied.
  expect_identical(
    dv_google(dv_lines("User-agent: * Disallow: /"), "OtherBot", "/page"),
    "allow NA"
  )
  expect_identical(
    dv_google(dv_lines("User-agent: ExampleBot Disallow: /"), "ExampleBot",
              "/page"),
    "allow NA"
  )
  # ExampleBot gets the `*` group: line 4 names `ExampleBotAllow` only.
  expect_identical(dv_google(dv_a, "ExampleBot", "/page"), "disallow 2")
  # No rules at all: `*Disallow` is no `*` line.
  expect_identical(dv_google(dv_b, "ExampleBot", "/private/x"), "allow NA")
  # The path is `/admin/Crawl-delay: 10`, which `/admin/x` does not match.
  expect_identical(dv_google(dv_c, "ExampleBot", "/admin/x"), "allow NA")
})

test_that("Google's reading of the stacks and rule values", {
  # The token read on a spaced line joins the next group.
  body <- dv_lines("User-agent: Foo Disallow: /x", "User-agent: Bar",
                   "Disallow: /y")
  expect_identical(dv_google(body, "Foo", "/y"), "disallow 3")
  expect_identical(dv_google(body, "Foo", "/x"), "allow NA")
  # On a glued line the token read is `FooAllow`; `Foo` gets no rules.
  body <- dv_lines("User-agent: FooAllow: /x", "User-agent: Bar",
                   "Disallow: /y")
  expect_identical(dv_google(body, "FooAllow", "/y"), "disallow 3")
  expect_identical(dv_google(body, "Foo", "/y"), "allow NA")
  # A rule's whole value is its path.
  body <- dv_lines("User-agent: *", "Disallow: /a Allow: /b")
  expect_identical(dv_google(body, "Foo", "/b"), "allow NA")
  expect_identical(dv_google(body, "Foo", "/a Allow: /b"), "disallow 2")
  # The sitemap URL is the whole value on Google's parser.
  parsed <- robotstxtr_validation_parse_(charToRaw(
    "Sitemap: https://example.com/s.xml Crawl-delay: 5\n"
  ))
  expect_identical(parsed$value[[1L]],
                   "https://example.com/s.xml Crawl-delay: 5")
})

test_that("consistency with the package's backend", {
  # Not evidence of what Bing or Yandex do; no message text depends on it.
  run <- function(body, path, backend, token) {
    r <- robots_evaluate_text_v1(body, paste0("https://example.com", path),
                                 token, "google", backend)$results
    paste(r$url_decision, r$matched_line)
  }
  expect_identical(run(dv_ex1, "/private/x", "bing", "bingbot"), "allow NA")
  expect_identical(run(dv_ex1, "/private/x", "yandex", "Yandex"), "allow NA")
  expect_identical(run(dv_a, "/page", "bing", "bingbot"), "disallow 2")
  expect_identical(run(dv_a, "/page", "yandex", "Yandex"), "disallow 2")
})

test_that("the ticket's examples get one row on the line", {
  expect_identical(dv_codes(robots_validate_text(dv_ex1)),
                   "1 directive_in_value")
  # no_rules stays.
  expect_identical(dv_codes(dv_text("User-agent: * Disallow: /")),
                   c("1 directive_in_value", "NA no_rules"))
  # It replaces the user_agent_cut row.
  expect_identical(dv_codes(dv_text("User-agent: ExampleBot Disallow: /")),
                   c("1 directive_in_value", "NA no_rules"))
  expect_identical(dv_codes(robots_validate_text(dv_a)),
                   "4 directive_in_value")
  expect_identical(dv_codes(robots_validate_text(dv_b)),
                   c("1 directive_in_value", "NA no_rules"))
  # rule_inner_whitespace stays.
  expect_identical(dv_codes(robots_validate_text(dv_c)),
                   c("2 rule_inner_whitespace", "2 directive_in_value"))
  row <- dv_rows(robots_validate_text(dv_ex1))
  expect_identical(row$severity, "warning")
  expect_identical(row$directive, "user-agent")
  expect_identical(row$raw_text, "User-agent: * Disallow: /private/")
})

test_that("example 1 names the hidden rule and Google's stack", {
  expect_identical(
    dv_rows(robots_validate_text(dv_ex1))$message,
    paste0(dv_lead("Disallow:", 15L, "Disallow: /private/"), dv_star,
           dv_stack(2L, "line 3", dv_every), dv_others)
  )
})

test_that("`User-agent: * Disallow: /` alone names the rule Google drops", {
  expect_identical(
    dv_rows(dv_text("User-agent: * Disallow: /"))$message,
    paste0(dv_lead("Disallow:", 15L, "Disallow: /"), dv_star, dv_others)
  )
  expect_identical(
    dv_rows(dv_text("User-agent: ExampleBot Disallow: /"))$message,
    paste0(dv_lead("Disallow:", 24L, "Disallow: /"),
           " Google's matcher reads the User-agent value as `ExampleBot`, ",
           "the text before `Disallow:`.", dv_others)
  )
})

test_that("example A names ExampleBot and the lost Allow, no such crawler", {
  message <- dv_rows(robots_validate_text(dv_a))$message
  expect_identical(message, paste0(
    dv_lead("Allow:", 23L, "Allow: /"),
    " Google's matcher reads the User-agent value only up to its first ",
    "character outside letters, '_' and '-', as `ExampleBotAllow`, not as ",
    "`ExampleBot`, the text before `Allow:`. Unless another group names it, ",
    "a crawler going by `ExampleBot` gets the `User-agent: *` group from ",
    "Google's matcher.", dv_others
  ))
  expect_false(grepl("crawler[^.]*ExampleBotAllow", message))
  # Without a `*` group, and in a `*` group.
  expect_match(
    dv_rows(dv_text("User-agent: ExampleBotAllow: /"))$message,
    paste0("a crawler going by `ExampleBot` gets no rules from Google's ",
           "matcher: the file has no `User-agent: *` group."), fixed = TRUE
  )
  expect_match(
    dv_rows(dv_text("User-agent: *", "User-agent: ExampleBotAllow: /",
                    "Disallow: /x"))$message,
    paste0("a crawler going by `ExampleBot` still gets this group from ",
           "Google's matcher, since the group also names `User-agent: *`."),
    fixed = TRUE
  )
})

test_that("example B names no crawler and no `*` line", {
  expect_identical(
    dv_rows(robots_validate_text(dv_b))$message,
    paste0(dv_lead("Disallow:", 14L, "Disallow: /private/"),
           " Google's matcher reads no product token from the User-agent ",
           "value, as it reads one only from a leading run of letters, '_' ",
           "and '-', so on Google this line names no crawler and `*`, the ",
           "text before `Disallow:`, is not read as `User-agent: *`.",
           dv_others)
  )
})

test_that("example C names the lost Crawl-delay and the rule's path", {
  expect_identical(
    dv_rows(robots_validate_text(dv_c))$message,
    paste0(dv_lead("Crawl-delay:", 18L, "Crawl-delay: 10", apply = FALSE),
           dv_path("/admin/Crawl-delay: 10"), dv_others)
  )
})

test_that("each value type and each key is read", {
  x <- dv_text("User-agent: *", "Allow: /a Disallow: /b",
               "Disallow: /c allow: /d",
               "Sitemap: https://example.com/s.xml Crawl-delay: 5",
               "Crawl-delay: 5 Host: example.com",
               "Host: example.com User-agent: x",
               "Disallow: /e Sitemap: https://example.com/s.xml",
               "User-agent: Foo DISALLOW: /")
  row <- dv_rows(x)
  expect_identical(row$line, 2:8)
  expect_identical(row$directive, c("allow", "disallow", "sitemap",
                                    "crawl-delay", "host", "disallow",
                                    "user-agent"))
  expect_identical(
    sub(paste0("^The value holds the directive key `([^`]*)` at byte ",
               "column ([0-9]+).*"), "\\1 \\2", row$message),
    c("Disallow: 11", "allow: 14", "Crawl-delay: 36", "Host: 16",
      "User-agent: 19", "Sitemap: 14", "DISALLOW: 17")
  )
  expect_identical(
    row$message[[3L]],
    paste0(dv_lead("Crawl-delay:", 36L, "Crawl-delay: 5", apply = FALSE),
           " Google reads the whole value, `https://example.com/s.xml ",
           "Crawl-delay: 5`, as the sitemap URL.", dv_others)
  )
  expect_identical(
    row$message[[4L]],
    paste0(dv_lead("Host:", 16L, "Host: example.com", apply = FALSE),
           dv_others)
  )
  # The Sitemap value keeps invalid_sitemap_url.
  expect_true("4 invalid_sitemap_url" %in% dv_codes(x))
})

test_that("a spaced key in any case, a glued key in its usual spelling", {
  x <- dv_text("User-agent: *", "Disallow: /c allow: /d",
               "Disallow: /eDisallow: /f", "Disallow: /swallow:x",
               "Disallow: /gdisallow: /h", "Disallow: /i Allow : /j",
               "Disallow: /k\tSITEMAP:/l")
  expect_identical(dv_rows(x)$line, c(2L, 3L, 6L, 7L))
  expect_match(dv_rows(x)$message[[3L]], "`Allow :` at byte column 14",
               fixed = TRUE)
})

test_that("a key needs its colon", {
  x <- dv_text("User-agent: ExampleBot Disallow /", "User-agent: Bar",
               "Disallow: /x Allow /y", "Disallow: /allowance/",
               "Disallow: /a:b")
  expect_identical(nrow(dv_rows(x)), 0L)
  expect_true("1 user_agent_cut" %in% dv_codes(x))
})

test_that("the hidden line's user_agent_cut row is replaced, no other", {
  x <- dv_text("User-agent: *", "Disallow: /", "",
               "User-agent: ExampleBotAllow: /", "User-agent: Other/1.0",
               "Disallow: /x")
  codes <- dv_codes(x)
  expect_true("4 directive_in_value" %in% codes)
  expect_false("4 user_agent_cut" %in% codes)
  expect_true("5 user_agent_cut" %in% codes)
})

test_that("a pointer to the line's cut names directive_in_value", {
  # A joined row naming the hidden line.
  x <- dv_text("User-agent: *", "Disallow: /x", "User-agent: Foo Allow: /a",
               "Sitemap: https://example.com/s.xml", "User-agent: Bar",
               "Disallow: /")
  joined <- dv_rows(x, "user_agent_joined_across_directive")$message
  expect_match(joined, paste0("Google's matcher reads only a product token ",
                              "from `Foo Allow: /a` (line 3) and takes the ",
                              "agent to be that token; see the ",
                              "directive_in_value row."), fixed = TRUE)
  # The hidden row points to the joined row of the line after it.
  expect_match(dv_rows(x)$message,
               "See the user_agent_joined_across_directive row on line 5.",
               fixed = TRUE)
  # Beside a cut line without a hidden key.
  x <- dv_text("User-agent: *", "Disallow: /x", "User-agent: Foo Allow: /a",
               "User-agent: Baz/1.0", "Sitemap: https://example.com/s.xml",
               "User-agent: Bar", "Disallow: /")
  joined <- dv_rows(x, "user_agent_joined_across_directive")$message
  expect_match(joined, "see the user_agent_cut and directive_in_value rows.",
               fixed = TRUE)
})

test_that("rows naming agents leave a hidden User-agent line out", {
  # A group whose only agent line hides a key draws no wildcard row.
  expect_false(any(grepl("^wildcard|^allow_reopens_wildcard",
                         robots_validate_text(dv_a)$diagnostics$code)))
  # In a mixed group the glued name is dropped.
  x <- dv_text("User-agent: *", "Disallow: /", "", "User-agent: GoodBot",
               "User-agent: ExampleBotAllow: /", "Disallow: /tmp")
  wild <- dv_rows(x, "wildcard_disallows_not_inherited")
  expect_identical(wild$line, 4L)
  expect_match(wild$message, "^GoodBot obeys only this group")
  expect_false(grepl("ExampleBot", wild$message, fixed = TRUE))
  # A repeated `*` group: the hidden line is owned.
  x <- dv_text("User-agent: *", "Disallow: /a",
               "User-agent: * Disallow: /b", "Disallow: /c")
  expect_identical(dv_codes(x), "3 directive_in_value")
  # The same with a plain `*` line draws the repeat.
  x <- dv_text("User-agent: *", "Disallow: /a", "User-agent: *",
               "Disallow: /c")
  expect_identical(dv_codes(x), "3 user_agent_repeated_group")
  # A duplicate in one group.
  x <- dv_text("User-agent: Foo", "User-agent: Foo Allow: /", "Disallow: /")
  expect_identical(dv_codes(x), "2 directive_in_value")
})

test_that("Google's stack follows the line's group", {
  # No rules in the group.
  expect_identical(
    dv_rows(dv_text("User-agent: * Disallow: /x", "User-agent: Foo"))$message,
    paste0(dv_lead("Disallow:", 15L, "Disallow: /x"), dv_star,
           " Google joins the User-agent line after it (line 2) to this ",
           "group.", dv_others)
  )
  # The token Google reads, spaced and glued.
  expect_identical(
    dv_rows(dv_text("User-agent: Foo Disallow: /x", "User-agent: Bar",
                    "Disallow: /y"))$message,
    paste0(dv_lead("Disallow:", 17L, "Disallow: /x"),
           " Google's matcher reads the User-agent value as `Foo`, the text ",
           "before `Disallow:`.",
           dv_stack(2L, "line 3",
                    "the token `Foo` Google reads from this line too"),
           dv_others)
  )
  expect_match(
    dv_rows(dv_text("User-agent: FooAllow: /x", "User-agent: Bar",
                    "Disallow: /y"))$message,
    dv_stack(2L, "line 3",
             "the token `FooAllow` Google reads from this line too"),
    fixed = TRUE
  )
  # No token: the line adds no crawler.
  expect_match(
    dv_rows(dv_text("User-agent: *Allow: /x", "User-agent: Bar",
                    "Disallow: /y"))$message,
    paste0(" Google joins the User-agent line after it (line 2) to this ",
           "group, to which this line adds no crawler."), fixed = TRUE
  )
  # A rule between: the next User-agent line starts a group of its own.
  expect_identical(
    dv_rows(dv_text("User-agent: * Disallow: /x", "Disallow: /z",
                    "User-agent: Foo", "Disallow: /"))$message,
    paste0(dv_lead("Disallow:", 15L, "Disallow: /x"), dv_star, dv_others)
  )
  # The group's rules, listed as joined rows list them.
  expect_match(
    dv_rows(dv_text("User-agent: * Disallow: /x", "User-agent: Foo",
                    paste0("Disallow: /p", 1:7)))$message,
    dv_stack(2L, "lines 3-9 (7 rules)", dv_every), fixed = TRUE
  )
})

test_that("the row states no Bing or Yandex reading", {
  bodies <- list(
    dv_ex1, dv_a, dv_b, dv_c, dv_lines("User-agent: * Disallow: /"),
    dv_lines("User-agent: *", "Allow: /a Disallow: /b",
             "Sitemap: https://example.com/s.xml Host: x",
             "Crawl-delay: 5 Host: x", "Host: x Allow: /")
  )
  for (body in bodies) {
    for (message in dv_rows(robots_validate_text(body))$message) {
      expect_true(endsWith(message, dv_others), label = message)
      expect_false(grepl("no engine", message, fixed = TRUE), label = message)
      # The generic clause is the only sentence naming either engine.
      expect_identical(
        lengths(regmatches(message, gregexpr("Bing|Yandex", message))), 2L,
        label = message
      )
    }
  }
})

test_that("values without a directive key and its colon draw nothing new", {
  for (body in list(
    dv_lines("User-agent: *", "Disallow: /a:b", "Disallow: /allowance/",
             "Disallow: /swallow:x", "Disallow: /x?user-agent=y"),
    dv_lines("User-agent: ExampleBot/1.0", "Disallow: /"),
    dv_lines("User-agent: Example Bot", "Disallow: /"),
    dv_lines("User-agent: *", "Disallow: /",
             "Sitemap: https://example.com/sitemap.xml"),
    dv_lines("Host: example.com", "Crawl-delay: 10"),
    dv_lines("User-agent: * # Disallow: /", "Disallow: /q"),
    dv_lines("User-agent: *", "Disallow:", "Allow:")
  )) {
    expect_identical(nrow(dv_rows(robots_validate_text(body))), 0L,
                     label = body)
  }
})

test_that("the value is read as bytes, as Google's parser reads it", {
  # Invalid UTF-8 and Latin-1 before the key: still found, columns in bytes.
  for (byte in list(as.raw(0xe9), as.raw(c(0xc3, 0x28)))) {
    body <- c(charToRaw("User-agent: *\nDisallow: /caf"), byte,
              charToRaw(" Allow: /\n"))
    row <- dv_rows(robots_validate_text(body))
    expect_identical(row$line, 2L)
    expect_match(row$message, sprintf("at byte column %d.",
                                      16L + length(byte)), fixed = TRUE)
  }
  # A NUL before the key: Google never reads it.
  body <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0),
            charToRaw(" Allow: /\n"))
  expect_identical(nrow(dv_rows(robots_validate_text(body))), 0L)
  # Past the line buffer: Google never reads it.
  x <- dv_text("User-agent: *",
               paste0("Disallow: /", strrep("a", 16700L), " Allow: /"))
  expect_identical(nrow(dv_rows(x)), 0L)
  # CR-only line ends are Google's lines.
  x <- robots_validate_text(
    "User-agent: * Disallow: /x\rUser-agent: Foo\rDisallow: /\r"
  )
  expect_identical(dv_rows(x)$message,
                   paste0(dv_lead("Disallow:", 15L, "Disallow: /x"), dv_star,
                          dv_stack(2L, "line 3", dv_every), dv_others))
  # A BOM on line 1 counts in the column.
  body <- c(as.raw(c(0xef, 0xbb, 0xbf)),
            charToRaw("User-agent: * Disallow: /x\n"))
  expect_match(dv_rows(robots_validate_text(body))$message,
               "at byte column 18.", fixed = TRUE)
  # Leading blanks and a blank before the line's own colon.
  x <- dv_text("User-agent: *", "  Disallow : /x Allow: /y")
  expect_match(dv_rows(x)$message, "`Allow:` at byte column 17.",
               fixed = TRUE)
})

test_that("several keys: the first is named, the rest counted", {
  x <- dv_text("User-agent: *", "Disallow: /k Allow: /l Disallow: /m Host: n")
  expect_identical(
    dv_rows(x)$message,
    paste0(dv_lead("Allow:", 14L, "Allow: /l Disallow: /m Host: n"),
           " The value holds 2 more directive keys after it.",
           dv_path("/k Allow: /l Disallow: /m Host: n"), dv_others)
  )
  x <- dv_text("User-agent: *", "Disallow: /k Allow: /l Host: n")
  expect_match(dv_rows(x)$message,
               " The value holds 1 more directive key after it.",
               fixed = TRUE)
})

test_that("a backtick is escaped and a long value cut", {
  x <- dv_text("User-agent: *", "Disallow: /a`b Allow: /`c")
  expect_identical(dv_rows(x)$message,
                   paste0(dv_lead("Allow:", 16L, "Allow: /\\x60c"),
                          dv_path("/a\\x60b Allow: /\\x60c"), dv_others))
  long <- strrep("b", 100L)
  x <- dv_text("User-agent: *", sprintf("Disallow: /x Allow: /%s", long))
  expect_match(dv_rows(x)$message,
               paste0("apply `Allow: /", strrep("b", 52L), "...`."),
               fixed = TRUE)
})

# Upper-case keys holding `I`, which a Turkish locale would not fold to `i`.
dv_upper <- dv_lines("User-agent: *", "Disallow: /a DISALLOW: /b",
                     "Disallow: /c SITEMAP: /d",
                     "Disallow: /e CRAWL-DELAY: 1",
                     "Disallow: /f USER-AGENT: x")

test_that("upper-case keys fold byte by byte", {
  expect_identical(dv_rows(robots_validate_text(dv_upper))$line, 2:5)
})

# The suite's locale legs run every test under these LC_CTYPEs too; this
# test also sets them where the platform has them.
for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("upper-case keys fold the same under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    expect_identical(dv_rows(robots_validate_text(dv_upper))$line, 2:5)
  })
}

test_that("a body over 512,000 bytes leaves out the effect after the line", {
  body <- paste0("User-agent: * Disallow: /x\n",
                 strrep("# filler\n", 57000L), "User-agent: Foo\n",
                 "Disallow: /\n")
  expect_gt(nchar(body, "bytes"), 512000L)
  expect_identical(
    dv_rows(robots_validate_text(body))$message,
    paste0(dv_lead("Disallow:", 15L, "Disallow: /x"), dv_star,
           " The file is over 512,000 bytes, past what Google reads, so ",
           "what the line does to the lines after it is not stated.",
           dv_others)
  )
})

test_that("a cut body says lines past the cut were not read", {
  bytes <- charToRaw(dv_ex1)
  x <- validate_document_bytes(bytes, "supplied", "text",
                               body_truncated = TRUE)
  row <- x$diagnostics[x$diagnostics$code == "directive_in_value", ]
  expect_match(row$message, paste0(" The body was cut, and lines past the ",
                                   "cut were not read.", dv_others, "$"))
})

# Best of five; bodies with a hidden key against the same bodies with a key
# that is none, so only the row's own cost is compared. The limits are over
# twice today's ratios (about 1.5 stacked and 1.3 for rules).
dv_time <- function(body) {
  min(vapply(1:5, function(i) {
    system.time(robots_validate_text(body))[["elapsed"]]
  }, 0))
}

# The messages of `hidden` hidden User-agent lines stacked above one run of
# `rules` rules, timed on their own, best of five: each names the same run,
# so its cost must not grow with the run.
dv_time_messages <- function(rules, hidden = 2000L) {
  bytes <- charToRaw(paste0(
    strrep("User-agent: x Disallow: /y\n", hidden),
    paste0("Disallow: /p", seq_len(rules), "\n", collapse = "")
  ))
  parsed <- as.data.frame(robotstxtr_validation_parse_(bytes),
                          stringsAsFactors = FALSE)
  raw_lines <- split_validation_lines(bytes)
  groups <- validation_groups(parsed, raw_lines)
  found <- directive_in_value_rows(parsed, raw_lines)
  groups$agents$hidden <- groups$agents$line %in% found$line
  min(vapply(1:5, function(k) {
    system.time(
      directive_in_value_messages(found, groups, FALSE, integer(), FALSE,
                                  FALSE)
    )[["elapsed"]]
  }, 0))
}

test_that("the row stays linear (ROBO-dbvmxcfw)", {
  skip_on_cran()
  # Stacked hidden User-agent lines, all one group on Google.
  stacked <- function(key) {
    paste0(paste0("User-agent: a", 1:6000, " ", key, ": /x\n",
                  collapse = ""), "Disallow: /\n")
  }
  expect_lt(dv_time(stacked("Disallow")),
            3.25 * max(dv_time(stacked("Dxsallow")), 0.05))
  # One group of rules each hiding a key.
  rules <- function(key) {
    paste0("User-agent: *\n", paste0("Disallow: /p", 1:6000, " ", key,
                                     ": /q\n", collapse = ""))
  }
  expect_lt(dv_time(rules("Allow")),
            2.75 * max(dv_time(rules("Alxow")), 0.05))
  # Many hidden lines above one long run of rules: 32 times the rules,
  # about the same time.
  expect_lt(dv_time_messages(16000L),
            2.5 * max(dv_time_messages(500L), 0.05))
})
