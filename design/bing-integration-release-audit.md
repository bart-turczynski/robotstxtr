# Bing integration release audit (BI7)

**Unit:** ROBO-ahilajyn (BI7 — Bing v2 release audit and handoff).
**Contract:** `design/robotstxtbing-integration-v2-spec.md`, host schema revision
`2026-07-24.1` (`robotstxtr.engine-aware/v2`).
**Audit date:** 2026-07-24.

This is the BI7 "final MUST audit" record for the activated Bing matcher
backend. It is durable and committed. It is the direct robotstxtr-side analog of
`design/yandex-integration-release-audit.md` (YI7) for the Yandex backend.

This audit is the **integration** record. It is distinct from the upstream,
library-side go/no-go in `design/robotstxtbing-release-verification.md`
(ROBO-xgjvnfii), which verified that `robotstxtbing 0.1.0` implements its own
frozen contract before robotstxtr adopted it. This document does not repeat that
verification; it cross-references it and records the robotstxtr-side integration
result on top of it.

## 1. Scope and boundary

This audit authorizes **completion and handoff only**. It does **not**
authorize:

- version tagging;
- CRAN or GitHub release / publication;
- downstream adoption; or
- new crawler profiles.

Each of those requires **separate** authorization. Per spec §18, "completion
does not establish production Bing crawler parity, exhaustive tester
equivalence, support for other Bing crawler identities, or semantics beyond the
accepted profiles," and tagging, publication, and downstream adoption require
separate authorization. The audit confirms the activation is complete and
reproducible within the unreleased `0.2.0` line; it does not move the release
forward beyond that.

## 2. Runtime identity (frozen, exact)

The activated backend's identity is byte-frozen. The values below byte-match
`inst/vendor/robotstxtbing/MANIFEST.dcf` and `inst/vendor/robotstxtbing/PROVENANCE`,
and are cross-checked by the corpus manifest `inst/bing-corpus/PROVENANCE.dcf`.

| Field | Value |
| --- | --- |
| Library version | `0.1.0` |
| Payload tag object | `c82855d0756c748cc4770246a19282323cdfa331` |
| Payload target commit | `1f2431b9d47ba25dec313eec5a396e795f00b5b8` |
| V3-audit RC-freeze commit | `8fc55919bacc297f40411f83c9fe819dece69c84` |
| Sibling contract id | `robotstxtbing-v2` |
| Sibling contract revision | `0.1.0` |
| Parser revision | `0.1.0` |
| Bingbot profile revision | `bingbot-2026-07-23.1` |
| AdIdxBot profile revision | `adidxbot-2026-07-23.1` |
| Sibling spec revision | `2026-07-23.1` |
| Sibling evidence cutoff | `2026-07-23` |
| Release manifest file | `releases/robotstxtbing-0.1.0.manifest` |
| Release manifest SHA-256 | `5e79ee5dcb1a22b73b5fa0f86766be529cf111fd5530d07b53fe1d6b7050a858` |
| Static archive SHA-256 | `d1552e1f146e5155b75f8ef30e8e8cbab3e96fa46de1455b3511cbea738aeed6` |
| Shared archive SHA-256 | `91aa203f8d35f41df5783709501c379f169e7b90bb7045d4a88e887e9c56aa7f` |
| Language baseline | `C++17` |
| Payload license | `Apache-2.0` |

**Pin reconciliation (`c82855d0` / `1f2431b` / `8fc55919`).** The owner-approved
pin `c82855d0756c748cc4770246a19282323cdfa331` is the **annotated tag object**
for tag `0.1.0` ("robotstxtbing 0.1.0 -- first frozen release", BING-osxlywax
R8); its recorded target commit is `1f2431b9d47ba25dec313eec5a396e795f00b5b8`.
The V3-audit RC-freeze commit `8fc55919bacc297f40411f83c9fe819dece69c84` (R7)
differs from the pin only by a docs-only R7→R8 delta (`CHANGELOG.md`,
`README.md`, `docs/RELEASE_AUDIT_0.1.0.md`) with zero production, source, or
profile bytes changed. Consequently `contract_info()` identity and every
vendored file SHA-256 are byte-identical between the audited commit and the
pinned release tree. A moving branch, a tag without a recorded target commit, or
a sibling worktree is not a valid pin.

Composed `MatcherRevision` (verbatim from
`inst/vendor/robotstxtbing/MANIFEST.dcf`):

```
robotstxtbing/0.1.0+payload.c82855d0756c748cc4770246a19282323cdfa331;contract=robotstxtbing-v2;contract-rev=0.1.0;parser=0.1.0;bingbot=bingbot-2026-07-23.1;adidxbot=adidxbot-2026-07-23.1;manifest=5e79ee5dcb1a22b73b5fa0f86766be529cf111fd5530d07b53fe1d6b7050a858
```

This string is single-sourced in R at activation (BI5) and byte-equals the
manifest `MatcherRevision` field. Every component
(library / payload / contract / parser / profiles / manifest) remains separately
inspectable through `robots_engine_contract_v2()$matcher_identity$bing`.

**Two package contracts.** The activation introduces the v2 host facade while
leaving v1 byte-unchanged:

| Accessor | Contract id | Schema revision |
| --- | --- | --- |
| `robots_engine_contract_v1()` | `robotstxtr.engine-aware/v1` | `2026-07-18.2` |
| `robots_engine_contract_v2()` | `robotstxtr.engine-aware/v2` | `2026-07-24.1` |

The v1 accessor's own `contract_id` and `schema_revision` are byte-unchanged by
this activation (spec §16.5). Only the new v2 accessor reports `.../v2` and
`2026-07-24.1`.

## 3. Bounded capability

- **Supported crawlers:** exactly the profiles `bingbot` and `adidxbot`
  (ASCII case-folded token match). Every other non-empty Bing-backend product
  token resolves to a checked `unsupported_profile` non-decision; missing/empty
  tokens remain facade-invalid.
- **Six core limits (enforced by the vendored core alone).** These are matcher
  limits, distinct from the host `max_bytes` acquisition policy that governs how
  many bytes are fetched before evaluation:

  | Limit (`include/robotstxtbing/limits.h`) | Value |
  | --- | --- |
  | `kMaxBodyBytes` | `2,097,152` |
  | `kMaxPhysicalLineBytes` | `65,536` |
  | `kMaxClassifiedRecords` | `65,536` |
  | `kMaxAccessRules` | `16,384` |
  | `kMaxRequestTargetBytes` | `65,536` |
  | `kMaxMatcherWorkUnits` | `67,108,864` |

- **Distinct non-decision states.** The v2 schema extends v1's four-value status
  vocabulary (`evaluated`, `not_needed`, `not_evaluated`,
  `capability_unavailable`) with four Bing outcomes v1 cannot losslessly carry:
  `invalid_request_target`, `unsupported_profile`,
  `matcher_input_limit_exceeded` (the four parse/input limits plus the
  request-target-limit fold in here, distinguished by `reason`), and
  `matcher_work_limit_exceeded`. Ordering is fixed (four v1 statuses, then four
  v2 additions) and enforced fail-closed by `validate_matcher_status_v2()` in
  `evaluate_rows_v1()`. **No non-evaluated status may ever be represented as an
  allow/disallow decision.**
- **Conformance corpus:** 191 concrete observation-level cases across 95 bodies
  (`bingbot = 95`, `adidxbot = 96`; `allow = 110`, `disallow = 81`), projected
  from 57 accepted `tester_observed` cells (29 bingbot / 28 adidxbot). Every
  accepted expectation passes through the public v2 facade.
- **Not production parity.** This is an independent, unofficial compatibility
  profile. `robotstxtbing` is not affiliated with, endorsed by, or maintained by
  Microsoft, Bing, Bingbot, or AdIdxBot, and contains no Microsoft/Bing source
  code, documentation text, or private data. The backend claims no
  production-crawler equivalence, exhaustive tester equivalence, support for
  other Bing crawler identities, or semantics beyond the accepted `bingbot` /
  `adidxbot` profiles (spec §18 completion caveat).

## 4. R version floor

The declared floor `R (>= 4.1.0)` (`DESCRIPTION`) is **correct for the package
runtime** and is **not** bumped by this activation. The vendored payload
compiles under `CXX_STD = CXX17` (`src/Makevars`, `src/Makevars.win`), which is
supported by every R the package targets.

`tools::sha256sum` (R >= 4.5.0) is used **only** by internal, non-exported
verifier helpers:

- `bing_sha256_file` / `verify_bing_vendor_tree` in
  `R/vendor-manifest-verify.R`; and
- the corpus SHA-256 verifier in `R/bing-corpus.R` (`verify_bing_corpus`).

These are reachable only from dev/CI scripts and tests, never from any exported
evaluation path, and **fail closed** with a clear `stop()` on old R.
**Conclusion:** no floor bump. The dev/CI vendor-fidelity lane requires R >= 4.5
and runs on CI `release`.

## 5. The §18 12-item MUST audit

Each spec §18 definition-of-done item, with the evidence (manifest / test / gate)
that discharges it. All cited artifacts are on `main` at the audited tree.

1. **Exact payload, both profile revisions, three SHA-256 digests approved and
   reproducible.** → `inst/vendor/robotstxtbing/MANIFEST.dcf` +
   `PROVENANCE`: tag object `c82855d0`, target commit `1f2431b`, profiles
   `bingbot-2026-07-23.1` / `adidxbot-2026-07-23.1`, release-manifest /
   static / shared digests. The release-manifest digest was independently
   reproduced from the shipped manifest at the pin (`§2`, PROVENANCE).
2. **Every vendored production file pinned and verified offline.** →
   35-file per-file SHA-256 set in `MANIFEST.dcf`; offline verifier
   `verify_bing_vendor_tree()` (`R/vendor-manifest-verify.R`); gate
   `dev/verify-bing-vendor.R` Phase A (35/35 matched).
3. **Explicit dispatch makes Google/Yandex fallback impossible.** → dispatch
   sentinels in `tests/testthat/test-cross-engine-separation-pdcrkcvq.R`
   (BD1–BD3 dispatch counters, BSEP1–BSEP4 separation); non-regression
   `tests/testthat/test-bing-nonregression-onwulhga.R` asserts Google/Yandex
   never invoke Bing.
4. **URL→request-target conversion byte-characterized without reconstructed
   `rurl`, Google, or Yandex semantics.** → `bing_extract_request_target()`
   (`R/bing-native.R`, `src/bing_binding.cpp`) exercised in
   `tests/testthat/test-match-bing-v1-qetsyvwv.R` and the request-target-limit
   sentinel BSEP2.
5. **Missing/empty tokens facade-invalid; unsupported profiles, invalid/
   over-limit targets, parse limits, work limits are distinct non-decisions that
   can never be allow/disallow.** → `engine_matcher_status_set_v2()` +
   `validate_matcher_status_v2()` (`R/engine-contract-v1.R`, BI1);
   `test-bing-activation-public-facade-qetsyvwv.R`; separation sentinels
   BSEP2/BSEP3.
6. **Every accepted Bing expectation passes through the public v2 facade.** →
   `inst/bing-corpus/` (191 cases) replayed through the facade in
   `tests/testthat/test-bing-corpus-onwulhga.R`; generator
   `dev/gen-bing-corpus.R` asserts engine decision == tester decision per case;
   two-tier provenance in `inst/bing-corpus/PROVENANCE.dcf`.
7. **Effective empty Disallow retains its distinct source and original rule.** →
   corpus `*-empty-*` bodies + adapter tests in
   `test-match-bing-v1-qetsyvwv.R`. NOTE: the shipped Bing profile treats an
   empty `Disallow:` as **inert → `default_allow`** (see §7); the effective-empty
   representation and its `raw(0)` owning-rule bytes are exercised where the
   profile produces them.
8. **Arbitrary rule bytes exact through the `raw(0)`/`NULL` representation.** →
   `matched_rule_value_raw` list column checks in
   `test-match-bing-v1-qetsyvwv.R` and the facade corpus replay.
9. **Six core limits enforced by the core alone, distinct from acquisition
   policy.** → `include/robotstxtbing/limits.h` (§3 table); input-limit /
   work-limit non-decision states in the v2 status set; acquisition `max_bytes`
   stays a separate host concern (BSEP2 request-target limit sentinel).
10. **v2 status/reason/error/raw-value/matcher-identity contract published.** →
    `robots_engine_contract_v2()` (contract id `robotstxtr.engine-aware/v2`,
    schema `2026-07-24.1`, eight-member status set,
    `matcher_identity$bing`) in `R/engine-contract-v1.R`;
    `test-bing-activation-public-facade-qetsyvwv.R`.
11. **Google and Yandex source, behavior, metadata, identities, and legacy APIs
    unchanged.** → `tests/testthat/test-bing-nonregression-onwulhga.R` (§16.5:
    Yandex bytes/revisions/schema/corpus unchanged; Google/Yandex never invoke
    Bing); the v1 accessor stays `.../v1` + `2026-07-18.2`.
12. **Clean build/test/install/fidelity/provenance/legal/sanitizer/portability
    gates pass without a sibling checkout.** → `dev/verify-bing-vendor.R`
    (byte fidelity / package-owned separation / Apache-2.0 survival / corpus
    equivalence) + the sibling-free `bing-vendor-fidelity` job in
    `.github/workflows/verify.yml`; Bing Apache-2.0 legal audit in
    `test-package-legal-audit-svbsdjns.R`; `dev/audit-package.R` tarball
    source/binary disposition (both engines). Sanitizer/portability lanes run on
    CI (see §6).

## 6. Gates and lanes run

All commands below were exercised on 2026-07-24 on darwin (macOS). The
"working-tree run" addendum (§6.1) records what this audit observed directly on
the working tree; the authoritative pass is the committed-tree verify gate and
CI.

**Locally substantiated (macOS):**

- `bash dev/verify.sh` — lint + `R CMD check --as-cran` on a clean `git-archive`
  export. **PASS** — 0 errors / 0 warnings / 1 NOTE (the expected CRAN-incoming
  "New submission" note); lint clean. This is the authoritative gate.
- `Rscript dev/verify-bing-vendor.R` — real-tree byte fidelity + separation +
  legal + compact-corpus engine equivalence of the vendored payload. **PASS** —
  Phase A 35/35 files matched; Phase B no package-owned code in the manifest;
  Phase C legal material present, corpus verifies (191 cases, 95 bodies);
  Phase D 28 compact-corpus cases match the vendored engine exactly.
- `Rscript dev/audit-package.R` — offline build/install + legal +
  vendor-fidelity on the built tarball, both engines. **PASS** — Apache-2.0
  license material present for Google, Yandex, and Bing; `src/` compiled-only
  (not installed); `LICENSE.md`/`THIRD_PARTY_NOTICES.md` excluded; both vendored
  trees byte-identical in the extracted tarball.
- `verify_bing_vendor_tree("src/vendor/robotstxtbing")$ok` — **PASS** (`TRUE`).
- `verify_bing_corpus()$ok` — **PASS** (`TRUE`); `n_records = 191`,
  `n_bodies = 95`, `n_bingbot = 95`, `n_adidxbot = 96`.
- Full `testthat` suite. **PASS** — exercised inside the authoritative
  `dev/verify.sh` R CMD check on the committed tree; the working-tree run
  recorded 0 failures / 0 warnings / 3 skips (see §6.1).

**CI-substantiated, NOT locally run** (stated honestly — these lanes were not
run on this darwin working tree):

- Windows-latest and ubuntu `oldrel-1` full check
  (`.github/workflows/full-check.yml`); **Windows CI is historically red
  (ROBO-yasmzyhl)** — pre-existing and unrelated to this epic;
- ASAN/UBSAN and valgrind sanitizer lanes (`.github/workflows/sanitizers.yml`);
- OSS Index / OSV security audit (secret-gated;
  `.github/workflows/security-audit.yml`, `.github/workflows/osv-audit.yml`).

The push-triggered `verify.yml` (lint, README-sync, ubuntu R CMD check,
coverage, **Vendored Yandex** + **Vendored Bing byte + legal fidelity** jobs)
and `pkgdown` (build + deploy) are green on `main`.

### 6.1 §6 addendum — working-tree run 2026-07-24 (darwin)

Observational results captured on the working tree by the BI7 audit run
(R >= 4.5, so the sha256-dependent lanes actually executed). The committed-tree
verify gate and CI supersede these:

- `Rscript dev/verify-bing-vendor.R` — **PASS** (exit 0). Phase A 35/35;
  Phase B clean; Phase C 191 cases / 95 bodies; Phase D 28/28.
- `verify_bing_vendor_tree("src/vendor/robotstxtbing")$ok` — **PASS** (`TRUE`),
  via `pkgload::load_all()` (the installed 0.2.0 binary on this host predates the
  BI3/BI6 verifier; the source function verifies clean).
- `verify_bing_corpus()$ok` — **PASS** (`TRUE`); `n_records = 191`,
  `n_bodies = 95`, `n_bingbot = 95`, `n_adidxbot = 96`.
- Full `testthat` suite — **PASS**. `FAIL 0 | WARN 0 | SKIP 3` (415 tests). The
  three skips are the OSV / OSS-Index-on-CRAN security tests (credential-gated)
  plus one install-only legal exclusion; no sha256 lane was skipped on this
  R >= 4.5 host.
- `bash dev/verify.sh` — **PASS** (exit 0). `R CMD check --as-cran` on the clean
  `git-archive` export: 0 errors, 0 warnings, 1 NOTE (the expected
  CRAN-incoming "New submission" note only). Lint clean.

## 7. Reproduction and handoff

All steps are **offline** and require **no sibling checkout** and **no
network** — the payload and corpus are byte-pinned in the package tree. The
sibling `../robotstxt-cpp-bing` is a corpus-import SOURCE only; it is never
fetched at build/test/install/runtime.

From a fresh clone:

```bash
# 1. Install once (dev): resolves rurl from the author's R-universe.
Rscript -e 'options(repos = c("bart-turczynski" = "https://bart-turczynski.r-universe.dev", getOption("repos"))); install.packages(c("rurl", "devtools"))'
Rscript -e 'devtools::install(dependencies = TRUE)'

# 2. Identity + fidelity + corpus (offline, no sibling, no network):
Rscript -e 'stopifnot(robotstxtr:::verify_bing_vendor_tree("src/vendor/robotstxtbing")$ok)'
Rscript -e 'stopifnot(robotstxtr:::verify_bing_corpus()$ok)'
Rscript dev/verify-bing-vendor.R

# 3. Full offline build/install + legal + vendor-fidelity audit on the tarball:
Rscript dev/audit-package.R

# 4. Clean-export check (lint + R CMD check --as-cran):
bash dev/verify.sh
```

**`rurl (>= 2.2.1)` resolution.** `rurl` at the required version is not yet on
CRAN. CI resolves it through the author's R-universe via the
`extra-repositories: https://bart-turczynski.r-universe.dev` setup-r input. It
is resolved as a **repository**, not a `Remotes:` field in `DESCRIPTION`. A
green local gate is not sufficient evidence for a green GitHub CI run; confirm
`verify.yml` + `pkgdown` after merge. Once a CRAN-compatible `rurl` is live this
extra repository can be removed (tracked separately, ROBO-yasmzyhl).

## 8. Preserved deferrals and disclaimers

**Schema divergence from the Yandex backend (preserved, deliberate).** The
shipped Bing profile treats an empty `Disallow:` as **inert →
`default_allow`**, NOT as an effective-empty allow-everything rule. The Bing
corpus therefore never exercises effective_empty. This differs from the Yandex
backend, whose empty `Disallow` is an effective-empty rule with `raw(0)` owning
bytes. The v2 status/reason vocabulary keeps both behaviors representable without
relabeling either engine.

**Preserved out-of-scope items.** The following remain outside this activation
and are preserved unchanged:

- additional Bing crawler identities beyond `bingbot` / `adidxbot`;
- production-crawler equivalence or exhaustive tester-equivalence claims;
- public diagnostics, analyzer UI, crawler-selection trace, or per-line
  parser-reporting APIs;
- crawl scheduling or `Crawl-delay` enforcement;
- newly promoted rule / line / record / body-limit semantics beyond the six
  frozen core limits;
- a shared Google/Yandex/Bing parser or matcher kernel; and
- RFC 9309 backend activation (`rfc9309` remains `capability_unavailable`).

**Disclaimers preserved:** non-affiliation with Microsoft / Bing / Bingbot /
AdIdxBot; no production-crawler parity; no tagging/publication authorization
from this integration. Google/Yandex/RFC9309 behavior, hashes, identities, and
the four legacy Google APIs stay byte-unchanged (spec §18.11); the v1 accessor
stays `.../v1` + `2026-07-18.2`.

## 9. Remaining external release actions (require separate human authorization)

The following are **not** authorized by this audit and must be separately
authorized by a human:

1. version tag for the `0.2.0` line;
2. CRAN and/or GitHub release / publication;
3. downstream adoption; and
4. new Bing crawler profiles or identities.

Until then, the Bing activation stands as complete, reproducible, and frozen
within the unreleased `0.2.0` line.
