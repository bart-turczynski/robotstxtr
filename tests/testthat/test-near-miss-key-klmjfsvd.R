# ROBO-klmjfsvd: an unknown key that is a near miss of `User-agent`, `Allow`
# or `Disallow` (a small edit distance, a stray leading non-letter, or
# `Deny`) is ignored by every engine. Fixtures are synthetic.

nm_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")
nm_text <- function(...) robots_validate_text(nm_lines(...))
nm_rows <- function(x, code = "unknown_directive") {
  d <- x$diagnostics
  d[d$code == code, , drop = FALSE]
}
nm_plain <- "Directive is not recognized by this validation profile."

# One "decision line" string per backend, for one path on example.com: each
# backend answers for its own crawler token (as dg_outcome() does).
nm_outcome <- function(body, path, google_token = "ExampleBot") {
  url <- paste0("https://example.com", path)
  run <- function(backend, token) {
    r <- robots_evaluate_text_v1(body, url, token, "google", backend)$results
    paste(r$url_decision, r$matched_line)
  }
  c(google = run("google", google_token), bing = run("bing", "bingbot"),
    yandex = run("yandex", "Yandex"))
}

nm_ticket <- nm_lines("User-agent: *", "Disallow: /tmp/", "",
                      "User-agnet: ExampleBot", "Disallow: /")

# Keys within range, by the directive they resemble.
nm_near <- list(
  "User-agnet" = "user-agent", "USER-AGNET" = "user-agent",
  "Usr-agent" = "user-agent", "User--agent" = "user-agent",
  "user_agent" = "user-agent", "Usr-agnt" = "user-agent",
  "Allwo" = "allow", "Alow" = "allow", "//Allow" = "allow",
  "Disaloow" = "disallow", "DISALLOOW" = "disallow", "Disallw" = "disallow",
  "Dsalow" = "disallow", "/Disallow" = "disallow",
  "///Disallow" = "disallow", "Deny" = "disallow", "DENY" = "disallow"
)

test_that("the backends ignore a near-miss User-agent line after a rule", {
  # The ticket's example: line 5 joins the `*` group on every backend.
  expect_identical(
    nm_outcome(nm_ticket, "/page"),
    c(google = "disallow 5", bing = "disallow 5", yandex = "disallow 5")
  )
})

test_that("the backends leave rules after a near miss at the start ungrouped", {
  body <- nm_lines("User-agnet: ExampleBot", "Disallow: /", "",
                   "User-agent: *", "Disallow: /tmp/")
  expect_identical(
    nm_outcome(body, "/page"),
    c(google = "allow NA", bing = "allow NA", yandex = "allow NA")
  )
})

test_that("the backends keep a stacked run when a rule follows a near miss", {
  body <- nm_lines("User-agent: ExampleBot", "User-agent: bingbot",
                   "User-agent: Yandex", "User-agnet: Other", "Disallow: /")
  expect_identical(
    nm_outcome(body, "/page"),
    c(google = "disallow 5", bing = "disallow 5", yandex = "disallow 5")
  )
})

test_that("bing alone ends a stacked run at a near miss before User-agent", {
  body <- nm_lines("User-agent: ExampleBot", "User-agent: bingbot",
                   "User-agent: Yandex", "User-agnet: Other",
                   "User-agent: Other", "Disallow: /")
  expect_identical(
    nm_outcome(body, "/page"),
    c(google = "disallow 6", bing = "allow NA", yandex = "disallow 6")
  )
})

test_that("the backends apply no near-miss rule", {
  for (key in c("Disaloow", "Deny", "Disallw", "Alow")) {
    body <- nm_lines("User-agent: *", "Disallow: /tmp/", paste0(key, ": /"))
    expect_identical(
      nm_outcome(body, "/page"),
      c(google = "allow NA", bing = "allow NA", yandex = "allow NA"),
      info = key
    )
  }
})

test_that("a near-miss key keeps unknown_directive as its only key row", {
  for (key in names(nm_near)) {
    x <- nm_text("User-agent: *", "Disallow: /tmp/", paste0(key, ": /x"))
    row <- nm_rows(x)
    expect_identical(row$line, 3L, label = key)
    expect_identical(row$severity, "warning", label = key)
    expect_identical(row$directive, ascii_lower(key), label = key)
    expect_false(any(c("accepted_directive_typo", "accepted_directive_prefix")
                     %in% x$diagnostics$code), label = key)
  }
})

test_that("today a near-miss key gets the plain message", {
  x <- robots_validate_text(nm_ticket)
  expect_identical(nm_rows(x)$line, 4L)
  expect_identical(nm_rows(x)$message, nm_plain)
  for (key in names(nm_near)) {
    x <- nm_text("User-agent: *", "Disallow: /tmp/", paste0(key, ": /x"))
    expect_identical(nm_rows(x)$message, nm_plain, label = key)
  }
})

test_that("accepted typos and prefix keys get no unknown_directive row", {
  for (key in c("Dissallow", "Useragent", "Disalow", "Dissalow", "Diasllow")) {
    x <- nm_text("User-agent: *", paste0(key, ": /x"))
    expect_identical(nrow(nm_rows(x)), 0L, label = key)
    expect_true("accepted_directive_typo" %in% x$diagnostics$code,
                label = key)
  }
  for (key in c("Allows", "Disallowed", "User-agents")) {
    x <- nm_text("User-agent: *", paste0(key, ": /x"))
    expect_identical(nrow(nm_rows(x)), 0L, label = key)
  }
})

test_that("keys out of range keep the plain message", {
  # Alwo is two edits from allow (bound 1); Dsalw three from disallow and
  # Usr-agt three from user-agent (bound 2); Below and Follow are two from
  # allow; Foo, Agent and Denyall resemble none.
  for (key in c("Foo", "Alwo", "Dsalw", "Usr-agt", "Denyall", "Agent",
                "Below", "Follow")) {
    x <- nm_text("User-agent: *", "Disallow: /tmp/", paste0(key, ": 1"))
    expect_identical(nm_rows(x)$message, nm_plain, label = key)
  }
})

test_that("non-ASCII keys are left to other checks", {
  # A misplaced BOM (ROBO-atkmqcov owns the line), a look-alike
  # (ROBO-wtixhwlo), an invisible character and invalid UTF-8.
  x <- robots_validate_text(
    "User-agent: a\nDisallow: /x\n﻿User-agnet: b\n"
  )
  expect_identical(nm_rows(x)$message, nm_plain)
  x <- nm_text("User-agent: *", "Disаllow: /x")
  expect_true(startsWith(nm_rows(x)$message, paste0(nm_plain, " ")))
  expect_false(grepl("resembles", nm_rows(x)$message, fixed = TRUE))
  x <- nm_text("User-agent: *", "​Disallow: /x")
  expect_identical(nm_rows(x)$message, nm_plain)
  x <- robots_validate_text("User-agent: *\nDis\xffallow: /x\n")
  expect_identical(nm_rows(x)$message, nm_plain)
})
