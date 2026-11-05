# Retry-After on robots.txt fetch rows (ROBO-cthdyvlk). A 429 or 503 for
# robots.txt may say when to come back (RFC 9110 section 10.2.3; RFC 9309
# sections 2.3.1.3 and 2.3.1.4). Responses are scripted at the ssrfr boundary
# (helper-fake-ssrfr.R).

# A handler serving `routes`, a list of fake_response() keyed by request URL.
ra_router <- function(routes) {
  function(req) {
    res <- routes[[req$url]]
    if (is.null(res)) {
      return(fake_response(404L, req$url))
    }
    res
  }
}

ra_robots_columns <- c(
  "source_id", "source_type", "robots_url", "effective_url", "http_status",
  "fetch_outcome", "redirect_count", "body_size", "timeout", "max_bytes",
  "error_stage", "error_class", "error_message", "body"
)

test_that("ROBO-cthdyvlk pin: the robots_fetch() source columns", {
  local_fake_ssrfr(ra_router(list(
    "http://a/robots.txt" = fake_response(503L)
  )))
  x <- robots_fetch("http://a/")
  expect_named(x$robots, ra_robots_columns)
})

test_that("ROBO-cthdyvlk pin: allowed_by_robots_url() carries the fetch row", {
  local_fake_ssrfr(ra_router(list(
    "http://a/robots.txt" = fake_response(503L)
  )))
  fetched <- robots_fetch("http://a/")
  decided <- allowed_by_robots_url("http://a/", "bot")
  expect_identical(decided$robots, fetched$robots)
})
