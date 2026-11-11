# ROBO-jqwukcog: under `safety_level = "crawler"` an address-class refusal is
# recorded as `evidence_status = unreachable_local` (ADR 0001 section 3, slice
# 4). The address is never dialed, the L0 record is unchanged
# (`fetch_outcome = ssrf_blocked`, the code in `safety_block_reason`), and the
# ruleset reads it as it reads an unreachable file. URL-shape refusals stay
# `safety_refused` at both levels. Offline: refusals are scripted at the ssrfr
# boundary (helper-fake-ssrfr.R).

# ADR 0001 section 3 and design/engine-profiles.md section 3a, by hand.
ul_address_codes <- c(
  "loopback", "private", "link-local", "cloud-metadata", "shared",
  "unspecified", "this-network", "multicast", "reserved", "ipv4-mapped",
  "ipv4-translated", "ipv4-compatible", "nat64", "6to4", "teredo", "isatap"
)
ul_url_shape_codes <- c(
  "scheme", "userinfo", "port", "parse", "numeric-literal",
  "malformed-address"
)

ul_rulesets <- c("google", "yandex", "rfc9309", "bing", "assumed_rfc9309")

# Refuse `code` on hop `on_hop` (1: the robots URL itself; 2: the target of
# a 301 the first hop returns). Every other hop goes through the ordinary
# fake. Returns an environment whose `fetches` counts acquire_fetch() calls.
ul_local_refusal <- function(code, on_hop = 1L, env = parent.frame()) {
  calls <- new.env(parent = emptyenv())
  calls$fetches <- 0L
  handler <- function(req) {
    fake_response(301L, headers = list(Location = "http://b/robots.txt"))
  }
  testthat::local_mocked_bindings(
    acquire_prepare_hop = function(url, policy, request = NULL, from = NULL) {
      hop <- if (is.null(from)) 1L else from$hop + 1L
      if (hop == on_hop) {
        return(fake_refusal(code, hop = hop))
      }
      fake_prepare_hop(url, policy, from)
    },
    acquire_fetch = function(binding) {
      calls$fetches <- calls$fetches + 1L
      fake_fetch(binding, handler)
    },
    .package = "robotstxtr",
    .env = env
  )
  calls
}

ul_evaluate <- function(safety_level, rulesets = "google") {
  robots_evaluate_url_v1(
    rep("http://a/x", length(rulesets)), "Googlebot", rulesets, "google",
    safety_level = safety_level
  )
}

# --- the classification -------------------------------------------------------

test_that("every admitted refusal with a safety reason has a class", {
  table <- acquire_refusal_table()
  codes <- ssrfr::ssrf_vocabulary("reason_codes")$code
  expect_setequal(table$code, codes)
  reasoned <- table[table$admitted & !is.na(table$safety_block_reason), ,
                    drop = FALSE]
  expect_length(reasoned$class, nrow(reasoned))
  expect_true(all(reasoned$class %in% c("address", "url_shape", "redirect")),
              info = toString(reasoned$code[is.na(reasoned$class)]))
  expect_setequal(table$code[table$class %in% "address"], ul_address_codes)
  expect_setequal(table$code[table$class %in% "url_shape"],
                  ul_url_shape_codes)
  expect_setequal(acquire_address_class_reasons(), ul_address_codes)
})

# --- the vocabulary walk --------------------------------------------------------

test_that("every address-class code is unreachable_local under crawler", {
  for (code in ul_address_codes) {
    local({
      calls <- ul_local_refusal(code, on_hop = 1L)
      e <- ul_evaluate("crawler")$evidence
      expect_identical(e$evidence_status, "unreachable_local", info = code)
      expect_identical(e$legacy_fetch_outcome, "ssrf_blocked", info = code)
      expect_identical(e$safety_block_reason, code, info = code)
      expect_identical(e$redirect_count, 0L, info = code)
      expect_identical(calls$fetches, 0L, info = code)
    })
  }
})

test_that("a redirect to an address-class target is unreachable_local", {
  for (code in ul_address_codes) {
    local({
      calls <- ul_local_refusal(code, on_hop = 2L)
      e <- ul_evaluate("crawler")$evidence
      expect_identical(e$evidence_status, "unreachable_local", info = code)
      expect_identical(e$legacy_fetch_outcome, "ssrf_blocked", info = code)
      expect_identical(e$safety_block_reason, code, info = code)
      expect_identical(e$redirect_count, 1L, info = code)
      # Only the 3xx was fetched; the refused target was never dialed.
      expect_identical(calls$fetches, 1L, info = code)
    })
  }
})

test_that("the same refusals stay safety_refused under strict", {
  for (code in ul_address_codes) {
    for (hop in 1:2) {
      local({
        calls <- ul_local_refusal(code, on_hop = hop)
        e <- ul_evaluate("strict")$evidence
        label <- paste(code, "hop", hop)
        expect_identical(e$evidence_status, "safety_refused", info = label)
        expect_identical(e$legacy_fetch_outcome, "ssrf_blocked", info = label)
        expect_identical(e$safety_block_reason, code, info = label)
        expect_identical(calls$fetches, hop - 1L, info = label)
      })
    }
  }
})

test_that("URL-shape refusals stay safety_refused under crawler", {
  for (code in ul_url_shape_codes) {
    local({
      calls <- ul_local_refusal(code, on_hop = 1L)
      e <- ul_evaluate("crawler")$evidence
      expect_identical(e$evidence_status, "safety_refused", info = code)
      expect_identical(e$safety_block_reason, code, info = code)
      expect_identical(calls$fetches, 0L, info = code)
    })
  }
})

test_that("a real loopback target under crawler is unreachable_local", {
  local_fake_ssrfr(function(req) {
    fake_response(301L, headers = list(Location = "http://127.0.0.1/r"))
  })
  e <- ul_evaluate("crawler")$evidence
  expect_identical(e$evidence_status, "unreachable_local")
  expect_identical(e$safety_block_reason, "loopback")
  expect_identical(e$safety_level, "crawler")
})

# --- the policy reading ---------------------------------------------------------

test_that("no ruleset turns unreachable_local into allow or deny", {
  ul_local_refusal("private", on_hop = 1L)
  r <- ul_evaluate("crawler", ul_rulesets)$results
  want <- c(
    google = "context_required", yandex = "documentation_gap",
    rfc9309 = "context_required", bing = "documentation_gap",
    assumed_rfc9309 = "context_required"
  )
  expect_identical(r$evidence_status, rep("unreachable_local", 5L))
  expect_identical(r$policy_status, unname(want[r$robots_policy_ruleset]))
  expect_true(all(is.na(r$policy_action)))
  expect_true(all(is.na(r$url_decision)))
  expect_identical(r$matcher_status, rep("not_evaluated", 5L))
  google <- r[r$robots_policy_ruleset == "google", , drop = FALSE]
  expect_identical(google$policy_reason, "crawler_lifecycle_context_required")
  expect_identical(google$policy_provenance, "documented")
  expect_identical(google$policy_source,
                   "design/engine-profiles.md#status-policy")
  assumed <- r[r$robots_policy_ruleset == "assumed_rfc9309", , drop = FALSE]
  expect_identical(assumed$policy_provenance, "application_choice")
})

test_that("resolve_policy_v1() reads unreachable_local by its own rows", {
  table <- engine_policy_table_v1()
  evidence <- list(
    evidence_status = "unreachable_local", source_kind = "fetched",
    final_http_status = NA_integer_, stored_bytes = 0L
  )
  for (ruleset in ul_rulesets) {
    row <- table[table$category == "unreachable_local" &
                   table$ruleset == ruleset, , drop = FALSE]
    expect_identical(nrow(row), 1L, label = ruleset)
    got <- resolve_policy_v1(evidence, ruleset, table)
    expect_identical(got$policy_status, row$policy_status, label = ruleset)
    expect_identical(got$policy_reason, row$policy_reason, label = ruleset)
    expect_identical(got$policy_provenance, row$policy_provenance,
                     label = ruleset)
    expect_identical(got$policy_source, row$policy_source, label = ruleset)
  }
})

test_that("the contract publishes an unreachable_local row per ruleset", {
  table <- robots_engine_contract_v1()$policy_table
  local <- table[table$category == "unreachable_local", , drop = FALSE]
  transport <- table[table$category == "transport", , drop = FALSE]
  expect_setequal(local$ruleset, engine_rulesets_v1())
  cells <- c("policy_status", "policy_action", "policy_reason",
             "policy_provenance", "policy_source")
  local <- local[order(local$ruleset), cells]
  transport <- transport[order(transport$ruleset), cells]
  rownames(local) <- NULL
  rownames(transport) <- NULL
  expect_identical(local, transport)
  expect_identical(engine_schema_revision_v1(), "2026-11-11.1")
  expect_identical(engine_schema_revision_v2(), "2026-11-11.1")
})

# --- the legacy frame and the invariants ----------------------------------------

test_that("the legacy frame reports a crawler address refusal as ssrf_blocked", {
  ul_local_refusal("link-local", on_hop = 2L)
  legacy <- as_legacy_robots_decisions_v1(ul_evaluate("crawler"))
  expect_identical(legacy$robots$fetch_outcome, "ssrf_blocked")
  expect_identical(legacy$robots$safety_block_reason, "link-local")
})

test_that("a safety reason means safety_refused or unreachable_local only", {
  cases <- list(
    list(code = "loopback", level = "crawler"),
    list(code = "loopback", level = "strict"),
    list(code = "port", level = "crawler"),
    list(code = "port", level = "strict")
  )
  for (case in cases) {
    local({
      ul_local_refusal(case$code, on_hop = 1L)
      e <- ul_evaluate(case$level)$evidence
      expect_true(
        e$evidence_status %in% c("safety_refused", "unreachable_local"),
        info = paste(case$code, case$level)
      )
      if (identical(e$evidence_status, "unreachable_local")) {
        expect_identical(e$safety_level, "crawler")
      }
    })
  }
  # A transport failure never carries a safety reason.
  local({
    local_fake_ssrfr(function(req) fake_failure("connect-failed"))
    e <- ul_evaluate("crawler")$evidence
    expect_identical(e$evidence_status, "transport_fail")
    expect_true(is.na(e$safety_block_reason))
  })
})

test_that("an unset safety reason keeps every other status under crawler", {
  result <- function(...) {
    defaults <- list(
      safety_block_reason = NA_character_, termination_reason = "complete",
      fetch_outcome = "fetched", terminal_redirect_reason = "none",
      http_status = 200L
    )
    utils::modifyList(defaults, list(...))
  }
  for (level in c("strict", "crawler")) {
    expect_identical(
      source_evidence_status_v1(result(), safety_level = level), "usable_body"
    )
    expect_identical(
      source_evidence_status_v1(
        result(fetch_outcome = "network_error", http_status = NA_integer_),
        safety_level = level
      ),
      "transport_fail"
    )
  }
  expect_identical(
    source_evidence_status_v1(result(safety_block_reason = "private")),
    "safety_refused"
  )
  expect_identical(
    source_evidence_status_v1(
      result(safety_block_reason = "https_downgrade"), safety_level = "crawler"
    ),
    "safety_refused"
  )
})

test_that("ssrf_guard = FALSE under crawler dials a reopened range", {
  # ADR 0001 section 6: a reopened range is fetched, so it is never
  # unreachable_local.
  local_fake_ssrfr(function(req) {
    fake_response(200L, body = "user-agent: *\ndisallow: /private\n")
  })
  expect_warning(
    x <- robots_evaluate_url_v1(
      "http://10.0.0.1/x", "Googlebot", "google", "google",
      ssrf_guard = FALSE, safety_level = "crawler"
    ),
    class = "robotstxtr_deprecated_ssrf_guard"
  )
  expect_identical(x$evidence$evidence_status, "usable_body")
  expect_true(is.na(x$evidence$safety_block_reason))
})
