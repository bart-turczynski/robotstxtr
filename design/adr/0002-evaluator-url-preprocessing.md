---
status: accepted
date: 2026-11-21
accepted: 2026-11-21
tracking: ROBO-bnvdmdjr
amended: 2026-11-21 (part B, ROBO-bnvdmdjr: the "whatwg" mode, the disagreement flag and the curl 8.13.0 boundary)
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
| curl and libcurl before 8.13.0 (changelog) | removed | sent | `rfc3986` |
| curl and libcurl 8.13.0 and later (changelog) | removed | removed | `whatwg` |

The curl boundary is 8.13.0 (released 2025-04-02). Its changelog lists under Bugfixes "urlapi:
remove percent encoded dot sequences from the URL path" (<https://curl.se/ch/8.13.0.html>; curl
issue 16869). curl and libcurl before 8.13.0 send `%2e` segments as given, and 8.13.0 and later
remove them, which agrees with the survey's 8.7.1 and 8.14.1 rows. The survey versions above are
kept as recorded on 2026-11-19. No crawler vendor documents its dot handling, and no crawler has
been observed on such a URL. Every client form keeps `%252e`, `%2F`, dots in the query and `//`.

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
- `"whatwg"` (part B): the WHATWG URL Standard serialization through `rurl::serialize_url(url,
  standard = "whatwg")`, opt-in, modeling browsers and Node `fetch`. See section 6.
- `"none"`: the URL as given, byte for byte, as before.

The value set is published on the contract objects as `url_normalizations`, default first.

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

A URL with no authority, which the text entry point accepts (`"/a/../b"`,
`"example.com/a/../b"`), keeps the bytes before its first `/`, and §5.2.4 is applied from that `/`
on, the path the backend reads. The note says so. If the result would start the path with `//`,
removing the dots would create an authority the input does not have (`"/a/..//evil.com/x"` would
become `"//evil.com/x"`, and `"https:/q/..//h2/a/x"` would become `"https://h2/a/x"`), so the URL
is evaluated as given and the note says why (review round 1). Bing and Yandex refuse a target with
no authority in either mode, as before.

### 5. The result columns

Two columns after `group_token`, on every row:

- `matcher_url`: the URL the matcher read (`url` under `"none"`).
- `url_preprocessing_note`: `NA` under `"none"`, and under `"rfc3986"` when the input is a
  valid RFC 3986 URI with an authority and the preprocessing changed nothing; otherwise the
  rule cited, for example `RFC 3986 §5.2.4 removed dot segments`,
  `not a valid RFC 3986 URI: raw space; dot segments removed as given` or
  `no authority: path read from the first /`. The full list is in the contract text.

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

### 6. `"whatwg"` (part B)

`"whatwg"` is the full WHATWG URL serialization through `rurl`, with no cherry-picking. The
matcher URL is rebuilt from `rurl`'s result the way section 4 rebuilds it: the scheme, `//`, the
host and port, the path and `?query`, with userinfo left out and the fragment dropped. The parse
removes literal and encoded (`%2e`, `%2E`, either case, mixed with `.`) dot segments. It changes
encoding by design (a space becomes `%20`, non-ASCII is percent-encoded, `\` is read as `/` for
special schemes) and the host (put in lower case, a default port dropped), so the "no encoding change"
rule of section 2 binds `"rfc3986"` and `"none"` only.

`serialize_url()` exists with this behavior at `rurl` 3.0.1, the floor in `DESCRIPTION`. The tests
pin only forms whose output is the same on `rurl` 3.0.1, 3.1.0 and its main branch: literal and
encoded dot segments removed; `%252e`, `%2F`, `//` and dots in the query kept. They do not pin the
encoding of spaces or non-ASCII, which differs between those versions.

The URL's bytes are handed to `rurl` as UTF-8 and never read through the session's native
encoding, so the form does not depend on the locale: a `"latin1"`-marked URL is converted from
latin1, any other is taken as its bytes, and bytes that are not valid UTF-8 cannot be parsed. A
URL with no scheme is split by the splitter `"rfc3986"` uses (`url_target_parts_v1()`), never its
own: only the path it finds, when that starts with `/`, is serialized, as `http://h.invalid` plus
the path and query (string concatenation, never resolution), and the serialized path and query
follow the same lead `"rfc3986"` keeps, an authority or the bytes before the first `/`
(`"/latam/../account/x"` gives `/account/x`, `"example.com/a/./b"` gives `example.com/a/b`,
`"//h/a/../x"` gives `//h/x`); the fragment is dropped as there. Any other scheme-less input
(`"foo?q=/a/../b"`, `"a#/b"`) is read as `"rfc3986"` reads it, with the same note, and one whose
serialized path would start with `//` after a lead with no authority (`"/a/..//h/x"`) is evaluated
as given, mirroring `"rfc3986"`'s guard, so Bing and Yandex refuse every scheme-less target in
every mode (review round 3). A URL `rurl` cannot parse (it returns `NA`) is evaluated as given, with the note
`not a valid WHATWG URL: evaluated as given`. A changed URL has the note
`WHATWG URL serialization changed the URL`, then `userinfo removed` or `fragment dropped`.

### 7. The disagreement flag (part B)

Two more columns after `url_preprocessing_note`, on every row and in every mode. Under `"none"`
they are never computed: every decided row has the flag `NA` and the clients note
`not compared under url_normalization = "none"`, with no `"rfc3986"` target, no `rurl` call and no
second pass, so `"none"` is the old reading with nothing extra (review round 3). The rest of this
section describes `"rfc3986"` and `"whatwg"`.

- `preprocessing_disagreement` (logical): on a row the selected matcher decided (`url_decision`
  not `NA`), `TRUE` when `"whatwg"` cannot parse the URL ("one mode fails"), or when the
  `"rfc3986"` and `"whatwg"` matcher URLs differ and the matcher decides them differently;
  `FALSE` for targets that are the same or decide alike. Any other row (an `NA` or empty URL, an
  empty token, `capability_unavailable`, a policy decision, a refused token or target) is always
  `FALSE`, and its `"whatwg"` form is never computed (review round 2).
- `disagreement_clients` (character): `NA` when the flag is `FALSE`. Otherwise each side's
  decision. When the two forms differ only through encoded dot segments (the `"rfc3986"` path,
  each whole segment `%2e`, `.%2e`, `%2e.` or `%2e%2e` in either case read as `.` or `..` and
  removed by §5.2.4, with its query, equals the `"whatwg"` path and query, under the same scheme
  and authority), it also names the client families, labeled for dot segments only:
  `rfc3986 allow (dot segments as in: wget 1.25, curl/libcurl < 8.13.0); whatwg disallow (dot
  segments as in: Chrome 157, Node 26 fetch, curl/libcurl >= 8.13.0)`. Otherwise it says
  `the forms differ in more than dot segments; no client survey covers this`, or, when `"whatwg"`
  fails, `rfc3986 <decision>; whatwg cannot parse the URL; no client survey covers this`, since
  the survey and curl's 8.13.0 entry cover dot segments only (review rounds 1 and 2).

The families come from the survey table. The clients that send the URL unchanged (`"none"`) are on
neither side, since the flag compares two forms; Nutch is left out while its encoded-dot behavior
is unrecorded.

The selected mode's pass decides the row. A second matcher pass reads the other mode's URL only
on decided rows whose two URLs differ in more than the scheme or host ASCII case, a default port
(80 for http, 443 for https), an empty path against `/`, or the fragment, compared on the split
parts in one vectorized call (review rounds 2 and 3). Under `"rfc3986"` the `"whatwg"` URL is
computed only for the rows compared, with one `rurl` call per distinct URL (about 0.1 ms each on
the maintainer's machine, and more on a long path with many dot segments). That second pass is the
one exception to each batch adapter being invoked once per evaluation (`BI-V2-DISPATCH`, the
Yandex and Bing adapters): it is a second batch call with only the candidate rows, so only their
bodies are parsed again.

Under `"rfc3986"`, a URL longer than 2048 bytes is not compared, because `rurl`'s cost
grows faster than linearly on long dot-heavy paths (about 53 s for 20,000 `/seg/..` pairs): its
flag is `NA`, `disagreement_clients` is `not compared: URL longer than 2048 bytes`, and no second
pass runs. `"whatwg"` serializes and compares any length.

The schema revision of both facades moves to `2026-11-21.2`. No policy revision moves.
`as_legacy_robots_decisions_v1()` drops both columns.

Per-crawler defaults wait for live evidence (ROBO-oxfpgdrx).

### 8. Per-surface steps under an agent preset (ROBO-uyfryhlz)

The first live evidence for a URL reader's own steps is agent-view's probes of ChatGPT-User and
Claude-User on their API surfaces (2026-11-26). The facades' `preset` argument applies them
(design/engine-contract-v1.md, "Agent presets"). They are opt-in, reached only through `preset`:
`url_normalization` keeps its three public values and its `"rfc3986"` default, and a preset with
an explicit `url_normalization` is refused.

Each preset starts from `"none"`, the URL as given, and applies only the steps measured for its
surface. Unlike `"rfc3986"`, they encode and case-fold bytes, which section 2 keeps out of every
mode:

- `claude_user`: uppercase the hex digits of every `%` followed by two hex digits, strip one
  trailing `/` from a path other than `/` when the URL has no query or fragment, and encode each
  `/` in the query as `%2F`. All three are seen in edge logs.
- `chatgpt_user`: uppercase the hex digits only, inferred from one verdict.

They are local byte operations, not `rurl`, for the reason section 2 gives: its `"normalized"`
form also decodes `%2E`, which neither agent was seen to do. Nothing is decoded, a `%` without two
hex digits is kept, and no other byte changes. A raw space or byte outside ASCII, a dot segment, a
`//` run and userinfo were not measured (AGEN-hdmtqpwx and AGEN-hsvkltop have not run), so a
preset reads them as given and `url_preprocessing_note` names them as unmeasured, rather than
borrowing `"rfc3986"`'s dot removal or `"whatwg"`'s encoding. The disagreement flag of section 7
is not computed under a preset: the row is `NA`, with `not compared under an agent preset`.
