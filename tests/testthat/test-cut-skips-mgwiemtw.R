# The checks a body cut at max_bytes skips (ROBO-mgwiemtw). Each fixture is
# a whole file that draws its code; read as a cut body (`body_truncated =
# TRUE`, the cut at its end, so no partial line is dropped) it draws none.

cs_fixtures <- list(
  wildcard_disallows_not_inherited = paste0(
    "User-agent: *\nDisallow: /private/\n\n",
    "User-agent: Foobot\nDisallow: /tmp/\n"
  ),
  allow_reopens_wildcard_disallow = paste0(
    "User-agent: *\nDisallow: /company/search/\n\n",
    "User-agent: Foobot\nDisallow: /\nAllow: /company\n"
  ),
  wildcard_rules_not_inherited = paste0(
    "User-agent: *\nDisallow: /\nAllow: /pub\n\n",
    "User-agent: Foobot\nDisallow: /\n"
  ),
  user_agent_groups_same_rules =
    "User-agent: Foo\nDisallow: /x\n\nUser-agent: Bar\nDisallow: /x\n",
  empty_disallow_with_full_block = "User-agent: *\nDisallow:\nDisallow: /\n",
  rule_query_parameter_position = "User-agent: *\nDisallow: /search?page=\n",
  rule_slash_split = "User-agent: *\nDisallow: /a/\n",
  rule_end_anchor_query = "User-agent: *\nDisallow: /a$\n",
  allow_reopens_through_query =
    "User-agent: *\nDisallow: /my/\nAllow: */s/\n",
  rule_render_resource_blocked = "User-agent: *\nDisallow: /*.js\n",
  rule_prefix_sibling = "User-agent: *\nDisallow: /feed\nDisallow: /feeds\n",
  no_rules = "User-agent: *\n"
)

cs_validate <- function(text, cut = FALSE) {
  body <- if (is.raw(text)) text else charToRaw(text)
  if (cut) {
    validate_document_bytes(body, "s", "supplied", max_bytes = length(body),
                            body_truncated = TRUE)
  } else {
    validate_document_bytes(body, "s", "supplied")
  }
}

cs_cut_message <- function(x) {
  d <- x$diagnostics
  d$message[d$code == "body_truncated"]
}

test_that("ROBO-mgwiemtw: each skipped code fires uncut, not on a cut body", {
  for (code in names(cs_fixtures)) {
    uncut <- cs_validate(cs_fixtures[[code]])$diagnostics$code
    cut <- cs_validate(cs_fixtures[[code]], cut = TRUE)$diagnostics$code
    expect_true(code %in% uncut, label = paste(code, "uncut"))
    expect_false(code %in% cut, label = paste(code, "cut"))
    expect_true("body_truncated" %in% cut, label = paste(code, "cut row"))
  }
})

test_that("ROBO-mgwiemtw: the body_truncated message of a cut body", {
  x <- cs_validate(cs_fixtures$rule_slash_split, cut = TRUE)
  expect_identical(cs_cut_message(x), paste0(
    "Decoded body exceeded max_bytes (28); only its first 28 bytes up to ",
    "the last complete line were validated."
  ))
})

test_that("ROBO-mgwiemtw: a cut before any line break reads nothing", {
  body <- c(charToRaw("Disallow: /"), rep(charToRaw("x"), 30L))
  x <- cs_validate(body, cut = TRUE)
  expect_identical(x$document$line_count, 0L)
  expect_identical(x$diagnostics$code, "body_truncated")
  expect_match(cs_cut_message(x), "only its first 0 bytes", fixed = TRUE)
})

test_that("ROBO-mgwiemtw: NUL-hidden rules are still reported when cut", {
  text <- "User-agent: *\nDisallow: /x\n"
  body <- c(unlist(lapply(charToRaw(text), function(b) c(b, as.raw(0L)))),
            charToRaw("\n"))
  codes <- cs_validate(body, cut = TRUE)$diagnostics$code
  expect_true("rules_after_nul_removal" %in% codes)
  expect_false("no_rules" %in% codes)
  expect_identical(codes[length(codes)], "body_truncated")
})

test_that("ROBO-mgwiemtw: a cut compressed body keeps its own message", {
  body <- memCompress(charToRaw(strrep("User-agent: *\n", 20L)), "gzip")
  x <- cs_validate(body, cut = TRUE)
  expect_true("compressed_body" %in% x$diagnostics$code)
  expect_identical(cs_cut_message(x), sprintf(paste0(
    "Body exceeded max_bytes (%d); it was cut at the size limit and was not ",
    "read as rules by the validator."
  ), length(body)))
})
