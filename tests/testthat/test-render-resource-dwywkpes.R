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
      "User-agent: *\nDisallow: /assets/app/*.js\nDisallow: /*.css\n",
      "Disallow: /*/*.json\n\nUser-agent: AdsBot-Google\n",
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
  query = list(body = "User-agent: %s\nDisallow: /*.json?v=*\n",
               today = "rule_query_parameter_position"),
  # Also rule_end_anchor_query's: both rows stand.
  anchored = list(body = "User-agent: %s\nDisallow: /*.js$\n",
                  today = "rule_end_anchor_query"),
  comment = list(body = "User-agent: %s\nDisallow: /*.js#x\n",
                 today = "rule_cut_by_comment"),
  repeated = list(
    body = paste0("User-agent: %s\nDisallow: /*.js\n\n",
                  "User-agent: %s\nDisallow: /*.css\n"),
    today = "user_agent_repeated_group"
  ),
  identical = list(
    body = "User-agent: %s\nDisallow: /*.js\nDisallow: /*.js\n",
    today = "duplicate_rule"
  ),
  two_crawlers = list(
    body = "User-agent: %s\nUser-agent: Bar\nDisallow: /a/*.mjs\n",
    today = character(0)
  ),
  ai = list(body = "User-agent: __usage_ai-training\nDisallow: /*.js\n",
            today = "ai_training_preference"),
  ai_anchor = list(
    body = paste0("User-agent: __usage_ai-training\nUser-agent: %s\n",
                  "Disallow: /*.js\n"),
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
  jsp = list(body = "User-agent: %s\nDisallow: /*.jsp\n",
             today = character(0)),
  inner = list(body = "User-agent: %s\nDisallow: /*.json/y\n",
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
    body = "User-agent: %s\nDisallow: https://e.example/*.js\n",
    today = "rule_missing_leading_slash"
  ),
  dot = list(body = "User-agent: %s\nDisallow: /a/./*.js\n",
             today = "rule_dot_segment"),
  stray = list(body = "User-agent: %s\nDisallow: /a%4/*.js\n",
               today = "rule_invalid_percent_escape")
)

rr_fill <- function(body, token = "Foo") {
  gsub("%s", token, body, fixed = TRUE)
}

rr_body <- function(name, token = "Foo") {
  rr_fill(rr_fixtures[[name]]$body, token)
}

# The recognition set: each listed file type bare, with `$`, `*`, `*$` and
# `?*`, and in upper case, after a folder or none: a type-wide value, whose
# file name is a run of `*`.
rr_types <- c("js", "mjs", "cjs", "css", "json", "wasm")
rr_suffixes <- c("", "$", "*", "*$", "?*")
rr_positive <- c(
  as.vector(outer(paste0("/*.", rr_types), rr_suffixes, paste0)),
  paste0("/*.", chartr("a-z", "A-Z", rr_types)), "/assets/*.css",
  "*/*.mjs", "/*/*.js", "/**.js", "/*.json?v=*", "*.css", "*.json$"
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
  list("query", c("/x.json?v=", "/x.json"), c("disallow", "allow")),
  list("two_kinds", c("/x.js", "/assets/x.css", "/x.css"),
       c("disallow", "disallow", "allow")),
  # With every candidate left out, the witness is allowed, unless a
  # broader rule blocks it.
  list(body = "User-agent: %s\nDisallow: /assets/\n", "/assets/x.js",
       "disallow"),
  list(body = "User-agent: %s\nDisallow: /\n", "/x.js", "disallow"),
  list(body = "User-agent: %s\nAllow: /assets/*.js\n", "/x.js", "allow"),
  # The package's Yandex matcher counts a pattern's length without its `*`
  # (the help says the row is Google's reading): `/*.js` (5) beats
  # `/x.j` (4) on Google and Bing, but counts 4 on Yandex, a tie the Allow
  # wins; `/*.js` ties `/x.js` on Google and Bing, the Allow winning, but
  # counts 4 on Yandex and loses.
  list(body = "User-agent: %s\nDisallow: /*.js\nAllow: /x.j\n", "/x.js",
       "disallow", list(yandex = "allow")),
  list(body = "User-agent: %s\nDisallow: /x.js\nAllow: /*.js\n", "/x.js",
       "allow", list(yandex = "disallow")),
  # `/ab/*.js` (8) ties `/*/**.js` on Google and Bing, the Allow winning on
  # every filler's file, but counts 7 to the Allow's 6 on Yandex.
  list(body = "User-agent: %s\nDisallow: /ab/*.js\nAllow: /*/**.js\n",
       c("/ab/x.js", "/ab/y.js", "/ab/z.js"), rep("allow", 3L),
       list(yandex = rep("disallow", 3L))),
  # A trailing bare `?` is a literal byte to every matcher: without it the
  # rule does not match, so the witness keeps it.
  list(body = "User-agent: %s\nDisallow: /*.js?\n", c("/x.js?", "/x.js"),
       c("disallow", "allow")),
  list(body = "User-agent: %s\nDisallow: /*.json?$\n",
       c("/x.json?", "/x.json"), c("disallow", "allow"))
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

# The lines of each fixture's new rows; a fixture not named gets none.
rr_rows <- list(
  shop = c(1L, 6L), one = 1L, global = 1L, allow_outside = 1L,
  two_kinds = 1L, filler = 1L, star_tail = 1L, query = 1L, anchored = 1L,
  comment = 1L, repeated = 1L, identical = 1L, two_crawlers = 1L,
  ai_anchor = 2L, avalanche = 1L
)

test_that("ROBO-dwywkpes: each fixture's new rows are all the change", {
  expect_true(all(names(rr_rows) %in% names(rr_fixtures)))
  for (name in names(rr_fixtures)) {
    d <- rr_diag(rr_body(name))
    rows <- rr_rows[[name]]
    if (is.null(rows)) {
      rows <- integer(0)
    }
    # The check's rows come after every row the file had before.
    expect_identical(d$code, c(rr_fixtures[[name]]$today,
                               rep(rr_code, length(rows))), label = name)
    expect_identical(d$line[d$code == rr_code], rows, label = name)
  }
})

rr_why <- paste0(
  " A page may need files like this to show its content. A crawler that ",
  "cannot get them may not see the page as users do. Check a rendered page ",
  "and the files it loads. You may block a tracking script or an API on ",
  "purpose."
)

# The row whose first Disallow, on line `line` (`value`), blocks
# `witness`; `same`, the sentence naming the row's other Disallows.
rr_one <- function(line, value, witness, same = "") {
  sprintf("The Disallow on line %d ('%s') blocks '%s'.%s%s", line, value,
          witness, same, rr_why)
}

rr_same <- function(lines, one = FALSE) {
  if (one) {
    return(sprintf(" The Disallow on line %s does the same.", lines))
  }
  sprintf(" The Disallows on lines %s do the same.", lines)
}

rr_note <- function(names) {
  sprintf(" This holds for every crawler the group names: %s.", names)
}

rr_nul <- paste0(" This is Google's reading, which ends each line at its ",
                 "first NUL; Bing and Yandex read the NUL as an ordinary ",
                 "byte.")

rr_message_of <- function(body) {
  d <- rr_diag(body)
  d$message[d$code == rr_code]
}

rr_message <- function(name) {
  rr_message_of(rr_body(name))
}

test_that("ROBO-dwywkpes: one info row on the group's User-agent line", {
  x <- robots_validate_text(rr_body("global"))
  d <- x$diagnostics[x$diagnostics$code == rr_code, , drop = FALSE]
  expect_identical(d$severity, "info")
  expect_identical(d$directive, "user-agent")
  expect_identical(d$raw_text, "User-agent: *")
  expect_identical(d$message, rr_one(2L, "/*.css", "/x.css"))
  expect_identical(x$documents$validation_status, "valid")
  # No security, error or Google wording, and no word on `*`; "may" where
  # the site decides.
  expect_false(grepl("secur|error|Google|wildcard|exact", d$message))
  expect_match(d$message, "You may block", fixed = TRUE)
  # The witness: a trailing run of `*` and a final `$` dropped, an inner
  # `*` written `x`, a query kept.
  expect_identical(rr_message("star_tail"), rr_one(2L, "/*.css*", "/x.css"))
  expect_identical(rr_message("anchored"), rr_one(2L, "/*.js$", "/x.js"))
  expect_identical(rr_message("query"),
                   rr_one(2L, "/*.json?v=*", "/x.json?v="))
  # A comment cut reads the rule as Google's parser does.
  expect_identical(rr_message("comment"), rr_one(2L, "/*.js", "/x.js"))
  expect_identical(rr_message("two_crawlers"), paste0(
    rr_one(3L, "/a/*.mjs", "/a/x.mjs"), rr_note("'Foo' and 'Bar'")
  ))
})

test_that("ROBO-dwywkpes: rows group by crawler set", {
  # The `*` group's three rules in one row; AdsBot-Google, which ignores
  # `*`, in its own, naming only that crawler; Googlebot's group, with no
  # such rule, gets none.
  d <- rr_diag(rr_body("shop"))
  d <- d[d$code == rr_code, , drop = FALSE]
  expect_identical(d$raw_text, c("User-agent: *", "User-agent: AdsBot-Google"))
  expect_identical(d$message, c(
    rr_one(2L, "/assets/app/*.js", "/assets/app/x.js", rr_same("3 and 4")),
    rr_one(7L, "/assets/app/*.js", "/assets/app/x.js")
  ))
  # The first rule with its witness, four more by line, then a count.
  expect_identical(rr_message("avalanche"), rr_one(
    2L, "/d1/*.js", "/d1/x.js", rr_same("3, 4, 5, 6 and 45 more")
  ))
  # Merged repeated groups give one row; an identical repeated line never
  # decides (the matcher keeps the first), but it blocks the file once the
  # first is gone, so the row names it too.
  expect_identical(rr_message("repeated"),
                   rr_one(2L, "/*.js", "/x.js", rr_same("5", one = TRUE)))
  expect_identical(rr_message("identical"),
                   rr_one(2L, "/*.js", "/x.js", rr_same("3", one = TRUE)))
  expect_identical(rr_message("two_kinds"),
                   rr_one(2L, "/*.js", "/x.js", rr_same("3", one = TRUE)))
  # The AI-training token's group gets no row; the row sits on the first
  # User-agent line the check reads.
  expect_identical(rr_codes(rr_body("ai")), "ai_training_preference")
  d <- rr_diag(rr_body("ai_anchor"))
  expect_identical(d$raw_text[d$code == rr_code], "User-agent: Foo")
})

test_that("ROBO-dwywkpes: a row names every candidate that blocks its file", {
  # The longer rule decides the witness; the shorter one blocks it too once
  # the longer one is gone, so both are named.
  expect_identical(
    rr_message_of("User-agent: Foo\nDisallow: /*.js\nDisallow: /*.js$\n"),
    rr_one(3L, "/*.js$", "/x.js", rr_same("2", one = TRUE))
  )
  expect_identical(
    rr_message_of("User-agent: Foo\nDisallow: /*.js\nDisallow: /*.js*\n"),
    rr_one(3L, "/*.js*", "/x.js", rr_same("2", one = TRUE))
  )
  # On every backend, /x.js stays blocked with only the decider gone, and
  # comes out allowed with both gone.
  for (backend in names(rr_engines)) {
    expect_identical(rr_decide("User-agent: %s\nDisallow: /*.js\n", "/x.js",
                               backend), "disallow", label = backend)
    expect_identical(rr_decide("User-agent: %s\n", "/x.js", backend),
                     "allow", label = backend)
  }
  # A candidate that loses to an Allow by itself is not named: with the
  # decider gone, /*.js ties /x.js and the Allow wins.
  expect_identical(
    rr_message_of(paste0("User-agent: Foo\nDisallow: /*.js\n",
                         "Disallow: /*.js$\nAllow: /x.js\n")),
    rr_one(3L, "/*.js$", "/x.js")
  )
  expect_identical(
    rr_message_of(paste0("User-agent: Foo\nDisallow: /*.js\n",
                         "Disallow: /*.js$\nAllow: /x.j\n")),
    rr_one(3L, "/*.js$", "/x.js", rr_same("2", one = TRUE))
  )
  # A candidate of another group the row's crawlers obey, on the
  # whole-value merge and on Google's.
  expect_identical(
    rr_message_of(paste0("User-agent: A\nUser-agent: B\nDisallow: /*.js$\n\n",
                         "User-agent: A\nDisallow: /*.js\n")),
    paste0(rr_one(3L, "/*.js$", "/x.js", rr_same("6", one = TRUE)),
           rr_note("'A' and 'B'"))
  )
  expect_identical(
    rr_message_of(paste0("User-agent: Foo web\nDisallow: /*.js$\n\n",
                         "User-agent: Foo blog\nDisallow: /*.js\n")),
    rr_one(2L, "/*.js$", "/x.js", rr_same("5", one = TRUE))
  )
  # Not one of a crawler the row does not cover.
  expect_identical(
    rr_message_of(paste0("User-agent: A\nDisallow: /*.js$\n\n",
                         "User-agent: B\nDisallow: /*.js\n")),
    c(rr_one(2L, "/*.js$", "/x.js"), rr_one(5L, "/*.js", "/x.js"))
  )
  # The bound holds: four more lines, then a count.
  body <- paste0("User-agent: Foo\nDisallow: /*.js$\n",
                 strrep("Disallow: /*.js\n", 9L))
  expect_identical(rr_message_of(body), rr_one(
    2L, "/*.js$", "/x.js", rr_same("3, 4, 5, 6 and 5 more")
  ))
})

test_that("ROBO-dwywkpes: an Allow or a broader rule silences the row", {
  # An Allow that wins the witness, by a tie or by length.
  expect_false(rr_code %in% rr_codes(rr_body("allow_tie")))
  expect_false(rr_code %in% rr_codes(
    "User-agent: Foo\nDisallow: /*.js\nAllow: /**.js\n"
  ))
  # An Allow that wins only the first filler's witness gives way to `y`.
  expect_identical(
    rr_message_of("User-agent: Foo\nDisallow: /*.js\nAllow: /*x.js\n"),
    rr_one(2L, "/*.js", "/y.js")
  )
  # An Allow that covers other files only.
  expect_identical(rr_message("allow_outside"), rr_one(2L, "/*.js", "/x.js"))
  # With every candidate left out, a broader rule still blocks the
  # witness: the rule changes nothing.
  for (name in c("root", "folder")) {
    expect_false(rr_code %in% rr_codes(rr_body(name)), label = name)
  }
  # Only a rule that is no candidate counts as broader: with every
  # candidate left out, `/*.js` no longer blocks `/assets/x.js`, so both
  # rules are named.
  expect_identical(
    rr_message_of("User-agent: Foo\nDisallow: /assets/*.js\nDisallow: /*.js\n"),
    rr_one(2L, "/assets/*.js", "/assets/x.js", rr_same("3", one = TRUE))
  )
  # A broader rule in another crawler's group is not this crawler's.
  expect_identical(
    rr_codes(paste0("User-agent: Foo\nDisallow: /*.js\n\n",
                    "User-agent: Bar\nDisallow: /\n")),
    rr_code
  )
})

test_that("ROBO-dwywkpes: the row is Google's reading where Yandex differs", {
  # Google and Bing disallow /x.js, Yandex allows it: the row stands and
  # names no engine. Google allows /x.js, Yandex disallows it: no row.
  m <- rr_message_of("User-agent: Foo\nDisallow: /*.js\nAllow: /x.j\n")
  expect_identical(m, rr_one(2L, "/*.js", "/x.js"))
  expect_false(grepl("Google|Bing|Yandex", m))
  expect_false(rr_code %in% rr_codes(
    "User-agent: Foo\nDisallow: /ab/*.js\nAllow: /*/**.js\n"
  ))
})

test_that("ROBO-dwywkpes: a filler another rule matches gives way", {
  expect_identical(rr_message("filler"), rr_one(2L, "/*.js", "/y.js"))
  expect_identical(
    rr_message("filler_all"), character(0)
  )
  d <- rr_diag(paste0("User-agent: Foo\nDisallow: /*.js\nAllow: /x.js\n",
                      "Allow: /y.js\n"))
  expect_identical(d$message[d$code == rr_code],
                   rr_one(2L, "/*.js", "/z.js"))
})

# The reading of each merge, as the shared reader gives it.
rr_groups <- function(body) {
  if (is.character(body)) {
    body <- charToRaw(body)
  }
  validation_groups(as.data.frame(robotstxtr_validation_parse_(body),
                                  stringsAsFactors = FALSE))
}

test_that("ROBO-dwywkpes: the scans make each exclusion", {
  misses <- c("/js/", "/json-api/", "/*.jsp", "/*.json/y", "/*.js/", "/",
              "/*.woff2", "/*.js.map", "/*.png", "x/*.js", "/*.js?/b",
              "/a/./*.js", "/a/%2E%2E/*.js", "/a%4/*.js", "/.js")
  groups <- rr_groups(paste0("User-agent: *\n",
                             paste0("Disallow: ", c(rr_positive, misses), "\n",
                                    collapse = ""),
                             "Disallow:\nAllow: /*.js\n"))
  expect_identical(groups$rules$value[seq_along(rr_positive)], rr_positive)
  expect_identical(render_resource_candidates(groups$rules),
                   seq_along(rr_positive))
  expect_identical(
    render_resource_witness(c("/*.js*$", "/a.json?v=*", "/*/cart.js",
                              "*.css", "/*.css**", "/a*b.wasm$"), "y"),
    c("/y.js", "/a.json?v=", "/y/cart.js", "/y.css", "/y.css", "/ayb.wasm")
  )
  # Every recognized value alone gets a row.
  for (value in rr_positive) {
    codes <- rr_codes(sprintf("User-agent: Foo\nDisallow: %s\n", value))
    expect_true(rr_code %in% codes, label = value)
  }
  # No candidate: an empty frame before any expander is built.
  local({
    local_mocked_bindings(validation_token_expander = function(...) {
      stop("expander built")
    })
    found <- render_resource_diagnostics(rr_groups(
      "User-agent: *\nDisallow: /js/\nAllow: /*.js\n"
    ))
    expect_identical(nrow(found), 0L)
    expect_named(found, c("line", "type", "message", "directive"))
  })
})

test_that("ROBO-dwywkpes: only a type-wide value gets a row", {
  # The file name, after the last `/` (or the whole value) up to the
  # type's dot, is a run of `*`.
  for (value in c("/*.js", "/*.js$", "*.json$", "/assets/*.css", "/*.css?*",
                  "*/*.mjs")) {
    codes <- rr_codes(sprintf("User-agent: Foo\nDisallow: %s\n", value))
    expect_true(rr_code %in% codes, label = value)
  }
  # An exact file or a named stem gets none, though it blocks a file.
  for (value in c("/push-worker.js", "/a/b/c.json", "/js/main-*.js",
                  "/*.app.json", "*/advertising_script.js", "/*.min.js")) {
    codes <- rr_codes(sprintf("User-agent: Foo\nDisallow: %s\n", value))
    expect_false(rr_code %in% codes, label = value)
  }
  # Such a rule (here the named stem `a*`) is no candidate in the removal
  # read either: it still blocks the file with every candidate left out, so
  # no row.
  body <- "User-agent: Foo\nDisallow: /assets/*.js\nDisallow: /a*.js\n"
  expect_identical(render_resource_candidates(rr_groups(body)$rules), 1L)
  expect_false(rr_code %in% rr_codes(body))
  for (backend in names(rr_engines)) {
    expect_identical(rr_decide("User-agent: %s\nDisallow: /a*.js\n",
                               paste0("/assets/", c("x", "y", "z"), ".js"),
                               backend), rep("disallow", 3L), label = backend)
  }
})

test_that("ROBO-dwywkpes: a file type inside the query gets no row", {
  # The type must sit in the path: a `?` before it makes it query text,
  # and so does a `=` or `&`.
  for (value in c("/*?*.js", "/search?q=*.css", "/*?file=*.json",
                  "/q?f=*.css", "/*name=*.js*", "/*a&b/*.js", "/*a=b/*.css",
                  "*&/*.json$")) {
    codes <- rr_codes(sprintf("User-agent: Foo\nDisallow: %s\n", value))
    expect_false(rr_code %in% codes, label = value)
  }
  # A query after the type stays in.
  for (value in c("/*.json?v=*", "/*.js?*", "/*.js?a.css")) {
    codes <- rr_codes(sprintf("User-agent: Foo\nDisallow: %s\n", value))
    expect_true(rr_code %in% codes, label = value)
  }
  expect_identical(rr_message_of("User-agent: Foo\nDisallow: /*.js?*\n"),
                   rr_one(2L, "/*.js?*", "/x.js?"))
})

test_that("ROBO-dwywkpes: a bare trailing `?` stays in the witness", {
  # The rule matches only a URL holding the `?` (every backend decides
  # so above), so dropping it would show a file the rule does not block.
  expect_identical(rr_message_of("User-agent: Foo\nDisallow: /*.js?\n"),
                   rr_one(2L, "/*.js?", "/x.js?"))
  expect_identical(rr_message_of("User-agent: Foo\nDisallow: /*.json?$\n"),
                   rr_one(2L, "/*.json?$", "/x.json?"))
})

test_that("ROBO-dwywkpes: a value no URL carries gets no row", {
  for (byte in list(as.raw(0x20), as.raw(0x09), as.raw(0x01), as.raw(0x7f))) {
    body <- c(charToRaw("User-agent: *\nDisallow: /a"), byte,
              charToRaw("b/*.js\n"))
    expect_false(rr_code %in% rr_codes(body), label = as.integer(byte))
  }
  for (name in c("dot", "stray", "full_url", "empty", "slash")) {
    expect_false(rr_code %in% rr_codes(rr_body(name)), label = name)
  }
})

test_that("ROBO-dwywkpes: every class on both merges must agree", {
  # `B` has an Allow for every filler's witness: no row for the group
  # naming A and B.
  shared <- "User-agent: A\nUser-agent: B\nDisallow: /*.js\n"
  expect_identical(rr_codes(shared), rr_code)
  body <- paste0(shared, "\nUser-agent: B\nAllow: /x.js\nAllow: /y.js\n",
                 "Allow: /z.js\n")
  expect_false(rr_code %in% rr_codes(body))
  # Or a broader rule that blocks the witness anyway.
  expect_false(rr_code %in% rr_codes(paste0(shared,
                                            "\nUser-agent: B\nDisallow: /\n")))
  # Google's merge reads `Foo web` and `Foo blog` as one crawler; the
  # whole-value merge keeps them apart. Each merge can silence the row,
  # in the deciding read and in the removal read.
  fails <- paste0("User-agent: Foo web\nDisallow: /*.js\n\n",
                  "User-agent: Foo blog\nDisallow: /\n")
  expect_false(rr_code %in% rr_codes(fails))
  fails <- paste0("User-agent: Foo web\nDisallow: /*.js\n\n",
                  "User-agent: Foo blog\nAllow: /x.js\nAllow: /y.js\n",
                  "Allow: /z.js\n")
  expect_false(rr_code %in% rr_codes(fails))
  both <- paste0("User-agent: Foo web\nDisallow: /*.js\n\n",
                 "User-agent: Foo blog\nDisallow: /b\n")
  expect_true(rr_code %in% rr_codes(both))
})

test_that("ROBO-dwywkpes: a removal read cut at the last filler stops", {
  # `Foo a` and `Foo b` read apart on the whole-value merge and as one on
  # Google's, so the removal read splits its budget between them; `x` and
  # `y` lose to Allows. Wherever the budget runs out, `/*.js` gets its
  # `z` row or the stop row leaves it unchecked: never counted as checked
  # with no row.
  for (case in list(list(r = 5L, m = 1L, to = 400L),
                    list(r = 20L, m = 3L, to = 700L))) {
    groups <- rr_groups(paste0(
      "User-agent: Foo a\nUser-agent: Foo b\nDisallow: /*.js\n",
      "Allow: /x.js\nAllow: /y.js\n",
      "\nUser-agent: Foo a\nDisallow: /q1\n\nUser-agent: Foo b\n",
      "Disallow: /q2\n\nUser-agent: Foo a\nUser-agent: Foo b\n",
      paste0("Disallow: /r", seq_len(case$r), "\n", collapse = ""),
      "\nUser-agent: Bar\n",
      paste0("Disallow: /c", seq_len(case$m), "/*.css\nAllow: /c",
             seq_len(case$m), "/*.css\n", collapse = "")
    ))
    full <- render_resource_diagnostics(groups)
    expect_identical(full$message, paste0(rr_one(3L, "/*.js", "/z.js"),
                                          rr_note("'Foo a' and 'Foo b'")))
    for (budget in seq_len(case$to)) {
      found <- render_resource_diagnostics(groups, budget = budget)
      if (nrow(found) == 0L) {
        expect_identical(attr(found, "stopped")$checked, 0L, label = budget)
      } else {
        expect_identical(found$message, full$message, label = budget)
      }
    }
  }
})

test_that("ROBO-dwywkpes: a budget cut while naming gets the stop row", {
  # `/*.js$` decides /x.js and `n` repeats of `/*.js` block it too, beside
  # `n` shorter Allows each repeat is read with. Wherever the budget runs
  # out, a row names them all or there is no row and the stop row says so;
  # some budgets run out in the naming (which has a budget of its own), in
  # the reads of each repeat by itself.
  named <- render_resource_named
  alone <- render_resource_alone
  seen <- new.env()
  seen$cut <- 0L
  seen$alone <- 0L
  local_mocked_bindings(
    render_resource_named = function(groups, at, hit, ...) {
      out <- named(groups, at, hit, ...)
      if (out$n < length(hit)) {
        seen$cut <- seen$cut + 1L
      }
      out
    },
    render_resource_alone = function(...) {
      out <- alone(...)
      if (is.finite(out$n)) {
        seen$alone <- seen$alone + 1L
      }
      out
    }
  )
  for (n in c(1L, 6L, 10L)) {
    same <- if (n == 1L) rr_same("3", one = TRUE) else
      rr_same(sprintf("3, 4, 5, 6 and %d more", n - 4L))
    for (allow in c("", strrep("Allow: /x\n", n))) {
      groups <- rr_groups(paste0("User-agent: Foo\nDisallow: /*.js$\n",
                                 strrep("Disallow: /*.js\n", n), allow))
      for (budget in 0:200) {
        found <- render_resource_diagnostics(groups, budget = budget)
        # A row names the repeats even where the budget leaves them
        # unchecked (the stop row then counts them).
        if (nrow(found) > 0L) {
          expect_identical(found$message, rr_one(2L, "/*.js$", "/x.js", same),
                           label = budget)
        } else {
          expect_identical(attr(found, "stopped")$checked, 0L, label = budget)
        }
      }
    }
  }
  expect_gt(seen$cut, 0L)
  expect_gt(seen$alone, 0L)
  # The pairs are counted before they are built: the forty candidates'
  # rows in Foo's class cost 40, then twenty reported `/dK/*.js` beside
  # twenty `/*/aK/*.js` whose head `/` every witness starts with cost
  # twenty pairs each, so a budget of 100 takes three; none matches. (One
  # row holds all twenty, so the naming then drops it whole.)
  k <- seq_len(20L)
  groups <- slash_groups(rr_groups(paste0(
    "User-agent: Foo\n", paste0("Disallow: /d", k, "/*.js\n", collapse = ""),
    paste0("Disallow: /*/a", k, "/*.js\n", collapse = "")
  )))
  at <- render_resource_candidates(groups$rules)
  witness <- paste0("/d", k, "/x.js")
  head <- slash_rule_parts(groups$rules$type[at], groups$rules$value[at])$head
  set <- slash_open_sets(groups, groups$rules$group[at])
  pairs <- function(budget) {
    render_resource_pairs(groups, groups$agents$uncut, at, k, head, witness,
                          NULL, budget, 20L, set)$n
  }
  expect_identical(pairs(100), 3L)
  expect_identical(pairs(39), 0L)
  expect_identical(render_resource_named(groups, at, k, witness, NULL, 100)$n,
                   0L)
  out <- render_resource_named(groups, at, k, witness, NULL, Inf)
  expect_identical(out$n, 20L)
  expect_identical(lengths(out$rules), integer(20L))
})

test_that("ROBO-dwywkpes: a row the naming cuts is dropped whole", {
  # `/a/*.js` and the first `/*.js` are reported in one row; the other
  # repeats block both files by themselves, each read beside 200 shorter
  # Allows. Where the naming's budget covers `/a/*.js` but not `/*.js`, a
  # row naming only what was read would leave out line 3, which blocks
  # /a/x.js too: the row is dropped instead, and the stop row counts both
  # unchecked.
  body <- paste0("User-agent: Foo\nDisallow: /a/*.js\n",
                 strrep("Disallow: /*.js\n", 3L), strrep("Allow: /*j\n", 200L))
  groups <- rr_groups(body)
  full <- rr_one(2L, "/a/*.js", "/a/x.js", rr_same("3, 4 and 5"))
  expect_identical(render_resource_diagnostics(groups)$message, full)
  named <- render_resource_named
  seen <- new.env()
  seen$cut <- 0L
  local_mocked_bindings(render_resource_named = function(groups, at, hit,
                                                         ...) {
    out <- named(groups, at, hit, ...)
    if (out$n < length(hit)) {
      seen$cut <- seen$cut + 1L
    }
    out
  })
  for (budget in seq(1200L, 1450L, by = 2L)) {
    found <- render_resource_diagnostics(groups, budget = budget)
    if (nrow(found) > 0L) {
      expect_identical(found$message, full, label = budget)
    } else {
      expect_identical(attr(found, "stopped")$checked, 0L, label = budget)
    }
  }
  expect_gt(seen$cut, 0L)
  # Leaving out the lines the full row names lets /a/x.js through; line 3
  # still blocks it with the others gone.
  for (backend in names(rr_engines)) {
    gone <- paste0("User-agent: %s\n", strrep("Disallow:\n", 4L),
                   strrep("Allow: /*j\n", 200L))
    expect_identical(rr_decide(gone, "/a/x.js", backend), "allow",
                     label = backend)
    kept <- paste0("User-agent: %s\nDisallow:\nDisallow: /*.js\n",
                   strrep("Disallow:\n", 2L), strrep("Allow: /*j\n", 200L))
    expect_identical(rr_decide(kept, "/a/x.js", backend), "disallow",
                     label = backend)
  }
  # The cut keeps whole rows only: the leading reported candidates of rows
  # that end within the first `n`.
  expect_identical(render_resource_whole(c("a", "a", "b"), 3L), 3L)
  expect_identical(render_resource_whole(c("a", "b", "a"), 2L), 0L)
  expect_identical(render_resource_whole(c("a", "b", "b", "c", "a"), 4L), 0L)
  expect_identical(render_resource_whole(c("a", "b", "c", "c"), 3L), 2L)
  expect_identical(render_resource_whole(c("a", "b", "c", "b", "d"), 3L), 1L)
})

# A body cut at max_bytes, whose cut line could have decided the witness.
rr_cut_text <- paste0("User-agent: *\nDisallow: /*.js\n",
                      "Allow: /later-", strrep("x", 200L), "\n")

test_that("ROBO-dwywkpes: a cut body is skipped, a NUL body is Google's", {
  body <- charToRaw(rr_cut_text)[seq_len(35L)]
  x <- validate_document_bytes(body, "s", "supplied", max_bytes = 35L,
                               body_truncated = TRUE)
  expect_false(rr_code %in% x$diagnostics$code)
  # The same bytes, not marked cut, get the row.
  x <- validate_document_bytes(body, "s", "supplied")
  expect_identical(x$diagnostics$message[x$diagnostics$code == rr_code],
                   rr_one(2L, "/*.js", "/x.js"))
  # A Disallow a NUL cuts takes part as Google cuts it, and the row says
  # it is Google's reading. Not testable on Bing and Yandex: the evaluator
  # takes a string, which cannot hold the NUL.
  cut <- c(charToRaw("User-agent: *\nDisallow: /*.js"), as.raw(0),
           charToRaw("zz\n"))
  d <- rr_diag(cut)
  expect_identical(d$code, c("nul_byte", "rule_cut_by_nul", rr_code))
  expect_identical(d$message[[3L]], paste0(rr_one(2L, "/*.js", "/x.js"),
                                           rr_nul))
  # A NUL elsewhere: the row is still Google's reading.
  other <- c(charToRaw("User-agent: *\nDisallow: /*.css\nDisallow: /b"),
             as.raw(0), charToRaw("\n"))
  d <- rr_diag(other)
  expect_identical(d$message[d$code == rr_code],
                   paste0(rr_one(2L, "/*.css", "/x.css"), rr_nul))
})

# The counts a check that stopped hands out, as slash_stop() builds them.
rr_stopped <- function(found, checked, value) {
  list(found = found, checked = checked, skipped = found - checked,
       value = value)
}

rr_stop_text <- function(found, value, done) {
  rules <- if (found == 1L) {
    "1 Disallow rule that ends in a file type a page may load"
  } else {
    sprintf("%d Disallow rules that end in a file type a page may load",
            found)
  }
  paste0(
    "This file has ", rules, " (.js, .css, .json and the like), such as '",
    value, "'. For each one, the validator checks whether the rule blocks ",
    "a file that a page may need to show its content. This file is too ",
    "large to check ", done
  )
}

test_that("ROBO-dwywkpes: the stop row says what the problem is", {
  # The intro names what the check looks for, so the counting sentences'
  # "the same problem" has a referent; the shared sentences and the other
  # kinds read as before.
  stop <- rr_stopped(3L, 1L, "/*.css")
  m <- slash_stop_message("render_resource", stop)
  expect_match(m, paste0("whether the rule blocks a file that a page may ",
                         "need to show its content. This file"), fixed = TRUE)
  expect_false(grepl("such a file", m, fixed = TRUE))
  expect_identical(
    sub("^.*[.] This file is too large", "This file is too large", m),
    sub("^.*[.] This file is too large", "This file is too large",
        slash_stop_message("end_anchor", stop))
  )
  expect_identical(
    slash_stop_message("split", rr_stopped(2L, 0L, "/a/")),
    paste0("This file has 2 rules whose path ends in '/', such as '/a/'. ",
           "For each one, the validator checks whether crawlers treat '/a' ",
           "and '/a/' differently. This file is too large to check them all ",
           "quickly, so none of them were checked. All 2 were skipped, and ",
           "some of them may have the same problem.")
  )
})

test_that("ROBO-dwywkpes: candidates past the work budget get no row", {
  # The deciding read costs 3 (a row, the class's rule, one body line)
  # within half the budget, the removal read 1 (a row; the rule is left
  # out) of the rest: from 6 the row.
  groups <- rr_groups("User-agent: Foo\nDisallow: /*.js\n")
  for (budget in list(NULL, 6)) {
    found <- render_resource_diagnostics(groups, budget = budget)
    expect_identical(found$line, 1L)
    expect_null(attr(found, "stopped"))
  }
  for (budget in 0:5) {
    found <- render_resource_diagnostics(groups, budget = budget)
    expect_identical(nrow(found), 0L, label = budget)
    expect_identical(attr(found, "stopped"), rr_stopped(1L, 0L, "/*.js"),
                     label = budget)
  }
  expect_identical(
    slash_stop_message("render_resource", rr_stopped(1L, 0L, "/*.js")),
    paste0(rr_stop_text(1L, "/*.js", "it quickly, so it was not checked."),
           " It was skipped, and it may have the same problem.")
  )
  # Candidates are checked in line order: the second runs out.
  groups <- rr_groups("User-agent: Foo\nDisallow: /*.js\nDisallow: /*.css\n")
  found <- render_resource_diagnostics(groups, budget = 10)
  expect_identical(found$message, rr_one(2L, "/*.js", "/x.js"))
  stop <- attr(found, "stopped")
  expect_identical(stop, rr_stopped(2L, 1L, "/*.css"))
  expect_identical(slash_stop_message("render_resource", stop), paste0(
    rr_stop_text(2L, "/*.css", paste0(
      "them all quickly, so only the first was checked, in line order."
    )),
    " The other 1 was skipped, and it may have the same problem."
  ))
  # A filler retry that runs out leaves the candidate unchecked, and no
  # later candidate gets a row past it, though its own reading fit.
  groups <- rr_groups(paste0("User-agent: Foo\nDisallow: /*.js\n",
                             "Allow: /x.js\nDisallow: /a/*.css\n"))
  for (budget in 8:24) {
    found <- render_resource_diagnostics(groups, budget = budget)
    if (nrow(found) > 0L) {
      expect_null(attr(found, "stopped"), label = budget)
      expect_identical(found$message, rr_one(
        2L, "/*.js", "/y.js", rr_same("4", one = TRUE)
      ), label = budget)
    } else {
      expect_identical(attr(found, "stopped")$checked, 0L, label = budget)
    }
  }
  # A normal file gets no such row.
  for (name in names(rr_fixtures)) {
    expect_false("rule_check_stopped" %in% rr_codes(rr_body(name)),
                 label = name)
  }
})

test_that("ROBO-dwywkpes: a budget cut in Google's reread gets the row", {
  # The whole-value merge reads `Foo extra` alone, cheaply; Google's reads
  # it as Foo, with 500 more Disallows. Wherever Google's reread runs out,
  # the candidate is not checked: no row, but the stop row says so.
  groups <- rr_groups(paste0(
    "User-agent: Foo extra\nDisallow: /*.js\n\n",
    "User-agent: Foo\n", paste0("Disallow: /*.js", 1:500, "\n", collapse = "")
  ))
  for (budget in seq(10, 1500, by = 70)) {
    found <- render_resource_diagnostics(groups, budget = budget)
    expect_true(nrow(found) > 0L || !is.null(attr(found, "stopped")),
                label = budget)
    if (nrow(found) > 0L) {
      expect_null(attr(found, "stopped"), label = budget)
    }
  }
  expect_identical(nrow(render_resource_diagnostics(groups)), 1L)
})

# How many of a body's candidates the check reads.
rr_checked <- function(body) {
  groups <- rr_groups(body)
  stop <- attr(render_resource_diagnostics(groups), "stopped")
  if (is.null(stop)) {
    return(length(render_resource_candidates(groups$rules)))
  }
  stop$checked
}

# Shapes where the bodies alone would grow with candidates times rules:
# `n` candidates beside `n` wide rules whose fragment every witness holds,
# so each body holds every wide rule (`wide`), `n` candidates alone
# (`many`), and one group naming `n` crawlers that each have a group of
# their own, with `n` candidates (`crawlers`) or five (`classes`).
rr_shape <- function(shape, n) {
  k <- seq_len(n)
  switch(
    shape,
    classes = paste0(paste0("User-agent: bot", k, "\n", collapse = ""),
                     paste0("Disallow: /d", 1:5, "/*.css\n", collapse = ""),
                     "\n",
                     paste0("User-agent: bot", k, "\nDisallow: /z", k, "\n",
                            collapse = "\n")),
    many = paste0("User-agent: *\n",
                  paste0("Disallow: /d", k, "/*.js\n", collapse = "")),
    wide = paste0("User-agent: *\n",
                  paste0("Disallow: /d", k, "/*.js\n", collapse = ""),
                  paste0("Allow: /*.js", k, "x\n", collapse = "")),
    crawlers = paste0(paste0("User-agent: bot", k, "\n", collapse = ""),
                      paste0("Disallow: /d", k, "/*.css\n", collapse = ""),
                      "\n",
                      paste0("User-agent: bot", k, "\nDisallow: /z", k, "\n",
                             collapse = "\n"))
  )
}

test_that("ROBO-dwywkpes: a file too large for the check gets the row", {
  d <- rr_diag(rr_shape("wide", 400L))
  stop <- d[d$code == "rule_check_stopped", , drop = FALSE]
  expect_identical(stop$line, NA_integer_)
  expect_identical(stop$severity, "info")
  expect_identical(stop$directive, NA_character_)
  expect_identical(stop$message, paste0(
    rr_stop_text(400L, "/d36/*.js", paste0(
      "them all quickly, so only the first 35 were checked, in line order."
    )),
    " The other 365 were skipped, and some of them may have the same problem."
  ))
  # The checked candidates keep their row; none past them.
  expect_identical(d$line[d$code == rr_code], 1L)
  expect_match(d$message[d$code == rr_code],
               "lines 3, 4, 5, 6 and 30 more do the same.", fixed = TRUE)
  expect_match(d$message[d$code == rr_code],
               "The Disallow on line 2 ('/d1/*.js') blocks '/d1/x.js'.",
               fixed = TRUE)
})

test_that("ROBO-dwywkpes: a cut value elsewhere leaves the budget whole", {
  # One cut value in its own group makes Google's merge differ from the
  # whole-value one, but not for the group holding the candidates: Google's
  # merge rereads only the groups whose classes differ.
  cut <- "\nUser-agent: Mediapartners-Google*\nDisallow: /zz/\n"
  for (body in list(rr_shape("many", 300L), rr_shape("wide", 200L))) {
    plain <- rr_checked(body)
    with_cut <- rr_checked(paste0(body, cut))
    expect_gt(with_cut, 0L)
    expect_gte(with_cut, plain - 1L)
  }
})

# The best of five runs of `small` and of `large`, taken in turn, so a
# loaded machine slows both alike and cannot fail the ratio
# (test-cut-note-zqyqbudf.R). A floor of 0.1s keeps a fast small run from
# making the bound a few tens of milliseconds.
rr_ratio_ok <- function(small, large, label) {
  times <- vapply(1:5, function(i) {
    c(system.time(small())[["elapsed"]], system.time(large())[["elapsed"]])
  }, numeric(2))
  expect_lt(min(times[2L, ]), 8 * max(min(times[1L, ]), 0.1), label = label)
}

test_that("ROBO-dwywkpes: the work stays linear in the file", {
  skip_on_cran()
  # Work units, not time, so load cannot move them: the elements of every
  # vector findInterval() searches, and the witness bodies' bytes the
  # matcher reads.
  count <- new.env()
  count$n <- 0
  on.exit(suppressMessages(untrace("findInterval", where = baseenv())),
          add = TRUE)
  suppressMessages(trace("findInterval", bquote(assign(
    "n", get("n", envir = .(count)) + length(vec), envir = .(count)
  )), print = FALSE, where = baseenv()))
  decide <- wildcard_witness_decide
  local_mocked_bindings(wildcard_witness_decide = function(bodies, ...) {
    count$n <- count$n + sum(nchar(bodies, "bytes"))
    decide(bodies, ...)
  })
  for (shape in c("many", "wide", "classes")) {
    work <- vapply(c(400L, 1600L, 6400L), function(n) {
      groups <- rr_groups(rr_shape(shape, n))
      count$n <- 0
      render_resource_diagnostics(groups)
      count$n
    }, 0)
    expect_gt(work[[1L]], 0)
    expect_lt(work[[2L]], 6 * work[[1L]], label = shape)
    expect_lt(work[[3L]], 6 * work[[2L]], label = shape)
  }
  # `n` crawlers each holding `n` candidates: no class fits, so nothing is
  # read, and the stop row says so.
  found <- render_resource_diagnostics(rr_groups(rr_shape("crawlers", 400L)))
  expect_identical(attr(found, "stopped")$checked, 0L)
})

test_that("ROBO-dwywkpes: the validator stays linear on costly shapes", {
  skip_on_cran()
  for (shape in c("wide", "crawlers")) {
    rr_ratio_ok(function() robots_validate_text(rr_shape(shape, 100L)),
                function() robots_validate_text(rr_shape(shape, 400L)),
                shape)
  }
})

test_that("ROBO-dwywkpes: the naming's rows stay linear in the crawlers", {
  # `n` crawlers with a group each, then one group naming them all with `n`
  # rules: candidates (`plain`), or plain Disallows beside a crawler of its
  # own whose `/*.css$` and `/*.css` the naming reads (`alone`). Crossing
  # every rule with every crawler would build `n` squared rows; the naming
  # crosses them with its rows' crawlers only. Work units: the rows every
  # expander builds.
  shape <- function(kind, n) {
    k <- seq_len(n)
    rule <- if (kind == "plain") "/*.js" else "/"
    own <- "User-agent: zz\nDisallow: /*.css$\nDisallow: /*.css\n\n"
    paste0(if (kind == "alone") own,
           paste0("User-agent: b", k, "\nAllow: /q\n\n", collapse = ""),
           paste0("User-agent: b", k, "\n", collapse = ""),
           paste0("Disallow: /a", k, rule, "\n", collapse = ""))
  }
  count <- new.env()
  count$n <- 0
  expander <- validation_token_expander
  local_mocked_bindings(validation_token_expander = function(...) {
    f <- expander(...)
    function(group) {
      out <- f(group)
      count$n <- count$n + length(out$owner)
      out
    }
  })
  for (kind in c("plain", "alone")) {
    work <- vapply(c(80L, 320L, 1280L), function(n) {
      groups <- rr_groups(shape(kind, n))
      count$n <- 0
      render_resource_diagnostics(groups)
      count$n
    }, 0)
    expect_lt(work[[2L]], 6 * work[[1L]], label = kind)
    expect_lt(work[[3L]], 6 * work[[2L]], label = kind)
  }
  # The `alone` row names `/*.css` beside `/*.css$`.
  expect_identical(rr_message_of(shape("alone", 3L)),
                   rr_one(2L, "/*.css$", "/x.css", rr_same("3", one = TRUE)))
  # With no candidate reported, the naming builds no expander.
  groups <- slash_groups(rr_groups(shape("plain", 3L)))
  local_mocked_bindings(validation_token_expander = function(...) {
    stop("expander built")
  })
  out <- render_resource_named(groups,
                               render_resource_candidates(groups$rules),
                               integer(), character(), NULL, Inf)
  expect_identical(out$n, 0L)
})

test_that("ROBO-dwywkpes: the naming's bodies stay linear in the pairs", {
  skip_on_cran()
  # `n / 2` folders' `/dK/*.js`, then `n / 2` repeats of `/*.js` that each
  # block every folder's file by itself: the naming builds one body per
  # pair, each taken from the pairs once, so 4 times the lines take about
  # 4 times as long (best of three, taken in turn, so load slows both).
  shape <- function(n) {
    k <- seq_len(n / 2)
    rr_groups(paste0("User-agent: Foo\n",
                     paste0("Disallow: /d", k, "/*.js\n", collapse = ""),
                     strrep("Disallow: /*.js\n", n / 2)))
  }
  small <- shape(1600L)
  large <- shape(6400L)
  times <- vapply(1:3, function(i) {
    c(system.time(render_resource_diagnostics(small))[["elapsed"]],
      system.time(render_resource_diagnostics(large))[["elapsed"]])
  }, numeric(2))
  expect_lt(min(times[2L, ]), 6 * max(min(times[1L, ]), 0.1))
})

# Sets the locale categories for the calling test, restored on exit; skips
# when one is not installed (as ar_local_locale() in
# test-allow-reopens-through-query-micbpqbc.R).
rr_local_locale <- function(locale, env = parent.frame()) {
  for (category in c("LC_CTYPE", "LC_COLLATE")) {
    old <- Sys.getlocale(category)
    do.call(base::on.exit,
            list(bquote(Sys.setlocale(.(category), .(old))), TRUE, FALSE),
            envir = env)
    set <- suppressWarnings(Sys.setlocale(category, locale))
    if (!nzchar(set)) {
      testthat::skip(sprintf("locale %s is not installed", locale))
    }
  }
}

# A latin1 byte, a UTF-8 character and an invalid UTF-8 lead byte in a
# value, and an upper-case `I` in the values and the crawler token, which
# tr_TR.UTF-8 folds otherwise.
rr_edge <- function() {
  for (byte in list(as.raw(0xe9), as.raw(c(0xc3, 0xa9)), as.raw(0xc3))) {
    body <- c(charToRaw("User-agent: *\nDisallow: /caf"), byte,
              charToRaw("/*.js\n"))
    escaped <- paste0("/caf", paste(sprintf("%%%02X", as.integer(byte)),
                                    collapse = ""), "/")
    d <- rr_diag(body)
    expect_identical(d$message[d$code == rr_code],
                     rr_one(2L, paste0(escaped, "*.js"),
                            paste0(escaped, "x.js")))
  }
  d <- rr_diag(paste0("User-agent: IndexBot\nDisallow: /INFO/*.JSON\n\n",
                      "User-agent: indexbot\nAllow: /INFO/I.JSON\n"))
  expect_identical(d$message[d$code == rr_code],
                   rr_one(2L, "/INFO/*.JSON", "/INFO/x.JSON"))
  expect_identical(render_resource_candidates(rr_groups(
    "User-agent: *\nDisallow: /*.JS\nDisallow: /*.JSI\n"
  )$rules), 1L)
}

test_that("ROBO-dwywkpes: edge inputs in the session's locale", {
  rr_edge()
  # Google's matcher compares the escaped witness; the package's Bing and
  # Yandex matchers compare the byte as written.
  body <- "User-agent: %s\nDisallow: /café/*.js\n"
  expect_identical(rr_decide(body, "/caf%C3%A9/x.js", "google"), "disallow")
  for (backend in c("bing", "yandex")) {
    expect_identical(rr_decide(body, "/café/x.js", backend), "disallow",
                     label = backend)
  }
  expect_identical(rr_codes(""), "no_rules")
})

for (locale in c("C", "en_US.UTF-8", "tr_TR.UTF-8")) {
  test_that(paste("ROBO-dwywkpes: edge inputs under", locale), {
    rr_local_locale(locale)
    rr_edge()
  })
}

test_that("ROBO-dwywkpes: a rule at the line buffer keeps a bounded row", {
  # `Disallow:` and no space fill the 16,663-byte line buffer.
  long <- strrep("a", 16663L - nchar("Disallow://*.js"))
  d <- rr_diag(sprintf("User-agent: *\nDisallow:/%s/*.js\n", long))
  shown <- paste0("/", strrep("a", 35L), "...")
  expect_identical(d$message[d$code == rr_code], rr_one(2L, shown, shown))
  expect_lt(nchar(d$message[d$code == rr_code]), 600L)
})

test_that("ROBO-dwywkpes: the row's length is bounded", {
  # 50 Disallows of 200 bytes: each value and witness is cut at 40 bytes
  # and four more lines are named, so the row stays short (one crawler, so
  # no crawler note).
  k <- seq_len(50L)
  body <- paste0("User-agent: Foo\n",
                 paste0("Disallow: /", k, strrep("a", 192L - nchar(k)),
                        "/*.json\n", collapse = ""))
  d <- rr_diag(body)
  m <- d$message[d$code == rr_code]
  expect_length(m, 1L)
  expect_false("rule_check_stopped" %in% d$code)
  expect_identical(nchar(rr_groups(body)$rules$value[[1L]]), 200L)
  shown <- paste0("/1", strrep("a", 34L), "...")
  expect_identical(m, rr_one(2L, shown, shown,
                             rr_same("3, 4, 5, 6 and 45 more")))
  expect_lt(nchar(m), 600L)
  # 300 of them cross (every witness holds each rule's `.json`), so the
  # budget stops the check, and the row stays bounded.
  k <- seq_len(300L)
  body <- paste0("User-agent: Foo\n",
                 paste0("Disallow: /", k, strrep("a", 192L - nchar(k)),
                        "/*.json\n", collapse = ""))
  d <- rr_diag(body)
  expect_true("rule_check_stopped" %in% d$code)
  expect_lt(nchar(d$message[d$code == rr_code]), 600L)
  # With a star in each value the bodies cross and the budget stops the
  # check, and the row stays bounded too.
  body <- paste0("User-agent: Foo\n",
                 paste0("Disallow: /", k, "*", strrep("a", 191L - nchar(k)),
                        "/*.json\n", collapse = ""))
  d <- rr_diag(body)
  expect_true("rule_check_stopped" %in% d$code)
  expect_lt(nchar(d$message[d$code == rr_code]), 600L)
})

test_that("ROBO-dwywkpes: robots_validate_url() gives the same rows", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, url = req$url, body = rr_body("global"))
  })
  x <- robots_validate_url("https://e.example/page")
  d <- x$diagnostics
  expect_identical(d$code, rr_code)
  expect_identical(d$message, rr_diag(rr_body("global"))$message)
  expect_identical(x$documents$validation_status, "valid")
})
