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
# A rule line `directive: /private/<tail>`.
ic_rule <- function(directive, tail) {
  sprintf("%s: /private/%s", directive, tail)
}

# Google's decision for `token` on `path`, the reading the rows state.
ic_google <- function(body, path, token = "ExampleBot") {
  robots_evaluate_text_v1(body, paste0("https://example.com", path), token,
                          "google", "google")$results$url_decision
}

ic_table <- validation_lookalike_code_points
ic_class <- ic_table[ic_table$kind %in% c("space", "invisible"), ]
ic_value_clause <- " Bing and Yandex may read this value differently."
ic_rule_clause <- " Bing and Yandex may read this rule differently."

# One point of each property class the ticket lists, none of them in the
# ROBO-jsecjjyo table: Zl, Zp, Cf (directional marks, bidi embeddings and
# isolates, U+061C, U+180E), C1, a tag, a variation selector, a Hangul
# filler and two unassigned default-ignorable points.
ic_sample <- c(0x2028, 0x2029, 0x200E, 0x200F, 0x202A, 0x202E, 0x2066,
               0x2069, 0x061C, 0x180E, 0x0085, 0xE0041, 0xFE0F, 0x3164,
               0x2065, 0xE0080)

ic_control <- ic_lines(paste0("User-agent: *", ic_chr(0x2028)),
                       ic_rule("Disallow", ic_chr(0x2028)))

# The name a row gives `point` at byte `at`.
ic_named <- function(point, at) {
  name <- ic_table$name[match(point, ic_table$point)]
  if (is.na(name)) {
    sprintf("U+%04X, an unassigned default-ignorable character, at byte %d",
            point, at)
  } else {
    sprintf("U+%04X %s at byte %d", point, name, at)
  }
}

# The trailing warning for one character: `named` as ic_named() gives it.
ic_trailing_message <- function(named, escaped, directive, shown) {
  paste0(
    "Pattern ends in an invisible, space or separator character: ", named,
    ". Google's parser trims only ASCII whitespace from a value, so it ",
    "keeps it and percent-encodes it as ", escaped, ": this ", directive,
    " matches only URLs with ", escaped, " at that point, so it does not ",
    if (directive == "Allow") "allow" else "block", " '", shown,
    "' or any other URL without it there.", ic_rule_clause
  )
}

test_that("Google's reading of the ticket's control and trailing values", {
  # The control: Google reads no `*` line and no rule for /private/x.
  expect_identical(ic_google(ic_control, "/private/x"), "allow")
  plain <- ic_lines("User-agent: *", "Disallow: /private/")
  expect_identical(ic_google(plain, "/private/x"), "disallow")
  # A trailing non-ASCII space or format character is kept and
  # percent-encoded: the rule covers only URLs holding it there.
  for (point in c(0x00A0, 0x2028, 0x200E)) {
    escaped <- ic_escaped(point)
    body <- ic_lines("User-agent: *", ic_rule("Disallow", ic_chr(point)))
    label <- sprintf("U+%04X", point)
    expect_identical(ic_google(body, "/private/x"), "allow", label = label)
    expect_identical(ic_google(body, "/private/"), "allow", label = label)
    expect_identical(ic_google(body, sprintf("/private/%s", escaped)),
                     "disallow", label = label)
    body <- ic_lines("User-agent: *", "Disallow: /",
                     ic_rule("Allow", ic_chr(point)))
    expect_identical(ic_google(body, "/private/x"), "disallow", label = label)
    expect_identical(ic_google(body, sprintf("/private/%sx", escaped)),
                     "allow", label = label)
  }
})

test_that("the class table is the Unicode property class", {
  # No duplicates, no ASCII, U+00AD keeps its look-alike row.
  expect_false(anyDuplicated(ic_table$point) > 0L)
  expect_false(any(ic_class$point < 0x80))
  expect_identical(ic_table$kind[ic_table$point == 0x00AD], "lookalike")
  # Kinds: Zs, Zl and Zp are spaces spelled as an ASCII space; the rest
  # are invisible and dropped.
  spaces <- c(0x00A0, 0x1680, 0x2000:0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
              0x3000)
  expect_setequal(ic_class$point[ic_class$kind == "space"], spaces)
  expect_true(all(ic_class$ascii[ic_class$kind == "space"] == " "))
  expect_true(all(ic_class$ascii[ic_class$kind == "invisible"] == ""))
  # Each family the ticket names, Hangul fillers and C1 among them.
  expect_true(all(c(0x0080:0x009F, 0x034F, 0x061C, 0x115F, 0x1160, 0x17B4,
                    0x180B:0x180F, 0x200B:0x200F, 0x202A:0x202E,
                    0x2060:0x206F, 0x3164, 0xFE00:0xFE0F, 0xFEFF, 0xFFA0,
                    0xFFF0:0xFFF8, 0xE0000:0xE0FFF) %in% ic_class$point))
  # Neither C0 nor visible neighbors.
  expect_false(any(c(0x0009, 0x0020, 0x007F, 0x00A1, 0x2010, 0x2190, 0xFFFD)
                   %in% ic_class$point))
  # The jsecjjyo rows keep their names.
  expect_identical(
    ic_table$name[match(c(0x00A0, 0x200B, 0x2060, 0xFEFF, 0x3000),
                        ic_table$point)],
    c("NO-BREAK SPACE", "ZERO WIDTH SPACE", "WORD JOINER",
      "ZERO WIDTH NO-BREAK SPACE", "IDEOGRAPHIC SPACE")
  )
  # Assigned points are named; only unassigned default-ignorable ones not.
  unnamed <- ic_class$point[is.na(ic_class$name)]
  expect_true(all(unnamed %in% c(0x2065, 0xFFF0:0xFFF8, 0xE0000:0xE0FFF)))
  expect_identical(ic_table$name[ic_table$point == 0x0085],
                   "NEXT LINE (NEL)")
})

test_that("every class point is named in a value and found before a key", {
  values <- vapply(ic_class$point, function(point) {
    ic_chr(c(0x61, point, 0x62))
  }, "")
  cache <- new.env(parent = emptyenv())
  # One expectation per check over the whole table, the failing points
  # named: thousands of single expectations would dominate the run time.
  space <- ic_class$kind == "space"
  named <- vapply(seq_along(values), function(k) {
    ic_named(ic_class$point[[k]], 2L)
  }, "")
  ok <- vapply(seq_along(values), function(k) {
    note <- lookalike_note(values[[k]], "value")
    key <- validation_hidden_key(paste0(ic_chr(ic_class$point[[k]]),
                                        "Disallow"), cache)
    isTRUE(note$unseen) &&
      grepl(named[[k]], note$sentence, fixed = TRUE) &&
      identical(note$spelled, if (space[[k]]) "a b" else "ab") &&
      identical(key$type, "disallow")
  }, logical(1L))
  expect_identical(sprintf("U+%04X", ic_class$point[!ok]), character())
  facts <- user_agent_cut_facts(values)
  expect_identical(facts$repaired_value,
                   ifelse(ic_class$kind == "space", "a b", "ab"))
})

test_that("the control's cut row names U+2028 and its rule warns", {
  x <- robots_validate_text(ic_control)
  expect_setequal(ic_codes(x), c("1 warning user_agent_cut",
                                 "2 warning rule_trailing_invisible_character"))
  cut <- ic_rows(x, "user_agent_cut")$message
  expect_true(grepl(paste0(
    "The value holds U+2028 LINE SEPARATOR at byte 2, which is a line or ",
    "paragraph separator; written in ASCII the value is '* '"
  ), cut, fixed = TRUE))
  expect_true(endsWith(cut, ic_value_clause))
  expect_identical(
    ic_rows(x, "rule_trailing_invisible_character")$message,
    ic_trailing_message(ic_named(0x2028, 10L), "%E2%80%A8", "Disallow",
                        "/private/")
  )
})

test_that("each property class is named in a User-agent value and a key", {
  for (point in ic_sample) {
    label <- sprintf("U+%04X", point)
    x <- ic_text(paste0("User-agent: a", ic_chr(point), "b"), "Disallow: /")
    # info -> warning: the value now holds a named character (jsecjjyo).
    expect_identical(ic_codes(x), "1 warning user_agent_cut", label = label)
    message <- x$diagnostics$message
    expect_true(grepl(ic_named(point, 2L), message, fixed = TRUE),
                label = label)
    expect_true(endsWith(message, ic_value_clause), label = label)
    expect_false(grepl("Bing (does|reads)|Yandex (does|reads)", message),
                 label = label)
    x <- ic_text("User-agent: *", paste0(ic_chr(point), "Disallow: /private/"))
    expect_identical(ic_codes(x), c("2 warning unknown_directive",
                                    "NA info no_rules"), label = label)
    message <- ic_rows(x, "unknown_directive")$message
    expect_true(grepl(paste0("The key holds ", ic_named(point, 1L)), message,
                      fixed = TRUE), label = label)
    expect_true(grepl("Without it, this is a Disallow line", message,
                      fixed = TRUE), label = label)
  }
  # A leading line separator before Googlebot: the value is meant as
  # Googlebot, which Google does not read here.
  body <- ic_lines(paste0("User-agent: ", ic_chr(0x2028), "Googlebot"),
                   "Disallow: /x")
  expect_identical(ic_google(body, "/x", "Googlebot"), "allow")
  row <- ic_rows(robots_validate_text(body), "user_agent_cut")
  expect_identical(row$severity, "warning")
  expect_true(grepl("If this line was meant as `Googlebot`", row$message,
                    fixed = TRUE))
})

test_that("a trailing class character in a rule value is one warning", {
  for (point in c(0x00A0, 0x2028, 0x200E)) {
    for (directive in c("Disallow", "Allow")) {
      for (suffix in c("", "$", " # c", " \t ", "$ # c")) {
        label <- sprintf("U+%04X %s '%s'", point, directive, suffix)
        x <- ic_text("User-agent: *",
                     ic_rule(directive, paste0(ic_chr(point), suffix)))
        rows <- x$diagnostics[x$diagnostics$line == 2L, , drop = FALSE]
        expect_identical(rows$code, "rule_trailing_invisible_character",
                         label = label)
        expect_identical(rows$severity, "warning", label = label)
        expect_identical(
          rows$message,
          ic_trailing_message(ic_named(point, 10L), ic_escaped(point),
                              directive, "/private/"),
          label = label
        )
        expect_identical(x$documents$validation_status, "warning",
                         label = label)
      }
    }
  }
  # Two trailing characters: both named, the escape spans them.
  x <- ic_text("User-agent: *",
               ic_rule("Disallow", ic_chr(0x200E, 0x00A0)))
  expect_identical(ic_codes(x), "2 warning rule_trailing_invisible_character")
  expect_identical(x$diagnostics$message, paste0(
    "Pattern ends in invisible, space or separator characters: ",
    ic_named(0x200E, 10L), ", ", ic_named(0x00A0, 13L), ". Google's parser ",
    "trims only ASCII whitespace from a value, so it keeps them and ",
    "percent-encodes them as %E2%80%8E%C2%A0: this Disallow matches only ",
    "URLs with %E2%80%8E%C2%A0 at that point, so it does not block ",
    "'/private/' or any other URL without them there.", ic_rule_clause
  ))
  # U+00AD, a look-alike row, and an unassigned point count too.
  for (point in c(0x00AD, 0xE0080, 0x0085)) {
    x <- ic_text("User-agent: *", ic_rule("Disallow", ic_chr(point)))
    expect_identical(ic_codes(x),
                     "2 warning rule_trailing_invisible_character",
                     label = sprintf("U+%04X", point))
    expect_true(grepl(ic_named(point, 10L), x$diagnostics$message,
                      fixed = TRUE), label = sprintf("U+%04X", point))
  }
  # No message advises a rewrite.
  expect_false(grepl("remove|delete|write ", x$diagnostics$message,
                     ignore.case = TRUE))
})

test_that("an interior class character keeps today's rows", {
  # Interior U+00A0 stays silent, interior U+200E stays info.
  x <- ic_text("User-agent: *",
               ic_rule("Disallow", paste0(ic_chr(0x00A0), "x")))
  expect_identical(nrow(x$diagnostics), 0L)
  x <- ic_text("User-agent: *",
               ic_rule("Disallow", paste0(ic_chr(0x200E), "x")))
  expect_identical(ic_codes(x), "2 info rule_invisible_character")
  expect_identical(x$documents$validation_status, "valid")
  # The same character inside and at the end: the info row names the
  # inside one, the warning the trailing one.
  x <- ic_text("User-agent: *",
               paste0("Disallow: /a", ic_chr(0x200E), "b/", ic_chr(0x200E)))
  expect_identical(ic_codes(x), c("2 warning rule_trailing_invisible_character",
                                  "2 info rule_invisible_character"))
  expect_true(grepl("U+200E first at byte 3", x$diagnostics$message[[2L]],
                    fixed = TRUE))
  expect_true(grepl(ic_named(0x200E, 8L), x$diagnostics$message[[1L]],
                    fixed = TRUE))
  # A trailing U+200E beside another invisible inside: the info row keeps
  # only the inside one.
  x <- ic_text("User-agent: *",
               paste0("Disallow: /a", ic_chr(0x200B), "b/", ic_chr(0x200E)))
  expect_true(grepl("Pattern holds an invisible or formatting character: ",
                    x$diagnostics$message[[2L]], fixed = TRUE))
  expect_false(grepl("U+200E", x$diagnostics$message[[2L]], fixed = TRUE))
})

test_that("edge inputs draw no trailing row", {
  silent <- function(body, label) {
    x <- robots_validate_text(body)
    expect_false("rule_trailing_invisible_character" %in% x$diagnostics$code,
                 label = label)
  }
  ua <- "User-agent: *\n"
  # Invalid UTF-8 at the tail: invalid_utf8 owns it.
  silent(paste0(ua, "Disallow: /private/", ic_chr(0x00A0), "\xc2\n"),
         "invalid tail")
  # Latin-1 A0 is not U+00A0.
  silent(paste0(ua, "Disallow: /private/\xa0\n"), "latin1")
  # A NUL before the character cuts the value.
  silent(c(charToRaw(paste0(ua, "Disallow: /private/")), as.raw(0x00),
           charToRaw(ic_chr(0x00A0)), charToRaw("\n")), "nul")
  # An empty value, and a value that is only the character (it does not
  # start with `/`: rule_missing_leading_slash).
  silent(paste0(ua, "Disallow:\n"), "empty")
  x <- ic_text("User-agent: *", paste0("Disallow: ", ic_chr(0x00A0)))
  expect_identical(ic_codes(x), "2 warning rule_missing_leading_slash")
  # A character split by the line buffer, and one that ends the buffer with
  # the line going on past it: the value's end is not the line's.
  head <- "Disallow: /"
  fill <- validation_line_bytes - nchar(head) - 1L
  silent(paste0(ua, head, strrep("a", fill), ic_chr(0x00A0), "\n"), "split")
  silent(paste0(ua, head, strrep("a", fill - 1L), ic_chr(0x00A0),
                strrep("b", 10L), "\n"), "oversized")
  # In a comment.
  silent(paste0(ua, "Disallow: /private/ # ", ic_chr(0x00A0), "\n"),
         "comment")
})
