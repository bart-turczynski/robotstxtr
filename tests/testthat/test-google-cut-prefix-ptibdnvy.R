# A robots.txt cut at max_bytes under the google ruleset (ROBO-ptibdnvy,
# ADR 0001 slice 9). Pins of the behavior before the google reading lands:
# a cut 2xx is `incomplete` evidence and every ruleset but yandex leaves it
# unmatched. Responses are scripted at the ssrfr boundary
# (helper-fake-ssrfr.R).

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

gc_resolve <- function(ev, ruleset = "google") {
  resolve_policy_v1(ev, ruleset, engine_policy_table_v1())
}

test_that("ROBO-ptibdnvy: a google 200 cut at 512 KiB is incomplete today", {
  gc_serve()
  calls <- gc_forbid_matchers()
  x <- gc_eval()
  gc_expect_cut_evidence(x, 524288L)
  gc_expect_incomplete(x)
  gc_expect_no_matcher(calls)
})

test_that("ROBO-ptibdnvy: a google 200 cut at 512,000 is incomplete today", {
  gc_serve()
  calls <- gc_forbid_matchers()
  x <- gc_eval(max_bytes = 512000L)
  gc_expect_cut_evidence(x, 512000L)
  gc_expect_incomplete(x)
  gc_expect_no_matcher(calls)
})

test_that("ROBO-ptibdnvy: a google 203 cut is incomplete today", {
  gc_serve(status = 203L)
  calls <- gc_forbid_matchers()
  x <- gc_eval()
  gc_expect_cut_evidence(x, 524288L)
  gc_expect_incomplete(x)
  gc_expect_no_matcher(calls)
})

test_that("ROBO-ptibdnvy: a google cut at 511,999 bytes stays incomplete", {
  gc_serve()
  calls <- gc_forbid_matchers()
  x <- gc_eval(max_bytes = 511999L)
  gc_expect_cut_evidence(x, 511999L)
  gc_expect_incomplete(x)
  gc_expect_no_matcher(calls)
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

test_that("ROBO-ptibdnvy: resolve_policy_v1() needs the cut flag", {
  for (flag in list(FALSE, NA, NULL)) {
    ev <- gc_cut_ev(524288L, body_truncated = flag)
    expect_identical(gc_resolve(ev)$policy_reason, "incomplete_evidence")
  }
  ev <- gc_cut_ev(524288L)
  ev$body_truncated <- NULL
  expect_identical(gc_resolve(ev)$policy_reason, "incomplete_evidence")
})

test_that("ROBO-ptibdnvy: the google policy revision", {
  expect_identical(
    engine_policy_revisions_v1()[["google"]], "google-robots-policy-2026-11-09"
  )
})
