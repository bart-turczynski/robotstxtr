# Agent Instructions

Use committed docs for durable project knowledge. Keep raw planning notes, temporary context, and generated scratch work in `_scratch/`.

Do not commit `_scratch/`, `.fp/`, secrets, dependencies, build outputs, or local caches.

## Verification

Gate: local
Verify: .fleet-ci/gate auto

Git follows the house `agent-workflow` skill. fp status changes stay decoupled from git (the `fp` skill's `references/decoupling.md`).

The merge gate is fleet-ci's local gate, run in the fleet image by the pre-push hook (install the hooks once per clone with `pre-commit install`, then `.fleet-ci/pre-push --install`); its settings are `.fleet-ci.yml`. Until it is installed, the warn-only pre-commit hook `fleet-ci-hook-installed` (`scripts/check-fleet-hook.sh`) prints a WARNING on every push, which then ran only the hygiene hooks. A diff against `main` that the classifier calls docs-only (`design/**/*.md` and the like; `_pkgdown.yml` is excluded here) gets T0, spelling and `pkgdown::check_pkgdown()`; any other gets T1, the cheap gates, one `R CMD check` and the case-folding locale leg. Branch pushes, merge requests and pushes to `main` create no pipeline, and an empty pipeline list is not a pass. CI runs fleet-ci's template: T2 on the weekly `deep-check` schedule, T3 on a `RELEASE=1` web pipeline and on the `v*` tag (seor ADR 0012; design/ci.md). The pages keep-list is `.fleet-ci.yml`'s `pages_keep`: a new top-level `.md` meant for the public site is not published until it is added there.

## NEWS.md

- A `NEWS.md` bullet is one terse line, for a change a package user acts on or notices: behavior, API, dependencies, R or system requirements, installation.
- Where a standard decides the change, cite its clause in a few words, such as "(RFC 9309 §2.2.2)"; the reasoning belongs in the issue.
- At most one issue or MR reference, at the end. No housekeeping bullets (CI, gates, lint, spelling, logos, badges, repository metadata such as `codemeta.json`, `CITATION.cff` and keywords, agent files) and no Internal section.
- The pre-push `news-terse` hook (`scripts/check-news.py`) enforces the one-line, word-limit, reference and Internal parts, and catches common housekeeping openings.

## The tracker is not in git unless it is snapshotted

`.fp/` is gitignored, so the issue tracker is a local database that no commit, no clone and no bundle has ever contained — while `NEWS.md`, the release audits under `design/` and the test suite all cite `ROBO-*` ids as the reasoning behind what they assert. Regenerate the one copy that is in git with:

```bash
sh data-raw/snapshot-tracker.sh
```

It writes `design/tracker-snapshot.md`. Not `docs/`: that path here is the generated pkgdown site and is gitignored (`.gitignore:51`), so a snapshot written there would reach no commit and defeat the point of the file. `design/` is where this package's committed design docs already live.

`fp` stays authoritative — nothing reads the snapshot back, and `fp context <id>` is still the way to read an issue. The file is a backstop, and every run overwrites it wholesale, so hand-edits to it are lost.

Refresh it before taking any copy of the repository you intend to keep: a mirror push to the `backup` remote at `~/Projects/_backups/robotstxtr.git`, or a `git bundle create <path> --all`. Both exist for this repository. A snapshot that is never regenerated is worse than none, because it looks current.

The gate refuses a push to `main` that adds more than one first-parent merge, on any remote it gates. It does not gate the `backup` mirror: its URL is a local path, so the gate prints `gate: skipped, backup is a local mirror` and exits 0, and a mirror push carrying several merges, or branches from before the fleet-ci migration, needs no `--no-verify`. Under pre-commit's migration mode (`hooks/pre-push.legacy`) pre-commit's own pre-push hooks still run on that push; only the owner bypasses them, with `--no-verify`, and an agent asks before using it (a gate bypass is confirm-first).

## A red gate on an untouched tree

The gate runs in the image the fleet-ci pin names, with a private package
library per run, so this machine's R library cannot turn the gate itself
red. A dependency that moved on CRAN can: the gate resolves the dependencies
afresh on every run. The push can still be blocked from this machine: the
pre-push `check-toolchain` hook (`scripts/check-toolchain.R`) checks the
host library and toolchain (roxygen2 against `Config/roxygen2/version`,
installed packages built under a newer R, the local pandoc against
`.fleet-ci/toolchain`), so that a local `devtools::document()` or README
knit writes what the gate accepts (SEOR-tcytizic), and a failure there stops
the push even when the gate passed. Run `Rscript scripts/check-toolchain.R`
first when a push is refused on an untouched tree.

If the gate is red on a tree you have not touched, say so and keep the
evidence (`FLEET_GATE_KEEP=<dir>` keeps the container's output) rather than
assuming your change caused it.
