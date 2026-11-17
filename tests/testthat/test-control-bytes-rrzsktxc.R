# ROBO-rrzsktxc: an ASCII control byte inside an Allow or Disallow value is
# rule_control_character. The set is 0x01-0x08 and 0x0E-0x1F: NUL, tab, VT and
# FF have their own codes, and DEL (0x7F) is allowed by RFC 9309 section 2.2.

cc_tail <- paste0(
  "RFC 9309 section 2.2 excludes control bytes from a path pattern, and RFC ",
  "3986 bars them from a URL, so crawlers request them percent-encoded; ",
  "Google's matcher compares the pattern as written, so this rule matches no ",
  "URL they send."
)

# A body from pieces: a string is text, a raw vector is bytes.
cc_body <- function(...) {
  parts <- list(...)
  unlist(lapply(parts, function(p) if (is.raw(p)) p else charToRaw(p)))
}

# The validator's rows for one rule line, after a User-agent line. `parts` is
# a list of pieces, as cc_body() takes them.
cc_rule <- function(parts) {
  robots_validate_text(
    do.call(cc_body, c(list("User-agent: *\n"), parts, list("\n")))
  )
}

cc_rows <- function(x) {
  x$diagnostics[x$diagnostics$code == "rule_control_character", , drop = FALSE]
}

test_that("ROBO-rrzsktxc: a control byte in a rule value is one warning row", {
  x <- robots_validate_text(cc_body(
    "User-agent: *\nDisallow: /private", as.raw(1), "\n"
  ))
  rows <- cc_rows(x)
  expect_identical(x$diagnostics$code, "rule_control_character")
  expect_identical(rows$line, 2L)
  expect_identical(rows$severity, "warning")
  expect_identical(rows$directive, "disallow")
  expect_identical(rows$raw_text, "Disallow: /private\\x01")
  expect_identical(
    rows$message, paste0("Pattern holds the control byte \\x01. ", cc_tail)
  )
  expect_identical(x$documents$validation_status, "warning")
})

test_that("ROBO-rrzsktxc: each byte is flagged at any position in a value", {
  bytes <- as.raw(c(0x01, 0x08, 0x0e, 0x1b, 0x1f))
  for (type in c("Allow", "Disallow")) {
    directive <- tolower(type)
    for (byte in bytes) {
      label <- sprintf("%s byte %02X", type, as.integer(byte))
      shapes <- list(
        middle = list(paste0(type, ": /a"), byte, "b"),
        end = list(paste0(type, ": /a"), byte),
        after_slash = list(paste0(type, ": /"), byte, "a")
      )
      for (shape in names(shapes)) {
        x <- cc_rule(shapes[[shape]])
        expect_identical(x$diagnostics$code, "rule_control_character",
                         label = paste(label, shape))
        expect_identical(x$diagnostics$line, 2L, label = paste(label, shape))
        expect_identical(x$diagnostics$directive, directive,
                         label = paste(label, shape))
      }
      # A byte that also leads the value keeps rule_missing_leading_slash.
      x <- cc_rule(list(paste0(type, ": "), byte, "/a"))
      expect_identical(
        x$diagnostics$code,
        c("rule_missing_leading_slash", "rule_control_character"),
        label = paste(label, "leading")
      )
    }
  }
})

test_that("ROBO-rrzsktxc: distinct bytes are listed once, up to ten", {
  x <- cc_rule(list("Disallow: /a", as.raw(c(0x01, 0x01, 0x01)), "b"))
  expect_identical(
    cc_rows(x)$message,
    paste0("Pattern holds the control byte \\x01. ", cc_tail)
  )

  two <- cc_rule(list("Disallow: /a", as.raw(c(0x02, 0x01)), "b"))
  expect_identical(
    cc_rows(two)$message,
    paste0("Pattern holds control bytes \\x01, \\x02. ", cc_tail)
  )

  ten <- cc_rule(list("Disallow: /a", as.raw(c(0x01:0x08, 0x0e, 0x0f)), "b"))
  expect_identical(nrow(cc_rows(ten)), 1L)
  expect_identical(
    cc_rows(ten)$message,
    paste0("Pattern holds control bytes \\x01, \\x02, \\x03, \\x04, \\x05, ",
           "\\x06, \\x07, \\x08, \\x0E, \\x0F. ", cc_tail)
  )

  all_bytes <- as.raw(c(0x01:0x08, 0x0e:0x1f))
  x <- cc_rule(list("Disallow: /a", all_bytes, "b"))
  rows <- cc_rows(x)
  expect_identical(nrow(rows), 1L)
  expect_identical(
    rows$message,
    paste0("Pattern holds control bytes \\x01, \\x02, \\x03, \\x04, \\x05, ",
           "\\x06, \\x07, \\x08, \\x0E, \\x0F, and 16 more. ", cc_tail)
  )
  expect_match(rows$message, "^[ -~]*$")
})

test_that("ROBO-rrzsktxc: each rule line gets its own row", {
  x <- robots_validate_text(cc_body(
    "User-agent: *\nDisallow: /a", as.raw(1), "\nAllow: /b", as.raw(2), "\n"
  ))
  rows <- cc_rows(x)
  expect_identical(rows$line, c(2L, 3L))
  expect_identical(rows$directive, c("disallow", "allow"))
  expect_identical(rows$raw_text, c("Disallow: /a\\x01", "Allow: /b\\x02"))
})

test_that("ROBO-rrzsktxc: tab, VT, FF, NUL and DEL get no control row", {
  tab <- cc_rule(list("Disallow: /a", as.raw(0x09), "b"))
  expect_identical(tab$diagnostics$code, "rule_inner_whitespace")
  vt <- cc_rule(list("Disallow: /a", as.raw(0x0b), "b"))
  expect_identical(vt$diagnostics$code, "rule_inner_whitespace")
  ff <- cc_rule(list("Disallow: /a", as.raw(0x0c), "b"))
  expect_identical(ff$diagnostics$code, "rule_inner_whitespace")
  nul <- cc_rule(list("Disallow: /a", as.raw(0x00), "b"))
  expect_identical(nul$diagnostics$code, c("nul_byte", "rule_cut_by_nul"))
  del <- cc_rule(list("Disallow: /a", as.raw(0x7f), "b"))
  expect_identical(nrow(del$diagnostics), 0L)
})

test_that("ROBO-rrzsktxc: bytes the parser never reads are not flagged", {
  after_nul <- cc_rule(list("Disallow: /a", as.raw(0x00), as.raw(0x01)))
  expect_identical(after_nul$diagnostics$code, c("nul_byte", "rule_cut_by_nul"))
  in_comment <- cc_rule(list("Disallow: /a #", as.raw(0x01)))
  expect_identical(nrow(in_comment$diagnostics), 0L)
  glued <- cc_rule(list("Disallow: /a#", as.raw(0x01)))
  expect_identical(glued$diagnostics$code, "rule_cut_by_comment")
  escaped <- cc_rule(list("Disallow: /a%01b"))
  expect_identical(nrow(escaped$diagnostics), 0L)
})

test_that("ROBO-rrzsktxc: the 16,663-byte line buffer bounds the check", {
  pre <- "disallow: /"
  kept <- cc_body(
    "User-agent: *\n", pre, strrep("x", 16663L - nchar(pre) - 1L),
    as.raw(1), "\n"
  )
  x <- robots_validate_text(kept)
  expect_identical(x$diagnostics$code, "rule_control_character")
  expect_identical(x$diagnostics$line, 2L)

  dropped <- cc_body(
    "User-agent: *\n", pre, strrep("x", 16664L - nchar(pre) - 1L),
    as.raw(1), "\n"
  )
  y <- robots_validate_text(dropped)
  expect_identical(y$diagnostics$code, "line_too_long")
})

test_that("ROBO-rrzsktxc: a leading byte with other findings keeps them", {
  x <- cc_rule(list("Disallow: ", as.raw(0x01), "private b"))
  expect_identical(
    x$diagnostics$code,
    c("rule_missing_leading_slash", "rule_inner_whitespace",
      "rule_control_character")
  )
})

test_that("ROBO-rrzsktxc: raw and character input give the same rows", {
  body <- cc_body(
    "User-agent: *\nDisallow: /a", as.raw(1), "b\nAllow: /c", as.raw(0x1f),
    "\n"
  )
  x <- robots_validate_text(body)
  text <- rawToChar(body)
  Encoding(text) <- "bytes"
  y <- robots_validate_text(text)
  expect_identical(x$diagnostics, y$diagnostics)
  expect_identical(nrow(cc_rows(x)), 2L)
})

test_that("ROBO-rrzsktxc: a fetched body gets the same control rows", {
  body <- cc_body("User-agent: *\nDisallow: /a", as.raw(1), "b\n")
  local_fake_ssrfr(function(req) fake_response(200L, body = body))
  z <- robots_validate_url("http://example.com/")
  x <- robots_validate_text(body)
  cols <- c("line", "severity", "code", "directive", "raw_text", "message")
  fetched <- cc_rows(z)[, cols]
  expected <- cc_rows(x)[, cols]
  rownames(fetched) <- NULL
  rownames(expected) <- NULL
  expect_identical(fetched, expected)
  expect_identical(nrow(fetched), 1L)
})

test_that("ROBO-rrzsktxc: Google's matcher does not match the escaped URL", {
  body <- "User-agent: *\nDisallow: /a\x01b\n"
  expect_true(allowed_by_robots_text(
    body, "https://example.com/a%01b", "FooBot"
  )$results$allowed)
})

test_that("ROBO-rrzsktxc: Sitemap and User-agent values are not rules", {
  sitemap <- cc_body(
    "User-agent: *\nSitemap: https://a.example/", as.raw(1), "\nallow: /\n"
  )
  expect_false(
    "rule_control_character" %in% robots_validate_text(sitemap)$diagnostics$code
  )
  agent <- cc_body("User-agent: a", as.raw(1), "\nDisallow: /x\n")
  expect_false(
    "rule_control_character" %in% robots_validate_text(agent)$diagnostics$code
  )
})

test_that("ROBO-rrzsktxc: clean rules, CRLF ends and empty values get no row", {
  x <- robots_validate_text(cc_body(
    "User-agent: *\r\nDisallow: /a\r\nAllow: /b%01c\r\n"
  ))
  expect_identical(nrow(x$diagnostics), 0L)
  y <- robots_validate_text("User-agent: *\nDisallow:\n")
  expect_identical(y$diagnostics$code, "empty_rule_value")
})
