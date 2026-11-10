# Google fidelity audit (ROBO-deehqhlc). robotstxtr's Google paths against the
# pristine upstream google/robotstxt engine at
# 22b355ff855419e6a3ff8ff09c0ad7fdb17116f9, on synthesized inputs.
#
# The fixtures, and the reference's answer to each, are in
# fixtures/google-fidelity-deehqhlc/cases.R; dev/google-fidelity/differential.R
# re-derives those answers from a reference binary. These tests need no
# binary: they pin what robotstxtr returns, and say in comments what the
# reference returns. The paths: the v1 facade with the google backend under
# every ruleset that reaches the matcher (`v1_text:<ruleset>`),
# allowed_by_robots_text() (`text`), allowed_by_robots_url() with the body
# served at the ssrfr boundary (`url`, helper-fake-ssrfr.R), and
# robots_evaluate_url_v1() the same way (`v1_url:google`). No network.
#
# Classes of difference (design/engine-profiles.md §5b):
#   1. an Allow/Disallow with an empty value: same decision, no line;
#   2. the 512,000-byte window (v1 paths): a rule after it, or a line it cuts;
#   3. the max_bytes cut (allowed_by_robots_url()): a rule past the cut;
#   4. input screening: an empty URL or token, a URL that is not HTTP(S);
#   5. a NUL byte in a fetched body is dropped, not read.

source(test_path("fixtures", "google-fidelity-deehqhlc", "cases.R"))

gf_v1_path <- function(path) startsWith(path, "v1_")

# What robotstxtr returns where it differs from the reference, by case and
# path: list(class, allowed, line, reason), or NULL where it must agree.
gf_expected_difference <- function(id, path) {
  empty_value <- c(
    "ev-disallow", "ev-allow", "ev-both", "ev-comment", "ev-beside-rule-miss"
  )
  invalid_reason <- if (gf_v1_path(path)) "input_invalid" else "input_unknown"
  if (id %in% empty_value) {
    return(list(class = 1L, allowed = TRUE, line = NA_integer_,
                reason = "default_allow"))
  }
  if (id %in% c("win-after", "win-after-ceiling", "win-straddle") &&
        gf_v1_path(path)) {
    return(list(class = 2L, allowed = TRUE, line = NA_integer_,
                reason = "default_allow"))
  }
  if (identical(id, "win-after-ceiling") && identical(path, "url")) {
    return(list(class = 3L, allowed = TRUE, line = NA_integer_,
                reason = "default_allow"))
  }
  if (id %in% c("in-empty-url", "in-empty-token")) {
    return(list(class = 4L, allowed = NA, line = NA_integer_,
                reason = invalid_reason))
  }
  if (id %in% c("in-schemeless-url", "in-ftp-url") &&
        path %in% c("url", "v1_url:google")) {
    return(list(class = 4L, allowed = NA, line = NA_integer_,
                reason = invalid_reason))
  }
  if (identical(id, "nul-before-key")) {
    return(list(class = 5L, allowed = FALSE, line = 2L,
                reason = "rule_disallow"))
  }
  NULL
}

test_that("ROBO-deehqhlc: every path agrees with the reference outside 1-5", {
  seen <- integer()
  for (case in gf_cases()) {
    got <- gf_run_case(case)
    for (k in seq_len(nrow(got))) {
      label <- paste(case$id, got$path[[k]])
      want <- gf_expected_difference(case$id, got$path[[k]])
      if (is.null(want)) {
        # The reference's decision, and its matching line (0: none).
        expect_identical(got$allowed[[k]], case$ref_allowed, label = label)
        expect_identical(
          got$line[[k]],
          if (case$ref_line > 0L) case$ref_line else NA_integer_,
          label = label
        )
      } else {
        seen <- union(seen, want$class)
        expect_identical(got$allowed[[k]], want$allowed, label = label)
        expect_identical(got$line[[k]], want$line, label = label)
        expect_identical(got$reason[[k]], want$reason, label = label)
      }
    }
  }
  expect_setequal(seen, 1:5)
})

test_that("ROBO-deehqhlc: the fixtures reach every path and family", {
  cases <- gf_cases()
  families <- vapply(cases, `[[`, character(1L), "family")
  expect_setequal(families, c(
    "empty_value", "window", "target", "pattern", "agent", "eol", "utf8",
    "long", "typo", "input", "nul"
  ))
  ids <- vapply(cases, `[[`, character(1L), "id")
  expect_false(anyDuplicated(ids) > 0L)
})

# --- Class 1: an Allow/Disallow with an empty value ---------------------------

test_that("ROBO-deehqhlc class 1: an empty Disallow reports no line", {
  # Reference: allowed, matching_line() 2 (the empty Disallow, priority 0).
  # robotstxtr: the same decision, reported as no rule (PRD §6.6, match
  # metadata rules; R/correlate_matches.R; match_google_v1() since af141e7).
  # The v1 contract (design/engine-contract-v1.md) does not say so for
  # Google rows; the Yandex backend reports `effective_empty_disallow` there.
  body <- "User-agent: FooBot\nDisallow:\n"
  url <- "https://example.com/x"
  v1 <- robots_evaluate_text_v1(body, url, "FooBot", "google", "google")
  r <- v1$results
  expect_identical(r$url_decision, "allow")
  expect_identical(r$reason, "default_allow")
  expect_identical(r$matched_line, NA_integer_)
  expect_identical(r$matched_rule_type, "none")
  expect_identical(r$matched_rule_value, NA_character_)
  legacy <- allowed_by_robots_text(body, url, "FooBot")$results
  expect_true(legacy$allowed)
  expect_identical(legacy$decision_source, "default_allow")
  expect_identical(legacy$matched_line, NA_integer_)
  expect_identical(legacy$matched_rule_type, "none")
  # The matcher itself reports the line; robotstxtr restates it.
  expect_identical(robotstxtr_matching_line_text_(body, url, "FooBot"), 2L)
})

test_that("ROBO-deehqhlc class 1: an empty Allow reports no line", {
  # Reference: allowed, matching_line() 2.
  body <- "User-agent: FooBot\nAllow:\n"
  url <- "https://example.com/x"
  r <- robots_evaluate_text_v1(body, url, "FooBot", "google", "google")$results
  expect_identical(r$reason, "default_allow")
  expect_identical(r$matched_line, NA_integer_)
  gf_with_body(charToRaw(body), {
    u <- allowed_by_robots_url(url, "FooBot")$results
  })
  expect_identical(u$decision_source, "default_allow")
  expect_identical(u$matched_line, NA_integer_)
})

test_that("ROBO-deehqhlc class 1: a real rule beside an empty one still wins", {
  # Reference: /private disallowed on line 3, /public allowed on line 2.
  body <- "User-agent: FooBot\nDisallow:\nDisallow: /private\n"
  r <- robots_evaluate_text_v1(
    body, c("https://example.com/private", "https://example.com/public"),
    "FooBot", "google", "google"
  )$results
  expect_identical(r$url_decision, c("disallow", "allow"))
  expect_identical(r$matched_line, c(3L, NA_integer_))
  expect_identical(r$reason, c("rule_disallow", "default_allow"))
})

# --- Class 2: the 512,000-byte window -----------------------------------------

test_that("ROBO-deehqhlc class 2: a rule after the window is not read", {
  # Reference (no window): disallowed on line 3. v1: Google reads the first
  # 512,000 bytes (design/engine-profiles.md §7, documented).
  # allowed_by_robots_text() reads the whole body, as the reference does.
  body <- gf_edge_body("Disallow: /after\n", 520000L)
  url <- "https://example.com/after"
  r <- robots_evaluate_text_v1(
    gf_body_string(body), url, "FooBot", "google", "google"
  )$results
  expect_identical(r$url_decision, "allow")
  expect_identical(r$reason, "default_allow")
  expect_true(r$matcher_body_truncated)
  # The comment line crosses the window: only "User-agent: *\n" is read.
  expect_identical(r$matcher_input_bytes, 14L)
  legacy <- allowed_by_robots_text(gf_body_string(body), url, "FooBot")
  expect_false(legacy$results$allowed)
  expect_identical(legacy$results$matched_line, 3L)
})

test_that("ROBO-deehqhlc class 2: a line the window cuts is dropped whole", {
  # Reference: /private-drafts/x disallowed on line 3; /public allowed, no
  # line. v1 drops the line the window cuts (§7, application_choice), so
  # neither "Disallow: /private-drafts/" nor its first 11 bytes,
  # "Disallow: /", is a rule.
  body <- gf_edge_body("Disallow: /private-drafts/\n", 512000L - 11L)
  r <- robots_evaluate_text_v1(
    gf_body_string(body),
    c("https://example.com/private-drafts/x", "https://example.com/public"),
    "FooBot", "google", "google"
  )$results
  expect_identical(r$url_decision, c("allow", "allow"))
  expect_identical(r$matched_line, c(NA_integer_, NA_integer_))
  expect_identical(r$matcher_input_bytes, rep(512000L - 11L, 2L))
})

test_that("ROBO-deehqhlc class 2: a line whose LF is past the window applies", {
  # Reference and v1 agree: disallowed on line 3, both when the LF is byte
  # 512,000 and when it is byte 512,001.
  for (at in c(512000L - 18L, 512000L - 19L)) {
    body <- gf_edge_body("Disallow: /private\n", at, 600000L)
    r <- robots_evaluate_text_v1(
      gf_body_string(body), "https://example.com/private", "FooBot",
      "google", "google"
    )$results
    expect_identical(r$url_decision, "disallow")
    expect_identical(r$matched_line, 3L)
    expect_identical(r$matcher_input_bytes, 512000L)
  }
})

# --- Class 3: the max_bytes cut of allowed_by_robots_url() --------------------

test_that("ROBO-deehqhlc class 3: a rule past max_bytes is not fetched", {
  # Reference (whole body): disallowed on line 3. allowed_by_robots_url()
  # keeps the first max_bytes (524,288) bytes of a 2xx and reads its complete
  # lines (its @param max_bytes; ROBO-ldpahknv); the rule starts at 530,001.
  body <- gf_edge_body("Disallow: /after\n", 530000L)
  gf_with_body(body, {
    x <- allowed_by_robots_url("https://example.com/after", "FooBot")
  })
  expect_true(x$results$allowed)
  expect_identical(x$results$decision_source, "default_allow")
  expect_true(x$robots$body_truncated)
  # Between the window and the cut, the legacy URL path still reads a rule
  # the v1 paths do not (class 2): the reference's answer.
  body <- gf_edge_body("Disallow: /after\n", 520000L)
  gf_with_body(body, {
    x <- allowed_by_robots_url("https://example.com/after", "FooBot")
  })
  expect_false(x$results$allowed)
  expect_identical(x$results$matched_line, 3L)
})

# --- Class 4: input screening -------------------------------------------------

test_that("ROBO-deehqhlc class 4: an empty URL or token is not matched", {
  # Reference: "" as URL is path "/" (allowed, no line); "" as agent reads
  # the `*` group (disallowed, line 2). robotstxtr refuses both rows
  # (allowed_by_robots_text() roxygen; PRD §6.6).
  body <- "User-agent: *\nDisallow: /private\n"
  r <- robots_evaluate_text_v1(
    body, c("", "https://example.com/private"), c("FooBot", ""),
    "google", "google"
  )$results
  expect_identical(r$url_decision, c(NA_character_, NA_character_))
  expect_identical(r$error_class, c(
    "robots_invalid_url", "robots_invalid_product_token"
  ))
  legacy <- allowed_by_robots_text(
    body, c("", "https://example.com/private"), c("FooBot", "")
  )$results
  expect_identical(legacy$allowed, c(NA, NA))
  expect_identical(legacy$decision_source, rep("input_unknown", 2L))
})

test_that("ROBO-deehqhlc class 4: the URL paths need an HTTP(S) URL", {
  # Reference: "example.com/private" and "ftp://example.com/private" are
  # path "/private", disallowed on line 2; so are the text paths, which pass
  # the URL through. The URL paths build a fetch origin first and refuse
  # both (allowed_by_robots_url() roxygen).
  body <- charToRaw("User-agent: *\nDisallow: /private\n")
  urls <- c("example.com/private", "ftp://example.com/private")
  gf_with_body(body, {
    u <- allowed_by_robots_url(urls, "FooBot")$results
    v <- robots_evaluate_url_v1(urls, "FooBot", "google", "google")$results
  })
  expect_identical(u$allowed, c(NA, NA))
  expect_identical(u$error_class, rep("robots_invalid_url", 2L))
  expect_identical(v$url_decision, c(NA_character_, NA_character_))
  expect_identical(v$error_class, rep("robots_invalid_url", 2L))
  t <- allowed_by_robots_text(rawToChar(body), urls, "FooBot")$results
  expect_identical(t$allowed, c(FALSE, FALSE))
  expect_identical(t$matched_line, c(2L, 2L))
})

# --- Class 5: a NUL byte ------------------------------------------------------

test_that("ROBO-deehqhlc class 5: a NUL before a key is dropped, not read", {
  # Reference: "\0Disallow" is an unknown key, so /x is allowed, no line.
  # robotstxtr drops NUL bytes before matching (PRD §6.6, NUL rule;
  # R/body-decode.R; ROBO-hcqrzikz), so the line is a Disallow.
  body <- c(
    charToRaw("User-agent: *\n"), as.raw(0), charToRaw("Disallow: /x\n")
  )
  url <- "https://example.com/x"
  gf_with_body(body, {
    u <- allowed_by_robots_url(url, "FooBot")$results
    v <- robots_evaluate_url_v1(url, "FooBot", "google", "google")$results
  })
  expect_false(u$allowed)
  expect_identical(u$matched_line, 2L)
  expect_identical(v$url_decision, "disallow")
  expect_identical(v$matched_line, 2L)
})
