# ROBO-sniltuap: where a document's bytes are not well-formed UTF-8.

iu_bytes <- function(...) {
  parts <- list(...)
  unlist(lapply(parts, function(p) if (is.character(p)) charToRaw(p) else
    as.raw(p)), use.names = FALSE)
}

test_that("invalid UTF-8 is one lineless error for the whole document", {
  x <- robots_validate_text(iu_bytes("# caf", 0xe9, "\nUser-agent: *\n",
                                     "Disallow: /a\n"))
  expect_identical(x$diagnostics$code, "invalid_utf8")
  expect_identical(x$diagnostics$line, NA_integer_)
  expect_identical(x$diagnostics$severity, "error")
  expect_identical(x$documents$validation_status, "error")

  x <- robots_validate_text(iu_bytes("User-agent: *\nDisallow: /caf", 0xe9,
                                     "\n"))
  expect_identical(x$diagnostics$code, "invalid_utf8")
  expect_identical(x$diagnostics$line, NA_integer_)
})
