#!/usr/bin/env Rscript
#
# Offline PACKAGE + LEGAL build-scope audit (ROBO-svbsdjns, YI6f).
#
# Proves the SOURCE / BINARY packaging disposition of both engines' legal and
# provenance material and of the vendored robotstxtyandex payload, with NO
# network and NO sibling checkout. It builds the source tarball (applying
# .Rbuildignore), audits which files survive into it, verifies the EXACT
# vendored bytes against the frozen manifest inside the extracted tarball, and
# (best effort) installs the tarball to confirm src/ is compiled-only.
#
# This lives under dev/ (Rbuildignored) on purpose: it needs a build, so it is
# NOT run at R CMD check time. The check-time, installed-package audits live in
# tests/testthat/test-package-legal-audit-svbsdjns.R. The network CRAN-incoming
# check stays a separate release audit; this script is an offline dev / CI gate.
#
# Usage (from the package root):
#   Rscript dev/audit-package.R

root_dir <- normalizePath(".", mustWork = TRUE)
manifest_path <- file.path(
  root_dir, "inst", "vendor", "robotstxtyandex", "MANIFEST.dcf"
)
if (!file.exists(manifest_path)) {
  stop(sprintf("Run from the package root? Manifest not found: %s",
    manifest_path))
}

state <- new.env(parent = emptyenv())
state$failures <- character(0)

check <- function(ok, label) {
  status <- if (isTRUE(ok)) "PASS" else "FAIL"
  message(sprintf("  [%s] %s", status, label))
  if (!isTRUE(ok)) {
    state$failures <- c(state$failures, label)
  }
  invisible(isTRUE(ok))
}

# ---------------------------------------------------------------------------
# 1. Build the source tarball, applying .Rbuildignore.
# ---------------------------------------------------------------------------

build_dir <- tempfile("robotstxtr-audit-build-")
dir.create(build_dir)
message("Building source tarball (applying .Rbuildignore)...")
tarball <- pkgbuild::build(
  path = root_dir,
  dest_path = build_dir,
  vignettes = FALSE,
  manual = FALSE,
  quiet = TRUE
)
message(sprintf("Tarball: %s", tarball))

entries <- untar(tarball, list = TRUE)
# Normalize away the leading "robotstxtr/" package directory component.
rel <- sub("^[^/]+/", "", entries)
rel <- rel[nzchar(rel)]

has_path <- function(path) {
  path %in% rel
}
has_prefix <- function(prefix) {
  any(startsWith(rel, prefix))
}
has_suffix <- function(suffix) {
  any(endsWith(rel, suffix))
}

# ---------------------------------------------------------------------------
# 2a. PRESENT -- both engines' legal / provenance + the vendored payload.
# ---------------------------------------------------------------------------

message("\nPRESENT (must survive into the source tarball):")
present_paths <- c(
  "inst/APACHE-2.0-LICENSE",
  "inst/NOTICE",
  "inst/PROVENANCE",
  "inst/vendor/robotstxtyandex/MANIFEST.dcf",
  "inst/vendor/robotstxtyandex/PROVENANCE",
  "src/vendor/robotstxtyandex/LICENSE",
  "src/vendor/robotstxtyandex/NOTICE",
  "src/vendor/robotstxtyandex/src/policy.cc",
  "src/vendor/robotstxtyandex/src/access_matcher.cc",
  "src/vendor/robotstxtyandex/include/robotstxtyandex/policy.h",
  "src/vendor/robotstxtyandex/include/robotstxtyandex/version.h"
)
for (path in present_paths) {
  check(has_path(path), sprintf("present: %s", path))
}

# ---------------------------------------------------------------------------
# 2b. ABSENT -- no prohibited dev / build files leaked into the tarball.
# ---------------------------------------------------------------------------

message("\nABSENT (must NOT appear in the source tarball):")
absent_prefixes <- c(
  "_scratch/", ".fp/", ".claude/", "dev/", "design/", "docs/", ".github/"
)
for (prefix in absent_prefixes) {
  check(!has_prefix(prefix), sprintf("absent dir: %s", prefix))
}
absent_suffixes <- c(".o", ".so", ".dll", ".tar.gz", ".Rcheck")
for (suffix in absent_suffixes) {
  check(!has_suffix(suffix), sprintf("absent build artifact: *%s", suffix))
}
absent_paths <- c("LICENSE.md", "THIRD_PARTY_NOTICES.md")
for (path in absent_paths) {
  check(!has_path(path), sprintf("absent dev summary: %s", path))
}

# ---------------------------------------------------------------------------
# 3. EXACT vendored bytes survive packaging (verify against the manifest).
# ---------------------------------------------------------------------------

message("\nVENDOR FIDELITY (exact bytes survive packaging):")
extract_dir <- tempfile("robotstxtr-audit-extract-")
dir.create(extract_dir)
untar(tarball, exdir = extract_dir)
pkg_root <- list.files(extract_dir, full.names = TRUE)[[1L]]

source(file.path(root_dir, "R", "vendor-manifest-verify.R"))
res <- verify_yandex_vendor_tree(
  root = file.path(pkg_root, "src", "vendor", "robotstxtyandex"),
  manifest_path = file.path(
    pkg_root, "inst", "vendor", "robotstxtyandex", "MANIFEST.dcf"
  )
)
ok_verify <- check(
  isTRUE(res$ok),
  "verify_yandex_vendor_tree(extracted tarball)$ok"
)
if (!ok_verify) {
  report <- function(label, paths) {
    if (length(paths) > 0L) {
      message(sprintf("    %s (%d): %s", label, length(paths),
        paste(paths, collapse = ", ")))
    }
  }
  report("missing", res$missing)
  report("extra", res$extra)
  report("mismatched", res$mismatched)
}

# ---------------------------------------------------------------------------
# 4. INSTALL the tarball: inst/ vendor records install; src/ is compiled-only.
# ---------------------------------------------------------------------------

message("\nBINARY DISPOSITION (install the tarball, offline):")
lib_dir <- tempfile("robotstxtr-audit-lib-")
dir.create(lib_dir)
install_log <- tempfile("robotstxtr-audit-install-", fileext = ".log")
install_status <- suppressWarnings(system2(
  file.path(R.home("bin"), "R"),
  c("CMD", "INSTALL", "--no-docs", "--no-multiarch",
    shQuote(paste0("--library=", lib_dir)), shQuote(tarball)),
  stdout = install_log, stderr = install_log
))
if (!identical(install_status, 0L)) {
  message(sprintf("  [SKIP] R CMD INSTALL failed (log: %s)", install_log))
} else {
  installed <- file.path(lib_dir, "robotstxtr")
  check(
    file.exists(file.path(
      installed, "vendor", "robotstxtyandex", "MANIFEST.dcf"
    )),
    "installed: inst/vendor/robotstxtyandex/MANIFEST.dcf present"
  )
  check(
    file.exists(file.path(installed, "APACHE-2.0-LICENSE")),
    "installed: APACHE-2.0-LICENSE present"
  )
  check(
    !dir.exists(file.path(installed, "src")),
    "installed: src/ is NOT installed (vendored source compiled-only)"
  )
  check(
    system.file("LICENSE.md", package = "robotstxtr", lib.loc = lib_dir) == "",
    "installed: LICENSE.md not installed"
  )
}

# ---------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------

message("")
if (length(state$failures) == 0L) {
  message("PASS: package + legal audit clean (source tarball + install).")
} else {
  message(sprintf("FAIL: %d audit check(s) failed:", length(state$failures)))
  message(paste0("  - ", state$failures, collapse = "\n"))
  quit(status = 1L)
}
