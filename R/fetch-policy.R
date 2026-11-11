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
#
# RFC 9309 section 2.5 sets a parsing limit of at least 500 KiB (512000
# bytes). The default, 524288, meets it. A smaller value stays accepted (tests
# and callers bound memory with one) and is documented as below the RFC 9309
# floor rather than refused (ROBO-ldpahknv).
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

# `safety_level` must be one value of engine_safety_levels_v1() (ADR 0001
# section 1).
validate_safety_level <- function(safety_level) {
  levels <- engine_safety_levels_v1()
  if (!is.character(safety_level) || length(safety_level) != 1L ||
        is.na(safety_level) || !safety_level %in% levels) {
    robots_abort(
      sprintf(
        "`safety_level` must be one of %s.",
        paste0("\"", levels, "\"", collapse = ", ")
      ),
      "robotstxtr_invalid_safety_level"
    )
  }
  invisible(unname(safety_level))
}

# `fetch_allow_ranges` must be a character vector of CIDR ranges (ADR 0001
# section 6), `character()` by default: no NA, no empty string, each entry one
# that ssrfr accepts as an `allow_ranges` entry. It is checked here, before
# anything reaches ssrfr, so a bad entry is the caller's error rather than an
# acquisition defect (acquire_call()).
#
# With `ssrf_guard = FALSE` a non-empty value is a call-level error, of the
# `ssrf_guard` class, whatever the entries are: the call gives two answers to
# the same question.
#
# An entry under which ssrfr would admit one of its provider endpoints is
# refused too: ssrfr reopens an endpoint for an exact allow entry, and
# section 6 keeps those endpoints refused whatever the caller lists.
#
# Returns the ranges as a plain character vector, as passed (no names or
# dimensions, no sorting, no deduplication).
validate_fetch_allow_ranges <- function(fetch_allow_ranges, ssrf_guard) {
  invalid <- function(detail) {
    robots_abort(
      paste(
        "`fetch_allow_ranges` must be a character vector of CIDR ranges, such",
        "as \"10.0.0.0/8\" or \"fd00::/8\", with no host bits set.", detail
      ),
      "robotstxtr_invalid_fetch_allow_ranges"
    )
  }
  if (isFALSE(ssrf_guard) && length(fetch_allow_ranges) > 0L) {
    robots_abort(
      paste(
        "`ssrf_guard = FALSE` cannot be combined with a non-empty",
        "`fetch_allow_ranges`. Drop `ssrf_guard = FALSE`: the listed ranges",
        "are reopened on their own."
      ),
      "robotstxtr_invalid_ssrf_guard"
    )
  }
  if (!is.character(fetch_allow_ranges)) {
    invalid("It is not a character vector.")
  }
  ranges <- as.character(unname(fetch_allow_ranges))
  for (i in seq_along(ranges)) {
    entry <- ranges[[i]]
    if (is.na(entry) || !nzchar(entry)) {
      invalid(sprintf("Entry %d is missing or empty.", i))
    }
    # A CIDR range is printable ASCII; checked by bytes, so an entry in
    # another encoding or with invalid UTF-8 never reaches ssrfr.
    if (!grepl("^[!-~]+$", entry, useBytes = TRUE)) {
      invalid(sprintf("Entry %d is not a range.", i))
    }
    policy <- tryCatch(
      ssrfr::ssrf_policy(allow_ranges = entry),
      ssrfr_error_invalid_policy = function(e) {
        invalid(sprintf("Entry %d is not a range.", i))
      }
    )
    if (fetch_range_admits_provider_endpoint(policy)) {
      robots_abort(
        sprintf(
          paste(
            "`fetch_allow_ranges` entry \"%s\" would reopen a cloud provider",
            "metadata endpoint, which stays refused (ADR 0001 section 6)."
          ),
          entry
        ),
        "robotstxtr_invalid_fetch_allow_ranges"
      )
    }
  }
  # The entries are also checked together, as the fetch uses them: the check
  # must not rest on endpoint admission being the union of each entry's.
  if (length(ranges) > 1L &&
        fetch_range_admits_provider_endpoint(
          fetch_endpoint_check(ssrfr::ssrf_policy(allow_ranges = ranges))
        )) {
    robots_abort(
      paste(
        "`fetch_allow_ranges` together would reopen a cloud provider metadata",
        "endpoint, which stays refused (ADR 0001 section 6)."
      ),
      "robotstxtr_invalid_fetch_allow_ranges"
    )
  }
  ranges
}

# The addresses of ssrfr's provider-endpoint vocabulary. An empty or missing
# vocabulary is an error, so the endpoint check fails closed rather than
# passing every entry.
fetch_provider_endpoint_addresses <- function() {
  addresses <- fetch_endpoint_check(
    ssrfr::ssrf_vocabulary("provider_endpoints")$address
  )
  if (!is.character(addresses) || length(addresses) == 0L ||
        anyNA(addresses)) {
    robots_abort(
      paste(
        "Cannot check `fetch_allow_ranges`: ssrfr's provider-endpoint",
        "vocabulary is empty or unreadable, so no range is accepted."
      ),
      "robotstxtr_invalid_fetch_allow_ranges"
    )
  }
  addresses
}

# Runs one step of the endpoint check, turning any error it raises (ssrfr's
# included) into the classed refusal: the check fails closed, never open.
fetch_endpoint_check <- function(expr) {
  tryCatch(expr, error = function(e) {
    if (inherits(e, "robotstxtr_invalid_fetch_allow_ranges")) {
      stop(e)
    }
    robots_abort(
      paste(
        "Cannot check `fetch_allow_ranges` against ssrfr's provider",
        "endpoints, so no range is accepted:", conditionMessage(e)
      ),
      "robotstxtr_invalid_fetch_allow_ranges"
    )
  })
}

# TRUE when `policy`, built from `fetch_allow_ranges` entries, admits any
# address of ssrfr's provider-endpoint vocabulary, all of which its default
# policy refuses as `cloud-metadata`. A probe ssrfr refuses for any other
# reason proves nothing about the endpoint, so it is an error, not a pass.
fetch_range_admits_provider_endpoint <- function(policy) {
  for (address in fetch_provider_endpoint_addresses()) {
    ipv6 <- grepl(":", address, fixed = TRUE)
    url <- sprintf(if (ipv6) "http://[%s]/" else "http://%s/", address)
    code <- fetch_endpoint_check(ssrfr::ssrf_inspect_url(url, policy)$code)
    if (is.na(code)) {
      return(TRUE)
    }
    if (!identical(code, "cloud-metadata")) {
      robots_abort(
        sprintf(
          paste(
            "Cannot check `fetch_allow_ranges`: ssrfr refused its provider",
            "endpoint %s as \"%s\", not as cloud-metadata, so no range is",
            "accepted."
          ),
          address, code
        ),
        "robotstxtr_invalid_fetch_allow_ranges"
      )
    }
  }
  FALSE
}

# The deprecation warning for `ssrf_guard = FALSE`, raised once per call by the
# public entry points that fetch: robots_fetch() (which allowed_by_robots_url()
# and robots_validate_url() call) and robots_evaluate_url_v1(). Under
# `safety_level = "crawler"` a second warning follows, of its own class: the
# deprecated switch makes internal addresses reachable, which no public
# crawler can do (ADR 0001 section 6).
warn_ssrf_guard_deprecated <- function(ssrf_guard, safety_level = "strict") {
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
        "`ssrf_guard = FALSE` is deprecated; use `fetch_allow_ranges` to",
        "reopen the ranges you need. It no longer turns the guard off:",
        "private and loopback addresses are reopened, but cloud metadata",
        "endpoints and IPv6 transition forms stay refused."
      ),
      call = NULL
    )
  ))
  if (identical(safety_level, "crawler")) {
    warning(structure(
      class = c("robotstxtr_ssrf_guard_crawler", "warning", "condition"),
      list(
        message = paste(
          "`ssrf_guard = FALSE` under `safety_level = \"crawler\"` makes",
          "private and loopback addresses reachable, which no public crawler",
          "can do; they are dialed, not recorded as unreachable."
        ),
        call = NULL
      )
    ))
  }
  invisible(NULL)
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
# `body_truncated` is TRUE only on a `fetched` row whose 2xx body was over
# `max_bytes`: ssrfr's `truncate_body` returns its first `max_bytes` decoded
# bytes, which are stored and matched (RFC 9309 section 2.5, ROBO-ldpahknv),
# with `termination_reason = "ceiling"` and ssrfr's `observed_bytes`
# (acquire_final_result()). Every other body over `max_bytes` is refused whole:
# on a 3xx, an unknown status or a 2xx whose libcurl and status-line statuses
# disagree it is `fetch_outcome = "body_too_large"` with `termination_reason =
# "ceiling"`; a 4xx or 5xx keeps its status outcome (acquire_failure_result()).
make_source_result <- function(outcome, http_status, effective_url,
                               redirect_count, body, error_message,
                               redirect_hops = list(),
                               terminal_redirect_reason = "none",
                               location_header = NA_character_,
                               observed_bytes = NULL,
                               body_truncated = FALSE,
                               transport_error_kind = NA_character_,
                               safety_block_reason = NA_character_,
                               termination_reason = "none",
                               final_http_status = NULL,
                               retry_after = NA_character_,
                               retry_after_seconds = NA_real_,
                               content_type = NA_character_,
                               content_flag = NA_character_) {
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
    body_truncated = body_truncated,
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
    retry_after_seconds = as.double(retry_after_seconds),
    content_type = content_type,
    content_flag = content_flag
  )
}

# --- A cut body's complete lines (ROBO-ldpahknv) -----------------------------

# The bytes of `body` up to and including its last CR or LF; raw(0) when it
# has none. A body cut at `max_bytes` usually ends inside a line, and that
# partial line would be read as a rule of its own ("Disallow: /private/" cut
# to "Disallow: /"), so matching and validation read only the complete lines.
# The stored body keeps every byte ssrfr returned.
complete_lines_prefix <- function(body) {
  breaks <- which(body == as.raw(0x0a) | body == as.raw(0x0d))
  if (length(breaks) == 0L) {
    return(raw(0))
  }
  body[seq_len(max(breaks))]
}

# The bytes of a stored body that matching and validation read: the whole
# body, or a cut body's complete lines.
readable_body <- function(body, body_truncated) {
  if (isTRUE(body_truncated)) complete_lines_prefix(body) else body
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
