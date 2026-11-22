# ROBO-fuhcwaom: an Allow or Disallow whose pattern names a query parameter
# right after its first `?` (`/items/*?sort=`). The matchers read `?` as a
# literal byte, so the rule may miss a URL where that parameter follows
# another one (`/items/x?a=1&sort=a`). One info row per rule line, silent
# when every crawler the group names also has the `&` form of the rule.

qp_code <- "rule_query_parameter_position"

qp_diag <- function(body) {
  robots_validate_text(body)$diagnostics
}

qp_codes <- function(body) {
  qp_diag(body)$code
}

qp_one <- function(type, value) {
  qp_codes(paste0("User-agent: *\n", type, ": ", value, "\n"))
}

# The lines of this check's rows.
qp_lines <- function(body) {
  d <- qp_diag(body)
  d$line[d$code == qp_code]
}

qp_message <- function(name, example, type = "disallow") {
  effect <- if (type == "allow") {
    sprintf(paste0("this Allow may not apply to URLs where '%s' follows ",
                   "another parameter, such as %s, and the gap can leave ",
                   "them restricted."), name, example)
  } else {
    sprintf(paste0("this rule may miss URLs where '%s' follows another ",
                   "parameter, such as %s."), name, example)
  }
  sprintf(paste0("Pattern holds '?%s=', which matches '%s' only where a '?' ",
                 "stands right before it, so %s"), name, name, effect)
}

# Each positive value with its parameter, the control path (each `*`
# written `x`) and the example path the message shows.
qp_hits <- list(
  "/items/*?sort=" = c("sort", "/items/x?sort=", "/items/x?a=1&sort="),
  "/search?page=" = c("page", "/search?page=", "/search?a=1&page="),
  "*?q=" = c("q", "/x?q=", "/x?a=1&q="),
  "/search?page=*&view=list" = c("page", "/search?page=x&view=list",
                                "/search?a=1&page=x&view=list"),
  "/p?a=" = c("a", "/p?a=", "/p?b=1&a="),
  "/p?page_no.x-1=2" = c("page_no.x-1", "/p?page_no.x-1=2",
                         "/p?a=1&page_no.x-1=2"),
  # Only the first `?` counts: the parameter is `back`, never `sort`.
  "/items?back=?sort=" = c("back", "/items?back=?sort=",
                         "/items?a=1&back=?sort="),
  # A `?` after the `=` does not matter: the first `?` starts `name=`.
  "/p?q=?" = c("q", "/p?q=?", "/p?a=1&q=?"),
  "/p?q=*?" = c("q", "/p?q=x?", "/p?a=1&q=x?"),
  # The stray `%` sits in the suffix; rule_invalid_percent_escape stands too.
  "/p?q=%" = c("q", "/p?q=%", "/p?a=1&q=%")
)

# Values that get no row, each with the codes it gets today.
qp_misses <- list(
  "/*?*sort=" = character(0),
  "/items?x*?sort=" = character(0),
  "/items*?" = character(0),
  "/v?$" = character(0),
  "/v?page=2$" = character(0),
  "/items/*?sort=*$" = character(0),
  "/p?" = character(0),
  "/p?=1" = character(0),
  "/p?q" = character(0),
  "/p&q=" = character(0),
  "/p?%C3%A9=1" = character(0),
  "p?q=" = "rule_missing_leading_slash",
  "/a/./p?q=" = "rule_dot_segment",
  # A dot segment after a `*` or escaped, anywhere before the first `?`.
  "/*/../p?q=" = character(0),
  "*/../p?q=" = character(0),
  "/*/./p?q=" = character(0),
  "/a/*/../p?q=" = character(0),
  "/a/*/..?q=" = character(0),
  "/p/%2e%2e/x?q=" = c("rule_escaped_unreserved", "rule_lowercase_escape"),
  "/p/.%2E/x?q=" = "rule_escaped_unreserved",
  "/p/%2e/x?q=" = c("rule_escaped_unreserved", "rule_lowercase_escape")
)

# Why those are skipped: under the v1 default `url_normalization =
# "rfc3986"` the control path loses its dot segment before matching, so the
# rule does not match it on at least one backend.
qp_dot_controls <- list(
  "/*/../p?q=" = c("allow", "allow", "allow"),
  "*/../p?q=" = c("allow", "allow", "allow"),
  "/*/./p?q=" = c("allow", "allow", "allow"),
  "/a/*/../p?q=" = c("allow", "allow", "allow"),
  "/p/%2e%2e/x?q=" = c("allow", "allow", "disallow")
)

test_that("ROBO-fuhcwaom: a query-parameter rule is one info row", {
  x <- robots_validate_text("User-agent: *\nDisallow: /items/*?sort=\n")
  expect_identical(x$diagnostics$code, qp_code)
  expect_identical(x$diagnostics$line, 2L)
  expect_identical(x$diagnostics$severity, "info")
  expect_identical(x$diagnostics$directive, "disallow")
  expect_identical(x$diagnostics$raw_text, "Disallow: /items/*?sort=")
  expect_identical(x$diagnostics$message,
                   qp_message("sort", "/items/x?a=1&sort="))
  expect_identical(x$documents$validation_status, "valid")

  y <- robots_validate_text("User-agent: *\nAllow: /search?page=\n")
  expect_identical(y$diagnostics$code, qp_code)
  expect_identical(y$diagnostics$directive, "allow")
  expect_identical(y$diagnostics$message,
                   qp_message("page", "/search?a=1&page=", "allow"))
})

test_that("ROBO-fuhcwaom: each positive shape names its example", {
  for (type in c("Allow", "Disallow")) {
    for (value in names(qp_hits)) {
      hit <- qp_hits[[value]]
      d <- qp_diag(paste0("User-agent: *\n", type, ": ", value, "\n"))
      expected <- if (value == "/p?q=%") {
        c("rule_invalid_percent_escape", qp_code)
      } else {
        qp_code
      }
      expect_identical(d$code, expected, label = paste(type, value))
      expect_identical(
        d$message[d$code == qp_code],
        qp_message(hit[[1L]], hit[[3L]], ascii_lower(type)),
        label = paste(type, value)
      )
    }
  }
})

test_that("ROBO-fuhcwaom: the other shapes keep their codes", {
  for (type in c("Allow", "Disallow")) {
    for (value in names(qp_misses)) {
      expect_identical(qp_one(type, value), qp_misses[[value]],
                       label = paste(type, value))
    }
  }
  expect_identical(qp_one("Disallow", ""), "allow_all_disallow")
  expect_identical(qp_one("Allow", ""), "empty_rule_value")
})

# The witness, in code: the paths the check builds, read by Google's
# matcher with the value alone as a one-rule Disallow (no URL
# preprocessing). The control matches and the example misses, so neither
# needs a matcher call at validation time.
qp_witness <- function(values) {
  paths <- query_parameter_paths(values)
  n <- length(values)
  found <- wildcard_witness_decide(
    paste0("User-agent: witness\nDisallow: ", values, "\n"),
    rep(seq_len(n), each = 2L),
    as.vector(rbind(paths$control, paths$example))
  )$allowed
  list(paths = paths, control = found[c(TRUE, FALSE)],
       example = found[c(FALSE, TRUE)])
}

test_that("ROBO-fuhcwaom: the control matches the pattern, the example not", {
  # Long and star-heavy values too: a later `?` and `*` runs in the suffix.
  values <- c(names(qp_hits), "/*?q=*?q=*", "/*?q=?q=", "/a*b?n=*?*?x",
              "*?a=*a=1&a=")
  found <- qp_witness(values)
  expect_identical(found$control, rep(FALSE, length(values)))
  expect_identical(found$example, rep(TRUE, length(values)))
  expect_identical(found$paths$control[seq_along(qp_hits)],
                   unname(vapply(qp_hits, `[[`, "", 2L)))
  expect_identical(found$paths$example[seq_along(qp_hits)],
                   unname(vapply(qp_hits, `[[`, "", 3L)))
  expect_identical(found$paths$name[seq_along(qp_hits)],
                   unname(vapply(qp_hits, `[[`, "", 1L)))
  expect_identical(query_parameter_paths(character(0))$example, character(0))
})

# The groups the validator reads from a body.
qp_parsed_groups <- function(body) {
  validation_groups(as.data.frame(
    robotstxtr_validation_parse_(charToRaw(body)),
    stringsAsFactors = FALSE
  ))
}

# The scan alone, where the exclusions are made.
qp_groups <- function(values) {
  qp_parsed_groups(paste0(
    "User-agent: *\n", paste0("Disallow: ", values, "\n", collapse = "")
  ))
}

test_that("ROBO-fuhcwaom: the scan makes each exclusion", {
  groups <- qp_groups(c(names(qp_misses), "/p?q=$", "/a/../p?q="))
  expect_identical(query_parameter_candidates(groups$rules, integer()),
                   integer(0))
  groups <- qp_groups(names(qp_hits))
  expect_identical(query_parameter_candidates(groups$rules, integer()),
                   seq_along(qp_hits))
  expect_identical(query_parameter_candidates(groups$rules, 3L),
                   seq_along(qp_hits)[-2L])
})

# The message's claim, on google, bing and yandex alike with the v1 default
# `url_normalization = "rfc3986"` (no fixture path holds a dot segment, so
# every mode decides the same): `?` is a literal byte and `*` any run. A
# Disallow disallows the control and allows the example; an Allow under a
# fixture-only `Disallow: /` does the reverse. No backend disagrees, so the
# message names none. The rfc9309 backend is capability_unavailable (ADR
# 0002), so it is not testable here.
qp_engines <- list(google = "Googlebot", bing = "bingbot", yandex = "Yandex")

qp_decide <- function(body, paths, backend) {
  robots_evaluate_text_v1(
    body, paste0("https://example.com", paths), qp_engines[[backend]],
    backend, backend
  )$results$url_decision
}

test_that("ROBO-fuhcwaom: every backend decides the control and example", {
  for (backend in names(qp_engines)) {
    for (value in names(qp_hits)) {
      paths <- qp_hits[[value]][2:3]
      label <- paste(backend, value)
      expect_identical(
        qp_decide(paste0("User-agent: *\nDisallow: ", value, "\n"), paths,
                  backend),
        c("disallow", "allow"), label = label
      )
      expect_identical(
        qp_decide(paste0("User-agent: *\nDisallow: /\nAllow: ", value, "\n"),
                  paths, backend),
        c("allow", "disallow"), label = label
      )
    }
    # A `*` can reach a later `?`, so this path is matched.
    expect_identical(
      qp_decide("User-agent: *\nDisallow: /items/*?sort=\n",
                "/items/x?a=?sort=a", backend),
      "disallow", label = backend
    )
  }
})

test_that("ROBO-fuhcwaom: a dot segment before `?` loses the control", {
  backends <- names(qp_engines)
  for (value in names(qp_dot_controls)) {
    control <- query_parameter_paths(value)$control
    got <- vapply(backends, function(backend) {
      qp_decide(paste0("User-agent: *\nDisallow: ", value, "\n"), control,
                backend)
    }, "", USE.NAMES = FALSE)
    expect_identical(got, qp_dot_controls[[value]], label = value)
  }
})

test_that("ROBO-fuhcwaom: the `&` twin in the merged rules silences the row", {
  expect_identical(
    qp_codes("User-agent: *\nDisallow: /*?page=\nDisallow: /*&page=\n"),
    character(0)
  )
  # The twin may come first, and Allow twins Allow.
  expect_identical(
    qp_codes("User-agent: *\nAllow: /*&page=\nAllow: /*?page=\n"),
    character(0)
  )
  # Two groups naming the same crawler merge.
  expect_identical(
    qp_codes(paste0("User-agent: a\nDisallow: /*?page=\n\n",
                    "User-agent: a\nDisallow: /*&page=\n")),
    "user_agent_repeated_group"
  )
  # Every crawler the group names needs the twin.
  two <- "User-agent: Foo\nUser-agent: Bar\nDisallow: /*?q=\n\n"
  expect_identical(
    qp_lines(paste0(two, "User-agent: Foo\nDisallow: /*&q=\n")), 3L
  )
  expect_identical(
    qp_lines(paste0(two, "User-agent: Foo\nUser-agent: Bar\n",
                    "Disallow: /*&q=\n")),
    integer(0)
  )
})

# The `&` twin reaches a later parameter only with a `*` right before it:
# on google, bing and yandex, `/search&page=` beside `/search?page=` leaves
# `/search?a=1&page=1` allowed, `/search*&page=` disallows it, and
# `/*&page=` beside `/*?page=` disallows `/x?a=1&page=1`.
qp_twin_note <- paste0(
  " The same rule with '&' in place of that '?' does not cover them ",
  "either: it needs '&' right after the text before it, so a '*' must ",
  "stand before the '&', as in '%s'."
)

test_that("ROBO-fuhcwaom: a twin with no `*` before it keeps the row", {
  plain <- paste0("User-agent: *\nDisallow: /search?page=\n",
                  "Disallow: /search&page=\n")
  for (backend in names(qp_engines)) {
    expect_identical(
      qp_decide(plain, c("/search?page=1", "/search?a=1&page=1"), backend),
      c("disallow", "allow"), label = backend
    )
    expect_identical(
      qp_decide(paste0("User-agent: *\nDisallow: /search?page=\n",
                       "Disallow: /search*&page=\n"),
                "/search?a=1&page=1", backend),
      "disallow", label = backend
    )
    expect_identical(
      qp_decide("User-agent: *\nDisallow: /*?page=\nDisallow: /*&page=\n",
                "/x?a=1&page=1", backend),
      "disallow", label = backend
    )
  }
  d <- qp_diag(plain)
  expect_identical(d$code, qp_code)
  expect_identical(d$line, 2L)
  expect_identical(d$message, paste0(
    qp_message("page", "/search?a=1&page="),
    sprintf(qp_twin_note, "/search*&page=")
  ))
  d <- qp_diag("User-agent: *\nAllow: /p/a?q=x*\nAllow: /p/a&q=x*\n")
  expect_identical(d$message, paste0(
    qp_message("q", "/p/a?a=1&q=xx", "allow"),
    sprintf(qp_twin_note, "/p/a*&q=x*")
  ))
  # The `*&` form is no twin: the row keeps the plain message.
  d <- qp_diag(paste0("User-agent: *\nDisallow: /search?page=\n",
                      "Disallow: /search*&page=\n"))
  expect_identical(d$message, qp_message("page", "/search?a=1&page="))
  # A `*` right before the `?` makes the twin reach: silent, led by `*` too.
  expect_identical(qp_codes("User-agent: *\nDisallow: *?q=\nDisallow: *&q=\n"),
                   character(0))
  expect_identical(
    qp_lines("User-agent: *\nDisallow: /a*?q=\nDisallow: /a*&q=\n"),
    integer(0)
  )
})

test_that("ROBO-fuhcwaom: anything less than the identical twin keeps it", {
  for (twin in c("/x*&page=", "/*&page=1", "/*&page=$", "/*&page",
                 "/*&Page=", "/*;page=")) {
    expect_identical(
      qp_lines(paste0("User-agent: *\nDisallow: /*?page=\nDisallow: ",
                      twin, "\n")),
      2L, label = twin
    )
  }
  # Another type is not a twin.
  expect_identical(
    qp_lines("User-agent: *\nDisallow: /*?page=\nAllow: /*&page=\n"), 2L
  )
  # `*` and named crawlers are kept apart, both ways.
  expect_identical(
    qp_lines(paste0("User-agent: *\nDisallow: /*&q=\n\n",
                    "User-agent: Foo\nDisallow: /*?q=\n")),
    5L
  )
  expect_identical(
    qp_lines(paste0("User-agent: Foo\nDisallow: /*&q=\n\n",
                    "User-agent: *\nDisallow: /*?q=\n")),
    5L
  )
})

# Groups merge on the whole User-agent value: Google's matcher cuts
# `Foo/1.0` to `Foo` and merges the groups, so there the twin covers the
# URL, but a matcher that compares the whole value keeps them apart.
test_that("ROBO-fuhcwaom: a twin only Google's cut supplies keeps the row", {
  d <- qp_diag(paste0("User-agent: Foo/1.0\nDisallow: /*?q=\n\n",
                      "User-agent: Foo\nDisallow: /*&q=\n"))
  expect_identical(d$line[d$code == qp_code], 2L)
  expect_identical(
    qp_lines(paste0("User-agent: Foo/1.0\nDisallow: /*?q=\n\n",
                    "User-agent: foo/1.0\nDisallow: /*&q=\n")),
    integer(0)
  )
  # The split on the backends, for a crawler each evaluates: Google merges
  # the groups and disallows both paths; Bing and Yandex read the plain
  # group alone, so its `&` rule disallows only the later position.
  paths <- c("/x?q=1", "/x?b=2&q=1")
  for (backend in names(qp_engines)) {
    token <- qp_engines[[backend]]
    body <- sprintf(paste0("User-agent: %s/1.0\nDisallow: /*?q=\n\n",
                           "User-agent: %s\nDisallow: /*&q=\n"), token, token)
    expected <- if (backend == "google") {
      c("disallow", "disallow")
    } else {
      c("allow", "disallow")
    }
    expect_identical(qp_decide(body, paths, backend), expected,
                     label = backend)
  }
})

test_that("ROBO-fuhcwaom: a lower-case-escape twin line gets no row", {
  d <- qp_diag("User-agent: *\nDisallow: /p?q=%2b\nDisallow: /p?q=%2B\n")
  expect_identical(d$code, c("rule_lowercase_escape_twin", qp_code))
  expect_identical(d$line, 2:3)
  expect_identical(d$message[[2L]], qp_message("q", "/p?a=1&q=%2B"))
  # Its canonical value is upper-cased, so an `&` twin written in upper case
  # silences it.
  expect_identical(
    qp_codes("User-agent: *\nDisallow: /p*?q=%2b\nDisallow: /p*&q=%2B\n"),
    "rule_lowercase_escape"
  )
  # Alone, the line keeps the row, and the example shows the escape in
  # upper case.
  d <- qp_diag("User-agent: *\nDisallow: /p?q=%2b\n")
  expect_identical(d$code, c("rule_lowercase_escape", qp_code))
  expect_identical(d$message[[2L]], qp_message("q", "/p?a=1&q=%2B"))
})

test_that("ROBO-fuhcwaom: the row coexists with duplicate_rule", {
  d <- qp_diag("User-agent: *\nDisallow: /*?q=\nDisallow: /*?q=\n")
  expect_identical(d$code, c("duplicate_rule", qp_code, qp_code))
  expect_identical(d$line, c(3L, 2L, 3L))
  expect_false(anyDuplicated(paste(d$line, d$message)) > 0L)
})

test_that("ROBO-fuhcwaom: edge inputs", {
  # A NUL on another rule line: the message says it is Google's reading.
  body <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0),
            charToRaw("b\nDisallow: /search?page=\n"))
  d <- qp_diag(body)
  expect_identical(d$code, c("nul_byte", "rule_cut_by_nul", qp_code))
  expect_identical(d$message[[3L]], paste0(
    qp_message("page", "/search?a=1&page="),
    " This is Google's reading, which ends each line at its first NUL; ",
    "Bing and Yandex read the NUL as an ordinary byte."
  ))
  # A non-ASCII parameter name is escaped, so it is outside the name class.
  body <- c(charToRaw("User-agent: *\nDisallow: /p?"), as.raw(c(0xc3, 0xa9)),
            charToRaw("=1\n"))
  expect_identical(qp_codes(body), character(0))
  # A control byte in the suffix is shown escaped, as raw_text is.
  body <- c(charToRaw("User-agent: *\nDisallow: /p?q="), as.raw(1),
            charToRaw("\n"))
  d <- qp_diag(body)
  expect_identical(d$code, c("rule_control_character", qp_code))
  expect_identical(d$message[[2L]], qp_message("q", "/p?a=1&q=\\x01"))
  # Rules before any User-agent belong to no group, and a group under an
  # empty User-agent line names no crawler class: neither gets a row.
  expect_identical(qp_codes("Disallow: /search?page=\n"),
                   c("rule_without_user_agent", "missing_user_agent"))
  expect_identical(qp_lines("User-agent:\nDisallow: /*?q=\n"), integer(0))
  expect_identical(
    qp_lines(paste0("User-agent:\nDisallow: /*?q=\n\n",
                    "User-agent: *\nDisallow: /*?q=\n")),
    5L
  )
  # No candidate: the helpers return empty vectors.
  groups <- qp_parsed_groups("User-agent: *\nDisallow: /p\n")
  expect_identical(query_parameter_kept(groups, integer()),
                   list(keep = logical(0), twin = logical(0)))
  expect_identical(
    query_parameter_message(character(), query_parameter_paths(character()),
                            logical()),
    character(0)
  )
})

# The name, the text before the `?` and the text after the `=` are each
# shown up to 40 bytes (36 and "..."), as ai_training_name() elides.
test_that("ROBO-fuhcwaom: the quoted example is capped", {
  long <- paste0("/", strrep("a", 8000L), "?q=", strrep("b", 8996L))
  expect_identical(nchar(long), 17000L)
  d <- qp_diag(paste0("User-agent: *\nDisallow: ", long, "\n"))
  expect_identical(d$code, c("line_too_long", qp_code))
  example <- paste0("/", strrep("a", 35L), "...?a=1&q=", strrep("b", 36L),
                    "...")
  expect_identical(d$message[[2L]], qp_message("q", example))
  expect_lt(nchar(d$message[[2L]]), 300L)
  # A long name is elided too, in the `?name=` run as in the example.
  name <- strrep("n", 9000L)
  d <- qp_diag(paste0("User-agent: *\nDisallow: /p?", name, "=1\n"))
  shown <- paste0(strrep("n", 36L), "...")
  expect_identical(d$code, qp_code)
  expect_identical(d$message,
                   qp_message(shown, paste0("/p?a=1&", shown, "=1")))
  # The `*&` form in the twin sentence is capped the same way.
  head <- paste0("/", strrep("h", 100L))
  d <- qp_diag(paste0("User-agent: *\nDisallow: ", head, "?q=1\nDisallow: ",
                      head, "&q=1\n"))
  shown <- paste0("/", strrep("h", 35L), "...")
  expect_identical(d$message, paste0(
    qp_message("q", paste0(shown, "?a=1&q=1")),
    sprintf(qp_twin_note, paste0(shown, "*&q=1"))
  ))
})

test_that("ROBO-fuhcwaom: a body cut at max_bytes is not checked", {
  body <- charToRaw(paste0(
    "User-agent: *\nDisallow: /search?page=\n",
    "Disallow: /later-", strrep("x", 200L), "\n"
  ))[seq_len(60L)]
  x <- validate_document_bytes(
    body, "s", "supplied", max_bytes = 60L, body_truncated = TRUE
  )
  expect_identical(x$diagnostics$code, "body_truncated")
  # The same bytes, not marked cut, get the row.
  x <- validate_document_bytes(body, "s", "supplied")
  expect_identical(x$diagnostics$line[x$diagnostics$code == qp_code], 2L)
})

# Best of five runs, so a loaded machine cannot fail the ratio
# (test-cut-note-zqyqbudf.R).
qp_time <- function(body) {
  min(vapply(1:5, function(i) {
    system.time(robots_validate_text(body))[["elapsed"]]
  }, 0))
}

# `n` candidates over two groups naming two crawlers each; every other rule
# has its `&` twin, so the scan, the twin lookup and the witness all run.
qp_rules <- function(n) {
  half <- seq_len(n %/% 2L)
  rules <- paste0(
    "Disallow: /p", half, "?q=\n", "Disallow: /t", half, "*?q=\n",
    "Disallow: /t", half, "*&q=\n", collapse = ""
  )
  paste0("User-agent: Foo\nUser-agent: Bar\n", rules,
         "\nUser-agent: Foo\nUser-agent: Baz\n", rules)
}

# The check alone on a parsed body, 10 calls per run: the rest of the
# validator costs far more and would hide the check's growth.
qp_time_check <- function(body) {
  groups <- qp_parsed_groups(body)
  min(vapply(1:5, function(i) {
    system.time(for (k in 1:10) {
      query_parameter_position_diagnostics(groups)
    })[["elapsed"]]
  }, 0))
}

test_that("ROBO-fuhcwaom: the check is linear in the rules (ROBO-dbvmxcfw)", {
  skip_on_cran()
  expect_length(qp_lines(qp_rules(4L)), 4L)
  expect_identical(
    nrow(query_parameter_position_diagnostics(
      qp_parsed_groups(qp_rules(1000L))
    )),
    1000L
  )
  small <- qp_time_check(qp_rules(1000L))
  large <- qp_time_check(qp_rules(4000L))
  expect_lt(large, 8 * max(small, 0.05))
  # The whole validator too, on the same bodies.
  small <- qp_time(qp_rules(500L))
  large <- qp_time(qp_rules(2000L))
  expect_lt(large, 8 * max(small, 0.05))
})

# One rule whose prefix and suffix carry the length, inside the 16,663-byte
# line buffer; the check alone, 20 calls per run so a cost that grows with
# the value clears the floor.
qp_value <- function(n) {
  paste0("/", strrep("ab", n), "?q=", strrep("*c", n))
}

qp_time_value <- function(value) {
  groups <- qp_parsed_groups(paste0("User-agent: *\nDisallow: ", value, "\n"))
  expect_identical(nrow(query_parameter_position_diagnostics(groups)), 1L)
  min(vapply(1:5, function(i) {
    system.time(for (k in 1:20) {
      query_parameter_position_diagnostics(groups)
    })[["elapsed"]]
  }, 0))
}

test_that("ROBO-fuhcwaom: the check is linear in the value's length", {
  skip_on_cran()
  short <- qp_time_value(qp_value(1000L))
  long <- qp_time_value(qp_value(4000L))
  expect_lt(long, 8 * max(short, 0.05))
})
