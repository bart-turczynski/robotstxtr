# ROBO-fqkgreev: a Content-Signal line (draft-romm-aipref-contentsignals-00,
# an expired Internet-Draft) is no rule to any matcher, and no crawler
# operator documents honoring it, so the validator gives it its own warning,
# content_signal_directive, instead of the generic unsupported_directive
# ("another crawler may use it"). It still counts as a known, unsupported
# directive. Content-Usage stays on the generic warning. Sources and the
# date the vendor docs were read: design/engine-profiles.md section 7a.

cs_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

cs_generic <- paste0(
  "Directive is known but ignored by this validation profile; ",
  "another crawler may use it."
)

cs_message <- paste0(
  "Content-Signal comes from an expired Internet-Draft and no crawler ",
  "operator documents honoring it; for an AI-training preference use a ",
  "`User-Agent: __usage_ai-training` group."
)

cs_fixture <- cs_lines(
  "User-agent: *", "Content-Signal: search=yes, ai-train=no",
  "Disallow: /private"
)

cs_rows <- function(body) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == "content_signal_directive", , drop = FALSE]
}

test_that("a Content-Signal line gets its own warning", {
  x <- robots_validate_text(cs_fixture)
  expect_identical(x$documents$validation_status, "warning")
  d <- x$diagnostics
  expect_identical(d$code, "content_signal_directive")
  expect_identical(d$severity, "warning")
  expect_identical(d$line, 2L)
  expect_identical(d$directive, "content-signal")
  expect_identical(d$message, cs_message)
  expect_match(d$message, "expired Internet-Draft", fixed = TRUE)
  expect_match(d$message, "no crawler operator documents", fixed = TRUE)
  expect_match(d$message, "__usage_ai-training", fixed = TRUE)
})

test_that("Content-Signal counts as a known, unsupported directive", {
  doc <- robots_validate_text(cs_fixture)$documents
  expect_identical(doc$unsupported_directives, 1L)
  expect_identical(doc$unknown_directives, 0L)
  expect_identical(doc$recognized_directives, 3L)
})

test_that("the key is matched without regard to ASCII case", {
  for (key in c("CONTENT-SIGNAL", "content-signal", "Content-signal")) {
    d <- cs_rows(cs_lines("User-agent: *", paste0(key, ": ai-train=no")))
    expect_identical(d$line, 2L, info = key)
    expect_identical(d$directive, "content-signal", info = key)
  }
})

test_that("Content-Usage, Crawl-delay and an unknown key keep their codes", {
  d <- robots_validate_text(cs_lines(
    "User-agent: *", "Content-Usage: train-ai=n", "Crawl-delay: 5",
    "unicorn: x", "Content-Signal: ai-train=no", "Disallow: /private"
  ))$diagnostics
  expect_identical(d$line, 2:5)
  expect_identical(
    d$code,
    c("unsupported_directive", "unsupported_directive", "unknown_directive",
      "content_signal_directive")
  )
  expect_identical(
    d$directive,
    c("content-usage", "crawl-delay", "unicorn", "content-signal")
  )
  expect_identical(d$message[1:2], c(cs_generic, cs_generic))
})

test_that("a key that only contains content-signal is not matched", {
  d <- robots_validate_text(cs_lines(
    "User-agent: *", "Content-Signals: ai-train=no", "X-Content-Signal: x",
    "Disallow: /private"
  ))$diagnostics
  expect_identical(d$code, c("unknown_directive", "unknown_directive"))
})

test_that("an empty or non-ASCII value still gets the code", {
  expect_identical(cs_rows(cs_lines("User-agent: *", "Content-Signal:"))$line,
                   2L)
  utf8 <- cs_lines("User-agent: *", "Content-Signal: ai-train=nö")
  expect_identical(cs_rows(utf8)$line, 2L)
  latin1 <- c(charToRaw("User-agent: *\nContent-Signal: ai-train=n"),
              as.raw(0xf6), charToRaw("\n"))
  codes <- robots_validate_text(latin1)$diagnostics$code
  expect_true("invalid_utf8" %in% codes)
  expect_true("content_signal_directive" %in% codes)
})

test_that("a NUL inside a Content-Signal line does not crash", {
  body <- c(charToRaw("User-agent: *\nContent-Signal: ai-"), as.raw(0),
            charToRaw("train=no\n"))
  codes <- robots_validate_text(body)$diagnostics$code
  expect_true("nul_byte" %in% codes)
})

test_that("the Content-Signal line does not change the google decision", {
  without <- cs_lines("User-agent: *", "Disallow: /private")
  url <- "https://example.com/private/a"
  a <- allowed_by_robots_text(cs_fixture, url, "Googlebot")$results
  b <- allowed_by_robots_text(without, url, "Googlebot")$results
  expect_false(a$allowed)
  expect_identical(a$allowed, b$allowed)
  expect_identical(a$decision_source, b$decision_source)
})
