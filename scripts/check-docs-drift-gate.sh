#!/bin/sh
# The generated-docs drift gate, a cheap gate of the fleet-ci local gate
# (.fleet-ci.yml): seor's scripts/check-docs-drift.R, run with the packages
# cpp11's registration needs.
#
#   sh scripts/check-docs-drift-gate.sh      # from the package root
#
# roxygen2 loads the package through pkgload, which compiles src/ and, since
# robotstxtr links to cpp11, first runs cpp11::cpp_register(). That needs
# cpp11:::get_cpp_register_needs() (brio, cli, decor, desc, glue, tibble,
# vctrs), which neither the fleet image's tooling library nor the gate's run
# library (robotstxtr's own dependencies) holds in full: without them the
# check stops at "The decor package(s) are required". The former `gates` CI
# job installed the same set. So the missing ones go into a throwaway library
# put first on R_LIBS for this one run. scripts/check-docs-drift.R itself is
# seor's copy, vendored byte for byte, so the setup lives here, not in it.
set -eu

lib=$(mktemp -d)
trap 'rm -rf "$lib"' EXIT

Rscript -e '
  need <- cpp11:::get_cpp_register_needs()
  miss <- need[!vapply(need, requireNamespace, NA, quietly = TRUE)]
  if (length(miss)) {
    cat("installing for cpp11::cpp_register():", miss, "\n")
    install.packages(miss, lib = commandArgs(TRUE)[[1L]], quiet = TRUE)
  }
  .libPaths(c(commandArgs(TRUE)[[1L]], .libPaths()))
  still <- need[!vapply(need, requireNamespace, NA, quietly = TRUE)]
  if (length(still)) stop("could not install: ", toString(still), call. = FALSE)
' "$lib"

R_LIBS="$lib${R_LIBS:+:$R_LIBS}" Rscript scripts/check-docs-drift.R .
