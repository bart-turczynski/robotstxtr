# Contributing

Install dependencies:

```sh
Rscript -e 'pak::local_install_deps(dependencies = TRUE)'
```

Run verification:

```sh
Rscript -e 'lints <- lintr::lint_package(); if (length(lints)) { print(lints); quit(status = 1) }' && Rscript -e 'res <- rcmdcheck::rcmdcheck(args = "--as-cran", error_on = "warning"); if (!identical(as.integer(res$status), 0L)) stop("R CMD check exited with status ", res$status, "; the run did not complete.", call. = FALSE)'
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
`DESCRIPTION`, since roxygen output formatting changes between releases. Like
`devtools::document()` itself, it loads the package through `pkgload`, which
runs `cpp11::cpp_register()` first — so `cpp11:::get_cpp_register_needs()`
(`brio`, `cli`, `decor`, `desc`, `glue`, `tibble`, `vctrs`) must be installed.

Source lives in `src/`, behavior features live in `features/`, tests live in `tests/`, and durable project context lives in `docs/`.

Keep local-only planning state in `_scratch/`. Do not commit `_scratch/`, `.fp/`, secrets, dependency folders, build outputs, or generated caches.

## The linter set

`.lintr` is intentionally aligned with the linter set `goodpractice::gp()` runs
(`goodpractice:::linters_to_lint()`), so the local and CI `lintr::lint_package()`
gate surfaces the same findings as the goodpractice report reviewers run. Without
that alignment a package passes its own lint gate and then trips a pile of
goodpractice findings later. Regenerate the list after a goodpractice upgrade,
comparing against `names(goodpractice:::linters_to_lint())`.

**Keep `.lintr` free of `#` comments.** It is parsed with `read.dcf()`, which
only learned to skip comment lines in R 4.6. On R 4.5 and older a single comment
makes `lint_package()` abort with `Invalid DCF format`, so the rationale lives
here instead. Keep it ASCII too: a non-ASCII byte in `.lintr` comes back
`bytes`-encoded on older R and makes any config error surface as a confusing
`sprintf()` failure instead of the real message.

Documented deviations from the goodpractice set — test-idiom and public-API
reasons a real package hits as it grows:

- `object_name_linter` / `object_usage_linter`: not part of the goodpractice set
  and deliberately NOT added. The cucumber DSL (`when`/`then`/`context`) and the
  testthat helpers read as undefined globals to `object_usage_linter`, and
  packages commonly expose mixed-case or dotted public parameters plus
  `._`-prefixed internal helpers that `object_name_linter` would flag.
- `expect_identical_linter`: off. Suites routinely rely on `expect_equal()`'s
  numeric tolerance (`expect_equal(nrow(x), 2)` compares integer vs double) and
  its string-encoding normalization, both of which `identical()` rejects; a
  wholesale swap means retyping literals for no behavioral gain.
- `implicit_assignment_linter`: off. Tests use the standard
  `expect_warning(res <- f(), "msg")` idiom to capture both the warning and the
  return value (`expect_warning()` returns the condition, not the value).
- `library_require_linter`: off. `tests/testthat.R` and vignette setup chunks
  legitimately call `library()`.
- `undesirable_operator_linter`: configured to keep flagging `<<-`/`->>` but
  allow `:::`, which tests use to reach internal (unexported) functions.

`strings_as_factors_linter` is off, as in goodpractice, which dropped it in 1.2.0
(ropensci-review-tools/goodpractice#321). It only guarded the pre-R-4.0
`data.frame()` default, and this package Depends on R >= 4.1.0. The fleet turned
it off on 2026-07-18, before goodpractice did (pagerankr PAGE-iiqjlfxl).

## CRAN release checklist

Follow the fleet checklist,
[seor `design/release-checklist.md`](https://gitlab.com/bart-turczynski/seor/-/blob/main/design/release-checklist.md).
robotstxtr's deltas:

- **Step 5: run every gate first.** The vendored C++ fidelity checks
  (`vendor-fidelity:yandex`, `vendor-fidelity:bing`) run only in CI's `gates`
  job, not in the pre-push hook. Confirm that job passed on the release
  commit, or run `Rscript dev/gates.R`, which runs them all.
- **Step 6: three R-hub platforms fail for platform reasons.** On 0.3.0
  (ROBO-lvddphcx): `windows`, because R-hub checks the tarball out of git and
  `.gitattributes` is Rbuildignored, so line-ending conversion rewrites the
  byte-exact corpus files (win-builder, which tests the tarball itself, is
  the Windows control); `valgrind`, with no frame in robotstxtr code; and
  `nosuggests`, where the vignette needs `rmarkdown`. The sanitizers and
  valgrind matter here because of the compiled code. By the owner's
  decision, those three were recorded on the release issue, not in
  `cran-comments.md`.
- **Step 7: submit from a clean clone, always.** `tmp/` is neither
  gitignored nor Rbuildignored (ROBO-bqvkezdp), so a tarball built from a
  working copy can ship it.
