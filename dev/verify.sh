#!/usr/bin/env bash
#
# Pre-push verify gate — mirrors CI (see .github/workflows/R-CMD-check.yml).
#
# Why a clean git-archive export instead of the working tree:
# R CMD build copies the *entire* package tree to a temp dir before it applies
# .Rbuildignore. That copy is a plain recursive file copy, so a non-regular file
# anywhere in the tree — e.g. a live browser's Unix-domain socket under
# _scratch/yandex-browser — makes the copy fail, even though _scratch/ is
# Rbuildignored (the prune happens *after* the copy). The result: any push while
# a browser is open gets blocked.
#
# Checking a `git archive HEAD` export sidesteps this entirely. The export holds
# only committed, tracked files — exactly what is being pushed and what CI checks
# out with actions/checkout — so _scratch/ and any sockets in it are never
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

# 2) R CMD check --as-cran against a clean export of HEAD in a temp dir.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
git archive HEAD | tar -x -C "$workdir"
Rscript -e 'rcmdcheck::rcmdcheck(path = commandArgs(TRUE)[1], args = "--as-cran", error_on = "warning")' "$workdir"
