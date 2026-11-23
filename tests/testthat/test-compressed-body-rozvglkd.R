# ROBO-rozvglkd: a compressed body handed to the validator. Fixtures are built
# here from a small robots.txt, never pasted as bytes, so the file stays ASCII.

cz_text <- paste0(
  "User-agent: *\n",
  "Disallow: /private/\n",
  "Disallow: /*?x=\n",
  "Allow: /public/\n"
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

test_that("ROBO-rozvglkd: the fixtures carry the signatures they stand for", {
  expect_identical(cz_gzip()[1:2], as.raw(c(0x1f, 0x8b)))
  expect_identical(cz_zlib()[1:2], as.raw(c(0x78, 0x9c)))
  expect_identical(cz_zstd[1:4], as.raw(c(0x28, 0xb5, 0x2f, 0xfd)))
})

test_that("ROBO-rozvglkd: pinned, a compressed body is read as lines", {
  for (body in list(cz_gzip(), cz_zlib(), cz_zstd)) {
    v <- robots_validate_text(body)
    codes <- v$diagnostics$code
    expect_false("compressed_body" %in% codes)
    expect_true(all(c("invalid_utf8", "no_rules") %in% codes))
  }
})

test_that("ROBO-rozvglkd: pinned, fetch rows have no content_encoding", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, headers = list(`Content-Encoding` = "gzip"),
                  body = cz_gzip())
  })
  x <- robots_fetch("https://example.com/")
  expect_false("content_encoding" %in% names(x$robots))
  expect_identical(x$robots$body[[1L]], cz_gzip())
})
