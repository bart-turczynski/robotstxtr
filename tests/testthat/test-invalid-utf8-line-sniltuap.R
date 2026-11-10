# ROBO-sniltuap: invalid UTF-8 is reported on each line that holds it, as
# the invalid_utf8 error when the bytes reach a key or value, and as the
# invalid_utf8_comment warning when they all sit after the line's first `#`,
# where the parser cuts the line.

iu_bytes <- function(...) {
  parts <- list(...)
  unlist(lapply(parts, function(p) {
    if (is.character(p)) charToRaw(p) else as.raw(p)
  }), use.names = FALSE)
}

iu_rows <- function(bytes) {
  robots_validate_text(bytes)$diagnostics
}

test_that("a Latin-1 byte in a full-line comment is a line warning", {
  x <- robots_validate_text(iu_bytes("# caf", 0xe9, "\nUser-agent: *\n",
                                     "Disallow: /a\n"))
  expect_identical(x$diagnostics$code, "invalid_utf8_comment")
  expect_identical(x$diagnostics$line, 1L)
  expect_identical(x$diagnostics$severity, "warning")
  expect_identical(x$diagnostics$raw_text, "# caf\\xE9")
  expect_identical(x$documents$validation_status, "warning")
  expect_identical(x$documents$encoding, "invalid-utf-8")
})

test_that("a Latin-1 byte in a rule value is a line error", {
  x <- robots_validate_text(iu_bytes("User-agent: *\nDisallow: /caf", 0xe9,
                                     "\n"))
  expect_identical(x$diagnostics$code, "invalid_utf8")
  expect_identical(x$diagnostics$line, 2L)
  expect_identical(x$diagnostics$severity, "error")
  expect_identical(x$diagnostics$raw_text, "Disallow: /caf\\xE9")
  expect_identical(x$documents$validation_status, "error")
  expect_identical(x$documents$encoding, "invalid-utf-8")
})

test_that("a Latin-1 byte in a key is a line error", {
  d <- iu_rows(iu_bytes("User-agent: *\nDis", 0xe9, "llow: /a\n"))
  expect_identical(d$code[d$code %in% c("invalid_utf8",
                                        "invalid_utf8_comment")],
                   "invalid_utf8")
  expect_identical(d$line[d$code == "invalid_utf8"], 2L)
})

test_that("a trailing comment is found by its #, not by is_comment", {
  d <- iu_rows(iu_bytes("User-agent: *\nDisallow: /a # caf", 0xe9, "\n"))
  expect_identical(d$code, "invalid_utf8_comment")
  expect_identical(d$line, 2L)
})

test_that("bad bytes before the # make the line an error", {
  d <- iu_rows(iu_bytes("User-agent: *\nDisallow: /caf", 0xe9, " # caf",
                        0xe9, "\n"))
  expect_identical(d$code, "invalid_utf8")
  expect_identical(d$line, 2L)
  # A truncated lead byte right before the #.
  d <- iu_rows(iu_bytes("User-agent: *\nDisallow: /a", 0xc3, "#\n"))
  expect_identical(d$code, "invalid_utf8")
  expect_identical(d$line, 2L)
})

test_that("NUL bytes are dropped before the line is checked", {
  d <- iu_rows(iu_bytes("User-agent: *\nDisallow: /x", 0x00, 0xff, "\n"))
  expect_identical(d$code, c("nul_byte", "invalid_utf8"))
  expect_identical(d$line, c(2L, 2L))
  # A NUL between a lead and a continuation byte: the matchers drop it and
  # read a well-formed character.
  d <- iu_rows(iu_bytes("User-agent: *\nDisallow: /", 0xc3, 0x00, 0xa9,
                        "\n"))
  expect_identical(d$code, "nul_byte")
  # A NUL before the #: the # is still found on the NUL-free line.
  d <- iu_rows(iu_bytes("User-agent: *\nDisallow: /a", 0x00, "# ", 0xff,
                        "\n"))
  expect_identical(d$code, c("nul_byte", "invalid_utf8_comment"))
})

test_that("several bad lines get one row each, in line order", {
  d <- iu_rows(iu_bytes("# ", 0xff, "\nUser-agent: *\nDisallow: /", 0xe9,
                        "\n# ok\nAllow: /", 0xfe, " # ", 0xfe, "\n"))
  expect_identical(d$code,
                   c("invalid_utf8_comment", "invalid_utf8", "invalid_utf8"))
  expect_identical(d$line, c(1L, 3L, 5L))
  expect_identical(d$severity, c("warning", "error", "error"))
})

test_that("thousands of bad lines give one row each, in line order", {
  n <- 30000L
  rules <- unlist(lapply(seq_len(n), function(i) {
    c(charToRaw(sprintf("Disallow: /p%05d", i)), as.raw(c(0xe9, 0x0a)))
  }), use.names = FALSE)
  d <- iu_rows(c(charToRaw("User-agent: *\n# "), as.raw(0xff),
                 charToRaw("\n"), rules))
  bad <- d[d$code %in% c("invalid_utf8", "invalid_utf8_comment"), ]
  expect_identical(nrow(bad), n + 1L)
  expect_identical(bad$line, seq_len(n + 1L) + 1L)
  expect_identical(bad$code, c("invalid_utf8_comment",
                               rep("invalid_utf8", n)))
  expect_identical(bad$raw_text[c(2L, n + 1L)],
                   c("Disallow: /p00001\\xE9", "Disallow: /p30000\\xE9"))
})

test_that("line numbers follow CR, CRLF and LF separators alike", {
  for (sep in c("\n", "\r", "\r\n")) {
    body <- iu_bytes("User-agent: *", sep, "Disallow: /a", sep, "# ", 0xe9,
                     sep, "Disallow: /", 0xe9, sep)
    d <- iu_rows(body)
    expect_identical(d$code, c("invalid_utf8_comment", "invalid_utf8"),
                     label = sep)
    expect_identical(d$line, c(3L, 4L), label = sep)
  }
})

test_that("a UTF-16 byte-order mark lands on line 1", {
  for (bom in list(c(0xff, 0xfe), c(0xfe, 0xff))) {
    d <- iu_rows(iu_bytes(bom, "User-agent: *\nDisallow: /a\n"))
    expect_identical(d$line[d$code == "invalid_utf8"], 1L)
  }
})

test_that("a bad byte past the parser's line buffer is still reported", {
  long <- strrep("a", 17000L)
  d <- iu_rows(iu_bytes("User-agent: *\nDisallow: /", long, 0xe9, "\n"))
  expect_identical(d$code, c("invalid_utf8", "line_too_long"))
  expect_identical(d$line, c(2L, 2L))
})

test_that("well-formed and empty bodies get no encoding row", {
  x <- robots_validate_text(iu_bytes("User-agent: *\nDisallow: /caf", 0xc3,
                                     0xa9, " # caf", 0xc3, 0xa9, "\n"))
  expect_identical(nrow(x$diagnostics), 0L)
  expect_identical(x$documents$encoding, "utf-8")
  x <- robots_validate_text(raw())
  expect_false(any(c("invalid_utf8", "invalid_utf8_comment") %in%
                     x$diagnostics$code))
  expect_identical(x$documents$encoding, "utf-8")
})
