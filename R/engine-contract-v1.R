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

# 2026-11-08.1: every fetching entry point takes `safety_level`; the contract
# publishes its value set (`safety_levels`) and the evidence gains
# `safety_level` and `fetch_allow_ranges` (ADR 0001 sections 1 and 8,
# ROBO-pezlychx). Both facades share the evidence schema, so both moved.
#
# 2026-11-05.1: the evidence `safety_block_reason` set gains "userinfo",
# "port", "parse", "multicast" and "reserved", the refusals ssrfr adds
# (ROBO-jbralthm; design/engine-profiles.md section 2). Both facades share the
# evidence schema, so both revisions moved.
engine_schema_revision_v1 <- function() {
  "2026-11-08.1"
}

# The engine-aware/v2 facade identity (BI-V2-SCHEMA, spec SS15). Introduced by
# the atomic Bing activation, it supersedes the v1 facade for Bing while leaving
# the v1 accessor's contract_id and schema_revision byte-unchanged at the time
# (spec SS16.5 preserved the Yandex schema-2026-07-18.2 guarantees across that
# activation; the freeze was scoped to it, not permanent). The v2 surface is
# published through robots_engine_contract_v2(); the shared registry and status
# vocabulary are the same objects both accessors read.
engine_contract_id_v2 <- function() {
  "robotstxtr.engine-aware/v2"
}

engine_schema_revision_v2 <- function() {
  "2026-11-08.1"
}

engine_rulesets_v1 <- function() {
  c("google", "yandex", "rfc9309", "bing", "assumed_rfc9309")
}

engine_matchers_v1 <- function() {
  c("google", "yandex", "rfc9309", "bing")
}

# The `safety_level` value set (ADR 0001 section 1). It decides what the fetch
# may do, never what an outcome means, and is independent of the ruleset.
# "strict", the default, is today's acquisition. "crawler" is published but not
# available yet: validate_safety_level() refuses it until it lands
# (ROBO-lwdxzdhw).
engine_safety_levels_v1 <- function() {
  c("strict", "crawler")
}

engine_available_safety_levels_v1 <- function() {
  "strict"
}

# Authoritative enumeration of the robotstxtr.engine-aware/v2 matcher-status set
# (spec design/robotstxtbing-integration-v2-spec.md decision BI-V2-SCHEMA, SS10,
# SS15). The v2 schema extends v1's four-value vocabulary with the four Bing
# outcomes v1 cannot losslessly carry: `invalid_request_target`,
# `unsupported_profile`, `matcher_input_limit_exceeded` (the four parse limits
# plus request-target-limit fold in here, distinguished by `reason`), and
# `matcher_work_limit_exceeded`. Ordering is fixed and MUST NOT change: the four
# v1 statuses first, then the four v2 additions. This is the single source of
# truth for the status vocabulary; the live guard below enforces it, and the
# atomic v2 activation (slice BI5) publishes it. No non-evaluated status may
# ever be represented as an allow/disallow decision.
engine_matcher_status_set_v2 <- function() {
  c(
    "evaluated", "not_needed", "not_evaluated", "capability_unavailable",
    "invalid_request_target", "unsupported_profile",
    "matcher_input_limit_exceeded", "matcher_work_limit_exceeded"
  )
}

# Fail-closed guard: every emitted matcher_status MUST be a v2-set member.
# evaluate_rows_v1() runs this over the fully assembled status vector before it
# reaches any result row, so no backend can surface a status outside the
# published vocabulary. Returns the input unchanged on success.
validate_matcher_status_v2 <- function(matcher_status) {
  allowed <- engine_matcher_status_set_v2()
  invalid <- is.na(matcher_status) | !matcher_status %in% allowed
  if (any(invalid)) {
    robots_abort(
      sprintf(
        "Matcher status outside the engine-aware/v2 set: %s.",
        toString(unique(matcher_status[invalid]))
      ),
      "robotstxtr_matcher_status_invariant"
    )
  }
  matcher_status
}

engine_policy_revisions_v1 <- function() {
  c(
    google = "google-robots-policy-2026-11-09",
    yandex = "yandex-robots-policy-2026-11-09",
    rfc9309 = "rfc9309-policy-2022",
    bing = "bing-documentation-gap-2026-07-17",
    assumed_rfc9309 = "assumed-rfc9309-policy-2026-07-17"
  )
}

engine_matcher_availability_v1 <- function() {
  matcher_registry_field_v1(validated_matcher_registry_v1(), "availability")
}

# The accepted matcher-profile selectors for one `bounded_profiles` backend.
#
# A `bounded_profiles` backend accepts a closed, tiny set of tokens and rejects
# everything else. Publishing only the membership of that set would be
# misleading, because the accepted tokens within one backend do NOT behave
# alike: each row's `group_selection` says whether the profile falls back to a
# wildcard group when no group names it.
#
#   exact_else_wildcard  Merge every group naming this token exactly; only if
#                        no such group exists, merge the `User-agent: *`
#                        groups. (`Yandex`, `bingbot`)
#   exact_only           Merge every group naming this token exactly, and never
#                        fall back to a wildcard group. A robots.txt with only
#                        `User-agent: *` therefore constrains this profile not
#                        at all. (`YandexAdditionalBot`, `adidxbot`)
#
# The pattern is vendor-neutral rather than a Yandex quirk: the Yandex
# "Additional" family and Bing's AdIdxBot both behave this way, in the vendored
# cores (robotstxtyandex crawler_selector.cc, robotstxtbing selection.h) as in
# vendor documentation.
#
# `accepted_token` is the canonical spelling. Comparison is ASCII
# case-insensitive and exact -- no trimming, prefix or suffix matching, and no
# aliases -- as published by `product_token_comparison`.
supported_profiles_row_v1 <- function(profile_id, accepted_token,
                                      group_selection, profile_revision) {
  data.frame(
    profile_id = profile_id,
    accepted_token = accepted_token,
    group_label = accepted_token,
    group_selection = group_selection,
    profile_revision = profile_revision,
    stringsAsFactors = FALSE
  )
}

# The published selection modes. Any row outside this set is a build error.
supported_profile_selection_modes_v1 <- function() {
  c("exact_else_wildcard", "exact_only")
}

# Yandex accepts exactly the umbrella group label and the Additional crawler.
# Both come from the single vendored profile library, so both rows carry that
# library's profile id as their revision -- read from the frozen identity, never
# restated as a literal here.
yandex_supported_profiles_v1 <- function() {
  revision <- yandex_matcher_identity_v1()$profile_id
  supported_profiles_row_v1(
    profile_id = c("yandex", "yandex_additional_bot"),
    accepted_token = c("Yandex", "YandexAdditionalBot"),
    group_selection = c("exact_else_wildcard", "exact_only"),
    profile_revision = c(revision, revision)
  )
}

# Bing accepts exactly `bingbot` and `adidxbot` (robotstxtbing policy.cpp
# is_supported_profile_token). Each has its own frozen profile revision.
bing_supported_profiles_v1 <- function() {
  id <- bing_matcher_identity_v1()
  supported_profiles_row_v1(
    profile_id = c("bingbot", "adidxbot"),
    accepted_token = c("bingbot", "adidxbot"),
    group_selection = c("exact_else_wildcard", "exact_only"),
    profile_revision = c(
      id$bingbot_profile_revision, id$adidxbot_profile_revision
    )
  )
}

# Build-time invariant over the published capability object. Keeps the two
# axes from drifting apart: a bounded backend must publish a profile table and
# an unbounded one must not, and every published selection mode must be one the
# contract defines. A violation is a package bug, not user input, so it aborts.
validate_backend_capability_v1 <- function(capability) {
  modes <- supported_profile_selection_modes_v1()
  profile_fields <- c(
    "product_token_role", "product_token_comparison", "supported_profiles"
  )

  for (backend in names(capability)) {
    entry <- capability[[backend]]
    bounded <- identical(entry$token_policy, "bounded_profiles")
    present <- profile_fields %in% names(entry)

    if (bounded && !all(present)) {
      capability_abort_v1(sprintf(
        "backend %s is bounded_profiles but omits: %s.",
        backend, toString(profile_fields[!present])
      ))
    }
    if (!bounded && any(present)) {
      capability_abort_v1(sprintf(
        "backend %s is not bounded_profiles but publishes: %s.",
        backend, toString(profile_fields[present])
      ))
    }
    if (!bounded) next

    profiles <- entry$supported_profiles
    if (!is.data.frame(profiles) || nrow(profiles) == 0L) {
      capability_abort_v1(sprintf(
        "backend %s must publish a non-empty supported_profiles frame.", backend
      ))
    }
    expected_cols <- c(
      "profile_id", "accepted_token", "group_label", "group_selection",
      "profile_revision"
    )
    if (!identical(names(profiles), expected_cols)) {
      capability_abort_v1(sprintf(
        "backend %s supported_profiles columns must be exactly: %s.",
        backend, toString(expected_cols)
      ))
    }
    bad_mode <- !profiles$group_selection %in% modes
    if (any(bad_mode)) {
      capability_abort_v1(sprintf(
        "backend %s publishes unknown group_selection: %s.",
        backend, toString(unique(profiles$group_selection[bad_mode]))
      ))
    }
    if (anyDuplicated(ascii_lower(profiles$accepted_token)) > 0L) {
      capability_abort_v1(sprintf(
        "backend %s publishes case-duplicate accepted_token values.", backend
      ))
    }
    if (any(is.na(profiles$profile_revision) |
              !nzchar(profiles$profile_revision))) {
      capability_abort_v1(sprintf(
        "backend %s publishes an empty profile_revision.", backend
      ))
    }
  }

  capability
}

capability_abort_v1 <- function(detail) {
  robots_abort(
    sprintf("Matcher capability invariant failed: %s", detail),
    "robotstxtr_matcher_capability_invariant"
  )
}

# The capability boundary between a matcher backend's owned vendor SEMANTICS and
# the robots product TOKEN used for user-agent group selection. Keyed like
# engine_matcher_registry_v1(). This is descriptive metadata only: it changes no
# matching behavior. `token_policy` is `"arbitrary_valid"` for Google (accepts
# any valid Google robots product token), `"bounded_profiles"` for the
# vendor-bounded backends, and `"rfc9309"` for the RFC backend.
# `matcher_semantics` names the sole vendor/semantics a backend owns; a Google
# decision on any token reflects Google parsing/matching, never a prediction of
# the crawler the token names.
#
# The two `bounded_profiles` backends additionally publish which selectors they
# accept, because passing an unaccepted one is not an error a caller can miss
# cheaply: on `yandex` it yields matcher_status `not_evaluated` with reason
# `unsupported_product_token`, which reads like a transport failure rather than
# a configuration mistake. `product_token_role` names what the token IS -- a
# robots.txt group selector, not an HTTP User-Agent crawler identity --
# `product_token_comparison` fixes how it is compared, and
# `supported_profiles` carries the accepted rows with their group-selection
# behavior. Backends whose `token_policy` is `arbitrary_valid` or `rfc9309`
# publish none of the three: the set is not closed, so there is nothing to
# enumerate. A `capability_unavailable` backend still publishes its capability
# entry; `rfc9309` is unavailable AND unbounded, so it publishes no profile
# table for the second reason, not the first.
engine_backend_capability_v1 <- function() {
  list(
    google = list(
      token_policy = "arbitrary_valid",
      matcher_semantics = "google",
      note = paste0(
        "Google backend accepts any valid Google robots product token for ",
        "user-agent group selection; the result reflects Google ",
        "parsing/matching semantics applied to that token, not behavioral ",
        "compatibility with or a prediction of the crawler the token names."
      )
    ),
    yandex = list(
      token_policy = "bounded_profiles",
      matcher_semantics = "yandex",
      note = paste0(
        "Yandex backend is bounded to its supported Yandex vendor profiles ",
        "only (profile yandex-0.1.0); it never generalizes to arbitrary ",
        "tokens and is not backed by Google matching."
      ),
      product_token_role = "matcher_profile_selector",
      product_token_comparison = "ascii_case_insensitive_exact",
      supported_profiles = yandex_supported_profiles_v1()
    ),
    bing = list(
      token_policy = "bounded_profiles",
      matcher_semantics = "bing",
      note = paste0(
        "Bing backend is bounded to its supported Bing vendor profiles only; ",
        "it never generalizes to arbitrary tokens and is not backed by Google ",
        "matching."
      ),
      product_token_role = "matcher_profile_selector",
      product_token_comparison = "ascii_case_insensitive_exact",
      supported_profiles = bing_supported_profiles_v1()
    ),
    rfc9309 = list(
      token_policy = "rfc9309",
      matcher_semantics = "rfc9309",
      note = paste0(
        "RFC 9309 behavior is available only under the rfc9309 backend; ",
        "no other backend may be relabeled as RFC 9309 semantics."
      )
    )
  )
}

validated_backend_capability_v1 <- function() {
  validate_backend_capability_v1(engine_backend_capability_v1())
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
#' the matcher token/semantics capability boundary (`matcher_capability`,
#' which for a `bounded_profiles` backend also publishes the accepted
#' matcher-profile selectors in `supported_profiles`),
#' the separately inspectable vendored-matcher identity fields
#' (`matcher_identity`, e.g. library/payload/profile/corpus/evidence/
#' profile-source for the Yandex backend), status-policy table, and supported
#' sibling-package ranges for the v1 engine-aware contract. It performs no fetch
#' or matching.
#'
#' @return A named list of contract metadata with class
#'   `robots_engine_contract_v1`.
#' @examples
#' # A plain offline accessor: it opens no socket and matches nothing.
#' contract <- robots_engine_contract_v1()
#' contract$contract_id
#' contract$schema_revision
#'
#' # Which matcher backends this installation can actually run.
#' contract$matcher_availability
#'
#' # The token/semantics boundary each backend is authoritative for.
#' contract$matcher_capability$yandex$token_policy
#'
#' # Which selectors a bounded backend accepts, and how each one selects a
#' # group. `Yandex` falls back to `User-agent: *`; `YandexAdditionalBot`
#' # never does, so the two are not interchangeable.
#' contract$matcher_capability$yandex$supported_profiles
#'
#' # Status policy is a lookup keyed by acquisition category and ruleset:
#' # how each ruleset treats a 4xx response to the robots.txt request.
#' policy <- contract$policy_table
#' policy[
#'   policy$category == "status_4xx",
#'   c("ruleset", "policy_status", "policy_action", "policy_provenance")
#' ]
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
      matcher_capability = validated_backend_capability_v1(),
      matcher_identity = list(
        yandex = yandex_matcher_identity_v1(),
        bing = bing_matcher_identity_v1()
      ),
      robots_policy_rulesets = engine_rulesets_v1(),
      matcher_backends = engine_matchers_v1(),
      safety_levels = engine_safety_levels_v1(),
      policy_table = engine_policy_table_v1(),
      sibling_versions = c(
        sitemapr = ">= 0.0.0.9000, < 0.1.0",
        `sitemap-validator` = ">= 1.0.0, < 2.0.0"
      )
    ),
    class = "robots_engine_contract_v1"
  )
}

#' Inspect the engine-aware/v2 robots contract (Bing activation)
#'
#' Returns the v2 facade metadata introduced by the atomic Bing matcher
#' activation. It has the same shape as [robots_engine_contract_v1()] but
#' publishes the v2 contract id (`robotstxtr.engine-aware/v2`), the v2
#' schema revision, the full eight-member v2 matcher-status set
#' (`matcher_status_set`), and the separately inspectable vendored-matcher
#' identity fields for both the Yandex and Bing backends
#' (`matcher_identity$bing`, with library/payload/contract/parser/profile/
#' manifest components). It reads the same shared matcher registry as the v1
#' accessor, so the Bing backend reports `available` here and there alike; the
#' v1 accessor's own `contract_id` and `schema_revision` stay unchanged. It does
#' no fetch or matching.
#'
#' @return A named list of contract metadata with class
#'   `robots_engine_contract_v2`.
#' @examples
#' v2 <- robots_engine_contract_v2()
#' v1 <- robots_engine_contract_v1()
#'
#' # v2 publishes its own identifiers; the v1 accessor keeps its own.
#' c(v1 = v1$contract_id, v2 = v2$contract_id)
#' c(v1 = v1$schema_revision, v2 = v2$schema_revision)
#'
#' # The component v2 adds is the full eight-member matcher-status set.
#' setdiff(names(v2), names(v1))
#' v2$matcher_status_set
#'
#' # Everything else is read from the same shared matcher registry, so the
#' # Bing identity and backend availability agree across both accessors.
#' v2$matcher_identity$bing$contract_id
#' identical(v2$matcher_availability, v1$matcher_availability)
#' @seealso [robots_engine_contract_v1()]
#' @export
robots_engine_contract_v2 <- function() {
  matcher_registry <- validated_matcher_registry_v1()
  structure(
    list(
      contract_id = engine_contract_id_v2(),
      schema_revision = engine_schema_revision_v2(),
      matcher_status_set = engine_matcher_status_set_v2(),
      policy_revisions = engine_policy_revisions_v1(),
      matcher_revisions = matcher_registry_field_v1(
        matcher_registry, "revision"
      ),
      matcher_availability = matcher_registry_field_v1(
        matcher_registry, "availability"
      ),
      matcher_capability = validated_backend_capability_v1(),
      matcher_identity = list(
        yandex = yandex_matcher_identity_v1(),
        bing = bing_matcher_identity_v1()
      ),
      robots_policy_rulesets = engine_rulesets_v1(),
      matcher_backends = engine_matchers_v1(),
      safety_levels = engine_safety_levels_v1(),
      policy_table = engine_policy_table_v1(),
      sibling_versions = c(
        sitemapr = ">= 0.0.0.9000, < 0.1.0",
        `sitemap-validator` = ">= 1.0.0, < 2.0.0"
      )
    ),
    class = "robots_engine_contract_v2"
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

# The bytes of a supplied robots.txt string, shared by every text entry point
# (ROBO-tipzbglv). A string marked "bytes" is used verbatim, and one marked
# UTF-8 is already UTF-8. An unmarked ("unknown") string is taken as UTF-8
# bytes as written when native_text_as_written() holds: enc2utf8() would
# re-encode it as native-locale text, and under LC_CTYPE C, whose charset is
# ASCII, that escapes each non-ASCII byte as "<xx>". In any other native
# encoding (an 8-bit locale such as ISO-8859-1 or ISO-8859-15) an unmarked
# string is native text, so it is converted. A string marked "latin1" is
# converted.
text_body_bytes_v1 <- function(robots_txt) {
  encoding <- Encoding(robots_txt)
  if (identical(encoding, "bytes")) {
    return(charToRaw(robots_txt))
  }
  if (identical(encoding, "unknown") && native_text_as_written()) {
    return(charToRaw(robots_txt))
  }
  charToRaw(enc2utf8(robots_txt))
}

# TRUE when the session's native encoding is UTF-8 or ASCII (the C locale), so
# an unmarked string's bytes are already what a UTF-8 reading wants. The C
# locale reports its codeset under several names; a platform that reports none
# is not assumed to be ASCII.
native_text_as_written <- function() {
  info <- l10n_info()
  if (isTRUE(info[["UTF-8"]])) {
    return(TRUE)
  }
  codeset <- info[["codeset"]]
  is.character(codeset) && length(codeset) == 1L &&
    codeset %in% c("US-ASCII", "ANSI_X3.4-1968", "ASCII")
}

matcher_string_v1 <- function(body) {
  decode_matcher_body(body)
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
    safety_level = character(),
    https_downgrade_guard = logical(),
    legacy_fetch_outcome = character(),
    legacy_http_status = integer(),
    error_stage = character(),
    error_class = character(),
    error_message = character(),
    stringsAsFactors = FALSE
  )
  out$fetch_allow_ranges <- list()
  out$redirect_hops <- list()
  out$body <- list()
  out
}

source_results_to_evidence_v1 <- function(results, source_ids, requested_url,
                                          fetch_ua, timeout, max_bytes,
                                          ssrf_guard, safety_level) {
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
    safety_level = rep(safety_level, length(results)),
    https_downgrade_guard = rep(safety_level == "strict", length(results)),
    legacy_fetch_outcome = vapply(
      results, `[[`, character(1L), "fetch_outcome"
    ),
    legacy_http_status = vapply(results, `[[`, integer(1L), "http_status"),
    error_stage = vapply(results, `[[`, character(1L), "error_stage"),
    error_class = vapply(results, `[[`, character(1L), "error_class"),
    error_message = vapply(results, `[[`, character(1L), "error_message"),
    stringsAsFactors = FALSE
  )
  # No range is reopened yet: `fetch_allow_ranges` lands with ROBO-bamcjvwn.
  out$fetch_allow_ranges <- rep(list(character()), length(results))
  out$redirect_hops <- lapply(results, `[[`, "redirect_hops")
  out$body <- lapply(results, `[[`, "body")
  out
}

fetch_evidence_v1 <- function(url, timeout, max_bytes, fetch_ua, ssrf_guard,
                              safety_level) {
  origin <- vapply(url, robots_origin, character(1L), USE.NAMES = FALSE)
  eligible <- !is.na(origin)
  distinct_origins <- unique(origin[eligible])
  source_ids <- paste0("robots_", seq_along(distinct_origins))
  fetched <- vector("list", length(distinct_origins))
  for (i in seq_along(distinct_origins)) {
    fetched[[i]] <- acquire_robots(
      distinct_origins[[i]], timeout, fetch_ua, max_bytes, ssrf_guard
    )
  }
  evidence <- source_results_to_evidence_v1(
    fetched, source_ids, distinct_origins, fetch_ua, timeout, max_bytes,
    ssrf_guard, safety_level
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
    safety_level = NA_character_,
    https_downgrade_guard = NA,
    legacy_fetch_outcome = "supplied",
    legacy_http_status = NA_integer_,
    error_stage = NA_character_,
    error_class = NA_character_,
    error_message = NA_character_,
    stringsAsFactors = FALSE
  )
  out$fetch_allow_ranges <- list(NA_character_)
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

# The policy-table category of a final HTTP status. 206 is not reached here:
# its evidence status is `partial`. A 1xx or a status outside 100-599 is a
# protocol error. robots_validate_url() uses it too (ROBO-ybzbxfml).
http_status_category_v1 <- function(status) {
  if (length(status) == 1L) {
    status <- suppressWarnings(as.integer(status))
  }
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

# Whether `ruleset` reads a 2xx cut at `max_bytes` despite its `incomplete`
# evidence (ADR 0001 section 5: the cut is an L0 fact, the ruleset decides
# what it means). Yandex ignores a file over 500 KB; a cut that stored
# 512,000 bytes or more is over it under either reading of "500 KB", so it
# goes on to the policy table and the yandex size branch (ROBO-arrtietl).
# Google parses the first 512,000 bytes; a cut that stored at least that
# many holds the whole window, so it goes on to the policy table and is
# matched on its complete lines inside the window (ROBO-ptibdnvy). That
# reading is the google matcher's, so it needs `matcher_backend` "google":
# another backend would match the cut prefix on its own terms. The yandex
# reading resolves allow_all with no matcher, so it needs no backend.
# A body_too_large row is not cut (`body_truncated` FALSE) and stays
# incomplete. rfc9309, assumed_rfc9309 and bing keep a cut incomplete, as
# do yandex and google below 512,000 stored bytes and google with any other
# backend.
ceiling_cut_readable_v1 <- function(evidence, ruleset,
                                    matcher_backend = NA_character_) {
  if (!isTRUE(evidence$body_truncated)) {
    return(FALSE)
  }
  if (identical(ruleset, "yandex")) {
    return(evidence$stored_bytes >= 512000L)
  }
  if (identical(ruleset, "google") && identical(matcher_backend, "google")) {
    return(evidence$stored_bytes >= 512000L)
  }
  FALSE
}

resolve_policy_v1 <- function(evidence, ruleset, policy_table,
                              matcher_backend = NA_character_) {
  evidence_status <- evidence$evidence_status
  if (identical(evidence_status, "safety_refused")) {
    return(policy_result_v1(
      "not_evaluated", NA_character_, "safety_refused",
      "application_choice", "design/engine-profiles.md#neutral-fetch"
    ))
  }
  if (identical(evidence_status, "incomplete") &&
        !ceiling_cut_readable_v1(evidence, ruleset, matcher_backend)) {
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
    http_status_category_v1(evidence$final_http_status)
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

# Google parses a robots.txt's first 500 KiB (512,000 bytes) and ignores the
# rest. A line the window cuts is not the site's rule, so, as for a body cut
# at `max_bytes` (ROBO-ldpahknv), matching stops at the last complete line
# inside the window. `matcher_input_bytes` counts the bytes fed to the
# matcher; `matcher_body_truncated` says the body exceeded the window.
match_google_v1 <- function(body, url, product_token) {
  limit <- 512000L
  truncated <- length(body) > limit
  matcher_body <- if (truncated) {
    # One byte past the window says whether the line at its edge is complete.
    lines <- complete_lines_prefix(body[seq_len(limit + 1L)])
    lines[seq_len(min(length(lines), limit))]
  } else {
    body
  }
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

# A decision frame from a row matcher: `row_match(body, url, product_token)`
# returns one row's fields as a list, called on each row in order. Every row
# is `evaluated` with no error; `matched_rule_value_raw` is NULL on every row.
row_matcher_frame_v1 <- function(row_match, bodies, urls, product_tokens) {
  n <- length(bodies)
  rows <- lapply(seq_len(n), function(k) {
    row_match(bodies[[k]], urls[[k]], product_tokens[[k]])
  })
  field <- function(name, type) vapply(rows, `[[`, type, name)
  out <- data.frame(
    matcher_status = rep("evaluated", n),
    url_decision = field("url_decision", character(1L)),
    reason = field("reason", character(1L)),
    matched_line = field("matched_line", integer(1L)),
    matched_rule_type = field("matched_rule_type", character(1L)),
    matched_rule_value = field("matched_rule_value", character(1L)),
    matcher_input_bytes = field("matcher_input_bytes", integer(1L)),
    matcher_body_truncated = field("matcher_body_truncated", logical(1L)),
    error_stage = rep(NA_character_, n),
    error_class = rep(NA_character_, n),
    error_message = rep(NA_character_, n),
    stringsAsFactors = FALSE
  )
  out$matched_rule_value_raw <- vector("list", n)
  out
}

# The Google matcher adapter. It still matches row by row: each row's body
# is cut to Google's 512,000-byte window by match_google_v1() itself, before
# any grouping, and each row keeps its own `matcher_body_truncated`. Google
# rows carry no raw rule value yet (`matched_rule_value_raw` NULL).
match_google_batch_v1 <- function(bodies, urls, product_tokens) {
  row_matcher_frame_v1(match_google_v1, bodies, urls, product_tokens)
}

# The frozen identity of the vendored robotstxtyandex payload. These six fields
# single-source the Yandex matcher revision and the separately inspectable
# library/payload/profile/corpus/evidence/profile-source metadata published on
# the contract accessor. They MUST byte-equal the corresponding
# inst/vendor/robotstxtyandex/MANIFEST.dcf fields; the composed MatcherRevision
# below byte-equals that manifest's MatcherRevision field.
yandex_matcher_identity_v1 <- function() {
  list(
    library_version = "0.2.0",
    payload_commit = "fdd60a7c3bc6825f3b3752562dc0d6ad9387a27e",
    profile_id = "yandex-0.1.0",
    accepted_corpus_revision = "337b9f3b886a92d6dc08c2fce84228d0cd6b801a",
    evidence_snapshot = paste0(
      "9d69d361db81e7d236562dc056b41865",
      "da33d467d06f316e2c9a20988e007c96"
    ),
    profile_source_revision = "337b9f3b886a92d6dc08c2fce84228d0cd6b801a"
  )
}

# Compose the frozen Yandex identity into the serialized MatcherRevision string.
# The format is fixed by design/robotstxtyandex-integration-v1-spec.md and MUST
# byte-equal inst/vendor/robotstxtyandex/MANIFEST.dcf's MatcherRevision field.
yandex_matcher_revision_v1 <- function() {
  id <- yandex_matcher_identity_v1()
  paste0(
    "robotstxtyandex/", id$library_version,
    "+payload.", id$payload_commit,
    ";profile=", id$profile_id,
    ";corpus=", id$accepted_corpus_revision,
    ";evidence=", id$evidence_snapshot,
    ";profile-source=", id$profile_source_revision
  )
}

# The frozen identity of the vendored robotstxtbing 0.1.0 payload (BI-V2-PIN /
# BI-V2-IDENTITY). These eight fields single-source the Bing matcher revision
# and the separately inspectable identity metadata published on the v2 contract
# accessor. They MUST byte-equal the corresponding
# inst/vendor/robotstxtbing/MANIFEST.dcf fields; the seven contract_info()
# fields reconcile against the compiled ground truth
# bing_native_contract_info(), and the composed MatcherRevision below
# byte-equals the manifest's MatcherRevision. `payload_commit` is the
# owner-approved pin: the annotated tag object for tag 0.1.0 (the value the
# manifest's MatcherRevision embeds), not its target commit.
bing_matcher_identity_v1 <- function() {
  list(
    library_version = "0.1.0",
    payload_commit = "c82855d0756c748cc4770246a19282323cdfa331",
    contract_id = "robotstxtbing-v2",
    contract_revision = "0.1.0",
    parser_revision = "0.1.0",
    bingbot_profile_revision = "bingbot-2026-07-23.1",
    adidxbot_profile_revision = "adidxbot-2026-07-23.1",
    release_manifest_sha256 = paste0(
      "5e79ee5dcb1a22b73b5fa0f86766be529",
      "cf111fd5530d07b53fe1d6b7050a858"
    )
  )
}

# Compose the frozen Bing identity into the serialized MatcherRevision string.
# The format is fixed by design/robotstxtbing-integration-v2-spec.md SS14 and
# MUST byte-equal the MatcherRevision field in
# inst/vendor/robotstxtbing/MANIFEST.dcf.
bing_matcher_revision_v1 <- function() {
  id <- bing_matcher_identity_v1()
  paste0(
    "robotstxtbing/", id$library_version,
    "+payload.", id$payload_commit,
    ";contract=", id$contract_id,
    ";contract-rev=", id$contract_revision,
    ";parser=", id$parser_revision,
    ";bingbot=", id$bingbot_profile_revision,
    ";adidxbot=", id$adidxbot_profile_revision,
    ";manifest=", id$release_manifest_sha256
  )
}

# The matcher registry: one entry per backend, its exact revision, its
# availability and, when available, its matcher adapter. Every adapter has
# the one batch interface `callable(bodies, urls, product_tokens)` and
# returns a decision frame (matcher_decision_columns_v1()); evaluate_rows_v1()
# dispatches on the entry alone, never on a backend's name.
engine_matcher_registry_v1 <- function() {
  list(
    google = list(
      revision = paste0(
        "google-robotstxt-",
        "22b355ff855419e6a3ff8ff09c0ad7fdb17116f9"
      ),
      availability = "available",
      callable = match_google_batch_v1
    ),
    yandex = list(
      revision = yandex_matcher_revision_v1(),
      availability = "available",
      callable = match_yandex_v1
    ),
    rfc9309 = list(
      revision = "capability-unavailable-v1",
      availability = "capability_unavailable",
      callable = NULL
    ),
    bing = list(
      revision = bing_matcher_revision_v1(),
      availability = "available",
      callable = match_bing_v1
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

# The decision frame: the columns every matcher adapter returns, one row per
# input row, in input order. `matched_rule_value_raw` is a list column (raw
# bytes, raw(0) or NULL per row). An adapter may add columns (`native_*`) or
# attributes (`n_parse_calls`); the evaluator ignores them.
matcher_decision_columns_v1 <- function() {
  c(
    "matcher_status", "url_decision", "reason", "matched_line",
    "matched_rule_type", "matched_rule_value", "matcher_input_bytes",
    "matcher_body_truncated", "error_stage", "error_class", "error_message",
    "matched_rule_value_raw"
  )
}

matcher_output_abort_v1 <- function(backend, detail) {
  robots_abort(
    sprintf("Matcher adapter `%s` broke its output contract: %s", backend,
            detail),
    "robotstxtr_matcher_output_invariant"
  )
}

# Fail-closed guard on an adapter's decision frame, like
# validate_matcher_status_v2(): a frame with the wrong row count or without
# a required column is an internal invariant violation, never a row outcome.
# Returns the frame unchanged on success.
check_matcher_output_v1 <- function(output, n, backend) {
  if (!is.data.frame(output)) {
    matcher_output_abort_v1(backend, "it returned no data frame.")
  }
  if (nrow(output) != n) {
    matcher_output_abort_v1(backend, sprintf(
      "%d row(s) for %d input row(s).", nrow(output), n
    ))
  }
  missing <- setdiff(matcher_decision_columns_v1(), names(output))
  if (length(missing) > 0L) {
    matcher_output_abort_v1(backend, sprintf(
      "missing column(s): %s.", toString(missing)
    ))
  }
  if (!is.list(output$matched_rule_value_raw)) {
    matcher_output_abort_v1(
      backend, "`matched_rule_value_raw` is not a list column."
    )
  }
  output
}

# Run one backend's adapter over its rows and check what comes back. An
# adapter reports every per-row outcome as a row; it aborts only on an
# internal invariant violation, and that abort is not caught here.
dispatch_matcher_v1 <- function(registry, backend, bodies, urls,
                                product_tokens) {
  entry <- registry[[backend]]
  if (!is.list(entry) || !identical(entry$availability, "available") ||
        !is.function(entry$callable)) {
    robots_abort(
      sprintf("Matcher backend `%s` is unavailable or unregistered.", backend),
      "robotstxtr_matcher_backend_unavailable"
    )
  }
  output <- entry$callable(
    bodies = bodies, urls = urls, product_tokens = product_tokens
  )
  check_matcher_output_v1(output, length(bodies), backend)
}

policy_limit_v1 <- function(ruleset) {
  out <- rep(NA_integer_, length(ruleset))
  out[ruleset == "google"] <- 512000L
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

# `matcher_registry` is internal: the public entry points never pass it, so
# it is the production registry, validated once per call. Tests pass a fake
# registry to swap matcher adapters.
evaluate_rows_v1 <- function(url, product_token, ruleset, matcher_backend,
                             source_id, evidence, url_valid, token_valid,
                             fetch_ua, timeout, max_bytes, ssrf_guard,
                             safety_level,
                             matcher_registry = engine_matcher_registry_v1()) {
  n <- length(url)
  policy_revisions <- engine_policy_revisions_v1()
  matcher_registry <- validate_matcher_registry_v1(matcher_registry)
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
  # Rows that need a matcher are collected here, with the evidence row whose
  # body they match and whether that body was cut at `max_bytes`, and
  # dispatched after the loop: one adapter call per backend.
  # Preallocated and set by index: growing them row by row is quadratic.
  needs_matcher <- logical(n)
  source_of <- integer(n)
  body_cut <- rep(FALSE, n)
  readable_bodies <- vector("list", length(evidence$source_id))
  for (i in which(valid)) {
    evidence_index <- match(source_id[[i]], evidence$source_id)
    ev <- lapply(evidence, function(column) column[[evidence_index]])
    evidence_status[[i]] <- ev$evidence_status
    policy <- resolve_policy_v1(
      ev, ruleset[[i]], policy_table, matcher_backend[[i]]
    )
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
    # A cut body reaches here only under the google ruleset with the google
    # backend (ceiling_cut_readable_v1()). Its partial last line is dropped
    # before the window, so a cut of exactly 512,000 bytes is read like a
    # longer one; uncut bodies pass through unchanged (ROBO-ptibdnvy). Each
    # source's readable body is computed once, however many URLs share it.
    if (is.null(readable_bodies[[evidence_index]])) {
      readable_bodies[evidence_index] <- list(
        readable_body(ev$body, ev$body_truncated)
      )
    }
    needs_matcher[[i]] <- TRUE
    source_of[[i]] <- evidence_index
    body_cut[[i]] <- isTRUE(ev$body_truncated)
  }

  # One adapter call per backend over all of its rows, in row order; the
  # decision frame's row k scatters back to the backend's k-th row. Adapters
  # that parse once per distinct body (yandex, bing) dedupe inside.
  matched_rule_value_raw <- vector("list", n)
  matcher_rows <- which(needs_matcher)
  matcher_sources <- source_of[matcher_rows]
  row_backends <- matcher_backend[matcher_rows]
  for (backend in unique(row_backends)) {
    picked <- row_backends == backend
    rows <- matcher_rows[picked]
    decided <- dispatch_matcher_v1(
      matcher_registry, backend,
      bodies = readable_bodies[matcher_sources[picked]],
      urls = url[rows], product_tokens = product_token[rows]
    )
    matcher_status[rows] <- decided$matcher_status
    url_decision[rows] <- decided$url_decision
    reason[rows] <- decided$reason
    matched_line[rows] <- decided$matched_line
    matched_rule_type[rows] <- decided$matched_rule_type
    matched_rule_value[rows] <- decided$matched_rule_value
    matcher_input_bytes[rows] <- decided$matcher_input_bytes
    # A cut of at least 512,000 bytes proves the file exceeded the window,
    # even when its complete lines fit inside it: each row's own cut joins
    # the adapter's flag.
    matcher_body_truncated[rows] <- decided$matcher_body_truncated |
      body_cut[rows]
    error_stage[rows] <- decided$error_stage
    error_class[rows] <- decided$error_class
    error_message[rows] <- decided$error_message
    matched_rule_value_raw[rows] <- decided$matched_rule_value_raw
  }

  # Fail closed: no row may carry a matcher_status outside the published
  # engine-aware/v2 vocabulary, regardless of backend (BI-V2-SCHEMA).
  matcher_status <- validate_matcher_status_v2(matcher_status)

  results <- data.frame(
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
    https_downgrade_guard = rep(
      if (is.na(timeout)) NA else safety_level == "strict",
      length.out = n
    ),
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
  # Public list column, unchanged since schema 2026-07-18.2: exactly one
  # element per row. Rows no adapter decided stay absent (NULL); adapter rows
  # carry what the adapter returned (raw bytes / raw(0) / NULL; NULL on every
  # Google row), so the present-empty raw(0) vs absent NULL distinction
  # survives verbatim.
  results$matched_rule_value_raw <- matched_rule_value_raw
  results
}

#' Evaluate URLs against supplied robots.txt under an explicit engine profile
#'
#' Versioned, no-network entry point for the engine-aware v1 contract. The
#' robots status-policy ruleset and matcher backend are selected independently;
#' an unavailable backend produces `matcher_status = "capability_unavailable"`
#' rather than silently using Google's matcher.
#'
#' @details
#' The `robots_product_token` is used ONLY for robots user-agent group
#' selection; it is never sent as an HTTP header. Each matcher backend is
#' authoritative only for its own vendor semantics: `google` for Google,
#' `yandex` for Yandex, `bing` for Bing, and RFC 9309 behavior only under the
#' `rfc9309` backend. The Google backend additionally accepts any valid Google
#' robots product token and returns Google parsing/matching semantics for it;
#' that is NOT a claim of compatibility with, or a prediction of, the crawler
#' the token names. The Yandex and Bing backends are bounded to their supported
#' vendor profiles only and never generalize to arbitrary tokens. This boundary
#' is published as `robots_engine_contract_v1()$matcher_capability`.
#'
#' The Yandex backend is active (since schema revision `2026-07-18.2`). An
#' evaluated Yandex row publishes `reason` as one of `default_allow`,
#' `rule_allow`, `rule_disallow`, or `effective_empty_disallow`; a non-evaluated
#' Yandex row reports `matcher_status = "not_evaluated"` with
#' `reason = "unsupported_product_token"`
#' (`error_class = "robots_unsupported_product_token"`) or
#' `reason = "invalid_request_target"`
#' (`error_class = "robots_invalid_request_target"`) at
#' `error_stage = "input"`. The activation adds the public
#' `matched_rule_value_raw` list column (one element per row: exact owning-rule
#' bytes, `raw(0)` for an effective-empty Disallow, or `NULL` for an absent
#' rule); it is populated for Yandex-evaluated rows and `NULL` elsewhere. The
#' vendored-matcher identity is published as
#' `robots_engine_contract_v1()$matcher_identity$yandex`.
#'
#' A Google row reports no line for a rule with an empty value: when the
#' selected rule is an `Allow:` or `Disallow:` with nothing after the colon,
#' the row reports `url_decision = "allow"` with `reason = "default_allow"`,
#' `matched_rule_type = "none"`, `NA` `matched_line` and `matched_rule_value`,
#' and a `NULL` `matched_rule_value_raw`; the legacy functions report the
#' same decision source, type, line and value (`design/PRD.md` section 6.6,
#' "Match metadata rules"). When a Yandex row's selected rule is an empty
#' `Disallow`, it instead reports `effective_empty_disallow` with that line.
#'
#' @param robots_txt A single, non-missing character value containing the
#'   robots.txt body. A body marked UTF-8 is used as written. An unmarked body
#'   (as `rawToChar()` gives) is taken as UTF-8 bytes as written when the
#'   session's native encoding is UTF-8 or ASCII (the C locale), and converted
#'   from the native encoding otherwise; one marked `"latin1"` is converted,
#'   and one marked `Encoding = "bytes"` is used verbatim.
#' @param url A character vector of URLs to evaluate.
#' @param robots_product_token A matcher-profile selector: a robots.txt
#'   `User-agent:` group label, NOT an HTTP `User-Agent` crawler identity. It is
#'   never sent as a header. A character vector of length one or `length(url)`.
#'   The Google backend accepts any valid Google robots product token and
#'   yields Google semantics for it, not a prediction of the named crawler. The
#'   `"yandex"` and `"bing"` backends accept only a closed set of selectors,
#'   published on the engine contract as
#'   `matcher_capability$<backend>$supported_profiles` and checkable up front
#'   with [robots_resolve_matcher_profile_v1()]; an
#'   unaccepted selector leaves its rows undecided rather than raising.
#' @param robots_policy_ruleset An explicit ruleset, length one or
#'   `length(url)`: `"google"`, `"yandex"`, `"rfc9309"`, `"bing"`, or
#'   `"assumed_rfc9309"`.
#' @param matcher_backend An explicit matcher backend, length one or
#'   `length(url)`: `"google"`, `"yandex"`, `"rfc9309"`, or `"bing"`.
#' @param source_id A non-empty identifier for the supplied body.
#'
#' @return A `robots_engine_decisions_v1` object with `results`, neutral
#'   `evidence`, and `contract` components.
#' @examples
#' # A non-Google-named token evaluated through the default Google backend
#' # yields Google parsing/matching semantics for that token. This is NOT a
#' # prediction of the named crawler's behavior.
#' decisions <- robots_evaluate_text_v1(
#'   "user-agent: *\ndisallow: /private",
#'   "https://example.com/private",
#'   robots_product_token = "Yandex",
#'   robots_policy_ruleset = "google",
#'   matcher_backend = "google"
#' )
#' decisions$results$matcher_backend  # "google" -- Google semantics, not Yandex
#' decisions$results$url_decision     # "disallow"
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
    token_valid, NA_character_, NA_real_, NA_integer_, NA, NA_character_
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
#' @details
#' As with [robots_evaluate_text_v1()], the `robots_product_token` drives ONLY
#' user-agent group selection. Each matcher backend is authoritative only for
#' its own vendor semantics; the Google backend accepts any valid Google robots
#' product token and returns Google semantics for it, which is not a claim of
#' compatibility with the named crawler, while the Yandex and Bing backends are
#' bounded to their supported vendor profiles and RFC 9309 behavior is available
#' only under the `rfc9309` backend. See
#' `robots_engine_contract_v1()$matcher_capability`.
#'
#' A Google row whose selected rule has an empty value reports
#' `reason = "default_allow"` with no line, as in [robots_evaluate_text_v1()].
#'
#' @inheritParams robots_evaluate_text_v1
#' @inheritParams robots_fetch
#'
#' @return A `robots_engine_decisions_v1` object with `results`, neutral
#'   `evidence`, and `contract` components.
#' @examples
#' # A refused origin is decided before any request, so this runs offline. The
#' # evidence records why, apart from the (absent) decision.
#' refused <- robots_evaluate_url_v1(
#'   "http://[fd00:ec2::254]/latest",
#'   robots_product_token = "my-bot",
#'   robots_policy_ruleset = "google",
#'   matcher_backend = "google"
#' )
#' refused$evidence[c("source_id", "safety_block_reason", "evidence_status")]
#'
#' \dontrun{
#' # A live fetch of https://example.com/robots.txt.
#' decisions <- robots_evaluate_url_v1(
#'   c("https://example.com/page", "https://example.com/private"),
#'   robots_product_token = "my-bot",
#'   robots_policy_ruleset = "google",
#'   matcher_backend = "google"
#' )
#' decisions$results[c("url", "policy_status", "url_decision", "reason")]
#'
#' # Acquisition evidence is recorded neutrally, apart from the decision, so
#' # the policy applied to the response stays auditable.
#' decisions$evidence[c("source_id", "final_http_status", "evidence_status")]
#' }
#' @export
robots_evaluate_url_v1 <- function(url, robots_product_token,
# nolint start: object_length_linter
                                   robots_policy_ruleset, matcher_backend,
# nolint end
                                   timeout = 10, max_bytes = 524288L,
                                   fetch_user_agent = NULL,
                                   ssrf_guard = TRUE,
                                   safety_level = "strict") {
  validate_url_type(url)
  timeout <- validate_timeout(timeout)
  max_bytes <- validate_max_bytes(max_bytes)
  validate_fetch_user_agent(fetch_user_agent)
  validate_ssrf_guard(ssrf_guard)
  safety_level <- validate_safety_level(safety_level)
  warn_ssrf_guard_deprecated(ssrf_guard)
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
    fetch_input, timeout, max_bytes, fetch_ua, ssrf_guard, safety_level
  )
  results <- evaluate_rows_v1(
    url, token, ruleset, backend, fetched$source_id, fetched$evidence,
    url_valid, token_valid, fetch_ua, timeout, max_bytes, ssrf_guard,
    safety_level
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
#' A source whose 2xx body was cut at `max_bytes` has
#' `fetch_outcome = "fetched"` and `body_truncated = TRUE`. When it stored
#' fewer than 512,000 bytes, its rows are `allowed = NA` /
#' `decision_source = "fetch_unknown"` with `NA` error fields: the v1 evidence
#' of a cut body is `incomplete`, the Google ruleset does not match a cut
#' that misses part of its 512,000-byte window, and the legacy `error_class`
#' set has no class for a cut body (the v1 result's `reason` is
#' `"incomplete_evidence"`). When it stored 512,000 bytes or more, its rows
#' are matched on the complete lines of the first 512,000 bytes and carry the
#' match as `allowed` and `decision_source`, unlike [allowed_by_robots_url()],
#' which matches the complete lines of the whole stored prefix.
#'
#' @param x A `robots_engine_decisions_v1` object using the Google policy and
#'   Google matcher backend for every row.
#'
#' @return A legacy `robots_decisions` object.
#' @examples
#' # Build a v1 engine result offline, then adapt it for a legacy consumer.
#' engine <- robots_evaluate_text_v1(
#'   "user-agent: *\nDisallow: /private\n",
#'   c("https://example.com/page", "https://example.com/private"),
#'   robots_product_token = "my-bot",
#'   robots_policy_ruleset = "google",
#'   matcher_backend = "google"
#' )
#' engine$results[c("url", "url_decision", "reason")]
#'
#' # The adapter collapses the three-valued `url_decision` into the legacy
#' # logical `allowed`, and carries `reason` over as `decision_source`.
#' legacy <- as_legacy_robots_decisions_v1(engine)
#' class(legacy)
#' legacy$results[c("url", "allowed", "decision_source", "matched_rule_type")]
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
    # The evidence frame keeps no Retry-After (ROBO-cthdyvlk) and no
    # Content-Type or content flag (ROBO-nhuirvrd): not available.
    retry_after = rep(NA_character_, nrow(evidence)),
    retry_after_seconds = rep(NA_real_, nrow(evidence)),
    content_type = rep(NA_character_, nrow(evidence)),
    content_flag = rep(NA_character_, nrow(evidence)),
    # A cut 2xx body (ROBO-ldpahknv); FALSE where the evidence has no value.
    body_truncated = !is.na(evidence$body_truncated) &
      evidence$body_truncated,
    # The evidence keeps both, so the legacy frame carries them as
    # robots_fetch() does (ROBO-bsloeclp).
    terminal_redirect_reason = evidence$terminal_redirect_reason,
    safety_block_reason = evidence$safety_block_reason,
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
