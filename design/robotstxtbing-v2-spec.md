# robotstxtbing compatibility contract v2

- Status: **architecture-complete draft for owner and evidence review; not
  implementation-authorizing**
- Contract ID: `robotstxtbing.compatibility/v2`
- Draft revision: `2026-07-17.2`
- Evidence cutoff: 2026-07-17
- Supersedes: [`robotstxtbing-v1-spec.md`](robotstxtbing-v1-spec.md)
- Product-boundary decision: FP `ROBO-rvnkadzd`
- Specification review: FP `ROBO-jeeycsyh`
- Intended first release: `robotstxtbing` 0.1.0

This document replaces the v1 draft as the implementation contract under
review. V1 correctly protected the evidence boundary, but left engineering
choices and empirical Bing questions in one open-clause register. V2 resolves
the engineering architecture. The remaining gates in section 17 are exact
evidence slots: observations may fill them, narrow the claimed profile, or
remove a feature, but may not silently redesign the API or parser.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**
describe the project contract. They are Bing claims only where an expectation
or source identified in a frozen release manifest gives them a Bing evidence
grade.

## 1. Critical review of v1

V2 resolves these material defects in the v1 draft:

| V1 defect | V2 disposition |
| --- | --- |
| Architecture, project fallbacks, and unknown Bing semantics were all “open clauses.” | Sections 3–16 freeze architecture and project behavior. Section 17 contains evidence gates only. |
| A public profile name was conflated with robots group tokens and historical aliases. | Section 8 separates evaluator profile identity, accepted API spelling, tester label, and ordered group-selection tiers. |
| `ParseResult` could not report a safety-limit rejection and promised a policy for every input. | Parsing is all-or-nothing with an explicit `ParseStatus`; no partial policy is exposed. |
| Three independent optionals in `EvaluationResult` admitted contradictory states, and decision source was coupled to original rule type. | An evaluation status guards one optional `Decision`; source `rule` is separate from the preserved Allow/Disallow rule type. |
| Resource ceilings and exhaustion behavior were release blockers but had no values or truthful outcomes. | Section 7 freezes byte, record, rule, target, and matching-work ceilings as project behavior. |
| Parser recovery was a list of questions rather than a grammar and state machine. | Section 9 defines the scanner, lexer, record classification, grouping state, and malformed-record behavior. |
| Metadata was called immutable but its scope, validity, duplicate behavior, and relation to groups were undefined. | Section 11 defines global Sitemap entries and group-associated Crawl-delay observations without scheduler semantics. |
| Winning-rule reporting was made conditional on what the tester UI displays. | Section 10 separates access-decision evidence from deterministic project reporting among equivalent duplicate winners. |
| The evidence corpus layout existed, but the relationship between live evidence, compiled semantics, and a release was unspecified. | Section 5 makes the frozen release manifest the sole bridge; runtime behavior never reads mutable evidence files. |
| The robotstxtr adapter requirement named “v2” without defining status and revision mappings. | Section 16 freezes the required adapter boundary and lossless outcome mapping. |
| Several normative `MAY` clauses left implementers to choose behavior. | V2 either chooses one behavior or marks the matter as a release evidence slot with only narrow/drop dispositions. |

The v1 evidence policy, clean-room boundary, and refusal to claim fetch or
production-crawler equivalence remain sound and are retained.

## 2. Product and claim boundary

`robotstxtbing` is an independent, unofficial, clean-room C++17 library that:

- parses a caller-supplied in-memory `robots.txt` byte sequence;
- evaluates an origin-form HTTP request target under an identified built-in
  Bing crawler profile;
- reports an owning decision and matched source rule;
- exposes immutable Sitemap and Crawl-delay observations; and
- performs no I/O and owns no fetch, cache, or scheduling policy.

The library has three contract layers:

1. **Engineering contract** — API, ownership, limits, deterministic parser
   mechanics, errors, packaging, and concurrency. These are project choices.
2. **Semantic profile revision** — exact record acceptance, group selection,
   pattern language, and winner behavior for `Bingbot` and `AdIdxBot`. Every
   compatibility-affecting cell is backed by accepted evidence.
3. **Release manifest** — immutable IDs and hashes selecting the exact source
   records, expectations, project-behavior vectors, contract revision, and
   semantic profile revisions shipped in one library release.

The project may claim only bounded tester/document compatibility. It MUST NOT
claim complete production-crawler equivalence. The July 2020 Microsoft
statement that the then-current tester used the production parser is dated
corroboration, not proof of current transport, fetch, caching, scheduling, or
unexposed crawler behavior.

### 2.1 Non-goals

The core does not own or perform:

- retrieval of `/robots.txt` or absolute-URL parsing;
- HTTP status, redirect, DNS, network, TLS, cache, or last-known-good policy;
- SSRF or HTTPS-downgrade enforcement;
- HTTP User-Agent parsing, bot authentication, or crawler detection;
- Crawl-delay selection, combination, sleeping, rate limiting, or scheduling;
- sitemap fetching, validation, resolution, or deduplication;
- Unicode normalization, percent decoding, dot-segment removal, or URL
  canonicalization;
- generic RFC 9309 validation or a selectable Google/RFC/Yandex mode; or
- runtime plugins, runtime profile files, or mutable evidence loading.

## 3. Repository, build, and dependency contract

The names and baseline are frozen:

```text
repository:          robotstxtbing
CMake package:       robotstxtbing
installed target:    robotstxtbing::robotstxtbing
C++ namespace:       robotstxtbing
language baseline:   C++17
license:             Apache-2.0
runtime dependency:  C++17 standard library only
```

The library is compiled, not header-only. The build MUST support static and
shared variants through the ordinary CMake `BUILD_SHARED_LIBS` choice, use an
export macro for shared-library symbols, and install self-contained public
headers plus relocatable CMake package configuration. A downstream consumer
gate MUST configure against the installed package and target.

Exceptions and the standard allocator are part of the 0.1 source contract.
The library does not require RTTI. Allocation and standard container size
failures propagate as standard exceptions; syntax errors and configured
resource-limit outcomes do not throw.

The 0.x line promises source and semantic compatibility only within the exact
contract and profile revisions advertised by the release. No public ABI
stability is promised before 1.0. Public symbols use `robotstxtbing` directly;
there is no inline ABI namespace in 0.x.

`robotstxt-cpp` is a pinned comparative baseline only. It MUST NOT be linked,
wrapped, copied, or used to generate Bing expected outcomes. Patterns and
processes from `robotstxtyandex` may inform repository tooling, but its code and
accepted semantics are not Bing evidence or implementation input.

`robotstxtr` may consume only a pinned released archive or vendored release
snapshot with recorded provenance. It MUST NOT fetch the sibling repository at
R package build or runtime.

## 4. Evidence contract

### 4.1 Grades and lifecycle

Every behavioral expectation has exactly one grade:

| Grade | Meaning |
| --- | --- |
| `documented` | A dated Bing or Microsoft primary source directly supports the exact expectation. |
| `tester_observed` | Accepted, dated Bing Webmaster Tools tester observations support the exact expectation. |
| `project_behavior` | The project deliberately chooses deterministic behavior where Bing evidence is unavailable or inapplicable. |

RFC 9309 predictions and pinned-Google results are separately labelled
comparisons and never behavioral grades.

Raw observations progress through:

```text
planned -> staged -> submitted -> terminal -> independently_reviewed
```

Reviewed expectations progress through:

```text
candidate -> accepted -> superseded
```

Raw observations are append-only. A contradiction adds an observation and
supersedes an expectation; it never rewrites history.

### 4.2 Promotion threshold

A documented matcher expectation MUST cite a dated primary source and bind an
exact body hash, public profile, and request-target fixture. A tester-observed
expectation normally requires an exact retained fixture, terminal result,
independent transcription review, two concordant observations preferably on
different dates, and no unresolved transport ambiguity. An owner-approved
exception records its weaker basis and rationale.

Editable tester results cannot establish fetch, status, redirect, cache, or
scheduler behavior. Production claims in those areas require a current,
behavior-specific Microsoft source and remain outside this library regardless.

### 4.3 Current documentation boundary

The source inventory accessed on 2026-07-17 supports a bounded starting set:

- the current tester offers `Bingbot` and UI label `AdIdxbot`, evaluates a URL
  against editor content, and can identify a blocking statement;
- current authoring help says a Bingbot-specific section replaces the generic
  section, recommends ASCII or UTF-8, and documents canonical User-agent,
  Allow, Disallow, wildcard, Sitemap, and Crawl-delay authoring;
- current crawler help lists crawler identity `AdIdxBot` for Bing Ads; and
- current Bingbot help documents Crawl-delay windows from 1 through 20 seconds.

The 2008 joint REP post and 2012 Bingbot post are historical evidence for
probe hypotheses including longest rule, `*`, terminal `$`, and the
`bingbot`/`msnbot`/`*` priority. They do not silently become current semantic
profile cells. The 2020 tester post's `BingAdsBot` and the current UI's
`AdIdxbot` are recorded identities, not automatic robots-token aliases.

## 5. Revision and release-manifest model

`version.h` MUST expose non-owning views into static storage for:

```cpp
struct ContractInfo {
  std::string_view library_version;
  std::string_view contract_id;
  std::string_view contract_revision;
  std::string_view parser_revision;
  std::string_view bingbot_profile_revision;
  std::string_view adidxbot_profile_revision;
  std::string_view release_manifest_sha256;
};

const ContractInfo& contract_info() noexcept;
```

The release manifest is committed, immutable for a tag, and mechanically
validated. It contains:

- every `ContractInfo` field above except `release_manifest_sha256`, plus the
  evidence cutoff;
- every accepted expectation ID, grade, source/observation references, and
  content hash;
- every project-behavior vector ID and hash;
- schema versions and corpus inventory hash;
- compiler/package provenance and license inventory references; and
- explicit compatibility nonclaims.

`release_manifest_sha256` is computed over the finalized canonical manifest
bytes, which do not contain that hash. The digest is then compiled into
`ContractInfo`; there is no self-referential manifest field.

Runtime code MUST NOT parse corpus or manifest files. The selected semantics
are compiled into the library and tested against the manifest. Changing any
compatibility-affecting behavior requires a new profile revision; changing a
public result shape, limit outcome, or grammar contract requires a new contract
revision. A new corpus observation alone changes neither.

## 6. Public C++ API

### 6.1 Headers

```cpp
#include <robotstxtbing/diagnostic.h>
#include <robotstxtbing/limits.h>
#include <robotstxtbing/metadata.h>
#include <robotstxtbing/policy.h>
#include <robotstxtbing/result.h>
#include <robotstxtbing/version.h>
```

Every public header MUST compile by itself. Public enums have an explicitly
documented closed value set for a contract revision.

### 6.2 Policy and parse result

```cpp
namespace robotstxtbing {

enum class ParseStatus {
  parsed,
  body_limit_exceeded,
  line_length_limit_exceeded,
  record_limit_exceeded,
  rule_limit_exceeded,
};

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
  ParseStatus status;
  std::optional<Policy> policy;
  std::vector<Diagnostic> diagnostics;
};

}  // namespace robotstxtbing
```

There is no public default constructor for `Policy`. `parsed` has a policy;
every other parse status has no policy and exactly one limit diagnostic,
emitted last. Diagnostics from completely classified earlier lines remain,
except `body_limit_exceeded` is checked before scanning and therefore has no
preceding diagnostics. Syntax and encoding irregularities do not fail parsing;
they produce a usable policy with stable diagnostics and deterministic
recovery. The parser never exposes a truncated or partially usable policy.

`Policy` owns or shares immutable storage and retains no caller view. Copy and
move operations are `noexcept`. A moved-from object may be destroyed or
assigned; other operations on it are outside the contract. References returned
by metadata accessors remain valid until that policy object is destroyed or
assigned.

### 6.3 Evaluation result

```cpp
enum class EvaluationStatus {
  evaluated,
  invalid_request_target,
  unsupported_profile,
  request_target_limit_exceeded,
  work_limit_exceeded,
};

enum class AccessDecision { allow, disallow };
enum class DecisionSource { rule, default_allow };
enum class RuleType { allow, disallow };

struct RuleMatch {
  RuleType type;
  std::string value;
  std::size_t line;
};

struct Decision {
  AccessDecision access;
  DecisionSource source;
  std::optional<RuleMatch> matched_rule;
};

struct EvaluationResult {
  EvaluationStatus status;
  std::optional<Decision> decision;
};
```

The only valid shapes are:

| Status | Decision payload |
| --- | --- |
| `evaluated` | present and one of the two rows below |
| any other status | absent |

| Source | Access | Matched rule |
| --- | --- | --- |
| `rule` | `allow` or `disallow` as defined by the profile | present with original type and value |
| `default_allow` | `allow` | absent |

An effective empty rule, if an accepted profile assigns one access meaning,
is reported with its original rule type, empty value, and source line. The
`rule` source deliberately does not derive access from the field name:
this can represent an empty Disallow that has an effective allow outcome
without fabricating an Allow record. No rejected, unsupported, or
resource-limited evaluation becomes default allow.

`Evaluate` copies any returned rule value and retains neither input view.
Apart from standard allocation/size exceptions while creating owning output,
it reports failures through `EvaluationStatus`.

## 7. Fixed safety and complexity limits

These 0.1 values are explicit `project_behavior`, not Bing limits:

```text
maximum body bytes:              2,097,152
maximum physical line bytes:        65,536
maximum classified records:         65,536
maximum retained access rules:      16,384
maximum request-target bytes:        65,536
maximum matcher work units:      67,108,864
```

`limits.h` exposes these as `inline constexpr std::size_t` values. A physical
line limit counts payload bytes excluding LF or CRLF. Classified records are
recognized, unknown, and malformed nonblank/noncomment lines. Access-rule
count includes retained empty, malformed-known, and orphan access records even
though an orphan can never become a matching candidate.

Limits are checked before committing the item that exceeds them. Parse checks
the body limit before scanning, the physical-line limit while scanning, and
then record before rule count for each source line. The first exceeded limit is
the terminal parse status. A parse-limit outcome returns no policy; evaluation
limits return no decision. There is no prefix truncation, fail-open conversion,
or partial winner. Boundary vectors at limit minus one, limit, and limit plus
one are release-gating.

Matcher work is an input-derived budget, not a count of implementation
instructions. Before matching, each candidate rule costs its parsed pattern
byte length plus the request-target byte length plus one. Costs are summed in
source order with checked arithmetic. A total at the maximum is permitted; a
larger total returns `work_limit_exceeded` before any rule is evaluated. This
makes the public outcome invariant under safe matcher optimizations.

Candidate membership is determined by the selected frozen semantic-profile
revision: group selection, record eligibility, and active pattern primitives
are applied before the budget is calculated. Consequently the same body and
target may have a different work outcome under different profile revisions,
but the result is deterministic within the revision published by
`contract_info()`.

These limits bound the core only. A fetcher may impose a smaller acquisition
limit, but the adapter must report that as acquisition policy rather than a
Bing matcher result.

## 8. Profiles, labels, and group-selection tiers

Four concepts MUST remain distinct:

| Concept | Example | Meaning |
| --- | --- | --- |
| Public profile | `Bingbot` | Finite evaluator behavior selected by the caller. |
| Accepted API spelling | `bingbot`, `BINGBOT` | Locale-independent ASCII-case variants resolving to the same public profile. |
| Tester UI label | `Bingbot`, `AdIdxbot` | Recorded UI selection used to collect evidence. It is not parsed as a robots field. |
| Group token/tier | `bingbot`, possibly `msnbot`, `*` | `User-agent` field value considered within one profile's selection algorithm. |

Version 0.1 supports exactly public profiles `Bingbot` and `AdIdxBot`.
`product_token` is resolved by locale-independent ASCII case folding against
exact complete tokens `bingbot` and `adidxbot`. Empty, affixed, historical, or
other strings return `unsupported_profile`. In particular, `msnbot` and
`BingAdsBot` are not public API aliases.

The canonical profile spelling is for API and reporting; the `AdIdxbot` UI
label is mapped in evidence records to public profile `AdIdxBot`. That mapping
does not assert that the label is a robots product token.

Each frozen semantic profile revision contains an ordered group-selection
table with exactly:

- accepted complete group tokens at each tier;
- token comparison rule;
- whether all groups at the chosen tier merge or only one contributes;
- whether stacked User-agent declarations share following access records;
- whether and when wildcard groups are a fallback; and
- the outcome when no tier is present.

No generic “most specific token” algorithm, substring matching, or implicit
cross-profile fallback exists. The exact two tables are release evidence slots
in section 17. Parser structure supports multiple groups and stacked agents,
but the tables alone determine which retained access records are candidates.

## 9. Scanner, lexer, and parser IR

The implementation keeps these internal stages independently testable:

```text
physical byte scanner
  -> line lexer and record classifier
  -> loss-preserving parser/group IR
  -> built-in profile selector
  -> pattern compiler and matcher
  -> winner selector
  -> owning public decision and metadata
```

The IR is private and may change without source compatibility, but it MUST
retain physical order, original parsed value bytes, source locations, group
identity, and record classification needed by the frozen semantic profiles.

### 9.1 Physical lines and opaque bytes

The body is an opaque, length-aware byte sequence:

- scanning searches for LF (`0A`);
- CR immediately before LF forms one CRLF terminator;
- terminator bytes are excluded from line payload;
- bare CR, NUL, a UTF-8 BOM, invalid UTF-8, and every other byte remain payload;
- the parser never decodes, validates, replaces, or normalizes Unicode and
  never strips a BOM;
- an empty body has zero lines;
- a terminal line ending creates no synthetic extra line;
- consecutive endings create intervening empty lines; and
- a nonempty final suffix is a final unterminated line.

Lines, byte columns, and absolute byte offsets are one-based, one-based, and
zero-based respectively. These rules are project behavior because the tester
editor cannot establish arbitrary byte identity.

### 9.2 Lexical grammar

Only ASCII space (`20`) and horizontal tab (`09`) are optional whitespace.
After removing a comment beginning at the first `#` byte, a nonblank line is
classified using:

```text
OWS field-name OWS ":" OWS field-value OWS
```

Trailing OWS is removed from the parsed value; other value bytes are retained.
Field names use locale-independent ASCII case folding and must exactly equal
`user-agent`, `allow`, `disallow`, `sitemap`, or `crawl-delay`. A missing colon,
empty field name, unknown field, or non-ASCII name is classified and diagnosed
but has no access or metadata effect in contract v2. Evidence that Bing accepts
one of these forms may justify a later parser revision; it does not mutate this
grammar implicitly.

This project grammar deliberately does not accept arbitrary Unicode space,
vertical whitespace, prefix/suffix field-name matching, multiple fields per
line, or backslash escapes.

First-`#` comment removal is frozen project grammar, including when `#` occurs
mid-value; a literal hash must be represented by other bytes such as `%23`.
The parser-recovery evidence gate may support or narrow a Bing compatibility
claim for exact comment fixtures, but cannot change this tokenization within
contract v2. Contrary Bing evidence requires an explicit later parser revision
or a compatibility nonclaim.

### 9.3 Access grouping

Grouping uses only recognized User-agent, Allow, and Disallow records.
Sitemap, Crawl-delay, unknown, malformed, blank, and comment-only records
cannot start, end, merge, or split an access group.

The state machine is:

1. A nonempty recognized User-agent starts a group when none is open.
2. Consecutive recognized User-agent records before the first retained access
   record stack in that group.
3. Once a retained Allow or Disallow record has occurred, the next recognized
   User-agent starts a new group.
4. A recognized access record with no open nonempty User-agent group is orphan
   data: it is retained for diagnostics but never a matching candidate.
5. Blank lines and comments have no grouping effect.
6. Repeated tokens and repeated groups remain distinct in source order; the
   selected profile table decides contribution and merging.

An access value beginning with `/` is canonical. Empty values and nonempty
values without leading `/` are retained as classified records so evidence can
define their exact profile effect. Until accepted, they are inert
project-behavior records and generate diagnostics. Missing-colon and unknown
records are not eligible for later semantic reinterpretation in 0.1.

## 10. Pattern matching, winners, and attribution

The matcher is byte-oriented, iterative, and nonrecursive. It MUST NOT use
`std::regex`, locale collation, URL libraries, Unicode libraries, percent
decoding, or a backtracking matcher.

For the literal/`*`/terminal-`$` language, matching one candidate rule MUST
take worst-case `O(pattern_bytes + request_target_bytes)` time. Pattern
compilation MAY use `O(pattern_bytes)` immutable policy storage; evaluation
uses `O(1)` matcher scratch space per rule apart from the owning returned
result. The abstract additive budget in section 7 is therefore an upper bound
on asymptotic matching work, not merely an input-size label. Adversarial cases
with many stars, long near-matches, and a late failing literal MUST gate the
complexity claim.

The supported internal pattern primitives are literal bytes, `*`, and a
terminal `$`. A semantic profile revision freezes:

- ordinary prefix and implicit-suffix behavior;
- whether each primitive is active and how nonterminal `$` is treated;
- query matching and literal/encoded metacharacter behavior;
- the exact specificity measure;
- Allow-versus-Disallow behavior at equal specificity; and
- the access effect of retained empty and missing-leading-slash records.

Only accepted profile cells may activate matching behavior. Google or RFC
normalization and winner rules are never defaults. A retained rule that uses a
primitive or noncanonical record class not active in the selected profile is
inert for that evaluation; it is not reinterpreted as a literal or another
rule. Inert rules are excluded from the abstract work budget.

After semantic comparison identifies multiple completely equivalent winners
with the same rule type, parsed value, specificity, and access outcome, the
earliest physical line is returned as `matched_rule`. This final attribution is
deterministic `project_behavior`; it does not claim the Bing UI chose that
duplicate. If Allow and Disallow tie or patterns differ, the profile's accepted
winner rule resolves the decision before this reporting tie-break applies.

The tester need not display a winning line for the library to report its own
winner. Evidence must establish the access semantics; the compiled algorithm
and earliest-equivalent reporting rule establish the owning `RuleMatch`.

## 11. Metadata contract

Metadata is parsed in parallel with access grouping and never changes an
access group or access decision.

### 11.1 Sitemap

```cpp
struct SitemapEntry {
  std::string value;
  std::size_t line;
};
```

A recognized `Sitemap` with a nonempty parsed value produces one global entry
wherever it occurs. Entries preserve source order and duplicates. Empty values
are diagnosed and omitted because `SitemapEntry` represents only a usable
opaque location and has no validity-status field. Values are opaque bytes; the
library does not parse, resolve, validate, canonicalize, fetch, or deduplicate
URLs. This canonical subset is project parser behavior backed as a Bing
compatibility claim only by the dated source mapped in the release manifest.

### 11.2 Crawl-delay

```cpp
enum class CrawlDelayValueStatus { parsed, empty, invalid, overflow };

struct AgentReference {
  std::string value;
  std::size_t line;
};

struct CrawlDelayEntry {
  std::string raw_value;
  std::optional<std::uint32_t> seconds;
  CrawlDelayValueStatus value_status;
  std::vector<AgentReference> group_agents;
  std::size_t line;
};
```

Every recognized Crawl-delay record produces one entry. `raw_value` is the
parsed value after lexical OWS/comment handling. `parsed` requires one or more
ASCII decimal digits and a value representable by `uint32_t`; leading zeroes
are accepted and preserved only in `raw_value`. Signs, decimal points,
exponents, internal whitespace, and other bytes are invalid.

`group_agents` contains the final stacked User-agent declarations of the open
access group with their source spelling and lines. It is empty for an unscoped
record. Because access grouping ignores metadata, a Crawl-delay between stacked
User-agent records is associated with the final group without changing it.
The parser therefore resolves and stores `group_agents` when that access group
closes or at end of input, rather than permanently snapshotting the agents when
the Crawl-delay line is first classified.

The parser preserves duplicates, invalid values, zero, and values above 20.
Unlike Sitemap, Crawl-delay retains empty and invalid entries because its public
value has an explicit status and exists to preserve scheduling metadata without
selecting or enforcing it.
The documented Bingbot range of 1 through 20 is evidence metadata, not parser
validity and not scheduler enforcement. The library does not select an
effective value or claim that AdIdxBot shares Bingbot scheduling behavior.

## 12. Diagnostics

```cpp
enum class DiagnosticSeverity { note, warning };

enum class DiagnosticCode {
  unknown_directive,
  missing_colon,
  empty_field_name,
  non_ascii_field_name,
  empty_user_agent,
  orphan_access_rule,
  empty_access_rule,
  access_value_missing_slash,
  empty_sitemap,
  empty_crawl_delay,
  invalid_crawl_delay,
  crawl_delay_overflow,
  body_limit_exceeded,
  line_length_limit_exceeded,
  record_limit_exceeded,
  rule_limit_exceeded,
};

struct SourceLocation {
  std::size_t line;
  std::size_t byte_column;
  std::size_t byte_offset;
  std::size_t byte_length;
};

struct Diagnostic {
  DiagnosticCode code;
  DiagnosticSeverity severity;
  SourceLocation location;
  std::string detail;
};
```

Codes, severities, and locations are stable within contract v2. The exhaustive
severity mapping is:

| Diagnostic code | Severity |
| --- | --- |
| `unknown_directive` | `note` |
| `missing_colon` | `warning` |
| `empty_field_name` | `warning` |
| `non_ascii_field_name` | `warning` |
| `empty_user_agent` | `warning` |
| `orphan_access_rule` | `warning` |
| `empty_access_rule` | `warning` |
| `access_value_missing_slash` | `warning` |
| `empty_sitemap` | `warning` |
| `empty_crawl_delay` | `warning` |
| `invalid_crawl_delay` | `warning` |
| `crawl_delay_overflow` | `warning` |
| `body_limit_exceeded` | `warning` |
| `line_length_limit_exceeded` | `warning` |
| `record_limit_exceeded` | `warning` |
| `rule_limit_exceeded` | `warning` |

Wording is owning project text, is not copied from the tester UI, and is not
stable before 1.0. Diagnostics are explanatory and never an access verdict.

Diagnostics are emitted in physical source order without deduplication. On a
parse-limit failure, diagnostics for completely classified earlier lines are
retained and the single terminal limit diagnostic is last.

For a missing token there is a zero-length location at the byte position where
it was expected. A whole-body limit diagnostic starts at line 1, column 1,
offset 0 and spans zero bytes. Exact location vectors are release-gating.

## 13. Request-target contract

`request_target` is the original origin-form request target:

- it is nonempty and begins with `/`;
- it contains the query delimiter and query bytes when present; and
- it contains no `#` fragment delimiter.

Empty, non-slash-prefixed, or fragment-containing input returns
`invalid_request_target`. An over-limit otherwise valid target returns
`request_target_limit_exceeded`. Absolute-form URLs are invalid.

Evaluation validation order is fixed: resolve `product_token`, validate target
shape, check target size, compute the abstract work budget, then match. Thus an
unsupported profile wins over a simultaneously invalid target; an invalid
target wins over its size; and no matcher work occurs for any earlier status.

The evaluator compares the supplied bytes. It does not percent-decode,
re-encode, Unicode-normalize, case-fold, resolve dot segments, strip a query,
or parse a URL. Byte transparency is project behavior where tester transport
does not establish equivalence. Accepted expectations may describe how Bing
behaves for exact tester-preserved target forms, but cannot cause this layer to
silently transform caller input.

## 14. Determinism, concurrency, and security properties

Parsing and evaluation use no network, filesystem, clock, locale, environment,
randomness, or mutable process-global state. Identical explicit inputs under
one released revision produce equivalent statuses, decisions, matched rules,
metadata, and diagnostic codes/locations.

Concurrent read-only calls to `Evaluate`, `sitemaps`, and `crawl_delays` on the
same non-moved-from policy are safe without caller locking. The implementation
performs no lazy mutation after `Parse` returns.

All size arithmetic is checked. Scanner, parser, pattern compiler, and matcher
must be safe for every byte value and every input up to the public limits.
The matcher satisfies the worst-case time and scratch-space bounds in section
10. Fuzzing and sanitizers supplement deterministic corpus and adversarial
complexity tests but do not replace them. No diagnostic includes caller data
beyond the relevant parsed field unless the caller explicitly formats the
returned owning value.

## 15. Corpus, calibration, and offline conformance

The sibling repository uses:

```text
evidence/sources/          dated primary-source records and paraphrases
corpus/bodies/             exact byte fixtures
corpus/plans/              frozen probe questions and submission units
corpus/observations/       append-only raw/reviewed tester records
corpus/expectations/       candidate/accepted/superseded expectations
corpus/project_behavior/   non-Bing engineering vectors
releases/                  immutable release manifests
docs/                      adjudications, coverage, and differentials
```

Schemas and documentation are mechanically synchronized. Live corpus inventory
and frozen release manifest are separate artifacts.

Before semantic probes, calibration on an approved neutral property records
authentication without credentials, property authorization, exact editor body
and hash, submitted and displayed URL, scheme/host restrictions, target
serialization, visible profile labels, terminal UI states, allow/deny and
winning-statement rendering, UI mutation, timestamps, and scrubbed screenshots.
Client rejection, transport normalization, analyzer rejection, timeout, and
evaluated allow/deny are distinct outcomes.

The normal offline gate covers:

- static and shared builds plus unit tests;
- installed-package downstream consumers;
- every accepted expectation and project-behavior vector;
- schema, manifest, and hash validation;
- repeated deterministic and concurrent evaluation;
- boundary, adversarial, fuzz-smoke, and sanitizer jobs;
- exported-header/package audits;
- source, license, and provenance audits; and
- repository-safety checks rejecting secrets, browser profiles, account data,
  accidental large blobs, dependencies, and build outputs.

Live tester access is never part of normal build, CI, or release verification.

## 16. robotstxtr integration contract

`robotstxtbing` does not change the accepted separation between neutral
acquisition, fetch/status policy, matcher backend, robots product token, and
HTTP User-Agent. Bing fetch/status policy remains `documentation_gap`; matcher
availability never relabels an RFC or application policy as Bing.

The backend requires `robotstxtr.engine-aware/v2` because the current v1
matcher status cannot losslessly represent all core outcomes. The v2 matcher
status set must include:

```text
evaluated
not_needed
not_evaluated
capability_unavailable
invalid_request_target
unsupported_profile
matcher_input_limit_exceeded
matcher_work_limit_exceeded
```

The adapter maps both parse-limit and request-target-limit outcomes to
`matcher_input_limit_exceeded` with a separate stable reason and preserves the
exact sibling contract revision, semantic profile revision, configured core
limits, canonical public profile, product-token input, and optional decision.
It MUST NOT convert any absent core decision to allow or disallow.

The adapter owns absolute HTTP(S) URL parsing. It supplies `/` for an empty URL
path, appends the original encoded query including `?`, rejects fragments at
the core boundary, and neither decodes nor normalizes the derived target. The
conversion is independently tested with raw/encoded reserved bytes, Unicode,
empty path, query, and fragment cases.

The adapter pins a released archive and manifest hash, records license and
provenance, executes the sibling conformance corpus plus end-to-end facade
tests, and offers no Bing-to-Google fallback. Sitemap and Crawl-delay metadata
may be carried in a versioned evidence table, but never in fields that imply an
access decision or scheduler action.

## 17. Remaining evidence gates — no open architecture

No compatibility-implementation issue may be created until the owner approves
sections 1–16 and each row below has either an accepted exact table or the
stated narrowing disposition. Evidence, calibration, and adjudication issues
exist to close these gates and may be created after architecture approval.
These are empirical release gates, not invitations for implementer judgment.

| Gate | Exact evidence needed | If evidence remains insufficient |
| --- | --- | --- |
| `BING-V2-BINGBOT-SELECTION` | Tier tokens/order, ASCII case behavior, stacked declarations, repeated same-tier groups, wildcard fallback, no-tier outcome | Remove unproved historical tiers; if ordinary exact/wildcard selection remains unresolved, 0.1.0 remains blocked. |
| `BING-V2-ADIDX-SELECTION` | Exact AdIdxBot group token(s), case behavior, stacked/repeated groups, wildcard fallback, no-tier outcome | 0.1.0 remains blocked; never infer it from Bingbot. |
| `BING-V2-ORDINARY-MATCH` | Ordinary prefix, implicit suffix, root, no-match default, and query controls for both profiles | 0.1.0 remains blocked. |
| `BING-V2-SPECIAL-MATCH` | `*`, terminal `$`, nonterminal/literal metacharacters, and encoded controls | Disable any unproved primitive and narrow the compatibility claim; no Google/RFC default. |
| `BING-V2-WINNER` | Specificity calculation, Allow/Disallow equal ties in both orders, differing patterns, and duplicate controls | Exclude unproved special-pattern competition; unresolved ordinary winner choice blocks 0.1.0. |
| `BING-V2-EMPTY-ACCESS` | Empty Allow and Disallow effects and attribution | Keep them inert project behavior and explicitly exclude those inputs from compatibility. |
| `BING-V2-PARSER-RECOVERY` | Representative Bing-affecting behavior for blank boundaries, canonical first-`#` comments, repeated groups, name case, OWS, orphan rules, empty values, and missing slash | Comment evidence may support or narrow the compatibility claim but never changes v2 tokenization. Otherwise ship only the canonical grammar; all retained noncanonical access records stay inert project behavior. |
| `BING-V2-METADATA-NONINTERFERENCE` | Canonical Sitemap and Crawl-delay fixtures prove no access-decision interference for both profiles | Preserve metadata but exclude placement/interference claims not directly documented or observed. |

The evidence program proceeds in that table order: calibration, selection,
ordinary matching, special matching, winner isolation, empty/recovery cases,
then metadata controls. Every unit includes a positive, negative, and stale-UI
control. Comparisons to RFC 9309 and pinned Google are frozen only after the
Bing question and exact fixture are defined.

## 18. Approval and release gates

Approval of this document means the architecture is complete; it does not
claim the evidence gates or implementation are complete. After architecture
approval, evidence/calibration issues may be created. Compatibility
implementation issues may be created only after the semantic tables they use
are accepted.

`robotstxtbing` 0.1.0 may ship only when:

- the owner explicitly approves this complete v2 contract;
- all shipped profile cells are documented or backed by accepted tester
  expectations and appear in the immutable release manifest;
- every other behavior is unsupported, deferred, or identified as
  `project_behavior`;
- both target profiles have independent selection, ordinary matching, and
  winner coverage; absence of either blocks 0.1.0 unless the owner first
  approves a product-scope amendment;
- no historical alias or unexposed crawler is accidentally accepted;
- all public result, diagnostic, metadata, limit, ownership, and concurrency
  invariants pass;
- the offline build, install, consumer, corpus, manifest, provenance, license,
  sanitizer, and repository-safety gates pass; and
- release notes identify the evidence cutoff, exact revisions, supported
  profiles, project limits, and nonclaims.

The post-approval issue graph must keep evidence collection, expectation
adjudication, repository foundation, scanner/IR, profile selection, matcher,
public API/metadata, conformance/robustness, release audit, and robotstxtr v2
adapter work as atomic FP issues with evidence dependencies explicit. No
markdown task checklist substitutes for those issues, and no implementation is
authorized merely because this draft contains a plausible algorithm.

## 19. Primary-source inventory

These primary sources were accessed on 2026-07-17. Durable evidence records in
the sibling repository must preserve access dates, relevant paraphrases, and
content hashes or archived captures where licensing permits.

- [Robots.txt tester](https://www4.bing.com/webmasters/help/robots-txt-tester-623520ca)
- [How to create a robots.txt file](https://www.bing.com/webmasters/help/how-to-create-a-robots-txt-file-cb7c31ec)
- [Which crawlers does Bing use?](https://www.bing.com/webmasters/help/which-crawlers-does-bing-use-8c184ec0)
- [How to report an issue with Bingbot](https://www.bing.com/webmasters/help/how-to-report-an-issue-with-bingbot-25c19802)
- [2008 joint REP announcement](https://blogs.bing.com/webmaster/June-2008/Robots-Exclusion-Protocol-joining-together-to-pro)
- [2012 Bingbot robots guidance](https://blogs.bing.com/webmaster/May-2012/To-crawl-or-not-to-crawl%2C-that-is-BingBot-s-questi)
- [2020 robots tester announcement](https://blogs.bing.com/webmaster/september-2020/Bing-Webmaster-Tools-makes-it-easy-to-edit-and-verify-your-robots-txt)
- [2020 production-parser statement](https://blogs.bing.com/webmaster/july-2020/Announcing-the-new-Bing-Webmaster-Tools-%28migration-complete%29)
