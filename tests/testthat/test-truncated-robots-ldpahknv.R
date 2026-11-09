# A robots.txt over max_bytes (ROBO-ldpahknv). Responses are scripted at the
# ssrfr boundary (helper-fake-ssrfr.R) or served over the wire by a loopback
# webfakes server through the real ssrfr (local_loopback_policy()).

# A robots.txt with a Disallow before `max_bytes = 1000` and one after it.
tr_limit <- 1000L
tr_body <- function(pad_lines = 30L) {
  charToRaw(paste0(
    "User-agent: *\nDisallow: /before\n",
    strrep(paste0("# ", strrep("x", 60L), "\n"), pad_lines),
    "Disallow: /after\n"
  ))
}
tr_urls <- function(base) paste0(base, c("before", "after", "other"))

# Serve `body` with `status` and `headers` at every path; the robots URL.
tr_server <- function(body, status = 200L, headers = list(),
                      env = parent.frame()) {
  skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$locals$body <- body
  app$locals$status <- status
  app$locals$headers <- headers
  app$get(webfakes::new_regexp("^/"), function(req, res) {
    for (name in names(req$app$locals$headers)) {
      res$set_header(name, req$app$locals$headers[[name]])
    }
    res$set_status(req$app$locals$status)
    res$set_type("text/plain")
    res$send(req$app$locals$body)
  })
  server <- webfakes::local_app_process(app, .local_envir = env)
  url <- server$url("/robots.txt")
  port <- as.integer(sub("^http://127\\.0\\.0\\.1:([0-9]+)/.*$", "\\1", url))
  local_loopback_policy(port, env = env)
  url
}

test_that("ROBO-ldpahknv: the body is over the limit, its first rule under", {
  body <- tr_body()
  expect_gt(length(body), tr_limit)
  text <- rawToChar(body)
  expect_lt(regexpr("/before", text, fixed = TRUE), tr_limit)
  expect_gt(regexpr("/after", text, fixed = TRUE), tr_limit)
})

# --- A 2xx over max_bytes -----------------------------------------------------

# The rows of a robots.txt cut at `limit`: fetched, its first `limit` bytes
# stored, no error; the Disallow before the cut applies, the one after not.
tr_expect_cut <- function(x, full = tr_body(), limit = tr_limit) {
  expect_identical(x$robots$fetch_outcome, "fetched")
  expect_identical(x$robots$http_status, 200L)
  expect_identical(x$robots$body[[1L]], full[seq_len(limit)])
  expect_identical(x$robots$body_size, limit)
  expect_true(is.na(x$robots$error_class))
  expect_identical(x$robots$content_flag, NA_character_)
  expect_identical(x$results$allowed, c(FALSE, TRUE, TRUE))
  expect_identical(
    x$results$decision_source, c("rule_disallow", "default_allow",
                                 "default_allow")
  )
}

test_that("ROBO-ldpahknv: an oversized 200 keeps its prefix (fake ssrfr)", {
  local_fake_ssrfr(function(req) fake_response(200L, body = tr_body()))
  x <- allowed_by_robots_url(tr_urls("http://a/"), "bot", max_bytes = tr_limit)
  tr_expect_cut(x)
  src <- acquire_robots("http://a/robots.txt", 5, "bot", tr_limit)
  expect_true(src$body_truncated)
  expect_identical(src$fetch_outcome, "fetched")
  expect_identical(src$termination_reason, "ceiling")
  expect_identical(src$observed_bytes, length(tr_body()))
  expect_identical(src$stored_bytes, tr_limit)
})

test_that("ROBO-ldpahknv: an oversized 200 over the wire, identity", {
  url <- tr_server(tr_body())
  x <- allowed_by_robots_url(
    tr_urls(sub("robots\\.txt$", "", url)), "bot",
    max_bytes = tr_limit, timeout = 5
  )
  tr_expect_cut(x)
  src <- acquire_robots(url, 5, "bot", tr_limit)
  expect_true(src$body_truncated)
  expect_gt(src$observed_bytes, tr_limit)
})

test_that("ROBO-ldpahknv: an oversized 200 over the wire, gzip", {
  gz <- memCompress(tr_body(), type = "gzip")
  expect_lt(length(gz), tr_limit)
  url <- tr_server(gz, headers = list("Content-Encoding" = "gzip"))
  x <- allowed_by_robots_url(
    tr_urls(sub("robots\\.txt$", "", url)), "bot",
    max_bytes = tr_limit, timeout = 5
  )
  tr_expect_cut(x)
  src <- acquire_robots(url, 5, "bot", tr_limit)
  expect_true(src$body_truncated)
  expect_gt(src$observed_bytes, tr_limit)
})

test_that("ROBO-ldpahknv: over the default 512 KiB limit, over the wire", {
  body <- tr_body(pad_lines = 9000L)
  expect_gt(length(body), 524288L)
  url <- tr_server(body)
  x <- allowed_by_robots_url(
    tr_urls(sub("robots\\.txt$", "", url)), "bot", timeout = 10
  )
  tr_expect_cut(x, full = body, limit = 524288L)
})

# --- Unchanged ----------------------------------------------------------------

test_that("ROBO-ldpahknv: a whole file is not truncated", {
  local_fake_ssrfr(function(req) fake_response(200L, body = tr_body()))
  x <- allowed_by_robots_url(tr_urls("http://a/"), "bot")
  expect_identical(x$robots$fetch_outcome, "fetched")
  expect_identical(x$robots$body[[1L]], tr_body())
  expect_identical(x$results$allowed, c(FALSE, FALSE, TRUE))
  src <- acquire_robots("http://a/robots.txt", 5, "bot", 524288L)
  expect_false(src$body_truncated)
  expect_identical(src$observed_bytes, length(tr_body()))
  e <- robots_evaluate_url_v1(
    "http://a/after", "Googlebot", "google", "google"
  )$evidence
  expect_false(e$body_truncated)
  expect_identical(e$evidence_status, "usable_body")
  expect_identical(e$termination_reason, "none")
})

test_that("ROBO-ldpahknv: an oversized 404 or 503 keeps its status outcome", {
  local_fake_ssrfr(function(req) {
    status <- if (startsWith(req$url, "http://a/")) 404L else 503L
    fake_response(status, body = tr_body())
  })
  x <- robots_fetch(c("http://a/", "http://b/"), max_bytes = tr_limit)
  expect_identical(x$robots$fetch_outcome, c("missing", "http_error"))
  expect_identical(x$robots$http_status, c(404L, 503L))
  expect_identical(x$robots$body, list(NULL, NULL))
})

test_that("ROBO-ldpahknv: an oversized 404 or 503 over the wire", {
  url404 <- tr_server(tr_body(), status = 404L)
  x <- robots_fetch(url404, max_bytes = tr_limit, timeout = 5)
  expect_identical(x$robots$fetch_outcome, "missing")
  expect_null(x$robots$body[[1L]])
  url503 <- tr_server(tr_body(), status = 503L)
  y <- robots_fetch(url503, max_bytes = tr_limit, timeout = 5)
  expect_identical(y$robots$fetch_outcome, "http_error")
  expect_identical(y$robots$http_status, 503L)
  expect_null(y$robots$body[[1L]])
})

test_that("ROBO-ldpahknv: the v1 evidence of an oversized 200 is incomplete", {
  # The prefix is kept and flagged, but the v1 evidence status of a body over
  # the ceiling stays `incomplete`: no v1 decision is made from this prefix,
  # which is under the 512,000 bytes google needs to read a cut
  # (ROBO-ptibdnvy).
  local_fake_ssrfr(function(req) fake_response(200L, body = tr_body()))
  x <- robots_evaluate_url_v1(
    "http://a/before", "Googlebot", "google", "google", max_bytes = tr_limit
  )
  e <- x$evidence
  expect_identical(e$evidence_status, "incomplete")
  expect_identical(e$termination_reason, "ceiling")
  expect_identical(e$observed_bytes, length(tr_body()))
  expect_identical(x$results$url_decision, NA_character_)
  expect_identical(e$legacy_fetch_outcome, "fetched")
  expect_true(e$body_truncated)
  expect_true(e$body_present)
  expect_identical(e$stored_bytes, tr_limit)
  expect_identical(e$body[[1L]], tr_body()[seq_len(tr_limit)])
})

# --- The content flag on a cut body -------------------------------------------

test_that("ROBO-ldpahknv: a character cut at the body's end is not binary", {
  # A cut can split a multibyte character; at most three of its bytes are
  # left, under the eight invalid bytes "binary" needs.
  cut <- c(charToRaw("User-agent: *\nDisallow: /caf"), as.raw(c(0xe2, 0x82)))
  expect_identical(robots_content_flag(cut), NA_character_)
  short <- c(charToRaw("# "), as.raw(c(0xf0, 0x9f, 0x98)))
  expect_identical(robots_content_flag(short), NA_character_)
})

test_that("ROBO-ldpahknv: a fetch cut inside a character is not binary", {
  # "# " then 3-byte characters: a 4-byte limit keeps two bytes of the first,
  # half the body, but under the eight invalid bytes "binary" needs.
  body <- paste0("# ", strrep("\u20ac", 10L), "\n")
  local_fake_ssrfr(function(req) fake_response(200L, body = body))
  row <- robots_fetch("http://a/", max_bytes = 4L)$robots
  expect_identical(row$fetch_outcome, "fetched")
  expect_identical(row$body[[1L]], charToRaw(body)[1:4])
  expect_identical(row$body[[1L]][3:4], as.raw(c(0xe2, 0x82)))
  expect_identical(row$content_flag, NA_character_)
})

# --- body_truncated on every robots frame -------------------------------------

test_that("ROBO-ldpahknv: every robots frame reports the cut", {
  local_fake_ssrfr(function(req) {
    if (startsWith(req$url, "http://a/")) {
      fake_response(200L, body = tr_body())
    } else {
      fake_response(200L, body = "User-agent: *\n")
    }
  })
  fetched <- robots_fetch(c("http://a/", "http://b/"), max_bytes = tr_limit)
  expect_identical(fetched$robots$body_truncated, c(TRUE, FALSE))
  url <- allowed_by_robots_url(
    c("http://a/x", "http://b/x"), "bot", max_bytes = tr_limit
  )
  expect_identical(url$robots$body_truncated, c(TRUE, FALSE))
  expect_identical(robots_fetch(character())$robots$body_truncated, logical())

  # A supplied text is whole.
  text <- allowed_by_robots_text(rawToChar(tr_body()), "http://a/x", "bot")
  expect_false(text$robots$body_truncated)
  both <- rbind(text$robots, url$robots)
  expect_identical(both$body_truncated, c(FALSE, TRUE, FALSE))

  # The legacy adapter carries the v1 evidence's flag.
  engine <- robots_evaluate_url_v1(
    c("http://a/x", "http://b/x"), "Googlebot", "google", "google",
    max_bytes = tr_limit
  )
  legacy <- as_legacy_robots_decisions_v1(engine)
  expect_identical(legacy$robots$body_truncated, c(TRUE, FALSE))
  supplied <- as_legacy_robots_decisions_v1(robots_evaluate_text_v1(
    "User-agent: *\n", "http://a/", "bot", "google", "google"
  ))
  expect_false(supplied$robots$body_truncated)
})

test_that("ROBO-ldpahknv: robots_validate_url() validates and reports a cut", {
  local_fake_ssrfr(function(req) fake_response(200L, body = tr_body()))
  x <- robots_validate_url("http://a/", max_bytes = tr_limit)
  doc <- x$documents
  expect_identical(doc$fetch_outcome, "fetched")
  expect_identical(doc$byte_size, tr_limit)
  expect_identical(doc$disallow_directives, 1L)
  expect_true(doc$body_truncated)
  expect_true(doc$limit_exceeded)
  expect_false("acquisition_limit_exceeded" %in% x$diagnostics$code)
})

test_that("ROBO-ldpahknv: a 3xx over max_bytes is still refused whole", {
  local_fake_ssrfr(function(req) {
    fake_response(
      302L, headers = list(Location = "http://a/moved"), body = tr_body()
    )
  })
  x <- robots_validate_url("http://a/", max_bytes = tr_limit)
  expect_identical(x$documents$fetch_outcome, "body_too_large")
  expect_identical(x$documents$validation_status, "not_validated")
  expect_identical(x$diagnostics$code, "acquisition_limit_exceeded")
  expect_true(x$documents$limit_exceeded)
  expect_false(x$documents$body_truncated)
  row <- robots_fetch("http://a/", max_bytes = tr_limit)$robots
  expect_false(row$body_truncated)
})

# --- The partial last line of a cut body --------------------------------------

# "User-agent: *\n" is 14 bytes and "Disallow: /" 11, so a 25-byte cut turns
# "Disallow: /private-drafts/" into "Disallow: /".
tr_crossing <- "User-agent: *\nDisallow: /private-drafts/\n"
# "Disallow: /caf" is 14 bytes; a 29-byte cut keeps the first byte of the
# two-byte "é".
tr_split_char <- "User-agent: *\nDisallow: /café\n"

test_that("ROBO-ldpahknv: a Disallow line crossing the cut", {
  local_fake_ssrfr(function(req) fake_response(200L, body = tr_crossing))
  x <- allowed_by_robots_url(
    c("http://a/public", "http://a/private-drafts/x"), "bot", max_bytes = 25L
  )
  # The stored body keeps every byte; matching stops at the last line break,
  # so the partial "Disallow: /" is not read as a rule.
  expect_identical(x$robots$body_size, 25L)
  expect_identical(x$robots$body[[1L]], charToRaw(tr_crossing)[1:25])
  expect_true(x$robots$body_truncated)
  expect_identical(x$results$allowed, c(TRUE, TRUE))
  expect_identical(
    x$results$decision_source, c("default_allow", "default_allow")
  )
})

test_that("ROBO-ldpahknv: a line cut short is not validated either", {
  local_fake_ssrfr(function(req) fake_response(200L, body = tr_crossing))
  x <- robots_validate_url("http://a/", max_bytes = 25L)
  expect_identical(x$documents$byte_size, 25L)
  expect_identical(x$documents$line_count, 1L)
  expect_identical(x$documents$disallow_directives, 0L)
})

test_that("ROBO-ldpahknv: validating a body cut inside a character", {
  local_fake_ssrfr(function(req) fake_response(200L, body = tr_split_char))
  x <- robots_validate_url("http://a/", max_bytes = 29L)
  doc <- x$documents
  expect_identical(doc$byte_size, 29L)
  expect_false("invalid_utf8" %in% x$diagnostics$code)
  expect_identical(doc$encoding, "utf-8")
  # The file's end was never read: no final-newline verdict.
  expect_identical(doc$final_newline, NA)
  expect_true(doc$body_truncated)
  expect_true(doc$limit_exceeded)
  expect_identical(x$diagnostics$code, "body_truncated")
  expect_identical(x$diagnostics$severity, "warning")
  expect_identical(doc$validation_status, "warning")
})

test_that("ROBO-ldpahknv: a cut body with no line break has no rules", {
  local_fake_ssrfr(function(req) {
    body <- c(charToRaw("Disallow: /"), rep(charToRaw("x"), 100L))
    fake_response(200L, body = body)
  })
  x <- allowed_by_robots_url("http://a/x", "bot", max_bytes = 20L)
  expect_true(x$robots$body_truncated)
  expect_true(x$results$allowed)
  expect_identical(x$results$decision_source, "default_allow")
  v <- robots_validate_url("http://a/", max_bytes = 20L)
  expect_identical(v$documents$line_count, 0L)
  expect_identical(v$documents$byte_size, 20L)
  # No rule was read, but the cut hides whether any exist (ROBO-vxrzcqpe).
  expect_setequal(v$diagnostics$code, "body_truncated")
})

test_that("ROBO-ldpahknv: complete_lines_prefix() keeps up to the last break", {
  expect_identical(complete_lines_prefix(charToRaw("a\nb")), charToRaw("a\n"))
  expect_identical(
    complete_lines_prefix(charToRaw("a\r\nb\rc")), charToRaw("a\r\nb\r")
  )
  expect_identical(complete_lines_prefix(charToRaw("abc")), raw(0))
  expect_identical(complete_lines_prefix(raw(0)), raw(0))
  expect_identical(readable_body(charToRaw("a\nb"), FALSE), charToRaw("a\nb"))
  # A whole file is matched and validated to its last byte.
  local_fake_ssrfr(function(req) {
    fake_response(200L, body = "User-agent: *\nDisallow: /x")
  })
  x <- allowed_by_robots_url("http://a/x", "bot")
  expect_false(x$results$allowed)
  v <- robots_validate_url("http://a/")
  expect_false(v$documents$final_newline)
  expect_false(v$documents$body_truncated)
  expect_false("body_truncated" %in% v$diagnostics$code)
})
