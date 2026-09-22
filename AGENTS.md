# Agent Instructions

Use committed docs for durable project knowledge. Keep raw planning notes, temporary context, and generated scratch work in `_scratch/`.

Do not commit `_scratch/`, `.fp/`, secrets, dependencies, build outputs, or local caches.

## Git hygiene

This project uses the [pre-commit](https://pre-commit.com) framework. Its config (`.pre-commit-config.yaml`) is cloned with the repo; each clone enables the hooks once:

```bash
pre-commit install && pre-commit install --hook-type pre-push
```

`pre-commit` is a Python tool. For non-Python templates, install it with `uv tool install pre-commit` or `pipx install pre-commit`.

### Per-commit checks

On every commit, lightweight hooks run: end-of-file fixer, trailing-whitespace trimming, merge-conflict detection, YAML/TOML validation, mixed-line-ending and case-conflict guards, and `check-added-large-files` — a portable 5 MB size guard that blocks accidentally committing heavy blobs (a big blob bloats `.git` history even after deletion).

### Pre-push verify gate

On `git push`, the `verify` hook runs the project's verify command — the same chain CI runs. GitLab is this project's forge (GitHub, where mirrored, is read-only), and GitLab Free does offer protected branches — the fleet's own instructions say to wire those up. They only gate what reaches the default branch; this local hook is complementary, not a substitute: it blocks a push whose tree would turn CI red before it ever leaves your machine.

**On a feature branch this hook is the only gate that runs by itself, and that is deliberate.** `.gitlab-ci.yml` carries a top-level `workflow:` block admitting only a tag, a push to `main`, or a hand-started (`web`) pipeline — so a branch push creates no pipeline and neither does its merge request, one pipeline per merge instead of three (SEOR-bmgkzhvy). Do not read a branch's empty pipeline list as a passing result: there is no result. To get a server-side answer on a branch before merging, start one at **Build > Pipelines > Run pipeline** and pick the ref; the full gate runs there. `pages` is pinned to `main`, because it publishes rather than reports. Note that `glab ci run` starts an `api`-source pipeline, which the block still refuses on a branch — use the button.

### The tracker is not in git unless it is snapshotted

`.fp/` is gitignored, so the issue tracker is a local database that no commit, no clone and no bundle has ever contained — while `NEWS.md`, the release audits under `design/` and the test suite all cite `ROBO-*` ids as the reasoning behind what they assert. Regenerate the one copy that is in git with:

```bash
sh data-raw/snapshot-tracker.sh
```

It writes `design/tracker-snapshot.md`. Not `docs/`: that path here is the generated pkgdown site and is gitignored (`.gitignore:51`), so a snapshot written there would reach no commit and defeat the point of the file. `design/` is where this package's committed design docs already live.

`fp` stays authoritative — nothing reads the snapshot back, and `fp context <id>` is still the way to read an issue. The file is a backstop, and every run overwrites it wholesale, so hand-edits to it are lost.

Refresh it before taking any copy of the repository you intend to keep: a mirror push to the `backup` remote at `~/Projects/_backups/robotstxtr.git`, or a `git bundle create <path> --all`. Both exist for this repository. A snapshot that is never regenerated is worse than none, because it looks current.

@FP_AGENTS.md
