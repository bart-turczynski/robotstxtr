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
                               final_http_status = NULL,
                               retry_after = NA_character_,
                               retry_after_seconds = NA_real_) {
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
    error_message = if (is.null(error_message)) {
      NA_character_
    } else {
      error_message
    },
    retry_after = retry_after,
    retry_after_seconds = as.double(retry_after_seconds)
  )
}

# --- Retry-After (ROBO-cthdyvlk) ---------------------------------------------

# The delay a Retry-After field value asks for, in seconds (RFC 9110 section
# 10.2.3): `delay-seconds` (1*DIGIT) as is, or an HTTP-date less `reference`,
# the response's own Date when it carries a valid one, else `fetched_at`
# (both seconds since the epoch). A date already past is 0. NA when the value
# is absent or is neither form. Unbounded: RFC 9110 sets no maximum, so the
# caller clamps.
retry_after_delay <- function(value, date, fetched_at) {
  if (length(value) != 1L || is.na(value)) {
    return(NA_real_)
  }
  value <- trimws(value, whitespace = "[ \t]")
  if (grepl("^[0-9]+$", value)) {
    return(as.double(value))
  }
  reference <- NA_real_
  if (!is.na(date)) {
    reference <- http_date_seconds(date, fetched_at)
  }
  if (is.na(reference)) {
    reference <- fetched_at
  }
  target <- http_date_seconds(value, reference)
  if (is.na(target)) {
    return(NA_real_)
  }
  max(0, target - reference)
}

# An HTTP-date (RFC 9110 section 5.6.7) as seconds since the epoch, or NA.
# Recipients accept all three formats: IMF-fixdate and the obsolete RFC 850
# and asctime forms. Names are case-sensitive. An RFC 850 two-digit year that
# would lie more than 50 years past `now` (seconds since the epoch) is the
# most recent past year with those digits.
http_date_seconds <- function(x, now) {
  x <- trimws(x, whitespace = "[ \t]")
  days <- "(Mon|Tue|Wed|Thu|Fri|Sat|Sun)"
  long_days <- "(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)"
  months <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
              "Oct", "Nov", "Dec")
  month <- paste0("(", paste(months, collapse = "|"), ")")
  time <- "([0-9]{2}):([0-9]{2}):([0-9]{2})"
  forms <- list(
    imf = list(
      pattern = paste0("^", days, ", ([0-9]{2}) ", month, " ([0-9]{4}) ",
                       time, " GMT$"),
      fields = c(day = 2L, month = 3L, year = 4L, hour = 5L)
    ),
    rfc850 = list(
      pattern = paste0("^", long_days, ", ([0-9]{2})-", month, "-([0-9]{2}) ",
                       time, " GMT$"),
      fields = c(day = 2L, month = 3L, year = 4L, hour = 5L)
    ),
    asctime = list(
      pattern = paste0("^", days, " ", month, " ([0-9]{2}| [0-9]) ", time,
                       " ([0-9]{4})$"),
      fields = c(day = 3L, month = 2L, year = 7L, hour = 4L)
    )
  )
  for (name in names(forms)) {
    form <- forms[[name]]
    m <- regmatches(x, regexec(form$pattern, x, perl = TRUE))[[1L]]
    if (length(m) == 0L) {
      next
    }
    m <- m[-1L]
    f <- form$fields
    year <- as.integer(m[[f[["year"]]]])
    month_day <- c(
      match(m[[f[["month"]]]], months), as.integer(m[[f[["day"]]]])
    )
    hms <- as.integer(m[f[["hour"]] + 0:2])
    if (hms[[1L]] > 23L || hms[[2L]] > 59L || hms[[3L]] > 60L) {
      return(NA_real_)
    }
    if (!identical(name, "rfc850")) {
      return(http_date_epoch(year, month_day, hms))
    }
    # RFC 850: the century of `now`, unless that puts the timestamp more than
    # 50 years after `now`; then the century before.
    later <- as.POSIXlt(now, origin = "1970-01-01", tz = "UTC")
    century <- ((later$year + 1900L) %/% 100L) * 100L
    later$year <- later$year + 50L
    target <- http_date_epoch(century + year, month_day, hms)
    if (!is.na(target) && target > as.double(as.POSIXct(later))) {
      target <- http_date_epoch(century - 100L + year, month_day, hms)
    }
    return(target)
  }
  NA_real_
}

# Seconds since the epoch for a UTC calendar time, or NA for a date that does
# not exist (such as 31 February).
http_date_epoch <- function(year, month_day, hms) {
  date <- as.Date(
    sprintf("%04d-%02d-%02d", year, month_day[[1L]], month_day[[2L]]),
    format = "%Y-%m-%d"
  )
  if (is.na(date)) {
    return(NA_real_)
  }
  as.double(date) * 86400 + sum(hms * c(3600, 60, 1))
}
