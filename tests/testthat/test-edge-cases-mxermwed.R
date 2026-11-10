# ROBO-mxermwed: the edge-case catalog (design/edge-case-catalog.md).
#
# Every fixture under fixtures/edge-cases/ is a synthesized robots.txt body,
# listed in manifest.csv with one row per check: the URL path and product
# token, the Google matcher's decision, the RFC 9309 reading where the RFC
# settles it, and the validator's diagnostics as `code@line` in emitted order.
# These tests pin CURRENT behavior, right or wrong; the rows whose behavior is
# a known gap are restated one by one at the end, each with its comment.
#
# A body is either `<id>.txt`, its bytes verbatim, or `<id>.hex`, its bytes
# as hexadecimal text. A body the pre-commit whitespace hooks would rewrite
# (a BOM, NUL, CR, invalid UTF-8, trailing whitespace or no final newline) is
# kept as hex so its bytes survive every commit.

edge_dir <- test_path("fixtures", "edge-cases")

edge_manifest <- utils::read.csv(
  file.path(edge_dir, "manifest.csv"),
  colClasses = "character", na.strings = character(),
  encoding = "UTF-8", check.names = FALSE
)

# Lowercase hex digits and whitespace only, an even number of digits: any
# other character or a dangling nibble is a broken fixture, not a byte.
edge_hex_bytes <- function(lines, file = "hex") {
  text <- paste(lines, collapse = "\n")
  if (grepl("[^0-9a-f[:space:]]", text)) {
    stop(sprintf("%s: a character outside [0-9a-f] and whitespace", file))
  }
  hex <- gsub("[[:space:]]", "", text)
  if (nchar(hex) %% 2L != 0L) {
    stop(sprintf("%s: an odd number of hex digits", file))
  }
  starts <- seq(1L, nchar(hex), by = 2L)
  as.raw(strtoi(substring(hex, starts, starts + 1L), 16L))
}

edge_body <- function(file) {
  path <- file.path(edge_dir, file)
  if (endsWith(file, ".hex")) {
    return(edge_hex_bytes(readLines(path), file))
  }
  readBin(path, "raw", file.size(path))
}

edge_url <- function(path) {
  url <- paste0("https://example.com", path)
  Encoding(url) <- "UTF-8"
  url
}

# The bytes as a character scalar the text entry points take verbatim.
edge_text <- function(bytes) {
  txt <- rawToChar(bytes)
  Encoding(txt) <- "bytes"
  txt
}

# The Google matcher's decision. R strings cannot hold a NUL, so a NUL-bearing
# body is decoded the way the fetch path decodes one (R/body-decode.R: NUL
# bytes dropped) and handed to the same binding allowed_by_robots_text() uses.
edge_decision <- function(bytes, path, token) {
  if (any(bytes == as.raw(0))) {
    allowed <- robotstxtr_allowed_text_(
      decode_matcher_body(bytes), edge_url(path), token
    )
  } else {
    allowed <- allowed_by_robots_text(
      edge_text(bytes), edge_url(path), token
    )$results$allowed
  }
  if (allowed) "allow" else "disallow"
}

# Diagnostics as the manifest writes them: `code@line`, `;`-separated.
edge_format_codes <- function(d) {
  paste(sprintf("%s@%s", d$code, ifelse(is.na(d$line), "NA", d$line)),
        collapse = ";")
}

edge_codes <- function(bytes) {
  edge_format_codes(robots_validate_text(bytes)$diagnostics)
}

test_that("ROBO-mxermwed: a .hex fixture holds hex digits in pairs only", {
  expect_identical(edge_hex_bytes(c("ef bb", "bf0a")),
                   as.raw(c(0xef, 0xbb, 0xbf, 0x0a)))
  expect_error(edge_hex_bytes("efbbg0"), "outside")
  expect_error(edge_hex_bytes("EFBB"), "outside")
  expect_error(edge_hex_bytes("efb"), "odd")
})

test_that("ROBO-mxermwed: the manifest and the fixture files agree", {
  m <- edge_manifest
  expect_named(
    m,
    c("id", "family", "body_file", "path", "token", "google_decision",
      "rfc9309_decision", "validator_codes", "surprise", "known_gap")
  )
  expect_true(all(m$google_decision %in% c("allow", "disallow")))
  expect_true(all(
    m$rfc9309_decision %in% c("allow", "disallow", "unspecified")
  ))
  expect_true(all(m$surprise %in% c("yes", "no")))
  expect_true(all(m$family %in% c(
    "encoding", "escaping", "blank", "comments-sitemaps", "grouping",
    "size", "content", "redirect", "other"
  )))
  # One body per case, named after it.
  per_case <- unique(m[c("id", "body_file")])
  expect_false(anyDuplicated(per_case$id) > 0L)
  expect_identical(tools::file_path_sans_ext(per_case$body_file), per_case$id)
  files <- setdiff(list.files(edge_dir), "manifest.csv")
  expect_setequal(files, per_case$body_file)
})

test_that("ROBO-mxermwed: every .txt fixture is one the hooks leave alone", {
  m <- edge_manifest
  for (file in unique(m$body_file[endsWith(m$body_file, ".txt")])) {
    bytes <- edge_body(file)
    # Checked on the raw bytes: rawToChar() errors on a NUL before any
    # assertion on the string could run.
    expect_false(any(bytes %in% as.raw(c(0x00, 0x0d))), label = file)
    txt <- rawToChar(bytes)
    expect_true(validUTF8(txt), label = file)
    expect_identical(bytes[[length(bytes)]], as.raw(0x0a), label = file)
    # end-of-file-fixer collapses trailing blank lines to one newline.
    expect_false(endsWith(txt, "\n\n"), label = file)
    expect_false(grepl("[ \t]\n", txt, useBytes = TRUE), label = file)
    expect_false(
      grepl("\xef\xbb\xbf", txt, fixed = TRUE, useBytes = TRUE),
      label = file
    )
  }
})

test_that("ROBO-mxermwed: the Google matcher's decision on every check", {
  m <- edge_manifest
  for (i in seq_len(nrow(m))) {
    row <- m[i, ]
    expect_identical(
      edge_decision(edge_body(row$body_file), row$path, row$token),
      row$google_decision,
      label = sprintf("%s %s as %s", row$id, substr(row$path, 1L, 40L),
                      row$token)
    )
  }
})

test_that("ROBO-mxermwed: the v1 google engine agrees on every NUL-free body", {
  m <- edge_manifest
  for (i in seq_len(nrow(m))) {
    row <- m[i, ]
    bytes <- edge_body(row$body_file)
    if (any(bytes == as.raw(0))) next
    x <- robots_evaluate_text_v1(
      edge_text(bytes), edge_url(row$path), row$token,
      robots_policy_ruleset = "google", matcher_backend = "google"
    )
    expect_identical(
      x$results$url_decision, row$google_decision,
      label = sprintf("%s %s as %s", row$id, substr(row$path, 1L, 40L),
                      row$token)
    )
  }
})

test_that("ROBO-mxermwed: the validator's diagnostics on every body", {
  m <- edge_manifest
  per_case <- unique(m[c("id", "body_file", "validator_codes")])
  expect_false(anyDuplicated(per_case$id) > 0L)
  for (i in seq_len(nrow(per_case))) {
    expect_identical(
      edge_codes(edge_body(per_case$body_file[[i]])),
      per_case$validator_codes[[i]],
      label = per_case$id[[i]]
    )
  }
})

# --- Known gaps, restated -----------------------------------------------
# Each block pins the current behavior of manifest rows whose `known_gap` is
# set. Fixing a gap turns its block red on purpose.

edge_case <- function(id) {
  m <- edge_manifest
  edge_body(m$body_file[m$id == id][[1L]])
}

test_that("ROBO-mxermwed: a BOM inside the file is named on its line", {
  # Fixed by ROBO-atkmqcov: misplaced_byte_order_mark names the BOM and the
  # directive it hides; the matcher still reads the line as unknown.
  bytes <- edge_case("enc-bom-mid-file")
  expect_identical(
    edge_codes(bytes),
    "misplaced_byte_order_mark@2;unknown_directive@2;no_rules@NA"
  )
  expect_identical(edge_decision(bytes, "/a", "FooBot"), "allow")
  bytes <- edge_case("enc-bom-before-user-agent")
  expect_identical(edge_codes(bytes),
                   "misplaced_byte_order_mark@4;unknown_directive@4")
  x <- robots_validate_text(bytes)$diagnostics
  expect_match(x$message[x$code == "misplaced_byte_order_mark"],
               "User-agent line is not read")
  expect_identical(edge_decision(bytes, "/a", "FooBot"), "disallow")
})

test_that("ROBO-mxermwed: UTF-16 without a BOM matches what no_rules denies", {
  # known gap (ROBO-igrkabdb): the matcher drops the NULs and enforces
  # Disallow: /a, while the validator reports no_rules ("places no
  # restrictions") for the same bytes
  bytes <- edge_case("enc-utf16le-no-bom")
  expect_identical(edge_decision(bytes, "/a", "FooBot"), "disallow")
  expect_true("no_rules" %in% robots_validate_text(bytes)$diagnostics$code)
})

test_that("ROBO-mxermwed: a Latin-1 byte in a comment is a lineless error", {
  # known gap (ROBO-sniltuap): invalid_utf8 has no line and is an error
  # although only a comment holds the byte and the decision is unchanged
  x <- robots_validate_text(edge_case("enc-latin1-comment"))
  expect_identical(x$diagnostics$code, "invalid_utf8")
  expect_identical(x$diagnostics$line, NA_integer_)
  expect_identical(x$documents$validation_status, "error")
})

test_that("ROBO-mxermwed: an escaped unreserved character is flagged", {
  # Fixed (ROBO-gaczsrgj): Disallow: /%7Ejoe still never matches /~joe under
  # Google (RFC 9309 section 2.2.2 would decode %7E), and
  # rule_escaped_unreserved now says so
  bytes <- edge_case("esc-pct7e-rule-tilde-url")
  expect_identical(edge_codes(bytes), "rule_escaped_unreserved@2")
  expect_identical(edge_decision(bytes, "/~joe", "FooBot"), "allow")
})

test_that("ROBO-mxermwed: a raw space inside a rule goes unflagged", {
  # known gap (ROBO-dlgeqluf): Disallow: /a b matches no percent-encoded URL;
  # no diagnostic
  bytes <- edge_case("esc-space-in-rule")
  expect_identical(edge_codes(bytes), "")
  expect_identical(edge_decision(bytes, "/a%20b", "FooBot"), "allow")
})

test_that("ROBO-mxermwed: a # inside a rule widens it, flagged", {
  # fixed (ROBO-gjhpykcj): Disallow: /a#b is still read as Disallow: /a and
  # blocks /abc, and rule_cut_by_comment now says so
  bytes <- edge_case("cmt-hash-in-rule")
  expect_identical(edge_codes(bytes), "rule_cut_by_comment@2")
  expect_identical(edge_decision(bytes, "/abc", "FooBot"), "disallow")
})

test_that("ROBO-mxermwed: Googlebot-Image does not fall back to Googlebot", {
  # known gap (ROBO-fbbmvbob, a maintainer decision): Google's common-crawlers
  # page lists Googlebot as Googlebot-Image's second token, so Google's crawler
  # would follow the Googlebot group (design/engine-profiles.md section 5a).
  # The binding compares the one token whole and falls through to `*`; this
  # pins that.
  bytes <- edge_case("grp-googlebot-image-fallback")
  expect_identical(edge_decision(bytes, "/x", "Googlebot-Image"), "allow")
  expect_identical(edge_decision(bytes, "/y", "Googlebot-Image"), "disallow")
})

test_that("ROBO-mxermwed: a User-agent value cut to its token is flagged", {
  # Fixed by ROBO-zvhrayhx: the matcher still reads only the token, and
  # user_agent_cut now says so.
  # User-agent: Foo Bot names Foo, not FooBot.
  bytes <- edge_case("grp-user-agent-with-space")
  expect_identical(edge_codes(bytes), "user_agent_cut@1")
  expect_identical(edge_decision(bytes, "/x", "Foo"), "disallow")
  expect_identical(edge_decision(bytes, "/x", "FooBot"), "allow")
  # User-agent: Bot2 names Bot, not Bot2.
  bytes <- edge_case("grp-digit-in-token")
  expect_identical(edge_codes(bytes), "user_agent_cut@1")
  expect_identical(edge_decision(bytes, "/x", "Bot2"), "allow")
  expect_identical(edge_decision(bytes, "/x", "Bot"), "disallow")
  # User-agent: *bot names no crawler.
  bytes <- edge_case("grp-star-prefixed-token")
  expect_identical(edge_codes(bytes), "user_agent_cut@1")
  expect_identical(edge_decision(bytes, "/x", "FooBot"), "allow")
})

test_that("ROBO-mxermwed: a lower-case escape in a rule misses its own path", {
  # known gap (ROBO-kormmfyg): Disallow: /a%3cb is stored as /a%3Cb, so the
  # exact path the owner wrote, /a%3cb, is allowed (RFC 9309 section 2.2.2
  # keeps %3c encoded and matches it octet for octet); no diagnostic
  bytes <- edge_case("esc-lower-hex-rule")
  expect_identical(edge_codes(bytes), "")
  expect_identical(edge_decision(bytes, "/a%3cb", "FooBot"), "allow")
  expect_identical(edge_decision(bytes, "/a%3Cb", "FooBot"), "disallow")
})

test_that("ROBO-mxermwed: every known_gap row is restated above", {
  m <- edge_manifest
  expect_setequal(
    unique(m$id[nzchar(m$known_gap)]),
    c("enc-utf16le-no-bom",
      "enc-latin1-comment", "esc-space-in-rule",
      "esc-lower-hex-rule",
      "grp-googlebot-image-fallback", "redirect-cross-host-html")
  )
})

# A surprise counts as covered when it has a known_gap issue or when an
# existing validator diagnostic already reports it
# (design/edge-case-catalog.md, "Reading the fixtures"). The one exception
# is a URL-side difference, which the caller owns: allowed_by_robots_text()
# matches the URL unchanged.
edge_covering_code <- c(
  "enc-bom-mid-file" = "misplaced_byte_order_mark",
  "enc-bom-before-user-agent" = "misplaced_byte_order_mark",
  "enc-bom-doubled" = "misplaced_byte_order_mark",
  "enc-utf16le-bom" = "nul_byte",
  "enc-utf16be-bom" = "nul_byte",
  "enc-latin1-rule" = "invalid_utf8",
  "esc-dollar-then-star" = "rule_inner_dollar",
  "esc-lone-dollar" = "rule_missing_leading_slash",
  "cmt-hash-in-rule" = "rule_cut_by_comment",
  "esc-pct7e-rule-tilde-url" = "rule_escaped_unreserved",
  "size-long-line" = "line_too_long",
  "content-spam-html" = "html_body",
  "grp-user-agent-with-space" = "user_agent_cut",
  "grp-digit-in-token" = "user_agent_cut",
  "grp-star-prefixed-token" = "user_agent_cut"
)
edge_caller_side <- "esc-tilde-rule-pct7e-url"

test_that("ROBO-mxermwed: every surprise is an issue or a diagnostic", {
  m <- edge_manifest
  open <- unique(m$id[m$surprise == "yes" & !nzchar(m$known_gap)])
  expect_setequal(open, c(names(edge_covering_code), edge_caller_side))
  for (id in names(edge_covering_code)) {
    codes <- robots_validate_text(edge_case(id))$diagnostics$code
    expect_true(edge_covering_code[[id]] %in% codes, label = id)
  }
})

test_that("ROBO-mxermwed: a spam HTML page served as robots.txt", {
  # fixed by ROBO-ccfsanhq: one html_body warning names the body as HTML,
  # beside the malformed_line and unknown_directive rows and no_rules; the
  # matcher still allows everything
  bytes <- edge_case("content-spam-html")
  x <- robots_validate_text(bytes)
  expect_identical(x$documents$validation_status, "error")
  expect_identical(
    sort(unique(x$diagnostics$code)),
    c("accepted_missing_colon", "html_body", "malformed_line", "no_rules",
      "unknown_directive")
  )
  expect_identical(sum(x$diagnostics$code == "html_body"), 1L)
  expect_identical(edge_decision(bytes, "/private/", "FooBot"), "allow")
})

# A robots.txt that redirects to an HTML page on another host. The fetch
# follows the redirect and matches the landing page as the robots.txt. The
# handler records every requested URL and refuses any other.
edge_redirect_handler <- function(state) {
  state$seen <- character()
  function(req) {
    state$seen[[length(state$seen) + 1L]] <- req$url
    if (identical(req$url, "http://a.example/robots.txt")) {
      fake_response(
        301L, url = req$url,
        headers = list(Location = "https://b.example/landing")
      )
    } else if (identical(req$url, "https://b.example/landing")) {
      fake_response(
        200L, url = req$url, headers = list(`Content-Type` = "text/html"),
        body = edge_case("redirect-cross-host-html")
      )
    } else {
      stop(sprintf("unexpected request URL in mock: %s", req$url))
    }
  }
}

edge_redirect_hops <- c("http://a.example/robots.txt",
                        "https://b.example/landing")

test_that("ROBO-mxermwed: a cross-host redirect to HTML is fetched and used", {
  state <- new.env(parent = emptyenv())
  local_fake_ssrfr(edge_redirect_handler(state))
  f <- robots_fetch("http://a.example/page")$robots
  expect_identical(state$seen, edge_redirect_hops)
  expect_identical(f$robots_url, "http://a.example/robots.txt")
  expect_identical(f$effective_url, "https://b.example/landing")
  expect_identical(f$fetch_outcome, "fetched")
  expect_identical(f$http_status, 200L)
  expect_identical(f$redirect_count, 1L)
  expect_identical(f$content_type, "text/html")
  expect_identical(f$content_flag, "html")
  expect_identical(f$body[[1L]], edge_case("redirect-cross-host-html"))

  a <- allowed_by_robots_url("http://a.example/page", "FooBot")$results
  expect_true(a$allowed)
  expect_identical(a$decision_source, "default_allow")

  e <- robots_evaluate_url_v1(
    "http://a.example/page", "FooBot",
    robots_policy_ruleset = "google", matcher_backend = "google"
  )
  expect_identical(e$evidence$evidence_status, "usable_body")
  expect_identical(e$evidence$redirect_count, 1L)
  expect_identical(e$results$policy_reason, "http_200_use_rules")
  expect_identical(e$results$url_decision, "allow")
  # Each entry point fetched afresh, through the same two hops.
  expect_identical(state$seen, rep(edge_redirect_hops, 3L))
})

test_that("ROBO-mxermwed: the validator reports no redirect", {
  # known gap (ROBO-gokbvzcb): no diagnostic for a successful cross-host
  # redirect; the document validates the landing page's lines only
  state <- new.env(parent = emptyenv())
  local_fake_ssrfr(edge_redirect_handler(state))
  v <- robots_validate_url("http://a.example/page")
  expect_identical(state$seen, edge_redirect_hops)
  expect_identical(v$documents$effective_url, "https://b.example/landing")
  expect_identical(v$documents$validation_status, "error")
  m <- edge_manifest
  expect_identical(
    edge_format_codes(v$diagnostics),
    m$validator_codes[m$id == "redirect-cross-host-html"][[1L]]
  )
})
