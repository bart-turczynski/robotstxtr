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
  ),
  # Yandex reads `Disallow :` as an unknown field (design/
  # engine-disagreements.md, class 4): only the plain form takes part.
  key_blank = list(body = sr_two("Disallow: /x", "Disallow : /x"),
                   today = character(0)),
  rule_tab_colon = list(
    body = paste(sr_group("bingbot", "Disallow\t: /x"),
                 sr_group("Yandex", "Disallow\t: /x"), sep = "\n"),
    today = character(0)
  ),
  # Bing and Yandex read `Disallow foo` as unknown, not as `Disallow`.
  rule_key_word = list(
    body = paste(sr_group("Yandex", c("Disallow foo:", "Disallow: /")),
                 sr_group("bingbot", c("Disallow:", "Disallow: /")),
                 sep = "\n"),
    today = c("accepted_directive_prefix", "allow_all_disallow",
              "allow_all_disallow", "empty_disallow_with_full_block",
              "empty_disallow_with_full_block")
  ),
  rule_blank_empty = list(
    body = paste(sr_group("bingbot", c("Disallow:", "Disallow: /")),
                 sr_group("Yandex", c("Disallow :", "Disallow: /")),
                 sep = "\n"),
    today = c("allow_all_disallow", "allow_all_disallow",
              "empty_disallow_with_full_block",
              "empty_disallow_with_full_block")
  ),
  # A comment-only line inside a group is read alike everywhere.
  comment_line = list(
    body = sr_two(c("Disallow: /x", "# note", "Allow: /x/y"),
                  c("Disallow: /x", "Allow: /x/y")),
    today = character(0)
  ),
  # Google reads a longer key by its prefix `user-agent`; others may not.
  prefix_key = list(
    body = paste0(sr_group("Foo", "Disallow: /x"),
                  "\nUser-agentx: Bar\nDisallow: /x\n"),
    today = character(0)
  ),
  agent_typo = list(
    body = paste0(sr_group("Foo", "Disallow: /x"),
                  "\nUseragent: Bar\nDisallow: /x\n"),
    today = "accepted_directive_typo"
  ),
  # The parser's line buffer cuts the padded rule to `/x`.
  long_line = list(
    body = sr_two("Disallow: /x", paste0("Disallow: /x", strrep(" ", 17000L))),
    today = "line_too_long"
  ),
  # Indented User-agent lines, by a space or a tab, are read alike
  # everywhere.
  agent_indent = list(
    body = paste0(" User-agent: Foo\nDisallow: /x\n\n",
                  sr_group("Bar", "Disallow: /x")),
    today = character(0)
  ),
  agent_tab_indent = list(
    body = paste0("\tUser-agent: Foo\nDisallow: /x\n\n",
                  sr_group("Bar", "Disallow: /x")),
    today = character(0)
  ),
  # A blank before the User-agent colon, or a longer key Google reads by its
  # prefix: Yandex, or Bing and Yandex, do not read it as User-agent.
  agent_space_colon = list(
    body = paste0(sr_group("Foo", "Disallow: /x"),
                  "\nUser-agent : Bar\nDisallow: /x\n"),
    today = character(0)
  ),
  agent_tab_colon = list(
    body = paste0(sr_group("Foo", "Disallow: /x"),
                  "\nUser-agent\t: Bar\nDisallow: /x\n"),
    today = character(0)
  ),
  agent_key_word = list(
    body = paste0("User-agent foo: bingbot\nDisallow: /x\n\n",
                  sr_group("Yandex", "Disallow: /x")),
    today = character(0)
  ),
  agent_tab_word = list(
    body = paste0(sr_group("bingbot", "Disallow: /x"),
                  "\nUser-agent\tfoo: Yandex\nDisallow: /x\n"),
    today = character(0)
  ),
  # The next group starts at a line Bing or Yandex do not read as
  # User-agent, so on them the group before runs on through its rules.
  next_typo = list(
    body = paste(sr_group("Yandex", c("Disallow: /x", "Useragent: Bar",
                                      "Disallow: /y")),
                 sr_group("bingbot", "Disallow: /x"), sep = "\n"),
    today = "accepted_directive_typo"
  ),
  next_prefix = list(
    body = paste(sr_group("Yandex", c("Disallow: /x", "User-agentx: Bar",
                                      "Disallow: /y")),
                 sr_group("bingbot", "Disallow: /x"), sep = "\n"),
    today = character(0)
  ),
  next_no_colon = list(
    body = paste(sr_group("Yandex", "Disallow: /x"),
                 "User-agent Bar\nDisallow: /y\n",
                 sr_group("bingbot", "Disallow: /x"), sep = "\n"),
    today = "accepted_missing_colon"
  ),
  next_comment_value = list(
    body = paste(sr_group("bingbot", "Disallow: /x"),
                 "User-agent: # none\nDisallow: /y\n",
                 sr_group("Yandex", "Disallow: /x"), sep = "\n"),
    today = c("empty_user_agent", "rule_without_user_agent")
  ),
  # Past the parser's buffer, the next group's first line is not plain.
  next_long = list(
    body = paste(sr_group("Foo", "Disallow: /x"),
                 sr_group("Bar", "Disallow: /x"),
                 paste0("User-agent: Baz", strrep(" ", 17000L),
                        "\nDisallow: /y\n"), sep = "\n"),
    today = "line_too_long"
  ),
  # A bare key with no colon is no plain line.
  bare_key = list(body = sr_two(c("Disallow: /x", "Disallow"),
                                "Disallow: /x"),
                  today = "malformed_line"),
  next_empty = list(
    body = paste(sr_group("bingbot", "Disallow: /x"),
                 "User-agent:\nDisallow: /y\n",
                 sr_group("Yandex", "Disallow: /x"), sep = "\n"),
    today = c("empty_user_agent", "rule_without_user_agent")
  ),
  # The parser skips line 1's byte-order mark, whole or in part, but Bing
  # does not read that line as User-agent, so its group takes no part.
  bom = list(
    body = c(as.raw(c(0xef, 0xbb, 0xbf)),
             charToRaw(sr_two("Disallow: /x", "Disallow: /x"))),
    today = "byte_order_mark"
  ),
  partial_bom = list(
    body = c(as.raw(c(0xef, 0xbb)),
             charToRaw(sr_two("Disallow: /x", "Disallow: /x"))),
    today = "invalid_utf8"
  ),
  # A key holding a byte not valid in UTF-8 is not `User-agent`.
  latin1_key = list(
    body = charToRaw(paste0(sr_group("Foo", "Disallow: /x"),
                            "\nUser-agent\xe9: Bar\nDisallow: /x\n")),
    today = "invalid_utf8"
  ),
  # Two classes, the later one first by its rules: rows go by line.
  two_classes = list(
    body = paste(sr_group("Foo", "Disallow: /b"),
                 sr_group("Bar", "Disallow: /b"),
                 sr_group("Baz", "Disallow: /a"),
                 sr_group("Qux", "Disallow: /a"), sep = "\n"),
    today = character(0)
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
  overlap = c("user_agent_repeated_group", sr_code),
  comment_line = sr_code,
  agent_indent = sr_code,
  agent_tab_indent = sr_code,
  two_classes = c(sr_code, sr_code)
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
  # The stacked group shows the repeated rule once.
  expect_match(d$message[d$code == sr_code],
               "`User-agent: Bar`, then `Disallow: /a`. This is", fixed = TRUE)
})

test_that("ROBO-rdxgnqhw: rows follow their first lines", {
  d <- sr_diag(sr_fixtures$two_classes$body)
  expect_identical(d$line[d$code == sr_code], c(1L, 7L))
  expect_match(d$message[d$code == sr_code][[1L]], "then `Disallow: /b`.",
               fixed = TRUE)
})

test_that("ROBO-rdxgnqhw: a byte-order mark keeps the first group out", {
  # The fixture loop above pins `bom`, `partial_bom` and `latin1_key` in the
  # session's locale, without an error; the checks run UTF-8, C and tr_TR.
  # Bing reads bingbot's line 1 behind the mark as no User-agent line, so
  # bingbot and adidxbot do not get the same rules there.
  tail <- paste(sr_group("bingbot", "Disallow: /x"),
                sr_group("adidxbot", "Disallow: /x"), sep = "\n")
  for (mark in list(as.raw(0xef), as.raw(c(0xef, 0xbb)),
                    as.raw(c(0xef, 0xbb, 0xbf)))) {
    d <- robots_validate_text(c(mark, charToRaw(tail)))$diagnostics
    expect_false(sr_code %in% d$code)
    base <- if (length(mark) == 3L) "byte_order_mark" else "invalid_utf8"
    expect_true(base %in% d$code)
  }
  # Without the mark the same body gets the row.
  expect_identical(sr_codes(tail), sr_code)
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

# The oracle: stack a body's groups exactly as a row's message shows them,
# and every crawler must get the same decisions on Google, Bing and Yandex.
# The message's `\xHH` escapes are read back to their bytes. Groups start
# at a User-agent-like line (any spelling Google takes) after a line that
# is not one; a member's lines run to the next start. The stacked group
# goes in place of the first member, or of the last, then a blank line, and
# the other members go. The message's line numbers are Google's, so the
# body is split as Google splits it: at LF, CR LF and a lone CR. Each
# engine still reads the body as written its own way (Bing and Yandex end
# a line at LF only), so a row whose stacking a lone CR upsets shows up as
# changed decisions.
sr_lines <- function(body) {
  strsplit(body, "\r\n|\r|\n", useBytes = TRUE)[[1L]]
}

sr_agent_like <- function(lines) {
  grepl("^[ \t]*(user-agent|useragent|user agent)([^:]*:| )", lines,
        ignore.case = TRUE, useBytes = TRUE)
}

sr_unescape <- function(x) {
  bytes <- charToRaw(x)
  out <- raw()
  i <- 1L
  while (i <= length(bytes)) {
    hex <- if (i + 3L <= length(bytes)) rawToChar(bytes[i + 2:3]) else ""
    if (bytes[[i]] == as.raw(0x5c) && bytes[[i + 1L]] == as.raw(0x78) &&
          grepl("^[0-9A-Fa-f]{2}$", hex)) {
      out <- c(out, as.raw(strtoi(hex, 16L)))
      i <- i + 4L
    } else {
      out <- c(out, bytes[[i]])
      i <- i + 1L
    }
  }
  rawToChar(out)
}

sr_stack <- function(body, message, last = FALSE) {
  expect_false(grepl(" more ", message, fixed = TRUE))
  head <- sub("give their crawlers.*", "", message)
  at <- as.integer(regmatches(head, gregexpr("[0-9]+", head))[[1L]])
  stack <- sub(".*with nothing between its User-agent lines: ", "", message)
  stack <- sub("\\. This is optional cleanup.*", "", stack)
  item <- regmatches(stack, gregexpr("`[^`]*`", stack))[[1L]]
  item <- gsub("`", "", item, fixed = TRUE)
  item <- vapply(item, sr_unescape, "", USE.NAMES = FALSE)
  lines <- sr_lines(body)
  like <- sr_agent_like(lines)
  start <- which(like & !c(FALSE, like[-length(like)]))
  end <- c(start[-1L] - 1L, length(lines))
  member <- match(at, start)
  stopifnot(!anyNA(member))
  into <- member[[if (last) length(member) else 1L]]
  keep <- rep(TRUE, length(lines))
  for (m in member) keep[start[[m]]:end[[m]]] <- FALSE
  before <- seq_along(lines) < start[[into]]
  paste0(paste(c(lines[keep & before], item, "", lines[keep & !before]),
               collapse = "\n"), "\n")
}

# Every crawler named in the body (cut at the first byte outside a token),
# plus Foo and one named nowhere; every rule path in the body, with and
# without `*` and `$`, and a few longer ones.
sr_tokens <- function(body) {
  lines <- sr_lines(body)
  agent <- sr_agent_like(lines) &
    grepl(":", lines, fixed = TRUE, useBytes = TRUE)
  value <- sub("^[^:]*:", "", lines[agent], useBytes = TRUE)
  value <- sub("^[ \t]*([A-Za-z_-]*).*$", "\\1", value, useBytes = TRUE)
  unique(c(value[nzchar(value)], "Foo", "Unnamedbot"))
}

sr_urls <- function(body) {
  lines <- sr_lines(body)
  rule <- grepl(":[ \t]*/", lines, useBytes = TRUE) & !sr_agent_like(lines)
  value <- sub("^[^:]*:[ \t]*", "", lines[rule], useBytes = TRUE)
  value <- sub("[ \t]*(#.*)?$", "", value, useBytes = TRUE)
  path <- unique(c("/", "/a", "/x", "/x/y", "/y", "/z", "/X", "/x?q",
                   value, gsub("[*$]", "", value, useBytes = TRUE)))
  path <- unique(c(path, paste0(path, "x"), sprintf("%s/y", path)))
  # A byte outside printable ASCII goes as its `%XX` escape.
  enc <- vapply(path, function(p) {
    paste(vapply(charToRaw(p), function(x) {
      if (x < as.raw(0x21) || x > as.raw(0x7e)) {
        sprintf("%%%02X", as.integer(x))
      } else {
        rawToChar(x)
      }
    }, ""), collapse = "")
  }, "", USE.NAMES = FALSE)
  paste0("https://example.com", enc)
}

sr_decisions <- function(body, tokens, urls, engine) {
  url <- rep(urls, times = length(tokens))
  token <- rep(tokens, each = length(urls))
  robots_evaluate_text_v1(body, url, token, engine, engine)$results$
    url_decision
}

# For each row of `body`, and each placement, the engines whose decisions
# change; character(0) when the stacking keeps every decision.
sr_oracle <- function(body) {
  if (is.raw(body)) body <- rawToChar(body)
  d <- sr_diag(body)
  out <- character()
  tokens <- sr_tokens(body)
  urls <- sr_urls(body)
  for (msg in d$message[d$code == sr_code]) {
    for (last in c(FALSE, TRUE)) {
      stacked <- sr_stack(body, msg, last)
      for (engine in c("google", "bing", "yandex")) {
        if (!identical(sr_decisions(body, tokens, urls, engine),
                       sr_decisions(stacked, tokens, urls, engine))) {
          out <- c(out, paste(engine, if (last) "last" else "first"))
        }
      }
    }
  }
  out
}

# Review 3's probe bodies, every one stacked and compared on the engines.
sr_g <- function(agents, ...) {
  paste0(paste0(agents, "\n", collapse = ""),
         paste0(c(...), "\n", collapse = ""))
}
sr_j <- function(...) paste(c(...), collapse = "\n")
sr_probes <- list(
  owner = sr_j(sr_g("User-agent: Foo", "Disallow: /", "Allow: /x/"),
               sr_g("User-agent: Bar", "Disallow: /", "Allow: /x/"),
               sr_g("User-agent: *", "Disallow: /z")),
  blank_ua_rules = sr_j(sr_g("User-agent: Yandex", "", "Disallow: /x"),
                        sr_g("User-agent: bingbot", "Disallow: /x")),
  blank_between = sr_j(sr_g("User-agent: Yandex", "Disallow: /x", "",
                            "Disallow: /y"),
                       sr_g("User-agent: bingbot", "Disallow: /x",
                            "Disallow: /y")),
  comment_between = sr_j(sr_g("User-agent: Yandex", "Disallow: /x", "# c",
                              "Disallow: /y"),
                         sr_g("User-agent: bingbot", "Disallow: /x",
                              "Disallow: /y")),
  comment_ua_rules = sr_j(sr_g("User-agent: Yandex", "# c", "Disallow: /x"),
                          sr_g("User-agent: bingbot", "Disallow: /x")),
  between_other = sr_j(sr_g("User-agent: Yandex", "Disallow: /x"),
                       sr_g("User-agent: bingbot", "Disallow: /y"),
                       sr_g("User-agent: bingbot", "Disallow: /x")),
  after_other = sr_j(sr_g("User-agent: Yandex", "Disallow: /x"),
                     sr_g("User-agent: bingbot", "Disallow: /x"),
                     sr_g("User-agent: bingbot", "Allow: /x")),
  name_case = sr_j(sr_g("User-agent: foo", "Disallow: /x"),
                   sr_g("User-agent: FOO", "Disallow: /x"),
                   sr_g("User-agent: Bar", "Disallow: /x")),
  key_case = sr_j(sr_g("USER-AGENT: Yandex", "DISALLOW: /x"),
                  sr_g("user-agent: bingbot", "disallow: /x")),
  ua_comment = sr_j(sr_g("User-agent: Foo # hi", "Disallow: /x # c"),
                    sr_g("User-agent: Bar", "Disallow: /x")),
  yandex_family = sr_j(sr_g("User-agent: Yandex", "Disallow: /x"),
                       sr_g("User-agent: YandexBot", "Disallow: /x"),
                       sr_g("User-agent: Yandex", "Disallow: /y")),
  empty_full = sr_j(sr_g("User-agent: Yandex", "Disallow:", "Disallow: /"),
                    sr_g("User-agent: bingbot", "Disallow:", "Disallow: /")),
  empty_full_rep = sr_j(sr_g("User-agent: Yandex", "Disallow:"),
                        sr_g("User-agent: bingbot", "Disallow:"),
                        sr_g("User-agent: Yandex", "Disallow: /")),
  rule_typo = sr_j(sr_g("User-agent: Yandex", "Dissallow: /x"),
                   sr_g("User-agent: bingbot", "Dissallow: /x")),
  rule_prefix = sr_j(sr_g("User-agent: Yandex", "Disallowed: /x"),
                     sr_g("User-agent: bingbot", "Disallowed: /x")),
  latin1_val = sr_j(sr_g("User-agent: Yandex", "Disallow: /\xe9"),
                    sr_g("User-agent: bingbot", "Disallow: /\xe9")),
  utf8_val = sr_j(sr_g("User-agent: Yandex", "Disallow: /\xc3\xa9"),
                  sr_g("User-agent: bingbot", "Disallow: /\xc3\xa9")),
  crlf = gsub("\n", "\r\n", fixed = TRUE,
              sr_j(sr_g("User-agent: Yandex", "Disallow: /x"),
                   sr_g("User-agent: bingbot", "Disallow: /x"))),
  bom_comment = paste0("\xef\xbb\xbf# hi\n",
                       sr_j(sr_g("User-agent: Yandex", "Disallow: /x"),
                            sr_g("User-agent: bingbot", "Disallow: /x"))),
  bom_line1_other = paste0("\xef\xbb\xbf", sr_j(
    sr_g("User-agent: adidxbot", "Disallow: /y"),
    sr_g("User-agent: adidxbot", "Disallow: /x"),
    sr_g("User-agent: Yandex", "Disallow: /x")
  )),
  bom_line1_two = paste0("\xef\xbb\xbf", sr_j(
    sr_g(c("User-agent: Foo", "User-agent: bingbot"), "Disallow: /x"),
    sr_g("User-agent: adidxbot", "Disallow: /x")
  )),
  late_sitemap = sr_j(sr_g("User-agent: Yandex", "Disallow: /x",
                           "Sitemap: https://example.com/s.xml"),
                      sr_g("User-agent: bingbot", "Disallow: /x")),
  orphan_before = sr_j("Disallow: /y", "",
                       sr_g("User-agent: Yandex", "Disallow: /x"),
                       sr_g("User-agent: bingbot", "Disallow: /x")),
  overlap = sr_j(sr_g("User-agent: Foo", "Disallow: /"),
                 sr_g(c("User-agent: Foo", "User-agent: Bar"),
                      "Disallow: /"),
                 sr_g("User-agent: Baz", "Disallow: /")),
  val_space = sr_j(sr_g("User-agent: Yandex", "Disallow: /a b"),
                   sr_g("User-agent: bingbot", "Disallow: /a b")),
  wild = sr_j(sr_g("User-agent: Yandex", "Disallow: /*x$", "Allow: /x*"),
              sr_g("User-agent: bingbot", "Allow: /x*", "Disallow: /*x$")),
  tab_indent_colon = sr_j(sr_g("\tUser-agent : Yandex", "Disallow: /x"),
                          sr_g("User-agent: bingbot", "Disallow: /x")),
  rule_indent = sr_j(sr_g("User-agent: Yandex", " Disallow: /x"),
                     sr_g("User-agent: bingbot", "Disallow: /x")),
  typo_mid = sr_j(sr_g("User-agent: Foo", "Disallow: /x", "Useragent: Bar",
                       "Disallow: /y"),
                  sr_g("User-agent: Yandex", "Disallow: /x"),
                  sr_g("User-agent: bingbot", "Disallow: /z")),
  typo_mid_rev = sr_j(sr_g("User-agent: bingbot", "Disallow: /x",
                           "Useragent: Bar", "Disallow: /y"),
                      sr_g("User-agent: Yandex", "Disallow: /x")),
  prefix_mid_blank = sr_j(sr_g("User-agent: bingbot", "Disallow: /x"),
                          sr_g("User-agentx: Bar", "Disallow: /y"),
                          sr_g("User-agent: Yandex", "Disallow: /x")),
  typo_sp_blank = sr_j(sr_g("User-agent: bingbot", "Disallow: /x"),
                       sr_g("User agent: Bar", "Disallow: /y"),
                       sr_g("User-agent: Yandex", "Disallow: /x")),
  camel_typo = sr_j(sr_g("User-agent: bingbot", "Disallow: /x"),
                    sr_g("UserAgent: Bar", "Disallow: /y"),
                    sr_g("User-agent: Yandex", "Disallow: /x")),
  no_colon_rev = sr_j(sr_g("User-agent: bingbot", "Disallow: /x"),
                      sr_g("User-agent Bar", "Disallow: /y"),
                      sr_g("User-agent: Yandex", "Disallow: /x")),
  policy_next = sr_j(sr_g("User-agent: bingbot", "Disallow: /x"),
                     sr_g("User-agent: Google-Extended", "Disallow: /y"),
                     sr_g("User-agent: Yandex", "Disallow: /x")),
  rule_space_colon = sr_j(sr_g("User-agent: Yandex", "Disallow : /x"),
                          sr_g("User-agent: bingbot", "Disallow: /x")),
  rule_word_empty = sr_j(sr_g("User-agent: Yandex", "Disallow foo:"),
                         sr_g("User-agent: bingbot", "Disallow:")),
  rule_word_value = sr_j(sr_g("User-agent: Yandex", "Disallow foo: /x"),
                         sr_g("User-agent: bingbot", "Disallow: /x")),
  rule_word_full = sr_j(sr_g("User-agent: bingbot", "Disallow:",
                             "Disallow: /"),
                        sr_g("User-agent: Yandex", "Disallow foo:",
                             "Disallow: /")),
  rule_blank_full = sr_j(sr_g("User-agent: bingbot", "Disallow:",
                              "Disallow: /"),
                         sr_g("User-agent: Yandex", "Disallow :",
                              "Disallow: /"))
)
# Each User-agent spelling of review 3, for each crawler, first or second.
sr_shapes <- c(
  indent_sp = " User-agent: %s", indent_tab = "\tUser-agent: %s",
  sp_colon = "User-agent : %s", tab_colon = "User-agent\t: %s",
  tab_sp_colon = "\tUser-agent : %s", sp2_colon = "User-agent  : %s",
  lower = "user-agent: %s", nospace = "User-agent:%s",
  trailing = "User-agent: %s ", key_word = "User-agent foo: %s",
  key_tab_word = "User-agent\tfoo: %s"
)
for (shape in names(sr_shapes)) {
  for (who in c("Yandex", "bingbot", "Googlebot")) {
    a <- sprintf(sr_shapes[[shape]], who)
    b <- paste0("User-agent: ", if (who == "bingbot") "Yandex" else "bingbot")
    sr_probes[[paste(shape, who, 1L)]] <- sr_j(sr_g(a, "Disallow: /x"),
                                                sr_g(b, "Disallow: /x"))
    sr_probes[[paste(shape, who, 2L)]] <- sr_j(sr_g(b, "Disallow: /x"),
                                                sr_g(a, "Disallow: /x"))
  }
}

# Review 4's bodies. A CR not directly before an LF: Google ends a line
# there, Bing and Yandex do not (design/engine-disagreements.md classes 7
# and 8), so the check skips the body. A VT or FF after a User-agent value:
# Google trims it, Bing and Yandex do not. A tab-only User-agent value as a
# next group's first line: no group starts there.
sr_withheld <- list(
  cr_comment = paste0("User-agent: Yandex\nDisallow: /x\n# c\rUser-agent: ",
                      "Foo\nDisallow: /y\n\nUser-agent: bingbot\n",
                      "Disallow: /x\n"),
  cr_comment_bing = paste0("User-agent: bingbot\nDisallow: /x\n# c\r",
                           "User-agent: Foo\nDisallow: /y\n\nUser-agent: ",
                           "Yandex\nDisallow: /x\n"),
  crcrlf_rule = sr_j(sr_g("User-agent: bingbot", "Disallow: /x\r\r"),
                     sr_g("User-agent: Yandex", "Disallow: /x")),
  crcr_agent_bing = sr_j(sr_g("User-agent: bingbot\r\r", "Disallow: /x"),
                         sr_g("User-agent: Yandex", "Disallow: /x")),
  crcr_agent_yandex = sr_j(sr_g("User-agent: Yandex\r\r", "Disallow: /x"),
                           sr_g("User-agent: bingbot", "Disallow: /x")),
  all_cr = paste0("User-agent: bingbot\rDisallow: /x\r\rUser-agent: ",
                  "Yandex\rDisallow: /x\r"),
  ua_vt_bing = sr_j(sr_g("User-agent: bingbot\v", "Disallow: /x"),
                    sr_g("User-agent: Yandex", "Disallow: /x")),
  ua_ff_yandex = sr_j(sr_g("User-agent: Yandex\f", "Disallow: /x"),
                      sr_g("User-agent: bingbot", "Disallow: /x")),
  next_ua_tab = sr_j(sr_g("User-agent: bingbot", "Disallow: /x"),
                     sr_g("User-agent:\t", "Disallow: /x"),
                     sr_g("User-agent: Yandex", "Disallow: /x"))
)
# A whitespace-only line is a blank line on every engine.
sr_spaced <- list(
  space_line = sr_j(sr_g("User-agent: Yandex", "Disallow: /x", " "),
                    sr_g("User-agent: bingbot", "Disallow: /x")),
  tab_line = sr_j(sr_g("User-agent: Yandex", "\t \t", "Disallow: /x"),
                  sr_g("User-agent: bingbot", "Disallow: /x"))
)
sr_probes <- c(sr_probes, sr_withheld, sr_spaced)

test_that("ROBO-rdxgnqhw: line ends and controls other engines read keep out", {
  for (name in names(sr_withheld)) {
    expect_false(sr_code %in% sr_codes(sr_withheld[[name]]), label = name)
  }
  # A plain CR LF body still gives its row.
  expect_identical(sr_codes(sr_probes$crlf), sr_code)
  # A whitespace-only line inside a group is blank: the row stays.
  for (name in names(sr_spaced)) {
    expect_identical(sr_codes(sr_spaced[[name]]), sr_code, label = name)
  }
})

test_that("ROBO-rdxgnqhw: a body over 500,000 bytes is skipped", {
  # Yandex allows everything in a file over 500,000 bytes, and Google reads
  # only the first 512,000. Comment lines of 100 bytes pad the body.
  pad <- function(n) strrep(paste0("# ", strrep("p", 97L), "\n"), n)
  at <- function(n) {
    paste0(sr_group("Foo", "Disallow: /x"), pad(n), "\n",
           sr_group("Googlebot", "Disallow: /x"))
  }
  # 499,965 bytes: the row.
  expect_identical(nchar(at(4999L), type = "bytes"), 499965L)
  expect_identical(sr_codes(at(4999L)), sr_code)
  # 500,065 and 520,065 bytes (Googlebot's group past Google's window):
  # none.
  expect_false(sr_code %in% sr_codes(at(5000L)))
  expect_false(sr_code %in% sr_codes(at(5200L)))
})

test_that("ROBO-rdxgnqhw: stacking as the message shows keeps every decision", {
  bodies <- c(lapply(sr_fixtures, `[[`, "body"), sr_probes)
  rows <- 0L
  for (name in names(bodies)) {
    body <- bodies[[name]]
    rows <- rows + sum(sr_codes(body) == sr_code)
    expect_identical(sr_oracle(body), character(0), label = name)
  }
  # The oracle ran on real rows, not on none.
  expect_gt(rows, 40L)
})
