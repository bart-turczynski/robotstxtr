# robotstxtbing compatibility contract v1

- Status: **draft for owner review; not implementation-authorizing**
- Contract ID: `robotstxtbing.compatibility/v1`
- Draft revision: `2026-07-17.1`
- Evidence cutoff: 2026-07-17
- Product-boundary decision: FP `ROBO-rvnkadzd`
- Specification review: FP `ROBO-jeeycsyh`
- Intended first release: `robotstxtbing` 0.1.0

This document is the review surface for the first versioned `robotstxtbing`
contract. It becomes implementation-authorizing only after the owner approves
the whole document and every release-blocking open clause is either resolved
by accepted evidence or explicitly deferred from the compatibility profile.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**
describe the proposed project contract. They do not imply that Bing has made
the same requirement unless the clause cites Bing evidence.

## 1. Product definition

`robotstxtbing` is an independent, unofficial, clean-room C++17 library for
parsing an in-memory `robots.txt` body and evaluating an HTTP request target
under a bounded, evidence-backed Bing crawler profile.

The first product is:

- a sibling repository and package, separate from `robotstxtr`,
  `robotstxt-cpp`, and `robotstxtyandex`;
- a deterministic in-memory parser, access matcher, diagnostic producer, and
  immutable metadata value;
- free of network, filesystem, clock, locale, environment, and process-global
  inputs during parsing and evaluation;
- implemented without a runtime dependency beyond the C++17 standard
  library; and
- licensed under Apache-2.0, with project and evidence provenance recorded in
  the repository.

The 0.1 series promises a reviewed source and semantic contract. It does not
promise a stable public ABI before 1.0.

### 1.1 Compatibility claim

The library may claim compatibility only for behavior represented by:

1. a dated current Bing or Microsoft primary source mapped to an exact
   expectation; or
2. an accepted, exact Bing Webmaster Tools tester expectation satisfying the
   evidence policy in section 3.

Everything else is an explicit project behavior, unsupported behavior, or an
open/deferred question. Agreement with RFC 9309, `robotstxt-cpp`, Google, or
another search engine is not Bing evidence.

The library MUST NOT claim complete production-crawler equivalence. A
[July 2020 Bing announcement](https://blogs.bing.com/webmaster/july-2020/Announcing-the-new-Bing-Webmaster-Tools-%28migration-complete%29)
said the then-current tester used the production parser. That dated statement
is relevant corroboration, but it does not establish current tester transport,
fetch policy, unexposed crawler profiles, or every production behavior.

### 1.2 Non-goals for v1

The core does not own:

- fetching `/robots.txt`;
- HTTP status, redirect, network-error, or TLS policy;
- cache lifetime or last-known-good behavior;
- SSRF or HTTPS-downgrade policy;
- Crawl-delay scheduling or crawl-rate enforcement;
- sitemap fetching or validation;
- extraction of a robots product token from a complete HTTP User-Agent;
- absolute-URL parsing or canonicalization;
- general REP conformance validation; or
- profiles for crawler identities not exposed by the current Bing tester.

## 2. Repository and package boundary

The intended repository, CMake package, installed target, and C++ namespace
are all named `robotstxtbing`:

```text
repository:       robotstxtbing
CMake package:    robotstxtbing
installed target: robotstxtbing::robotstxtbing
C++ namespace:    robotstxtbing
language:         C++17
license:          Apache-2.0
```

The library MUST be consumable as an ordinary installed CMake package. A
downstream consumer test MUST build against the installed target rather than
repository-relative private headers.

`robotstxtr` will later vendor or otherwise consume a pinned released revision
subject to its own CRAN and provenance constraints. No live network dependency
on the sibling repository is permitted at R package build or runtime.

`robotstxtyandex` may supply process and tooling patterns, including corpus
schemas, validators, provenance checks, and release gates. Its parser code,
crawler tiers, accepted expectations, result conflations, and release
snapshots are not inputs to Bing behavior.

`robotstxt-cpp` is a pinned comparative baseline only. It MUST NOT be linked,
wrapped, copied as the Bing implementation, or used to generate Bing expected
outcomes.

## 3. Evidence contract

### 3.1 Vocabulary

Every expectation has exactly one behavioral evidence grade:

| Grade | Meaning |
| --- | --- |
| `documented` | Supported by a dated, cited Bing or Microsoft primary source. |
| `tester_observed` | Supported by accepted Bing Webmaster Tools tester observations. |
| `project_behavior` | Deterministic behavior selected by this project where Bing evidence does not answer the question. |

Research comparisons use separate labels such as `rfc9309_prediction` and
`pinned_google_observation`. They never become behavioral evidence grades.

Raw observations have lifecycle states distinct from expectations:

```text
planned -> staged -> submitted -> terminal -> independently_reviewed
```

Reviewed expectations have separate states:

```text
candidate -> accepted -> superseded
```

Raw observations are append-only historical records. Later contradictions
supersede expectations and add observations; they do not rewrite prior runs.

### 3.2 Promotion threshold

A documented expectation MUST cite a dated primary source and an exact body,
profile, and request-target fixture that makes the expected outcome
unambiguous.

An undocumented matcher behavior normally requires:

- exact retained fixture content and a cryptographic body hash;
- a terminal tester result;
- independent transcription review;
- two concordant observations, preferably on different dates; and
- no unresolved transport ambiguity that could explain the result.

An owner-approved exception to the two-observation threshold MUST be recorded
with rationale and may not be described as stronger evidence than it is.

Production fetch, cache, or scheduler claims require a current, behavior-
specific Microsoft statement. The editable tester cannot establish them.

### 3.3 Current documentation boundary

The primary-source inventory accessed on 2026-07-17 supports these bounded
facts:

- current tester labels are `Bingbot` and `AdIdxbot`, and the tester evaluates
  a submitted URL against editable content;
- a Bingbot-specific section replaces the generic section for Bingbot;
- ASCII and UTF-8 are recommended body encodings;
- canonical `Allow`, `Disallow`, wildcard, `Sitemap`, and `Crawl-delay`
  authoring forms are recognized;
- Bingbot Crawl-delay uses values from 1 through 20 seconds and overrides the
  Crawl Control product setting; and
- robots changes may take at least several hours to appear because Bing keeps
  a cached copy.

Sources:

- [robots.txt tester](https://www4.bing.com/webmasters/help/robots-txt-tester-623520ca)
- [How to create a robots.txt file](https://www.bing.com/webmasters/help/how-to-create-a-robots-txt-file-cb7c31ec)
- [Which crawlers does Bing use?](https://www.bing.com/webmasters/help/which-crawlers-does-bing-use-8c184ec0)
- [How to report an issue with Bingbot](https://www.bing.com/webmasters/help/how-to-report-an-issue-with-bingbot-25c19802)
- [Crawl Control](https://www.bing.com/webmasters/help/crawl-control-55a30303)

The inventory does not currently answer the exact robots-specific status
table, redirect policy, network policy, cache duration, body or line limit,
truncation behavior, malformed recovery, empty-directive behavior,
percent/Unicode processing, repeated-group treatment, or complete current
token-selection algorithm.

Historical sources may define probe hypotheses but do not silently fill those
gaps:

- a [2008 joint REP post](https://blogs.bing.com/webmaster/June-2008/Robots-Exclusion-Protocol-joining-together-to-pro)
  described longest-rule selection and `*`/terminal-`$` support;
- a [2010 Bing crawler post](https://blogs.bing.com/webmaster/June-2010/Bing-crawler-bingbot-on-the-horizon)
  described `msnbot` backwards compatibility; and
- a [2012 Bingbot post](https://blogs.bing.com/webmaster/May-2012/To-crawl-or-not-to-crawl%2C-that-is-BingBot-s-questi)
  described the priority `bingbot`, then `msnbot`, then `*`.

The current tester and crawler inventory do not expose `msnbot`. A September
2020 tester post used `BingAdsBot`, while current help uses `AdIdxbot` and the
crawler inventory uses `AdIdxBot`. These are recorded conflicts, not automatic
aliases.

## 4. Supported profile boundary

The target v1 profile set is:

| Canonical profile | Current basis | v1 state |
| --- | --- | --- |
| `Bingbot` | Current tester and crawler help | release candidate, pending calibration and semantic expectations |
| `AdIdxBot` | Current tester and crawler help; tester label casing is `AdIdxbot` | release candidate, pending calibration and semantic expectations |

Product-token spelling is compared with locale-independent ASCII case folding
only if the calibration/selection expectations confirm that behavior. The
canonical public spelling remains as shown above.

These names are not v1 profiles:

| Name | Disposition |
| --- | --- |
| `msnbot` | Historical probe control; unsupported in v1 unless separately approved after current evidence. |
| `BingAdsBot` | Historical tester naming control; not an alias for `AdIdxBot` without evidence. |
| `BingPreview` | Current inventory role whose shown identification strings use `bingbot`; no distinct tester profile. |
| `MicrosoftPreview` | Current crawler inventory only; no tester profile. |
| `BingVideoPreview` | Current crawler inventory only; no tester profile. |
| any other token | `unsupported_profile`; never silently mapped to Bingbot or wildcard. |

Open clause `BING-V1-PROFILE-1`: exact selection, case comparison, stacked
agents, repeated same-token groups, and wildcard fallback MUST be resolved by
accepted expectations before release.

Open clause `BING-V1-PROFILE-2`: `AdIdxbot` tester-label casing versus
`AdIdxBot` public profile spelling MUST be captured in calibration and mapped
without claiming that UI labels are robots product tokens.

## 5. Public C++ API

The exact spelling is reviewable, but the state separation in this section is
normative for the target v1 contract.

### 5.1 Proposed headers

```cpp
#include <robotstxtbing/diagnostic.h>
#include <robotstxtbing/metadata.h>
#include <robotstxtbing/policy.h>
#include <robotstxtbing/result.h>
#include <robotstxtbing/version.h>
```

Every public header MUST be self-contained.

### 5.2 Policy and parse result

```cpp
namespace robotstxtbing {

struct ParseResult;

class Policy {
 public:
  Policy(const Policy&) noexcept;
  Policy(Policy&&) noexcept;
  Policy& operator=(const Policy&) noexcept;
  Policy& operator=(Policy&&) noexcept;
  ~Policy();

  static ParseResult Parse(std::string_view body);

  EvaluationResult Evaluate(std::string_view product_token,
                            std::string_view request_target) const;

  const std::vector<SitemapEntry>& sitemaps() const noexcept;
  const std::vector<CrawlDelayEntry>& crawl_delays() const noexcept;
};

struct ParseResult {
  Policy policy;
  std::vector<Diagnostic> diagnostics;
};

}  // namespace robotstxtbing
```

`Parse` copies all retained information. The returned objects MUST NOT retain
views or pointers into caller storage. Malformed input MUST NOT prevent return
of a usable policy unless ordinary allocation failure occurs.

`Policy` is an immutable owning value after parsing. Copies MAY share
immutable storage. Concurrent read-only evaluation and metadata access on the
same non-moved-from policy MUST be safe without caller locking.

### 5.3 Evaluation result

```cpp
enum class EvaluationStatus {
  evaluated,
  invalid_request_target,
  unsupported_profile,
};

enum class AccessDecision {
  allow,
  disallow,
};

enum class DecisionSource {
  rule_allow,
  rule_disallow,
  default_allow,
};

struct RuleMatch {
  RuleType type;
  std::string value;
  std::size_t line;
};

struct EvaluationResult {
  EvaluationStatus status;
  std::optional<AccessDecision> decision;
  std::optional<DecisionSource> source;
  std::optional<RuleMatch> matched_rule;
};
```

Only `evaluated` may contain an access decision. The valid shapes are:

| Status | Decision | Source | Matched rule |
| --- | --- | --- | --- |
| `evaluated` | `allow` | `rule_allow` | present, Allow |
| `evaluated` | `disallow` | `rule_disallow` | present, Disallow |
| `evaluated` | `allow` | `default_allow` | absent |
| `invalid_request_target` | absent | absent | absent |
| `unsupported_profile` | absent | absent | absent |

Invalid input and unsupported profiles MUST NOT be represented as genuine
default allow. This deliberately improves on result shapes that conflate
caller error with an evaluated no-match outcome.

If evidence later establishes an effective empty directive that wins while
retaining a distinct source meaning, the enum MUST gain an explicit source
rather than fabricating an Allow rule. This is open clause
`BING-V1-RESULT-1`.

## 6. Input contracts

### 6.1 Body

The input body is an in-memory byte sequence supplied through
`std::string_view`. Parsing MUST be length-aware and MUST NOT use a terminating
NUL as the body boundary.

Current Bing authoring help recommends ASCII or UTF-8. Exact behavior for a
UTF-8 BOM, invalid UTF-8, embedded NUL, lone CR, and other noncanonical bytes
is not documented.

Open clause `BING-V1-BYTES-1`: before implementation, the spec MUST define a
deterministic, memory-safe project behavior for tester-unpreservable byte
forms. Those decisions MUST remain labeled `project_behavior` and MUST NOT be
presented as Bing compatibility.

Open clause `BING-V1-BYTES-2`: exact accepted physical line endings and final
unterminated-line behavior require documented or tester evidence, or an
explicit project behavior.

No Bing body-size, line-size, or truncation limit is currently accepted. The
library MUST impose a documented safety ceiling before release, but that
ceiling is project behavior unless Bing evidence establishes a compatibility
limit. It MUST NOT be copied from Google, Yandex, or RFC 9309 and labeled Bing.

### 6.2 Product token

`product_token` is a robots product token, not a complete HTTP User-Agent.
The library does not extract a token from an HTTP header and does not apply
arbitrary substring matching.

An empty token and every token outside the accepted v1 profile set return
`unsupported_profile` with no access decision.

### 6.3 Request target

`request_target` is the original HTTP request-target representation used by
the core:

- it begins with `/`;
- it includes a query string when present; and
- it excludes a fragment.

An empty target or one that does not begin with `/` returns
`invalid_request_target` with no access decision. Absolute URLs are invalid at
this layer.

The core MUST NOT silently percent-decode, Unicode-normalize, resolve dot
segments, case-fold paths, strip query data, or apply an absolute-URL parser.

Open clause `BING-V1-TARGET-1`: exact percent, Unicode, reserved-character,
query, and fragment-transport behavior remains outside the Bing compatibility
claim until accepted expectations resolve it. The initial deterministic core
may use byte-transparent project behavior, but that choice requires owner
approval in this spec.

## 7. Parser and group model

The parser architecture MUST keep these stages independently testable:

```text
physical line scanner
  -> directive lexer
  -> parser/group IR
  -> profile selector
  -> access matcher
  -> winner selector
  -> owning result and metadata
```

This is an architectural separation, not reuse of Yandex semantics.

Canonical directive names for the target v1 surface are:

| Directive | Public effect |
| --- | --- |
| `User-agent` | Starts or extends crawler selection context. |
| `Allow` | Candidate access rule. |
| `Disallow` | Candidate access rule. |
| `Sitemap` | Immutable metadata; never changes access matching. |
| `Crawl-delay` | Immutable metadata; never changes access matching in this library. |

The parser MUST expose project-authored diagnostics with stable codes and
one-based physical line/byte-column locations. Diagnostic wording is owning
text but is not a reproduction of the Bing tester UI and is not stable before
1.0.

Unknown directives MAY produce diagnostics. They do not become semantic
metadata in v1 without an approved use case. Parsing an unknown or malformed
record MUST NOT silently borrow Google or Yandex recovery.

Open clause `BING-V1-PARSE-1`: blank lines, stacked User-agent fields,
repeated groups, orphan rules, name casing, comments, whitespace, missing
colons, missing leading slash, empty values, and malformed recovery require
accepted expectations or explicit project behavior.

Open clause `BING-V1-PARSE-2`: whether `Sitemap`, `Crawl-delay`, and unknown
records terminate or otherwise affect groups must be resolved. Metadata MUST
remain noninterfering with access matching unless Bing evidence requires a
different parse boundary.

## 8. Access matching and winner selection

Current Bing help documents `Allow`, `Disallow`, and wildcard use. The 2008
historical Microsoft/Google/Yahoo post described longest-rule selection,
`Allow` used with `Disallow`, `*`, and terminal `$`. RFC 9309 separately
defines longest-octet matching and Allow preference on an equal match.

These inputs define hypotheses, not a complete accepted Bing matcher.

Open clause `BING-V1-MATCH-1`: accepted expectations must resolve ordinary
prefix matching, implicit suffix behavior, `*`, terminal `$`, query matching,
and literal/escaped metacharacters.

Open clause `BING-V1-MATCH-2`: accepted expectations must discriminate winner
specificity, including wildcard contribution, terminal-anchor contribution,
equal Allow/Disallow ties in both source orders, and duplicate rules.

Open clause `BING-V1-MATCH-3`: a binary tester allow does not by itself prove
whether a particular Allow rule won or no rule matched. `matched_rule` may be
populated only when the tester displays it or the complete accepted semantics
and fixture identify it unambiguously.

No URL or rule normalization from `robotstxt-cpp` may be inherited unless the
same behavior independently enters the Bing evidence profile.

## 9. Metadata

### 9.1 Sitemap

`SitemapEntry` preserves at least:

```cpp
struct SitemapEntry {
  std::string value;
  std::size_t line;
};
```

Entries preserve source order. The library does not fetch, validate, resolve,
canonicalize, or deduplicate sitemap URLs.

Open clause `BING-V1-META-1`: canonical placement, name casing, whitespace,
duplicates, empty values, malformed values, and interaction with group parsing
must be bounded before release.

### 9.2 Crawl-delay

`CrawlDelayEntry` preserves at least:

```cpp
struct CrawlDelayEntry {
  std::string raw_value;
  std::optional<unsigned int> seconds;
  std::size_t line;
};
```

Current Bingbot help describes integer intervals from 1 through 20 seconds.
The optional parsed value is present only for a canonical accepted form in
that range. The raw value and source line remain available even when the
semantic value is absent.

The library does not select a crawl schedule, sleep, rate-limit, combine
values, or enforce requests per interval.

Open clause `BING-V1-META-2`: numeric syntax, whitespace, duplicate values,
group association, out-of-range values, diagnostics, and whether the AdIdxBot
profile shares Bingbot's documented range require accepted boundaries. Until
then, the 1-through-20 semantic claim applies only to Bingbot.

## 10. Bing tester calibration

No semantic matrix may be promoted before a calibration run establishes the
tester transport and observation boundary on an approved neutral property.

The operator must record:

- authentication state without retaining credentials or private account data;
- selected neutral property and authorization basis;
- exact staged body representation and body hash;
- submitted full URL and the value visible after staging;
- scheme, host, and property restrictions;
- query, percent, Unicode, and fragment serialization;
- exact visible crawler labels;
- analyzer completion, diagnostics, rejection, and timeout states;
- allow/deny rendering and displayed winning-rule behavior;
- whether the UI mutates body, URL, profile, or scroll/tab state; and
- timestamps and screenshots scrubbed of account data.

Tester client rejection, transport normalization, analyzer rejection,
timeout, and evaluated allow/deny are distinct terminal states. None may be
coerced into another.

The first calibration body and targets should use unique, ordinary ASCII path
prefixes and isolate:

- a default allow;
- one definite Disallow;
- one nested Allow candidate;
- distinct Bingbot and AdIdxBot sections; and
- an ordinary query control.

Calibration is observation infrastructure, not a release expectation by
itself.

## 11. Bounded v1 probe program

After calibration, freeze minimal-pair units in this order:

1. crawler selection: exact Bingbot and AdIdxBot, wildcard fallback,
   specific-versus-generic behavior, stacked agents, repeated groups, ASCII
   casing, and historical `msnbot`/`BingAdsBot` controls;
2. ordinary access: prefix match, no-match default, root, path plus query;
3. special matching: `*`, terminal `$`, longest/specific winner, equal
   Allow/Disallow in both orders, and duplicate winners;
4. parser recovery: comments, blank boundaries, directive-name case, empty
   values, orphan rules, missing colon, representative whitespace, unknown
   records, and metadata noninterference;
5. target transport: reserved/unreserved percent forms, raw/encoded Unicode,
   query serialization, dot segments, and fragments; and
6. metadata: canonical Sitemap, canonical Bingbot Crawl-delay 1 and 20,
   out-of-range controls, duplicates, and access noninterference.

Large bodies, line limits, arbitrary malformed bytes, and exhaustive recovery
belong after ordinary transport and matcher semantics. They enter v1 only if
the reviewed release boundary requires them.

Every unit must contain controls that distinguish a genuine matcher result
from a broken submission or stale UI result. Google and RFC predictions are
frozen only after the Bing question and exact fixture are defined.

## 12. Offline corpus and conformance

The repository must separate:

```text
evidence/sources/       dated source records and durable paraphrases
corpus/bodies/          exact body fixtures
corpus/plans/           frozen questions and submissions
corpus/observations/    append-only raw/reviewed tester records
corpus/expectations/    reviewed candidate/accepted/superseded outcomes
corpus/project_behavior/  explicit non-Bing byte and API behavior
docs/                   adjudications, differentials, release inventories
```

Schemas and their documentation MUST be mechanically synchronized. A release
revision record MUST identify exact accepted expectation IDs and hashes. Live
corpus inventory and frozen release inventory are distinct artifacts.

The normal offline verify gate must cover at least:

- build and unit tests;
- installed-package downstream consumer;
- accepted expectation execution;
- corpus and schema validation;
- deterministic repeated evaluation;
- concurrent read-only evaluation;
- adversarial and fuzz smoke tests;
- source, license, and provenance audits;
- exported-package audit; and
- repository-safety checks that reject secrets, browser profiles, raw account
  data, oversized accidental blobs, and generated build outputs.

## 13. Release gate

`robotstxtbing` 0.1.0 may ship only when:

- the owner has approved this complete v1 contract;
- all release-blocking open clauses have accepted dispositions;
- every Bing compatibility behavior is documented or backed by an accepted
  tester expectation;
- every tester-unobservable behavior is unsupported, deferred, or named
  `project_behavior`;
- the two target profiles have independent selection and matcher coverage;
- no historical alias or unexposed crawler is accidentally accepted;
- diagnostics and metadata cannot be confused with an access verdict;
- the frozen release inventory is immutable and complete;
- the offline verify, install, consumer, corpus, provenance, and safety gates
  pass; and
- the release notes state the evidence cutoff and exact nonclaims.

The release claim is bounded tester/document compatibility, not production-
crawler parity.

## 14. robotstxtr integration

The accepted `robotstxtr.engine-aware/v1` contract keeps neutral acquisition,
policy ruleset, matcher backend, product token, and HTTP User-Agent separate.
Those separations remain correct.

Its current matcher outcome set cannot represent `unsupported_profile`
separately from an evaluated default allow or generic input error. Therefore:

- the Bing backend remains `capability_unavailable` in robotstxtr v1;
- Google remains the only current matcher and there is no Bing-to-Google
  fallback;
- Bing fetch/status policy remains `documentation_gap` even after a matcher
  exists; and
- integration requires `robotstxtr.engine-aware/v2` or an explicitly approved
  revised schema that preserves the result distinctions in section 5.3.

The later adapter must pin a released `robotstxtbing` revision and compatibility
range, preserve the product-token versus HTTP-User-Agent boundary, convert an
absolute HTTP(S) URL to a request target through an explicit tested layer, and
carry corpus/provenance/end-to-end gates.

Matcher availability does not authorize relabeling RFC status behavior as
Bing policy.

## 15. Review register

These clauses block implementation issue creation unless their disposition is
explicitly deferred from v1:

| Clause | Review question | Required disposition |
| --- | --- | --- |
| `BING-V1-PROFILE-1` | Exact group selection and fallback for both profiles | Accepted expectations or narrower profile |
| `BING-V1-PROFILE-2` | Tester label versus public AdIdxBot spelling | Calibrated mapping |
| `BING-V1-RESULT-1` | Empty directive result attribution | Accepted behavior, explicit project behavior, or deferral |
| `BING-V1-BYTES-1` | Unpreservable and invalid body bytes | Explicit safe project contract |
| `BING-V1-BYTES-2` | Physical line boundaries | Accepted behavior or explicit project contract |
| `BING-V1-TARGET-1` | Target normalization and byte transparency | Accepted behavior or explicit project contract |
| `BING-V1-PARSE-1` | Canonical grouping and representative recovery | Accepted bounded parser profile |
| `BING-V1-PARSE-2` | Metadata/unknown-record group interaction | Accepted behavior or explicit project contract |
| `BING-V1-MATCH-1` | Pattern language | Accepted bounded matcher profile |
| `BING-V1-MATCH-2` | Specificity and ties | Accepted winner model |
| `BING-V1-MATCH-3` | Winning-rule attribution | Evidence-safe reporting rule |
| `BING-V1-META-1` | Sitemap parsing boundary | Accepted canonical subset |
| `BING-V1-META-2` | Crawl-delay parsing and profile association | Accepted canonical subset |

Owner review should also confirm the proposed API spelling, Apache-2.0 license,
0.1 ABI nonpromise, and whether a project safety ceiling belongs in the first
release even if no Bing-compatible size limit is claimed.

## 16. Spec-to-issue transformation

After this document is approved, implementation work is generated as atomic
FP issues rather than a markdown checklist. The issue graph should separate:

- repository/toolchain/package foundation;
- evidence schemas, source inventory, and calibration harness;
- calibrated observations and expectation adjudication;
- scanner, lexer, IR, profile selection, matcher, and winner selection;
- owning public API, diagnostics, and metadata;
- conformance, adversarial, fuzz, concurrency, and consumer gates;
- provenance, license, release inventory, and package audit; and
- robotstxtr v2 contract and adapter work, dependent on a released core.

Dependencies must follow evidence promotion before compatibility
implementation, core release before adapter activation, and schema approval
before consumer integration. No implementation issue is authorized merely by
the presence of a plausible draft clause here.
