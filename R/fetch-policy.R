# Deterministic fetch policy for robots_fetch() (PRD 6.4 request/response
# behavior, 6.5 grouping). This file holds the request builder, the HTTP status
# and transport-condition classifiers, the manual redirect loop, and the
# per-outcome error-metadata mapping. It performs NO matching (slice R8) and no
# decoded-byte streaming abort (slice R7); max_bytes is carried, not enforced.

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

# `fetch_user_agent` must be NULL or one non-empty, non-missing character value.
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
  invisible(fetch_user_agent)
}

# Minimal, safe `max_bytes` handling for R6: strict whole-number coercion and
# fractional/overflow call-level errors are slice R7's scope. Here we only store
# the value, coercing to integer when it is already a valid whole number.
coerce_max_bytes <- function(max_bytes) {
  if (is.numeric(max_bytes) && length(max_bytes) == 1L && !is.na(max_bytes) &&
        is.finite(max_bytes) && max_bytes == trunc(max_bytes) &&
        max_bytes <= .Machine$integer.max) {
    return(as.integer(max_bytes))
  }
  NA_integer_
}

# The package fetch user agent (PRD 6.4): package name and version. Never the
# matcher user_agent (robots_fetch has no matcher user agent anyway).
package_fetch_user_agent <- function() {
  paste0("robotstxtr/", as.character(getNamespaceVersion("robotstxtr")))
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

# Classify a transport failure signalled by httr2/curl into timeout, tls_error,
# or network_error (PRD 6.4). httr2 wraps the curl error as the `parent` of an
# `httr2_failure`; curl (>= 5) classes conditions after the CURLcode name (e.g.
# `curl_error_operation_timedout`, `curl_error_peer_failed_verification`). We
# walk the whole condition/parent chain and match on those class names so the
# classification is robust to nesting and testable offline.
classify_transport_condition <- function(cnd) {
  classes <- character(0)
  cur <- cnd
  while (!is.null(cur) && inherits(cur, "condition")) {
    classes <- c(classes, class(cur))
    cur <- cur$parent
  }
  if (any(grepl("timedout|timeout", classes, ignore.case = TRUE))) {
    return("timeout")
  }
  if (any(grepl("ssl|tls|peer_failed_verification|cacert|certificate|cert_",
                classes, ignore.case = TRUE))) {
    return("tls_error")
  }
  "network_error"
}

# --- Per-outcome error metadata (PRD 6.6 error mapping table) ---------------

fetch_error_meta <- function(outcome) {
  switch(outcome,
    fetched = c(stage = NA_character_, class = NA_character_),
    missing = c(stage = NA_character_, class = NA_character_),
    partial_response = c(stage = "response", class = "robots_partial_response"),
    http_error = c(stage = "response", class = "robots_http_error"),
    redirect_error = c(stage = "redirect", class = "robots_redirect_error"),
    timeout = c(stage = "request", class = "robots_timeout"),
    network_error = c(stage = "request", class = "robots_network_error"),
    tls_error = c(stage = "request", class = "robots_tls_error"),
    c(stage = NA_character_, class = NA_character_)
  )
}

# Assemble one source-fetch result (the fields a `robots` row needs, minus the
# grouping-assigned source_id). `body` is a raw vector for `fetched`, else NULL.
make_source_result <- function(outcome, http_status, effective_url,
                               redirect_count, body, error_message) {
  meta <- fetch_error_meta(outcome)
  list(
    fetch_outcome = outcome,
    http_status = if (is.null(http_status)) {
      NA_integer_
    } else {
      as.integer(http_status)
    },
    effective_url = if (is.null(effective_url)) {
      NA_character_
    } else {
      effective_url
    },
    redirect_count = as.integer(redirect_count),
    body = body,
    body_size = if (is.null(body)) NA_integer_ else length(body),
    error_stage = unname(meta[["stage"]]),
    error_class = unname(meta[["class"]]),
    error_message = if (is.null(error_message)) NA_character_ else error_message
  )
}

# --- Request builder --------------------------------------------------------

# Build one clean GET request for a robots URL. The grouping key never carries
# userinfo (robots_origin drops it), and we build a fresh request each hop, so
# no Authorization, cookies, or caller session state is ever forwarded (PRD
# 6.4). Automatic redirect following is disabled so the manual loop can enforce
# the redirect policy; HTTP status is never treated as an error here because
# the response classifier owns status handling.
build_fetch_request <- function(url, timeout, fetch_ua) {
  req <- httr2::request(url)
  req <- httr2::req_method(req, "GET")
  req <- httr2::req_user_agent(req, fetch_ua)
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_options(req, followlocation = FALSE)
  httr2::req_error(req, is_error = function(resp) FALSE)
}

# --- Manual redirect loop + fetch of one origin -----------------------------

# Fetch a single robots URL under the deterministic policy and return a source
# result (see make_source_result). Grouping is by the ORIGINAL requested URL
# (PRD 6.5): the caller keys on `robots_url`, not on the final destination.
perform_fetch <- function(robots_url, timeout, fetch_ua) {
  current_url <- robots_url
  redirect_count <- 0L
  visited <- character(0)

  repeat {
    req <- build_fetch_request(current_url, timeout, fetch_ua)
    resp <- tryCatch(httr2::req_perform(req), error = function(e) e)

    # Transport failure (DNS/connection/TLS/timeout): classify and stop.
    if (inherits(resp, "condition")) {
      outcome <- classify_transport_condition(resp)
      return(make_source_result(
        outcome, NULL, NULL, redirect_count, NULL, conditionMessage(resp)
      ))
    }

    status <- httr2::resp_status(resp)

    # Redirect handling (PRD 6.4). Any 3xx we cannot legally follow, a loop, or
    # exceeding five redirects is a `redirect_error`.
    if (status >= 300L && status <= 399L) {
      loc <- httr2::resp_header(resp, "Location")
      if (is.null(loc) || !nzchar(loc)) {
        return(make_source_result(
          "redirect_error", NULL, NULL, redirect_count, NULL,
          sprintf("HTTP %d redirect without a usable Location header.", status)
        ))
      }
      if (redirect_count >= 5L) {
        return(make_source_result(
          "redirect_error", NULL, NULL, redirect_count, NULL,
          "Exceeded the maximum of five redirects."
        ))
      }
      target <- httr2::url_modify_relative(current_url, loc)
      target_scheme <- tolower(as.character(httr2::url_parse(target)$scheme))
      current_scheme <- tolower(
        as.character(httr2::url_parse(current_url)$scheme)
      )
      if (length(target_scheme) != 1L ||
            !target_scheme %in% c("http", "https")) {
        return(make_source_result(
          "redirect_error", NULL, NULL, redirect_count, NULL,
          sprintf("Redirect to a non-HTTP(S) target (%s).", loc)
        ))
      }
      if (identical(current_scheme, "https") &&
            identical(target_scheme, "http")) {
        return(make_source_result(
          "redirect_error", NULL, NULL, redirect_count, NULL,
          "Rejected an HTTPS-to-HTTP downgrade redirect."
        ))
      }
      if (target %in% c(visited, current_url)) {
        return(make_source_result(
          "redirect_error", NULL, NULL, redirect_count, NULL,
          "Redirect loop detected."
        ))
      }
      visited <- c(visited, current_url)
      current_url <- target
      redirect_count <- redirect_count + 1L
      next
    }

    # Final (non-3xx) response: classify by status.
    outcome <- classify_status(status)
    # An empty 2xx body is a valid `fetched` result (stored as raw(0)); httr2
    # errors on resp_body_raw() for an empty body, so guard with resp_has_body.
    body <- if (identical(outcome, "fetched")) {
      if (httr2::resp_has_body(resp)) httr2::resp_body_raw(resp) else raw(0)
    } else {
      NULL
    }
    return(make_source_result(
      outcome, status, current_url, redirect_count, body, NA_character_
    ))
  }
}
