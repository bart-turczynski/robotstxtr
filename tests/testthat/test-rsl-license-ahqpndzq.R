# ROBO-ahqpndzq: a `License:` line is the License directive of Really Simple
# Licensing (RSL 1.0 section 4.4). The validator gives it its own code,
# rsl_license_directive: info when the value is an absolute URI, warning
# when not, and the message states the line's scope under RSL (global before
# the first User-agent line, else the group it sits in). It counts as a known,
# unsupported directive. The dated adoption record is
# design/engine-profiles.md section 7b. All fixtures are synthetic.
#
# Symmetry: no matcher reads the line (Google, Bing and Yandex ignore unknown
# fields), so no per-engine decision exists to test; Bing's group end at an
# unknown field is user_agent_joined_across_directive's, pinned below.

rsl_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

rsl_diag <- function(body) robots_validate_text(body)$diagnostics

rsl_rows <- function(body) {
  d <- rsl_diag(body)
  d[d$code == "rsl_license_directive", , drop = FALSE]
}

rsl_valid_lead <- paste0(
  "License is the RSL 1.0 section 4.4 directive that points to licensing ",
  "terms."
)
rsl_common <- paste0(
  "It changes no crawl access, which Allow and Disallow alone decide, and no ",
  "crawler operator is documented as reading it."
)
rsl_no_global <- paste0(
  "Crawlers outside that group find no License in this file unless their ",
  "own group has one; a License line before the first User-agent line ",
  "applies to every crawler."
)
rsl_has_global <- paste0(
  "For them it replaces the License lines before the first User-agent line."
)
rsl_global <- paste0(
  "Before the first User-agent line, it applies to every crawler under RSL"
)

test_that("a License line gets its own info, counted as unsupported", {
  x <- robots_validate_text(rsl_lines(
    "User-agent: *", "Disallow: /private",
    "License: https://example.com/license.xml"
  ))
  d <- x$diagnostics
  expect_identical(d$code, "rsl_license_directive")
  expect_identical(d$severity, "info")
  expect_identical(d$line, 3L)
  expect_identical(d$directive, "license")
  expect_identical(d$message, paste(
    rsl_valid_lead, rsl_common,
    paste0("Under RSL it applies only to the crawlers that select the group ",
           "on line 1 (*)."),
    rsl_no_global
  ))
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$documents$unknown_directives, 0L)
  expect_identical(x$documents$unsupported_directives, 1L)
  expect_identical(x$documents$recognized_directives, 3L)
})

test_that("the message never calls the placement an error", {
  m <- rsl_rows(rsl_lines("User-agent: a-bot", "Disallow: /",
                          "License: https://example.com/l.xml"))$message
  expect_no_match(m, "error|mistake|wrong|invalid", ignore.case = TRUE)
  expect_match(m, "RSL 1.0 section 4.4", fixed = TRUE)
  expect_match(m, "changes no crawl access", fixed = TRUE)
  expect_match(m, "no crawler operator is documented", fixed = TRUE)
})

test_that("a License line before the first User-agent line is global", {
  d <- rsl_rows(rsl_lines(
    "License: https://example.com/l.xml", "", "User-agent: *",
    "Disallow: /private"
  ))
  expect_identical(d$line, 1L)
  expect_identical(d$severity, "info")
  expect_identical(d$message,
                   paste(rsl_valid_lead, rsl_common, paste0(rsl_global, ".")))
})

test_that("a group-scoped License names the group, mid-group and after it", {
  scope <- function(line, agents) {
    sprintf(paste0("Under RSL it applies only to the crawlers that select ",
                   "the group on line %d (%s)."), line, agents)
  }
  # Mid-group, between two rules.
  mid <- rsl_rows(rsl_lines(
    "User-agent: a-bot", "Disallow: /a", "License: https://example.com/l.xml",
    "Disallow: /b"
  ))
  expect_match(mid$message, scope(1L, "a-bot"), fixed = TRUE)
  expect_match(mid$message, rsl_no_global, fixed = TRUE)
  # After the last rule, with and without a blank line, before another group.
  for (gap in list(character(), "")) {
    d <- rsl_rows(rsl_lines(
      "User-agent: a-bot", "Disallow: /a", gap,
      "License: https://example.com/l.xml", "User-agent: *", "Disallow: /b"
    ))
    expect_match(d$message, scope(1L, "a-bot"), fixed = TRUE,
                 info = length(gap))
  }
  # At the end of the file, after a blank line: the last group's.
  d <- rsl_rows(rsl_lines(
    "User-agent: *", "Disallow: /b", "User-agent: a-bot", "Disallow: /",
    "", "License: https://example.com/l.xml"
  ))
  expect_match(d$message, scope(3L, "a-bot"), fixed = TRUE)
  # A group with no Allow or Disallow.
  d <- rsl_rows(rsl_lines(
    "User-agent: a-bot", "License: https://example.com/l.xml"
  ))
  expect_match(d$message, scope(1L, "a-bot"), fixed = TRUE)
})

test_that("between stacked User-agent lines it scopes the joined group", {
  body <- rsl_lines(
    "User-agent: a-bot", "License: https://example.com/l.xml",
    "User-agent: b-bot", "Disallow: /"
  )
  d <- rsl_diag(body)
  expect_identical(d$code, c("rsl_license_directive",
                             "user_agent_joined_across_directive"))
  # The License line joins the stacked lines, as any unknown field does.
  expect_identical(d$line, 2:3)
  expect_identical(d$severity, c("info", "warning"))
  expect_match(d$message[[1L]], "the group on line 1 (a-bot and b-bot)",
               fixed = TRUE)
})

test_that("the agent list is bounded at five", {
  agents <- sprintf("User-agent: bot-%s", letters[1:7])
  d <- rsl_rows(rsl_lines(agents, "Disallow: /",
                          "License: https://example.com/l.xml"))
  expect_match(d$message,
               "(bot-a, bot-b, bot-c, bot-d, bot-e and 2 more)", fixed = TRUE)
})

test_that("global and group-local lines: local replaces, global falls back", {
  d <- rsl_rows(rsl_lines(
    "License: https://example.com/all.xml", "User-agent: *", "Disallow: /x",
    "User-agent: a-bot", "Disallow: /", "License: https://example.com/a.xml",
    "User-agent: b-bot", "License: https://example.com/b.xml"
  ))
  expect_identical(d$line, c(1L, 6L, 8L))
  expect_identical(d$message[[1L]], paste(
    rsl_valid_lead, rsl_common,
    paste0(rsl_global, ", except one that selects a group with its own ",
           "License line (the groups on lines 4 and 7).")
  ))
  expect_match(d$message[[2L]], rsl_has_global, fixed = TRUE)
  expect_no_match(d$message[[2L]], "find no License", fixed = TRUE)
  expect_match(d$message[[3L]], "the group on line 7 (b-bot)", fixed = TRUE)
  # One group of its own: singular.
  one <- rsl_rows(rsl_lines(
    "License: https://example.com/all.xml", "User-agent: a-bot",
    "License: https://example.com/a.xml"
  ))
  expect_match(one$message[[1L]], "License line (the group on line 2).",
               fixed = TRUE)
})

test_that("empty User-agent lines are left out of the agent list", {
  d <- rsl_rows(rsl_lines("User-agent: a-bot", "User-agent:", "Disallow: /",
                          "License: https://example.com/l.xml"))
  expect_match(d$message, "the group on line 1 (a-bot).", fixed = TRUE)
})

test_that("a group of only empty User-agent lines reaches no crawler", {
  d <- rsl_rows(rsl_lines("User-agent:", "License: https://example.com/l.xml",
                          "Disallow: /"))
  expect_identical(d$severity, "info")
  expect_identical(d$message, paste(
    rsl_valid_lead, rsl_common,
    paste0("It sits in the group on line 1, whose User-agent lines are all ",
           "empty, so no crawler selects that group and the line reaches ",
           "none.")
  ))
})

test_that("a long agent name is shortened as other codes shorten it", {
  name <- paste0("bot-", strrep("a", 70L))
  d <- rsl_rows(rsl_lines(paste("User-agent:", name), "Disallow: /",
                          "License: https://example.com/l.xml"))
  expect_match(d$message, sprintf("the group on line 1 (%s...).",
                                  substr(name, 1L, 60L)), fixed = TRUE)
})

test_that("several values and mixed valid and invalid lines", {
  d <- rsl_rows(rsl_lines(
    "User-agent: a-bot", "Disallow: /",
    "License: https://example.com/one.xml", "License: /two.xml",
    "License: urn:example:three"
  ))
  expect_identical(d$line, 3:5)
  expect_identical(d$severity, c("info", "warning", "info"))
})

test_that("a synthetic trailing-License shape scopes to the final group", {
  # Shape only (corpus privacy, ROBO-qbxsydcf): a `*` group, then stacked
  # AI crawlers blocked with Disallow: /, a blank line and a trailing
  # License line. RSL's example 2 places a group's License after its rules;
  # the blank line before it ends no group under RFC 9309.
  body <- rsl_lines(
    "# Licensing terms for model training: see below.",
    "User-agent: *", "Disallow: /search", "",
    "User-agent: example-ai-one", "User-agent: example-ai-two",
    "User-agent: example-ai-three", "Disallow: /", "",
    "License: https://example.com/license.xml"
  )
  x <- robots_validate_text(body)
  d <- x$diagnostics
  expect_false("unknown_directive" %in% d$code)
  r <- d[d$code == "rsl_license_directive", , drop = FALSE]
  expect_identical(r$line, 10L)
  expect_identical(r$severity, "info")
  expect_match(r$message, paste0(
    "the group on line 5 (example-ai-one, example-ai-two and ",
    "example-ai-three)."
  ), fixed = TRUE)
  expect_match(r$message, rsl_no_global, fixed = TRUE)
  # A Sitemap between the rules and the License does not make it global.
  body2 <- rsl_lines(
    "User-agent: *", "Disallow: /search", "User-agent: example-ai-one",
    "Disallow: /", "Sitemap: https://example.com/sitemap.xml",
    "License: https://example.com/license.xml"
  )
  expect_match(rsl_rows(body2)$message, "the group on line 3", fixed = TRUE)
})

test_that("the value must be an absolute URI", {
  cases <- c(
    "/license.xml" = "warning", "urn:example:license" = "info",
    "https://example.com/%zz" = "warning",
    "https://example.com/a b" = "warning",
    "https://example.com/%2Fok" = "info", "https://example.com/a%2" = "warning",
    "1http://example.com/" = "warning", "license.xml" = "warning",
    "mailto:rights@example.com" = "info",
    "https://example.com/l.xml?v=1&x=[2]" = "info"
  )
  for (value in names(cases)) {
    d <- rsl_rows(rsl_lines("User-agent: *", paste("License:", value)))
    expect_identical(d$severity, cases[[value]], info = value)
  }
  bad <- rsl_rows(rsl_lines("User-agent: *", "License: /license.xml"))
  expect_match(bad$message, paste0(
    "^License value is not an absolute URI, which RSL 1.0 section 4.4 ",
    "requires"
  ))
  expect_match(bad$message, rsl_common, fixed = TRUE)
})

test_that("a # starts a comment, so the checked value has no fragment", {
  d <- rsl_rows(rsl_lines("User-agent: *",
                          "License: https://example.com/l.xml#frag"))
  expect_identical(d$severity, "info")
  # The text after `#` is not checked: a space there changes nothing.
  d <- rsl_rows(rsl_lines("User-agent: *",
                          "License: https://example.com/l.xml#a b"))
  expect_identical(d$severity, "info")
})

test_that("an empty value is a warning", {
  d <- rsl_rows(rsl_lines("User-agent: *", "License:"))
  expect_identical(d$severity, "warning")
  expect_match(d$message, paste0("^License value is empty; RSL 1.0 section ",
                                 "4.4 requires an absolute URI."))
})

test_that("the key is matched without regard to ASCII case", {
  for (key in c("license", "LICENSE", "License", "liCense")) {
    d <- rsl_rows(rsl_lines("User-agent: *",
                            paste0(key, ": https://example.com/l.xml")))
    expect_identical(d$line, 2L, info = key)
    expect_identical(d$directive, "license", info = key)
  }
})

test_that("a missing colon with a colon-free value is still a License line", {
  d <- rsl_diag(rsl_lines("User-agent: *", "License /license.xml"))
  expect_identical(d$code[which(d$line == 2L)],
                   c("accepted_missing_colon", "rsl_license_directive"))
  expect_identical(d$severity[d$code == "rsl_license_directive"], "warning")
})

test_that("invalid UTF-8 in the value is a warning and keeps invalid_utf8", {
  body <- c(charToRaw("User-agent: *\nLicense: https://example.com/l"),
            as.raw(0xe9), charToRaw(".xml\n"))
  d <- rsl_diag(body)
  expect_true("invalid_utf8" %in% d$code)
  expect_identical(d$severity[d$code == "rsl_license_directive"], "warning")
})

test_that("a non-ASCII value is a warning though the parser %-escapes it", {
  # The parser hands R `%C3%A9` for the written bytes, so the check reads the
  # raw line; the same escape written in the file is a URI.
  utf8 <- rsl_rows(rsl_lines("User-agent: *",
                             "License: https://example.com/é.xml"))
  expect_identical(utf8$severity, "warning")
  escaped <- rsl_rows(rsl_lines("User-agent: *",
                                "License: https://example.com/%C3%A9.xml"))
  expect_identical(escaped$severity, "info")
  # A non-ASCII byte in a comment after the value changes nothing.
  comment <- rsl_rows(rsl_lines("User-agent: *",
                                "License: https://example.com/l # é"))
  expect_identical(comment$severity, "info")
})

test_that("a NUL in the value checks the prefix Google reads", {
  # Google's reading ends the line at the NUL, so `https://example.com/l`
  # is the value checked; the bytes after it are not.
  body <- c(charToRaw("User-agent: *\nLicense: https://example.com/l"),
            as.raw(0), charToRaw("a b\n"))
  d <- rsl_diag(body)
  expect_true("nul_byte" %in% d$code)
  expect_identical(d$severity[d$code == "rsl_license_directive"], "info")
})

test_that("a License line on line 1 after a byte-order mark is recognized", {
  body <- c(as.raw(c(0xef, 0xbb, 0xbf)),
            charToRaw("License: https://example.com/l.xml\nUser-agent: *\n"))
  d <- rsl_diag(body)
  expect_identical(d$code[which(d$line == 1L)],
                   c("byte_order_mark", "rsl_license_directive"))
  expect_match(d$message[d$code == "rsl_license_directive"], rsl_global,
               fixed = TRUE)
  # The BOM is no byte of the value: the line is info.
  expect_identical(d$severity[d$code == "rsl_license_directive"], "info")
})

test_that("a partial byte-order mark on line 1 is skipped as the parser does", {
  for (prefix in list(as.raw(0xef), as.raw(c(0xef, 0xbb)))) {
    body <- c(prefix, charToRaw(
      "License: https://example.com/l.xml\nUser-agent: *\n"
    ))
    d <- rsl_rows(body)
    expect_identical(d$line, 1L, info = length(prefix))
    expect_identical(d$severity, "info", info = length(prefix))
  }
})

test_that("bytes after a NUL are not read for the non-ASCII check", {
  body <- c(charToRaw("User-agent: *\nLicense: https://example.com/l"),
            as.raw(c(0x00, 0xc3, 0xa9)), charToRaw("\n"))
  d <- rsl_diag(body)
  expect_true("nul_byte" %in% d$code)
  expect_identical(d$severity[d$code == "rsl_license_directive"], "info")
})

test_that("bytes past the parser's line buffer are not read", {
  # The parser keeps the first validation_line_bytes bytes of a line, so a
  # non-ASCII byte after them is in no value it reads.
  head <- "License: https://example.com/"
  fill <- strrep("a", validation_line_bytes - nchar(head))
  body <- c(charToRaw(paste0("User-agent: *\n", head, fill)),
            as.raw(c(0xc3, 0xa9)), charToRaw("\n"))
  d <- rsl_diag(body)
  expect_true("line_too_long" %in% d$code)
  expect_identical(d$severity[d$code == "rsl_license_directive"], "info")
  # One byte shorter, the non-ASCII byte is inside the buffer.
  body <- c(charToRaw(paste0("User-agent: *\n", head, substring(fill, 2L))),
            as.raw(c(0xc3, 0xa9)), charToRaw("\n"))
  expect_identical(rsl_rows(body)$severity, "warning")
})

test_that("a line-1 byte-order mark, whole or partial, is not in the buffer", {
  # The parser skips the mark before it counts the line buffer, so a
  # non-ASCII byte right at its end is still read after a mark on line 1.
  head <- "License: https://example.com/"
  fill <- strrep("a", validation_line_bytes - nchar(head) - 1L)
  for (prefix in list(validation_bom, as.raw(c(0xef, 0xbb)))) {
    body <- c(prefix, charToRaw(paste0(head, fill)), as.raw(c(0xc3, 0xa9)),
              charToRaw("\nUser-agent: *\n"))
    d <- rsl_rows(body)
    expect_identical(d$line, 1L, info = length(prefix))
    expect_identical(d$severity, "warning", info = length(prefix))
  }
})

test_that("a key that only contains license is not matched", {
  d <- rsl_diag(rsl_lines("User-agent: *", "License-URL: https://example.com/l",
                          "Licenses: https://example.com/l",
                          "Disallow: /private"))
  expect_identical(d$code, c("unknown_directive", "unknown_directive"))
})

test_that("the License line does not change the google decision", {
  with <- rsl_lines("User-agent: *", "License: https://example.com/l.xml",
                    "Disallow: /private")
  without <- rsl_lines("User-agent: *", "Disallow: /private")
  url <- "https://example.com/private/a"
  a <- allowed_by_robots_text(with, url, "Googlebot")$results
  b <- allowed_by_robots_text(without, url, "Googlebot")$results
  expect_false(a$allowed)
  expect_identical(a$allowed, b$allowed)
  expect_identical(a$decision_source, b$decision_source)
})

test_that("X-RSL is an unknown directive and draws no License code", {
  x <- robots_validate_text(rsl_lines(
    "User-agent: *", "Disallow: /private", "X-RSL: https://example.com/l.xml"
  ))
  d <- x$diagnostics
  expect_identical(d$code, "unknown_directive")
  expect_identical(d$directive, "x-rsl")
  expect_identical(x$documents$unknown_directives, 1L)
})

test_that("Content-Signal and an unknown key keep their codes", {
  d <- rsl_diag(rsl_lines(
    "User-agent: *", "Content-Signal: ai-train=no", "Foo: bar",
    "Disallow: /private"
  ))
  expect_identical(d$code, c("content_signal_directive", "unknown_directive"))
  expect_identical(d$directive, c("content-signal", "foo"))
})

test_that("a License line in a training-preference group still warns", {
  d <- rsl_diag(rsl_lines(
    "User-agent: __usage_ai-training", "Disallow: /",
    "License: https://example.com/l.xml"
  ))
  extra <- d[d$code == "ai_training_group_extra_line", , drop = FALSE]
  expect_identical(extra$line, 3L)
})

test_that("License then a space and a URL is cut at the URL's colon", {
  # The parser's separator is the first colon, here the scheme's, so the key
  # is `License https` and no missing colon is reported: not a License line.
  d <- rsl_diag(rsl_lines("User-agent: *", "Disallow: /",
                          "License https://example.com/l.xml"))
  expect_identical(d$code, "unknown_directive")
  expect_identical(d$directive, "license https")
})

test_that("a bytes-encoded key is not read as License", {
  body <- c(charToRaw("Lic"), as.raw(0xe9),
            charToRaw("nse: https://example.com/l.xml\n"))
  d <- rsl_diag(body)
  expect_identical(d$code[which(d$line == 1L)],
                   c("invalid_utf8", "unknown_directive"))
  expect_identical(d$directive[d$code == "unknown_directive"], "unknown")
})
