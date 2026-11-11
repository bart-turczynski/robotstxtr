#' Fetch robots.txt documents for URLs under the deterministic fetch policy
#'
#' Performs the grouped robots.txt fetch stage for one or more target URLs and
#' returns a `robots_fetches` object. No matching is performed (that is the
#' `allowed_by_robots_url()` path, a later slice); this function only computes
#' each URL's
#' fetch-origin, fetches each distinct `/robots.txt` once, and classifies the
#' HTTP outcome.
#'
#' For every input URL the fetch-origin grouping key
#' `scheme://host[:port]/robots.txt` is built from the URL alone. The URL must
#' begin with an explicit `http://` or `https://` (in any letter case); a
#' scheme-relative (`//host/...`) or scheme-less URL is invalid, never defaulted
#' to HTTP. The scheme and host are put in lower case, an IDN host is converted
#' to its ASCII form, a default port (80 for `http`, 443 for `https`) is dropped
#' while any other port is kept, an IPv6 literal stays bracketed, userinfo is
#' dropped, and the path, query, and fragment are replaced by `/robots.txt`.
#' Within one call each distinct grouping key is fetched exactly once and every
#' input row sharing that key references the same source row and stored body.
#' Grouping is keyed on the requested robots URL, not on the final redirect
#' destination. Input order is preserved in `map`, and fetch groups run
#' sequentially in first-occurrence order; source IDs are assigned `robots_1`,
#' `robots_2`, and so on in that order. There is no persistent, cross-call, or
#' hidden HTTP cache.
#'
#' A URL whose fetch-origin cannot be constructed (missing, empty, malformed, or
#' non-HTTP(S)) is invalid: it never triggers an HTTP request and appears in
#' `map` with `fetch_outcome = "input_invalid"`, no `source_id`, and
#' invalid-URL error metadata.
#'
#' The request policy is deterministic and intentionally conservative: HTTP
#' `GET` over a new HTTP/1.1 connection; TLS verified with platform defaults;
#' no proxy; one total timeout per origin, redirects included; at most five
#' redirects; redirects allowed only to `http`/`https`; HTTP-to-HTTPS upgrades
#' allowed but, under `safety_level = "strict"`, every HTTPS-to-HTTP downgrade
#' rejected as `redirect_error`; no
#' URL userinfo, authorization, cookies, or caller session state forwarded; a
#' package fetch user agent (`robotstxtr/<version>`) unless the caller supplies
#' one; and no automatic retries.
#'
#' Every request goes through the \pkg{ssrfr} guard, for the initial origin and
#' for every redirect target. A host name is resolved once, every address it
#' resolves to is checked, and the connection is pinned to those addresses, so
#' a name cannot be rebound between the check and the request. An origin or
#' target that is, or resolves to, a loopback, private, link-local, shared,
#' multicast, reserved, or cloud-metadata address, an IPv6 form that embeds
#' one, or a known metadata host name is refused before any connection, as
#' `ssrf_blocked`; so is a URL whose host the two URL parsers read differently,
#' or one on port 0.
#'
#' Each response is classified into a stable `fetch_outcome`. For a `fetched`
#' outcome the exact decoded entity bytes are stored once as a raw vector in
#' the source row's `body` (an empty body is valid); all other outcomes store
#' no body.
#'
#' `max_bytes` caps the decoded response body. The limit is enforced on decoded
#' entity bytes (after any HTTP content decoding, such as gzip) as they arrive,
#' and the transfer stops the moment the decoded byte count exceeds the limit;
#' the compressed entity is never fully downloaded before the check. A body at
#' or under the limit is stored normally as a `fetched` result. A 2xx body over
#' the limit is cut at it: its first `max_bytes` decoded bytes are stored as a
#' `fetched` result and matched, and anything after the cut is ignored, as
#' RFC 9309 section 2.5 allows. The cut falls at a byte, so the stored body may
#' end inside a multibyte character, and `body_size` then equals `max_bytes`.
#' The source row's logical `body_truncated` is `TRUE` for such a cut body and
#' `FALSE` otherwise. The cut usually falls inside a line, so
#' [allowed_by_robots_url()] matches, and [robots_validate_url()] validates, a
#' cut body only up to its last complete line (its last line break): a rule cut
#' short is never read as a shorter rule. A cut body with no line break yields
#' no rules. `body` and `body_size` keep every stored byte.
#' A 4xx or 5xx keeps its status outcome whatever its body size, with no
#' stored body. A body over the limit with a 3xx status, an unknown status, or a
#' 2xx whose libcurl and status-line statuses disagree ends as `body_too_large`;
#' a 3xx is not followed, because \pkg{ssrfr} keeps no `Location` for it.
#'
#' The response header may take up to 64 KiB and 256 fields per hop; a header
#' over either limit is a `network_error`.
#'
#' A 429 or 503 for robots.txt may say when to try again (RFC 9110 section
#' 10.2.3). Each source row keeps the final response's `Retry-After` field
#' value as `retry_after`, as \pkg{ssrfr} delivers it (optional whitespace
#' trimmed, obs-fold unfolded; several fields joined with `", "`), and the
#' delay it asks for as `retry_after_seconds`: the `delay-seconds` value, or
#' an HTTP-date less the response's `Date` (the fetch time when `Date` is
#' absent or invalid), with a date already past giving `0`. The delay is
#' unbounded, since RFC 9110 sets no maximum, so clamp it before waiting.
#' `retry_after_seconds` alone is `NA` when the value is neither form. Only
#' the final response counts, never a redirect before it.
#'
#' `NA` in both columns means the delay is not available, not that none was
#' requested. That is the case when the final response has no `Retry-After`,
#' and also when the fetch ends without a usable final response: a refusal, a
#' transport failure, a redirect error, or a body over `max_bytes` with a 3xx
#' status, an unknown status, or a 2xx whose libcurl and status-line statuses
#' disagree. A 4xx or 5xx whose body exceeds `max_bytes` keeps its status and
#' outcome, but its headers are not available, so its `Retry-After` is `NA`
#' even when the server sent one. `robots_fetch()` never retries: honoring the
#' delay is the caller's choice.
#'
#' Each source row also keeps the final response's `Content-Type` field value
#' as `content_type`, exactly as received (`NA` when absent or when there is
#' no final response), and a heuristic `content_flag` read from the first
#' 4096 bytes of a stored body: `"binary"` (a NUL byte, or at least 8 bytes,
#' and more than 10% of them, not valid UTF-8), `"html"` (a line starting
#' with `<!doctype html`, `<html`, `<head` or `<body`, possibly after an
#' `<?xml ...?>` or `<!-- ... -->` on that line; or a body starting with `<`
#' that holds `<!doctype html`, `<html`, `<head`, `<body`, `<script` or
#' `<style` anywhere), `"xml"` (any other body starting with `<`), `"json"`
#' (the body starts with a JSON object or array), or `NA`.
#' The flag comes from the body alone, never from `content_type`, and changes
#' nothing: the body is matched as it is either way.
#'
#' Each source row also says why a redirect chain ended without a final
#' response, as `terminal_redirect_reason`: `"over_budget"` (a sixth
#' redirect), `"no_location"` (a 3xx that names no target: not a 301, 302,
#' 303, 307 or 308, or an empty or repeated `Location`), `"loop"` (a target
#' already requested), `"downgrade"` (an `https` to `http` redirect, refused
#' under `safety_level = "strict"`),
#' `"non_http_target"` (a redirect to a scheme other than `http` or `https`,
#' refused), or `"none"` for every other outcome, a redirect followed to its
#' end included. A refusal by the guard sets `safety_block_reason` to its
#' reason code, the same value the v1 evidence of [robots_evaluate_url_v1()]
#' carries (such as `"loopback"`, `"private"` or `"cloud-metadata"`, and
#' `"https_downgrade"` or `"scheme"` for the two refused redirects); it is
#' `NA` when nothing was refused.
#'
#' `timeout` is one budget for the whole chain of one origin, redirects
#' included, rounded up to whole seconds; each connection attempt also gets at
#' most three seconds. Two things can make a fetch overrun it: the time spent
#' between hops in robotstxtr's own code is not counted, and the system
#' resolver cannot be interrupted, so a slow DNS answer is only noticed once
#' it returns.
#'
#' @param url A character vector of target URLs. May have length zero (an empty
#'   result is returned). A wrong R type is a call-level error.
#' @param timeout A single positive, finite numeric total timeout in seconds per
#'   origin, including redirects, rounded up to whole seconds. Defaults to
#'   `10`.
#' @param max_bytes A single positive, finite, whole-number decoded-body byte
#'   limit no greater than `.Machine$integer.max`, coerced to integer and
#'   recorded on each source row. A whole-number double (for example `524288`)
#'   is accepted; fractional, non-positive, out-of-range, or non-scalar values
#'   are call-level errors. Defaults to `524288L` (512 KiB). RFC 9309 section
#'   2.5 asks a crawler to parse at least 500 KiB (`512000` bytes) of a
#'   robots.txt file; a smaller value is accepted but falls below that floor.
#' @param fetch_user_agent `NULL` (use the package fetch user agent) or a single
#'   non-empty character HTTP user agent to send instead. It must be a valid
#'   HTTP field value: no control character, and no leading or trailing
#'   whitespace.
#' @param ssrf_guard A single logical, `TRUE` by default. `FALSE` is
#'   deprecated and warns: the guard has no off switch any more. It now
#'   selects a permissive policy, which reopens private, loopback and other
#'   internal address ranges and the metadata host names, for example to fetch
#'   `robots.txt` from a trusted intranet host. Known cloud-metadata endpoints
#'   and the IPv6 transition forms that embed an address stay refused.
#' @param safety_level A single string: what the fetch may do on the network,
#'   whatever ruleset reads the outcome. `"strict"`, the default, refuses an
#'   `https` to `http` redirect and every address the guard refuses.
#'   `"crawler"` fetches as a public crawler does: it follows an `https` to
#'   `http` redirect as an ordinary hop within the five-redirect budget, and
#'   still refuses every address the guard refuses. Any other value is a
#'   call-level error.
#'
#' @return An S3 object of class `robots_fetches`: a named list with two
#'   components, `map` (one row per input URL, in input order) and `robots` (one
#'   row per fetched source, with the fetched body stored once as a raw vector
#'   in `robots$body`, and the final response's `Retry-After` as the character
#'   `retry_after` and the double `retry_after_seconds`, its `Content-Type` as
#'   the character `content_type`, the character `content_flag`, the logical
#'   `body_truncated`, and the character `terminal_redirect_reason` and
#'   `safety_block_reason`).
#'
#' @examples
#' # A refused origin is decided before any request, so this runs offline.
#' # Both URLs share one fetch-origin, which is refused once; the invalid URL
#' # is never fetched.
#' robots_fetch(c("http://127.0.0.1/", "http://127.0.0.1/private", "not-a-url"))
#'
#' \dontrun{
#' # robots_fetch() performs live HTTP. Both URLs share one fetch-origin, so
#' # https://example.com/robots.txt is fetched once.
#' robots_fetch(c("https://example.com/", "https://example.com/private"))
#' }
#'
#' @seealso [allowed_by_robots_url()] to fetch and match in one step.
#' @export
robots_fetch <- function(url, timeout = 10, max_bytes = 524288L,
                         fetch_user_agent = NULL, ssrf_guard = TRUE,
                         safety_level = "strict") {
  # --- Call-level input validation / shared fetch controls (PRD 6.6). --------
  validate_url_type(url)
  timeout <- validate_timeout(timeout)
  validate_fetch_user_agent(fetch_user_agent)
  max_bytes_int <- validate_max_bytes(max_bytes)
  validate_ssrf_guard(ssrf_guard)
  safety_level <- validate_safety_level(safety_level)
  warn_ssrf_guard_deprecated(ssrf_guard)
  fetch_ua <- if (is.null(fetch_user_agent)) {
    package_fetch_user_agent()
  } else {
    fetch_user_agent
  }

  n <- length(url)

  # --- Per-element fetch-origin (PRD 6.3). A URL is fetch-eligible only when it
  # has a grouping key; otherwise it is input-invalid and never fetched.
  origin <- vapply(url, robots_origin, character(1L), USE.NAMES = FALSE)
  eligible <- !is.na(origin)

  # --- Grouping (PRD 6.5): fetch each DISTINCT origin exactly once, in
  # first-occurrence order. Distinct keys among eligible rows only.
  distinct_origins <- unique(origin[eligible])
  n_src <- length(distinct_origins)
  source_ids <- if (n_src > 0L) {
    paste0("robots_", seq_len(n_src))
  } else {
    character(0)
  }

  # Fetch each distinct origin sequentially in first-occurrence order.
  results <- vector("list", n_src)
  for (i in seq_len(n_src)) {
    results[[i]] <- acquire_robots(
      distinct_origins[[i]], timeout, fetch_ua, max_bytes_int, ssrf_guard,
      safety_level
    )
  }

  # --- robots source table (one row per fetched source). --------------------
  robots <- data.frame(
    source_id = source_ids,
    source_type = rep("fetched", n_src),
    robots_url = distinct_origins,
    effective_url = vapply(results, function(r) r$effective_url,
                           character(1L)),
    http_status = vapply(results, function(r) r$http_status, integer(1L)),
    fetch_outcome = vapply(results, function(r) r$fetch_outcome, character(1L)),
    redirect_count = vapply(results, function(r) r$redirect_count, integer(1L)),
    body_size = vapply(results, function(r) r$body_size, integer(1L)),
    timeout = rep(timeout, n_src),
    max_bytes = rep(max_bytes_int, n_src),
    error_stage = vapply(results, function(r) r$error_stage, character(1L)),
    error_class = vapply(results, function(r) r$error_class, character(1L)),
    error_message = vapply(results, function(r) r$error_message, character(1L)),
    retry_after = vapply(results, function(r) r$retry_after, character(1L)),
    retry_after_seconds = vapply(
      results, function(r) r$retry_after_seconds, numeric(1L)
    ),
    content_type = vapply(results, function(r) r$content_type, character(1L)),
    content_flag = vapply(results, function(r) r$content_flag, character(1L)),
    body_truncated = vapply(
      results, function(r) r$body_truncated, logical(1L)
    ),
    # Why a redirect chain ended, and the guard's refusal code
    # (ROBO-bsloeclp; design/engine-profiles.md section 2).
    terminal_redirect_reason = vapply(
      results, function(r) r$terminal_redirect_reason, character(1L)
    ),
    safety_block_reason = vapply(
      results, function(r) r$safety_block_reason, character(1L)
    ),
    stringsAsFactors = FALSE
  )
  # `body` is a list-of-raw column: each fetched body stored exactly once.
  robots$body <- lapply(results, function(r) r$body)

  # --- Per-input map (one row per input URL, in input order). ---------------
  # Match each eligible input to its source row by origin key; invalid inputs
  # are detached (input_invalid) and reference no source.
  src_index <- match(origin, distinct_origins)

  map_source_id <- rep(NA_character_, n)
  map_robots_url <- rep(NA_character_, n)
  map_http_status <- rep(NA_integer_, n)
  map_fetch_outcome <- rep("input_invalid", n)
  map_error_stage <- rep("origin", n)
  map_error_class <- rep("robots_invalid_url", n)
  map_error_message <- rep(
    "URL is missing, empty, malformed, or not HTTP(S).", n
  )

  if (any(eligible)) {
    idx <- which(eligible)
    si <- src_index[idx]
    map_source_id[idx] <- source_ids[si]
    map_robots_url[idx] <- distinct_origins[si]
    map_http_status[idx] <- robots$http_status[si]
    map_fetch_outcome[idx] <- robots$fetch_outcome[si]
    map_error_stage[idx] <- robots$error_stage[si]
    map_error_class[idx] <- robots$error_class[si]
    map_error_message[idx] <- robots$error_message[si]
  }

  map <- data.frame(
    input_id = seq_len(n),
    url = url,
    source_id = map_source_id,
    robots_url = map_robots_url,
    http_status = map_http_status,
    fetch_outcome = map_fetch_outcome,
    error_stage = map_error_stage,
    error_class = map_error_class,
    error_message = map_error_message,
    stringsAsFactors = FALSE
  )

  new_robots_fetches(map, robots)
}

#' Construct a `robots_fetches` object
#'
#' Internal low-level constructor. Assembles the two primary components into the
#' `robots_fetches` S3 object and stamps the package version as an attribute. No
#' validation of column shape is performed here; callers build conforming `map`
#' and `robots` frames.
#'
#' @param map A data frame with one row per input URL, in input order.
#' @param robots A data frame with one row per fetched source.
#'
#' @return An S3 object of class `robots_fetches`.
#' @keywords internal
#' @noRd
new_robots_fetches <- function(map, robots) {
  structure(
    list(map = map, robots = robots),
    class = "robots_fetches",
    package_version = as.character(getNamespaceVersion("robotstxtr"))
  )
}

#' Print a `robots_fetches` object
#'
#' Prints a compact one-line header (input and source counts) and a preview of
#' up to ten input-map rows. Body values are never shown. Returns the object
#' invisibly.
#'
#' @inheritParams print.robots_decisions
#' @param x A `robots_fetches` object.
#'
#' @return `x`, invisibly.
#' @examples
#' # A robots_fetches object comes from robots_fetch(). A refused origin needs
#' # no network, so this runs offline.
#' fetches <- robots_fetch("http://169.254.169.254/page")
#' print(fetches)
#' @export
print.robots_fetches <- function(x, ...) {
  n <- nrow(x$map)
  n_src <- nrow(x$robots)
  cat(sprintf(
    "<robots_fetches>: %d input%s, %d source%s\n",
    n, if (n == 1L) "" else "s",
    n_src, if (n_src == 1L) "" else "s"
  ))
  if (n > 0L) {
    show_n <- min(n, 10L)
    preview <- x$map[
      seq_len(show_n),
      c("input_id", "url", "source_id", "http_status", "fetch_outcome"),
      drop = FALSE
    ]
    print(preview, row.names = FALSE)
    if (n > show_n) {
      extra <- n - show_n
      cat(sprintf(
        "  ... and %d more row%s\n", extra, if (extra == 1L) "" else "s"
      ))
    }
  }
  invisible(x)
}
