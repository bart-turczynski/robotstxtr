# The translation tables of the acquisition module (R/acquire.R,
# ROBO-jbralthm), as data: ssrfr's refusal codes to robotstxtr's
# (fetch_outcome, terminal_redirect_reason, safety_block_reason), and its
# failure causes to robotstxtr's transport outcome. A test walks
# ssrf_vocabulary("reason_codes") and ssrf_vocabulary("causes") in full, so a
# code or cause ssrfr adds fails a test instead of falling through.

# Every ssrfr reason code. `admitted` says whether robotstxtr's published
# `safety_block_reason` set (design/engine-profiles.md section 2) carries it.
# A refusal whose code is not admitted is a defect here, since the policy
# acquire_policy() builds cannot produce it (it states no deny rules), and it
# aborts rather than reach a result row.
#
# The 17 codes robotstxtr's own guard published pass through unchanged; ssrfr
# adds "userinfo", "port", "parse", "multicast" and "reserved", which the
# schema revision of 2026-11-05 admits. "downgrade" keeps its published name,
# `https_downgrade`.
#
# The `redirect_*` columns apply to a refusal of a redirect target (hop 2 and
# later). Only "scheme" differs there: a non-HTTP(S) Location is a
# `redirect_error` / `non_http_target`, as before ssrfr. A downgrade only ever
# happens on a redirect. "redirect-limit" cannot occur under the
# budget-plus-one policy; if it does, it is the `over_budget` it stands for.
acquire_refusal_table <- function() {
  shared <- c(
    "loopback", "private", "link-local", "cloud-metadata", "shared",
    "unspecified", "this-network", "ipv4-mapped", "ipv4-translated",
    "ipv4-compatible", "nat64", "6to4", "teredo", "isatap",
    "malformed-address", "numeric-literal", "scheme"
  )
  added <- c("userinfo", "port", "parse", "multicast", "reserved")
  guarded <- c(shared, added)
  rows <- data.frame(
    code = c(guarded, "downgrade", "host-denied", "range-denied",
             "redirect-limit"),
    admitted = c(rep(TRUE, length(guarded)), TRUE, FALSE, FALSE, TRUE),
    fetch_outcome = c(rep("ssrf_blocked", length(guarded)),
                      "redirect_error", NA, NA, "redirect_error"),
    terminal_redirect_reason = c(rep("none", length(guarded)),
                                 "downgrade", NA, NA, "over_budget"),
    safety_block_reason = c(guarded, "https_downgrade", NA, NA, NA),
    stringsAsFactors = FALSE
  )
  rows$redirect_fetch_outcome <- rows$fetch_outcome
  rows$redirect_terminal_redirect_reason <- rows$terminal_redirect_reason
  scheme <- rows$code == "scheme"
  rows$redirect_fetch_outcome[scheme] <- "redirect_error"
  rows$redirect_terminal_redirect_reason[scheme] <- "non_http_target"
  rows
}

# Every ssrfr failure cause, to a robotstxtr transport outcome, which is also
# its `transport_error_kind`. "response-too-large" splits on the limit
# reached (`detail$check`): the decoded body over `max_bytes` is
# `body_too_large` (a 2xx body the policy's `truncate_body` cut is a response,
# never this failure), any other limit (a header limit) a `network_error`. A row
# with `check = NA` matches any check. acquire_failure_result() reads the
# status before this table for a body over `max_bytes` on a 4xx or 5xx, and
# for several Location fields on a 3xx.
acquire_cause_table <- function() {
  data.frame(
    cause = c("unresolvable", "pin-mismatch", "connect-failed", "tls-failed",
              "timeout", "response-too-large", "response-too-large",
              "protocol-error"),
    check = c(NA, NA, NA, NA, NA, "decoded-bytes", NA, NA),
    fetch_outcome = c("network_error", "network_error", "network_error",
                      "tls_error", "timeout", "body_too_large",
                      "network_error", "network_error"),
    stringsAsFactors = FALSE
  )
}

# The `safety_block_reason` values robotstxtr publishes: the admitted codes
# under their published names. design/engine-profiles.md section 2 lists the
# same set.
acquire_safety_block_reasons <- function() {
  table <- acquire_refusal_table()
  reasons <- table$safety_block_reason[table$admitted]
  reasons[!is.na(reasons)]
}

acquire_refusal_row <- function(code) {
  table <- acquire_refusal_table()
  row <- table[table$code %in% code, , drop = FALSE]
  if (nrow(row) != 1L || !isTRUE(row$admitted)) {
    robots_abort(
      sprintf("ssrfr refusal code outside robotstxtr's mapping: %s.",
              toString(code)),
      "robotstxtr_acquisition_invariant"
    )
  }
  row
}

acquire_cause_row <- function(cause, check = NULL) {
  table <- acquire_cause_table()
  rows <- table[table$cause %in% cause, , drop = FALSE]
  exact <- rows[!is.na(rows$check) & rows$check %in% check, , drop = FALSE]
  if (nrow(exact) == 1L) {
    return(exact)
  }
  rows <- rows[is.na(rows$check), , drop = FALSE]
  if (nrow(rows) != 1L) {
    robots_abort(
      sprintf("ssrfr failure cause outside robotstxtr's mapping: %s.",
              toString(cause)),
      "robotstxtr_acquisition_invariant"
    )
  }
  rows
}
