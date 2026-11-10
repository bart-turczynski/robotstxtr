# ROBO-gjhpykcj: a `#` with no whitespace before it cuts an Allow or
# Disallow value into a wider prefix.

cc_validate <- function(line) {
  robots_validate_text(c(charToRaw("user-agent: *\n"), line,
                         charToRaw("\nallow: /\n")))
}

cc_hits <- function(line) {
  if (is.character(line)) line <- charToRaw(line)
  x <- cc_validate(line)
  x$diagnostics[x$diagnostics$code == "rule_cut_by_comment", , drop = FALSE]
}

test_that("a # inside a rule value is not flagged yet", {
  for (line in c("Disallow: /a#b", "Allow: /a#b", "Disallow: /a#",
                 "Disallow /a#b")) {
    expect_identical(nrow(cc_hits(line)), 0L, label = line)
  }
})
