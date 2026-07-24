#!/usr/bin/env Rscript
#
# Dev-time / CI vendored-fidelity gate for the vendored robotstxtbing payload
# (ROBO-onwulhga, BI6; spec SS16.2). Runs fully OFFLINE from a clean tree with
# NO sibling robotstxtbing repository.
#
# It proves, in order:
#   A. Byte fidelity — every vendored file under src/vendor/robotstxtbing matches
#      the frozen inst/vendor/robotstxtbing/MANIFEST.dcf, with no missing, extra,
#      or byte-mismatched file (via verify_bing_vendor_tree).
#   B. Separation — package-owned binding/build code (the cpp11 binding, the
#      adapter, the native/corpus R, the Makevars) is EXCLUDED from the vendor
#      manifest, and every manifest file lives under the vendor root.
#   C. Legal/provenance survival — the payload's own Apache-2.0 LICENSE and
#      NOTICE are present under the vendor root and declared `legal` in the
#      manifest; the manifest and PROVENANCE ship under inst/vendor; and the
#      shipped Bing conformance corpus verifies clean offline (verify_bing_corpus).
#   D. Engine equivalence (optional, requires a loadable compiled package) — a
#      compact integration corpus of shipped cases is driven through the public
#      v2 facade and each result must equal the recorded golden snapshot AND the
#      independently observed tester decision. When the package cannot be loaded
#      (a base-R CI runner), phase D is delegated to the compiled check job's
#      tests/testthat/test-bing-corpus-onwulhga.R, which runs the full 191-case
#      equivalence, and this script reports the delegation rather than skipping
#      silently.
#
# Phases A-C are base R + jsonlite only (no compilation, no package load, no
# sibling). This lives under dev/ (Rbuildignored) because R does not install
# src/, so a check-time testthat test that read the vendored tree would run from
# the installed package where src/ is absent and fail.
#
# Usage (from the package root):
#   Rscript dev/verify-bing-vendor.R

vendor_root <- "src/vendor/robotstxtbing"
manifest_path <- "inst/vendor/robotstxtbing/MANIFEST.dcf"
corpus_dir <- "inst/bing-corpus"

if (!file.exists(manifest_path)) {
  stop(sprintf("Manifest not found (run from the package root?): %s",
               manifest_path))
}

source(file.path("R", "vendor-manifest-verify.R"))
source(file.path("R", "bing-corpus.R"))

failures <- character(0)
note_fail <- function(msg) failures <<- c(failures, msg)

report_paths <- function(label, paths) {
  if (length(paths) > 0L) {
    message(sprintf("%s (%d):", label, length(paths)))
    message(paste0("  ", paths, collapse = "\n"))
  }
}

# ---- Phase A: byte fidelity -------------------------------------------------
message("== Phase A: vendored byte fidelity ==")
res <- verify_bing_vendor_tree(root = vendor_root, manifest_path = manifest_path)
message(sprintf("Vendor tree:   %s", res$root))
message(sprintf("Manifest:      %s", res$manifest_path))
message(sprintf("Expected:      %d files", res$n_expected))
message(sprintf("Matched:       %d files", length(res$matched)))
report_paths("Missing", res$missing)
report_paths("Extra", res$extra)
report_paths("Mismatched", res$mismatched)
if (!isTRUE(res$ok)) {
  note_fail("A: vendored tree does not match the frozen manifest.")
} else {
  message("OK: vendored robotstxtbing tree matches the frozen manifest.")
}

# ---- Phase B: package-owned code is excluded from the vendor manifest -------
message("\n== Phase B: package-owned binding/build code excluded ==")
parsed <- read_bing_vendor_manifest(manifest_path)
manifest_files <- parsed$files$file
# Every declared file lives under the vendor root (fails closed otherwise).
bad_root <- manifest_files[!startsWith(manifest_files,
                                       paste0(parsed$vendor_root, "/"))]
if (length(bad_root) > 0L) {
  note_fail(sprintf("B: manifest file(s) outside vendor root: %s",
                    toString(bad_root)))
}
package_owned <- c(
  "src/bing_binding.cpp",
  "src/Makevars",
  "src/Makevars.win",
  "R/bing-native.R",
  "R/match-bing-v1.R",
  "R/bing-corpus.R",
  "R/engine-contract-v1.R",
  "dev/gen-bing-corpus.R",
  "dev/verify-bing-vendor.R"
)
leaked <- intersect(package_owned, manifest_files)
if (length(leaked) > 0L) {
  note_fail(sprintf("B: package-owned file(s) present in vendor manifest: %s",
                    toString(leaked)))
} else {
  message(sprintf(
    "OK: %d vendor files, all under %s; no package-owned code in the manifest.",
    length(manifest_files), parsed$vendor_root
  ))
}

# ---- Phase C: Apache-2.0 legal + provenance survival ------------------------
message("\n== Phase C: Apache-2.0 legal + provenance survival ==")
dcf <- read.dcf(manifest_path)
is_file <- !is.na(dcf[, "File"])
file_rows <- dcf[is_file, , drop = FALSE]
category <- if ("Category" %in% colnames(file_rows)) {
  file_rows[, "Category"]
} else {
  rep(NA_character_, nrow(file_rows))
}
legal_files <- file_rows[!is.na(category) & category == "legal", "File"]
want_legal <- c(
  file.path(vendor_root, "LICENSE"),
  file.path(vendor_root, "NOTICE")
)
for (lf in want_legal) {
  if (!lf %in% legal_files) {
    note_fail(sprintf("C: %s is not declared 'legal' in the manifest.", lf))
  }
  if (!file.exists(lf)) {
    note_fail(sprintf("C: legal file missing on disk: %s", lf))
  }
}
# The LICENSE must actually be the Apache-2.0 text.
lic_path <- file.path(vendor_root, "LICENSE")
if (file.exists(lic_path)) {
  lic <- paste(readLines(lic_path, warn = FALSE), collapse = "\n")
  if (!grepl("Apache License", lic, fixed = TRUE) ||
        !grepl("Version 2.0", lic, fixed = TRUE)) {
    note_fail("C: vendor LICENSE is not the Apache-2.0 license text.")
  }
}
for (f in c("MANIFEST.dcf", "PROVENANCE")) {
  p <- file.path("inst", "vendor", "robotstxtbing", f)
  if (!file.exists(p)) {
    note_fail(sprintf("C: inst vendor artifact missing: %s", p))
  }
}
# The shipped conformance corpus verifies clean offline.
if (!dir.exists(corpus_dir)) {
  note_fail(sprintf("C: Bing corpus directory missing: %s", corpus_dir))
} else {
  cres <- verify_bing_corpus(corpus_dir)
  if (!isTRUE(cres$ok)) {
    note_fail(sprintf("C: Bing corpus failed offline verification:\n%s",
                      paste(cres$errors, collapse = "\n")))
  } else {
    message(sprintf(
      "OK: legal material present; corpus verifies (%d cases, %d bodies).",
      cres$n_records, cres$n_bodies
    ))
  }
}

# ---- Phase D: vendored-engine equivalence on a compact corpus ---------------
message("\n== Phase D: vendored engine == golden == tester (compact corpus) ==")
loadable <- requireNamespace("pkgload", quietly = TRUE) &&
  !inherits(try(suppressMessages(pkgload::load_all(".", quiet = TRUE)),
                silent = TRUE), "try-error")
native_ok <- loadable &&
  is.function(tryCatch(get("robotstxtr_bing_eval_batch_"),
                       error = function(e) NULL))
if (!native_ok) {
  message(paste0(
    "Delegated: package/native binding not loadable here. The full 191-case ",
    "equivalence runs in the compiled check job via ",
    "tests/testthat/test-bing-corpus-onwulhga.R."
  ))
} else {
  records <- read_bing_corpus(corpus_dir)
  # Compact integration corpus: up to two cases per source unit.
  units <- vapply(records, function(r) r$unit, character(1))
  pick <- unlist(lapply(unique(units), function(u) {
    idx <- which(units == u)
    idx[seq_len(min(2L, length(idx)))]
  }))
  compact <- records[sort(pick)]
  hex2raw <- function(h) {
    if (!nzchar(h)) {
      return(raw(0))
    }
    as.raw(strtoi(substring(h, seq(1L, nchar(h), 2L), seq(2L, nchar(h), 2L)),
                  16L))
  }
  mismatches <- character(0)
  for (rec in compact) {
    body <- rawToChar(readBin(file.path(corpus_dir, rec$body_file), "raw",
                              n = as.integer(rec$byte_size)))
    Encoding(body) <- "bytes"
    url <- paste0("https://example.test", rec$request_target)
    r <- robotstxtr::robots_evaluate_text_v1(
      robots_txt = body, url = url, robots_product_token = rec$profile,
      robots_policy_ruleset = "assumed_rfc9309", matcher_backend = "bing"
    )$results
    exp <- rec$matcher_expected
    ok <- identical(r$matcher_status[[1L]], "evaluated") &&
      identical(r$url_decision[[1L]], exp$url_decision) &&
      identical(r$url_decision[[1L]], rec$tester_observed$decision) &&
      identical(r$reason[[1L]], exp$reason)
    if (!is.null(exp$matched_rule)) {
      raw_1 <- r$matched_rule_value_raw[[1L]]
      ok <- ok &&
        identical(r$matched_line[[1L]], as.integer(exp$matched_rule$line)) &&
        identical(r$matched_rule_type[[1L]], exp$matched_rule$type) &&
        identical(r$matched_rule_value[[1L]], exp$matched_rule$value) &&
        identical(raw_1, hex2raw(exp$matched_rule$value_raw_hex))
    }
    if (!ok) mismatches <- c(mismatches, rec$case_id)
  }
  if (length(mismatches) > 0L) {
    note_fail(sprintf("D: %d compact-corpus case(s) diverged: %s",
                      length(mismatches), toString(mismatches)))
  } else {
    message(sprintf(
      "OK: %d compact-corpus cases match the vendored engine exactly.",
      length(compact)
    ))
  }
}

# ---- Verdict ----------------------------------------------------------------
message("")
if (length(failures) > 0L) {
  for (f in failures) message(sprintf("FAIL %s", f))
  stop("FAIL: vendored robotstxtbing fidelity gate did not pass.")
}
message("PASS: vendored robotstxtbing fidelity gate passed.")
