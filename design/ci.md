# robotstxtr's CI

robotstxtr runs fleet-ci's tiered CI (seor ADR 0012). `.gitlab-ci.yml`
includes fleet-ci's `templates/r-package.yml`, pinned by commit SHA, and sets
only package variables, with no `x-*` job; `.fleet-ci.yml` holds the local
gate's settings, and `.fleet-ci/` is fleet-ci's vendored gate (re-run
fleet-ci's `bin/vendor`, never edit it). The job names below are the
template's.

| Tier | Where | What runs |
| --- | --- | --- |
| hygiene hooks | pre-commit, at commit and at push | `.pre-commit-config.yaml`. At commit and again at push: the hygiene fixers (end of file, trailing whitespace, line endings; the vendored trees, the Yandex corpus and testthat snapshots excluded), the large-file, merge-conflict, YAML and case-conflict checks, and codespell. At push only: the toolchain, citation, BugReports and NEWS terseness checks, the `check-citation.py`, `check-bugreports.py` and `check-news.py` self-tests when those scripts change, and the warn-only `fleet-ci-hook-installed` check |
| T0 | every push whose diff against `main` is docs-only (`design/**/*.md` and the like, minus `.fleet-ci.yml`'s `docs_exclude`, `_pkgdown.yml`), locally, the pre-push hook | the gate's docs tier, `.fleet-ci/gate` in the fleet image (`fleet-r`): spelling and `pkgdown::check_pkgdown()` |
| T1 | every other push, locally, the pre-push hook | the gate's full tier: T0's checks, then the `NEWS.md` heading (`scripts/check-news-version.R`), `codemeta.json` against `DESCRIPTION` (`scripts/check-codemeta.R`), docs drift, lintr, README drift (`scripts/check-readme-drift.sh`), the two vendored-tree fidelity checks (`dev/verify-yandex-vendor.R`, `dev/verify-bing-vendor.R`), the URL check, one `R CMD check --as-cran` (incoming checks off) with the Turkish and Azeri locales built, then a second check under `LC_ALL=C` and `scripts/check-locale-legs.R` against it |
| T2 | the weekly `deep-check` schedule; every T3 run | `t2-check-release`, `t2-check-oldrel`, `t2-check-devel`, `t2-floor` (R 4.1.3), `t2-sanitizers` (R-hub's clang-asan container), `t2-locale` (the locales built, `R CMD check` under `LC_ALL=C`, then `scripts/check-locale-legs.R`), `t2-ascran`, `coverage` (fails below 95%), `osv-audit`, `security-audit`, `citation-version` |
| T3 | a `RELEASE=1` web pipeline on `main`; a `v*` tag | all of T2 plus `t3-manual` (the PDF manual); the tag, or `RELEASE=1` on a tag, adds `pages` |

Pushes to `main` or a branch, merge requests and API pipelines (`glab ci run`)
create no pipeline at all, and neither does a web pipeline without
`RELEASE=1` (or `PAGES=1` on a tag). An empty pipeline list is not a pass:
the merge gate is the local gate (T0 or T1), run before the branch leaves the
machine.

Before a CRAN submission, start T3 on `main` from **Build > Pipelines > Run
pipeline**, ref `main`, variable `RELEASE=1` (see
[release-deltas.md](release-deltas.md)). `PAGES=1` on a `v*` tag runs `pages`
alone.

## The hook, once per clone

```sh
pre-commit install
.fleet-ci/pre-push --install
```

`pre-commit install` writes both hook types (`default_install_hook_types`);
`.fleet-ci/pre-push --install` then replaces the pre-push one with
fleet-ci's, which runs the gate on each pushed ref's tip and then the
pre-commit pre-push stage. Two commands drop it: `pre-commit install -f`, and
`pre-commit install -f --hook-type pre-push`; re-run the install after
either. Without `-f`, `pre-commit install` (with or without
`--hook-type pre-push`) moves the hook to `hooks/pre-push.legacy`
(pre-commit's migration mode), which still runs the gate first; `-f
--hook-type pre-commit` leaves it alone. `.fleet-ci/gate auto` runs the gate
by hand on `HEAD`. A pass is stamped by tree, tier, classifier version, image
and (full tier) resolved dependency lock, and a stamped commit is skipped.

The gate refuses a push carrying more than one ref to `main`, and a push to
`main` that adds more than one first-parent merge. It skips a push to a local
mirror: when the push URL is local by git's rule (the `backup` remote's
path, or `file:///` with an empty host) it prints `gate: skipped, <remote> is
a local mirror` and exits 0, so a mirror push to `backup` needs no
`--no-verify`. Under pre-commit's migration mode the skip ends only the
gate's hook, and the pre-commit pre-push stage still runs (AGENTS.md).

The gate checks the pushed commit, exported from git, never the working
tree, so an uncommitted fix cannot pass it, and a live socket under
`_scratch/` cannot break `R CMD build` (the reason the former hook,
`dev/verify.sh`, checked a `git archive` export). It installs the
dependencies fresh in the container, into a private library per run, so a
dev build of rurl, pslr or punycoder that another session is installing on
this machine can no longer turn it red.

## The case-folding locale legs

`test-ascii-case-folding-tldlaxgq.R` runs two legs per locale in
`tests/testthat/fixtures/case-folding-locales.txt` (`tr_TR.UTF-8`,
`az_AZ.UTF-8`), and each skips where its locale is missing. A skip is a
pass to `R CMD check`, so two things prove the legs ran:

- the gate's skip policy: `.fleet-ci.yml` builds both locales (and
  `en_US.UTF-8`, which `R CMD check`'s syntax check needs under the `C` leg)
  before T1's check, and `allowed_skips` is empty, so a leg that skips fails
  T1;
- `scripts/check-locale-legs.R`, a `locale_assertions` entry: after the
  `LC_ALL=C` leg's check, in T1 and in `t2-locale`, it switches to each
  locale by its exact name, asserts it folds "I" to the dotless U+0131 (the
  former CI's early probe), and runs the test file against the package that
  leg's check installed, failing unless every leg ran, passed and asserted
  something.

## Runner

Every job runs on robotstxtr's own project runner, a self-hosted Docker
runner on one Mac (seor `design/adr/0003-fleet-ci-runs-on-self-hosted-runners.md`).
The template's jobs carry no `tags:`, and that runner also runs untagged
jobs, so the former `default: tags: [local-docker]` is gone. The tag existed
to keep jobs off GitLab's shared runners (SEOR-hhtzaknn). Shared runners are
disabled for robotstxtr (project setting `shared_runners_enabled` false, read
2026-10-30), so an untagged job has only the project runner to land on. A
scheduled or release pipeline started while the Mac sleeps waits, queued; it
has not passed. The images come from fleet-ci's private registry, pulled
with the job token (seor ADR 0013). `t2-sanitizers` runs R-hub's clang-asan
container, an amd64 image, under emulation on the arm64 runner, as the
former `sanitizers` job did.

## Platforms CI cannot cover

Every job is Linux. Windows, macOS and valgrind are checked once per
release, by win-builder and R-hub, not in CI
([release-deltas.md](release-deltas.md), release checklist step 6;
ROBO-mkuskipr). R-hub v2 dispatches workflows inside a GitHub repository, so
it cannot be ported to GitLab, and GitHub holds a read-only mirror that runs
no CI.

## Project settings CI depends on, which are not in this repository

These live in GitLab's project settings, so a clone does not carry them:

- **Pipeline schedule 4472810** (Build > Pipeline schedules), "Weekly deep
  check (fleet standard)", `0 22 * * 1` Europe/Warsaw on `main`, carrying
  `SCHEDULE_KIND=deep-check`. Required: it is T2's only unattended run, and
  every pipeline on `main` carries `coverage`, so the coverage badge reads
  it.
- **Pipeline schedule 4467473**, `SCHEDULE_KIND=dependency-audit`. The
  template starts no pipeline for it any more (the audits run in T2); its
  removal is owner-gated.
- **`OSSINDEX_USER` / `OSSINDEX_TOKEN`** (Settings > CI/CD > Variables;
  `OSSINDEX_TOKEN` masked). `security-audit` sets
  `OSSINDEX_AUDIT_REQUIRED=true`, so without them it fails rather than
  passing having audited nothing.
- **fleet-ci's job token allowlist** must admit robotstxtr, or every fleet
  image pull fails (fleet-ci README, "The registry is private").
- **Pages**: `pages` publishes pkgdown's destination (`docs/`, the default)
  with only the top-level `.md` files on `.fleet-ci.yml`'s `pages_keep`.

Never set `SCHEDULE_KIND` as a project or group variable: every schedule
would inherit it.

## Gaps accepted in the fleet-ci migration

- **`--as-cran` runs on R release only.** The former `full-check` ran
  `R CMD check --as-cran` with incoming checks on R release, oldrel and
  devel, and `floor-check` ran `--as-cran` too. Now only `t2-ascran`
  (release R) runs `--as-cran` with incoming on; `t2-check-release`,
  `t2-check-oldrel` and `t2-check-devel` run a plain `R CMD check`
  (`--no-manual`), and `t2-floor` keeps `--as-cran` with incoming off. An
  `--as-cran`-only finding on oldrel or devel now surfaces at win-builder, or
  at CRAN.
- **The case-folding legs run on R release only.** The former `check` and
  the three `full-check` legs (release, oldrel, devel) each built
  `tr_TR.UTF-8` and `az_AZ.UTF-8` and ran `scripts/check-locale-legs.R`
  after the check. Now T1 and `t2-locale` build them and assert the legs, both
  on the release R; the T2 check legs build no locale, so the legs skip
  there, which does not fail them.
- **`t2-locale`'s leg runs under `LC_ALL=C`**, the template's default, which
  the former CI never ran; the former CI's checks ran in rocker's
  `en_US.UTF-8`. The local gate runs the same leg in T1.
- **The live OSS Index audit reaches every `NOT_CRAN=true` job, not only
  `security-audit`.** `OSSINDEX_USER` and `OSSINDEX_TOKEN` are project
  variables, which reach every job. With `NOT_CRAN=true`,
  `test-security.R`'s audit test passes its `skip_on_cran()`, finds the
  credentials and calls OSS Index in `t2-check-release`, `t2-check-oldrel`,
  `t2-check-devel`, `t2-locale`, `t2-sanitizers` and `t3-manual`, and
  `test-osv.R` queries osv.dev in the same jobs. An OSS Index outage, an
  HTTP 429 or the shutdown of the endpoint oysteR calls turns all of them
  red, and on a `v*` tag that blocks `pages`. Scoping the credentials to the
  audit job is a fleet follow-up (seor SEOR-yrsmlrvp).
- **T1 drops `test-security.R`'s offline tests.** `exclude_tests` drops the
  whole file, so its allow-list well-formedness tests no longer run before a
  push; they run in T2. Moving them into a file of their own changes
  `tests/`, so it is a follow-up.
- **No server-side drift checks.** The former `gates` and `citation-version`
  jobs ran lint, README and docs drift, both vendored-tree fidelity checks,
  the NEWS heading, codemeta, spelling, `check-citation.py`,
  `check-bugreports.py` and `check-news.py` on every push to `main`, which
  caught a web edit or a `--no-verify` push. Those runs are gone; only the
  local gate and the pre-push hooks run them, and T2's `citation-version`
  runs `check-citation.py` alone.
- **No per-push CI check or coverage.** The former `check` (`--as-cran`
  with incoming on) and `coverage` ran on every push to `main`; now T1 runs
  the check before every push (incoming off), and `coverage` runs in T2 and
  T3.
- **No incoming check before a merge.** T1's check runs with
  `_R_CHECK_CRAN_INCOMING_=false`; the incoming feasibility and URL checks
  the former hook's and `check`'s `--as-cran` ran run in `t2-ascran` (T2 and
  T3), and `scripts/check-urls.R` still checks every declared URL in T1.
- **A NOTE fails nothing, as before.** The former hook and `check` failed on
  an ERROR or a WARNING only (`error_on = "warning"`, no NOTE list), so
  `.fleet-ci.yml` sets no `allowed_notes`: neither the gate nor the T2 check
  legs (`t2-check-release`, `-oldrel`, `-devel`, the only CI jobs that would
  apply the list) fail on a NOTE. Read `t2-ascran`'s NOTEs, the only leg with
  the incoming feasibility and URL checks, before a submission.
- **The floor leg is unproven.** `t2-floor` installs every dependency,
  `Suggests` included, from one dated snapshot (`FLEET_FLOOR_SNAPSHOT`), and
  `rurl (>= 3.0.1)` puts that snapshot in late 2026, after R 4.6.0. The former
  `floor-check` took a 2025-07-15 snapshot for the third-party packages and
  installed punycoder, pslr and rurl from current CRAN; the template has no
  such mix. Two risks: a dependency in the snapshot that no longer supports
  R 4.1, and rurl 3.1.0's zero-padded IPv6 serialization under R < 4.2,
  which ssrfr's floor leg hit and which `test-robots_origin-r5.R`'s
  bracketed IPv6 origins could meet. If the first T2 run fails on either,
  move the date, carry the former recipe as an `x-floor` job (ssrfr's
  shape), or record `FLEET_FLOOR: "false"` here with the reason.
- **rurl comes from CRAN, not a git tag.** The former CI installed rurl from
  its `v3.0.1` git tag (`RURL_GIT`, ROBO-hzcnolhe) in every job; the template
  resolves `Imports: rurl (>= 3.0.1)` from Posit Package Manager like any
  dependency, so CI tests the rurl CRAN serves, as a user installs it.
- **No hand-started pipeline on a branch.** The former `workflow:` admitted
  a web pipeline on any ref, running the full gate there, with the deep-check
  and audit jobs offered as manual. The template admits a web pipeline only
  with `RELEASE=1` on `main` or a `v*` tag, or `PAGES=1` on a tag.
- **`pages` deploys from a `v*` tag only**, not on every push to `main`, so
  the site documents the release CRAN serves.
- **The per-push check left macOS.** The former hook ran `R CMD check` on
  the maintainer's macOS R and Apple clang; T1 runs it on Linux in the fleet
  image. macOS's compiler warnings now show only at R-hub, per release (step
  6), while the case-folding legs, which macOS's libc cannot turn red, now
  run where they can.
- **Self-tests run when their script changes.** The former
  `citation-version` job ran the `check-citation.py`, `check-bugreports.py`
  and `check-news.py` self-tests on every push to `main`.
- **No runner tag.** The former CI's `default: tags: [local-docker]` is
  gone: the template sets no `tags`. That is safe while shared runners stay
  off (Runner, above); if they were ever enabled on the project, jobs could
  land on GitLab's SaaS runners instead.
- **The validators that read the old CI are retired**: `dev/check-ci-config.R`
  pinned the `.r-binaries` library-path line and the `.pkgdown-site`
  keep-list (the `pages` keep-list is `.fleet-ci.yml`'s `pages_keep`, which
  the template enforces, and no job keeps an R library cache), and
  `dev/verify.sh` and `dev/gates.R`, whose gates are now `.fleet-ci.yml`
  gates.
- **Comments in `tests/` and the dated release audits under `design/` still
  name the former hook** (`test-security.R`, `dev/verify.sh`); a CI migration
  does not edit `tests/`, and the audits record what ran at the time.
- **Pandoc** comes from the fleet image (`.fleet-ci/toolchain`, 3.10), which
  reproduces the committed `README.md`. `scripts/check-toolchain.R` checks a
  local pandoc against it, so a local README knit writes what the gate
  accepts.
