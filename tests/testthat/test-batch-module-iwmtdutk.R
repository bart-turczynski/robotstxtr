# Pins for the shared Yandex/Bing batch module (ROBO-iwmtdutk).
#
# The refactor moves the body grouping, the request-target bytes, the empty
# frame and the recycling that match_yandex_v1() and match_bing_v1() each
# carried into one module, and the C++ byte helpers the three bindings each
# carried into one header. It must change no result. Slice A's pin
# (test-matcher-seam-pin-bukqpjli.R) covers the public v1 results frame;
# these pin what that frame does not show: each adapter's full frame (the
# native_* columns and the n_parse_calls attribute included) on bodies and
# targets with invalid UTF-8 and NUL bytes, the empty input, length-1
# recycling, and the UTF-8 check at every boundary through each binding.
# All bodies and URLs are synthesized.

iw_bytes <- function(...) {
  parts <- list(...)
  unlist(lapply(parts, function(p) {
    if (is.character(p)) charToRaw(p) else as.raw(p)
  }))
}

# A URL holding raw bytes, marked UTF-8 (as slice A's pin marks its URLs) so
# the bytes reach the extractors untranslated in every locale.
iw_url <- function(...) {
  url <- rawToChar(iw_bytes(...))
  Encoding(url) <- "UTF-8"
  url
}

iw_bodies <- list(
  plain = iw_bytes("User-agent: *\nDisallow: /private\nAllow: /private/ok\n"),
  # As long as `plain` and differing in one byte: grouping must key on bytes.
  plain_twin = iw_bytes(
    "User-agent: *\nDisallow: /privatf\nAllow: /private/ok\n"
  ),
  nul = iw_bytes("User-agent: *\nDisallow: /n", 0L, "ul\n"),
  bad_utf8 = iw_bytes("User-agent: *\nDisallow: /a", 0xffL, "\n"),
  empty = raw(0),
  named = iw_bytes(
    "User-agent: Yandex\nUser-agent: bingbot\nDisallow: /\n",
    "User-agent: *\nAllow: /\n"
  ),
  empty_disallow = iw_bytes("User-agent: *\nDisallow:\n"),
  # One physical line over Bing's 65,536-byte ceiling: a Bing parse limit.
  long_line = iw_bytes(
    "User-agent: *\nDisallow: /", strrep("a", 70000L), "\n"
  )
)

iw_urls <- c(
  "https://example.com/private",
  "https://example.com/private/ok",
  iw_url("https://example.com/a", 0xffL),
  "https://example.com/n%00ul",
  "https://example.com/",
  NA_character_,
  "",
  "not a url"
)

# Every body against every URL and token, so the batch holds duplicate
# bodies and every outcome the two engines give at this layer.
iw_grid <- function(tokens) {
  g <- expand.grid(
    body = seq_along(iw_bodies), url = seq_along(iw_urls),
    token = seq_along(tokens)
  )
  list(
    bodies = unname(iw_bodies[g$body]),
    urls = iw_urls[g$url],
    tokens = tokens[g$token]
  )
}

iw_tokens <- list(
  yandex = c("Yandex", "YandexAdditionalBot", "FooBot", ""),
  bing = c("bingbot", "adidxbot", "FooBot", "")
)

iw_adapters <- list(yandex = match_yandex_v1, bing = match_bing_v1)

iw_digest <- function(frame) {
  seam_digest(frame, extra = c(
    sprintf("n_parse_calls %s", format(attr(frame, "n_parse_calls"))),
    sprintf("row.names %s", paste(attr(frame, "row.names"), collapse = ","))
  ))
}

# Computed with the R adapters of the base before the refactor (232b92d)
# sourced over the refactored native bindings, since the grid gained
# `plain_twin` (993091e). Without the twin, the current code still gives the
# digests the base itself gave.
iw_pinned <- c(
  yandex = "5ac927dc412f247270973dc70b83f04e",
  bing = "bd3e1b4caa6d74d34f20bdf5b40b332f"
)

test_that("each adapter's full frame on the synthesized batch is unchanged", {
  for (backend in names(iw_adapters)) {
    g <- iw_grid(iw_tokens[[backend]])
    frame <- iw_adapters[[backend]](g$bodies, g$urls, g$tokens)
    expect_identical(
      check_matcher_output_v1(frame, length(g$bodies), backend), frame
    )
    expect_identical(attr(frame, "n_parse_calls"), length(iw_bodies))
    expect_identical(iw_digest(frame), iw_pinned[[backend]], label = backend)
  }
})

test_that("an empty batch returns the empty frame of each adapter", {
  columns <- list(
    native_evaluation_status = character(),
    matcher_status = character(),
    url_decision = character(),
    reason = character(),
    matched_line = integer(),
    matched_rule_type = character(),
    matched_rule_value = character(),
    matcher_input_bytes = integer(),
    matcher_body_truncated = logical(),
    error_stage = character(),
    error_class = character(),
    error_message = character()
  )
  empty_frame <- function(cols) {
    out <- do.call(data.frame, c(cols, stringsAsFactors = FALSE))
    out$matched_rule_value_raw <- list()
    attr(out, "n_parse_calls") <- 0L
    out
  }
  expected <- list(
    yandex = empty_frame(columns),
    bing = empty_frame(c(list(native_parse_status = character()), columns))
  )
  for (backend in names(iw_adapters)) {
    for (args in list(
      list(list(), character(), character()),
      list(list(), "https://example.com/", iw_tokens[[backend]][[1L]])
    )) {
      frame <- do.call(iw_adapters[[backend]], args)
      expect_identical(frame, expected[[backend]], label = backend)
      expect_identical(check_matcher_output_v1(frame, 0L, backend), frame)
    }
  }
})

test_that("a length-1 URL and token are recycled over every body", {
  for (backend in names(iw_adapters)) {
    adapter <- iw_adapters[[backend]]
    bodies <- unname(iw_bodies)
    n <- length(bodies)
    for (url in iw_urls) {
      for (token in iw_tokens[[backend]]) {
        expect_identical(
          adapter(bodies, url, token),
          adapter(bodies, rep(url, n), rep(token, n)),
          label = paste(backend, url, token)
        )
      }
    }
  }
})

test_that("a non-list `bodies` aborts with the adapter's own class", {
  body <- iw_bodies$plain
  expect_error(
    match_yandex_v1(body, "https://example.com/", "Yandex"),
    class = "robotstxtr_invalid_yandex_bodies"
  )
  expect_error(
    match_bing_v1(body, "https://example.com/", "bingbot"),
    class = "robotstxtr_invalid_bing_bodies"
  )
})

test_that("a non-raw body element is refused by each native binding", {
  expect_error(
    yandex_evaluate_checked_batch(
      list("x"), 1L, "Yandex", list(charToRaw("/"))
    ),
    "expected a raw vector"
  )
  expect_error(
    bing_evaluate_batch(list("x"), 1L, "bingbot", list(charToRaw("/"))),
    "expected a raw vector"
  )
  expect_error(
    yandex_evaluate_checked_batch(list(raw(0)), 1L, "Yandex", list("/")),
    "expected a raw vector"
  )
  expect_error(
    bing_evaluate_batch(list(raw(0)), 1L, "bingbot", list("/")),
    "expected a raw vector"
  )
})

# Each byte sequence and whether it is well-formed UTF-8: the boundaries of
# every branch of the bindings' is_valid_utf8().
iw_utf8_cases <- list(
  list(bytes = 0x7fL, valid = TRUE),
  list(bytes = 0x80L, valid = FALSE),
  list(bytes = c(0xc1L, 0xbfL), valid = FALSE),
  list(bytes = c(0xc2L, 0x80L), valid = TRUE),
  list(bytes = c(0xdfL, 0xbfL), valid = TRUE),
  list(bytes = c(0xc2L, 0x41L), valid = FALSE),
  list(bytes = 0xc2L, valid = FALSE),
  list(bytes = c(0xe0L, 0x9fL, 0xbfL), valid = FALSE),
  list(bytes = c(0xe0L, 0xa0L, 0x80L), valid = TRUE),
  list(bytes = c(0xe1L, 0x80L), valid = FALSE),
  list(bytes = c(0xe1L, 0x80L, 0x41L), valid = FALSE),
  list(bytes = c(0xedL, 0x9fL, 0xbfL), valid = TRUE),
  list(bytes = c(0xedL, 0xa0L, 0x80L), valid = FALSE),
  list(bytes = c(0xefL, 0xbfL, 0xbfL), valid = TRUE),
  list(bytes = c(0xf0L, 0x8fL, 0xbfL, 0xbfL), valid = FALSE),
  list(bytes = c(0xf0L, 0x90L, 0x80L, 0x80L), valid = TRUE),
  list(bytes = c(0xf4L, 0x8fL, 0xbfL, 0xbfL), valid = TRUE),
  list(bytes = c(0xf4L, 0x90L, 0x80L, 0x80L), valid = FALSE),
  list(bytes = c(0xf1L, 0x80L, 0x80L), valid = FALSE),
  list(bytes = c(0xf1L, 0x80L, 0x80L, 0x41L), valid = FALSE),
  list(bytes = c(0xf5L, 0x80L, 0x80L, 0x80L), valid = FALSE),
  list(bytes = 0xffL, valid = FALSE)
)

test_that("Yandex and Bing surface a rule value as UTF-8 only when it is", {
  for (case in iw_utf8_cases) {
    value <- iw_bytes("/a", case$bytes)
    body <- iw_bytes("User-agent: *\nDisallow: ", value, "\n")
    url <- iw_url("https://example.com", value, "x")
    for (backend in names(iw_adapters)) {
      label <- paste(backend, paste(case$bytes, collapse = " "))
      frame <- iw_adapters[[backend]](
        list(body), url, iw_tokens[[backend]][[1L]]
      )
      expect_identical(frame$url_decision, "disallow", label = label)
      expect_identical(frame$matched_rule_value_raw, list(value), label = label)
      if (case$valid) {
        expected <- rawToChar(value)
        Encoding(expected) <- "UTF-8"
        expect_identical(frame$matched_rule_value, expected, label = label)
      } else {
        expect_identical(frame$matched_rule_value, NA_character_, label = label)
      }
    }
  }
})

test_that("the Google collector marks a value UTF-8 only when it is", {
  for (case in iw_utf8_cases) {
    value <- iw_bytes("http://a/", case$bytes)
    body <- rawToChar(iw_bytes("sitemap: ", value))
    Encoding(body) <- "UTF-8"
    d <- collect_directive_lookup(body)
    got <- d$value[d$line == 1L]
    label <- paste(case$bytes, collapse = " ")
    expect_identical(charToRaw(got), value, label = label)
    # R leaves an all-ASCII string unmarked whatever the binding asks for.
    expected <- if (!case$valid) {
      "bytes"
    } else if (all(value < as.raw(0x80))) {
      "unknown"
    } else {
      "UTF-8"
    }
    expect_identical(Encoding(got), expected, label = label)
  }
})

test_that("each binding hands the request-target bytes back verbatim", {
  target <- iw_bytes("/a", 0xffL, 0L, "b")
  y <- yandex_evaluate_checked_batch(
    list(iw_bodies$plain), 1L, "Yandex", list(target)
  )
  b <- bing_evaluate_batch(list(iw_bodies$plain), 1L, "bingbot", list(target))
  expect_identical(y$matcher_request_target_raw, list(target))
  expect_identical(b$matcher_request_target_raw, list(target))
})

# A fake native batch for driving run_batch_matcher_v1() directly: every row
# allowed, one native status column, and what it was called with recorded in
# `seen`. Its parameters are in a different order from the module's.
iw_fake_run <- function(urls, tokens, seen = new.env()) {
  native_eval <- function(bodies, body_index, targets, product_tokens) {
    seen$targets <- targets
    seen$product_tokens <- product_tokens
    n <- length(body_index)
    list(
      native_status = rep("ok", n),
      url_decision = rep(TRUE, n),
      matched_line = rep(NA_integer_, n),
      matched_rule_type = rep(NA_character_, n),
      matched_rule_value = rep(NA_character_, n),
      matcher_input_bytes = rep(0L, n),
      matched_rule_value_raw = vector("list", n),
      n_parse_calls = 1L
    )
  }
  map_status <- function(native, url_decision) {
    n <- length(url_decision)
    list(
      matcher_status = rep("evaluated", n), reason = rep(NA_character_, n),
      matcher_body_truncated = rep(FALSE, n),
      error_stage = rep(NA_character_, n),
      error_class = rep(NA_character_, n), error_message = rep(NA_character_, n)
    )
  }
  run_batch_matcher_v1(
    rep(list(charToRaw("User-agent: *\n")), length(urls)), urls, tokens,
    "robotstxtr_test_bodies", function(url) "/x", native_eval, map_status,
    "native_status"
  )
}

test_that("the module hands the native batch its tokens and targets", {
  seen <- new.env()
  iw_fake_run("https://example.com/", "bot", seen)
  # The call is by name (ROBO-wuhugihe), so a native batch whose parameters
  # are ordered differently still gets each argument where it belongs.
  expect_identical(seen$product_tokens, "bot")
  expect_identical(seen$targets, list(charToRaw("/x")))
})

test_that("the decision prototype is the contract's atomic columns", {
  expect_named(
    matcher_decision_prototype_v1(),
    setdiff(matcher_decision_columns_v1(), "matched_rule_value_raw")
  )
})

test_that("the empty and non-empty frames have one column list and types", {
  empty <- matcher_batch_empty_frame_v1("native_status")
  one <- iw_fake_run("https://example.com/", "bot")
  expected <- c("native_status", matcher_decision_columns_v1())
  expect_named(empty, expected)
  expect_named(one, expected)
  expect_identical(
    vapply(empty, typeof, character(1L)), vapply(one, typeof, character(1L))
  )
  expect_identical(lapply(empty, class), lapply(one, class))
})

test_that("a native result missing a declared column aborts", {
  native_eval <- function(bodies, body_index, product_tokens, targets) {
    n <- length(body_index)
    list(
      url_decision = rep(TRUE, n),
      matched_line = rep(NA_integer_, n),
      matched_rule_type = rep(NA_character_, n),
      matched_rule_value = rep(NA_character_, n),
      matcher_input_bytes = rep(0, n),
      matched_rule_value_raw = vector("list", n),
      n_parse_calls = 1L
    )
  }
  map_status <- function(native, url_decision) {
    n <- length(url_decision)
    list(
      matcher_status = rep("evaluated", n), reason = rep(NA_character_, n),
      matcher_body_truncated = rep(FALSE, n),
      error_stage = rep(NA_character_, n),
      error_class = rep(NA_character_, n), error_message = rep(NA_character_, n)
    )
  }
  expect_error(
    run_batch_matcher_v1(
      list(charToRaw("User-agent: *\n")), "https://example.com/", "bot",
      "robotstxtr_test_bodies", identity, native_eval, map_status,
      "native_status"
    ),
    class = "robotstxtr_matcher_output_invariant"
  )
})
