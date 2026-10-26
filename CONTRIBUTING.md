# Contributing

Report bugs and request features in the GitLab issue tracker:
<https://gitlab.com/bart-turczynski/robotstxtr/-/work_items>. Report security issues
privately as described in `SECURITY.md`. Send changes as merge requests on
GitLab; the GitHub repository is a read-only mirror.

New code needs tests, and each user-facing change needs one `NEWS.md` bullet.
A merge request must pass the verification command below.

Install dependencies:

```sh
Rscript -e 'pak::local_install_deps(dependencies = TRUE)'
```

Run verification (the pre-push chain: the hygiene hooks and codespell, the
toolchain check, the NEWS, codemeta and spelling gates, the URL check, then
lintr, the generated-docs drift check and `R CMD check --as-cran` in the
`verify` hook, then the citation and BugReports checks):

```sh
pre-commit run --hook-stage pre-push --all-files
```

`man/` and `NAMESPACE` are generated from the roxygen comments in `R/`: edit the
comment, then run `devtools::document()` and commit the regenerated files with
the change. A stale `.Rd` is still valid `.Rd`, so neither lintr nor
`R CMD check` notices when the two drift apart — `scripts/check-docs-drift.R`
regenerates them (and `DESCRIPTION`, whose roxygen-owned fields drift the same
way) and diffs them, and both the pre-push hook and CI run it. It is seor's
script, vendored byte for byte, so a fix goes into seor's copy and is copied
here, never edited in place:

```sh
Rscript scripts/check-docs-drift.R
```

It needs the exact roxygen2 version pinned by `Config/roxygen2/version` in
`DESCRIPTION`, since roxygen output formatting changes between releases. Like
`devtools::document()` itself, it loads the package through `pkgload`, which
runs `cpp11::cpp_register()` first — so `cpp11:::get_cpp_register_needs()`
(`brio`, `cli`, `decor`, `desc`, `glue`, `tibble`, `vctrs`) must be installed.

Source lives in `src/`, tests live in `tests/`, and durable project context
lives in `ARCHITECTURE.md` and `design/`: the CRAN release deltas in
[`design/release-deltas.md`](https://gitlab.com/bart-turczynski/robotstxtr/-/blob/main/design/release-deltas.md),
and why `.lintr` holds the linters it does in
[`design/linter-set.md`](https://gitlab.com/bart-turczynski/robotstxtr/-/blob/main/design/linter-set.md).
`docs/` is the generated pkgdown site, not design docs.

Keep local-only planning state in `_scratch/`. Do not commit `_scratch/`, `.fp/`, secrets, dependency folders, build outputs, or generated caches.
