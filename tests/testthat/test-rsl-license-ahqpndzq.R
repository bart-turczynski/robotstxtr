# ROBO-ahqpndzq: a `License:` line is the License directive of Really Simple
# Licensing (RSL 1.0 section 4.4). Before this unit the validator read it as
# any unknown field. These tests pin that reading, and what must not change.
# All fixtures are synthetic.

rsl_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

rsl_diag <- function(body) robots_validate_text(body)$diagnostics

test_that("a License line is an unknown directive today", {
  x <- robots_validate_text(rsl_lines(
    "User-agent: *", "Disallow: /private",
    "License: https://example.com/license.xml"
  ))
  d <- x$diagnostics
  expect_identical(d$code, "unknown_directive")
  expect_identical(d$severity, "warning")
  expect_identical(d$line, 3L)
  expect_identical(d$directive, "license")
  expect_identical(x$documents$unknown_directives, 1L)
  expect_identical(x$documents$unsupported_directives, 0L)
  expect_identical(x$documents$recognized_directives, 2L)
})

test_that("X-RSL is an unknown directive", {
  x <- robots_validate_text(rsl_lines(
    "User-agent: *", "Disallow: /private", "X-RSL: https://example.com/l.xml"
  ))
  d <- x$diagnostics
  expect_identical(d$code, "unknown_directive")
  expect_identical(d$directive, "x-rsl")
  expect_identical(x$documents$unknown_directives, 1L)
})

test_that("Content-Signal and an unknown key keep their codes", {
  d <- rsl_diag(rsl_lines(
    "User-agent: *", "Content-Signal: ai-train=no", "Foo: bar",
    "Disallow: /private"
  ))
  expect_identical(d$code, c("content_signal_directive", "unknown_directive"))
  expect_identical(d$directive, c("content-signal", "foo"))
})

test_that("a License line between User-agent lines joins them, as any field", {
  d <- rsl_diag(rsl_lines(
    "User-agent: a-bot", "License: https://example.com/l.xml",
    "User-agent: b-bot", "Disallow: /"
  ))
  joined <- d[d$code == "user_agent_joined_across_directive", , drop = FALSE]
  expect_identical(joined$line, 3L)
  expect_identical(joined$severity, "warning")
})

test_that("a License line in a training-preference group still warns", {
  d <- rsl_diag(rsl_lines(
    "User-agent: __usage_ai-training", "Disallow: /",
    "License: https://example.com/l.xml"
  ))
  extra <- d[d$code == "ai_training_group_extra_line", , drop = FALSE]
  expect_identical(extra$line, 3L)
})

test_that("License then a space and a URL is cut at the URL's colon", {
  # The parser's separator is the first colon, here the scheme's, so the key
  # is `License https` and no missing colon is reported: not a License line.
  d <- rsl_diag(rsl_lines("User-agent: *", "Disallow: /",
                          "License https://example.com/l.xml"))
  expect_identical(d$code, "unknown_directive")
  expect_identical(d$directive, "license https")
})

test_that("a bytes-encoded key is not read as License", {
  body <- c(charToRaw("Lic"), as.raw(0xe9),
            charToRaw("nse: https://example.com/l.xml\n"))
  d <- rsl_diag(body)
  expect_identical(d$code[d$line %in% 1L],
                   c("invalid_utf8", "unknown_directive"))
  expect_identical(d$directive[d$code == "unknown_directive"], "unknown")
})
