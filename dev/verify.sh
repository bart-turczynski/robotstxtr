#!/usr/bin/env bash
#
# Pre-push verify gate — mirrors CI (see .gitlab-ci.yml).
#
# Why a clean git-archive export instead of the working tree:
# R CMD build copies the *entire* package tree to a temp dir before it applies
# .Rbuildignore. That copy is a plain recursive file copy, so a non-regular file
# anywhere in the tree — e.g. a live browser's Unix-domain socket under
# _scratch/yandex-browser — makes the copy fail, even though _scratch/ is
# Rbuildignored (the prune happens *after* the copy). The result: any push while
# a browser is open gets blocked.
#
# Checking a `git archive` export of the pushed commit sidesteps this entirely. The export holds
# only committed, tracked files — exactly what is being pushed and what the CI
# runner clones — so _scratch/ and any sockets in it are never
# present to trip the copy. This makes the local gate a truer mirror of CI.
set -euo pipefail

# 0) Preflight: surface non-regular files (sockets/FIFOs) in the working tree.
#    These come from live processes — most often a browser profile under
#    _scratch/ (e.g. _scratch/yandex-browser/SingletonSocket). They can't be
#    committed, so `git archive` never includes them and the build below is
#    unaffected; this is a non-fatal heads-up (you can still push with a browser
#    open) so an unexpected special file elsewhere is visible rather than silent.
specials="$(find . -path ./.git -prune -o \( -type s -o -type p \) -print 2>/dev/null || true)"
if [ -n "$specials" ]; then
  {
    echo "verify: note — non-regular files (sockets/FIFOs) present in the working tree:"
    echo "$specials" | sed 's/^/  /'
    echo "verify: not committable, so the git-archive build export excludes them; continuing."
  } >&2
fi

# 1) Lint the working tree. lintr reads source files in place (no tree copy), so
#    it is safe to run against the working dir and gives fast, local feedback.
Rscript -e 'lints <- lintr::lint_package(); if (length(lints)) { print(lints); quit(status = 1) }'

docsdir="$(mktemp -d)"
workdir="$(mktemp -d)"
trap 'rm -rf "$docsdir" "$workdir"' EXIT

# The commit being pushed: pre-commit's pre-push stage names it in
# PRE_COMMIT_TO_REF (it may not be the checked-out HEAD); a manual run checks HEAD.
ref="${PRE_COMMIT_TO_REF:-HEAD}"

# 2) Generated-docs drift: regenerate man/, NAMESPACE and DESCRIPTION from the
#    roxygen comments in R/ and fail if they differ from what is committed. The
#    check is seor's scripts/check-docs-drift.R, vendored byte for byte
#    (SEOR-lyciowif); repo specifics go in its argument, never into the copy.
#    A stale .Rd is still valid .Rd, so neither the lint above nor the check
#    below can see it (ROBO-cbzemsnq). Runs before the check because it is the
#    cheaper of the two and fails fast.
#
#    It gets its OWN export, not the one the check builds from: roxygen loads
#    the package through pkgload, which compiles src/ in place and leaves .o
#    files and a .so behind that would contaminate the R CMD build below.
git archive "$ref" | tar -x -C "$docsdir"
Rscript scripts/check-docs-drift.R "$docsdir"

# 3) R CMD check --as-cran against a clean export of $ref in a temp dir.
#    rcmdcheck reads a check that halted partway as 0/0/0 and returns normally,
#    so error_on never fires. The guard also fails on R CMD check's own exit
#    status (SEOR-maavnxdm).
git archive "$ref" | tar -x -C "$workdir"
Rscript -e 'res <- rcmdcheck::rcmdcheck(path = commandArgs(TRUE)[1], args = "--as-cran", error_on = "warning"); if (!identical(as.integer(res$status), 0L)) stop("R CMD check exited with status ", res$status, "; the run did not complete.", call. = FALSE)' "$workdir"
