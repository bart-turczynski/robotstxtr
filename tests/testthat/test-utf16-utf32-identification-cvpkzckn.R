# ROBO-cvpkzckn: UTF-16 and UTF-32 bodies. These pins record what the
# validator says about them before it identifies them: `encoding` reports UTF-8
# byte validity only, and a NUL counts as a valid one-byte character.

enc_text <- "User-agent: *\nDisallow: /a\n"

# ASCII text as UTF-16 or UTF-32 code units, with no byte-order mark.
enc_units <- function(text, width, big_endian) {
  bytes <- charToRaw(text)
  pad <- rep(list(as.raw(0)), width - 1L)
  rows <- if (big_endian) c(pad, list(bytes)) else c(list(bytes), pad)
  as.vector(do.call(rbind, lapply(rows, rep_len, length(bytes))))
}
enc_utf16le <- function(text) enc_units(text, 2L, FALSE)
enc_utf16be <- function(text) enc_units(text, 2L, TRUE)
enc_utf32le <- function(text) enc_units(text, 4L, FALSE)
enc_utf32be <- function(text) enc_units(text, 4L, TRUE)

enc_bom <- list(
  "utf-16le" = as.raw(c(0xff, 0xfe)),
  "utf-16be" = as.raw(c(0xfe, 0xff)),
  "utf-32le" = as.raw(c(0xff, 0xfe, 0x00, 0x00)),
  "utf-32be" = as.raw(c(0x00, 0x00, 0xfe, 0xff))
)

enc_codes <- function(x) {
  d <- x$diagnostics
  paste(sprintf("%s@%s", d$code, ifelse(is.na(d$line), "NA", d$line)),
        collapse = ";")
}

test_that("ROBO-cvpkzckn: the code-unit helpers lay bytes out as expected", {
  expect_identical(enc_utf16le("AB"), as.raw(c(0x41, 0, 0x42, 0)))
  expect_identical(enc_utf16be("AB"), as.raw(c(0, 0x41, 0, 0x42)))
  expect_identical(enc_utf32le("A"), as.raw(c(0x41, 0, 0, 0)))
  expect_identical(enc_utf32be("A"), as.raw(c(0, 0, 0, 0x41)))
})

test_that("ROBO-cvpkzckn: BOM-less UTF-16LE reads as UTF-8 and is not named", {
  x <- robots_validate_text(enc_utf16le(enc_text))
  expect_identical(x$documents$encoding, "utf-8")
  expect_false(x$documents$has_bom)
  expect_false("encoding_signature" %in% names(x$documents))
  expect_identical(
    enc_codes(x),
    paste0("nul_byte@1;nul_byte@2;nul_byte@3;malformed_line@1;",
           "rules_after_nul_removal@NA")
  )
})

test_that("ROBO-cvpkzckn: a UTF-32LE BOM is only invalid UTF-8 and NULs", {
  x <- robots_validate_text(c(enc_bom[["utf-32le"]], enc_utf32le(enc_text)))
  expect_identical(x$documents$encoding, "invalid-utf-8")
  expect_false(x$documents$has_bom)
  expect_false("encoding_signature" %in% names(x$documents))
  expect_identical(
    enc_codes(x),
    paste0("nul_byte@1;nul_byte@2;nul_byte@3;invalid_utf8@1;malformed_line@1;",
           "rules_after_nul_removal@NA")
  )
  bare <- robots_validate_text(enc_bom[["utf-32le"]])
  expect_identical(enc_codes(bare),
                   "nul_byte@1;invalid_utf8@1;malformed_line@1;no_rules@NA")
})

test_that("ROBO-cvpkzckn: no UTF-16 or UTF-32 body is identified today", {
  bodies <- list(
    "utf-16be" = enc_utf16be(enc_text),
    "utf-32le" = enc_utf32le(enc_text),
    "utf-32be" = enc_utf32be(enc_text),
    "utf-16le bom" = c(enc_bom[["utf-16le"]], enc_utf16le(enc_text)),
    "utf-16be bom" = c(enc_bom[["utf-16be"]], enc_utf16be(enc_text)),
    "utf-32be bom" = c(enc_bom[["utf-32be"]], enc_utf32be(enc_text))
  )
  for (label in names(bodies)) {
    x <- robots_validate_text(bodies[[label]])
    expect_false("encoding_signature" %in% names(x$documents), label = label)
    expect_false("utf16_or_utf32_encoding" %in% x$diagnostics$code,
                 label = label)
  }
})
