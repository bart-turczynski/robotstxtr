# ROBO-bwpacxtq: under a named group that disallows `/` (a full block), the
# `User-agent: *` Disallows it lacks add nothing, so the check lists only the
# lost Allow rules, framed as possible exceptions.

bp_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

# The wildcard_rules_not_inherited rows of a document's validation.
bp_rows <- function(body) {
  x <- robots_validate_text(body)
  x$diagnostics[x$diagnostics$code == "wildcard_rules_not_inherited", ,
                drop = FALSE]
}

bp_tail <- paste0(
  " A crawler obeys only the groups that name it and ignores ",
  "`User-agent: *` once any group does; `User-agent: *` applies only to ",
  "crawlers no group names."
)

bp_full_note <- "A stricter policy for a named crawler may be deliberate."

test_that("a named full block lists only its lost * Allow", {
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Allow: /a", "Disallow: /b",
    "User-agent: x", "Disallow: /"
  ))
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$line, 4L)
  expect_identical(rows$message, paste0(
    "x obeys only this group, which disallows `/`, so this `User-agent: *` ",
    "Allow rule may be meant as an exception and does not apply to it: ",
    "Allow: /a (line 2). ", bp_full_note, bp_tail
  ))
  expect_no_match(rows$message, "Disallow: /b", fixed = TRUE)
})

test_that("several lost * Allows are framed as plural exceptions", {
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Allow: /a", "Disallow: /b", "Allow: /c",
    "User-agent: x", "Disallow: /"
  ))
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$message, paste0(
    "x obeys only this group, which disallows `/`, so these ",
    "`User-agent: *` Allow rules may be meant as exceptions and do not ",
    "apply to it: Allow: /a (line 2), Allow: /c (line 4). ",
    bp_full_note, bp_tail
  ))
})

test_that("the ExampleBot reproduction lists nothing", {
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Disallow: /admin/",
    "User-agent: ExampleBot", "Disallow: /"
  ))
  expect_identical(nrow(rows), 0L)
})

test_that("an Allow exception beside a lost Disallow lists the Allow only", {
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Disallow: /admin/", "Allow: /public/",
    "User-agent: ExampleBot", "Disallow: /"
  ))
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$line, 4L)
  expect_identical(rows$message, paste0(
    "ExampleBot obeys only this group, which disallows `/`, so this ",
    "`User-agent: *` Allow rule may be meant as an exception and does not ",
    "apply to it: Allow: /public/ (line 3). ", bp_full_note, bp_tail
  ))
  expect_no_match(rows$message, "/admin/", fixed = TRUE)
})

test_that("a full block with no lost * Allow gets no finding", {
  for (star in list(
    c("Disallow: /a", "Disallow: /b"),
    c("Allow: /", "Disallow: /b"),
    c("Allow: /*", "Disallow: /b", "Allow: /**$")
  )) {
    body <- bp_lines("User-agent: *", star, "User-agent: x", "Disallow: /")
    expect_identical(nrow(bp_rows(body)), 0L, label = body)
  }
})

test_that("a named Disallow: / plus a non-empty Allow is not a full block", {
  for (allow in c("Allow: /x", "Allow: /", "Allow: /*")) {
    rows <- bp_rows(bp_lines(
      "User-agent: *", "Allow: /a", "Disallow: /b",
      "User-agent: x", "Disallow: /", allow
    ))
    expect_identical(nrow(rows), 1L, label = allow)
    expect_identical(rows$message, paste0(
      "x obeys only this group, so these `User-agent: *` rules do not apply ",
      "to it: Allow: /a (line 2), Disallow: /b (line 3).", bp_tail
    ), label = allow)
  }
})

test_that("a named Disallow that ends in $ is not a full block", {
  for (value in c("/$", "/*$", "*$")) {
    rows <- bp_rows(bp_lines(
      "User-agent: *", "Allow: /a", "Disallow: /b",
      "User-agent: x", paste("Disallow:", value)
    ))
    expect_identical(nrow(rows), 1L, label = value)
    expect_identical(rows$message, paste0(
      "x obeys only this group, so these `User-agent: *` rules do not apply ",
      "to it: Allow: /a (line 2), Disallow: /b (line 3).", bp_tail
    ), label = value)
  }
})

test_that("an empty Allow does not cancel a full block", {
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Allow: /a", "Disallow: /b",
    "User-agent: x", "Disallow: /", "Allow:"
  ))
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$message, paste0(
    "x obeys only this group, which disallows `/`, so this `User-agent: *` ",
    "Allow rule may be meant as an exception and does not apply to it: ",
    "Allow: /a (line 2). ", bp_full_note, bp_tail
  ))
})

test_that("root-wide Disallow forms all make a full block", {
  for (value in c("/", "/*", "*", "**", "/**")) {
    rows <- bp_rows(bp_lines(
      "User-agent: *", "Allow: /a", "Disallow: /b",
      "User-agent: x", paste("Disallow:", value)
    ))
    expect_identical(nrow(rows), 1L, label = value)
    expect_match(rows$message, "Allow: /a (line 2). ", fixed = TRUE,
                 label = value)
    expect_no_match(rows$message, "Disallow: /b", fixed = TRUE, label = value)
  }
})

test_that("two named groups merge before the full-block test", {
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Allow: /a", "Disallow: /b",
    "User-agent: x", "Disallow: /a",
    "User-agent: x", "Disallow: /"
  ))
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$line, 4L)
  expect_identical(rows$message, paste0(
    "x obeys only the groups that name it, which together disallow `/`, ",
    "so this `User-agent: *` Allow rule may be meant as an exception and ",
    "does not apply to it: Allow: /a (line 2). ", bp_full_note, bp_tail
  ))
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Allow: /a", "Disallow: /b",
    "User-agent: x", "Disallow: /",
    "User-agent: x", "Allow: /x"
  ))
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$message, paste0(
    "x obeys only the groups that name it, so these `User-agent: *` rules ",
    "do not apply to it: Allow: /a (line 2), Disallow: /b (line 3).", bp_tail
  ))
})

test_that("a full block and a partial block with one loss get a row each", {
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Allow: /a",
    "User-agent: x", "User-agent: y", "Disallow: /",
    "User-agent: y", "Allow: /z"
  ))
  expect_identical(rows$line, c(3L, 3L))
  expect_identical(rows$message[[1L]], paste0(
    "x obeys only this group, which disallows `/`, so this `User-agent: *` ",
    "Allow rule may be meant as an exception and does not apply to it: ",
    "Allow: /a (line 2). ", bp_full_note, bp_tail
  ))
  expect_identical(rows$message[[2L]], paste0(
    "y obeys only the groups that name it, so this `User-agent: *` rule ",
    "does not apply to it: Allow: /a (line 2).", bp_tail
  ))
})

test_that("a blanket * Allow is never listed under a full block", {
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Allow: /", "Disallow: /b",
    "User-agent: x", "Disallow: /"
  ))
  expect_identical(nrow(rows), 0L)
})

test_that("two named agents sharing a full block are named as them", {
  rows <- bp_rows(bp_lines(
    "User-agent: *", "Allow: /a", "Disallow: /b",
    "User-agent: x", "User-agent: y", "Disallow: /"
  ))
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$line, 4L)
  expect_identical(rows$message, paste0(
    "x and y obey only this group, which disallows `/`, so this ",
    "`User-agent: *` Allow rule may be meant as an exception and does not ",
    "apply to them: Allow: /a (line 2). ", bp_full_note, bp_tail
  ))
})
