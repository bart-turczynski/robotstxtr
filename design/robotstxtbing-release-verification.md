# robotstxtbing 0.1.0 — robotstxtr-side release verification (ROBO-xgjvnfii)

Status: FINAL — owner-accepted 2026-07-24 (see §9). Recommendation: **GO** (accepted).
Verified: 2026-07-24 (darwin, cmake 4.3.4, Apple clang 21). Method: 3 offline read/build-only
units against the pinned release; neither repo's working tree mutated.

## 1. Scope & boundary
Independent robotstxtr-side verification that robotstxtbing **0.1.0** implements its approved
frozen contract before robotstxtr adopts/vendors it. This is a go/no-go gate, NOT authorization to
finish library work inside robotstxtr. Later integration work is filed only from this decision.

## 2. Pin & runtime identity (frozen, exact)
- Release tag `0.1.0` → payload commit `c82855d0756c748cc4770246a19282323cdfa331`.
- Release manifest `releases/robotstxtbing-0.1.0.manifest`, sha256 `5e79ee5d…0858` (non-self-referential).
- Archives (verified against `SHA256SUMS`): static `d1552e1f…`, shared `91aa203f…` — both `shasum -c` OK, match `docs/RELEASE_AUDIT_0.1.0.md`.
- Shipped `contract_info()` (release-cache-injected): **contract_id literal `robotstxtbing-v2`**,
  contract_revision = parser_revision = `0.1.0`, profiles `bingbot-2026-07-23.1` / `adidxbot-2026-07-23.1`.
- Note (benign): audit's R1–R7 frozen library commit `8fc55919…` differs from tag `c82855d0…` — the
  expected docs-only R8 sign-off layered atop the frozen library; no source change; identity unchanged.

## 3. Legal / provenance (V1 — PASS)
- LICENSE = **Apache-2.0** (confirmed), NOTICE + clean-room PROVENANCE present.
- Runtime deps = libc++ / libSystem only. No Abseil / no third-party runtime dependency — the
  standard-library-only claim holds.

## 4. Build / install / consume / conformance (V2 — GREEN)
- Both prebuilt variants relocated into clean prefixes; consumer `find_package(robotstxtbing CONFIG
  REQUIRED)` links ONLY the exported target `robotstxtbing::robotstxtbing` and runs correctly from
  relocated prefixes (static self-contained; shared @rpath dylib). Decisions correct.
- From-source tag-0.1.0 build clean. Offline gates: build-first **129/129**; offline_verify PASS
  (static 129/129, shared 129/129, sanitizers 127/127) — matches the RC audit exactly.
- First-pass `repository_safety` 128/129 was a scratch-tree `__pycache__` artifact from our own test
  run; `PYTHONDONTWRITEBYTECODE=1` + clean → 129/129. Not a library defect, not a gate regression.

## 5. Contract-vs-manifest conformance (V3 — CONFORMS)
- 7 public headers byte-match spec §6 signatures; 6 limit ceilings match §7; 5+5 status enums,
  Decision/RuleMatch shapes, 16 diagnostic codes, and metadata structs all match; contract_info
  self-consistent with the manifest.
- **No-misreport-as-allow is structurally enforced** (verified `src/policy.cpp`): only
  `EvaluationStatus::evaluated` carries a Decision (all other statuses → `std::nullopt`); only
  `ParseStatus::parsed` yields a Policy; `default_allow` occurs only inside a genuine evaluated
  decision. Unsupported profile / invalid target / limit-exceeded / absent-decision cannot become allow.

## 6. Schema decision (the one that diverges from Yandex) — evidence-resolved
All FOUR of Bing's distinctive outcomes — invalid-request-target, unsupported-profile,
input/parse-limit-exceeded, and **work-limit-exceeded** — are surfaced as DISTINCT first-class result
states. Yandex fit `engine-aware/v1` losslessly because its adapter only emits
`evaluated`/`not_evaluated`; Bing does not. A lossless adapter therefore REQUIRES a new
**`robotstxtr.engine-aware/v2`** matcher-status set (adding invalid_request_target,
unsupported_profile, matcher_input_limit_exceeded, matcher_work_limit_exceeded), NOT an incremental
v1 revision bump. This agrees with sibling v2-spec §16 and design/yandex-integration-release-audit.md:217.

## 7. Discrepancies (non-blocking, not allow-safety) → fold into the durable integration spec
- **D1** — adapter must pin the LITERAL shipped contract_id `robotstxtbing-v2` (spec prose says
  `robotstxtbing.compatibility/v2`).
- **D2** — robotstxtr's local `design/robotstxtbing-v2-spec.md` is a STALE `2026-07-17.2` draft
  (cutoff 2026-07-17); the release shipped at spec_revision `2026-07-23.1` / cutoff `2026-07-23`.
  Sync when promoting the durable integration spec.

## 8. Recommendation
**GO** — 0.1.0 is reproducibly verified, correctly licensed, dependency-clean, conformant, and
safe-by-construction. Adoption is gated only on the owner decision (schema = v2, exact pin, named
contract decisions) and a merged durable integration spec, mirroring the Yandex YI0 gate.

## 9. Owner acceptance decision
Owner decision recorded verbatim on 2026-07-24 (bartek@turczynski.pl): **"approve all three as written"**, in response to the three-item gate:
1. **GO** — adopt robotstxtbing 0.1.0 (verified green).
2. **Schema** = new `robotstxtr.engine-aware/v2` matcher-status set (adds `invalid_request_target`, `unsupported_profile`, `matcher_input_limit_exceeded`, `matcher_work_limit_exceeded`); a deliberate divergence from the Yandex incremental-v1 pattern, required because Bing surfaces those four outcomes as distinct states with no lossless v1 representation.
3. **Pin** (exact): library `0.1.0` / payload `c82855d0756c748cc4770246a19282323cdfa331` / static archive `d1552e1f…` + shared `91aa203f…` / manifest sha256 `5e79ee5d…0858` / profiles `bingbot-2026-07-23.1` + `adidxbot-2026-07-23.1` / contract_id literal `robotstxtbing-v2` / license Apache-2.0.

Decision: **ACCEPT**. Later integration work (durable integration spec + build slices) is authorized to be *filed and drafted* from this decision; implementation itself remains blocked until the durable `design/robotstxtbing-integration-v2-spec.md` is approved and merged (Yandex YI0 pattern). ROBO-xgjvnfii closes once that spec is approved and the build issues are filed.
