# ROBO-nvzzjubl: Shopify's default robots.txt writes each rule with an
# escaped `+` twice, as `%2B` and `%2b`. Google and Bing upper-case a
# pattern's escapes, so the `%2b` line is the same rule as the `%2B` line,
# and a URL written with `%2b` matches neither. A line whose group already
# has the rule in upper case gets the info code rule_lowercase_escape_twin,
# naming that line, instead of the rule_lowercase_escape warning, and
# neither line of the pair gets a duplicate_rule row. The package's Yandex
# matcher compares the pattern as written (ROBO-kormmfyg).

tw_codes <- function(x) {
  d <- x$diagnostics
  paste0(d$code, "@", d$line)
}

tw_text <- function(...) robots_validate_text(paste0(paste(..., sep = "\n"),
                                                     "\n"))

tw_message <- function(escape, twin) {
  sprintf(paste0(
    "Line %d has this rule with the escape in upper case. Google and Bing ",
    "upper-case the escape '%s' in a pattern, so there this line is the ",
    "same rule as line %d, and a URL written with '%s' matches neither. The ",
    "package's Yandex matcher compares the pattern as written, so there ",
    "this line ",
    "matches URLs written with '%s', which line %d does not."
  ), twin, escape, twin, escape, escape, twin)
}

test_that("the matchers read the twin as the message says", {
  urls <- c("https://example.com/c/a%2Bb", "https://example.com/c/a%2bb",
            "https://example.com/c/a+b")
  decide <- function(value, backend, token, ruleset) {
    robots_evaluate_text_v1(
      robots_txt = paste0("User-agent: *\nDisallow: ", value, "\n"),
      url = urls, robots_product_token = token,
      robots_policy_ruleset = ruleset, matcher_backend = backend
    )$results$url_decision
  }
  same <- c("disallow", "allow", "allow")
  for (value in c("/c/*%2b*", "/c/*%2B*")) {
    expect_identical(decide(value, "google", "FooBot", "google"), same,
                     label = value)
    expect_identical(
      decide(value, "bing", "bingbot", "assumed_rfc9309"), same,
      label = value
    )
  }
  expect_identical(decide("/c/*%2B*", "yandex", "Yandex", "assumed_rfc9309"),
                   same)
  expect_identical(decide("/c/*%2b*", "yandex", "Yandex", "assumed_rfc9309"),
                   c("allow", "disallow", "allow"))
})

test_that("a lower-case twin after the upper-case rule is one info row", {
  x <- tw_text("User-agent: *", "Disallow: /c/*%2B*", "Disallow: /c/*%2b*")
  expect_identical(tw_codes(x), "rule_lowercase_escape_twin@3")
  d <- x$diagnostics
  expect_identical(d$severity, "info")
  expect_identical(d$directive, "disallow")
  expect_identical(d$message, tw_message("%2b", 2L))
  expect_identical(x$documents$validation_status, "valid")
})

test_that("a twin before the upper-case rule names the later line", {
  x <- tw_text("User-agent: *", "Allow: /c/*%2b*", "Allow: /c/*%2B*")
  expect_identical(tw_codes(x), "rule_lowercase_escape_twin@2")
  expect_identical(x$diagnostics$message, tw_message("%2b", 3L))
  expect_identical(x$diagnostics$directive, "allow")
})

test_that("a mixed %3d/%3f line names both escapes", {
  x <- tw_text("User-agent: *", "Disallow: /*?*ls%3D*%3Fls%3D*",
               "Disallow: /*?*ls%3d*%3fls%3d*")
  # The `?` also draws the crawl-not-index note (ROBO-jnnnkyat).
  expect_identical(tw_codes(x), c("rule_lowercase_escape_twin@3",
                                  "rule_query_crawl_not_index@2"))
  expect_identical(x$diagnostics$message[[1L]], paste0(
    "Line 2 has this rule with the escapes in upper case. Google and Bing ",
    "upper-case the escapes '%3d', '%3f' in a pattern, so there this line ",
    "is the same rule as line 2, and a URL written with these lower-case ",
    "escapes matches neither. The package's Yandex matcher compares the ",
    "pattern as written, so there this line matches URLs written with them, ",
    "which ",
    "line 2 does not."
  ))
})

test_that("a twin only partly upper-case is no twin", {
  # Both lines hold a lower-case escape: no line writes the rule right.
  x <- tw_text("User-agent: *", "Disallow: /*%3D*%3f", "Disallow: /*%3d*%3F")
  expect_identical(
    tw_codes(x),
    c("rule_lowercase_escape@2", "rule_lowercase_escape@3",
      "duplicate_rule@3")
  )
})

test_that("a lone lower-case rule keeps the warning", {
  x <- tw_text("User-agent: *", "Disallow: /c/*%2b*")
  expect_identical(tw_codes(x), "rule_lowercase_escape@2")
  expect_identical(x$documents$validation_status, "warning")
})

test_that("a twin in another group is no twin", {
  x <- tw_text("User-agent: a", "Disallow: /c/*%2B*", "",
               "User-agent: b", "Disallow: /c/*%2b*")
  expect_identical(tw_codes(x), "rule_lowercase_escape@5")
  # The same crawler in two groups: still no twin, the groups are apart.
  y <- tw_text("User-agent: a", "Disallow: /c/*%2B*", "",
               "User-agent: a", "Disallow: /c/*%2b*")
  expect_true("rule_lowercase_escape@5" %in% tw_codes(y))
  expect_false("rule_lowercase_escape_twin" %in% y$diagnostics$code)
})

test_that("a different type or value is no twin", {
  x <- tw_text("User-agent: *", "Allow: /c/*%2B*", "Disallow: /c/*%2b*")
  expect_true("rule_lowercase_escape@3" %in% tw_codes(x))
  x <- tw_text("User-agent: *", "Disallow: /c/*%2B", "Disallow: /c/*%2b*")
  expect_identical(tw_codes(x), "rule_lowercase_escape@3")
})

test_that("duplicate_rule keeps its other rows", {
  # Two identical upper-case lines are still duplicate_rule; the twin row
  # names the first one.
  x <- tw_text("User-agent: *", "Disallow: /c/*%2B*", "Disallow: /c/*%2B*",
               "Disallow: /c/*%2b*")
  expect_identical(tw_codes(x),
                   c("rule_lowercase_escape_twin@4", "duplicate_rule@3"))
  expect_identical(x$diagnostics$message[[1L]], tw_message("%2b", 2L))
  # Two identical lower-case lines are a lower-case rule written twice.
  y <- tw_text("User-agent: *", "Disallow: /c/*%2b*", "Disallow: /c/*%2b*")
  expect_identical(
    tw_codes(y),
    c("rule_lowercase_escape@2", "rule_lowercase_escape@3",
      "duplicate_rule@3")
  )
})

test_that("the Shopify shape draws no lower-case warning", {
  # Shopify's default robots.txt.liquid, as served by Shopify stores
  # (gymshark.com/robots.txt, fetched 2026-11-18), shortened.
  x <- tw_text(
    "User-agent: *",
    "Disallow: /collections/*sort_by*",
    "Disallow: /*/collections/*sort_by*",
    "Disallow: /collections/*+*",
    "Disallow: /collections/*%2B*",
    "Disallow: /collections/*%2b*",
    "Disallow: /*/collections/*+*",
    "Disallow: /*/collections/*%2B*",
    "Disallow: /*/collections/*%2b*",
    "Disallow: /*/collections/*filter*&*filter*",
    "Disallow: /blogs/*+*",
    "Disallow: /blogs/*%2B*",
    "Disallow: /blogs/*%2b*",
    "Disallow: /*?*ls=*&ls=*",
    "Disallow: /*?*ls%3D*%3Fls%3D*",
    "Disallow: /*?*ls%3d*%3fls%3d*"
  )
  # Line 10's `&` also draws the crawl-not-index note (ROBO-jnnnkyat).
  expect_identical(
    tw_codes(x),
    c(paste0("rule_lowercase_escape_twin@", c(6L, 9L, 13L, 16L)),
      "rule_query_crawl_not_index@10")
  )
  expect_identical(x$documents$validation_status, "valid")
})

test_that("a twin is neither a duplicate nor the rule a duplicate repeats", {
  # Review of c05347a, major: a merged group's real duplicate still counts.
  x <- tw_text("User-agent: a", "Disallow: /%2B", "",
               "User-agent: a", "Disallow: /%2b", "Disallow: /%2B")
  expect_identical(
    tw_codes(x),
    c("rule_lowercase_escape_twin@5", "user_agent_repeated_group@4",
      "duplicate_rule@6")
  )
  d <- x$diagnostics
  expect_identical(d$message[d$code == "duplicate_rule"],
                   "Rule has no effect: line 2 already has the same Disallow.")
  # The duplicate names the upper-case line it repeats, not the twin.
  y <- tw_text("User-agent: *", "Disallow: /%2b", "Disallow: /%2B",
               "Disallow: /%2B")
  expect_identical(tw_codes(y),
                   c("rule_lowercase_escape_twin@2", "duplicate_rule@4"))
  expect_identical(y$diagnostics$message[[2L]],
                   "Rule has no effect: line 3 already has the same Disallow.")
})

test_that("a raw byte is not an upper-case escape", {
  # `/é` canonicalizes to `/%C3%A9` but spells no escape.
  x <- tw_text("User-agent: *", "Disallow: /é", "Disallow: /%C3%a9")
  expect_true("rule_lowercase_escape@3" %in% tw_codes(x))
  expect_false("rule_lowercase_escape_twin" %in% x$diagnostics$code)
})

test_that("a line holding a NUL is no twin", {
  # Google cuts at the NUL; Bing reads it as a byte, so the rules differ.
  bytes <- c(charToRaw("User-agent: *\nDisallow: /%2B\nDisallow: /%2b"),
             as.raw(0), charToRaw("x\n"))
  x <- robots_validate_text(bytes)
  expect_true("rule_lowercase_escape@3" %in% tw_codes(x))
  expect_false("rule_lowercase_escape_twin" %in% x$diagnostics$code)
})

test_that("a pattern that never matches is no twin", {
  x <- tw_text("User-agent: *", "Disallow: x%2B", "Disallow: x%2b")
  expect_true("rule_lowercase_escape@3" %in% tw_codes(x))
  expect_false("rule_lowercase_escape_twin" %in% x$diagnostics$code)
})
