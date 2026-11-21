# ROBO-wnuttuit: a User-agent line that repeats a name already in its own
# group, in any case, changes nothing (RFC 9309 section 2.2.1). The bodies
# are synthetic. These pins fix what the validator says today; the code that
# reports the repeat follows in its own commit.

dg_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

# The codes the validator gives the lines in `line`.
dg_codes <- function(body, line) {
  d <- robots_validate_text(body)$diagnostics
  d$code[d$line %in% line]
}

test_that("a case-only repeat in one group draws no row today", {
  body <- dg_lines("User-agent: Acme-Bot", "User-agent: acme-bot",
                   "Disallow: /a")
  expect_identical(dg_codes(body, 2L), character())
})

test_that("an exact repeat in one group draws no row today", {
  body <- dg_lines("User-agent: Acme-Bot", "User-agent: Acme-Bot",
                   "Disallow: /a")
  expect_identical(dg_codes(body, 2L), character())
})

test_that("a `*` repeated in one group draws no row today", {
  body <- dg_lines("User-agent: *", "User-agent: *", "Disallow: /a")
  expect_identical(dg_codes(body, 2L), character())
})

test_that("three case pairs in one group draw no rows today", {
  body <- dg_lines("User-agent: Alpha", "User-agent: alpha",
                   "User-agent: Beta", "User-agent: beta",
                   "User-agent: Gamma", "User-agent: gamma",
                   "Disallow: /a")
  expect_identical(dg_codes(body, c(2L, 4L, 6L)), character())
})

test_that("a policy-token repeat draws only its preference row today", {
  body <- dg_lines("User-agent: __usage_ai-training",
                   "User-agent: __usage_ai-training", "Disallow: /a")
  expect_identical(dg_codes(body, 2L), character())
  expect_identical(dg_codes(body, 1L), "ai_training_preference")
})

test_that("a cut value beside its token draws no repeat row today", {
  body <- dg_lines("User-agent: Foo Bot", "User-agent: foo", "Disallow: /a")
  expect_identical(dg_codes(body, 2L), character())
  expect_identical(dg_codes(body, 1L), "user_agent_cut")
})

test_that("a repeat of a cut line draws only the cut row today", {
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

test_that("a repeat in one group and in an earlier one draws the group row", {
  body <- dg_lines("User-agent: FooBot", "Disallow: /a", "",
                   "User-agent: Bar", "User-agent: foobot",
                   "User-agent: FOOBOT", "Disallow: /b")
  expect_identical(dg_codes(body, 5L), "user_agent_repeated_group")
  expect_identical(dg_codes(body, 6L), character())
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
