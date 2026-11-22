# ROBO-jdnluzbb: an Allow or Disallow value written as a full http(s) URL
# draws rule_missing_leading_slash, one row per line, as any value not led by
# `/` or `*` does. These pins hold the rows each full-URL shape gets.

# A body from pieces: a string is text, a raw vector is bytes.
fu_body <- function(...) {
  parts <- list(...)
  unlist(lapply(parts, function(p) if (is.raw(p)) p else charToRaw(p)))
}

# The validator's rows for line 2, a rule after `User-agent: *`.
fu_rows <- function(..., type = "Disallow: ") {
  d <- robots_validate_text(
    fu_body("User-agent: *\n", type, ..., "\n")
  )$diagnostics
  d[d$line == 2L, , drop = FALSE]
}

fu_message <- function(rows) {
  rows$message[rows$code == "rule_missing_leading_slash"]
}

fu_slash <- "rule_missing_leading_slash"

fu_today <- paste0(
  "Pattern does not start with '/' or '*'; URL paths always start with '/', ",
  "so this rule never matches."
)

# Each full-URL shape with the codes its line gets, in row order.
fu_shapes <- list(
  natu = list("https://shop.example/collections/produkty-bialko", fu_slash),
  http = list("http://e.example/a", fu_slash),
  upper = list("HTTPS://e.example/a", fu_slash),
  host = list("https://e.example", fu_slash),
  host_slash = list("https://e.example/", fu_slash),
  host_query = list("https://e.example?x=1", fu_slash),
  query = list("https://e.example/a?b=1&c=2", fu_slash),
  lower_escape = list(
    "https://e.example/a?b=C%2f", c(fu_slash, "rule_lowercase_escape")
  ),
  port = list("https://e.example:8443/a", fu_slash),
  star = list("https://e.example/a*b", fu_slash),
  dollar = list("https://e.example/a$", fu_slash),
  encoded = list("https://e.example/caf%C3%A9", fu_slash),
  raw_utf8 = list(
    fu_body("https://e.example/caf", as.raw(c(0xc3, 0xa9))), fu_slash
  ),
  quote = list("https://e.example/a'b", fu_slash),
  dots = list("https://e.example/a/./b/../c", fu_slash),
  only_dot = list("https://e.example/.", fu_slash),
  blanks = list("  https://e.example/a", fu_slash),
  stray_percent = list(
    "https://e.example/a%zz", c(fu_slash, "rule_invalid_percent_escape")
  ),
  lower_path = list(
    "https://e.example/a%2f", c(fu_slash, "rule_lowercase_escape")
  )
)

test_that("ROBO-jdnluzbb: each full-URL shape keeps its codes and severity", {
  for (name in names(fu_shapes)) {
    rows <- fu_rows(fu_shapes[[name]][[1L]])
    expect_identical(rows$code, fu_shapes[[name]][[2L]], label = name)
    expect_true(all(rows$severity == "warning"), label = name)
    expect_length(fu_message(rows), 1L)
  }
})

test_that("ROBO-jdnluzbb: a full-URL value gets today's message", {
  for (name in names(fu_shapes)) {
    rows <- fu_rows(fu_shapes[[name]][[1L]])
    expect_identical(fu_message(rows), fu_today, label = name)
  }
})

test_that("ROBO-jdnluzbb: values that are no absolute URL keep the message", {
  for (value in c("https://", "https:/x", "http:e.example/a", "ftp://e.x/a",
                  "httpsx://e.example/a", "private/")) {
    rows <- fu_rows(value)
    expect_identical(rows$code, fu_slash, label = value)
    expect_identical(fu_message(rows), fu_today, label = value)
  }
})

test_that("ROBO-jdnluzbb: a fragment is cut by the parser first", {
  rows <- fu_rows("https://e.example/a#f")
  expect_identical(rows$code, c("rule_cut_by_comment", fu_slash))
  expect_identical(fu_message(rows), fu_today)
})

test_that("ROBO-jdnluzbb: a blank or control byte keeps today's message", {
  rows <- fu_rows("https://e.example/a b")
  expect_identical(rows$code, c(fu_slash, "rule_inner_whitespace"))
  expect_identical(fu_message(rows), fu_today)
  rows <- fu_rows("https://e.example/a?q=1\tb")
  expect_identical(rows$code, c(fu_slash, "rule_inner_whitespace"))
  expect_identical(fu_message(rows), fu_today)
  rows <- fu_rows(fu_body("https://e.example/a", as.raw(0x01), "b"))
  expect_identical(rows$code, c(fu_slash, "rule_control_character"))
  expect_identical(fu_message(rows), fu_today)
  rows <- fu_rows(fu_body("https://e.example/a", as.raw(0x7f)))
  expect_identical(rows$code, fu_slash)
  expect_identical(fu_message(rows), fu_today)
})

test_that("ROBO-jdnluzbb: an invisible prefix keeps its sentence", {
  rows <- fu_rows(fu_body(as.raw(c(0xef, 0xbb, 0xbf)), "https://e.example/a"))
  expect_identical(rows$code, fu_slash)
  expect_identical(
    fu_message(rows),
    paste0(fu_today, " It starts with an invisible character (U+FEFF).")
  )
})

test_that("ROBO-jdnluzbb: invalid UTF-8 in the URL keeps today's message", {
  rows <- fu_rows(fu_body("https://e.example/caf", as.raw(0xe9)))
  expect_identical(rows$code, c("invalid_utf8", fu_slash))
  expect_identical(fu_message(rows), fu_today)
})

test_that("ROBO-jdnluzbb: a value at the line buffer keeps today's message", {
  rows <- fu_rows("https://e.example/", strrep("a", 16663L))
  expect_identical(rows$code, c("line_too_long", fu_slash))
  expect_identical(fu_message(rows), fu_today)
})

test_that("ROBO-jdnluzbb: a NUL in the URL", {
  rows <- fu_rows(fu_body("https://e.example/a", as.raw(0x00), "b"))
  expect_identical(rows$code, c("nul_byte", "rule_cut_by_nul", fu_slash))
  expect_identical(fu_message(rows), fu_today)
})

test_that("ROBO-jdnluzbb: the missing-colon form never reaches the check", {
  # The scheme's `:` ends the key, so the key is `Disallow https` (a prefix
  # Google accepts) and the value `//e.example/m` is led by `/`.
  rows <- fu_rows("https://e.example/m", type = "Disallow ")
  expect_identical(rows$code, "accepted_directive_prefix")
})

test_that("ROBO-jdnluzbb: an empty value draws no leading-slash row", {
  expect_identical(fu_rows("")$code, "allow_all_disallow")
})
