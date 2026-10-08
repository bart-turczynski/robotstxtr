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
lives in `design/`. `docs/` is the generated pkgdown site, not design docs.

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
- **Step 6 is the only Windows, macOS and valgrind check.** Every CI job is
  Linux (`.gitlab-ci.yml`): the fleet's runners are Docker on an arm64 Mac,
  which can host neither Windows nor R-hub's x86_64 valgrind image. That was
  chosen on 2026-10-08 instead of Windows and macOS CI legs (ROBO-mkuskipr).
  So step 6, on the release SHA, gates the release on:
  - win-builder devel, release and oldrelease, the Windows check, because
    they test the tarball itself;
  - R-hub `macos` and `macos-arm64`, the macOS check;
  - R-hub `linux`, `clang-asan` and `clang-ubsan`. The sanitizers matter here
    because of the compiled code.

  Three R-hub platforms fail for platform reasons and do not gate (0.3.0,
  ROBO-lvddphcx). By the owner's decision they are recorded on the release
  issue, not in `cran-comments.md`:
  - `windows`: R-hub checks the tarball out of git and `.gitattributes` is
    Rbuildignored, so line-ending conversion rewrites the byte-exact corpus
    files.
  - `valgrind`: the job fails on any valgrind error, and R's own regex and
    DCF code and the test-only dependencies report some. Read its log: an
    error with a frame in robotstxtr code blocks the release; on 0.3.0 there
    was none.
  - `nosuggests`: the vignette needs `rmarkdown`.
- **Step 7: submit from a clean clone, always.** A tarball built from a
  working copy can ship untracked files that no ignore list names
  (ROBO-bqvkezdp; `tmp/` itself is now both gitignored and Rbuildignored).
