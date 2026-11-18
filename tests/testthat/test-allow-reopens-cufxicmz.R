# ROBO-cufxicmz: a named group replaces `User-agent: *` for the crawlers it
# names (RFC 9309 section 2.2.1), so an Allow in it can reopen a path that
# `*` disallows: bloomberg.com's AI-crawler groups hold `Disallow: /` plus
# `Allow: /company` while `*` disallows `/company/search/`. The group gets
# the warning allow_reopens_wildcard_disallow when a witness path is
# disallowed under the `*` groups, allowed under the named crawler's
# merged groups, and disallowed by those groups' Disallows alone (the Allow
# causes the opening; a path the Disallows alone leave open is
# wildcard_disallows_not_inherited, ROBO-pbwijkdq). Google's matcher
# decides every read, so a reported witness is exact; a pair whose overlap
# no candidate path shows is skipped.

ar_text <- function(...) {
  robots_validate_text(paste0(paste(c(...), collapse = "\n"), "\n"))
}

ar_codes <- function(x) {
  d <- x$diagnostics
  keep <- d$code %in% c("allow_reopens_wildcard_disallow",
                        "wildcard_disallows_not_inherited",
                        "wildcard_rules_not_inherited")
  paste0(d$code[keep], "@", d$line[keep])
}

ar_rows <- function(x, code = "allow_reopens_wildcard_disallow") {
  d <- x$diagnostics
  d[d$code == code, , drop = FALSE]
}

# The Google backend's decision for `url` as crawler `agent`.
ar_google <- function(lines, agent, path) {
  robots_evaluate_text_v1(
    paste0(paste(lines, collapse = "\n"), "\n"),
    paste0("https://example.com", path), agent,
    robots_policy_ruleset = "google", matcher_backend = "google"
  )$results$url_decision
}

ar_tail <- function(k = 1L) {
  paste0("A named group replaces `User-agent: *` for the crawlers it names ",
         "instead of adding to it (RFC 9309 section 2.2.1). If ",
         if (k == 1L) "this path was" else "these paths were",
         " meant to stay blocked for it, add ",
         if (k == 1L) "a Disallow" else "Disallows",
         " to this group longer than the Allow matching ",
         if (k == 1L) "the path." else "each path.")
}

bloomberg <- c(
  "User-agent: *",
  "Disallow: /account/",
  "Disallow: /company/search/",
  "Disallow: /tc/search/",
  "",
  "User-agent: ClaudeBot",
  "Disallow: /",
  "Allow: /company",
  "Allow: /tc"
)

test_that("the Bloomberg shape warns, naming each reopened path", {
  x <- ar_text(bloomberg)
  expect_identical(ar_codes(x), c("allow_reopens_wildcard_disallow@6",
                                  "wildcard_rules_not_inherited@6"))
  d <- ar_rows(x)
  expect_identical(d$severity, "warning")
  expect_identical(d$directive, "user-agent")
  expect_identical(d$message, paste(
    paste0("ClaudeBot obeys only this group, so Allows there reopen these ",
           "paths, which `User-agent: *` disallows: /company/search/ ",
           "(allowed by Allow: /company on line 8; disallowed for `*` by ",
           "Disallow: /company/search/ on line 3), /tc/search/ (allowed by ",
           "Allow: /tc on line 9; disallowed for `*` by Disallow: ",
           "/tc/search/ on line 4)."),
    ar_tail(2L)
  ))
  # The info row keeps only what the warning does not report.
  info <- ar_rows(x, "wildcard_rules_not_inherited")$message
  expect_match(info, "Disallow: /account/ (line 2)", fixed = TRUE)
  expect_no_match(info, "search", fixed = TRUE)
  expect_identical(x$documents$validation_status, "warning")
  # Google's matcher agrees: the named crawler gets the path, `*` does not.
  expect_identical(ar_google(bloomberg, "ClaudeBot", "/company/search/q"),
                   "allow")
  expect_identical(ar_google(bloomberg, "otherbot", "/company/search/q"),
                   "disallow")
})

test_that("a restated Disallow with a narrower Allow under it warns", {
  lines <- c("User-agent: *", "Disallow: /private", "",
             "User-agent: GPTBot", "Disallow: /private",
             "Allow: /private/public")
  x <- ar_text(lines)
  expect_identical(ar_codes(x), "allow_reopens_wildcard_disallow@4")
  expect_identical(ar_rows(x)$message, paste(
    paste0("GPTBot obeys only this group, so Allows there reopen this ",
           "path, which `User-agent: *` disallows: /private/public ",
           "(allowed by Allow: /private/public on line 6; disallowed for ",
           "`*` by Disallow: /private on line 2)."),
    ar_tail(1L)
  ))
  expect_identical(ar_google(lines, "GPTBot", "/private/public"), "allow")
  expect_identical(ar_google(lines, "otherbot", "/private/public"),
                   "disallow")
})

test_that("a `*`-led `*` Disallow is read under the Allow (washingtonpost)", {
  lines <- c("User-agent: *", "Disallow: /*_print.html", "",
             "User-agent: ClaudeBot", "Disallow: /",
             "Allow: /creativegroup/")
  x <- ar_text(lines)
  expect_identical(ar_codes(x), "allow_reopens_wildcard_disallow@4")
  expect_match(ar_rows(x)$message, paste0(
    "/creativegroup/_print.html (allowed by Allow: /creativegroup/ on line ",
    "6; disallowed for `*` by Disallow: /*_print.html on line 2)"
  ), fixed = TRUE)
  expect_identical(ar_google(lines, "ClaudeBot", "/creativegroup/a_print.html"),
                   "allow")
  expect_identical(ar_google(lines, "otherbot", "/creativegroup/a_print.html"),
                   "disallow")
})

test_that("`$` and query patterns under an Allow warn (medium.com)", {
  lines <- c("User-agent: *", "Disallow: /*/edit$", "Disallow: /*/search?q=",
             "", "User-agent: GPTBot", "Disallow: /", "Allow: /about")
  x <- ar_text(lines)
  expect_identical(ar_codes(x), "allow_reopens_wildcard_disallow@5")
  msg <- ar_rows(x)$message
  expect_match(msg, "/about/edit (allowed by Allow: /about on line 7",
               fixed = TRUE)
  expect_match(msg, "/about/search?q= (allowed by Allow: /about on line 7",
               fixed = TRUE)
  expect_identical(ar_google(lines, "GPTBot", "/about/search?q=x"), "allow")
  expect_identical(ar_google(lines, "otherbot", "/about/search?q=x"),
                   "disallow")
  # Control: without the Allow, the group blocks everything (a full block).
  y <- ar_text(lines[-7L])
  expect_false("allow_reopens_wildcard_disallow" %in% y$diagnostics$code)
})

test_that("it is silent where no Allow reopens a `*`-disallowed path", {
  silent <- function(...) {
    x <- ar_text(...)
    expect_false("allow_reopens_wildcard_disallow" %in% x$diagnostics$code)
  }
  # The named group's own rules block every witness.
  silent("User-agent: *", "Disallow: /company/search/", "",
         "User-agent: GPTBot", "Disallow: /", "Allow: /company",
         "Disallow: /company/search/")
  # A `*` Allow cancels the `*` Disallow.
  silent("User-agent: *", "Disallow: /company/search/",
         "Allow: /company/search/", "",
         "User-agent: GPTBot", "Disallow: /", "Allow: /company")
  # The `*` Disallow is under none of the group's Allows.
  silent("User-agent: *", "Disallow: /company/search/", "",
         "User-agent: GPTBot", "Disallow: /", "Allow: /news")
  # The group has no Allow.
  silent("User-agent: *", "Disallow: /company/search/", "",
         "User-agent: GPTBot", "Disallow: /other")
  # The group allows the path without any Allow: that is the loss
  # ROBO-pbwijkdq reports, not an Allow reopening it.
  silent("User-agent: *", "Disallow: /company/search/", "",
         "User-agent: GPTBot", "Disallow: /other", "Allow: /other/ok")
  # Paths are case-sensitive: `/Company` does not match `/company/search/`.
  silent("User-agent: *", "Disallow: /company/search/", "",
         "User-agent: GPTBot", "Disallow: /", "Allow: /Company")
  # The crawlers that ignore `*` anyway (ROBO-fbbmvbob).
  silent("User-agent: *", "Disallow: /company/search/", "",
         "User-agent: Mediapartners-Google", "Disallow: /",
         "Allow: /company")
})

test_that("an Allow prefix matches across a segment boundary", {
  # Google matches `/tc` as a prefix, so it reopens `/tcx/search/`.
  lines <- c("User-agent: *", "Disallow: /tcx/search/", "",
             "User-agent: GPTBot", "Disallow: /", "Allow: /tc")
  x <- ar_text(lines)
  expect_match(ar_rows(x)$message, "/tcx/search/ (allowed by Allow: /tc on ",
               fixed = TRUE)
  expect_identical(ar_google(lines, "GPTBot", "/tcx/search/"), "allow")
  # `/tc/` does not match it.
  y <- ar_text(c(lines[-6L], "Allow: /tc/"))
  expect_false("allow_reopens_wildcard_disallow" %in% y$diagnostics$code)
})

test_that("a query and an escaped `/` are matched as Google matches them", {
  lines <- c("User-agent: *", "Disallow: /search?q=", "", "User-agent: GPTBot",
             "Disallow: /", "Allow: /search")
  x <- ar_text(lines)
  expect_match(ar_rows(x)$message, "/search?q= (allowed by Allow: /search ",
               fixed = TRUE)
  expect_identical(ar_google(lines, "GPTBot", "/search?q=a"), "allow")
  # `%2F` is not `/`: `Allow: /a/` does not match `/a%2Fb`, and `Allow: /a`
  # does.
  enc <- c("User-agent: *", "Disallow: /a%2Fb", "", "User-agent: GPTBot",
           "Disallow: /", "Allow: /a/")
  expect_false("allow_reopens_wildcard_disallow" %in%
                 ar_text(enc)$diagnostics$code)
  expect_identical(ar_google(enc, "GPTBot", "/a%2Fb"), "disallow")
  enc[[6L]] <- "Allow: /a"
  expect_match(ar_rows(ar_text(enc))$message,
               "/a%2Fb (allowed by Allow: /a on line 6", fixed = TRUE)
  expect_identical(ar_google(enc, "GPTBot", "/a%2Fb"), "allow")
})

test_that("merged repeated groups and stacked agents give one row", {
  # GPTBot's two groups merge: the block in one, the Allow in the other.
  x <- ar_text("User-agent: *", "Disallow: /company/search/", "",
               "User-agent: GPTBot", "Disallow: /", "",
               "User-agent: GPTBot", "Allow: /company")
  d <- ar_rows(x)
  expect_identical(d$line, 4L)
  expect_match(d$message, "^GPTBot obeys only the groups that name it, ")
  expect_match(d$message, "add a Disallow to these groups longer ",
               fixed = TRUE)
  # Two crawlers stacked on one group share its row.
  y <- ar_text("User-agent: *", "Disallow: /company/search/", "",
               "User-agent: ClaudeBot", "User-agent: GPTBot", "Disallow: /",
               "Allow: /company")
  d <- ar_rows(y)
  expect_identical(d$line, 4L)
  expect_match(d$message, "^ClaudeBot and GPTBot obey only this group, ")
  expect_match(d$message, "blocked for them, add ", fixed = TRUE)
})

test_that("a `*` Disallow lost to the group is not reported again", {
  # `/a` is lost (the Disallows alone leave `/ax` open): that is
  # wildcard_disallows_not_inherited's row, even though the Allow also
  # reopens `/a/b`.
  x <- ar_text("User-agent: *", "Disallow: /a", "", "User-agent: GPTBot",
               "Disallow: /a/", "Allow: /a/b")
  expect_identical(ar_codes(x), "wildcard_disallows_not_inherited@4")
})

test_that("a `*` after a literal part is read under a longer Allow", {
  # `/p/*/share` under `Allow: /p/abc` gives `/p/abc/share`.
  lines <- c("User-agent: *", "Disallow: /p/*/share", "", "User-agent: GPTBot",
             "Disallow: /", "Allow: /p/abc")
  expect_match(ar_rows(ar_text(lines))$message,
               "/p/abc/share (allowed by Allow: /p/abc on line 6", fixed = TRUE)
  expect_identical(ar_google(lines, "GPTBot", "/p/abc/share"), "allow")
  expect_identical(ar_google(lines, "otherbot", "/p/abc/share"), "disallow")
})

test_that("the list stops at ten paths", {
  x <- ar_text("User-agent: *", sprintf("Disallow: /s/%02d", 1:12), "",
               "User-agent: GPTBot", "Disallow: /", "Allow: /s")
  msg <- ar_rows(x)$message
  expect_match(msg, "on line 11), and 2 more. A named group", fixed = TRUE)
  expect_no_match(msg, "/s/11", fixed = TRUE)
})

test_that("crawlers with the same rules each cite their own Allow line", {
  # Review of bc71586: groups with identical rules share one check, and
  # ClaudeBot's row cited GPTBot's Allow on line 6.
  x <- ar_text("User-agent: *", "Disallow: /company/search/", "",
               "User-agent: GPTBot", "Disallow: /", "Allow: /company", "",
               "User-agent: ClaudeBot", "Disallow: /", "Allow: /company")
  d <- ar_rows(x)
  expect_identical(d$line, c(4L, 8L))
  expect_match(d$message[[1L]], "Allow: /company on line 6;", fixed = TRUE)
  expect_match(d$message[[2L]], "Allow: /company on line 10;", fixed = TRUE)
})

test_that("stacked crawlers reopened by different Allows get their own rows", {
  # Review of bc71586: A's later group reopens the path through line 10,
  # B only through line 7; one shared row cited line 10 for both.
  x <- ar_text("User-agent: *", "Disallow: /company/search/", "",
               "User-agent: A", "User-agent: B", "Disallow: /",
               "Allow: /company", "", "User-agent: A",
               "Allow: /company/search/")
  d <- ar_rows(x)
  expect_identical(d$line, c(4L, 4L))
  expect_match(d$message, paste0("^(A obeys only the groups that name it|",
                                 "B obeys only this group), "))
  a <- d$message[startsWith(d$message, "A ")]
  b <- d$message[startsWith(d$message, "B ")]
  expect_match(a, "Allow: /company/search/ on line 10;", fixed = TRUE)
  expect_match(b, "Allow: /company on line 7;", fixed = TRUE)
})
