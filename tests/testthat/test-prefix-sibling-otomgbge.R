# ROBO-otomgbge: a literal rule with no trailing `/` or `$` matches every
# path that starts with it, so `Disallow: /feed` also matches `/feeds`.
# When the same crawlers' rules also list such a sibling, with the same
# type, the row notes that the shorter rule already matches it
# (`rule_prefix_sibling`, info). Every fixture is synthetic and generic.

ps_diag <- function(body) {
  robots_validate_text(body)$diagnostics
}

ps_codes <- function(body) {
  ps_diag(body)$code
}

ps_code <- "rule_prefix_sibling"

# Each fixture: a body and `today`, the codes it got before ROBO-otomgbge.
ps_fixtures <- list(
  one = list(body = "User-agent: *\nDisallow: /feed\nDisallow: /feeds\n",
             today = character(0)),
  login = list(
    body = "User-agent: *\nDisallow: /login\nDisallow: /login.php\n",
    today = character(0)
  ),
  allow_pair = list(body = "User-agent: Foo\nAllow: /about\nAllow: /aboutx\n",
                    today = character(0)),
  # Two groups naming different crawlers: no pair.
  split_other = list(
    body = paste0("User-agent: Foo\nDisallow: /feed\n\n",
                  "User-agent: Bar\nDisallow: /feeds\n"),
    today = character(0)
  ),
  # Two groups naming the same crawler merge into one.
  split_same = list(
    body = paste0("User-agent: Foo\nDisallow: /feed\n\n",
                  "User-agent: Foo\nDisallow: /feeds\n"),
    today = "user_agent_repeated_group"
  ),
  # With line 3 left out, the Allow on line 4 decides `/feeds`.
  allow_beside = list(
    body = paste0("User-agent: *\nDisallow: /feed\nDisallow: /feeds\n",
                  "Allow: /feeds\n"),
    today = "disallow_tied_by_allow"
  ),
  # With line 3 left out, the wildcard Allow on line 4 decides `/feedsx`.
  allow_takes_over = list(
    body = paste0("User-agent: *\nDisallow: /feed\nDisallow: /feedsx\n",
                  "Allow: /fe*sx\n"),
    today = character(0)
  ),
  opposite = list(body = "User-agent: *\nDisallow: /search\nAllow: /searchx\n",
                  today = character(0)),
  sub_path = list(
    body = "User-agent: *\nDisallow: /feed\nDisallow: /feed/rss\n",
    today = character(0)
  ),
  query = list(body = "User-agent: *\nDisallow: /feed\nDisallow: /feed?x\n",
               today = "rule_query_crawl_not_index"),
  star = list(body = "User-agent: *\nDisallow: /feed\nDisallow: /feeds*\n",
              today = character(0)),
  dollar = list(body = "User-agent: *\nDisallow: /feed\nDisallow: /feeds$\n",
                today = character(0)),
  percent = list(body = "User-agent: *\nDisallow: /a\nDisallow: /a%2F\n",
                 today = character(0)),
  stem_slash = list(body = "User-agent: *\nDisallow: /x/\nDisallow: /x/y\n",
                    today = "rule_slash_split"),
  stem_dollar = list(body = "User-agent: *\nDisallow: /x$\nDisallow: /xy\n",
                     today = "rule_end_anchor_query"),
  stem_star = list(body = "User-agent: *\nDisallow: /x*\nDisallow: /xy\n",
                   today = character(0)),
  stem_query = list(body = "User-agent: *\nDisallow: /a?b\nDisallow: /a?bc\n",
                    today = "rule_query_crawl_not_index"),
  root = list(body = "User-agent: *\nDisallow: /\nDisallow: /x\n",
              today = character(0)),
  empty = list(body = "User-agent: *\nDisallow:\nDisallow: /x\n",
               today = "allow_all_disallow"),
  # The comment cut leaves `/feed`, which pairs with `/feeds`.
  comment = list(
    body = "User-agent: *\nDisallow: /feed#x\nDisallow: /feeds\n",
    today = "rule_cut_by_comment"
  ),
  ai = list(
    body = paste0("User-agent: __usage_ai-training\nDisallow: /feed\n",
                  "Disallow: /feeds\n"),
    today = "ai_training_preference"
  ),
  # Google cuts `Foo/1.0` to `Foo`, so only its merge joins the groups.
  cut_agent = list(
    body = paste0("User-agent: Foo/1.0\nDisallow: /feed\n\n",
                  "User-agent: Foo\nDisallow: /feeds\n"),
    today = c("user_agent_cut", "user_agent_repeated_group")
  ),
  # An `=` draws the crawl-not-index note (ROBO-jnnnkyat) as well.
  equals = list(body = "User-agent: *\nDisallow: /a=b\nDisallow: /a=bc\n",
                today = "rule_query_crawl_not_index"),
  seven = list(
    body = paste0("User-agent: *\nDisallow: /feed\n",
                  paste0("Disallow: /feed", letters[1:7], "\n",
                         collapse = "")),
    today = character(0)
  )
)

test_that("ROBO-otomgbge: today's codes on the sibling fixtures", {
  for (name in names(ps_fixtures)) {
    expect_identical(ps_codes(ps_fixtures[[name]]$body),
                     ps_fixtures[[name]]$today, label = name)
  }
})
