# ROBO-dbvmxcfw: validate_document_bytes() gathers its diagnostics as column
# chunks and builds the frame once. These pins fix what the frame holds before
# that change, for bodies that reach every emission path: values, column
# types, encoding marks, row names and row order. seam_digest() reduces a
# frame to an MD5 of its canonical text (helper-matcher-seam-pin-bukqpjli.R);
# `paste0(code, "@", line)` lists the same rows in order.

linear_join <- function(lines) {
  unlist(lapply(lines, function(line) c(line, as.raw(0x0a))),
         use.names = FALSE)
}

# Every emission path in one document: a leading BOM, a misplaced BOM, invalid
# UTF-8 in a comment and in rules (the batch), the per-line checks, the
# AI-training batch, the wildcard and tied-disallow checks, a duplicate_rule
# batch, a non-ASCII value and a line past the parser's buffer.
linear_body_main <- function() {
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  e9 <- as.raw(0xe9)
  linear_join(list(
    c(bom, charToRaw("User-agent: *")),
    charToRaw("Disallow: /private"),
    c(bom, charToRaw("Disallow: /misplaced")),
    c(charToRaw("# caf"), e9, charToRaw(" comment")),
    c(charToRaw("# more"), e9, charToRaw(" comment")),
    c(charToRaw("Disallow: /caf"), e9),
    c(charToRaw("Allow: /bad"), e9, charToRaw("x")),
    charToRaw("Disallow /missing-colon"),
    charToRaw("Dissallow: /typo"),
    charToRaw("Disalow: /typo2"),
    charToRaw("Disallowed: /prefix"),
    charToRaw("Crawl-delay: 5"),
    charToRaw("Content-Signal: search=yes"),
    charToRaw("Host: example.com"),
    charToRaw("Foo: bar"),
    charToRaw("malformed line here"),
    charToRaw("User-agent:"),
    charToRaw("Disallow: "),
    charToRaw("Allow: /a#b"),
    charToRaw("Disallow: missing-slash"),
    charToRaw("Allow: /a%2fb"),
    charToRaw("Sitemap:"),
    charToRaw("Sitemap: not a url"),
    charToRaw("Disallow: café"),
    charToRaw("User-agent: Foo.Bot"),
    charToRaw("Disallow: /dup"),
    charToRaw("Disallow: /dup"),
    charToRaw("Disallow: /dup"),
    charToRaw("Disallow: /same"),
    charToRaw("Allow: /same"),
    charToRaw("User-agent: __usage_ai_training"),
    charToRaw("User-agent: __usage_ai-training"),
    charToRaw("Disallow: /ai"),
    charToRaw("User-agent: Bot-A"),
    charToRaw("Allow: /x"),
    charToRaw("User-agent:"),
    charToRaw("Disallow: /after-empty-agent"),
    charToRaw("User-agent: Bot-C"),
    charToRaw("User-agent: __usage_ai-training"),
    charToRaw("Disallow: /z"),
    c(charToRaw("Disallow: /"), rep(charToRaw("a"), 17000L))
  ))
}

# UTF-16 text: a NUL after each character, so the rules appear only once the
# NULs are dropped (nul_byte, malformed_line and rules_after_nul_removal).
linear_body_utf16 <- function() {
  chars <- strsplit("User-agent: *\nDisallow: /x\n", "", fixed = TRUE)[[1L]]
  unlist(lapply(chars, function(ch) c(charToRaw(ch), as.raw(0L))),
         use.names = FALSE)
}

# An HTML page with a rule and no User-agent line: missing_user_agent and
# html_body are document-level rows (line NA).
linear_body_html <- function() {
  charToRaw("<!DOCTYPE html>\nDisallow: /x\n")
}

linear_body_clean <- function() {
  charToRaw("User-agent: *\nDisallow: /private\n")
}

# The frame's row names and attribute names, as seam_digest()'s extra lines.
linear_frame_extra <- function(frame) {
  c(
    paste("row.names", paste(.row_names_info(frame, 0L), collapse = ",")),
    paste("attributes", paste(names(attributes(frame)), collapse = ","))
  )
}

linear_rows <- function(frame) {
  paste0(frame$code, "@", frame$line)
}

# robots_fetch() handlers: a redirect to another site, a 2xx body cut at
# max_bytes, and a 203 (another 2xx, which keeps its body).
linear_redirect_handler <- function(req) {
  if (identical(req$url, "http://example.com/robots.txt")) {
    fake_response(301L, url = req$url,
                  headers = list(Location = "http://example.net/robots.txt"))
  } else {
    fake_response(200L, url = req$url,
                  headers = list(`Content-Type` = "text/plain"),
                  body = charToRaw("User-agent: *\nDisallow: private\n"))
  }
}

linear_cut_body <- function() {
  charToRaw(paste0("User-agent: *\n", strrep("Disallow: x\n", 20L)))
}

linear_fetch_body <- function(status, body) {
  function(req) fake_response(status, url = req$url, body = body)
}

test_that("the frame of a body on every emission path is pinned", {
  d <- robots_validate_text(linear_body_main())$diagnostics
  expect_identical(
    linear_rows(d),
    c(
      "byte_order_mark@1",
      "misplaced_byte_order_mark@3",
      "invalid_utf8_comment@4",
      "invalid_utf8_comment@5",
      "invalid_utf8@6",
      "invalid_utf8@7",
      "malformed_line@16",
      "line_too_long@41",
      "unknown_directive@3",
      "accepted_missing_colon@8",
      "accepted_directive_typo@9",
      "accepted_directive_typo@10",
      "accepted_directive_prefix@11",
      "unsupported_directive@12",
      "content_signal_directive@13",
      "unsupported_directive@14",
      "unknown_directive@15",
      "empty_user_agent@17",
      "rule_without_user_agent@18",
      "empty_rule_value@18",
      "rule_without_user_agent@19",
      "rule_cut_by_comment@19",
      "rule_without_user_agent@20",
      "rule_missing_leading_slash@20",
      "rule_without_user_agent@21",
      "rule_lowercase_escape@21",
      "empty_sitemap_value@22",
      "invalid_sitemap_url@23",
      "rule_without_user_agent@24",
      "rule_missing_leading_slash@24",
      "empty_user_agent@36",
      "rule_without_user_agent@37",
      "user_agent_cut@25",
      "ai_training_token_near_miss@31",
      "ai_training_preference@32",
      "ai_training_preference@39",
      "wildcard_rules_not_inherited@25",
      "wildcard_rules_not_inherited@31",
      "wildcard_rules_not_inherited@34",
      "wildcard_rules_not_inherited@38",
      "disallow_tied_by_allow@29",
      "duplicate_rule@27",
      "duplicate_rule@28"
    )
  )
  expect_identical(
    seam_digest(d, linear_frame_extra(d)),
    "380182c8c90d264239c28cd319256ee5"
  )
})

test_that("the frame of a NUL-bearing UTF-16 body is pinned", {
  d <- robots_validate_text(linear_body_utf16())$diagnostics
  expect_identical(
    linear_rows(d),
    c("nul_byte@1", "nul_byte@2", "nul_byte@3", "malformed_line@1",
      "rules_after_nul_removal@NA")
  )
  expect_identical(
    seam_digest(d, linear_frame_extra(d)),
    "681085d553350c7f48eddde12a55101f"
  )
})

test_that("an HTML page with rules and no User-agent is pinned", {
  d <- robots_validate_text(linear_body_html())$diagnostics
  expect_identical(
    linear_rows(d),
    c("accepted_missing_colon@1", "unknown_directive@1",
      "rule_without_user_agent@2", "missing_user_agent@NA",
      "html_body@NA")
  )
  expect_identical(
    seam_digest(d, linear_frame_extra(d)),
    "091fcb80c5442ce1ca384dcde100d87c"
  )
})

test_that("a body with no diagnostics gives the empty frame", {
  d <- robots_validate_text(linear_body_clean())$diagnostics
  expect_identical(d, empty_validation_diagnostics())
})

test_that("an empty body's no_rules row is pinned", {
  d <- robots_validate_text(raw())$diagnostics
  expect_identical(linear_rows(d), "no_rules@NA")
  expect_identical(
    seam_digest(d, linear_frame_extra(d)),
    "b87027a7f039f7ece78b927469f40ece"
  )
})

test_that("a fetch through a redirect keeps its redirect row in place", {
  local_fake_ssrfr(linear_redirect_handler)
  d <- robots_validate_url("http://example.com/page")$diagnostics
  expect_identical(
    linear_rows(d),
    c("rule_missing_leading_slash@2", "redirect_cross_site@NA")
  )
  expect_identical(
    seam_digest(d, linear_frame_extra(d)),
    "3ef41956e83080671d92cf117fae22ed"
  )
})

test_that("a 2xx body cut at max_bytes keeps its document-level row", {
  local_fake_ssrfr(linear_fetch_body(200L, linear_cut_body()))
  d <- robots_validate_url("http://example.com/page",
                           max_bytes = 60L)$diagnostics
  expect_identical(
    linear_rows(d),
    c("rule_missing_leading_slash@2", "rule_missing_leading_slash@3",
      "rule_missing_leading_slash@4", "body_truncated@NA")
  )
  expect_identical(
    seam_digest(d, linear_frame_extra(d)),
    "06bdf3de2651d8c53a7aed000440c650"
  )
})

test_that("a 203 robots.txt keeps its info row beside its rules", {
  local_fake_ssrfr(linear_fetch_body(
    203L, charToRaw("User-agent: *\nDisallow: x\n")
  ))
  d <- robots_validate_url("http://example.com/page")$diagnostics
  expect_identical(
    linear_rows(d),
    c("rule_missing_leading_slash@2", "acquisition_http_other_2xx@NA")
  )
  expect_identical(
    seam_digest(d, linear_frame_extra(d)),
    "bf067c52aa2d02e673554f6dcf4c08d6"
  )
})

test_that("a non-ASCII directive name keeps its UTF-8 encoding mark", {
  # The only value of the pinned frames marked UTF-8: the directive is
  # `action`, read through validation_ascii_action(), and keeps its mark.
  body <- charToRaw("User-agent: *\nCafé: /x\n")
  d <- robots_validate_text(body)$diagnostics
  expect_identical(linear_rows(d), c("unknown_directive@2", "no_rules@NA"))
  expect_identical(Encoding(d$directive), c("UTF-8", "unknown"))
  expect_identical(
    seam_digest(d, linear_frame_extra(d)),
    "33c52d397e23a2760bd8dcd10c44b258"
  )
})
