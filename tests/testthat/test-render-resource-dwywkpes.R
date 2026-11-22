# ROBO-dwywkpes: a Disallow whose pattern ends in a file type a page may
# load (`.js`, `.mjs`, `.cjs`, `.css`, `.json`, `.wasm`) can block the
# scripts, styles and data a page needs to show its content
# (`rule_render_resource_blocked`, info). Every fixture is synthetic and
# generic, and the witnesses are cross-checked on the Google, Bing and
# Yandex backends.

rr_diag <- function(body) {
  robots_validate_text(body)$diagnostics
}

rr_codes <- function(body) {
  rr_diag(body)$code
}

rr_code <- "rule_render_resource_blocked"

# Each fixture: a body (`%s` stands for the crawler token, so the backends
# can read it) and `today`, the codes it got before ROBO-dwywkpes.
rr_fixtures <- list(
  # Three rules in `*`, one in a group of a crawler that ignores `*`, and
  # a named group with no such rule.
  shop = list(
    body = paste0(
      "User-agent: *\nDisallow: /assets/app/*.js\nDisallow: /basket.js\n",
      "Disallow: /*/basket.js\n\nUser-agent: AdsBot-Google\n",
      "Disallow: /assets/app/*.js\n\nUser-agent: Googlebot\n",
      "Disallow: /private\n"
    ),
    today = c("wildcard_rules_not_inherited",
              "wildcard_disallows_not_inherited")
  ),
  one = list(body = "User-agent: %s\nDisallow: /*.js\n",
             today = character(0)),
  global = list(body = "User-agent: *\nDisallow: /*.css\n",
                today = character(0)),
  # The witness `/x.js` lies outside `/assets/`.
  allow_outside = list(
    body = "User-agent: %s\nDisallow: /*.js\nAllow: /assets/*.js\n",
    today = character(0)
  ),
  # A tie of pattern lengths goes to the Allow.
  allow_tie = list(body = "User-agent: %s\nDisallow: /*.js\nAllow: /*.js\n",
                   today = "disallow_tied_by_allow"),
  # A broader rule already blocks the witness.
  root = list(body = "User-agent: %s\nDisallow: /\nDisallow: /*.js\n",
              today = character(0)),
  folder = list(
    body = "User-agent: %s\nDisallow: /assets/\nDisallow: /assets/*.js\n",
    today = "rule_slash_split"
  ),
  # Two candidates, neither covering the other's witness.
  two_kinds = list(
    body = "User-agent: %s\nDisallow: /*.js\nDisallow: /assets/*.css\n",
    today = character(0)
  ),
  # An Allow that wins the first filler's witness: `y` is tried next.
  filler = list(body = "User-agent: %s\nDisallow: /*.js\nAllow: /x.js\n",
                today = character(0)),
  filler_all = list(
    body = paste0("User-agent: %s\nDisallow: /*.js\nAllow: /x.js\n",
                  "Allow: /y.js\nAllow: /z.js\n"),
    today = character(0)
  ),
  star_tail = list(body = "User-agent: %s\nDisallow: /*.css*\n",
                   today = character(0)),
  query = list(body = "User-agent: %s\nDisallow: /a.json?v=*\n",
               today = "rule_query_parameter_position"),
  # Also rule_end_anchor_query's: both rows stand.
  anchored = list(body = "User-agent: %s\nDisallow: /*.js$\n",
                  today = "rule_end_anchor_query"),
  comment = list(body = "User-agent: %s\nDisallow: /a.js#x\n",
                 today = "rule_cut_by_comment"),
  repeated = list(
    body = paste0("User-agent: %s\nDisallow: /a.js\n\n",
                  "User-agent: %s\nDisallow: /b.js\n"),
    today = "user_agent_repeated_group"
  ),
  identical = list(
    body = "User-agent: %s\nDisallow: /a.js\nDisallow: /a.js\n",
    today = "duplicate_rule"
  ),
  two_crawlers = list(
    body = "User-agent: %s\nUser-agent: Bar\nDisallow: /a/*.mjs\n",
    today = character(0)
  ),
  ai = list(body = "User-agent: __usage_ai-training\nDisallow: /a.js\n",
            today = "ai_training_preference"),
  ai_anchor = list(
    body = paste0("User-agent: __usage_ai-training\nUser-agent: %s\n",
                  "Disallow: /a.js\n"),
    today = "ai_training_preference"
  ),
  avalanche = list(
    body = paste0("User-agent: %s\n",
                  paste0("Disallow: /d", 1:50, "/*.js\n", collapse = "")),
    today = character(0)
  ),
  # Negatives.
  js_folder = list(body = "User-agent: %s\nDisallow: /js/\n",
                   today = "rule_slash_split"),
  json_folder = list(body = "User-agent: %s\nDisallow: /json-api/\n",
                     today = "rule_slash_split"),
  jsp = list(body = "User-agent: %s\nDisallow: /a.jsp\n",
             today = character(0)),
  inner = list(body = "User-agent: %s\nDisallow: /x.json/y\n",
               today = character(0)),
  ext_folder = list(body = "User-agent: %s\nDisallow: /*.js/\n",
                    today = character(0)),
  font = list(body = "User-agent: %s\nDisallow: /*.woff2\n",
              today = character(0)),
  source_map = list(body = "User-agent: %s\nDisallow: /*.js.map\n",
                    today = character(0)),
  allow_only = list(body = "User-agent: %s\nAllow: /*.css\n",
                    today = character(0)),
  slash = list(body = "User-agent: %s\nDisallow: /\n",
               today = character(0)),
  empty = list(body = "User-agent: %s\nDisallow:\n",
               today = "allow_all_disallow"),
  full_url = list(
    body = "User-agent: %s\nDisallow: https://e.example/a.js\n",
    today = "rule_missing_leading_slash"
  ),
  dot = list(body = "User-agent: %s\nDisallow: /a/./b.js\n",
             today = "rule_dot_segment"),
  stray = list(body = "User-agent: %s\nDisallow: /a%4/b.js\n",
               today = "rule_invalid_percent_escape")
)

rr_fill <- function(body, token = "Foo") {
  gsub("%s", token, body, fixed = TRUE)
}

rr_body <- function(name, token = "Foo") {
  rr_fill(rr_fixtures[[name]]$body, token)
}

# The recognition set: each listed file type bare, with `$`, `*`, `*$` and
# `?*`, and in upper case.
rr_types <- c("js", "mjs", "cjs", "css", "json", "wasm")
rr_suffixes <- c("", "$", "*", "*$", "?*")
rr_positive <- c(
  as.vector(outer(paste0("/*.", rr_types), rr_suffixes, paste0)),
  paste0("/A.", toupper(rr_types)), "/cart.js", "/*/cart.js",
  "/a.json?v=*", "*.css"
)

test_that("ROBO-dwywkpes: today's codes on every candidate shape and skip", {
  for (name in names(rr_fixtures)) {
    codes <- rr_codes(rr_body(name))
    expect_identical(codes[codes != rr_code], rr_fixtures[[name]]$today,
                     label = name)
  }
  # Each recognized value alone: only rule_end_anchor_query, on a final
  # `$` with no `*` before it, and rule_query_parameter_position on a
  # `?name=`.
  for (value in rr_positive) {
    codes <- rr_codes(sprintf("User-agent: Foo\nDisallow: %s\n", value))
    today <- character(0)
    if (grepl("[^*][$]$", value)) {
      today <- "rule_end_anchor_query"
    }
    if (grepl("?v=", value, fixed = TRUE)) {
      today <- "rule_query_parameter_position"
    }
    expect_identical(codes[codes != rr_code], today, label = value)
  }
})

# The crossing check: how each backend decides the witnesses. Default
# `url_normalization` ("rfc3986"): the paths hold no dot segment, so it
# removes nothing.
rr_engines <- list(google = "Googlebot", bing = "bingbot", yandex = "Yandex")

rr_decide <- function(body, paths, backend) {
  token <- rr_engines[[backend]]
  robots_evaluate_text_v1(
    gsub("%s", token, body, fixed = TRUE),
    paste0("https://example.com", paths), token, backend, backend
  )$results$url_decision
}

# Fixture (or body), the paths and the decisions every backend gives them,
# with any backend that decides otherwise.
rr_decisions <- list(
  list("one", c("/x.js", "/y.js", "/x.css"),
       c("disallow", "disallow", "allow")),
  list("allow_outside", c("/x.js", "/assets/x.js"), c("disallow", "allow")),
  # A tie of pattern lengths goes to the Allow on every backend here, for an
  # identical Allow and for another pattern of the same length.
  list("allow_tie", "/x.js", "allow"),
  list(body = "User-agent: %s\nDisallow: /*.js\nAllow: /x.j*\n", "/x.js",
       "allow"),
  list("filler", c("/x.js", "/y.js"), c("allow", "disallow")),
  list("filler_all", c("/x.js", "/y.js", "/z.js"), rep("allow", 3L)),
  list("star_tail", c("/x.css", "/x.cssx"), c("disallow", "disallow")),
  list("query", c("/a.json?v=", "/a.json"), c("disallow", "allow")),
  list("two_kinds", c("/x.js", "/assets/x.css", "/x.css"),
       c("disallow", "disallow", "allow")),
  # With every candidate left out, the witness is allowed, unless a
  # broader rule blocks it.
  list(body = "User-agent: %s\nDisallow: /assets/\n", "/assets/x.js",
       "disallow"),
  list(body = "User-agent: %s\nDisallow: /\n", "/x.js", "disallow"),
  list(body = "User-agent: %s\nAllow: /assets/*.js\n", "/x.js", "allow")
)

test_that("ROBO-dwywkpes: every backend decides the witnesses", {
  for (backend in names(rr_engines)) {
    for (case in rr_decisions) {
      body <- if (is.null(names(case)) || !nzchar(names(case)[[1L]])) {
        rr_fixtures[[case[[1L]]]]$body
      } else {
        case[[1L]]
      }
      expected <- case[[3L]]
      if (length(case) > 3L && !is.null(case[[4L]][[backend]])) {
        expected <- case[[4L]][[backend]]
      }
      expect_identical(rr_decide(body, case[[2L]], backend), expected,
                       label = paste(backend, case[[2L]][[1L]]))
    }
  }
})
