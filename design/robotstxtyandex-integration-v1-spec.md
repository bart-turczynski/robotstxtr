# `robotstxtyandex` backend integration contract v1

- Status: **draft for owner review; not implementation-authorizing**
- Contract ID: `robotstxtr.yandex-backend/v1`
- Draft revision: `2026-07-17.1`
- Evidence cutoff: 2026-07-17
- Host package: `robotstxtr` 0.2 series
- Host facade: `robotstxtr.engine-aware/v1`
- Candidate standalone engine: `robotstxtyandex` 0.1.0
- Standalone improvement backlog: `YDX-ysmuamje` and its children
- Google comparison engine: `robotstxt-cpp` at commit
  `1cb8b047d81dfa0e9c1a1549b269fb5f196756c9`

This document specifies how `robotstxtr` may add the independent
`robotstxtyandex` library as an available Yandex matcher backend. It collects
the reusable integration, provenance, packaging, and verification ideas proven
by the existing `robotstxt-cpp` integration while keeping Google and Yandex
behavior strictly separate.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**
describe the proposed project contract. They do not imply that Yandex has made
the same requirement unless a cited `robotstxtyandex` compatibility source or
accepted expectation supports it.

Implementation is not authorized by this draft. Owner approval must resolve
the review decisions in section 17 and change the status before work begins.

## 1. Outcome

After this contract is implemented, an explicit call such as:

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
policy says to use rules, evaluate the URL through a pinned, vendored
`robotstxtyandex` engine. Results will use the existing engine-aware result
shape and will retain the Yandex decision source and winning source rule.

The integration MUST NOT:

- route a Yandex matcher request to the Google matcher;
- modify or fork the vendored Google implementation;
- copy Google parsing, URL normalization, crawler selection, or winner
  semantics into Yandex;
- claim production Yandex crawler equivalence; or
- introduce a build-time, test-time, installation-time, or runtime network
  dependency on a sibling repository.

## 2. Current state and prerequisite correction

`robotstxtr` already separates these four concepts in
`design/engine-contract-v1.md`:

1. neutral acquisition evidence;
2. an engine-specific status-policy ruleset;
3. a matcher backend; and
4. the robots product token used for group selection.

The public value set already contains `matcher_backend = "yandex"`, but
`R/engine-contract-v1.R` currently reports it as
`capability_unavailable`. That is the correct state until this contract's
release gates pass.

The current row evaluator checks backend availability and then calls
`match_google_v1()` unconditionally. Therefore, changing only the availability
metadata would silently relabel Google behavior as Yandex behavior. Before a
Yandex source file is vendored, backend invocation MUST be refactored into an
explicit dispatcher and the existing Google behavior MUST remain unchanged.

The four Google production files currently vendored under `src/` are
byte-identical to `robotstxt-cpp` at its recorded pin. That integration is the
process precedent for Yandex, not a shared behavioral implementation.

## 3. Architecture and ownership

The required architecture is:

```text
robots_evaluate_text_v1() / robots_evaluate_url_v1()
  -> neutral source evidence
  -> selected robots_policy_ruleset
  -> policy action
       |-- allow_all -> no matcher call
       `-- use_rules
            -> explicit matcher_backend dispatch
                 |-- google -> package-owned Google adapter
                 |              -> vendored robotstxt-cpp
                 `-- yandex -> package-owned Yandex adapter
                                -> vendored robotstxtyandex
```

Ownership boundaries are normative:

| Layer | Owner | Responsibility |
| --- | --- | --- |
| HTTP acquisition and safety | `robotstxtr` | Origin construction, redirects, timeout, byte ceiling, SSRF, HTTPS downgrade prevention, evidence retention. |
| Status and body policy | `robotstxtr` engine profile | Decide whether evidence is usable, rules should be evaluated, or access is open/unknown. |
| Absolute URL to Yandex request target | `robotstxtr` Yandex adapter | Produce the byte-preserving slash-prefixed request target required by the core. |
| Yandex body parsing and group selection | `robotstxtyandex` | Apply only its released evidence-backed parser and crawler profiles. |
| Yandex access matching and source rule | `robotstxtyandex` | Produce its owning checked evaluation result. |
| R result schema and errors | `robotstxtr` | Map the native result without changing its meaning. |

The matcher backend MUST be selected by `matcher_backend`, never inferred from
`robots_policy_ruleset`. Mixed explicit combinations remain possible because
the existing contract intentionally keeps those axes independent.

## 4. Reusable ideas and prohibited inheritance

### 4.1 Ideas adopted from the `robotstxt-cpp` integration

The Yandex integration MUST adopt these engineering patterns:

- the standalone C++ engine remains the source of truth;
- `robotstxtr` consumes one immutable, released engine revision;
- production sources are vendored and compiled locally;
- vendored files have an exact manifest and cryptographic hashes;
- engine provenance and underlying evidence baselines are recorded;
- the native adapter is package-authored and outside the vendored source set;
- normal package build, install, check, and tests are offline;
- no production dependency beyond C++17 and the R package's existing native
  interface is added;
- standalone tests, vendored fidelity tests, binding tests, and facade tests
  form separate gates; and
- an engine update is a deliberate revalidation event, never an automatic
  dependency refresh.

### 4.2 Google behavior that MUST NOT be inherited

The Yandex adapter MUST NOT reuse behavior merely because it exists in
`robotstxt-cpp`, including:

- `googlebot::GetPathParamsQuery()` as an implicit Yandex URL contract;
- `MaybeEscapePattern()` percent-escape or non-ASCII canonicalization;
- Google UTF-8 BOM removal;
- Google `index.htm` or `index.html` rewriting;
- Google product-token extraction or first-space handling;
- Google arbitrary agent matching or global-group fallback;
- Google acceptable-typo and missing-colon recovery;
- Google line-length behavior;
- Google empty-access-directive behavior; and
- Google wildcard-specificity behavior where accepted Yandex expectations
  differ.

Code sharing is limited to package-owned integration infrastructure and neutral
result transport. The parser, group selector, access matcher, and engine
behavior remain separate implementations.

### 4.3 Standalone `robotstxtyandex` improvements informed by
`robotstxt-cpp`

The integration review SHOULD also consider improvements to the standalone
Yandex library. These are adaptations of useful product or observability ideas,
not imports of Google behavior.

#### 4.3.1 Checked evaluation as the primary auditing surface

`robotstxt-cpp` makes several matcher preconditions and state facts observable
through helpers such as `IsValidUserAgentToObey()`, `matching_line()`, and
`ever_seen_specific_agent()`. The Yandex library already improves on the
winning-rule surface by returning an owning `RuleMatch`, but its 0.1
`Policy::Evaluate()` still represents unsupported crawler tokens and invalid
request targets as `default_allow`.

The standalone library SHOULD add the parallel checked evaluation API already
reviewed in `docs/FUTURE_CHECKED_EVALUATION_API.md`. It SHOULD become the
recommended surface for audit, validation, and multi-engine adapters while the
0.1 fail-open method remains available for compatibility. This is the only
standalone API improvement that is recommended as a blocker for the preferred
integration path.

#### 4.3.2 Crawler-selection provenance

Google's `ever_seen_specific_agent()` exposes a useful distinction that a
binary access decision alone cannot express. The Yandex analogue should be
richer and profile-specific rather than copying that Boolean.

A future checked or traced evaluation MAY report an owning selection summary
with a stable shape such as:

```cpp
enum class SelectionTier {
  exact_yandex,
  wildcard_fallback,
  exact_yandex_additional_bot,
  none,
};

struct SelectionSummary {
  SelectionTier tier;
  std::vector<std::size_t> selected_group_lines;
  std::size_t effective_rule_count;
};
```

This would distinguish:

- no applicable group;
- an applicable group with no matching access rule;
- exact-profile selection;
- wildcard fallback; and
- multiple merged groups at one selected tier.

The exact type is not approved by this integration spec. Any implementation
MUST preserve the accepted Yandex tier semantics, MUST remain owning, and MUST
not expose private parser-IR references. Selection provenance is useful for
diagnostics and future source analysis but is not required to return correct v1
access decisions.

#### 4.3.3 Separate parser-reporting API

`robotstxt-cpp` separates low-level parse callbacks and
`RobotsParsingReporter` from access matching. `robotstxtyandex` already has a
better ownership model for its primary use case: `ParseResult` owns diagnostics
and `Policy` owns access rules and metadata. It should retain that model.

A future additive analysis API MAY expose a stable, project-authored per-line
report for validators and debugging. Useful fields include:

- one-based line and byte-column locations;
- recognized directive kind;
- accepted, ignored, unsupported, or malformed disposition;
- diagnostic codes;
- parsed directive value when safely representable;
- group-boundary or selected-tier relevance; and
- whether an access rule entered the effective policy.

This API MUST be separate from the access matcher and MUST NOT reproduce Yandex
tester UI wording or assets. It MUST NOT replace the owning `Policy` API with a
callback-only API. Freezing internal parser IR, implementation-only recovery
state, or exact diagnostic prose as public ABI is discouraged.

The reporting API is a good follow-up for `robotstxtr` validation features, but
it SHOULD NOT block initial Yandex access-backend availability.

#### 4.3.4 Immutable compatibility-profile identity

The standalone `version()` function identifies the library release, but an
adapter also needs to identify the behavioral profile and evidence snapshot.
The library SHOULD expose or install immutable, machine-readable constants for:

- library version;
- compatibility profile ID;
- accepted-expectation/corpus revision;
- evidence cutoff or release snapshot identity; and
- source revision when reproducibly available.

The exact source may be a public value function, generated header, installed
manifest, or package metadata. It MUST be deterministic, require no runtime
I/O, and avoid embedding a dirty-worktree identity. `robotstxtr` should publish
that identity as its matcher revision rather than inventing a looser label.

#### 4.3.5 Deterministic differential harness against an independent reference

`robotstxt-cpp` earns unusually strong confidence from its 10,138-case
differential harness against pristine upstream Google source. Yandex has no
public pristine source implementation, so an identical proof is impossible.
The closest legitimate analogue is an independent, deliberately simple
project reference model for the behavior the project itself specifies.

The standalone project SHOULD elevate its existing simple/exhaustive matcher
checks into a deterministic maintainer harness that:

1. runs the optimized access matcher and an independently structured slow
   reference matcher;
2. uses accepted bodies plus generated byte patterns, wildcard arrangements,
   anchors, empty directives, query targets, and rule-order permutations;
3. records a corpus version, generator version, seed, and case count;
4. compares decision, decision source, winning line, rule type, and rule value;
5. emits reproducible failing cases; and
6. runs offline without presenting reference-model agreement as Yandex
   evidence.

This harness validates implementation consistency only. Accepted public
documentation and reviewed Yandex observations remain the sole inputs to
compatibility behavior.

#### 4.3.6 Parser/result correlation invariants

`robotstxt-cpp` needs a separate callback-correlation test because its matcher
reports a line while its parser callback supplies rule type and value.
`robotstxtyandex` returns all three in one `RuleMatch`, which is the preferable
surface.

The standalone library SHOULD strengthen this advantage with invariant tests
covering every result shape:

- a positive rule source always has an in-range physical line;
- returned type and value are exactly the parsed rule at that line;
- comments and syntax padding are absent from the value;
- byte spelling is retained according to the public Yandex contract;
- `effective_empty_disallow` retains a Disallow type and empty value;
- `default_allow` has no rule; and
- checked non-evaluated statuses have no `MatchResult`.

These invariants SHOULD also be serialized by the standalone/vendored
differential runner so an adapter cannot reconstruct a different rule from the
body.

#### 4.3.7 Explicit limit outcomes after evidence approval

Google's parser reports line-limit state rather than failing silently. Yandex
research now contains exact-limit observations beyond the frozen 0.1 accepted
profile, while the 0.1 core deliberately does not enforce all documented
500,000-byte, 2,048-rule, 1,024-character, or 500-parameter boundaries.

If a later Yandex compatibility profile promotes limit semantics, the library
SHOULD make each limit mechanically observable through a diagnostic, parse
status, or policy outcome. It MUST define whether the affected line, section,
remaining body, or complete file is ignored, and MUST preserve fail-open
behavior where the accepted evidence requires it. Limits MUST NOT be copied
from Google merely because the constants or reporting machinery already
exist.

Fetch-size policy SHOULD remain outside the pure parser when it depends on HTTP
acquisition. Parser rule/line/value limits MAY enter the standalone core only
after the evidence and specification are revised together.

#### 4.3.8 Portability and consumer verification

`robotstxt-cpp` declares GCC, Clang, Apple Clang, and MSVC support. The Yandex
project already has strict compiler, sanitizer, installed-package, and
downstream-consumer gates. It SHOULD close the remaining portability gap by
adding an offline Windows/MSVC build-and-test lane before claiming MSVC
support.

The installed consumer SHOULD continue to exercise every public header and
result invariant. A future checked API, selection summary, or profile-identity
surface is incomplete until the install audit and downstream consumer cover
it. Compiler support MUST be stated only for toolchains that run the normal
tests, not inferred from C++17 syntax alone.

#### 4.3.9 Ideas that are already better in the Yandex design

Several `robotstxt-cpp` choices should not displace stronger existing Yandex
designs:

- retain parse-once immutable `Policy` rather than a mutable matcher that
  reparses the body per URL;
- retain owning results rather than requiring callback correlation;
- retain explicit diagnostics and canonical metadata;
- retain concurrent read-only evaluation;
- retain exact, bounded crawler profiles instead of accepting arbitrary agents;
- retain the slash-prefixed request-target core boundary instead of embedding
  an absolute-URL parser; and
- retain evidence-backed behavior rather than source-derived Google quirks.

The goal is to adopt `robotstxt-cpp`'s useful observability, provenance,
differential-verification, and portability ideas without regressing the
standalone Yandex library's cleaner ownership and policy architecture.

## 5. Standalone engine release prerequisite

`robotstxtr` MUST integrate a released `robotstxtyandex` revision, not an
arbitrary sibling checkout. The candidate 0.1.0 engine provides the required
parser and matcher, but its `Policy::Evaluate()` deliberately conflates invalid
caller input and unsupported crawler profiles with evaluated
`default_allow`.

Before the integration is marked available, one of these reviewed approaches
MUST be selected:

1. **Preferred:** release a parallel checked entry point in
   `robotstxtyandex`, following its reviewed
   `docs/FUTURE_CHECKED_EVALUATION_API.md` direction; or
2. validate the exact supported profile and request-target preconditions in the
   package-owned Yandex native adapter before calling the unchanged 0.1 API.

Either approach MUST make these states mechanically distinct:

| Native adapter status | Match payload |
| --- | --- |
| `evaluated` | Exactly one Yandex `MatchResult`. |
| `unsupported_crawler` | None. |
| `invalid_request_target` | None. |

An unsupported token or invalid request target MUST NOT become a genuine
`default_allow` in the engine-aware result.

The chosen engine release MUST pass its complete standalone offline verification
before vendoring. The standalone release identity, source archive hash, public
API, compiler requirements, legal text, and accepted-expectation inventory
MUST be frozen in the integration review.

## 6. Vendoring and build contract

### 6.1 Vendored source set

The vendored set MUST contain only the production files required to compile the
released engine:

- the five public headers under `include/robotstxtyandex/`;
- the production `.cc` files under `src/`; and
- the private `src/*.h` files included by those translation units.

It MUST NOT contain standalone tests, evidence observations, browser artifacts,
probe tooling, CMake build output, `_scratch/`, `.fp/`, source-control data, or
generated local caches.

The candidate layout is:

```text
src/vendor/robotstxtyandex/include/robotstxtyandex/*.h
src/vendor/robotstxtyandex/src/*.{cc,h}
src/yandex_binding.cpp
```

The final layout MAY differ to satisfy portable R package compilation, but the
vendored files themselves MUST remain byte-identical to the approved source
archive. They MUST NOT be flattened or edited merely to simplify the R build.
A portable `src/Makevars`/`src/Makevars.win` object layout or a generated build
manifest is preferable to changing engine source.

### 6.2 Namespace and symbols

The standalone engine namespace `robotstxtyandex` MUST be preserved. Google
continues to use `googlebot`. Package-owned bindings MUST use distinct names
and MUST NOT expose private engine headers as an R package API.

The R package does not promise a public C++ ABI for either vendored engine.
Only the R engine-aware contract and its published revision metadata are public
integration surfaces.

### 6.3 Provenance and legal files

The integration MUST add a plainly diffable Yandex provenance record containing:

- immediate repository and full commit SHA;
- standalone package version;
- source archive SHA-256;
- every vendored path and SHA-256;
- import date;
- approved source-to-vendored mapping;
- compiler/language baseline;
- standalone verification result;
- compatibility/evidence snapshot identity;
- license and notice disposition; and
- a deterministic offline verification procedure.

The existing Google provenance MUST remain intact. A Yandex import MUST NOT
rewrite Google source provenance or imply common authorship. Licensing review
MUST confirm that the standalone engine's license and notices are compatible
with the R package and are included in source and binary distributions as
required.

No Git submodule, `FetchContent`, package-manager download, sibling-path lookup,
or dynamic network fetch is allowed in configure, build, install, check, test,
or runtime paths.

## 7. Package-owned backend dispatch

Backend metadata and invocation MUST remain adjacent enough that a backend
cannot be marked available without a callable implementation.

The R layer SHOULD expose one package-private dispatcher with semantics
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

The exact implementation MAY use a registry rather than `switch`, but these
invariants are mandatory:

- `matcher_availability == "available"` implies a registered adapter;
- an unregistered or unavailable backend is never sent to another backend;
- dispatch depends only on the explicit matcher backend;
- a registered adapter returns the common internal result shape; and
- a dispatch invariant failure is a package error, not an allow decision.

The refactor introducing dispatch MUST land with Google-only regression tests
before the Yandex availability flag changes.

## 8. Native Yandex adapter

### 8.1 Input and lifetime

The native adapter MUST accept the exact retained body bytes from the evidence
object. It MUST be length-aware and MUST NOT rely on NUL termination or a
locale conversion. Converting fetched raw bytes through `rawToChar()` before
the native call SHOULD be avoided; the binding should construct the C++ body
from an R raw vector or another explicitly length-bearing input.

For one distinct source body, the binding MUST:

1. construct one owning `robotstxtyandex::Policy`;
2. retain its parse diagnostics for the duration of the native call;
3. evaluate every applicable row against that policy; and
4. return owning R values without retaining R or C++ views after the call.

Parsing the same body once per URL is prohibited unless a measured platform
constraint makes parse-once batching impossible and the owner approves the
regression. A persistent external-pointer API is not required for v1; one
native batch call per distinct source is sufficient.

### 8.2 Common internal result

Every evaluated row returned by a backend adapter MUST supply:

```text
evaluation_status
url_decision
reason
matched_line
matched_rule_type
matched_rule_value
matcher_input_bytes
matcher_body_truncated
```

The Yandex mapping is normative:

| Yandex source | `url_decision` | `reason` | Matched rule |
| --- | --- | --- | --- |
| `default_allow` | `allow` | `default_allow` | line absent; type `none`; value absent |
| `rule_allow` | `allow` | `rule_allow` | retain original line, type `allow`, and parsed value |
| `rule_disallow` | `disallow` | `rule_disallow` | retain original line, type `disallow`, and parsed value |
| `effective_empty_disallow` | `allow` | `effective_empty_disallow` | retain original line, type `disallow`, and empty value |

The effective-empty case MUST NOT be rewritten as `rule_allow` or
`default_allow`. It is an evaluated Yandex allow caused by an original empty
`Disallow` rule.

For non-evaluated input:

| Checked status | `matcher_status` | `url_decision` | `reason` |
| --- | --- | --- | --- |
| `unsupported_crawler` | `not_evaluated` | absent | `unsupported_product_token` |
| `invalid_request_target` | `not_evaluated` | absent | `invalid_request_target` |

The error stage/class fields MUST identify these as matcher-input failures, not
HTTP acquisition failures.

### 8.3 Diagnostics and metadata

`robotstxtyandex` also produces source-located diagnostics, ordered `Sitemap`
entries, and canonical `Clean-param` metadata. They do not affect the access
decision in its 0.1 profile.

Access-backend availability MUST NOT depend on inventing an R representation
for those values. However, the binding MUST not accidentally use or reinterpret
them as access rules. Whether v1 exposes them in a new source-analysis table is
an owner decision in section 17. If exposed, they belong once per source, not
duplicated on every URL result row, and require an engine-contract schema
revision with explicit value shapes.

## 9. Absolute URL to request-target boundary

### 9.1 Required Yandex core input

The Yandex core accepts an original slash-prefixed HTTP request target:

- path begins with `/`;
- query is included when present; and
- fragment is excluded.

It does not accept an absolute URL and does not percent-decode, normalize
Unicode, resolve dot segments, fold path case, or otherwise canonicalize the
target.

`robotstxtr` accepts absolute HTTP(S) URLs. Therefore, producing the Yandex
request target is an integration responsibility owned by the Yandex adapter,
not by the standalone engine and not by the Google adapter.

### 9.2 Extraction contract

The extractor MUST operate on the original URL element supplied for matching,
after only the package's ordinary scalar/HTTP(S) validity checks. It MUST:

- remove the scheme and authority without changing later bytes;
- use `/` when the absolute URL has no explicit path;
- preserve the path byte spelling;
- preserve the query delimiter and query byte spelling, including an empty
  query when representable by the input;
- remove the fragment delimiter and fragment;
- preserve percent-escape case;
- preserve literal Unicode bytes as represented at the native boundary;
- preserve duplicate slashes and dot-segment spelling;
- preserve parameter and query ordering; and
- reject extraction failures as `invalid_request_target` without a crawl
  decision.

Examples of the intended engineering boundary are:

| Absolute URL | Yandex request target |
| --- | --- |
| `https://example.test` | `/` |
| `https://example.test?x=1` | `/?x=1` |
| `https://example.test/a//b?x=%2f` | `/a//b?x=%2f` |
| `https://example.test/a/../b#frag` | `/a/../b` |

The extractor MUST NOT use a cleaned, decoded, canonicalized, or reserialized
URL. In particular, it MUST NOT silently delegate Yandex semantics to
`googlebot::GetPathParamsQuery()` or a `rurl` clean-URL result. A package-owned
extractor MAY use a URL library only if byte-preservation tests prove the exact
contract above on every supported platform.

This extraction behavior is a `robotstxtr` engineering contract. It is not
evidence that the Yandex tester or production crawler receives an identical
wire representation.

## 10. Policy and limit interaction

The existing Yandex status-policy ruleset remains owned by `robotstxtr` and is
applied before matcher dispatch.

For a supplied or fetched usable body:

- a body of at most 500,000 bytes may proceed to the Yandex matcher;
- a body over 500,000 bytes resolves through the documented Yandex
  `allow_all` policy and MUST NOT be truncated and parsed by the matcher;
- when policy selects `allow_all`, `matcher_status` is `not_needed`; and
- matcher input/truncation fields remain absent because no matcher ran.

The Google 524,288-byte retained-prefix behavior remains unchanged and applies
only when the selected policy/backend path calls for it.

The standalone 0.1 Yandex core does not enforce every documented rule-count,
rule-length, `Clean-param`, or fetch limit. `robotstxtr` MUST NOT silently add
such parser semantics inside the adapter and label them as core matcher
behavior. Any future executable validation policy requires its own contract
and evidence review.

## 11. Engine-aware contract changes

When all implementation gates pass:

- `engine_matcher_revisions_v1()` MUST publish the exact Yandex engine revision,
  including enough immutable identity to trace the vendored source;
- `engine_matcher_availability_v1()` MAY change Yandex to `available` only in
  the same release that includes its registered adapter and tests;
- `robots_engine_contract_v1()` MUST publish the new schema revision;
- the policy revision remains independent of the matcher revision; and
- existing Google, RFC 9309, Bing, and assumed-RFC states remain unchanged
  unless separately reviewed.

Adding Yandex access matching does not make RFC 9309 or Bing matchers available.
It also does not change the four legacy Google-oriented public functions or
make the legacy adapter accept Yandex results.

An `effective_empty_disallow` reason is a new meaningful result value. Even if
the `reason` column is not formally enumerated in R, the contract revision and
documentation MUST identify it and its invariant with the retained empty
Disallow rule.

## 12. Conformance and regression gates

### 12.1 Standalone engine gate

The exact standalone revision selected for vendoring MUST pass its normal
offline gate, including:

- C++ build and unit tests;
- every accepted Yandex matcher expectation;
- corpus and evidence lifecycle validation;
- install and downstream-consumer audit;
- fuzz/adversarial smoke tests; and
- repository safety and release identity checks.

### 12.2 Vendored-fidelity gate

`robotstxtr` MUST prove that:

- every vendored file matches its manifest hash;
- the vendored file set is complete and contains no unapproved file;
- the package-native binding is excluded from the vendored hash set;
- the vendored engine produces the same result as the approved standalone
  engine for the complete compact integration corpus; and
- provenance and legal files are present in source and installed package
  artifacts as required.

The fidelity gate MUST run offline from a clean package source tree. It MUST
not depend on `~/Projects/robotstxtyandex` existing.

### 12.3 Yandex facade conformance gate

The R package MUST carry a compact, provenance-recorded integration projection
of all 140 accepted Yandex expectations from the candidate 0.1.0 profile, or
the complete accepted set from the later approved integration baseline. For
every case, the test MUST check through the real engine-aware facade:

- evaluated/non-evaluated status;
- allow/disallow decision;
- decision reason;
- matched line;
- matched rule type; and
- matched rule value.

The projection MUST retain exact body bytes and case IDs. It MUST not rewrite
standalone expectations to accommodate R adapter behavior.

### 12.4 Cross-engine sentinel gate

Google/Yandex agreement is not a Yandex conformance requirement. A small
cross-engine sentinel suite SHOULD retain the known semantic separation:

- Google and Yandex agree on the ordinary shared controls;
- the known empty-Disallow differences remain visible;
- the known wildcard-specificity differences remain visible; and
- representative malformed/typo parser differences remain visible.

At the candidate corpus cutoff, direct evaluation found 125 of 140 accepted
Yandex decisions agreeing with `robotstxt-cpp` and 15 deliberate differences.
The sentinel gate protects against accidental Google routing; it MUST NOT turn
the 125 agreements into evidence for Yandex or require future disagreement
counts to remain frozen after a reviewed evidence update.

### 12.5 Google non-regression gate

The integration MUST leave the Google engine and legacy API behavior unchanged.
At minimum:

- all existing `robotstxtr` tests pass;
- the vendored Google source hashes remain unchanged;
- Google engine-aware facade fixtures remain byte-for-byte equivalent;
- empty Google access directives retain their current Google result shapes;
- Google matched-rule callback correlation remains unchanged; and
- the Yandex adapter is never loaded by a Google matcher request.

### 12.6 Package quality gates

The final package MUST pass, offline:

- the project's normal verify command;
- `R CMD build` and `R CMD check` under the supported R/toolchain matrix;
- native registration checks;
- sanitizer jobs for package-authored bindings and both vendored engines;
- source-package and binary-package legal/provenance audits; and
- a clean-checkout test proving no sibling repository is required.

## 13. Byte and representation requirements

The adapter MUST preserve body length and content through the C++ parse call,
including embedded NUL and invalid UTF-8, to the extent the engine-aware source
evidence can contain those bytes. Such byte forms remain
`robotstxtyandex` project behavior where its evidence policy says they are not
Yandex compatibility claims.

R result strings cannot be assumed to losslessly represent every arbitrary
byte sequence. The access decision, source type, and source line MUST remain
available even if a matched rule value cannot be represented as an ordinary R
character scalar.

Before implementation, the owner MUST choose one representation for a
non-text matched rule value:

- a raw list-column or parallel raw field in a revised schema;
- an explicitly byte-marked R string when R supports the exact value; or
- a documented unavailable textual value plus an exact raw source-level
  representation.

The adapter MUST NOT replace invalid bytes, truncate at NUL, or silently
convert them to UTF-8. This decision may require an engine-contract schema
revision beyond merely enabling the backend.

## 14. Performance and concurrency

No network or filesystem access is permitted in matcher invocation. Matching
must be deterministic for identical explicit inputs.

The Yandex binding SHOULD parse once per distinct source body and evaluate all
associated rows using the immutable policy. It SHOULD avoid one native-call
round trip per URL when a batch result can be returned safely.

R evaluation remains sequential unless a separate package contract introduces
parallelism. The standalone engine's concurrent read-only guarantee is useful
for correctness but does not authorize background threads, R API calls from
worker threads, or new process-global caches in this integration.

Performance changes to the Google adapter, such as combining its decision and
matching-line passes, are explicitly separate. They SHOULD be considered after
Yandex integration, but MUST NOT be mixed into the first Yandex implementation
slice because doing so would make Google regressions harder to attribute.

## 15. Delivery slices

Each slice must end in a runnable, offline tracer bullet. Planning/backlog
issues MAY exist while this specification is under review, but their existence
does not authorize implementation. An implementation issue may be claimed only
after the relevant owner decisions and specification status permit it.

### YI1: Backend dispatch without behavior change

**Repository:** `robotstxtr`

**Deliverables:**

- explicit package-owned matcher dispatcher;
- availability/registration invariant checks; and
- Google-only regression tests.

**Acceptance:** all current tests pass; every current Google result is
unchanged; requesting unavailable Yandex still returns
`capability_unavailable`; no Yandex source is present.

### YI2: Checked standalone integration surface

**Repository:** `robotstxtyandex`

**Deliverables:** either the reviewed checked evaluation API and a new release,
or a formally approved decision that adapter-side prevalidation is sufficient;
immutable compatibility-profile identity; and strengthened result-correlation
invariants. The owner decision may also include the reference differential
harness from section 4.3.5 in the selected standalone baseline.

**Acceptance:** unsupported crawler, invalid request target, genuine
`default_allow`, every rule source, and all result invariants have exhaustive
public/consumer tests; normal standalone verification passes.

### YI3: Vendored source and provenance

**Repository:** `robotstxtr`

**Deliverables:** approved production source snapshot, build wiring, manifest,
provenance, legal files, and hash verifier.

**Acceptance:** package compiles offline on supported platforms; hashes match;
no sibling checkout is used; Google hashes remain unchanged; no adapter is yet
reported available unless YI4 and YI5 are in the same atomic release change.

### YI4: Native binding and request-target extractor

**Repository:** `robotstxtr`

**Deliverables:** byte-length-aware binding, parse-once batch evaluation,
checked-status mapping, request-target extraction, and native unit fixtures.

**Acceptance:** exact URL-boundary matrix passes; embedded-byte body fixtures
are safe; all standalone expectation projections match through the native
binding; no R facade availability change is required yet.

### YI5: Engine-aware facade activation

**Repository:** `robotstxtr`

**Deliverables:** `match_yandex_v1()`, registered dispatch, immutable backend
revision, availability change, result mapping, documentation, and contract
schema revision.

**Acceptance:** text and fetched-body tracer bullets return Yandex decisions;
non-200 and oversized-body policy bypass matching correctly; invalid inputs
produce non-decisions; mixed explicit policy/backend combinations retain their
declared axes.

### YI6: Complete conformance and non-regression

**Repository:** `robotstxtr`

**Deliverables:** complete accepted-expectation projection, vendored-fidelity
runner, cross-engine sentinels, Google non-regression coverage, package audits,
and release notes.

**Acceptance:** every gate in section 12 passes offline on a clean checkout and
the resulting source package contains only approved source, corpus projection,
provenance, and legal material.

### YI7: Release handoff

**Repository:** `robotstxtr`

**Deliverables:** final MUST audit, exact revision identities, supported
sibling ranges, upgrade notes, and release artifact reproduction instructions.

**Acceptance:** the owner approves the final audit; package version and
contract revision match runtime metadata; no release or publication action is
implied without separate authorization.

## 16. Definition of done

The Yandex backend is complete only when:

1. the exact standalone engine revision is released and reproducible;
2. every vendored production file is pinned and verified;
3. backend dispatch cannot silently select Google for Yandex;
4. absolute URL to request-target conversion is byte-characterized;
5. unsupported crawler and invalid target are non-decisions;
6. all accepted Yandex expectations pass through the public R facade;
7. effective empty `Disallow` retains its distinct Yandex result shape;
8. Yandex status and 500,000-byte policy bypass the matcher correctly;
9. existing Google source hashes and behavior remain unchanged;
10. normal build, test, check, install, provenance, legal, sanitizer, and
    clean-checkout gates pass offline;
11. public documentation limits the claim to the bounded standalone Yandex
    compatibility profile; and
12. the engine-aware contract publishes exact policy, matcher, schema, and
    sibling compatibility revisions.

Passing the definition of done does not establish production Yandex crawler
parity, complete Yandex tester equivalence, or support for crawler profiles and
input transformations outside the standalone engine's accepted scope.

## 17. Owner review decisions

This draft remains non-authorizing until the owner records decisions for these
items:

| ID | Decision required | Recommended choice |
| --- | --- | --- |
| `YI-V1-API-1` | Require a standalone checked evaluation API, or validate in the adapter? | Release and vendor the checked API so multi-engine callers receive native state separation. |
| `YI-V1-BUILD-1` | Exact nested vendored layout and portable R build wiring. | Preserve source paths under `src/vendor/robotstxtyandex` and list objects explicitly; never edit vendored includes merely to flatten files. |
| `YI-V1-TARGET-1` | Implementation of byte-preserving absolute URL to request-target extraction. | Package-owned native extractor with a frozen cross-platform byte matrix; no Google or cleaned-URL delegation. |
| `YI-V1-BYTES-1` | Representation of matched rule values that are not valid ordinary R text. | Add an exact raw representation in a revised engine schema while retaining the convenient text field when representable. |
| `YI-V1-META-1` | Expose diagnostics, Sitemap, and Clean-param in the first integration release? | Defer public source analysis to a separately reviewed additive table; do not block access-backend availability. |
| `YI-V1-PIN-1` | Vendor 0.1.0 with adapter validation or a later release containing checked evaluation. | Prefer the later reviewed release; record 0.1.0 only as the behavioral baseline. |
| `YI-V1-SCHEMA-1` | Exact `robotstxtr.engine-aware/v1` schema revision and reason vocabulary. | Bump the schema revision when Yandex becomes available and document `effective_empty_disallow` plus matcher-input non-decisions. |
| `YI-V1-IDENTITY-1` | Require machine-readable standalone compatibility-profile identity? | Require it in the selected engine release so `robotstxtr` can publish an engine-supplied matcher revision. |
| `YI-V1-TRACE-1` | Add crawler-selection provenance to the standalone result surface? | Approve as a later additive checked/trace API; do not block initial access matching. |
| `YI-V1-REPORT-1` | Add a standalone per-line parser-reporting API modeled on the useful role, but not the callback shape, of Google's reporter? | Defer to a separate validator/source-analysis contract while preserving the owning Policy API. |
| `YI-V1-DIFF-1` | Require an optimized-versus-reference generated differential harness in the selected standalone baseline? | Require a deterministic offline harness before the next standalone compatibility-profile release; label it implementation verification, never Yandex evidence. |
| `YI-V1-PORT-1` | Is Windows/MSVC part of the standalone and R integration support claim? | Add a real MSVC lane before claiming support; otherwise document it as unverified. |

## 18. Deferred work

The following are outside this integration v1 unless a later reviewed revision
moves them in:

- additional Yandex crawler profiles;
- production-crawler equivalence claims;
- `Clean-param` URL canonicalization or deduplication;
- public parser/analyzer UI reproduction;
- crawl scheduling or Crawl-delay enforcement;
- sitemap fetching or validation;
- new rule-count or line-length enforcement not present in the approved engine;
- automatic standalone engine updates;
- a public persistent native policy pointer;
- parallel R evaluation;
- refactoring or optimizing the Google native adapter;
- a shared Google/Yandex parser or matcher kernel; and
- making RFC 9309 or Bing matcher backends available.

Unless separately approved in section 17, initial backend availability also
defers the optional standalone selection-trace API, public per-line parser
reporting, newly promoted parser-limit semantics, and an MSVC support claim.

## 19. Review checklist

The review session should verify, in order:

1. product and claim boundary;
2. independent policy and matcher axes;
3. dispatch correction before availability;
4. standalone checked-result decision;
5. URL/request-target byte boundary;
6. vendored source layout, pin, provenance, and licensing;
7. result mapping, especially effective empty `Disallow`;
8. body-limit interaction;
9. byte representation in R;
10. standalone improvements in section 4.3, including which are blockers;
11. diagnostics/metadata and parser-reporting scope;
12. conformance, reference-differential, portability, and Google
    non-regression gates;
13. delivery slices and release definition; and
14. every owner decision in section 17.

Approval should replace the draft status with an implementation-authorizing
status, record the approved engine pin or pin-selection rule, assign FP issues
for the slices, and preserve this reviewed contract as durable project
knowledge.
