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

test_that("ROBO-ldpahknv: an oversized 200 is body_too_large (fake ssrfr)", {
  local_fake_ssrfr(function(req) fake_response(200L, body = tr_body()))
  x <- allowed_by_robots_url(tr_urls("http://a/"), "bot", max_bytes = tr_limit)
  expect_identical(x$robots$fetch_outcome, "body_too_large")
  expect_null(x$robots$body[[1L]])
  expect_identical(x$results$allowed, c(NA, NA, NA))
  src <- acquire_robots("http://a/robots.txt", 5, "bot", tr_limit)
  expect_false(src$body_truncated)
  expect_identical(src$observed_bytes, length(tr_body()))
})

test_that("ROBO-ldpahknv: an oversized 200 over the wire, identity", {
  url <- tr_server(tr_body())
  x <- allowed_by_robots_url(
    tr_urls(sub("robots\\.txt$", "", url)), "bot",
    max_bytes = tr_limit, timeout = 5
  )
  expect_identical(x$robots$fetch_outcome, "body_too_large")
  expect_null(x$robots$body[[1L]])
  expect_identical(x$results$allowed, c(NA, NA, NA))
})

test_that("ROBO-ldpahknv: an oversized 200 over the wire, gzip", {
  gz <- memCompress(tr_body(), type = "gzip")
  expect_lt(length(gz), tr_limit)
  url <- tr_server(gz, headers = list("Content-Encoding" = "gzip"))
  x <- allowed_by_robots_url(
    tr_urls(sub("robots\\.txt$", "", url)), "bot",
    max_bytes = tr_limit, timeout = 5
  )
  expect_identical(x$robots$fetch_outcome, "body_too_large")
  expect_null(x$robots$body[[1L]])
  expect_identical(x$results$allowed, c(NA, NA, NA))
})

test_that("ROBO-ldpahknv: over the default 512 KiB limit, over the wire", {
  body <- tr_body(pad_lines = 9000L)
  expect_gt(length(body), 524288L)
  url <- tr_server(body)
  x <- allowed_by_robots_url(
    tr_urls(sub("robots\\.txt$", "", url)), "bot", timeout = 10
  )
  expect_identical(x$robots$fetch_outcome, "body_too_large")
  expect_identical(x$results$allowed, c(NA, NA, NA))
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
  local_fake_ssrfr(function(req) fake_response(200L, body = tr_body()))
  x <- robots_evaluate_url_v1(
    "http://a/before", "Googlebot", "google", "google", max_bytes = tr_limit
  )
  e <- x$evidence
  expect_identical(e$evidence_status, "incomplete")
  expect_identical(e$termination_reason, "ceiling")
  expect_identical(e$observed_bytes, length(tr_body()))
  expect_identical(x$results$url_decision, NA_character_)
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
