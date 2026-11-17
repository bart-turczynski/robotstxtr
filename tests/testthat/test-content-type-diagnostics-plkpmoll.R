# ROBO-plkpmoll: the validator reads a fetched response's Content-Type and
# reports a malformed header, a media type other than text/plain, an
# unsupported charset, and charset=us-ascii over bytes of 0x80 or above. A
# missing header adds no row, and the header changes no parse or decision.

ct_rules <- "User-agent: *\nDisallow: /private\n"
ct_html <- paste0(
  "<!DOCTYPE html>\n<html><head><title>Home</title></head>\n",
  "<body><p>Welcome</p></body></html>\n"
)

# A one-hop fetch answering `status` with the given headers and body.
ct_validate <- function(type = NULL, body = ct_rules, status = 200L,
                        headers = NULL, ...) {
  if (is.null(headers)) {
    headers <- if (is.null(type)) list() else list(`Content-Type` = type)
  }
  local_fake_ssrfr(function(req) {
    fake_response(status, headers = headers, body = body)
  })
  robots_validate_url("https://example.com/", ...)
}

ct_rows <- function(v) {
  v$diagnostics[startsWith(v$diagnostics$code, "content_type_"), ,
                drop = FALSE]
}

test_that("ROBO-plkpmoll: text/plain with UTF-8 or US-ASCII adds nothing", {
  accepted <- c(
    "text/plain", "TEXT/PLAIN", "text/plain;charset=UTF-8",
    "text/plain ; charset=\"utf-8\"",
    "text/plain; format=flowed; charset=us-ascii",
    "text/plain;charset=US-ASCII", "Text/Plain;\tCharset=\"US-ASCII\""
  )
  for (type in accepted) {
    v <- ct_validate(type)
    expect_identical(nrow(ct_rows(v)), 0L, info = type)
    expect_identical(v$documents$validation_status, "valid", info = type)
  }
})

test_that("ROBO-plkpmoll: a missing Content-Type adds no row", {
  missing <- ct_validate()
  plain <- ct_validate("text/plain")
  expect_identical(missing$diagnostics, plain$diagnostics)
  expect_identical(missing$documents$validation_status, "valid")
})

test_that("ROBO-plkpmoll: rules served as another media type", {
  for (type in c("text/html", "application/octet-stream")) {
    v <- ct_validate(type)
    d <- ct_rows(v)
    expect_identical(d$code, "content_type_not_text_plain", info = type)
    expect_identical(d$severity, "warning")
    expect_identical(d$line, NA_integer_)
    expect_identical(d$directive, NA_character_)
    expect_identical(d$raw_text, type)
    expect_match(d$message, type, fixed = TRUE)
    expect_match(d$message, "may still read the body", fixed = TRUE)
    expect_false("html_body" %in% v$diagnostics$code)
    expect_identical(v$documents$validation_status, "warning", info = type)
    expect_identical(v$documents$warning_count, 1L)
    expect_identical(v$documents$diagnostic_count, nrow(v$diagnostics))
  }
})

test_that("ROBO-plkpmoll: HTML under text/plain keeps html_body alone", {
  v <- ct_validate("text/plain", body = ct_html)
  expect_identical(sum(v$diagnostics$code == "html_body"), 1L)
  expect_identical(nrow(ct_rows(v)), 0L)
})

test_that("ROBO-plkpmoll: HTML under text/html", {
  v <- ct_validate("text/html", body = ct_html)
  expect_identical(sum(v$diagnostics$code == "html_body"), 1L)
  n <- nrow(v$diagnostics)
  expect_identical(v$diagnostics$code[[n]], "content_type_not_text_plain")
  expect_identical(ct_rows(v)$code, "content_type_not_text_plain")
})

test_that("ROBO-plkpmoll: malformed and repeated headers", {
  malformed <- c(
    "text/plain, text/html", "text", "", "text/", "/plain",
    "text/plain; charset=\"utf-8", "text/plain; charset = utf-8"
  )
  for (type in malformed) {
    d <- ct_rows(ct_validate(type))
    expect_identical(d$code, "content_type_malformed", info = type)
    expect_identical(d$raw_text, type, info = type)
  }
  # Two fields of the same name, as a server may send them.
  two <- ct_validate(headers = stats::setNames(
    list("text/plain", "text/html"), rep("Content-Type", 2L)
  ))
  d <- ct_rows(two)
  expect_identical(d$code, "content_type_malformed")
  expect_identical(d$raw_text, "text/plain, text/html")
  expect_match(d$message, "several Content-Type fields", fixed = TRUE)
  d <- ct_rows(ct_validate("text"))
  expect_match(d$message, "type/subtype", fixed = TRUE)
})

test_that("ROBO-plkpmoll: unsupported, empty and repeated charsets", {
  unsupported <- c(
    "text/plain; charset=\"\"", "text/plain; charset=latin1",
    "text/plain; charset=utf-16", "text/plain; charset=ISO-8859-1",
    "text/plain; charset=utf-8; charset=us-ascii"
  )
  for (type in unsupported) {
    v <- ct_validate(type)
    expect_identical(
      ct_rows(v)$code, "content_type_charset_unsupported", info = type
    )
    expect_identical(v$documents$validation_status, "warning", info = type)
  }
  expect_match(
    ct_rows(ct_validate("text/plain; charset=Latin1"))$message,
    "declares charset latin1", fixed = TRUE
  )
  expect_match(
    ct_rows(ct_validate("text/plain; charset=\"\""))$message, "empty charset",
    fixed = TRUE
  )
  expect_match(
    ct_rows(ct_validate("text/plain; charset=a; charset=b"))$message,
    "more than once", fixed = TRUE
  )
})

test_that("ROBO-plkpmoll: another type with an unsupported charset", {
  v <- ct_validate("text/html; charset=latin1")
  expect_identical(
    ct_rows(v)$code,
    c("content_type_not_text_plain", "content_type_charset_unsupported")
  )
  expect_identical(v$documents$warning_count, 2L)
})

test_that("ROBO-plkpmoll: a header with non-ASCII bytes does not crash", {
  bad <- rawToChar(as.raw(c(0x74, 0x65, 0x78, 0x74, 0x2f, 0xe9)))
  d <- ct_rows(ct_validate(bad))
  expect_identical(d$code, "content_type_malformed")
  expect_identical(d$raw_text, "text/\\xE9")
  quoted <- rawToChar(c(charToRaw("text/plain; charset=\""), as.raw(0xe9),
                        charToRaw("\"")))
  d <- ct_rows(ct_validate(quoted))
  expect_identical(d$code, "content_type_charset_unsupported")
  expect_identical(d$raw_text, "text/plain; charset=\"\\xE9\"")
  expect_match(d$message, "charset \\xE9", fixed = TRUE)
})

test_that("ROBO-plkpmoll: us-ascii over bytes of 0x80 and above", {
  utf8 <- c(charToRaw("User-agent: *\nDisallow: /caf"), as.raw(c(0xc3, 0xa9)),
            charToRaw("\n"))
  v <- ct_validate("text/plain; charset=us-ascii", body = utf8)
  d <- ct_rows(v)
  expect_identical(d$code, "content_type_charset_conflict")
  expect_identical(d$raw_text, "text/plain; charset=us-ascii")
  expect_match(d$message, "0x80 or above", fixed = TRUE)
  expect_identical(v$documents$validation_status, "warning")
  latin1 <- c(charToRaw("User-agent: *\nDisallow: /caf"), as.raw(0xe9),
              charToRaw("\n"))
  v <- ct_validate("text/plain; charset=US-ASCII", body = latin1)
  expect_identical(ct_rows(v)$code, "content_type_charset_conflict")
  expect_true("invalid_utf8" %in% v$diagnostics$code)
  bom8 <- c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(ct_rules))
  v <- ct_validate("text/plain; charset=us-ascii", body = bom8)
  expect_identical(ct_rows(v)$code, "content_type_charset_conflict")
  # ASCII bytes cannot tell UTF-8 from another ASCII-compatible charset.
  v <- ct_validate("text/plain; charset=iso-8859-1")
  expect_identical(ct_rows(v)$code, "content_type_charset_unsupported")
})

test_that("ROBO-plkpmoll: a UTF-16 body under us-ascii", {
  wide <- c(as.raw(c(0xff, 0xfe)),
            as.vector(rbind(charToRaw(ct_rules), as.raw(0L))))
  v <- ct_validate("text/plain; charset=us-ascii", body = wide)
  expect_identical(v$documents$encoding_signature, "utf-16le")
  expect_true("utf16_or_utf32_encoding" %in% v$diagnostics$code)
  expect_identical(nrow(ct_rows(v)), 0L)
  v <- ct_validate("text/plain; charset=utf-8", body = wide)
  expect_true("utf16_or_utf32_encoding" %in% v$diagnostics$code)
  expect_identical(nrow(ct_rows(v)), 0L)
})

test_that("ROBO-plkpmoll: invalid UTF-8 declared utf-8 keeps invalid_utf8", {
  latin1 <- c(charToRaw("User-agent: *\nDisallow: /caf"), as.raw(0xe9),
              charToRaw("\n"))
  v <- ct_validate("text/plain; charset=utf-8", body = latin1)
  expect_true("invalid_utf8" %in% v$diagnostics$code)
  expect_identical(nrow(ct_rows(v)), 0L)
})

test_that("ROBO-plkpmoll: a body cut at max_bytes", {
  long <- paste0("User-agent: *\n", strrep("Disallow: /private\n", 20L))
  v <- ct_validate("text/html", body = long, max_bytes = 100L)
  expect_true("body_truncated" %in% v$diagnostics$code)
  expect_identical(ct_rows(v)$code, "content_type_not_text_plain")
})

test_that("ROBO-plkpmoll: the header rows come after the redirect rows", {
  local_fake_ssrfr(function(req) {
    if (identical(req$url, "http://example.com/robots.txt")) {
      fake_response(
        301L, url = req$url,
        headers = list(Location = "https://example.org/robots.txt")
      )
    } else {
      fake_response(200L, url = req$url,
                    headers = list(`Content-Type` = "text/html"),
                    body = ct_rules)
    }
  })
  v <- robots_validate_url("http://example.com/")
  expect_identical(
    v$diagnostics$code,
    c("redirect_cross_site", "content_type_not_text_plain")
  )
})

test_that("ROBO-plkpmoll: an empty 2xx body is still checked", {
  for (status in c(203L, 204L)) {
    v <- ct_validate("text/html", body = raw(), status = status)
    expect_identical(
      ct_rows(v)$code, "content_type_not_text_plain",
      info = as.character(status)
    )
  }
})

test_that("ROBO-plkpmoll: an unavailable document gets no header row", {
  for (status in c(404L, 503L)) {
    v <- ct_validate("text/html", body = ct_html, status = status)
    expect_identical(nrow(ct_rows(v)), 0L, info = as.character(status))
  }
})

test_that("ROBO-plkpmoll: fetch rows, decisions and text validation", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, headers = list(`Content-Type` = "text/html"),
                  body = ct_rules)
  })
  fetched <- robots_fetch("https://example.com/")
  expect_identical(fetched$robots$content_type, "text/html")
  expect_true(is.na(fetched$robots$content_flag))
  html <- allowed_by_robots_url("https://example.com/private", "Googlebot")
  local_fake_ssrfr(function(req) {
    fake_response(200L, headers = list(`Content-Type` = "text/plain"),
                  body = ct_rules)
  })
  plain <- allowed_by_robots_url("https://example.com/private", "Googlebot")
  expect_identical(html$results, plain$results)
  expect_false(any(startsWith(
    robots_validate_text(ct_html)$diagnostics$code, "content_type_"
  )))
})

ct_utf8_body <- c(charToRaw("User-agent: *\nDisallow: /caf"),
                  as.raw(c(0xc3, 0xa9)), charToRaw("\n"))

test_that("ROBO-plkpmoll: the IANA US-ASCII aliases read as us-ascii", {
  aliases <- c(
    "ASCII", "us", "ANSI_X3.4-1968", "iso-ir-6", "ANSI_X3.4-1986",
    "\"ISO_646.irv:1991\"", "ISO646-US", "IBM367", "cp367", "csASCII"
  )
  for (alias in aliases) {
    type <- paste0("text/plain; charset=", alias)
    expect_identical(nrow(ct_rows(ct_validate(type))), 0L, info = alias)
    expect_identical(
      ct_rows(ct_validate(type, body = ct_utf8_body))$code,
      "content_type_charset_conflict", info = alias
    )
  }
})

test_that("ROBO-plkpmoll: a nonstandard UTF-8 label is named as one", {
  for (label in c("utf8", "UTF8", "unicode-1-1-utf-8")) {
    d <- ct_rows(ct_validate(paste0("text/plain; charset=", label)))
    expect_identical(d$code, "content_type_charset_unsupported", info = label)
    expect_match(d$message, "nonstandard label", fixed = TRUE)
    expect_match(d$message, "charset=utf-8", fixed = TRUE)
    expect_no_match(d$message, "may not read as intended", fixed = TRUE)
  }
})

test_that("ROBO-plkpmoll: an ASCII-compatible charset over an ASCII body", {
  for (charset in c("iso-8859-1", "windows-1252")) {
    d <- ct_rows(ct_validate(paste0("text/plain; charset=", charset)))
    expect_identical(d$code, "content_type_charset_unsupported")
    expect_match(d$message, "plain ASCII", fixed = TRUE)
    expect_no_match(d$message, "may not read as intended", fixed = TRUE)
  }
  latin1 <- c(charToRaw("User-agent: *\nDisallow: /caf"), as.raw(0xe9),
              charToRaw("\n"))
  d <- ct_rows(ct_validate("text/plain; charset=iso-8859-1", body = latin1))
  expect_identical(d$code, "content_type_charset_unsupported")
  expect_no_match(d$message, "plain ASCII", fixed = TRUE)
})

test_that("ROBO-plkpmoll: one charset repeated is not ambiguous", {
  v <- ct_validate("text/plain; charset=utf-8; charset=UTF-8")
  expect_identical(nrow(ct_rows(v)), 0L)
  d <- ct_rows(ct_validate("text/plain; charset=utf-8; charset=us-ascii"))
  expect_identical(d$code, "content_type_charset_unsupported")
  expect_match(d$message, "more than once", fixed = TRUE)
})

test_that("ROBO-plkpmoll: an empty parameter value is malformed", {
  for (type in c("text/plain; charset=", "text/plain; format=")) {
    expect_identical(
      ct_rows(ct_validate(type))$code, "content_type_malformed", info = type
    )
  }
})

test_that("ROBO-plkpmoll: a control byte in a quoted string is malformed", {
  for (byte in c(0x01, 0x0a, 0x1f, 0x7f)) {
    type <- rawToChar(c(charToRaw("text/plain; charset=\"utf"), as.raw(byte),
                        charToRaw("-8\"")))
    expect_identical(
      ct_rows(ct_validate(type))$code, "content_type_malformed",
      info = sprintf("0x%02X", byte)
    )
  }
  # Tab, space and a quoted-pair are allowed.
  v <- ct_validate("text/plain; format=\"a\tb c\\\"d\"; charset=utf-8")
  expect_identical(nrow(ct_rows(v)), 0L)
})

test_that("ROBO-plkpmoll: the same media type twice asks for one field", {
  same <- list(
    ct_validate("text/plain, text/plain"),
    ct_validate("text/plain; charset=utf-8, TEXT/PLAIN; charset=utf-8"),
    ct_validate(headers = stats::setNames(
      list("text/plain", "text/plain"), rep("Content-Type", 2L)
    ))
  )
  for (v in same) {
    d <- ct_rows(v)
    expect_identical(d$code, "content_type_malformed")
    expect_match(d$message, "send one Content-Type field", fixed = TRUE)
    expect_no_match(d$message, "Serve robots.txt as text/plain", fixed = TRUE)
  }
  d <- ct_rows(ct_validate("text/plain, text/html"))
  expect_match(d$message, "Serve robots.txt as text/plain", fixed = TRUE)
})

test_that("ROBO-plkpmoll: a long quoted parameter parses in linear time", {
  # A 64 KiB quoted value, then one of quoted-pairs. Copying the value byte
  # by byte took over two seconds here; one pass takes a few hundredths.
  value <- paste0("text/plain; x=\"", strrep("a", 65536L), "\"")
  elapsed <- system.time(parsed <- content_type_parse(value))[["elapsed"]]
  expect_identical(parsed$reason, NA_character_)
  expect_identical(parsed$media_type, "text/plain")
  expect_lt(elapsed, 1)
  pairs <- paste0("text/plain; charset=\"", strrep("\\a", 32768L), "\"")
  elapsed <- system.time(parsed <- content_type_parse(pairs))[["elapsed"]]
  expect_identical(parsed$charsets, strrep("a", 32768L))
  expect_lt(elapsed, 1)
})
