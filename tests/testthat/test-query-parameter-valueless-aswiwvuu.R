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
  two_crawlers = list(body = "User-agent: %s\nUser-agent: Bar\nDisallow: /*?s=\n",
                      today = qv_position),
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
