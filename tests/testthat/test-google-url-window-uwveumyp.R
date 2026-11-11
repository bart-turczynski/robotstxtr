# allowed_by_robots_url()'s default max_bytes against Google's 512,000-byte
# window (ROBO-uwveumyp; design/engine-profiles.md §7). The default is
# 512,000 bytes, read up to the last complete line. Responses are scripted
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

# The rows of a URL path cut at 512,000 bytes that read no rule.
uw_expect_unread <- function(x, label = NULL) {
  n <- nrow(x$results)
  expect_identical(x$results$allowed, rep(TRUE, n), label = label)
  expect_identical(x$results$decision_source, rep("default_allow", n),
                   label = label)
  expect_identical(x$results$matched_line, rep(NA_integer_, n),
                   label = label)
  expect_true(x$robots$body_truncated, label = label)
  expect_identical(x$robots$body_size, 512000L, label = label)
  expect_identical(x$robots$max_bytes, 512000L, label = label)
}

# A complete rule starting at byte 520,001: past the window, before 524,288.
uw_between <- uw_body("Disallow: /after\n", 520000L)

test_that("ROBO-uwveumyp: the default max_bytes is 512000L", {
  expect_identical(formals(allowed_by_robots_url)$max_bytes, 512000L)
})

test_that("ROBO-uwveumyp: the default does not read a rule past 512,000", {
  expect_gt(length(uw_between), 512000L)
  expect_lt(length(uw_between), 524288L)
  uw_serve(uw_between)
  uw_expect_unread(allowed_by_robots_url(uw_url("/after"), "bot"))
})

test_that("ROBO-uwveumyp: an explicit 524288L still reads that rule", {
  uw_serve(uw_between)
  x <- allowed_by_robots_url(uw_url("/after"), "bot", max_bytes = 524288L)
  expect_false(x$results$allowed)
  expect_identical(x$results$decision_source, "rule_disallow")
  expect_identical(x$results$matched_line, 3L)
  expect_false(x$robots$body_truncated)
  expect_identical(x$robots$max_bytes, 524288L)
})

test_that("ROBO-uwveumyp: a rule before byte 512,000 is read at the default", {
  uw_serve(uw_body("Disallow: /before\n", 400000L, 600000L))
  x <- allowed_by_robots_url(uw_url(c("/before", "/other")), "bot")
  expect_identical(x$results$allowed, c(FALSE, TRUE))
  expect_identical(x$results$matched_line, c(3L, NA))
  expect_true(x$robots$body_truncated)
  expect_identical(x$robots$body_size, 512000L)
})

test_that("ROBO-uwveumyp: a line across byte 512,000 is dropped whole", {
  # Its first 11 bytes, "Disallow: /", lie inside the cut; read on their own
  # they would disallow everything.
  body <- uw_body("Disallow: /private-drafts/\n", 512000L - 11L)
  expect_gt(length(body), 512000L)
  uw_serve(body)
  uw_expect_unread(
    allowed_by_robots_url(uw_url(c("/private-drafts/x", "/public")), "bot")
  )
})

test_that("ROBO-uwveumyp: a rule whose LF is byte 512,000 is read", {
  uw_serve(uw_body("Disallow: /private\n", 512000L - 19L, 600000L))
  x <- allowed_by_robots_url(uw_url("/private"), "bot")
  expect_false(x$results$allowed)
  expect_identical(x$results$matched_line, 3L)
  expect_true(x$robots$body_truncated)
})

test_that("ROBO-uwveumyp: a rule ending at 512,000, LF at 512,001", {
  # Accepted divergence (engine-profiles.md §7): the URL path stores 512,000
  # bytes, so the rule's break is not stored and the line is dropped; the
  # v1 window looks one byte past 512,000 and keeps it.
  body <- uw_body("Disallow: /private\n", 512000L - 18L, 600000L)
  uw_serve(body)
  uw_expect_unread(allowed_by_robots_url(uw_url("/private"), "bot"))
  v1 <- robots_evaluate_url_v1(uw_url("/private"), "bot", "google", "google")
  expect_identical(v1$results$url_decision, "disallow")
  expect_identical(v1$results$matched_line, 3L)
})

test_that("ROBO-uwveumyp: a whole file up to 512,000 keeps its last line", {
  # A genuine last line with no newline is read when the file fits.
  for (size in c(511999L, 512000L)) {
    body <- uw_body("Disallow: /last", size - 15L)
    expect_identical(length(body), size)
    uw_serve(body)
    x <- allowed_by_robots_url(uw_url("/last"), "bot")
    expect_false(x$results$allowed, label = size)
    expect_identical(x$results$matched_line, 3L, label = size)
    expect_false(x$robots$body_truncated, label = size)
    expect_identical(x$robots$body_size, size, label = size)
  }
})
