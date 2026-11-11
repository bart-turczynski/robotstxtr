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

# A one-line page longer than max_bytes: the cut leaves no complete line.
one_line_html <- paste0(
  "<!DOCTYPE html><html><head><title>Example</title></head><body>",
  strrep("<p>x</p>", 20L), "</body></html>\n"
)

test_that("ROBO-qquftxcx: a one-line HTML page cut at max_bytes is HTML", {
  # The cut leaves an empty readable prefix; html_body sniffs the stored
  # bytes, as the fetch row does, so the two agree.
  local_fake_ssrfr(function(req) {
    fake_response(200L, headers = list(`Content-Type` = "text/html"),
                  body = one_line_html)
  })
  x <- robots_validate_url("https://example.com/", max_bytes = 100L)
  expect_identical(x$diagnostics$code, c("html_body", "body_truncated"))
  expect_one_html_body(x)
  expect_match(x$diagnostics$message[[1L]], "read as directives anyway")
  expect_identical(x$documents$line_count, 0L)
  expect_identical(robots_fetch("https://example.com/", max_bytes = 100L)$
                     robots$content_flag, "html")
})

test_that("ROBO-qquftxcx: a minified page cut mid-line keeps its lines", {
  # A complete first line, with no marker, survives the cut: it is read, and
  # html_body comes from the stored bytes, whose markers lie past the cut.
  body <- paste0("<div>var a=1;</div>\n<style>p{}</style><html><body>",
                 strrep("<p>x</p>", 20L), "</body></html>\n")
  local_fake_ssrfr(function(req) {
    fake_response(200L, body = body)
  })
  x <- robots_validate_url("https://example.com/", max_bytes = 60L)
  expect_one_html_body(x)
  expect_identical(x$documents$line_count, 1L)
  expect_identical(
    paste0(x$diagnostics$code, "@", x$diagnostics$line),
    c("accepted_missing_colon@1", "unknown_directive@1", "html_body@NA",
      "body_truncated@NA")
  )
})

test_that("ROBO-qquftxcx: binary bytes past the cut keep html_body", {
  # The NUL lies in the partial last line the cut drops, so the stored bytes
  # sniff "binary" and nul_byte never fires; the readable lines still sniff
  # "html", and that is enough.
  body <- c(charToRaw("<!DOCTYPE html>\n<html><body>x</body>\n<p>abc"),
            as.raw(0), charToRaw(strrep("a", 200L)))
  expect_identical(robots_content_flag(body), "binary")
  local_fake_ssrfr(function(req) {
    fake_response(200L, body = body)
  })
  x <- robots_validate_url("https://example.com/", max_bytes = 60L)
  expect_one_html_body(x)
  expect_false("nul_byte" %in% x$diagnostics$code)
  expect_identical(
    paste0(x$diagnostics$code, "@", x$diagnostics$line),
    c("malformed_line@2", "accepted_missing_colon@1", "unknown_directive@1",
      "html_body@NA", "body_truncated@NA")
  )
})

test_that("ROBO-qquftxcx: a minified page opening with script or style", {
  script <- paste0("<script>var a={b:1};</script><!DOCTYPE html><html>",
                   "<body>x</body></html>\n")
  style <- "<style>p{color:red}</style><body><p>x</p></body>\n"
  upper <- "<SCRIPT SRC=\"/a.js\"></SCRIPT><BODY></BODY>\n"
  bom <- c(as.raw(c(0xef, 0xbb, 0xbf)),
           charToRaw("<script></script><html></html>\n"))
  crlf <- "\r\n  <style>p{}</style>\r\n"
  bodies <- list(script = script, style = style, upper = upper, bom = bom,
                 crlf = crlf)
  for (label in names(bodies)) {
    body <- bodies[[label]]
    bytes <- if (is.raw(body)) body else charToRaw(body)
    expect_identical(robots_content_flag(bytes), "html", label = label)
    expect_one_html_body(robots_validate_text(bytes), label = label)
  }
})

test_that("ROBO-qquftxcx: markup with no HTML marker draws no html_body", {
  # A feed's title and link tags, and tag names that only start like one.
  feed <- paste0("<?xml version=\"1.0\"?><feed><title>x</title>",
                 "<link href=\"https://example.com/\"/></feed>\n")
  soup <- "<div><headline/><scripts/><bodyx/></div>\n"
  for (body in c(feed, soup)) {
    expect_identical(robots_content_flag(charToRaw(body)), "xml", label = body)
    expect_false("html_body" %in% html_codes(body), label = body)
  }
  # A robots.txt never opens with `<`, so a marker inside it is still no flag.
  rules <- "User-agent: *\nDisallow: /<script>\n# <style>\n"
  expect_true(is.na(robots_content_flag(charToRaw(rules))))
  expect_false("html_body" %in% html_codes(rules))
})

test_that("ROBO-qquftxcx: a marker cut by the sniffer's window is not read", {
  # `<script` would start at byte 4093: only `<scr` is in the window.
  pad <- paste0("<div>", strrep("a", 4087L))
  cut <- paste0(pad, "<script></script>\n")
  expect_identical(regexpr("<script", cut, fixed = TRUE)[[1L]], 4093L)
  expect_identical(robots_content_flag(charToRaw(cut)), "xml")
  # The same marker whole at the window's end counts.
  whole <- paste0(substr(pad, 1L, content_check_bytes - 6L), "<style")
  expect_identical(nchar(whole), content_check_bytes)
  expect_identical(robots_content_flag(charToRaw(whole)), "html")
})

test_that("ROBO-qquftxcx: binary still wins over a mid-line marker", {
  with_nul <- c(charToRaw("<script></script><html>"), as.raw(0),
                charToRaw("</html>\n"))
  expect_identical(robots_content_flag(with_nul), "binary")
  expect_false("html_body" %in% html_codes(with_nul))
  latin1 <- c(charToRaw("<style></style><body>caf"), as.raw(0xe9),
              charToRaw("</body>\n"))
  expect_identical(robots_content_flag(latin1), "html")
  expect_one_html_body(robots_validate_text(latin1))
})
