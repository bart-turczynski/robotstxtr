# ROBO-uphlyomt: invisible, space and separator characters chosen by Unicode
# property (Zs other than U+0020, Zl, Zp, Cf, Default_Ignorable_Code_Point
# and the C1 controls) in User-agent values, before a key and at the end of
# an Allow or Disallow value. Fixtures are synthetic and built from code
# points with ic_chr(), so this file stays ASCII (R refuses bidi controls
# written as \u escapes).

ic_chr <- function(...) intToUtf8(c(...))
ic_lines <- function(...) enc2utf8(paste0(paste(c(...), collapse = "\n"), "\n"))
ic_text <- function(...) robots_validate_text(ic_lines(...))
ic_rows <- function(x, code) {
  d <- x$diagnostics
  d[d$code == code, , drop = FALSE]
}
# The UTF-8 bytes of `point` as the parser escapes them: U+00A0 is %C2%A0.
ic_escaped <- function(point) {
  paste(sprintf("%%%02X", as.integer(charToRaw(ic_chr(point)))),
        collapse = "")
}
ic_codes <- function(x) {
  d <- x$diagnostics
  paste(d$line, d$severity, d$code)
}

# Google's decision for `token` on `path`, the reading the rows state.
ic_google <- function(body, path, token = "ExampleBot") {
  robots_evaluate_text_v1(body, paste0("https://example.com", path), token,
                          "google", "google")$results$url_decision
}

# One point of each property class the ticket lists, none of them in the
# ROBO-jsecjjyo table.
ic_sample <- c(0x2028, 0x2029, 0x200E, 0x200F, 0x202A, 0x202E, 0x2066,
               0x2069, 0x061C, 0x180E, 0x0085, 0xE0041, 0xFE0F, 0x3164,
               0x2065, 0xE0080)

ic_control <- ic_lines(paste0("User-agent: *", ic_chr(0x2028)),
                       paste0("Disallow: /private/", ic_chr(0x2028)))

test_that("Google's reading of the ticket's control and trailing values", {
  # The control: Google reads no `*` line and no rule for /private/x.
  expect_identical(ic_google(ic_control, "/private/x"), "allow")
  plain <- ic_lines("User-agent: *", "Disallow: /private/")
  expect_identical(ic_google(plain, "/private/x"), "disallow")
  # A trailing non-ASCII space or format character is kept and
  # percent-encoded: the rule covers only URLs holding it there.
  for (point in c(0x00A0, 0x2028, 0x200E)) {
    escaped <- ic_escaped(point)
    body <- ic_lines("User-agent: *",
                     paste0("Disallow: /private/", ic_chr(point)))
    label <- sprintf("U+%04X", point)
    expect_identical(ic_google(body, "/private/x"), "allow", label = label)
    expect_identical(ic_google(body, "/private/"), "allow", label = label)
    expect_identical(ic_google(body, paste0("/private/", escaped)),
                     "disallow", label = label)
    body <- ic_lines("User-agent: *", "Disallow: /",
                     paste0("Allow: /private/", ic_chr(point)))
    expect_identical(ic_google(body, "/private/x"), "disallow", label = label)
    expect_identical(ic_google(body, paste0("/private/", escaped, "x")),
                     "allow", label = label)
  }
})

test_that("today: the control's cut row names no U+2028", {
  x <- robots_validate_text(ic_control)
  expect_identical(ic_codes(x), "1 warning user_agent_cut")
  expect_false(grepl("U+2028", x$diagnostics$message, fixed = TRUE))
})

test_that("today: a class point outside the table is named nowhere", {
  for (point in ic_sample) {
    label <- sprintf("U+%04X", point)
    x <- ic_text(paste0("User-agent: a", ic_chr(point), "b"), "Disallow: /")
    expect_identical(ic_codes(x), "1 info user_agent_cut", label = label)
    expect_false(grepl(label, x$diagnostics$message, fixed = TRUE),
                 label = label)
    x <- ic_text("User-agent: *", paste0(ic_chr(point), "Disallow: /private/"))
    expect_identical(ic_codes(x), c("2 warning unknown_directive",
                                    "NA info no_rules"), label = label)
    expect_false(any(grepl(label, x$diagnostics$message, fixed = TRUE)),
                 label = label)
  }
})

test_that("today: a trailing character draws no warning", {
  x <- ic_text("User-agent: *", paste0("Disallow: /private/", ic_chr(0x00A0)))
  expect_identical(nrow(x$diagnostics), 0L)
  x <- ic_text("User-agent: *", paste0("Disallow: /private/", ic_chr(0x200E)))
  expect_identical(ic_codes(x), "2 info rule_invisible_character")
  expect_identical(x$documents$validation_status, "valid")
})
