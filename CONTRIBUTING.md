# Contributing

Install dependencies:

```sh
Rscript -e 'pak::local_install_deps(dependencies = TRUE)'
```

Run verification:

```sh
Rscript -e 'lints <- lintr::lint_package(); if (length(lints)) { print(lints); quit(status = 1) }' && Rscript -e 'rcmdcheck::rcmdcheck(args = "--as-cran", error_on = "warning")'
```

`man/` and `NAMESPACE` are generated from the roxygen comments in `R/`: edit the
comment, then run `devtools::document()` and commit the regenerated files with
the change. A stale `.Rd` is still valid `.Rd`, so neither the lint nor the
check above notices when the two drift apart — `dev/check-docs-drift.R`
regenerates and diffs them, and both the pre-push hook and CI run it:

```sh
Rscript dev/check-docs-drift.R
```

It needs the exact roxygen2 version pinned by `Config/roxygen2/version` in
`DESCRIPTION`, since roxygen output formatting changes between releases.

Source lives in `src/`, behavior features live in `features/`, tests live in `tests/`, and durable project context lives in `docs/`.

Keep local-only planning state in `_scratch/`. Do not commit `_scratch/`, `.fp/`, secrets, dependency folders, build outputs, or generated caches.
