# Agent Instructions

Use committed docs for durable project knowledge. Keep raw planning notes, temporary context, and generated scratch work in `_scratch/`.

Do not commit `_scratch/`, `.fp/`, secrets, dependencies, build outputs, or local caches.

## Git and the verify gate

Git follows the house `agent-workflow` skill. fp status changes stay decoupled from git (the `fp` skill's `references/decoupling.md`). What is specific to this repository:

- Each clone enables the hooks once: `pre-commit install && pre-commit install --hook-type pre-push`. `pre-commit` is a Python tool; install it with `uv tool install pre-commit` or `pipx install pre-commit`.
- The pre-push `verify` hook runs `dev/verify.sh`, the chain CI runs. Run it by hand with `pre-commit run --hook-stage pre-push --all-files`.
- **On a branch that hook is the only gate.** `.gitlab-ci.yml`'s top-level `workflow:` block admits only a tag, a push to `main`, or a hand-started (`web`) pipeline, so a branch push and its merge request create no pipeline (SEOR-bmgkzhvy). An empty pipeline list is not a pass. For a server-side answer on a branch, start one at **Build > Pipelines > Run pipeline**; `glab ci run` starts an `api` pipeline, which the block refuses.
- The pages keep-list is `keep=` in the `.pkgdown-site` job of `.gitlab-ci.yml`, pinned by `dev/check-ci-config.R`. A new top-level `.md` meant for the public site is not published until it is added there.

## The tracker is not in git unless it is snapshotted

`.fp/` is gitignored, so the issue tracker is a local database that no commit, no clone and no bundle has ever contained — while `NEWS.md`, the release audits under `design/` and the test suite all cite `ROBO-*` ids as the reasoning behind what they assert. Regenerate the one copy that is in git with:

```bash
sh data-raw/snapshot-tracker.sh
```

It writes `design/tracker-snapshot.md`. Not `docs/`: that path here is the generated pkgdown site and is gitignored (`.gitignore:51`), so a snapshot written there would reach no commit and defeat the point of the file. `design/` is where this package's committed design docs already live.

`fp` stays authoritative — nothing reads the snapshot back, and `fp context <id>` is still the way to read an issue. The file is a backstop, and every run overwrites it wholesale, so hand-edits to it are lost.

Refresh it before taking any copy of the repository you intend to keep: a mirror push to the `backup` remote at `~/Projects/_backups/robotstxtr.git`, or a `git bundle create <path> --all`. Both exist for this repository. A snapshot that is never regenerated is worse than none, because it looks current.

## A red gate on an untouched tree

Toolchain drift makes the verify gate go red on a tree nobody changed, and it
looks exactly like a defect in the change being made. `scripts/check-toolchain.R`
runs ahead of the expensive step and names it in one line: roxygen2's installed
version against this package's `Config/roxygen2/version`, and any installed
package built under a newer R than the one running. Both have happened, and both
cost an afternoon (SEOR-tcytizic).

If that check passes and the gate is still red on a tree you have not touched,
say so and keep the evidence rather than assuming your change caused it.

A third cause is a reinstall in flight. `there is no package called '<pkg>'`
for a package in the rurl stack (rurl, pslr, punycoder) usually means another
session is installing a dev build of it, and the library directory is briefly
absent. Re-run the gate before investigating. `ls -ld` on that package's
directory in the R library, showing an mtime from the last few minutes, or a
`.9000` version, confirms it.
