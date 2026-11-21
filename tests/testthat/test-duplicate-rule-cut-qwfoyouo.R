# ROBO-qwfoyouo: Google's matcher cuts a User-agent value at its first
# character outside letters, `_` and `-`, so `Foo web spider` and `Foo blog`
# both name `Foo` there and their groups merge. A duplicate_rule row that
# exists only through that merge says so; a duplicate across groups naming
# the same uncut crawler keeps today's row. Fixtures are synthetic.

dc_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

dc_rows <- function(body, code = "duplicate_rule") {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == code, , drop = FALSE]
}

dc_plain <- function(first_line, type = "Disallow") {
  sprintf("Rule has no effect: line %d already has the same %s.",
          first_line, type)
}

# Three groups whose values Google reads as `Foo`, sharing two rules.
dc_cut_shape <- dc_lines(
  "User-agent: Foo web spider", "Disallow: /a", "Disallow: /b", "",
  "User-agent: Foo blog", "Disallow: /a", "Disallow: /b", "",
  "User-agent: Foo News Spider", "Disallow: /a", "Disallow: /b"
)

test_that("groups merged by a cut draw duplicate_rule rows", {
  d <- dc_rows(dc_cut_shape)
  expect_identical(d$line, c(6L, 7L, 10L, 11L))
  expect_identical(d$severity, rep("info", 4L))
})

test_that("the cut merge draws today's plain duplicate_rule text", {
  d <- dc_rows(dc_cut_shape)
  expect_identical(d$message, dc_plain(c(2L, 3L, 2L, 3L)))
})

test_that("the user_agent_cut rows do not depend on the repeated rules", {
  apart <- dc_lines(
    "User-agent: Foo web spider", "Disallow: /a", "Disallow: /b", "",
    "User-agent: Foo blog", "Disallow: /c", "Disallow: /d", "",
    "User-agent: Foo News Spider", "Disallow: /e", "Disallow: /f"
  )
  expect_identical(nrow(dc_rows(apart)), 0L)
  cut <- dc_rows(dc_cut_shape, "user_agent_cut")
  expect_identical(cut$line, c(1L, 5L, 9L))
  rownames(cut) <- NULL
  expect_identical(cut, dc_rows(apart, "user_agent_cut"))
})

test_that("a duplicate across uncut groups keeps today's text", {
  d <- dc_rows(dc_lines(
    "User-agent: Foo", "Disallow: /a", "", "User-agent: foo", "Disallow: /a"
  ))
  expect_identical(d$line, 5L)
  expect_identical(d$message, dc_plain(2L))
  # Within one group a cut value changes nothing: the line repeats there.
  d <- dc_rows(dc_lines("User-agent: Foo bar", "Disallow: /a",
                        "Disallow: /a"))
  expect_identical(d$line, 3L)
  expect_identical(d$message, dc_plain(2L))
  # The same cut value twice is the same crawler, cut or not.
  d <- dc_rows(dc_lines(
    "User-agent: Foo bar", "Disallow: /a", "", "User-agent: foo BAR",
    "Disallow: /a"
  ))
  expect_identical(d$line, 5L)
  expect_identical(d$message, dc_plain(2L))
})

test_that("a rule an uncut group already gives is a real duplicate", {
  # Line 9 repeats line 2 for `foo` with no cut, though the merge of
  # `Foo bar` into `foo` covers it too; line 5 repeats line 2 only through
  # that merge.
  d <- dc_rows(dc_lines(
    "User-agent: foo", "Disallow: /a", "", "User-agent: Foo bar",
    "Disallow: /a", "Disallow: /z", "", "User-agent: foo", "Disallow: /a"
  ))
  expect_identical(d$line, c(5L, 9L))
  expect_identical(d$message[[2L]], dc_plain(2L))
})

# The matchers, unchanged by this ticket. Each probe file has a second group
# whose value Google cuts to the first group's token and a rule only that
# group holds: `/y` is disallowed where the groups merge. The probed crawler
# token is letters only, as the Bing and Yandex backends accept only their
# own crawlers' tokens and refuse a value such as `bingbot/2.0`.
dc_probe <- function(first, second, token, backend) {
  body <- dc_lines(paste("User-agent:", first), "Disallow: /x", "",
                   paste("User-agent:", second), "Disallow: /y")
  robots_evaluate_text_v1(body, c("http://e.com/x", "http://e.com/y"),
                          token, backend, backend)$results
}

test_that("Google's matcher merges groups whose values cut to one token", {
  for (pair in list(c("Googlebot", "Googlebot/2.1"),
                    c("bingbot", "bingbot/2.0"),
                    c("Yandex", "Yandex 2.0"))) {
    x <- dc_probe(pair[[1L]], pair[[2L]], pair[[1L]], "google")
    expect_identical(x$url_decision, c("disallow", "disallow"),
                     label = toString(pair))
    expect_identical(x$matched_line, c(2L, 5L), label = toString(pair))
  }
  x <- allowed_by_robots_text(dc_cut_shape, "http://e.com/a", "Foo")
  expect_false(x$results$allowed)
  expect_identical(x$results$matched_line, 2L)
})

test_that("the Bing and Yandex matchers keep those groups apart", {
  for (second in c("bingbot/2.0", "bingbot spider", "bingbot*")) {
    x <- dc_probe("bingbot", second, "bingbot", "bing")
    expect_identical(x$url_decision, c("disallow", "allow"), label = second)
    expect_identical(x$matched_line, c(2L, NA), label = second)
  }
  for (second in c("Yandex 2.0", "Yandex/2.0", "Yandex spider")) {
    x <- dc_probe("Yandex", second, "Yandex", "yandex")
    expect_identical(x$url_decision, c("disallow", "allow"), label = second)
    expect_identical(x$matched_line, c(2L, NA), label = second)
  }
  # Neither backend evaluates a crawler going by the full cut value.
  x <- dc_probe("bingbot", "bingbot/2.0", "bingbot/2.0", "bing")
  expect_identical(x$matcher_status, rep("unsupported_profile", 2L))
  x <- dc_probe("Yandex", "Yandex 2.0", "Yandex 2.0", "yandex")
  expect_identical(x$matcher_status, rep("not_evaluated", 2L))
})
