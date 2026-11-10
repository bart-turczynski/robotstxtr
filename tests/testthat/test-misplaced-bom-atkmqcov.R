# ROBO-atkmqcov: a UTF-8 byte-order mark after the start of the file.
#
# The Google-compatible parser skips one BOM at byte 0 only. A BOM anywhere
# else that starts a line's content stays at the start of its key, so the
# directive on that line is not read.

bom <- as.raw(c(0xef, 0xbb, 0xbf))

bom_fixture <- function(id) {
  path <- test_path("fixtures", "edge-cases", paste0(id, ".hex"))
  hex <- gsub("[[:space:]]", "", paste(readLines(path), collapse = ""))
  starts <- seq(1L, nchar(hex), by = 2L)
  as.raw(strtoi(substring(hex, starts, starts + 1L), 16L))
}

bom_codes <- function(bytes) {
  d <- robots_validate_text(bytes)$diagnostics
  paste(sprintf("%s@%s", d$code, ifelse(is.na(d$line), "NA", d$line)),
        collapse = ";")
}

test_that("ROBO-atkmqcov: a BOM after the start is today only unknown", {
  expect_identical(bom_codes(bom_fixture("enc-bom-mid-file")),
                   "unknown_directive@2;no_rules@NA")
  expect_identical(bom_codes(bom_fixture("enc-bom-before-user-agent")),
                   "unknown_directive@4")
  expect_identical(
    bom_codes(bom_fixture("enc-bom-doubled")),
    paste0("byte_order_mark@1;unknown_directive@1;",
           "rule_without_user_agent@2;missing_user_agent@NA")
  )
  expect_identical(bom_codes(bom_fixture("enc-bom-start")),
                   "byte_order_mark@1")
})
