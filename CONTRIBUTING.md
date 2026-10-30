# Contributing

Report bugs and request features in the GitLab issue tracker:
<https://gitlab.com/bart-turczynski/robotstxtr/-/work_items>. Report security issues
privately as described in `SECURITY.md`. Send changes as merge requests on
GitLab; the GitHub repository is a read-only mirror.

New code needs tests, and each user-facing change needs one `NEWS.md` bullet.
A merge request must pass the verification gate below.

Install dependencies:

```sh
Rscript -e 'pak::local_install_deps(dependencies = TRUE)'
```

## Verification gate

Verification is fleet-ci's local gate, which runs in the fleet Docker image
(settings in `.fleet-ci.yml`), so it needs Docker, python3, Ruby, git,
[`pre-commit`](https://pre-commit.com/) (for example `pipx install
pre-commit`) and a `docker login registry.gitlab.com`. Install the hooks once
per clone, from the package root:

```sh
pre-commit install
.fleet-ci/pre-push --install
```

From then on the gate runs on every push, on each pushed ref's tip, followed
by the pre-commit pre-push hooks (the toolchain, citation, BugReports and
NEWS terseness checks). `pre-commit install -f` (which installs both hook
types, from `.pre-commit-config.yaml`'s `default_install_hook_types`) and
`pre-commit install -f --hook-type pre-push` replace that hook and drop the
gate; re-run `.fleet-ci/pre-push --install` after either. Without `-f`,
`pre-commit install` keeps the gate (pre-commit's migration mode). To run the
gate by hand on `HEAD`:

```sh
.fleet-ci/gate auto
```

The gate checks the committed tree, never uncommitted edits, so commit a fix
before you push it. A diff that is docs-only (`design/**/*.md` and the like)
gets the docs tier: spelling and `pkgdown::check_pkgdown()`. Any other diff
gets the full tier: spelling, `pkgdown::check_pkgdown()`, the `NEWS.md`
heading against `DESCRIPTION`'s Version, `codemeta.json` against
`DESCRIPTION`, docs drift, lintr, `README.md` against a fresh knit of
`README.Rmd`, the two vendored-tree fidelity checks, the URL check, one
`R CMD check --as-cran` (incoming checks off), which **fails on errors and
warnings**, and a second check under `LC_ALL=C` followed by
`scripts/check-locale-legs.R`, which proves the Turkish and Azeri
case-folding legs ran. A test skip that `.fleet-ci.yml` does not allow fails
it too. GitLab CI runs no pipeline for a branch, a merge request or a push to
`main`; what it runs, and when, is in
[`design/ci.md`](https://gitlab.com/bart-turczynski/robotstxtr/-/blob/main/design/ci.md).

`man/` and `NAMESPACE` are generated from the roxygen comments in `R/`: edit the
comment, then run `devtools::document()` and commit the regenerated files with
the change. A stale `.Rd` is still valid `.Rd`, so neither lintr nor
`R CMD check` notices when the two drift apart — `scripts/check-docs-drift.R`
regenerates them (and `DESCRIPTION`, whose roxygen-owned fields drift the same
way) and diffs them, and the gate's full tier runs it. To run it alone:

```sh
Rscript scripts/check-docs-drift.R
```

It needs the exact roxygen2 version pinned by `Config/roxygen2/version` in
`DESCRIPTION`, since roxygen output formatting changes between releases. Like
`devtools::document()` itself, it loads the package through `pkgload`, which
runs `cpp11::cpp_register()` first — so what cpp11's own
`Config/Needs/cpp11/cpp_register` field names (`brio`, `cli`, `decor`,
`desc`, `glue`, `tibble`, `vctrs` in cpp11 0.5.5) must be installed;
`Rscript scripts/cpp-register-needs.R <library>` installs the missing ones
into `<library>`, as the gate does.

Source lives in `src/`, tests live in `tests/`, and durable project context
lives in `ARCHITECTURE.md` and `design/`: CI, the local gate and the project
settings CI depends on in
[`design/ci.md`](https://gitlab.com/bart-turczynski/robotstxtr/-/blob/main/design/ci.md),
the CRAN release deltas in
[`design/release-deltas.md`](https://gitlab.com/bart-turczynski/robotstxtr/-/blob/main/design/release-deltas.md),
and why `.lintr` holds the linters it does in
[`design/linter-set.md`](https://gitlab.com/bart-turczynski/robotstxtr/-/blob/main/design/linter-set.md).
`docs/` is the generated pkgdown site, not design docs.

Keep local-only planning state in `_scratch/`. Do not commit `_scratch/`, `.fp/`, secrets, dependency folders, build outputs, or generated caches.
