# The shared batch module behind the Yandex, Bing and Google matcher adapters
# (ROBO-iwmtdutk; Google since ROBO-iooslxvj).
#
# The adapters have slice A's batch interface `callable(bodies, urls,
# product_tokens)` -> a decision frame (ROBO-bukqpjli), and each native
# binding parses each DISTINCT body exactly once. What the adapters
# share is batching and result transport, and that is all this module
# holds: the argument check, recycling, the request-target bytes, the
# distinct-body grouping, the allow/disallow decision, the empty frame and
# the frame assembly. Everything an engine decides stays with its adapter:
# the request-target extractor, the native evaluation, and the mapping of
# native statuses onto matcher_status, reason and the error columns. No
# parser, group selector, access matcher or URL normalizer is shared
# (design/robotstxtbing-integration-v2-spec.md SS4).

# One row's absolute URL as the exact request-target BYTES a native binding
# evaluates. `extract_target` is the engine's own lexical extractor: one URL
# in, the slash-prefixed target or NA_character_ out. A missing or empty URL,
# or one the extractor gives no target for, becomes an empty target
# (raw(0)), and each engine decides what that means. Yandex and Bing reject it
# as invalid_request_target -- unless the product token is also unsupported,
# in which case the engine reports that first; leaving that precedence to the
# engine, rather than mapping the NA here, keeps each engine's own
# unsupported-first rule. Google reads the empty URL as the path "/".
matcher_target_bytes_v1 <- function(url, extract_target) {
  if (is.na(url) || !nzchar(url)) {
    return(raw(0))
  }
  target <- extract_target(url)
  if (is.na(target)) {
    return(raw(0))
  }
  charToRaw(target)
}

# One body's grouping key, exact on its bytes alone (attributes aside). A raw
# body with no NUL byte is its own key: the bytes as one string. Any other
# raw body's key is its length, the positions of its NUL bytes and its other
# bytes, which give the bytes back. A body that is not raw (NULL included)
# gets a key of its own row: it is never grouped with another, and reaches
# the engine as it is, to be refused there as on its own (by the Yandex and
# Bing bindings, and by Google's matcher decoding). The keys are all in the
# native encoding, so duplicated() and match() compare them as stored, never
# translated.
matcher_body_key_v1 <- function(body, row) {
  if (!is.raw(body)) {
    return(sprintf("<%s>%d", typeof(body), row))
  }
  # rawToChar() refuses an embedded NUL and drops trailing ones: either way
  # the body is not a plain string.
  text <- tryCatch(rawToChar(body), error = function(e) NULL)
  if (!is.null(text) && nchar(text, type = "bytes") == length(body)) {
    return(text)
  }
  nul <- body == as.raw(0)
  paste0(
    length(body), ":", paste(which(nul), collapse = ","), ":",
    rawToChar(body[!nul])
  )
}

# Group per-row raw bodies into the distinct-body list + 1-based index the
# native batch bindings take, distinct bodies in order of first appearance,
# raw ones with their attributes dropped. The key is exact on the bytes
# (matcher_body_key_v1()), so embedded NUL and invalid UTF-8 dedupe exactly,
# and match() hashes it. A plain body's key is its bytes, which could spell
# any other key, so plain and other keys are matched apart. Rendering every
# byte as hex for a key (the earlier helper) cost more than the Google
# matcher's parses on a large body, and match() on the list of bodies itself
# is as slow (ROBO-iooslxvj, dev/bench-google-batch.R).
matcher_body_groups_v1 <- function(bodies) {
  n <- length(bodies)
  keys <- vapply(
    seq_len(n), function(i) matcher_body_key_v1(bodies[[i]], i), character(1L)
  )
  # Only a plain body's key is exactly as long as the body: another raw key
  # adds its length and NUL positions, which outnumber the NULs it drops.
  plain <- vapply(bodies, is.raw, logical(1L)) &
    nchar(keys, type = "bytes") == lengths(bodies)
  group <- integer(n)
  group[plain] <- which(plain)[match(keys[plain], keys[plain])]
  group[!plain] <- which(!plain)[match(keys[!plain], keys[!plain])]
  first <- !duplicated(group)
  distinct_bodies <- lapply(bodies[first], function(body) {
    if (is.raw(body)) as.vector(body) else body
  })
  list(
    distinct_bodies = distinct_bodies,
    body_index = match(group, group[first])
  )
}

# The one list of the atomic decision columns the module builds, in frame
# order, each as its zero-length type: matcher_decision_columns_v1() without
# the list column matched_rule_value_raw, which is assigned separately. Both
# the empty and the assembled frame take their columns from it.
matcher_decision_prototype_v1 <- function() {
  list(
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
}

# The frame for zero rows: the adapter's native status columns, then the
# decision columns, with the types the non-empty frame has.
matcher_batch_empty_frame_v1 <- function(native_columns) {
  native <- rep(list(character()), length(native_columns))
  names(native) <- native_columns
  out <- do.call(data.frame, c(
    native, matcher_decision_prototype_v1(), stringsAsFactors = FALSE
  ))
  out$matched_rule_value_raw <- list()
  attr(out, "n_parse_calls") <- 0L
  out
}

# Run one engine's batch over every row and return its decision frame.
#
# - `bodies_class`: the error class for a `bodies` that is not a list.
# - `extract_target(url)`: the engine's request-target extractor (see
#   matcher_target_bytes_v1()).
# - `native_eval(bodies, body_index, product_tokens, targets)`: the engine's
#   native batch, called with those four arguments by name: the distinct
#   bodies, the 1-based body per row, and the token and target bytes per row.
#   It returns the native per-row columns and the scalar `n_parse_calls`.
# - `map_status(native, url_decision)`: the engine's mapping, returning a list
#   of `matcher_status`, `reason`, `matcher_body_truncated`, `error_stage`,
#   `error_class` and `error_message`, one element per row.
# - `native_columns`: the native status columns the frame carries first,
#   verbatim.
#
# The frame carries the native columns, then the decision columns
# (matcher_decision_columns_v1()), the matched-rule columns passed through
# from the native result, and the distinct-body parse count as the
# `n_parse_calls` attribute.
run_batch_matcher_v1 <- function(bodies, urls, product_tokens, bodies_class,
                                 extract_target, native_eval, map_status,
                                 native_columns) {
  if (!is.list(bodies)) {
    robots_abort("`bodies` must be a list of raw vectors.", bodies_class)
  }
  n <- length(bodies)
  if (n == 0L) {
    return(matcher_batch_empty_frame_v1(native_columns))
  }
  urls <- rep(urls, length.out = n)
  product_tokens <- rep(product_tokens, length.out = n)

  targets_raw <- lapply(urls, matcher_target_bytes_v1, extract_target)
  groups <- matcher_body_groups_v1(bodies)

  native <- native_eval(
    bodies = groups$distinct_bodies, body_index = groups$body_index,
    product_tokens = product_tokens, targets = targets_raw
  )

  decided <- !is.na(native$url_decision)
  url_decision <- rep(NA_character_, n)
  url_decision[decided & native$url_decision] <- "allow"
  url_decision[decided & !native$url_decision] <- "disallow"

  mapped <- map_status(native, url_decision)

  # A renamed native column would come back NULL and vanish from the frame.
  missing_native <- setdiff(native_columns, names(native))
  if (length(missing_native) > 0L) {
    robots_abort(
      sprintf(
        "Native matcher output lacks column(s): %s.",
        toString(missing_native)
      ),
      "robotstxtr_matcher_output_invariant"
    )
  }

  # Each decision column from where it comes: the decision computed here, the
  # matched-rule columns from the native result, the rest from the mapping.
  # The prototype names which columns the frame carries, and in what order.
  decision <- c(
    list(url_decision = url_decision),
    native[c(
      "matched_line", "matched_rule_type", "matched_rule_value",
      "matcher_input_bytes"
    )],
    mapped
  )
  out <- do.call(data.frame, c(
    native[native_columns],
    decision[names(matcher_decision_prototype_v1())],
    stringsAsFactors = FALSE
  ))
  # Assign the native list THROUGH unchanged so the raw(0) (present-but-empty)
  # vs NULL (absent) distinction survives verbatim -- rebuilding it would drop
  # the NULL elements.
  out$matched_rule_value_raw <- native$matched_rule_value_raw
  attr(out, "n_parse_calls") <- native$n_parse_calls
  out
}
