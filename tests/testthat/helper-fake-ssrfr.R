# A fake at the ssrfr boundary (ROBO-jbralthm). The acquisition module
# (R/acquire.R) reaches ssrfr only through acquire_prepare_hop() and
# acquire_fetch(); local_fake_ssrfr() replaces those two with a scripted
# server, so a test drives the real hop loop, redirect rules and translation
# tables with no network and no DNS.
#
# What the fake keeps from ssrfr, so the loop sees what it would see live:
# - every hop is checked by ssrfr itself, through ssrf_inspect_url() at layer
#   L0 under the module's real policy: scheme, userinfo, port, parse, address
#   literals, metadata names, and the downgrade of an https hop's redirect
#   (lifted by the policy's `allow_downgrade`, as ssrfr lifts it).
#   A name is not resolved, so "http://a/" passes.
# - a relative Location is resolved against the previous hop (WHATWG), and
#   the fragment dropped, as the binding's `url` is.
# - the binding records the status, the Location and the Location count; a 3xx
#   past the policy's `max_redirects` is the "redirect-limit" refusal, decided
#   first. Then, in ssrfr's order: more header fields than
#   `max_header_fields` is the "response-too-large" failure with
#   `check = "header"`; a body over `max_response_size` the same failure with
#   `check = "decoded-bytes"`, its status and the bytes observed, the binding
#   recording the status but no Location, unless the policy's
#   `truncate_body` keeps a 2xx body's first `max_response_size` bytes as a
#   response marked `truncated` with `observed_bytes` (ROBO-ldpahknv); and,
#   for any status, more than one Location field the "protocol-error" failure
#   with `check = "location"`. That is ssrfr under libcurl < 8.18; libcurl
#   >= 8.18 refuses such a response first, which ssrfr reports as a
#   "protocol-error" with `check = "transport"` (ssrfr SSRF-xhobpkza). The
#   fake models the older libcurl; the wire tests see whichever is linked.
#   The header byte limit is not modeled: the loopback tests cover it.
#
# The handler is `function(req)`: `req$url` is the URL the hop requests,
# `req$user_agent` the User-Agent the policy sends, `req$method` "GET" and
# `req$headers` the request plan's fields (none). It returns fake_response(),
# fake_failure() or fake_refusal().
#
# Tests that need ssrfr's own wire behavior (pinning, streaming, decoding) use
# a loopback server instead: see local_loopback_policy().

fake_response <- function(status_code = 200L, url = NULL, headers = list(),
                          body = raw()) {
  if (is.null(body)) {
    body <- raw()
  }
  if (is.character(body)) {
    body <- charToRaw(paste(body, collapse = ""))
  }
  headers <- unlist(headers)
  if (is.null(headers)) {
    headers <- character()
  }
  names(headers) <- ascii_lower(names(headers))
  structure(
    list(status = as.integer(status_code), headers = headers, body = body),
    class = "ssrfr_response"
  )
}

fake_outcome <- function(token, hop, detail, class) {
  structure(
    c(token, list(
      hop = as.integer(hop), host = NA_character_, address = NA_character_,
      url = NA_character_, detail = detail
    )),
    class = c(class, "ssrfr_outcome")
  )
}

fake_failure <- function(cause, ..., hop = 1L) {
  fake_outcome(list(cause = cause), hop, list(...), "ssrfr_failure")
}

fake_refusal <- function(code, ..., hop = 1L) {
  fake_outcome(list(code = code), hop, list(...), "ssrfr_refusal")
}

fake_prepare_hop <- function(url, policy, from = NULL) {
  base <- if (is.null(from)) NULL else from$url
  hop <- if (is.null(from)) 1L else from$hop + 1L
  inspection <- ssrfr::ssrf_inspect_url(url, policy, base = base)
  if (!is.na(inspection$code)) {
    return(fake_refusal(inspection$code, hop = hop))
  }
  target <- if (is.null(base)) {
    url
  } else {
    rurl::resolve_url(url, base, url_standard = "whatwg", output = "serialized")
  }
  state <- new.env(parent = emptyenv())
  state$status <- NULL
  state$location <- NULL
  state$location_count <- NULL
  structure(
    list(
      hop = hop, url = sub("#.*$", "", target), policy = policy, state = state
    ),
    class = "ssrfr_binding"
  )
}

fake_fetch <- function(binding, handler) {
  req <- list(
    url = binding$url, method = "GET",
    user_agent = binding$policy$user_agent, headers = list()
  )
  res <- handler(req)
  if (inherits(res, "ssrfr_outcome")) {
    res$hop <- binding$hop
    return(res)
  }
  binding$state$status <- res$status
  if (res$status >= 300L && res$status <= 399L &&
        binding$hop - 1L >= binding$policy$max_redirects) {
    return(fake_refusal("redirect-limit", hop = binding$hop))
  }
  if (length(res$headers) > binding$policy$max_header_fields) {
    binding$state$status <- NULL
    return(fake_failure(
      "response-too-large",
      check = "header", limit = "max_header_fields", hop = binding$hop
    ))
  }
  limit <- binding$policy$max_response_size
  truncating <- isTRUE(binding$policy$truncate_body)
  if (length(res$body) > limit && truncating &&
        res$status >= 200L && res$status <= 299L) {
    # truncate_body: a 2xx keeps its first max_response_size bytes.
    res$observed_bytes <- as.numeric(length(res$body))
    res$body <- res$body[seq_len(limit)]
    res$truncated <- TRUE
  } else if (length(res$body) > limit) {
    return(fake_failure(
      "response-too-large",
      check = "decoded-bytes", limit = "max_response_size",
      status = res$status, observed_bytes = length(res$body),
      hop = binding$hop
    ))
  }
  locations <- unname(res$headers[names(res$headers) == "location"])
  binding$state$location_count <- length(locations)
  if (length(locations) == 1L) {
    binding$state$location <- locations[[1L]]
  }
  if (length(locations) > 1L) {
    return(fake_failure(
      "protocol-error", check = "location", hop = binding$hop
    ))
  }
  if (truncating && is.null(res$truncated)) {
    res$truncated <- FALSE
    res$observed_bytes <- as.numeric(length(res$body))
  }
  res
}

local_fake_ssrfr <- function(handler, env = parent.frame()) {
  testthat::local_mocked_bindings(
    acquire_prepare_hop = function(url, policy, request = NULL, from = NULL) {
      fake_prepare_hop(url, policy, from)
    },
    acquire_fetch = function(binding) fake_fetch(binding, handler),
    .package = "robotstxtr",
    .env = env
  )
}

with_fake_ssrfr <- function(handler, code) {
  local_fake_ssrfr(handler)
  force(code)
}

# Reopen loopback on `port` in the policy acquire_policy() builds, for a test
# that fetches a local server through the real ssrfr (ssrf_fetch()'s
# documented testing advice). Test-scoped: nothing in the package can do this.
local_loopback_policy <- function(port, env = parent.frame()) {
  real <- acquire_policy
  testthat::local_mocked_bindings(
    acquire_policy = function(timeout, fetch_ua, max_bytes, ssrf_guard = TRUE,
                              safety_level = "strict",
                              fetch_allow_ranges = character()) {
      policy <- real(
        timeout, fetch_ua, max_bytes, ssrf_guard, safety_level,
        fetch_allow_ranges
      )
      ssrfr::ssrf_policy(
        allow_ports = port,
        allow_ranges = "127.0.0.0/8",
        max_redirects = policy$max_redirects,
        connect_timeout = policy$connect_timeout,
        total_timeout = policy$total_timeout,
        max_response_size = policy$max_response_size,
        max_header_bytes = policy$max_header_bytes,
        max_header_fields = policy$max_header_fields,
        user_agent = policy$user_agent,
        truncate_body = isTRUE(policy$truncate_body),
        allow_downgrade = isTRUE(policy$allow_downgrade)
      )
    },
    .package = "robotstxtr",
    .env = env
  )
}
