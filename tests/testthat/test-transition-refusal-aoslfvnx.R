# ROBO-aoslfvnx: the evidence a crawler records for an IPv6 transition
# literal ssrfr refuses. 6to4, Teredo and ISATAP are `safety_refused` at both
# levels (ADR 0001 section 3); NAT64 stays `unreachable_local` under crawler.
# The real ssrfr classifies each literal (helper-fake-ssrfr.R,
# fake_prepare_hop()); nothing is dialed.

tr_public_6to4 <- "http://[2002:808:808::1]/x"
tr_loopback_6to4 <- "http://[2002:7f00:1::1]/x"
# Teredo obfuscates the client IPv4: f7f7:f7f7 is 8.8.8.8.
tr_public_teredo <- "http://[2001::f7f7:f7f7]/x"
tr_reserved_teredo <- "http://[2001:0::1]/x"
# A global prefix around 10.0.0.1: an ISATAP router can serve it publicly.
tr_global_isatap <- "http://[2600::5efe:a00:1]/x"
tr_local_isatap <- "http://[fe80::5efe:5db8:d822]/x"
tr_local_nat64 <- "http://[64:ff9b::7f00:1]/x"

tr_transition <- list(
  list(url = tr_public_6to4, code = "6to4"),
  list(url = tr_loopback_6to4, code = "6to4"),
  list(url = tr_public_teredo, code = "teredo"),
  list(url = tr_reserved_teredo, code = "teredo"),
  list(url = tr_global_isatap, code = "isatap"),
  list(url = tr_local_isatap, code = "isatap")
)

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
  for (case in tr_transition) {
    expect_identical(tr_code(case$url), case$code, info = case$url)
  }
  expect_identical(tr_code(tr_local_nat64), "nat64")
  # ISATAP under a global prefix around a routable IPv4 is admitted.
  expect_true(is.na(tr_code("http://[2600::5efe:a83f:8110]/x")))
})

# None of these refusals says the target is internal: ssrfr refuses 6to4 and
# Teredo whatever IPv4 they wrap, and ISATAP around a private IPv4 under a
# global prefix. robotstxtr does not unwrap the IPv4, so the internal-looking
# ones (loopback 6to4, link-local ISATAP) are safety_refused too.
test_that("6to4, Teredo and ISATAP targets are safety_refused under crawler", {
  classed <- acquire_address_class_reasons()
  expect_false(any(c("6to4", "teredo", "isatap") %in% classed))
  for (case in tr_transition) {
    for (hop in 1:2) {
      local({
        calls <- tr_local_target(case$url, on_hop = hop)
        e <- tr_evidence(calls, "crawler")
        label <- paste(case$url, "hop", hop)
        expect_identical(e$evidence_status, "safety_refused", info = label)
        expect_identical(e$safety_block_reason, case$code, info = label)
        expect_identical(e$legacy_fetch_outcome, "ssrf_blocked", info = label)
        expect_identical(calls$fetches, hop - 1L, info = label)
      })
    }
  }
})

test_that("a NAT64 refusal stays unreachable_local under crawler", {
  expect_true("nat64" %in% acquire_address_class_reasons())
  for (hop in 1:2) {
    local({
      calls <- tr_local_target(tr_local_nat64, on_hop = hop)
      e <- tr_evidence(calls, "crawler")
      label <- paste("hop", hop)
      expect_identical(e$evidence_status, "unreachable_local", info = label)
      expect_identical(e$safety_block_reason, "nat64", info = label)
      expect_identical(calls$fetches, hop - 1L, info = label)
    })
  }
})

test_that("6to4, Teredo and ISATAP targets are safety_refused under strict", {
  for (case in tr_transition) {
    local({
      calls <- tr_local_target(case$url)
      e <- tr_evidence(calls, "strict")
      expect_identical(e$evidence_status, "safety_refused", info = case$url)
      expect_identical(e$safety_block_reason, case$code, info = case$url)
      expect_identical(calls$fetches, 0L, info = case$url)
    })
  }
})

test_that("a NAT64 refusal is safety_refused under strict", {
  calls <- tr_local_target(tr_local_nat64)
  e <- tr_evidence(calls, "strict")
  expect_identical(e$evidence_status, "safety_refused")
  expect_identical(e$safety_block_reason, "nat64")
  expect_identical(calls$fetches, 0L)
})
