# Product Requirements Document v3: Faithful Google robots.txt Parser for C++ and R

Version: 3
Status: implementation baseline, sliced for delivery
Date: 2026-07-10
Upstream matcher baseline: `google/robotstxt` commit
`22b355ff855419e6a3ff8ff09c0ad7fdb17116f9`
Source research: `RESEARCH.md`

Changing this immutable baseline is a deliberate product decision and requires
rerunning every fidelity gate in this document.

v3 keeps every v2 contract unchanged and reorganizes delivery around
self-contained, tracer-bullet vertical slices (§5). §6 is the normative
reference the slices cite; §7 and §8 are the slice catalogs an implementer or
subagent works from directly.

## 1. Summary

Build two related projects:

1. A standalone C++ library that is a source-minimal, standard-library-only,
   test-validated replica of Google's open-source `robotstxt` parser and
   matcher at the pinned upstream commit.
2. An R package that vendors the validated C++ library and adds deterministic
   URL-first robots.txt fetching, local-body matching, and rich results.

The core differentiator is fidelity to the pinned open-source matcher,
including its quirks. The C++ library is the fidelity layer. The R package is
the user-facing workflow and fetch-policy layer.

Public wording for v1 should be "a faithful, upstream-test-validated replica."
Do not claim universal behavioral identity with Googlebot. Googlebot has policy
outside this matcher, and the R fetch policy is intentionally conservative.

## 2. Goals

### C++ Library

- Preserve the parser and matcher behavior of `google/robotstxt` commit
  `22b355ff855419e6a3ff8ff09c0ad7fdb17116f9` as closely as practical.
- Remove Abseil and all other production dependencies outside the C++ standard
  library.
- Keep the implementation source-minimal relative to the upstream baseline.
- Preserve Google naming, namespace, file organization, and public surface
  wherever practical.
- Include all relevant upstream library surfaces: `robots.cc`, `robots.h`,
  `reporting_robots.cc`, `reporting_robots.h`.
- Validate against mechanically adapted upstream tests and a differential
  corpus built against pristine upstream source at the same SHA.
- Provide a minimal, offline-capable CMake build.

### R Package

- Provide a URL-first R interface that fetches `/robots.txt`, matches a URL,
  and returns a stable rich result.
- Provide a local/body-based path for users who already have robots.txt
  content.
- Vendor a pinned, validated snapshot of the C++ library.
- Pass the original URL string to the C++ matcher. Never pass a cleaned,
  decoded, or reserialized URL into the matcher.
- Use `rurl` as an `Imports` dependency for fetch-origin parsing and IDN
  handling.
- Use `httr2` as an `Imports` dependency for HTTP.
- Distinguish matcher decisions, default decisions, missing-file decisions,
  invalid input, and fetch failures with stable machine-readable metadata.
- Store each fetched or supplied robots.txt body once per result object and
  provide a body-preview helper.
- Be suitable for CRAN without build-time or test-time network access.

## 3. Non-Goals for V1

- Not a web crawler.
- Not a robots.txt authoring or validation tool.
- Not an RFC-corrected matcher fork. Preserve pinned Google matcher behavior
  even where disputed.
- Not a cache manager.
- Not a parallel URL audit engine.
- Not a complete replacement for the `robotstxt` or `spiderbar` ecosystem on
  day one.
- Not exact Googlebot fetch-policy parity. Matcher fidelity is the exact target;
  R fetch behavior is the explicit product policy in this document.
- No user-facing CLI.
- No multi-body vectorization in the local/body API.
- No formal performance benchmark gate unless an obvious regression appears.

## 4. Product Split

### Project 1: C++ Replica Library

> A standard-library-only, test-validated C++ replica of Google's open-source
> `robotstxt` parser and matcher at a pinned commit, preserving the upstream API
> and algorithm structure wherever practical.

The C++ library accepts a robots.txt body, user agent information, and a URL
string. It does not fetch URLs, construct origins, punycode hostnames, or fully
normalize URLs. Callers remain responsible for providing matcher input in the
format required by the upstream API.

### Project 2: R Package

> An R package that wraps the faithful C++ matcher and adds deterministic
> URL-first robots.txt fetching, robust origin construction, rich results, and
> R-friendly sequential batch workflows.

The R package computes and fetches the robots.txt URL. It passes the original
input URL element to the C++ matcher without routing that value through `rurl`.

The projects live in separate repositories. The R package vendors a copied,
SHA-pinned snapshot; it does not link to or download the C++ repository during
installation.

## 5. Delivery Model: Tracer-Bullet Vertical Slices

### 5.1 Why slices

The work is delivered as an ordered set of **vertical slices**. Each slice is a
tracer bullet: a thin cut through every layer it touches that ends in code which
**compiles or installs, runs end-to-end, and is testable and usable on its
own** — not a horizontal layer that only becomes useful once a later layer
lands. Later slices thicken earlier ones instead of replacing them.

A slice is sized so that a single implementer or subagent can pick it up with
only this document, deliver it, and prove it, without holding the rest of the
project in their head.

### 5.2 Slice contract

Every slice in §7 and §8 is written to the same template:

- **Repo** — which of the two repositories the slice lands in.
- **Tracer bullet** — the one thing that demonstrably works after the slice, as
  a command or code snippet a human can run.
- **Depends on** — the slices that must be merged first. A slice may only depend
  on slices listed here.
- **In scope / Out of scope** — the exact behavior this slice owns, and what is
  deliberately deferred to a named later slice.
- **Normative references** — the §6 subsections that fully specify the
  behavior. The slice must satisfy them for the parts in scope and must not
  silently diverge.
- **Deliverables** — files, functions, or targets produced.
- **Acceptance** — the concrete, runnable checks that gate the slice as done.

### 5.3 Rules for a subagent delivering a slice

- Read this whole section, the slice, and every §6 subsection the slice cites.
- Deliver only the slice's in-scope behavior. If in-scope work forces a stub for
  an out-of-scope column or enum value, fill it with the documented "not yet
  applicable" value (`NA`, `unknown`) — never with a fabricated result.
- Do not weaken a §6 contract to make a slice easier. If a contract blocks the
  slice, stop and surface it rather than diverging.
- A slice is done only when its Acceptance checks run green and the tracer
  bullet works from a clean checkout with no network access (except the
  maintainer-only differential and live-integration jobs, which are explicitly
  exempt).
- Preserve original input order and one-based indexing in every row-shaped
  output, even for behavior a slice stubs out.

### 5.4 Dependency graph

```
C++ repo:   C1 ─▶ C2 ─▶ C4
                 └▶ C3 ─▶ C4
            C2,C3 ─▶ C5
            (all) ─▶ C6

R repo:     R1 ─▶ R2 ─▶ R3
                 └▶ R4
            R1 ─▶ R5 ─▶ R6 ─▶ R7
            R2,R3,R6,R7 ─▶ R8
            (all) ─▶ R9

Cross-repo: C2 gates R1 (vendored engine must pass the matcher suite).
            C3 gates R3 (reporting/callback surface).
            C4 gates R3 (callback-contract correlation test).
```

The C++ repo (C1–C6) and the R repo (R1–R9) can proceed in parallel up to the
cross-repo gates: R1 cannot vendor an engine until C2 is green, and R3 cannot
correlate match metadata until C3/C4 are green.

## 6. Reference Contracts (normative)

This section is the single source of truth the slices cite. It is unchanged in
substance from v2.

### 6.1 C++ baseline, fidelity, and preserved surface

- The v1 matcher baseline is `google/robotstxt` commit
  `22b355ff855419e6a3ff8ff09c0ad7fdb17116f9`.
- This baseline commit is the 2026-04-01 WASM merge. The baseline intentionally
  includes the matcher/reporting state at that commit while excluding
  `robots_wasm.cc` from the product surface.
- Record the full upstream SHA, import date, copied files, and upstream URLs.
  Keep a machine-readable or plainly diffable manifest of every local source
  change. Document a repeatable sync procedure; a future upstream update is a
  new validation event, not an automatic dependency update.

Fidelity requirements:

- Keep Google's algorithm structure intact wherever practical.
- Do not change behavior to improve RFC 9309 compliance.
- Do not adopt nzrsky's ada-based URL parsing or its behavioral changes.
- Replace Abseil with standard C++ equivalents while preserving byte-level
  behavior.
- Replace `absl::btree_map` in the reporting layer with a standard-library
  structure that preserves observable sorted-by-line output.
- Preserve namespace, class names, function names, and file organization where
  practical. ABI identity is not required because replacing Abseil types changes
  signatures.

Expected preserved surface: `RobotsMatcher`, `AllowedByRobots`,
`OneAgentAllowedByRobots`, `ParseRobotsTxt`, `GetPathParamsQuery`,
`MaybeEscapePattern`, `matching_line()`, `RobotsParsingReporter`, and
`RobotsParsedLine`.

Build requirements: C++17 target; minimal CMake; static library; optional test
building; production target uses only the C++ standard library; test-only
GoogleTest allowed but never downloaded during normal configure/build; no
Abseil in library or test targets; Bazel dropped; `robots_main.cc` and
`robots_wasm.cc` excluded from the v1 product surface; a tiny smoke/example
binary allowed when useful; support GCC, Clang, Apple Clang, and MSVC across the
R/CRAN platform matrix.

The known Abseil surface to replace (behavior-neutral): `absl::string_view` →
`std::string_view`; `absl::FixedArray` → `std::vector`; `absl::StartsWith` /
`EndsWith` / `AsciiStrToLower` → local helpers; `absl::SimpleAtoi` →
`std::from_chars`; `absl::ascii_is*` → `<cctype>` helpers.

### 6.2 Matcher URL boundary

For every row on which matching runs:

- pass the original input URL string to C++;
- do not pass `rurl::get_clean_url()` or any other cleaned, decoded,
  canonicalized, or reserialized URL to the matcher;
- do not strip query strings;
- do not remove fragments or userinfo on the matcher side;
- do not normalize Unicode or percent escapes on the matcher side.

`rurl` is a fetch-origin and URL-validation dependency, not a matcher-input
transformation.

### 6.3 Fetch-origin construction

The URL-first and fetch functions accept only absolute `http` or `https` URLs
with an explicit scheme and host. Scheme-relative and scheme-less inputs are
invalid instead of silently defaulting to HTTP.

Before calling any `rurl` parser, apply an ASCII case-insensitive explicit
scheme guard to the untouched input string and require it to begin with
`http://` or `https://`. Only then call `rurl` to validate and decompose the
URL. This guard is required because `rurl` may otherwise assign HTTP to a
scheme-less input. It validates eligibility only and must not alter the string
later passed to the matcher.

For a valid URL, `rurl` must construct `scheme://host[:port]/robots.txt`.
Origin serialization must: lowercase the scheme and host; convert IDN hostnames
to ASCII/punycode; preserve non-default ports and omit default ports; serialize
IPv6 literals with brackets; omit userinfo; ignore path, parameters, query, and
fragment; emit exactly `/robots.txt` as the request path.

The serialized robots URL is the per-call grouping key.

### 6.4 Deterministic fetch policy

V1 uses `httr2` and the following product policy. It is intentionally
conservative and is not presented as Googlebot fetch-policy parity.

Request behavior:

- use HTTP `GET`;
- verify TLS using the platform defaults;
- use a 10-second total timeout per origin, including redirects, unless the
  caller supplies another positive value;
- follow at most five redirects;
- allow same- or cross-origin redirects only to `http` or `https`;
- allow HTTP-to-HTTPS upgrades, but reject every HTTPS-to-HTTP downgrade as
  `redirect_error`;
- never forward URL userinfo, authorization, cookies, or caller session state;
- send a package-specific fetch user agent containing package name and version
  when `fetch_user_agent = NULL`;
- allow a caller-supplied non-empty fetch user agent;
- never reuse the matcher `user_agent` as the HTTP user agent implicitly;
- perform no automatic retries in v1.

Response behavior:

| Condition | `fetch_outcome` | Match body? | Decision |
|---|---|---:|---|
| final `100`-`199` response | `http_error` | no | `NA` / `fetch_unknown` |
| `200`-`299` except `206` | `fetched` | yes | run matcher; an empty body is valid |
| `206 Partial Content` | `partial_response` | no | `NA` / `fetch_unknown` |
| `404` or `410` | `missing` | no | `TRUE` / `missing_allow` |
| any other `400`-`499`, including `408` and `429` | `http_error` | no | `NA` / `fetch_unknown` |
| any `500`-`599` | `http_error` | no | `NA` / `fetch_unknown` |
| redirect loop, invalid redirect, HTTPS-to-HTTP downgrade, more than five redirects, or a remaining `300`-`399` response | `redirect_error` | no | `NA` / `fetch_unknown` |
| DNS, connection, or other non-TLS transport failure | `network_error` | no | `NA` / `fetch_unknown` |
| TLS failure | `tls_error` | no | `NA` / `fetch_unknown` |
| timeout | `timeout` | no | `NA` / `fetch_unknown` |
| decoded response body exceeds `max_bytes` | `body_too_large` | no | `NA` / `fetch_unknown` |

Additional response rules:

- `max_bytes` defaults to 524,288 bytes and must be a positive whole-number
  scalar no greater than R's maximum integer.
- Enforce the body limit on decoded entity bytes and abort reading when the
  limit is exceeded. Do not match a truncated body.
- HTTP content decoding may be performed by the HTTP stack. Do not perform
  charset reserialization before passing resulting bytes to C++.
- Store the exact decoded entity bytes passed to C++ in the source row's raw
  `body` value.
- Do not reject a successful body based on `Content-Type`. The upstream parser
  is tolerant of arbitrary content.
- Record requested robots URL, final effective URL, status, redirect count,
  body size, timeout, byte limit, and structured failure metadata.
- A native binding exception or violated internal invariant is a package error,
  not a robots decision. Do not silently convert implementation bugs to
  `allowed = NA`.

Streaming byte-limit enforcement (implementation note for §8, R7):

- Enforcing `max_bytes` on decoded bytes requires a streaming path that counts
  bytes after HTTP content decoding and aborts as soon as the limit is crossed.
- A small lower-level curl write callback behind the `httr2` request path is
  allowed if the high-level response API cannot enforce the limit without
  buffering the full entity.
- Do not substitute compressed `Content-Length` checks, compressed-byte
  counting, or download-then-check behavior.

### 6.5 Fetch grouping and caching

- Within one call, fetch each distinct serialized robots URL present among
  fetch-eligible rows exactly once.
- All fetch-eligible input rows sharing that key must use the same source row
  and body. Input-invalid rows have no grouping key and remain detached (§6.6).
- Group by the requested serialized robots URL, not by the final redirect
  destination.
- Preserve original input order in results. Fetch groups sequentially in
  first-occurrence order.
- No persistent cache. No cross-call in-memory cache. No hidden use of HTTP
  cache results such as `304 Not Modified`.

This one-fetch-per-origin rule is a correctness and determinism requirement, not
product-level caching.

### 6.6 Result contract

Public V1 API and committed signatures:

- `allowed_by_robots_url(url, user_agent, timeout = 10,
  max_bytes = 524288L, fetch_user_agent = NULL)` fetches and matches.
- `allowed_by_robots_text(robots_txt, url, user_agent,
  source_id = "supplied")` matches one supplied body without HTTP.
- `robots_fetch(url, timeout = 10, max_bytes = 524288L,
  fetch_user_agent = NULL)` performs the same grouped fetch stage without
  matching.
- `robots_body(x, source_id = NULL, n = 20, raw = FALSE)` previews or extracts
  a stored body. `n = Inf` requests the full body.

The two matching functions return an S3 object of class `robots_decisions`.
`robots_fetch()` returns an S3 object of class `robots_fetches`.

Input and vectorization contract for `allowed_by_robots_url()`:

- `url` must be a character vector and may have length zero.
- `user_agent` must be a character vector of length one or `length(url)`. A
  scalar user agent expands across URLs. No other R recycling is allowed. A
  length mismatch or wrong R type is a call-level error. An empty result is
  returned for a zero-length URL vector.
- A missing, empty, malformed, or non-HTTP(S) URL produces a per-row
  `input_unknown` decision with `allowed = NA`; it does not abort other rows.
- A missing or empty user-agent element produces a per-row `input_unknown`
  decision.
- A non-empty user-agent string is passed unchanged to the matcher. Upstream
  extraction semantics apply, so `Googlebot/2.1` is not pre-trimmed by R.
- URL validation runs before user-agent validation when both are invalid, so
  each row has one deterministic primary error class.
- Complete URL and user-agent validation before constructing the fetch plan.
  Any row with either invalid element is excluded from fetch grouping and never
  causes an HTTP request.
- An invalid-user-agent row is fully detached from fetch results even if a valid
  sibling row causes the same origin to be fetched. For that invalid row, set
  `source_id`, `robots_url`, and `http_status` to `NA`; set
  `fetch_outcome = "input_invalid"`, `decision_source = "input_unknown"`,
  `allowed = NA`, and populate the user-agent error metadata.
- The detachment rule also applies to local/body matching. The supplied body may
  exist in the object's `robots` table, but an invalid input row does not
  reference it.

Shared fetch controls (apply to `allowed_by_robots_url()` and `robots_fetch()`):

- `url` follows the URL type, zero-length, and per-element validity rules above.
- `timeout` must be one non-missing, finite, positive numeric value.
- `max_bytes` must be one non-missing, finite, positive whole-number value no
  greater than R's maximum integer. Coerce it to integer once after validation;
  fractional or out-of-range values are call-level errors.
- `fetch_user_agent` must be `NULL` or one non-empty, non-missing character
  value; violations are call-level errors.
- Invalid URL elements remain in the returned input map with
  `fetch_outcome = "input_invalid"` and no `source_id`.

`allowed_by_robots_text()`:

- `robots_txt` must be one non-missing character scalar. An empty body is valid.
- `source_id` must be one non-empty, non-missing character scalar.
- `url` and `user_agent` follow the same length rules as the URL-first function.
- No URL-origin parse or fetch is performed.
- Missing or empty URL/user-agent elements produce per-row `input_unknown`.
- Other URL strings are passed unchanged to the matcher. The documentation must
  state the upstream requirement that callers supply an appropriately encoded
  full URL.
- Multiple supplied bodies in one call are deferred; users call the function
  once per body.

`robots_decisions` is a named list with exactly two primary components: `results`
(one row per input URL, in input order) and `robots` (one row per fetched or
supplied source body/outcome). The object may carry class metadata, package
version, and call metadata as attributes. Large body values must not appear in
`results`.

`robots_fetches` is a named list with exactly two primary components: `map` (one
row per input URL, in input order) and `robots` (the same source-table schema).
Required `map` columns are `input_id`, `url`, `source_id`, `robots_url`,
`http_status`, `fetch_outcome`, `error_stage`, `error_class`, and
`error_message`, with the same types and meanings below.

Required `results` columns:

| Column | Type | Meaning |
|---|---|---|
| `input_id` | integer | one-based input position |
| `url` | character | original input string |
| `user_agent` | character | original matcher user-agent string |
| `allowed` | logical | `TRUE`, `FALSE`, or `NA` |
| `decision_source` | character | stable enum below |
| `source_id` | character | reference into `robots`, or `NA` for invalid input |
| `robots_url` | character | requested robots URL, or `NA` |
| `http_status` | integer | final HTTP status, or `NA` |
| `fetch_outcome` | character | stable fetch enum |
| `error_stage` | character | stable processing stage, or `NA` |
| `error_class` | character | stable package error class, or `NA` |
| `error_message` | character | diagnostic message, or `NA` |
| `matched_line` | integer | upstream one-based matching line, or `NA` |
| `matched_rule_type` | character | `allow`, `disallow`, `none`, or `unknown` |
| `matched_rule_value` | character | canonical (post-escape) callback value for the matched directive, or `NA` |

Required `robots` columns:

| Column | Type | Meaning |
|---|---|---|
| `source_id` | character | unique, stable within the result object |
| `source_type` | character | `fetched` or `supplied` |
| `robots_url` | character | requested robots URL, or `NA` for supplied text |
| `effective_url` | character | final response URL, or `NA` |
| `http_status` | integer | final status, or `NA` |
| `fetch_outcome` | character | stable enum below |
| `redirect_count` | integer | followed redirects, or zero for supplied text |
| `body_size` | integer | stored decoded bytes, or `NA` when no body was used |
| `timeout` | double | configured seconds, or `NA` for supplied text |
| `max_bytes` | integer | configured limit, or `NA` for supplied text |
| `error_stage` | character | `input`, `origin`, `request`, `redirect`, `response`, or `NA` |
| `error_class` | character | stable package error class, or `NA` |
| `error_message` | character | diagnostic message, or `NA` |
| `body` | list of raw | body used for matching, stored once, or `NULL` |

Fetched source IDs are assigned deterministically as `robots_1`, `robots_2`, and
so on in first-occurrence grouping order. The single supplied source uses the
caller's `source_id`. Store `max_bytes` using the validated integer value,
including when the caller supplied an R double that represented a valid whole
number.

Stable `decision_source` values:

| Value | `allowed` | Meaning |
|---|---:|---|
| `rule_allow` | `TRUE` | an Allow directive won |
| `rule_disallow` | `FALSE` | a Disallow directive won |
| `default_allow` | `TRUE` | matching ran and no directive matched |
| `missing_allow` | `TRUE` | fetch returned `404` or `410` |
| `fetch_unknown` | `NA` | no safe decision because fetching failed |
| `input_unknown` | `NA` | no safe decision because an input was invalid |

Stable `fetch_outcome` values: `fetched`, `supplied`, `missing`,
`partial_response`, `http_error`, `redirect_error`, `timeout`, `network_error`,
`tls_error`, `body_too_large`, `input_invalid`.

`decision_source` and `fetch_outcome` describe different dimensions.
`input_unknown` means no allow/deny decision was possible; `input_invalid` means
the fetch/match pipeline stopped during input validation. The deliberately
different names must not be collapsed into one enum.

Stable non-missing `error_class` values: `robots_invalid_url`,
`robots_invalid_user_agent`, `robots_partial_response`, `robots_http_error`,
`robots_redirect_error`, `robots_timeout`, `robots_network_error`,
`robots_tls_error`, `robots_body_too_large`. `error_class` is `NA` for
`fetched`, `supplied`, and `missing` outcomes. `error_message` is diagnostic
text and is not a stable value for programmatic branching.

Error metadata mapping:

| Condition or outcome | `error_stage` | `error_class` |
|---|---|---|
| invalid URL | `origin` | `robots_invalid_url` |
| invalid user agent | `input` | `robots_invalid_user_agent` |
| `partial_response` | `response` | `robots_partial_response` |
| `http_error` | `response` | `robots_http_error` |
| `redirect_error` | `redirect` | `robots_redirect_error` |
| `timeout` | `request` | `robots_timeout` |
| `network_error` | `request` | `robots_network_error` |
| `tls_error` | `request` | `robots_tls_error` |
| `body_too_large` | `response` | `robots_body_too_large` |
| `fetched`, `supplied`, or `missing` | `NA` | `NA` |

Match metadata rules:

- `matching_line() == 0` maps to `matched_line = NA`. Positive upstream line
  numbers are already one-based and returned unchanged.
- `rule_allow` requires `matched_rule_type = "allow"`; `rule_disallow` requires
  `"disallow"`; `default_allow` requires `"none"`; `missing_allow`,
  `fetch_unknown`, and `input_unknown` require `"unknown"`.
- `matched_rule_value` is the exact directive value emitted by the upstream
  parse callback for `matched_line` — the canonical value the matcher actually
  uses, i.e. after `MaybeEscapePattern` canonicalization (see the note below). R
  must not reconstruct it by reserializing the URL or rule, and must not attempt
  to recover a pre-escape form by re-parsing the raw directive text.
- When matching ran but no rule matched, `matched_rule_type = "none"`. When
  matching did not run, `matched_rule_type = "unknown"`.
- `matched_line` and `matched_rule_value` are `NA` unless a rule matched.
- An `allow`/`disallow` directive with an empty path is ignored by the matcher
  (per Google; verified against upstream `robots_test.cc:317-323`), so it wins
  nothing: such a row surfaces as `default_allow` with `matched_rule_type =
  "none"` and `matched_line`/`matched_rule_value` `NA` (and `allowed` stays
  `TRUE`), even though the reporting layer may report a positive matching line
  for the ignored empty-path directive. A real rule always has a non-empty path
  (even `/`), so a correlated callback value of exactly `""` uniquely
  identifies this ignored-empty-path case.

Correlation mechanism:

- Run the matcher for each eligible result row and obtain `matching_line()`.
- Run `ParseRobotsTxt()` once per distinct source body with a private,
  read-only `RobotsParseHandler` collector that stores Allow/Disallow callback
  type and value keyed by line number.
- Join a positive `matching_line()` to that per-source lookup to populate
  `matched_rule_type` and `matched_rule_value`.
- `RobotsParsedLine` and `RobotsParsingReporter` remain preserved public
  surfaces, but v1 must not assume that `RobotsParsedLine` itself stores the
  directive value.
- At the pinned SHA, for Allow/Disallow keys the callback value has already
  undergone upstream comment removal and whitespace stripping performed by
  `ParseRobotsTxt()`, **and** `MaybeEscapePattern` canonicalization (non-ASCII
  bytes percent-escaped, existing `%xx` escapes upper-cased) — this was verified
  in `robots.cc` `ParseAndEmitLine` (the `NeedEscapeValueForKey` branch escapes
  the value before emitting it to the handler). That canonical callback value is
  the result contract. This corrects an earlier draft that assumed the callback
  value was pre-escape; the engine's real behavior is authoritative and is not
  altered (fidelity, §6.1). For plain-ASCII directives canonicalization is a
  no-op, so this is observable only for non-ASCII or lowercase-hex-escape
  directives. C4's callback-contract test and C5's differential harness both
  gate this against pristine upstream.
- A positive matching line missing from the callback lookup is an internal
  invariant failure and must raise a package error, not `allowed = NA`.

Body handling: for supplied text, convert the R character scalar to UTF-8 once,
store those exact bytes in `robots$body`, and pass that same byte sequence to
C++. If a matched callback value is not valid UTF-8, return it as an R character
value with `Encoding = "bytes"` rather than replacing bytes.

`robots_body()` must select from the `robots` table, render raw bytes safely when
`raw = FALSE`, and return the raw vector unchanged when `raw = TRUE`. If
`source_id` is omitted and the object contains more than one source, it must
error rather than choose silently.

### 6.7 Relationship to existing R packages

The R package is standalone first and backend-compatible later. Do not contort
v1 around `robotstxt` or `spiderbar` APIs. The stable result and decision enums
should make a compatibility wrapper possible later.

> A Google-parser-backed engine that can serve as an alternative backend for
> `robotstxt`-style workflows.

## 7. C++ Slice Catalog

### Slice C1 — De-Abseiled core matcher with an offline build and one real decision

- **Repo:** C++.
- **Tracer bullet:** `cmake -S . -B build && cmake --build build` produces a
  static library and a smoke binary; running the smoke binary evaluates
  `AllowedByRobots("user-agent: *\ndisallow: /private", {"crawler"},
  "http://example.com/private/x")` and prints `disallow`.
- **Depends on:** none.
- **In scope:** import `robots.{cc,h}` at the pinned SHA; replace the Abseil
  surface used by `robots.{cc,h}` with C++17 stdlib equivalents (§6.1);
  offline CMake static-library target; optional-test toggle; a tiny smoke
  binary; start the change manifest and SHA record.
- **Out of scope:** reporting layer (C3); the full upstream test suite (C2);
  differential harness (C5); final license/NOTICE (C6).
- **Normative references:** §6.1, §6.2.
- **Deliverables:** `robots.cc`, `robots.h`, `CMakeLists.txt`, smoke binary,
  initial `PROVENANCE`/manifest stub.
- **Acceptance:** builds offline on the host toolchain with no Abseil include
  remaining in `robots.{cc,h}`; smoke binary prints the correct decision for at
  least the disallow case above and one allow case; production target links no
  Abseil.

### Slice C2 — Upstream matcher test suite green

- **Repo:** C++.
- **Tracer bullet:** `ctest` runs the adapted `robots_test.cc` and every case
  passes, including `ID_Encoding`.
- **Depends on:** C1.
- **In scope:** mechanically adapt `robots_test.cc` under the allowed
  adaptations only (§6.1 build/test rules); wire GoogleTest as a test-only,
  never-downloaded dependency; document the exact test diff.
- **Out of scope:** reporting tests (C3); regression tests for replacements
  (C4).
- **Normative references:** §6.1.
- **Acceptance:** all adapted `robots_test.cc` cases pass with no assertion,
  fixture, URL, user-agent, or expected-value changes; the documented diff
  contains only mechanical adaptations; test target links no Abseil.

### Slice C3 — Reporting layer, its tests, and the `btree_map` replacement

- **Repo:** C++.
- **Tracer bullet:** `ctest` runs the adapted `reporting_robots_test.cc` and
  every case passes; reporting output is observably sorted by line.
- **Depends on:** C1 (C2 recommended).
- **In scope:** import and de-Abseil `reporting_robots.{cc,h}`; replace
  `absl::btree_map` with a stdlib structure preserving sorted-by-line output;
  preserve `RobotsParsingReporter` and `RobotsParsedLine`; mechanically adapt
  `reporting_robots_test.cc`.
- **Out of scope:** the callback-contract correlation test (C4); R-side
  correlation (R3).
- **Normative references:** §6.1, §6.6 (correlation-surface preservation only).
- **Acceptance:** all adapted reporting tests pass with no assertion changes;
  sorted-by-line output verified; no Abseil in library or test targets.

### Slice C4 — Abseil-replacement regression tests and the callback-contract test

- **Repo:** C++.
- **Tracer bullet:** `ctest` runs a focused regression suite that pins each
  Abseil replacement and proves `ParseRobotsTxt()` emits Allow/Disallow values
  keyed by the same one-based lines `matching_line()` returns.
- **Depends on:** C2, C3.
- **In scope:** focused tests for non-ASCII bytes, character classification,
  integer conversion, fixed-array replacement, and sorted reporting output; a
  callback-contract test proving value/line correlation after comment and
  whitespace handling and before matcher escaping.
- **Out of scope:** the differential harness (C5).
- **Normative references:** §6.1, §6.6 (correlation mechanism).
- **Acceptance:** every replacement has at least one dedicated failing-if-broken
  test; the callback-contract test asserts type, value, and line for cases with
  comments, whitespace, and percent escapes.

### Slice C5 — Maintainer-only differential harness

- **Repo:** C++.
- **Tracer bullet:** a maintainer command builds pristine upstream and the
  replica at the same SHA from a local source path, runs the upstream corpus
  plus at least 10,000 deterministic generated cases, and reports zero matcher
  and reporting differences.
- **Depends on:** C2, C3.
- **In scope:** deterministic robots.txt/URL/user-agent case generator with a
  recorded seed and corpus-generation version; a harness that accepts a local
  path to pristine upstream source and diffs both matcher and reporting output.
- **Out of scope:** anything in the offline build or CI default path — the
  harness must never download source during ordinary configure, CI, or install.
- **Normative references:** §6.1.
- **Acceptance:** ≥10,000 generated cases plus the upstream corpus run with zero
  differences; seed and corpus version recorded; harness excluded from the
  offline build.

### Slice C6 — Provenance, licensing, and sync procedure

- **Repo:** C++.
- **Tracer bullet:** a clean checkout contains a complete provenance manifest and
  license set, and following the documented sync procedure reproduces the
  vendored state.
- **Depends on:** C1–C5.
- **In scope:** full upstream SHA, copied files, diffable local-change manifest,
  and sync instructions; preserved Google copyright and Apache-2.0 headers;
  `LICENSE` and `NOTICE`; naming that avoids implying Google affiliation.
- **Out of scope:** the R package's own license arrangement (R9, §8).
- **Normative references:** §6.1, §7 of prior structure now folded into §9.
- **Acceptance:** manifest and license files present in the buildable source
  tree; sync procedure verified to reproduce the pinned state.

## 8. R Slice Catalog

### Slice R1 — Vendored engine, cpp11 binding, minimal text decision

- **Repo:** R.
- **Tracer bullet:** `R CMD INSTALL .` compiles the vendored C++ with no network
  access, and
  `allowed_by_robots_text("user-agent: *\ndisallow: /x", "http://a/x", "bot")`
  returns a `robots_decisions` whose single `results$allowed` is `FALSE`.
- **Depends on:** C2 (vendored matcher must pass the upstream suite).
- **In scope:** vendor the validated C++ snapshot and record its SHA; declare
  `R (>= 4.1.0)`, C++17, and `cpp11`; a cpp11 binding taking (body, url,
  user_agent) and returning a logical, vectorized over `url`; a minimal
  `allowed_by_robots_text()` returning a `robots_decisions` with the `results`
  and `robots` skeletons populated for the happy path (`rule_allow`,
  `rule_disallow`, `default_allow`); the body stored once as raw.
- **Out of scope:** full input validation and vectorization contract (R2);
  match-metadata correlation (R3); `robots_body()` (R4); all fetching (R5–R8).
  Columns owned by later slices are present but filled with `NA`/`unknown`.
- **Normative references:** §6.1, §6.2, §6.6 (`robots_decisions` shape,
  `decision_source` happy-path values, body handling).
- **Acceptance:** offline install and one green `testthat` test per happy-path
  `decision_source` value; the exact supplied body round-trips through
  `robots$body`.

### Slice R2 — `allowed_by_robots_text()` full result contract and input rules

- **Repo:** R.
- **Tracer bullet:** the text function honors the full `results`/`robots`
  schema, input validation, scalar user-agent expansion, and per-row
  `input_unknown`, e.g. a mixed-validity vector returns one row per input in
  order with correct `decision_source` and error metadata.
- **Depends on:** R1.
- **In scope:** full `results` and `robots` columns for the text path; input
  type, length, and per-element validity rules; scalar user-agent expansion;
  zero-length and length errors; per-row `input_unknown`; detachment rule for
  invalid rows; UTF-8 conversion once and `Encoding = "bytes"` fallback;
  `matched_line` from `matching_line()` and `matched_rule_type` derived from the
  decision.
- **Out of scope:** `matched_rule_value` and callback-derived
  `matched_rule_type` correlation (R3); anything network (R5–R8).
- **Normative references:** §6.2, §6.6 (all text-path parts; correlation
  deferred to R3).
- **Acceptance:** `testthat` covers every text-path `decision_source` value,
  scalar expansion, equal-length vectors, zero-length input, length errors, the
  detachment rule, and byte-encoded callback values; `matched_rule_value` is
  `NA` pending R3.

### Slice R3 — Match-metadata correlation

- **Repo:** R.
- **Tracer bullet:** for a matched row, `matched_rule_value` equals the exact
  pre-escape directive value and `matched_rule_type` is the callback-derived
  type, joined by line.
- **Depends on:** R2, C3, C4.
- **In scope:** expose the C++ `RobotsParseHandler` collector through cpp11; run
  `ParseRobotsTxt()` once per distinct source body; join positive
  `matching_line()` to the per-source lookup; raise a package error on a missing
  line.
- **Out of scope:** fetch integration (R8) reuses this but does not reimplement
  it.
- **Normative references:** §6.6 (match metadata rules, correlation mechanism).
- **Acceptance:** `testthat` asserts `matched_rule_type`/`matched_rule_value`
  for cases with comments, whitespace, acceptable missing-colon syntax, Unicode,
  and percent escapes; a synthetic missing-line case raises a package error, not
  `NA`.

### Slice R4 — `robots_body()` helper

- **Repo:** R.
- **Tracer bullet:** `robots_body(x)` previews the stored body; `raw = TRUE`
  returns the raw vector unchanged; omitting `source_id` on a multi-source
  object errors.
- **Depends on:** R2.
- **In scope:** selection from the `robots` table; safe rendering when
  `raw = FALSE`; unchanged raw vector when `raw = TRUE`; `n`/`n = Inf` handling;
  multi-source error.
- **Out of scope:** none beyond the helper.
- **Normative references:** §6.6 (`robots_body()` rules).
- **Acceptance:** `testthat` covers preview, full extraction, raw round-trip,
  and the multi-source error.

### Slice R5 — Fetch-origin construction (pure, offline)

- **Repo:** R.
- **Tracer bullet:** a pure origin function turns `https://例え.jp/a?b#c` into
  the grouping key `https://xn--r8jz45g.jp/robots.txt`, and rejects scheme-less
  input before any `rurl` parse.
- **Depends on:** R1.
- **In scope:** the explicit-scheme guard on the untouched input; `rurl`-based
  origin serialization per §6.3 (lowercasing, IDN/punycode, ports, IPv6
  brackets, userinfo omission, `/robots.txt` path); returns the serialized
  grouping key. `rurl` in `Imports`.
- **Out of scope:** performing any HTTP (R6); grouping across a call (R6).
- **Normative references:** §6.2 (must not alter the matcher string), §6.3.
- **Acceptance:** `testthat` covers IDN, IPv4, IPv6, userinfo, explicit/default
  ports, fragments, queries, and scheme-less/scheme-relative rejection; verified
  fully offline.

### Slice R6 — `robots_fetch()` and the deterministic fetch policy (mocked)

- **Repo:** R.
- **Tracer bullet:** `robots_fetch(c("http://a/x", "http://a/y"))` against a
  mocked server issues exactly one request for the shared origin, returns a
  `robots_fetches` with `map` and `robots`, and classifies each HTTP outcome per
  the table.
- **Depends on:** R5.
- **In scope:** `httr2` request policy (§6.4 request behavior); the full
  response classification table to `fetch_outcome`; `robots_fetches` schema;
  one-fetch-per-origin grouping and input-order preservation (§6.5); error
  metadata mapping; redirect policy including HTTPS-to-HTTP downgrade rejection;
  `httr2` in `Imports`.
- **Out of scope:** decoded-byte `body_too_large` streaming enforcement (R7);
  matching (R8).
- **Normative references:** §6.3, §6.4 (except streaming), §6.5, §6.6
  (`robots_fetches`, `fetch_outcome`, error mapping).
- **Acceptance:** `testthat` with mocked responses / local test server covers
  every `fetch_outcome` row, redirect limits, cross-origin and downgrade cases,
  invalid targets, loops, DNS/TLS/timeout/network failures, one-fetch-per-origin
  grouping, and stable order — no live network.

### Slice R7 — Streaming `max_bytes` enforcement on decoded bytes

- **Repo:** R.
- **Tracer bullet:** a mocked compressed response whose encoded body is under
  the limit but whose decoded body exceeds it ends as `body_too_large` with no
  stored or matched truncated body.
- **Depends on:** R6.
- **In scope:** a streaming path counting decoded bytes and aborting on limit,
  using a lower-level curl write callback behind `httr2` if needed; the
  `body_too_large` outcome and metadata.
- **Out of scope:** matching (R8).
- **Normative references:** §6.4 (additional rules and streaming note).
- **Acceptance:** the compressed-expands-past-limit test passes; no compressed
  `Content-Length` shortcut or download-then-check path is used; truncated
  bodies are never stored or matched.

### Slice R8 — `allowed_by_robots_url()` fetch-and-match integration

- **Repo:** R.
- **Tracer bullet:** `allowed_by_robots_url("http://a/private", "bot")` against a
  mocked `/robots.txt` returns a `robots_decisions` with the correct
  `allowed`/`decision_source`, and a `404` origin yields `missing_allow`/`TRUE`.
- **Depends on:** R2, R3, R6, R7.
- **In scope:** combine the fetch stage with matching; reuse one fetched source
  body across all rows sharing an origin; `missing_allow` for `404`/`410`;
  `fetch_unknown` for fetch failures; populate the full `results` contract from
  fetched bodies; carry match-metadata correlation from R3 through fetched
  bodies.
- **Out of scope:** none for the URL-first headline path.
- **Normative references:** all of §6.
- **Acceptance:** `testthat` covers `missing_allow`, `fetch_unknown`, grouped
  reuse of a source body across rows, exact-URL-preservation into the matcher
  (percent escapes, Unicode, path case, query, fragment), and combined
  fetch+match ordering — no live network.

### Slice R9 — CRAN, platform, provenance, and licensing gate

- **Repo:** R.
- **Tracer bullet:** `R CMD check --as-cran` completes clean, and the full R
  test-gate list runs green with no network access across the platform matrix.
- **Depends on:** R1–R8.
- **In scope:** complete the R Test Gate coverage list below; `R CMD check
  --as-cran` clean; CI on Linux GCC/Clang, macOS Apple Clang, Windows UCRT
  across R oldrel/release/devel; sanitizer job on a supported Linux toolchain;
  vendored-source manifest and license/NOTICE present in the built source
  package; document the R package's overall license arrangement.
- **Out of scope:** later features (§11).
- **Normative references:** §6, §9.
- **Acceptance:** all gate items pass; the CRAN release block on `rurl`
  availability is documented and respected (no ASCII-only fallback substituted).

R Test Gate coverage (owned collectively by R2–R9; R9 confirms completeness):

- every `decision_source` and `fetch_outcome` value;
- every row of the HTTP outcome table; the final 1xx fallback may be tested
  through the pure response classifier because curl/`httr2` normally consumes
  informational responses before exposing a final response;
- redirect limits, cross-origin redirects, HTTPS-to-HTTP downgrade rejection,
  invalid redirect targets, and loops;
- DNS, TLS, timeout, oversized-body, and malformed-origin failures;
- a compressed response that expands past `max_bytes` while streaming;
- IDN, IPv4, IPv6, userinfo, explicit/default ports, fragments, and queries;
- explicit-scheme prevalidation that rejects scheme-less and scheme-relative
  inputs before `rurl` parsing;
- preservation of the exact original matcher URL, including percent escapes,
  Unicode, path case, query strings, and fragments;
- scalar user-agent expansion, equal-length vectors, zero-length input, and
  length errors;
- invalid-user-agent detachment both with and without a valid same-origin
  sibling row;
- whole-number `max_bytes` coercion plus fractional and overflow errors;
- mandatory one-fetch-per-origin grouping and stable input order;
- local empty bodies, supplied-body matching, and body inspection;
- matched line/type/value correlation, including callback values with comments,
  whitespace, acceptable missing-colon syntax, Unicode, and percent escapes;
- all mechanically portable upstream matcher cases in `testthat`.

HTTP tests, examples, and vignettes must not require live internet access. Use
mocked responses or a local test server. Any optional live integration tests
must be maintainer-only and skipped by default.

## 9. Cross-Cutting Gates

These gates span slices and are confirmed at the milestone, not owned by a
single slice.

### R and native dependencies

- Declare `R (>= 4.1.0)` and C++17 in package metadata and build configuration.
- Use `cpp11` for the native binding unless implementation uncovers a concrete
  blocker.
- Put `rurl` and `httr2` in `Imports`.
- Public CRAN release is blocked until the required `rurl` version is available
  through CRAN-compatible package repositories. Do not silently replace robust
  origin handling with an ASCII-only fallback.
- Vendor the validated C++ snapshot; do not fetch native source at configure,
  build, test, or install time. Require no external system libraries beyond
  those normally available to R and the standard toolchain.

### CRAN and platform gate (R9)

- `R CMD check --as-cran` completes with no errors or warnings and no
  unexplained notes;
- CI passes on Linux with GCC and Clang, macOS with Apple Clang, and Windows
  UCRT, covering R oldrel, release, and devel where the platform supports it;
- package installation, tests, examples, and vignettes complete without network
  access;
- compiled code passes the relevant sanitizer job on a supported Linux
  toolchain;
- the vendored-source manifest and license files are present in the built
  source package.

### Licensing and provenance (C6, R9)

Provenance handling starts with the first source import rather than at release.
Required before any distributable artifact: preserve applicable Google copyright
and Apache-2.0 headers; include required `LICENSE` and `NOTICE` material;
disclose bundled code in the R package; choose and document the R package's
overall license arrangement; record the upstream full SHA, copied files, local
changes, validation date, and sync instructions; avoid names or descriptions
that imply Google affiliation.

## 10. Remaining Product Decisions

These decisions do not change the v1 matcher, fetch, input, or result contracts.

### Naming

Final C++ project and R package names remain open. Check CRAN availability,
GitHub availability, trademark and affiliation risk, and clarity to users.

### Final license arrangement

Legal/CRAN review must choose between Apache-2.0 for the whole project, an R
package license plus bundled Apache-2.0 code, or another compatible structure.
This must be resolved before a distributable artifact.

### Low-level R surface

Deferred from v1: full parsed robots.txt line tables, unsupported-tag reporting,
low-level parser callbacks, multi-user-agent obey-list matching, and arbitrary
multi-body vectorization. The C++ fork preserves the relevant upstream surface
so these can be added without changing matcher behavior.

## 11. Later Features

- An explicitly researched Googlebot-like fetch-policy mode.
- Persistent cache with TTL, purge, location, and size controls.
- Parallel fetching.
- Compatibility wrapper for `robotstxt`-style workflows.
- Full parsed-line/rule-table output.
- Multi-body local matching in one call.
- Single-header or amalgamated C++ distribution.
- Package-manager integrations for the C++ library.
- CLI or example binary if real demand appears.

## 12. Acceptance Criteria for First Milestone

The milestone is met when every slice in §7 and §8 is delivered and its
Acceptance checks are green. The slice-to-outcome mapping:

### C++ milestone

- Source pinned to `22b355ff855419e6a3ff8ff09c0ad7fdb17116f9` — C1, C6.
- Minimal offline CMake build on supported compiler families — C1.
- No Abseil in production or test targets — C1, C2, C3.
- Adapted upstream matcher tests pass with no assertion changes — C2.
- Adapted upstream reporting tests pass with no assertion changes — C3.
- Abseil-replacement regression tests pass — C4.
- Parse-callback and matching-line correlation contract verified — C4.
- Deterministic differential corpus of ≥10,000 cases with zero differences — C5.
- Upstream SHA, copied files, expected local changes, and sync instructions
  documented — C6.

### R milestone

- Vendors the validated C++ snapshot and records its SHA — R1.
- The four committed public functions implement the documented signatures —
  R1, R2, R4, R6, R8.
- URL-first matching implements the complete deterministic fetch table — R6, R8.
- Local/body matching accepts one supplied body and returns the same result
  schema — R2.
- Exact original URL strings proven by tests to reach the matcher — R8.
- Invalid-user-agent rows remain detached and never initiate or reference a
  fetch — R2, R8.
- `rurl` constructs robust fetch origins, including IDN and IPv6 — R5.
- The explicit-scheme guard rejects scheme-less inputs before `rurl` parsing —
  R5.
- Each robots URL is fetched exactly once per call — R6, R8.
- Streaming byte enforcement rejects compressed bodies that decode past
  `max_bytes` without matching truncated content — R7.
- Result columns, enums, match metadata, and source references match §6 — R2,
  R3, R6, R8.
- Positive matching lines correlate to callback-derived rule type/value from the
  same source bytes — R3, R8.
- Users can preview or extract the exact stored body — R4.
- No persistent or cross-call cache exists — R6.
- Sequential vectorized checks and scalar user-agent expansion work — R2, R8.
- All HTTP behavior tested without live network access — R6, R7, R8, R9.
- `R CMD check --as-cran` and the required platform matrix pass — R9.
- Licensing and bundled-source provenance complete before any distributable
  artifact — C6, R9.
