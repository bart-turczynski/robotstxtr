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

expect_cut <- function(line, directive) {
  found <- cc_hits(line)
  label <- if (is.character(line)) line else paste(line, collapse = " ")
  expect_identical(nrow(found), 1L, label = label)
  expect_identical(found$line, 2L, label = label)
  expect_identical(found$severity, "warning", label = label)
  expect_identical(found$directive, directive, label = label)
}

test_that("a # glued to an Allow or Disallow value is rule_cut_by_comment", {
  expect_cut("Disallow: /a#b", "disallow")
  expect_cut("Allow: /a#b", "allow")
  # A trailing # is still a comment, so it fires too.
  expect_cut("Disallow: /a#", "disallow")
  expect_cut("Disallow: /a#b # note", "disallow")
})

test_that("a missing colon still gets the cut warning", {
  x <- cc_validate(charToRaw("Disallow /a#b"))
  line2 <- x$diagnostics$code[which(x$diagnostics$line == 2L)]
  expect_setequal(line2, c("accepted_missing_colon", "rule_cut_by_comment"))
})

test_that("a comment set apart, an empty value or a %23 stays silent", {
  for (line in c("Disallow: /a #b", "Disallow: /a\t#b", "# whole-line #x",
                 "Disallow: /a%23b", "Disallow: /a")) {
    expect_identical(nrow(cc_hits(line)), 0L, label = line)
  }
  # An empty value is empty_rule_value only.
  for (line in c("Disallow: #x", "Disallow:#x")) {
    x <- cc_validate(charToRaw(line))
    expect_identical(x$diagnostics$code[which(x$diagnostics$line == 2L)],
                     "empty_rule_value", label = line)
  }
})

test_that("Sitemap and User-agent values cut by # are out of scope", {
  expect_identical(nrow(cc_hits("Sitemap: https://example.com/s.xml#x")), 0L)
  x <- robots_validate_text("User-agent: a#b\nDisallow: /a\n")
  expect_false("rule_cut_by_comment" %in% x$diagnostics$code)
})

test_that("the check reads raw bytes: invalid UTF-8 and Latin-1 values", {
  # \xff is never UTF-8; \xe9 is Latin-1 e-acute.
  for (byte in c(0xff, 0xe9)) {
    line <- c(charToRaw("Disallow: /a"), as.raw(byte), charToRaw("#b"))
    expect_cut(line, "disallow")
    line <- c(charToRaw("Disallow: /a"), as.raw(byte), charToRaw(" #b"))
    expect_identical(nrow(cc_hits(line)), 0L)
  }
})

test_that("a NUL before the # hides it from the parser; after, it fires", {
  before <- c(charToRaw("Disallow: /a"), as.raw(0), charToRaw("x#b"))
  expect_identical(nrow(cc_hits(before)), 0L)
  glued <- c(charToRaw("Disallow: /a"), as.raw(0), charToRaw("#b"))
  expect_identical(nrow(cc_hits(glued)), 0L)
  after <- c(charToRaw("Disallow: /a#b"), as.raw(0), charToRaw("c"))
  expect_cut(after, "disallow")
})

test_that("CRLF lines, a BOM and an empty body behave", {
  x <- robots_validate_text("User-agent: *\r\nDisallow: /a#b\r\n")
  found <- x$diagnostics[x$diagnostics$code == "rule_cut_by_comment", ]
  expect_identical(found$line, 2L)
  bom <- c(as.raw(c(0xef, 0xbb, 0xbf)),
           charToRaw("User-agent: *\nDisallow: /a#b\n"))
  found <- robots_validate_text(bom)$diagnostics
  expect_identical(found$line[found$code == "rule_cut_by_comment"], 2L)
  expect_false("rule_cut_by_comment" %in%
                 robots_validate_text("")$diagnostics$code)
})

test_that("a # past the parser's line buffer is not seen", {
  long <- paste0("Disallow: /", strrep("a", 17000L), "#b")
  x <- robots_validate_text(paste0("User-agent: *\n", long, "\n"))
  expect_true("line_too_long" %in% x$diagnostics$code)
  expect_false("rule_cut_by_comment" %in% x$diagnostics$code)
})
