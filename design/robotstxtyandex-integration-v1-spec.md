# `robotstxtyandex` backend integration contract v1

- Status: **approved on 2026-07-18; implementation-authorizing**
- Contract ID: `robotstxtr.yandex-backend/v1`
- Contract revision: `2026-07-18.2`
- Owner decision: exact immutable pin and all fifteen section 19 decisions approved as written
- Host package: `robotstxtr` 0.2 series or a reviewed successor
- Host facade: `robotstxtr.engine-aware/v1`
- Activation schema revision: `2026-07-18.2`
- Standalone engine: `robotstxtyandex` 0.2.0
- Behavioral profile: `yandex-0.1.0`
- Evidence cutoff: 2026-07-17

This approved contract authorizes `robotstxtr` to implement and vendor the
independent `robotstxtyandex` C++ library as an explicit Yandex matcher backend
within the boundaries and gates below. It does not authorize tagging,
publication, or downstream adoption; each requires separate owner
authorization.

Revision `2026-07-18.2` incorporates the owner-approved resolutions for empty
product tokens, exact raw result values, native-status/error mapping, immutable
identity, and the R-character-to-request-target boundary. It retains the
reviewed division in which `robotstxtyandex` consumes an original
slash-prefixed request target and the package-owned `robotstxtr` adapter
extracts that target from an absolute HTTP(S) URL.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**
describe this approved project contract. They do not state Yandex requirements
unless the selected standalone compatibility profile cites supporting public
documentation or dated black-box observations.

## 1. Intended outcome

After implementation, a call such as:

```r
robots_evaluate_text_v1(
  robots_txt,
  url,
  robots_product_token = "Yandex",
  robots_policy_ruleset = "yandex",
  matcher_backend = "yandex"
)
```

will apply the existing `robotstxtr` Yandex status/body policy and, when that
policy selects rule evaluation, evaluate the original request target through a
pinned vendored `robotstxtyandex` backend.

The integration MUST:

- retain independent policy-ruleset, matcher-backend, robots-product-token,
  and HTTP User-Agent axes;
- identify the exact standalone payload and compatibility profile;
- return Yandex decisions and owning winning-rule metadata without
  reinterpretation;
- preserve non-decisions for unsupported tokens and invalid request targets;
- preserve existing Google behavior and source provenance; and
- build, install, test, and run without a sibling checkout or network access.

The integration MUST NOT:

- route a Yandex matcher request to the Google matcher;
- infer the matcher backend from the policy ruleset or product token;
- claim production Yandex crawler equivalence;
- widen the supported Yandex crawler profiles beyond the standalone contract;
- copy Google parsing, group selection, URL normalization, or matcher behavior;
- expose standalone private headers or private ABI as an R package API; or
- add a submodule, `FetchContent`, runtime loader, or sibling-path dependency.

## 2. Approved immutable baseline

The approved immutable standalone payload is:

| Field | Value |
| --- | --- |
| Library version | `0.2.0` |
| Payload Git revision | `fdd60a7c3bc6825f3b3752562dc0d6ad9387a27e` |
| Unix source-archive SHA-256 | `366dd57e2319f572624bdddffc6ccc1e51f6358d1a011453aebb4541de24bd90` |
| Compatibility profile ID | `yandex-0.1.0` |
| Accepted corpus revision | `337b9f3b886a92d6dc08c2fce84228d0cd6b801a` |
| Evidence snapshot | `9d69d361db81e7d236562dc056b41865da33d467d06f316e2c9a20988e007c96` |
| Profile source revision | `337b9f3b886a92d6dc08c2fce84228d0cd6b801a` |
| Language baseline | C++17 |
| License | MIT, with installed `LICENSE` and `NOTICE` |

The later administrative commit `c886b7f` is not the source payload identity.
The integration MUST reproduce and hash the payload tree at `fdd60a7...`.

The library version and behavioral profile intentionally differ. Version
0.2.0 adds checked evaluation, immutable identity, verification, and packaging
surfaces while retaining the frozen `yandex-0.1.0` compatibility behavior.

On 2026-07-18, the owner approved this exact pin as written. Replacing any
identity above requires a later reviewed contract revision. A moving branch,
tag without a recorded target, or sibling worktree is not a valid pin.

## 3. Existing host state and prerequisite correction

`design/engine-contract-v1.md` defines the independent axes and the
engine-aware result schema. The current implementation reports the Yandex
matcher as `capability_unavailable`, which remains correct until all activation
gates pass.

The current row evaluator calls `match_google_v1()` after checking generic
availability. Merely changing Yandex availability would therefore relabel
Google behavior as Yandex behavior. Explicit backend dispatch MUST land and be
regression-tested before any Yandex source is added or activated.

This revision supersedes the prior durable document's stale 0.1.0 candidate
and standalone-prerequisite assumptions. The owner approved this replacement
and its exact 0.2.0 baseline on 2026-07-18.

## 4. Architecture and ownership

```text
robots_evaluate_text_v1() / robots_evaluate_url_v1()
  -> neutral source evidence
  -> explicit robots_policy_ruleset
  -> policy action
       |-- allow_all -> no matcher invocation
       `-- use_rules
            -> explicit matcher_backend dispatcher
                 |-- google -> package-owned Google adapter
                 |              -> vendored robotstxt-cpp
                 `-- yandex -> package-owned Yandex adapter
                                -> vendored robotstxtyandex
```

| Layer | Owner | Responsibility |
| --- | --- | --- |
| Acquisition and safety | `robotstxtr` | Origins, redirects, timeouts, byte ceiling, SSRF and HTTPS-downgrade guards, retained evidence. |
| Status/body policy | `robotstxtr` profile | Decide whether to use rules, allow all, or return no decision. |
| Absolute URL extraction | `robotstxtr` Yandex adapter | Produce the original byte-preserving slash-prefixed request target. |
| Parser and crawler selection | `robotstxtyandex` | Apply the frozen bounded Yandex profile. |
| Access match and source rule | `robotstxtyandex` | Return checked status and owning match values. |
| R schema and errors | `robotstxtr` | Map native values without changing their meaning. |

The adapter MAY reuse package-owned infrastructure for native registration,
batching, and common result transport. It MUST NOT share a parser, group
selector, access matcher, or URL normalizer with Google.

## 5. Supported product-token capability

The Yandex backend supports only the standalone library's evidence-backed
profiles:

- `Yandex`, case-insensitively; and
- `YandexAdditionalBot`, case-insensitively.

A missing (`NA`) or empty product token is invalid facade input. It MUST be
reported through the existing `robotstxtr` input-invalid path, MUST NOT cause a
fetch, and MUST NOT reach policy resolution or a matcher backend. This
preserves existing Google behavior and does not reinterpret missing identity
as the wildcard group.

Every other non-empty token, including a complete HTTP `User-Agent` header and
names of unrelated crawlers, is well-formed facade input but unsupported by the
bounded Yandex backend. When policy selects Yandex rule evaluation, it MUST
reach `EvaluateChecked()` and return `unsupported_crawler` without a decision.
It MUST NOT become a genuine `default_allow` or acquire wildcard/general-Yandex
behavior.

`robotstxtr` MUST publish capability metadata that distinguishes:

- Google semantics applied to an arbitrary Google-valid product token; from
- bounded Yandex semantics applied only to supported Yandex profiles.

Evaluating `Yandex` through the Google backend remains possible only as an
explicit request for Google parsing/matching semantics. It MUST NOT be
described as predicting Yandex crawler behavior.

The empty/missing facade check is common input validation. The supported-token
check is backend-specific capability. Implementing the latter MUST NOT narrow
the non-empty product tokens accepted by the existing Google path.

## 6. Standalone API used by the adapter

The binding MUST use the public installed headers and public namespace only.
Its primary flow is equivalent to:

```cpp
const auto parsed = robotstxtyandex::Policy::Parse(body_bytes);
const auto checked = parsed.policy.EvaluateChecked(
    product_token,
    request_target
);
```

The integration MUST use `EvaluateChecked()`, not adapter-side duplication of
the crawler/target preconditions and not legacy `Evaluate()`.

The binding MAY read `compatibility_profile_identity()` during deterministic
package tests or expose equivalent compiled constants. Runtime matcher
revision metadata MUST be derived from the approved engine identity, not from
the current Git worktree or filesystem.

No persistent external-pointer API is required for v1. For one distinct source
body, one native batch call SHOULD construct one owning `Policy` and evaluate
all associated rows before returning owning R values.

## 7. Backend dispatch contract

The R layer MUST introduce a package-private dispatcher with semantics
equivalent to:

```r
match_backend_v1 <- function(backend, body, url, product_token) {
  switch(
    backend,
    google = match_google_v1(body, url, product_token),
    yandex = match_yandex_v1(body, url, product_token),
    robots_abort("Matcher backend is unavailable or unregistered.", ...)
  )
}
```

The implementation MAY use a registry instead of `switch`, provided that:

- availability `available` implies a registered callable adapter;
- dispatch depends only on the explicit matcher backend;
- no unavailable or unknown backend falls through to another backend;
- backend metadata and registration cannot drift silently; and
- invariant failure is a package error, never an allow decision.

The dispatch refactor MUST first land as a Google-only behavior-preserving
slice. Yandex MUST remain `capability_unavailable` in that slice.

## 8. Native input and lifetime contract

The Yandex binding MUST accept the retained body as a length-bearing raw value.
It MUST NOT depend on NUL termination, locale conversion, or implicit UTF-8
translation. Embedded NUL and invalid UTF-8 bytes MUST reach
`Policy::Parse(std::string_view)` unchanged.

For each distinct body, the binding MUST:

1. create one owning `Policy`;
2. retain parse diagnostics for the duration of the call without making them
   part of access semantics;
3. evaluate all applicable rows through `EvaluateChecked()`; and
4. return owning R values with no retained C++ or R views.

Parsing once per URL is prohibited unless a measured platform limitation is
documented and separately approved.

## 9. Absolute URL to request-target contract

The Yandex core accepts an original slash-prefixed HTTP request target, not an
absolute URL. The package-owned extractor MUST operate on the original URL
element after only ordinary HTTP(S) validity checks.

The facade accepts R character URLs, not URL raw vectors. For each
non-missing, non-empty row selecting the Yandex backend:

1. a bytes-marked R string or a string that cannot be translated by the
   existing R/`cpp11` character boundary is outside the supported URL-input
   contract and retains the existing call-level translation error;
2. ordinary R character input is translated exactly once to UTF-8 by the
   existing `cpp11` boundary; and
3. the native extractor operates lexically on those UTF-8 bytes.

The extractor MUST NOT percent-encode literal Unicode after that translation.
Thus “original bytes” in this contract means the UTF-8 native-boundary bytes of
the original ordinary R character value, not an unsupported bytes-marked
`CHARSXP` representation.

Yandex activation MUST NOT change how an existing Google row is validated,
translated, or matched. A later common URL-input tightening would require its
own Google compatibility review.

It MUST:

- remove scheme and authority without changing later bytes;
- substitute `/` when no explicit path exists;
- retain the query delimiter and exact query spelling;
- exclude the fragment delimiter and fragment;
- preserve percent-escape case, literal Unicode boundary bytes, duplicate
  slashes, dot segments, parameters, and query order; and
- return `invalid_request_target` without a crawl decision on failure.

Required examples include:

| Absolute URL | Request target |
| --- | --- |
| `https://example.test` | `/` |
| `https://example.test?` | `/?` |
| `https://example.test?x=1` | `/?x=1` |
| `https://example.test/a//b?x=%2f` | `/a//b?x=%2f` |
| `https://example.test/a/../b#frag` | `/a/../b` |
| `https://example.test/café?q=✓` | `/café?q=✓` as the corresponding UTF-8 bytes |

`rurl` MAY continue to validate the HTTP(S) scheme/authority and construct the
fetch origin. Neither `rurl`'s cleaned URL nor its parsed path/query outputs may
be used to reconstruct the matcher target, because those surfaces may
canonicalize percent escapes, resolve dot segments, encode Unicode, or lose an
empty query delimiter. The extractor MUST NOT use
`googlebot::GetPathParamsQuery()` or another engine's URL behavior. A future
source-preserving URL-library API MAY replace the package-owned lexical
extractor only after cross-platform tests prove this entire contract.

A URL rejected by ordinary facade validation remains the existing
facade-level invalid-URL outcome and does not reach the adapter. If a URL passes
that validation but the native lexical extractor cannot produce a non-empty
slash-prefixed target, the checked matcher outcome is
`invalid_request_target` without a crawl decision.

## 10. Common result mapping

The native adapter MUST return an internal `native_evaluation_status` with the
exact `EvaluationStatus` value from `EvaluateChecked()`. This is an adapter
invariant and is not a new public result column. The public facade continues to
use `matcher_status`; native status detail is represented by the normative
`matcher_status`, `reason`, and error mapping below.

For every row for which policy selects `use_rules` and the Yandex adapter is
invoked, the adapter MUST return at least:

```text
native_evaluation_status
url_decision
reason
matched_line
matched_rule_type
matched_rule_value
matched_rule_value_raw
matcher_input_bytes
matcher_body_truncated
```

The Yandex mapping is normative:

| Native source | Matcher status | Decision | Reason | Rule metadata |
| --- | --- | --- | --- | --- |
| `default_allow` | `evaluated` | `allow` | `default_allow` | No line; type `none`; no value. |
| `rule_allow` | `evaluated` | `allow` | `rule_allow` | Original line, type `allow`, exact value. |
| `rule_disallow` | `evaluated` | `disallow` | `rule_disallow` | Original line, type `disallow`, exact value. |
| `effective_empty_disallow` | `evaluated` | `allow` | `effective_empty_disallow` | Original line, type `disallow`, exact empty value. |

The effective-empty case MUST NOT be rewritten to `rule_allow` or
`default_allow`.

For every evaluated result, `error_stage`, `error_class`, and `error_message`
are absent unless an independent acquisition error is already present.

Checked non-evaluated mappings are:

| Native status | Matcher status | Decision | Reason | Error stage | Error class |
| --- | --- | --- | --- | --- | --- |
| `unsupported_crawler` | `not_evaluated` | absent | `unsupported_product_token` | `input` | `robots_unsupported_product_token` |
| `invalid_request_target` | `not_evaluated` | absent | `invalid_request_target` | `input` | `robots_invalid_request_target` |

For both checked non-evaluated results:

- `matched_line` is `NA_integer_`;
- `matched_rule_type` is `unknown`;
- `matched_rule_value` is `NA_character_`;
- `matched_rule_value_raw` is `NULL`;
- `matcher_input_bytes` is the complete body length supplied under `use_rules`;
- `matcher_body_truncated` is `FALSE`; and
- `error_message` is human-readable and non-normative, while the stage and
  class above are stable schema values.

These are matcher-input failures, not acquisition failures. If both checked
inputs are invalid, `unsupported_crawler` takes precedence exactly as in the
standalone API. Facade-invalid URL or empty/missing-token outcomes occur before
adapter invocation and retain their existing facade mappings instead.

## 11. Exact-byte result representation

The activation schema revision `2026-07-18.2` MUST add a
`matched_rule_value_raw` list column with exactly one list element per result
row. `matched_rule_value` remains a convenient character field only when the
same bytes are valid UTF-8 and contain no embedded NUL.

For an evaluated matched rule:

- `matched_rule_value_raw` contains the exact owning C++ string bytes;
- `matched_rule_value` contains the byte-equivalent UTF-8 R character scalar
  without normalization when the bytes are valid UTF-8 and NUL-free;
- otherwise `matched_rule_value` is `NA_character_`;
- an effective empty Disallow has a present `raw(0)` list element and an empty
  UTF-8 text value; and
- an absent rule has a `NULL` list element and `NA_character_` text.

`raw(0)` and `NULL` are semantically distinct and MUST remain distinct through
construction, subsetting, concatenation, serialization, and package tests.
Evaluated `default_allow` and every non-evaluated outcome use the absent-rule
representation.

The adapter MUST NOT truncate at NUL, replace invalid bytes, normalize Unicode,
or silently transcode the value. The facade contract and generated
documentation MUST identify schema revision `2026-07-18.2` and this exact
representation.

## 12. Policy and size-limit interaction

The existing Yandex status/body policy documented in
`design/engine-profiles.md` remains host-owned and runs before matcher
dispatch.

For usable supplied or fetched evidence:

- bodies of at most 500,000 bytes may reach the Yandex matcher;
- bodies over 500,000 bytes resolve through the documented Yandex `allow_all`
  policy and MUST NOT be truncated and parsed;
- policy `allow_all` produces matcher status `not_needed`; and
- matcher input/truncation fields remain absent when no matcher ran.

The Google 524,288-byte retained-prefix behavior remains unchanged and applies
only to the Google path.

The adapter MUST NOT introduce new rule-count, line-length, parameter-count,
or parser-limit semantics absent from the approved standalone profile.

## 13. Vendored source and build contract

The approved vendored set MUST contain only the production files required to
compile the pinned payload:

- five public headers under `include/robotstxtyandex/`;
- eight production `.cc` translation units under `src/`;
- six private `src/*.h` headers used by those translation units; and
- required `LICENSE` and `NOTICE` material in the package's approved legal
  layout.

The proposed source layout is:

```text
src/vendor/robotstxtyandex/include/robotstxtyandex/*.h
src/vendor/robotstxtyandex/src/*.{cc,h}
src/yandex_binding.cpp
```

Vendored files MUST be byte-identical to the approved archive. Package-owned
bindings and build files MUST be outside the vendored hash set. Includes MUST
not be edited merely to flatten the source layout.

The build MUST:

- compile as C++17 on the package's supported R toolchains;
- list or derive the nested vendor objects deterministically;
- register package-owned native entry points through the existing `cpp11`
  mechanism;
- avoid exported private engine symbols as an R API promise; and
- require no source-tree CMake package, sibling repository, or download.

## 14. Provenance and legal contract

`robotstxtr` MUST add a plainly diffable Yandex provenance record containing:

- immediate repository and full payload SHA;
- library version and all compatibility-profile identity fields;
- archive SHA-256;
- import date;
- every approved source-to-vendored path mapping and file SHA-256;
- compiler and language baseline;
- standalone verification result;
- license and notice disposition; and
- deterministic offline fidelity commands.

The existing Google provenance and vendored hashes MUST remain unchanged.
Source and binary package audits MUST verify both engines' license and notice
material independently.

## 15. Engine-aware contract activation

Yandex availability may change to `available` only in the same atomic release
change that includes:

- the registered Yandex adapter;
- exact matcher revision metadata;
- checked-status and raw-value mapping;
- the request-target extractor;
- complete facade conformance tests;
- provenance and vendored hash verification; and
- engine schema revision `2026-07-18.2` documenting all added fields, status,
  reason, and error-class values.

The matcher revision MUST be a deterministic structured identity based on the
library version, payload SHA, profile ID, accepted corpus revision, evidence
snapshot, and profile source revision. Its serialized form is:

```text
robotstxtyandex/0.2.0+payload.fdd60a7c3bc6825f3b3752562dc0d6ad9387a27e;profile=yandex-0.1.0;corpus=337b9f3b886a92d6dc08c2fce84228d0cd6b801a;evidence=9d69d361db81e7d236562dc056b41865da33d467d06f316e2c9a20988e007c96;profile-source=337b9f3b886a92d6dc08c2fce84228d0cd6b801a
```

Every component MUST also remain separately inspectable through contract
metadata. A later audited engine may replace the values only through a reviewed
contract/schema revision; field names and ordering MUST NOT drift silently.

Adding Yandex does not change RFC 9309 or Bing availability, the Google policy
or matcher revision, or the four legacy Google-oriented APIs. The legacy
adapter MUST continue to reject non-Google engine-aware results.

## 16. Conformance gates

### 16.1 Standalone release gate

The exact payload MUST pass its normal offline verification, including the
accepted corpus, C++ tests, differential harness, fuzz smoke, package install,
external consumer, repository safety, release reproduction, and recorded
portability gates.

### 16.2 Vendored fidelity gate

The host MUST prove offline that:

- every vendored file matches the approved manifest;
- no required file is missing and no unapproved file is included;
- package-owned code is excluded from the vendor manifest;
- the vendored engine matches the standalone payload on the compact
  integration corpus; and
- legal/provenance material survives source and binary packaging.

This gate MUST pass from a clean package source tree without the sibling
`robotstxtyandex` repository.

### 16.3 Yandex facade gate

The R package MUST carry a compact provenance-recorded projection of all 140
accepted expectations from the selected profile, or the complete accepted set
from an approved later baseline. Every case MUST run through the public
engine-aware facade and verify:

- evaluated or non-evaluated status;
- allow/disallow decision;
- reason;
- matched line and rule type;
- exact raw rule value and textual representation; and
- exact body bytes and stable case ID.

Additional facade cases outside the accepted matcher corpus MUST verify:

- missing and empty product tokens remain facade-invalid and do not fetch or
  invoke either backend;
- every non-empty unsupported Yandex token maps to the checked
  `unsupported_crawler` contract;
- checked invalid-target and unsupported-crawler error stage/class values;
- unsupported-first precedence when both checked inputs are invalid;
- `NULL` absent raw values versus present `raw(0)` empty-rule values; and
- UTF-8 URL translation, the existing bytes-marked URL call error, empty query
  preservation, percent-escape case, literal Unicode, duplicate slashes, dot
  segments, parameters, query order, and fragment removal.

Standalone expectations MUST not be rewritten to accommodate adapter behavior.

### 16.4 Cross-engine sentinels

A small suite MUST prove that Yandex requests reach the Yandex backend and
retain known separation from Google, including effective empty Disallow,
wildcard-specificity, and representative malformed-line differences.
Agreement cases are controls, not Yandex evidence.

### 16.5 Google non-regression

All existing host tests MUST pass. Google vendored hashes, engine-aware
fixtures, callback-correlated match metadata, empty-directive behavior, legacy
results, and matcher revision MUST remain unchanged. Google requests MUST not
load or invoke the Yandex adapter.

### 16.6 Package quality

The final clean package MUST pass the project's supported offline test, build,
install, native registration, sanitizer, source-package, binary-package,
provenance, and legal gates. Network-dependent CRAN incoming checks are a
separate release audit and MUST NOT be described as an offline verification
requirement.

## 17. Delivery slices

These approved slices define the implementation sequence. Tracker state and
issue creation remain governed separately by the project's FP workflow.

### YI1 — Preserve Google while introducing explicit dispatch

Repository: `robotstxtr`.

Add the backend dispatcher and registration/availability invariant. Keep
Yandex unavailable. Prove every existing Google result is unchanged.

### YI2 — Freeze the Yandex import manifest and legal disposition

Repository: `robotstxtr`.

Record the approved 0.2.0 payload, exact vendored set, hashes, path mapping,
license/notice handling, and offline verifier before importing behavior.

### YI3 — Vendor and compile the standalone engine

Repository: `robotstxtr`.

Import only approved production files, add portable nested build wiring, and
prove a clean source package compiles without a sibling checkout. Keep Yandex
unavailable.

### YI4 — Implement the native batch binding and request-target extractor

Repository: `robotstxtr`.

Accept raw bodies, parse once per source, call `EvaluateChecked()`, return
owning result values, implement the exact `raw(0)`/`NULL` raw-value
representation, and freeze the UTF-8/native lexical URL-boundary matrix. Use
`rurl` only for ordinary URL/origin validation, not target reconstruction. Keep
public availability unchanged.

### YI5 — Activate the engine-aware facade

Repository: `robotstxtr`.

Add `match_yandex_v1()`, register dispatch, publish exact identity, update the
facade to schema revision `2026-07-18.2`, publish the status/reason/error-class
mappings, enable availability, and exercise supplied/fetched tracer bullets
plus facade-invalid, checked non-decision, and oversized-body paths.

### YI6 — Complete conformance and non-regression

Repository: `robotstxtr`.

Add the full accepted-expectation projection, fidelity runner, cross-engine
sentinels, Google non-regression gates, and package/legal audits.

### YI7 — Release audit and handoff

Repository: `robotstxtr`.

Produce the final MUST audit, exact runtime identities, upgrade notes, sibling
compatibility ranges, and artifact reproduction instructions. Tagging,
publication, and downstream adoption require separate authorization.

## 18. Definition of done

The v1 backend is complete only when:

1. the exact standalone payload and all five profile identity fields are
   approved and reproducible;
2. every vendored production file is pinned and verified;
3. explicit dispatch makes Google fallback impossible;
4. the UTF-8 request-target conversion contract is byte-characterized without
   reconstructed `rurl` or Google target semantics;
5. missing/empty product tokens remain facade-invalid, while non-empty
   unsupported Yandex crawlers and invalid native targets remain checked
   non-decisions;
6. every accepted Yandex expectation passes through the public R facade;
7. effective empty Disallow retains its distinct source and original rule;
8. arbitrary rule bytes remain exact through the mandatory raw result
   representation, including the `raw(0)`/`NULL` distinction;
9. the Yandex 500,000-byte policy bypasses the matcher correctly;
10. schema revision `2026-07-18.2` publishes the exact status, reason,
    error-class, raw-value, and matcher-identity contract;
11. Google source, behavior, metadata, and legacy APIs remain unchanged;
12. clean build, test, install, fidelity, provenance, legal, sanitizer, and
    portability gates pass without a sibling checkout; and
13. public documentation limits claims to the frozen compatibility profile.

Completion does not establish production crawler parity, exhaustive tester
equivalence, support for other Yandex crawler identities, or semantics beyond
the accepted profile.

## 19. Approved owner decisions

On 2026-07-18, the owner approved all fifteen decisions exactly as written:

| ID | Approved v1 decision |
| --- | --- |
| `YI-V1-PIN` | Vendor immutable payload `fdd60a7...` as library 0.2.0 retaining profile `yandex-0.1.0`, and record all five engine identity fields separately. |
| `YI-V1-API` | Require native `EvaluateChecked()`; do not duplicate prevalidation in the adapter. |
| `YI-V1-DISPATCH` | Land Google-preserving explicit dispatch before vendoring or activation. |
| `YI-V1-BUILD` | Preserve nested vendored paths and compile an explicit deterministic object set. |
| `YI-V1-TARGET` | Translate ordinary R character URLs once to UTF-8, retain the existing bytes-marked URL call error, and use a package-owned native lexical extractor. `rurl` validates the URL/origin but does not reconstruct the target. |
| `YI-V1-BYTES` | Require `matched_rule_value_raw`; use `raw(0)` for a present empty value and `NULL` for absence, with text only for valid NUL-free UTF-8. |
| `YI-V1-IDENTITY` | Publish the exact serialized matcher revision plus separately inspectable payload SHA and all five engine-supplied profile identity fields. |
| `YI-V1-TOKENS` | Treat missing/empty tokens as facade-invalid. Support only non-empty `Yandex` and `YandexAdditionalBot`, case-insensitively; every other non-empty Yandex-backend token is checked `unsupported_crawler`. |
| `YI-V1-SCHEMA` | Activate as schema revision `2026-07-18.2`; keep native evaluation status internal and publish its exact matcher-status/reason/error mapping. |
| `YI-V1-METADATA` | Defer public diagnostics, Sitemap, and Clean-param source-analysis tables. |
| `YI-V1-TRACE` | Defer crawler-selection provenance; it does not block access matching. |
| `YI-V1-REPORT` | Defer public per-line parser reporting to a validator/source-analysis contract. |
| `YI-V1-LIMITS` | Do not add parser-limit semantics beyond the selected profile. |
| `YI-V1-PORTABILITY` | Claim only toolchain lanes actually run by the combined R package gate. |
| `YI-V1-RELEASE` | Integration completion does not itself authorize tagging or publication. |

## 20. Deferred work

The following are outside v1:

- additional Yandex crawler profiles;
- production-crawler equivalence claims;
- `Clean-param` URL rewriting or deduplication;
- public diagnostics or analyzer UI;
- crawler-selection trace and per-line parser-reporting APIs;
- crawl scheduling or Crawl-delay enforcement;
- sitemap fetching or validation;
- newly promoted rule, line, parameter, or body-limit semantics;
- persistent public native policy pointers;
- parallel R evaluation or process-global matcher caches;
- Google binding refactors or optimizations unrelated to dispatch;
- a shared Google/Yandex parser or matcher kernel; and
- RFC 9309 or Bing backend activation.

## 21. Approval record and implementation boundary

On 2026-07-18, the owner approved the exact section 2 immutable pin and all
fifteen section 19 decisions as written in revision `2026-07-18.2`. This
approval authorizes the implementation slices and conformance work specified
here. It does not authorize changing the approved identity or semantics,
activating Yandex before every activation gate passes, tagging, publication,
or downstream adoption.

## 22. Revision disposition

This approved revision supersedes the stale non-authorizing 0.1.0 assumptions
previously stored in this durable document. Historical scratch review material
remains non-authoritative. This implementation-authorizing contract records
the approved resolutions:

1. missing and empty product tokens remain facade-invalid and never mean the
   wildcard group;
2. non-empty unsupported Yandex tokens use the standalone checked
   `unsupported_crawler` result;
3. `matched_rule_value_raw` is mandatory, with `raw(0)` for a present empty
   value and `NULL` for absence;
4. native evaluation status remains adapter-internal, with exact public
   matcher-status, reason, and error-class mappings;
5. all five standalone compatibility-profile identity fields, including
   `profile_source_revision`, participate in published identity;
6. ordinary R character URLs cross the existing `cpp11` boundary as UTF-8,
   while bytes-marked URL input retains its existing call error; and
7. `rurl` remains authoritative for ordinary URL/origin validation but never
   reconstructs the byte-sensitive Yandex request target.
