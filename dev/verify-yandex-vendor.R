#!/usr/bin/env Rscript
#
# Dev-time real-tree fidelity check for the vendored robotstxtyandex payload.
#
# Runs the fail-closed verifier (R/vendor-manifest-verify.R) against the real
# source tree under src/vendor/robotstxtyandex, using the frozen manifest at
# inst/vendor/robotstxtyandex/MANIFEST.dcf. Exits non-zero on any missing,
# extra, or byte-mismatched file.
#
# This lives under dev/ (Rbuildignored) on purpose: R does not install src/, so
# a check-time testthat test that read the vendored tree would run from the
# installed package where src/ is absent and fail. The fixture-driven verifier
# tests in tests/testthat/ cover the verifier logic; this script covers the
# real bytes and is meant to be run from the repo root during development and
# release prep.
#
# Usage (from the package root):
#   Rscript dev/verify-yandex-vendor.R

root <- "src/vendor/robotstxtyandex"
manifest_path <- "inst/vendor/robotstxtyandex/MANIFEST.dcf"

if (!file.exists(manifest_path)) {
  stop(sprintf("Manifest not found (run from the package root?): %s",
    manifest_path))
}

source(file.path("R", "vendor-manifest-verify.R"))

res <- verify_yandex_vendor_tree(root = root, manifest_path = manifest_path)

report_paths <- function(label, paths) {
  if (length(paths) > 0L) {
    message(sprintf("%s (%d):", label, length(paths)))
    message(paste0("  ", paths, collapse = "\n"))
  }
}

message(sprintf("Vendor tree:   %s", res$root))
message(sprintf("Manifest:      %s", res$manifest_path))
message(sprintf("Expected:      %d files", res$n_expected))
message(sprintf("Matched:       %d files", length(res$matched)))
report_paths("Missing", res$missing)
report_paths("Extra", res$extra)
report_paths("Mismatched", res$mismatched)

if (isTRUE(res$ok)) {
  message("OK: vendored robotstxtyandex tree matches the frozen manifest.")
} else {
  stop("FAIL: vendored robotstxtyandex tree does not match the manifest.")
}
