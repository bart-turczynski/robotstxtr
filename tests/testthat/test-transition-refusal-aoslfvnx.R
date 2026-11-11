# ROBO-aoslfvnx: the evidence a crawler records for an IPv6 transition
# literal ssrfr refuses. 6to4 and Teredo are `safety_refused` at both levels
# (ADR 0001 section 3); ISATAP and NAT64 stay `unreachable_local` under
# crawler. The real ssrfr classifies each literal (helper-fake-ssrfr.R,
# fake_prepare_hop()); nothing is dialed.

tr_public_6to4 <- "http://[2002:808:808::1]/x"
tr_loopback_6to4 <- "http://[2002:7f00:1::1]/x"
tr_teredo <- "http://[2001:0::1]/x"
tr_local_isatap <- "http://[fe80::5efe:5db8:d822]/x"
tr_local_nat64 <- "http://[64:ff9b::7f00:1]/x"

# Serve `url` (hop 1), or a 301 from http://a/ to it (hop 2). Returns an
# environment whose `fetches` counts the requests that reached the network.
tr_local_target <- function(url, on_hop = 1L, env = parent.frame()) {
  calls <- new.env(parent = emptyenv())
  calls$fetches <- 0L
  local_fake_ssrfr(function(req) {
    calls$fetches <- calls$fetches + 1L
    fake_response(301L, headers = list(Location = url))
  }, env = env)
  calls$url <- if (on_hop == 1L) url else "http://a/x"
  calls
}

tr_evidence <- function(calls, safety_level) {
  robots_evaluate_url_v1(
    calls$url, "Googlebot", "google", "google", safety_level = safety_level
  )$evidence
}

tr_code <- function(url) {
  ssrfr::ssrf_inspect_url(url, ssrfr::ssrf_policy())$code
}

test_that("ssrfr refuses each literal with the code these tests assume", {
  expect_identical(tr_code(tr_public_6to4), "6to4")
  expect_identical(tr_code(tr_loopback_6to4), "6to4")
  expect_identical(tr_code(tr_teredo), "teredo")
  expect_identical(tr_code(tr_local_isatap), "isatap")
  expect_identical(tr_code(tr_local_nat64), "nat64")
  # ISATAP under a global prefix around a routable IPv4 is admitted.
  expect_true(is.na(tr_code("http://[2600::5efe:a83f:8110]/x")))
})

# ssrfr refuses 6to4 and Teredo whatever IPv4 they wrap (reachability
# unknown), so calling 8.8.8.8 behind 2002::/16 internal would be false.
test_that("6to4 and Teredo targets are safety_refused under crawler", {
  cases <- list(
    list(url = tr_public_6to4, code = "6to4"),
    list(url = tr_teredo, code = "teredo")
  )
  for (case in cases) {
    for (hop in 1:2) {
      local({
        calls <- tr_local_target(case$url, on_hop = hop)
        e <- tr_evidence(calls, "crawler")
        label <- paste(case$code, "hop", hop)
        expect_identical(e$evidence_status, "safety_refused", info = label)
        expect_identical(e$safety_block_reason, case$code, info = label)
        expect_identical(e$legacy_fetch_outcome, "ssrf_blocked", info = label)
        expect_identical(calls$fetches, hop - 1L, info = label)
      })
    }
  }
})

# Accepted consequence: robotstxtr does not unwrap the IPv4 itself, so a 6to4
# literal around loopback is safety_refused too.
test_that("a 6to4 literal wrapping loopback is safety_refused", {
  calls <- tr_local_target(tr_loopback_6to4)
  e <- tr_evidence(calls, "crawler")
  expect_identical(e$evidence_status, "safety_refused")
  expect_identical(e$safety_block_reason, "6to4")
})

# ssrfr refuses ISATAP only under a non-global prefix or around a prohibited
# IPv4, both internal facts, so it keeps the address class.
test_that("ISATAP and NAT64 refusals stay unreachable_local under crawler", {
  classed <- acquire_address_class_reasons()
  expect_true(all(c("isatap", "nat64") %in% classed))
  expect_false(any(c("6to4", "teredo") %in% classed))
  cases <- list(
    list(url = tr_local_isatap, code = "isatap"),
    list(url = tr_local_nat64, code = "nat64")
  )
  for (case in cases) {
    for (hop in 1:2) {
      local({
        calls <- tr_local_target(case$url, on_hop = hop)
        e <- tr_evidence(calls, "crawler")
        label <- paste(case$code, "hop", hop)
        expect_identical(e$evidence_status, "unreachable_local", info = label)
        expect_identical(e$safety_block_reason, case$code, info = label)
        expect_identical(calls$fetches, hop - 1L, info = label)
      })
    }
  }
})

test_that("every transition literal is safety_refused under strict", {
  urls <- c(tr_public_6to4, tr_loopback_6to4, tr_teredo, tr_local_isatap)
  for (url in urls) {
    local({
      calls <- tr_local_target(url)
      e <- tr_evidence(calls, "strict")
      expect_identical(e$evidence_status, "safety_refused", info = url)
      expect_identical(e$safety_block_reason, tr_code(url), info = url)
      expect_identical(calls$fetches, 0L, info = url)
    })
  }
})
