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
# can read it) and `today`, the codes it got before ROBO-micbpqbc (plus
# rule_query_crawl_not_index, added later by ROBO-jnnnkyat). A bare
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
              "rule_query_crawl_not_index", ar_split)
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
    today = "rule_query_crawl_not_index"
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

ar_fill <- function(body, token = "Foo") {
  gsub("%s", token, body, fixed = TRUE)
}

ar_body <- function(name, token = "Foo") {
  ar_fill(ar_fixtures[[name]]$body, token)
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

# The lines of each fixture's new rows; a fixture not named gets none.
ar_rows <- list(
  positive = 1L, global = 1L, slash_led = 1L, stars = 1L, star_dollar = 1L,
  wild_disallow = 1L, cause_short = 1L, two_cause = 1L, decider = 1L,
  fourth = 1L, tie = 1L, ai_anchor = 2L, adsbot = 1L, repeated = 1L,
  seven = 1L, two_crawlers = 1L, overlap = 1L
)

test_that("ROBO-micbpqbc: each fixture's new rows are all the change", {
  expect_true(all(names(ar_rows) %in% names(ar_fixtures)))
  for (name in names(ar_fixtures)) {
    d <- ar_diag(ar_body(name))
    rows <- ar_rows[[name]]
    if (is.null(rows)) {
      rows <- integer(0)
    }
    # The check's rows come after every row the file had before.
    expect_identical(d$code, c(ar_fixtures[[name]]$today,
                               rep(ar_code, length(rows))), label = name)
    expect_identical(d$line[d$code == ar_code], rows, label = name)
  }
})

# The row whose first Allow, on line `line` (`value`), has the witness
# `control`, `?q=` and `literal`, `decider` the line deciding the control;
# `same`, the row's other Allows (ar_same()).
ar_one <- function(line, value, control, literal, decider, same = "") {
  sprintf(paste0(
    "The Allow on line %d ('%s') allows '%s?q=%s'. The Disallow on line %d ",
    "blocks '%s'. The '*' at the start of the Allow also matches text in ",
    "the query.%s You may not mean to allow URLs like this."
  ), line, value, control, literal, decider, control, same)
}

# The sentence naming a row's other Allows, `lines` as the row writes them.
ar_same <- function(lines, one = FALSE) {
  if (one) {
    return(sprintf(" The Allow on line %s does the same.", lines))
  }
  sprintf(" The Allows on lines %s do the same.", lines)
}

ar_note <- function(names) {
  sprintf(" This holds for every crawler the group names: %s.", names)
}

ar_nul <- paste0(" This is Google's reading, which ends each line at its ",
                 "first NUL; Bing and Yandex read the NUL as an ordinary ",
                 "byte.")

ar_sitemap <- function(line = 3L, decider = 2L, control = "/my/",
                       value = "*/sitemap_output/") {
  ar_one(line, value, control, "/sitemap_output/", decider)
}

test_that("ROBO-micbpqbc: one info row on the group's User-agent line", {
  x <- robots_validate_text(ar_body("global"))
  d <- x$diagnostics[x$diagnostics$code == ar_code, , drop = FALSE]
  expect_identical(d$severity, "info")
  expect_identical(d$directive, "user-agent")
  expect_identical(d$raw_text, "User-agent: *")
  expect_identical(d$message, ar_sitemap())
  expect_identical(x$documents$validation_status, "valid")
  # No security, error or indexing wording; "may" where the site decides.
  expect_false(grepl("secur|error|index|bypass|broken", d$message))
  expect_match(d$message, "You may not mean", fixed = TRUE)
  m <- function(name) {
    d <- ar_diag(ar_body(name))
    d$message[d$code == ar_code]
  }
  expect_identical(m("slash_led"), ar_sitemap(value = "/*/sitemap_output/"))
  # A run of `*` and a final `$` leave the literal; a `*`-led Disallow is
  # written `x`.
  expect_identical(m("stars"), ar_one(3L, "/**/x$", "/my", "/x", 2L))
  expect_identical(m("star_dollar"), ar_one(3L, "*/x/$", "/my", "/x/", 2L))
  expect_identical(m("wild_disallow"), ar_sitemap(control = "/x/my/"))
  # Ties go to the Allow; a `?` in the literal stays as written.
  expect_identical(m("tie"), ar_one(3L, "*/ss/", "/abc/", "/ss/", 2L))
  expect_identical(m("overlap"), ar_one(3L, "*/x?p=", "/my/", "/x?p=", 2L))
  expect_identical(m("two_crawlers"), paste0(
    ar_one(4L, "*/sx/", "/my/", "/sx/", 3L), ar_note("'Foo' and 'Bar'")
  ))
})

test_that("ROBO-micbpqbc: the row names the line deciding the control", {
  # `/my/$` is longer than `/my/` and decides the control; it is no control
  # itself (a final `$`).
  d <- ar_diag(ar_body("decider"))
  expect_identical(d$message, ar_sitemap(4L, 3L))
  # Three Disallows fail and the fourth proves: every pair is read.
  d <- ar_diag(ar_body("fourth"))
  expect_identical(d$message[d$code == ar_code],
                   ar_sitemap(9L, 5L, "/d/"))
})

test_that("ROBO-micbpqbc: the removal read leaves out every shape-A Allow", {
  # Each Allow alone, and both: the longer one also matches the shorter
  # one's witness, and both are named.
  expect_identical(ar_diag(ar_body("positive"))$message[[2L]], ar_sitemap())
  expect_identical(ar_diag(ar_body("cause_short"))$message[[2L]],
                   ar_one(3L, "*/output/", "/my/", "/output/", 2L))
  expect_identical(ar_diag(ar_body("two_cause"))$message[[2L]], ar_one(
    3L, "*/sitemap_output/", "/my/", "/sitemap_output/", 2L,
    ar_same("4", one = TRUE)
  ))
  # `*/b/` opens `/my/?q=/a/b/` too, but gets no row of its own: the
  # `/*q=/b/` Disallow blocks its own witness. The removal read leaves it
  # out with the Allow; without it left out, `*/b/` would keep the witness
  # open and the row would go. The row names only `*/a/b/`.
  d <- ar_diag(paste0("User-agent: Foo\nDisallow: /my/\nAllow: */a/b/\n",
                      "Allow: */b/\nDisallow: /*q=/b/\n"))
  expect_identical(d$message[d$code == ar_code],
                   ar_one(3L, "*/a/b/", "/my/", "/a/b/", 2L))
  # An Allow of another shape opens the witness: no row.
  expect_false(ar_code %in% ar_codes(ar_body("non_a_opener")))
  # The removal read reads the Allow's crawlers, not those of the deciding
  # Disallow's group: Bar's own Allow of another shape opens the witness for
  # Bar alone, whom Foo's Allow never covers.
  extra <- paste0("User-agent: %s\nUser-agent: Bar\nDisallow: /my/\n\n",
                  "User-agent: %s\nAllow: */x/\n\n",
                  "User-agent: Bar\nAllow: /my/?\n")
  d <- ar_diag(ar_fill(extra))
  expect_identical(d$line[d$code == ar_code], 5L)
  expect_identical(d$message[d$code == ar_code],
                   ar_one(6L, "*/x/", "/my/", "/x/", 3L))
  for (backend in names(ar_engines)) {
    # A tie of pattern lengths, which the package's Yandex matcher gives
    # the Disallow.
    expect_identical(ar_decide(extra, c("/my/", "/my/?q=/x/"), backend),
                     if (backend == "yandex") ar_closed else ar_opened,
                     label = backend)
    no_allow <- sub("Allow: */x/", "Allow: /zz", extra, fixed = TRUE)
    expect_identical(ar_decide(no_allow, "/my/?q=/x/", backend), "disallow",
                     label = backend)
  }
  # Allows left out with it that get no row of their own (each shorter than
  # the Disallow) are not named.
  d <- ar_diag(paste0("User-agent: Foo\nDisallow: /abcdefgh/\n",
                      "Allow: */a_long_name/\n",
                      paste0("Allow: */", letters[1:7], "/\n",
                             collapse = "")))
  expect_identical(d$message[d$code == ar_code], ar_one(
    3L, "*/a_long_name/", "/abcdefgh/", "/a_long_name/", 2L
  ))
  # Google's merge reads `Foo extra` as Foo, so the Allow on line 6 is one
  # the removal read left out too, and the row stands: without line 3
  # alone, line 6 keeps the witness open on Google. Google's cut only: the
  # check decides on Google's matcher, and Bing and Yandex do not cut the
  # value this way.
  cut <- paste0("User-agent: Foo extra\nDisallow: /my/\nAllow: /*/a/\n\n",
                "User-agent: Foo\nAllow: */a/\n")
  d <- ar_diag(cut)
  expect_identical(d$line[d$code == ar_code], 1L)
  expect_identical(d$message[d$code == ar_code],
                   ar_one(3L, "/*/a/", "/my/", "/a/", 2L))
  google <- function(body) {
    robots_evaluate_text_v1(body, "https://example.com/my/?q=/a/", "Foo",
                            "google", "google")$results$url_decision
  }
  expect_identical(google(sub("Allow: /*/a/", "Allow: /zz", cut,
                              fixed = TRUE)), "allow")
  expect_identical(google(gsub("Allow: [*/]+a/", "Allow: /zz", cut)),
                   "disallow")
  for (backend in names(ar_engines)) {
    body <- paste0("User-agent: %s\nDisallow: /my/\nAllow: */a/b/\n",
                   "Allow: */b/\nDisallow: /*q=/b/\n")
    expect_identical(ar_decide(body, c("/my/", "/my/?q=/a/b/", "/my/?q=/b/"),
                               backend),
                     c(ar_opened, "disallow"), label = backend)
    # A tie of pattern lengths, which the package's Yandex matcher gives
    # the Disallow.
    expect_identical(
      ar_decide("User-agent: %s\nDisallow: /my/\nAllow: */b/\n",
                c("/my/", "/my/?q=/a/b/"), backend),
      if (backend == "yandex") ar_closed else ar_opened, label = backend
    )
  }
})

test_that("ROBO-micbpqbc: rows group by crawler set, five Allows named", {
  # The first Allow with its witness, four more by line, then a count.
  d <- ar_diag(ar_body("seven"))
  expect_identical(d$message[d$code == ar_code], ar_one(
    3L, "*/ax/", "/my/", "/ax/", 2L, ar_same("4, 5, 6, 7 and 2 more")
  ))
  # Merged repeated groups give one row.
  d <- ar_diag(ar_body("repeated"))
  expect_identical(d$message[d$code == ar_code], ar_one(
    3L, "*/a/", "/my/", "/a/", 2L, ar_same("6", one = TRUE)
  ))
  # The AI-training token's group gets no row; the row sits on the first
  # User-agent line the check reads.
  expect_identical(ar_codes(ar_body("ai")), "ai_training_preference")
  d <- ar_diag(ar_body("ai_anchor"))
  expect_identical(d$raw_text[d$code == ar_code], "User-agent: Foo")
  # A crawler that ignores `*` is judged on its own group.
  d <- ar_diag(ar_body("adsbot"))
  expect_identical(d$line[d$code == ar_code], 1L)
})

# The reading of each merge, as the shared reader gives it.
ar_groups <- function(body) {
  if (is.character(body)) {
    body <- charToRaw(body)
  }
  validation_groups(as.data.frame(robotstxtr_validation_parse_(body),
                                  stringsAsFactors = FALSE))
}

ar_ok <- function(body, key) {
  groups <- ar_groups(body)
  at <- reopen_shape(groups$rules)[[1L]]
  witness_pair_reading(groups, at, groups$agents[[key]], "/my/",
                       "/my/?q=/s/", "long")$ok
}

test_that("ROBO-micbpqbc: every class on both merges must agree", {
  # `B` blocks the witness with a longer rule, or opens it with an Allow
  # of another shape: no row for the group naming A and B.
  shared <- "User-agent: A\nUser-agent: B\nDisallow: /my/\nAllow: */s/\n"
  expect_identical(ar_codes(shared), c(ar_split, ar_code))
  for (rule in c("Disallow: /my/?q=", "Allow: /my/?")) {
    body <- paste0(shared, "\nUser-agent: B\n", rule, "\n")
    expect_false(ar_code %in% ar_codes(body), label = rule)
  }
  # Google's merge reads `Foo web` and `Foo blog` as one crawler; the
  # whole-value merge keeps them apart.
  fails <- paste0("User-agent: Foo web\nDisallow: /my/\nAllow: */s/\n\n",
                  "User-agent: Foo blog\nDisallow: /my/?q=\n")
  expect_true(ar_ok(fails, "uncut"))
  expect_false(ar_ok(fails, "key"))
  expect_false(ar_code %in% ar_codes(fails))
  both <- paste0("User-agent: Foo web\nDisallow: /my/\nAllow: */s/\n\n",
                 "User-agent: Foo blog\nDisallow: /b\n")
  expect_true(ar_ok(both, "uncut"))
  expect_true(ar_ok(both, "key"))
  expect_true(ar_code %in% ar_codes(both))
  # Both classes pass the first reading, but a longer Disallow only B has
  # decides B's control: the classes name no one deciding line, so the row
  # could name none, and the pair gets none. Another control that both
  # classes block by the same line keeps the row. Google's matched lines
  # only: the row names Google's deciding line.
  apart <- paste0("User-agent: A\nUser-agent: B\nDisallow: /my/\n",
                  "Allow: */sss/\n\nUser-agent: B\nDisallow: /my/*\n")
  expect_false(ar_code %in% ar_codes(apart))
  lines <- vapply(c("A", "B"), function(token) {
    robots_evaluate_text_v1(apart, "https://example.com/my/", token,
                            "google", "google")$results$matched_line
  }, 0L)
  expect_identical(unname(lines), c(3L, 7L))
  d <- ar_diag(sub("Allow: */sss/\n", "Allow: */sss/\nDisallow: /zz/\n",
                   apart, fixed = TRUE))
  expect_identical(d$message[d$code == ar_code], paste0(
    ar_one(4L, "*/sss/", "/zz/", "/sss/", 5L), ar_note("'A' and 'B'")
  ))
  # A Disallow only another crawler has is no control for this one.
  expect_false(ar_code %in% ar_codes(ar_body("cross_group")))
  expect_false(ar_code %in% ar_codes(ar_body("star_group")))
})

test_that("ROBO-micbpqbc: the scans make each exclusion", {
  shape <- c("*/x/", "/*/x/", "/**/x$", "*/x/$", "**/a", "*/x?p=", "/*/a*b",
             "/*/a*")
  # A final run of `*` names no byte: `/*/*` matches what `/*/` matches.
  not_shape <- c("/*/", "/*/$", "*/", "/*.css", "*?next=", "/my/*x", "/x/*/y",
                 "*", "/*", "*/$", "x*/y", "/*/*", "/*/**", "*/*$")
  expect_false(ar_code %in%
                 ar_codes("User-agent: *\nDisallow: /c\nAllow: /*/*\n"))
  for (backend in names(ar_engines)) {
    paths <- c("/c", "/c?q=/x", "/c/x", "/cx")
    expect_identical(
      ar_decide("User-agent: %s\nDisallow: /c\nAllow: /*/*\n", paths, backend),
      ar_decide("User-agent: %s\nDisallow: /c\nAllow: /*/\n", paths, backend),
      label = backend
    )
  }
  groups <- ar_groups(paste0("User-agent: *\n",
                             paste0("Allow: ", c(shape, not_shape), "\n",
                                    collapse = ""),
                             "Allow:\nDisallow: */x/\n"))
  expect_identical(groups$rules$value[seq_along(shape)], shape)
  expect_identical(reopen_shape(groups$rules), seq_along(shape))
  expect_identical(reopen_literal(shape),
                   c("/x/", "/x/", "/x", "/x/", "/a", "/x?p=", "/axb", "/ax"))
  controls <- c("/a", "/a/", "*/b", "/a*b", "/a%41", "/a.b", "/a/x..")
  misses <- c("/a?", "/a/$", "/a$", "/a/./", "/a/..", "/a/%2E/", "/a%4",
              "/a%", "x", "")
  groups <- ar_groups(paste0("User-agent: *\n",
                             paste0("Disallow: ", c(controls, misses), "\n",
                                    collapse = ""),
                             "Allow: /a/\n"))
  found <- reopen_controls(groups$rules)
  expect_identical(found$at, seq_along(controls))
  expect_identical(found$control,
                   c("/a", "/a/", "/x/b", "/axb", "/a%41", "/a.b", "/a/x.."))
  # The URL-safety scan, shared with rule_end_anchor_query.
  expect_identical(
    url_safe_path(c("/a", "/a b", "/a", "/a", "/a", "/a"),
                  c("/a", "/a b", "/a/./", "/a/%2e%2E", "/a%4", "/a%41")),
    c(TRUE, FALSE, FALSE, TRUE, FALSE, TRUE)
  )
  # No shape-A Allow: an empty frame before any expander is built.
  local({
    local_mocked_bindings(validation_token_expander = function(...) {
      stop("expander built")
    })
    found <- allow_reopens_diagnostics(ar_groups(
      "User-agent: *\nDisallow: /a/\nAllow: /a/b\n"
    ))
    expect_identical(nrow(found), 0L)
    expect_named(found, c("line", "type", "message", "directive"))
    # Shape-A Allows but no control: no pair, and no expander either.
    found <- allow_reopens_diagnostics(ar_groups(
      "User-agent: *\nDisallow: /a$\nDisallow: /*?b=\nAllow: */c/\n"
    ))
    expect_identical(nrow(found), 0L)
    expect_null(attr(found, "stopped"))
  })
})

# Bytes no URL a crawler sends carries, built in code inside an Allow and a
# Disallow.
ar_odd_bytes <- list(space = as.raw(0x20), tab = as.raw(0x09),
                     control = as.raw(0x01), del = as.raw(0x7f))

test_that("ROBO-micbpqbc: a value no URL carries gets no row", {
  for (name in names(ar_odd_bytes)) {
    byte <- ar_odd_bytes[[name]]
    allow <- c(charToRaw("User-agent: *\nDisallow: /my/\nAllow: */a"), byte,
               charToRaw("b/\n"))
    disallow <- c(charToRaw("User-agent: *\nDisallow: /a"), byte,
                  charToRaw("b/\nAllow: */s/\n"))
    expect_false(ar_code %in% ar_codes(allow), label = name)
    expect_false(ar_code %in% ar_codes(disallow), label = name)
  }
  for (name in c("dot_disallow", "dot_allow", "dot_escaped_allow",
                 "stray_disallow", "stray_allow")) {
    expect_false(ar_code %in% ar_codes(ar_body(name)), label = name)
  }
})

# A body cut at max_bytes, whose cut line could have decided the witness.
ar_cut_text <- paste0("User-agent: *\nDisallow: /my/\nAllow: */s/\n",
                      "Disallow: /later-", strrep("x", 200L), "\n")

test_that("ROBO-micbpqbc: a cut body is skipped, a NUL body is Google's", {
  body <- charToRaw(ar_cut_text)[seq_len(45L)]
  x <- validate_document_bytes(body, "s", "supplied", max_bytes = 45L,
                               body_truncated = TRUE)
  expect_false(ar_code %in% x$diagnostics$code)
  # The same bytes, not marked cut, get the row.
  x <- validate_document_bytes(body, "s", "supplied")
  expect_identical(x$diagnostics$message[x$diagnostics$code == ar_code],
                   ar_one(3L, "*/s/", "/my/", "/s/", 2L))
  # An Allow and a Disallow a NUL cuts take part as Google cuts them, and
  # the row says it is Google's reading. Not testable on Bing and Yandex:
  # the evaluator takes a string, which cannot hold the NUL.
  allow <- c(charToRaw("User-agent: *\nDisallow: /my/\nAllow: */s/"),
             as.raw(0), charToRaw("zz\n"))
  d <- ar_diag(allow)
  expect_identical(d$code, c("nul_byte", "rule_cut_by_nul", ar_split, ar_code))
  expect_identical(d$message[[4L]],
                   paste0(ar_one(3L, "*/s/", "/my/", "/s/", 2L), ar_nul))
  disallow <- c(charToRaw("User-agent: *\nDisallow: /my/"), as.raw(0),
                charToRaw("zz\nAllow: */s/\n"))
  d <- ar_diag(disallow)
  expect_identical(d$message[d$code == ar_code],
                   paste0(ar_one(3L, "*/s/", "/my/", "/s/", 2L), ar_nul))
  # The length filter reads the Allow as Google cuts it: `*/s/` is shorter
  # than `/abcde/`, whatever the NUL cuts off.
  short <- c(charToRaw("User-agent: *\nDisallow: /abcde/\nAllow: */s/"),
             as.raw(0), charToRaw(strrep("z", 20L)), charToRaw("\n"))
  expect_false(ar_code %in% ar_codes(short))
})

test_that("ROBO-micbpqbc: the length filter changes no row", {
  # A tie gives a row, one byte shorter none, with the filter on or off.
  for (filter in c(TRUE, FALSE)) {
    found <- allow_reopens_diagnostics(ar_groups(ar_body("tie")),
                                       filter = filter)
    expect_identical(found$line, 1L, label = filter)
    found <- allow_reopens_diagnostics(ar_groups(ar_body("shorter")),
                                       filter = filter)
    expect_identical(nrow(found), 0L, label = filter)
  }
  # Seeded synthetic files: the same rows with the filter on and off.
  disallows <- c("/a/", "/ab/", "/abc/", "/a", "/*/a/", "/b/x/", "/abcdefg/",
                 "/a/?q=/b/", "/a/$", "/b/")
  allows <- c("*/b/", "*/ab/", "/*/b/x/", "*/abc/$", "*/b", "/a/?", "*/a/b/",
              "/**/bb/", "/b/")
  agents <- c("*", "Foo", "Bar", "Foo web")
  set.seed(20261122)
  rows <- 0L
  for (i in 1:40) {
    body <- paste(vapply(1:3, function(g) {
      ua <- paste0("User-agent: ", sample(agents, sample(1:2, 1L)), "\n",
                   collapse = "")
      rules <- c(paste0("Disallow: ", sample(disallows, 3L)),
                 paste0("Allow: ", sample(allows, 2L)))
      paste0(ua, paste0(sample(rules), "\n", collapse = ""))
    }, ""), collapse = "\n")
    groups <- ar_groups(body)
    on <- allow_reopens_diagnostics(groups, budget = Inf)
    off <- allow_reopens_diagnostics(groups, budget = Inf, filter = FALSE)
    expect_identical(on, off, label = body)
    rows <- rows + nrow(on)
  }
  # The files do report: the comparison is not vacuous.
  expect_gt(rows, 10L)
})

# The counts a check that stopped hands out, as slash_stop() builds them.
ar_stopped <- function(found, checked, value) {
  list(found = found, checked = checked, skipped = found - checked,
       value = value)
}

ar_stop_text <- function(found, value, done) {
  rules <- if (found == 1L) {
    "1 Allow rule that opens with '*' or '/*' and then names a path"
  } else {
    sprintf("%d Allow rules that open with '*' or '/*' and then name a path",
            found)
  }
  paste0(
    "This file has ", rules, ", such as '", value, "'. For each one, the ",
    "validator checks whether it also matches inside a URL's query and so ",
    "allows a URL that a Disallow blocks without the query. This file is ",
    "too large to check ", done
  )
}

test_that("ROBO-micbpqbc: Allows past the work budget get no row", {
  # A round's half holds the take, 3 (a group and a Disallow gathered, one
  # entry passed), and the first reading, 5 (a row, the class's two rules,
  # two body lines); the removal read costs 3 of the rest. From 16 the
  # first round fits; below, the next round has less.
  groups <- ar_groups("User-agent: Foo\nDisallow: /my/\nAllow: */s/\n")
  for (budget in list(NULL, 16)) {
    found <- allow_reopens_diagnostics(groups, budget = budget)
    expect_identical(found$line, 1L)
    expect_null(attr(found, "stopped"))
  }
  found <- allow_reopens_diagnostics(groups, budget = 15)
  expect_identical(nrow(found), 0L)
  stop <- attr(found, "stopped")
  expect_identical(stop, ar_stopped(1L, 0L, "*/s/"))
  expect_identical(slash_stop_message("allow_reopen", stop), paste0(
    ar_stop_text(1L, "*/s/", "it quickly, so it was not checked."),
    " It was skipped, and it may do the same."
  ))
  # Allows are checked in line order: the second runs out.
  groups <- ar_groups(
    "User-agent: Foo\nDisallow: /my/\nAllow: */s/\nAllow: */t/\n"
  )
  found <- allow_reopens_diagnostics(groups, budget = 22)
  expect_identical(found$message, ar_one(3L, "*/s/", "/my/", "/s/", 2L))
  stop <- attr(found, "stopped")
  expect_identical(stop, ar_stopped(2L, 1L, "*/t/"))
  expect_identical(slash_stop_message("allow_reopen", stop), paste0(
    ar_stop_text(2L, "*/t/", paste0(
      "them all quickly, so only the first was checked, in line order."
    )),
    " The other 1 was skipped, and it may do the same."
  ))
  # The rounds read Allows out of line order: `*/tttttttt/` proves on its
  # first pair while `*/ssssss/`, whose witnesses a longer Disallow blocks,
  # is still reading its twenty, and runs out. No Allow counts as checked,
  # so the later one gets no row either. From 320 the rounds, doubling
  # each Allow's pairs, read all twenty-one.
  groups <- ar_groups(paste0("User-agent: Foo\n",
                             paste0("Disallow: /d", 1:20, "/\n", collapse = ""),
                             "Disallow: /*?q=/ssssss/\n",
                             "Allow: */ssssss/\nAllow: */tttttttt/\n"))
  found <- allow_reopens_diagnostics(groups, budget = 200)
  expect_identical(nrow(found), 0L)
  expect_identical(attr(found, "stopped"), ar_stopped(2L, 0L, "*/ssssss/"))
  found <- allow_reopens_diagnostics(groups, budget = 320)
  expect_match(found$message, "The Allow on line 24 ('*/tttttttt/')",
               fixed = TRUE)
  expect_null(attr(found, "stopped"))
  # The removal read reads the Allow's crawlers, here one class, at 3 (a
  # row, the class's one live rule, one body line), not the three classes
  # of the deciding Disallow's group (11): from 18 the take (4: two groups
  # and a Disallow gathered, one entry passed) and the first reading (5)
  # fit their half, and the removal read fits the rest.
  groups <- ar_groups(paste0("User-agent: Foo\nUser-agent: Bar\n",
                             "User-agent: Baz\nDisallow: /my/\n\n",
                             "User-agent: Foo\nAllow: */s/\n\n",
                             "User-agent: Bar\nDisallow: /zz?\n\n",
                             "User-agent: Baz\nDisallow: /zz?\n"))
  found <- allow_reopens_diagnostics(groups, budget = 17)
  expect_identical(nrow(found), 0L)
  expect_identical(attr(found, "stopped"), ar_stopped(1L, 0L, "*/s/"))
  for (budget in c(18, 24)) {
    found <- allow_reopens_diagnostics(groups, budget = budget)
    expect_identical(found$line, 6L, label = budget)
    expect_null(attr(found, "stopped"))
  }
  # A normal file gets no such row.
  for (name in names(ar_fixtures)) {
    expect_false("rule_check_stopped" %in% ar_codes(ar_body(name)),
                 label = name)
  }
})

# Shapes where the pairs alone would grow with Disallows times Allows:
# `n` Disallows and `n` long shape-A Allows in one group, whose literals
# share a gram with every witness (`cross`), Allows named like the
# Disallows (`gram`), one group naming `n` crawlers that each have a group
# of their own (`classes`), pairs in one group beside a cut value, so
# both merges are read (`cut`), and pairs that all fail, a longer Disallow
# blocking every witness, so every Allow reads its whole list in rounds
# (`fail`).
ar_shape <- function(shape, n) {
  k <- seq_len(n)
  switch(
    shape,
    cross = paste0("User-agent: *\n",
                   paste0("Disallow: /d", k, "/\n", collapse = ""),
                   paste0("Allow: */aaaaaa", k, "/\n", collapse = "")),
    gram = paste0("User-agent: *\n",
                  paste0("Disallow: /page", k, "/\n", collapse = ""),
                  paste0("Allow: */page", k, "x/\n", collapse = "")),
    classes = paste0(paste0("User-agent: bot", k, "\n", collapse = ""),
                     paste0("Allow: */a", k, "x/\nDisallow: /d", k, "/\n",
                            collapse = ""), "\n",
                     paste0("User-agent: bot", k, "\nDisallow: /z", k, "\n",
                            collapse = "\n")),
    cut = paste0("User-agent: *\n",
                 paste0("Disallow: /d", k, "/\nAllow: */a", k, "x/\n",
                        collapse = ""),
                 "\nUser-agent: Foo web\nDisallow: /g/\nAllow: */gx/\n"),
    fail = paste0("User-agent: *\n",
                  paste0("Disallow: /d", k, "/\n", collapse = ""),
                  "Disallow: /*?q=/aaaaaa*\n",
                  paste0("Allow: */aaaaaa", k, "/\n", collapse = ""))
  )
}

test_that("ROBO-micbpqbc: a file too large for the check gets the row", {
  # Each witness holds a gram of every Allow, so each body holds every
  # Allow: the body lines grow with Allows times Allows.
  d <- ar_diag(ar_shape("cross", 400L))
  stop <- d[d$code == "rule_check_stopped", , drop = FALSE]
  expect_identical(stop$line, NA_integer_)
  expect_identical(stop$severity, "info")
  expect_identical(stop$directive, NA_character_)
  expect_identical(stop$message, paste0(
    ar_stop_text(400L, "*/aaaaaa86/", paste0(
      "them all quickly, so only the first 85 were checked, in line order."
    )),
    " The other 315 were skipped, and some of them may do the same."
  ))
  # The checked Allows keep their row; none past them.
  expect_identical(d$line[d$code == ar_code], 1L)
  expect_match(d$message[d$code == ar_code],
               "line 402 ('*/aaaaaa1/') allows", fixed = TRUE)
  expect_match(d$message[d$code == ar_code], "'/d1/'.", fixed = TRUE)
  expect_match(d$message[d$code == ar_code],
               "lines 403, 404, 405, 406 and 80 more do the same.",
               fixed = TRUE)
})

# `n` Disallows and `n` Allows in one group, each Allow's first pair
# proving (the reviewer's shape).
ar_square <- function(n, ua = "Foo") {
  k <- seq_len(n)
  paste0("User-agent: ", ua, "\n",
         paste0("Disallow: /d", k, "/\n", collapse = ""),
         paste0("Allow: */a", k, "xxxxxxxx/\n", collapse = ""))
}

test_that("ROBO-micbpqbc: an Allow's pairs are read up to the first proof", {
  # Every Allow is checked and none stops, however many Disallows the
  # crawlers have: an Allow reads the pairs it uses, not all of them.
  for (n in c(50L, 150L, 300L)) {
    for (ua in c("Foo", "Foo extra")) {
      d <- ar_diag(ar_square(n, ua))
      expect_false("rule_check_stopped" %in% d$code, label = n)
      found <- allow_reopens_diagnostics(ar_groups(ar_square(n, ua)))
      expect_null(attr(found, "stopped"), label = n)
      expect_match(found$message, sprintf(
        "line %d ('*/a1xxxxxxxx/') allows '/d1/?q=/a1xxxxxxxx/'", n + 2L
      ), fixed = TRUE)
      expect_match(found$message, sprintf("and %d more", n - 5L),
                   fixed = TRUE)
    }
  }
})

# `allows` Allows `/*/xN/` after 1,001 Disallows, `fails` Disallow/Allow
# ties `/aK` first, whose controls the tie allows, so their pairs fail, then
# the proving `/zz` and the rest of the ties (the reviewer's shape).
ar_late_proof <- function(ua, fails, allows = 30L) {
  k <- seq_len(1000L)
  ties <- paste0("Disallow: /a", k, "\nAllow: /a", k, "\n")
  paste0("User-agent: ", ua, "\n",
         paste(ties[seq_len(fails)], collapse = ""), "Disallow: /zz\n",
         paste(ties[-seq_len(fails)], collapse = ""),
         paste0("Allow: /*/x", seq_len(allows), "/\n", collapse = ""),
         if (grepl(" ", ua, fixed = TRUE)) {
           "\nUser-agent: Foo\nDisallow: /q\n"
         } else {
           ""
         })
}

test_that("ROBO-micbpqbc: a failing pair costs the first Allow no more", {
  # Every Allow proves on `/zz`, past failing pairs; the first Allow reads
  # in rounds like the rest, not its whole list once a pair fails, so the
  # budget left after its proof checks all thirty.
  for (case in list(list("Foo web", 10L), list("Foo", 50L))) {
    found <- allow_reopens_diagnostics(ar_groups(ar_late_proof(case[[1L]],
                                                               case[[2L]])))
    expect_null(attr(found, "stopped"), label = case[[1L]])
    expect_match(found$message, "line 2003 ('/*/x1/') allows '/zz?q=/x1/'",
                 fixed = TRUE, label = case[[1L]])
    expect_match(found$message, "and 25 more do the same.", fixed = TRUE,
                 label = case[[1L]])
  }
})

test_that("ROBO-micbpqbc: reading in rounds changes no row", {
  # Seeded synthetic files, several pairs per Allow: the same rows read in
  # rounds as read all at once.
  disallows <- c("/a/", "/ab/", "/abc/", "/a", "/*/a/", "/b/x/", "/abcdefg/",
                 "/a/?q=/b/", "/a/$", "/b/", "/*?q=/b/", "/c/", "/d/")
  allows <- c("*/b/", "*/ab/", "/*/b/x/", "*/abc/$", "*/b", "/a/?", "*/a/b/",
              "/**/bb/", "/b/", "*/bbbb/")
  agents <- c("*", "Foo", "Bar", "Foo web")
  set.seed(20261123)
  rows <- 0L
  for (i in 1:60) {
    body <- paste(vapply(1:3, function(g) {
      ua <- paste0("User-agent: ", sample(agents, sample(1:2, 1L)), "\n",
                   collapse = "")
      rules <- c(paste0("Disallow: ", sample(disallows, 6L)),
                 paste0("Allow: ", sample(allows, 3L)))
      paste0(ua, paste0(sample(rules), "\n", collapse = ""))
    }, ""), collapse = "\n")
    groups <- ar_groups(body)
    lazy <- allow_reopens_diagnostics(groups, budget = Inf)
    whole <- allow_reopens_diagnostics(groups, budget = Inf, chunk = Inf)
    expect_identical(lazy, whole, label = body)
    expect_identical(allow_reopens_diagnostics(groups), lazy, label = body)
    rows <- rows + nrow(lazy)
  }
  expect_gt(rows, 10L)
})

# How many of a body's shape-A Allows the check reads.
ar_checked <- function(body) {
  found <- allow_reopens_diagnostics(ar_groups(body))
  stop <- attr(found, "stopped")
  if (is.null(stop)) {
    return(length(reopen_shape(ar_groups(body)$rules)))
  }
  stop$checked
}

test_that("ROBO-micbpqbc: a cut value elsewhere leaves the budget whole", {
  # One cut value in its own group makes Google's merge differ from the
  # whole-value one, but not for the group holding the pairs: Google's
  # merge rereads only the groups whose classes differ, so the pairs are
  # read once and as many Allows are checked as without the cut value.
  pairs <- function(n) {
    k <- seq_len(n)
    paste0("User-agent: Foo\n",
           paste0("Disallow: /d", k, "/\n", collapse = ""),
           paste0("Allow: */a", k, "xxxxxxxx/\n", collapse = ""))
  }
  cut <- "\nUser-agent: Mediapartners-Google*\nDisallow: /zz/\n"
  for (body in list(pairs(50L), ar_shape("cross", 100L))) {
    plain <- ar_checked(body)
    with_cut <- ar_checked(paste0(body, cut))
    expect_gt(with_cut, 0L)
    expect_gte(with_cut, plain - 1L)
  }
  # Where the merges differ, both read: Google's merge reads `Foo extra`
  # as Foo, whose `/my/?q=` Disallow blocks the witness.
  body <- paste0("User-agent: Foo extra\nDisallow: /my/\nAllow: */s/\n\n",
                 "User-agent: Foo\nDisallow: /my/?q=\n")
  expect_false(ar_code %in% ar_codes(body))
  groups <- ar_groups(paste0(body, cut))
  expect_identical(merge_differs(groups, groups$rules$group),
                   c(TRUE, TRUE, TRUE, FALSE))
})

test_that("ROBO-micbpqbc: a budget cut in Google's reread gets the row", {
  # The whole-value merge reads `Foo extra` alone, cheaply; Google's reads
  # it as Foo, with 500 more Disallows. Wherever Google's reread runs out,
  # the Allow is not checked: no row, but the stop row says so.
  groups <- ar_groups(paste0(
    "User-agent: Foo extra\nDisallow: /my/\nAllow: */s/\n\n",
    "User-agent: Foo\n", paste0("Disallow: /r", 1:500, "/\n", collapse = "")
  ))
  for (budget in seq(200, 1000, by = 50)) {
    found <- allow_reopens_diagnostics(groups, budget = budget)
    expect_true(nrow(found) > 0L || !is.null(attr(found, "stopped")),
                label = budget)
  }
  expect_identical(nrow(allow_reopens_diagnostics(groups)), 1L)
})

# `n` Disallows and `n` Allows under `Foo extra`, which Google's merge
# reads with the Foo group: both merges read every pair.
ar_both <- function(n) {
  k <- seq_len(n)
  paste0("User-agent: Foo extra\n",
         paste0("Disallow: /d", k, "/\n", collapse = ""),
         paste0("Allow: */a", k, "xxxxxxxx/\n", collapse = ""),
         "\nUser-agent: Foo\nDisallow: /q\n")
}

test_that("ROBO-micbpqbc: both merges read under their share", {
  # The whole-value reading gets its candidates' share of the budget, so
  # Google's reread has the rest; with the whole budget, it would leave
  # Google's none and no Allow would be checked.
  expect_gt(ar_checked(ar_both(300L)), 150L)
  # Google's merge cuts `360Spider` to no token: the group names no
  # crawler there, so its reading holds no class and the pair fails.
  spider <- "User-agent: 360Spider\nDisallow: /my/\nAllow: */s/\n"
  expect_false(ar_code %in% ar_codes(spider))
  # Google's reread reads each Disallow under its Allow's crawlers: under
  # those of the `zzqbot` group, whose `/zz?` would fail the pair, `/my/`
  # would not decide the witness without the Allow.
  d <- ar_diag(paste0(
    "User-agent: zzqbot extra\nUser-agent: otherbot\nDisallow: /my/\n\n",
    "User-agent: zzqbot extra\nAllow: */x/\n\n",
    "User-agent: otherbot\nAllow: /my/?\n\n",
    "User-agent: zzqbot\nDisallow: /zz?\n"
  ))
  expect_identical(d$line[d$code == ar_code], 5L)
  # Google's reread must not open the witness another way: `/my/?` does
  # once the shape-A Allows are left out, on Google's merge only.
  expect_false(ar_code %in% ar_codes(paste0(
    "User-agent: Foo extra\nDisallow: /my/\nAllow: */sss/\n\n",
    "User-agent: Foo\nAllow: /my/?\n"
  )))
})

test_that("ROBO-micbpqbc: the shared reading returns only what both read", {
  groups <- ar_groups(ar_both(20L))
  at <- reopen_shape(groups$rules)
  short <- sprintf("/d%d/", seq_along(at))
  long <- paste0(short, "?q=", reopen_literal(groups$rules$value[at]))
  read <- function(budget, key = NULL) {
    if (is.null(key)) {
      return(witness_pair_readings(groups, at, short, long, "long",
                                   budget = budget, share = TRUE))
    }
    witness_pair_reading(groups, at, groups$agents[[key]], short, long,
                         "long", budget = budget)
  }
  # A budget the whole-value reading's share cuts: Google's reread reads
  # only the candidates it read, and spends what they cost.
  both <- read(200)
  whole <- read(100, "uncut")
  expect_gt(whole$read, 0L)
  expect_lt(whole$read, length(at))
  expect_identical(both$checked, whole$read)
  k <- seq_len(whole$read)
  google <- witness_pair_reading(groups, at[k], groups$agents$key, short[k],
                                 long[k], "long", budget = 200 - whole$spent)
  expect_identical(both$spent, whole$spent + google$spent)
  # Where the merges name other lines deciding the control, the line is
  # NA: `/my/*` decides it on Google's merge only.
  groups <- ar_groups(paste0(
    "User-agent: Foo extra\nDisallow: /my/\nAllow: */sss/\n\n",
    "User-agent: Foo\nDisallow: /my/*\n"
  ))
  at <- reopen_shape(groups$rules)
  one <- witness_pair_reading(groups, at, groups$agents$uncut, "/my/",
                              "/my/?q=/sss/", "long")
  expect_identical(one$line, 2L)
  both <- witness_pair_readings(groups, at, "/my/", "/my/?q=/sss/", "long",
                                share = TRUE)
  expect_true(both$ok)
  expect_identical(both$line, NA_integer_)
})

test_that("ROBO-micbpqbc: the rounds go on while they gather, and no further", {
  # Gathering the Allow's list (a group and 200 Disallows) leaves the first
  # round too little to read its pair. A round that gathers a list moves
  # on: the next one, the list held, reads the pair.
  body <- paste0("User-agent: Foo\n",
                 paste0("Disallow: /d", 1:200, "/\n", collapse = ""),
                 "Allow: */sxxxxxxxx/\n")
  for (budget in c(650, 700, 750, 800)) {
    found <- allow_reopens_diagnostics(ar_groups(body), budget = budget)
    expect_identical(found$line, 1L, label = budget)
    expect_null(attr(found, "stopped"), label = budget)
  }
  # 100 Allows, a tiny budget: the takes stop at the first that does not
  # fit, rather than passing every Allow's entries.
  calls <- new.env()
  calls$n <- 0L
  take <- reopen_take
  local_mocked_bindings(reopen_take = function(...) {
    calls$n <- calls$n + 1L
    take(...)
  })
  found <- allow_reopens_diagnostics(ar_groups(ar_square(100L)), budget = 50)
  expect_identical(attr(found, "stopped"),
                   ar_stopped(100L, 0L, "*/a1xxxxxxxx/"))
  expect_lt(calls$n, 10L)
})

# The best of five runs of `small` and of `large`, taken in turn, so a
# loaded machine slows both alike and cannot fail the ratio
# (test-cut-note-zqyqbudf.R). A floor of 0.1s keeps a fast small run from
# making the bound a few tens of milliseconds.
ar_ratio_ok <- function(small, large, label) {
  times <- vapply(1:5, function(i) {
    c(system.time(small())[["elapsed"]], system.time(large())[["elapsed"]])
  }, numeric(2))
  expect_lt(min(times[2L, ]), 8 * max(min(times[1L, ]), 0.1), label = label)
}

ar_check_fn <- function(body) {
  groups <- ar_groups(body)
  function() allow_reopens_diagnostics(groups)
}

test_that("ROBO-micbpqbc: the check stays linear on costly shapes", {
  skip_on_cran()
  # Each shape stops at the budget rather than growing.
  shapes <- c("cross", "gram", "classes", "cut", "fail")
  for (shape in shapes) {
    found <- allow_reopens_diagnostics(ar_groups(ar_shape(shape, 400L)))
    expect_false(is.null(attr(found, "stopped")), label = shape)
  }
  for (shape in shapes) {
    ar_ratio_ok(ar_check_fn(ar_shape(shape, 100L)),
                ar_check_fn(ar_shape(shape, 400L)), shape)
  }
  # The whole validator too.
  ar_ratio_ok(function() robots_validate_text(ar_shape("cross", 100L)),
              function() robots_validate_text(ar_shape("cross", 400L)),
              "validator")
})

# `n` Disallows and `n` Allows whose witnesses all hold one gram, so every
# wide rule's posting holds every row (`uploads`), or each Allow's pairs
# failing until the last Disallow (`failing`).
ar_wide <- function(shape, n) {
  k <- seq_len(n)
  switch(
    shape,
    uploads = paste0("User-agent: *\n",
                     paste0("Disallow: /d", k, "/\n", collapse = ""),
                     paste0("Allow: */wp-content/uploads/", k, "/\n",
                            collapse = "")),
    failing = paste0("User-agent: *\n",
                     paste0("Disallow: /d", k, "/\nAllow: /d", k, "/$\n",
                            collapse = ""),
                     "Disallow: /last/\n",
                     paste0("Allow: */sitemapxxxxxx", k, "/\n", collapse = ""))
  )
}

test_that("ROBO-micbpqbc: the work stays linear in the file", {
  skip_on_cran()
  # Work units, not time, so load cannot move them: the elements of every
  # vector findInterval() searches. The budget's halving searches the rows
  # each wide rule's posting holds; counted once per rule, that grew with
  # Allows times rows.
  count <- new.env()
  count$n <- 0
  on.exit(suppressMessages(untrace("findInterval", where = baseenv())),
          add = TRUE)
  suppressMessages(trace("findInterval", bquote(assign(
    "n", get("n", envir = .(count)) + length(vec), envir = .(count)
  )), print = FALSE, where = baseenv()))
  bodies <- list(
    uploads = function(n) ar_wide("uploads", n),
    cross = function(n) ar_shape("cross", n),
    failing = function(n) ar_wide("failing", n)
  )
  for (shape in names(bodies)) {
    work <- vapply(c(400L, 1600L, 6400L), function(n) {
      groups <- ar_groups(bodies[[shape]](n))
      count$n <- 0
      found <- allow_reopens_diagnostics(groups)
      expect_false(is.null(attr(found, "stopped")), label = shape)
      count$n
    }, 0)
    expect_lt(work[[2L]], 6 * work[[1L]], label = shape)
    expect_lt(work[[3L]], 6 * work[[2L]], label = shape)
  }
})

# Sets the locale categories for the calling test, restored on exit; skips
# when one is not installed (as pt_local_locale() in
# test-product-token-grammar-mtmkpwuf.R).
ar_local_locale <- function(locale, env = parent.frame()) {
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

# A latin1 byte, a UTF-8 character and an invalid UTF-8 lead byte in the
# Allow's literal, and an upper-case `I` in the values and the crawler
# token, which tr_TR.UTF-8 folds otherwise.
ar_edge <- function() {
  for (byte in list(as.raw(0xe9), as.raw(c(0xc3, 0xa9)), as.raw(0xc3))) {
    body <- c(charToRaw("User-agent: *\nDisallow: /my/\nAllow: */caf"), byte,
              charToRaw("/\n"))
    escaped <- paste0("/caf", paste(sprintf("%%%02X", as.integer(byte)),
                                    collapse = ""), "/")
    d <- ar_diag(body)
    expect_identical(d$message[d$code == ar_code],
                     ar_one(3L, paste0("*", escaped), "/my/", escaped, 2L))
  }
  d <- ar_diag(paste0("User-agent: IndexBot\nDisallow: /INFO/\n",
                      "Allow: */IMAGES/\n\nUser-agent: indexbot\n",
                      "Allow: /x\n"))
  expect_identical(d$message[d$code == ar_code],
                   ar_one(3L, "*/IMAGES/", "/INFO/", "/IMAGES/", 2L))
}

test_that("ROBO-micbpqbc: edge inputs in the session's locale", {
  ar_edge()
  # Google's matcher compares the escaped witness; the package's Bing and
  # Yandex matchers compare the byte as written.
  body <- "User-agent: %s\nDisallow: /my/\nAllow: */caf\u00e9/\n"
  expect_identical(ar_decide(body, c("/my/", "/my/?q=/caf%C3%A9/"), "google"),
                   ar_opened)
  for (backend in c("bing", "yandex")) {
    expect_identical(ar_decide(body, c("/my/", "/my/?q=/caf\u00e9/"),
                               backend), ar_opened, label = backend)
  }
  # Empty values give no pair.
  expect_false(ar_code %in% ar_codes(ar_body("empty_allow")))
  expect_false(ar_code %in% ar_codes("User-agent: *\nDisallow:\nAllow: */s/\n"))
  expect_identical(ar_codes(""), "no_rules")
})

for (locale in c("C", "en_US.UTF-8", "tr_TR.UTF-8")) {
  test_that(paste("ROBO-micbpqbc: edge inputs under", locale), {
    ar_local_locale(locale)
    ar_edge()
  })
}

test_that("ROBO-micbpqbc: a rule at the line buffer keeps its row", {
  # `Allow:` and no space fill the 16,663-byte line buffer: a witness line
  # written `Allow: ` would lose the final `/`.
  long <- strrep("a", 16663L - nchar("Allow:*//"))
  d <- ar_diag(sprintf("User-agent: *\nDisallow: /my/\nAllow:*/%s/\n", long))
  value <- paste0("*/", strrep("a", 34L), "...")
  literal <- paste0("/", strrep("a", 35L), "...")
  expect_identical(d$message[d$code == ar_code],
                   ar_one(3L, value, "/my/", literal, 2L))
  expect_lt(nchar(d$message[d$code == ar_code]), 500L)
})

test_that("ROBO-micbpqbc: the row's length is bounded", {
  # 300 Allows of 200 bytes beside a 200-byte Disallow: each value is cut
  # at 40 bytes and four more lines are named, so the row stays short.
  k <- seq_len(300L)
  body <- paste0("User-agent: Foo\nDisallow: /", strrep("d", 199L), "\n",
                 paste0("Allow: */", k, strrep("a", 199L - nchar(k)), "/\n",
                        collapse = ""))
  d <- ar_diag(body)
  m <- d$message[d$code == ar_code]
  expect_length(m, 1L)
  expect_match(m, "lines 4, 5, 6, 7 and 295 more do the same.", fixed = TRUE)
  expect_lt(nchar(m), 600L)
})

test_that("ROBO-micbpqbc: robots_validate_url() gives the same rows", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, url = req$url, body = ar_body("global"))
  })
  x <- robots_validate_url("https://e.example/page")
  d <- x$diagnostics
  expect_identical(d$code, c(ar_split, ar_code))
  expect_identical(d$message, ar_diag(ar_body("global"))$message)
  expect_identical(x$documents$validation_status, "valid")
})
