# ROBO-wnuttuit: a User-agent line that repeats a name already in its own
# group, in any case, draws one info row (RFC 9309 section 2.2.1). Google reads
# the same group with or without it. Where Bing or Yandex ends the group
# between the two lines, the message says which engine and does not offer
# deletion. The bodies are synthetic.

dg_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

# The codes the validator gives the lines in `line`.
dg_codes <- function(body, line) {
  d <- robots_validate_text(body)$diagnostics
  d$code[d$line %in% line]
}

# The rows of one code.
dg_rows <- function(body, code) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == code, , drop = FALSE]
}

test_that("a case-only repeat in one group draws one info row", {
  body <- dg_lines("User-agent: Acme-Bot", "User-agent: acme-bot",
                   "Disallow: /a")
  r <- dg_rows(body, "user_agent_duplicate_in_group")
  expect_identical(r$line, 2L)
  expect_identical(r$severity, "info")
  expect_identical(r$directive, "user-agent")
  expect_identical(r$raw_text, "User-agent: acme-bot")
  expect_identical(r$message, paste0(
    "`User-agent: acme-bot` (line 2) repeats `User-agent: Acme-Bot` (line 1) ",
    "in the same group. Product tokens match case-insensitively (RFC 9309 ",
    "section 2.2.1), so the group names the same crawler with or without ",
    "this line, and the line can be deleted."
  ))
})

test_that("an exact repeat in one group draws one info row", {
  body <- dg_lines("User-agent: Acme-Bot", "User-agent: Acme-Bot",
                   "Disallow: /a")
  expect_identical(dg_rows(body, "user_agent_duplicate_in_group")$line, 2L)
})

test_that("a `*` repeated in one group draws one info row", {
  body <- dg_lines("User-agent: *", "User-agent: *", "Disallow: /a")
  r <- dg_rows(body, "user_agent_duplicate_in_group")
  expect_identical(r$line, 2L)
  expect_match(r$message, paste0(
    "`User-agent: *` (line 2) repeats `User-agent: *` (line 1) in the same"
  ), fixed = TRUE)
})

test_that("three case pairs in one group draw three rows", {
  body <- dg_lines("User-agent: Alpha", "User-agent: alpha",
                   "User-agent: Beta", "User-agent: beta",
                   "User-agent: Gamma", "User-agent: gamma",
                   "Disallow: /a")
  r <- dg_rows(body, "user_agent_duplicate_in_group")
  expect_identical(r$line, c(2L, 4L, 6L))
})

test_that("a policy-token repeat draws only its preference row", {
  body <- dg_lines("User-agent: __usage_ai-training",
                   "User-agent: __usage_ai-training", "Disallow: /a")
  expect_identical(dg_codes(body, 2L), character())
  expect_identical(dg_codes(body, 1L), "ai_training_preference")
})

test_that("a cut value beside its token draws no repeat row", {
  body <- dg_lines("User-agent: Foo Bot", "User-agent: foo", "Disallow: /a")
  expect_identical(dg_codes(body, 2L), character())
  expect_identical(dg_codes(body, 1L), "user_agent_cut")
})

test_that("a repeat of a cut line draws only the cut row", {
  body <- dg_lines("User-agent: Foo Bot", "User-agent: foo bot",
                   "Disallow: /a")
  expect_identical(dg_codes(body, 2L), "user_agent_cut")
})

test_that("a case pair split into two groups draws the group row only", {
  body <- dg_lines("User-agent: Acme-Bot", "Disallow: /a", "",
                   "User-agent: acme-bot", "Disallow: /b")
  expect_identical(dg_codes(body, 4L), "user_agent_repeated_group")
})

test_that("a repeat a join owns draws the join row only", {
  body <- dg_lines("User-agent: Foo", "Sitemap: https://example.com/s.xml",
                   "User-agent: Bar", "Crawl-delay: 1", "User-agent: foo",
                   "Disallow: /a")
  expect_identical(dg_codes(body, 5L), "user_agent_joined_across_directive")
})

test_that("a repeat in one group and in an earlier one draws both rows", {
  # Line 5 starts the second group's FooBot, which the first group named:
  # the group row. Line 6 repeats line 5 inside that group: the new row.
  body <- dg_lines("User-agent: FooBot", "Disallow: /a", "",
                   "User-agent: Bar", "User-agent: foobot",
                   "User-agent: FOOBOT", "Disallow: /b")
  expect_identical(dg_codes(body, 5L), "user_agent_repeated_group")
  expect_identical(dg_codes(body, 6L), "user_agent_duplicate_in_group")
  r <- dg_rows(body, "user_agent_duplicate_in_group")
  expect_match(r$message, paste0(
    "`User-agent: FOOBOT` (line 6) repeats `User-agent: foobot` (line 5)"
  ), fixed = TRUE)
})

test_that("a repeat in a group with no rule draws nothing", {
  body <- dg_lines("User-agent: Acme-Bot", "User-agent: acme-bot")
  expect_identical(dg_codes(body, 2L), character())
})

test_that("invalid UTF-8 in a repeated cut value is read as bytes", {
  body <- c(charToRaw("User-agent: Foo"), as.raw(0xff),
            charToRaw(" Bot\nUser-agent: Foo"), as.raw(0xff),
            charToRaw(" Bot\nDisallow: /a\n"))
  expect_setequal(dg_codes(body, 2L), c("invalid_utf8", "user_agent_cut"))
})

# Validator only: no engine answer is involved, so no per-engine check.

test_that("a repeat across a blank line in the same group counts", {
  body <- dg_lines("User-agent: Acme-Bot", "", "User-agent: acme-bot",
                   "Disallow: /a")
  expect_identical(dg_codes(body, 3L), "user_agent_duplicate_in_group")
})

test_that("a repeat across a directive in the same group counts", {
  body <- dg_lines("User-agent: Acme-Bot", "Crawl-delay: 1",
                   "User-agent: acme-bot", "Disallow: /a")
  expect_identical(dg_codes(body, 3L), "user_agent_duplicate_in_group")
})

test_that("values that share only a cut key draw no repeat row", {
  body <- dg_lines("User-agent: Foo Bot", "User-agent: Foo Baz",
                   "Disallow: /a")
  expect_identical(dg_codes(body, 2L), "user_agent_cut")
})

test_that("a repeat on a NUL-bearing line carries Google's reading", {
  body <- c(charToRaw("User-agent: Acme-Bot\nUser-agent: acme-bot"),
            as.raw(0), charToRaw("x\nDisallow: /a\n"))
  r <- dg_rows(body, "user_agent_duplicate_in_group")
  expect_identical(r$line, 2L)
  expect_match(r$message, "This is Google's reading, which ends each line",
               fixed = TRUE)
})

test_that("an empty body draws no repeat row", {
  expect_false("user_agent_duplicate_in_group" %in%
                 robots_validate_text("")$diagnostics$code)
})

for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("a case-only repeat is found under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    body <- dg_lines("User-agent: ID-Bot", "User-agent: id-bot",
                     "Disallow: /a")
    expect_identical(dg_codes(body, 2L), "user_agent_duplicate_in_group")
  })
}

test_that("a group of 5,000 repeats of one name draws 4,999 rows", {
  body <- dg_lines(c(rep("User-agent: Acme-Bot", 5000L), "Disallow: /a"))
  r <- dg_rows(body, "user_agent_duplicate_in_group")
  expect_identical(nrow(r), 4999L)
  expect_identical(r$line[[1L]], 2L)
})

# The message of a repeat that a blank line separates from its first name
# (line 3 repeats line 1, line 2 is blank). A comment line draws the same.
dg_yandex_blank <- paste0(
  "`User-agent: acme-bot` (line 3) repeats `User-agent: Acme-Bot` ",
  "(line 1) in the same group. Product tokens match case-insensitively ",
  "(RFC 9309 section 2.2.1), so Google reads one group with or without ",
  "this line. Yandex ends a group at every blank or comment line, as at ",
  "line 2, so deleting this line would take the rules below it from that ",
  "crawler on Yandex."
)

test_that("a repeat across a blank line names Yandex and advises no deletion", {
  body <- dg_lines("User-agent: Acme-Bot", "", "User-agent: acme-bot",
                   "Disallow: /a")
  expect_identical(dg_rows(body, "user_agent_duplicate_in_group")$message,
                   dg_yandex_blank)
})

test_that("a repeat across a comment line draws the same Yandex message", {
  body <- dg_lines("User-agent: Acme-Bot", "# note", "User-agent: acme-bot",
                   "Disallow: /a")
  expect_identical(dg_rows(body, "user_agent_duplicate_in_group")$message,
                   dg_yandex_blank)
})

test_that("a repeat across a Crawl-delay names Bing and Yandex", {
  body <- dg_lines("User-agent: Acme-Bot", "Crawl-delay: 1",
                   "User-agent: acme-bot", "Disallow: /a")
  expect_identical(
    dg_rows(body, "user_agent_duplicate_in_group")$message,
    paste0(
      "`User-agent: acme-bot` (line 3) repeats `User-agent: Acme-Bot` ",
      "(line 1) in the same group. Product tokens match case-insensitively ",
      "(RFC 9309 section 2.2.1), so Google reads one group with or without ",
      "this line. Bing and Yandex end the group at line 2, so deleting this ",
      "line would take the rules below it from that crawler on Bing and ",
      "Yandex."
    )
  )
})

test_that("a repeat across another directive names Bing only", {
  body <- dg_lines("User-agent: Acme-Bot",
                   "Sitemap: https://example.com/s.xml",
                   "User-agent: acme-bot", "Disallow: /a")
  expect_identical(
    dg_rows(body, "user_agent_duplicate_in_group")$message,
    paste0(
      "`User-agent: acme-bot` (line 3) repeats `User-agent: Acme-Bot` ",
      "(line 1) in the same group. Product tokens match case-insensitively ",
      "(RFC 9309 section 2.2.1), so Google reads one group with or without ",
      "this line. Bing ends the group at line 2, so deleting this line would ",
      "take the rules below it from that crawler on Bing."
    )
  )
})

test_that("a blank then a Crawl-delay names both engines' first breaks", {
  body <- dg_lines("User-agent: Acme-Bot", "", "Crawl-delay: 1",
                   "User-agent: acme-bot", "Disallow: /a")
  expect_identical(
    dg_rows(body, "user_agent_duplicate_in_group")$message,
    paste0(
      "`User-agent: acme-bot` (line 4) repeats `User-agent: Acme-Bot` ",
      "(line 1) in the same group. Product tokens match case-insensitively ",
      "(RFC 9309 section 2.2.1), so Google reads one group with or without ",
      "this line. Bing ends the group at line 3, and Yandex ends it at line ",
      "2, so deleting this line would take the rules below it from that ",
      "crawler on Bing and Yandex."
    )
  )
})

test_that("a `*` repeat across a Crawl-delay names every crawler it covers", {
  body <- dg_lines("User-agent: *", "Crawl-delay: 1", "User-agent: *",
                   "Disallow: /a")
  expect_identical(
    dg_rows(body, "user_agent_duplicate_in_group")$message,
    paste0(
      "`User-agent: *` (line 3) repeats `User-agent: *` (line 1) in the ",
      "same group. Product tokens match case-insensitively (RFC 9309 section ",
      "2.2.1), so Google reads one group with or without this line. Bing and ",
      "Yandex end the group at line 2, so deleting this line would take the ",
      "rules below it from every crawler without a group of its own on Bing ",
      "and Yandex."
    )
  )
})

test_that("a `*` line with trailing text is quoted as written", {
  body <- dg_lines("User-agent: *", "User-agent: * foo", "Disallow: /a")
  expect_identical(
    dg_rows(body, "user_agent_duplicate_in_group")$message,
    paste0(
      "`User-agent: * foo` (line 2) repeats `User-agent: *` (line 1) in the ",
      "same group. Product tokens match case-insensitively (RFC 9309 section ",
      "2.2.1), so the group names the same crawler with or without this ",
      "line, and the line can be deleted."
    )
  )
})

test_that("a long name is elided in the message", {
  early <- paste0("Q", strrep("abc", 24L))
  late <- ascii_lower(early)
  body <- dg_lines(paste0("User-agent: ", early), paste0("User-agent: ", late),
                   "Disallow: /a")
  m <- dg_rows(body, "user_agent_duplicate_in_group")$message
  expect_match(m, paste0(
    "`User-agent: ", substr(late, 1L, 60L), "...` (line 2) repeats ",
    "`User-agent: ", substr(early, 1L, 60L), "...` (line 1)"
  ), fixed = TRUE)
  expect_false(grepl(late, m, fixed = TRUE))
})

test_that("bare User-agent lines, which name no crawler, repeat nothing", {
  body <- dg_lines("User-agent:", "User-agent:", "User-agent: Acme-Bot",
                   "Disallow: /a")
  expect_false("user_agent_duplicate_in_group" %in% dg_codes(body, 2L))
})

test_that("a single User-agent line draws no repeat row", {
  body <- dg_lines("User-agent: Acme-Bot", "Disallow: /a")
  expect_false("user_agent_duplicate_in_group" %in%
                 robots_validate_text(body)$diagnostics$code)
})
