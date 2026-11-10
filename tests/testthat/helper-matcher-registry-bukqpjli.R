# Fake matcher registries and the shared adapter-output check
# (ROBO-bukqpjli).
#
# Every matcher adapter has one batch interface,
# `callable(bodies, urls, product_tokens)` -> a decision frame, and the
# evaluator dispatches on the registry entry alone. So a test swaps an
# engine by swapping its registry entry: fake_matcher_registry() builds one
# from the production registry, and local_matcher_registry() makes the
# public entry points use it. evaluate_rows_v1() also takes the registry as
# its internal `matcher_registry` argument.

# The production registry with the named adapters swapped in. A backend
# named here becomes available; an unavailable backend gets a fake revision,
# as the registry invariants require.
fake_matcher_registry <- function(...) {
  adapters <- list(...)
  registry <- engine_matcher_registry_v1()
  for (backend in names(adapters)) {
    entry <- registry[[backend]]
    if (identical(entry$availability, "capability_unavailable")) {
      entry$revision <- paste0("fake-", backend)
      entry$availability <- "available"
    }
    entry["callable"] <- list(adapters[[backend]])
    registry[[backend]] <- entry
  }
  registry
}

# Make the public entry points use `registry` until `env` exits.
local_matcher_registry <- function(registry, env = parent.frame()) {
  # Built now, from the real registry, before the binding is swapped.
  force(registry)
  testthat::local_mocked_bindings(
    engine_matcher_registry_v1 = function() registry,
    .package = "robotstxtr",
    .env = env
  )
}

# A batch adapter from a row fake `function(body, url, product_token)` that
# returns one row's fields, the way the Google adapter wraps match_google_v1.
fake_row_adapter <- function(row_fake) {
  function(bodies, urls, product_tokens) {
    row_matcher_frame_v1(row_fake, bodies, urls, product_tokens)
  }
}

# An adapter that fails the test if it is ever called, counting the calls in
# `calls[[backend]]`.
forbidden_adapter <- function(calls, backend) {
  calls[[backend]] <- 0L
  function(bodies, urls, product_tokens) {
    calls[[backend]] <- calls[[backend]] + 1L
    stop(sprintf("the %s adapter must not be called", backend))
  }
}

# A registry whose every available adapter is forbidden: for tests that a
# row never reaches a matcher.
forbidden_matcher_registry <- function(calls) {
  fake_matcher_registry(
    google = forbidden_adapter(calls, "google"),
    yandex = forbidden_adapter(calls, "yandex"),
    bing = forbidden_adapter(calls, "bing")
  )
}

# The shared adapter-output check, for real and fake adapters alike: the
# frame passes check_matcher_output_v1(), has one row per input, and each
# row is what the adapter returns for that row alone, so order is kept.
expect_adapter_output <- function(adapter, bodies, urls, product_tokens,
                                  backend) {
  n <- length(bodies)
  urls <- rep_len(urls, n)
  product_tokens <- rep_len(product_tokens, n)
  out <- adapter(bodies = bodies, urls = urls, product_tokens = product_tokens)
  expect_identical(
    check_matcher_output_v1(out, n, backend), out, label = backend
  )
  expect_identical(nrow(out), n, label = backend)
  columns <- matcher_decision_columns_v1()
  for (k in seq_len(n)) {
    alone <- adapter(
      bodies = bodies[k], urls = urls[k], product_tokens = product_tokens[k]
    )
    for (column in columns) {
      expect_identical(
        out[[column]][k], alone[[column]][1L],
        label = sprintf("%s row %d %s", backend, k, column)
      )
    }
  }
  invisible(out)
}

# A canned decision frame for `n` rows; `url_decision` and the raw value
# follow the row's URL, so a scatter to the wrong row shows.
fake_decision_frame <- function(urls, status = "evaluated") {
  n <- length(urls)
  private <- grepl("private", urls, fixed = TRUE)
  out <- data.frame(
    matcher_status = rep(status, n),
    url_decision = ifelse(private, "disallow", "allow"),
    reason = ifelse(private, "rule_disallow", "default_allow"),
    matched_line = ifelse(private, 7L, NA_integer_),
    matched_rule_type = ifelse(private, "disallow", "none"),
    matched_rule_value = ifelse(private, urls, NA_character_),
    matcher_input_bytes = rep(42L, n),
    matcher_body_truncated = rep(FALSE, n),
    error_stage = rep(NA_character_, n),
    error_class = rep(NA_character_, n),
    error_message = rep(NA_character_, n),
    native_fake = rep("ignored", n),
    stringsAsFactors = FALSE
  )
  out$matched_rule_value_raw <- lapply(urls, charToRaw)
  attr(out, "n_parse_calls") <- 1L
  out
}

# A batch fake that records every call's arguments in `calls$args`.
recording_adapter <- function(calls) {
  calls$args <- list()
  function(bodies, urls, product_tokens) {
    calls$args[[length(calls$args) + 1L]] <- list(
      bodies = bodies, urls = urls, product_tokens = product_tokens
    )
    fake_decision_frame(urls)
  }
}

# evaluate_rows_v1() on one supplied body, with `registry`.
evaluate_supplied_rows <- function(text, url, token, ruleset, backend,
                                   registry) {
  n <- length(url)
  evidence <- supplied_evidence_v1(charToRaw(text), "supplied")
  evaluate_rows_v1(
    url, rep_len(token, n), rep_len(ruleset, n), rep_len(backend, n),
    rep("supplied", n), evidence, rep(TRUE, n), rep(TRUE, n),
    NA_character_, NA_real_, NA_integer_, NA, NA_character_,
    matcher_registry = registry
  )
}
