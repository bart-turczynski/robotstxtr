---
status: accepted
date: 2026-11-21
accepted: 2026-11-21
tracking: ROBO-bnvdmdjr
amended: none
---

# ADR 0002: The v1 evaluator removes dot segments before matching

Amends [`design/PRD.md`](../PRD.md) §6.2 ("Matcher URL boundary") for the v1 facades
`robots_evaluate_text_v1()` and `robots_evaluate_url_v1()` only. The legacy functions
`allowed_by_robots_text()` and `allowed_by_robots_url()` stay bound by §6.2 as written.
`BI-V2-TARGET` in [`design/robotstxtbing-integration-v2-spec.md`](../robotstxtbing-integration-v2-spec.md)
still holds at the extractor boundary. The contract text is
[`design/engine-contract-v1.md`](../engine-contract-v1.md), "The URL the matcher reads".

## Context

The matchers take the request target as they are handed it. A client sends a target built by URL
parsing or link resolution, and that target can differ from the string a caller passes. RFC 9309
§2.2.2 defines percent-encoding handling for the comparison and says nothing about dot segments.

Tested 2026-11-17 with `Disallow: /account/` and `Allow: /latam` (google, bing and yandex agree):

- `/latam/../account/x` was allowed through `Allow: /latam`, but curl, Node `fetch` and link
  resolution request `/account/x`, which the file disallows.
- `/latam/%2e%2e/account/x` was allowed. Node `fetch` (WHATWG) requests `/account/x`; Python
  `urllib` and Go `net/http` send it unchanged.

Google's vendored `GetPathParamsQuery()` finds the path by searching for `/`, `?` or `;` without
parsing the authority, so `https://u;v@example.com/x` is matched as `/;v@example.com/x` and allowed
under `Disallow: /x`, while `https://u%3Bv@example.com/x` is disallowed (2026-11-18). Bing's and
Yandex's extractors parse the authority and disallow both.

### Client survey (2026-11-19)

A localhost client survey plus source and documentation reading:

| Clients | Literal `.` / `..` | Encoded `%2e%2e`, `%2E%2E`, `.%2E` | Form |
|---|---|---|---|
| Python 3.15 `urllib`, Go `net/http`, Java 21 | sent | sent | `none` |
| wget 1.25, curl 8.7.1 (the macOS system copy) | removed | sent | `rfc3986` |
| Chrome 157, Node 26 `fetch`, libcurl 8.14.1 (R curl, httr2), curl 8.23.0 | removed | removed | `whatwg` |
| Nutch `BasicURLNormalizer` (from source) | removed | not recorded | |

The curl version where encoded-dot removal began lies between 8.7.1 (keeps them) and 8.14.1
(removes them). It is not pinned yet. No crawler vendor documents its dot handling, and no crawler
has been observed on such a URL. Every client form keeps `%252e`, `%2F`, dots in the query and `//`.

## Decision

### 1. Where the preprocessing sits

In `evaluate_rows_v1()`, above every backend's request-target extractor. It builds one matcher URL
per row, and each adapter receives that URL. The extractors (`google_request_target_v1()`,
`robotstxtr_extract_request_target_()`, `bing_extract_request_target()`) stay byte-transparent, and
their tests, which pin `/a/../b`, stay as they are. The `url` column keeps the input.

### 2. The modes

Both facades take `url_normalization`, length one, validated like `safety_level`:

- `"rfc3986"`, the default: RFC 3986 §5.2.4 `remove_dot_segments` on the path, and nothing else
  in the path. No byte is percent-encoded, decoded or case-folded, so `%2e` and `%2E` are not
  dots and stay as they are. Encoding stays with the backends until ROBO-tvcnkkdi decides it. It is
  a local function on the path bytes, not `rurl`: `rurl`'s `rfc3986` verdicts differ between 3.0.1,
  3.1.0 and its main branch (raw non-ASCII), its `"normalized"` form also decodes `%2E` and folds
  escape case, and it returns `NA` on input this ADR still evaluates.
- `"none"`: the URL as given, byte for byte, as before.

Part B (below) adds `"whatwg"`.

### 3. Invalid input is evaluated, with the reason recorded

A URL that is not a valid RFC 3986 URI is still evaluated. A lexical check of its bytes records
why: a raw space, a byte at or above `0x80`, a backslash, another character RFC 3986 excludes
(`` "<>^`{|} `` and controls), or a `%` not followed by two hex digits. It only records. It never
re-encodes (ROBO-tvcnkkdi owns encoding; ROBO-rswdwrnp owns a stray `%` on the validator side).

### 4. What a backend receives

Under `"rfc3986"` the URL is split the RFC 3986 way (Appendix B; the authority ends at the first
`/`, `?` or `#`) and rebuilt as the scheme, `//`, the host and port, the processed path and
`?query`. Userinfo is left out and the fragment is dropped. Userinfo therefore never reaches
`GetPathParamsQuery()`, and Google reads `https://u;v@example.com/x` as `/x`. Under `"none"` the
URL passes byte-identical.

A URL with no scheme or authority, which the text entry point accepts (`"/a/../b"`,
`"example.com/a/../b"`), keeps the bytes before its first `/`, and §5.2.4 is applied from that `/`
on, the path the backend reads. The note says so. Bing and Yandex refuse such a target in either
mode, as before.

### 5. The result columns

Two columns after `group_token`, on every row:

- `matcher_url`: the URL the matcher read (`url` under `"none"`).
- `url_preprocessing_note`: `NA` when the input is a valid URI with an authority and nothing
  changed; otherwise the rule cited, for example `RFC 3986 §5.2.4 removed dot segments` or
  `not a valid RFC 3986 URI: raw space; dot segments removed as given`.

The schema revision of both facades moves to `2026-11-21.1`. No policy revision moves.
`as_legacy_robots_decisions_v1()` drops both columns, as it drops `group_token`; its decisions are
the v1 result's.

## Consequences

- The default changes v1 answers on URLs with literal dot segments, with userinfo under the
  google backend, and in `design/library-comparison.md` class 21 (`Disallow: /a/./b` no longer
  matches `/a/./b`, which is read as `/a/b`). Callers that want the old reading pass
  `url_normalization = "none"`.
- The rule paths in the robots.txt are not normalized. A rule written with dot segments matches
  only a URL that keeps them, which `"rfc3986"` never hands over.
- The symmetry check runs on google, bing and yandex (`/a/../b`, `/a/./b`, `%2e` kept, `u;v@host`);
  the rfc9309 backend is `capability_unavailable` in every mode.
- `robots_evaluate_url_v1()` builds the `/robots.txt` origin from the input URL, so the mode never
  changes what is fetched.

## Part B (to follow)

Part B adds `"whatwg"`: full WHATWG URL serialization through `rurl`, opt-in and documented as
modeling browser and Node fetchers. It changes encoding by design (spaces and non-ASCII
percent-encoded, `\` read as `/`), so the "no encoding change" rule binds `"rfc3986"` and `"none"`
only. Part B also adds the disagreement flag, which marks rows where the `"rfc3986"` and
`"whatwg"` forms decide differently (encoded dots) or where one mode fails, and names the client
families on each side, from the survey above. It pins the curl version where `%2e` removal began,
between 8.7.1 and 8.14.1. Per-crawler defaults wait for live evidence (ROBO-oxfpgdrx).
