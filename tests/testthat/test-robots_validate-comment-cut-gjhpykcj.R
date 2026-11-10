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

test_that("a NUL before or after the # still gets the cut warning", {
  # The parser stops at the NUL, but Google's matcher drops NULs and reads
  # on, so it cuts the rule at the `#`: the check reads the line NUL-free.
  for (tail in list(charToRaw("x#b"), charToRaw("#b"))) {
    line <- c(charToRaw("Disallow: /a"), as.raw(0), tail)
    expect_cut(line, "disallow")
    codes <- cc_validate(line)$diagnostics$code
    expect_true("nul_byte" %in% codes)
  }
  body <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0),
            charToRaw("#b\n"))
  expect_false(robotstxtr_allowed_text_(decode_matcher_body(body),
                                        "https://example.com/abc", "FooBot"))
  after <- c(charToRaw("Disallow: /a#b"), as.raw(0), charToRaw("c"))
  expect_cut(after, "disallow")
  # A NUL-free space before the # still sets the comment apart.
  spaced <- c(charToRaw("Disallow: /a "), as.raw(0), charToRaw("#b"))
  expect_identical(nrow(cc_hits(spaced)), 0L)
})

test_that("only SP and HT set a # apart; a $ before it still fires", {
  # RFC 9309 WS is SP and HT; a vertical tab or form feed is glued.
  expect_cut("Disallow: /a\v#b", "disallow")
  expect_cut("Disallow: /a\f#b", "disallow")
  # The cut leaves /a$, a changed rule rather than a wider one.
  expect_cut("Disallow: /a$#b", "disallow")
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

test_that("the observed Bing fragment body gets the cut warning", {
  # Expectation exp-sr2-bingbot-fragment-comment: Bing cuts at the #.
  path <- system.file("bing-corpus", "bodies",
                      "body-sr2-bingbot-fragment-prefix-discriminator.txt",
                      package = "robotstxtr", mustWork = TRUE)
  bytes <- readBin(path, "raw", file.size(path))
  found <- robots_validate_text(bytes)$diagnostics
  expect_identical(found$line[found$code == "rule_cut_by_comment"], 2L)
})
