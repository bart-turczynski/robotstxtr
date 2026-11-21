# ROBO-mgtngbpm: robots_validate_text() and robots_validate_url() say when a
# body is XML or JSON served in place of robots.txt, as html_body says it for
# HTML (ROBO-ccfsanhq). The kind is read by the content sniffer,
# robots_content_flag() (ROBO-nhuirvrd), on the stored bytes and on the
# validated bytes; body_kind_advisory() picks one kind from the two reads.
#
# The three matching engines are not relevant here: this is a body-type
# advisory on the validator's own summary, not a matching decision, and the
# sniffer does not depend on the engine. Nothing in this file is per engine.

kind_codes <- c("html_body", "xml_body", "json_body")

# The diagnostics of a validation as `code@line`, in emission order.
row_keys <- function(x) {
  d <- x$diagnostics
  if (nrow(d) == 0L) {
    return(character())
  }
  paste0(d$code, "@", d$line)
}

# The one body-kind row of a validation, which must be `code`: a warning on no
# line, with no directive. Returns its message.
expect_body_kind <- function(x, code, label = code) {
  d <- x$diagnostics[x$diagnostics$code %in% kind_codes, , drop = FALSE]
  expect_identical(d$code, code, label = label)
  expect_identical(d$severity, "warning", label = label)
  expect_identical(d$line, NA_integer_, label = label)
  expect_identical(d$directive, NA_character_, label = label)
  d$message
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

test_that("ROBO-mgtngbpm: an S3-style XML error draws xml_body", {
  x <- robots_validate_text(xml_s3)
  expect_identical(robots_content_flag(charToRaw(xml_s3)), "xml")
  expect_identical(
    row_keys(x),
    c("malformed_line@1", "malformed_line@2", "xml_body@NA", "no_rules@NA")
  )
  expect_body_kind(x, "xml_body")
})

test_that("ROBO-mgtngbpm: an Atom feed and an SVG draw xml_body", {
  expect_identical(robots_content_flag(charToRaw(xml_feed)), "xml")
  expect_identical(
    row_keys(robots_validate_text(xml_feed)),
    c("accepted_missing_colon@1", "unknown_directive@1",
      "unknown_directive@2", "xml_body@NA", "no_rules@NA")
  )
  expect_identical(robots_content_flag(charToRaw(svg)), "xml")
  x <- robots_validate_text(svg)
  expect_identical(row_keys(x), c("unknown_directive@1", "xml_body@NA",
                                  "no_rules@NA"))
  expect_body_kind(x, "xml_body")
})

test_that("ROBO-mgtngbpm: a JSON object or array draws json_body", {
  x <- robots_validate_text(json_obj)
  expect_identical(robots_content_flag(charToRaw(json_obj)), "json")
  expect_identical(
    row_keys(x),
    c("unknown_directive@1", "json_body@NA", "no_rules@NA")
  )
  expect_body_kind(x, "json_body")
  expect_identical(
    row_keys(robots_validate_text('[{"a":1}]\n')),
    c("unknown_directive@1", "json_body@NA", "no_rules@NA")
  )
  expect_identical(robots_content_flag(charToRaw("[]\n")), "json")
  expect_identical(
    row_keys(robots_validate_text("[]\n")),
    c("malformed_line@1", "json_body@NA", "no_rules@NA")
  )
})

test_that("ROBO-mgtngbpm: a rule line in an XML or JSON body is still read", {
  xml_rule <- paste0('<?xml version="1.0"?>\n',
                     "User-agent: *\nDisallow: /x\n")
  x <- robots_validate_text(xml_rule)
  expect_identical(
    row_keys(x),
    c("accepted_missing_colon@1", "unknown_directive@1", "xml_body@NA")
  )
  expect_identical(x$documents$disallow_directives, 1L)
  json_rule <- '["a",\nUser-agent: *\nDisallow: /x\n]\n'
  y <- robots_validate_text(json_rule)
  expect_identical(robots_content_flag(charToRaw(json_rule)), "json")
  expect_identical(y$documents$disallow_directives, 1L)
  expect_body_kind(y, "json_body")
})

test_that("ROBO-mgtngbpm: markup in a comment or a rule is no body kind", {
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

test_that("ROBO-mgtngbpm: a body cut mid-first-line keeps its stored kind", {
  # The validated lines are empty after the cut; the stored bytes still read
  # as markup or JSON, so the advisory is drawn beside body_truncated.
  local_fake_ssrfr(serve(xml_s3))
  x <- robots_validate_url("https://example.com/", max_bytes = 20L)
  expect_identical(row_keys(x), c("xml_body@NA", "body_truncated@NA"))
  expect_body_kind(x, "xml_body")
  local_fake_ssrfr(serve(json_obj, content_type = "application/json"))
  y <- robots_validate_url("https://example.com/", max_bytes = 5L)
  expect_identical(
    row_keys(y),
    c("json_body@NA", "body_truncated@NA", "content_type_not_text_plain@NA")
  )
  expect_body_kind(y, "json_body")
})

test_that("ROBO-mgtngbpm: a fetched JSON 200 draws json_body; errors do not", {
  local_fake_ssrfr(serve(json_obj, content_type = "application/json"))
  expect_identical(
    row_keys(robots_validate_url("https://example.com/")),
    c("unknown_directive@1", "json_body@NA", "no_rules@NA",
      "content_type_not_text_plain@NA")
  )
  # An unacquired body is not validated, so it draws no advisory.
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

test_that("ROBO-mgtngbpm: a BOM, invalid UTF-8 and NUL around JSON", {
  bom <- c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(json_obj))
  expect_identical(robots_content_flag(bom), "json")
  expect_identical(
    row_keys(robots_validate_text(bom)),
    c("byte_order_mark@1", "unknown_directive@1", "json_body@NA",
      "no_rules@NA")
  )
  latin1 <- c(charToRaw('{"error": "caf'), as.raw(0xe9), charToRaw('"}\n'))
  expect_identical(robots_content_flag(latin1), "json")
  expect_identical(
    row_keys(robots_validate_text(latin1)),
    c("invalid_utf8@1", "unknown_directive@1", "json_body@NA", "no_rules@NA")
  )
  # A NUL makes the read binary, and binary draws no advisory.
  with_nul <- c(charToRaw(json_obj), as.raw(0))
  expect_identical(robots_content_flag(with_nul), "binary")
  expect_identical(
    row_keys(robots_validate_text(with_nul)),
    c("nul_byte@2", "unknown_directive@1", "no_rules@NA")
  )
  # UTF-16 XML: its NUL bytes make the read binary, so no XML kind either.
  utf16 <- c(as.raw(c(0xff, 0xfe)),
             unlist(lapply(utf8ToInt("<?xml?>\n<Error/>\n"), function(ch) {
               as.raw(c(ch %% 256L, ch %/% 256L))
             })))
  expect_identical(robots_content_flag(utf16), "binary")
  codes <- robots_validate_text(utf16)$diagnostics$code
  expect_false(any(kind_codes %in% codes))
  expect_true("nul_byte" %in% codes)
})

test_that("ROBO-mgtngbpm: one kind per document, html first across the reads", {
  # A cut that leaves `<html` whole in the stored bytes but not in the
  # validated lines: the stored read is html, the validated read xml or json.
  # The stored html wins, so html_body is the one advisory.
  local_fake_ssrfr(serve("<Error>\n<html></html>\n"))
  x <- robots_validate_url("https://example.com/", max_bytes = 13L)
  expect_identical(
    row_keys(x),
    c("malformed_line@1", "html_body@NA", "body_truncated@NA")
  )
  expect_body_kind(x, "html_body")
  local_fake_ssrfr(serve('{"a":1}\n<html></html>\n'))
  y <- robots_validate_url("https://example.com/", max_bytes = 13L)
  expect_identical(
    row_keys(y),
    c("unknown_directive@1", "html_body@NA", "body_truncated@NA")
  )
  expect_body_kind(y, "html_body")
})

test_that("ROBO-mgtngbpm: a binary stored read does not hide markup", {
  # The NUL lies in the partial line the cut drops; the readable line is XML.
  body <- c(charToRaw("<Error><Code>x</Code></Error>\n<Message>abc"),
            as.raw(0), charToRaw(strrep("a", 200L)))
  expect_identical(robots_content_flag(body), "binary")
  local_fake_ssrfr(serve(body))
  x <- robots_validate_url("https://example.com/", max_bytes = 60L)
  expect_identical(
    row_keys(x),
    c("malformed_line@1", "xml_body@NA", "body_truncated@NA")
  )
  expect_false("nul_byte" %in% x$diagnostics$code)
})

test_that("ROBO-mgtngbpm: an HTML page keeps html_body beside its lines", {
  x <- robots_validate_text("<!DOCTYPE html>\n<html></html>\n")
  expect_identical(
    row_keys(x),
    c("malformed_line@2", "accepted_missing_colon@1", "unknown_directive@1",
      "html_body@NA", "no_rules@NA")
  )
  expect_body_kind(x, "html_body")
})

test_that("ROBO-mgtngbpm: a comment-led body draws no xml_body", {
  # ROBO-isbpzgqn: a body that opens with a markup comment is a robots.txt
  # with a comment first, so its sniffer read "xml" draws no advisory. The
  # first two are the comment-led bodies of test-html-body-ccfsanhq.R, pinned
  # here as well; the third has an element after the comment and no robots
  # line, and the same rule suppresses it.
  bodies <- list(
    generated = "<!-- generated -->\nUser-agent: *\nDisallow: /*<script\n",
    commented = "<!-- <script> -->\nUser-agent: *\nDisallow: /\n",
    element = "<!-- c -->\n<Error><Code>x</Code></Error>\n"
  )
  for (label in names(bodies)) {
    expect_identical(robots_content_flag(charToRaw(bodies[[label]])), "xml",
                     label = label)
    expect_false(
      "xml_body" %in% robots_validate_text(bodies[[label]])$diagnostics$code,
      label = label
    )
  }
  expect_identical(
    row_keys(robots_validate_text(bodies$generated)),
    "malformed_line@1"
  )
  expect_identical(
    row_keys(robots_validate_text(bodies$element)),
    c("malformed_line@1", "malformed_line@2", "no_rules@NA")
  )
  # A BOM and leading whitespace before the comment do not change the lead.
  bom <- c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(" \n"),
           charToRaw(bodies$element))
  expect_false("xml_body" %in% robots_validate_text(bom)$diagnostics$code)
})

test_that("ROBO-mgtngbpm: a comment lead is read from the sniffer window only", {
  # The lead is looked for in the first 4,096 bytes, as the sniffer reads them.
  # A NUL past that window leaves the read "xml", and the lead check must not
  # hand the whole body to rawToChar(), which errors on an embedded NUL. The
  # NUL draws nul_byte; no xml_body.
  body <- c(charToRaw("<!-- c -->\n"), charToRaw(strrep("a", 5000L)),
            as.raw(0), charToRaw("\n"))
  expect_identical(robots_content_flag(body), "xml")
  x <- robots_validate_text(body)
  expect_identical(
    row_keys(x),
    c("nul_byte@2", "malformed_line@1", "malformed_line@2", "no_rules@NA")
  )
  expect_false("xml_body" %in% x$diagnostics$code)
})

test_that("ROBO-mgtngbpm: a comment lead is found as the sniffer finds it", {
  # The sniffer's `^\s*<` takes its whitespace from the session's locale
  # tables, and the comment lead reads the same way, so the two agree in any
  # locale. In en_US.UTF-8 a leading 0xA0 (no-break space) is whitespace.
  nbsp <- c(as.raw(0xa0),
            charToRaw("<!-- c -->\nUser-agent: *\nDisallow: /\n"))
  sniffed <- grepl("^\\s*<", rawToChar(nbsp), perl = TRUE, useBytes = TRUE)
  expect_identical(robots_content_flag(nbsp),
                   if (sniffed) "xml" else NA_character_)
  expect_identical(body_opens_with_comment(nbsp), sniffed)
  expect_false("xml_body" %in% robots_validate_text(nbsp)$diagnostics$code)
})

test_that("ROBO-mgtngbpm: body_kind_advisory() prefers html, xml, json", {
  expect_identical(body_kind_advisory("json", "html"), "html")
  expect_identical(body_kind_advisory("html", "xml"), "html")
  expect_identical(body_kind_advisory("xml", "json"), "xml")
  expect_identical(body_kind_advisory(NA_character_, "json"), "json")
  expect_identical(body_kind_advisory("binary", "xml"), "xml")
  expect_identical(body_kind_advisory("binary", "binary"), NA_character_)
  expect_identical(body_kind_advisory(NA_character_, NA_character_),
                   NA_character_)
})

test_that("ROBO-mgtngbpm: each advisory names its kind only", {
  xml_msg <- expect_body_kind(robots_validate_text(xml_s3), "xml_body")
  json_msg <- expect_body_kind(robots_validate_text(json_obj), "json_body")
  expect_match(xml_msg, "starts with markup (`<`), such as XML", fixed = TRUE)
  expect_match(
    json_msg,
    "looks like a JSON object or array, such as an API error",
    fixed = TRUE
  )
  for (msg in c(xml_msg, json_msg)) {
    expect_match(msg, "read as directives anyway", fixed = TRUE)
    # The kind is named, never an access decision (the sniffer is no proof).
    expect_false(grepl("denied|access|forbidden", msg, ignore.case = TRUE))
  }
})
