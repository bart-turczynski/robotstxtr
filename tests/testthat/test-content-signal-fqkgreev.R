# ROBO-fqkgreev: a Content-Signal line (draft-romm-aipref-contentsignals-00,
# an expired Internet-Draft) is no rule to any matcher. Content-Usage stays
# on the generic unsupported_directive warning. Sources and the date the
# vendor docs were read: design/engine-profiles.md section 7a.

cs_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

cs_generic <- paste0(
  "Directive is known but ignored by this validation profile; ",
  "another crawler may use it."
)

cs_fixture <- cs_lines(
  "User-agent: *", "Content-Signal: search=yes, ai-train=no",
  "Disallow: /private"
)

test_that("a Content-Signal line gets the generic unsupported warning", {
  x <- robots_validate_text(cs_fixture)
  d <- x$diagnostics
  expect_identical(d$code, "unsupported_directive")
  expect_identical(d$severity, "warning")
  expect_identical(d$line, 2L)
  expect_identical(d$directive, "content-signal")
  expect_identical(d$message, cs_generic)
})

test_that("Content-Signal counts as a known, unsupported directive", {
  doc <- robots_validate_text(cs_fixture)$documents
  expect_identical(doc$unsupported_directives, 1L)
  expect_identical(doc$unknown_directives, 0L)
  expect_identical(doc$recognized_directives, 3L)
})

test_that("Content-Usage, Crawl-delay and an unknown key keep their codes", {
  d <- robots_validate_text(cs_lines(
    "User-agent: *", "Content-Usage: train-ai=n", "Crawl-delay: 5",
    "unicorn: x", "Disallow: /private"
  ))$diagnostics
  expect_identical(d$line, 2:4)
  expect_identical(
    d$code,
    c("unsupported_directive", "unsupported_directive", "unknown_directive")
  )
  expect_identical(d$directive, c("content-usage", "crawl-delay", "unicorn"))
  expect_identical(d$message[1:2], c(cs_generic, cs_generic))
})
