# One batch interface for every matcher backend, dispatched generically
# (ROBO-bukqpjli). Fakes come in through the registry
# (helper-matcher-registry-bukqpjli.R), never by mocking a matcher function.

skip_without_native <- function() {
  skip_if_not(
    is.function(tryCatch(robotstxtr_checked_batch_, error = function(e) NULL)),
    "native binding not built (pure-R install)"
  )
}

seam_text <- "User-agent: *\nDisallow: /private\n"

test_that("ROBO-bukqpjli: a backend needs only a registry entry", {
  calls <- new.env(parent = emptyenv())
  registry <- fake_matcher_registry(rfc9309 = recording_adapter(calls))
  url <- c(
    "https://example.com/private/a", "https://example.com/public",
    "https://example.com/private/b"
  )
  r <- evaluate_supplied_rows(
    seam_text, url, "FooBot", "rfc9309", "rfc9309", registry
  )
  # One call, every row, in row order.
  expect_length(calls$args, 1L)
  expect_identical(calls$args[[1L]]$urls, url)
  expect_identical(calls$args[[1L]]$product_tokens, rep("FooBot", 3L))
  expect_identical(
    calls$args[[1L]]$bodies, rep(list(charToRaw(seam_text)), 3L)
  )
  expect_identical(r$matcher_backend_revision, rep("fake-rfc9309", 3L))
  expect_identical(r$matcher_availability, rep("available", 3L))
  expect_identical(r$matcher_status, rep("evaluated", 3L))
  expect_identical(r$url_decision, c("disallow", "allow", "disallow"))
  expect_identical(r$matched_line, c(7L, NA, 7L))
  expect_identical(r$matched_rule_value_raw, lapply(url, charToRaw))
  # Extra columns and attributes of the frame are ignored.
  expect_false("native_fake" %in% names(r))
})

test_that("ROBO-bukqpjli: interleaved backends scatter back to their rows", {
  calls_google <- new.env(parent = emptyenv())
  calls_rfc <- new.env(parent = emptyenv())
  registry <- fake_matcher_registry(
    google = recording_adapter(calls_google),
    rfc9309 = recording_adapter(calls_rfc)
  )
  url <- paste0("https://example.com/", c("private/1", "a", "private/3", "b"))
  backend <- c("google", "rfc9309", "rfc9309", "google")
  r <- evaluate_supplied_rows(
    seam_text, url, "FooBot", "google", backend, registry
  )
  expect_length(calls_google$args, 1L)
  expect_length(calls_rfc$args, 1L)
  expect_identical(calls_google$args[[1L]]$urls, url[c(1L, 4L)])
  expect_identical(calls_rfc$args[[1L]]$urls, url[c(2L, 3L)])
  expect_identical(r$url_decision, c("disallow", "allow", "disallow", "allow"))
  expect_identical(r$matched_rule_value, c(url[[1L]], NA, url[[3L]], NA))
  expect_identical(r$matched_rule_value_raw, lapply(url, charToRaw))
})

test_that("ROBO-bukqpjli: the public entry points take no registry", {
  expect_true("matcher_registry" %in% names(formals(evaluate_rows_v1)))
  for (f in list(robots_evaluate_text_v1, robots_evaluate_url_v1)) {
    expect_false("matcher_registry" %in% names(formals(f)))
  }
})

test_that("ROBO-bukqpjli: the evaluator never dispatches on a backend name", {
  code <- deparse1(evaluate_rows_v1, collapse = "\n")
  for (name in engine_matchers_v1()) {
    expect_false(grepl(sprintf("\"%s\"", name), code, fixed = TRUE),
                 label = name)
  }
})

test_that("ROBO-bukqpjli: every adapter passes the adapter-output check", {
  skip_without_native()
  bodies <- list(
    charToRaw(seam_text),
    charToRaw("User-agent: Yandex\nUser-agent: bingbot\nDisallow: /a\n"),
    charToRaw(seam_text)
  )
  urls <- c(
    "https://example.com/private", "https://example.com/a",
    "https://example.com/public"
  )
  expect_adapter_output(
    match_google_batch_v1, bodies, urls, "FooBot", "google"
  )
  expect_adapter_output(match_yandex_v1, bodies, urls, "Yandex", "yandex")
  expect_adapter_output(match_bing_v1, bodies, urls, "bingbot", "bing")
  fake <- function(bodies, urls, product_tokens) fake_decision_frame(urls)
  expect_adapter_output(fake, bodies, urls, "FooBot", "fake")
  # Unaccepted selectors are rows too, never an abort.
  expect_adapter_output(match_yandex_v1, bodies, urls, "FooBot", "yandex")
  expect_adapter_output(match_bing_v1, bodies, urls, "FooBot", "bing")
})

test_that("ROBO-bukqpjli: the Google adapter keeps each row's own cut", {
  over <- c(
    charToRaw("User-agent: *\nDisallow: /private\n"),
    rep(charToRaw("#"), 520000L), charToRaw("\nAllow: /private\n")
  )
  bodies <- list(over, charToRaw(seam_text), over)
  out <- expect_adapter_output(
    match_google_batch_v1, bodies, "https://example.com/private", "FooBot",
    "google"
  )
  expect_identical(out$matcher_body_truncated, c(TRUE, FALSE, TRUE))
  expect_identical(out$url_decision, rep("disallow", 3L))
  expect_identical(out$matched_rule_value_raw, vector("list", 3L))
  expect_identical(out$matcher_status, rep("evaluated", 3L))
})

test_that("ROBO-bukqpjli: a cut body reaches the adapter cut to lines", {
  calls <- new.env(parent = emptyenv())
  local_matcher_registry(
    fake_matcher_registry(google = recording_adapter(calls))
  )
  body <- c(
    charToRaw("User-agent: *\nDisallow: /private\n"),
    rep(charToRaw("#"), 600000L)
  )
  local_fake_ssrfr(function(req) fake_response(200L, body = body))
  x <- robots_evaluate_url_v1(
    c("http://example.test/private", "http://example.test/public"),
    "FooBot", "google", "google", fetch_user_agent = "seam/1.0"
  )
  # The evidence is cut at max_bytes; the adapter sees only complete lines
  # and is called once for both rows.
  expect_true(x$evidence$body_truncated)
  expect_length(calls$args, 1L)
  expect_identical(
    calls$args[[1L]]$bodies,
    rep(list(charToRaw("User-agent: *\nDisallow: /private\n")), 2L)
  )
  # The adapter said "not truncated"; each row keeps its own cut.
  expect_identical(x$results$matcher_body_truncated, c(TRUE, TRUE))
  expect_identical(x$results$url_decision, c("disallow", "allow"))
})

# --- The adapter-output check bites -----------------------------------------

test_that("ROBO-bukqpjli: a broken decision frame fails loudly", {
  good <- fake_decision_frame(c("https://e.test/private", "https://e.test/"))
  expect_identical(check_matcher_output_v1(good, 2L, "fake"), good)
  short <- good[1L, , drop = FALSE]
  no_reason <- good[setdiff(names(good), "reason")]
  flat_raw <- good
  flat_raw$matched_rule_value_raw <- c("a", "b")
  for (broken in list(short, no_reason, flat_raw, as.list(good), NULL)) {
    expect_error(
      check_matcher_output_v1(broken, 2L, "fake"),
      class = "robotstxtr_matcher_output_invariant"
    )
  }
  expect_error(
    check_matcher_output_v1(no_reason, 2L, "fake"),
    "missing column\\(s\\): reason"
  )
  expect_error(check_matcher_output_v1(short, 2L, "fake"), "1 row\\(s\\) for 2")
})

test_that("ROBO-bukqpjli: the evaluator runs the check on every adapter", {
  url <- c("https://example.com/private", "https://example.com/public")
  one_short <- function(bodies, urls, product_tokens) {
    fake_decision_frame(urls)[-1L, , drop = FALSE]
  }
  missing_column <- function(bodies, urls, product_tokens) {
    out <- fake_decision_frame(urls)
    out$error_class <- NULL
    out
  }
  for (adapter in list(one_short, missing_column)) {
    for (backend in c("google", "rfc9309")) {
      registry <- fake_matcher_registry(google = adapter, rfc9309 = adapter)
      expect_error(
        evaluate_supplied_rows(
          seam_text, url, "FooBot", "google", backend, registry
        ),
        class = "robotstxtr_matcher_output_invariant"
      )
    }
  }
  # Through a public entry point too.
  local_matcher_registry(fake_matcher_registry(google = one_short))
  expect_error(
    robots_evaluate_text_v1(seam_text, url, "FooBot", "google", "google"),
    class = "robotstxtr_matcher_output_invariant"
  )
})

test_that("ROBO-bukqpjli: an adapter's own abort is not caught", {
  aborting <- function(bodies, urls, product_tokens) {
    robots_abort("adapter invariant", "robotstxtr_fake_adapter_invariant")
  }
  registry <- fake_matcher_registry(google = aborting)
  expect_error(
    evaluate_supplied_rows(
      seam_text, "https://example.com/", "FooBot", "google", "google",
      registry
    ),
    class = "robotstxtr_fake_adapter_invariant"
  )
})

test_that("ROBO-bukqpjli: no fallthrough for an unknown backend", {
  registry <- engine_matcher_registry_v1()
  for (backend in c("unknown", "rfc9309", NA_character_)) {
    expect_error(
      dispatch_matcher_v1(
        registry, backend, list(raw(0)), "https://example.com/", "bot"
      ),
      class = "robotstxtr_matcher_backend_unavailable"
    )
  }
  # An unavailable backend is decided before dispatch, as before.
  r <- evaluate_supplied_rows(
    seam_text, "https://example.com/private", "FooBot", "rfc9309",
    "rfc9309", registry
  )
  expect_identical(r$matcher_status, "capability_unavailable")
})

test_that("ROBO-bukqpjli: a forbidden registry proves no row was matched", {
  calls <- new.env(parent = emptyenv())
  local_matcher_registry(forbidden_matcher_registry(calls))
  x <- robots_evaluate_text_v1(
    seam_text, "https://example.com/private", "FooBot", "rfc9309", "rfc9309"
  )
  expect_identical(x$results$matcher_status, "capability_unavailable")
  expect_identical(c(calls$google, calls$yandex, calls$bing), c(0L, 0L, 0L))
  expect_error(
    robots_evaluate_text_v1(
      seam_text, "https://example.com/private", "FooBot", "google", "google"
    ),
    "the google adapter must not be called"
  )
  expect_identical(calls$google, 1L)
})
