# ROBO-zvhrayhx: the matcher reads a User-agent value only up to its first
# byte outside [A-Za-z_-] (src/robots.cc, RobotsMatcher::ExtractUserAgent),
# so `Foo Bot` names Foo, `Bot2` names Bot and `*bot` names no crawler. The
# validator reports `user_agent_cut` on every such value, `Googlebot/2.1`
# included; ROBO-txnzyugl made it info unless a Google crawler reads the cut
# and added the effect to the message. A global line (`*` alone or followed
# by whitespace) is exempt: its group still applies to every crawler.

uac_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

uac_body <- function(value) {
  uac_lines(paste0("User-agent: ", value), "Disallow: /x")
}

uac_rows <- function(body) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == "user_agent_cut", , drop = FALSE]
}

uac_no_star <- paste0("Unless another group names it, a crawler going by ",
                      "the full value gets no rules from Google's matcher: ",
                      "the file has no `User-agent: *` group.")

uac_other <- paste0("Only Google's parser shortens the value, and Google's ",
                    "crawlers do not go by it, so nothing changes for them; ",
                    "how the named crawler's own parser reads it is ",
                    "unknown.")

uac_read_as <- function(token, tail = uac_other) {
  paste(sprintf(paste0(
    "User-agent value is read as '%s' by Google's matcher, which stops at ",
    "the first character outside letters, '_' and '-'. There the full ",
    "written value does not match this record, and a crawler whose token ",
    "is '%s' matches it instead."
  ), token, token), uac_no_star, tail)
}

uac_none <- paste(
  paste0("User-agent value names no crawler for Google's matcher, which ",
         "reads a product token only from a leading run of letters, '_' ",
         "and '-', so there this line matches no crawler."),
  uac_no_star, uac_other
)

test_that("a value cut at a space is one info row naming the token read", {
  x <- robots_validate_text(uac_body("Foo Bot"))
  expect_identical(x$documents$validation_status, "valid")
  d <- x$diagnostics
  expect_identical(d$code, "user_agent_cut")
  expect_identical(d$severity, "info")
  expect_identical(d$line, 1L)
  expect_identical(d$directive, "user-agent")
  expect_identical(d$raw_text, "User-agent: Foo Bot")
  expect_identical(d$message, uac_read_as("Foo"))
})

test_that("each cut names the token the matcher reads", {
  expect_identical(uac_rows(uac_body("Bot2"))$message, uac_read_as("Bot"))
  expect_identical(
    uac_rows(uac_body("Googlebot/2.1"))$message,
    uac_read_as("Googlebot", paste0(
      "'Googlebot' is the Google crawler token the value names, so nothing ",
      "changes for that crawler."
    ))
  )
  expect_identical(uac_rows(uac_body("*bot"))$message, uac_none)
  expect_identical(uac_rows(uac_body("2bot"))$message, uac_none)
})

test_that("a value the matcher reads whole, or as global, is not flagged", {
  for (value in c("FooBot", "FooBot   # c", "foo_bar-baz", "*", "* foo",
                  "*\tfoo")) {
    expect_identical(nrow(uac_rows(uac_body(value))), 0L, label = value)
  }
  x <- robots_validate_text(uac_body(""))
  expect_false("user_agent_cut" %in% x$diagnostics$code)
  expect_true("empty_user_agent" %in% x$diagnostics$code)
})

test_that("two cut lines in one group give a row each, at its own line", {
  d <- uac_rows(uac_lines("User-agent: Foo Bot", "User-agent: Bot2",
                          "User-agent: Baz", "Disallow: /x"))
  expect_identical(d$line, c(1L, 2L))
  expect_identical(d$message, c(uac_read_as("Foo"), uac_read_as("Bot")))
})

test_that("a non-UTF-8 byte cuts the value without an R error", {
  body <- as.raw(c(charToRaw("User-agent: B"), 0xe4,
                   charToRaw("r\nDisallow: /x\n")))
  x <- robots_validate_text(body)
  expect_true("invalid_utf8" %in% x$diagnostics$code)
  d <- uac_rows(body)
  expect_identical(d$message, uac_read_as("B"))
  expect_true(validUTF8(d$message))
  led <- as.raw(c(charToRaw("User-agent: "), 0xe4,
                  charToRaw("r\nDisallow: /x\n")))
  expect_identical(uac_rows(led)$message, uac_none)
})

test_that("a NUL in the line leaves only nul_byte", {
  body <- as.raw(c(charToRaw("User-agent: Foo"), 0x00,
                   charToRaw("Bot\nDisallow: /x\n")))
  codes <- robots_validate_text(body)$diagnostics$code
  expect_true("nul_byte" %in% codes)
  expect_false("user_agent_cut" %in% codes)
})

test_that("an empty body has no cut", {
  expect_identical(nrow(uac_rows("")), 0L)
})

test_that("a body cut at max_bytes is still checked on the lines read", {
  body <- charToRaw(uac_lines("User-agent: Foo Bot", "Disallow: /x",
                              strrep("#", 200L)))[seq_len(40L)]
  x <- validate_document_bytes(
    body, "s", "supplied", max_bytes = 40L, body_truncated = TRUE
  )
  expect_identical(x$diagnostics$code, c("user_agent_cut", "body_truncated"))
  expect_identical(x$diagnostics$line, c(1L, NA_integer_))
})

test_that("a value past the line buffer still names the token read", {
  d <- uac_rows(uac_body(paste0("Foo ", strrep("a", 17000L))))
  expect_identical(d$message, uac_read_as("Foo"))
})

test_that("a cut line still forms its group for the matcher", {
  x <- allowed_by_robots_text(uac_body("Foo Bot"), "http://e/x", "Foo")
  expect_false(x$results$allowed)
})
