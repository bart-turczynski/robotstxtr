# Engine-aware Yandex matcher adapter (ROBO-agrvzdnr, YI4c; registered by
# YI5).
#
# `match_yandex_v1()` maps the checked robotstxtyandex native batch binding
# (YI4b, R/yandex-checked-batch.R) onto the host per-row result shape, applying
# the normative §10/§11 status/reason/error and exact-byte raw-value mappings of
# design/robotstxtyandex-integration-v1-spec.md. It is the callable
# engine_matcher_registry_v1() registers for the `yandex` backend.
#
# BATCH SHAPE. Every matcher adapter has the one batch interface
# `callable(bodies, urls, product_tokens)` -> a decision frame
# (ROBO-bukqpjli): evaluate_rows_v1() calls it once with every `yandex` row.
# YI4b's hard mandate is parse-once per DISTINCT body:
# yandex_evaluate_checked_batch() parses each distinct body exactly once and
# evaluates all rows that select it in a single native call. The batching
# (recycling, target bytes, distinct-body grouping, frame assembly) is the
# shared module in R/matcher-batch-v1.R (ROBO-iwmtdutk); the extractor, the
# native call and the status mapping below are Yandex's own.

# Map the checked native columns onto §10/§11 matcher_status, reason and the
# error columns. For evaluated rows the four native DecisionSource names are
# byte-identical to the four required §10 reasons (default_allow / rule_allow /
# rule_disallow / effective_empty_disallow); non-evaluated rows are mapped.
yandex_map_native_v1 <- function(native, url_decision) {
  n <- length(url_decision)
  status <- native$native_evaluation_status
  evaluated <- status == "evaluated"
  unsupported <- status == "unsupported_crawler"
  invalid_target <- status == "invalid_request_target"

  reason <- rep(NA_character_, n)
  reason[evaluated] <- native$decision_source[evaluated]
  reason[unsupported] <- "unsupported_product_token"
  reason[invalid_target] <- "invalid_request_target"

  error_stage <- rep(NA_character_, n)
  error_class <- rep(NA_character_, n)
  error_message <- rep(NA_character_, n)
  error_stage[unsupported | invalid_target] <- "input"
  error_class[unsupported] <- "robots_unsupported_product_token"
  error_class[invalid_target] <- "robots_invalid_request_target"
  error_message[unsupported] <- sprintf(
    paste0(
      "Robots product token is not supported by the Yandex matcher backend. ",
      "Accepted selectors: %s. Resolve the token before evaluating with ",
      "robots_resolve_matcher_profile_v1()."
    ),
    accepted_selectors_phrase_v1("yandex")
  )
  error_message[invalid_target] <-
    "A request target could not be derived from the URL."

  # §10: matcher_body_truncated is FALSE for any non-evaluated row. Evaluated
  # rows carry the native per-body flag (FALSE in practice under §12 policy).
  matcher_body_truncated <- native$matcher_body_truncated
  matcher_body_truncated[!evaluated] <- FALSE

  list(
    matcher_status = ifelse(evaluated, "evaluated", "not_evaluated"),
    reason = reason,
    matcher_body_truncated = matcher_body_truncated,
    error_stage = error_stage,
    error_class = error_class,
    error_message = error_message
  )
}

#' Map checked Yandex native results onto the host per-row result shape
#'
#' Package-private engine-aware adapter (YI4c), registered for the `yandex`
#' backend and called once per evaluation with every `yandex` row
#' (ROBO-bukqpjli). It runs the YI4a request-target extractor per row, groups
#' rows by distinct body, evaluates them through the checked robotstxtyandex
#' batch binding (parse-once per distinct body), and maps native columns to the
#' normative §10/§11 status, reason, error, and exact-byte raw-value contract.
#'
#' @param bodies A list of raw vectors, one per row -- the use_rules robots body
#'   for that row (bytes verbatim). Deduped internally for parse-once batching.
#' @param urls A character vector of absolute HTTP(S) URLs, one per row (or a
#'   single value recycled).
#' @param product_tokens A character vector of robots product tokens, one per
#'   row (or a single value recycled). Passed through to the engine's
#'   EvaluateChecked; the supported-token boundary is the engine's behavior, not
#'   an adapter allowlist.
#'
#' @return A data.frame with one row per input carrying
#'   `native_evaluation_status`, `matcher_status`, `url_decision`, `reason`,
#'   `matched_line`, `matched_rule_type`, `matched_rule_value`, the
#'   `matched_rule_value_raw` list column (exact bytes / `raw(0)` / `NULL`),
#'   `matcher_input_bytes`, `matcher_body_truncated`, and `error_stage` /
#'   `error_class` / `error_message`. The distinct-body parse count is attached
#'   as the `n_parse_calls` attribute.
#' @keywords internal
#' @noRd
match_yandex_v1 <- function(bodies, urls, product_tokens) {
  run_batch_matcher_v1(
    bodies, urls, product_tokens,
    bodies_class = "robotstxtr_invalid_yandex_bodies",
    extract_target = robotstxtr_extract_request_target_,
    native_eval = yandex_evaluate_checked_batch,
    map_status = yandex_map_native_v1,
    native_columns = "native_evaluation_status"
  )
}
