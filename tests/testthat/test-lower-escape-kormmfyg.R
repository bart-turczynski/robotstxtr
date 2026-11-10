# ROBO-kormmfyg: a lower-case percent-escape in an Allow or Disallow value.
# Google's parser upper-cases the escapes in a rule value but never the URL
# path, so `Disallow: /a%3cb` does not block the path `/a%3cb` the owner wrote.

lc_validate <- function(line) {
  robots_validate_text(paste0("user-agent: *\n", line, "\nallow: /\n"))
}

lc_found <- function(x) {
  x$diagnostics[x$diagnostics$code == "rule_lowercase_escape", ,
                drop = FALSE]
}

# Values the parser keeps with a lower-case escape: either hex digit counts,
# a '%' before another '%' is not an escape of its own, and a raw non-ASCII
# byte before the escape is no bar.
lc_flagged <- c(
  "/a%3cb", "/a%c3", "/a%aB", "/a%Ab", "/%%3c", "/café%3c", "/a%3cb%3C"
)

test_that("known gap (ROBO-kormmfyg): a lower-case escape is unflagged", {
  for (value in lc_flagged) {
    for (directive in c("disallow", "allow")) {
      line <- paste0(directive, ": ", value)
      expect_identical(nrow(lc_found(lc_validate(line))), 0L, label = line)
    }
  }
  for (line in c(
    "Disallow /a%3cb", "Dissallow: /a%3cb", "Allow /a%3cb"
  )) {
    expect_identical(nrow(lc_found(lc_validate(line))), 0L, label = line)
  }
})

test_that("a known gap (ROBO-kormmfyg) holds for a rule's line-ending forms", {
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  bodies <- list(
    crlf = charToRaw("User-agent: *\r\nDisallow: /a%3cb\r\n"),
    bom_start = c(bom, charToRaw("User-agent: *\nDisallow: /a%3cb\n")),
    invalid_utf8 = c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0xff),
                     charToRaw("%3cb\n")),
    nul_after = c(charToRaw("User-agent: *\nDisallow: /a%3cb"), as.raw(0x00),
                  charToRaw("\n"))
  )
  for (name in names(bodies)) {
    x <- robots_validate_text(bodies[[name]])
    expect_identical(nrow(lc_found(x)), 0L, label = name)
  }
})

test_that("a known gap (ROBO-kormmfyg) holds across the parser's line buffer", {
  # The parser keeps 16,663 bytes of a line. The escape here ends exactly at
  # byte 16,663, so it is in the value: known gap, no finding yet.
  inside <- paste0("User-agent: *\nDisallow: /", strrep("a", 16649L), "%3c\n")
  expect_identical(nrow(lc_found(robots_validate_text(inside))), 0L)
})

test_that("an escape outside a rule's value draws no finding", {
  for (line in c(
    "Disallow: /a%3Cb", "Disallow: /a%Zb", "Disallow: /a%3", "Disallow: /a%",
    "Disallow: /a #%3c", "Disallow%3c: /x", "Disallow:"
  )) {
    expect_identical(nrow(lc_found(lc_validate(line))), 0L, label = line)
  }
  # The parser does not escape a User-agent or Sitemap value.
  x <- robots_validate_text(
    "User-agent: %3c\nSitemap: https://example.com/%3c.xml\n"
  )
  expect_identical(nrow(lc_found(x)), 0L)
})

test_that("a NUL or a buffer cut before the escape is no finding", {
  # The parser stops a value at the NUL, so the escape after it is not kept.
  nul_before <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0x00),
                  charToRaw("%3cb\n"))
  expect_identical(nrow(lc_found(robots_validate_text(nul_before))), 0L)
  # The escape starts at byte 16,664, past the 16,663 bytes the parser keeps.
  past_cut <- paste0("User-agent: *\nDisallow: /", strrep("a", 16652L),
                     "%3cb\n")
  expect_identical(nrow(lc_found(robots_validate_text(past_cut))), 0L)
})

test_that("a key escape with a missing colon is no finding", {
  # The parser strips the blanks before the key, so the key is `Disallow%3c`
  # and the value is `/x`: the escape is in the key only. On line 1 a
  # byte-order mark is skipped before the blanks.
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  body <- c(bom, charToRaw("  Disallow%3c /x\n"))
  expect_identical(nrow(lc_found(robots_validate_text(body))), 0L)
  body <- charToRaw("User-agent: *\n  Disallow%3c /x\n")
  expect_identical(nrow(lc_found(robots_validate_text(body))), 0L)
})
