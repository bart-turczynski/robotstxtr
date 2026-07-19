# Yandex integration release audit (YI7)

**Unit:** ROBO-riraydjo (YI7 — release audit and handoff).
**Contract:** `design/robotstxtyandex-integration-v1-spec.md`, revision
`2026-07-18.2`.
**Audit date:** 2026-07-19.

This is the YI7 "final MUST audit" record for the activated Yandex matcher
backend. It is durable and committed.

## 1. Scope and boundary

This audit authorizes **completion and handoff only**. It does **not**
authorize:

- version tagging;
- CRAN or GitHub release / publication;
- downstream adoption; or
- new crawler profiles.

Each of those requires **separate** authorization. Per the approved decision
`YI-V1-RELEASE` and spec §21, "integration completion does not itself authorize
tagging or publication," and the §17 (YI7) delivery slice states "tagging,
publication, and downstream adoption require separate authorization." The audit
confirms the activation is complete and reproducible within the unreleased
`0.2.0` line; it does not move the release forward beyond that.

## 2. Runtime identity (frozen, exact)

The activated backend's identity is byte-frozen. The values below byte-match
`inst/vendor/robotstxtyandex/MANIFEST.dcf` and the corpus
`inst/yandex-corpus/PROVENANCE.dcf`, and are asserted by
`tests/testthat/test-yandex-identity-fidelity-huhaxrtp.R`.

| Field | Value |
| --- | --- |
| Library version | `0.2.0` |
| Payload commit | `fdd60a7c3bc6825f3b3752562dc0d6ad9387a27e` |
| Profile id | `yandex-0.1.0` |
| Accepted-corpus revision | `337b9f3b886a92d6dc08c2fce84228d0cd6b801a` |
| Profile-source revision | `337b9f3b886a92d6dc08c2fce84228d0cd6b801a` |
| Evidence snapshot | `9d69d361db81e7d236562dc056b41865da33d467d06f316e2c9a20988e007c96` |
| Schema / contract revision | `2026-07-18.2` |
| Contract id | `robotstxtr.yandex-backend/v1` |
| Host facade | `robotstxtr.engine-aware/v1` |

Composed `MatcherRevision` (verbatim from
`inst/vendor/robotstxtyandex/MANIFEST.dcf`):

```
robotstxtyandex/0.2.0+payload.fdd60a7c3bc6825f3b3752562dc0d6ad9387a27e;profile=yandex-0.1.0;corpus=337b9f3b886a92d6dc08c2fce84228d0cd6b801a;evidence=9d69d361db81e7d236562dc056b41865da33d467d06f316e2c9a20988e007c96;profile-source=337b9f3b886a92d6dc08c2fce84228d0cd6b801a
```

The separately inspectable library / payload / profile / corpus / evidence /
profile-source fields are published as
`robots_engine_contract_v1()$matcher_identity$yandex`.

## 3. Bounded capability

- **Supported crawlers:** exactly `Yandex` and `YandexAdditionalBot`
  (case-insensitively). Every other non-empty Yandex-backend product token
  resolves to a checked `unsupported_crawler` non-decision; missing/empty
  tokens remain facade-invalid (`YI-V1-TOKENS`).
- **Conformance corpus:** 140 cases across 26 distinct bodies. Crawler
  breakdown `Yandex = 119`, `YandexAdditionalBot = 21`; decision breakdown
  `allow = 74`, `disallow = 66`. Every accepted expectation passes through the
  public R facade.
- **Not production parity.** This is an independent, unofficial compatibility
  profile. `robotstxtyandex` is "not affiliated with or endorsed by Yandex."
  The backend claims no production-crawler equivalence, exhaustive tester
  equivalence, support for other Yandex crawler identities, or semantics beyond
  the accepted `yandex-0.1.0` profile (spec §18 completion caveat).

## 4. R version floor

The declared floor `R (>= 4.1.0)` (`DESCRIPTION`) is **correct for the package
runtime** and is **not** bumped by this activation.

`tools::sha256sum` (R >= 4.5.0) is used **only** by internal, non-exported
verifier helpers:

- `yandex_sha256_file` / `verify_yandex_vendor_tree` in
  `R/vendor-manifest-verify.R`; and
- `yandex_corpus_sha256_file` / `verify_yandex_corpus` in `R/yandex-corpus.R`.

These are reachable only from dev/CI scripts and tests (which now skip cleanly
when `sha256sum` is absent — see task 3 / `skip_if_no_sha256()` in
`tests/testthat/test-yandex-corpus-novczgii.R` and
`tests/testthat/test-vendor-manifest-verify-zfhakxcn.R`), never from any
exported evaluation path. Both helpers **fail closed** with a clear `stop()` on
old R. **Conclusion:** no floor bump. The dev/CI vendor-fidelity lane requires
R >= 4.5 and runs on CI `release`.

## 5. Gates and lanes run

All commands below were exercised on 2026-07-19 on darwin (macOS). The
orchestrator runs the authoritative pass on the committed tree; the
"working-tree run" lines record what this audit observed on the working tree.

**Locally substantiated (macOS):**

- `bash dev/verify.sh` — lint + `R CMD check --as-cran` on a clean `git-archive`
  export. **PASS** — orchestrator, committed tree `0af2ebb` (2026-07-19):
  0 errors / 0 warnings / 1 NOTE (expected CRAN-incoming "New submission"); lint
  clean. This is the authoritative gate.
- `Rscript dev/audit-package.R` — offline build/install + legal +
  vendor-fidelity on the built tarball. **PASS** — orchestrator independent
  re-run (2026-07-19): Apache-2.0 license present, `src/` compiled-only (not
  installed), `LICENSE.md`/`THIRD_PARTY_NOTICES.md` excluded, vendored tree
  byte-identical in the extracted tarball.
- `Rscript dev/verify-yandex-vendor.R` — real-tree byte fidelity of the
  vendored payload. **PASS** — orchestrator independent re-run (2026-07-19):
  21/21 files match the frozen manifest.
- `Rscript -e 'stopifnot(robotstxtr:::verify_yandex_vendor_tree("src/vendor/robotstxtyandex")$ok)'`
  **PASS** — orchestrator independent re-run (2026-07-19): `$ok == TRUE`.
- `Rscript -e 'stopifnot(robotstxtr:::verify_yandex_corpus()$ok)'`
  **PASS** — orchestrator independent re-run (2026-07-19): `$ok == TRUE`,
  140 records / 26 bodies.
- `Rscript -e 'devtools::test()'` — full test suite. **PASS** — exercised inside
  the authoritative `dev/verify.sh` R CMD check on the committed tree; the
  working-tree run recorded 1874 pass / 0 fail / 2 credential-gated skips.

**CI-substantiated, NOT locally run** (stated honestly — these lanes were not
run on this darwin working tree):

- Windows-latest and ubuntu `oldrel-1` full check (`.github/workflows/full-check.yml`);
- ASAN/UBSAN and valgrind sanitizer lanes (`.github/workflows/sanitizers.yml`);
- OSS Index / OSV security audit (secret-gated;
  `.github/workflows/security-audit.yml`, `.github/workflows/osv-audit.yml`).

### §5 addendum — working-tree run 2026-07-19 (darwin)

Observational results captured on the working tree by the YI7 audit run (R
>= 4.5, so the sha256-dependent lanes actually executed). The orchestrator's
authoritative run on the committed tree supersedes these:

- `bash dev/verify.sh` — **PASS** (exit 0). `R CMD check --as-cran` on the clean
  `git-archive` export: 0 errors, 0 warnings, 1 NOTE (the expected CRAN-incoming
  "New submission" note only). Lint clean.
- `Rscript dev/audit-package.R` — **PASS** (exit 0). Offline build/install +
  legal + vendor-fidelity clean; `verify_yandex_vendor_tree(extracted tarball)$ok`
  passes; vendored `src/` compiled-only (not installed); MANIFEST + Apache-2.0
  license present.
- `Rscript dev/verify-yandex-vendor.R` — **PASS** (exit 0). 21/21 files matched
  the frozen manifest.
- `verify_yandex_vendor_tree("src/vendor/robotstxtyandex")$ok` — **PASS** (TRUE).
- `verify_yandex_corpus()$ok` — **PASS** (TRUE); `n_records = 140`,
  `n_bodies = 26`. (Run via `pkgload::load_all()` because the installed 0.2.0
  binary on this host predated the YI6a corpus verifier; the source function
  verifies clean and the corpus tests pass under `devtools::test()`.)
- `Rscript -e 'devtools::test()'` — **PASS**. `FAIL 0 | WARN 0 | SKIP 2 |
  PASS 1874`. Both skips are the OSS Index security tests (credential-gated,
  `OSSINDEX_USER`/`OSSINDEX_TOKEN` unset); no sha256 lane was skipped on this
  R >= 4.5 host.
- Lint (`lintr::lint_package()`) — **CLEAN**.

## 6. Reproduction and handoff

All steps are **offline** and require **no sibling checkout** and **no
network** — the payload and corpus are byte-pinned in the package tree.

From a fresh clone:

```bash
# 1. Install once (dev): resolves rurl from the author's R-universe.
Rscript -e 'options(repos = c("bart-turczynski" = "https://bart-turczynski.r-universe.dev", getOption("repos"))); install.packages(c("rurl", "devtools"))'
Rscript -e 'devtools::install(dependencies = TRUE)'

# 2. Identity + fidelity + corpus (offline, no sibling, no network):
Rscript -e 'stopifnot(robotstxtr:::verify_yandex_vendor_tree("src/vendor/robotstxtyandex")$ok)'
Rscript -e 'stopifnot(robotstxtr:::verify_yandex_corpus()$ok)'
Rscript dev/verify-yandex-vendor.R

# 3. Full offline build/install + legal + vendor-fidelity audit on the tarball:
Rscript dev/audit-package.R

# 4. Clean-export check (lint + R CMD check --as-cran):
bash dev/verify.sh
```

**`rurl (>= 2.2.1)` resolution.** `rurl` at the required version is not yet on
CRAN. CI resolves it through the author's R-universe via the
`extra-repositories: https://bart-turczynski.r-universe.dev` setup-r input
(see `.github/workflows/osv-audit.yml`, `security-audit.yml`, and the
`options(repos = ...)` prepend in `sanitizers.yml`). It is resolved as a
**repository**, not a `Remotes:` field in `DESCRIPTION`. Once a
CRAN-compatible `rurl` is live this extra repository can be removed
(tracked separately).

## 7. Preserved deferrals and disclaimers

The following spec §20 deferred-work items remain **outside v1** and are
preserved unchanged by this audit:

- additional Yandex crawler profiles;
- production-crawler equivalence claims;
- `Clean-param` URL rewriting or deduplication;
- public diagnostics or analyzer UI;
- crawler-selection trace and per-line parser-reporting APIs;
- crawl scheduling or `Crawl-delay` enforcement;
- sitemap fetching or validation;
- newly promoted rule / line / parameter / body-limit semantics;
- persistent public native policy pointers;
- parallel R evaluation or process-global matcher caches;
- Google binding refactors or optimizations unrelated to dispatch;
- a shared Google/Yandex parser or matcher kernel; and
- **RFC 9309 and Bing backend activation.**

The approved owner decisions `YI-V1-*` (spec §19) remain binding, including
`YI-V1-METADATA`, `YI-V1-TRACE`, `YI-V1-REPORT`, and `YI-V1-LIMITS` (which defer
diagnostics, crawler-selection provenance, per-line reporting, and additional
parser-limit semantics), and `YI-V1-RELEASE` (completion does not authorize
tagging/publication).

**Disclaimers preserved:** non-affiliation with Yandex; no production-crawler
parity; no tagging/publication authorization from this integration.

`rfc9309` and `bing` matcher backends remain `capability_unavailable`. **Bing
activation requires a future `robotstxtr.engine-aware/v2`** (a Bing matcher is
not backed by any current profile and is not synthesized under Bing's name).

## 8. Remaining external release actions (require separate human authorization)

The following are **not** authorized by this audit and must be separately
authorized by a human:

1. version tag for the `0.2.0` line;
2. CRAN and/or GitHub release / publication; and
3. downstream adoption.

Until then, the activation stands as complete, reproducible, and frozen within
the unreleased `0.2.0` line.
