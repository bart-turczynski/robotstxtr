# A robots.txt cut at max_bytes under the google ruleset (ROBO-ptibdnvy,
# ADR 0001 slice 9). The evidence of a cut 2xx stays `incomplete` (an L0
# fact); the google ruleset with the google matcher backend reads a cut that
# stored at least 512,000 bytes, its whole parse window, as the table does an
# uncut 2xx and matches the complete lines inside the window. A smaller cut,
# a google cut with another backend, and a cut under rfc9309,
# assumed_rfc9309 or bing stay incomplete; yandex resolves a cut of that
# size allow_all with no matcher (ROBO-arrtietl). Responses are scripted at
# the ssrfr boundary (helper-fake-ssrfr.R).

gc_url <- "http://example.test/private"

# A 600,000-byte robots.txt that disallows everything, with a NUL and invalid
# UTF-8 / latin1 bytes in its first lines and no line break after them.
gc_body <- function(size = 600000L) {
  head <- gc_head()
  c(head, rep(charToRaw("#"), size - length(head)))
}

gc_head <- function() {
  c(
    charToRaw("User-agent: *\nDisallow: /\n# "),
    as.raw(c(0x00, 0xff, 0xfe, 0xe9, 0xc3)), charToRaw("\n")
  )
}

# "User-agent: *\n" and one comment line, sized so that `tail` starts at
# byte `at + 1`, then `tail`, then a run with no line break up to `size`.
gc_edge_body <- function(tail, at, size = 600000L) {
  agent <- charToRaw("User-agent: *\n")
  pad <- at - length(agent) - 1L
  head <- c(agent, rep(charToRaw("#"), pad), charToRaw("\n"))
  stopifnot(length(head) == at)
  body <- c(head, charToRaw(tail))
  c(body, rep(charToRaw("#"), size - length(body)))
}

gc_serve <- function(status = 200L, body = gc_body(), env = parent.frame()) {
  local_fake_ssrfr(function(req) fake_response(status, body = body), env = env)
}

# Fail any matcher call. The registry looks these up at call time.
gc_forbid_matchers <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv())
  calls$google <- 0L
  calls$yandex <- 0L
  calls$bing <- 0L
  testthat::local_mocked_bindings(
    match_google_v1 = function(body, url, product_token) {
      calls$google <- calls$google + 1L
      stop("match_google_v1 must not be called")
    },
    match_yandex_v1 = function(bodies, urls, product_tokens) {
      calls$yandex <- calls$yandex + 1L
      stop("match_yandex_v1 must not be called")
    },
    match_bing_v1 = function(bodies, urls, product_tokens) {
      calls$bing <- calls$bing + 1L
      stop("match_bing_v1 must not be called")
    },
    .package = "robotstxtr",
    .env = env
  )
  calls
}

gc_expect_no_matcher <- function(calls) {
  expect_identical(
    c(calls$google, calls$yandex, calls$bing), c(0L, 0L, 0L)
  )
}

gc_eval <- function(url = gc_url, ruleset = "google", backend = ruleset,
                    max_bytes = 524288L) {
  robots_evaluate_url_v1(url, "bot", ruleset, backend, max_bytes = max_bytes)
}

gc_expect_cut_evidence <- function(x, max_bytes) {
  e <- x$evidence
  expect_identical(e$evidence_status, "incomplete")
  expect_identical(e$termination_reason, "ceiling")
  expect_identical(e$legacy_fetch_outcome, "fetched")
  expect_true(e$body_truncated)
  expect_identical(e$stored_bytes, as.integer(max_bytes))
}

gc_expect_incomplete <- function(x) {
  r <- x$results
  expect_identical(r$policy_status, rep("not_evaluated", nrow(r)))
  expect_identical(r$policy_action, rep(NA_character_, nrow(r)))
  expect_identical(r$policy_reason, rep("incomplete_evidence", nrow(r)))
  expect_identical(r$reason, rep("incomplete_evidence", nrow(r)))
  expect_identical(r$url_decision, rep(NA_character_, nrow(r)))
  expect_identical(r$matcher_status, rep("not_evaluated", nrow(r)))
}

# The table cell of an uncut google 2xx, matched, with the window flagged.
gc_expect_matched <- function(x, reason = "http_200_use_rules",
                              category = "status_200") {
  r <- x$results
  table <- engine_policy_table_v1()
  row <- table[
    table$category == category & table$ruleset == "google", ,
    drop = FALSE
  ]
  expect_identical(r$evidence_status, "incomplete")
  expect_identical(r$policy_status, "evaluated")
  expect_identical(r$policy_action, "use_rules")
  expect_identical(r$policy_reason, reason)
  expect_identical(r$policy_reason, row$policy_reason[[1L]])
  expect_identical(r$policy_provenance, "documented")
  expect_identical(r$policy_source, row$policy_source[[1L]])
  expect_identical(r$matcher_status, "evaluated")
  expect_true(r$matcher_body_truncated)
}

gc_cut_ev <- function(stored_bytes, body_truncated = TRUE, status = 200L) {
  ev <- list(
    evidence_status = "incomplete",
    source_kind = "fetched",
    final_http_status = status,
    stored_bytes = stored_bytes
  )
  ev["body_truncated"] <- list(body_truncated)
  ev
}

gc_resolve <- function(ev, ruleset = "google", backend = ruleset) {
  resolve_policy_v1(ev, ruleset, engine_policy_table_v1(), backend)
}

# --- The facade ---------------------------------------------------------------

test_that("ROBO-ptibdnvy: a google 200 cut at the default 512 KiB", {
  gc_serve()
  x <- gc_eval()
  gc_expect_cut_evidence(x, 524288L)
  gc_expect_matched(x)
  r <- x$results
  expect_identical(r$url_decision, "disallow")
  expect_identical(r$reason, "rule_disallow")
  expect_identical(r$matched_line, 2L)
  expect_identical(r$matched_rule_type, "disallow")
  # The run after the head has no line break, so only the head is read.
  expect_identical(r$matcher_input_bytes, length(gc_head()))
})

test_that("ROBO-ptibdnvy: a google 200 cut at exactly 512,000 bytes", {
  gc_serve()
  x <- gc_eval(max_bytes = 512000L)
  gc_expect_cut_evidence(x, 512000L)
  gc_expect_matched(x)
  expect_identical(x$results$url_decision, "disallow")
  expect_identical(x$results$matcher_input_bytes, length(gc_head()))
})

test_that("ROBO-ptibdnvy: a rule the cut splits is not a shorter rule", {
  # The cut at 512,000 leaves "disallow: /" of "disallow: /private-drafts/".
  body <- gc_edge_body("disallow: /private-drafts/\n", 512000L - 11L)
  gc_serve(body = body)
  x <- gc_eval("http://example.test/public", max_bytes = 512000L)
  gc_expect_cut_evidence(x, 512000L)
  gc_expect_matched(x)
  r <- x$results
  expect_identical(r$url_decision, "allow")
  expect_identical(r$reason, "default_allow")
  expect_identical(r$matched_line, NA_integer_)
  expect_identical(r$matcher_input_bytes, 512000L - 11L)
})

test_that("ROBO-ptibdnvy: a line whose break the cut hides is dropped", {
  # "disallow: /private" ends at byte 512,000; its LF, byte 512,001, is cut.
  body <- gc_edge_body("disallow: /private\n", 512000L - 18L)
  gc_serve(body = body)
  x <- gc_eval(max_bytes = 512000L)
  gc_expect_cut_evidence(x, 512000L)
  gc_expect_matched(x)
  r <- x$results
  expect_identical(r$url_decision, "allow")
  expect_identical(r$reason, "default_allow")
  expect_identical(r$matcher_input_bytes, 512000L - 18L)
})

test_that("ROBO-ptibdnvy: a line whose break is the last stored byte applies", {
  body <- gc_edge_body("disallow: /private\n", 512000L - 19L)
  gc_serve(body = body)
  x <- gc_eval(max_bytes = 512000L)
  gc_expect_cut_evidence(x, 512000L)
  gc_expect_matched(x)
  r <- x$results
  expect_identical(r$url_decision, "disallow")
  expect_identical(r$reason, "rule_disallow")
  expect_identical(r$matched_line, 3L)
  expect_identical(r$matched_rule_value, "/private")
  expect_identical(r$matcher_input_bytes, 512000L)
})

test_that("ROBO-ptibdnvy: a cut with no line break is read as empty", {
  gc_serve(body = rep(charToRaw("#"), 600000L))
  x <- gc_eval(max_bytes = 512000L)
  gc_expect_cut_evidence(x, 512000L)
  gc_expect_matched(x)
  expect_identical(x$results$url_decision, "allow")
  expect_identical(x$results$reason, "default_allow")
  expect_identical(x$results$matcher_input_bytes, 0L)
})

test_that("ROBO-ptibdnvy: a longer cut reads as match_google_v1() does", {
  # A line crosses byte 512,000 and more lines follow before the cut, so the
  # stored body's complete lines run past the window.
  tail <- c(
    "disallow: /private-drafts/\n",
    rep(paste0(strrep("#", 99L), "\n"), 100L)
  )
  body <- gc_edge_body(paste(tail, collapse = ""), 512000L - 11L)
  stored <- body[seq_len(524288L)]
  for (path in c("/private-drafts/x", "/public")) {
    url <- paste0("http://example.test", path)
    gc_serve(body = body)
    x <- gc_eval(url)
    gc_expect_cut_evidence(x, 524288L)
    gc_expect_matched(x)
    direct <- match_google_v1(stored, url, "bot")
    r <- x$results
    expect_identical(r$url_decision, direct$url_decision)
    expect_identical(r$url_decision, "allow")
    expect_identical(r$matched_line, direct$matched_line)
    expect_identical(r$matcher_input_bytes, direct$matcher_input_bytes)
    expect_identical(r$matcher_input_bytes, 512000L - 11L)
    expect_true(direct$matcher_body_truncated)
  }
})

test_that("ROBO-ptibdnvy: a google 203 cut is matched as an uncut 203", {
  gc_serve(status = 203L)
  x <- gc_eval()
  gc_expect_cut_evidence(x, 524288L)
  gc_expect_matched(x, "http_2xx_use_rules", "status_other_2xx")
  expect_identical(x$results$url_decision, "disallow")
})

test_that("ROBO-ptibdnvy: a google cut at 511,999 bytes stays incomplete", {
  for (status in c(200L, 203L)) {
    gc_serve(status = status)
    calls <- gc_forbid_matchers()
    x <- gc_eval(max_bytes = 511999L)
    gc_expect_cut_evidence(x, 511999L)
    gc_expect_incomplete(x)
    gc_expect_no_matcher(calls)
  }
})

test_that("ROBO-ptibdnvy: a google cut needs the google backend", {
  # The 524,288 cut leaves "disallow: /" of "disallow: /private-drafts/".
  body <- gc_edge_body("disallow: /private-drafts/\n", 524288L - 11L)
  url <- "http://example.test/public"
  gc_serve(body = body)
  calls <- gc_forbid_matchers()
  x <- robots_evaluate_url_v1(
    rep(url, 2L), c("Yandex", "bingbot"), "google", c("yandex", "bing")
  )
  gc_expect_cut_evidence(x, 524288L)
  gc_expect_incomplete(x)
  expect_identical(x$results$matcher_body_truncated, c(NA, NA))
  gc_expect_no_matcher(calls)
})

test_that("ROBO-ptibdnvy: google with the google backend reads that cut", {
  body <- gc_edge_body("disallow: /private-drafts/\n", 524288L - 11L)
  gc_serve(body = body)
  x <- gc_eval("http://example.test/public")
  gc_expect_matched(x)
  expect_identical(x$results$url_decision, "allow")
  # The comment line crosses the window, so only "User-agent: *\n" is read.
  expect_identical(x$results$matcher_input_bytes, 14L)
})

test_that("ROBO-ptibdnvy: a cut source's readable body is built once", {
  body <- gc_edge_body("disallow: /private-drafts/\n", 512000L - 11L)
  urls <- paste0("http://example.test", c("/public", "/private-drafts/x", "/"))
  original <- readable_body
  count <- new.env(parent = emptyenv())
  count$n <- 0L
  testthat::local_mocked_bindings(
    readable_body = function(body, body_truncated) {
      count$n <- count$n + 1L
      original(body, body_truncated)
    },
    .package = "robotstxtr"
  )
  gc_serve(body = body)
  one <- gc_eval(urls[[1L]], max_bytes = 512000L)
  calls_one <- count$n
  count$n <- 0L
  all <- gc_eval(urls, max_bytes = 512000L)
  expect_identical(count$n, calls_one)
  expect_identical(all$results$url_decision, rep("allow", 3L))
  expect_identical(all$results$matcher_input_bytes, rep(512000L - 11L, 3L))
  expect_identical(all$results$matcher_body_truncated, rep(TRUE, 3L))
  expect_identical(all$results[1L, "url_decision"], one$results$url_decision)
})

test_that("ROBO-ptibdnvy: rfc9309, assumed_rfc9309 and bing keep a cut", {
  gc_serve()
  calls <- gc_forbid_matchers()
  x <- robots_evaluate_url_v1(
    rep(gc_url, 3L), "bot",
    c("rfc9309", "assumed_rfc9309", "bing"),
    c("rfc9309", "bing", "bing")
  )
  gc_expect_cut_evidence(x, 524288L)
  gc_expect_incomplete(x)
  gc_expect_no_matcher(calls)
})

test_that("ROBO-ptibdnvy: yandex still reads a cut as over its limit", {
  gc_serve()
  calls <- gc_forbid_matchers()
  x <- gc_eval(ruleset = "yandex")
  r <- x$results
  expect_identical(r$policy_action, "allow_all")
  expect_identical(r$policy_reason, "yandex_file_over_500000_bytes")
  expect_identical(r$url_decision, "allow")
  gc_expect_no_matcher(calls)
})

test_that("ROBO-ptibdnvy: an uncut google body is matched whole", {
  # readable_body() leaves an uncut body alone: no trailing break needed.
  gc_serve(body = charToRaw("User-agent: *\nDisallow: /private"))
  x <- gc_eval()
  expect_identical(x$evidence$evidence_status, "usable_body")
  expect_false(x$evidence$body_truncated)
  expect_identical(x$results$url_decision, "disallow")
  expect_false(x$results$matcher_body_truncated)
})

test_that("ROBO-ptibdnvy: the legacy adapter carries a matched cut", {
  gc_serve()
  legacy <- as_legacy_robots_decisions_v1(gc_eval())
  r <- legacy$results
  expect_false(r$allowed)
  expect_identical(r$decision_source, "rule_disallow")
  expect_identical(r$fetch_outcome, "fetched")
  expect_identical(r$matched_line, 2L)
  expect_true(legacy$robots$body_truncated)
})

test_that("ROBO-ptibdnvy: the legacy adapter keeps a short cut unknown", {
  gc_serve()
  legacy <- as_legacy_robots_decisions_v1(gc_eval(max_bytes = 511999L))
  r <- legacy$results
  expect_identical(r$allowed, NA)
  expect_identical(r$decision_source, "fetch_unknown")
  expect_true(legacy$robots$body_truncated)
})

# --- resolve_policy_v1() ------------------------------------------------------

test_that("ROBO-ptibdnvy: resolve_policy_v1() on cut google evidence", {
  expect_identical(
    gc_resolve(gc_cut_ev(511999L))$policy_reason, "incomplete_evidence"
  )
  for (bytes in c(512000L, 524288L)) {
    policy <- gc_resolve(gc_cut_ev(bytes))
    expect_identical(policy$policy_action, "use_rules")
    expect_identical(policy$policy_reason, "http_200_use_rules")
    policy <- gc_resolve(gc_cut_ev(bytes, status = 203L))
    expect_identical(policy$policy_action, "use_rules")
    expect_identical(policy$policy_reason, "http_2xx_use_rules")
  }
  expect_true(ceiling_cut_readable_v1(gc_cut_ev(512000L), "google", "google"))
  expect_false(
    ceiling_cut_readable_v1(gc_cut_ev(511999L), "google", "google")
  )
  # The google reading is the google matcher's: no other backend, and no
  # backend given, opens the cut.
  for (backend in list("yandex", "bing", "rfc9309", NA_character_)) {
    expect_false(
      ceiling_cut_readable_v1(gc_cut_ev(524288L), "google", backend)
    )
    expect_identical(
      gc_resolve(gc_cut_ev(524288L), backend = backend)$policy_reason,
      "incomplete_evidence"
    )
  }
  expect_false(ceiling_cut_readable_v1(gc_cut_ev(524288L), "google"))
  for (ruleset in c("rfc9309", "assumed_rfc9309", "bing")) {
    expect_false(ceiling_cut_readable_v1(gc_cut_ev(524288L), ruleset))
  }
})

test_that("ROBO-ptibdnvy: resolve_policy_v1() needs the cut flag", {
  # Incomplete but not cut (a deadline, or body_too_large), or no flag at all.
  for (flag in list(FALSE, NA, NULL)) {
    ev <- gc_cut_ev(524288L, body_truncated = flag)
    expect_identical(gc_resolve(ev)$policy_reason, "incomplete_evidence")
  }
  ev <- gc_cut_ev(524288L)
  ev$body_truncated <- NULL
  expect_identical(gc_resolve(ev)$policy_reason, "incomplete_evidence")
})

test_that("ROBO-ptibdnvy: the google policy revision", {
  # google-robots-policy-2026-11-09 covers the 512,000-byte window
  # (ROBO-phfbpfiy) and the cut reading (ROBO-ptibdnvy).
  expect_identical(
    engine_policy_revisions_v1()[["google"]], "google-robots-policy-2026-11-09"
  )
})
