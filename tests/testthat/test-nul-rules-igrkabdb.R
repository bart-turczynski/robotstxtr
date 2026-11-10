# ROBO-igrkabdb: the validator's rule count against the matchers' NUL drop.
# Every matcher removes the NUL bytes and reads on (R/body-decode.R), while
# the validation parser ends a line at its first NUL.

# `text` as UTF-16LE bytes with no BOM: each ASCII byte followed by a NUL.
nr_utf16le <- function(text) {
  bytes <- charToRaw(text)
  as.vector(rbind(bytes, as.raw(0)))
}

nr_ascii_nul <- c(charToRaw("User-agent: *\n"), as.raw(0),
                  charToRaw("Disallow: /x\n"))

# The Google matcher's decision on `bytes`. R strings cannot hold a NUL, so
# the body is decoded as the fetch path decodes it (NULs dropped) and handed
# to the binding allowed_by_robots_text() uses.
nr_allowed <- function(bytes, path) {
  url <- paste0("https://example.com", path)
  Encoding(url) <- "UTF-8"
  robotstxtr_allowed_text_(decode_matcher_body(bytes), url, "FooBot")
}

test_that("a NUL-split body is called rule-free while its rule is enforced", {
  # Pins the gap before the fix: no_rules beside a matcher that disallows.
  bytes <- nr_utf16le("User-agent: *\nDisallow: /a\n")
  expect_false(nr_allowed(bytes, "/a"))
  expect_true("no_rules" %in% robots_validate_text(bytes)$diagnostics$code)

  expect_false(nr_allowed(nr_ascii_nul, "/x"))
  expect_true(
    "no_rules" %in% robots_validate_text(nr_ascii_nul)$diagnostics$code
  )
})
