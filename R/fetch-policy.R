# Deterministic fetch policy for robots_fetch() (PRD 6.4 request/response
# behavior, 6.5 grouping): the call-level validators of the shared fetch
# controls, the HTTP status classifier, the per-outcome error metadata and the
# source-result shape. It performs NO matching (slice R8) and no I/O: the
# acquisition itself, the redirect loop included, is R/acquire.R, the one
# caller of ssrfr (ROBO-jbralthm).

# --- Call-level validators (whole call aborts on violation, PRD 6.6) --------

# `timeout` must be one non-missing, finite, positive numeric value.
validate_timeout <- function(timeout) {
  if (!is.numeric(timeout) || length(timeout) != 1L || is.na(timeout) ||
        !is.finite(timeout) || timeout <= 0) {
    robots_abort(
      "`timeout` must be a single, positive, finite numeric value (seconds).",
      "robotstxtr_invalid_timeout"
    )
  }
  invisible(as.double(timeout))
}

# `fetch_user_agent` must be NULL or one non-empty, non-missing character value
# that ssrfr accepts as a `user_agent`: a valid HTTP field value. ssrfr's own
# check decides, and its error is re-classed so the call-level error keeps
# robotstxtr's class (ROBO-jbralthm).
validate_fetch_user_agent <- function(fetch_user_agent) {
  if (is.null(fetch_user_agent)) {
    return(invisible(NULL))
  }
  if (!is.character(fetch_user_agent) || length(fetch_user_agent) != 1L ||
        is.na(fetch_user_agent) || !nzchar(fetch_user_agent)) {
    robots_abort(
      paste(
        "`fetch_user_agent` must be `NULL` or a single, non-empty",
        "character value."
      ),
      "robotstxtr_invalid_fetch_user_agent"
    )
  }
  tryCatch(
    ssrfr::ssrf_policy(user_agent = fetch_user_agent),
    ssrfr_error_invalid_policy = function(e) {
      robots_abort(
        paste(
          "`fetch_user_agent` must be a valid HTTP field value: no control",
          "character, and no leading or trailing whitespace."
        ),
        "robotstxtr_invalid_fetch_user_agent"
      )
    }
  )
  invisible(fetch_user_agent)
}

# `max_bytes` must be one non-missing, finite, POSITIVE, WHOLE-NUMBER value no
# greater than `.Machine$integer.max` (PRD 6.6 shared fetch controls). An R
# double that represents a valid whole number (e.g. `524288` or `1e5`) is
# accepted; fractional, non-positive, non-scalar, non-numeric, NA/Inf, or
# out-of-range values are call-level errors (not a silent NA). Coerced to
# integer exactly once, after validation.
validate_max_bytes <- function(max_bytes) {
  if (!is.numeric(max_bytes) || length(max_bytes) != 1L || is.na(max_bytes) ||
        !is.finite(max_bytes) || max_bytes <= 0 ||
        max_bytes != trunc(max_bytes) ||
        max_bytes > .Machine$integer.max) {
    robots_abort(
      paste(
        "`max_bytes` must be a single, positive, finite, whole-number value",
        "no greater than `.Machine$integer.max`."
      ),
      "robotstxtr_invalid_max_bytes"
    )
  }
  as.integer(max_bytes)
}

# `ssrf_guard` must be one non-missing logical value. It defaults to TRUE at the
# public surface. FALSE is deprecated: ssrfr has no off switch, so it selects a
# permissive policy instead (acquire_policy()).
validate_ssrf_guard <- function(ssrf_guard) {
  if (!is.logical(ssrf_guard) || length(ssrf_guard) != 1L ||
        is.na(ssrf_guard)) {
    robots_abort(
      "`ssrf_guard` must be a single, non-missing logical (`TRUE`/`FALSE`).",
      "robotstxtr_invalid_ssrf_guard"
    )
  }
  invisible(ssrf_guard)
}

# The deprecation warning for `ssrf_guard = FALSE`, raised once per call by the
# public entry points that fetch: robots_fetch() (which allowed_by_robots_url()
# and robots_validate_url() call) and robots_evaluate_url_v1().
warn_ssrf_guard_deprecated <- function(ssrf_guard) {
  if (!isFALSE(ssrf_guard)) {
    return(invisible(NULL))
  }
  warning(structure(
    class = c(
      "robotstxtr_deprecated_ssrf_guard", "deprecatedWarning", "warning",
      "condition"
    ),
    list(
      message = paste(
        "`ssrf_guard = FALSE` is deprecated. It no longer turns the guard",
        "off: private and loopback addresses are reopened, but cloud",
        "metadata endpoints and IPv6 transition forms stay refused."
      ),
      call = NULL
    )
  ))
}

# The package fetch user agent (PRD 6.4): package name and version. Never the
# matcher user_agent (robots_fetch has no matcher user agent anyway).
package_fetch_user_agent <- function() {
  sprintf("robotstxtr/%s", as.character(getNamespaceVersion("robotstxtr")))
}

# --- Classifiers ------------------------------------------------------------

# Map a final (non-3xx) HTTP status to a stable fetch_outcome (PRD 6.4 table).
classify_status <- function(status) {
  if (status >= 100L && status <= 199L) {
    return("http_error")
  }
  if (status == 206L) {
    return("partial_response")
  }
  if (status >= 200L && status <= 299L) {
    return("fetched")
  }
  if (status == 404L || status == 410L) {
    return("missing")
  }
  if (status >= 400L && status <= 599L) {
    return("http_error")
  }
  # Any other final status is not a body and not a redirect; treat defensively
  # as an HTTP error rather than fabricating a decision.
  "http_error"
}

# --- Per-outcome error metadata (PRD 6.6 error mapping table) ---------------

fetch_error_meta <- function(outcome) {
  switch(outcome,
    fetched = c(stage = NA_character_, class = NA_character_),
    missing = c(stage = NA_character_, class = NA_character_),
    partial_response = c(stage = "response", class = "robots_partial_response"),
    http_error = c(stage = "response", class = "robots_http_error"),
    body_too_large = c(stage = "response", class = "robots_body_too_large"),
    ssrf_blocked = c(stage = "request", class = "robots_ssrf_blocked"),
    redirect_error = c(stage = "redirect", class = "robots_redirect_error"),
    timeout = c(stage = "request", class = "robots_timeout"),
    network_error = c(stage = "request", class = "robots_network_error"),
    tls_error = c(stage = "request", class = "robots_tls_error"),
    c(stage = NA_character_, class = NA_character_)
  )
}

# Assemble one source-fetch result (the fields a `robots` row needs, minus the
# grouping-assigned source_id). `body` is a raw vector for `fetched`, else NULL.
#
# `body_truncated` is FALSE on every row (ROBO-jbralthm). ssrfr never returns
# part of a body: a body over `max_bytes` is refused whole, so no truncated
# body can exist. On a 2xx or 3xx the overflow is recorded as `fetch_outcome =
# "body_too_large"` with `termination_reason = "ceiling"`; a 4xx or 5xx keeps
# its status outcome (acquire_failure_result()). robots_validate.R's documents
# say FALSE likewise.
make_source_result <- function(outcome, http_status, effective_url,
                               redirect_count, body, error_message,
                               redirect_hops = list(),
                               terminal_redirect_reason = "none",
                               location_header = NA_character_,
                               observed_bytes = NULL,
                               transport_error_kind = NA_character_,
                               safety_block_reason = NA_character_,
                               termination_reason = "none",
                               final_http_status = NULL) {
  meta <- fetch_error_meta(outcome)
  stored_bytes <- if (is.null(body)) 0L else length(body)
  if (is.null(observed_bytes)) {
    observed_bytes <- if (is.null(body)) NA_integer_ else stored_bytes
  }
  list(
    fetch_outcome = outcome,
    http_status = if (is.null(http_status)) {
      NA_integer_
    } else {
      as.integer(http_status)
    },
    final_http_status = if (is.null(final_http_status)) {
      if (is.null(http_status)) NA_integer_ else as.integer(http_status)
    } else {
      as.integer(final_http_status)
    },
    effective_url = if (is.null(effective_url)) {
      NA_character_
    } else {
      effective_url
    },
    redirect_count = as.integer(redirect_count),
    redirect_hops = redirect_hops,
    terminal_redirect_reason = terminal_redirect_reason,
    location_header = location_header,
    body = body,
    body_size = if (is.null(body)) NA_integer_ else length(body),
    observed_bytes = as.integer(observed_bytes),
    stored_bytes = as.integer(stored_bytes),
    body_truncated = FALSE,
    transport_error_kind = transport_error_kind,
    safety_block_reason = safety_block_reason,
    termination_reason = termination_reason,
    error_stage = unname(meta[["stage"]]),
    error_class = unname(meta[["class"]]),
    error_message = if (is.null(error_message)) NA_character_ else error_message
  )
}
