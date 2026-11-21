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

la_perplexity <- "User-agent: Perplexity‑User"

test_that("a look-alike cut row keeps today's text as its start", {
  x <- la_text(la_perplexity, "Disallow: /x")
  row <- la_rows(x)
  expect_identical(row$severity, "info")
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
    list("User-agent: Perplexity−User", la_read_as("Perplexity")),
    list("User-agent: Bingbоt", la_read_as("Bingb")),
    list("User-agent: аbcbot", la_none()),
    list("User-agent: google＿extended", la_read_as("google")),
    list("User-agent: Perplexity­User", la_read_as("Perplexity"))
  )
  for (case in cases) {
    row <- la_rows(la_text(case[[1L]], "Disallow: /x"))
    expect_identical(nrow(row), 1L, label = case[[1L]])
    expect_identical(row$severity, "info", label = case[[1L]])
    expect_true(startsWith(row$message, case[[2L]]), label = case[[1L]])
  }
  x <- la_text("Disаllow: /a")
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
    list("User-agent: __usage_aï-training\nDisallow: /x\n",
         la_read_as("__usage_a"))
  )
  for (case in cases) {
    row <- la_rows(robots_validate_text(case[[1L]]))
    expect_identical(row$message, case[[2L]], label = case[[1L]])
  }
  for (body in c("Café: /x\n",
                 "User-agent: a\nDisallow: /x\n﻿User-agent: b\n")) {
    row <- la_rows(robots_validate_text(body), "unknown_directive")
    expect_identical(row$message, la_unknown, label = body)
  }
  x <- robots_validate_text("User-agent:\nDisallow: /x\n")
  expect_false(any(grepl("U+", x$diagnostics$message, fixed = TRUE)))
})

test_that("a look-alike Google's parser never reads stays silent", {
  nul <- c(charToRaw("User-agent: Perplexity"), as.raw(0),
           charToRaw("‑User\nDisallow: /x\n"))
  hash <- "User-agent: Perplexity #‑User\nDisallow: /x\n"
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
  cases <- list(c("Bingbоt", "bingbot", "bing"),
                c("Yandeх", "Yandex", "yandex"))
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
