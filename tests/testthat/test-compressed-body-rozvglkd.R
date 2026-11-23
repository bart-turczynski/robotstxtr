# ROBO-rozvglkd: a compressed body handed to the validator draws one
# compressed_body error in place of its line rows, and a fetch row keeps the
# response's Content-Encoding. Fixtures are built here from a small
# robots.txt, never pasted as bytes, so the file stays ASCII.

# The `?x=` rule would draw rule_query_parameter_position and
# rule_query_crawl_not_index if the plaintext were read, so the skip covers
# the rule checks too.
cz_text <- paste0(
  "User-agent: *\n",
  "Disallow: /private/\n",
  "Disallow: /*?x=\n",
  "Allow: /public/\n",
  paste0("Disallow: /dir-", seq_len(40L), "/\n", collapse = "")
)

# The gzip stream gzfile() writes (1f 8b).
cz_gzip <- function(text = cz_text) {
  path <- tempfile(fileext = ".gz")
  on.exit(unlink(path))
  con <- gzfile(path, "wb")
  writeBin(charToRaw(text), con)
  close(con)
  readBin(path, "raw", file.size(path))
}

# memCompress(type = "gzip") writes a zlib stream (78 9c), not gzip.
cz_zlib <- function(text = cz_text) memCompress(charToRaw(text), "gzip")

# A zstd frame header (28 b5 2f fd) and a few frame bytes.
cz_zstd <- as.raw(c(0x28, 0xb5, 0x2f, 0xfd, 0x24, 0x10, 0x81, 0x00, 0x00))

# The codes a compressed body drew before ROBO-rozvglkd, or would draw if its
# plaintext were read.
cz_line_codes <- c(
  "no_rules", "nul_byte", "invalid_utf8", "malformed_line",
  "unknown_directive", "accepted_missing_colon", "rules_after_nul_removal",
  "rule_query_parameter_position", "rule_query_crawl_not_index",
  "utf16_or_utf32_encoding", "byte_order_mark"
)

cz_codes <- function(body) robots_validate_text(body)$diagnostics$code

test_that("ROBO-rozvglkd: the fixtures carry the signatures they stand for", {
  expect_identical(cz_gzip()[1:2], as.raw(c(0x1f, 0x8b)))
  expect_identical(cz_zlib()[1:2], as.raw(c(0x78, 0x9c)))
  expect_identical(cz_zstd[1:4], as.raw(c(0x28, 0xb5, 0x2f, 0xfd)))
  # Read as text, the plaintext draws the query rows the skip must cover.
  plain <- cz_codes(charToRaw(cz_text))
  expect_true(all(c("rule_query_parameter_position",
                    "rule_query_crawl_not_index") %in% plain))
})

test_that("ROBO-rozvglkd: each listed zlib FLG byte passes the checksum", {
  # RFC 1950: CMF * 256 + FLG is a multiple of 31, so the list is the check.
  flags <- as.integer(compressed_body_zlib_flags)
  expect_identical((0x78L * 256L + flags) %% 31L, rep(0L, 4L))
})

test_that("ROBO-rozvglkd: a gzip body gives one compressed_body error only", {
  v <- robots_validate_text(cz_gzip())
  expect_identical(v$diagnostics$code, "compressed_body")
  expect_identical(v$diagnostics$severity, "error")
  expect_false(any(cz_line_codes %in% v$diagnostics$code))
  expect_match(v$diagnostics$message, "gzip signature", fixed = TRUE)
  expect_match(v$diagnostics$message, "not read as rules", fixed = TRUE)
  expect_match(v$diagnostics$message, "curl --compressed", fixed = TRUE)
  expect_identical(v$documents$validation_status, "error")
  expect_identical(v$documents$error_count, 1L)
  expect_identical(v$documents$diagnostic_count, 1L)
})

test_that("ROBO-rozvglkd: a zlib body names zlib", {
  v <- robots_validate_text(cz_zlib())
  expect_identical(v$diagnostics$code, "compressed_body")
  expect_match(v$diagnostics$message, "zlib (deflate) signature", fixed = TRUE)
  expect_identical(v$documents$validation_status, "error")
})

test_that("ROBO-rozvglkd: a zstd body names Zstandard", {
  v <- robots_validate_text(cz_zstd)
  expect_identical(v$diagnostics$code, "compressed_body")
  expect_match(v$diagnostics$message, "Zstandard (zstd) signature",
               fixed = TRUE)
})

test_that("ROBO-rozvglkd: the document keeps byte facts, no directives", {
  body <- cz_gzip()
  doc <- robots_validate_text(body)$documents
  expect_named(doc, names(robots_validate_text("User-agent: *\n")$documents))
  expect_identical(doc$byte_size, length(body))
  expect_identical(doc$line_count, length(split_validation_lines(body)))
  expect_identical(doc$nul_byte_count, as.integer(sum(body == as.raw(0))))
  expect_identical(doc$encoding, "invalid-utf-8")
  expect_false(doc$has_bom)
  expect_identical(doc$encoding_signature, NA_character_)
  counts <- c("active_line_count", "recognized_directives",
              "unknown_directives", "malformed_lines", "user_agent_directives",
              "allow_directives", "disallow_directives", "sitemap_directives",
              "unsupported_directives")
  expect_identical(unlist(doc[counts], use.names = FALSE), rep(0L, 9L))
})

test_that("ROBO-rozvglkd: the line count matches the line splitter", {
  for (body in list(raw(0), charToRaw("a"), charToRaw("a\n"),
                    charToRaw("a\r\nb\rc\n\nd"), charToRaw("\r"),
                    cz_gzip(), cz_zlib())) {
    expect_identical(validation_line_total(body),
                     length(split_validation_lines(body)))
  }
})

test_that("ROBO-rozvglkd: text that starts like a zlib header is not flagged", {
  rules <- "\nUser-agent: *\nDisallow: /private/\n"
  # `x^` is 78 5e; valid UTF-8 text.
  expect_false("compressed_body" %in% cz_codes(charToRaw(paste0("x^", rules))))
  # 78 01 and 78 da 80 (U+0680) are well-formed UTF-8 too.
  for (head in list(as.raw(c(0x78, 0x01)), as.raw(c(0x78, 0xda, 0x80)))) {
    body <- c(head, charToRaw(rules))
    expect_true(validUTF8(rawToChar(body)))
    expect_false("compressed_body" %in% cz_codes(body))
  }
  # Not well-formed UTF-8, but a second byte that is no zlib FLG byte.
  body <- c(as.raw(c(0x78, 0x5f, 0xff)), charToRaw(rules))
  expect_false("compressed_body" %in% cz_codes(body))
  # The same `x^` head over bytes that are not UTF-8 is a zlib header.
  body <- c(as.raw(c(0x78, 0x5e, 0xff)), charToRaw(rules))
  expect_true("compressed_body" %in% cz_codes(body))
})

test_that("ROBO-rozvglkd: short and partial signatures are not flagged", {
  for (body in list(raw(0), as.raw(0x1f), as.raw(0x78), as.raw(0x28),
                    as.raw(c(0x28, 0xb5, 0x2f)), as.raw(c(0x1f, 0x41)))) {
    expect_false("compressed_body" %in% cz_codes(body))
  }
  expect_identical(cz_codes(as.raw(c(0x1f, 0x8b))), "compressed_body")
})

test_that("ROBO-rozvglkd: character input is checked too", {
  text <- rawToChar(as.raw(c(0x1f, 0x8b, 0x08, 0x41, 0x0a)))
  Encoding(text) <- "bytes"
  expect_identical(cz_codes(text), "compressed_body")
})

test_that("ROBO-rozvglkd: a cut compressed body keeps body_truncated", {
  body <- cz_gzip()
  v <- validate_document_bytes(
    body, "s", "fetch", fetch_outcome = "fetched", http_status = 200L,
    max_bytes = length(body), body_truncated = TRUE
  )
  expect_identical(v$diagnostics$code, c("compressed_body", "body_truncated"))
  expect_identical(v$document$final_newline, NA)
  expect_true(v$document$body_truncated)
  # A 2xx other than 200 keeps its acquisition row.
  v <- validate_document_bytes(
    body, "s", "fetch", fetch_outcome = "fetched", http_status = 203L,
    max_bytes = 524288L
  )
  expect_identical(v$diagnostics$code,
                   c("compressed_body", "acquisition_http_other_2xx"))
})

test_that("ROBO-rozvglkd: a cut that splits a character is still text", {
  # `x^` text whose last character (e-acute, c3 a9) the cut split.
  body <- c(charToRaw("x^ab\nUser-agent: *\nDisallow: /\n# caf"),
            as.raw(0xc3))
  cut <- validate_document_bytes(body, "s", "fetch", max_bytes = 100L,
                                 body_truncated = TRUE)
  expect_false("compressed_body" %in% cut$diagnostics$code)
  whole <- validate_document_bytes(body, "s", "fetch")
  expect_true("compressed_body" %in% whole$diagnostics$code)
})

# --- Fetched rows -------------------------------------------------------------

cz_fetch <- function(body, headers, env = parent.frame()) {
  local_fake_ssrfr(function(req) {
    fake_response(200L, headers = headers, body = body)
  }, env = env)
}

test_that("ROBO-rozvglkd: a fetch row keeps Content-Encoding raw", {
  body <- cz_gzip()
  cz_fetch(body, list(`Content-Encoding` = "GZip"))
  x <- robots_fetch("https://example.com/")
  expect_identical(x$robots$content_encoding, "GZip")
  expect_identical(
    match("content_encoding", names(x$robots)),
    match("content_flag", names(x$robots)) + 1L
  )
  # The fake transport decodes nothing, as a libcurl without zlib.
  expect_identical(x$robots$body[[1L]], body)
  v <- robots_validate_url("https://example.com/")
  expect_identical(v$diagnostics$code, "compressed_body")
})

test_that("ROBO-rozvglkd: content_encoding is NA without the header", {
  cz_fetch(charToRaw(cz_text), list())
  x <- robots_fetch("https://example.com/")
  expect_identical(x$robots$content_encoding, NA_character_)
  local_fake_ssrfr(function(req) fake_response(404L))
  x <- robots_fetch("https://example.com/")
  expect_identical(x$robots$content_encoding, NA_character_)
})

test_that("ROBO-rozvglkd: robots_compare_fetches() carries it, uncompared", {
  cz_fetch(charToRaw(cz_text), list(`Content-Encoding` = "gzip"))
  x <- robots_compare_fetches("https://example.com/", max_requests = 2)
  expect_identical(x$observations$content_encoding, "gzip")
  expect_false("content_encoding" %in% x$comparison$field)
})

test_that("ROBO-rozvglkd: frames with no response carry NA", {
  x <- allowed_by_robots_text(cz_text, "http://a/x", "b")
  expect_identical(x$robots$content_encoding, NA_character_)
  engine <- robots_evaluate_text_v1(cz_text, "http://a/", "b", "google",
                                    "google")
  legacy <- as_legacy_robots_decisions_v1(engine)
  expect_identical(legacy$robots$content_encoding, NA_character_)
  expect_named(legacy$robots, names(x$robots))
})

test_that("ROBO-rozvglkd: no charset conflict on a compressed body", {
  cz_fetch(cz_gzip(), list(`Content-Type` = "text/plain; charset=us-ascii"))
  v <- robots_validate_url("https://example.com/")
  expect_identical(v$diagnostics$code, "compressed_body")
  # The rows about the header itself stay.
  cz_fetch(cz_gzip(), list(`Content-Type` = "application/x-gzip"))
  v <- robots_validate_url("https://example.com/")
  expect_identical(v$diagnostics$code,
                   c("compressed_body", "content_type_not_text_plain"))
})

# A loopback server sending `body` with `headers` at /robots.txt; its URL.
cz_server <- function(body, headers, env = parent.frame()) {
  skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$locals$body <- body
  app$locals$headers <- headers
  app$get("/robots.txt", function(req, res) {
    for (name in names(req$app$locals$headers)) {
      res$set_header(name, req$app$locals$headers[[name]])
    }
    res$set_type("text/plain")
    res$send(req$app$locals$body)
  })
  server <- webfakes::local_app_process(app, .local_envir = env)
  url <- server$url("/robots.txt")
  port <- as.integer(sub("^http://127\\.0\\.0\\.1:([0-9]+)/.*$", "\\1", url))
  local_loopback_policy(port, env = env)
  url
}

test_that("ROBO-rozvglkd: a loopback gzip body is decoded, not flagged", {
  url <- cz_server(cz_gzip(), list("Content-Encoding" = "gzip"))
  # libcurl asked for gzip and decoded it.
  x <- robots_fetch(url, timeout = 5)
  expect_identical(x$robots$content_encoding, "gzip")
  expect_identical(x$robots$body[[1L]], charToRaw(cz_text))
  v <- robots_validate_url(url, timeout = 5)
  expect_false("compressed_body" %in% v$diagnostics$code)
})

test_that("ROBO-rozvglkd: loopback gzip bytes with no coding are flagged", {
  # The server sends gzip bytes without saying so, so libcurl stores them.
  url <- cz_server(cz_gzip(), list())
  x <- robots_fetch(url, timeout = 5)
  expect_identical(x$robots$content_encoding, NA_character_)
  v <- robots_validate_url(url, timeout = 5)
  expect_identical(v$diagnostics$code, "compressed_body")
})
