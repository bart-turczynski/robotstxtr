# ROBO-qxcwxtbm: with `unicode_advisories = TRUE` the validator adds info rows
# for three narrow indicators in the raw value of an active Allow or Disallow
# line: U+FFFD (rule_replacement_character), an invisible or formatting
# character (rule_invisible_character) and two or more sequences that read
# like UTF-8 decoded as Latin-1 (rule_possible_mojibake). The default adds
# nothing, and the rows never change the status or a match.
#
# Non-ASCII text is built from code points with ua_chr(), so this file stays
# ASCII (R also refuses bidi controls written as \u escapes).

ua_chr <- function(...) intToUtf8(c(...))

ua_tail <- paste0(
  "Valid UTF-8 can neither prove nor disprove corruption; this advisory ",
  "changes no match."
)
ua_invisible_tail <- paste0(
  ". They may be meant, but they are easy to paste unseen, and the matcher ",
  "compares them byte for byte, so a URL without them may not match. ",
  ua_tail
)
ua_codes <- c(
  "rule_replacement_character", "rule_invisible_character",
  "rule_possible_mojibake"
)

ua_replacement_message <- function(at) {
  paste0(
    "Pattern holds the replacement character: U+FFFD first at byte ", at,
    ". A decoder writes it for bytes it could not read, so an earlier ",
    "conversion may have lost the original characters, or it may be meant. ",
    ua_tail
  )
}

ua_invisible_message <- function(items) {
  lead <- if (length(items) == 1L) {
    "Pattern holds an invisible or formatting character: "
  } else {
    "Pattern holds invisible or formatting characters: "
  }
  paste0(lead, toString(items), ua_invisible_tail)
}

ua_mojibake_message <- function(items) {
  paste0(
    "Pattern holds sequences that read like UTF-8 decoded as Latin-1 and ",
    "encoded again (possible mojibake): ", toString(items),
    ". This is a heuristic: the text may be meant as written and its ",
    "original cannot be known. ", ua_tail
  )
}

# One rule line after a User-agent line, as UTF-8 text.
ua_body <- function(...) {
  enc2utf8(paste0("User-agent: *\n", ..., "\n"))
}

ua_rows <- function(x) {
  x$diagnostics[x$diagnostics$code %in% ua_codes, , drop = FALSE]
}

# The opt-in run on the same input as the default run adds only advisory
# rows: every other row, and the document row but for diagnostic_count, are
# identical.
ua_expect_adds_only <- function(input, label) {
  off <- robots_validate_text(input)
  on <- robots_validate_text(input, unicode_advisories = TRUE)
  added <- on$diagnostics$code %in% ua_codes
  kept <- on$diagnostics[!added, , drop = FALSE]
  rownames(kept) <- NULL
  expect_identical(kept, off$diagnostics, label = label)
  expect_identical(on$documents$diagnostic_count,
                   off$documents$diagnostic_count + sum(added), label = label)
  on$documents$diagnostic_count <- off$documents$diagnostic_count
  expect_identical(on$documents, off$documents, label = label)
}

ua_expect_silent <- function(input, label) {
  off <- robots_validate_text(input)
  on <- robots_validate_text(input, unicode_advisories = TRUE)
  expect_identical(on$diagnostics, off$diagnostics, label = label)
  expect_identical(on$documents, off$documents, label = label)
}

test_that("ROBO-qxcwxtbm: the default reports nothing for U+200B or U+FFFD", {
  for (point in c(0x200b, 0xfffd)) {
    body <- ua_body("Disallow: /a", ua_chr(point), "b")
    label <- sprintf("U+%04X", point)
    x <- robots_validate_text(body)
    expect_identical(nrow(x$diagnostics), 0L, label = label)
    expect_identical(x$documents$validation_status, "valid", label = label)
    expect_identical(
      robots_validate_text(body, unicode_advisories = FALSE), x,
      label = label
    )
    expect_false(attr(x, "unicode_advisories"))
  }
})

test_that("ROBO-qxcwxtbm: the opt-in records itself on the result", {
  x <- robots_validate_text(ua_body("Disallow: /a"), unicode_advisories = TRUE)
  expect_true(attr(x, "unicode_advisories"))
  expect_identical(attr(x, "validation_profile"), "google-parser-compatible")
  expect_identical(nrow(x$diagnostics), 0L)
})

test_that("ROBO-qxcwxtbm: U+200B and U+FFFD give info rows, still valid", {
  x <- robots_validate_text(
    ua_body("Disallow: /a", ua_chr(0x200b), "b"), unicode_advisories = TRUE
  )
  expect_identical(x$diagnostics$code, "rule_invisible_character")
  expect_identical(x$diagnostics$line, 2L)
  expect_identical(x$diagnostics$severity, "info")
  expect_identical(x$diagnostics$directive, "disallow")
  expect_identical(x$diagnostics$raw_text, "Disallow: /a\\xE2\\x80\\x8Bb")
  expect_identical(
    x$diagnostics$message, ua_invisible_message("U+200B first at byte 3")
  )
  expect_identical(x$documents$validation_status, "valid")
  expect_identical(x$documents$warning_count, 0L)

  x <- robots_validate_text(
    ua_body("Allow: /a", ua_chr(0xfffd), "b", ua_chr(0xfffd)),
    unicode_advisories = TRUE
  )
  expect_identical(x$diagnostics$code, "rule_replacement_character")
  expect_identical(x$diagnostics$severity, "info")
  expect_identical(x$diagnostics$directive, "allow")
  expect_identical(x$diagnostics$message, ua_replacement_message(3L))
  expect_identical(x$documents$validation_status, "valid")
})

test_that("ROBO-qxcwxtbm: each invisible or formatting family is reported", {
  points <- c(0x2066, 0x00ad, 0x0085, 0x009f, 0x0080, 0xfeff, 0x200b,
              0x200f, 0x202a, 0x202e, 0x2060, 0x2064, 0x2069)
  for (point in points) {
    label <- sprintf("U+%04X", point)
    x <- robots_validate_text(
      ua_body("Disallow: /a", ua_chr(point), "b"), unicode_advisories = TRUE
    )
    expect_identical(x$diagnostics$code, "rule_invisible_character",
                     label = label)
    expect_identical(
      x$diagnostics$message,
      ua_invisible_message(paste(label, "first at byte 3")),
      label = label
    )
  }
  # Neighbors just outside each range stay silent.
  for (point in c(0x00ac, 0x00a0, 0x00a1, 0x200a, 0x2010, 0x2029, 0x202f,
                  0x2065, 0x206a, 0xfefe)) {
    ua_expect_silent(ua_body("Disallow: /a", ua_chr(point), "b"),
                     sprintf("U+%04X", point))
  }
})

test_that("ROBO-qxcwxtbm: two mojibake sequences in a value are reported", {
  # "resume" with two e-acute, each read as Latin-1: U+00C3 U+00A9.
  x <- robots_validate_text(
    ua_body("Disallow: /r", ua_chr(0xc3, 0xa9), "sum", ua_chr(0xc3, 0xa9)),
    unicode_advisories = TRUE
  )
  expect_identical(x$diagnostics$code, "rule_possible_mojibake")
  expect_identical(x$diagnostics$severity, "info")
  expect_identical(x$diagnostics$directive, "disallow")
  expect_identical(
    x$diagnostics$message,
    ua_mojibake_message(c("U+00C3 U+00A9 at byte 3",
                          "U+00C3 U+00A9 at byte 10"))
  )
  # A three-byte original: U+2019 (E2 80 99) read as Latin-1 is U+00E2
  # U+0080 U+0099, whose C1 controls are invisible characters too.
  x <- robots_validate_text(
    ua_body("Disallow: /it", ua_chr(0xe2, 0x80, 0x99), "s/",
            ua_chr(0xc3, 0xbc)),
    unicode_advisories = TRUE
  )
  expect_identical(
    x$diagnostics$code,
    c("rule_invisible_character", "rule_possible_mojibake")
  )
  expect_identical(
    x$diagnostics$message[[1L]],
    ua_invisible_message(c("U+0080 first at byte 6", "U+0099 first at byte 8"))
  )
  expect_identical(
    x$diagnostics$message[[2L]],
    ua_mojibake_message(c("U+00E2 U+0080 U+0099 at byte 4",
                          "U+00C3 U+00BC at byte 12"))
  )
  expect_identical(x$documents$validation_status, "valid")
})

test_that("ROBO-qxcwxtbm: intended non-ASCII paths stay silent", {
  values <- list(
    c("/caf", ua_chr(0xe9)),
    c("/", ua_chr(0x65e5, 0x672c, 0x8a9e)),
    c("/na", ua_chr(0xef), "ve"),
    # One sequence alone is too weak a sign.
    c("/caf", ua_chr(0xc3, 0xa9)),
    # Latin-1 letters that would not decode to well-formed UTF-8.
    c("/", ua_chr(0xc3, 0xc3)),
    c("/", ua_chr(0xc3), "a", ua_chr(0xc3), "b"),
    c("/", ua_chr(0xc3, 0xc0), "x", ua_chr(0xc3, 0xff)),
    c("/", ua_chr(0xe0, 0xa0, 0xe0, 0xa0)),
    # Typed escapes are ASCII in the file.
    "/a%E2%80%8Bb", "/a%EF%BF%BDb", "/a%e2%80%8bb"
  )
  for (value in values) {
    value <- paste(value, collapse = "")
    ua_expect_silent(ua_body("Disallow: ", value), value)
  }
})

test_that("ROBO-qxcwxtbm: lines and bytes no rule reads stay silent", {
  zwsp <- ua_chr(0x200b)
  ua_expect_silent(
    ua_body("Disallow: /a # ", zwsp, " ", ua_chr(0xfffd)), "comment"
  )
  ua_expect_silent(ua_body("Disallow: /a#", zwsp), "glued comment")
  ua_expect_silent(ua_body("# Disallow: /a", zwsp), "comment line")
  ua_expect_silent(ua_body("User-agent: bot", zwsp), "user-agent")
  ua_expect_silent(
    ua_body("Sitemap: https://example.com/s", zwsp, ".xml"), "sitemap"
  )
  ua_expect_silent(ua_body("Crawl-delay: 1", zwsp), "unknown")
  ua_expect_silent(
    c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0),
      charToRaw(zwsp), charToRaw("\n")),
    "after NUL"
  )
  # An ASCII control byte is rule_control_character's alone.
  ua_expect_silent(
    c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(1), charToRaw("\n")),
    "ASCII control"
  )
  # A latin1-marked string is converted to UTF-8 first.
  latin1 <- "User-agent: *\nDisallow: /caf\xe9\n"
  Encoding(latin1) <- "latin1"
  ua_expect_silent(latin1, "latin1")
  # UTF-16LE: each line ends at its first NUL.
  utf16 <- iconv(ua_body("Disallow: /a", zwsp, "b"), "UTF-8", "UTF-16LE",
                 toRaw = TRUE)[[1L]]
  ua_expect_silent(utf16, "UTF-16LE")
})

test_that("ROBO-qxcwxtbm: invalid UTF-8 keeps invalid_utf8 and no advisory", {
  body <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0xff),
            charToRaw(ua_chr(0x200b, 0xfffd)), charToRaw("\n"))
  ua_expect_silent(body, "invalid")
  x <- robots_validate_text(body, unicode_advisories = TRUE)
  expect_identical(x$diagnostics$code, "invalid_utf8")
})

test_that("ROBO-qxcwxtbm: raw and character input give the same rows", {
  text <- ua_body(
    "Disallow: /", ua_chr(0xc3, 0xa9), "t", ua_chr(0xc3, 0xa9),
    ua_chr(0x200b, 0xfffd)
  )
  from_text <- robots_validate_text(text, unicode_advisories = TRUE)
  from_raw <- robots_validate_text(charToRaw(text), unicode_advisories = TRUE)
  expect_identical(
    from_text$diagnostics$code,
    c("rule_replacement_character", "rule_invisible_character",
      "rule_possible_mojibake")
  )
  expect_identical(from_raw$diagnostics, from_text$diagnostics)
  ua_expect_adds_only(text, "mixed")
})

test_that("ROBO-qxcwxtbm: a fetched body gives the same rows", {
  text <- ua_body("Disallow: /a", ua_chr(0x200b), "b", ua_chr(0xfffd))
  local_fake_ssrfr(function(req) {
    fake_response(200L, headers = list(`Content-Type` = "text/html"),
                  body = charToRaw(text))
  })
  on <- robots_validate_url("https://example.com/", unicode_advisories = TRUE)
  expect_true(attr(on, "unicode_advisories"))
  supplied <- robots_validate_text(text, unicode_advisories = TRUE)
  expect_identical(
    on$diagnostics$code,
    c(supplied$diagnostics$code, "content_type_not_text_plain")
  )
  expect_identical(
    on$diagnostics$message[seq_len(2L)], supplied$diagnostics$message
  )
  expect_identical(on$documents$validation_status, "warning")

  off <- robots_validate_url("https://example.com/")
  expect_false(attr(off, "unicode_advisories"))
  expect_identical(off$diagnostics$code, "content_type_not_text_plain")
})

test_that("ROBO-qxcwxtbm: a leading U+200B or U+FEFF is the slash row's", {
  slash <- function(x) {
    x$diagnostics$message[x$diagnostics$code == "rule_missing_leading_slash"]
  }
  for (point in c(0x200b, 0xfeff)) {
    lead <- ua_chr(point)
    label <- sprintf("U+%04X", point)
    x <- robots_validate_text(
      ua_body("Disallow: ", lead, "/a"), unicode_advisories = TRUE
    )
    expect_identical(x$diagnostics$code, "rule_missing_leading_slash",
                     label = label)
    expect_match(slash(x), paste0("invisible character (", label, ")"),
                 fixed = TRUE)
    # A second one later in the value is still reported.
    x <- robots_validate_text(
      ua_body("Disallow: ", lead, "/a", lead, "b"),
      unicode_advisories = TRUE
    )
    expect_identical(
      x$diagnostics$code,
      c("rule_missing_leading_slash", "rule_invisible_character"),
      label = label
    )
    expect_identical(
      x$diagnostics$message[[2L]],
      ua_invisible_message(paste(label, "first at byte 6")),
      label = label
    )
  }
  # A leading character the slash row does not name is reported.
  x <- robots_validate_text(
    ua_body("Disallow: ", ua_chr(0x2066), "/a"), unicode_advisories = TRUE
  )
  expect_identical(
    x$diagnostics$code,
    c("rule_missing_leading_slash", "rule_invisible_character")
  )
  expect_identical(
    x$diagnostics$message[[2L]],
    ua_invisible_message("U+2066 first at byte 1")
  )
})

test_that("ROBO-qxcwxtbm: one row lists ten code points and counts the rest", {
  points <- c(0x2060, 0x00ad, 0x200b, 0x200c, 0x200d, 0x200e, 0x200f, 0x202a,
              0x202b, 0x202c, 0x202d, 0x202e, 0x200b)
  value <- paste0("/", intToUtf8(points, multiple = TRUE), collapse = "")
  x <- robots_validate_text(
    ua_body("Disallow: ", value), unicode_advisories = TRUE
  )
  expect_identical(x$diagnostics$code, "rule_invisible_character")
  # Each "/" is one byte; U+00AD is two bytes, the others three.
  at <- c("U+00AD" = 6L, "U+200B" = 9L, "U+200C" = 13L, "U+200D" = 17L,
          "U+200E" = 21L, "U+200F" = 25L, "U+202A" = 29L, "U+202B" = 33L,
          "U+202C" = 37L, "U+202D" = 41L)
  expect_identical(
    x$diagnostics$message,
    sub(
      "U+202D first at byte 41", "U+202D first at byte 41, and 2 more",
      ua_invisible_message(paste(names(at), "first at byte", at)),
      fixed = TRUE
    )
  )
})

test_that("ROBO-qxcwxtbm: a document stops at 100 advisory rows", {
  rules <- paste0(sprintf("Disallow: /p%d", seq_len(1000L)), ua_chr(0x200b))
  body <- enc2utf8(paste0("User-agent: *\n", paste(rules, collapse = "\n"),
                          "\n"))
  x <- robots_validate_text(body, unicode_advisories = TRUE)
  rows <- ua_rows(x)
  expect_identical(nrow(rows), 100L)
  expect_identical(rows$line, 2:101)
  expect_identical(
    rows$message[[100L]],
    paste0(
      ua_invisible_message("U+200B first at byte 6"),
      " Unicode advisories stop at 100 rows per document; 900 more were not ",
      "reported."
    )
  )
  expect_false(grepl("stop at 100", rows$message[[99L]], fixed = TRUE))
  # Exactly 100 rows carry no note.
  x <- robots_validate_text(
    enc2utf8(paste0("User-agent: *\n", paste(rules[1:100], collapse = "\n"))),
    unicode_advisories = TRUE
  )
  expect_identical(nrow(ua_rows(x)), 100L)
  expect_false(any(grepl("stop at 100", x$diagnostics$message, fixed = TRUE)))
})

test_that("ROBO-qxcwxtbm: the flag must be TRUE or FALSE", {
  for (bad in list(NA, "yes", c(TRUE, TRUE), 1L, NULL)) {
    expect_error(
      robots_validate_text("User-agent: *\n", unicode_advisories = bad),
      class = "robotstxtr_invalid_unicode_advisories"
    )
    expect_error(
      robots_validate_url("https://example.com/", unicode_advisories = bad),
      class = "robotstxtr_invalid_unicode_advisories"
    )
  }
})

test_that("ROBO-qxcwxtbm: the edge-case fixtures keep their default rows", {
  edge_dir <- test_path("fixtures", "edge-cases")
  files <- list.files(edge_dir, pattern = "[.](txt|hex)$")
  expect_gt(length(files), 0L)
  for (file in files) {
    path <- file.path(edge_dir, file)
    bytes <- if (endsWith(file, ".hex")) {
      edge_hex_bytes(readLines(path), file)
    } else {
      readBin(path, "raw", file.size(path))
    }
    default <- robots_validate_text(bytes)
    expect_identical(
      robots_validate_text(bytes, unicode_advisories = FALSE), default,
      label = file
    )
    ua_expect_adds_only(bytes, file)
  }
})
