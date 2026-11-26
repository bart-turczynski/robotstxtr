# ROBO-aswiwvuu: a Disallow that names a query parameter with its `=`
# (`/*?s=`) blocks `/x?s=1` but not the same parameter written without a
# value (`/x?s`): the pattern matches its bytes literally (RFC 9309 section
# 2.2.2), so a URL without the `=` does not match it
# (`rule_query_parameter_valueless`, info). Every fixture is synthetic, and
# every control and witness is read on the package's Google, Bing and
# Yandex backends too: agreement there shows the check is consistent with
# those backends, not what Bing or Yandex do.

qv_diag <- function(body) {
  d <- robots_validate_text(body)$diagnostics
  # The crawl-not-index note (ROBO-jnnnkyat) has its own tests; leave it out.
  d[d$code != "rule_query_crawl_not_index", , drop = FALSE]
}

qv_codes <- function(body) {
  qv_diag(body)$code
}

qv_code <- "rule_query_parameter_valueless"

# One rule line under the crawler token `%s`.
qv_one <- function(value) {
  paste0("User-agent: %s\nDisallow: ", value, "\n")
}

qv_position <- "rule_query_parameter_position"

# Each fixture: a body (`%s` stands for the crawler token, so the backends
# can read it) and `today`, the codes it got before ROBO-aswiwvuu.
qv_fixtures <- list(
  eq = list(body = qv_one("/*?s="), today = qv_position),
  eq_star = list(body = qv_one("/*?s=*"), today = qv_position),
  eq_stars = list(body = qv_one("/*?s=**"), today = qv_position),
  amp = list(body = qv_one("/*&s="), today = character(0)),
  path_eq = list(body = qv_one("/search?q="), today = qv_position),
  star_led = list(body = qv_one("*?s="), today = qv_position),
  root = list(body = qv_one("/?s="), today = qv_position),
  names = list(
    body = paste0("User-agent: %s\nDisallow: /*?utm_source=\n",
                  "Disallow: /*?a.b=\nDisallow: /*&utm-x=\n"),
    today = rep(qv_position, 2L)
  ),
  q_and_amp = list(body = "User-agent: %s\nDisallow: /*?s=\nDisallow: /*&s=\n",
                   today = character(0)),
  # A sibling rule that blocks the valueless witness.
  sibling = list(body = "User-agent: %s\nDisallow: /*?s=\nDisallow: /*?s\n",
                 today = qv_position),
  sibling_star = list(
    body = "User-agent: %s\nDisallow: /*?s=\nDisallow: /*?s*\n",
    today = qv_position
  ),
  sibling_dollar = list(
    body = "User-agent: %s\nDisallow: /*?s=\nDisallow: /*?s$\n",
    today = qv_position
  ),
  # An Allow that wins the control: a longer one, and a tie.
  allow_wins = list(body = "User-agent: %s\nDisallow: /*?s=\nAllow: /*?s=*\n",
                    today = rep(qv_position, 2L)),
  allow_tie = list(
    body = "User-agent: %s\nDisallow: /*?s=\nAllow: /*?s=\n",
    today = c("disallow_tied_by_allow", qv_position, qv_position)
  ),
  # An Allow is not this check's, though it leaves `/x?s` restricted.
  allow_only = list(body = "User-agent: %s\nDisallow: /\nAllow: /*?s=\n",
                    today = qv_position),
  # A value after the `=` blocks one value, not the parameter.
  value_tail = list(body = qv_one("/*?s=shoes"), today = qv_position),
  value_star_tail = list(body = qv_one("/*?s=a*"), today = qv_position),
  dollar = list(body = qv_one("/*?s=$"), today = character(0)),
  star_dollar = list(body = qv_one("/*?s=*$"), today = character(0)),
  # URL normalization removes a dot segment from the control.
  dot = list(body = qv_one("/a/.?s="), today = "rule_dot_segment"),
  dot_dot = list(body = qv_one("/a/..?s="), today = "rule_dot_segment"),
  # Not the parameter grammar: a `*` before the `=`, a later `?`, an `&`
  # with no `*` before it or after a `?`, no name.
  star_name = list(body = qv_one("/*?*s="), today = character(0)),
  later_q = list(body = qv_one("/a?b*?s="), today = character(0)),
  amp_no_star = list(body = qv_one("/a&s="), today = character(0)),
  amp_after_q = list(body = qv_one("/a?b=1*&s="), today = qv_position),
  no_name = list(body = qv_one("/p?"), today = character(0)),
  empty = list(body = "User-agent: %s\nDisallow:\n",
               today = "allow_all_disallow"),
  # A group no crawler reads.
  empty_group = list(
    body = "User-agent:\nDisallow: /*?s=\n",
    today = c("empty_user_agent", "rule_without_user_agent",
              "missing_user_agent")
  ),
  ai = list(body = "User-agent: __usage_ai-training\nDisallow: /*?s=\n",
            today = c("ai_training_preference", qv_position)),
  # One set of crawlers with the sibling and one without.
  two_sets = list(
    body = paste0("User-agent: A\nDisallow: /*?s=\n\nUser-agent: %s\n",
                  "Disallow: /*?s=\nDisallow: /*?s\n"),
    today = rep(qv_position, 2L)
  ),
  class_disagree = list(
    body = paste0("User-agent: A\nUser-agent: B\nDisallow: /*?s=\n\n",
                  "User-agent: B\nDisallow: /*?s\n"),
    today = c("user_agent_repeated_group", qv_position)
  ),
  two_crawlers = list(
    body = "User-agent: %s\nUser-agent: Bar\nDisallow: /*?s=\n",
    today = qv_position
  ),
  # Another rule matches the first filler (`x`), or both fillers.
  filler = list(body = "User-agent: %s\nDisallow: /*?s=\nDisallow: /x?\n",
                today = qv_position),
  filler_amp = list(body = "User-agent: %s\nDisallow: /*&s=\nDisallow: /x?a\n",
                    today = character(0)),
  filler_both = list(
    body = "User-agent: %s\nDisallow: /*?s=\nDisallow: /x?\nDisallow: /y?\n",
    today = qv_position
  ),
  # A lower-case-escape twin, after and before its upper-case line.
  lower_twin = list(
    body = "User-agent: %s\nDisallow: /a%2F*?s=\nDisallow: /a%2f*?s=\n",
    today = c("rule_lowercase_escape_twin", qv_position)
  ),
  lower_first = list(
    body = "User-agent: %s\nDisallow: /a%2f*?s=\nDisallow: /a%2F*?s=\n",
    today = c("rule_lowercase_escape_twin", qv_position)
  ),
  lower = list(body = qv_one("/a%2f*?s="),
               today = c("rule_lowercase_escape", qv_position)),
  seven = list(
    body = paste0("User-agent: %s\n",
                  paste0("Disallow: /*?", letters[1:7], "=\n", collapse = "")),
    today = rep(qv_position, 7L)
  ),
  dup = list(body = "User-agent: %s\nDisallow: /*?s=\nDisallow: /*?s=\n",
             today = c("duplicate_rule", qv_position, qv_position))
)

qv_body <- function(name, token = "Foo") {
  gsub("%s", token, qv_fixtures[[name]]$body, fixed = TRUE)
}

test_that("ROBO-aswiwvuu: today's codes on every candidate shape and skip", {
  for (name in names(qv_fixtures)) {
    codes <- qv_codes(qv_body(name))
    expect_identical(codes[codes != qv_code], qv_fixtures[[name]]$today,
                     label = name)
  }
})

# A body cut at max_bytes, whose cut line could have blocked the witness.
qv_cut_text <- paste0("User-agent: *\nDisallow: /*?s=\nDisallow: /later-",
                      strrep("x", 200L), "\n")

qv_cut <- function() {
  body <- charToRaw(qv_cut_text)[seq_len(43L)]
  validate_document_bytes(body, "s", "supplied", max_bytes = 43L,
                          body_truncated = TRUE)
}

# A sibling a NUL cuts: Google reads `Disallow: /*?s`, which blocks the
# witness; Bing and Yandex read the value with the NUL and `zz`.
qv_nul_sibling <- c(charToRaw("User-agent: *\nDisallow: /*?s=\nDisallow: /*?s"),
                    as.raw(0), charToRaw("zz\n"))

# A candidate a NUL cuts after its `=`: Google reads `/*?s=`.
qv_nul_candidate <- c(charToRaw("User-agent: *\nDisallow: /*?s="), as.raw(0),
                      charToRaw("zz\n"))

test_that("ROBO-aswiwvuu: today's codes on cut, NUL and odd-byte bodies", {
  expect_identical(qv_cut()$diagnostics$code,
                   c("rule_query_crawl_not_index", "body_truncated"))
  codes <- qv_codes(qv_nul_sibling)
  expect_identical(codes[codes != qv_code],
                   c("nul_byte", "rule_cut_by_nul", qv_position))
  codes <- qv_codes(qv_nul_candidate)
  expect_identical(codes[codes != qv_code],
                   c("nul_byte", "rule_cut_by_nul", qv_position))
  # A latin1 byte is invalid UTF-8; a UTF-8 character is not.
  odd <- list(latin1 = as.raw(0xe9), utf8 = as.raw(c(0xc3, 0xa9)))
  today <- list(latin1 = c("invalid_utf8", qv_position), utf8 = qv_position)
  for (name in names(odd)) {
    body <- c(charToRaw("User-agent: *\nDisallow: /caf"), odd[[name]],
              charToRaw("*?s=\n"))
    codes <- qv_codes(body)
    expect_identical(codes[codes != qv_code], today[[name]], label = name)
  }
})

# The crossing check: how each backend decides the control and the witness.
qv_engines <- list(google = "Googlebot", bing = "bingbot", yandex = "Yandex")

qv_decide <- function(body, paths, backend) {
  token <- qv_engines[[backend]]
  robots_evaluate_text_v1(
    gsub("%s", token, body, fixed = TRUE),
    paste0("https://example.com", paths), token, backend, backend
  )$results$url_decision
}

# Fixture, the paths and the decisions every backend gives them, with any
# backend that decides otherwise.
qv_blocked <- c("disallow", "allow")
qv_decisions <- list(
  # The bare key, and the same key before another parameter, escape.
  list("eq", c("/x?s=1", "/x?s", "/x?s&page=2"), c(qv_blocked, "allow")),
  list("eq_star", c("/x?s=1", "/x?s"), qv_blocked),
  list("eq_stars", c("/x?s=1", "/x?s"), qv_blocked),
  list("amp", c("/x?a=1&s=1", "/x?a=1&s"), qv_blocked),
  list("path_eq", c("/search?q=1", "/search?q"), qv_blocked),
  list("star_led", c("/x?s=1", "/x?s"), qv_blocked),
  list("root", c("/?s=1", "/?s"), qv_blocked),
  list("names", c("/x?utm_source=1", "/x?utm_source", "/x?a.b=1", "/x?a.b",
                  "/x?a=1&utm-x=1", "/x?a=1&utm-x"), rep(qv_blocked, 3L)),
  list("two_crawlers", c("/x?s=1", "/x?s"), qv_blocked),
  list("lower_twin", c("/a%2Fx?s=1", "/a%2Fx?s"), qv_blocked),
  # The package's Yandex matcher compares a lower-case escape as written,
  # so the upper-case control is not blocked there (rule_lowercase_escape).
  # The check decides on Google's matcher.
  list("lower", c("/a%2Fx?s=1", "/a%2Fx?s"), qv_blocked,
       list(yandex = c("allow", "allow"))),
  # Silent: the witness is blocked too, or the control is allowed.
  list("sibling", c("/x?s=1", "/x?s"), c("disallow", "disallow")),
  list("sibling_star", c("/x?s=1", "/x?s"), c("disallow", "disallow")),
  list("sibling_dollar", c("/x?s=1", "/x?s"), c("disallow", "disallow")),
  list("allow_wins", c("/x?s=1", "/x?s", "/y?s=2", "/y?s"),
       rep("allow", 4L)),
  list("allow_tie", c("/x?s=1", "/x?s"), c("allow", "allow")),
  list("allow_only", c("/x?s=1", "/x?s"), c("allow", "disallow")),
  # A value tail: the control with `1` after the `=` is not blocked.
  list("value_tail", c("/x?s=shoes", "/x?s", "/x?s=1"),
       c("disallow", "allow", "allow")),
  list("dollar", c("/x?s=", "/x?s=1", "/x?s"),
       c("disallow", "allow", "allow")),
  # The first filler is matched, the second is not.
  list("filler", c("/x?s=1", "/x?s", "/y?s=2", "/y?s"),
       c("disallow", "disallow", qv_blocked)),
  list("filler_amp", c("/x?a=1&s=1", "/x?a=1&s", "/y?b=2&s=2", "/y?b=2&s"),
       c("disallow", "disallow", qv_blocked)),
  list("filler_both", c("/x?s=1", "/x?s", "/y?s=2", "/y?s"),
       rep("disallow", 4L))
)

test_that("ROBO-aswiwvuu: every backend decides the control and witness", {
  for (backend in names(qv_engines)) {
    for (case in qv_decisions) {
      expected <- case[[3L]]
      if (length(case) > 3L && !is.null(case[[4L]][[backend]])) {
        expected <- case[[4L]][[backend]]
      }
      expect_identical(qv_decide(qv_fixtures[[case[[1L]]]]$body, case[[2L]],
                                 backend),
                       expected, label = paste(backend, case[[1L]]))
    }
  }
})

# The lines of each fixture's new rows; a fixture not named gets none.
qv_rows <- list(
  eq = 1L, eq_star = 1L, eq_stars = 1L, amp = 1L, path_eq = 1L,
  star_led = 1L, root = 1L, names = 1L, q_and_amp = 1L, two_sets = 1L,
  two_crawlers = 1L, filler = 1L, filler_amp = 1L, lower_twin = 1L,
  lower = 1L, seven = 1L, dup = 1L
)

test_that("ROBO-aswiwvuu: each fixture's new rows are all the change", {
  expect_true(all(names(qv_rows) %in% names(qv_fixtures)))
  for (name in names(qv_fixtures)) {
    d <- qv_diag(qv_body(name))
    rows <- qv_rows[[name]]
    if (is.null(rows)) {
      rows <- integer(0)
    }
    # The check's rows come after every row the file had before.
    expect_identical(d$code, c(qv_fixtures[[name]]$today,
                               rep(qv_code, length(rows))), label = name)
    expect_identical(d$line[d$code == qv_code], rows, label = name)
  }
})

qv_why <- function(rule = "the rule") {
  paste0(" The pattern matches its bytes literally (RFC 9309 section ",
         "2.2.2), so a URL that writes the parameter without '=' falls ",
         "outside ", rule, ". The site may link to the parameter without a ",
         "value.")
}

qv_one_message <- function(line, control, witness) {
  sprintf("The Disallow on line %d blocks '%s' but not '%s'.%s", line,
          control, witness, qv_why())
}

qv_blocks <- function(line, control, witness) {
  sprintf("line %d blocks '%s' but not '%s'", line, control, witness)
}

qv_list_message <- function(listed) {
  paste0("These Disallows block a query parameter with a value but not the ",
         "same parameter without one: ", listed, ".", qv_why("each rule"))
}

qv_nul <- paste0(" This is Google's reading, which ends each line at its ",
                 "first NUL; Bing and Yandex read the NUL as an ordinary ",
                 "byte.")

test_that("ROBO-aswiwvuu: one info row per group, on its User-agent line", {
  x <- robots_validate_text(qv_body("eq"))
  d <- x$diagnostics[x$diagnostics$code == qv_code, , drop = FALSE]
  expect_identical(d$severity, "info")
  expect_identical(d$directive, "user-agent")
  expect_identical(d$raw_text, "User-agent: Foo")
  expect_identical(d$message, qv_one_message(2L, "/x?s=1", "/x?s"))
  expect_identical(x$documents$validation_status, "valid")
  # No rewrite advice, no engine named.
  expect_no_match(d$message, "Google|Bing|Yandex|add |write ")
  # A `*` tail reads as no tail; the `&` form puts a parameter first.
  for (name in c("eq_star", "eq_stars", "star_led")) {
    expect_identical(qv_diag(qv_body(name))$message[[2L]],
                     qv_one_message(2L, "/x?s=1", "/x?s"), label = name)
  }
  d <- qv_diag(qv_body("amp"))
  expect_identical(d$message[d$code == qv_code],
                   qv_one_message(2L, "/x?a=1&s=1", "/x?a=1&s"))
  d <- qv_diag(qv_body("path_eq"))
  expect_identical(d$message[d$code == qv_code],
                   qv_one_message(2L, "/search?q=1", "/search?q"))
  d <- qv_diag(qv_body("root"))
  expect_identical(d$message[d$code == qv_code],
                   qv_one_message(2L, "/?s=1", "/?s"))
  # Names of [A-Za-z0-9_.-] only, in either form.
  d <- qv_diag(qv_body("names"))
  expect_identical(d$message[d$code == qv_code], qv_list_message(paste0(
    qv_blocks(2L, "/x?utm_source=1", "/x?utm_source"), ", ",
    qv_blocks(3L, "/x?a.b=1", "/x?a.b"), " and ",
    qv_blocks(4L, "/x?a=1&utm-x=1", "/x?a=1&utm-x")
  )))
  # A lower-case-escape twin after its upper-case line: only that line;
  # before it, the twin decides the control and is skipped, so no row.
  d <- qv_diag(qv_body("lower_twin"))
  expect_identical(d$message[d$code == qv_code],
                   qv_one_message(2L, "/a%2Fx?s=1", "/a%2Fx?s"))
  # A repeat decides nothing: only the first line is named.
  d <- qv_diag(qv_body("dup"))
  expect_identical(d$message[d$code == qv_code],
                   qv_one_message(2L, "/x?s=1", "/x?s"))
})

test_that("ROBO-aswiwvuu: rows group by crawler set, five rules listed", {
  d <- qv_diag(qv_body("seven"))
  listed <- vapply(1:5, function(k) {
    qv_blocks(k + 1L, sprintf("/x?%s=1", letters[k]),
              sprintf("/x?%s", letters[k]))
  }, "")
  expect_identical(d$message[d$code == qv_code], qv_list_message(paste0(
    toString(listed), " and 2 more"
  )))
  # The set with the sibling gets no row; the set without it does.
  d <- qv_diag(qv_body("two_sets"))
  d <- d[d$code == qv_code, , drop = FALSE]
  expect_identical(d$raw_text, "User-agent: A")
  expect_identical(d$message, qv_one_message(2L, "/x?s=1", "/x?s"))
  expect_identical(
    qv_diag(qv_body("two_crawlers"))$message[[2L]],
    paste0(qv_one_message(3L, "/x?s=1", "/x?s"),
           " This holds for every crawler the group names: 'Foo' and 'Bar'.")
  )
})

test_that("ROBO-aswiwvuu: a rule matching the first filler gets the second", {
  d <- qv_diag(qv_body("filler"))
  expect_identical(d$message[d$code == qv_code],
                   qv_one_message(2L, "/y?s=2", "/y?s"))
  d <- qv_diag(qv_body("filler_amp"))
  expect_identical(d$message[d$code == qv_code],
                   qv_one_message(2L, "/y?b=2&s=2", "/y?b=2&s"))
  expect_false(qv_code %in% qv_codes(qv_body("filler_both")))
  # A list shows each rule with its own pair.
  d <- qv_diag(paste0("User-agent: *\nDisallow: /*?s=\nDisallow: /*?t=\n",
                      "Disallow: /x?s\n"))
  expect_identical(d$message[d$code == qv_code], qv_list_message(paste0(
    qv_blocks(2L, "/y?s=2", "/y?s"), " and ", qv_blocks(3L, "/x?t=1", "/x?t")
  )))
})

# The reading of each merge, as the shared reader gives it.
qv_groups <- function(body) {
  validation_groups(as.data.frame(
    robotstxtr_validation_parse_(if (is.raw(body)) body else charToRaw(body)),
    stringsAsFactors = FALSE
  ))
}

test_that("ROBO-aswiwvuu: the scan makes each exclusion", {
  misses <- c("/*?s=shoes", "/*?s=a*", "/*?s=$", "/*?s=*$", "/a/.?s=",
              "/a/..?s=", "/a/%2E?s=", "/*?*s=", "/a?b*?s=", "/a&s=",
              "/a?b=1*&s=", "/p?", "/*?s", "/*?=", "/*&=", "?s=", "s=",
              "/a&b=*&s=", "/a%4*?s=")
  groups <- qv_groups(paste0("User-agent: *\n",
                             paste0("Disallow: ", misses, "\n", collapse = ""),
                             "Disallow:\nAllow: /*?s=\n"))
  expect_identical(groups$rules$value[seq_along(misses)], misses)
  expect_identical(query_valueless_candidates(groups$rules), integer(0))
  hits <- c("/*?s=", "/*?s=*", "/*?s=**", "*?s=", "/?s=", "/search?q=",
            "/*&s=", "**&s=", "/a&b*&s=", "/a&b=?s=", "/*?a-b_c.d=")
  groups <- qv_groups(paste0("User-agent: *\n",
                             paste0("Disallow: ", hits, "\n", collapse = "")))
  expect_identical(query_valueless_candidates(groups$rules), seq_along(hits))
  paths <- query_valueless_paths(hits)
  expect_identical(paths$control,
                   c("/x?s=1", "/x?s=1", "/x?s=1", "/x?s=1", "/?s=1",
                     "/search?q=1", "/x?a=1&s=1", "/xx?a=1&s=1",
                     "/a&bx?a=1&s=1", "/a&b=?s=1", "/x?a-b_c.d=1"))
  expect_identical(paths$witness, sub("=[12]$", "", paths$control))
  expect_identical(query_valueless_paths("/*&s=", 2L)$control, "/y?b=2&s=2")
  # Skipped lines (file lines, not indexes) are left out.
  expect_identical(query_valueless_candidates(groups$rules, skip = 3:12),
                   1L)
  # No candidate: an empty frame before any expander is built.
  local({
    local_mocked_bindings(validation_token_expander = function(...) {
      stop("expander built")
    })
    found <- query_valueless_diagnostics(qv_groups(
      "User-agent: *\nDisallow: /a\n"
    ))
    expect_identical(nrow(found), 0L)
    expect_named(found, c("line", "type", "message", "directive"))
  })
})

test_that("ROBO-aswiwvuu: every class on both merges must agree", {
  expect_false(qv_code %in% qv_codes(qv_body("class_disagree")))
  # Google's merge reads `Foo web` and `Foo blog` as one crawler; the
  # whole-value merge keeps them apart. Either merge blocking the witness
  # silences the row.
  expect_false(qv_code %in% qv_codes(paste0(
    "User-agent: Foo web\nDisallow: /*?s=\n\n",
    "User-agent: Foo blog\nDisallow: /*?s\n"
  )))
  expect_true(qv_code %in% qv_codes(paste0(
    "User-agent: Foo web\nDisallow: /*?s=\n\n",
    "User-agent: Foo blog\nDisallow: /b\n"
  )))
})

test_that("ROBO-aswiwvuu: a cut body is skipped, a NUL body is Google's", {
  expect_false(qv_code %in% qv_cut()$diagnostics$code)
  # The same bytes, not marked cut, get the row.
  body <- charToRaw(qv_cut_text)[seq_len(43L)]
  x <- validate_document_bytes(body, "s", "supplied")
  d <- x$diagnostics
  expect_identical(d$message[d$code == qv_code],
                   qv_one_message(2L, "/x?s=1", "/x?s"))
  # A sibling a NUL cuts to `/*?s` blocks the witness on Google's reading.
  expect_false(qv_code %in% qv_codes(qv_nul_sibling))
  for (backend in names(qv_engines)) {
    expect_identical(
      qv_decide("User-agent: %s\nDisallow: /*?s=\nDisallow: /*?s\n",
                c("/x?s=1", "/x?s"), backend),
      c("disallow", "disallow"), label = backend
    )
  }
  # A candidate a NUL cuts after its `=` keeps its row, which says it is
  # Google's reading.
  d <- qv_diag(qv_nul_candidate)
  expect_identical(d$message[d$code == qv_code],
                   paste0(qv_one_message(2L, "/x?s=1", "/x?s"), qv_nul))
})

test_that("ROBO-aswiwvuu: edge inputs", {
  # A latin1 byte and a UTF-8 character are escaped in the canonical value,
  # and the control shows the escape.
  for (byte in list(as.raw(0xe9), as.raw(c(0xc3, 0xa9)))) {
    body <- c(charToRaw("User-agent: *\nDisallow: /caf"), byte,
              charToRaw("*?s=\n"))
    escaped <- paste0("/caf", paste(sprintf("%%%02X", as.integer(byte)),
                                    collapse = ""), "x")
    d <- qv_diag(body)
    expect_identical(d$message[d$code == qv_code],
                     qv_one_message(2L, paste0(escaped, "?s=1"),
                                    paste0(escaped, "?s")))
  }
  # A control byte or DEL leaves the value out.
  for (byte in list(as.raw(0x01), as.raw(0x7f))) {
    body <- c(charToRaw("User-agent: *\nDisallow: /a"), byte,
              charToRaw("*?s=\n"))
    expect_false(qv_code %in% qv_codes(body))
  }
  expect_identical(qv_codes(""), "no_rules")
  # A long path and a long name are elided, each on its own, so the two
  # URLs stay apart.
  long <- strrep("a", 100L)
  d <- qv_diag(sprintf("User-agent: *\nDisallow: /%s*?%s=\n", long, long))
  path <- paste0("/", strrep("a", 35L), "...")
  name <- paste0(strrep("a", 36L), "...")
  expect_identical(d$message[d$code == qv_code],
                   qv_one_message(2L, paste0(path, "?", name, "=1"),
                                  paste0(path, "?", name)))
  # robots_validate_url() gives the same rows.
  local_fake_ssrfr(function(req) {
    fake_response(200L, url = req$url, body = qv_body("q_and_amp"))
  })
  x <- robots_validate_url("https://e.example/page")
  d <- x$diagnostics
  expect_identical(d$message[d$code == qv_code],
                   qv_diag(qv_body("q_and_amp"))$message[[1L]])
})

# The counts a check that stopped hands out, as slash_stop() builds them.
qv_stopped <- function(found, checked, value) {
  list(found = found, checked = checked, skipped = found - checked,
       value = value)
}

test_that("ROBO-aswiwvuu: candidates past the work budget get no row", {
  groups <- qv_groups("User-agent: Foo\nDisallow: /*?s=\nDisallow: /*?t=\n")
  found <- query_valueless_diagnostics(groups)
  expect_identical(found$message, qv_list_message(paste0(
    qv_blocks(2L, "/x?s=1", "/x?s"), " and ", qv_blocks(3L, "/x?t=1", "/x?t")
  )))
  expect_null(attr(found, "stopped"))
  found <- query_valueless_diagnostics(groups, budget = 0)
  expect_identical(nrow(found), 0L)
  stop <- attr(found, "stopped")
  expect_identical(stop, qv_stopped(2L, 0L, "/*?s="))
  expect_identical(slash_stop_message("query_valueless", stop), paste0(
    "This file has 2 Disallow rules that this check reads (a pattern that ",
    "ends in a query parameter name and '='), such as '/*?s='. For each ",
    "one, the validator checks whether the rule blocks '/x?s=1' but not ",
    "'/x?s'. This file is too large to check them all quickly, so none of ",
    "them were checked. All 2 were skipped, and some of them may have the ",
    "same problem."
  ))
  # One read in: the first gets its row, the second its count.
  found <- query_valueless_diagnostics(groups, budget = 5)
  expect_identical(found$message, qv_one_message(2L, "/x?s=1", "/x?s"))
  expect_identical(attr(found, "stopped"), qv_stopped(2L, 1L, "/*?t="))
  # A normal file gets no such row.
  for (name in names(qv_fixtures)) {
    expect_false("rule_check_stopped" %in% qv_codes(qv_body(name)),
                 label = name)
  }
})

# `n` crawlers named in one group of `n` `?name=` candidates, each crawler
# with a group of its own, so every candidate is read once per class.
qv_classes <- function(n) {
  k <- seq_len(n)
  paste0(paste0("User-agent: bot", k, "\n", collapse = ""),
         paste0("Disallow: /*?p", k, "=\n", collapse = ""), "\n",
         paste0("User-agent: bot", k, "\nDisallow: /z", k, "\n",
                collapse = "\n"))
}

test_that("ROBO-aswiwvuu: a file too large for the check gets the row", {
  d <- qv_diag(qv_classes(250L))
  stop <- d[d$code == "rule_check_stopped", , drop = FALSE]
  expect_identical(stop$line, NA_integer_)
  expect_identical(stop$message, paste0(
    "This file has 250 Disallow rules that this check reads (a pattern ",
    "that ends in a query parameter name and '='), such as '/*?p1='. For ",
    "each one, the validator checks whether the rule blocks '/x?p1=1' but ",
    "not '/x?p1'. This file is too large to check them all quickly, so ",
    "none of them were checked. All 250 were skipped, and some of them may ",
    "have the same problem."
  ))
  expect_false(qv_code %in% d$code)
})
