# `safety_level = "crawler"` follows an https to http redirect as an ordinary
# hop within the five-redirect budget (ADR 0001 section 3, slice 3,
# ROBO-lwdxzdhw). acquire_policy() sets ssrfr's `allow_downgrade` from it;
# `strict` still refuses the downgrade. The fake checks each hop with
# ssrf_inspect_url() under the real policy, so it honors the flag as ssrfr does.

cd_body <- "user-agent: *\ndisallow: /private\n"

cd_router <- function(routes) {
  function(req) {
    handler <- routes[[req$url]]
    if (is.null(handler)) {
      stop(sprintf("unexpected request URL in fake: %s", req$url))
    }
    handler(req)
  }
}

cd_downgrade_chain <- function() {
  cd_router(list(
    "https://a/robots.txt" = function(req) {
      fake_response(301L, headers = list(Location = "http://a/robots.txt"))
    },
    "http://a/robots.txt" = function(req) fake_response(200L, body = cd_body)
  ))
}

test_that("crawler follows https -> 301 -> http -> 200 as one hop", {
  local_fake_ssrfr(cd_downgrade_chain())
  x <- robots_evaluate_url_v1(
    "https://a/private/x", "Googlebot", "google", "google",
    safety_level = "crawler"
  )
  e <- x$evidence
  expect_identical(e$evidence_status, "usable_body")
  expect_identical(e$redirect_count, 1L)
  expect_identical(e$terminal_redirect_reason, "none")
  expect_true(is.na(e$safety_block_reason))
  expect_identical(e$final_http_status, 200L)
  expect_identical(e$safety_level, "crawler")
  expect_false(e$https_downgrade_guard)
  expect_false(x$results$https_downgrade_guard)
  hops <- e$redirect_hops[[1L]]
  expect_length(hops, 1L)
  expect_identical(hops[[1L]]$from_url, "https://a/robots.txt")
  expect_identical(hops[[1L]]$status, 301L)
  expect_identical(hops[[1L]]$location_target, "http://a/robots.txt")
  expect_identical(x$results$url_decision, "disallow")
})

test_that("strict still refuses the same chain as https_downgrade", {
  local_fake_ssrfr(cd_downgrade_chain())
  x <- robots_evaluate_url_v1(
    "https://a/private/x", "Googlebot", "google", "google",
    safety_level = "strict"
  )
  e <- x$evidence
  expect_identical(e$evidence_status, "safety_refused")
  expect_identical(e$safety_block_reason, "https_downgrade")
  expect_identical(e$terminal_redirect_reason, "downgrade")
  expect_identical(e$redirect_count, 0L)
  expect_true(e$https_downgrade_guard)
  expect_true(is.na(x$results$url_decision))
})

test_that("the legacy entry points follow the downgrade under crawler", {
  local_fake_ssrfr(cd_downgrade_chain())
  f <- robots_fetch("https://a/x", safety_level = "crawler")
  expect_identical(f$robots$fetch_outcome, "fetched")
  expect_identical(f$robots$redirect_count, 1L)
  expect_identical(f$robots$effective_url, "http://a/robots.txt")
  expect_identical(f$robots$terminal_redirect_reason, "none")

  d <- allowed_by_robots_url(
    "https://a/private/x", "Googlebot", safety_level = "crawler"
  )
  expect_false(d$results$allowed)

  v <- robots_validate_url("https://a/x", safety_level = "crawler")
  expect_false("acquisition_redirect_downgrade" %in% v$diagnostics$code)

  strict <- robots_fetch("https://a/x")
  expect_identical(strict$robots$fetch_outcome, "redirect_error")
  expect_identical(strict$robots$terminal_redirect_reason, "downgrade")
})

test_that("a downgrade spends the five-redirect budget like any hop", {
  # https://a/0 -> http://a/1 -> ... -> http://a/5 -> http://a/6: the sixth
  # redirect is over budget under crawler, the first one refused under strict.
  routes <- list(
    "https://a/robots.txt" = function(req) {
      fake_response(301L, headers = list(Location = "http://a/1"))
    }
  )
  for (i in 1:5) {
    routes[[sprintf("http://a/%d", i)]] <- local({
      next_url <- sprintf("http://a/%d", i + 1L)
      function(req) fake_response(301L, headers = list(Location = next_url))
    })
  }
  local_fake_ssrfr(cd_router(routes))
  e <- robots_evaluate_url_v1(
    "https://a/x", "Googlebot", "google", "google", safety_level = "crawler"
  )$evidence
  expect_identical(e$evidence_status, "redirect_over_budget")
  expect_identical(e$terminal_redirect_reason, "over_budget")
  expect_identical(e$redirect_count, 5L)
})

test_that("crawler keeps every other refusal: a loopback target is refused", {
  local_fake_ssrfr(cd_router(list(
    "https://a/robots.txt" = function(req) {
      fake_response(301L, headers = list(Location = "http://127.0.0.1/r"))
    }
  )))
  e <- robots_evaluate_url_v1(
    "https://a/x", "Googlebot", "google", "google", safety_level = "crawler"
  )$evidence
  expect_identical(e$safety_block_reason, "loopback")
  expect_identical(e$evidence_status, "safety_refused")
})

test_that("acquire_policy() sets allow_downgrade from the safety level", {
  expect_false(acquire_policy(10, "bot/1", 4096L)$allow_downgrade)
  expect_false(
    acquire_policy(10, "bot/1", 4096L, safety_level = "strict")$allow_downgrade
  )
  expect_true(
    acquire_policy(10, "bot/1", 4096L, safety_level = "crawler")$allow_downgrade
  )
})
