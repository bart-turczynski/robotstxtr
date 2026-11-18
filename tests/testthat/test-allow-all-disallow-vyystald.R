# ROBO-vyystald: an empty Disallow is the allow-all idiom (robotstxt.org's
# original standard; RFC 9309 section 2.2 admits an empty pattern), so it is
# the info code allow_all_disallow, not an empty_rule_value warning. In a
# named group the message adds that the named crawlers follow this group,
# merged with any other group naming them, and not `User-agent: *` (RFC 9309
# section 2.2.1). An empty Allow and a value a NUL empties stay warnings.

av_codes <- function(x) {
  d <- x$diagnostics
  paste0(d$code, "@", d$line)
}

av_text <- function(...) robots_validate_text(paste0(paste(..., sep = "\n"),
                                                     "\n"))

av_plain <- paste0("An empty Disallow value adds no restriction; the ",
                   "group's other rules still apply.")
av_named <- paste0(av_plain, " The crawlers this group names follow it, ",
                   "merged with any other group naming them, and not the ",
                   "`User-agent: *` group.")

av_row <- function(x, line) {
  d <- x$diagnostics
  found <- d[d$code == "allow_all_disallow", , drop = FALSE]
  expect_identical(found$line, line)
  expect_identical(found$severity, "info")
  expect_identical(found$directive, "disallow")
  found
}

test_that("the textbook allow-all file is valid, with one info row", {
  x <- av_text("User-agent: *", "Disallow:")
  expect_identical(av_codes(x), "allow_all_disallow@2")
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(av_row(x, 2L)$message, av_plain)
})

test_that("a named group's empty Disallow says it leaves `*`", {
  x <- av_text("User-agent: X", "Disallow:", "",
               "User-agent: *", "Disallow: /p")
  expect_identical(av_codes(x), "allow_all_disallow@2")
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(av_row(x, 2L)$message, av_named)
})

av_named_alone <- paste0(av_plain, " The crawlers this group names follow ",
                         "it, merged with any other group naming them.")

test_that("only a group that names a crawler and not `*` gets the note", {
  # Stacked with `*`, the group is the `*` group itself (review, minor).
  x <- av_text("User-agent: *", "User-agent: X", "Disallow:")
  expect_identical(av_row(x, 3L)$message, av_plain)
  # `*` then whitespace is the global group, as Google reads it.
  x <- av_text("User-agent: * foo", "Disallow:")
  expect_identical(av_row(x, 2L)$message, av_plain)
  # A value Google reads as no crawler names none (user_agent_cut says so).
  for (agent in c("*bot", "/")) {
    x <- av_text(paste0("User-agent: ", agent), "Disallow:", "",
                 "User-agent: *", "Disallow: /p")
    expect_identical(av_row(x, 2L)$message, av_plain, label = agent)
  }
})

test_that("with no `*` group the note names none", {
  x <- av_text("User-agent: GPTBot", "Disallow:")
  expect_identical(av_row(x, 2L)$message, av_named_alone)
  expect_identical(x$documents$validation_status, "valid")
})

test_that("the next group starts unnamed again", {
  x <- av_text("User-agent: X", "Disallow: /a", "",
               "User-agent: *", "Disallow:")
  expect_identical(av_row(x, 5L)$message, av_plain)
})

test_that("an empty Allow keeps the empty_rule_value warning", {
  x <- av_text("User-agent: *", "Allow:", "Disallow: /p")
  expect_identical(av_codes(x), "empty_rule_value@2")
  expect_identical(x$documents$validation_status, "warning")
  # The empty Allow still ends the User-agent run: X gets its own group.
  y <- av_text("User-agent: X", "Allow:", "User-agent: *", "Disallow: /p")
  expect_true("empty_rule_value" %in% y$diagnostics$code)
  expect_identical(y$documents$validation_status, "warning")
})

test_that("a Disallow a NUL empties keeps the warning", {
  nul <- as.raw(0)
  cases <- list(
    "NUL alone" = c(charToRaw("User-agent: *\nDisallow:"), nul,
                    charToRaw("\n")),
    "blank then NUL" = c(charToRaw("User-agent: *\nDisallow:  "), nul,
                         charToRaw("\n")),
    "NUL hides a path" = c(charToRaw("User-agent: *\nDisallow: "), nul,
                           charToRaw("/private\n"))
  )
  for (case in names(cases)) {
    x <- robots_validate_text(cases[[case]])
    expect_identical(av_codes(x), c("nul_byte@2", "empty_rule_value@2"),
                     label = case)
  }
})

test_that("blank and comment-only values are empty Disallows too", {
  for (line in c("Disallow:   ", "Disallow:\t", "Disallow: # x",
                 "disallow:")) {
    x <- av_text("User-agent: *", line)
    expect_identical(av_codes(x), "allow_all_disallow@2", label = line)
  }
})

test_that("next to a non-empty Disallow, no other report changes", {
  x <- av_text("User-agent: *", "Disallow:", "Disallow: /p")
  expect_identical(av_codes(x), "allow_all_disallow@2")
  x <- av_text("User-agent: *", "Disallow:", "Disallow:")
  expect_identical(av_codes(x),
                   c("allow_all_disallow@2", "allow_all_disallow@3"))
})

test_that("repeated named groups keep their own reports", {
  x <- av_text("User-agent: X", "Disallow:", "",
               "User-agent: X", "Disallow: /p")
  expect_setequal(av_codes(x), c("allow_all_disallow@2",
                                 "user_agent_repeated_group@4"))
  expect_identical(x$documents$validation_status, "valid")
  # The Yoast-plus-full-block split still warns.
  y <- av_text("User-agent: *", "Disallow:", "",
               "User-agent: *", "Disallow: /")
  expect_true(all(c("allow_all_disallow", "empty_disallow_with_full_block",
                    "user_agent_repeated_group") %in% y$diagnostics$code))
  expect_identical(y$documents$validation_status, "warning")
})

test_that("a Mediapartners-Google allow-all group draws no warning", {
  # The shape of theguardian.com/robots.txt lines 59-60 (fetched 2026-11-17)
  # and Blogger's default: AdSense's crawler gets full access.
  x <- av_text("User-agent: *", "Disallow: /sendarticle", "",
               "User-agent: Mediapartners-Google", "Disallow:")
  expect_identical(av_codes(x), "allow_all_disallow@5")
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(av_row(x, 5L)$message, av_named)
})

test_that("an empty Disallow outside any group keeps the warning", {
  x <- av_text("Disallow:", "User-agent: *", "Disallow: /p")
  expect_identical(
    av_codes(x), c("rule_without_user_agent@1", "empty_rule_value@1")
  )
  # After a rule, an empty User-agent opens no group either.
  y <- av_text("User-agent: *", "Disallow: /p", "User-agent:", "Disallow:")
  expect_true(all(c("empty_user_agent@3", "rule_without_user_agent@4",
                    "empty_rule_value@4") %in% av_codes(y)))
})
