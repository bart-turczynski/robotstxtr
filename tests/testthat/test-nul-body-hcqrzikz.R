# ROBO-hcqrzikz: a NUL-bearing fetched robots.txt must not abort the call.
#
# Every decode of ACQUIRED bytes used to call a bare `rawToChar()`, which raises
# an unclassed base R `simpleError` ("embedded nul in string") as soon as a NUL
# is followed by another byte. A server serving a stray NUL at /robots.txt --
# a UTF-16-encoded file, a WAF challenge page, a truncated or NUL-padded
# response -- therefore aborted the whole call, and escaped downstream through
# the v1 engine facade.
#
# These tests pin the fix at each public entry point AND pin the rules
# (R/body-decode.R): the body preview REMOVES the NUL bytes; the Google
# matcher ends each line at its first NUL, as upstream does (ROBO-pvqrfvol),
# and reads the lines after it; the malformation stays visible through
# `robots_validate_text()`.

# --- Test helpers (local to this file) --------------------------------------

# A 200 text/plain response whose body is supplied as RAW bytes, so a NUL can be
# served verbatim (charToRaw() of a string could never produce one).
nul_ok_bytes <- function(bytes) {
  force(bytes)
  function(req) {
    fake_response(
      status_code = 200L, url = req$url,
      headers = list(`content-type` = "text/plain"), body = bytes
    )
  }
}

nul_router <- function(routes) {
  function(req) {
    handler <- routes[[req$url]]
    if (is.null(handler)) {
      stop(sprintf("unexpected request URL in mock: %s", req$url))
    }
    handler(req)
  }
}

# "user-agent: *\n" + NUL + "disallow: /x\n" + "disallow: /y\n". The NUL sits at
# the start of the first rule line: the Google matcher ends that line at it, so
# /x is never read, and reads the next line, so /y is. A decode that truncated
# the whole document at the NUL would lose both rules.
nul_body_bytes <- c(
  charToRaw("user-agent: *\n"),
  as.raw(0),
  charToRaw("disallow: /x\ndisallow: /y\n")
)

# --- The two decode helpers --------------------------------------------------

test_that("render_body_bytes() honors its no-error contract on a NUL", {
  out <- render_body_bytes(as.raw(c(0x55, 0x73, 0x65, 0x72, 0x00, 0x61)))
  expect_identical(out, "Usera")

  # Bytes that are valid UTF-8 once the NUL is gone are still marked UTF-8 (an
  # all-ASCII result stays "unknown", which is R's own no-op for ASCII).
  utf8 <- render_body_bytes(as.raw(c(0x63, 0x61, 0x66, 0x00, 0xc3, 0xa9)))
  expect_identical(Encoding(utf8), "UTF-8")
  expect_identical(charToRaw(utf8), as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)))
})

test_that("render_body_bytes() marks bytes for invalid UTF-8 past a NUL", {
  out <- render_body_bytes(as.raw(c(0x2f, 0x00, 0xff)))
  expect_identical(Encoding(out), "bytes")
  expect_identical(charToRaw(out), as.raw(c(0x2f, 0xff)))
})

test_that("matcher_string_v1() decodes NUL-bearing bytes without erroring", {
  out <- matcher_string_v1(nul_body_bytes)
  expect_identical(out, "user-agent: *\n\ndisallow: /y\n")

  # The matcher input is marked UTF-8 so cpp11 forwards the exact bytes; a
  # non-ASCII body shows the mark (ASCII-only results stay "unknown" in R).
  marked <- matcher_string_v1(c(charToRaw("disallow: /café"), as.raw(0)))
  expect_identical(Encoding(marked), "UTF-8")
})

test_that("the preview removes NUL bytes; the matcher ends a line at one", {
  # The preview keeps every other byte; the matcher reads the line holding
  # the NUL only up to it and every later line whole (ROBO-pvqrfvol).
  expect_identical(
    nul_free_bytes(nul_body_bytes),
    charToRaw("user-agent: *\ndisallow: /x\ndisallow: /y\n")
  )
  expect_identical(
    nul_line_end_bytes(nul_body_bytes),
    charToRaw("user-agent: *\n\ndisallow: /y\n")
  )
})

# --- Entry point 1: robots_body() preview ------------------------------------

test_that("robots_body() previews a NUL-bearing fetched body byte-safely", {
  local_fake_ssrfr(nul_router(list(
    "http://a/robots.txt" = nul_ok_bytes(nul_body_bytes)
  )))
  x <- allowed_by_robots_url("http://a/x", "TestBot")

  # The preview renders; the NUL is gone from the string but the STORED bytes
  # are untouched, so raw = TRUE still round-trips the body byte-for-byte.
  expect_identical(
    robots_body(x, n = Inf),
    "user-agent: *\ndisallow: /x\ndisallow: /y\n"
  )
  expect_identical(robots_body(x, raw = TRUE), nul_body_bytes)
})

# --- Entry point 2: allowed_by_robots_url() ----------------------------------

test_that("allowed_by_robots_url() matches a NUL-bearing body, no abort", {
  local_fake_ssrfr(nul_router(list(
    "http://a/robots.txt" = nul_ok_bytes(nul_body_bytes)
  )))
  urls <- c("http://a/x", "http://a/y", "http://a/z")
  x <- allowed_by_robots_url(urls, "TestBot")

  # The NUL ends its line, so /x is unread while /y, on the next line, is
  # live; the row keeps the ordinary fetched-source contract, not an error.
  expect_identical(x$results$allowed, c(TRUE, FALSE, TRUE))
  expect_identical(
    x$results$decision_source,
    c("default_allow", "rule_disallow", "default_allow")
  )
  expect_identical(x$robots$fetch_outcome, "fetched")
  expect_identical(x$robots$error_class, NA_character_)
  # Match-metadata correlation runs the parse collector over the same decoded
  # body; its value channel cannot carry a NUL either, so this pins that too.
  expect_identical(
    x$results$matched_rule_value, c(NA_character_, "/y", NA_character_)
  )
  expect_identical(x$results$matched_line, c(NA_integer_, 3L, NA_integer_))
})

# --- Entry point 3: robots_evaluate_url_v1() (and sitemapr's caller) ---------

test_that("robots_evaluate_url_v1() evaluates a NUL-bearing body", {
  local_fake_ssrfr(nul_router(list(
    "http://a/robots.txt" = nul_ok_bytes(nul_body_bytes)
  )))
  x <- robots_evaluate_url_v1(
    "http://a/y", robots_product_token = "TestBot",
    robots_policy_ruleset = "google", matcher_backend = "google"
  )

  expect_identical(x$results$url_decision, "disallow")
  expect_identical(x$results$reason, "rule_disallow")
  expect_identical(x$results$matched_rule_value, "/y")
  expect_identical(x$results$matcher_status, "evaluated")
})

# --- The malformation stays visible -----------------------------------------

test_that("robots_validate_text() still reports the NUL it decoded past", {
  v <- robots_validate_text(nul_body_bytes)
  nul <- v$diagnostics[v$diagnostics$code == "nul_byte", , drop = FALSE]

  expect_identical(nrow(nul), 1L)
  expect_identical(nul$severity, "error")
  expect_identical(nul$line, 2L)
  # The byte itself is rendered, not silently dropped, in the diagnostic.
  expect_match(nul$raw_text, "\\\\x00", fixed = FALSE)
  expect_identical(v$documents$validation_status, "error")
})
