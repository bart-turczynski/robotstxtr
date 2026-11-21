# ROBO-rnjfbhvn: an Allow or Disallow pattern with a literal `.` or `..` path
# segment. Most URL handling removes dot segments before a request (RFC 3986
# section 5.2.4), so such a pattern matches only a client that sends the path
# unnormalized. The scan reads the canonical value up to its first `?` and
# stops at its first `*`; a hit is `.` or `..` after a `/`, followed by `/`,
# by `?` or by a `$` that is the value's last byte. One row per rule line.

# The validator's codes for one rule line, after a User-agent line.
ds_codes <- function(type, value) {
  robots_validate_text(
    paste0("User-agent: *\n", type, ": ", value, "\n")
  )$diagnostics$code
}

# Patterns with a bounded dot segment.
ds_hits <- c(
  "/a/./b", "/a/../b", "/a/.$", "/a/..$", "/a/..?q=x", "/./b", "/../b",
  "/a/./"
)

# Patterns that get no rule_dot_segment row, each with the codes it gets
# today, which must not move.
ds_misses <- list(
  "/a/." = character(0),
  "/a/.." = character(0),
  "/a/..foo" = character(0),
  "/file.html" = character(0),
  "/a..b/" = character(0),
  "/.well-known/" = character(0),
  "/?q=/../z" = character(0),
  "/*/../x" = character(0),
  "*/./b" = character(0),
  "/a/..$x" = "rule_inner_dollar",
  "/a/%2e/b" = c("rule_escaped_unreserved", "rule_lowercase_escape"),
  "/a/%2E%2E/b" = "rule_escaped_unreserved",
  "a/../b" = "rule_missing_leading_slash"
)

ds_message <- paste0(
  "Pattern holds a '.' or '..' path segment. Some URL parsers remove dot ",
  "segments before requesting (RFC 3986 section 5.2.4), so this rule may ",
  "never match."
)

test_that("ROBO-rnjfbhvn: a dot segment in a rule value is one warning row", {
  x <- robots_validate_text("User-agent: *\nDisallow: /a/./b\n")
  expect_identical(x$diagnostics$code, "rule_dot_segment")
  expect_identical(x$diagnostics$line, 2L)
  expect_identical(x$diagnostics$severity, "warning")
  expect_identical(x$diagnostics$directive, "disallow")
  expect_identical(x$diagnostics$raw_text, "Disallow: /a/./b")
  expect_identical(x$diagnostics$message, ds_message)
  expect_identical(x$documents$validation_status, "warning")
})

test_that("ROBO-rnjfbhvn: a bounded dot segment is flagged", {
  for (type in c("Allow", "Disallow")) {
    for (value in ds_hits) {
      expect_identical(
        ds_codes(type, value), "rule_dot_segment",
        label = paste(type, value)
      )
    }
  }
})

test_that("ROBO-rnjfbhvn: other dots keep their codes", {
  for (type in c("Allow", "Disallow")) {
    for (value in names(ds_misses)) {
      expect_identical(
        ds_codes(type, value), ds_misses[[value]],
        label = paste(type, value)
      )
    }
  }
})

test_that("ROBO-rnjfbhvn: several dot segments on one line are one row", {
  expect_identical(ds_codes("Disallow", "/a/./b/../c"), "rule_dot_segment")
})

test_that("ROBO-rnjfbhvn: a NUL or a `#` cuts the value before the check", {
  nul <- c(
    charToRaw("User-agent: *\nDisallow: /a/"), as.raw(0),
    charToRaw("/./b\n")
  )
  expect_identical(
    robots_validate_text(nul)$diagnostics$code,
    c("nul_byte", "rule_cut_by_nul")
  )
  expect_identical(ds_codes("Disallow", "/a#/./b"), "rule_cut_by_comment")
})

# The parser keeps 16,663 bytes of a line, so a value cut right after `/.`
# has no bound, while one cut right after `/./` keeps its bound.
ds_cut <- function(tail_bytes) {
  pre <- "Disallow: /"
  filler <- strrep("a", 16663L - nchar(pre) - tail_bytes)
  robots_validate_text(
    paste0("User-agent: *\n", pre, filler, "/./b\n")
  )$diagnostics$code
}

test_that("ROBO-rnjfbhvn: the line buffer bounds the check", {
  expect_identical(ds_cut(2L), "line_too_long")
  expect_identical(ds_cut(3L), c("line_too_long", "rule_dot_segment"))
})

test_that("ROBO-rnjfbhvn: a byte the parser escapes leaves the check intact", {
  body <- c(charToRaw("User-agent: *\nDisallow: /a/./b"), as.raw(0xe9),
            charToRaw("\n"))
  expect_identical(
    robots_validate_text(body)$diagnostics$code,
    c("invalid_utf8", "rule_dot_segment")
  )
})

# Best of five runs, so a loaded machine cannot fail the ratio
# (test-cut-note-zqyqbudf.R).
ds_time <- function(body) {
  min(vapply(1:5, function(i) {
    system.time(robots_validate_text(body))[["elapsed"]]
  }, 0))
}

ds_rules <- function(n) {
  paste0(
    "User-agent: *\n",
    paste0("Disallow: /p", seq_len(n), "/./b\n", collapse = "")
  )
}

test_that("ROBO-rnjfbhvn: the check stays linear (ROBO-dbvmxcfw)", {
  skip_on_cran()
  small <- ds_time(ds_rules(1000L))
  large <- ds_time(ds_rules(4000L))
  expect_lt(large, 8 * max(small, 0.05))

  # About 16,000 bytes of `/..a`, a near miss at every `/`, so the scan
  # reads the whole value; against a same-length value with no dot.
  dots <- ds_time(paste0("User-agent: *\nDisallow: ", strrep("/..a", 4000L),
                         "\n"))
  plain <- ds_time(paste0("User-agent: *\nDisallow: ", strrep("/aaa", 4000L),
                          "\n"))
  expect_lt(dots, 8 * max(plain, 0.05))
})

# The message's claim and the code table's ADR 0002 clause, on google, bing
# and yandex alike: the matchers compare the dot segment as written, and the
# v1 default `url_normalization = "rfc3986"` removes it from the URL. The
# rfc9309 backend is capability_unavailable in every mode (ADR 0002), so it
# is not testable here.
ds_engines <- list(google = "Googlebot", bing = "bingbot", yandex = "Yandex")
ds_urls <- c("https://example.com/a/./b", "https://example.com/a/b")

test_that("ROBO-rnjfbhvn: a dot-segment rule matches only a raw URL", {
  for (backend in names(ds_engines)) {
    none <- robots_evaluate_text_v1(
      "User-agent: *\nDisallow: /a/./b\n", ds_urls, ds_engines[[backend]],
      backend, backend, url_normalization = "none"
    )$results
    expect_identical(none$url_decision, c("disallow", "allow"), label = backend)
    default <- robots_evaluate_text_v1(
      "User-agent: *\nDisallow: /a/./b\n", ds_urls, ds_engines[[backend]],
      backend, backend
    )$results
    expect_identical(
      default$url_decision, c("allow", "allow"), label = backend
    )
  }
})
