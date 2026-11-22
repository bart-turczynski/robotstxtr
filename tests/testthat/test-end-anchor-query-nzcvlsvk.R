# ROBO-nzcvlsvk: a Disallow whose pattern ends in `$` and holds no `?`
# blocks its path but not the same path with a query added, since the `$`
# ends the match at the end of the path and query together
# (`rule_end_anchor_query`, info). Every fixture is synthetic, and every
# control and witness is cross-checked on the Google, Bing and Yandex
# backends.

ea_diag <- function(body) {
  robots_validate_text(body)$diagnostics
}

ea_codes <- function(body) {
  ea_diag(body)$code
}

ea_code <- "rule_end_anchor_query"

# One rule line under the crawler token `%s`.
ea_one <- function(value) {
  paste0("User-agent: %s\nDisallow: ", value, "\n")
}

# Each fixture: a body (`%s` stands for the crawler token, so the backends
# can read it) and `today`, the codes it got before ROBO-nzcvlsvk.
ea_fixtures <- list(
  positive = list(
    body = paste0("User-agent: %s\nDisallow: /@me$\nDisallow: /*/edit$\n",
                  "Disallow: /*/*/edit$\n"),
    today = character(0)
  ),
  one = list(body = ea_one("/x/edit$"), today = character(0)),
  home = list(body = ea_one("/$"), today = character(0)),
  star_led = list(body = ea_one("*/edit$"), today = character(0)),
  slash_end = list(body = ea_one("/x/$"), today = character(0)),
  escaped_dollar = list(body = ea_one("/a%24$"), today = character(0)),
  two_crawlers = list(
    body = "User-agent: %s\nUser-agent: Bar\nDisallow: /a$\n",
    today = character(0)
  ),
  shorter_allow = list(
    body = "User-agent: %s\nDisallow: /@me$\nAllow: /@me\n",
    today = character(0)
  ),
  # A second rule blocks the query variant.
  query_blocked = list(
    body = "User-agent: %s\nDisallow: /@me$\nDisallow: /@me?\n",
    today = character(0)
  ),
  star_query_blocked = list(
    body = "User-agent: %s\nDisallow: /@me$\nDisallow: /*?\n",
    today = character(0)
  ),
  # An Allow already permits the control: a tie, and a longer Allow.
  tie = list(
    body = "User-agent: %s\nDisallow: /@me$\nAllow: /@me$\n",
    today = "disallow_tied_by_allow"
  ),
  longer_allow = list(
    body = "User-agent: %s\nDisallow: /@me$\nAllow: /@*me*\n",
    today = character(0)
  ),
  # An internal or literal `$`, and a `$` that is no last byte.
  inner = list(body = ea_one("/a$b"), today = "rule_inner_dollar"),
  double = list(body = ea_one("/a$$"), today = "rule_inner_dollar"),
  escaped_only = list(body = ea_one("/a%24"), today = character(0)),
  # Query-bearing patterns are out of scope.
  query_value = list(body = ea_one("/search?q$"), today = character(0)),
  query_param = list(body = ea_one("/search?q=1$"), today = character(0)),
  # A `*` right before the `$` matches every extension: the `$` anchors
  # nothing.
  star_end = list(body = ea_one("/*$"), today = character(0)),
  bare_star_end = list(body = ea_one("*$"), today = character(0)),
  word_star_end = list(body = ea_one("/a*$"), today = character(0)),
  # URL normalization removes a dot segment from the control.
  dot = list(body = ea_one("/a/.$"), today = "rule_dot_segment"),
  dot_dot = list(body = ea_one("/a/..$"), today = "rule_dot_segment"),
  dot_escaped = list(body = ea_one("/a/%2E$"),
                     today = "rule_escaped_unreserved"),
  dot_star = list(body = ea_one("/*/../x$"), today = character(0)),
  empty = list(body = "User-agent: %s\nDisallow:\n",
               today = "allow_all_disallow"),
  no_lead = list(body = ea_one("x$"), today = "rule_missing_leading_slash"),
  dollar_only = list(body = ea_one("$"),
                     today = "rule_missing_leading_slash"),
  # An end-anchored Allow (ROBO-xcojrook's shape) is not this check's.
  allow_dollar = list(body = "User-agent: %s\nDisallow: /\nAllow: /x$\n",
                      today = character(0)),
  ai = list(body = "User-agent: __usage_ai-training\nDisallow: /x$\n",
            today = "ai_training_preference"),
  ai_anchor = list(
    body = "User-agent: __usage_ai-training\nUser-agent: %s\nDisallow: /x$\n",
    today = "ai_training_preference"
  ),
  repeated = list(
    body = "User-agent: %s\nDisallow: /a$\n\nUser-agent: %s\nDisallow: /b$\n",
    today = "user_agent_repeated_group"
  ),
  seven = list(
    body = paste0("User-agent: %s\n",
                  paste0("Disallow: /", letters[1:7], "$\n", collapse = "")),
    today = character(0)
  ),
  two_sets = list(
    body = "User-agent: *\nDisallow: /a$\n\nUser-agent: %s\nDisallow: /b$\n",
    today = "wildcard_disallows_not_inherited"
  ),
  class_disagree = list(
    body = paste0("User-agent: A\nUser-agent: B\nDisallow: /a$\n\n",
                  "User-agent: B\nDisallow: /a?\n"),
    today = "user_agent_repeated_group"
  ),
  cut_uncut_fails = list(
    body = paste0("User-agent: Foo web\nDisallow: /a$\nDisallow: /a?\n\n",
                  "User-agent: Foo blog\nAllow: /a?x\n"),
    today = c("user_agent_cut", "user_agent_cut")
  ),
  cut_google_fails = list(
    body = paste0("User-agent: Foo web\nDisallow: /a$\n\n",
                  "User-agent: Foo blog\nDisallow: /a?\n"),
    today = c("user_agent_cut", "user_agent_cut")
  ),
  cut_both = list(
    body = paste0("User-agent: Foo web\nDisallow: /a$\n\n",
                  "User-agent: Foo blog\nDisallow: /b\n"),
    today = c("user_agent_cut", "user_agent_cut")
  ),
  dup = list(body = "User-agent: %s\nDisallow: /a$\nDisallow: /a$\n",
             today = "duplicate_rule"),
  lower = list(body = ea_one("/c%2f$"), today = "rule_lowercase_escape")
)

ea_body <- function(name, token = "Foo") {
  gsub("%s", token, ea_fixtures[[name]]$body, fixed = TRUE)
}

test_that("ROBO-nzcvlsvk: today's codes on every candidate shape and skip", {
  for (name in names(ea_fixtures)) {
    codes <- ea_codes(ea_body(name))
    expect_identical(codes[codes != ea_code], ea_fixtures[[name]]$today,
                     label = name)
  }
})

test_that("ROBO-nzcvlsvk: before the check, no fixture gets the row", {
  for (name in names(ea_fixtures)) {
    expect_false(ea_code %in% ea_codes(ea_body(name)), label = name)
  }
})

# A body cut at max_bytes, whose cut line could have blocked the witness.
ea_cut_text <- paste0("User-agent: *\nDisallow: /a$\nDisallow: /later-",
                      strrep("x", 200L), "\n")

test_that("ROBO-nzcvlsvk: today's codes on a cut body and a NUL body", {
  body <- charToRaw(ea_cut_text)[seq_len(40L)]
  x <- validate_document_bytes(body, "s", "supplied", max_bytes = 40L,
                               body_truncated = TRUE)
  expect_identical(x$diagnostics$code, "body_truncated")
  x <- validate_document_bytes(body, "s", "supplied")
  expect_identical(x$diagnostics$code, character(0))
  nul <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0),
           charToRaw("zz\nDisallow: /b$\n"))
  expect_identical(ea_codes(nul), c("nul_byte", "rule_cut_by_nul"))
})
