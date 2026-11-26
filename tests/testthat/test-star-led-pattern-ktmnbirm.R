# ROBO-ktmnbirm: an Allow or Disallow pattern led by `*` (`*.pdf`) is outside
# RFC 9309's path-pattern grammar. Google's matcher matches `*X` as if led by
# `/` when X is not `/`-led (`*/X` also matches what `/X` matches), with a
# priority one byte lower. Only rules inside a group count.

sl_code <- "rule_star_led_pattern"
sl_ua <- "User-agent: *\n"

sl_diag <- function(body) robots_validate_text(body)$diagnostics

# The note for one line, as the validator writes it.
sl_one <- function(line, shown) {
  paste0(
    "The rule on line ", line, " ('", shown, "') starts with '*', which is ",
    "outside RFC 9309's path-pattern grammar: there a pattern starts with ",
    "'/' (RFC 9309 section 2.2). Google's matcher reads it as if led by ",
    "'/': '", shown, "' matches the same paths as '/", shown, "', but ",
    "counts one byte less when the longest matching rule decides. Bing and ",
    "Yandex may read this rule differently."
  )
}

# The note for several lines: `listed` as the message lists them.
sl_many <- function(listed, shown) {
  paste0(
    "The rules on lines ", listed, " (the first '", shown, "') start with ",
    "'*', which is outside RFC 9309's path-pattern grammar: there a pattern ",
    "starts with '/' (RFC 9309 section 2.2). Google's matcher reads such a ",
    "pattern as if led by '/': '", shown, "' matches the same paths as '/",
    shown, "', but counts one byte less when the longest matching rule ",
    "decides. Bing and Yandex may read these rules differently."
  )
}

# Each body, with the codes it draws besides the new one, the line the new
# row stands on, and the pattern it shows.
sl_cases <- list(
  list(body = paste0(sl_ua, "Disallow: *.pdf\n"), codes = character(),
       shown = "*.pdf", directive = "disallow"),
  list(body = paste0(sl_ua, "Disallow: *?\n"),
       codes = "rule_query_crawl_not_index", shown = "*?",
       directive = "disallow"),
  list(body = paste0(sl_ua, "Disallow: *\n"), codes = character(),
       shown = "*", directive = "disallow"),
  list(body = paste0(sl_ua, "Allow: *\n"), codes = character(),
       shown = "*", directive = "allow"),
  list(body = paste0(sl_ua, "Disallow: **x\n"), codes = character(),
       shown = "**x", directive = "disallow"),
  list(body = paste0(sl_ua, "Allow: *.pdf\n"), codes = character(),
       shown = "*.pdf", directive = "allow"),
  list(body = paste0(sl_ua, "Disallow: \t  *.pdf   # note\n"),
       codes = character(), shown = "*.pdf", directive = "disallow"),
  list(body = "User-agent: *\r\nDisallow: *.pdf\r\n", codes = character(),
       shown = "*.pdf", directive = "disallow"),
  list(body = "User-agent: *\rDisallow: *.pdf\r", codes = character(),
       shown = "*.pdf", directive = "disallow"),
  list(body = "User-agent: *\nAllow: /\nDisallow: *.pdf\n",
       codes = character(), shown = "*.pdf", line = 3L,
       directive = "disallow")
)

# Bodies that draw no new row: `/`-led, empty, a `*` inside the value or
# only in a comment, and a `*` only on User-agent lines.
sl_silent <- list(
  list(body = paste0(sl_ua, "Disallow: /*.pdf\n"), codes = character()),
  list(body = paste0(sl_ua, "Disallow:\n"), codes = "allow_all_disallow"),
  list(body = paste0(sl_ua, "Disallow: /\n"), codes = character()),
  list(body = paste0(sl_ua, "Disallow: /a*b\n"), codes = character()),
  list(body = paste0(sl_ua, "Disallow: /a # *x\n# Disallow: *.y\n"),
       codes = character()),
  list(body = "User-agent: *\nUser-agent: *bot\nDisallow: /x\n",
       codes = "user_agent_cut"),
  # A rule before any User-agent line is in no group: Google reads none.
  list(body = "Disallow: *.pdf\nUser-agent: *\nAllow: /\n",
       codes = "rule_without_user_agent")
)

test_that("ROBO-ktmnbirm: a `*`-led rule gets one info row", {
  for (case in sl_cases) {
    d <- sl_diag(case$body)
    line <- if (is.null(case$line)) 2L else case$line
    expect_identical(d$code[d$code != sl_code], case$codes, label = case$body)
    row <- d[d$code == sl_code, , drop = FALSE]
    expect_identical(row$line, line, label = case$body)
    expect_identical(row$severity, "info", label = case$body)
    expect_identical(row$directive, case$directive, label = case$body)
    expect_identical(row$message, sl_one(line, case$shown), label = case$body)
  }
})

test_that("ROBO-ktmnbirm: the row leaves the validation status alone", {
  x <- robots_validate_text(paste0(sl_ua, "Disallow: *.pdf\n"))
  expect_identical(x$documents$validation_status, "valid")
})

test_that("ROBO-ktmnbirm: `/`-led, empty and inner-`*` rules stay silent", {
  for (case in sl_silent) {
    d <- sl_diag(case$body)
    expect_identical(d$code, case$codes, label = case$body)
  }
})

test_that("ROBO-ktmnbirm: Google matches `*X` on the paths `/*X` matches", {
  paths <- c("/", "/x.pdf", "/a/b.pdf", "/x.pdfz", "/x.html", "/pdf",
             "/?q=1", "/a?q=", "/a?b=1&q=2", "/a?b=1", "/q=")
  urls <- paste0("https://example.com", paths)
  pairs <- list(c("*.pdf", "/*.pdf"), c("*?q=", "/*?q="), c("*", "/"))
  for (pair in pairs) {
    decide <- function(pattern) {
      body <- paste0(sl_ua, "Disallow: ", pattern, "\n")
      allowed_by_robots_text(body, urls, "FooBot")$results$allowed
    }
    expect_identical(decide(pair[[1L]]), decide(pair[[2L]]),
                     label = pair[[1L]])
  }
  # `*.pdf` blocks a PDF and leaves other files open.
  x <- allowed_by_robots_text(
    paste0(sl_ua, "Disallow: *.pdf\n"),
    c("https://example.com/x.pdf", "https://example.com/x.html"), "FooBot"
  )
  expect_identical(x$results$allowed, c(FALSE, TRUE))
})

test_that("ROBO-ktmnbirm: a `*/X` rule also matches the paths `/X` matches", {
  # src/robots.cc Matches() anchors at the path's first byte and lets `*`
  # match nothing, so `*/a` reads `/a` from byte 0 too; `/*/a` cannot.
  paths <- c("/", "/a", "/a/", "/a/b.pdf", "/aprivate", "/x/a", "/x/ab",
             "/x", "/b/c")
  decide <- function(pattern) {
    body <- paste0(sl_ua, "Disallow: ", pattern, "\n")
    r <- robots_evaluate_text_v1(body, paste0("https://example.com", paths),
                                 "googlebot", "google", "google")
    r$results$url_decision
  }
  blocked <- function(pattern) paths[decide(pattern) == "disallow"]
  expect_identical(blocked("*/a"),
                   c("/a", "/a/", "/a/b.pdf", "/aprivate", "/x/a", "/x/ab"))
  expect_identical(blocked("/*/a"), c("/x/a", "/x/ab"))
  expect_identical(blocked("/a"), c("/a", "/a/", "/a/b.pdf", "/aprivate"))
  # `*/` blocks every path; `/*/` only a path with a second `/`.
  expect_identical(blocked("*/"), paths)
  expect_identical(blocked("/*/"), c("/a/", "/a/b.pdf", "/x/a", "/x/ab",
                                     "/b/c"))
})

test_that("ROBO-ktmnbirm: the note for a `*/`-led rule", {
  d <- sl_diag(paste0(sl_ua, "Disallow: */feed/\n"))
  expect_identical(d$code, sl_code)
  expect_identical(d$message, paste0(
    "The rule on line 2 ('*/feed/') starts with '*', which is outside RFC ",
    "9309's path-pattern grammar: there a pattern starts with '/' (RFC 9309 ",
    "section 2.2). Google's matcher lets a leading '*' match nothing at the ",
    "path's first byte: '*/feed/' matches the paths '/*/feed/' matches and ",
    "also those '/feed/' matches, but counts one byte less than '/*/feed/' ",
    "when the longest matching rule decides. Bing and Yandex may read this ",
    "rule differently."
  ))
  # A run of `*` is read past whole; several lines take the same sentence.
  d <- sl_diag(paste0(sl_ua, "Disallow: **/a\nAllow: *.css\n"))
  expect_match(d$message, paste0("'**/a' matches the paths '/**/a' matches ",
                                 "and also those '/a' matches"),
               fixed = TRUE)
  expect_match(d$message, "lines 2 and 3", fixed = TRUE)
})

test_that("ROBO-ktmnbirm: a `*` lead ranks one byte below a `/*` lead", {
  # src/robots.cc ranks a match by the pattern's byte length: `*.pdf` (5)
  # loses to `/a.pdf` (6), and `/*.pdf` (6) ties it, so the Allow wins.
  # So the note suggests no `/*.pdf` rewrite.
  url <- "https://example.com/a.pdf"
  x <- allowed_by_robots_text(
    paste0(sl_ua, "Allow: *.pdf\nDisallow: /a.pdf\n"), url, "FooBot"
  )
  expect_false(x$results$allowed)
  y <- allowed_by_robots_text(
    paste0(sl_ua, "Allow: /*.pdf\nDisallow: /a.pdf\n"), url, "FooBot"
  )
  expect_true(y$results$allowed)
  d <- sl_diag(paste0(sl_ua, "Allow: *.pdf\nDisallow: /a.pdf\n"))
  expect_no_match(d$message[d$code == sl_code], "write", fixed = TRUE)
})

test_that("ROBO-ktmnbirm: one row per file, five lines then a count", {
  three <- paste0(sl_ua, "Disallow: *.pdf\nAllow: /a\nDisallow: *.doc\n",
                  "Allow: *.txt\n")
  d <- sl_diag(three)
  expect_identical(d$code, sl_code)
  expect_identical(d$line, 2L)
  expect_identical(d$message, sl_many("2, 4 and 5", "*.pdf"))
  seven <- paste0(sl_ua, paste0("Disallow: *.e", 1:7, "\n", collapse = ""))
  d <- sl_diag(seven)
  expect_identical(d$code, sl_code)
  expect_identical(d$line, 2L)
  expect_identical(d$message, sl_many("2, 3, 4, 5, 6 and 2 more", "*.e1"))
  # Five lines exactly are all listed.
  five <- paste0(sl_ua, paste0("Disallow: *.e", 1:5, "\n", collapse = ""))
  expect_identical(sl_diag(five)$message,
                   sl_many("2, 3, 4, 5 and 6", "*.e1"))
})

test_that("ROBO-ktmnbirm: lines in several groups still give one row", {
  body <- paste0("User-agent: a\nDisallow: /x\nAllow: *.css\n\n",
                 "User-agent: b\nDisallow: *.pdf\n")
  d <- sl_diag(body)
  row <- d[d$code == sl_code, , drop = FALSE]
  expect_identical(row$line, 3L)
  expect_identical(row$directive, "allow")
  expect_identical(row$message, sl_many("3 and 6", "*.css"))
})

test_that("ROBO-ktmnbirm: a long pattern is shown elided", {
  pattern <- paste0("*", strrep("a", 50L))
  d <- sl_diag(paste0(sl_ua, "Disallow: ", pattern, "\n"))
  shown <- paste0("*", strrep("a", 35L), "...")
  expect_identical(d$message[d$code == sl_code], sl_one(2L, shown))
})

test_that("ROBO-ktmnbirm: a `*?name=` rule draws the valueless note too", {
  d <- sl_diag(paste0(sl_ua, "Disallow: *?s=\n"))
  expect_identical(d$code, c("rule_query_parameter_position",
                             "rule_query_crawl_not_index",
                             sl_code,
                             "rule_query_parameter_valueless"))
  expect_identical(d$line[d$code == sl_code], 2L)
})

test_that("ROBO-ktmnbirm: NUL, malformed bytes and long lines", {
  # A NUL before the `*`: Google reads an empty value, so no row.
  nul <- c(charToRaw(paste0(sl_ua, "Disallow: ")), as.raw(0),
           charToRaw("*.pdf\n"))
  expect_identical(sl_diag(nul)$code, c("nul_byte", "empty_rule_value"))
  nul_after <- c(charToRaw(paste0(sl_ua, "Disallow: /a")), as.raw(0),
                 charToRaw("*.pdf\n"))
  expect_identical(sl_diag(nul_after)$code, c("nul_byte", "rule_cut_by_nul"))
  # Only the first byte is read, so bytes after the `*` do not matter.
  bad <- c(charToRaw(paste0(sl_ua, "Disallow: *")), as.raw(0xe9),
           charToRaw(".pdf\n"))
  d <- sl_diag(bad)
  expect_identical(d$code, c("invalid_utf8", sl_code))
  expect_identical(d$message[[2L]], sl_one(2L, "*%E9.pdf"))
  latin1 <- c(charToRaw(paste0(sl_ua, "Disallow: *caf")), as.raw(0xe9),
              charToRaw("\n"))
  expect_identical(sl_diag(latin1)$code, c("invalid_utf8", sl_code))
  # A control byte is shown escaped, not raw.
  ctl <- c(charToRaw(paste0(sl_ua, "Disallow: *")), as.raw(1),
           charToRaw("x\n"))
  d <- sl_diag(ctl)
  expect_identical(d$message[d$code == sl_code], sl_one(2L, "*\\x01x"))
  long <- paste0(sl_ua, "Disallow: *", strrep("x", 17000L), "\n")
  d <- sl_diag(long)
  expect_identical(d$code, c("line_too_long", sl_code))
  expect_identical(d$line, c(2L, 2L))
})

test_that("ROBO-ktmnbirm: a cut body still gets the row", {
  text <- paste0(sl_ua, "Disallow: *.pdf\nAllow: /later-",
                 strrep("x", 200L), "\n")
  x <- validate_document_bytes(charToRaw(text)[seq_len(40L)], "s",
                               "supplied", max_bytes = 40L,
                               body_truncated = TRUE)
  d <- x$diagnostics
  expect_identical(d$code, c(sl_code, "body_truncated"))
  expect_identical(d$line[[1L]], 2L)
  expect_false(sl_code %in% names(validation_cut_skips))
})
