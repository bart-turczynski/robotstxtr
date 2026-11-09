# A robots.txt cut at max_bytes under the yandex ruleset (ROBO-arrtietl,
# ADR 0001 slice 8). The evidence of a cut 2xx stays `incomplete` (an L0
# fact); the yandex ruleset reads a cut at or above 512,000 stored bytes as a
# file over Yandex's 500 KB limit, which is its documented allow_all.
# Responses are scripted at the ssrfr boundary (helper-fake-ssrfr.R).

ac_url <- "http://example.test/private"

# A 600,000-byte robots.txt that disallows everything, with a NUL and invalid
# UTF-8 / latin1 bytes early on: a cut body is never decoded on this path.
ac_body <- function(size = 600000L) {
  head <- c(
    charToRaw("User-agent: *\nDisallow: /\n# "),
    as.raw(c(0x00, 0xff, 0xfe, 0xe9, 0xc3)), charToRaw("\n")
  )
  c(head, rep(charToRaw("#"), size - length(head)))
}

ac_serve <- function(status = 200L, body = ac_body(), env = parent.frame()) {
  local_fake_ssrfr(function(req) fake_response(status, body = body), env = env)
}

# Fail any matcher call: an allow_all or incomplete row must not reach one.
# The registry (engine_matcher_registry_v1()) looks these up at call time.
ac_forbid_matchers <- function(env = parent.frame()) {
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

ac_expect_no_matcher <- function(calls) {
  expect_identical(
    c(calls$google, calls$yandex, calls$bing), c(0L, 0L, 0L)
  )
}

ac_eval <- function(ruleset = "yandex", backend = ruleset,
                    max_bytes = 524288L) {
  robots_evaluate_url_v1(
    ac_url, "bot", ruleset, backend, max_bytes = max_bytes
  )
}

# The evidence row of a cut 2xx: incomplete, flagged, `max_bytes` stored.
ac_expect_cut_evidence <- function(x, max_bytes) {
  e <- x$evidence
  expect_identical(e$evidence_status, "incomplete")
  expect_identical(e$termination_reason, "ceiling")
  expect_identical(e$legacy_fetch_outcome, "fetched")
  expect_true(e$body_truncated)
  expect_identical(e$stored_bytes, as.integer(max_bytes))
  expect_identical(x$results$evidence_status, "incomplete")
}

ac_expect_incomplete <- function(x) {
  r <- x$results
  expect_identical(r$policy_status, rep("not_evaluated", nrow(r)))
  expect_identical(r$policy_action, rep(NA_character_, nrow(r)))
  expect_identical(r$policy_reason, rep("incomplete_evidence", nrow(r)))
  expect_identical(r$reason, rep("incomplete_evidence", nrow(r)))
  expect_identical(r$url_decision, rep(NA_character_, nrow(r)))
  expect_identical(r$matcher_status, rep("not_evaluated", nrow(r)))
}

ac_size_source <- "design/engine-profiles.md#policy-matcher-limits"

ac_expect_open <- function(x, reason = "yandex_file_over_500000_bytes",
                           source = ac_size_source) {
  r <- x$results
  expect_identical(r$policy_status, "evaluated")
  expect_identical(r$policy_action, "allow_all")
  expect_identical(r$policy_reason, reason)
  expect_identical(r$policy_provenance, "documented")
  expect_identical(r$policy_source, source)
  expect_identical(r$matcher_status, "not_needed")
  expect_identical(r$url_decision, "allow")
  expect_identical(r$reason, "policy_allow_all")
  expect_identical(r$matcher_input_bytes, NA_integer_)
}

# A hand-built evidence row of a body cut at `stored_bytes`.
ac_cut_ev <- function(stored_bytes, body_truncated = TRUE, status = 200L) {
  ev <- list(
    evidence_status = "incomplete",
    source_kind = "fetched",
    final_http_status = status,
    stored_bytes = stored_bytes
  )
  ev["body_truncated"] <- list(body_truncated)
  ev
}

ac_resolve <- function(ev, ruleset = "yandex") {
  resolve_policy_v1(ev, ruleset, engine_policy_table_v1())
}

# --- The facade ---------------------------------------------------------------

test_that("ROBO-arrtietl: a yandex 200 cut at the default 512 KiB", {
  ac_serve()
  calls <- ac_forbid_matchers()
  x <- ac_eval()
  ac_expect_cut_evidence(x, 524288L)
  ac_expect_open(x)
  ac_expect_no_matcher(calls)
})

test_that("ROBO-arrtietl: a yandex 200 cut at exactly 512,000 bytes", {
  ac_serve()
  calls <- ac_forbid_matchers()
  x <- ac_eval(max_bytes = 512000L)
  ac_expect_cut_evidence(x, 512000L)
  ac_expect_open(x)
  ac_expect_no_matcher(calls)
})

test_that("ROBO-arrtietl: a yandex 200 cut at 511,999 bytes stays incomplete", {
  ac_serve()
  x <- ac_eval(max_bytes = 511999L)
  ac_expect_cut_evidence(x, 511999L)
  ac_expect_incomplete(x)
})

test_that("ROBO-arrtietl: a yandex 203 cut at the default 512 KiB", {
  # A non-200 2xx is allow_all from the table, as when uncut.
  ac_serve(status = 203L)
  x <- ac_eval()
  ac_expect_cut_evidence(x, 524288L)
  table <- engine_policy_table_v1()
  row <- table[
    table$category == "status_other_2xx" & table$ruleset == "yandex", ,
    drop = FALSE
  ]
  ac_expect_open(x, "non_200_allow_all", row$policy_source[[1L]])
})

test_that("ROBO-arrtietl: a yandex 203 cut under 512,000 stays incomplete", {
  ac_serve(status = 203L)
  x <- ac_eval(max_bytes = 511999L)
  ac_expect_cut_evidence(x, 511999L)
  ac_expect_incomplete(x)
})

test_that("ROBO-arrtietl: other rulesets keep a cut body incomplete", {
  ac_serve()
  calls <- ac_forbid_matchers()
  # google: ROBO-ptibdnvy gives it its own reading of the cut.
  x <- robots_evaluate_url_v1(
    rep(ac_url, 4L), "bot",
    c("google", "rfc9309", "assumed_rfc9309", "bing"),
    c("google", "rfc9309", "bing", "bing")
  )
  expect_identical(x$evidence$evidence_status, "incomplete")
  expect_true(x$evidence$body_truncated)
  ac_expect_incomplete(x)
  ac_expect_no_matcher(calls)
})

test_that("ROBO-arrtietl: a 3xx over max_bytes stays incomplete", {
  local_fake_ssrfr(function(req) {
    fake_response(
      302L, headers = list(Location = "http://example.test/moved"),
      body = ac_body()
    )
  })
  x <- ac_eval()
  e <- x$evidence
  expect_identical(e$legacy_fetch_outcome, "body_too_large")
  expect_identical(e$evidence_status, "incomplete")
  expect_false(e$body_truncated)
  expect_identical(e$stored_bytes, 0L)
  ac_expect_incomplete(x)
})

test_that("ROBO-arrtietl: a 2xx ssrfr refused whole stays incomplete", {
  # ssrfr fails a 2xx whose status libcurl and the status line disagree on.
  local_fake_ssrfr(function(req) {
    fake_failure(
      "response-too-large",
      check = "decoded-bytes", limit = "max_response_size",
      status = 200L, observed_bytes = 600000L
    )
  })
  x <- ac_eval()
  e <- x$evidence
  expect_identical(e$legacy_fetch_outcome, "body_too_large")
  expect_identical(e$evidence_status, "incomplete")
  expect_false(e$body_truncated)
  ac_expect_incomplete(x)
})

test_that("ROBO-arrtietl: an uncut yandex file over 500,000 bytes", {
  ac_serve(body = ac_body(500001L))
  x <- ac_eval()
  expect_identical(x$evidence$evidence_status, "usable_body")
  expect_false(x$evidence$body_truncated)
  ac_expect_open(x)
})

test_that("ROBO-arrtietl: the yandex policy revision", {
  ac_serve(body = ac_body(1000L))
  x <- ac_eval()
  expect_identical(
    x$results$policy_ruleset_revision, "yandex-robots-policy-2026-11-09"
  )
  expect_identical(
    engine_policy_revisions_v1()[["yandex"]], "yandex-robots-policy-2026-11-09"
  )
})

# --- resolve_policy_v1() ------------------------------------------------------

test_that("ROBO-arrtietl: resolve_policy_v1() on cut evidence", {
  expect_identical(
    ac_resolve(ac_cut_ev(511999L))$policy_reason, "incomplete_evidence"
  )
  for (bytes in c(512000L, 524288L)) {
    policy <- ac_resolve(ac_cut_ev(bytes))
    expect_identical(policy$policy_status, "evaluated")
    expect_identical(policy$policy_action, "allow_all")
    expect_identical(policy$policy_reason, "yandex_file_over_500000_bytes")
    expect_identical(policy$policy_provenance, "documented")
  }
  expect_true(ceiling_cut_readable_v1(ac_cut_ev(512000L), "yandex"))
  expect_false(ceiling_cut_readable_v1(ac_cut_ev(511999L), "yandex"))
})

test_that("ROBO-arrtietl: resolve_policy_v1() needs the cut flag", {
  # Incomplete but not cut (a deadline, or body_too_large), or no flag at all.
  for (flag in list(FALSE, NA, NULL)) {
    ev <- ac_cut_ev(524288L, body_truncated = flag)
    expect_identical(ac_resolve(ev)$policy_reason, "incomplete_evidence")
  }
  ev <- ac_cut_ev(524288L)
  ev$body_truncated <- NULL
  expect_false("body_truncated" %in% names(ev))
  expect_identical(ac_resolve(ev)$policy_reason, "incomplete_evidence")
})

test_that("ROBO-arrtietl: resolve_policy_v1() under other rulesets", {
  for (ruleset in c("google", "rfc9309", "assumed_rfc9309", "bing")) {
    policy <- ac_resolve(ac_cut_ev(524288L), ruleset)
    expect_identical(policy$policy_status, "not_evaluated")
    expect_identical(policy$policy_reason, "incomplete_evidence")
  }
})
