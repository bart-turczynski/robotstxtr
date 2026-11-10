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

# --- Bodies that are HTML --------------------------------------------------

spam_path <- test_path("fixtures", "edge-cases", "content-spam-html.txt")
spam_html <- readBin(spam_path, "raw", file.info(spam_path)$size)

# The per-line rows of a validation, as `code@line`, without html_body.
line_rows <- function(d) {
  keep <- d$code != "html_body"
  paste0(d$code[keep], "@", d$line[keep])
}

expect_one_html_body <- function(x, label = NULL) {
  d <- x$diagnostics[x$diagnostics$code == "html_body", , drop = FALSE]
  expect_identical(nrow(d), 1L, label = label)
  expect_identical(d$severity, "warning", label = label)
  expect_identical(d$line, NA_integer_, label = label)
  expect_identical(d$directive, NA_character_, label = label)
}

test_that("a spam HTML page draws one html_body and keeps its line rows", {
  x <- robots_validate_text(spam_html)
  expect_one_html_body(x)
  expect_identical(x$documents$validation_status, "error")
  # The summary adds a row; it replaces none. These are the rows the page
  # drew before html_body existed (ROBO-mxermwed's manifest, as pinned then).
  before <- c(
    paste0("malformed_line@", c(3, 5, 8, 9, 10, 14, 15)),
    paste0(c("accepted_missing_colon", "unknown_directive"), "@",
           rep(c(1, 2, 4), each = 2L)),
    paste0("unknown_directive@", c(6, 7, 11, 12, 13)),
    "no_rules@NA"
  )
  expect_identical(line_rows(x$diagnostics), before)
  expect_identical(x$documents$malformed_lines, 7L)
})

test_that("a minimal HTML page draws html_body beside its line codes", {
  x <- robots_validate_text("<!DOCTYPE html>\n<html></html>\n")
  expect_one_html_body(x)
  # `<html></html>` reads as a colon-less `html` directive.
  expect_identical(
    x$diagnostics$code,
    c("malformed_line", "accepted_missing_colon", "unknown_directive",
      "html_body", "no_rules")
  )
})

test_that("a BOM before HTML draws byte_order_mark and html_body", {
  bytes <- c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("<html>\n<body></body>\n"))
  x <- robots_validate_text(bytes)
  expect_one_html_body(x)
  expect_true("byte_order_mark" %in% x$diagnostics$code)
})

test_that("a short Latin-1 byte in an HTML page still draws html_body", {
  bytes <- c(charToRaw("<!DOCTYPE html>\n<html><body>caf"), as.raw(0xe9),
             charToRaw("</body></html>\n"))
  expect_identical(robots_content_flag(bytes), "html")
  x <- robots_validate_text(bytes)
  expect_one_html_body(x)
  expect_true("invalid_utf8" %in% x$diagnostics$code)
})

test_that("robots_validate_url() draws html_body on an HTML 200", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, headers = list(`Content-Type` = "text/html"),
                  body = spam_html)
  })
  x <- robots_validate_url("https://example.com/")
  expect_one_html_body(x)
  expect_identical(x$documents$validation_status, "error")
})

test_that("an HTML body cut at max_bytes draws html_body, not no_rules", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, headers = list(`Content-Type` = "text/html"),
                  body = spam_html)
  })
  x <- robots_validate_url("https://example.com/", max_bytes = 100L)
  expect_one_html_body(x)
  expect_true("body_truncated" %in% x$diagnostics$code)
  expect_false("no_rules" %in% x$diagnostics$code)
})
