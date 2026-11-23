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
  "retry_after_seconds", "content_type", "content_flag", "content_encoding",
  "cache_control", "age", "date", "expires", "etag", "last_modified", "vary",
  "body_truncated",
  "terminal_redirect_reason", "safety_block_reason", "redirect_hops", "body"
)

ch_cache_columns <- c(
  "cache_control", "age", "date", "expires", "etag", "last_modified", "vary"
)

# Fetch http://a/robots.txt answered by `res`; the source row.
ch_fetch_one <- function(res, ..., env = parent.frame()) {
  local_fake_ssrfr(ch_router(list("http://a/robots.txt" = res)), env = env)
  robots_fetch("http://a/", ...)$robots
}

# The cache columns of `robots` as a named list of character vectors.
ch_cache <- function(robots) {
  as.list(robots[ch_cache_columns])
}

ch_na <- function(n = 1L) {
  stats::setNames(
    rep(list(rep(NA_character_, n)), length(ch_cache_columns)),
    ch_cache_columns
  )
}

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

test_that("ROBO-zleohwyz: the cache columns are typed character", {
  local_fake_ssrfr(ch_router(list(
    "http://a/robots.txt" = fake_response(200L, headers = ch_all_headers)
  )))
  fetched <- robots_fetch("http://a/")$robots
  empty <- robots_fetch(character())$robots
  text <- allowed_by_robots_text("user-agent: *\n", "http://a/", "bot")$robots
  for (col in ch_cache_columns) {
    expect_type(fetched[[col]], "character")
    expect_type(empty[[col]], "character")
    expect_type(text[[col]], "character")
  }
  expect_identical(nrow(empty), 0L)
})

# --- the final response's values, raw ----------------------------------------

test_that("ROBO-zleohwyz: each field is kept as received", {
  row <- ch_fetch_one(fake_response(
    200L, headers = ch_all_headers, body = "user-agent: *\n"
  ))
  expect_identical(row$fetch_outcome, "fetched")
  expect_identical(ch_cache(row), stats::setNames(
    unname(ch_all_headers), ch_cache_columns
  ))
})

test_that("ROBO-zleohwyz: any status keeps its cache fields", {
  for (status in c(404L, 503L)) {
    row <- ch_fetch_one(fake_response(status, headers = ch_all_headers))
    expect_identical(row$http_status, status)
    expect_identical(row$etag, "\"v1-abc\"")
    expect_identical(row$cache_control, "max-age=3600, public")
  }
})

test_that("ROBO-zleohwyz: Date is stored raw and still bases Retry-After", {
  row <- ch_fetch_one(fake_response(503L, headers = list(
    "Retry-After" = "Fri, 06 Nov 2026 08:49:37 GMT",
    "Date" = "Fri, 06 Nov 2026 08:47:37 GMT"
  )))
  expect_identical(row$date, "Fri, 06 Nov 2026 08:47:37 GMT")
  expect_identical(row$retry_after_seconds, 120)
})

test_that("ROBO-zleohwyz: an absent field is NA", {
  row <- ch_fetch_one(fake_response(200L, body = "user-agent: *\n"))
  expect_identical(ch_cache(row), ch_na())
})

test_that("ROBO-zleohwyz: an empty field is the empty string, not NA", {
  headers <- stats::setNames(
    as.list(rep("", length(ch_all_headers))), names(ch_all_headers)
  )
  row <- ch_fetch_one(fake_response(200L, headers = headers))
  expect_identical(ch_cache(row), stats::setNames(
    as.list(rep("", length(ch_cache_columns))), ch_cache_columns
  ))
})

test_that("ROBO-zleohwyz: repeated fields are joined with a comma", {
  headers <- c(
    stats::setNames(list("max-age=60", "public"), rep("Cache-Control", 2L)),
    stats::setNames(list("Accept-Encoding", "User-Agent"), rep("Vary", 2L))
  )
  row <- ch_fetch_one(fake_response(200L, headers = headers))
  expect_identical(row$cache_control, "max-age=60, public")
  expect_identical(row$vary, "Accept-Encoding, User-Agent")
  expect_identical(row$etag, NA_character_)
})

test_that("ROBO-zleohwyz: malformed values are kept verbatim", {
  headers <- list(
    "Cache-Control" = "max-age=abc", "Age" = "-1", "Expires" = "0",
    "Date" = "yesterday", "Last-Modified" = "not a date", "ETag" = "abc"
  )
  row <- ch_fetch_one(fake_response(200L, headers = headers))
  expect_identical(row$cache_control, "max-age=abc")
  expect_identical(row$age, "-1")
  expect_identical(row$expires, "0")
  expect_identical(row$date, "yesterday")
  expect_identical(row$last_modified, "not a date")
  expect_identical(row$etag, "abc")
  expect_named(row, ch_robots_columns)
})

# --- the final response only --------------------------------------------------

test_that("ROBO-zleohwyz: a redirect hop's cache fields never reach the row", {
  local_fake_ssrfr(ch_router(list(
    "http://a/robots.txt" = fake_response(301L, headers = list(
      "Location" = "http://b/robots.txt", "Cache-Control" = "max-age=5",
      "ETag" = "\"hop\"", "Date" = "Thu, 05 Nov 2026 11:00:00 GMT"
    )),
    "http://b/robots.txt" = fake_response(200L, body = "user-agent: *\n"),
    "http://c/robots.txt" = fake_response(302L, headers = list(
      "Location" = "http://d/robots.txt", "ETag" = "\"hop\""
    )),
    "http://d/robots.txt" = fake_response(
      200L, headers = list("ETag" = "\"final\"")
    )
  )))
  x <- robots_fetch(c("http://a/", "http://c/"))
  expect_identical(x$robots$redirect_count, c(1L, 1L))
  expect_identical(ch_cache(x$robots[1L, ]), ch_na())
  expect_identical(x$robots$etag, c(NA, "\"final\""))
  expect_identical(x$robots$cache_control, c(NA_character_, NA_character_))
})

test_that("ROBO-zleohwyz: no final response, no cache fields", {
  hop <- function(to) {
    fake_response(301L, headers = c(list("Location" = to), ch_all_headers))
  }
  routes <- list(
    "http://a/robots.txt" = fake_failure("timeout"),
    "http://b/robots.txt" = fake_response(302L, headers = ch_all_headers)
  )
  # A sixth redirect is over the budget.
  chain <- sprintf("http://c/%d", 0:6)
  chain[[1L]] <- "http://c/robots.txt"
  for (i in 1:6) {
    routes[[chain[[i]]]] <- hop(chain[[i + 1L]])
  }
  local_fake_ssrfr(ch_router(routes))
  x <- robots_fetch(c(
    "http://a/", "http://b/", "http://c/", "http://127.0.0.1/"
  ))
  expect_identical(
    x$robots$terminal_redirect_reason,
    c("none", "no_location", "over_budget", "none")
  )
  expect_identical(
    x$robots$fetch_outcome[c(1L, 4L)], c("timeout", "ssrf_blocked")
  )
  expect_identical(ch_cache(x$robots), ch_na(4L))
})

test_that("ROBO-zleohwyz: a 5xx over max_bytes keeps its status, no header", {
  # ssrfr's decoded-bytes failure carries no headers: NA is "not available".
  row <- ch_fetch_one(
    fake_response(503L, headers = ch_all_headers, body = strrep("x", 64L)),
    max_bytes = 8L
  )
  expect_identical(row$http_status, 503L)
  expect_identical(ch_cache(row), ch_na())
})

# --- one schema across entry points ------------------------------------------

test_that("ROBO-zleohwyz: allowed_by_robots_url() carries the fetch row", {
  local_fake_ssrfr(ch_router(list(
    "http://a/robots.txt" = fake_response(200L, headers = ch_all_headers)
  )))
  # allowed_by_robots_url() reads 512,000 bytes by default (ROBO-uwveumyp).
  fetched <- robots_fetch("http://a/", max_bytes = 512000L)
  decided <- allowed_by_robots_url("http://a/", "bot")
  expect_identical(decided$robots, fetched$robots)
  expect_identical(decided$robots$vary, "Accept-Encoding")
})

test_that("ROBO-zleohwyz: text and legacy frames write NA cache columns", {
  text <- allowed_by_robots_text("user-agent: *\n", "http://a/", "bot")
  expect_identical(ch_cache(text$robots), ch_na())

  engine <- robots_evaluate_text_v1(
    "user-agent: *\n", "http://a/", "bot", "google", "google"
  )
  legacy <- as_legacy_robots_decisions_v1(engine)
  expect_identical(ch_cache(legacy$robots), ch_na())

  local_fake_ssrfr(ch_router(list(
    "http://a/robots.txt" = fake_response(200L, headers = ch_all_headers)
  )))
  url <- allowed_by_robots_url("http://a/", "bot")
  expect_identical(
    vapply(text$robots, typeof, character(1L)),
    vapply(url$robots, typeof, character(1L))
  )
  expect_identical(
    vapply(legacy$robots, typeof, character(1L)),
    vapply(url$robots, typeof, character(1L))
  )
  both <- rbind(text$robots, url$robots)
  expect_identical(both$etag, c(NA, "\"v1-abc\""))
})
