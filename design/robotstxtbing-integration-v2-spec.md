# `robotstxtbing` backend integration contract v2 — DRAFT

- Status: **APPROVED 2026-07-24 (owner: bartek@turczynski.pl). Implementation-authorizing upon merge of this document.**
- Draft date: **2026-07-24**
- Contract ID (host facade): `robotstxtr.engine-aware/v2` (new; supersedes `robotstxtr.engine-aware/v1` for Bing activation)
- Activation schema revision: `2026-07-24.1` (APPROVED)
- Standalone engine: `robotstxtbing` **0.1.0** (GO — owner-approved adoption)
- Sibling contract identity (literal): `robotstxtbing-v2` (APPROVED — decision `BI-V2-PIN`/`D1`)
- Semantic profiles: `bingbot-2026-07-23.1` + `adidxbot-2026-07-23.1`
- Evidence cutoff of shipped release: **2026-07-23** (release manifest authority)

This DRAFT proposes the durable, `robotstxtr`-owned contract that would authorize
building and vendoring the independent `robotstxtbing` C++ library as an explicit
Bing matcher backend, under the new `robotstxtr.engine-aware/v2` facade contract.
It mirrors the structure and rigor of the approved
`design/robotstxtyandex-integration-v1-spec.md` but adapts every decision to Bing
semantics and to the v2 matcher-status set.

**Owner-approved decisions.** The GO decision to adopt `robotstxtbing` 0.1.0; the
SCHEMA decision to introduce `robotstxtr.engine-aware/v2` with the four additional
matcher statuses; the exact immutable PIN (including the literal sibling
`contract_id` `robotstxtbing-v2`); and — recorded on 2026-07-24 — all twelve
remaining named decisions (§19). Every named decision below is **APPROVED**.
**Implementation is authorized upon merge of this spec (see §21);** it remained
blocked until this approval.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**
describe this proposed project contract. They do not state Bing requirements
unless the selected standalone compatibility profile cites supporting dated
primary sources or accepted tester observations. `robotstxtbing` makes only a
bounded tester/document compatibility claim, never production Bingbot parity.

## 1. Intended outcome

After implementation, a call such as:

```r
robots_evaluate_text_v1(
  robots_txt,
  url,
  robots_product_token = "bingbot",
  robots_policy_ruleset = "assumed_rfc9309",
  matcher_backend = "bing"
)
```

would apply the existing `robotstxtr` status/body policy for the selected
ruleset and, when that policy selects rule evaluation, evaluate the original
request target through a pinned, vendored `robotstxtbing` backend, returning that
backend's decision and attribution without reinterpretation.

The integration MUST:

- retain the four independent axes (neutral acquisition, policy ruleset, matcher
  backend, robots product token) plus the separate HTTP User-Agent;
- identify the exact standalone payload and both semantic profile revisions;
- return Bing decisions and owning matched-rule attribution without
  reinterpretation;
- represent every non-evaluated core outcome (unsupported profile, invalid
  target, input-limit, work-limit) as a first-class, distinct matcher status
  that can never mean allow or disallow;
- preserve existing Google and Yandex behavior and source provenance; and
- build, install, test, and run without a sibling checkout or network access.

The integration MUST NOT:

- route a Bing matcher request to the Google (or any other) matcher, i.e. no
  fallback of any kind;
- infer the matcher backend from the policy ruleset or product token;
- claim production Bing crawler equivalence;
- widen the supported Bing profiles beyond `bingbot`/`adidxbot`;
- copy Google or Yandex parsing, group selection, URL normalization, or matcher
  behavior into the Bing path;
- collapse any distinct core non-evaluated outcome into a single ambiguous
  status; or
- add a submodule, `FetchContent`, runtime loader, or sibling-path dependency.

## 2. Proposed immutable baseline (PIN — APPROVED)

The owner-approved immutable standalone payload is:

| Field | Value | Disposition |
| --- | --- | --- |
| Library version | `0.1.0` | APPROVED |
| Payload Git revision | `c82855d0756c748cc4770246a19282323cdfa331` | APPROVED |
| Sibling `contract_id` (literal) | `robotstxtbing-v2` | APPROVED (pin the literal, not spec prose — see D1) |
| Contract revision | `0.1.0` | from shipped `contract_info()` |
| Parser revision | `0.1.0` | from shipped `contract_info()` |
| Bingbot profile revision | `bingbot-2026-07-23.1` | APPROVED |
| AdIdxBot profile revision | `adidxbot-2026-07-23.1` | APPROVED |
| Release manifest SHA-256 | `5e79ee5d…0858` (full digest recorded from the release manifest at import) | APPROVED (prefix); full digest to be pinned verbatim |
| Static source-archive SHA-256 | `d1552e1f…` (full digest recorded at import) | APPROVED (prefix); full digest to be pinned verbatim |
| Shared source-archive SHA-256 | `91aa203f…` (full digest recorded at import) | APPROVED (prefix); full digest to be pinned verbatim |
| Language baseline | C++17 | from §3 of the v2 spec |
| License | Apache-2.0, with installed `LICENSE`/`NOTICE` as required | APPROVED |
| Runtime dependency | C++17 standard library only | APPROVED |

**D1 (identity fidelity — pin the literal).** The `robotstxtbing` v2 spec prose
declares a contract-id token `robotstxtbing.compatibility/v2`, but the shipped
library's `contract_info().contract_id` **and** its release manifest both use the
literal `robotstxtbing-v2`, and are internally self-consistent. The adapter's
sibling-identity assertion MUST pin the actual shipped literal `robotstxtbing-v2`,
NOT the spec's prose token. The owner approved pinning the literal.

Replacing any identity above requires a later reviewed contract revision. A
moving branch, a tag without a recorded target commit, or a sibling worktree is
not a valid pin. The three SHA-256 values are recorded here by prefix as
owner-approved; the full digests MUST be transcribed verbatim from the shipped
release manifest at import and MUST match before any byte is compiled.

> Note (reconcile at import, non-blocking): the V3 evidence audit recorded the
> RC-freeze commit `8fc55919bacc297f40411f83c9fe819dece69c84` as the audited
> library commit, whereas the owner-approved payload pin is
> `c82855d0756c748cc4770246a19282323cdfa331`. As with the Yandex payload vs.
> administrative-commit distinction, the owner-approved payload commit is the
> pin; the audited-commit relationship MUST be reconciled and recorded in the
> provenance record at import (see §20 follow-ups). This DRAFT does not resolve
> that relationship.

## 3. Existing host state and prerequisite correction

`R/engine-contract-v1.R` already defines the independent axes, the matcher
registry with its validator invariants, and a `bing` registry entry that is
currently `capability_unavailable` with `callable = NULL` (registry lines
~704–708). It also already publishes a `bing` backend-capability boundary
(`token_policy = "bounded_profiles"`, `matcher_semantics = "bing"`) and a `bing`
policy ruleset whose status is `bing-documentation-gap-2026-07-17`.

The current `bing` **policy ruleset** resolves to `documentation_gap` for every
fetched status category, so a fetched `bing`-ruleset row never reaches
`use_rules`. The Bing **matcher backend** is nonetheless exercisable through the
axis separation: any policy ruleset that selects `use_rules` (a supplied/local
body, or a fetched 200 under `google`/`assumed_rfc9309`) may be paired with
`matcher_backend = "bing"`. Activating the Bing matcher MUST NOT change the Bing
fetch/status policy, which remains `documentation_gap` (v2 spec §16).

Yandex was activated **inside** `robotstxtr.engine-aware/v1` because its adapter
only ever emits `evaluated`/`not_evaluated`, which v1's four-value status set
carries losslessly. Bing is different: the shipped library surfaces four
additional distinct non-evaluated outcomes (invalid target, unsupported profile,
input-limit, work-limit). v1's status set would collapse all of these into a
single `not_evaluated`, destroying the reason distinction. Bing therefore
**requires** the new `robotstxtr.engine-aware/v2` status set and cannot be an
incremental v1 bump.

## 4. Architecture and ownership

```text
robots_evaluate_text_v1() / robots_evaluate_url_v1()
  -> neutral source evidence
  -> explicit robots_policy_ruleset (fetch/status policy)
  -> policy action
       |-- allow_all -> no matcher invocation (matcher_status = not_needed)
       `-- use_rules
            -> explicit matcher_backend dispatcher (registry)
                 |-- google -> package-owned Google adapter -> vendored robotstxt-cpp
                 |-- yandex -> package-owned Yandex adapter -> vendored robotstxtyandex
                 `-- bing   -> package-owned Bing adapter   -> vendored robotstxtbing
```

| Layer | Owner | Responsibility |
| --- | --- | --- |
| Acquisition and safety | `robotstxtr` | Origins, redirects, timeouts, byte ceiling, SSRF and HTTPS-downgrade guards, retained evidence. |
| Status/body policy | `robotstxtr` profile | Decide whether to use rules, allow all, or return no decision. |
| Absolute URL extraction | `robotstxtr` Bing adapter | Produce the original byte-preserving slash-prefixed request target. |
| Parse and evaluate | `robotstxtbing` | Apply the frozen bounded Bing profiles under the fixed validation order and limits. |
| Access match and source rule | `robotstxtbing` | Return `EvaluationStatus` + optional `Decision` with owning `RuleMatch`. |
| R schema and errors | `robotstxtr` | Map native values to the v2 status set without changing their meaning. |

The Bing adapter MAY reuse package-owned infrastructure for native
registration, batching, and result transport. It MUST NOT share a parser, group
selector, access matcher, or URL normalizer with Google or Yandex.

## 5. Supported product-token capability (TOKENS)

The Bing backend supports only the two evidence-backed public profiles, resolved
by ASCII case-folding:

- `bingbot` (public profile Bingbot); and
- `adidxbot` (public profile AdIdxBot).

A missing (`NA`) or empty product token is invalid facade input. It MUST be
reported through the existing `robotstxtr` input-invalid path, MUST NOT cause a
fetch, and MUST NOT reach policy resolution or a matcher backend. This preserves
existing behavior and never reinterprets missing identity as the wildcard group.

Every other non-empty token — including any other Bing-associated name
(`msnbot`, `BingAdsBot`), an unrelated crawler name, or a full HTTP `User-Agent`
header — is well-formed facade input but unsupported by the bounded Bing backend.
When policy selects `use_rules`, such a token MUST reach `Policy::Evaluate` and
return the native `EvaluationStatus::unsupported_profile`, which the adapter maps
to matcher status `unsupported_profile` **without a decision**. It MUST NOT
become a genuine allow or acquire wildcard/general-Bing behavior.

`robotstxtr` MUST keep publishing capability metadata (`matcher_capability`)
that distinguishes bounded Bing semantics on the two supported profiles from
Google semantics applied to an arbitrary Google-valid token. Evaluating a
Bing-named token through the Google backend remains possible only as an explicit
request for Google parsing/matching semantics and MUST NOT be described as
predicting Bing crawler behavior.

## 6. Standalone API used by the adapter (API)

The binding MUST use the public installed headers and public namespace
(`robotstxtbing`) only. Its primary flow is equivalent to:

```cpp
const auto parsed = robotstxtbing::Policy::Parse(body_bytes);   // ParseResult
// parsed.status == parsed → parsed.policy has value; otherwise policy is nullopt
const auto result = parsed.policy->Evaluate(product_token, request_target);
// result.status, result.decision (optional<Decision>)
```

`robotstxtbing` exposes a single `Evaluate` (there is no separate "Checked"
variant). `Evaluate` already performs the fixed validation order internally
(resolve token → validate target shape → check target size → compute work budget
→ match). The adapter MUST call `Policy::Parse` then `Policy::Evaluate` and MUST
NOT duplicate any of those precondition checks adapter-side.

The binding MUST bind exactly these owning entry points:
`Policy::Parse`, `Policy::Evaluate`, `Policy::sitemaps`, `Policy::crawl_delays`,
and `contract_info()`. It MUST read matcher identity from `contract_info()`
during deterministic tests, or expose equivalent compiled constants; runtime
matcher-revision metadata MUST be derived from the approved engine identity, not
from a Git worktree or filesystem.

No persistent external-pointer API is required for v2. For one distinct source
body, one native batch call SHOULD construct one owning `Policy` and evaluate all
associated rows before returning owning R values.

## 7. Backend dispatch contract (DISPATCH)

Dispatch uses the existing registry in `R/engine-contract-v1.R`. Bing
availability changes to `available` with `callable = match_bing_v1` only in the
atomic activation release. The registry validator invariants MUST continue to
hold: availability `available` implies a registered callable; a placeholder
revision (`capability-unavailable-v1`) implies `capability_unavailable` and vice
versa; dispatch depends only on the explicit matcher backend; no unavailable or
unknown backend falls through to another; invariant failure is a package error,
never an allow decision.

Like Yandex, the Bing adapter is **batch-shaped** (parse-once per distinct
body). `evaluate_rows_v1()` MUST collect Bing rows and invoke `match_bing_v1`
once in batch form, and the per-row `match_backend_v1` guard that today rejects
row-dispatching `yandex` MUST be extended to also reject row-dispatching `bing`
as an internal invariant violation.

The explicit-dispatch refactor already landed for Yandex; no new Google-only
dispatch slice is required. Bing MUST remain `capability_unavailable` until its
activation slice.

## 8. Native input and lifetime contract

The Bing binding MUST accept the retained body as a length-bearing raw value. It
MUST NOT depend on NUL termination, locale conversion, or implicit UTF-8
translation. Embedded NUL and invalid UTF-8 bytes MUST reach
`Policy::Parse(std::string_view)` unchanged.

For each distinct body, the binding MUST:

1. call `Policy::Parse` once and inspect `ParseStatus`;
2. when `ParseStatus != parsed` (a parse limit), there is **no** `Policy` to
   evaluate — every associated row resolves to `matcher_input_limit_exceeded`
   with the corresponding stable reason and no decision;
3. when parsed, evaluate all applicable rows through `Policy::Evaluate`; and
4. return owning R values with no retained C++ or R views.

Parse diagnostics are retained only for the duration of the call and never
become part of access semantics. Parsing once per URL is prohibited unless a
measured platform limitation is documented and separately approved.

## 9. Absolute URL to request-target contract (TARGET)

The Bing core accepts an original origin-form request target (nonempty,
`/`-prefixed, no `#` fragment), not an absolute URL. The package-owned extractor
MUST operate on the original URL element after only ordinary HTTP(S) validity
checks, mirroring the approved Yandex extractor.

Ordinary R character URLs cross the existing `cpp11` boundary as UTF-8 exactly
once; a bytes-marked R string that cannot be translated retains the existing
call-level translation error. The native extractor then operates lexically on
those UTF-8 bytes and MUST:

- remove scheme and authority without changing later bytes;
- substitute `/` when no explicit path exists;
- retain the query delimiter `?` and exact query spelling when present;
- exclude the fragment delimiter and fragment (reject fragments at the core
  boundary);
- neither percent-decode, re-encode, Unicode-normalize, case-fold, nor resolve
  dot segments — preserve percent-escape case, literal Unicode boundary bytes,
  duplicate slashes, dot segments, parameters, and query order; and
- surface `invalid_request_target` (no decision) when it cannot produce a
  nonempty slash-prefixed target.

Required examples (identical byte-transparency contract to Yandex):

| Absolute URL | Request target |
| --- | --- |
| `https://example.test` | `/` |
| `https://example.test?` | `/?` |
| `https://example.test?x=1` | `/?x=1` |
| `https://example.test/a//b?x=%2f` | `/a//b?x=%2f` |
| `https://example.test/a/../b#frag` | `/a/../b` |
| `https://example.test/café?q=✓` | the corresponding UTF-8 bytes |

`rurl` MAY validate the HTTP(S) scheme/authority and construct the fetch origin,
but neither its cleaned URL nor its parsed path/query outputs may reconstruct the
matcher target (they may canonicalize escapes, resolve dot segments, encode
Unicode, or drop an empty query delimiter). The extractor MUST NOT reuse Google's
or Yandex's URL behavior. Bing activation MUST NOT change how an existing Google
or Yandex row is validated, translated, or matched.

## 10. Common result mapping (SCHEMA)

The native adapter MUST carry the exact `EvaluationStatus` (and, for parse
limits, the exact `ParseStatus`) as an internal invariant; the public facade
publishes `matcher_status`, `reason`, and error mapping below. For every row for
which policy selects `use_rules` and the Bing adapter is invoked, the adapter
returns at least: native status, `url_decision`, `reason`, `matched_line`,
`matched_rule_type`, `matched_rule_value`, `matched_rule_value_raw`,
`matcher_input_bytes`, `matcher_body_truncated`.

### 10.1 Evaluated outcomes (`EvaluationStatus::evaluated`, decision present)

| Native `Decision` | Matcher status | Decision | Reason | Rule metadata |
| --- | --- | --- | --- | --- |
| source `default_allow` | `evaluated` | `allow` | `default_allow` | No line; type `none`; no value. |
| source `rule`, access `allow` | `evaluated` | `allow` | `rule_allow` | Original line, type from `RuleMatch.type` (`allow`), exact value. |
| source `rule`, access `disallow` | `evaluated` | `disallow` | `rule_disallow` | Original line, type `disallow`, exact value. |
| source `rule`, access `allow`, empty Disallow value | `evaluated` | `allow` | `effective_empty_disallow` | Original line, type `disallow`, exact empty value. |

The effective-empty case (an empty Disallow whose effective outcome is allow) is
represented natively by `source = rule` + `access = allow` + `RuleType =
disallow` + empty value; the adapter MUST NOT rewrite it to `rule_allow` or
`default_allow`. (Whether an accepted Bing profile assigns any effective-empty
access meaning is governed by the shipped profile; where the library treats such
inputs as inert, the adapter reflects the shipped decision and does not
fabricate one — see §12/REPORT deferrals.)

### 10.2 Non-evaluated outcomes (decision absent)

| Native status | Matcher status | Decision | Reason | Error stage | Error class |
| --- | --- | --- | --- | --- | --- |
| `EvaluationStatus::unsupported_profile` | `unsupported_profile` | absent | `unsupported_profile` | `input` | `robots_unsupported_profile` |
| `EvaluationStatus::invalid_request_target` | `invalid_request_target` | absent | `invalid_request_target` | `input` | `robots_invalid_request_target` |
| `EvaluationStatus::request_target_limit_exceeded` | `matcher_input_limit_exceeded` | absent | `request_target_limit_exceeded` | `input` | `robots_matcher_input_limit_exceeded` |
| `ParseStatus::body_limit_exceeded` | `matcher_input_limit_exceeded` | absent | `body_limit_exceeded` | `input` | `robots_matcher_input_limit_exceeded` |
| `ParseStatus::line_length_limit_exceeded` | `matcher_input_limit_exceeded` | absent | `line_length_limit_exceeded` | `input` | `robots_matcher_input_limit_exceeded` |
| `ParseStatus::record_limit_exceeded` | `matcher_input_limit_exceeded` | absent | `record_limit_exceeded` | `input` | `robots_matcher_input_limit_exceeded` |
| `ParseStatus::rule_limit_exceeded` | `matcher_input_limit_exceeded` | absent | `rule_limit_exceeded` | `input` | `robots_matcher_input_limit_exceeded` |
| `EvaluationStatus::work_limit_exceeded` | `matcher_work_limit_exceeded` | absent | `work_limit_exceeded` | `input` | `robots_matcher_work_limit_exceeded` |

For every non-evaluated outcome: `url_decision` is `NA`; `matched_line` is
`NA_integer_`; `matched_rule_type` is `unknown`; `matched_rule_value` is
`NA_character_`; `matched_rule_value_raw` is `NULL`; `matcher_input_bytes` is the
complete body length supplied under `use_rules`; `matcher_body_truncated` is
`FALSE`; `error_message` is human-readable and non-normative while stage/class
are stable schema values.

**Safety invariant (from the shipped core, TASK 4 of the V3 audit).** Only
`EvaluationStatus::evaluated` carries a `Decision`; every other status returns
`decision = nullopt`, and a parse limit yields no `Policy` at all. `default_allow`
occurs only inside a genuine evaluated decision. No unsupported, invalid,
over-limit, or work-limit outcome is representable as `allow` or `disallow`. The
adapter MUST NOT convert any absent core decision to allow or disallow.

The four `ParseStatus` limits plus `request_target_limit_exceeded` fold into
`matcher_input_limit_exceeded` (distinguished by `reason`); `work_limit_exceeded`
is its own status `matcher_work_limit_exceeded`. This is exactly the SCHEMA
mapping the owner approved.

## 11. Exact-byte result representation (BYTES)

The v2 schema reuses the `matched_rule_value_raw` list column already introduced
for Yandex (schema `2026-07-18.2`): exactly one list element per result row.
`RuleMatch.value` is a `std::string`, so:

- an evaluated matched rule carries the exact owning C++ string bytes in
  `matched_rule_value_raw`;
- `matched_rule_value` carries the byte-equivalent UTF-8 scalar only when the
  bytes are valid UTF-8 and NUL-free, else `NA_character_`;
- an effective empty Disallow carries a present `raw(0)` element and an empty
  UTF-8 text value;
- an absent rule (`default_allow` and every non-evaluated outcome) carries a
  `NULL` element and `NA_character_` text.

`raw(0)` and `NULL` are semantically distinct and MUST remain distinct through
construction, subsetting, concatenation, serialization, and package tests. The
adapter MUST NOT truncate at NUL, replace invalid bytes, normalize Unicode, or
transcode the value.

## 12. Policy and size-limit interaction (LIMITS)

The Bing **matcher** enforces exactly the six shipped ceilings (§7 of the v2
spec), which the adapter MUST NOT alter or supplement:

```text
maximum body bytes:              2,097,152
maximum physical line bytes:        65,536
maximum classified records:         65,536
maximum retained access rules:      16,384
maximum request-target bytes:        65,536
maximum matcher work units:      67,108,864
```

These bound the core only. The host acquisition byte ceiling (`max_bytes`,
default `524288`) is separate acquisition policy and is reported through neutral
evidence, never as a Bing matcher result. A body that passes host policy and
reaches the core over the 2,097,152-byte limit returns
`ParseStatus::body_limit_exceeded` → `matcher_input_limit_exceeded`; there is no
prefix truncation or fail-open. The Bing fetch/status policy remains
`documentation_gap` and is unchanged by matcher activation. The Google
524,288-byte retained-prefix behavior and the Yandex 500,000-byte policy bypass
remain confined to their own paths.

## 13. Vendored source and build contract (BUILD)

Mirror the approved Yandex vendoring pattern:

```text
src/vendor/robotstxtbing/include/robotstxtbing/*.h   (7 public headers)
src/vendor/robotstxtbing/src/*.{cpp,h}               (production translation units + private headers)
src/bing_binding.cpp                                 (package-owned cpp11 binding)
inst/vendor/robotstxtbing/MANIFEST.dcf               (per-file SHA-256 pins + MatcherRevision)
```

The build MUST:

- copy the sibling production source byte-identically into
  `src/vendor/robotstxtbing/` (public headers, production `.cpp`, required
  private `.h`, and `LICENSE`/`NOTICE` in the approved legal layout);
- add `inst/vendor/robotstxtbing/MANIFEST.dcf` with a per-file SHA-256 pin for
  every vendored file and the composed `MatcherRevision` string (§14/IDENTITY);
- extend `src/Makevars` and `src/Makevars.win` OBJECTS/VPATH/`-I` to compile the
  nested vendor objects deterministically as C++17;
- add `src/bing_binding.cpp` binding parse/evaluate/metadata/contract_info
  through the existing `cpp11` mechanism, keeping package-owned binding/build
  files outside the vendored hash set;
- single-source the frozen identity in R (a `bing_matcher_identity_v1()` analog
  of `yandex_matcher_identity_v1()`); and
- require no source-tree CMake package, sibling repository, or download — the
  sibling MUST never be fetched at build, test, install, or runtime.

Includes MUST NOT be edited merely to flatten the layout. The seven public
headers are `diagnostic.h`, `export.h`, `limits.h`, `metadata.h`, `policy.h`,
`result.h`, `version.h` (`export.h` is the mandated export-macro carrier).

## 14. Provenance and legal contract (IDENTITY + provenance)

`robotstxtr` MUST add a plainly diffable Bing provenance record containing:
immediate repository and full payload SHA (`c82855d0…`); library version; the
sibling `contract_id` literal `robotstxtbing-v2`; contract/parser revisions;
both profile revisions; release manifest SHA-256; static and shared archive
SHA-256; import date; every source-to-vendored path mapping and file SHA-256;
compiler and C++17 baseline; standalone verification result; Apache-2.0 license
and notice disposition; and deterministic offline fidelity commands. Existing
Google and Yandex provenance and vendored hashes MUST remain unchanged.

**Proposed matcher revision (IDENTITY — PROPOSED)** — composed from
`contract_info()`, mirroring the Yandex serialized form and single-sourced in R
so it byte-equals the manifest's `MatcherRevision` field:

```text
robotstxtbing/0.1.0+payload.c82855d0756c748cc4770246a19282323cdfa331;contract=robotstxtbing-v2;contract-rev=0.1.0;parser=0.1.0;bingbot=bingbot-2026-07-23.1;adidxbot=adidxbot-2026-07-23.1;manifest=5e79ee5d…0858
```

Every component MUST remain separately inspectable through contract metadata
(`robots_engine_contract_v2()$matcher_identity$bing`). Field names and ordering
MUST NOT drift silently; a later audited engine may replace the values only
through a reviewed contract/schema revision.

## 15. Engine-aware contract activation (v2 facade)

Introducing `robotstxtr.engine-aware/v2` and flipping Bing to `available` MUST
occur in one atomic release change that includes: the registered `match_bing_v1`
batch adapter; exact matcher-revision metadata; the checked-status /
raw-value mapping of §10–§11; the request-target extractor of §9; the v2
matcher-status set (`evaluated`, `not_needed`, `not_evaluated`,
`capability_unavailable`, `invalid_request_target`, `unsupported_profile`,
`matcher_input_limit_exceeded`, `matcher_work_limit_exceeded`); complete facade
conformance tests; and provenance/vendored-hash verification.

The v2 contract MUST preserve the v1 axes, the Google policy/matcher revision,
the Yandex activation and its schema-`2026-07-18.2` guarantees, the four legacy
Google-oriented APIs, and the legacy adapter's rejection of non-Google
engine-aware results. Adding Bing MUST NOT change RFC 9309 availability, the
Google or Yandex behavior, or their identities. Whether v2 is exposed as a new
`robots_engine_contract_v2()` accessor or as a revision of the existing accessor
is an implementation detail bounded by "v1 guarantees are preserved verbatim."

## 16. Conformance gates

### 16.1 Standalone release gate

The exact payload MUST pass its normal offline verification: static and shared
builds, unit tests, installed-package downstream consumer, every accepted
expectation and project-behavior vector, schema/manifest/hash validation,
deterministic and concurrent repeat evaluation, boundary/adversarial/fuzz-smoke/
sanitizer jobs, exported-header/package audits, and source/license/provenance and
repository-safety audits. Live tester access is never part of verification.

### 16.2 Vendored fidelity gate

A `dev/verify-bing-vendor.R` analog MUST prove offline that: every vendored file
matches the approved `MANIFEST.dcf`; no required file is missing and no
unapproved file is included; package-owned binding/build code is excluded from
the vendor manifest; the vendored engine matches the standalone payload on a
compact integration corpus; and Apache-2.0 legal/provenance material survives
source and binary packaging. A vendor-fidelity CI job MUST run this gate from a
clean tree without the sibling `robotstxtbing` repository.

### 16.3 Bing facade gate

The package MUST carry a compact, provenance-recorded projection of the released
accepted expectations (per the V3 audit, 57 `tester_observed` cells — 29
Bingbot / 28 AdIdxBot — or the complete accepted set from an approved later
baseline). Every case MUST run through the public v2 facade and verify:
evaluated/non-evaluated status, allow/disallow decision, reason, matched line and
rule type, exact raw rule value and textual representation, exact body bytes, and
a stable case ID.

Additional facade cases outside the accepted matcher corpus MUST verify: missing
and empty product tokens remain facade-invalid and do not fetch or invoke any
backend; every non-empty unsupported token maps to `unsupported_profile`; the
invalid-target, input-limit (all four parse limits + request-target-limit), and
work-limit mappings with their distinct reasons and error classes; the fixed
precedence (unsupported profile > invalid target > target size > work budget);
`NULL` absent vs. present `raw(0)` empty-rule values; and the full URL→target
byte matrix (empty path, empty/nonempty query, `?`-only, percent-escape case,
literal Unicode, duplicate slashes, dot segments, parameters, query order,
fragment rejection, and the bytes-marked URL call error). Standalone expectations
MUST NOT be rewritten to accommodate adapter behavior.

### 16.4 Cross-engine sentinels

A small suite MUST prove Bing requests reach the Bing backend and stay separate
from Google and Yandex (including at least one representative difference in
winner selection, empty-Disallow handling, and a limit outcome). Agreement cases
are controls, not Bing evidence.

### 16.5 Google and Yandex non-regression

All existing host tests MUST pass. Google and Yandex vendored hashes,
engine-aware fixtures, matched-rule metadata, schema-`2026-07-18.2` guarantees,
legacy results, and matcher revisions MUST remain unchanged. Google and Yandex
requests MUST NOT load or invoke the Bing adapter.

### 16.6 Package quality

The final clean package MUST pass the project's supported offline test, build,
install, native registration, sanitizer, source-package, binary-package,
provenance, and legal gates. Network-dependent CRAN incoming checks are a
separate release audit, not an offline verification requirement.

## 17. Delivery slices (PROPOSED sequence)

Tracker state and issue creation remain governed by the project's FP workflow;
these slices define the proposed implementation order.

- **BI1 — v2 facade scaffold.** Introduce the `robotstxtr.engine-aware/v2`
  status set and metadata surface while keeping Bing `capability_unavailable`;
  prove Google and Yandex results are byte-unchanged.
- **BI2 — Freeze the Bing import manifest and legal disposition.** Record the
  approved 0.1.0 payload, exact vendored set, all SHA-256 digests (full),
  path mapping, Apache-2.0 license/notice handling, and the offline verifier.
- **BI3 — Vendor and compile the standalone engine.** Import only approved
  production files; add portable nested build wiring; prove a clean source
  package compiles without a sibling checkout. Keep Bing unavailable.
- **BI4 — Native batch binding and request-target extractor.** Accept raw
  bodies, parse once per source, call `Policy::Evaluate`, implement the
  `raw(0)`/`NULL` representation, and freeze the URL-boundary matrix. Keep
  availability unchanged.
- **BI5 — Activate the v2 facade.** Add `match_bing_v1`, register batch
  dispatch, publish exact identity, enable availability, publish the
  status/reason/error mappings, and exercise supplied/fetched tracer bullets plus
  every non-evaluated path.
- **BI6 — Conformance and non-regression.** Add the accepted-expectation
  projection, fidelity runner, cross-engine sentinels, Google/Yandex
  non-regression, and package/legal audits.
- **BI7 — Release audit and handoff.** Final MUST audit, exact runtime
  identities, upgrade notes, sibling compatibility ranges, and reproduction
  instructions. Tagging/publication/adoption require separate authorization.

## 18. Definition of done

The v2 Bing backend is complete only when:

1. the exact standalone payload, both profile revisions, and all three SHA-256
   digests are approved and reproducible;
2. every vendored production file is pinned and verified offline;
3. explicit dispatch makes Google/Yandex fallback impossible;
4. the URL→request-target conversion is byte-characterized without reconstructed
   `rurl`, Google, or Yandex target semantics;
5. missing/empty tokens remain facade-invalid, while unsupported profiles,
   invalid/over-limit targets, parse limits, and work limits remain distinct
   non-decisions that can never be allow/disallow;
6. every accepted Bing expectation passes through the public v2 facade;
7. effective empty Disallow retains its distinct source and original rule;
8. arbitrary rule bytes remain exact through the `raw(0)`/`NULL` representation;
9. the six core limits are enforced by the core alone, distinct from acquisition
   policy;
10. the v2 status/reason/error/raw-value/matcher-identity contract is published;
11. Google and Yandex source, behavior, metadata, identities, and legacy APIs
    remain unchanged; and
12. clean build/test/install/fidelity/provenance/legal/sanitizer/portability
    gates pass without a sibling checkout.

Completion does not establish production Bing crawler parity, exhaustive tester
equivalence, support for other Bing crawler identities, or semantics beyond the
accepted profiles.

## 19. Named owner decisions

All fifteen named decisions are **APPROVED**: GO/SCHEMA/PIN as owner-fixed inputs,
and the remaining twelve signed off by the owner on 2026-07-24 ("approve").

| ID | Proposed v2 decision | Rationale | Disposition |
| --- | --- | --- | --- |
| `BI-V2-PIN` | Vendor immutable payload `c82855d0…` as library `0.1.0`, retaining profiles `bingbot-2026-07-23.1` + `adidxbot-2026-07-23.1`; pin the literal sibling `contract_id` `robotstxtbing-v2` (D1), Apache-2.0, std-lib-only; record all identity fields separately. | Owner-fixed exact pin; the literal is what `contract_info()` and the manifest actually return. | **APPROVED** |
| `BI-V2-API` | Bind public headers only; call `Policy::Parse` then `Policy::Evaluate` (the single checked entry with the fixed validation order); do not duplicate preconditions adapter-side. | The shipped API has no "Checked" variant; `Evaluate` already enforces the order. | APPROVED |
| `BI-V2-DISPATCH` | Extend the existing registry: `match_bing_v1` batch adapter, availability `available`, and reject row-dispatching `bing`. | Dispatch machinery already exists (Yandex); Bing is parse-once like Yandex. | APPROVED |
| `BI-V2-BUILD` | Vendor into `src/vendor/robotstxtbing/`, add `MANIFEST.dcf`, extend `Makevars`(+`.win`), add `src/bing_binding.cpp`, single-source identity in R; fully offline. | Mirrors the approved, proven Yandex vendoring pattern. | APPROVED |
| `BI-V2-TARGET` | Adapter owns absolute HTTP(S) URL→origin-form target: `/` for empty path, keep encoded query with `?`, reject fragments, no decode/normalize; UTF-8 once via cpp11; `rurl` validates but never reconstructs. | Byte-transparent core (§13 of v2 spec) requires source-preserving extraction. | APPROVED |
| `BI-V2-BYTES` | Reuse `matched_rule_value_raw`: exact bytes for a present rule, `raw(0)` for empty value, `NULL` for absence; text only for valid NUL-free UTF-8. | `RuleMatch.value` is `std::string`; matches the approved Yandex byte contract. | APPROVED |
| `BI-V2-IDENTITY` | Publish the composed `robotstxtbing/0.1.0+payload.…;…` matcher revision plus separately inspectable identity fields; byte-equal the manifest. | Deterministic, auditable identity single-sourced from `contract_info()`. | APPROVED |
| `BI-V2-TOKENS` | Missing/empty tokens facade-invalid; support only `bingbot`/`adidxbot` (ASCII case-fold); every other non-empty token → native `unsupported_profile` (no decision). | Bounded profile capability; core exposes a first-class `unsupported_profile`. | APPROVED |
| `BI-V2-SCHEMA` | Activate `robotstxtr.engine-aware/v2` adding `invalid_request_target`, `unsupported_profile`, `matcher_input_limit_exceeded`, `matcher_work_limit_exceeded`; fold 4 parse limits + request-target-limit into `matcher_input_limit_exceeded` (distinct reasons); `work_limit_exceeded` its own status; no non-evaluated outcome becomes allow/disallow. | Owner-fixed; v1's 4-value set cannot losslessly carry Bing's outcomes. | **APPROVED** |
| `BI-V2-METADATA` | Defer public Sitemap/Crawl-delay tables; the binding MAY read `sitemaps()`/`crawl_delays()` for tests, but v2 publishes no decision-bearing metadata field. | v2 spec §16 forbids metadata in access/scheduler fields; matches Yandex deferral. | APPROVED |
| `BI-V2-TRACE` | Defer group/profile-selection provenance; it does not block access matching. | Not required for the decision surface; mirrors Yandex. | APPROVED |
| `BI-V2-REPORT` | Defer public per-line parser diagnostics (the 16 diagnostic codes) to a later validator/source-analysis contract. | Diagnostics are not access semantics; keeps the v2 surface bounded. | APPROVED |
| `BI-V2-LIMITS` | Enforce exactly the six shipped core ceilings; add no adapter-side limit; acquisition ceiling stays separate acquisition policy. | Limits are fixed core `project_behavior`; adapter must not alter them. | APPROVED |
| `BI-V2-PORTABILITY` | Claim only toolchain lanes actually run by the combined R package gate (incl. the Windows `Makevars.win` lane). | Honest portability scope; matches Yandex. | APPROVED |
| `BI-V2-RELEASE` | Integration completion does not itself authorize tagging, publication, or downstream adoption. | Each requires separate owner authorization. | APPROVED |
| `BI-V2-GO` | Adopt `robotstxtbing` 0.1.0 as an explicit Bing matcher backend. | Owner-fixed GO decision. | **APPROVED** |

## 20. Deferrals and known follow-ups

- **D2 — stale spec sync (non-blocking).** `robotstxtr`'s copy of
  `design/robotstxtbing-v2-spec.md` is the `2026-07-17.2` draft (evidence cutoff
  `2026-07-17`); the library shipped at `spec_revision 2026-07-23.1` / cutoff
  `2026-07-23`. No behavioral conflict — the manifest is the release authority
  and every result-shape/limit/enum/nonclaim cell still matches — but the design
  doc trails the release by one revision. **Follow-up:** refresh the robotstxtr
  copy of the v2 spec to the shipped `2026-07-23.1` revision and cite the
  2026-07-23 manifest values. This DRAFT deliberately does not resolve the spec
  content.
- **Full SHA-256 digests.** Only prefixes are recorded here (`5e79ee5d…0858`
  manifest, `d1552e1f…` static, `91aa203f…` shared). The complete digests MUST
  be transcribed verbatim from the shipped release manifest at import (slice BI2)
  and verified before compilation.
- **Payload vs. audited commit.** Reconcile and record the relationship between
  the owner-approved payload pin `c82855d0…` and the V3-audit RC-freeze commit
  `8fc55919…` in the provenance record at import (see §2 note).
- **Deferred surfaces (out of v2):** additional Bing crawler profiles;
  production-crawler equivalence claims; public Sitemap/Crawl-delay exposure and
  any scheduler/Crawl-delay enforcement; public per-line diagnostics/analyzer;
  group/profile-selection trace; persistent public native policy pointers;
  parallel R evaluation or process-global matcher caches; a shared
  Google/Yandex/Bing parser or matcher kernel; and changing the Bing
  fetch/status policy away from `documentation_gap`.
- **Upstream evidence gates.** The v2 spec §17 selection/matching/winner/
  empty-access/parser-recovery/metadata evidence gates are the sibling's
  release preconditions and are assumed satisfied by the shipped 0.1.0 release;
  they are not re-adjudicated here.

## 21. Implementation boundary

**All named decisions (GO, SCHEMA, PIN, and the twelve remaining) are owner-approved
as of 2026-07-24; implementation is authorized upon merge of this spec.** The build
proceeds through slices BI1–BI7 (§17). Until the activation slice (BI5) lands, the
`bing` matcher backend MUST remain `capability_unavailable`. Approval of this
contract does not authorize changing the approved identity or semantics, activating
Bing before every activation gate passes, tagging, publication, or downstream
adoption — each requires separate authorization.
