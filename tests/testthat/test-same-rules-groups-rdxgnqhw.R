# ROBO-rdxgnqhw: separate groups that give their crawlers the same rules
# could share one group, with their User-agent lines stacked (RFC 9309
# section 2.2.1). The row (`user_agent_groups_same_rules`, info) suggests
# it only where moving the lines keeps every crawler's rules on Google,
# Bing and Yandex. The crawler names are public tokens; every path is
# synthetic.

sr_diag <- function(body) {
  robots_validate_text(body)$diagnostics
}

sr_codes <- function(body) {
  sr_diag(body)$code
}

sr_code <- "user_agent_groups_same_rules"

# One group: its User-agent lines, then its rule lines.
sr_group <- function(agents, rules) {
  paste0(paste0("User-agent: ", agents, "\n", collapse = ""),
         paste0(rules, "\n", collapse = ""))
}

# The owner's example: four crawlers blocked with two exceptions, then two
# blocked with none.
sr_exceptions <- c("Disallow: /", "Allow: /creativegroup/",
                   "Allow: /advertising/")
sr_owner <- function(blocked = c("DataForSeoBot", "europarchive.org")) {
  paste(
    c(vapply(c("ClaudeBot", "cohere-training-data-crawler", "Diffbot",
               "FacebookBot"), sr_group, "", rules = sr_exceptions),
      vapply(blocked, sr_group, "", rules = "Disallow: /")),
    collapse = "\n"
  )
}

# Groups `Foo` and `Bar` with rule lines `a` and `b`, then any more text.
sr_two <- function(a, b, ...) {
  paste(sr_group("Foo", a), sr_group("Bar", b), ..., sep = "\n")
}

sr_split <- function(k) rep("rule_slash_split", k)

# Each fixture: a body and `today`, the codes it got before ROBO-rdxgnqhw.
sr_fixtures <- list(
  # `europarchive.org` is cut to `europarchive` by Google's matcher.
  owner = list(body = sr_owner(),
               today = c("user_agent_cut", sr_split(8L))),
  owner_uncut = list(body = sr_owner(c("DataForSeoBot", "Bytespider")),
                     today = sr_split(8L)),
  # Beside a `*` group each named group drops its rules.
  owner_star = list(
    body = paste(sr_group("*", "Disallow: /private/"),
                 sr_owner(c("DataForSeoBot", "Bytespider")), sep = "\n"),
    today = c("wildcard_rules_not_inherited", sr_split(9L))
  ),
  distinct = list(body = sr_two("Disallow: /x", "Disallow: /y"),
                  today = character(0)),
  allows_differ = list(body = sr_two(c("Disallow: /", "Allow: /a/"),
                                     "Disallow: /"),
                       today = "rule_slash_split"),
  order = list(body = sr_two(c("Disallow: /a", "Allow: /b"),
                             c("Allow: /b", "Disallow: /a")),
               today = character(0)),
  repeat_in_group = list(body = sr_two(c("Disallow: /a", "Disallow: /a"),
                                       "Disallow: /a"),
                         today = "duplicate_rule"),
  # Key case and blanks around the value are read alike everywhere.
  spacing = list(body = sr_two("Disallow: /a", "disallow:/a "),
                 today = character(0)),
  stacked = list(body = sr_group(c("Foo", "Bar"), "Disallow: /"),
                 today = character(0)),
  star_suffix = list(body = sr_two("Disallow: /x", "Disallow: /x*"),
                     today = character(0)),
  escape = list(body = sr_two("Disallow: /%7Ea", "Disallow: /~a"),
                today = "rule_escaped_unreserved"),
  empty_member = list(body = sr_two(c("Disallow:", "Disallow: /x"),
                                    "Disallow: /x"),
                      today = "allow_all_disallow"),
  both_empty = list(body = sr_two("Disallow:", "Disallow:"),
                    today = c("allow_all_disallow", "allow_all_disallow")),
  crawl_delay = list(body = sr_two(c("Disallow: /x", "Crawl-delay: 10"),
                                   "Disallow: /x"),
                     today = "unsupported_directive"),
  clean_param = list(body = sr_two(c("Clean-param: ref /x", "Disallow: /x"),
                                   "Disallow: /x"),
                     today = "unsupported_directive"),
  unknown = list(body = sr_two(c("Disallow: /x", "Foo-field: 1"),
                               "Disallow: /x"),
                 today = "unknown_directive"),
  sitemap_inside = list(
    body = sr_two(c("Disallow: /x", "Sitemap: https://example.com/s.xml",
                    "Allow: /x/y"),
                  c("Disallow: /x", "Allow: /x/y")),
    today = character(0)
  ),
  sitemap_after = list(
    body = sr_two("Disallow: /x", "Disallow: /x",
                  "Sitemap: https://example.com/s.xml\n"),
    today = character(0)
  ),
  missing_colon = list(body = sr_two("Disallow /x", "Disallow /x"),
                       today = c("accepted_missing_colon",
                                 "accepted_missing_colon")),
  typo = list(body = sr_two("Dissallow: /x", "Disallow: /x"),
              today = "accepted_directive_typo"),
  repeated_only = list(
    body = paste(sr_group("Foo", "Disallow: /x"),
                 sr_group("Foo", "Disallow: /x"), sep = "\n"),
    today = c("user_agent_repeated_group", "duplicate_rule")
  ),
  repeated_with_other = list(
    body = paste(sr_group("Foo", "Disallow: /x"),
                 sr_group("Bar", "Disallow: /x"),
                 sr_group("Foo", "Disallow: /x"), sep = "\n"),
    today = c("user_agent_repeated_group", "duplicate_rule")
  ),
  repeated_elsewhere = list(
    body = paste(sr_group("Foo", "Disallow: /x"),
                 sr_group("Bar", "Disallow: /x"),
                 sr_group("Foo", "Allow: /x/y"), sep = "\n"),
    today = "user_agent_repeated_group"
  ),
  overlap = list(
    body = paste(sr_group("Foo", "Disallow: /"),
                 sr_group(c("Foo", "Bar"), "Disallow: /"), sep = "\n"),
    today = "user_agent_repeated_group"
  ),
  star_equal = list(
    body = paste(sr_group("*", "Disallow: /x"),
                 sr_group("Foo", "Disallow: /x"), sep = "\n"),
    today = character(0)
  ),
  joined_blank = list(
    body = paste0("User-agent: Foo\n\nUser-agent: Bar\nDisallow: /x\n\n",
                  sr_group("Baz", "Disallow: /x")),
    today = "user_agent_joined_across_blank"
  ),
  ai_token = list(
    body = paste(sr_group("__usage_ai-training", "Disallow: /"),
                 sr_group("Foo", "Disallow: /"), sep = "\n"),
    today = "ai_training_preference"
  ),
  empty_agent = list(
    body = paste(sr_group("", "Disallow: /x"),
                 sr_group("Foo", "Disallow: /x"), sep = "\n"),
    today = c("empty_user_agent", "rule_without_user_agent")
  ),
  cut_agent = list(
    body = paste(sr_group("Foo/1.0", "Disallow: /x"),
                 sr_group("Bar", "Disallow: /x"), sep = "\n"),
    today = "user_agent_cut"
  ),
  case_twins = list(
    body = paste(sr_group("Foo", "Disallow: /x"),
                 sr_group("foo", "Disallow: /x"), sep = "\n"),
    today = c("user_agent_repeated_group", "duplicate_rule")
  )
)

# The fixtures that gain the row, with their codes now; every other one
# keeps `today`. The row comes right after the repeated-group rows.
sr_want <- list(
  owner = c("user_agent_cut", sr_code, sr_split(8L)),
  owner_uncut = c(sr_code, sr_code, sr_split(8L)),
  owner_star = c(sr_code, sr_code, "wildcard_rules_not_inherited",
                 sr_split(9L)),
  order = sr_code,
  repeat_in_group = c(sr_code, "duplicate_rule"),
  spacing = sr_code,
  both_empty = c("allow_all_disallow", "allow_all_disallow", sr_code),
  sitemap_after = sr_code,
  repeated_with_other = c("user_agent_repeated_group", sr_code,
                          "duplicate_rule"),
  repeated_elsewhere = c("user_agent_repeated_group", sr_code),
  overlap = c("user_agent_repeated_group", sr_code)
)

test_that("ROBO-rdxgnqhw: the row is the only code the fixtures gain", {
  for (name in names(sr_fixtures)) {
    want <- if (is.null(sr_want[[name]])) {
      sr_fixtures[[name]]$today
    } else {
      sr_want[[name]]
    }
    expect_identical(sr_codes(sr_fixtures[[name]]$body), want, label = name)
    expect_identical(want[want != sr_code], sr_fixtures[[name]]$today,
                     label = name)
  }
})

test_that("ROBO-rdxgnqhw: the owner's example gives one row per rule set", {
  # Uncut names: the four with exceptions, then the two blocked outright.
  body <- sr_owner(c("DataForSeoBot", "Bytespider"))
  d <- sr_diag(body)
  d <- d[d$code == sr_code, , drop = FALSE]
  expect_identical(d$line, c(1L, 21L))
  expect_identical(d$severity, c("info", "info"))
  expect_identical(d$directive, c("user-agent", "user-agent"))
  expect_identical(d$raw_text, c("User-agent: ClaudeBot",
                                 "User-agent: DataForSeoBot"))
  expect_identical(d$message[[1L]], paste0(
    "The group at line 1 and the groups at lines 6, 11 and 16 give their ",
    "crawlers the same rules, as written. Consecutive User-agent lines ",
    "share one group (RFC 9309 section 2.2.1), and Google, Bing and Yandex ",
    "read each User-agent line the same wherever it stands, so these groups ",
    "could be one, with nothing between its User-agent lines: ",
    "`User-agent: ClaudeBot`, `User-agent: cohere-training-data-crawler`, ",
    "`User-agent: Diffbot` and `User-agent: FacebookBot`, then ",
    "`Disallow: /`, `Allow: /creativegroup/` and `Allow: /advertising/`. ",
    "This is optional cleanup; each crawler keeps the same rules."
  ))
  # The blocked-only pair is never folded into the exceptions' group.
  expect_false(grepl("DataForSeoBot|Bytespider", d$message[[1L]]))
  expect_match(d$message[[2L]], paste0(
    "The group at line 21 and the group at line 24 .*`User-agent: ",
    "DataForSeoBot` and `User-agent: Bytespider`, then `Disallow: /`\\."
  ))
  expect_false(grepl("creativegroup|ClaudeBot", d$message[[2L]]))
  expect_identical(robots_validate_text(body)$documents$validation_status,
                   "valid")

  # As the owner wrote it, Google cuts `europarchive.org` to `europarchive`
  # (its user_agent_cut row): that group takes no part, so DataForSeoBot's
  # group is alone and only the first row is left.
  d <- sr_diag(sr_owner())
  expect_identical(d$line[d$code == sr_code], 1L)

  # Beside a `*` group the named groups still share their rules.
  d <- sr_diag(sr_fixtures$owner_star$body)
  expect_identical(d$line[d$code == sr_code], c(4L, 24L))
})

test_that("ROBO-rdxgnqhw: a crawler named in two groups is stacked once", {
  d <- sr_diag(sr_fixtures$overlap$body)
  msg <- d$message[d$code == sr_code]
  expect_match(msg, "lines: `User-agent: Foo` and `User-agent: Bar`, then ",
               fixed = TRUE)
  # The repeated-group row keeps its meaning.
  expect_identical(d$line[d$code == "user_agent_repeated_group"], 4L)
  d <- sr_diag(sr_fixtures$repeated_with_other$body)
  expect_identical(d$line[d$code == "user_agent_repeated_group"], 7L)
  expect_identical(d$line[d$code == sr_code], 1L)
  expect_match(d$message[d$code == sr_code], "groups at lines 4 and 7")
  # An exact repeat inside a group is still duplicate_rule's.
  d <- sr_diag(sr_fixtures$repeat_in_group$body)
  expect_identical(d$line[d$code == "duplicate_rule"], 3L)
})

test_that("ROBO-rdxgnqhw: thousands of equal groups give one bounded row", {
  names <- paste0("Bot", apply(expand.grid(letters, letters, letters), 1,
                               paste, collapse = "")[1:2000])
  body <- paste(vapply(names, sr_group, "",
                       rules = c("Disallow: /", paste0("Allow: /a", 1:7))),
                collapse = "\n")
  d <- sr_diag(body)
  msg <- d$message[d$code == sr_code]
  expect_length(msg, 1L)
  expect_match(msg, "groups at lines 11, 21, 31, 41, 51 and 1994 more groups",
               fixed = TRUE)
  expect_match(msg, paste0("`User-agent: Boteaa` and 1995 more User-agent ",
                           "lines, then `Disallow: /`"), fixed = TRUE)
  expect_match(msg, "`Allow: /a4` and 3 more rules.", fixed = TRUE)
  expect_lt(nchar(msg), 1000L)
})

test_that("ROBO-rdxgnqhw: rules are compared as written, bytes exactly", {
  # The same non-ASCII byte in both groups: equal, and the message is ASCII.
  same <- charToRaw(sr_two("Disallow: /\xe9", "Disallow: /\xe9"))
  d <- robots_validate_text(same)$diagnostics
  msg <- d$message[d$code == sr_code]
  expect_length(msg, 1L)
  expect_match(msg, "`Disallow: /\\xE9`", fixed = TRUE)
  expect_false(grepl("[^ -~]", msg, useBytes = TRUE))
  # Two different bytes: not equal.
  other <- charToRaw(sr_two("Disallow: /\xe9", "Disallow: /\xe8"))
  d <- robots_validate_text(other)$diagnostics
  expect_false(sr_code %in% d$code)
  # A `#` cuts both rules to the same value, as every engine reads it.
  d <- sr_diag(sr_two("Disallow: /a # one", "Disallow: /a # two"))
  expect_identical(d$line[d$code == sr_code], 1L)
})

test_that("ROBO-rdxgnqhw: a NUL a rule hides keeps its group out", {
  # Google ends the line at the NUL; Bing and Yandex read past it.
  nul <- c(charToRaw("User-agent: Foo\nDisallow: /a"), as.raw(0L),
           charToRaw("b\n\nUser-agent: Bar\nDisallow: /a\n"))
  d <- robots_validate_text(nul)$diagnostics
  expect_false(sr_code %in% d$code)
  # A NUL inside a comment hides nothing.
  quiet <- c(charToRaw("User-agent: Foo\nDisallow: /a # x"), as.raw(0L),
             charToRaw("\n\nUser-agent: Bar\nDisallow: /a\n"))
  d <- robots_validate_text(quiet)$diagnostics
  expect_identical(d$line[d$code == sr_code], 1L)
})

test_that("ROBO-rdxgnqhw: a cut body is skipped", {
  body <- charToRaw(sr_two("Disallow: /x", "Disallow: /x"))
  x <- validate_document_bytes(body, "s", "supplied", max_bytes = 40L,
                               body_truncated = TRUE)
  expect_false(sr_code %in% x$diagnostics$code)
  x <- validate_document_bytes(body, "s", "supplied")
  expect_identical(x$diagnostics$line[x$diagnostics$code == sr_code], 1L)
})

test_that("ROBO-rdxgnqhw: robots_validate_url() gives the same row", {
  body <- sr_owner(c("DataForSeoBot", "Bytespider"))
  local_fake_ssrfr(function(req) {
    fake_response(200L, url = req$url, body = body)
  })
  x <- robots_validate_url("https://e.example/page")
  d <- x$diagnostics
  want <- sr_diag(body)
  expect_identical(d$code, want$code)
  expect_identical(d$message[d$code == sr_code],
                   want$message[want$code == sr_code])
  expect_identical(d$raw_text[d$code == sr_code],
                   c("User-agent: ClaudeBot", "User-agent: DataForSeoBot"))
  expect_identical(x$documents$validation_status, "valid")
})
