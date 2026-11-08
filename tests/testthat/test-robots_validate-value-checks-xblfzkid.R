# ROBO-xblfzkid: value checks on Sitemap and Allow/Disallow lines.

vc_codes <- c(
  "invalid_sitemap_url", "unsupported_sitemap_scheme",
  "rule_missing_leading_slash", "rule_inner_dollar"
)

vc_validate <- function(line) {
  robots_validate_text(paste0("user-agent: *\n", line, "\n"))
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
    "Sitemap: //x.com/s.xml", "Sitemap: https://", "Sitemap: http:x.com"
  )) {
    x <- expect_value_codes(line, "invalid_sitemap_url", "sitemap")
    expect_identical(x$documents$validation_status, "warning", label = line)
  }
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

test_that("well-formed patterns stay clean of the value checks", {
  for (line in c(
    "Disallow: *.pdf", "Disallow: /*.pdf$", "Disallow: /", "Allow: /$"
  )) {
    x <- vc_validate(line)
    expect_identical(nrow(x$diagnostics), 0L, label = line)
  }
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
