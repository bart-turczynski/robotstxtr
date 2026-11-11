# allowed_by_robots_url()'s default max_bytes against Google's 512,000-byte
# window (ROBO-uwveumyp; design/engine-profiles.md §7). Responses are scripted
# at the ssrfr boundary (helper-fake-ssrfr.R); no network.

# "User-agent: *\n", one comment line up to byte `at`, then `tail` from byte
# `at + 1`, then `#` bytes (a line with no break) up to `size` bytes.
uw_body <- function(tail, at, size = NULL) {
  agent <- charToRaw("User-agent: *\n")
  head <- c(agent, rep(charToRaw("#"), at - length(agent) - 1L),
            charToRaw("\n"))
  body <- c(head, charToRaw(tail))
  if (!is.null(size)) {
    body <- c(body, rep(charToRaw("#"), size - length(body)))
  }
  body
}

uw_serve <- function(body, env = parent.frame()) {
  local_fake_ssrfr(
    function(req) fake_response(200L, url = req$url, body = body),
    env = env
  )
}

uw_url <- function(path) paste0("http://example.com", path)

# A complete rule starting at byte 520,001: past the window, before 524,288.
uw_between <- uw_body("Disallow: /after\n", 520000L)

test_that("ROBO-uwveumyp: the default reads a rule past byte 512,000", {
  expect_gt(length(uw_between), 512000L)
  expect_lt(length(uw_between), 524288L)
  uw_serve(uw_between)
  x <- allowed_by_robots_url(uw_url("/after"), "bot")
  expect_false(x$results$allowed)
  expect_identical(x$results$matched_line, 3L)
  expect_false(x$robots$body_truncated)
  expect_identical(x$robots$max_bytes, 524288L)
})
