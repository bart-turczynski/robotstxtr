# Versioned, engine-aware robots policy and matcher facade (ROBO-unowhvjx).
#
# The v1 facade deliberately keeps four concepts separate: neutral acquisition
# evidence, an engine status-policy ruleset, a matcher backend, and the robots
# product token used for group selection. The legacy public functions remain
# unchanged; as_legacy_robots_decisions_v1() is the explicit bridge back to
# their Google-oriented result schema.

engine_contract_id_v1 <- function() {
  "robotstxtr.engine-aware/v1"
}

engine_schema_revision_v1 <- function() {
  "2026-07-17.1"
}

engine_rulesets_v1 <- function() {
  c("google", "yandex", "rfc9309", "bing", "assumed_rfc9309")
}

engine_matchers_v1 <- function() {
  c("google", "yandex", "rfc9309", "bing")
}

engine_policy_revisions_v1 <- function() {
  c(
    google = "google-robots-policy-2026-07-17",
    yandex = "yandex-robots-policy-2026-07-17",
    rfc9309 = "rfc9309-policy-2022",
    bing = "bing-documentation-gap-2026-07-17",
    assumed_rfc9309 = "assumed-rfc9309-policy-2026-07-17"
  )
}

engine_matcher_revisions_v1 <- function() {
  matcher_registry_field_v1(validated_matcher_registry_v1(), "revision")
}

engine_matcher_availability_v1 <- function() {
  matcher_registry_field_v1(validated_matcher_registry_v1(), "availability")
}

policy_rows_set_v1 <- function(table, category, ruleset, policy_status,
                               policy_action, policy_reason,
                               policy_provenance, policy_source) {
  selected <- table$category == category & table$ruleset %in% ruleset
  table$policy_status[selected] <- policy_status
  table$policy_action[selected] <- policy_action
  table$policy_reason[selected] <- policy_reason
  table$policy_provenance[selected] <- policy_provenance
  table$policy_source[selected] <- policy_source
  table
}

# The status-policy matrix from design/engine-profiles.md represented as data.
engine_policy_table_v1 <- function() {
  categories <- c(
    "status_200", "status_other_2xx", "status_206", "status_4xx",
    "status_429", "status_5xx", "transport", "redirect_over_budget",
    "protocol_error"
  )
  table <- expand.grid(
    category = categories,
    ruleset = engine_rulesets_v1(),
    stringsAsFactors = FALSE
  )
  table$policy_status <- "documentation_gap"
  table$policy_action <- NA_character_
  table$policy_reason <- "policy_documentation_gap"
  table$policy_provenance <- "documentation_gap"
  table$policy_source <- "design/engine-profiles.md"

  acc <- new.env(parent = emptyenv())
  acc$table <- table

  set <- function(category, ruleset, status, action, reason, provenance,
                  source) {
    acc$table <- policy_rows_set_v1(
      acc$table, category, ruleset, status, action, reason, provenance, source
    )
  }

  set(
    "status_200", c("google", "yandex", "rfc9309"), "evaluated",
    "use_rules", "http_200_use_rules", "documented",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "status_200", "assumed_rfc9309", "evaluated", "use_rules",
    "http_200_use_rules", "application_choice",
    "design/engine-profiles.md#bing-policy"
  )
  set(
    "status_other_2xx", "google", "evaluated", "use_rules",
    "http_2xx_use_rules", "documented",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "status_other_2xx", "yandex", "evaluated", "allow_all",
    "non_200_allow_all", "documented",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "status_206", "google", "evaluated", "use_rules",
    "partial_policy_use_rules", "documented",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "status_206", "yandex", "evaluated", "allow_all",
    "non_200_allow_all", "documented",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "status_4xx", c("rfc9309", "assumed_rfc9309"), "evaluated",
    "allow_all", "http_4xx_allow_all", "application_choice",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "status_4xx", c("google", "yandex"), "evaluated", "allow_all",
    "http_4xx_allow_all", "documented",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "status_429", c("rfc9309", "assumed_rfc9309"), "evaluated",
    "allow_all", "http_429_allow_all", "application_choice",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "status_429", "yandex", "evaluated", "allow_all",
    "non_200_allow_all", "documented",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "status_5xx", c("google", "rfc9309"), "context_required", NA,
    "crawler_lifecycle_context_required", "documented",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "status_5xx", "assumed_rfc9309", "context_required", NA,
    "crawler_lifecycle_context_required", "application_choice",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "status_5xx", "yandex", "evaluated", "allow_all",
    "non_200_allow_all", "documented",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "transport", c("google", "rfc9309"), "context_required", NA,
    "crawler_lifecycle_context_required", "documented",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "transport", "assumed_rfc9309", "context_required", NA,
    "crawler_lifecycle_context_required", "application_choice",
    "design/engine-profiles.md#status-policy"
  )
  set(
    "redirect_over_budget", c("rfc9309", "assumed_rfc9309"),
    "evaluated", "allow_all", "redirect_over_budget_allow_all",
    "application_choice", "design/engine-profiles.md#redirect-handling"
  )
  set(
    "redirect_over_budget", "google", "evaluated", "allow_all",
    "redirect_over_budget_as_404", "documented",
    "design/engine-profiles.md#redirect-handling"
  )
  acc$table
}

#' Inspect the versioned engine-aware robots contract
#'
#' Returns the stable identifiers, value sets, backend capability states,
#' status-policy table, and supported sibling-package ranges for the v1
#' engine-aware contract. It performs no fetch or matching.
#'
#' @return A named list of contract metadata with class
#'   `robots_engine_contract_v1`.
#' @export
robots_engine_contract_v1 <- function() {
  matcher_registry <- validated_matcher_registry_v1()
  structure(
    list(
      contract_id = engine_contract_id_v1(),
      schema_revision = engine_schema_revision_v1(),
      policy_revisions = engine_policy_revisions_v1(),
      matcher_revisions = matcher_registry_field_v1(
        matcher_registry, "revision"
      ),
      matcher_availability = matcher_registry_field_v1(
        matcher_registry, "availability"
      ),
      robots_policy_rulesets = engine_rulesets_v1(),
      matcher_backends = engine_matchers_v1(),
      policy_table = engine_policy_table_v1(),
      sibling_versions = c(
        sitemapr = ">= 0.0.0.9000, < 0.1.0",
        `sitemap-validator` = ">= 1.0.0, < 2.0.0"
      )
    ),
    class = "robots_engine_contract_v1"
  )
}

expand_engine_argument_v1 <- function(x, n, argument, choices) {
  if (!is.character(x)) {
    robots_abort(
      sprintf("`%s` must be a character vector.", argument),
      paste0("robotstxtr_invalid_", argument)
    )
  }
  if (length(x) == 1L) {
    x <- rep(x, length.out = n)
  } else if (length(x) != n) {
    robots_abort(
      sprintf(
        "`%s` must be length 1 or length(url) (%d); got length %d.",
        argument, n, length(x)
      ),
      "robotstxtr_length_mismatch"
    )
  }
  invalid <- is.na(x) | !nzchar(x) | !x %in% choices
  if (any(invalid)) {
    robots_abort(
      sprintf(
        "`%s` must contain only: %s.",
        argument, toString(choices)
      ),
      paste0("robotstxtr_invalid_", argument)
    )
  }
  x
}

expand_product_token_v1 <- function(token, n) {
  if (!is.character(token)) {
    robots_abort(
      "`robots_product_token` must be a character vector.",
      "robotstxtr_invalid_robots_product_token_type"
    )
  }
  if (length(token) == 1L) {
    return(rep(token, length.out = n))
  }
  if (length(token) == n) {
    return(token)
  }
  robots_abort(
    sprintf(
      paste0(
        "`robots_product_token` must be length 1 or length(url) (%d); ",
        "got length %d."
      ),
      n, length(token)
    ),
    "robotstxtr_length_mismatch"
  )
}

text_body_bytes_v1 <- function(robots_txt) {
  if (identical(Encoding(robots_txt), "bytes")) {
    charToRaw(robots_txt)
  } else {
    charToRaw(enc2utf8(robots_txt))
  }
}

matcher_string_v1 <- function(body) {
  out <- rawToChar(body)
  Encoding(out) <- "UTF-8"
  out
}

source_evidence_status_v1 <- function(result) {
  if (!is.na(result$safety_block_reason)) {
    return("safety_refused")
  }
  if (result$termination_reason %in% c("deadline", "ceiling") ||
        identical(result$fetch_outcome, "body_too_large")) {
    return("incomplete")
  }
  terminal <- result$terminal_redirect_reason
  if (identical(terminal, "over_budget")) {
    return("redirect_over_budget")
  }
  if (terminal %in% c("no_location", "loop")) {
    return("http_protocol_error")
  }
  if (identical(result$fetch_outcome, "partial_response")) {
    return("partial")
  }
  if (identical(result$fetch_outcome, "fetched")) {
    return("usable_body")
  }
  if (result$fetch_outcome %in% c("timeout", "tls_error", "network_error")) {
    return("transport_fail")
  }
  status <- result$http_status
  if (!is.na(status) && status >= 100L && status <= 199L) {
    return("http_protocol_error")
  }
  if (!is.na(status) && status >= 400L && status <= 599L) {
    return("http_status")
  }
  "not_applicable"
}

empty_evidence_v1 <- function() {
  out <- data.frame(
    source_id = character(),
    source_kind = character(),
    requested_url = character(),
    effective_url = character(),
    redirect_count = integer(),
    terminal_redirect_reason = character(),
    final_http_status = integer(),
    location_header = character(),
    body_present = logical(),
    observed_bytes = integer(),
    stored_bytes = integer(),
    body_truncated = logical(),
    transport_error_kind = character(),
    safety_block_reason = character(),
    termination_reason = character(),
    evidence_status = character(),
    http_user_agent = character(),
    acquisition_timeout_seconds = numeric(),
    acquisition_max_bytes = integer(),
    redirect_limit = integer(),
    ssrf_guard = logical(),
    https_downgrade_guard = logical(),
    legacy_fetch_outcome = character(),
    legacy_http_status = integer(),
    error_stage = character(),
    error_class = character(),
    error_message = character(),
    stringsAsFactors = FALSE
  )
  out$redirect_hops <- list()
  out$body <- list()
  out
}

source_results_to_evidence_v1 <- function(results, source_ids, requested_url,
                                          fetch_ua, timeout, max_bytes,
                                          ssrf_guard) {
  if (length(results) == 0L) {
    return(empty_evidence_v1())
  }
  out <- data.frame(
    source_id = source_ids,
    source_kind = rep("fetched", length(results)),
    requested_url = requested_url,
    effective_url = vapply(results, `[[`, character(1L), "effective_url"),
    redirect_count = vapply(results, `[[`, integer(1L), "redirect_count"),
    terminal_redirect_reason = vapply(
      results, `[[`, character(1L), "terminal_redirect_reason"
    ),
    final_http_status = vapply(
      results, `[[`, integer(1L), "final_http_status"
    ),
    location_header = vapply(results, `[[`, character(1L), "location_header"),
    body_present = vapply(results, function(x) !is.null(x$body), logical(1L)),
    observed_bytes = vapply(results, `[[`, integer(1L), "observed_bytes"),
    stored_bytes = vapply(results, `[[`, integer(1L), "stored_bytes"),
    body_truncated = vapply(results, `[[`, logical(1L), "body_truncated"),
    transport_error_kind = vapply(
      results, `[[`, character(1L), "transport_error_kind"
    ),
    safety_block_reason = vapply(
      results, `[[`, character(1L), "safety_block_reason"
    ),
    termination_reason = vapply(
      results, `[[`, character(1L), "termination_reason"
    ),
    evidence_status = vapply(
      results, source_evidence_status_v1, character(1L)
    ),
    http_user_agent = rep(fetch_ua, length(results)),
    acquisition_timeout_seconds = rep(timeout, length(results)),
    acquisition_max_bytes = rep(max_bytes, length(results)),
    redirect_limit = rep(5L, length(results)),
    ssrf_guard = rep(ssrf_guard, length(results)),
    https_downgrade_guard = rep(TRUE, length(results)),
    legacy_fetch_outcome = vapply(
      results, `[[`, character(1L), "fetch_outcome"
    ),
    legacy_http_status = vapply(results, `[[`, integer(1L), "http_status"),
    error_stage = vapply(results, `[[`, character(1L), "error_stage"),
    error_class = vapply(results, `[[`, character(1L), "error_class"),
    error_message = vapply(results, `[[`, character(1L), "error_message"),
    stringsAsFactors = FALSE
  )
  out$redirect_hops <- lapply(results, `[[`, "redirect_hops")
  out$body <- lapply(results, `[[`, "body")
  out
}

fetch_evidence_v1 <- function(url, timeout, max_bytes, fetch_ua, ssrf_guard) {
  origin <- vapply(url, robots_origin, character(1L), USE.NAMES = FALSE)
  eligible <- !is.na(origin)
  distinct_origins <- unique(origin[eligible])
  source_ids <- paste0("robots_", seq_along(distinct_origins))
  fetched <- vector("list", length(distinct_origins))
  for (i in seq_along(distinct_origins)) {
    fetched[[i]] <- perform_fetch(
      distinct_origins[[i]], timeout, fetch_ua, max_bytes, ssrf_guard
    )
  }
  evidence <- source_results_to_evidence_v1(
    fetched, source_ids, distinct_origins, fetch_ua, timeout, max_bytes,
    ssrf_guard
  )
  source_index <- match(origin, distinct_origins)
  mapped_source <- rep(NA_character_, length(url))
  if (any(eligible)) {
    mapped_source[eligible] <- source_ids[source_index[eligible]]
  }
  list(source_id = mapped_source, evidence = evidence)
}

supplied_evidence_v1 <- function(raw_body, source_id) {
  out <- data.frame(
    source_id = source_id,
    source_kind = "supplied",
    requested_url = NA_character_,
    effective_url = NA_character_,
    redirect_count = 0L,
    terminal_redirect_reason = "none",
    final_http_status = NA_integer_,
    location_header = NA_character_,
    body_present = TRUE,
    observed_bytes = length(raw_body),
    stored_bytes = length(raw_body),
    body_truncated = FALSE,
    transport_error_kind = NA_character_,
    safety_block_reason = NA_character_,
    termination_reason = "none",
    evidence_status = "usable_body",
    http_user_agent = NA_character_,
    acquisition_timeout_seconds = NA_real_,
    acquisition_max_bytes = NA_integer_,
    redirect_limit = NA_integer_,
    ssrf_guard = NA,
    https_downgrade_guard = NA,
    legacy_fetch_outcome = "supplied",
    legacy_http_status = NA_integer_,
    error_stage = NA_character_,
    error_class = NA_character_,
    error_message = NA_character_,
    stringsAsFactors = FALSE
  )
  out$redirect_hops <- list(list())
  out$body <- list(raw_body)
  out
}

policy_result_v1 <- function(status, action, reason, provenance, source) {
  list(
    policy_status = status,
    policy_action = action,
    policy_reason = reason,
    policy_provenance = provenance,
    policy_source = source
  )
}

resolve_policy_v1 <- function(evidence, ruleset, policy_table) {
  evidence_status <- evidence$evidence_status
  if (identical(evidence_status, "safety_refused")) {
    return(policy_result_v1(
      "not_evaluated", NA_character_, "safety_refused",
      "application_choice", "design/engine-profiles.md#neutral-fetch"
    ))
  }
  if (identical(evidence_status, "incomplete")) {
    return(policy_result_v1(
      "not_evaluated", NA_character_, "incomplete_evidence",
      "application_choice", "design/engine-profiles.md#neutral-fetch"
    ))
  }
  if (identical(evidence_status, "not_applicable")) {
    return(policy_result_v1(
      "not_evaluated", NA_character_, "evidence_not_applicable",
      "application_choice", "design/engine-profiles.md#neutral-fetch"
    ))
  }
  if (evidence$source_kind %in% c("supplied", "local")) {
    return(policy_result_v1(
      "evaluated", "use_rules", "supplied_body_use_rules",
      "application_choice", "design/engine-profiles.md#neutral-fetch"
    ))
  }

  category <- if (identical(evidence_status, "transport_fail")) {
    "transport"
  } else if (identical(evidence_status, "redirect_over_budget")) {
    "redirect_over_budget"
  } else if (identical(evidence_status, "http_protocol_error")) {
    "protocol_error"
  } else if (identical(evidence_status, "partial")) {
    "status_206"
  } else {
    status <- evidence$final_http_status
    if (identical(status, 200L)) {
      "status_200"
    } else if (!is.na(status) && status >= 200L && status <= 299L) {
      "status_other_2xx"
    } else if (identical(status, 429L)) {
      "status_429"
    } else if (!is.na(status) && status >= 400L && status <= 499L) {
      "status_4xx"
    } else if (!is.na(status) && status >= 500L && status <= 599L) {
      "status_5xx"
    } else {
      "protocol_error"
    }
  }
  row <- policy_table[
    policy_table$category == category & policy_table$ruleset == ruleset,
    , drop = FALSE
  ]
  policy <- policy_result_v1(
    row$policy_status[[1L]], row$policy_action[[1L]],
    row$policy_reason[[1L]], row$policy_provenance[[1L]],
    row$policy_source[[1L]]
  )
  if (identical(ruleset, "yandex") &&
        identical(policy$policy_action, "use_rules") &&
        evidence$stored_bytes > 500000L) {
    policy <- policy_result_v1(
      "evaluated", "allow_all", "yandex_file_over_500000_bytes",
      "documented", "design/engine-profiles.md#policy-matcher-limits"
    )
  }
  policy
}

match_google_v1 <- function(body, url, product_token) {
  limit <- 524288L
  truncated <- length(body) > limit
  matcher_body <- if (truncated) body[seq_len(limit)] else body
  body_string <- matcher_string_v1(matcher_body)
  allowed <- robotstxtr_allowed_text_(body_string, url, product_token)[[1L]]
  line <- robotstxtr_matching_line_text_(
    body_string, url, product_token
  )[[1L]]
  matched_line <- if (line > 0L) line else NA_integer_
  matched_rule_type <- if (!allowed) {
    "disallow"
  } else if (line > 0L) {
    "allow"
  } else {
    "none"
  }
  matched_rule_value <- NA_character_
  if (line > 0L) {
    lookup <- collect_directive_lookup(body_string)
    matched <- match(line, lookup$line)
    if (is.na(matched)) {
      robots_abort(
        sprintf("matched line %d has no collected directive.", line),
        "robotstxtr_missing_collected_line"
      )
    }
    matched_rule_type <- lookup$type[[matched]]
    matched_rule_value <- lookup$value[[matched]]
    if (identical(matched_rule_value, "")) {
      matched_line <- NA_integer_
      matched_rule_type <- "none"
      matched_rule_value <- NA_character_
    }
  }
  reason <- if (!allowed) {
    "rule_disallow"
  } else if (!is.na(matched_line)) {
    "rule_allow"
  } else {
    "default_allow"
  }
  list(
    url_decision = if (allowed) "allow" else "disallow",
    reason = reason,
    matched_line = matched_line,
    matched_rule_type = matched_rule_type,
    matched_rule_value = matched_rule_value,
    matcher_input_bytes = length(matcher_body),
    matcher_body_truncated = truncated
  )
}

engine_matcher_registry_v1 <- function() {
  list(
    google = list(
      revision = paste0(
        "google-robotstxt-",
        "22b355ff855419e6a3ff8ff09c0ad7fdb17116f9"
      ),
      availability = "available",
      callable = match_google_v1
    ),
    yandex = list(
      revision = "capability-unavailable-v1",
      availability = "capability_unavailable",
      callable = NULL
    ),
    rfc9309 = list(
      revision = "capability-unavailable-v1",
      availability = "capability_unavailable",
      callable = NULL
    ),
    bing = list(
      revision = "capability-unavailable-v1",
      availability = "capability_unavailable",
      callable = NULL
    )
  )
}

matcher_registry_abort_v1 <- function(detail) {
  robots_abort(
    sprintf("Matcher registry invariant failed: %s", detail),
    "robotstxtr_matcher_registry_invariant"
  )
}

validate_matcher_registry_v1 <- function(registry) {
  expected_backends <- engine_matchers_v1()
  if (!is.list(registry) ||
        !identical(names(registry), expected_backends)) {
    matcher_registry_abort_v1(sprintf(
      "registry names must be exactly: %s.", toString(expected_backends)
    ))
  }

  expected_fields <- c("revision", "availability", "callable")
  for (backend in expected_backends) {
    entry <- registry[[backend]]
    if (!is.list(entry) || !identical(names(entry), expected_fields)) {
      matcher_registry_abort_v1(sprintf(
        "backend `%s` must define revision, availability, and callable.",
        backend
      ))
    }

    revision <- entry$revision
    if (!is.character(revision) || length(revision) != 1L ||
          is.na(revision) || !nzchar(revision)) {
      matcher_registry_abort_v1(sprintf(
        "backend `%s` must have one non-empty revision.", backend
      ))
    }

    availability <- entry$availability
    if (!is.character(availability) || length(availability) != 1L ||
          is.na(availability) ||
          !availability %in% c("available", "capability_unavailable")) {
      matcher_registry_abort_v1(sprintf(
        "backend `%s` has an invalid availability state.", backend
      ))
    }

    registered <- is.function(entry$callable)
    if (identical(availability, "available") && !registered) {
      matcher_registry_abort_v1(sprintf(
        "available backend `%s` must have a registered callable.", backend
      ))
    }
    if (identical(availability, "capability_unavailable") && registered) {
      matcher_registry_abort_v1(sprintf(
        "unavailable backend `%s` must not have a registered callable.",
        backend
      ))
    }

    unavailable_revision <- identical(
      revision, "capability-unavailable-v1"
    )
    if (!identical(
      unavailable_revision,
      identical(availability, "capability_unavailable")
    )) {
      matcher_registry_abort_v1(sprintf(
        "backend `%s` revision and availability disagree.", backend
      ))
    }
  }
  registry
}

validated_matcher_registry_v1 <- function() {
  validate_matcher_registry_v1(engine_matcher_registry_v1())
}

matcher_registry_field_v1 <- function(registry, field) {
  vapply(registry, `[[`, character(1L), field)
}

match_backend_v1 <- function(backend, body, url, product_token,
                             registry = engine_matcher_registry_v1()) {
  registry <- validate_matcher_registry_v1(registry)
  if (!is.character(backend) || length(backend) != 1L ||
        is.na(backend) || !nzchar(backend) || !backend %in% names(registry)) {
    robots_abort(
      "Matcher backend is unavailable or unregistered.",
      "robotstxtr_matcher_backend_unavailable"
    )
  }
  entry <- registry[[backend]]
  if (!identical(entry$availability, "available") ||
        !is.function(entry$callable)) {
    robots_abort(
      sprintf("Matcher backend `%s` is unavailable or unregistered.", backend),
      "robotstxtr_matcher_backend_unavailable"
    )
  }
  entry$callable(body, url, product_token)
}

policy_limit_v1 <- function(ruleset) {
  out <- rep(NA_integer_, length(ruleset))
  out[ruleset == "google"] <- 524288L
  out[ruleset == "yandex"] <- 500000L
  out
}

new_engine_decisions_v1 <- function(results, evidence) {
  structure(
    list(
      results = results,
      evidence = evidence,
      contract = robots_engine_contract_v1()
    ),
    class = "robots_engine_decisions_v1",
    contract_id = engine_contract_id_v1(),
    schema_revision = engine_schema_revision_v1(),
    package_version = as.character(getNamespaceVersion("robotstxtr"))
  )
}

evaluate_rows_v1 <- function(url, product_token, ruleset, matcher_backend,
                             source_id, evidence, url_valid, token_valid,
                             fetch_ua, timeout, max_bytes, ssrf_guard) {
  n <- length(url)
  policy_revisions <- engine_policy_revisions_v1()
  matcher_registry <- validated_matcher_registry_v1()
  matcher_revisions <- matcher_registry_field_v1(
    matcher_registry, "revision"
  )
  matcher_availability <- matcher_registry_field_v1(
    matcher_registry, "availability"
  )
  policy_table <- engine_policy_table_v1()

  evidence_status <- rep("not_applicable", n)
  policy_status <- rep("not_evaluated", n)
  policy_action <- rep(NA_character_, n)
  policy_reason <- rep("input_invalid", n)
  policy_provenance <- rep("application_choice", n)
  policy_source <- rep("design/engine-profiles.md#neutral-fetch", n)
  matcher_status <- rep("not_evaluated", n)
  url_decision <- rep(NA_character_, n)
  reason <- rep("input_invalid", n)
  matched_line <- rep(NA_integer_, n)
  matched_rule_type <- rep("unknown", n)
  matched_rule_value <- rep(NA_character_, n)
  matcher_input_bytes <- rep(NA_integer_, n)
  matcher_body_truncated <- rep(NA, n)
  error_stage <- ifelse(url_valid, "input", "origin")
  error_class <- ifelse(
    url_valid, "robots_invalid_product_token", "robots_invalid_url"
  )
  error_message <- ifelse(
    url_valid,
    "Robots product token is missing or empty.",
    "URL is missing, empty, malformed, or not HTTP(S)."
  )

  valid <- url_valid & token_valid
  for (i in which(valid)) {
    evidence_index <- match(source_id[[i]], evidence$source_id)
    ev <- lapply(evidence, function(column) column[[evidence_index]])
    evidence_status[[i]] <- ev$evidence_status
    policy <- resolve_policy_v1(ev, ruleset[[i]], policy_table)
    policy_status[[i]] <- policy$policy_status
    policy_action[[i]] <- policy$policy_action
    policy_reason[[i]] <- policy$policy_reason
    policy_provenance[[i]] <- policy$policy_provenance
    policy_source[[i]] <- policy$policy_source
    error_stage[[i]] <- ev$error_stage
    error_class[[i]] <- ev$error_class
    error_message[[i]] <- ev$error_message

    if (!identical(policy$policy_status, "evaluated")) {
      reason[[i]] <- policy$policy_reason
      next
    }
    if (identical(policy$policy_action, "allow_all")) {
      matcher_status[[i]] <- "not_needed"
      url_decision[[i]] <- "allow"
      reason[[i]] <- "policy_allow_all"
      matched_rule_type[[i]] <- "none"
      next
    }
    if (identical(ev$evidence_status, "partial")) {
      reason[[i]] <- "partial_evidence"
      next
    }
    availability <- matcher_availability[[matcher_backend[[i]]]]
    if (!identical(availability, "available")) {
      matcher_status[[i]] <- "capability_unavailable"
      reason[[i]] <- "matcher_capability_unavailable"
      next
    }
    matched <- match_backend_v1(
      matcher_backend[[i]], ev$body, url[[i]], product_token[[i]],
      matcher_registry
    )
    matcher_status[[i]] <- "evaluated"
    url_decision[[i]] <- matched$url_decision
    reason[[i]] <- matched$reason
    matched_line[[i]] <- matched$matched_line
    matched_rule_type[[i]] <- matched$matched_rule_type
    matched_rule_value[[i]] <- matched$matched_rule_value
    matcher_input_bytes[[i]] <- matched$matcher_input_bytes
    matcher_body_truncated[[i]] <- matched$matcher_body_truncated
  }

  data.frame(
    input_id = seq_len(n),
    url = url,
    robots_product_token = product_token,
    robots_policy_ruleset = ruleset,
    policy_ruleset_revision = unname(policy_revisions[ruleset]),
    matcher_backend = matcher_backend,
    matcher_backend_revision = unname(matcher_revisions[matcher_backend]),
    matcher_availability = unname(matcher_availability[matcher_backend]),
    http_user_agent = rep(fetch_ua, length.out = n),
    acquisition_timeout_seconds = rep(timeout, length.out = n),
    acquisition_max_bytes = rep(max_bytes, length.out = n),
    redirect_limit = rep(if (is.na(timeout)) NA_integer_ else 5L,
                         length.out = n),
    ssrf_guard = rep(ssrf_guard, length.out = n),
    https_downgrade_guard = rep(if (is.na(timeout)) NA else TRUE,
                                length.out = n),
    policy_body_limit_bytes = policy_limit_v1(ruleset),
    source_id = source_id,
    evidence_status = evidence_status,
    policy_status = policy_status,
    policy_action = policy_action,
    policy_reason = policy_reason,
    policy_provenance = policy_provenance,
    policy_source = policy_source,
    matcher_status = matcher_status,
    url_decision = url_decision,
    reason = reason,
    matched_line = matched_line,
    matched_rule_type = matched_rule_type,
    matched_rule_value = matched_rule_value,
    matcher_input_bytes = matcher_input_bytes,
    matcher_body_truncated = matcher_body_truncated,
    error_stage = error_stage,
    error_class = error_class,
    error_message = error_message,
    stringsAsFactors = FALSE
  )
}

#' Evaluate URLs against supplied robots.txt under an explicit engine profile
#'
#' Versioned, no-network entry point for the engine-aware v1 contract. The
#' robots status-policy ruleset and matcher backend are selected independently;
#' an unavailable backend produces `matcher_status = "capability_unavailable"`
#' rather than silently using Google's matcher.
#'
#' @param robots_txt A single, non-missing character value containing the
#'   robots.txt body.
#' @param url A character vector of URLs to evaluate.
#' @param robots_product_token A character vector of length one or
#'   `length(url)` used only for robots user-agent group selection.
#' @param robots_policy_ruleset An explicit ruleset, length one or
#'   `length(url)`: `"google"`, `"yandex"`, `"rfc9309"`, `"bing"`, or
#'   `"assumed_rfc9309"`.
#' @param matcher_backend An explicit matcher backend, length one or
#'   `length(url)`: `"google"`, `"yandex"`, `"rfc9309"`, or `"bing"`.
#' @param source_id A non-empty identifier for the supplied body.
#'
#' @return A `robots_engine_decisions_v1` object with `results`, neutral
#'   `evidence`, and `contract` components.
#' @export
robots_evaluate_text_v1 <- function(robots_txt, url, robots_product_token,
                                    robots_policy_ruleset, matcher_backend,
                                    source_id = "supplied") {
  validate_robots_txt(robots_txt)
  validate_source_id(source_id)
  validate_url_type(url)
  n <- length(url)
  token <- expand_product_token_v1(robots_product_token, n)
  ruleset <- expand_engine_argument_v1(
    robots_policy_ruleset, n, "robots_policy_ruleset", engine_rulesets_v1()
  )
  backend <- expand_engine_argument_v1(
    matcher_backend, n, "matcher_backend", engine_matchers_v1()
  )
  raw_body <- text_body_bytes_v1(robots_txt)
  evidence <- supplied_evidence_v1(raw_body, source_id)
  url_valid <- !is.na(url) & nzchar(url)
  token_valid <- !is.na(token) & nzchar(token)
  mapped_source <- ifelse(url_valid & token_valid, source_id, NA_character_)
  results <- evaluate_rows_v1(
    url, token, ruleset, backend, mapped_source, evidence, url_valid,
    token_valid, NA_character_, NA_real_, NA_integer_, NA
  )
  new_engine_decisions_v1(results, evidence)
}

#' Fetch and evaluate robots.txt under an explicit engine profile
#'
#' Versioned URL-first entry point for the engine-aware v1 contract. It records
#' neutral acquisition and safety evidence before applying the explicitly
#' selected policy ruleset and matcher backend. `fetch_user_agent` is the HTTP
#' request User-Agent and is never used as `robots_product_token`.
#'
#' @inheritParams robots_evaluate_text_v1
#' @inheritParams robots_fetch
#'
#' @return A `robots_engine_decisions_v1` object with `results`, neutral
#'   `evidence`, and `contract` components.
#' @export
robots_evaluate_url_v1 <- function(url, robots_product_token,
# nolint start: object_length_linter
                                   robots_policy_ruleset, matcher_backend,
# nolint end
                                   timeout = 10, max_bytes = 524288L,
                                   fetch_user_agent = NULL,
                                   ssrf_guard = TRUE) {
  validate_url_type(url)
  timeout <- validate_timeout(timeout)
  max_bytes <- validate_max_bytes(max_bytes)
  validate_fetch_user_agent(fetch_user_agent)
  validate_ssrf_guard(ssrf_guard)
  n <- length(url)
  token <- expand_product_token_v1(robots_product_token, n)
  ruleset <- expand_engine_argument_v1(
    robots_policy_ruleset, n, "robots_policy_ruleset", engine_rulesets_v1()
  )
  backend <- expand_engine_argument_v1(
    matcher_backend, n, "matcher_backend", engine_matchers_v1()
  )
  fetch_ua <- if (is.null(fetch_user_agent)) {
    package_fetch_user_agent()
  } else {
    fetch_user_agent
  }
  origin <- vapply(url, robots_origin, character(1L), USE.NAMES = FALSE)
  url_valid <- !is.na(origin)
  token_valid <- !is.na(token) & nzchar(token)
  fetch_input <- url
  fetch_input[!token_valid] <- NA_character_
  fetched <- fetch_evidence_v1(
    fetch_input, timeout, max_bytes, fetch_ua, ssrf_guard
  )
  results <- evaluate_rows_v1(
    url, token, ruleset, backend, fetched$source_id, fetched$evidence,
    url_valid, token_valid, fetch_ua, timeout, max_bytes, ssrf_guard
  )
  new_engine_decisions_v1(results, fetched$evidence)
}

#' Convert a v1 Google engine result to the legacy decision schema
#'
#' Explicit compatibility adapter for callers that still consume the original
#' `robots_decisions` schema. It accepts only results whose ruleset and matcher
#' backend are both `"google"`; unsupported legacy fetch outcomes remain
#' unknown exactly as in the original API.
#'
#' @param x A `robots_engine_decisions_v1` object using the Google policy and
#'   Google matcher backend for every row.
#'
#' @return A legacy `robots_decisions` object.
#' @export
as_legacy_robots_decisions_v1 <- function(x) {
  if (!inherits(x, "robots_engine_decisions_v1")) {
    robots_abort(
      "`x` must be a `robots_engine_decisions_v1` object.",
      "robotstxtr_invalid_engine_result"
    )
  }
  result <- x$results
  if (any(result$robots_policy_ruleset != "google") ||
        any(result$matcher_backend != "google")) {
    robots_abort(
      "The legacy adapter requires the Google policy and matcher backend.",
      "robotstxtr_incompatible_legacy_adapter"
    )
  }
  evidence_index <- match(result$source_id, x$evidence$source_id)
  final_status <- x$evidence$final_http_status[evidence_index]
  legacy_status <- x$evidence$legacy_http_status[evidence_index]
  source_kind <- x$evidence$source_kind[evidence_index]
  matched <- result$matcher_status == "evaluated"
  missing <- !is.na(final_status) & final_status %in% c(404L, 410L)
  supplied <- !is.na(source_kind) & source_kind == "supplied"
  input_invalid <- result$reason == "input_invalid"
  allowed <- rep(NA, nrow(result))
  allowed[matched] <- result$url_decision[matched] == "allow"
  allowed[missing] <- TRUE
  decision_source <- rep("fetch_unknown", nrow(result))
  decision_source[matched] <- result$reason[matched]
  decision_source[missing] <- "missing_allow"
  decision_source[input_invalid] <- "input_unknown"
  decision_source[supplied & !matched] <- "fetch_unknown"
  matched_rule_type <- result$matched_rule_type
  matched_rule_type[!matched] <- "unknown"
  matched_line <- result$matched_line
  matched_line[!matched] <- NA_integer_
  matched_rule_value <- result$matched_rule_value
  matched_rule_value[!matched] <- NA_character_
  fetch_outcome <- rep("input_invalid", nrow(result))
  has_source <- !is.na(evidence_index)
  fetch_outcome[has_source] <- x$evidence$legacy_fetch_outcome[
    evidence_index[has_source]
  ]
  robots_url <- rep(NA_character_, nrow(result))
  http_status <- rep(NA_integer_, nrow(result))
  robots_url[has_source] <- x$evidence$requested_url[evidence_index[has_source]]
  http_status[has_source] <- legacy_status[has_source]
  results <- data.frame(
    input_id = result$input_id,
    url = result$url,
    user_agent = result$robots_product_token,
    allowed = allowed,
    decision_source = decision_source,
    source_id = result$source_id,
    robots_url = robots_url,
    http_status = http_status,
    fetch_outcome = fetch_outcome,
    error_stage = result$error_stage,
    error_class = result$error_class,
    error_message = result$error_message,
    matched_line = matched_line,
    matched_rule_type = matched_rule_type,
    matched_rule_value = matched_rule_value,
    stringsAsFactors = FALSE
  )
  evidence <- x$evidence
  body_size <- ifelse(evidence$body_present, evidence$stored_bytes, NA_integer_)
  robots <- data.frame(
    source_id = evidence$source_id,
    source_type = evidence$source_kind,
    robots_url = evidence$requested_url,
    effective_url = evidence$effective_url,
    http_status = evidence$legacy_http_status,
    fetch_outcome = evidence$legacy_fetch_outcome,
    redirect_count = evidence$redirect_count,
    body_size = body_size,
    timeout = evidence$acquisition_timeout_seconds,
    max_bytes = evidence$acquisition_max_bytes,
    error_stage = evidence$error_stage,
    error_class = evidence$error_class,
    error_message = evidence$error_message,
    stringsAsFactors = FALSE
  )
  robots$body <- evidence$body
  new_robots_decisions(results, robots)
}

#' @export
print.robots_engine_decisions_v1 <- function(x, ...) {
  result <- x$results
  cat(sprintf(
    "<robots_engine_decisions_v1 [%s]>: %d result%s, %d evidence source%s\n",
    attr(x, "schema_revision"), nrow(result),
    if (nrow(result) == 1L) "" else "s", nrow(x$evidence),
    if (nrow(x$evidence) == 1L) "" else "s"
  ))
  if (nrow(result) > 0L) {
    preview <- result[
      seq_len(min(10L, nrow(result))),
      c(
        "input_id", "url", "robots_policy_ruleset", "matcher_backend",
        "policy_status", "matcher_status", "url_decision", "reason"
      ),
      drop = FALSE
    ]
    print(preview, row.names = FALSE)
  }
  invisible(x)
}
