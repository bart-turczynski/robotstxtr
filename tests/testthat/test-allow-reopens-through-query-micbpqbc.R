# ROBO-micbpqbc: an Allow that opens with `*` or `/*` and then names a path
# (`*/x/`) also matches inside a URL's query, so it can allow a URL with a
# query (`/c?q=/x/`) while a Disallow blocks the URL without it (`/c`)
# (`allow_reopens_through_query`, info). Every fixture is synthetic, and
# every control and witness is cross-checked on the Google, Bing and Yandex
# backends.

ar_diag <- function(body) {
  robots_validate_text(body)$diagnostics
}

ar_codes <- function(body) {
  ar_diag(body)$code
}

ar_code <- "allow_reopens_through_query"

# Each fixture: a body (`%s` stands for the crawler token, so the backends
# can read it) and `today`, the codes it got before ROBO-micbpqbc. A bare
# `Disallow: /my/` also gets rule_slash_split: it blocks `/my/` and leaves
# `/my` allowed.
ar_split <- "rule_slash_split"
ar_fixtures <- list(
  positive = list(
    body = "User-agent: %s\nDisallow: /my/\nAllow: */sitemap_output/\n",
    today = ar_split
  ),
  global = list(
    body = "User-agent: *\nDisallow: /my/\nAllow: */sitemap_output/\n",
    today = ar_split
  ),
  slash_led = list(
    body = "User-agent: %s\nDisallow: /my/\nAllow: /*/sitemap_output/\n",
    today = ar_split
  ),
  stars = list(body = "User-agent: %s\nDisallow: /my\nAllow: /**/x$\n",
               today = character(0)),
  star_dollar = list(body = "User-agent: %s\nDisallow: /my\nAllow: */x/$\n",
                     today = character(0)),
  wild_disallow = list(
    body = "User-agent: %s\nDisallow: /*/my/\nAllow: */sitemap_output/\n",
    today = character(0)
  ),
  # Two shape-A Allows that each reopen `/my/`: the longer one also
  # matches the shorter one's witness.
  cause_short = list(
    body = "User-agent: %s\nDisallow: /my/\nAllow: */output/\n",
    today = ar_split
  ),
  two_cause = list(
    body = paste0("User-agent: %s\nDisallow: /my/\n",
                  "Allow: */sitemap_output/\nAllow: */output/\n"),
    today = ar_split
  ),
  # An Allow of another shape opens the witness too: removing the shape-A
  # Allow leaves it open, so the shape-A Allow is not the cause.
  non_a_opener = list(
    body = paste0("User-agent: %s\nDisallow: /my/\n",
                  "Allow: */sitemap_output/\nAllow: /my/?\n"),
    today = ar_split
  ),
  # A longer Disallow that is no control decides the control.
  decider = list(
    body = paste0("User-agent: %s\nDisallow: /my/\nDisallow: /my/$\n",
                  "Allow: */sitemap_output/\n"),
    today = character(0)
  ),
  # Three Disallows that fail (a longer Disallow covers the witness, an
  # Allow wins the control, a query Disallow covers the witness) and a
  # fourth that proves.
  fourth = list(
    body = paste0("User-agent: %s\nDisallow: /a/\nDisallow: /b/\n",
                  "Disallow: /c/\nDisallow: /d/\n",
                  "Disallow: /a/*sitemap_output/\nAllow: /b/\n",
                  "Disallow: /c/?q=/sitemap_output/\n",
                  "Allow: */sitemap_output/\n"),
    today = c("disallow_tied_by_allow", "rule_query_parameter_position",
              ar_split)
  ),
  # Google ranks by pattern length and an Allow wins a tie.
  tie = list(body = "User-agent: %s\nDisallow: /abc/\nAllow: */ss/\n",
             today = ar_split),
  shorter = list(body = "User-agent: %s\nDisallow: /abc/\nAllow: */s/\n",
                 today = ar_split),
  # Negatives.
  longer_cover = list(
    body = paste0("User-agent: %s\nDisallow: /my/\n",
                  "Disallow: /my/*sitemap_output\n",
                  "Allow: */sitemap_output/\n"),
    today = ar_split
  ),
  cross_group = list(
    body = paste0("User-agent: %s\nDisallow: /my/\n\n",
                  "User-agent: Other\nAllow: */sitemap_output/\n"),
    today = ar_split
  ),
  star_group = list(
    body = paste0("User-agent: *\nDisallow: /my/\n\n",
                  "User-agent: %s\nAllow: */sitemap_output/\n"),
    today = c("wildcard_disallows_not_inherited", ar_split)
  ),
  prefixed = list(body = "User-agent: %s\nDisallow: /my/\nAllow: /my/*x\n",
                  today = ar_split),
  slash_star = list(body = "User-agent: %s\nDisallow: /x\nAllow: /*/\n",
                    today = character(0)),
  slash_star_dollar = list(
    body = "User-agent: %s\nDisallow: /x\nAllow: /*/$\n",
    today = character(0)
  ),
  css = list(body = "User-agent: %s\nDisallow: /my/\nAllow: /*.css\n",
             today = ar_split),
  shape_b = list(body = "User-agent: %s\nDisallow: /my/\nAllow: *?next=\n",
                 today = c("rule_query_parameter_position", ar_split)),
  query_disallow = list(
    body = "User-agent: %s\nDisallow: /my/?\nAllow: */s/\n",
    today = character(0)
  ),
  dollar_disallow = list(
    body = "User-agent: %s\nDisallow: /my/$\nAllow: */s/\n",
    today = "rule_end_anchor_query"
  ),
  dot_disallow = list(body = "User-agent: %s\nDisallow: /a/./\nAllow: */s/\n",
                      today = "rule_dot_segment"),
  dot_allow = list(body = "User-agent: %s\nDisallow: /my/\nAllow: */./s/\n",
                   today = ar_split),
  dot_escaped_allow = list(
    body = "User-agent: %s\nDisallow: /my/\nAllow: */%2E%2E/s/\n",
    today = c("rule_escaped_unreserved", ar_split)
  ),
  stray_disallow = list(
    body = "User-agent: %s\nDisallow: /a%4/\nAllow: */s/\n",
    today = "rule_invalid_percent_escape"
  ),
  stray_allow = list(
    body = "User-agent: %s\nDisallow: /my/\nAllow: */s%4/\n",
    today = c("rule_invalid_percent_escape", ar_split)
  ),
  ai = list(
    body = "User-agent: __usage_ai-training\nDisallow: /my/\nAllow: */s/\n",
    today = "ai_training_preference"
  ),
  ai_anchor = list(
    body = paste0("User-agent: __usage_ai-training\nUser-agent: %s\n",
                  "Disallow: /my/\nAllow: */s/\n"),
    today = c("ai_training_preference", ar_split)
  ),
  # AdsBot-Google ignores the `*` group and is judged on its own rules.
  adsbot = list(
    body = paste0("User-agent: *\nDisallow: /my/\nAllow: */s/\n\n",
                  "User-agent: AdsBot-Google\nDisallow: /my/\n"),
    today = c("wildcard_rules_not_inherited", ar_split, ar_split)
  ),
  repeated = list(
    body = paste0("User-agent: %s\nDisallow: /my/\nAllow: */a/\n\n",
                  "User-agent: %s\nAllow: */b/\n"),
    today = c("user_agent_repeated_group", ar_split)
  ),
  seven = list(
    body = paste0("User-agent: %s\nDisallow: /my/\n",
                  paste0("Allow: */", letters[1:7], "x/\n", collapse = "")),
    today = ar_split
  ),
  two_crawlers = list(
    body = paste0("User-agent: %s\nUser-agent: Bar\nDisallow: /my/\n",
                  "Allow: */sx/\n"),
    today = ar_split
  ),
  # Also rule_query_parameter_position's: both rows stand.
  overlap = list(body = "User-agent: %s\nDisallow: /my/\nAllow: */x?p=\n",
                 today = c("rule_query_parameter_position", ar_split)),
  empty_allow = list(body = "User-agent: %s\nDisallow: /my/\nAllow:\n",
                     today = c("empty_rule_value", ar_split))
)

ar_body <- function(name, token = "Foo") {
  gsub("%s", token, ar_fixtures[[name]]$body, fixed = TRUE)
}

test_that("ROBO-micbpqbc: today's codes on every candidate shape and skip", {
  for (name in names(ar_fixtures)) {
    codes <- ar_codes(ar_body(name))
    expect_identical(codes[codes != ar_code], ar_fixtures[[name]]$today,
                     label = name)
  }
})

# The crossing check: how each backend decides the control, the witness
# and, where given, another path. Default `url_normalization` ("rfc3986"):
# the paths hold no dot segment, so it removes nothing.
ar_engines <- list(google = "Googlebot", bing = "bingbot", yandex = "Yandex")

ar_decide <- function(body, paths, backend) {
  token <- ar_engines[[backend]]
  robots_evaluate_text_v1(
    gsub("%s", token, body, fixed = TRUE),
    paste0("https://example.com", paths), token, backend, backend
  )$results$url_decision
}

# Fixture (or body), the paths and the decisions every backend gives them,
# with any backend that decides otherwise.
ar_opened <- c("disallow", "allow")
ar_closed <- c("disallow", "disallow")
ar_decisions <- list(
  # The witness written with its slashes escaped is no match for the
  # Allow: only the query that holds the path as written reopens.
  list("positive", c("/my/", "/my/?q=/sitemap_output/",
                     "/my/?next=%2Fsitemap_output%2F"),
       c(ar_opened, "disallow")),
  list("slash_led", c("/my/", "/my/?q=/sitemap_output/"), ar_opened),
  list("stars", c("/my", "/my?q=/x"), ar_opened),
  list("star_dollar", c("/my", "/my?q=/x/"), ar_opened),
  list("wild_disallow", c("/x/my/", "/x/my/?q=/sitemap_output/"), ar_opened),
  list("two_cause", c("/my/", "/my/?q=/sitemap_output/", "/my/?q=/output/"),
       c(ar_opened, "allow")),
  list("non_a_opener", c("/my/", "/my/?q=/sitemap_output/"), ar_opened),
  list("decider", c("/my/", "/my/?q=/sitemap_output/"), ar_opened),
  list("fourth", c("/a/", "/a/?q=/sitemap_output/", "/b/", "/c/",
                   "/c/?q=/sitemap_output/", "/d/", "/d/?q=/sitemap_output/"),
       c(ar_closed, "allow", ar_closed, ar_opened)),
  # A backend disagreement: the package's Yandex matcher does not let the
  # Allow win a tie of pattern lengths here. The check decides on Google's
  # matcher.
  list("tie", c("/abc/", "/abc/?q=/ss/"), ar_opened,
       list(yandex = ar_closed)),
  list("seven", c("/my/", "/my/?q=/gx/"), ar_opened),
  list("shorter", c("/abc/", "/abc/?q=/s/"), ar_closed),
  list("longer_cover", c("/my/", "/my/?q=/sitemap_output/"), ar_closed),
  list("overlap", c("/my/", "/my/?q=/x?p="), ar_opened),
  # The removal reads: with the shape-A Allow gone, the witness is blocked,
  # unless an Allow of another shape opens it.
  list(body = "User-agent: %s\nDisallow: /my/\n",
       c("/my/", "/my/?q=/sitemap_output/"), ar_closed),
  list(body = "User-agent: %s\nDisallow: /my/\nAllow: /my/?\n",
       c("/my/", "/my/?q=/sitemap_output/"), ar_opened)
)

test_that("ROBO-micbpqbc: every backend decides the control and witness", {
  for (backend in names(ar_engines)) {
    for (case in ar_decisions) {
      body <- if (is.null(names(case)) || !nzchar(names(case)[[1L]])) {
        ar_fixtures[[case[[1L]]]]$body
      } else {
        case[[1L]]
      }
      expected <- case[[3L]]
      if (length(case) > 3L && !is.null(case[[4L]][[backend]])) {
        expected <- case[[4L]][[backend]]
      }
      expect_identical(ar_decide(body, case[[2L]], backend), expected,
                       label = paste(backend, case[[2L]][[2L]]))
    }
  }
})
