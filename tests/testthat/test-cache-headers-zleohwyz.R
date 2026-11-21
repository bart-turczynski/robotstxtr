# Cache headers on robots.txt fetch rows (ROBO-zleohwyz). The final
# response's Cache-Control, Age, Date, Expires, ETag, Last-Modified and Vary
# field values, raw and unparsed, so a caller can explain a stale copy.
# Responses are scripted at the ssrfr boundary (helper-fake-ssrfr.R); no
# network.

# A handler serving `routes`, a list of fake_response() keyed by request URL.
ch_router <- function(routes, recorder = NULL) {
  function(req) {
    if (!is.null(recorder)) {
      recorder$reqs <- c(recorder$reqs, list(req))
    }
    res <- routes[[req$url]]
    if (is.null(res)) {
      return(fake_response(404L, req$url))
    }
    res
  }
}

ch_robots_columns <- c(
  "source_id", "source_type", "robots_url", "effective_url", "http_status",
  "fetch_outcome", "redirect_count", "body_size", "timeout", "max_bytes",
  "error_stage", "error_class", "error_message", "retry_after",
  "retry_after_seconds", "content_type", "content_flag", "body_truncated",
  "terminal_redirect_reason", "safety_block_reason", "redirect_hops", "body"
)

# The v1 evidence frame does not move: the cache headers are legacy columns.
ch_evidence_columns <- c(
  "source_id", "source_kind", "requested_url", "effective_url",
  "redirect_count", "terminal_redirect_reason", "final_http_status",
  "location_header", "body_present", "observed_bytes", "stored_bytes",
  "body_truncated", "transport_error_kind", "safety_block_reason",
  "termination_reason", "evidence_status", "http_user_agent",
  "acquisition_timeout_seconds", "acquisition_max_bytes", "redirect_limit",
  "ssrf_guard", "safety_level", "https_downgrade_guard",
  "legacy_fetch_outcome", "legacy_http_status", "error_stage", "error_class",
  "error_message", "fetch_allow_ranges", "redirect_hops", "body"
)

ch_all_headers <- list(
  "Cache-Control" = "max-age=3600, public",
  "Age" = "120",
  "Date" = "Thu, 05 Nov 2026 12:00:00 GMT",
  "Expires" = "Thu, 05 Nov 2026 13:00:00 GMT",
  "ETag" = "\"v1-abc\"",
  "Last-Modified" = "Wed, 04 Nov 2026 08:00:00 GMT",
  "Vary" = "Accept-Encoding"
)

# --- the schema of every robots frame ---------------------------------------

test_that("ROBO-zleohwyz: the robots frames' columns", {
  local_fake_ssrfr(ch_router(list(
    "http://a/robots.txt" = fake_response(200L, headers = ch_all_headers)
  )))
  expect_named(robots_fetch("http://a/")$robots, ch_robots_columns)
  expect_named(robots_fetch(character())$robots, ch_robots_columns)

  text <- allowed_by_robots_text("user-agent: *\n", "http://a/", "bot")
  expect_named(text$robots, ch_robots_columns)

  engine <- robots_evaluate_text_v1(
    "user-agent: *\n", "http://a/", "bot", "google", "google"
  )
  expect_named(as_legacy_robots_decisions_v1(engine)$robots, ch_robots_columns)
})

test_that("ROBO-zleohwyz: the v1 evidence keeps its columns", {
  local_fake_ssrfr(ch_router(list(
    "http://a/robots.txt" = fake_response(200L, headers = ch_all_headers)
  )))
  engine <- robots_evaluate_url_v1("http://a/", "bot", "google", "google")
  expect_named(engine$evidence, ch_evidence_columns)
})

# --- the request does not change --------------------------------------------

test_that("ROBO-zleohwyz: one plain request per origin", {
  # The fake hard-codes an empty `req$headers`, so this cannot see a
  # conditional request (If-None-Match, If-Modified-Since). That rests on
  # acquire_robots() preparing every chain with `request = list()`, which
  # helper-security.R re-checks by grep. This pins the request count.
  rec <- new.env(parent = emptyenv())
  rec$reqs <- list()
  local_fake_ssrfr(ch_router(list(
    "http://a/robots.txt" = fake_response(200L, headers = ch_all_headers)
  ), recorder = rec))
  robots_fetch(c("http://a/x", "http://a/y"))
  robots_fetch("http://a/")
  expect_length(rec$reqs, 2L)
  for (req in rec$reqs) {
    expect_identical(req$method, "GET")
    expect_length(req$headers, 0L)
  }
})
