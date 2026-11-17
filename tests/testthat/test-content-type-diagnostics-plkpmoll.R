# ROBO-plkpmoll: the validator reads a fetched response's Content-Type.
# These pins record the behavior before the change: the header is kept on the
# fetch row but never read by robots_validate_url(), so no header, however
# wrong, adds a row.

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

test_that("ROBO-plkpmoll: a text/plain header with UTF-8 or US-ASCII adds nothing", {
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
    expect_identical(nrow(ct_rows(v)), 0L, info = type)
    expect_false("html_body" %in% v$diagnostics$code)
    expect_identical(v$documents$validation_status, "valid", info = type)
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
  expect_identical(nrow(ct_rows(v)), 0L)
})

test_that("ROBO-plkpmoll: malformed and repeated headers", {
  malformed <- c(
    "text/plain, text/html", "text", "", "text/", "/plain",
    "text/plain; charset=\"utf-8", "text/plain; charset = utf-8"
  )
  for (type in malformed) {
    expect_identical(nrow(ct_rows(ct_validate(type))), 0L, info = type)
  }
  two <- ct_validate(headers = list(
    `Content-Type` = "text/plain", `Content-Type` = "text/html"
  ))
  expect_identical(nrow(ct_rows(two)), 0L)
})

test_that("ROBO-plkpmoll: unsupported, empty and repeated charsets", {
  unsupported <- c(
    "text/plain; charset=", "text/plain; charset=latin1",
    "text/plain; charset=utf-16", "text/plain; charset=ISO-8859-1",
    "text/plain; charset=utf-8; charset=utf-8"
  )
  for (type in unsupported) {
    expect_identical(nrow(ct_rows(ct_validate(type))), 0L, info = type)
  }
})

test_that("ROBO-plkpmoll: another type with an unsupported charset", {
  v <- ct_validate("text/html; charset=latin1")
  expect_identical(nrow(ct_rows(v)), 0L)
})

test_that("ROBO-plkpmoll: a header with non-ASCII bytes does not crash", {
  bad <- rawToChar(as.raw(c(0x74, 0x65, 0x78, 0x74, 0x2f, 0xe9)))
  expect_identical(nrow(ct_rows(ct_validate(bad))), 0L)
  quoted <- rawToChar(c(charToRaw("text/plain; charset=\""), as.raw(0xe9),
                        charToRaw("\"")))
  expect_identical(nrow(ct_rows(ct_validate(quoted))), 0L)
})

test_that("ROBO-plkpmoll: us-ascii over bytes of 0x80 and above", {
  utf8 <- c(charToRaw("User-agent: *\nDisallow: /caf"), as.raw(c(0xc3, 0xa9)),
            charToRaw("\n"))
  v <- ct_validate("text/plain; charset=us-ascii", body = utf8)
  expect_identical(nrow(ct_rows(v)), 0L)
  expect_identical(v$documents$validation_status, "valid")
  latin1 <- c(charToRaw("User-agent: *\nDisallow: /caf"), as.raw(0xe9),
              charToRaw("\n"))
  v <- ct_validate("text/plain; charset=us-ascii", body = latin1)
  expect_identical(nrow(ct_rows(v)), 0L)
  expect_true("invalid_utf8" %in% v$diagnostics$code)
  bom8 <- c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(ct_rules))
  v <- ct_validate("text/plain; charset=us-ascii", body = bom8)
  expect_identical(nrow(ct_rows(v)), 0L)
})

test_that("ROBO-plkpmoll: a UTF-16 body under us-ascii", {
  wide <- c(as.raw(c(0xff, 0xfe)),
            as.vector(rbind(charToRaw(ct_rules), as.raw(0L))))
  v <- ct_validate("text/plain; charset=us-ascii", body = wide)
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
  expect_identical(nrow(ct_rows(v)), 0L)
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
  expect_identical(v$diagnostics$code, "redirect_cross_site")
})

test_that("ROBO-plkpmoll: an unavailable document gets no header row", {
  for (status in c(404L, 503L)) {
    v <- ct_validate("text/html", body = ct_html, status = status)
    expect_identical(nrow(ct_rows(v)), 0L, info = status)
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
