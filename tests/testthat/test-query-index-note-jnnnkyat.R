# ROBO-jnnnkyat: a Disallow whose pattern holds a query delimiter (`?`,
# `=` or `&`) may target URL parameters, and robots.txt controls crawling,
# not indexing (`rule_query_crawl_not_index`, info, one row per file).
# Every fixture is synthetic and minimal; the shop shapes mirror a public
# file's patterns without its host.

qi_diag <- function(body) {
  robots_validate_text(body)$diagnostics
}

qi_code <- "rule_query_crawl_not_index"

# Each fixture: a body, `today`, the codes it got before ROBO-jnnnkyat,
# and `note`, the lines the new row names (none: no row).
qi_fixtures <- list(
  # The shop shapes: a sort parameter, a parameter after a run of `*`, a
  # filter pair joined by `&`, a repeated parameter, and parameter-like
  # path text with no delimiter, which the check leaves alone.
  shop = list(
    body = paste0(
      "User-agent: *\nDisallow: /*?sort=\nDisallow: /*?*oseid=*\n",
      "Disallow: /collections/*filter*&*filter*\n",
      "Disallow: /*?*ls=*&ls=*\nDisallow: /collections/*sort_by*\n"
    ),
    today = "rule_query_parameter_position",
    note = 2:5
  ),
  no_delimiter = list(
    body = "User-agent: *\nDisallow: /collections/*sort_by*\n",
    today = character(),
    note = integer()
  ),
  allow_only = list(
    body = "User-agent: *\nAllow: /*?x=\n",
    today = "rule_query_parameter_position",
    note = integer()
  ),
  full_url = list(
    body = "User-agent: *\nDisallow: https://ex.example/*?a=\n",
    today = "rule_missing_leading_slash",
    note = integer()
  ),
  comment = list(
    body = "User-agent: *\nDisallow: /a#?b\n",
    today = "rule_cut_by_comment",
    note = integer()
  ),
  empty = list(
    body = "User-agent: *\nDisallow:\n",
    today = "allow_all_disallow",
    note = integer()
  ),
  tied = list(
    body = "User-agent: *\nDisallow: /*?x\nAllow: /*?x\n",
    today = "disallow_tied_by_allow",
    note = integer()
  ),
  ai_training = list(
    body = "User-agent: __usage_ai-training\nDisallow: /*?x=\n",
    today = c("ai_training_preference", "rule_query_parameter_position"),
    note = integer()
  ),
  before_agent = list(
    body = "Disallow: /*?x=\nUser-agent: *\nDisallow: /p\n",
    today = "rule_without_user_agent",
    note = integer()
  ),
  repeated = list(
    body = paste0(
      "User-agent: a\nDisallow: /*?s=\n\nUser-agent: b\nDisallow: /*?s=\n\n",
      "User-agent: a\nDisallow: /*?s=\n"
    ),
    # `a` and `b` share their rules too (ROBO-rdxgnqhw).
    today = c("user_agent_repeated_group", "user_agent_groups_same_rules",
              "duplicate_rule", rep("rule_query_parameter_position", 3L)),
    note = c(2L, 5L, 8L)
  ),
  seven = list(
    body = paste0("User-agent: *\n",
                  paste0("Disallow: /p", 1:7, "?a=\n", collapse = "")),
    today = rep("rule_query_parameter_position", 7L),
    note = 2:8
  ),
  coexist = list(
    body = "User-agent: *\nDisallow: /items/*?sort=\n",
    today = "rule_query_parameter_position",
    note = 2L
  ),
  # `=` alone and `&` alone each make a candidate.
  equals = list(
    body = "User-agent: *\nDisallow: /*sessionid=*\n",
    today = character(),
    note = 2L
  ),
  ampersand = list(
    body = "User-agent: *\nDisallow: /collections/*filter*&*filter*\n",
    today = character(),
    note = 2L
  ),
  # Tied for Foo only: `*` still reads the Disallow.
  partial_tie = list(
    body = paste0("User-agent: *\nDisallow: /*?x\n\nUser-agent: Foo\n",
                  "Disallow: /*?x\nAllow: /*?x\n"),
    today = c("allow_reopens_wildcard_disallow", "disallow_tied_by_allow"),
    note = 2L
  ),
  # The AI-training token beside a crawler: Foo reads the rule.
  ai_shared = list(
    body = paste0("User-agent: __usage_ai-training\nUser-agent: Foo\n",
                  "Disallow: /*?x=\n"),
    today = c("ai_training_preference", "rule_query_parameter_position"),
    note = 3L
  ),
  # A digit-led agent: Google reads no token, but Bing and Yandex compare
  # the whole value, so a crawler reads the rule.
  digit_led = list(
    body = "User-agent: 360Spider\nDisallow: /*?x=\n",
    today = c("user_agent_cut", "rule_query_parameter_position"),
    note = 2L
  ),
  # A lower-case-escape twin has its own row and is not named again.
  escape_twin = list(
    body = "User-agent: *\nDisallow: /p?q=%2B\nDisallow: /p?q=%2b\n",
    today = c("rule_lowercase_escape_twin", "rule_query_parameter_position"),
    note = 2L
  )
)

# The row's opening, as query_index_note_message() builds it.
qi_lead <- function(lines, first) {
  if (length(lines) == 1L) {
    return(sprintf("The Disallow on line %d ('%s') holds", lines, first))
  }
  shown <- utils::head(lines, 5L)
  listed <- toString(shown[-length(shown)])
  last <- shown[[length(shown)]]
  more <- length(lines) - length(shown)
  listed <- if (more > 0L) {
    sprintf("%s, %d and %d more", listed, last, more)
  } else {
    sprintf("%s and %d", listed, last)
  }
  sprintf("The Disallows on lines %s (the first '%s') hold", listed, first)
}

test_that("ROBO-jnnnkyat: every fixture gains the note or stays as it was", {
  for (name in names(qi_fixtures)) {
    fixture <- qi_fixtures[[name]]
    d <- qi_diag(fixture$body)
    want <- fixture$today
    if (length(fixture$note) > 0L) {
      want <- c(want, qi_code)
    }
    expect_identical(d$code, want, label = name)
  }
})

test_that("ROBO-jnnnkyat: one info row on the first line, naming each", {
  for (name in names(qi_fixtures)) {
    fixture <- qi_fixtures[[name]]
    if (length(fixture$note) == 0L) next
    d <- qi_diag(fixture$body)
    row <- d[d$code == qi_code, , drop = FALSE]
    expect_identical(nrow(row), 1L, label = name)
    expect_identical(row$line, fixture$note[[1L]], label = name)
    expect_identical(row$severity, "info", label = name)
    expect_identical(row$directive, "disallow", label = name)
    lines <- strsplit(fixture$body, "\n", fixed = TRUE)[[1L]]
    expect_identical(row$raw_text, lines[[fixture$note[[1L]]]], label = name)
    first <- sub("^Disallow: ", "", lines[[fixture$note[[1L]]]])
    expect_true(startsWith(row$message, qi_lead(fixture$note, first)),
                label = name)
  }
})

test_that("ROBO-jnnnkyat: five lines then a count", {
  msg <- qi_diag(qi_fixtures$seven$body)
  msg <- msg$message[msg$code == qi_code]
  expect_true(startsWith(
    msg, "The Disallows on lines 2, 3, 4, 5, 6 and 2 more (the first '/p1?a=')"
  ))
  expect_false(grepl("line 7|, 7|, 8", msg))
})

test_that("ROBO-jnnnkyat: the message is hedged and never misdirects", {
  msg <- qi_diag(qi_fixtures$shop$body)
  msg <- msg$message[msg$code == qi_code]
  expect_match(msg, "may target URL parameters", fixed = TRUE)
  expect_match(msg, "reads the pattern text only", fixed = TRUE)
  expect_match(msg, "robots.txt controls crawling, not indexing",
               fixed = TRUE)
  expect_match(msg, "Google's documentation says a blocked URL may still be",
               fixed = TRUE)
  expect_match(msg, "works only on a page the crawler may fetch",
               fixed = TRUE)
  expect_match(msg, "rel=canonical is a consolidation hint, not an exclusion",
               fixed = TRUE)
  expect_match(msg, "deliberate crawl control", fixed = TRUE)
  # No noindex line in robots.txt, no claim a URL is indexed or blocked
  # for sure, no call to unblock.
  expect_false(grepl("noindex[^.]*robots[.]txt", msg, ignore.case = TRUE))
  expect_false(grepl("Noindex:", msg, fixed = TRUE))
  expect_false(grepl("is indexed|are indexed|will be indexed", msg))
  expect_false(grepl("unblock|remove the|should", msg, ignore.case = TRUE))
  # One explanation, whatever the count.
  seven <- qi_diag(qi_fixtures$seven$body)
  seven <- seven$message[seven$code == qi_code]
  expect_identical(lengths(gregexpr("not indexing", seven, fixed = TRUE)),
                   1L)
})

test_that("ROBO-jnnnkyat: the note is info only", {
  for (name in names(qi_fixtures)) {
    fixture <- qi_fixtures[[name]]
    if (length(fixture$note) == 0L) next
    x <- robots_validate_text(fixture$body)
    others <- x$diagnostics[x$diagnostics$code != qi_code, , drop = FALSE]
    want <- if (any(others$severity == "error")) {
      "error"
    } else if (any(others$severity == "warning")) {
      "warning"
    } else {
      "valid"
    }
    expect_identical(x$documents$validation_status, want, label = name)
  }
  x <- robots_validate_text(qi_fixtures$shop$body)
  expect_identical(x$documents$validation_status, "valid")
})

test_that("ROBO-jnnnkyat: a cut body is checked, a NUL body is Google's", {
  text <- paste0("User-agent: *\nDisallow: /*?sort=\n",
                 "Allow: /later-", strrep("x", 200L), "\n")
  body <- charToRaw(text)[seq_len(40L)]
  x <- validate_document_bytes(body, "s", "supplied", max_bytes = 40L,
                               body_truncated = TRUE)
  d <- x$diagnostics
  expect_identical(d$line[d$code == qi_code], 2L)
  # On a cut body the note judges only the bytes read: an Allow that would
  # tie the Disallow, past the cut, is not seen, so the Disallow is named.
  text <- "User-agent: *\nDisallow: /a?b\nAllow: /a?b\n"
  expect_false(qi_code %in% qi_diag(text)$code)
  x <- validate_document_bytes(charToRaw(text)[seq_len(35L)], "s",
                               "supplied", max_bytes = 35L,
                               body_truncated = TRUE)
  d <- x$diagnostics
  expect_identical(d$line[d$code == qi_code], 2L)
  expect_false("disallow_tied_by_allow" %in% d$code)
  # A rule a NUL cuts takes part as Google's parser cuts it, and the row
  # says it is Google's reading.
  cut <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0),
           charToRaw("?x=1\nDisallow: /*?q=\n"))
  d <- qi_diag(cut)
  msg <- d$message[d$code == qi_code]
  expect_true(startsWith(msg, qi_lead(3L, "/*?q=")))
  expect_match(msg, "Google", fixed = TRUE)
  plain <- qi_diag("User-agent: *\nDisallow: /a\nDisallow: /*?q=\n")
  plain <- plain$message[plain$code == qi_code]
  expect_gt(nchar(msg), nchar(plain))
  expect_true(startsWith(msg, plain))
})

test_that("ROBO-jnnnkyat: the scan reads each value once", {
  groups <- validation_groups(as.data.frame(
    robotstxtr_validation_parse_(charToRaw(qi_fixtures$shop$body)),
    stringsAsFactors = FALSE
  ))
  found <- query_index_note_diagnostics(groups)
  expect_identical(nrow(found), 1L)
  expect_identical(found$line, 2L)
  # Lines in `skip` are left out, as the validator leaves out tied
  # Disallows and lower-case-escape twins.
  found <- query_index_note_diagnostics(groups, skip = 2:5)
  expect_identical(nrow(found), 0L)
  found <- query_index_note_diagnostics(groups, skip = 2L)
  expect_identical(found$line, 3L)
})

test_that("ROBO-jnnnkyat: the row's length is bounded", {
  long <- paste0("User-agent: *\nDisallow: /", strrep("a", 5000L), "?b=\n",
                 paste0("Disallow: /q", seq_len(200L), "?c=\n",
                        collapse = ""))
  d <- qi_diag(long)
  msg <- d$message[d$code == qi_code]
  expect_length(msg, 1L)
  expect_lt(nchar(msg), 800L)
  expect_match(msg, "and 196 more", fixed = TRUE)
  # A non-ASCII value shows ASCII-safe.
  wide <- paste0("User-agent: *\nDisallow: /",
                 strrep(intToUtf8(233L), 30L), "?a=\n")
  d <- qi_diag(wide)
  msg <- d$message[d$code == qi_code]
  expect_false(grepl("[^ -~]", msg, useBytes = TRUE))
  expect_lt(nchar(msg), 800L)
})

test_that("ROBO-jnnnkyat: robots_validate_url() gives the same row", {
  body <- qi_fixtures$shop$body
  local_fake_ssrfr(function(req) {
    fake_response(200L, url = req$url, body = body)
  })
  x <- robots_validate_url("https://e.example/page")
  d <- x$diagnostics
  expect_identical(d$code, c("rule_query_parameter_position", qi_code))
  expect_identical(d$message, qi_diag(body)$message)
  expect_identical(x$documents$validation_status, "valid")
})
