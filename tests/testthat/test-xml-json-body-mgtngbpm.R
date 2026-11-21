# ROBO-mgtngbpm: robots_validate_text() and robots_validate_url() say when a
# body is XML or JSON served in place of robots.txt, as html_body says it for
# HTML (ROBO-ccfsanhq). The kind is read by the content sniffer,
# robots_content_flag() (ROBO-nhuirvrd), on the stored bytes and on the
# validated bytes.
#
# The three matching engines are not relevant here: this is a body-type
# advisory on the validator's own summary, not a matching decision, and the
# sniffer does not depend on the engine. Nothing in this file is per engine.
#
# This first commit pins today's behavior: none of these bodies draws an
# xml_body or json_body row yet, and each is still read line by line.

# The diagnostics of a validation as `code@line`, in emission order.
row_keys <- function(x) {
  d <- x$diagnostics
  if (nrow(d) == 0L) {
    return(character())
  }
  paste0(d$code, "@", d$line)
}

xml_s3 <- paste0('<?xml version="1.0" encoding="UTF-8"?>\n',
                 "<Error><Code>AccessDenied</Code><Message>denied</Message>",
                 "</Error>\n")
xml_feed <- paste0('<?xml version="1.0"?>\n',
                   '<feed xmlns="http://www.w3.org/2005/Atom">',
                   "<title>x</title></feed>\n")
svg <- '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>\n'
json_obj <- '{"error": "not found"}\n'

# A fixed body served with one Content-Type and status, through the ssrfr fake.
serve <- function(body, status = 200L, content_type = NULL) {
  headers <- if (is.null(content_type)) {
    list()
  } else {
    list(`Content-Type` = content_type)
  }
  function(req) {
    fake_response(status, headers = headers, body = body)
  }
}

test_that("ROBO-mgtngbpm pin: an S3-style XML error is read as lines", {
  expect_identical(robots_content_flag(charToRaw(xml_s3)), "xml")
  expect_identical(
    row_keys(robots_validate_text(xml_s3)),
    c("malformed_line@1", "malformed_line@2", "no_rules@NA")
  )
})

test_that("ROBO-mgtngbpm pin: an Atom feed and an SVG are read as lines", {
  expect_identical(robots_content_flag(charToRaw(xml_feed)), "xml")
  expect_identical(
    row_keys(robots_validate_text(xml_feed)),
    c("accepted_missing_colon@1", "unknown_directive@1",
      "unknown_directive@2", "no_rules@NA")
  )
  expect_identical(robots_content_flag(charToRaw(svg)), "xml")
  expect_identical(
    row_keys(robots_validate_text(svg)),
    c("unknown_directive@1", "no_rules@NA")
  )
})

test_that("ROBO-mgtngbpm pin: a JSON object or array is read as lines", {
  expect_identical(robots_content_flag(charToRaw(json_obj)), "json")
  expect_identical(
    row_keys(robots_validate_text(json_obj)),
    c("unknown_directive@1", "no_rules@NA")
  )
  expect_identical(robots_content_flag(charToRaw("[]\n")), "json")
  expect_identical(
    row_keys(robots_validate_text("[]\n")),
    c("malformed_line@1", "no_rules@NA")
  )
})

test_that("ROBO-mgtngbpm pin: a rule line in an XML or JSON body is read", {
  xml_rule <- paste0('<?xml version="1.0"?>\n',
                     "User-agent: *\nDisallow: /x\n")
  x <- robots_validate_text(xml_rule)
  expect_identical(
    row_keys(x),
    c("accepted_missing_colon@1", "unknown_directive@1")
  )
  expect_identical(x$documents$disallow_directives, 1L)
  json_rule <- '["a",\nUser-agent: *\nDisallow: /x\n]\n'
  y <- robots_validate_text(json_rule)
  expect_identical(robots_content_flag(charToRaw(json_rule)), "json")
  expect_identical(y$documents$disallow_directives, 1L)
})

test_that("ROBO-mgtngbpm pin: markup in a comment or a rule is no body kind", {
  bodies <- list(
    comment_xml = '# <?xml version="1.0"?>\nUser-agent: *\nDisallow: /\n',
    comment_json = '# {"a":1}\nUser-agent: *\nDisallow: /\n',
    rule = "User-agent: *\nDisallow: /<x>\n"
  )
  for (label in names(bodies)) {
    expect_true(is.na(robots_content_flag(charToRaw(bodies[[label]]))),
                label = label)
    expect_identical(row_keys(robots_validate_text(bodies[[label]])),
                     character(), label = label)
  }
  expect_true(is.na(robots_content_flag(charToRaw("   \n\n"))))
  expect_identical(row_keys(robots_validate_text("   \n\n")), "no_rules@NA")
  expect_identical(row_keys(robots_validate_text(raw())), "no_rules@NA")
})

test_that("ROBO-mgtngbpm pin: a body cut mid-first-line keeps its kind", {
  local_fake_ssrfr(serve(xml_s3))
  expect_identical(
    row_keys(robots_validate_url("https://example.com/", max_bytes = 20L)),
    "body_truncated@NA"
  )
  local_fake_ssrfr(serve(json_obj, content_type = "application/json"))
  expect_identical(
    row_keys(robots_validate_url("https://example.com/", max_bytes = 5L)),
    c("body_truncated@NA", "content_type_not_text_plain@NA")
  )
})

test_that("ROBO-mgtngbpm pin: a fetched JSON 200 is read, and errors are not", {
  local_fake_ssrfr(serve(json_obj, content_type = "application/json"))
  expect_identical(
    row_keys(robots_validate_url("https://example.com/")),
    c("unknown_directive@1", "no_rules@NA", "content_type_not_text_plain@NA")
  )
  local_fake_ssrfr(serve(json_obj, status = 404L,
                         content_type = "application/json"))
  expect_identical(
    row_keys(robots_validate_url("https://example.com/")),
    "acquisition_missing@NA"
  )
  local_fake_ssrfr(serve(json_obj, status = 500L,
                         content_type = "application/json"))
  expect_identical(
    row_keys(robots_validate_url("https://example.com/")),
    "acquisition_http_5xx@NA"
  )
})

test_that("ROBO-mgtngbpm pin: a BOM, invalid UTF-8 and NUL around JSON", {
  bom <- c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(json_obj))
  expect_identical(robots_content_flag(bom), "json")
  expect_identical(
    row_keys(robots_validate_text(bom)),
    c("byte_order_mark@1", "unknown_directive@1", "no_rules@NA")
  )
  latin1 <- c(charToRaw('{"error": "caf'), as.raw(0xe9), charToRaw('"}\n'))
  expect_identical(robots_content_flag(latin1), "json")
  expect_identical(
    row_keys(robots_validate_text(latin1)),
    c("invalid_utf8@1", "unknown_directive@1", "no_rules@NA")
  )
  with_nul <- c(charToRaw(json_obj), as.raw(0))
  expect_identical(robots_content_flag(with_nul), "binary")
  expect_identical(
    row_keys(robots_validate_text(with_nul)),
    c("nul_byte@2", "unknown_directive@1", "no_rules@NA")
  )
  # UTF-16 XML: its NUL bytes make the read binary, so no XML kind.
  utf16 <- c(as.raw(c(0xff, 0xfe)),
             unlist(lapply(utf8ToInt("<?xml?>\n<Error/>\n"), function(ch) {
               as.raw(c(ch %% 256L, ch %/% 256L))
             })))
  expect_identical(robots_content_flag(utf16), "binary")
  expect_true(
    "nul_byte" %in% robots_validate_text(utf16)$diagnostics$code
  )
})

test_that("ROBO-mgtngbpm pin: the stored and validated reads agree on html", {
  # A cut that leaves `<html` whole in the stored bytes but not in the
  # validated lines: the stored read is html, the validated read xml or json.
  # Today html_body is the only kind drawn.
  local_fake_ssrfr(serve("<Error>\n<html></html>\n"))
  x <- robots_validate_url("https://example.com/", max_bytes = 13L)
  expect_identical(
    row_keys(x),
    c("malformed_line@1", "html_body@NA", "body_truncated@NA")
  )
  local_fake_ssrfr(serve('{"a":1}\n<html></html>\n'))
  y <- robots_validate_url("https://example.com/", max_bytes = 13L)
  expect_identical(
    row_keys(y),
    c("unknown_directive@1", "html_body@NA", "body_truncated@NA")
  )
})

test_that("ROBO-mgtngbpm pin: a binary stored read does not hide markup", {
  # The NUL lies in the partial line the cut drops; the readable line is XML.
  body <- c(charToRaw("<Error><Code>x</Code></Error>\n<Message>abc"),
            as.raw(0), charToRaw(strrep("a", 200L)))
  expect_identical(robots_content_flag(body), "binary")
  local_fake_ssrfr(serve(body))
  x <- robots_validate_url("https://example.com/", max_bytes = 60L)
  expect_identical(
    row_keys(x),
    c("malformed_line@1", "body_truncated@NA")
  )
  expect_false("nul_byte" %in% x$diagnostics$code)
})

test_that("ROBO-mgtngbpm pin: an HTML page keeps html_body beside its lines", {
  x <- robots_validate_text("<!DOCTYPE html>\n<html></html>\n")
  expect_identical(
    row_keys(x),
    c("malformed_line@2", "accepted_missing_colon@1", "unknown_directive@1",
      "html_body@NA", "no_rules@NA")
  )
})
