# ROBO-jnnnkyat: a Disallow whose pattern holds a query delimiter (`?`,
# `=` or `&`) may target URL parameters, and robots.txt controls crawling,
# not indexing. Every fixture is synthetic and minimal; the shop shapes
# mirror a public file's patterns without its host.

qi_diag <- function(body) {
  robots_validate_text(body)$diagnostics
}

qi_code <- "rule_query_crawl_not_index"

# Each fixture: a body and `today`, the codes it got before ROBO-jnnnkyat.
qi_fixtures <- list(
  # The shop shapes: a sort parameter, a parameter after a run of `*`, a
  # filter pair joined by `&`, a repeated parameter, and parameter-like
  # path text with no delimiter, which the check leaves alone.
  shop = list(
    body = paste0(
      "User-agent: *\nDisallow: /*?sort=\nDisallow: /*?*oseid=*\n",
      "Disallow: /collections/*filter*&*filter*\n",
      "Disallow: /*?*ls=*&ls=*\nDisallow: /collections/*sort_by*\n"
    ),
    today = "rule_query_parameter_position"
  ),
  no_delimiter = list(
    body = "User-agent: *\nDisallow: /collections/*sort_by*\n",
    today = character()
  ),
  allow_only = list(
    body = "User-agent: *\nAllow: /*?x=\n",
    today = "rule_query_parameter_position"
  ),
  full_url = list(
    body = "User-agent: *\nDisallow: https://ex.example/*?a=\n",
    today = "rule_missing_leading_slash"
  ),
  comment = list(
    body = "User-agent: *\nDisallow: /a#?b\n",
    today = "rule_cut_by_comment"
  ),
  empty = list(
    body = "User-agent: *\nDisallow:\n",
    today = "allow_all_disallow"
  ),
  tied = list(
    body = "User-agent: *\nDisallow: /*?x\nAllow: /*?x\n",
    today = "disallow_tied_by_allow"
  ),
  ai_training = list(
    body = "User-agent: __usage_ai-training\nDisallow: /*?x=\n",
    today = c("ai_training_preference", "rule_query_parameter_position")
  ),
  before_agent = list(
    body = "Disallow: /*?x=\nUser-agent: *\nDisallow: /p\n",
    today = "rule_without_user_agent"
  ),
  repeated = list(
    body = paste0(
      "User-agent: a\nDisallow: /*?s=\n\nUser-agent: b\nDisallow: /*?s=\n\n",
      "User-agent: a\nDisallow: /*?s=\n"
    ),
    today = c("user_agent_repeated_group", "duplicate_rule",
              rep("rule_query_parameter_position", 3L))
  ),
  seven = list(
    body = paste0("User-agent: *\n",
                  paste0("Disallow: /p", 1:7, "?a=\n", collapse = "")),
    today = rep("rule_query_parameter_position", 7L)
  ),
  coexist = list(
    body = "User-agent: *\nDisallow: /items/*?sort=\n",
    today = "rule_query_parameter_position"
  )
)

test_that("ROBO-jnnnkyat: today's codes on every fixture", {
  for (name in names(qi_fixtures)) {
    fixture <- qi_fixtures[[name]]
    d <- qi_diag(fixture$body)
    expect_identical(d$code, fixture$today, label = name)
    expect_false(qi_code %in% d$code, label = name)
  }
})
