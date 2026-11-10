# ROBO-vxrzcqpe: how a robots.txt with no Allow or Disallow rules validates.

nr_message <- paste0(
  "Document has no Allow or Disallow rules, so it places no restrictions ",
  "on crawling."
)

nr_rule_free <- list(
  "zero bytes" = raw(),
  "blank lines" = "\n\n  \n\t\n",
  "CRLF blank lines" = "\r\n\r\n",
  "comments only" = "# only a comment\n# another",
  "Sitemap only" = "Sitemap: https://example.com/s.xml\n",
  "comments and sitemaps" = paste0(
    "# c\nSitemap: https://example.com/s.xml\n",
    "Sitemap: https://example.com/t.xml"
  ),
  "User-agent only" = "User-agent: *\n"
)

# The one no_rules row of `x`: a document-level info with the settled
# message, and no missing_user_agent beside it.
expect_no_rules <- function(x, label) {
  found <- x$diagnostics[x$diagnostics$code == "no_rules", , drop = FALSE]
  expect_identical(nrow(found), 1L, label = label)
  expect_identical(found$severity, "info", label = label)
  expect_identical(found$line, NA_integer_, label = label)
  expect_identical(found$directive, NA_character_, label = label)
  expect_identical(found$raw_text, NA_character_, label = label)
  expect_identical(found$message, nr_message, label = label)
  expect_false("missing_user_agent" %in% x$diagnostics$code, label = label)
}

test_that("a rule-free document is valid with only the no_rules info", {
  for (case in names(nr_rule_free)) {
    x <- robots_validate_text(nr_rule_free[[case]])
    expect_identical(x$documents$validation_status, "valid", label = case)
    expect_identical(x$map$validation_status, "valid", label = case)
    expect_identical(x$diagnostics$code, "no_rules", label = case)
    expect_identical(x$documents$error_count, 0L, label = case)
    expect_identical(x$documents$warning_count, 0L, label = case)
    expect_identical(x$documents$diagnostic_count, 1L, label = case)
    expect_no_rules(x, case)
  }
})

test_that("a 200 with an empty body is valid with no_rules", {
  local_fake_ssrfr(function(req) fake_response(200L, body = raw()))
  x <- robots_validate_url("http://a/")
  expect_identical(x$map$validation_status, "valid")
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$diagnostics$code, "no_rules")
  expect_identical(x$diagnostics$source_id, x$documents$source_id)
  expect_no_rules(x, "empty 200")
})

test_that("rules without a User-agent still draw missing_user_agent", {
  for (body in c("Disallow: /\n", "Allow: /x\nDisallow: /y")) {
    x <- robots_validate_text(body)
    expect_identical(x$documents$validation_status, "error", label = body)
    expect_true(all(c("rule_without_user_agent", "missing_user_agent") %in%
                      x$diagnostics$code), label = body)
    expect_false("no_rules" %in% x$diagnostics$code, label = body)
  }
})

test_that("an empty or typo'd rule line still counts as a rule", {
  x <- robots_validate_text("User-agent: *\nDisallow:\n")
  expect_identical(x$diagnostics$code, "empty_rule_value")
  expect_identical(x$documents$validation_status, "warning")

  x <- robots_validate_text("User-agent: *\nDisalow: /x\n")
  expect_identical(x$documents$disallow_directives, 1L)
  expect_identical(x$diagnostics$code, "accepted_directive_typo")
  expect_false("no_rules" %in% x$diagnostics$code)
})

test_that("no_rules sits beside the other findings of a rule-free file", {
  cases <- list(
    list(
      body = as.raw(c(0xef, 0xbb, 0xbf, charToRaw(
        "Sitemap: https://example.com/s.xml\n"
      ))),
      codes = c("byte_order_mark", "no_rules"), status = "warning"
    ),
    list(body = as.raw(c(0xef, 0xbb, 0xbf)),
         codes = c("byte_order_mark", "no_rules"), status = "warning"),
    list(body = "Crawl-delay: 5\n",
         codes = c("unsupported_directive", "no_rules"), status = "warning"),
    list(body = "User-agent:\n", codes = c("empty_user_agent", "no_rules"),
         status = "error"),
    list(body = "Sitemap: https://example.com/s.xml\nnot a directive\n",
         codes = c("malformed_line", "no_rules"), status = "error"),
    list(body = "Sitemap: not a url\n",
         codes = c("invalid_sitemap_url", "no_rules"), status = "warning"),
    list(body = as.raw(c(0x23, 0x00, 0x0a)),
         codes = c("nul_byte", "no_rules"), status = "error"),
    list(body = as.raw(c(0x23, 0xff, 0x0a)),
         codes = c("invalid_utf8_comment", "no_rules"), status = "warning")
  )
  for (case in cases) {
    label <- if (is.raw(case$body)) {
      paste(as.character(case$body), collapse = " ")
    } else {
      case$body
    }
    x <- robots_validate_text(case$body)
    expect_identical(x$diagnostics$code, case$codes, label = label)
    expect_identical(x$documents$validation_status, case$status,
                     label = label)
    expect_no_rules(x, label)
  }
})

test_that("character encodings of a rule-free file all get no_rules", {
  latin1 <- "# \xe9t\xe9\n"
  Encoding(latin1) <- "latin1"
  x <- robots_validate_text(latin1)
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$diagnostics$code, "no_rules")

  bytes <- "# c\nSitemap: https://example.com/s.xml\n"
  Encoding(bytes) <- "bytes"
  from_bytes <- robots_validate_text(bytes)
  from_raw <- robots_validate_text(charToRaw(bytes))
  expect_identical(from_bytes$diagnostics, from_raw$diagnostics)
  expect_identical(from_bytes$diagnostics$code, "no_rules")
})

test_that("a body cut before its first rule is not called rule-free", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, body = "User-agent: *\nDisallow: /private-drafts/\n")
  })
  x <- robots_validate_url("http://a/", max_bytes = 25L)
  expect_identical(x$documents$disallow_directives, 0L)
  expect_identical(x$diagnostics$code, "body_truncated")
})
