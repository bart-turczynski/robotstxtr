# ROBO-xblfzkid: value checks on Sitemap and Allow/Disallow lines.

vc_codes <- c(
  "invalid_sitemap_url", "unsupported_sitemap_scheme",
  "rule_missing_leading_slash", "rule_inner_dollar", "rule_inner_whitespace"
)

vc_validate <- function(line) {
  robots_validate_text(paste0("user-agent: *\n", line, "\nallow: /\n"))
}

# The value-check findings of one line: exactly `codes`, each a line-2
# warning on `directive`.
expect_value_codes <- function(line, codes, directive) {
  x <- vc_validate(line)
  found <- x$diagnostics[x$diagnostics$code %in% vc_codes, , drop = FALSE]
  expect_identical(found$code, codes, label = line)
  expect_identical(found$severity, rep("warning", length(codes)), label = line)
  expect_identical(found$line, rep(2L, length(codes)), label = line)
  expect_identical(found$directive, rep(directive, length(codes)),
                   label = line)
  invisible(x)
}

test_that("a sitemap value without a scheme is invalid_sitemap_url", {
  for (line in c(
    "Sitemap: not a url", "Sitemap: /sitemap.xml", "Sitemap: sitemap.xml",
    "Sitemap: //x.com/s.xml", "Sitemap: https://", "Sitemap: http:x.com",
    "Sitemap: x.com:8080/s.xml", "Sitemap: localhost:8080/s.xml"
  )) {
    x <- expect_value_codes(line, "invalid_sitemap_url", "sitemap")
    expect_identical(x$documents$validation_status, "warning", label = line)
  }
})

test_that("a scheme without '//' is invalid whatever rurl accepts", {
  # A lenient rurl that parses "http:x.com" must not let it pass.
  local_mocked_bindings(
    safe_parse_url = function(...) list(scheme = "http", host = "x.com"),
    .package = "rurl"
  )
  expect_value_codes("Sitemap: http:x.com", "invalid_sitemap_url", "sitemap")
  x <- vc_validate("Sitemap: http:x.com")
  expect_identical(
    x$diagnostics$message, "Sitemap value is not a valid absolute URL."
  )
  # The mock passes a well-formed URL, so the guard is what rejects the above.
  expect_identical(nrow(vc_validate("Sitemap: http://x.com")$diagnostics), 0L)
})

test_that("a non-http sitemap scheme is one unsupported_sitemap_scheme", {
  for (line in c(
    "Sitemap: mailto:a@b.c", "Sitemap: javascript:void(0)",
    "Sitemap: file:///etc/sitemap.xml"
  )) {
    expect_value_codes(line, "unsupported_sitemap_scheme", "sitemap")
  }
  x <- vc_validate("Sitemap: mailto:a@b.c")
  expect_identical(
    x$diagnostics$message,
    "Sitemap URL scheme 'mailto' is not http, https or ftp."
  )
})

test_that("absolute http, https, ftp and IDN sitemap URLs stay clean", {
  for (line in c(
    "Sitemap: https://example.com/sitemap.xml",
    "Sitemap: HTTPS://EXAMPLE.COM/s.xml",
    "Sitemap: http://example.com/s.xml",
    "Sitemap: ftp://example.com/s.xml",
    "Sitemap: https://bücher.de/s.xml"
  )) {
    x <- vc_validate(line)
    expect_identical(nrow(x$diagnostics), 0L, label = line)
    expect_identical(x$documents$validation_status, "valid", label = line)
  }
})

test_that("an empty sitemap value keeps only empty_sitemap_value", {
  x <- vc_validate("Sitemap:")
  expect_identical(x$diagnostics$code, "empty_sitemap_value")
})

test_that("a pattern not led by '/' or '*' is rule_missing_leading_slash", {
  expect_value_codes("Disallow: private", "rule_missing_leading_slash",
                     "disallow")
  expect_value_codes("Allow: private", "rule_missing_leading_slash", "allow")
  expect_value_codes("Disallow: ?x", "rule_missing_leading_slash", "disallow")
  # A lone '$' is a pattern without a leading slash, not an inner '$'.
  x <- expect_value_codes("Disallow: $", "rule_missing_leading_slash",
                          "disallow")
  expect_identical(
    x$diagnostics$message,
    paste0(
      "Pattern does not start with '/' or '*'; URL paths always start ",
      "with '/', so this rule never matches."
    )
  )
})

test_that("an inner '$' is rule_inner_dollar", {
  expect_value_codes("Disallow: /a$b", "rule_inner_dollar", "disallow")
  expect_value_codes("Disallow: /a$$", "rule_inner_dollar", "disallow")
  expect_value_codes(
    "Disallow: private$x",
    c("rule_missing_leading_slash", "rule_inner_dollar"), "disallow"
  )
})

test_that("a space, tab, VT or FF inside a rule is rule_inner_whitespace", {
  # ROBO-dlgeqluf: an interior whitespace byte matches no percent-encoded URL,
  # so the rule never matches
  expect_value_codes("Disallow: /a b", "rule_inner_whitespace", "disallow")
  expect_value_codes("Allow: /a b", "rule_inner_whitespace", "allow")
  expect_value_codes("Disallow: /a\tb", "rule_inner_whitespace", "disallow")
  expect_value_codes("Disallow: /a\vb", "rule_inner_whitespace", "disallow")
  expect_value_codes("Disallow: /a\fb", "rule_inner_whitespace", "disallow")
  x <- vc_validate("Disallow: /a b")
  expect_identical(
    x$diagnostics$message,
    paste0(
      "Pattern holds a raw space or other whitespace; crawlers request it ",
      "percent-encoded (a space is %20), so this rule matches no URL they ",
      "send."
    )
  )
})

test_that("a whitespace finding keeps the other findings on its rule", {
  expect_value_codes(
    "Disallow: private b",
    c("rule_missing_leading_slash", "rule_inner_whitespace"), "disallow"
  )
  expect_value_codes(
    "Disallow: /a$ b",
    c("rule_inner_dollar", "rule_inner_whitespace"), "disallow"
  )
  # The parser escapes the 'é' to %C3%A9 before the check reads the value.
  expect_value_codes(
    "Disallow: /é b", "rule_inner_whitespace", "disallow"
  )
})

test_that("a raw space beside malformed bytes is checked, not an error", {
  body <- c(charToRaw("user-agent: *\nDisallow: /a"), as.raw(0xff),
            charToRaw(" b\nallow: /\n"))
  x <- expect_no_error(robots_validate_text(body))
  expect_true(all(
    c("invalid_utf8", "rule_inner_whitespace") %in% x$diagnostics$code
  ))
  text <- rawToChar(body)
  Encoding(text) <- "bytes"
  y <- expect_no_error(robots_validate_text(text))
  expect_identical(x$diagnostics, y$diagnostics)
})

test_that("a space after a NUL is not read by the parser", {
  # The value stops at the NUL, so the space behind it is never checked.
  body <- c(charToRaw("user-agent: *\nDisallow: /a"), as.raw(0),
            charToRaw(" b\nallow: /\n"))
  x <- expect_no_error(robots_validate_text(body))
  expect_true("nul_byte" %in% x$diagnostics$code)
  expect_false("rule_inner_whitespace" %in% x$diagnostics$code)
})

test_that("a raw space in a line past the parser's buffer is still checked", {
  long <- sprintf("user-agent: *\ndisallow: /a b%s\n", strrep("x", 17000L))
  y <- expect_no_error(robots_validate_text(long))
  expect_identical(
    y$diagnostics$code, c("line_too_long", "rule_inner_whitespace")
  )
})

for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("a rule's whitespace check is byte-based under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    expect_value_codes("Disallow: /a b", "rule_inner_whitespace", "disallow")
  })
}

test_that("a value trimmed or escaped to a clean pattern draws nothing", {
  # The parser trims the edges of a value and cuts a comment, so these values
  # are clean; %20 is an escaped space, not a raw one.
  for (line in c(
    "Disallow: /a%20b", "Disallow: /a #comment", "Disallow: /a ",
    "Disallow:  /a", "Disallow: /a\t", "Disallow: /a\v", "Disallow: /a\f"
  )) {
    x <- vc_validate(line)
    expect_identical(nrow(x$diagnostics), 0L, label = line)
  }
})

test_that("a User-agent or Sitemap value with a space is no rule", {
  for (line in c("User-agent: Foo Bot", "Sitemap: https://a.example/x y")) {
    x <- vc_validate(line)
    expect_false("rule_inner_whitespace" %in% x$diagnostics$code, label = line)
  }
})

test_that("well-formed patterns stay clean of the value checks", {
  for (line in c(
    "Disallow: *.pdf", "Disallow: /*.pdf$", "Allow: /$"
  )) {
    x <- vc_validate(line)
    expect_identical(nrow(x$diagnostics), 0L, label = line)
  }
  # The fixture's own `allow: /` ties `Disallow: /` (ROBO-fdhmlvwm).
  x <- vc_validate("Disallow: /")
  expect_identical(x$diagnostics$code, "disallow_tied_by_allow")
  expect_identical(x$diagnostics$line, 2L)
  x <- vc_validate("Disallow:")
  expect_identical(x$diagnostics$code, "empty_rule_value")
})

test_that("an invisible leading character is named in the message", {
  x <- expect_value_codes("Disallow: \u200b/imgres",
                          "rule_missing_leading_slash", "disallow")
  expect_match(
    x$diagnostics$message,
    "It starts with an invisible character (U+200B).", fixed = TRUE
  )
  x <- vc_validate("Disallow: \ufeff/imgres")
  expect_match(x$diagnostics$message, "(U+FEFF).", fixed = TRUE)
  x <- vc_validate("Disallow: private")
  expect_no_match(x$diagnostics$message, "invisible", fixed = TRUE)
})

test_that("a rule before any user-agent gets both findings", {
  x <- robots_validate_text("Disallow: private\n")
  expect_true(all(c(
    "rule_without_user_agent", "rule_missing_leading_slash"
  ) %in% x$diagnostics$code))
  expect_identical(
    x$diagnostics$line[x$diagnostics$code == "rule_missing_leading_slash"], 1L
  )
})

test_that("malformed bytes in a value are diagnosed without an R error", {
  body <- as.raw(c(
    charToRaw("user-agent: *\nSitemap: https://a"), 0xff,
    charToRaw("/s.xml\nDisallow: "), 0xe9, charToRaw("x\n")
  ))
  x <- expect_no_error(robots_validate_text(body))
  expect_true(all(c(
    "invalid_utf8", "invalid_sitemap_url", "rule_missing_leading_slash"
  ) %in% x$diagnostics$code))
  expect_identical(
    x$diagnostics$line[x$diagnostics$code == "invalid_sitemap_url"], 2L
  )
  expect_identical(
    x$diagnostics$line[x$diagnostics$code == "rule_missing_leading_slash"], 3L
  )

  text <- rawToChar(body)
  Encoding(text) <- "bytes"
  y <- expect_no_error(robots_validate_text(text))
  expect_identical(x$diagnostics, y$diagnostics)
})

test_that("NUL bytes and over-long lines do not break the value checks", {
  body <- as.raw(c(
    charToRaw("user-agent: *\nSitemap: https://example.com/s"), 0x00,
    charToRaw(".xml\n")
  ))
  x <- expect_no_error(robots_validate_text(body))
  expect_true("nul_byte" %in% x$diagnostics$code)

  long <- sprintf("user-agent: *\ndisallow: /%s$x", strrep("x", 17000L))
  y <- expect_no_error(robots_validate_text(long))
  expect_true("line_too_long" %in% y$diagnostics$code)
})

# The suite's locale legs run every test under these LC_CTYPEs too; this
# test also sets them where the platform has them.
for (locale in readLines(test_path("fixtures", "case-folding-locales.txt"))) {
  test_that(paste("an upper-case scheme folds the same under", locale), {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    skip_if_not(identical(set, locale), paste(locale, "is not available"))
    x <- vc_validate("Sitemap: HTTPS://EXAMPLE.COM/s.xml")
    expect_identical(nrow(x$diagnostics), 0L)
    y <- vc_validate("Sitemap: MAILTO:I@B.C")
    expect_identical(
      y$diagnostics$message,
      "Sitemap URL scheme 'mailto' is not http, https or ftp."
    )
  })
}

test_that("the matcher never matches a slashless pattern or an inner '$'", {
  slashless <- allowed_by_robots_text(
    "user-agent: *\nDisallow: private\n", "https://x.com/private", "bot"
  )
  expect_true(slashless$results$allowed)
  inner_dollar <- allowed_by_robots_text(
    "user-agent: *\nDisallow: /a$b\n", "https://x.com/ab", "bot"
  )
  expect_true(inner_dollar$results$allowed)
})
