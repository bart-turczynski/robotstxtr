# ROBO-ccfsanhq: robots_validate_text() and robots_validate_url() say when a
# body looks like an HTML page, with one document-level `html_body` warning.
# The flag is the fetch row's sniffer, robots_content_flag() (ROBO-nhuirvrd),
# read on the validated bytes; only its "html" answer draws the warning.

html_codes <- function(body) {
  robots_validate_text(body)$diagnostics$code
}

test_that("an ordinary robots.txt draws no html_body", {
  body <- "User-agent: *\nDisallow: /private/\nSitemap: https://example.com/s\n"
  expect_false("html_body" %in% html_codes(body))
})

test_that("an HTML marker that does not start a line draws no html_body", {
  # A robots.txt comment and a rule value: the sniffer reads neither as HTML.
  comment <- "# <!DOCTYPE html>\nUser-agent: *\nDisallow: /x\n"
  rule <- "User-agent: *\nDisallow: /x <html>\n"
  for (body in c(comment, rule)) {
    expect_true(is.na(robots_content_flag(charToRaw(body))), label = body)
    expect_false("html_body" %in% html_codes(body), label = body)
  }
})

test_that("an XML or JSON body draws no html_body", {
  xml <- paste0('<?xml version="1.0"?>\n<Error><Code>NoSuchKey</Code>',
                "</Error>\n")
  json <- '{"error": "not found"}\n'
  expect_identical(robots_content_flag(charToRaw(xml)), "xml")
  expect_identical(robots_content_flag(charToRaw(json)), "json")
  expect_false("html_body" %in% html_codes(xml))
  expect_false("html_body" %in% html_codes(json))
})

test_that("an empty body draws no html_body", {
  expect_identical(html_codes(raw()), "no_rules")
  expect_identical(html_codes(""), "no_rules")
})

test_that("an HTML body the sniffer calls binary draws no html_body", {
  # A NUL makes the window binary; the nul_byte error already reports it.
  with_nul <- c(charToRaw("<!DOCTYPE html>\n<html>"), as.raw(0),
                charToRaw("</html>\n"))
  expect_identical(robots_content_flag(with_nul), "binary")
  codes <- html_codes(with_nul)
  expect_true("nul_byte" %in% codes)
  expect_false("html_body" %in% codes)
  # Mostly invalid UTF-8: past the binary threshold, invalid_utf8 reports it.
  latin1 <- c(charToRaw("<html>\n<body>"), rep(as.raw(0xe9), 20L),
              charToRaw("\n</body></html>\n"))
  expect_identical(robots_content_flag(latin1), "binary")
  codes <- html_codes(latin1)
  expect_true("invalid_utf8" %in% codes)
  expect_false("html_body" %in% codes)
})

test_that("HTML past the sniffer's window draws no html_body", {
  lines <- rep("Disallow: /aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 150L)
  body <- paste0("User-agent: *\n", paste(lines, collapse = "\n"),
                 "\n<!DOCTYPE html>\n<html></html>\n")
  expect_gt(regexpr("<!DOCTYPE", body, fixed = TRUE), content_check_bytes)
  expect_true(is.na(robots_content_flag(charToRaw(body))))
  expect_false("html_body" %in% html_codes(body))
})
