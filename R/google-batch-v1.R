# The Google side of the shared batch module (ROBO-iooslxvj).
#
# match_google_batch_v1() (R/engine-contract-v1.R) runs Google through
# run_batch_matcher_v1() (R/matcher-batch-v1.R) with the three pieces below:
# the request-target extractor, the native batch, and the status mapping.
# The native batch parses each distinct body once and answers every row that
# selects it (the line collector reads each body with a matched row once
# more); match_google_v1() stays the reference row matcher, and the batch
# gives, row for row, the frame row_matcher_frame_v1(match_google_v1, ...)
# gives (tests/testthat/test-google-batch-iooslxvj.R).

# Whether a Google batch holds a row the row matcher refuses: a body that is
# not raw, a URL or product token that is not a string, or a "bytes"-marked
# URL. evaluate_rows_v1() sends none of these. The batch would refuse them
# too, but in its own order (every URL before any body, every body before any
# token), so match_google_batch_v1() hands such a batch to the row matcher,
# whose first failing row then decides the error, as it always has.
google_batch_refused_v1 <- function(bodies, urls, product_tokens) {
  !all(vapply(bodies, is.raw, logical(1L))) ||
    !is.character(urls) || !is.character(product_tokens) ||
    any(Encoding(urls) == "bytes")
}

# The vendored matcher takes the whole URL and finds the path itself
# (GetPathParamsQuery()), so the target is the whole URL, made into a string
# by the same cpp11 conversion the row matcher's URL goes through: a latin1
# URL arrives as its UTF-8 bytes, and a "bytes"-marked URL fails with the row
# path's error.
google_request_target_v1 <- function(url) {
  robotstxtr_google_request_target_(url)
}

# The native Google batch, with the by-name signature run_batch_matcher_v1()
# calls. Per DISTINCT body, it applies Google's 512,000-byte window and the
# matcher decoding exactly as match_google_v1() does per row, hands the
# decoded strings to one native parse each, and runs the directive collector
# once per body that has a matched row. An empty matched value is restated
# as no line, type "none" and no value, as match_google_v1() restates it
# (design/engine-contract-v1.md). `n_parse_calls` counts the matcher's
# parses, one per distinct body; the collector's parses are not counted.
google_evaluate_batch_v1 <- function(bodies, body_index, product_tokens,
                                     targets) {
  limit <- 512000L
  truncated <- lengths(bodies) > limit
  matcher_bodies <- lapply(seq_along(bodies), function(b) {
    body <- bodies[[b]]
    if (!truncated[[b]]) {
      return(body)
    }
    # One byte past the window says whether the line at its edge is complete.
    lines <- complete_lines_prefix(body[seq_len(limit + 1L)])
    lines[seq_len(min(length(lines), limit))]
  })
  strings <- vapply(matcher_bodies, matcher_string_v1, character(1L))
  body_index <- as.integer(body_index)

  native <- robotstxtr_google_eval_batch_(
    bodies = strings, ids = body_index,
    agents = product_tokens, urls = targets
  )
  allowed <- native$allowed
  line <- native$matching_line
  n <- length(line)
  matched <- line > 0L

  matched_line <- line
  matched_line[!matched] <- NA_integer_
  # A matched row takes its type from the collector below; a disallowed row
  # always has a matched line.
  matched_rule_type <- rep("none", n)
  matched_rule_value <- rep(NA_character_, n)
  matched_rows <- split(which(matched), body_index[matched])
  for (b in names(matched_rows)) {
    rows <- matched_rows[[b]]
    lookup <- collect_directive_lookup(strings[[as.integer(b)]])
    hit <- match(line[rows], lookup$line)
    if (anyNA(hit)) {
      robots_abort(
        sprintf(
          "matched line %d has no collected directive.",
          line[rows][is.na(hit)][[1L]]
        ),
        "robotstxtr_missing_collected_line"
      )
    }
    matched_rule_type[rows] <- lookup$type[hit]
    matched_rule_value[rows] <- lookup$value[hit]
  }
  empty <- matched & !nzchar(matched_rule_value)
  matched_line[empty] <- NA_integer_
  matched_rule_type[empty] <- "none"
  matched_rule_value[empty] <- NA_character_

  list(
    url_decision = allowed,
    matched_line = matched_line,
    matched_rule_type = matched_rule_type,
    matched_rule_value = matched_rule_value,
    matcher_input_bytes = lengths(matcher_bodies)[body_index],
    matcher_body_truncated = truncated[body_index],
    matched_rule_value_raw = vector("list", n),
    n_parse_calls = native$n_parse_calls
  )
}

# Every Google row is evaluated with no error. The reason reads the restated
# line, so an empty Allow stays default_allow.
google_map_native_v1 <- function(native, url_decision) {
  n <- length(url_decision)
  reason <- rep("default_allow", n)
  reason[!is.na(native$matched_line)] <- "rule_allow"
  reason[url_decision == "disallow"] <- "rule_disallow"
  list(
    matcher_status = rep("evaluated", n),
    reason = reason,
    matcher_body_truncated = native$matcher_body_truncated,
    error_stage = rep(NA_character_, n),
    error_class = rep(NA_character_, n),
    error_message = rep(NA_character_, n)
  )
}
