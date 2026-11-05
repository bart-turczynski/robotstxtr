# robots.txt acquisition through ssrfr (ROBO-jbralthm; the architecture
# review's candidate 4, ROBO-tlvrxtvb).
#
# This module is the only caller of ssrfr. robots_fetch(),
# robots_validate_url(), allowed_by_robots_url() and robots_evaluate_url_v1()
# all reach it through acquire_robots(), which returns the
# make_source_result() shape the rest of the package reads. It owns four
# things:
#
# 1. The policy: one ssrf_policy() per origin, built by acquire_policy().
# 2. The hop loop: prepare, fetch, then robotstxtr's own redirect rules (a
#    missing Location, the loop check, the five-redirect budget) and
#    classify_status() on the final response.
# 3. The translation tables, as data: ssrfr's refusal codes to robotstxtr's
#    (fetch_outcome, terminal_redirect_reason, safety_block_reason), and its
#    failure causes to transport_error_kind. A test walks
#    ssrf_vocabulary("reason_codes") and ssrf_vocabulary("causes") in full, so
#    a code ssrfr adds fails a test instead of falling through.
# 4. ssrfr's misuse errors, which become a robotstxtr error class.
#
# ssrfr resolves a name once and pins the connection to the validated
# addresses, so the guard covers what is dialed, not only what is spelled.
# robotstxtr keeps translating ssrfr's refusals into its own published reason
# codes (design/engine-profiles.md section 2).

# --- The ssrfr boundary -------------------------------------------------------

# The two ssrfr primitives, called through these wrappers only. They are the
# seam the tests replace with a fake (tests/testthat/helper-fake-ssrfr.R), so a
# test drives the hop loop with scripted responses and no network.
acquire_prepare_hop <- function(url, policy, request = NULL, from = NULL) {
  ssrfr::ssrf_prepare_hop(url, policy, request = request, from = from)
}

acquire_fetch <- function(binding) {
  ssrfr::ssrf_fetch(binding)
}

# Run one ssrfr call, turning a misuse error (class `ssrfr_error`) into a
# robotstxtr error. Arguments are validated before they reach ssrfr, so this
# signals a defect in this module rather than bad caller input.
acquire_call <- function(expr) {
  tryCatch(expr, ssrfr_error = function(e) {
    robots_abort(
      paste0("ssrfr refused the acquisition request: ", conditionMessage(e)),
      "robotstxtr_acquisition_error"
    )
  })
}

# --- Policy -------------------------------------------------------------------

# Redirects followed per origin. PRD 6.4 and RFC 9309 section 2.3.1.2: at least
# five consecutive redirects.
acquire_redirect_limit <- 5L

# The response header limits per hop (acquire_policy()).
acquire_max_header_bytes <- 65536L
acquire_max_header_fields <- 256L

# The policy for one origin's chain.
#
# - `max_redirects` is the budget plus one, so the sixth 3xx comes back as a
#   response and robotstxtr records it as `over_budget` with its Location,
#   instead of as ssrfr's "redirect-limit" refusal, which carries none.
# - `total_timeout` is chain-scoped in ssrfr: fixed by the first hop and
#   inherited through `from`, which is one origin's chain. A fractional
#   `timeout` is rounded up to whole seconds.
# - `allow_ports = 1:65535` keeps the any-port behavior robotstxtr has always
#   had; port 0 is still refused as "port".
# - The response header may take 64 KiB and 256 fields, four and two times
#   ssrfr's defaults: large news and CDN sites send 20 KB of header, and a
#   header over its limit is a `network_error` with no status.
# - `ssrf_guard = FALSE` is deprecated. ssrfr has no off switch, so it
#   becomes a permissive policy: every address range reopened, and the
#   metadata host names. Exact provider endpoints, and the transition and
#   embedded forms ssrfr refuses whatever the policy, stay refused.
acquire_policy <- function(timeout, fetch_ua, max_bytes, ssrf_guard = TRUE) {
  total <- max(1, ceiling(timeout))
  args <- list(
    allow_ports = 1:65535,
    max_redirects = acquire_redirect_limit + 1L,
    connect_timeout = min(3, total),
    total_timeout = total,
    max_response_size = max_bytes,
    max_header_bytes = acquire_max_header_bytes,
    max_header_fields = acquire_max_header_fields,
    user_agent = fetch_ua
  )
  if (!isTRUE(ssrf_guard)) {
    args$allow_ranges <- c("0.0.0.0/0", "::/0")
    args$allow_hosts <- ssrfr::ssrf_vocabulary("metadata_hostnames")$hostname
  }
  acquire_call(do.call(ssrfr::ssrf_policy, args))
}

# --- Results ------------------------------------------------------------------

# The result for a refusal (`x` of class `ssrfr_refusal`). `redirect` is the
# 3xx context when the refused hop is a redirect target: a list of the
# response `status` and its `location`, or NULL on the first hop.
acquire_refusal_result <- function(x, redirect_count, redirect_hops,
                                   redirect = NULL) {
  row <- acquire_refusal_row(x$code)
  if (is.null(redirect)) {
    outcome <- row$fetch_outcome
    terminal <- row$terminal_redirect_reason
  } else {
    outcome <- row$redirect_fetch_outcome
    terminal <- row$redirect_terminal_redirect_reason
  }
  # A refusal the redirect itself causes (its scheme, its downgrade, the
  # budget) ends the chain at the 3xx, which the result records with its
  # Location. A refused target address ends it one hop further on, as a
  # redirect that was followed and then blocked.
  at_redirect <- !is.null(redirect) && terminal != "none"
  if (!is.null(redirect) && !at_redirect) {
    redirect_count <- redirect_count + 1L
  }
  make_source_result(
    outcome, NULL, NULL, redirect_count, NULL,
    acquire_refusal_message(x$code, terminal),
    redirect_hops = redirect_hops,
    terminal_redirect_reason = terminal,
    location_header = if (at_redirect) redirect$location else NA_character_,
    safety_block_reason = row$safety_block_reason,
    final_http_status = if (at_redirect) redirect$status else NULL
  )
}

acquire_refusal_message <- function(code, terminal) {
  switch(terminal,
    non_http_target = "Redirect to a non-HTTP(S) target.",
    downgrade = "Rejected an HTTPS-to-HTTP downgrade redirect.",
    over_budget = "Exceeded the maximum of five redirects.",
    sprintf("Blocked by SSRF guard (%s).", code)
  )
}

# The result for a failure (`x` of class `ssrfr_failure`).
#
# ssrfr applies `max_response_size` to every response's body, so a decoded
# body over `max_bytes` is classified by the status it carries: a 4xx or 5xx
# as classify_status() says, as if the body had fit, since its body is never
# read anyway. A 2xx, a 3xx (ssrfr records no Location for it, so it cannot
# be followed) and an unknown status are `body_too_large`, keeping the final
# status and URL; ssrfr never returns any of that body, so nothing is stored
# and `body_truncated` stays FALSE.
#
# ssrfr fails a response with more than one Location field as
# "protocol-error" with check "location", whatever its status. On a 3xx that
# is the redirect without a usable Location it would have been. On any other
# status ssrfr has refused the body, so it stays a `network_error`.
acquire_failure_result <- function(x, binding, redirect_count, redirect_hops,
                                   max_bytes) {
  if (identical(x$cause, "protocol-error") &&
        identical(x$detail$check, "location")) {
    status <- binding$state$status
    if (!is.null(status) && status >= 300L && status <= 399L) {
      return(acquire_no_location_result(
        binding$url, as.integer(status), redirect_count, redirect_hops
      ))
    }
  }
  row <- acquire_cause_row(x$cause, x$detail$check)
  if (identical(row$fetch_outcome, "body_too_large")) {
    observed <- x$detail$observed_bytes
    status <- x$detail$status
    if (is.null(status)) {
      status <- binding$state$status
    }
    if (!is.null(status) && status >= 400L) {
      return(make_source_result(
        classify_status(as.integer(status)), status, binding$url,
        redirect_count, NULL, NA_character_,
        redirect_hops = redirect_hops
      ))
    }
    return(make_source_result(
      "body_too_large", status, binding$url, redirect_count, NULL,
      sprintf(
        "Decoded response body exceeded the %d-byte limit (max_bytes).",
        max_bytes
      ),
      redirect_hops = redirect_hops,
      observed_bytes = if (is.null(observed)) NA_integer_ else observed,
      termination_reason = "ceiling"
    ))
  }
  make_source_result(
    row$fetch_outcome, NULL, NULL, redirect_count, NULL,
    sprintf("Fetch failed (%s).", x$cause),
    redirect_hops = redirect_hops,
    transport_error_kind = row$fetch_outcome
  )
}

# A refusal or failure from ssrfr, as a result. `binding` is the hop that was
# being fetched, NULL when the outcome came from preparing a hop.
acquire_outcome_result <- function(x, binding, redirect_count, redirect_hops,
                                   max_bytes, redirect = NULL) {
  if (inherits(x, "ssrfr_refusal")) {
    if (identical(x$code, "redirect-limit")) {
      redirect <- list(
        status = binding$state$status, location = NA_character_
      )
    }
    return(acquire_refusal_result(x, redirect_count, redirect_hops, redirect))
  }
  if (inherits(x, "ssrfr_failure")) {
    if (!is.null(redirect)) {
      redirect_count <- redirect_count + 1L
    }
    return(acquire_failure_result(
      x, binding, redirect_count, redirect_hops, max_bytes
    ))
  }
  robots_abort(
    "ssrfr returned an outcome of an unknown class.",
    "robotstxtr_acquisition_invariant"
  )
}

# The URL a Location points at, for the redirect-hop log only. ssrfr decides
# where the next hop goes; this is the same WHATWG resolution, kept so a hop
# that is not followed (the budget, a refusal) still names its target.
acquire_location_target <- function(location, base) {
  target <- tryCatch(
    rurl::resolve_url(
      location, base, url_standard = "whatwg", output = "serialized"
    ),
    error = function(e) NA_character_
  )
  if (length(target) != 1L || is.na(target) || !nzchar(target)) {
    return(location)
  }
  target
}

acquire_followable <- function(status) {
  status %in% c(301L, 302L, 303L, 307L, 308L)
}

# A 3xx from `url` that names no target: not a followable status, an empty
# Location, or several Location fields.
acquire_no_location_result <- function(url, status, redirect_count,
                                       redirect_hops) {
  redirect_hops[[length(redirect_hops) + 1L]] <- list(
    from_url = url, status = status, location_target = NA_character_
  )
  make_source_result(
    "redirect_error", NULL, NULL, redirect_count, NULL,
    sprintf("HTTP %d redirect without a usable Location header.", status),
    redirect_hops = redirect_hops,
    terminal_redirect_reason = "no_location",
    final_http_status = status
  )
}

acquire_loop_result <- function(location, status, redirect_count,
                                redirect_hops) {
  make_source_result(
    "redirect_error", NULL, NULL, redirect_count, NULL,
    "Redirect loop detected.",
    redirect_hops = redirect_hops,
    terminal_redirect_reason = "loop",
    location_header = location,
    final_http_status = status
  )
}

# --- The hop loop -------------------------------------------------------------

# Fetch one robots URL and return a source result (make_source_result()).
# Grouping is by the requested URL (PRD 6.5): the caller keys on `robots_url`,
# not on where the redirects lead. `max_bytes` is the validated integer limit
# on decoded body bytes.
acquire_robots <- function(robots_url, timeout, fetch_ua, max_bytes,
                           ssrf_guard = TRUE) {
  policy <- acquire_policy(timeout, fetch_ua, max_bytes, ssrf_guard)
  redirect_count <- 0L
  redirect_hops <- list()
  visited <- character(0)

  binding <- acquire_call(acquire_prepare_hop(
    robots_url, policy, request = list()
  ))
  if (!inherits(binding, "ssrfr_binding")) {
    return(acquire_outcome_result(
      binding, NULL, redirect_count, redirect_hops, max_bytes
    ))
  }

  repeat {
    response <- acquire_call(acquire_fetch(binding))
    if (!inherits(response, "ssrfr_response")) {
      return(acquire_outcome_result(
        response, binding, redirect_count, redirect_hops, max_bytes
      ))
    }
    status <- as.integer(response$status)

    if (status < 300L || status > 399L) {
      return(acquire_final_result(
        response, status, binding$url, redirect_count, redirect_hops
      ))
    }

    # A 3xx. Only a 301, 302, 303, 307 or 308 with a non-empty Location is
    # followed. ssrfr returns a response with at most one Location field
    # (several are a failure, acquire_failure_result()).
    location <- binding$state$location
    if (!acquire_followable(status) || is.null(location) || !nzchar(location)) {
      return(acquire_no_location_result(
        binding$url, status, redirect_count, redirect_hops
      ))
    }
    target <- acquire_location_target(location, binding$url)
    redirect_hops[[length(redirect_hops) + 1L]] <- list(
      from_url = binding$url, status = status, location_target = target
    )
    if (redirect_count >= acquire_redirect_limit) {
      return(make_source_result(
        "redirect_error", NULL, NULL, redirect_count, NULL,
        "Exceeded the maximum of five redirects.",
        redirect_hops = redirect_hops,
        terminal_redirect_reason = "over_budget",
        location_header = location,
        final_http_status = status
      ))
    }

    # The loop check runs after the hop is prepared, on the URL ssrfr will
    # request, so a refusal of the target (a downgrade) wins over a loop.
    redirect <- list(status = status, location = location)
    following <- acquire_call(acquire_prepare_hop(
      location, policy, from = binding
    ))
    if (!inherits(following, "ssrfr_binding")) {
      return(acquire_outcome_result(
        following, binding, redirect_count, redirect_hops, max_bytes,
        redirect = redirect
      ))
    }
    if (following$url %in% c(visited, binding$url)) {
      return(acquire_loop_result(
        location, status, redirect_count, redirect_hops
      ))
    }
    visited <- c(visited, binding$url)
    redirect_count <- redirect_count + 1L
    binding <- following
  }
}

# The result for a final (non-3xx) response. Only `fetched` stores a body: the
# exact decoded bytes ssrfr read, within `max_bytes` (an empty body is raw(0)).
acquire_final_result <- function(response, status, url, redirect_count,
                                 redirect_hops) {
  outcome <- classify_status(status)
  if (!identical(outcome, "fetched")) {
    return(make_source_result(
      outcome, status, url, redirect_count, NULL, NA_character_,
      redirect_hops = redirect_hops
    ))
  }
  body <- response$body
  if (is.null(body)) {
    body <- raw(0)
  }
  make_source_result(
    "fetched", status, url, redirect_count, body, NA_character_,
    redirect_hops = redirect_hops
  )
}
