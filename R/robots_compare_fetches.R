#' Compare robots.txt responses across explicitly selected fetch variants
#'
#' An opt-in audit: fetches robots.txt once per planned observation of the
#' variants you supply, under a hard request budget, and reports how the
#' responses differ. It is meant for spotting a CDN or firewall that answers
#' differently by HTTP User-Agent, by origin variant (`http` or `https`, `www`
#' or the bare host, a port) or over time. The other fetching functions make
#' one request chain per origin (a request and up to five redirects); this
#' one may make several, as `variants` asks, up to `max_requests` requests.
#'
#' Each variant's `url` is reduced to its robots.txt URL as [robots_fetch()]
#' reduces it (`scheme://host[:port]/robots.txt`). Scheme, host and port stay
#' part of that URL, so `http://example.com/`, `https://example.com/` and
#' `https://www.example.com/` are separate robots.txt scopes, each read on its
#' own by a crawler (RFC 9309 section 2.3). A difference between them is
#' evidence about what each scope serves, not a configuration error: two
#' scopes may rightly serve different rules. A URL with no robots.txt URL
#' (missing, malformed, not `http` or `https`) is never fetched; its
#' observations have `observation_status = "input_invalid"`.
#'
#' A variant's `fetch_user_agent` is the HTTP `User-Agent` header the request
#' sends, a plain string you supply; the package keeps no list of crawler
#' strings. It is not a crawler identity and not the robots.txt product token
#' that `User-agent:` lines match. A server cannot tell a spoofed header from a
#' real crawler by the header alone, and many check the crawler's address, so
#' a response to a spoofed agent proves nothing about what verified Googlebot,
#' Bingbot or YandexBot receive. Treat a difference by agent as a lead to
#' check, not as what a crawler sees.
#'
#' Every request follows the [robots_fetch()] policy and its \pkg{ssrfr}
#' guard: the same redirect rules, size limit, timeout and refusals. A refused
#' origin makes no request. Nothing is cached between observations, and no
#' allow or disallow decision is computed: read a body with [robots_body()]
#' on the observation's `body`, or match it with [allowed_by_robots_text()].
#'
#' @section Request budget and order:
#' `max_requests` bounds every outbound HTTP request of the call: each
#' observation's first request, every redirect hop it follows, and every
#' repeat. It is checked before each request, never after, so the call makes
#' at most `max_requests` requests; and before the request's host name is
#' looked up, so a spent budget causes no network activity at all.
#' Observations run in round-robin passes:
#' every variant once, in row order, then a second pass over the variants with
#' `repeats` of at least 2, and so on. So the budget goes to every variant
#' once before it goes to any repeat. An observation whose chain the budget
#' cuts part way, after a redirect, has `observation_status =
#' "budget_exhausted"` and keeps the hops it made; one never started for lack
#' of budget has `"not_requested"`. A refusal by the guard, before any
#' request, spends nothing; a redirect to a refused target spends the request
#' that returned the redirect.
#'
#' @section Comparison:
#' Bodies are compared byte for byte, never through a hash. Each stored body
#' gets a `body_label` local to this report: `"body_1"`, `"body_2"`, and so
#' on, in order of first occurrence, and observations with identical bytes
#' share a label (an empty body is a body too). A body cut at `max_bytes`
#' (`body_truncated = TRUE`) is never equal to anything, an identical cut
#' body included, since the bytes after the cut are unknown: it always gets a
#' label of its own. `body_label` is `NA` when there is no stored body.
#'
#' `comparison` counts the distinct values of `fetch_outcome`, `http_status`,
#' `effective_url`, `redirect_count`, `terminal_redirect_reason`,
#' `body_label`, `body_size`, `content_type` and `content_flag` over the
#' completed observations, those with `observation_status` `"response"`,
#' `"acquisition_failure"` or `"refused"`. `NA` counts as a value. The seven
#' cache columns are kept on `observations` but not compared: `date` and
#' `age` differ from one request to the next by nature.
#'
#' `observation_status` keeps a transient failure apart from a content
#' difference: `"response"` (the server answered, whatever its status,
#' redirect errors and a body over `max_bytes` included),
#' `"acquisition_failure"` (a timeout, TLS or network failure, which may not
#' recur), `"refused"` (the
#' guard refused the origin or a redirect target), `"budget_exhausted"`,
#' `"not_requested"` or `"input_invalid"`. Two observations of one variant
#' that differ only because one timed out differ in status, not in body.
#'
#' @param variants The variants to fetch: a character vector of URLs
#'   (shorthand for `data.frame(url = variants)`), or a data frame with a
#'   character column `url` and optional columns `fetch_user_agent` (the HTTP
#'   `User-Agent` to send; `NA`, or no column, sends the package agent
#'   `robotstxtr/<version>`; each other value must be a valid HTTP field
#'   value, as in [robots_fetch()]), `label` (a name for the report; `NA`, or
#'   no column, gives `"variant_<i>"`) and `repeats` (how many observations of
#'   the variant to make, a whole number of at least 1; 1 when absent). Any
#'   other column, a misspelled one included, is a call-level error. A
#'   variant is one row: list a URL twice with different agents to compare the
#'   agents. `sum(repeats)`, the number of planned observations, may be at
#'   most 10000. May have zero rows. Every check runs before any request, and
#'   a bad value is a call-level error.
#' @param max_requests The request budget: a single positive, finite,
#'   whole-number value no greater than `.Machine$integer.max`. Required; it
#'   bounds every outbound request, redirect hops and repeats included.
#' @inheritParams robots_fetch
#'
#' @return An S3 object of class `robots_fetch_comparison`: a list of
#'   `observations` and `comparison`.
#'
#'   `observations` has one row per planned observation, in request order:
#'   `observation_id`, `variant_id` (the variant's row), `label`,
#'   `repeat_index` (1 for the first observation of a variant, 2 for its
#'   first repeat, ...), `url`, `robots_url`, `http_user_agent` (the
#'   `User-Agent` sent, or that would have been sent), `fetched_at` (a UTC
#'   `POSIXct` taken as the observation started; `NA` when not started),
#'   `observation_status`, then the fetch result as [robots_fetch()]'s
#'   `robots` rows carry it: `fetch_outcome` (`"budget_exhausted"` for a chain
#'   the budget cut, `"input_invalid"` for an invalid URL, `NA` when not
#'   requested), `http_status`, `effective_url`, `redirect_count`,
#'   `terminal_redirect_reason`, `safety_block_reason`,
#'   `transport_error_kind`, `error_message`, `body_label`, `body_size`,
#'   `body_truncated`, `observed_bytes`, `content_type`, `content_flag`, the
#'   seven raw cache columns `cache_control`, `age`, `date`, `expires`,
#'   `etag`, `last_modified` and `vary`, and the list columns `redirect_hops`
#'   and `body` (the exact stored bytes, `NULL` when none).
#'
#'   `comparison` has one row per compared field: `field`, `n_distinct` and
#'   the list column `values`, the distinct values in order of first
#'   occurrence.
#'
#'   The attributes `max_requests` and `requests_made` record the budget and
#'   how much of it the call spent.
#'
#' @examples
#' # A refused origin and an invalid URL make no request, so this runs
#' # offline and spends none of the budget.
#' robots_compare_fetches(c("http://127.0.0.1/", "not-a-url"), max_requests = 4)
#'
#' \dontrun{
#' # Live HTTP: the https and http scopes, and one https fetch repeated with
#' # another User-Agent header. At most 8 requests, redirects included.
#' robots_compare_fetches(
#'   data.frame(
#'     url = c(
#'       "https://example.com/", "http://example.com/", "https://example.com/"
#'     ),
#'     fetch_user_agent = c(NA, NA, "Mozilla/5.0 (compatible; audit)"),
#'     repeats = c(2, 1, 1)
#'   ),
#'   max_requests = 8
#' )
#' }
#'
#' @seealso [robots_fetch()] for the single fetch per origin the other
#'   functions make.
#' @export
robots_compare_fetches <- function(variants, max_requests, timeout = 10,
                                   max_bytes = 524288L,
                                   safety_level = "strict",
                                   fetch_allow_ranges = character()) {
  max_requests <- validate_max_requests(max_requests)
  variants <- validate_variants(variants)
  controls <- list(
    timeout = validate_timeout(timeout),
    max_bytes = validate_max_bytes(max_bytes),
    safety_level = validate_safety_level(safety_level),
    fetch_allow_ranges = validate_fetch_allow_ranges(fetch_allow_ranges, TRUE)
  )
  plan <- compare_plan(variants)
  budget <- new.env(parent = emptyenv())
  budget$remaining <- max_requests
  observed <- compare_run(plan, controls, budget)
  observations <- compare_observation_frame(plan, observed)
  structure(
    list(
      observations = observations,
      comparison = compare_differences(observations)
    ),
    class = "robots_fetch_comparison",
    max_requests = max_requests,
    requests_made = max_requests - budget$remaining,
    package_version = as.character(getNamespaceVersion("robotstxtr"))
  )
}

# --- Plan -------------------------------------------------------------------

# One row per planned observation, in request order: round-robin passes, so
# pass p holds every variant with at least p repeats, in row order.
compare_plan <- function(variants) {
  n <- nrow(variants)
  variant_id <- rep(seq_len(n), variants$repeats)
  repeat_index <- sequence(variants$repeats)
  ord <- order(repeat_index, variant_id)
  variant_id <- variant_id[ord]
  robots_url <- vapply(
    variants$url, robots_origin, character(1L), USE.NAMES = FALSE
  )
  agent <- variants$fetch_user_agent
  agent[is.na(agent)] <- package_fetch_user_agent()
  data.frame(
    observation_id = seq_along(variant_id),
    variant_id = variant_id,
    label = variants$label[variant_id],
    repeat_index = repeat_index[ord],
    url = variants$url[variant_id],
    robots_url = robots_url[variant_id],
    http_user_agent = agent[variant_id],
    stringsAsFactors = FALSE
  )
}

# --- Observe ----------------------------------------------------------------

# Every planned observation, in plan order: a list of its status, start time
# and source result (NULL when nothing was requested). Each starts as
# `not_requested` (`input_invalid` without a robots URL), in one step; the
# valid ones are then observed in order until the budget is spent, so no
# work is done per observation once it is.
compare_run <- function(plan, controls, budget) {
  unrun <- function(status) {
    list(status = status, fetched_at = NA_real_, result = NULL)
  }
  invalid <- is.na(plan$robots_url)
  observed <- rep(list(unrun("not_requested")), nrow(plan))
  observed[invalid] <- list(unrun("input_invalid"))
  for (i in which(!invalid)) {
    if (budget$remaining < 1L) {
      break
    }
    observed[[i]] <- compare_observe(
      plan$robots_url[[i]], plan$http_user_agent[[i]], controls, budget
    )
  }
  observed
}

# One observation of `robots_url`, sending `agent`.
compare_observe <- function(robots_url, agent, controls, budget) {
  fetched_at <- acquire_now()
  result <- acquire_robots(
    robots_url, controls$timeout, agent, controls$max_bytes,
    TRUE, controls$safety_level, controls$fetch_allow_ranges,
    budget = budget
  )
  list(
    status = compare_status(result), fetched_at = fetched_at, result = result
  )
}

# The observation status of a source result.
compare_status <- function(result) {
  if (identical(result$fetch_outcome, "budget_exhausted")) {
    return("budget_exhausted")
  }
  if (!is.na(result$safety_block_reason)) {
    return("refused")
  }
  if (!is.na(result$transport_error_kind)) {
    return("acquisition_failure")
  }
  "response"
}

# --- Report -----------------------------------------------------------------

# One field of every observation's result, `na` where there is none.
compare_field <- function(observed, name, na) {
  vapply(observed, function(o) {
    if (is.null(o$result)) na else o$result[[name]]
  }, na)
}

compare_outcomes <- function(observed) {
  outcome <- compare_field(observed, "fetch_outcome", NA_character_)
  status <- vapply(observed, function(o) o$status, character(1L))
  outcome[status == "input_invalid"] <- "input_invalid"
  outcome
}

compare_result_columns <- function(observed) {
  text_of <- function(f) compare_field(observed, f, NA_character_)
  list(
    http_status = compare_field(observed, "http_status", NA_integer_),
    effective_url = text_of("effective_url"),
    redirect_count = compare_field(observed, "redirect_count", NA_integer_),
    terminal_redirect_reason = text_of("terminal_redirect_reason"),
    safety_block_reason = text_of("safety_block_reason"),
    transport_error_kind = text_of("transport_error_kind"),
    error_message = text_of("error_message")
  )
}

compare_body_columns <- function(observed) {
  bodies <- lapply(observed, function(o) o$result$body)
  truncated <- compare_field(observed, "body_truncated", NA)
  list(
    body_label = compare_body_labels(bodies, truncated),
    body_size = compare_field(observed, "body_size", NA_integer_),
    body_truncated = truncated,
    observed_bytes = compare_field(observed, "observed_bytes", NA_integer_),
    content_type = compare_field(observed, "content_type", NA_character_),
    content_flag = compare_field(observed, "content_flag", NA_character_)
  )
}

compare_cache_columns <- function(observed) {
  cols <- lapply(names(cache_header_fields), function(f) {
    compare_field(observed, f, NA_character_)
  })
  names(cols) <- names(cache_header_fields)
  cols
}

compare_observation_frame <- function(plan, observed) {
  fetched_at <- vapply(observed, function(o) o$fetched_at, numeric(1L))
  frame <- data.frame(
    plan,
    fetched_at = .POSIXct(fetched_at, tz = "UTC"),
    observation_status = vapply(observed, function(o) o$status, character(1L)),
    fetch_outcome = compare_outcomes(observed),
    compare_result_columns(observed),
    compare_body_columns(observed),
    compare_cache_columns(observed),
    stringsAsFactors = FALSE
  )
  frame$redirect_hops <- lapply(observed, function(o) {
    if (is.null(o$result)) list() else o$result$redirect_hops
  })
  frame$body <- lapply(observed, function(o) o$result$body)
  frame
}

# Report-local body labels, byte for byte: identical() raw bodies share a
# label in first-occurrence order; a truncated body always gets its own.
compare_body_labels <- function(bodies, truncated) {
  labels <- rep(NA_character_, length(bodies))
  seen <- list()
  seen_labels <- character()
  k <- 0L
  for (i in seq_along(bodies)) {
    body <- bodies[[i]]
    if (is.null(body)) {
      next
    }
    whole <- !isTRUE(truncated[[i]])
    hit <- if (whole) compare_body_match(body, seen) else 0L
    if (hit > 0L) {
      labels[[i]] <- seen_labels[[hit]]
      next
    }
    k <- k + 1L
    labels[[i]] <- sprintf("body_%d", k)
    if (whole) {
      seen <- c(seen, list(body))
      seen_labels <- c(seen_labels, labels[[i]])
    }
  }
  labels
}

# The index of the first body in `seen` with exactly the bytes of `body`, or
# 0.
compare_body_match <- function(body, seen) {
  Position(function(s) identical(s, body), seen, nomatch = 0L)
}

# The fields `comparison` counts, and the statuses it counts them over.
compare_fields <- c(
  "fetch_outcome", "http_status", "effective_url", "redirect_count",
  "terminal_redirect_reason", "body_label", "body_size", "content_type",
  "content_flag"
)
compare_completed <- c("response", "acquisition_failure", "refused")

compare_differences <- function(observations) {
  done <- observations[
    observations$observation_status %in% compare_completed, , drop = FALSE
  ]
  values <- lapply(compare_fields, function(f) unique(done[[f]]))
  out <- data.frame(
    field = compare_fields,
    n_distinct = vapply(values, length, integer(1L)),
    stringsAsFactors = FALSE
  )
  out$values <- values
  out
}

#' Print a `robots_fetch_comparison` object
#'
#' Prints a header (observations, variants and requests spent), the count of
#' each observation status, the compared fields that differ, and a preview of
#' up to ten observations. Body values are never shown. Returns the object
#' invisibly.
#'
#' @inheritParams print.robots_decisions
#' @param x A `robots_fetch_comparison` object.
#'
#' @return `x`, invisibly.
#' @examples
#' # A refused origin needs no network, so this runs offline.
#' cmp <- robots_compare_fetches("http://127.0.0.1/", max_requests = 1)
#' print(cmp)
#' @export
print.robots_fetch_comparison <- function(x, ...) {
  obs <- x$observations
  n <- nrow(obs)
  n_var <- length(unique(obs$variant_id))
  cat(sprintf(
    "<robots_fetch_comparison>: %d observation%s of %d variant%s, %s\n",
    n, if (n == 1L) "" else "s", n_var, if (n_var == 1L) "" else "s",
    sprintf(
      "%d of %d requests", attr(x, "requests_made"), attr(x, "max_requests")
    )
  ))
  if (n == 0L) {
    return(invisible(x))
  }
  counts <- table(factor(obs$observation_status,
                         levels = unique(obs$observation_status)))
  cat(sprintf("Status: %s\n", paste(names(counts), counts, collapse = ", ")))
  differ <- x$comparison[x$comparison$n_distinct > 1L, , drop = FALSE]
  if (nrow(differ) == 0L) {
    cat("Differs: nothing among the completed observations\n")
  } else {
    cat(sprintf("Differs: %s\n", paste0(
      differ$field, " (", differ$n_distinct, ")", collapse = ", "
    )))
  }
  show_n <- min(n, 10L)
  print(obs[seq_len(show_n), c(
    "observation_id", "label", "repeat_index", "observation_status",
    "http_status", "body_label"
  ), drop = FALSE], row.names = FALSE)
  if (n > show_n) {
    cat(sprintf("  ... and %d more row%s\n", n - show_n,
                if (n - show_n == 1L) "" else "s"))
  }
  invisible(x)
}
