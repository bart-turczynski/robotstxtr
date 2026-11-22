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
  lower = list(body = ea_one("/c%2f$"), today = "rule_lowercase_escape"),
  # A `%` that starts no escape: no correctly encoded URL is the control.
  stray = list(body = ea_one("/a%4$"), today = "rule_invalid_percent_escape")
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

# The lines of each fixture's new rows; a fixture not named gets none.
ea_rows <- list(
  positive = 1L, one = 1L, home = 1L, star_led = 1L, slash_end = 1L,
  escaped_dollar = 1L, two_crawlers = 1L, shorter_allow = 1L,
  ai_anchor = 2L, repeated = 1L, seven = 1L, two_sets = c(1L, 4L),
  cut_both = 1L, dup = 1L, lower = 1L
)

test_that("ROBO-nzcvlsvk: each fixture's new rows are all the change", {
  expect_true(all(names(ea_rows) %in% names(ea_fixtures)))
  for (name in names(ea_fixtures)) {
    d <- ea_diag(ea_body(name))
    rows <- ea_rows[[name]]
    if (is.null(rows)) {
      rows <- integer(0)
    }
    # The check's rows come after every row the file had before.
    expect_identical(d$code, c(ea_fixtures[[name]]$today,
                               rep(ea_code, length(rows))), label = name)
    expect_identical(d$line[d$code == ea_code], rows, label = name)
  }
})

ea_why <- function(rule = "the rule") {
  paste0(" A final '$' ends the match at the end of the path and query ",
         "together, so the query shown takes the URL out of ", rule,
         ". The site may serve the same page with a query.")
}

ea_one_message <- function(line, control, query = "?x=1") {
  sprintf("The Disallow on line %d blocks '%s' but not '%s%s'.%s", line,
          control, control, query, ea_why())
}

ea_list_message <- function(listed) {
  paste0("These Disallows block a path but not the same path with a query ",
         "added: ", listed, ".", ea_why("each rule"))
}

ea_blocks <- function(line, control, query = "?x=1") {
  sprintf("line %d blocks '%s' but not '%s%s'", line, control, control, query)
}

ea_note <- function(names) {
  sprintf(" This holds for every crawler the group names: %s.", names)
}

ea_nul <- paste0(" This is Google's reading, which ends each line at its ",
                 "first NUL; Bing and Yandex read the NUL as an ordinary ",
                 "byte.")

test_that("ROBO-nzcvlsvk: one info row per group, on its User-agent line", {
  x <- robots_validate_text(ea_body("positive"))
  d <- x$diagnostics
  expect_identical(d$severity, "info")
  expect_identical(d$directive, "user-agent")
  expect_identical(d$raw_text, "User-agent: Foo")
  expect_identical(d$message, ea_list_message(paste0(
    ea_blocks(2L, "/@me"), ", ", ea_blocks(3L, "/x/edit"), " and ",
    ea_blocks(4L, "/x/x/edit")
  )))
  expect_identical(x$documents$validation_status, "valid")
  # No "broken" or "bypass" wording; "may" where the site decides.
  expect_false(grepl("broken|bypass", d$message))
  expect_match(d$message, "The site may serve", fixed = TRUE)
  expect_identical(ea_diag(ea_body("one"))$message,
                   ea_one_message(2L, "/x/edit"))
  # The home page alone, a `*`-led value, a final `/` and an escape.
  expect_identical(ea_diag(ea_body("home"))$message, ea_one_message(2L, "/"))
  expect_identical(ea_diag(ea_body("star_led"))$message,
                   ea_one_message(2L, "/x/edit"))
  expect_identical(ea_diag(ea_body("slash_end"))$message,
                   ea_one_message(2L, "/x/"))
  expect_identical(ea_diag(ea_body("escaped_dollar"))$message,
                   ea_one_message(2L, "/a%24"))
  # A shorter Allow loses the control and wins the witness.
  expect_identical(ea_diag(ea_body("shorter_allow"))$message,
                   ea_one_message(2L, "/@me"))
  # A repeat decides nothing: only the first line is named.
  d <- ea_diag(ea_body("dup"))
  expect_identical(d$message[d$code == ea_code], ea_one_message(2L, "/a"))
})

test_that("ROBO-nzcvlsvk: rows group by crawler set, five rules listed", {
  d <- ea_diag(ea_body("seven"))
  expect_identical(d$message, ea_list_message(paste0(
    ea_blocks(2L, "/a"), ", ", ea_blocks(3L, "/b"), ", ", ea_blocks(4L, "/c"),
    ", ", ea_blocks(5L, "/d"), ", ", ea_blocks(6L, "/e"), " and 2 more"
  )))
  # Merged repeated groups give one row.
  d <- ea_diag(ea_body("repeated"))
  expect_identical(d$message[d$code == ea_code], ea_list_message(paste0(
    ea_blocks(2L, "/a"), " and ", ea_blocks(5L, "/b")
  )))
  # Two groups naming the same crawler share a row; other crawlers do not.
  d <- ea_diag(paste0("User-agent: Foo\nDisallow: /a$\n\nUser-agent: Bar\n",
                      "Disallow: /b$\n\nUser-agent: Foo\nDisallow: /c$\n"))
  d <- d[d$code == ea_code, , drop = FALSE]
  expect_identical(d$line, c(1L, 4L))
  expect_identical(d$message, c(
    ea_list_message(paste0(ea_blocks(2L, "/a"), " and ", ea_blocks(8L, "/c"))),
    ea_one_message(5L, "/b")
  ))
  d <- ea_diag(ea_body("two_sets"))
  expect_identical(d$message[d$code == ea_code],
                   c(ea_one_message(2L, "/a"), ea_one_message(5L, "/b")))
  # A group naming several crawlers names them.
  expect_identical(ea_diag(ea_body("two_crawlers"))$message,
                   paste0(ea_one_message(3L, "/a"), ea_note("'Foo' and 'Bar'")))
})

test_that("ROBO-nzcvlsvk: the AI-training policy token gets no row", {
  expect_identical(ea_codes(ea_body("ai")), "ai_training_preference")
  # The row sits on the first User-agent line the check reads.
  d <- ea_diag(ea_body("ai_anchor"))
  d <- d[d$code == ea_code, , drop = FALSE]
  expect_identical(d$raw_text, "User-agent: Foo")
  expect_identical(d$message, ea_one_message(3L, "/x"))
})

# The reading of each merge, as the shared reader gives it.
ea_groups <- function(body) {
  validation_groups(as.data.frame(
    robotstxtr_validation_parse_(charToRaw(body)),
    stringsAsFactors = FALSE
  ))
}

ea_ok <- function(body, key) {
  groups <- ea_groups(body)
  at <- end_anchor_candidates(groups$rules)
  control <- end_anchor_controls(groups$rules$value[at])
  witness_pair_reading(groups, at, groups$agents[[key]], control,
                       paste0(control, "?x=1"), "short")$ok
}

test_that("ROBO-nzcvlsvk: every class on both merges must agree", {
  # `B` also blocks the witness: no row for the group naming A and B.
  expect_identical(ea_codes(ea_body("class_disagree")),
                   "user_agent_repeated_group")
  # Google's merge reads `Foo web` and `Foo blog` as one crawler; the
  # whole-value merge keeps them apart. Each fixture fails on one merge.
  body <- ea_body("cut_uncut_fails")
  expect_false(ea_ok(body, "uncut"))
  expect_true(ea_ok(body, "key"))
  body <- ea_body("cut_google_fails")
  expect_true(ea_ok(body, "uncut"))
  expect_false(ea_ok(body, "key"))
  body <- ea_body("cut_both")
  expect_true(ea_ok(body, "uncut"))
  expect_true(ea_ok(body, "key"))
})

test_that("ROBO-nzcvlsvk: the scan makes each exclusion", {
  misses <- c("/a$b", "/a$$", "/a%24", "/search?q$", "/s?q=1$", "/*$", "*$",
              "/a*$", "/a/.$", "/a/..$", "/a/%2E$", "/*/../x$", "x$", "$",
              "/a", "/a*", "/a%$", "/a%4$", "/a%4*b$", "/%%41$")
  groups <- ea_groups(paste0("User-agent: *\n",
                             paste0("Disallow: ", misses, "\n",
                                    collapse = ""),
                             "Disallow:\nAllow: /b$\n"))
  expect_identical(groups$rules$value[seq_along(misses)], misses)
  expect_identical(end_anchor_candidates(groups$rules), integer(0))
  hits <- c("/a$", "*/b$", "/$", "/a/$", "/a%24$", "/a.b$", "/a/.b$",
            "/a*b$", "/a/x..$")
  groups <- ea_groups(paste0("User-agent: *\n",
                             paste0("Disallow: ", hits, "\n", collapse = "")))
  expect_identical(end_anchor_candidates(groups$rules), seq_along(hits))
  expect_identical(end_anchor_controls(hits),
                   c("/a", "/x/b", "/", "/a/", "/a%24", "/a.b", "/a/.b",
                     "/axb", "/a/x.."))
  # No candidate: an empty frame before any expander is built.
  local({
    local_mocked_bindings(validation_token_expander = function(...) {
      stop("expander built")
    })
    found <- end_anchor_diagnostics(ea_groups("User-agent: *\nDisallow: /a\n"))
    expect_identical(nrow(found), 0L)
    expect_named(found, c("line", "type", "message", "directive"))
  })
})

# A body cut at max_bytes, whose cut line could have blocked the witness.
ea_cut_text <- paste0("User-agent: *\nDisallow: /a$\nDisallow: /later-",
                      strrep("x", 200L), "\n")

test_that("ROBO-nzcvlsvk: a cut body is skipped, a NUL body is Google's", {
  body <- charToRaw(ea_cut_text)[seq_len(40L)]
  x <- validate_document_bytes(body, "s", "supplied", max_bytes = 40L,
                               body_truncated = TRUE)
  expect_identical(x$diagnostics$code, "body_truncated")
  # The same bytes, not marked cut, get the row.
  x <- validate_document_bytes(body, "s", "supplied")
  expect_identical(x$diagnostics$code, ea_code)
  expect_identical(x$diagnostics$message, ea_one_message(2L, "/a"))
  # Not testable on Bing and Yandex: the NUL sentence is about the reading,
  # and the rule the row names holds no NUL.
  nul <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0),
           charToRaw("zz\nDisallow: /b$\n"))
  d <- ea_diag(nul)
  expect_identical(d$code, c("nul_byte", "rule_cut_by_nul", ea_code))
  expect_identical(d$message[[3L]], paste0(ea_one_message(3L, "/b"), ea_nul))
})

test_that("ROBO-nzcvlsvk: edge inputs", {
  # A latin1 byte and a UTF-8 character are escaped in the canonical value,
  # and the control shows the escape.
  for (byte in list(as.raw(0xe9), as.raw(c(0xc3, 0xa9)))) {
    body <- c(charToRaw("User-agent: *\nDisallow: /caf"), byte,
              charToRaw("$\n"))
    d <- ea_diag(body)
    escaped <- paste0("/caf", paste(sprintf("%%%02X", as.integer(byte)),
                                    collapse = ""))
    expect_identical(d$message[d$code == ea_code],
                     ea_one_message(2L, escaped))
  }
  # An empty body gets no row.
  expect_identical(ea_codes(""), "no_rules")
  # A rule at the line buffer: `disalow:` and no space fill it, so a witness
  # line written `Disallow:` would lose the final `$`, match the witness and
  # silence the row.
  long <- strrep("a", 16653L)
  d <- ea_diag(sprintf("User-agent: *\ndisalow:/%s$\n", long))
  shown <- paste0("/", strrep("a", 35L), "...")
  expect_identical(d$code, c("accepted_directive_typo", ea_code))
  expect_identical(d$message[[2L]], ea_one_message(2L, shown))
  expect_lt(nchar(d$message[[2L]]), 400L)
})

test_that("ROBO-nzcvlsvk: robots_validate_url() gives the same rows", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, url = req$url, body = ea_body("positive"))
  })
  x <- robots_validate_url("https://e.example/page")
  d <- x$diagnostics
  expect_identical(d$code, ea_code)
  expect_identical(d$message,
                   ea_diag(ea_body("positive"))$message)
  expect_identical(x$documents$validation_status, "valid")
})

# The crossing check: how each backend decides the control and the witness.
# Default `url_normalization` ("rfc3986"): the paths hold no dot segment, so
# it removes nothing.
ea_engines <- list(google = "Googlebot", bing = "bingbot", yandex = "Yandex")

ea_decide <- function(body, paths, backend) {
  token <- ea_engines[[backend]]
  robots_evaluate_text_v1(
    gsub("%s", token, body, fixed = TRUE),
    paste0("https://example.com", paths), token, backend, backend
  )$results$url_decision
}

# Fixture, the paths and the decisions every backend gives them, with any
# backend that decides otherwise.
ea_blocked <- c("disallow", "allow")
ea_decisions <- list(
  list("positive", c("/@me", "/@me?x=1", "/x/edit", "/x/edit?x=1",
                     "/x/x/edit", "/x/x/edit?x=1"), rep(ea_blocked, 3L)),
  list("one", c("/x/edit", "/x/edit?x=1"), ea_blocked),
  list("home", c("/", "/?x=1"), ea_blocked),
  list("star_led", c("/x/edit", "/x/edit?x=1"), ea_blocked),
  list("slash_end", c("/x/", "/x/?x=1"), ea_blocked),
  list("escaped_dollar", c("/a%24", "/a%24?x=1"), ea_blocked),
  # A backend disagreement: the package's Yandex matcher lets `Allow: /@me`
  # win over `Disallow: /@me$` for `/@me`, where Google and Bing take the
  # longer `/@me$` (as in test-slash-pair-split-roypaoox.R). The check
  # decides on Google's matcher.
  list("shorter_allow", c("/@me", "/@me?x=1"), ea_blocked,
       list(yandex = c("allow", "allow"))),
  list("dup", c("/a", "/a?x=1"), ea_blocked),
  list("seven", c("/g", "/g?x=1"), ea_blocked),
  # Silent: the witness is blocked too, or the control is allowed.
  list("query_blocked", c("/@me", "/@me?x=1"), c("disallow", "disallow")),
  list("star_query_blocked", c("/@me", "/@me?x=1"),
       c("disallow", "disallow")),
  list("tie", c("/@me", "/@me?x=1"), c("allow", "allow")),
  list("longer_allow", c("/@me", "/@me?x=1"), c("allow", "allow")),
  # `*` before the `$` matches the query too.
  list("star_end", c("/x", "/x?x=1"), c("disallow", "disallow")),
  list("word_star_end", c("/ab", "/ab?x=1"), c("disallow", "disallow")),
  # The package's Yandex matcher compares a lower-case escape as written,
  # so the upper-case control is not blocked there (rule_lowercase_escape).
  # The check decides on Google's matcher.
  list("lower", c("/c%2F", "/c%2F?x=1"), ea_blocked,
       list(yandex = c("allow", "allow")))
)

test_that("ROBO-nzcvlsvk: every backend decides the control and witness", {
  for (backend in names(ea_engines)) {
    for (case in ea_decisions) {
      expected <- case[[3L]]
      if (length(case) > 3L && !is.null(case[[4L]][[backend]])) {
        expected <- case[[4L]][[backend]]
      }
      expect_identical(ea_decide(ea_fixtures[[case[[1L]]]]$body, case[[2L]],
                                 backend),
                       expected, label = paste(backend, case[[1L]]))
    }
  }
})

test_that("ROBO-nzcvlsvk: a non-ASCII control on each backend", {
  # Google's matcher compares the pattern with each non-ASCII byte escaped,
  # as the canonical value writes it; the package's Bing and Yandex matchers
  # compare the byte as written, so they block the raw path instead. On
  # each, the query escapes the `$`.
  body <- "User-agent: %s\nDisallow: /caf\u00e9$\n"
  expect_identical(ea_decide(body, c("/caf%C3%A9", "/caf%C3%A9?x=1"),
                             "google"), ea_blocked)
  for (backend in c("bing", "yandex")) {
    expect_identical(ea_decide(body, c("/caf\u00e9", "/caf\u00e9?x=1"),
                               backend), ea_blocked, label = backend)
  }
})

# The counts a check that stopped hands out, as slash_stop() builds them.
ea_stopped <- function(found, checked, value) {
  list(found = found, checked = checked, skipped = found - checked,
       value = value)
}

test_that("ROBO-nzcvlsvk: candidates past the work budget get no row", {
  # Each candidate is one (candidate, class) read, the first also pays once
  # for its class's two rules, and each witness body holds one line: 3 and
  # 1 to plan, then 1 and 1 to read. Candidates are read in line order.
  groups <- ea_groups("User-agent: Foo\nDisallow: /a$\nDisallow: /b$\n")
  for (budget in list(NULL, 6)) {
    found <- end_anchor_diagnostics(groups, budget = budget)
    expect_identical(found$message, ea_list_message(paste0(
      ea_blocks(2L, "/a"), " and ", ea_blocks(3L, "/b")
    )))
    expect_null(attr(found, "stopped"))
  }
  found <- end_anchor_diagnostics(groups, budget = 5)
  expect_identical(found$message, ea_one_message(2L, "/a"))
  stop <- attr(found, "stopped")
  expect_identical(stop, ea_stopped(2L, 1L, "/b$"))
  expect_identical(slash_stop_message("end_anchor", stop), paste0(
    "This file has 2 Disallow rules whose pattern ends in '$' and has no ",
    "'?' before it, such as '/b$'. For each one, the validator checks ",
    "whether the rule blocks '/b' but not '/b?x=1'. This file is too large to check them all quickly, so ",
    "only the first was checked, in line order. The other 1 was skipped, ",
    "and it may have the same problem."
  ))
  # The plan fits, but no body line does: none checked.
  found <- end_anchor_diagnostics(groups, budget = 4)
  expect_identical(nrow(found), 0L)
  expect_identical(attr(found, "stopped"), ea_stopped(2L, 0L, "/a$"))
  # A cut value makes two readings, and they share the budget: each costs 2
  # to plan and 1 to read, so 6 reads both and 5 leaves the second short.
  groups <- ea_groups("User-agent: Foo web\nDisallow: /a$\n")
  expect_identical(end_anchor_diagnostics(groups, budget = 6)$line, 1L)
  found <- end_anchor_diagnostics(groups, budget = 5)
  expect_identical(nrow(found), 0L)
  stop <- attr(found, "stopped")
  expect_identical(stop, ea_stopped(1L, 0L, "/a$"))
  expect_identical(slash_stop_message("end_anchor", stop), paste0(
    "This file has 1 Disallow rule whose pattern ends in '$' and has no '?' ",
    "before it, such as '/a$'. For each one, the validator checks whether ",
    "the rule blocks '/a' but not '/a?x=1'. This file is too large to check it quickly, so it was ",
    "not checked. It was skipped, and it may have the same problem."
  ))
  # A normal file gets no such row.
  for (name in names(ea_fixtures)) {
    expect_false("rule_check_stopped" %in% ea_codes(ea_body(name)),
                 label = name)
  }
})

# Shapes where the reads alone would grow faster than the input: rules
# whose head `/` or later fragment every control and witness share
# (`wild`, `gram`, `locale`), one group naming `n` crawlers that each have
# a group of their own, so every candidate is read once per class
# (`classes`), and rules of every kind in one group with a cut value, so
# both merges are read (`rules`).
ea_shape <- function(shape, n) {
  k <- seq_len(n)
  switch(
    shape,
    rules = paste0(
      "User-agent: *\n",
      paste0("Disallow: /d", k[k %% 4L == 0L], "$\nDisallow: /e", k, "\n",
             collapse = ""),
      "\nUser-agent: Foo web\nDisallow: /g$\n"
    ),
    wild = paste0("User-agent: *\n",
                  paste0("Disallow: /c", k, "$\n", collapse = ""),
                  paste0("Disallow: /*?f", k, "=\n", collapse = ""),
                  paste0("Allow: /*/f", k, "/\n", collapse = "")),
    gram = paste0("User-agent: *\n",
                  paste0("Disallow: /page", k, "$\n", collapse = ""),
                  paste0("Disallow: /*page", k, "-print\n", collapse = "")),
    locale = paste0("User-agent: *\n",
                    paste0("Disallow: /c", k, "$\n", collapse = ""),
                    paste0("Allow: /*/c", k, "\n", collapse = "")),
    classes = paste0(paste0("User-agent: bot", k, "\n", collapse = ""),
                     paste0("Disallow: /d", k, "$\n", collapse = ""), "\n",
                     paste0("User-agent: bot", k, "\nDisallow: /z", k, "\n",
                            collapse = "\n"))
  )
}

test_that("ROBO-nzcvlsvk: a file too large for the check gets the row", {
  d <- ea_diag(ea_shape("classes", 250L))
  stop <- d[d$code == "rule_check_stopped", , drop = FALSE]
  expect_identical(stop$line, NA_integer_)
  expect_identical(stop$severity, "info")
  expect_identical(stop$directive, NA_character_)
  expect_identical(stop$raw_text, NA_character_)
  expect_identical(stop$message, paste0(
    "This file has 250 Disallow rules whose pattern ends in '$' and has no ",
    "'?' before it, such as '/d1$'. For each one, the validator checks ",
    "whether the rule blocks '/d1' but not '/d1?x=1'. This file is too large to check them all ",
    "quickly, so none of them were checked. All 250 were skipped, and some ",
    "of them may have the same problem."
  ))
  expect_false(ea_code %in% d$code)
})

# Best of five runs, so a loaded machine cannot fail the ratio
# (test-cut-note-zqyqbudf.R).
ea_best <- function(expr_fn) {
  min(vapply(1:5, function(i) system.time(expr_fn())[["elapsed"]], 0))
}

ea_time_check <- function(body, times = 1L) {
  groups <- ea_groups(body)
  ea_best(function() {
    for (k in seq_len(times)) {
      end_anchor_diagnostics(groups)
    }
  })
}

# The smaller input of each shape; the larger is four times it.
ea_sizes <- c(rules = 1000L, wild = 500L, gram = 500L, locale = 500L,
              classes = 250L)

test_that("ROBO-nzcvlsvk: the check stays linear on costly shapes", {
  skip_on_cran()
  # Each shape still reports: the guards time a check that does its work.
  expect_identical(nrow(end_anchor_diagnostics(ea_groups(
    ea_shape("rules", 400L)
  ))), 2L)
  for (shape in c("wild", "gram", "locale")) {
    expect_identical(nrow(end_anchor_diagnostics(ea_groups(
      ea_shape(shape, 100L)
    ))), 1L, label = shape)
  }
  for (shape in names(ea_sizes)) {
    n <- ea_sizes[[shape]]
    small <- ea_time_check(ea_shape(shape, n), 2L)
    large <- ea_time_check(ea_shape(shape, 4L * n), 2L)
    expect_lt(large, 8 * max(small, 0.05), label = shape)
  }
  # The whole validator too.
  small <- ea_best(function() robots_validate_text(ea_shape("rules", 500L)))
  large <- ea_best(function() robots_validate_text(ea_shape("rules", 2000L)))
  expect_lt(large, 8 * max(small, 0.05))
})

# A value that carries the length, inside the 16,663-byte line buffer.
ea_value <- function(n) {
  sprintf("User-agent: *\nDisallow: /%s$\nAllow: /%sc\n", strrep("ab", n),
          strrep("ab", n))
}

test_that("ROBO-nzcvlsvk: the check is linear in the value's length", {
  skip_on_cran()
  expect_identical(nrow(end_anchor_diagnostics(ea_groups(ea_value(10L)))),
                   1L)
  short <- ea_time_check(ea_value(1000L), 20L)
  long <- ea_time_check(ea_value(4000L), 20L)
  expect_lt(long, 8 * max(short, 0.05))
})

# Bytes no URL a crawler sends carries (rule_inner_whitespace,
# rule_control_character): a space, a tab, a control byte and DEL, built
# in code between `/a` and `b$`.
ea_odd_bytes <- list(space = as.raw(0x20), tab = as.raw(0x09),
                     control = as.raw(0x01), del = as.raw(0x7f))

ea_odd_body <- function(byte) {
  c(charToRaw("User-agent: *\nDisallow: /a"), byte, charToRaw("b$\n"))
}

ea_odd_today <- list(space = "rule_inner_whitespace",
                     tab = "rule_inner_whitespace",
                     control = "rule_control_character", del = character(0))

test_that("ROBO-nzcvlsvk: a value no URL carries gets no row", {
  for (name in names(ea_odd_bytes)) {
    expect_identical(ea_codes(ea_odd_body(ea_odd_bytes[[name]])),
                     ea_odd_today[[name]], label = name)
  }
})

# A value whose canonical escapes grow past the 16,663-byte line buffer:
# `n` e-acute characters, two bytes each written, six bytes escaped.
ea_long_utf8 <- function(n) {
  paste0("User-agent: *\nDisallow: /", strrep(intToUtf8(233L), n), "$\n")
}

test_that("ROBO-nzcvlsvk: a value escaped past the buffer keeps its row", {
  expect_identical(ea_codes(ea_long_utf8(10L)), ea_code)
  # The witness line copies the written bytes, so it stays inside the
  # buffer as its source line does.
  d <- ea_diag(ea_long_utf8(3000L))
  expect_identical(d$code, ea_code)
  # Elided with each escape whole (query_parameter_cap()).
  shown <- paste0("/", strrep("%C3%A9", 5L), "%C3...")
  expect_identical(d$message, ea_one_message(2L, shown))
  expect_identical(
    slash_written_rules(lapply(c("Disallow: /a$", "  disalow :/b", "Allow /c",
                                 "Disallow:\t/d # e"), charToRaw)),
    c("Disallow:/a$", "disalow:/b", "Allow:/c", "Disallow:/d # e")
  )
  expect_identical(slash_written_rules(list(c(charToRaw("Disallow: /a"),
                                              as.raw(0), charToRaw("z")))),
                   "Disallow:/a")
})

# A twin a NUL cuts: Google reads `Disallow: /a?`, which blocks the
# witness; Bing and Yandex read the value with the NUL and `zz`.
ea_nul_twin <- c(charToRaw("User-agent: *\nDisallow: /a$\nDisallow: /a?"),
                 as.raw(0), charToRaw("zz\n"))

test_that("ROBO-nzcvlsvk: a NUL-cut twin silences nothing", {
  # As for rule_query_parameter_position, the twin Google alone reads is
  # left out. Not testable on Bing and Yandex: the evaluator takes the body
  # as a string, which cannot hold the NUL.
  d <- ea_diag(ea_nul_twin)
  expect_identical(d$code, c("nul_byte", "rule_cut_by_nul", ea_code))
  expect_identical(d$message[[3L]], paste0(ea_one_message(2L, "/a"), ea_nul))
})

# Another rule that matches the filler bytes of the first control or
# witness: `/x/` the control `/x/edit`, `/*x=` the witness `/a?x=1`.
ea_filler <- list(
  path = "User-agent: %s\nDisallow: /*/edit$\nDisallow: /x/\n",
  query = "User-agent: %s\nDisallow: /a$\nDisallow: /*x=\n"
)

# `Disallow: /x/` alone also blocks `/x/` and not `/x` (ROBO-roypaoox).
ea_filler_today <- list(path = "rule_slash_split", query = character(0))

test_that("ROBO-nzcvlsvk: a rule matching the filler gets the next pair", {
  # Each row shows the pair it read: `y` and `?y=2`.
  shown <- list(path = ea_one_message(2L, "/y/edit", "?y=2"),
                query = ea_one_message(2L, "/a", "?y=2"))
  for (name in names(ea_filler)) {
    d <- ea_diag(gsub("%s", "Foo", ea_filler[[name]], fixed = TRUE))
    expect_identical(d$code, c(ea_filler_today[[name]], ea_code),
                     label = name)
    expect_identical(d$message[d$code == ea_code], shown[[name]],
                     label = name)
  }
  # The pair after it, when `y` is matched too; a rule matching all three
  # silences the row.
  expect_identical(
    ea_diag("User-agent: *\nDisallow: /a$\nDisallow: /*x=\nDisallow: /*y=\n")$
      message,
    ea_one_message(2L, "/a", "?z=3")
  )
  expect_identical(
    ea_codes("User-agent: *\nDisallow: /a$\nDisallow: /*=\n"), character(0)
  )
  # A list shows each rule with its own pair.
  d <- ea_diag("User-agent: *\nDisallow: /a$\nDisallow: /b$\nDisallow: /a?x\n")
  expect_identical(d$message, ea_list_message(paste0(
    ea_blocks(2L, "/a", "?y=2"), " and ", ea_blocks(3L, "/b")
  )))
  # Each control writes its own filler for `*`.
  d <- ea_diag(paste0("User-agent: *\nDisallow: /*/a$\nDisallow: /*/b$\n",
                      "Disallow: /x/a\n"))
  expect_identical(d$message, ea_list_message(paste0(
    ea_blocks(2L, "/y/a", "?y=2"), " and ", ea_blocks(3L, "/x/b")
  )))
  expect_identical(end_anchor_controls(c("/*/a$", "*b$"), c("y", "z")),
                   c("/y/a", "/zb"))
  # Every backend decides each pair as the row says.
  for (backend in names(ea_engines)) {
    expect_identical(
      ea_decide(ea_filler$path, c("/y/edit", "/y/edit?y=2", "/x/edit"),
                backend),
      c(ea_blocked, "disallow"), label = backend
    )
    expect_identical(
      ea_decide(ea_filler$query, c("/a", "/a?y=2", "/a?x=1"), backend),
      c(ea_blocked, "disallow"), label = backend
    )
  }
})
