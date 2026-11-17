# ROBO-cvpkzckn: UTF-16 and UTF-32 bodies are named. `encoding` still reports
# UTF-8 byte validity only (a NUL counts as a valid one-byte character); the
# `encoding_signature` and `encoding_signature_basis` columns say which
# encoding the bytes point to and how, and a utf16_or_utf32_encoding warning
# says so in words. A byte-order mark is "bom"; without one, the heuristic
# "byte_pattern" reads the zero bytes of ASCII text in UTF-16 or UTF-32.

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
enc_encoders <- list(
  "utf-16le" = enc_utf16le, "utf-16be" = enc_utf16be,
  "utf-32le" = enc_utf32le, "utf-32be" = enc_utf32be
)

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

enc_label <- c(
  "utf-16le" = "UTF-16LE", "utf-16be" = "UTF-16BE",
  "utf-32le" = "UTF-32LE", "utf-32be" = "UTF-32BE"
)

enc_tail <- paste0(
  "; robots.txt must be UTF-8, so re-save it as UTF-8 ",
  "(RFC 9309 section 2.3)."
)

enc_bom_message <- function(label) {
  paste0("The body starts with a ", label, " byte-order mark", enc_tail)
}

enc_pattern_message <- function(label) {
  paste0(
    "The byte pattern suggests ", label, " text (heuristic; the intended ",
    "encoding cannot be known)", enc_tail
  )
}

# The signature, its basis and the new row's count, for one body.
enc_named <- function(bytes) {
  x <- robots_validate_text(bytes)
  list(
    signature = x$documents$encoding_signature,
    basis = x$documents$encoding_signature_basis,
    rows = sum(x$diagnostics$code == "utf16_or_utf32_encoding")
  )
}

enc_none <- list(signature = NA_character_, basis = NA_character_, rows = 0L)

test_that("ROBO-cvpkzckn: the code-unit helpers lay bytes out as expected", {
  expect_identical(enc_utf16le("AB"), as.raw(c(0x41, 0, 0x42, 0)))
  expect_identical(enc_utf16be("AB"), as.raw(c(0, 0x41, 0, 0x42)))
  expect_identical(enc_utf32le("A"), as.raw(c(0x41, 0, 0, 0)))
  expect_identical(enc_utf32be("A"), as.raw(c(0, 0, 0, 0x41)))
})

test_that("ROBO-cvpkzckn: BOM-less UTF-16LE is named by its byte pattern", {
  x <- robots_validate_text(enc_utf16le(enc_text))
  # encoding keeps meaning UTF-8 byte validity.
  expect_identical(x$documents$encoding, "utf-8")
  expect_false(x$documents$has_bom)
  expect_identical(x$documents$encoding_signature, "utf-16le")
  expect_identical(x$documents$encoding_signature_basis, "byte_pattern")
  expect_identical(
    enc_codes(x),
    paste0("nul_byte@1;nul_byte@2;nul_byte@3;malformed_line@1;",
           "utf16_or_utf32_encoding@NA;rules_after_nul_removal@NA")
  )
  row <- x$diagnostics[x$diagnostics$code == "utf16_or_utf32_encoding", ]
  expect_identical(row$severity, "warning")
  expect_identical(row$line, NA_integer_)
  expect_identical(row$directive, NA_character_)
  expect_identical(row$raw_text, NA_character_)
  expect_identical(row$message, enc_pattern_message("UTF-16LE"))
  expect_no_match(row$message, "Bing|Yandex")
  expect_identical(x$documents$validation_status, "error")
})

test_that("ROBO-cvpkzckn: the rows the body had before are unchanged", {
  x <- robots_validate_text(enc_utf16le(enc_text))$diagnostics
  old <- x[x$code != "utf16_or_utf32_encoding", ]
  expect_identical(
    old$code,
    c("nul_byte", "nul_byte", "nul_byte", "malformed_line",
      "rules_after_nul_removal")
  )
  expect_identical(
    old$message[[5L]],
    paste0("The NUL bytes hide 1 Allow or Disallow rule(s): Google's matcher ",
           "ends each line at its first NUL and never reads them; if this is ",
           "a UTF-16 file, re-save it as UTF-8 (RFC 9309 section 2.3).")
  )
  y <- robots_validate_text(c(enc_bom[["utf-16le"]], enc_utf16le(enc_text)))
  bad <- y$diagnostics[y$diagnostics$code == "invalid_utf8", ]
  expect_identical(bad$line, 1L)
  expect_identical(bad$message, "Line bytes are not well-formed UTF-8.")
})

test_that("ROBO-cvpkzckn: each byte-order mark names its encoding", {
  for (name in names(enc_bom)) {
    bytes <- c(enc_bom[[name]], enc_encoders[[name]](enc_text))
    x <- robots_validate_text(bytes)
    expect_identical(x$documents$encoding_signature, name, label = name)
    expect_identical(x$documents$encoding_signature_basis, "bom", label = name)
    expect_identical(x$documents$encoding, "invalid-utf-8", label = name)
    expect_false(x$documents$has_bom, label = name)
    row <- x$diagnostics[x$diagnostics$code == "utf16_or_utf32_encoding", ]
    expect_identical(row$message, enc_bom_message(enc_label[[name]]),
                     label = name)
    expect_false("byte_order_mark" %in% x$diagnostics$code, label = name)
  }
})

test_that("ROBO-cvpkzckn: a UTF-32LE mark wins over its UTF-16LE prefix", {
  x <- robots_validate_text(c(enc_bom[["utf-32le"]], enc_utf32le(enc_text)))
  expect_identical(x$documents$encoding_signature, "utf-32le")
  expect_identical(
    enc_codes(x),
    paste0("nul_byte@1;nul_byte@2;nul_byte@3;invalid_utf8@1;malformed_line@1;",
           "utf16_or_utf32_encoding@NA;rules_after_nul_removal@NA")
  )
  # The mark alone is UTF-32 too; FF FE before a UTF-16 unit is UTF-16LE.
  expect_identical(enc_named(enc_bom[["utf-32le"]])$signature, "utf-32le")
  expect_identical(enc_named(enc_bom[["utf-32be"]])$signature, "utf-32be")
  expect_identical(
    enc_named(c(enc_bom[["utf-16le"]], enc_utf16le("A")))$signature,
    "utf-16le"
  )
})

test_that("ROBO-cvpkzckn: a body too short for UTF-32 is never UTF-32", {
  bom <- function(...) list(signature = c(...), basis = "bom", rows = 1L)
  expect_identical(enc_named(as.raw(c(0xff, 0xfe))), bom("utf-16le"))
  expect_identical(enc_named(as.raw(c(0xfe, 0xff))), bom("utf-16be"))
  expect_identical(enc_named(as.raw(c(0xff, 0xfe, 0x00))), bom("utf-16le"))
  expect_identical(enc_named(as.raw(c(0x00, 0x00, 0xfe))), enc_none)
  expect_identical(enc_named(as.raw(c(0x00, 0xfe, 0xff))), enc_none)
  expect_identical(enc_named(as.raw(0xff)), enc_none)
  expect_identical(enc_named(raw()), enc_none)
})

test_that("ROBO-cvpkzckn: a mark after the start of the file is not read", {
  bytes <- c(charToRaw("User-agent: *\n"), enc_bom[["utf-16le"]],
             charToRaw("Disallow: /a\n"))
  expect_identical(enc_named(bytes), enc_none)
})

test_that("ROBO-cvpkzckn: a UTF-8 mark keeps byte_order_mark only", {
  x <- robots_validate_text(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(enc_text)))
  expect_identical(x$diagnostics$code, "byte_order_mark")
  expect_true(x$documents$has_bom)
  expect_identical(x$documents$encoding, "utf-8")
  expect_identical(x$documents$encoding_signature, "utf-8-bom")
  expect_identical(x$documents$encoding_signature_basis, "bom")
})

test_that("ROBO-cvpkzckn: BOM-less UTF-16BE and UTF-32 are named too", {
  for (name in c("utf-16be", "utf-32le", "utf-32be")) {
    x <- robots_validate_text(enc_encoders[[name]](enc_text))
    expect_identical(x$documents$encoding_signature, name, label = name)
    expect_identical(x$documents$encoding_signature_basis, "byte_pattern",
                     label = name)
    expect_identical(x$documents$encoding, "utf-8", label = name)
    row <- x$diagnostics[x$diagnostics$code == "utf16_or_utf32_encoding", ]
    expect_identical(row$message, enc_pattern_message(enc_label[[name]]),
                     label = name)
    # The row sits right before rules_after_nul_removal.
    at <- match(c("utf16_or_utf32_encoding", "rules_after_nul_removal"),
                x$diagnostics$code)
    expect_identical(diff(at), 1L, label = name)
  }
})

test_that("ROBO-cvpkzckn: the heuristic needs eight code units", {
  pattern <- list(signature = "utf-16le", basis = "byte_pattern", rows = 1L)
  expect_identical(enc_named(enc_utf16le("Allow: /")), pattern)
  expect_identical(enc_named(enc_utf16le("Allow: ")), enc_none)
  expect_identical(enc_named(as.raw(c(0x41, 0x00))), enc_none)
  expect_identical(enc_named(as.raw(c(0x41, 0x00, 0x42))), enc_none)
  expect_identical(enc_named(enc_utf32le("Allow: ")), enc_none)
  expect_identical(enc_named(enc_utf32le("Allow: /"))$signature, "utf-32le")
})

test_that("ROBO-cvpkzckn: the heuristic needs 90 percent of the units", {
  # Ten units: nine shaped as UTF-16LE ASCII and one holding two ASCII bytes
  # is named; eight of ten is not.
  nine <- c(enc_utf16le("Disallow:"), charToRaw("ab"))
  expect_identical(enc_named(nine)$signature, "utf-16le")
  eight <- c(enc_utf16le("Disallow"), charToRaw("abcd"))
  expect_identical(enc_named(eight), enc_none)
  half <- c(enc_utf16le("Disallo"), charToRaw("abcdefgh"))
  expect_identical(enc_named(half), enc_none)
})

test_that("ROBO-cvpkzckn: an odd length is not a UTF-16 body", {
  bytes <- enc_utf16le(enc_text)
  expect_identical(enc_named(bytes[-length(bytes)]), enc_none)
  expect_identical(enc_named(c(bytes, as.raw(0x41))), enc_none)
})

test_that("ROBO-cvpkzckn: NUL-cut rule files are not named", {
  cut <- robots_validate_text(c(
    charToRaw("User-agent: *\nDisallow: /a"), as.raw(0), charToRaw("b\n")
  ))
  expect_identical(cut$diagnostics$code, c("nul_byte", "rule_cut_by_nul"))
  expect_identical(cut$documents$encoding_signature, NA_character_)
  ctrl <- robots_validate_text(c(
    charToRaw("User-agent: *\nDisallow: /a"), as.raw(c(0, 1)), charToRaw("\n")
  ))
  expect_identical(ctrl$diagnostics$code, c("nul_byte", "rule_cut_by_nul"))
  expect_identical(ctrl$documents$encoding_signature, NA_character_)
  hidden <- c(charToRaw("User-agent: *"), as.raw(0),
              charToRaw("\nDisallow: /\n"))
  expect_identical(enc_named(hidden), enc_none)
  expect_identical(enc_named(as.raw(rep(0, 32))), enc_none)
})

test_that("ROBO-cvpkzckn: control bytes and binary data are not named", {
  # UTF-16LE shaped, but a unit holds 0x01: control bytes fail the test.
  ctrl <- c(enc_utf16le("Disallow: /a"), as.raw(c(0x01, 0x00)),
            enc_utf16le("\n"))
  expect_identical(enc_named(ctrl), enc_none)
  expect_identical(enc_named(rep(as.raw(c(0x1f, 0x00)), 20L)), enc_none)
  # 0x80 and above in a unit (Latin-1 text in UTF-16) is not ASCII.
  latin <- c(enc_utf16le("Disallow: /caf"), as.raw(c(0xe9, 0x00)))
  expect_identical(enc_named(latin), enc_none)
  binary <- as.raw((seq_len(512L) * 37L) %% 256L)
  expect_identical(enc_named(binary), enc_none)
})

test_that("ROBO-cvpkzckn: UTF-8, Latin-1 and invalid UTF-8 are not named", {
  utf8 <- charToRaw(enc2utf8("User-agent: *\nDisallow: /café\n"))
  expect_identical(enc_named(utf8), enc_none)
  latin1 <- c(charToRaw("User-agent: *\nDisallow: /caf"), as.raw(0xe9),
              charToRaw("\n"))
  expect_identical(enc_named(latin1), enc_none)
  expect_identical(enc_named(charToRaw(enc_text)), enc_none)
})

test_that("ROBO-cvpkzckn: the heuristic reads the first 4,096 bytes", {
  text <- enc_utf16le(strrep("# x\n", 600L))
  expect_gt(length(text), 4096L)
  # A byte past the window is not read, and the odd length is past it too.
  expect_identical(enc_named(c(text, as.raw(0x01)))$signature, "utf-16le")
  late <- c(as.raw(rep(0x41, 4096L)), enc_utf16le(enc_text))
  expect_identical(enc_named(late), enc_none)
})

test_that("ROBO-cvpkzckn: a body cut mid code unit is still named", {
  validate <- function(bytes, cut) {
    validate_document_bytes(
      bytes, source_id = "x", source_type = "fetched",
      fetch_outcome = "fetched", max_bytes = length(bytes),
      body_truncated = cut
    )$document
  }
  marked <- c(enc_bom[["utf-16le"]], enc_utf16le(enc_text))[1:21]
  doc <- validate(marked, TRUE)
  expect_identical(doc$encoding_signature, "utf-16le")
  expect_identical(doc$encoding_signature_basis, "bom")
  bare <- enc_utf16le(enc_text)[1:21]
  expect_identical(validate(bare, TRUE)$encoding_signature, "utf-16le")
  expect_identical(validate(bare, TRUE)$encoding_signature_basis,
                   "byte_pattern")
  expect_identical(validate(bare, FALSE)$encoding_signature, NA_character_)
})

test_that("ROBO-cvpkzckn: character input names no encoding", {
  marked <- c(enc_bom[["utf-16le"]], charToRaw(enc_text))
  raw_x <- robots_validate_text(marked)
  expect_identical(raw_x$documents$encoding_signature, "utf-16le")
  text <- rawToChar(marked)
  Encoding(text) <- "bytes"
  chr_x <- robots_validate_text(text)
  expect_identical(chr_x$documents$encoding_signature, NA_character_)
  expect_identical(chr_x$documents$encoding_signature_basis, NA_character_)
  expect_false("utf16_or_utf32_encoding" %in% chr_x$diagnostics$code)
  expect_identical(
    raw_x$diagnostics[raw_x$diagnostics$code != "utf16_or_utf32_encoding", ],
    chr_x$diagnostics,
    ignore_attr = TRUE
  )
  bom8 <- robots_validate_text(paste0("﻿", enc_text))
  expect_true(bom8$documents$has_bom)
  expect_identical(bom8$documents$encoding_signature, NA_character_)
  expect_identical(bom8$diagnostics$code, "byte_order_mark")
})

test_that("ROBO-cvpkzckn: a fetched body is named as a raw one is", {
  body <- enc_utf16le(enc_text)
  local_fake_ssrfr(function(req) fake_response(200L, body = body))
  z <- robots_validate_url("http://example.com/")
  x <- robots_validate_text(body)
  expect_identical(z$documents$encoding_signature, "utf-16le")
  expect_identical(z$documents$encoding_signature_basis, "byte_pattern")
  cols <- c("line", "severity", "code", "directive", "raw_text", "message")
  pick <- function(d) {
    d <- d[d$code == "utf16_or_utf32_encoding", cols]
    rownames(d) <- NULL
    d
  }
  expect_identical(pick(z$diagnostics), pick(x$diagnostics))
  expect_identical(nrow(pick(z$diagnostics)), 1L)
})

test_that("ROBO-cvpkzckn: an unfetched document carries NA columns", {
  body <- enc_utf16le(enc_text)
  local_fake_ssrfr(function(req) {
    if (startsWith(req$url, "http://a.example/")) {
      fake_response(200L, body = body)
    } else {
      fake_response(404L)
    }
  })
  z <- robots_validate_url(c("http://a.example/", "http://b.example/"))
  expect_identical(nrow(z$documents), 2L)
  expect_identical(z$documents$encoding_signature, c("utf-16le", NA))
  expect_identical(z$documents$encoding_signature_basis,
                   c("byte_pattern", NA))
  empty <- empty_validation_documents()
  expect_true(all(c("encoding_signature", "encoding_signature_basis") %in%
                    names(empty)))
  expect_identical(empty$encoding_signature, character())
})
