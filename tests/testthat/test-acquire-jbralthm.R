# ROBO-jbralthm: the acquisition module (R/acquire.R, R/acquire-map.R), the one
# caller of ssrfr. Its translation tables, its policy, and the hop loop's own
# redirect rules, driven through the fake at the ssrfr boundary
# (helper-fake-ssrfr.R), which checks every hop with the real ssrfr. Offline.

ok_robots <- function(body = "user-agent: *\ndisallow: /private") {
  function(req) fake_response(200L, body = charToRaw(body))
}

# Route each requested URL to a handler; anything else fails the test.
fake_router <- function(routes) {
  function(req) {
    handler <- routes[[req$url]]
    if (is.null(handler)) {
      stop(sprintf("unexpected request URL in fake: %s", req$url))
    }
    handler(req)
  }
}

redirect_to <- function(location, status = 301L) {
  force(location)
  force(status)
  function(req) fake_response(status, headers = list(Location = location))
}

evidence_of <- function(url = "http://a/x") {
  robots_evaluate_url_v1(url, "Googlebot", "google", "google")$evidence
}

# --- The translation tables walk ssrfr's vocabularies in full -----------------

test_that("every ssrfr reason code has exactly one refusal-table row", {
  codes <- ssrfr::ssrf_vocabulary("reason_codes")$code
  table <- acquire_refusal_table()
  expect_setequal(table$code, codes)
  expect_false(anyDuplicated(table$code) > 0L)
  # Each admitted row maps to a published outcome and terminal reason.
  admitted <- table[table$admitted, , drop = FALSE]
  expect_true(all(admitted$fetch_outcome %in% c(
    "ssrf_blocked", "redirect_error"
  )))
  expect_true(all(admitted$redirect_terminal_redirect_reason %in% c(
    "none", "over_budget", "no_location", "loop", "non_http_target",
    "downgrade"
  )))
  # Each admitted row with a safety reason is classed (ROBO-jqwukcog), so a
  # code ssrfr adds fails until robotstxtr says whether `crawler` reads it as
  # unreachable_local; a row with none has no class.
  reasoned <- !is.na(admitted$safety_block_reason)
  expect_true(
    all(admitted$class[reasoned] %in% c("address", "url_shape", "redirect")),
    info = toString(admitted$code[reasoned & is.na(admitted$class)])
  )
  expect_true(all(is.na(table$class[is.na(table$safety_block_reason)])))
})

test_that("every ssrfr failure cause has a cause-table row", {
  causes <- ssrfr::ssrf_vocabulary("causes")$cause
  table <- acquire_cause_table()
  expect_setequal(unique(table$cause), causes)
  for (cause in causes) {
    expect_true(
      acquire_cause_row(cause, "anything")$fetch_outcome %in%
        c("timeout", "tls_error", "network_error"),
      info = cause
    )
  }
})

test_that("the refusal codes map as the issue's table says", {
  shared <- c(
    "loopback", "private", "link-local", "cloud-metadata", "shared",
    "unspecified", "this-network", "ipv4-mapped", "ipv4-translated",
    "ipv4-compatible", "nat64", "6to4", "teredo", "isatap",
    "malformed-address", "numeric-literal", "scheme"
  )
  for (code in shared) {
    row <- acquire_refusal_row(code)
    expect_identical(row$fetch_outcome, "ssrf_blocked", info = code)
    expect_identical(row$safety_block_reason, code, info = code)
  }
  downgrade <- acquire_refusal_row("downgrade")
  expect_identical(downgrade$safety_block_reason, "https_downgrade")
  expect_identical(downgrade$redirect_fetch_outcome, "redirect_error")
  expect_identical(downgrade$redirect_terminal_redirect_reason, "downgrade")
  scheme <- acquire_refusal_row("scheme")
  expect_identical(scheme$redirect_fetch_outcome, "redirect_error")
  expect_identical(scheme$redirect_terminal_redirect_reason, "non_http_target")
  limit <- acquire_refusal_row("redirect-limit")
  expect_identical(limit$terminal_redirect_reason, "over_budget")
  expect_true(is.na(limit$safety_block_reason))
})

test_that("the published safety_block_reason set is the 2026-11-05.1 set", {
  expect_setequal(acquire_safety_block_reasons(), c(
    "loopback", "private", "link-local", "cloud-metadata", "shared",
    "unspecified", "this-network", "ipv4-mapped", "ipv4-translated",
    "ipv4-compatible", "nat64", "6to4", "teredo", "isatap",
    "malformed-address", "numeric-literal", "scheme", "https_downgrade",
    "userinfo", "port", "parse", "multicast", "reserved"
  ))
  expect_identical(engine_schema_revision_v1(), "2026-11-11.1")
  expect_identical(engine_schema_revision_v2(), "2026-11-11.1")
})

test_that("a code or cause outside the tables aborts, never falls through", {
  expect_error(
    acquire_refusal_row("host-denied"),
    class = "robotstxtr_acquisition_invariant"
  )
  expect_error(
    acquire_refusal_row("no-such-code"),
    class = "robotstxtr_acquisition_invariant"
  )
  expect_error(
    acquire_cause_row("no-such-cause"),
    class = "robotstxtr_acquisition_invariant"
  )
})

test_that("the causes map to transport kinds", {
  expected <- c(
    "unresolvable" = "network_error", "pin-mismatch" = "network_error",
    "connect-failed" = "network_error", "protocol-error" = "network_error",
    "tls-failed" = "tls_error", "timeout" = "timeout"
  )
  for (cause in names(expected)) {
    local_fake_ssrfr(function(req) fake_failure(cause))
    e <- evidence_of()
    expect_identical(e$legacy_fetch_outcome, expected[[cause]], info = cause)
    expect_identical(e$transport_error_kind, expected[[cause]], info = cause)
    expect_identical(e$evidence_status, "transport_fail", info = cause)
  }
  # A header over its limit is not a body over max_bytes.
  local_fake_ssrfr(function(req) {
    fake_failure("response-too-large", check = "header",
                 limit = "max_header_bytes")
  })
  expect_identical(evidence_of()$legacy_fetch_outcome, "network_error")
})

# --- A body over max_bytes ----------------------------------------------------

test_that("a 2xx body over max_bytes keeps its prefix, truncated", {
  # ROBO-ldpahknv (RFC 9309 section 2.5): ssrfr's truncate_body keeps the
  # first max_bytes bytes; the evidence stays incomplete.
  local_fake_ssrfr(function(req) {
    fake_response(200L, body = strrep("x", 2000L))
  })
  e <- robots_evaluate_url_v1(
    "http://a/x", "Googlebot", "google", "google", max_bytes = 1000L
  )$evidence
  expect_identical(e$legacy_fetch_outcome, "fetched")
  expect_identical(e$legacy_http_status, 200L)
  expect_identical(e$effective_url, "http://a/robots.txt")
  expect_identical(e$observed_bytes, 2000L)
  expect_identical(e$stored_bytes, 1000L)
  expect_true(e$body_truncated)
  expect_identical(e$termination_reason, "ceiling")
  expect_identical(e$evidence_status, "incomplete")
  expect_true(is.na(e$transport_error_kind))
})

test_that("body_truncated is FALSE on every row within max_bytes", {
  local_fake_ssrfr(fake_router(list(
    "http://a/robots.txt" = ok_robots(),
    "http://b/robots.txt" = function(req) fake_failure("timeout"),
    "http://c/robots.txt" = function(req) fake_response(200L, body = "x")
  )))
  e <- robots_evaluate_url_v1(
    c("http://a/", "http://b/", "http://c/", "http://10.0.0.1/"),
    "Googlebot", "google", "google"
  )$evidence
  expect_identical(e$body_truncated, rep(FALSE, 4L))
})

# --- Redirect rules the module keeps ------------------------------------------

test_that("the sixth redirect is over_budget and keeps its Location", {
  routes <- list("http://a/robots.txt" = redirect_to("/1"))
  for (i in 1:6) {
    routes[[sprintf("http://a/%d", i)]] <- redirect_to(sprintf("/%d", i + 1L))
  }
  local_fake_ssrfr(fake_router(routes))
  e <- evidence_of()
  expect_identical(e$legacy_fetch_outcome, "redirect_error")
  expect_identical(e$terminal_redirect_reason, "over_budget")
  expect_identical(e$evidence_status, "redirect_over_budget")
  expect_identical(e$redirect_count, 5L)
  expect_identical(e$location_header, "/6")
  expect_identical(e$final_http_status, 301L)
  hops <- e$redirect_hops[[1L]]
  expect_length(hops, 6L)
  expect_identical(hops[[6L]]$from_url, "http://a/5")
  expect_identical(hops[[6L]]$location_target, "http://a/6")
})

test_that("five redirects are followed", {
  routes <- list("http://a/robots.txt" = redirect_to("/1"))
  for (i in 1:4) {
    routes[[sprintf("http://a/%d", i)]] <- redirect_to(sprintf("/%d", i + 1L))
  }
  routes[["http://a/5"]] <- ok_robots()
  local_fake_ssrfr(fake_router(routes))
  x <- robots_fetch("http://a/x")
  expect_identical(x$robots$fetch_outcome, "fetched")
  expect_identical(x$robots$redirect_count, 5L)
  expect_identical(x$robots$effective_url, "http://a/5")
})

test_that("redirect-limit, if ssrfr ever returns it, is over_budget", {
  result <- acquire_outcome_result(
    fake_refusal("redirect-limit", hop = 7L),
    list(state = list(status = 302L)), 6L, list(), 100L
  )
  expect_identical(result$fetch_outcome, "redirect_error")
  expect_identical(result$terminal_redirect_reason, "over_budget")
  expect_identical(result$final_http_status, 302L)
  expect_true(is.na(result$safety_block_reason))
})

test_that("a redirect back to the start is a loop, caught before fetching", {
  local_fake_ssrfr(fake_router(list(
    "http://a/robots.txt" = redirect_to("http://b/robots.txt"),
    "http://b/robots.txt" = redirect_to("http://a/robots.txt")
  )))
  e <- evidence_of()
  expect_identical(e$terminal_redirect_reason, "loop")
  expect_identical(e$evidence_status, "http_protocol_error")
  expect_identical(e$redirect_count, 1L)
  expect_identical(e$location_header, "http://a/robots.txt")
})

test_that("a relative self-redirect is a loop", {
  local_fake_ssrfr(fake_router(list(
    "http://a/robots.txt" = redirect_to("robots.txt", 302L)
  )))
  e <- evidence_of()
  expect_identical(e$terminal_redirect_reason, "loop")
  expect_identical(e$redirect_count, 0L)
})

test_that("a loop is judged on the resolved URL, not the Location text", {
  local_fake_ssrfr(fake_router(list(
    "http://a/robots.txt" = redirect_to("/b"),
    "http://a/b" = redirect_to("http://a/c#frag"),
    "http://a/c" = redirect_to("../b?"),
    "http://a/b?" = ok_robots()
  )))
  e <- evidence_of()
  # The fragment is not part of the URL fetched, and "../b?" resolves to
  # http://a/b? -- a different URL from http://a/b, so it is followed.
  expect_identical(e$redirect_count, 3L)
  expect_identical(e$terminal_redirect_reason, "none")
  expect_identical(e$effective_url, "http://a/b?")
})

test_that("a 3xx without one usable Location is no_location", {
  cases <- list(
    "empty Location" = function(req) {
      fake_response(302L, headers = list(Location = ""))
    },
    "two Locations" = function(req) {
      two <- stats::setNames(list("/a", "/b"), c("Location", "Location"))
      fake_response(302L, headers = two)
    },
    "a 304" = function(req) {
      fake_response(304L, headers = list(Location = "/a"))
    },
    "a 300" = function(req) {
      fake_response(300L, headers = list(Location = "/a"))
    }
  )
  for (name in names(cases)) {
    local_fake_ssrfr(cases[[name]])
    e <- evidence_of()
    expect_identical(e$terminal_redirect_reason, "no_location", info = name)
    expect_identical(e$legacy_fetch_outcome, "redirect_error", info = name)
  }
})

# --- Refusals of a redirect target --------------------------------------------

test_that("a redirect to a non-HTTP(S) scheme is non_http_target / scheme", {
  local_fake_ssrfr(fake_router(list(
    "http://a/robots.txt" = redirect_to("ftp://a/robots.txt", 302L)
  )))
  e <- evidence_of()
  expect_identical(e$legacy_fetch_outcome, "redirect_error")
  expect_identical(e$terminal_redirect_reason, "non_http_target")
  expect_identical(e$safety_block_reason, "scheme")
  expect_identical(e$evidence_status, "safety_refused")
  expect_identical(e$location_header, "ftp://a/robots.txt")
  expect_identical(e$final_http_status, 302L)
  expect_identical(e$redirect_count, 0L)
})

test_that("an HTTPS-to-HTTP redirect is downgrade / https_downgrade", {
  local_fake_ssrfr(fake_router(list(
    "https://a/robots.txt" = redirect_to("http://a/robots.txt")
  )))
  e <- evidence_of("https://a/x")
  expect_identical(e$legacy_fetch_outcome, "redirect_error")
  expect_identical(e$terminal_redirect_reason, "downgrade")
  expect_identical(e$safety_block_reason, "https_downgrade")
  expect_identical(e$location_header, "http://a/robots.txt")
})

test_that("a redirect carrying credentials is refused as userinfo", {
  local_fake_ssrfr(fake_router(list(
    "http://a/robots.txt" = redirect_to("http://u:p@b/robots.txt")
  )))
  e <- evidence_of()
  expect_identical(e$legacy_fetch_outcome, "ssrf_blocked")
  expect_identical(e$safety_block_reason, "userinfo")
  expect_identical(e$terminal_redirect_reason, "none")
  expect_identical(e$redirect_count, 1L)
})

test_that("a refused or failed redirect target counts the redirect", {
  local_fake_ssrfr(fake_router(list(
    "http://a/robots.txt" = redirect_to("http://b/robots.txt"),
    "http://b/robots.txt" = function(req) fake_failure("connect-failed")
  )))
  x <- robots_fetch("http://a/x")
  expect_identical(x$robots$fetch_outcome, "network_error")
  expect_identical(x$robots$redirect_count, 1L)
})

# --- Policy -------------------------------------------------------------------

test_that("the policy carries the fetch controls", {
  policy <- acquire_policy(2.5, "bot/1", 4096L)
  expect_identical(policy$max_redirects, 6)
  expect_identical(policy$total_timeout, 3)
  expect_identical(policy$connect_timeout, 3)
  expect_identical(policy$max_response_size, 4096)
  expect_identical(policy$user_agent, "bot/1")
  expect_equal(policy$allow_ports, 1:65535)
  expect_length(policy$allow_ranges, 0L)
  # A fractional or sub-second timeout is rounded up to whole seconds, and the
  # connect timeout never exceeds the total.
  small <- acquire_policy(0.2, "bot/1", 10L)
  expect_identical(small$total_timeout, 1)
  expect_identical(small$connect_timeout, 1)
})

test_that("ssrf_guard = FALSE builds the permissive policy", {
  policy <- acquire_policy(10, "bot/1", 10L, ssrf_guard = FALSE)
  expect_setequal(policy$allow_ranges, c("0.0.0.0/0", "::/0"))
  expect_setequal(
    policy$allow_hosts,
    ssrfr::ssrf_vocabulary("metadata_hostnames")$hostname
  )
})

test_that("the first hop is fetched with the policy's user agent", {
  seen <- new.env(parent = emptyenv())
  local_fake_ssrfr(function(req) {
    seen$ua <- req$user_agent
    fake_response(404L)
  })
  robots_fetch("http://a/x", fetch_user_agent = "my-crawler/9 (+https://x)")
  expect_identical(seen$ua, "my-crawler/9 (+https://x)")
})

# --- Errors -------------------------------------------------------------------

test_that("a user agent ssrfr would refuse is robotstxtr's call-level error", {
  for (ua in c("bot\r\nX-Injected: 1", "bot\n", " bot", "bot\t", "a\001b")) {
    expect_error(
      robots_fetch("http://a/x", fetch_user_agent = ua),
      class = "robotstxtr_invalid_fetch_user_agent"
    )
  }
  expect_invisible(validate_fetch_user_agent("bot/1\t(inner tab)"))
})

test_that("an ssrfr misuse error becomes robotstxtr_acquisition_error", {
  local_mocked_bindings(
    acquire_prepare_hop = function(...) {
      stop(structure(
        class = c("ssrfr_error_invalid_from", "ssrfr_error", "error",
                  "condition"),
        list(message = "bad from", call = NULL)
      ))
    }
  )
  expect_error(
    robots_fetch("http://a/x"),
    class = "robotstxtr_acquisition_error"
  )
})
