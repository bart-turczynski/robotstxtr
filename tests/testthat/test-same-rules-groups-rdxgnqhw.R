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

test_that("ROBO-rdxgnqhw: today's codes on the same-rules fixtures", {
  for (name in names(sr_fixtures)) {
    expect_identical(sr_codes(sr_fixtures[[name]]$body),
                     sr_fixtures[[name]]$today, label = name)
  }
})
