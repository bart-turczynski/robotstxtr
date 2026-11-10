# Google fidelity audit (ROBO-deehqhlc). robotstxtr's Google paths against the
# pristine upstream google/robotstxt engine at
# 22b355ff855419e6a3ff8ff09c0ad7fdb17116f9, on synthesized inputs.
#
# The fixtures, and the reference's answer to each, are in
# fixtures/google-fidelity-deehqhlc/cases.R; dev/google-fidelity/differential.R
# re-derives those answers from a reference binary. These tests need no
# binary: they pin what robotstxtr returns, and say in comments what the
# reference returns. The paths: the v1 facade with the google backend under
# every ruleset that reaches the matcher (`v1_text:<ruleset>`; the window
# bodies under `google` only, gf_case_rulesets()),
# allowed_by_robots_text() (`text`), allowed_by_robots_url() with the body
# served at the ssrfr boundary (`url`, helper-fake-ssrfr.R), and
# robots_evaluate_url_v1() the same way (`v1_url:google`). No network.
#
# Classes of difference (design/engine-profiles.md §5b):
#   1. an Allow/Disallow with an empty value: same decision, no line;
#   2. the 512,000-byte window (v1 paths): a rule after it, or a line it cuts;
#   3. the max_bytes cut (allowed_by_robots_url()): a rule past the cut;
#   4. input screening: an empty URL or token, a URL that is not HTTP(S);
#   5. a NUL byte in a fetched body: the reference reads a line only up to
#      its first NUL, robotstxtr removes the NUL.

# Into this file's environment, which sees helper-fake-ssrfr.R and the
# namespace; globalenv sees neither under an installed-package check.
source(
  test_path("fixtures", "google-fidelity-deehqhlc", "cases.R"), local = TRUE
)

# Every case runs once, here; the tests below read these rows. A case is keyed
# by its id: a NUL body never becomes an R string.
gf_case_list <- gf_cases()
names(gf_case_list) <- vapply(gf_case_list, `[[`, character(1L), "id")
gf_results <- lapply(gf_case_list, gf_run_case)

# One case's row on one path.
gf_result <- function(id, path) {
  got <- gf_results[[id]]
  got[got$path == path, , drop = FALSE]
}

# All rows, with the reference's recorded answers beside them.
gf_all_rows <- function() {
  rows <- do.call(rbind, unname(gf_results))
  case <- gf_case_list[rows$id]
  rows$ref_allowed <- vapply(case, `[[`, logical(1L), "ref_allowed")
  rows$ref_line <- vapply(case, `[[`, integer(1L), "ref_line")
  rows
}

test_that("ROBO-deehqhlc: every path agrees with the reference outside 1-5", {
  seen <- integer()
  differing <- character()
  for (case in gf_case_list) {
    got <- gf_results[[case$id]]
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
        differing <- union(differing, case$id)
        expect_identical(got$allowed[[k]], want$allowed, label = label)
        expect_identical(got$line[[k]], want$line, label = label)
        expect_identical(got$reason[[k]], want$reason, label = label)
      }
    }
  }
  expect_setequal(seen, 1:5)
  # Every case the table lists names a case and reaches a path where it
  # differs.
  expect_setequal(differing, gf_expected_ids())
})

test_that("ROBO-oxjmtaon: gf_check_rows() checks each row's listed answer", {
  rows <- gf_all_rows()
  check <- function(rows) {
    vapply(
      gf_check_rows(rows, rows$ref_allowed, rows$ref_line), nrow, integer(1L)
    )
  }
  none <- c(unexpected = 0L, mismatched = 0L, stale = 0L)
  expect_identical(check(rows), none)

  # A class-5 row whose line or reason moves is not the listed answer.
  k <- which(rows$id == "nul-before-key" & rows$path == "url")
  expect_length(k, 1L)
  moved <- rows
  moved$line[[k]] <- 3L
  expect_identical(check(moved), replace(none, "mismatched", 1L))
  moved <- rows
  moved$reason[[k]] <- "rule_allow"
  expect_identical(check(moved), replace(none, "mismatched", 1L))

  # A listed row that now gives the reference's answer is a stale entry.
  k <- which(rows$id == "nul-in-rule-prefix" & rows$path == "url")
  expect_length(k, 1L)
  agrees <- rows
  agrees$allowed[[k]] <- rows$ref_allowed[[k]]
  agrees$line[[k]] <- rows$ref_line[[k]]
  agrees$reason[[k]] <- "rule_disallow"
  out <- gf_check_rows(agrees, agrees$ref_allowed, agrees$ref_line)
  expect_identical(out$stale$id, "nul-in-rule-prefix")
  expect_identical(out$stale$class, 5L)
  expect_identical(nrow(out$mismatched), 0L)

  # A differing row the table does not list is unexpected.
  k <- which(rows$id == "url-root" & rows$path == "text")
  expect_length(k, 1L)
  off <- rows
  off$allowed[[k]] <- !rows$ref_allowed[[k]]
  out <- gf_check_rows(off, off$ref_allowed, off$ref_line)
  expect_identical(out$unexpected$id, "url-root")
  expect_identical(out$unexpected$class, NA_integer_)
  expect_identical(check(off), replace(none, "unexpected", 1L))
  # So is a line-only difference.
  off <- rows
  off$line[[k]] <- rows$ref_line[[k]] + 1L
  expect_identical(check(off), replace(none, "unexpected", 1L))
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
  # Every entry point is reached, and a NUL body only by the fetched ones.
  paths <- lapply(cases, `[[`, "paths")
  expect_setequal(unlist(paths), c("v1_text", "text", "url", "v1_url"))
  nul <- families == "nul"
  expect_true(all(vapply(paths[nul], setequal, logical(1L), gf_url_paths)))
  expect_true(all(vapply(paths[!nul], setequal, logical(1L), gf_all_paths)))
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

# The window and max_bytes tests read the `window` rows gf_results already
# holds, rather than rebuilding and rerunning their 0.5 to 0.6 MB bodies.

test_that("ROBO-deehqhlc: the window bodies run once, under google only", {
  window <- names(gf_case_list)[
    vapply(gf_case_list, `[[`, character(1L), "family") == "window"
  ]
  expect_length(window, 6L)
  for (id in window) {
    expect_setequal(
      gf_results[[id]]$path, c("v1_text:google", "text", "url", "v1_url:google")
    )
  }
})

test_that("ROBO-deehqhlc class 2: a rule after the window is not read", {
  # Reference (no window): disallowed on line 3. v1: Google reads the first
  # 512,000 bytes (design/engine-profiles.md §7, documented).
  # allowed_by_robots_text() reads the whole body, as the reference does.
  for (path in c("v1_text:google", "v1_url:google")) {
    r <- gf_result("win-after", path)
    expect_true(r$allowed, label = path)
    expect_identical(r$reason, "default_allow", label = path)
    expect_true(r$matcher_body_truncated, label = path)
    # The comment line crosses the window: only "User-agent: *\n" is read.
    expect_identical(r$matcher_input_bytes, 14L, label = path)
  }
  legacy <- gf_result("win-after", "text")
  expect_false(legacy$allowed)
  expect_identical(legacy$line, 3L)
  expect_false(legacy$body_truncated)
})

test_that("ROBO-deehqhlc class 2: a line the window cuts is dropped whole", {
  # Reference: /private-drafts/x disallowed on line 3; /public allowed, no
  # line. v1 drops the line the window cuts (§7, application_choice), so
  # neither "Disallow: /private-drafts/" nor its first 11 bytes,
  # "Disallow: /", is a rule.
  for (id in c("win-straddle", "win-straddle-prefix")) {
    r <- gf_result(id, "v1_text:google")
    expect_true(r$allowed, label = id)
    expect_identical(r$line, NA_integer_, label = id)
    expect_true(r$matcher_body_truncated, label = id)
    expect_identical(r$matcher_input_bytes, 512000L - 11L, label = id)
  }
})

test_that("ROBO-deehqhlc class 2: a rule ending at the window edge applies", {
  # Reference and v1 agree: disallowed on line 3, both when the rule ends at
  # byte 512,000 and its LF is byte 512,001 (past the window), and when the
  # LF itself is byte 512,000.
  for (id in c("win-edge-lf-outside", "win-edge-lf-inside")) {
    r <- gf_result(id, "v1_text:google")
    expect_false(r$allowed, label = id)
    expect_identical(r$line, 3L, label = id)
    expect_identical(r$matcher_input_bytes, 512000L, label = id)
  }
})

# --- Class 3: the max_bytes cut of allowed_by_robots_url() --------------------

test_that("ROBO-deehqhlc class 3: a rule past max_bytes is not fetched", {
  # Reference (whole body): disallowed on line 3. allowed_by_robots_url()
  # keeps the first max_bytes (524,288) bytes of a 2xx and reads its complete
  # lines (its @param max_bytes; ROBO-ldpahknv); the rule starts at 530,001.
  x <- gf_result("win-after-ceiling", "url")
  expect_true(x$allowed)
  expect_identical(x$reason, "default_allow")
  expect_true(x$body_truncated)
  # Between the window and the cut, the legacy URL path still reads a rule
  # the v1 paths do not (class 2): the reference's answer.
  x <- gf_result("win-after", "url")
  expect_false(x$allowed)
  expect_identical(x$line, 3L)
  expect_false(x$body_truncated)
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
  # Reference: the parser reads each line as a NUL-terminated C string
  # (src/robots.cc, GetKeyAndValueFrom()), so "\0Disallow: /x" is an empty
  # line and /x is allowed, no line. robotstxtr removes NUL bytes before
  # matching (PRD §6.6, NUL rule; R/body-decode.R; ROBO-hcqrzikz), so the
  # line is a Disallow.
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

test_that("ROBO-deehqhlc class 5: a NUL inside a value is removed, not a cut", {
  # Reference: the same C string ends the value at the NUL, so the rule is
  # "/a": /a, /ac and /ab are all disallowed on line 2. robotstxtr removes
  # the NUL, so the rule is "/ab": only /ab is disallowed (PRD §6.6: the
  # document is not truncated at the NUL; R/body-decode.R).
  body <- c(
    charToRaw("User-agent: *\nDisallow: /a"), as.raw(0), charToRaw("b\n")
  )
  urls <- c(
    "https://example.com/a", "https://example.com/ac", "https://example.com/ab"
  )
  gf_with_body(body, {
    u <- allowed_by_robots_url(urls, "FooBot")$results
    v <- robots_evaluate_url_v1(urls, "FooBot", "google", "google")$results
  })
  expect_identical(u$allowed, c(TRUE, TRUE, FALSE))
  expect_identical(u$matched_line, c(NA_integer_, NA_integer_, 2L))
  expect_identical(v$url_decision, c("allow", "allow", "disallow"))
  expect_identical(v$matched_line, c(NA_integer_, NA_integer_, 2L))
  expect_identical(v$matched_rule_value[[3L]], "/ab")
})
