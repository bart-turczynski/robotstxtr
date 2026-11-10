# ROBO-atkmqcov: a UTF-8 byte-order mark after the start of the file.
#
# The Google-compatible parser skips one BOM at byte 0 only. A BOM anywhere
# else that starts a line's content stays at the start of its key, so the
# directive on that line is not read. misplaced_byte_order_mark names it.

bom <- as.raw(c(0xef, 0xbb, 0xbf))
ua_star <- charToRaw("User-agent: *\nDisallow: /x\n")

bom_fixture <- function(id) {
  path <- test_path("fixtures", "edge-cases", paste0(id, ".hex"))
  hex <- gsub("[[:space:]]", "", paste(readLines(path), collapse = ""))
  starts <- seq(1L, nchar(hex), by = 2L)
  as.raw(strtoi(substring(hex, starts, starts + 1L), 16L))
}

bom_format <- function(d) {
  paste(sprintf("%s@%s", d$code, ifelse(is.na(d$line), "NA", d$line)),
        collapse = ";")
}

bom_codes <- function(bytes) {
  bom_format(robots_validate_text(bytes)$diagnostics)
}

bom_hits <- function(bytes) {
  d <- robots_validate_text(bytes)$diagnostics
  d[d$code == "misplaced_byte_order_mark", , drop = FALSE]
}

test_that("ROBO-atkmqcov: the catalog fixtures name the misplaced BOM", {
  expect_identical(
    bom_codes(bom_fixture("enc-bom-mid-file")),
    "misplaced_byte_order_mark@2;unknown_directive@2;no_rules@NA"
  )
  expect_identical(
    bom_codes(bom_fixture("enc-bom-before-user-agent")),
    "misplaced_byte_order_mark@4;unknown_directive@4"
  )
  expect_identical(
    bom_codes(bom_fixture("enc-bom-doubled")),
    paste0("byte_order_mark@1;misplaced_byte_order_mark@1;",
           "unknown_directive@1;rule_without_user_agent@2;",
           "missing_user_agent@NA")
  )
  # The one BOM at byte 0 is the parser's to skip, not misplaced.
  expect_identical(bom_codes(bom_fixture("enc-bom-start")),
                   "byte_order_mark@1")
})

test_that("ROBO-atkmqcov: the message names the directive the BOM hides", {
  hit <- bom_hits(bom_fixture("enc-bom-before-user-agent"))
  expect_identical(hit$severity, "warning")
  expect_identical(hit$directive, "user-agent")
  expect_match(hit$message, "This User-agent line is not read")
  expect_match(hit$message, "stay with the group before it")

  # A visible User-agent after the hidden one starts the next group: the
  # message says the lines stay only until then. Here /y belongs to c.
  bytes <- c(charToRaw("User-agent: a\nDisallow: /x\n"), bom,
             charToRaw("User-agent: b\nUser-agent: c\nDisallow: /y\n"))
  hit <- bom_hits(bytes)
  expect_identical(hit$line, 3L)
  expect_match(
    hit$message,
    paste0("the parser starts no group here, so the lines after it stay ",
           "with the group before it, or with no group, until the next ",
           "User-agent line."),
    fixed = TRUE
  )
  allowed <- function(token) {
    allowed_by_robots_text(rawToChar(bytes), "https://example.com/y",
                           token)$results$allowed
  }
  expect_false(allowed("c"))
  expect_true(allowed("a"))

  hit <- bom_hits(bom_fixture("enc-bom-mid-file"))
  expect_identical(hit$directive, "disallow")
  expect_match(hit$message, "This Disallow line is not read.", fixed = TRUE)

  # A typo spelling is still a User-agent once the BOM is gone.
  hit <- bom_hits(c(ua_star, bom, charToRaw("useragent: FooBot\n")))
  expect_identical(hit$directive, "user-agent")
  expect_match(hit$message, "User-agent")

  hit <- bom_hits(c(ua_star, bom,
                    charToRaw("Sitemap: https://example.com/s\n")))
  expect_identical(hit$directive, "sitemap")

  # A directive the profile does not read gets the generic message.
  hit <- bom_hits(c(ua_star, bom, charToRaw("Crawl-delay: 5\n")))
  expect_identical(hit$directive, NA_character_)
  expect_no_match(hit$message, "line is not read")
})

test_that("ROBO-atkmqcov: the hidden directive is read past the BOM only", {
  # The doubled fixture: the second BOM, right after the skipped one, hides
  # User-agent; the re-parse sees the line without either BOM.
  hit <- bom_hits(bom_fixture("enc-bom-doubled"))
  expect_identical(hit$directive, "user-agent")
  expect_match(hit$message, "This User-agent line is not read")
  # Blanks before the BOM: the re-parse starts after the BOM, not at the
  # line's first byte, which would leave the BOM in the key.
  hit <- bom_hits(c(ua_star, charToRaw(" \t"), bom,
                    charToRaw("User-agent: FooBot\n")))
  expect_identical(hit$directive, "user-agent")
  expect_match(hit$message, "This User-agent line is not read")
  # Line 1 after the skipped BOM: blanks, then a second BOM. The offset must
  # pass over the skipped BOM, or the re-parse keeps the second BOM.
  hit <- bom_hits(c(bom, charToRaw("  "), bom,
                    charToRaw("User-agent: *\nDisallow: /a\n")))
  expect_identical(hit$line, 1L)
  expect_identical(hit$directive, "user-agent")
  expect_match(hit$message, "This User-agent line is not read")
})

test_that("ROBO-atkmqcov: a BOM after leading blanks or on a CRLF line", {
  expect_identical(
    bom_codes(c(ua_star, charToRaw("  \t"), bom, charToRaw("Allow: /a\n"))),
    "misplaced_byte_order_mark@3;unknown_directive@3"
  )
  # VT and FF are blanks the parser strips too (AsciiIsSpace in robots.cc).
  expect_identical(
    bom_codes(c(ua_star, as.raw(c(0x0b, 0x0c)), bom,
                charToRaw("Allow: /a\n"))),
    "misplaced_byte_order_mark@3;unknown_directive@3"
  )
  expect_identical(
    bom_codes(c(charToRaw("User-agent: *\r\nDisallow: /x\r\n"), bom,
                charToRaw("Allow: /a\r\n"))),
    "misplaced_byte_order_mark@3;unknown_directive@3"
  )
})

test_that("ROBO-atkmqcov: a BOM on a comment or an empty line is reported", {
  # Both lines turn active: the BOM is a key with no colon.
  hit <- bom_hits(c(ua_star, bom, charToRaw("# x\n")))
  expect_identical(hit$line, 3L)
  expect_match(hit$message, "comment line is read as an active line")
  expect_identical(
    bom_codes(c(ua_star, bom, charToRaw("\n"))),
    "misplaced_byte_order_mark@3;malformed_line@3"
  )
})

test_that("ROBO-atkmqcov: a BOM that does not start the key is not counted", {
  expect_identical(bom_codes(c(ua_star, charToRaw("Allow: /a"), bom,
                               charToRaw("\n"))), "")
  expect_identical(bom_codes(c(ua_star, charToRaw("Allow: /a"), bom,
                               charToRaw("b\n"))), "")
  expect_identical(bom_codes(c(ua_star, charToRaw("Al"), bom,
                               charToRaw("low: /a\n"))),
                   "unknown_directive@3")
  # Two BOM bytes at a line's end are not a BOM.
  expect_false("misplaced_byte_order_mark" %in% robots_validate_text(
    c(ua_star, bom[1:2])
  )$diagnostics$code)
})

test_that("ROBO-atkmqcov: empty, BOM-only, NUL and non-UTF-8 bodies", {
  expect_identical(bom_codes(raw()), "no_rules@NA")
  expect_identical(bom_codes(bom), "byte_order_mark@1;no_rules@NA")
  # A NUL on another line: the scan reads raw bytes and does not error.
  x <- robots_validate_text(c(ua_star, as.raw(c(0x41, 0x00, 0x0a)), bom,
                              charToRaw("Allow: /y\n")))$diagnostics
  expect_identical(x$line[x$code == "misplaced_byte_order_mark"], 4L)
  # A Latin-1 byte on the BOM's own line does not hide the BOM.
  hit <- bom_hits(c(charToRaw("User-agent: *\n"), bom,
                    charToRaw("Disallow: /a"), as.raw(0xe9),
                    charToRaw("\n")))
  expect_identical(hit$line, 2L)
  expect_identical(hit$directive, "disallow")
})

test_that("ROBO-atkmqcov: a truncated body is scanned up to its last line", {
  bytes <- c(ua_star, bom, charToRaw("Allow: /y\n"), bom,
             charToRaw("Allow: /z"))
  d <- validate_document_bytes(bytes, "s", "url", body_truncated = TRUE)
  expect_identical(d$diagnostics$line[
    d$diagnostics$code == "misplaced_byte_order_mark"
  ], 3L)
})
