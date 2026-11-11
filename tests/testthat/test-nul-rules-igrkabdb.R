# ROBO-igrkabdb: the rules NUL bytes hide, as in UTF-16 text. The validation
# parser ends a line at its first NUL, and since ROBO-pvqrfvol Google's
# matcher does too (R/body-decode.R), so neither reads them; the validator
# names them in place of no_rules.

# `text` as UTF-16LE bytes with no BOM: each ASCII byte followed by a NUL.
nr_utf16le <- function(text) {
  bytes <- charToRaw(text)
  as.vector(rbind(bytes, as.raw(0)))
}

nr_ascii_nul <- c(charToRaw("User-agent: *\n"), as.raw(0),
                  charToRaw("Disallow: /x\n"))

# The Google matcher's decision on `bytes`. R strings cannot hold a NUL, so
# the body is decoded as the fetch path decodes it (each line cut at its first
# NUL) and handed to the binding allowed_by_robots_text() uses.
nr_allowed <- function(bytes, path) {
  url <- paste0("https://example.com", path)
  Encoding(url) <- "UTF-8"
  robotstxtr_allowed_text_(decode_matcher_body(bytes), url, "FooBot")
}

nr_message <- function(n) {
  sprintf(
    paste0(
      "The NUL bytes hide %d Allow or Disallow rule(s): Google's matcher ",
      "ends each line at its first NUL and never reads them; if this is ",
      "a UTF-16 file, re-save it as UTF-8 (RFC 9309 section 2.3)."
    ),
    n
  )
}

# The one rules_after_nul_removal row of `x`: a lineless warning naming `n`
# rules, with no no_rules beside it.
expect_rules_after_nul <- function(x, n, label) {
  d <- x$diagnostics
  found <- d[d$code == "rules_after_nul_removal", , drop = FALSE]
  expect_identical(nrow(found), 1L, label = label)
  expect_identical(found$severity, "warning", label = label)
  expect_identical(found$line, NA_integer_, label = label)
  expect_identical(found$directive, NA_character_, label = label)
  expect_identical(found$raw_text, NA_character_, label = label)
  expect_identical(found$message, nr_message(n), label = label)
  expect_false("no_rules" %in% d$code, label = label)
}

test_that("a NUL-split body reports the rules the NULs hide", {
  bytes <- nr_utf16le("User-agent: *\nDisallow: /a\n")
  expect_true(nr_allowed(bytes, "/a"))
  x <- robots_validate_text(bytes)
  expect_rules_after_nul(x, 1L, "UTF-16LE")
  expect_identical(x$documents$validation_status, "error")
  # The raw-parse rows and counts are unchanged.
  expect_identical(x$diagnostics$line[x$diagnostics$code == "nul_byte"],
                   1:3)
  expect_identical(x$documents$disallow_directives, 0L)

  expect_true(nr_allowed(nr_ascii_nul, "/x"))
  expect_rules_after_nul(robots_validate_text(nr_ascii_nul), 1L, "ASCII")

  bytes <- nr_utf16le("User-agent: *\nAllow: /a\nDisallow: /\n")
  expect_rules_after_nul(robots_validate_text(bytes), 2L, "two rules")
})

test_that("a body with no rule even NUL-free keeps no_rules", {
  cases <- list(
    "NUL in a comment" = as.raw(c(0x23, 0x00, 0x0a)),
    "NUL only" = as.raw(0),
    "empty" = raw(),
    "comment only" = charToRaw("# only a comment\n"),
    "UTF-16LE User-agent only" = nr_utf16le("User-agent: *\n")
  )
  for (case in names(cases)) {
    codes <- robots_validate_text(cases[[case]])$diagnostics$code
    expect_true("no_rules" %in% codes, label = case)
    expect_false("rules_after_nul_removal" %in% codes, label = case)
  }
})

test_that("a rule the raw parse already reads draws neither code", {
  bytes <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0),
             charToRaw("b\n"))
  codes <- robots_validate_text(bytes)$diagnostics$code
  expect_true("nul_byte" %in% codes)
  expect_false("no_rules" %in% codes)
  expect_false("rules_after_nul_removal" %in% codes)
})

test_that("UTF-16 with a BOM or CRLF still gets the code", {
  ascii <- charToRaw("User-agent: *\nDisallow: /a\n")
  be_bom <- c(as.raw(c(0xfe, 0xff)), as.vector(rbind(as.raw(0), ascii)))
  x <- robots_validate_text(be_bom)
  expect_true("invalid_utf8" %in% x$diagnostics$code)
  expect_rules_after_nul(x, 1L, "UTF-16BE BOM")

  le_bom <- c(as.raw(c(0xff, 0xfe)), nr_utf16le("User-agent: *\n"),
              nr_utf16le("Disallow: /a\n"))
  expect_rules_after_nul(robots_validate_text(le_bom), 1L, "UTF-16LE BOM")

  crlf <- nr_utf16le("User-agent: *\r\nDisallow: /a\r\n")
  x <- robots_validate_text(crlf)
  expect_rules_after_nul(x, 1L, "UTF-16LE CRLF")
  has_nul <- vapply(split_validation_lines(crlf),
                    function(line) any(line == as.raw(0)), logical(1L))
  expect_identical(x$diagnostics$line[x$diagnostics$code == "nul_byte"],
                   which(has_nul))
})

test_that("a body cut after a NUL-split rule still reports it", {
  body <- nr_utf16le(paste0(
    "User-agent: *\nDisallow: /a\n# ",
    strrep("x", 200L), "\n"
  ))
  local_fake_ssrfr(function(req) fake_response(200L, body = body))
  x <- robots_validate_url("http://example.com/", max_bytes = 100L)
  expect_true(x$documents$body_truncated)
  expect_true("body_truncated" %in% x$diagnostics$code)
  expect_rules_after_nul(x, 1L, "cut body")
})
