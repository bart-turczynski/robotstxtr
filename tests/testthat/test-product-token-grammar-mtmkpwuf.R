# ROBO-mtmkpwuf: a robots product token outside the RFC 9309 identifier rule
# (section 2.2.1: ASCII letters, `_` and `-`) on the google and rfc9309
# backends.
#
# Google's matcher cuts each `User-agent` value in the file at its first
# character outside that grammar and compares the cut value with the
# caller's token as given, so a token outside the grammar can never name a
# group: it read `*`, or allowed by default, as `evaluated`. The v1 facades
# now refuse such a row as input, before any fetch, on those two backends
# under every ruleset. The legacy functions and the bounded yandex and bing
# backends are unchanged.

pt_body <- paste0(
  "User-agent: archive.org_bot\nDisallow: /\n\n",
  "User-agent: Googlebot/2.1\nDisallow: /g\n\n",
  "User-agent: *\nDisallow: /star\n"
)

pt_rulesets <- c("google", "yandex", "rfc9309", "bing", "assumed_rfc9309")

pt_refused <- c(
  "archive.org_bot", "Googlebot/2.1",
  "Mozilla/5.0 (compatible; Googlebot/2.1)", " Googlebot", "123", "*",
  "Googlebot ", "Googlebot\t", "Gooģlebot", "Googlebot\n"
)
# The hint each refused token gets: its leading run of grammar bytes.
pt_hints <- c(
  "archive", "Googlebot", "Mozilla", NA, NA, NA, "Googlebot", "Googlebot",
  "Goo", "Googlebot"
)
pt_valid <- c("Googlebot", "Googlebot-Image", "google_extended", "a-")

pt_text <- function(token, ruleset = "google", backend = "google",
                    url = "https://example.com/g", body = pt_body) {
  n <- length(token)
  robots_evaluate_text_v1(body, rep(url, n), token, ruleset, backend)$results
}

pt_expect_refused <- function(r, label = NULL) {
  n <- nrow(r)
  expect_identical(r$matcher_status, rep("not_evaluated", n), label = label)
  expect_identical(r$reason, rep("input_invalid", n), label = label)
  expect_identical(r$policy_reason, rep("input_invalid", n), label = label)
  expect_identical(r$error_stage, rep("input", n), label = label)
  expect_identical(
    r$error_class, rep("robots_invalid_product_token", n), label = label
  )
  expect_true(all(is.na(r$url_decision)), label = label)
  expect_true(all(is.na(r$group_token)), label = label)
  expect_true(all(is.na(r$source_id)), label = label)
}

pt_grammar_message <- "outside the RFC 9309 product-token grammar"

test_that("Googlebot/2.1 on google/google is refused, with a hint", {
  r <- pt_text("Googlebot/2.1")
  pt_expect_refused(r)
  expect_match(r$error_message, pt_grammar_message, fixed = TRUE)
  expect_match(r$error_message, "not the HTTP `User-Agent` string",
               fixed = TRUE)
  expect_match(r$error_message, "leading valid part is \"Googlebot\"",
               fixed = TRUE)
  # The token is not echoed.
  expect_false(grepl("Googlebot/2.1", r$error_message, fixed = TRUE))
})

test_that("a mixed vector refuses per row, with no throw, on both entries", {
  tokens <- c(pt_refused, pt_valid)
  n_bad <- length(pt_refused)
  r <- pt_text(tokens)
  pt_expect_refused(r[seq_len(n_bad), ])
  ok <- r[-seq_len(n_bad), ]
  expect_identical(ok$matcher_status, rep("evaluated", length(pt_valid)))
  expect_identical(ok$url_decision, c("disallow", "disallow", "allow", "allow"))
  expect_identical(r$robots_product_token, tokens)

  local_fake_ssrfr(function(req) fake_response(200L, body = pt_body))
  u <- robots_evaluate_url_v1(
    rep("http://example.test/g", length(tokens)), tokens, "google", "google"
  )$results
  pt_expect_refused(u[seq_len(n_bad), ])
  expect_identical(
    u$url_decision[-seq_len(n_bad)], c("disallow", "disallow", "allow", "allow")
  )
  expect_identical(u$error_message, r$error_message)
})

test_that("each refused token names its hint, or none", {
  r <- pt_text(pt_refused)
  for (k in seq_along(pt_refused)) {
    msg <- r$error_message[[k]]
    expect_match(msg, pt_grammar_message, fixed = TRUE)
    if (is.na(pt_hints[[k]])) {
      expect_false(grepl("leading valid part", msg, fixed = TRUE),
                   label = pt_refused[[k]])
    } else {
      expect_match(msg, sprintf("leading valid part is \"%s\",", pt_hints[[k]]),
                   fixed = TRUE, label = pt_refused[[k]])
    }
    expect_true(validUTF8(msg))
    expect_false(grepl("[^\\x01-\\x7F]", msg, perl = TRUE, useBytes = TRUE))
  }
})

test_that("both screened backends refuse under all five rulesets", {
  for (backend in c("google", "rfc9309")) {
    for (ruleset in pt_rulesets) {
      r <- pt_text(pt_refused, ruleset, backend)
      pt_expect_refused(r, label = paste(backend, ruleset))
    }
  }
  # An rfc9309-backend row was capability_unavailable; a valid one still is.
  r <- pt_text(c("Googlebot/2.1", "Googlebot"), "rfc9309", "rfc9309")
  expect_identical(r$matcher_status,
                   c("not_evaluated", "capability_unavailable"))
})

test_that("the bounded backends keep their own refusals", {
  r <- pt_text("Yandex/1.0", "yandex", "yandex")
  expect_identical(r$matcher_status, "not_evaluated")
  expect_identical(r$reason, "unsupported_product_token")
  expect_identical(r$error_class, "robots_unsupported_product_token")
  r <- pt_text("Bingbot/2.0", "bing", "bing")
  expect_identical(r$reason, "unsupported_profile")
  # Keyed on the backend, not the ruleset: the google ruleset on a bounded
  # backend is not screened.
  r <- pt_text(c("Yandex/1.0", "123"), "google", "yandex")
  expect_identical(r$reason, rep("unsupported_product_token", 2L))
  r <- pt_text(c("Bingbot/2.0", "123"), "google", "bing")
  expect_identical(r$reason, rep("unsupported_profile", 2L))
})

test_that("the legacy functions read Googlebot/2.1 as before", {
  x <- allowed_by_robots_text(pt_body, "https://example.com/g",
                              "Googlebot/2.1")$results
  expect_true(x$allowed)
  x <- allowed_by_robots_text(pt_body, "https://example.com/star",
                              "Googlebot/2.1")$results
  expect_false(x$allowed)
  local_fake_ssrfr(function(req) fake_response(200L, body = pt_body))
  x <- allowed_by_robots_url("http://example.test/g", "Googlebot/2.1")$results
  expect_true(x$allowed)
})

test_that("empty and NA keep the missing-or-empty message", {
  r <- pt_text(c("", NA_character_))
  pt_expect_refused(r)
  expect_identical(
    r$error_message, rep("Robots product token is missing or empty.", 2L)
  )
})

test_that("an invalid URL wins over an invalid token", {
  r <- robots_evaluate_text_v1(
    pt_body, NA_character_, "Googlebot/2.1", "google", "google"
  )$results
  expect_identical(r$error_class, "robots_invalid_url")
  expect_identical(r$error_stage, "origin")
})

test_that("latin1 and invalid UTF-8 tokens are refused with no warning", {
  latin1 <- "G\xf6bot"
  Encoding(latin1) <- "latin1"
  bad <- rawToChar(as.raw(c(0x47, 0xff)))
  marked <- bad
  Encoding(marked) <- "bytes"
  tokens <- c(latin1, bad, marked)
  expect_no_warning(r <- pt_text(tokens))
  pt_expect_refused(r)
  # One at a time too: a bytes-marked element puts a whole vector in bytes
  # mode, so only an unmarked invalid token alone shows a screen that reads
  # characters instead of bytes.
  for (token in tokens) {
    expect_no_warning(one <- pt_text(token))
    pt_expect_refused(one)
  }
  expect_true(all(validUTF8(r$error_message)))
  expect_match(r$error_message, "leading valid part is \"G\",", fixed = TRUE)
})

test_that("the grammar does not widen with the collation locale", {
  withr::local_locale(c(LC_COLLATE = "en_US.UTF-8"))
  expect_no_warning(
    r <- pt_text(c("Gooģlebot", rawToChar(as.raw(c(0x47, 0xff)))))
  )
  pt_expect_refused(r)
  expect_no_warning(r <- pt_text(rawToChar(as.raw(c(0x47, 0xff)))))
  pt_expect_refused(r)
  expect_identical(pt_text("Googlebot")$matcher_status, "evaluated")
})

test_that("an oversized token is screened in one linear pass", {
  long <- strrep("a", 100000L)
  r <- pt_text(c(long, paste0(long, "/")))
  expect_identical(r$matcher_status, c("evaluated", "not_evaluated"))
  expect_identical(r$error_class[[2L]], "robots_invalid_product_token")
})

test_that("a refused row has no disagreement, as an empty-token row", {
  r <- pt_text(c("Googlebot/2.1", ""))
  expect_identical(r$preprocessing_disagreement, c(FALSE, FALSE))
  expect_identical(r$disagreement_clients, rep(NA_character_, 2L))
  expect_identical(r$matcher_url, rep("https://example.com/g", 2L))
})

# --- The URL entry point: no request for a refused row -----------------------

pt_recorder <- function(status = 200L) {
  seen <- new.env(parent = emptyenv())
  seen$urls <- character()
  handler <- function(req) {
    seen$urls <- c(seen$urls, req$url)
    fake_response(status, body = if (status == 200L) pt_body else raw())
  }
  list(seen = seen, handler = handler)
}

test_that("an invalid-token row alone on its origin makes no request", {
  rec <- pt_recorder()
  local_fake_ssrfr(rec$handler)
  r <- robots_evaluate_url_v1(
    c("http://bad.test/g", "http://good.test/g"),
    c("Googlebot/2.1", "Googlebot"), "google", "google"
  )
  expect_identical(rec$seen$urls, "http://good.test/robots.txt")
  pt_expect_refused(r$results[1L, ])
  expect_identical(r$results$url_decision[[2L]], "disallow")
  expect_identical(nrow(r$evidence), 1L)
})

test_that("a valid and an invalid row on one origin make one request", {
  rec <- pt_recorder()
  local_fake_ssrfr(rec$handler)
  r <- robots_evaluate_url_v1(
    rep("http://one.test/g", 2L), c("Googlebot", "archive.org_bot"),
    "google", "google"
  )$results
  expect_identical(rec$seen$urls, "http://one.test/robots.txt")
  expect_identical(r$url_decision[[1L]], "disallow")
  pt_expect_refused(r[2L, ])
})

test_that("a 404 origin with an invalid token is refused, not allow_all", {
  rec <- pt_recorder(404L)
  local_fake_ssrfr(rec$handler)
  r <- robots_evaluate_url_v1(
    rep("http://gone.test/g", 2L), c("Googlebot/2.1", "Googlebot"),
    "google", "google"
  )$results
  pt_expect_refused(r[1L, ])
  expect_identical(r$reason[[2L]], "policy_allow_all")
  expect_identical(rec$seen$urls, "http://gone.test/robots.txt")
})

# --- The published grammar --------------------------------------------------

test_that("google and rfc9309 publish the grammar; bounded backends do not", {
  for (contract in list(robots_engine_contract_v1(),
                        robots_engine_contract_v2())) {
    cap <- contract$matcher_capability
    expect_identical(cap$google$product_token_grammar, "rfc9309_identifier")
    expect_identical(cap$rfc9309$product_token_grammar, "rfc9309_identifier")
    expect_null(cap$yandex$product_token_grammar)
    expect_null(cap$bing$product_token_grammar)
    expect_identical(contract$schema_revision, "2026-11-22.1")
  }
  expect_identical(product_token_grammar_backends_v1(), c("google", "rfc9309"))
})

test_that("the validator refuses a misplaced or unknown grammar", {
  cap <- engine_backend_capability_v1()
  missing <- cap
  missing$google$product_token_grammar <- NULL
  expect_error(validate_backend_capability_v1(missing),
               class = "robotstxtr_matcher_capability_invariant")
  missing <- cap
  missing$rfc9309$product_token_grammar <- NULL
  expect_error(validate_backend_capability_v1(missing),
               class = "robotstxtr_matcher_capability_invariant")
  bounded <- cap
  bounded$yandex$product_token_grammar <- "rfc9309_identifier"
  expect_error(validate_backend_capability_v1(bounded),
               class = "robotstxtr_matcher_capability_invariant")
  unknown <- cap
  unknown$google$product_token_grammar <- "^[A-Za-z_-]+$"
  expect_error(validate_backend_capability_v1(unknown),
               class = "robotstxtr_matcher_capability_invariant")
  expect_identical(validate_backend_capability_v1(cap), cap)
})

test_that("resolve_matcher_profile keeps returning unbounded rows", {
  r <- robots_resolve_matcher_profile_v1("google", "Googlebot/2.1")
  expect_identical(r$robots_product_token, "Googlebot/2.1")
  expect_true(is.na(r$profile_id))
})
