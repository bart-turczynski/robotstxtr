# ROBO-pbwijkdq: a named group replaces `User-agent: *` for the crawlers it
# names (RFC 9309 section 2.2.1), so a group written as if it added to `*`
# loses every `*` Disallow. When a lost `*` Disallow blocks a path under `*`
# that the named group allows (a witness, decided by Google's matcher), the
# group gets the warning wildcard_disallows_not_inherited, and those rules
# leave its wildcard_rules_not_inherited info row. Info rows whose remaining
# lost rules are the same merge into one row naming each group. A full block
# loses no Disallow; the crawlers that ignore `*` anyway (AdsBot-Google,
# AdsBot-Google-Mobile, Mediapartners-Google, APIs-Google; ROBO-fbbmvbob)
# lose nothing, and their info row says so.

wd_text <- function(...) robots_validate_text(paste0(paste(..., sep = "\n"),
                                                     "\n"))

wd_codes <- function(x) {
  d <- x$diagnostics
  keep <- d$code %in% c("wildcard_disallows_not_inherited",
                        "wildcard_rules_not_inherited")
  paste0(d$code[keep], "@", d$line[keep])
}

wd_rows <- function(x, code = "wildcard_disallows_not_inherited") {
  d <- x$diagnostics
  d[d$code == code, , drop = FALSE]
}

wd_tail <- function(k = 2L) {
  paste0("A named group replaces `User-agent: *` for the crawlers it names ",
         "instead of adding to it (RFC 9309 section 2.2.1). If the group ",
         "was meant to add to `User-agent: *`, repeat ",
         if (k == 1L) "this Disallow" else "these Disallows", " in it.")
}

test_that("an additive group warns, naming each lost Disallow", {
  x <- wd_text("User-agent: *", "Disallow: /account/", "Disallow: /search",
               "", "User-agent: Googlebot-News", "Disallow: /news-a",
               "Disallow: /news-b")
  expect_identical(wd_codes(x), "wildcard_disallows_not_inherited@5")
  d <- wd_rows(x)
  expect_identical(d$severity, "warning")
  expect_identical(d$directive, "user-agent")
  expect_identical(d$message, paste(
    paste0("Googlebot-News obeys only this group, so these `User-agent: *` ",
           "Disallows do not apply to it: Disallow: /account/ (line 2), ",
           "Disallow: /search (line 3)."),
    wd_tail()
  ))
  expect_identical(x$documents$validation_status, "warning")
})

test_that("an allow-only group says it blocks nothing", {
  x <- wd_text("User-agent: *", "Disallow: /account/", "",
               "User-agent: Twitterbot", "Allow: /en/news/thp")
  expect_identical(wd_codes(x), "wildcard_disallows_not_inherited@4")
  expect_identical(wd_rows(x)$message, paste(
    paste0("Twitterbot obeys only this group, so this `User-agent: *` ",
           "Disallow does not apply to it: Disallow: /account/ (line 2)."),
    "This group holds no Disallow, so it blocks nothing for it.",
    wd_tail(1L)
  ))
})

test_that("an `Allow: /` group and an empty Disallow group warn", {
  # The shape of wordpress.org/robots.txt (fetched 2026-11-18).
  x <- wd_text("User-agent: *", "Disallow: /wp-admin/", "Disallow: /search",
               "", "User-agent: GPTBot", "User-agent: ClaudeBot", "Allow: /")
  expect_identical(wd_codes(x), "wildcard_disallows_not_inherited@5")
  expect_match(wd_rows(x)$message,
               "^GPTBot and ClaudeBot obey only this group, so these ")
  expect_match(wd_rows(x)$message,
               "This group holds no Disallow, so it blocks nothing for them.",
               fixed = TRUE)
  y <- wd_text("User-agent: *", "Disallow: /p", "", "User-agent: X",
               "Disallow:")
  expect_identical(wd_codes(y), "wildcard_disallows_not_inherited@4")
  expect_true("allow_all_disallow" %in% y$diagnostics$code)
})

test_that("a group that restates every `*` Disallow does not warn", {
  x <- wd_text("User-agent: *", "Disallow: /p", "Allow: /p/ok", "",
               "User-agent: X", "Disallow: /p", "Disallow: /q")
  expect_identical(wd_codes(x), "wildcard_rules_not_inherited@5")
  expect_match(wd_rows(x, "wildcard_rules_not_inherited")$message,
               "Allow: /p/ok (line 3)", fixed = TRUE)
})

test_that("a group can carry both codes for different lost rules", {
  x <- wd_text("User-agent: *", "Disallow: /p", "Allow: /q/ok",
               "Disallow: /q", "", "User-agent: X", "Disallow: /q")
  expect_identical(wd_codes(x), c("wildcard_disallows_not_inherited@6",
                                  "wildcard_rules_not_inherited@6"))
  expect_match(wd_rows(x)$message, ": Disallow: /p (line 2).", fixed = TRUE)
  info <- wd_rows(x, "wildcard_rules_not_inherited")$message
  expect_match(info, "rule does not apply to it: Allow: /q/ok (line 3).",
               fixed = TRUE)
  expect_no_match(info, "/p (line 2)", fixed = TRUE)
})

test_that("a full block loses no Disallow", {
  x <- wd_text("User-agent: *", "Disallow: /p", "Allow: /p/ok", "",
               "User-agent: CCBot", "Disallow: /")
  expect_identical(wd_codes(x), "wildcard_rules_not_inherited@5")
})

test_that("full blocks with the same loss merge into one info row", {
  agents <- c("CCBot", "GPTBot", "Bytespider", "Amazonbot", "cohere-ai",
              "PerplexityBot", "YouBot")
  blocks <- unlist(lapply(agents, function(a) {
    c("", paste0("User-agent: ", a), "Disallow: /")
  }))
  x <- do.call(wd_text, as.list(c("User-agent: *", "Disallow: /p",
                                  "Allow: /p/ok", blocks)))
  expect_identical(wd_codes(x), "wildcard_rules_not_inherited@5")
  expect_identical(wd_rows(x, "wildcard_rules_not_inherited")$message, paste0(
    "CCBot (line 5); GPTBot (line 8); Bytespider (line 11); Amazonbot ",
    "(line 14); cohere-ai (line 17); and 2 more groups each obey only the ",
    "groups that name them, which disallow `/`, so this `User-agent: *` ",
    "Allow rule may be meant as an exception and does not apply to them: ",
    "Allow: ",
    "/p/ok (line 3). A stricter policy for a named crawler may be ",
    "deliberate. A crawler obeys only the groups that name it and ignores ",
    "`User-agent: *` once any group does; `User-agent: *` applies only to ",
    "crawlers no group names."
  ))
})

test_that("full blocks with different losses stay apart", {
  x <- wd_text("User-agent: *", "Disallow: /p", "Allow: /p/ok",
               "Allow: /p/fine", "", "User-agent: A", "Disallow: /", "",
               "User-agent: B", "Disallow: /", "Allow: /p/ok")
  expect_identical(wd_codes(x), c("wildcard_rules_not_inherited@6",
                                  "wildcard_rules_not_inherited@9"))
})

test_that("a `$` pattern is no restatement where a witness path differs", {
  x <- wd_text("User-agent: *", "Disallow: /private", "",
               "User-agent: X", "Disallow: /private$")
  expect_identical(wd_codes(x), "wildcard_disallows_not_inherited@4")
  expect_identical(
    robots_evaluate_text_v1(
      robots_txt = paste0("User-agent: *\nDisallow: /private\n\n",
                          "User-agent: X\nDisallow: /private$\n"),
      url = "https://example.com/private/x", robots_product_token = "X",
      robots_policy_ruleset = "google", matcher_backend = "google"
    )$results$url_decision,
    "allow"
  )
})

test_that("a `*` Allow that cancels the Disallow on every witness is no loss", {
  x <- wd_text("User-agent: *", "Disallow: /private", "Allow: /private", "",
               "User-agent: X", "Disallow: /other")
  expect_false("wildcard_disallows_not_inherited" %in% x$diagnostics$code)
})

test_that("repeated named groups merge before the check", {
  x <- wd_text("User-agent: *", "Disallow: /private", "",
               "User-agent: X", "Disallow: /a", "",
               "User-agent: X", "Disallow: /private")
  expect_false("wildcard_disallows_not_inherited" %in% x$diagnostics$code)
})

test_that("crawlers that ignore `*` get no warning", {
  x <- wd_text("User-agent: *", "Disallow: /p", "",
               "User-agent: AdsBot-Google", "Disallow: /q", "",
               "User-agent: Mediapartners-Google", "Allow: /q")
  # The same remaining rules: one row naming both groups.
  expect_identical(wd_codes(x), "wildcard_rules_not_inherited@4")
  expect_match(wd_rows(x, "wildcard_rules_not_inherited")$message, paste0(
    "^AdsBot-Google \\(line 4\\); and Mediapartners-Google \\(line 7\\) ",
    "ignore `User-agent: \\*` whether or not a group names them"
  ))
  x <- wd_text("User-agent: *", "Disallow: /p", "",
               "User-agent: AdsBot-Google", "Disallow: /q")
  expect_identical(wd_rows(x, "wildcard_rules_not_inherited")$message,
                   paste0(
    "AdsBot-Google ignores `User-agent: *` whether or not a group names it ",
    "(one of Google's special-case crawlers), so this `User-agent: *` rule ",
    "never applied to it: Disallow: /p (line 2)."
  ))
  body <- paste0("User-agent: *\nDisallow: /p\n\n",
                 "User-agent: AdsBot-Google\nDisallow: /q\n")
  expect_identical(
    robots_evaluate_text_v1(
      robots_txt = "User-agent: *\nDisallow: /p\n",
      url = "https://example.com/p", robots_product_token = "AdsBot-Google",
      robots_policy_ruleset = "google", matcher_backend = "google"
    )$results$url_decision,
    "allow"
  )
  expect_identical(wd_codes(robots_validate_text(body)),
                   "wildcard_rules_not_inherited@4")
})

test_that("the Bloomberg shape warns on the loosening groups", {
  # bloomberg.com/robots.txt (fetched 2026-11-17), shortened.
  x <- wd_text(
    "User-agent: *", "Disallow: /account/", "Disallow: /search",
    "Allow: /account/newsletters", "",
    "User-agent: Mediapartners-Google", "Disallow: /podcasts/", "",
    "User-agent: Spinn3r", "Disallow: /podcasts/", "",
    "User-agent: Googlebot-News", "Disallow: /a", "Disallow: /b", "",
    "User-agent: Twitterbot", "Allow: /en/news/thp", "",
    "User-agent: CCBot", "Disallow: /", "",
    "User-agent: GPTBot", "Disallow: /"
  )
  codes <- wd_codes(x)
  expect_true(all(paste0("wildcard_disallows_not_inherited@",
                         c(9L, 12L, 16L)) %in% codes))
  expect_false("wildcard_disallows_not_inherited@6" %in% codes)
  # The two full blocks lose the same Allow: one row.
  expect_identical(sum(codes == "wildcard_rules_not_inherited@19"), 1L)
  expect_false("wildcard_rules_not_inherited@22" %in% codes)
})

test_that("a path only the group's own Allow reopens is not this warning", {
  # bloomberg.com's AI-crawler groups: `Disallow: /` with Allow prefixes
  # that reopen a narrower `*` Disallow (ROBO-cufxicmz's case).
  x <- wd_text("User-agent: *", "Disallow: /company/search/", "",
               "User-agent: GPTBot", "Disallow: /", "Allow: /company")
  expect_false("wildcard_disallows_not_inherited" %in% x$diagnostics$code)
  expect_match(wd_rows(x, "wildcard_rules_not_inherited")$message,
               "Disallow: /company/search/ (line 2)", fixed = TRUE)
})

test_that("a merged info row still owns each group's line", {
  # Review of 2a1a5a4: merging must not hand a later group's first line to
  # user_agent_repeated_group, which skips lines another report owns.
  x <- wd_text("User-agent: *", "Allow: /p/ok", "Disallow: /p", "",
               "User-agent: A", "Disallow: /", "",
               "User-agent: A", "User-agent: B", "Disallow: /")
  expect_identical(wd_codes(x), "wildcard_rules_not_inherited@5")
  expect_false("user_agent_repeated_group" %in% x$diagnostics$code)
})
