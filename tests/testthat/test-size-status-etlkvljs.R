# Size and status audit (ROBO-etlkvljs). A robots.txt cut at max_bytes, one
# over a size limit, and one answered by a non-200 status, under every
# ruleset and every matcher backend, checked against the documented
# contract: design/engine-profiles.md sections 2, 3, 4 and 7, and
# design/engine-contract-v1.md ("A robots.txt over `max_bytes`"). Every
# fixture is synthesized here; responses are scripted at the ssrfr boundary
# (helper-fake-ssrfr.R). The assertions pin current behavior; where it
# departs from the documents a comment starting "contract mismatch" says so.

ss_window <- 512000L
ss_rulesets <- c("rfc9309", "google", "yandex", "bing", "assumed_rfc9309")
ss_backends <- c("google", "yandex", "bing", "rfc9309")
ss_tokens <- c(
  google = "bot", yandex = "Yandex", bing = "bingbot", rfc9309 = "bot"
)
ss_grid <- expand.grid(
  ruleset = ss_rulesets, backend = ss_backends, stringsAsFactors = FALSE
)

# --- Fixtures -----------------------------------------------------------------

# `n` bytes of short comment lines, so no backend meets a line-length limit.
ss_pad <- function(n) {
  stopifnot(n >= 2L)
  line <- function(size) c(rep(charToRaw("#"), size - 1L), charToRaw("\n"))
  full <- n %/% 64L
  rest <- n %% 64L
  if (rest == 1L) {
    return(c(rep(line(64L), full - 1L), line(65L)))
  }
  c(rep(line(64L), full), if (rest > 0L) line(rest))
}

# "User-agent: *", comment lines up to byte `at`, then `tail` from byte
# `at + 1`, then comment lines cut to exactly `size` bytes.
ss_body <- function(tail, at, size = 600000L) {
  head <- c(charToRaw("User-agent: *\n"), ss_pad(at - 14L))
  stopifnot(length(head) == at)
  body <- c(head, tail)
  if (length(body) < size) {
    body <- c(body, ss_pad(size - length(body) + 64L))
  }
  body[seq_len(size)]
}

# Three rule lines and where each is split: `keep` is the number of the
# line's bytes left before the split.
# - rule: "Disallow: /" is all that is left of a longer rule.
# - escape: the split falls between "%" and "2F".
# - utf8: the split falls between the two bytes of "é" (C3 A9).
# `probes` are paths and the decision each gets when the line is read whole.
ss_tails <- list(
  rule = list(
    bytes = charToRaw("Disallow: /private-drafts/\n"), keep = 11L,
    probes = c("/private-drafts/x" = "disallow", "/public" = "allow")
  ),
  escape = list(
    bytes = charToRaw("Disallow: /a%2Fb\n"), keep = 13L,
    probes = c("/a%2Fb" = "disallow", "/a" = "allow")
  ),
  utf8 = list(
    bytes = c(charToRaw("Disallow: /caf"), as.raw(c(0xc3, 0xa9)),
              charToRaw("\n")),
    keep = 15L,
    probes = c("/caf%C3%A9" = "disallow", "/cafe" = "allow")
  )
)

# A body whose `tail` line is split at byte `split` (`keep` bytes before it).
ss_split_body <- function(tail, split = ss_window, size = 600000L) {
  ss_body(tail$bytes, split - tail$keep, size)
}

ss_urls <- function(paths) paste0("http://example.com", paths)

ss_serve <- function(body, status = 200L, env = parent.frame()) {
  local_fake_ssrfr(
    function(req) fake_response(status, url = req$url, body = body),
    env = env
  )
}

# Every ruleset x backend pair, once per path.
ss_eval_url <- function(paths, max_bytes, grid = ss_grid) {
  rows <- grid[rep(seq_len(nrow(grid)), each = length(paths)), ]
  robots_evaluate_url_v1(
    ss_urls(rep(paths, nrow(grid))), unname(ss_tokens[rows$backend]),
    rows$ruleset, rows$backend, max_bytes = max_bytes
  )
}

# Supplied text marked as UTF-8: under LC_ALL=C an unmarked string with the
# bytes of "é" is native-encoded and gets re-encoded on its way in.
ss_text <- function(body) {
  text <- rawToChar(body)
  Encoding(text) <- "UTF-8"
  text
}

ss_eval_text <- function(body, paths, grid = ss_grid) {
  rows <- grid[rep(seq_len(nrow(grid)), each = length(paths)), ]
  robots_evaluate_text_v1(
    ss_text(body), ss_urls(rep(paths, nrow(grid))),
    unname(ss_tokens[rows$backend]), rows$ruleset, rows$backend
  )
}

ss_label <- function(r, i, ...) {
  paste(
    r$robots_policy_ruleset[[i]], r$matcher_backend[[i]], r$url[[i]], ...
  )
}

# --- What the documents say a cut 2xx resolves to ----------------------------

# design/engine-profiles.md section 7: yandex reads a cut of at least
# 512,000 stored bytes as a file over 500 KB (allow_all, whatever the
# backend); google with the google backend reads it as its uncut form and
# matches the window; everything else, and both below 512,000, stays
# incomplete.
ss_cut_expected <- function(ruleset, backend, stored, status) {
  incomplete <- list(
    policy_status = "not_evaluated", policy_action = NA_character_,
    policy_reason = "incomplete_evidence", matcher_status = "not_evaluated",
    reason = "incomplete_evidence"
  )
  if (stored < ss_window) {
    return(incomplete)
  }
  if (identical(ruleset, "yandex")) {
    return(list(
      policy_status = "evaluated", policy_action = "allow_all",
      policy_reason = if (status == 200L) {
        "yandex_file_over_500000_bytes"
      } else {
        "non_200_allow_all"
      },
      matcher_status = "not_needed", reason = "policy_allow_all"
    ))
  }
  if (identical(ruleset, "google") && identical(backend, "google")) {
    return(list(
      policy_status = "evaluated", policy_action = "use_rules",
      policy_reason = if (status == 200L) {
        "http_200_use_rules"
      } else {
        "http_2xx_use_rules"
      },
      matcher_status = "evaluated", reason = NULL
    ))
  }
  incomplete
}

ss_expect_cut_rows <- function(x, stored, status) {
  e <- x$evidence
  expect_identical(e$evidence_status, "incomplete")
  expect_true(e$body_truncated)
  expect_identical(e$termination_reason, "ceiling")
  expect_identical(e$stored_bytes, as.integer(stored))
  r <- x$results
  for (i in seq_len(nrow(r))) {
    want <- ss_cut_expected(
      r$robots_policy_ruleset[[i]], r$matcher_backend[[i]], stored, status
    )
    label <- ss_label(r, i, stored, status)
    expect_identical(r$evidence_status[[i]], "incomplete", label = label)
    expect_identical(r$policy_status[[i]], want$policy_status, label = label)
    expect_identical(r$policy_action[[i]], want$policy_action, label = label)
    expect_identical(r$policy_reason[[i]], want$policy_reason, label = label)
    expect_identical(r$matcher_status[[i]], want$matcher_status,
                     label = label)
    if (!is.null(want$reason)) {
      expect_identical(r$reason[[i]], want$reason, label = label)
    }
    if (identical(want$policy_action, "allow_all")) {
      expect_identical(r$url_decision[[i]], "allow", label = label)
    } else if (identical(want$matcher_status, "evaluated")) {
      expect_true(r$matcher_body_truncated[[i]], label = label)
    } else {
      expect_identical(r$url_decision[[i]], NA_character_, label = label)
    }
  }
}

# --- A fetched 2xx cut at max_bytes, every ruleset x backend ------------------

test_that("etlkvljs: a cut 200 or 203 at each size, every ruleset x backend", {
  body <- ss_split_body(ss_tails$rule)
  for (status in c(200L, 203L)) {
    for (max_bytes in c(511999L, 512000L, 512001L, 524288L)) {
      ss_serve(body, status)
      x <- ss_eval_url(names(ss_tails$rule$probes), max_bytes)
      ss_expect_cut_rows(x, max_bytes, status)
    }
  }
})

test_that("etlkvljs: a line split at byte 512,000 is never read in part", {
  # google with the google backend matches the complete lines of the first
  # 512,000 bytes; the split line, whether through a rule, a percent-escape
  # or a UTF-8 character, is dropped, so each probe is allowed.
  google <- ss_grid[ss_grid$ruleset == "google" &
                      ss_grid$backend == "google", ]
  for (name in names(ss_tails)) {
    tail <- ss_tails[[name]]
    paths <- names(tail$probes)
    for (max_bytes in c(512000L, 512001L, 524288L)) {
      ss_serve(ss_split_body(tail))
      r <- ss_eval_url(paths, max_bytes, google)$results
      label <- paste(name, max_bytes)
      expect_identical(r$policy_reason, rep("http_200_use_rules", 2L),
                       label = label)
      expect_identical(r$url_decision, rep("allow", 2L), label = label)
      expect_identical(r$reason, rep("default_allow", 2L), label = label)
      expect_identical(
        r$matcher_input_bytes, rep(ss_window - tail$keep, 2L), label = label
      )
      expect_identical(r$matcher_body_truncated, rep(TRUE, 2L),
                       label = label)
    }
  }
})

test_that("etlkvljs: the same lines inside the window are read", {
  # The positive control: each probe's decision when its line is whole.
  google <- ss_grid[ss_grid$ruleset == "google" &
                      ss_grid$backend == "google", ]
  for (name in names(ss_tails)) {
    tail <- ss_tails[[name]]
    ss_serve(ss_split_body(tail, split = ss_window - 1000L))
    r <- ss_eval_url(names(tail$probes), 524288L, google)$results
    expect_identical(r$url_decision, unname(tail$probes), label = name)
    expect_identical(r$matcher_body_truncated, rep(TRUE, 2L), label = name)
  }
})

test_that("etlkvljs: a 3xx over max_bytes is incomplete under every ruleset", {
  local_fake_ssrfr(function(req) {
    fake_response(
      302L, headers = list(Location = "http://example.com/moved"),
      body = ss_split_body(ss_tails$rule)
    )
  })
  x <- ss_eval_url("/x", 524288L)
  expect_identical(x$evidence$legacy_fetch_outcome, "body_too_large")
  expect_identical(x$evidence$evidence_status, "incomplete")
  expect_false(x$evidence$body_truncated)
  r <- x$results
  expect_identical(r$policy_reason, rep("incomplete_evidence", nrow(r)))
  expect_identical(r$url_decision, rep(NA_character_, nrow(r)))
})

# --- A supplied body around the limits, every ruleset x backend --------------

# A supplied body is `use_rules` under every ruleset (engine-profiles.md
# section 2), so the yandex 500,000-byte branch, which reads fetched
# evidence, never applies to it; only the google matcher's 512,000-byte
# window does.
ss_expect_supplied <- function(x, size, google_bytes, decisions) {
  r <- x$results
  expect_identical(x$evidence$stored_bytes, as.integer(size))
  expect_false(x$evidence$body_truncated)
  expect_identical(r$evidence_status, rep("usable_body", nrow(r)))
  expect_identical(r$policy_reason, rep("supplied_body_use_rules", nrow(r)))
  for (i in seq_len(nrow(r))) {
    backend <- r$matcher_backend[[i]]
    label <- ss_label(r, i, size)
    if (identical(backend, "rfc9309")) {
      expect_identical(r$matcher_status[[i]], "capability_unavailable",
                       label = label)
      expect_identical(r$url_decision[[i]], NA_character_, label = label)
      next
    }
    # contract mismatch: engine-profiles.md section 6 and engine-contract-v1.md
    # call the bing backend capability_unavailable; it is available.
    expect_identical(r$matcher_status[[i]], "evaluated", label = label)
    expect_identical(
      r$url_decision[[i]], decisions[[backend]][[r$url[[i]]]], label = label
    )
    windowed <- identical(backend, "google") && size > ss_window
    expect_identical(r$matcher_body_truncated[[i]], windowed, label = label)
    expect_identical(
      r$matcher_input_bytes[[i]],
      if (identical(backend, "google")) google_bytes else as.integer(size),
      label = label
    )
  }
}

ss_decisions <- function(google, other) {
  list(google = google, yandex = other, bing = other)
}

test_that("etlkvljs: a supplied body whose last line ends at the limits", {
  # The rule line's LF is the body's last byte. Up to 512,001 bytes the
  # line's text lies inside the google window, so every matcher reads it:
  # at 512,001 only the LF is past the window, and the byte past it shows
  # the line is complete (google matches 512,000 bytes). At 512,002 the
  # window splits the text, so google drops the line; yandex and bing read
  # it.
  tail <- charToRaw("Disallow: /private\n")
  paths <- c("/private", "/public")
  read <- stats::setNames(c("disallow", "allow"), ss_urls(paths))
  dropped <- stats::setNames(c("allow", "allow"), ss_urls(paths))
  for (size in c(511999L, 512000L, 512001L, 512002L)) {
    body <- ss_body(tail, size - length(tail), size)
    x <- ss_eval_text(body, paths)
    google <- if (size > ss_window + 1L) dropped else read
    google_bytes <- if (size > ss_window + 1L) {
      size - length(tail)
    } else {
      min(size, ss_window)
    }
    ss_expect_supplied(x, size, google_bytes, ss_decisions(google, read))
  }
})

test_that("etlkvljs: a supplied body over 500,000 bytes keeps use_rules", {
  # Under the yandex ruleset too: the size branch reads fetched evidence
  # (engine-profiles.md section 2: a supplied body is use_rules).
  # contract mismatch: engine-contract-v1.md says bodies over 500,000 bytes
  # resolve allow_all under yandex, without limiting that to fetched bodies.
  body <- ss_body(charToRaw("Disallow: /private\n"), 1000L, 500001L)
  x <- ss_eval_text(body, "/private")
  r <- x$results
  expect_identical(r$policy_action, rep("use_rules", nrow(r)))
  yandex <- r$robots_policy_ruleset == "yandex" &
    r$matcher_backend != "rfc9309"
  expect_identical(r$url_decision[yandex], rep("disallow", sum(yandex)))
})

test_that("etlkvljs: a supplied line split at byte 512,000", {
  # google drops the line the window splits; yandex and bing read the whole
  # supplied body, so they apply it. Neither of those two matches a raw
  # non-ASCII pattern against its percent-escaped path, so the utf8 line
  # allows both of its probes there (matcher semantics, not size).
  for (name in names(ss_tails)) {
    tail <- ss_tails[[name]]
    paths <- names(tail$probes)
    read <- stats::setNames(unname(tail$probes), ss_urls(paths))
    dropped <- stats::setNames(rep("allow", 2L), ss_urls(paths))
    if (identical(name, "utf8")) {
      read <- dropped
    }
    for (size in c(524288L, 600000L)) {
      x <- ss_eval_text(ss_split_body(tail, size = size), paths)
      ss_expect_supplied(
        x, size, ss_window - tail$keep, ss_decisions(dropped, read)
      )
    }
  }
})

# --- The legacy functions -----------------------------------------------------

test_that("etlkvljs: allowed_by_robots_text() reads past byte 512,000", {
  # The legacy text path has no truncation flag and no google window: it
  # matches the whole supplied body (engine-contract-v1.md, Legacy
  # compatibility: the legacy functions remain unchanged).
  for (name in names(ss_tails)) {
    tail <- ss_tails[[name]]
    x <- allowed_by_robots_text(
      ss_text(ss_split_body(tail)), ss_urls(names(tail$probes)), "bot"
    )
    expect_identical(
      x$results$allowed, unname(tail$probes == "allow"), label = name
    )
    expect_false(x$robots$body_truncated)
  }
})

test_that("etlkvljs: allowed_by_robots_url() drops the line max_bytes splits", {
  # engine-contract-v1.md: the legacy path matches a cut prefix up to its
  # last line break, with no 512,000-byte window.
  for (name in names(ss_tails)) {
    tail <- ss_tails[[name]]
    paths <- names(tail$probes)
    for (max_bytes in c(511999L, 512000L, 524288L)) {
      ss_serve(ss_split_body(tail, split = max_bytes))
      x <- allowed_by_robots_url(ss_urls(paths), "bot", max_bytes = max_bytes)
      label <- paste(name, max_bytes)
      expect_identical(x$results$allowed, c(TRUE, TRUE), label = label)
      expect_identical(x$results$decision_source, rep("default_allow", 2L),
                       label = label)
      expect_true(x$robots$body_truncated, label = label)
      expect_identical(x$robots$body_size, max_bytes, label = label)
    }
  }
})

test_that("etlkvljs: legacy and v1 differ on a line past the window", {
  # A complete line between bytes 512,000 and max_bytes: the legacy path
  # reads it, the google ruleset's v1 reading does not (documented).
  tail <- ss_tails$rule
  ss_serve(ss_split_body(tail, split = ss_window + 1000L))
  url <- ss_urls("/private-drafts/x")
  legacy <- allowed_by_robots_url(url, "bot")
  expect_false(legacy$results$allowed)
  v1 <- robots_evaluate_url_v1(url, "bot", "google", "google")
  expect_identical(v1$results$url_decision, "allow")
  adapted <- as_legacy_robots_decisions_v1(v1)
  expect_true(adapted$results$allowed)
})

# --- robots_validate_url() on a cut body ------------------------------------

test_that("etlkvljs: the validator reads a cut prefix to its last line", {
  for (name in names(ss_tails)) {
    tail <- ss_tails[[name]]
    for (max_bytes in c(511999L, 512000L, 512001L, 524288L)) {
      ss_serve(ss_split_body(tail, split = max_bytes))
      x <- robots_validate_url("http://example.com/", max_bytes = max_bytes)
      d <- x$documents
      label <- paste(name, max_bytes)
      expect_identical(d$fetch_outcome, "fetched", label = label)
      expect_true(d$body_truncated, label = label)
      expect_true(d$limit_exceeded, label = label)
      expect_identical(d$byte_size, max_bytes, label = label)
      expect_identical(d$disallow_directives, 0L, label = label)
      expect_identical(x$diagnostics$code, "body_truncated", label = label)
      expect_identical(x$diagnostics$severity, "warning", label = label)
    }
  }
})

test_that("etlkvljs: the validator reads a supplied body past 512,000", {
  for (name in names(ss_tails)) {
    x <- robots_validate_text(ss_split_body(ss_tails[[name]]))
    expect_false(x$documents$body_truncated, label = name)
    expect_identical(x$documents$disallow_directives, 1L, label = name)
    expect_false("body_truncated" %in% x$diagnostics$code, label = name)
  }
})

# --- Status classes: the v1 policy -------------------------------------------

# engine-profiles.md sections 3 and 4, transcribed by hand (status, action)
# per ruleset. assumed_rfc9309 is the RFC reading as an application choice
# (section 1), so it takes the rfc9309 cell.
ss_cell <- function(status, action = NA_character_) list(status, action)
ss_gap <- ss_cell("documentation_gap")
ss_open <- ss_cell("evaluated", "allow_all")
ss_rules <- ss_cell("evaluated", "use_rules")
ss_context <- ss_cell("context_required")
ss_row <- function(rfc9309, google, yandex, bing = ss_gap) {
  list(
    rfc9309 = rfc9309, google = google, yandex = yandex, bing = bing,
    assumed_rfc9309 = rfc9309
  )
}
ss_status_policy <- list(
  status_200 = ss_row(ss_rules, ss_rules, ss_rules),
  status_other_2xx = ss_row(ss_gap, ss_rules, ss_open),
  status_206 = ss_row(ss_gap, ss_rules, ss_open),
  status_4xx = ss_row(ss_open, ss_open, ss_open),
  status_429 = ss_row(ss_open, ss_gap, ss_open),
  status_5xx = ss_row(ss_context, ss_context, ss_open),
  transport = ss_row(ss_context, ss_context, ss_gap),
  redirect_over_budget = ss_row(ss_open, ss_open, ss_gap),
  protocol_error = ss_row(ss_gap, ss_gap, ss_gap)
)

ss_over_budget <- function(req) {
  hop <- suppressWarnings(as.integer(sub("^.*/r", "", req$url)))
  hop <- if (is.na(hop)) 1L else hop + 1L
  fake_response(
    301L, url = req$url,
    headers = list(Location = paste0("http://example.com/r", hop))
  )
}

ss_status_cases <- list(
  list(label = "200", category = "status_200", evidence = "usable_body",
       handler = function(req) fake_response(200L, body = "User-agent: *\n")),
  list(label = "203", category = "status_other_2xx",
       evidence = "usable_body",
       handler = function(req) fake_response(203L, body = "User-agent: *\n")),
  list(label = "204", category = "status_other_2xx",
       evidence = "usable_body",
       handler = function(req) fake_response(204L)),
  list(label = "206", category = "status_206", evidence = "partial",
       handler = function(req) fake_response(206L, body = "User-agent: *\n")),
  list(label = "302 no Location", category = "protocol_error",
       evidence = "http_protocol_error",
       handler = function(req) fake_response(302L)),
  list(label = "301 loop", category = "protocol_error",
       evidence = "http_protocol_error",
       handler = function(req) {
         fake_response(301L, url = req$url,
                       headers = list(Location = req$url))
       }),
  list(label = "301 over budget", category = "redirect_over_budget",
       evidence = "redirect_over_budget", handler = ss_over_budget),
  list(label = "400", category = "status_4xx", evidence = "http_status",
       handler = function(req) fake_response(400L)),
  list(label = "401", category = "status_4xx", evidence = "http_status",
       handler = function(req) fake_response(401L)),
  list(label = "403", category = "status_4xx", evidence = "http_status",
       handler = function(req) fake_response(403L)),
  list(label = "404", category = "status_4xx", evidence = "http_status",
       handler = function(req) fake_response(404L)),
  list(label = "410", category = "status_4xx", evidence = "http_status",
       handler = function(req) fake_response(410L)),
  list(label = "429", category = "status_429", evidence = "http_status",
       handler = function(req) fake_response(429L)),
  list(label = "500", category = "status_5xx", evidence = "http_status",
       handler = function(req) fake_response(500L)),
  list(label = "503", category = "status_5xx", evidence = "http_status",
       handler = function(req) fake_response(503L)),
  list(label = "timeout", category = "transport", evidence = "transport_fail",
       handler = function(req) fake_failure("timeout")),
  list(label = "unresolvable", category = "transport",
       evidence = "transport_fail",
       handler = function(req) fake_failure("unresolvable")),
  list(label = "102", category = "protocol_error",
       evidence = "http_protocol_error",
       handler = function(req) fake_response(102L))
)

test_that("etlkvljs: each status class resolves as section 4 documents", {
  for (case in ss_status_cases) {
    local_fake_ssrfr(case$handler)
    x <- ss_eval_url("/x", 524288L)
    r <- x$results
    expect_identical(x$evidence$evidence_status, case$evidence,
                     label = case$label)
    for (i in seq_len(nrow(r))) {
      want <- ss_status_policy[[case$category]][[r$robots_policy_ruleset[[i]]]]
      label <- ss_label(r, i, case$label)
      expect_identical(r$policy_status[[i]], want[[1L]], label = label)
      expect_identical(r$policy_action[[i]], want[[2L]], label = label)
      if (identical(want[[2L]], "allow_all")) {
        expect_identical(r$url_decision[[i]], "allow", label = label)
        expect_identical(r$matcher_status[[i]], "not_needed", label = label)
      } else if (!identical(want[[2L]], "use_rules")) {
        expect_identical(r$url_decision[[i]], NA_character_, label = label)
      } else if (identical(case$evidence, "partial")) {
        # Policy resolves, the partial body is not matched (section 2).
        expect_identical(r$matcher_status[[i]], "not_evaluated",
                         label = label)
        expect_identical(r$url_decision[[i]], NA_character_, label = label)
      }
    }
  }
})

test_that("etlkvljs: a 4xx or 5xx over max_bytes keeps its status class", {
  # engine-profiles.md section 7: classified by its status (section 4).
  body <- ss_split_body(ss_tails$rule)
  for (status in c(403L, 503L)) {
    ss_serve(body, status)
    x <- ss_eval_url("/x", 524288L)
    expect_identical(x$evidence$evidence_status, "http_status")
    expect_false(x$evidence$body_truncated)
    expect_false(x$evidence$body_present)
    r <- x$results
    category <- if (status == 403L) "status_4xx" else "status_5xx"
    for (i in seq_len(nrow(r))) {
      want <- ss_status_policy[[category]][[r$robots_policy_ruleset[[i]]]]
      expect_identical(r$policy_status[[i]], want[[1L]],
                       label = ss_label(r, i, status))
      expect_identical(r$policy_action[[i]], want[[2L]],
                       label = ss_label(r, i, status))
    }
  }
})

# --- Status classes: the validator -------------------------------------------

# The validator's code, severity and engine readings per class, from the
# robots_validate_text() code table and the section 3 and 4 cells above.
ss_no_robots <- paste0(
  "may treat it as no robots.txt, which places no restrictions on crawling"
)
ss_open_yandex <- "places no restrictions on crawling"
ss_context_phrase <- paste0(
  "context-dependent (may pause crawling or use its last cached copy)"
)
ss_readings <- function(google, yandex, bing = "not documented") {
  paste0("Google: ", google, "; Yandex: ", yandex, "; Bing: ", bing, ".")
}
ss_tail <- " See robots_engine_contract_v1()."
ss_firewall <- paste(
  "A 401 or 403 is often a firewall or bot filter answering this client,",
  "not the site's own robots.txt."
)

ss_validator_cases <- list(
  list(label = "400", code = "acquisition_http_4xx", severity = "warning",
       message = paste0("HTTP 400: ",
                        ss_readings(ss_no_robots, ss_open_yandex), ss_tail)),
  list(label = "401", code = "acquisition_http_4xx", severity = "warning",
       message = paste0("HTTP 401: ",
                        ss_readings(ss_no_robots, ss_open_yandex), " ",
                        ss_firewall, ss_tail)),
  list(label = "403", code = "acquisition_http_4xx", severity = "warning",
       message = paste0("HTTP 403: ",
                        ss_readings(ss_no_robots, ss_open_yandex), " ",
                        ss_firewall, ss_tail)),
  list(label = "404", code = "acquisition_missing", severity = "info",
       message = paste0("HTTP 404: ",
                        ss_readings(ss_no_robots, ss_open_yandex), ss_tail)),
  list(label = "410", code = "acquisition_missing", severity = "info",
       message = paste0("HTTP 410: ",
                        ss_readings(ss_no_robots, ss_open_yandex), ss_tail)),
  list(label = "429", code = "acquisition_http_429", severity = "error",
       message = paste0(
         "HTTP 429: ",
         ss_readings(
           paste("not documented for robots.txt (Google excludes 429",
                 "from its 4xx rule)"),
           ss_open_yandex
         ),
         ss_tail
       )),
  list(label = "500", code = "acquisition_http_5xx", severity = "error",
       message = paste0("HTTP 500: ",
                        ss_readings(ss_context_phrase, ss_open_yandex),
                        ss_tail)),
  list(label = "503", code = "acquisition_http_5xx", severity = "error",
       message = paste0("HTTP 503: ",
                        ss_readings(ss_context_phrase, ss_open_yandex),
                        ss_tail)),
  list(label = "102", code = "acquisition_http_protocol", severity = "error",
       message = paste0("HTTP 102: ",
                        ss_readings("not documented", "not documented"),
                        ss_tail)),
  list(label = "timeout", code = "acquisition_transport_failed",
       severity = "error",
       message = paste0(": ",
                        ss_readings(ss_context_phrase, "not documented"),
                        ss_tail)),
  list(label = "302 no Location", code = "acquisition_redirect_no_location",
       severity = "error",
       message = paste0(": ",
                        ss_readings("not documented", "not documented"),
                        ss_tail)),
  list(label = "301 loop", code = "acquisition_redirect_loop",
       severity = "error",
       message = paste0(": ",
                        ss_readings("not documented", "not documented"),
                        ss_tail)),
  list(label = "301 over budget", code = "acquisition_redirect_over_budget",
       severity = "error",
       message = paste0(
         ": ",
         ss_readings(
           paste("may stop and treat it as a 404, which places no",
                 "restrictions on crawling"),
           "not documented"
         ),
         ss_tail
       )),
  list(label = "206", code = "acquisition_partial_response",
       severity = "error",
       message = "Partial HTTP response was rejected; no body was validated.")
)

ss_case_handler <- function(label) {
  for (case in ss_status_cases) {
    if (identical(case$label, label)) {
      return(case$handler)
    }
  }
  stop("no status case ", label)
}

test_that("etlkvljs: the validator's code and message per status class", {
  for (case in ss_validator_cases) {
    local_fake_ssrfr(ss_case_handler(case$label))
    x <- robots_validate_url("http://example.com/")
    d <- x$diagnostics
    expect_identical(d$code, case$code, label = case$label)
    expect_identical(d$severity, case$severity, label = case$label)
    expect_identical(x$documents$validation_status, "not_validated",
                     label = case$label)
    if (startsWith(case$message, ": ")) {
      # The fetch's own message opens it; the engine readings close it.
      expect_true(endsWith(d$message, case$message), label = d$message)
    } else {
      expect_identical(d$message, case$message, label = case$label)
    }
  }
})

test_that("etlkvljs: a non-200 2xx body is validated with no status code", {
  # Yandex reads a non-200 2xx as allow_all (section 4), but the validator
  # validates its body like a 200's and names no status.
  for (status in c(203L, 204L)) {
    local_fake_ssrfr(function(req) {
      fake_response(status, body = "User-agent: *\nDisallow: /x\n")
    })
    x <- robots_validate_url("http://example.com/")
    expect_identical(x$documents$http_status, status)
    expect_identical(x$documents$fetch_outcome, "fetched")
    expect_false(any(startsWith(x$diagnostics$code, "acquisition_")))
  }
})

test_that("etlkvljs: a 2xx refused whole is acquisition_limit_exceeded", {
  # engine-profiles.md section 7: a status mismatch over the limit is
  # body_too_large, refused whole, as a 3xx is.
  # contract mismatch: the robots_validate_text() code table says this code
  # is for a 3xx body; a 2xx ssrfr refuses whole gets it too.
  local_fake_ssrfr(function(req) {
    fake_failure(
      "response-too-large",
      check = "decoded-bytes", limit = "max_response_size",
      status = 200L, observed_bytes = 600000L
    )
  })
  x <- robots_validate_url("http://example.com/")
  expect_identical(x$documents$fetch_outcome, "body_too_large")
  expect_identical(x$diagnostics$code, "acquisition_limit_exceeded")
  expect_identical(
    x$diagnostics$message,
    paste(
      "Decoded body exceeded max_bytes (524288); no truncated body was",
      "validated."
    )
  )
  expect_true(x$documents$limit_exceeded)
  expect_false(x$documents$body_truncated)
})
