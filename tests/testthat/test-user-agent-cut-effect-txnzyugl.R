# ROBO-txnzyugl: user_agent_cut states the effect of the cut. Google's
# matcher reads `Spinn3r` as `Spinn`, so the written value does not match its
# own record: a crawler going by it gets another group naming it, else
# `User-agent: *`, else no rules. Only Google's parser cuts, and a Google
# crawler goes only by its own product tokens, so the row stays a warning
# only when the cut value is a documented Google token the written value did
# not mean (`Googlebot Image` is read as `Googlebot`); a version suffix
# (`Googlebot/2.1`), a trailing `*` (`Mediapartners-Google*`) and every other
# value are info (owner decision, 2026-11-18). Every other group diagnostic
# names the agent as written, ASCII-safe, not the cut token.

cx_text <- function(...) robots_validate_text(paste0(paste(..., sep = "\n"),
                                                     "\n"))

cx_rows <- function(x, code = "user_agent_cut") {
  d <- x$diagnostics
  d[d$code == code, , drop = FALSE]
}

cx_star <- paste0("Unless another group names it, a crawler going by the ",
                  "full value gets the `User-agent: *` group from Google's ",
                  "matcher.")
cx_no_star <- paste0("Unless another group names it, a crawler going by the ",
                     "full value gets no rules from Google's matcher: the ",
                     "file has no `User-agent: *` group.")

cx_read_as <- function(token, fallback, tail) {
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

cx_none <- function(fallback) {
  paste(
    paste0("User-agent value names no crawler for Google's matcher, which ",
           "reads a product token only from a leading run of letters, '_' ",
           "and '-', so there this line matches no crawler."),
    fallback, cx_other
  )
}

cx_google <- function(token) {
  sprintf(paste0("'%s' is a Google crawler token, so that Google crawler ",
                 "follows this group."), token)
}

cx_same <- function(token) {
  sprintf(paste0("'%s' is the Google crawler token the value names, so ",
                 "nothing changes for that crawler."), token)
}

cx_other <- paste0("Only Google's parser shortens the value, and Google's ",
                   "crawlers do not go by it, so nothing changes for them; ",
                   "how the named crawler's own parser reads it is unknown.")

cx_decide <- function(body, url, token, ruleset = "google") {
  robots_evaluate_text_v1(
    robots_txt = body, url = paste0("https://example.com", url),
    robots_product_token = token, robots_policy_ruleset = ruleset,
    matcher_backend = "google"
  )$results$url_decision
}

test_that("severity follows whether a Google crawler reads the cut", {
  cases <- c("Googlebot Image" = "warning", "googlebot image" = "warning",
             "Googlebot/2.1" = "info", "Mediapartners-Google*" = "info",
             "img2dataset" = "info", "dotbot/1.0" = "info",
             "Brightbot 1.0" = "info", "Googlebot-Image/1.0" = "info",
             "360Spider" = "info", "Spinn3r" = "info")
  for (value in names(cases)) {
    x <- cx_text(paste0("User-agent: ", value), "Disallow: /x")
    expect_identical(cx_rows(x)$severity, cases[[value]], label = value)
    expect_identical(
      x$documents$validation_status,
      if (cases[[value]] == "warning") "warning" else "valid",
      label = value
    )
  }
})

test_that("each message states the effect for its kind of cut", {
  x <- cx_text("User-agent: Googlebot Image", "Disallow: /x")
  expect_identical(cx_rows(x)$message,
                   cx_read_as("Googlebot", cx_no_star, cx_google("Googlebot")))
  x <- cx_text("User-agent: Googlebot/2.1", "Disallow: /x")
  expect_identical(cx_rows(x)$message,
                   cx_read_as("Googlebot", cx_no_star, cx_same("Googlebot")))
  x <- cx_text("User-agent: Mediapartners-Google*", "Disallow: /x")
  expect_identical(
    cx_rows(x)$message,
    cx_read_as("Mediapartners-Google", cx_no_star,
               cx_same("Mediapartners-Google"))
  )
  x <- cx_text("User-agent: *", "Disallow: /a", "",
               "User-agent: img2dataset", "Disallow: /")
  expect_identical(cx_rows(x)$message,
                   cx_read_as("img", cx_star, cx_other))
  x <- cx_text("User-agent: *", "Disallow: /a", "",
               "User-agent: 360Spider", "Disallow: /")
  expect_identical(cx_rows(x)$message, cx_none(cx_star))
})

test_that("a cut value falls back to `*` on the Google backend", {
  body <- paste0("User-agent: *\nDisallow: /account/\n\n",
                 "User-agent: Spinn3r\nDisallow: /podcasts/\n")
  expect_identical(cx_decide(body, c("/podcasts/x", "/account/settings"),
                             "Spinn3r"),
                   c("allow", "disallow"))
  expect_identical(cx_decide(body, "/podcasts/x", "Spinn"), "disallow")
  x <- robots_validate_text(body)
  expect_identical(cx_rows(x)$message,
                   cx_read_as("Spinn", cx_star, cx_other))
})

test_that("with no `*` group a cut value gets no rules", {
  body <- "User-agent: MJ12bot\nDisallow: /\n"
  expect_identical(cx_decide(body, "/x", "MJ12bot"), "allow")
  expect_identical(cx_rows(robots_validate_text(body))$message,
                   cx_read_as("MJ", cx_no_star, cx_other))
})

test_that("an empty cut matches no crawler", {
  body <- "User-agent: *\nAllow: /\n\nUser-agent: 360Spider\nDisallow: /\n"
  expect_identical(cx_decide(body, "/x", "360Spider"), "allow")
  expect_identical(cx_rows(robots_validate_text(body))$message,
                   cx_none(cx_star))
})

test_that("an agent stacked with a cut value keeps the group", {
  body <- paste0("User-agent: *\nAllow: /\n\n",
                 "User-agent: MJ12bot\nUser-agent: AhrefsBot\nDisallow: /\n")
  expect_identical(cx_decide(body, "/x", "AhrefsBot"), "disallow")
  expect_identical(cx_decide(body, "/x", "MJ12bot"), "allow")
  expect_identical(cx_rows(robots_validate_text(body))$line, 4L)
})

test_that("a crawler named correctly elsewhere follows that group", {
  body <- paste0("User-agent: Googlebot Image\nDisallow: /a\n\n",
                 "User-agent: Googlebot-Image\nDisallow: /b\n")
  expect_identical(cx_decide(body, c("/a", "/b"), "Googlebot-Image"),
                   c("allow", "disallow"))
  expect_identical(cx_decide(body, c("/a", "/b"), "Googlebot"),
                   c("disallow", "allow"))
  d <- cx_rows(robots_validate_text(body))
  expect_identical(d$line, 1L)
  expect_identical(d$severity, "warning")
})

test_that("the inheritance row names the agent as written", {
  x <- cx_text("User-agent: *", "Disallow: /account/", "",
               "User-agent: Spinn3r", "Disallow: /podcasts/")
  m <- cx_rows(x, "wildcard_disallows_not_inherited")$message
  expect_match(m, "^Spinn3r obeys only this group")
  expect_no_match(m, "Spinn ", fixed = TRUE)
})

test_that("written values sharing a cut token are each named", {
  x <- cx_text("User-agent: *", "Disallow: /account/", "",
               "User-agent: Peer39_Crawler", "Disallow: /p", "",
               "User-agent: Peer42", "Disallow: /p")
  d <- cx_rows(x)
  expect_identical(d$line, c(4L, 7L))
  m <- cx_rows(x, "wildcard_disallows_not_inherited")$message
  expect_match(m, "^Peer39_Crawler and Peer42 obey only the groups that name")
})

test_that("joined and full-block rows name the agent as written", {
  x <- cx_text("User-agent: Foo Bot", "", "User-agent: Baz", "Disallow: /")
  m <- cx_rows(x, "user_agent_joined_across_blank")$message
  expect_match(m, "`User-agent: Foo Bot` (line 1)", fixed = TRUE)
  expect_no_match(m, "`Foo`", fixed = TRUE)
  y <- cx_text("User-agent: Spinn3r", "Disallow:", "",
               "User-agent: Spinn3r", "Disallow: /")
  m <- cx_rows(y, "empty_disallow_with_full_block")$message
  expect_match(m, "If Spinn3r is meant", fixed = TRUE)
})

test_that("a repeated group names the agent as written", {
  x <- cx_text("User-agent: Googlebot", "Disallow: /a", "",
               "User-agent: googlebot", "Disallow: /b")
  m <- cx_rows(x, "user_agent_repeated_group")$message
  expect_match(m, "^`User-agent: googlebot` \\(line 4\\) names Googlebot")
})

test_that("a value that is not valid UTF-8 stays ASCII-only", {
  body <- as.raw(c(charToRaw("User-agent: *\nDisallow: /a\n\nUser-agent: B"),
                   0xe4, charToRaw("r\nDisallow: /p\n")))
  x <- robots_validate_text(body)
  d <- cx_rows(x)
  expect_identical(d$message, cx_read_as("B", cx_star, cx_other))
  m <- cx_rows(x, "wildcard_disallows_not_inherited")$message
  expect_match(m, "^B\\\\xE4r obeys only this group")
  expect_true(all(validUTF8(x$diagnostics$message)))
})

test_that("a suffix that plainly means the token is info", {
  # Review of 20707cd: these meant the Google token, so no crawler moves.
  for (value in c("Googlebot *", "Googlebot/",
                  "AdsBot-Google (+http://www.google.com/adsbot.html)")) {
    x <- cx_text(paste0("User-agent: ", value), "Disallow: /x")
    expect_identical(cx_rows(x)$severity, "info", label = value)
  }
  for (value in c("Googlebot2", "Googlebot, Bingbot")) {
    x <- cx_text(paste0("User-agent: ", value), "Disallow: /x")
    expect_identical(cx_rows(x)$severity, "warning", label = value)
  }
})

test_that("a cut line in a `*` group still gets that group", {
  body <- "User-agent: *\nUser-agent: Spinn3r\nDisallow: /a\n"
  expect_identical(cx_decide(body, "/a", "Spinn3r"), "disallow")
  m <- cx_rows(robots_validate_text(body))$message
  expect_match(m, paste0("a crawler going by the full value still gets this ",
                         "group from Google's matcher, since the group also ",
                         "names `User-agent: *`."), fixed = TRUE)
})

test_that("a repeated group names the crawler by its uncut value", {
  # Review of 20707cd: the earlier line's cut value is not the crawler.
  x <- cx_text("User-agent: Googlebot/2.1", "Disallow: /", "",
               "User-agent: googlebot", "Disallow: /a")
  m <- cx_rows(x, "user_agent_repeated_group")$message
  expect_match(m, "^`User-agent: googlebot` \\(line 4\\) names googlebot,")
  expect_no_match(m, "Googlebot/2.1", fixed = TRUE)
})
