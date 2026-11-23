# Target URL encoding before matching: the matrix

Tracking: ROBO-tvcnkkdi. Date: 2026-11-23. Status: research and proposal. Nothing here changes an
evaluator answer: the proposal at the end waits for the maintainer (the ticket's decision gate).

The question is which spelling of a request target each engine matches against robots.txt, when
the same resource can be written with raw non-ASCII, escapes of either case, `%2F` or `/`, `%7E`
or `~`, a raw space or `%20`, a backslash, or a query the client re-serializes. The rule side is
researched elsewhere: [engine-disagreements.md](engine-disagreements.md) classes 6 and 11, and
[library-comparison.md](library-comparison.md) classes 13 to 16 and 20. This file covers the
target side, on all three engines (the owner's symmetry rule of 2026-11-19).

## Scope of this run

- **Delivered offline:** the vendored matchers' source, vendor documentation already cited in
  `design/`, all three local backends under all three `url_normalization` modes, a localhost
  client survey re-run on 2026-11-23, and the tester observations already on record (Y4, Y7, B3,
  ROBO-bpywsjwv, 2026-11-13).
- **Not delivered here:** new Bing or Yandex tester captures. They belong to the sibling capture
  protocols (Bing: BING-snztgvmf, BING-mabpuxza; Yandex: YDX-vakiowhn). Every tester cell with no
  evidence says `not tested: <owner issue>`.
- **Not delivered here:** crawler observations. [The crawler-request probe](#crawler-request-probe-for-robo-oxfpgdrx)
  specifies the fixtures; ROBO-oxfpgdrx serves them (the deploy is in the separate cloudflare-edge
  repository). Every crawler cell says `not tested: ROBO-oxfpgdrx`.
- **Out of scope:** changing vendored matchers (sibling projects), the rule-side validator
  warnings (ROBO-wrlaufai, ROBO-ovgfyowt), and a stray `%` (ROBO-rswdwrnp, commit cb4221d).

## Evidence labels

- **OBSERVED**: a vendor tool's result on a submitted body (Yandex Webmaster's robots.txt
  analysis, the Bing Webmaster robots.txt Tester), or a live crawler's request. Tester results are
  the tester's reading of a submitted body, not crawler behavior.
- **TESTED**: run here, on this machine: the local backends through `robots_evaluate_text_v1()`,
  or a client against a loopback listener.
- **INFERRED**: read from vendored source or vendor documentation, not run.

A local backend result says what this package's backend does. It does not establish what the
engine's live crawler requests or compares.

## Three mechanisms, kept apart

A target passes three stages before a rule is compared with it. The matrix keeps them apart.

1. **External preprocessing**, `url_normalization` in `evaluate_rows_v1()`
   ([ADR 0002](adr/0002-evaluator-url-preprocessing.md)). `"none"` passes the input byte for
   byte. `"rfc3986"` removes dot segments (RFC 3986 §5.2.4) and changes no encoding; an input
   that is not a valid RFC 3986 URI is still evaluated, and `url_preprocessing_note` says why it
   is invalid. `"whatwg"` is the WHATWG URL Standard serialization through `rurl`: it encodes a
   raw space and raw non-ASCII as upper-case UTF-8 escapes, reads `\` as `/`, escapes `'` in a
   query, and removes `%2e` dot segments. It never changes the case of an escape the input
   already has. The result's `matcher_url` column is the stage's output.
2. **Adapter extraction**: the backend's request-target extractor
   (`google_request_target_v1()`, `robotstxtr_extract_request_target_()`,
   `bing_extract_request_target()`). Each is byte-transparent on a UTF-8 input (`BI-V2-TARGET`;
   [robotstxtyandex-integration-v1-spec.md](robotstxtyandex-integration-v1-spec.md), "preserve
   percent-escape case, literal Unicode boundary bytes"). One locale effect sits here; see
   [Adapter extraction](#adapter-extraction-an-unmarked-url-under-lc_allc).
3. **Backend-internal matching**, INFERRED from the vendored source:
   - Google (`src/robots.cc`): `MaybeEscapePattern` escapes a rule's non-ASCII bytes as
     upper-case `%HH` and upper-cases the rule's existing escapes. The target is compared as
     given; `src/robots.h` documents that it "must be %-encoded according to RFC3986", so the
     matcher assumes the caller has done it. Nothing is decoded on either side.
   - Bing (`src/vendor/robotstxtbing/src/matcher.h`, `compile_pattern`): a rule's `%HH` has its
     two hex digits upper-cased; nothing is decoded; raw bytes are compared as bytes; the target
     is "verbatim".
   - Yandex (`src/vendor/robotstxtyandex/src/access_matcher.cc`): bytes as written on both
     sides; no escape is upper-cased or decoded.

## The local matrix (TESTED)

One unchanged body, 42 target spellings, 3 modes, 3 backends: 378 cells, each decided, refused
or failed as shown. Run on robotstxtr commit 4598ada (origin/main, 2026-11-23), R 4.6.2. The
WHATWG snapshot is the one `rurl` 3.1.0.9000 implements; `rurl` does not publish the Standard's
commit it follows, so the implementation version is the pin. Under `"whatwg"` the encoding of a
space and of non-ASCII differs between `rurl` 3.0.1, 3.1.0 and its main branch
([ADR 0002](adr/0002-evaluator-url-preprocessing.md) §6), so the `whatwg` columns hold for
3.1.0.9000 only. The block between the markers is the script's output, byte for byte.

<!-- matrix:begin -->

Generated by `data-raw/target-encoding-matrix.R`.

- robotstxtr 0.3.1.9000; rurl 3.1.0.9000
- google backend: `google-robotstxt-22b355ff855419e6a3ff8ff09c0ad7fdb17116f9`
- bing backend: `robotstxtbing/0.1.0+payload.c82855d0756c748cc4770246a19282323cdfa331;contract=robotstxtbing-v2;contract-rev=0.1.0;parser=0.1.0;bingbot=bingbot-2026-07-23.1;adidxbot=adidxbot-2026-07-23.1;manifest=5e79ee5dcb1a22b73b5fa0f86766be529cf111fd5530d07b53fe1d6b7050a858`
- yandex backend: `robotstxtyandex/0.2.0+payload.fdd60a7c3bc6825f3b3752562dc0d6ad9387a27e;profile=yandex-0.1.0;corpus=337b9f3b886a92d6dc08c2fce84228d0cd6b801a;evidence=9d69d361db81e7d236562dc056b41865da33d467d06f316e2c9a20988e007c96;profile-source=337b9f3b886a92d6dc08c2fce84228d0cd6b801a`
- tokens: `Googlebot` (google), `bingbot` (bing), `Yandex` (yandex); ruleset = backend

Body (`User-agent: *` group; line numbers as the matchers report them):

| Line | Bytes |
|---|---|
| 1 | `User-agent:<20>*` |
| 2 | `Disallow:<20>/r/caf<C3><A9>` |
| 3 | `Disallow:<20>/e/caf%C3%A9` |
| 4 | `Disallow:<20>/c/cafe<CC><81>` |
| 5 | `Disallow:<20>/y/<D0><BA><D0><B0><D1><82>` |
| 6 | `Disallow:<20>/j/<E8><B7><AF>` |
| 7 | `Disallow:<20>/h/a%3Cb` |
| 8 | `Disallow:<20>/l/a%3cb` |
| 9 | `Disallow:<20>/s/a%2Fb` |
| 10 | `Disallow:<20>/p/a/b` |
| 11 | `Disallow:<20>/t/~joe` |
| 12 | `Disallow:<20>/u/%7Ejoe` |
| 13 | `Disallow:<20>/w/a%20b` |
| 14 | `Disallow:<20>/v/a<20>b` |
| 15 | `Disallow:<20>/k/` |
| 16 | `Disallow:<20>/d/a%252eb` |
| 17 | `Disallow:<20>/b/a/` |
| 18 | `Disallow:<20>/B/a\b` |
| 19 | `Disallow:<20>/q?k=a%20b` |
| 20 | `Disallow:<20>/q?a='x'` |
| 21 | `Disallow:<20>/q?n=caf%C3%A9` |

Target the matcher reads, per mode (the backend does not change it). `none` is the input as given.

| Id | Spelling | Input path | rfc3986 | whatwg |
|---|---|---|---|---|
| r1 | raw Latin-1 range, raw rule | `/r/caf<C3><A9>` | `/r/caf<C3><A9>` (not a valid RFC 3986 URI: raw non-ASCII) | `/r/caf%C3%A9` (WHATWG URL serialization changed the URL) |
| r2 | raw Latin-1 range, escaped rule | `/e/caf<C3><A9>` | `/e/caf<C3><A9>` (not a valid RFC 3986 URI: raw non-ASCII) | `/e/caf%C3%A9` (WHATWG URL serialization changed the URL) |
| r3 | upper escape, raw rule | `/r/caf%C3%A9` | `/r/caf%C3%A9` | `/r/caf%C3%A9` |
| r4 | upper escape, escaped rule | `/e/caf%C3%A9` | `/e/caf%C3%A9` | `/e/caf%C3%A9` |
| r5 | lower escape, raw rule | `/r/caf%c3%a9` | `/r/caf%c3%a9` | `/r/caf%c3%a9` |
| r6 | lower escape, escaped rule | `/e/caf%c3%a9` | `/e/caf%c3%a9` | `/e/caf%c3%a9` |
| r7 | mixed escape, raw rule | `/r/caf%C3%a9` | `/r/caf%C3%a9` | `/r/caf%C3%a9` |
| r8 | mixed escape, escaped rule | `/e/caf%C3%a9` | `/e/caf%C3%a9` | `/e/caf%C3%a9` |
| c1 | raw combining mark | `/c/cafe<CC><81>` | `/c/cafe<CC><81>` (not a valid RFC 3986 URI: raw non-ASCII) | `/c/cafe%CC%81` (WHATWG URL serialization changed the URL) |
| c2 | escaped combining mark | `/c/cafe%CC%81` | `/c/cafe%CC%81` | `/c/cafe%CC%81` |
| c3 | precomposed form of a combining rule | `/c/caf<C3><A9>` | `/c/caf<C3><A9>` (not a valid RFC 3986 URI: raw non-ASCII) | `/c/caf%C3%A9` (WHATWG URL serialization changed the URL) |
| y1 | raw Cyrillic | `/y/<D0><BA><D0><B0><D1><82>` | `/y/<D0><BA><D0><B0><D1><82>` (not a valid RFC 3986 URI: raw non-ASCII) | `/y/%D0%BA%D0%B0%D1%82` (WHATWG URL serialization changed the URL) |
| y2 | escaped Cyrillic | `/y/%D0%BA%D0%B0%D1%82` | `/y/%D0%BA%D0%B0%D1%82` | `/y/%D0%BA%D0%B0%D1%82` |
| j1 | raw CJK | `/j/<E8><B7><AF>` | `/j/<E8><B7><AF>` (not a valid RFC 3986 URI: raw non-ASCII) | `/j/%E8%B7%AF` (WHATWG URL serialization changed the URL) |
| j2 | escaped CJK | `/j/%E8%B7%AF` | `/j/%E8%B7%AF` | `/j/%E8%B7%AF` |
| h1 | lower ASCII escape, upper rule | `/h/a%3cb` | `/h/a%3cb` | `/h/a%3cb` |
| h2 | upper ASCII escape, upper rule | `/h/a%3Cb` | `/h/a%3Cb` | `/h/a%3Cb` |
| h3 | lower ASCII escape, lower rule | `/l/a%3cb` | `/l/a%3cb` | `/l/a%3cb` |
| h4 | upper ASCII escape, lower rule | `/l/a%3Cb` | `/l/a%3Cb` | `/l/a%3Cb` |
| s1 | %2F target, %2F rule | `/s/a%2Fb` | `/s/a%2Fb` | `/s/a%2Fb` |
| s2 | / target, %2F rule | `/s/a/b` | `/s/a/b` | `/s/a/b` |
| s3 | %2F target, / rule | `/p/a%2Fb` | `/p/a%2Fb` | `/p/a%2Fb` |
| s4 | lower %2f target, %2F rule | `/s/a%2fb` | `/s/a%2fb` | `/s/a%2fb` |
| t1 | ~ target, ~ rule | `/t/~joe` | `/t/~joe` | `/t/~joe` |
| t2 | %7E target, ~ rule | `/t/%7Ejoe` | `/t/%7Ejoe` | `/t/%7Ejoe` |
| t3 | %7e target, ~ rule | `/t/%7ejoe` | `/t/%7ejoe` | `/t/%7ejoe` |
| t4 | ~ target, %7E rule | `/u/~joe` | `/u/~joe` | `/u/~joe` |
| w1 | raw space, %20 rule | `/w/a<20>b` | `/w/a<20>b` (not a valid RFC 3986 URI: raw space) | `/w/a%20b` (WHATWG URL serialization changed the URL) |
| w2 | %20, %20 rule | `/w/a%20b` | `/w/a%20b` | `/w/a%20b` |
| w3 | raw space, raw-space rule | `/v/a<20>b` | `/v/a<20>b` (not a valid RFC 3986 URI: raw space) | `/v/a%20b` (WHATWG URL serialization changed the URL) |
| w4 | %20, raw-space rule | `/v/a%20b` | `/v/a%20b` | `/v/a%20b` |
| d1 | double encoding, control | `/d/a%252eb` | `/d/a%252eb` | `/d/a%252eb` |
| d2 | double-encoded dot segment | `/d/%252e%252e/k/x` | `/d/%252e%252e/k/x` | `/d/%252e%252e/k/x` |
| d3 | single-encoded dot segment | `/d/%2e%2e/k/x` | `/d/%2e%2e/k/x` | `/k/x` (WHATWG URL serialization changed the URL) |
| b1 | backslash, / rule | `/b/a\b` | `/b/a\b` (not a valid RFC 3986 URI: backslash) | `/b/a/b` (WHATWG URL serialization changed the URL) |
| b2 | backslash, backslash rule | `/B/a\b` | `/B/a\b` (not a valid RFC 3986 URI: backslash) | `/B/a/b` (WHATWG URL serialization changed the URL) |
| q1 | query raw space | `/q?k=a<20>b` | `/q?k=a<20>b` (not a valid RFC 3986 URI: raw space) | `/q?k=a%20b` (WHATWG URL serialization changed the URL) |
| q2 | query apostrophe | `/q?a='x'` | `/q?a='x'` | `/q?a=%27x%27` (WHATWG URL serialization changed the URL) |
| q3 | query raw non-ASCII | `/q?n=caf<C3><A9>` | `/q?n=caf<C3><A9>` (not a valid RFC 3986 URI: raw non-ASCII) | `/q?n=caf%C3%A9` (WHATWG URL serialization changed the URL) |
| k1 | ASCII control | `/k/x` | `/k/x` | `/k/x` |
| k2 | ASCII control, no rule | `/z/x` | `/z/x` | `/z/x` |
| i1 | invalid UTF-8 byte (unmarked) | `/r/caf<E9>` | `/r/caf<E9>` (not a valid RFC 3986 URI: raw non-ASCII) | `/r/caf<E9>` (not a valid WHATWG URL: evaluated as given) |

Decision per backend and mode. `D:n` disallowed by line n, `A` allowed by default, otherwise the matcher status or the call error.

| Id | google none | google rfc3986 | google whatwg | bing none | bing rfc3986 | bing whatwg | yandex none | yandex rfc3986 | yandex whatwg |
|---|---|---|---|---|---|---|---|---|---|
| r1 | A | A | D:2 | D:2 | D:2 | A | D:2 | D:2 | A |
| r2 | A | A | D:3 | A | A | D:3 | A | A | D:3 |
| r3 | D:2 | D:2 | D:2 | A | A | A | A | A | A |
| r4 | D:3 | D:3 | D:3 | D:3 | D:3 | D:3 | D:3 | D:3 | D:3 |
| r5 | A | A | A | A | A | A | A | A | A |
| r6 | A | A | A | A | A | A | A | A | A |
| r7 | A | A | A | A | A | A | A | A | A |
| r8 | A | A | A | A | A | A | A | A | A |
| c1 | A | A | D:4 | D:4 | D:4 | A | D:4 | D:4 | A |
| c2 | D:4 | D:4 | D:4 | A | A | A | A | A | A |
| c3 | A | A | A | A | A | A | A | A | A |
| y1 | A | A | D:5 | D:5 | D:5 | A | D:5 | D:5 | A |
| y2 | D:5 | D:5 | D:5 | A | A | A | A | A | A |
| j1 | A | A | D:6 | D:6 | D:6 | A | D:6 | D:6 | A |
| j2 | D:6 | D:6 | D:6 | A | A | A | A | A | A |
| h1 | A | A | A | A | A | A | A | A | A |
| h2 | D:7 | D:7 | D:7 | D:7 | D:7 | D:7 | D:7 | D:7 | D:7 |
| h3 | A | A | A | A | A | A | D:8 | D:8 | D:8 |
| h4 | D:8 | D:8 | D:8 | D:8 | D:8 | D:8 | A | A | A |
| s1 | D:9 | D:9 | D:9 | D:9 | D:9 | D:9 | D:9 | D:9 | D:9 |
| s2 | A | A | A | A | A | A | A | A | A |
| s3 | A | A | A | A | A | A | A | A | A |
| s4 | A | A | A | A | A | A | A | A | A |
| t1 | D:11 | D:11 | D:11 | D:11 | D:11 | D:11 | D:11 | D:11 | D:11 |
| t2 | A | A | A | A | A | A | A | A | A |
| t3 | A | A | A | A | A | A | A | A | A |
| t4 | A | A | A | A | A | A | A | A | A |
| w1 | A | A | D:13 | A | A | D:13 | A | A | D:13 |
| w2 | D:13 | D:13 | D:13 | D:13 | D:13 | D:13 | D:13 | D:13 | D:13 |
| w3 | D:14 | D:14 | A | D:14 | D:14 | A | D:14 | D:14 | A |
| w4 | A | A | A | A | A | A | A | A | A |
| d1 | D:16 | D:16 | D:16 | D:16 | D:16 | D:16 | D:16 | D:16 | D:16 |
| d2 | A | A | A | A | A | A | A | A | A |
| d3 | A | A | D:15 | A | A | D:15 | A | A | D:15 |
| b1 | A | A | D:17 | A | A | D:17 | A | A | D:17 |
| b2 | D:18 | D:18 | A | D:18 | D:18 | A | D:18 | D:18 | A |
| q1 | A | A | D:19 | A | A | D:19 | A | A | D:19 |
| q2 | D:20 | D:20 | A | D:20 | D:20 | A | D:20 | D:20 | A |
| q3 | A | A | D:21 | A | A | D:21 | A | A | D:21 |
| k1 | D:15 | D:15 | D:15 | D:15 | D:15 | D:15 | D:15 | D:15 | D:15 |
| k2 | A | A | A | A | A | A | A | A | A |
| i1 | A | A | A | A | A | A | A | A | A |

<!-- matrix:end -->

### What the local matrix shows

Every row is one target against the one body above. Line numbers refer to that body.

- **Raw non-ASCII** (r1, r2, c1, y1, j1). `"rfc3986"` hands the bytes over as `"none"` does, with
  the note `not a valid RFC 3986 URI: raw non-ASCII`. Google never matches a raw target, because
  `MaybeEscapePattern` turns every rule's non-ASCII into `%HH`; Bing and Yandex match it only
  against a raw rule. `"whatwg"` escapes the target in upper case, which moves the engines in
  opposite directions: Google now matches the raw rule (r1 `D:2`), Bing and Yandex stop matching
  it (r1 `A`), and all three match the escaped rule (r2 `D:3`). Both change directions occur.
- **Escape case of non-ASCII** (r3 to r8). No mode changes the case of an escape the input
  already has, so the three columns of each backend agree. An upper-case target matches an
  upper-case rule on every backend (r4). A lower-case or mixed-case target matches nothing on any
  backend (r5 to r8). Google alone matches an upper-case target against a raw rule (r3).
- **Unicode normalization** (c3). No backend and no mode folds `e` + U+0301 into U+00E9: the
  precomposed target misses the combining rule everywhere. It is the changed-form,
  equal-decision control: `"whatwg"` rewrites it and every cell stays `A`.
- **ASCII escape case** (h1 to h4). Google and Bing upper-case the rule's escape, so a
  lower-case rule matches the upper-case target (h4 `D:8`) and not its own spelling (h3 `A`).
  Yandex compares as written (h3 `D:8`, h4 `A`). A lower-case target never matches an upper-case
  rule (h1).
- **`%2F` and `/`** (s1 to s4). No backend decodes `%2F`, and no backend folds the target's
  escape case (s4 `A`). This is what RFC 9309 §2.2.2 asks for a reserved character, apart from
  the case question.
- **`%7E` and `~`** (t1 to t4). No backend decodes an unreserved escape, so `%7E`, `%7e` and `~`
  are three different targets everywhere. RFC 9309 §2.2.2 decodes an escaped unreserved
  character before comparing, so on t2 to t4 every backend departs from the RFC reading, which
  would disallow (the Google side is catalog `esc-pct7e-rule-tilde-url` and
  `esc-tilde-rule-pct7e-url`).
- **Space** (w1 to w4). The mode decides, and the three backends agree in each mode. Under
  `"none"` and `"rfc3986"` a raw space matches only a raw-space rule; `"whatwg"` sends `%20`,
  which matches the `%20` rule (w1 `D:13`) and no longer the raw-space rule (w3 `A`).
- **Double encoding** (d1 to d3). `%252e` is never decoded in any mode (d2 `A` throughout). The
  single-encoded `%2e%2e` segment (d3) is removed only by `"whatwg"`, which is ADR 0002's dot-
  segment finding, kept here as a control.
- **Backslash** (b1, b2). `"whatwg"` reads `\` as `/` on a special scheme: b1 goes from `A` to
  `D:17`, b2 from `D:18` to `A`, on all three backends.
- **Query serialization** (q1 to q3). `"whatwg"` encodes a space, `'` and non-ASCII in the
  query. q2 is the disallow-to-allow direction: the rule written with `'` stops matching.
  Library-comparison class 20 records the same `'` effect in `rs` and `js`.
- **Controls** (k1, k2). Unchanged in every mode and equal across backends.
- **Invalid UTF-8** (i1, the byte `E9` alone). Evaluated in every mode, never replaced:
  `"rfc3986"` records `raw non-ASCII`, and `"whatwg"` fails and falls back to the input with
  `not a valid WHATWG URL: evaluated as given` (ADR 0002 §6; under ADR 0002 §7 a decided row
  whose `"whatwg"` form fails has `preprocessing_disagreement` `TRUE`). No rule matches the lone
  byte.

### Adapter extraction: an unmarked URL under `LC_ALL=C`

The adapters' extractors take the URL through the `cpp11` boundary, which translates it to UTF-8
from the session's native encoding. Under `LC_ALL=C` the native encoding is ASCII, so an
unmarked URL (`Encoding()` is `"unknown"`) that holds UTF-8 bytes is translated to R's escape
text: `bing_extract_request_target()` and `robotstxtr_extract_request_target_()` both return the
twelve ASCII bytes `/caf<c3><a9>` for the bytes `/caf` `C3 A9`. `matcher_url` still shows the
original bytes, while the backend reads the escape text. The body goes the other way:
`text_body_bytes_v1()` keeps an unmarked body's bytes as written in the C locale
(`native_text_as_written()`). In a first run of the script with unmarked strings (a `\u` escape
parsed under `LC_ALL=C` came out unmarked), r1, c1, y1 and j1 went from `D` to `A` on the bing
and yandex backends under `"none"` and `"rfc3986"`. The UTF-8, `en_US.UTF-8` and `tr_TR.UTF-8`
runs were unaffected. The script now marks its strings UTF-8, and its output is the same in all
four locales. The extraction effect itself is unchanged and is not fixed by this research
issue.

## Client survey (TESTED, localhost, 2026-11-23)

What each client puts in the request line for a URL typed in each spelling. A Node `net`
listener on 127.0.0.1 recorded the request-target bytes and answered `204`; each client was given
`http://127.0.0.1:8765` plus the path as UTF-8 command-line text. `=` means sent as typed;
`refused` means the client raised an error and sent nothing. Raw bytes are shown as `<HH>`.

Clients: curl 8.7.1 (the macOS system copy); libcurl 8.14.1-DEV through R `curl` 8.1.0; GNU
Wget 1.25.0; Python 3.15.2 `urllib.request`; Go 1.27.4 `net/http`; OpenJDK 21.0.13.1
`java.net.http.HttpClient` with `URI.create`; Node 26.13.1 `fetch`; Chrome 157.0.8103.79
headless (`--dump-dom`).

| Typed path | curl, libcurl | wget | Python | Go | Java | Node, Chrome |
|---|---|---|---|---|---|---|
| `/caf<C3><A9>` | `/caf%c3%a9` | `/caf%C3%A9` | refused | `/caf%C3%A9` | `/caf%C3%A9` | `/caf%C3%A9` |
| `/cafe<CC><81>` | `/cafe%cc%81` | `/cafe%CC%81` | refused | `/cafe%CC%81` | `/caf%C3%A9` | `/cafe%CC%81` |
| Cyrillic, CJK (raw) | lower-case escapes | upper-case escapes | refused | upper-case escapes | upper-case escapes | upper-case escapes |
| `/caf%C3%A9`, `/caf%c3%a9`, `/caf%C3%a9` | = | = | = | = | = | = |
| `/a%3cb`, `/a%2Fb`, `/%7Ejoe`, `/%7ejoe`, `/~joe` | = | = | = | = | = | = |
| `/a<20>b` | refused | `/a%20b` | refused | `/a%20b` | refused | `/a%20b` |
| `/a%20b`, `/a/%252e%252e/b` | = | = | = | = | = | = |
| `/a\b` | = | `/a%5Cb` | = | `/a%5Cb` | refused | `/a/b` |
| `/p?q=a<20>b` | refused | `/p?q=a%20b` | refused | = (raw space) | refused | `/p?q=a%20b` |
| `/p?a='x'` | = | = | = | = | = | `/p?a=%27x%27` |
| `/p?q=caf<C3><A9>` | = (raw bytes) | `/p?q=caf%C3%A9` | refused | = (raw bytes) | `/p?q=caf%C3%A9` | `/p?q=caf%C3%A9` |

Findings:

- No client changes the case of an escape it was given, and none decodes `%7E` or `%2F`. Escape
  case therefore reaches the server, and the matcher, as the link was written.
- Raw non-ASCII in the path is escaped by every client that sends it, in upper case except curl
  and libcurl (lower case, 8.7.1 and 8.14.1 alike). This confirms the ROBO-bnvdmdjr research note
  of 2026-11-19 (curl lower, wget, Go, Node and Chrome upper) and adds Java (upper) and Python
  (refuses).
- Java's `URI` normalizes `e` + U+0301 to U+00E9 (NFC) before escaping; no other client does.
- In the query, curl, libcurl and Go send raw non-ASCII bytes; Go even sends a raw space.
- Node `fetch` and Chrome send exactly the `"whatwg"` form in every row; wget and Go send
  upper-case escapes for raw bytes but keep `'` and differ on `\`.

The survey is of HTTP clients, not of crawlers. Which of these behaviors a crawler shares is the
probe's question 1.

## The engine matrix

One row per spelling family, one column per engine. The local-backend part of each cell names
the matrix rows above; `none`, `rfc3986` and `whatwg` are the modes. Google publishes no
URL-decision tester (Search Console's robots.txt report shows fetch status and parse problems, not
a decision for a URL), so every Google tester cell is `not testable`. Every crawler cell, on all
three engines, is `not tested: ROBO-oxfpgdrx`.

| Spelling | Google | Bing | Yandex |
|---|---|---|---|
| Raw Latin-1 range (r1, r2) | INFERRED: rule escaped, target as given. TESTED: raw target matches nothing under none and rfc3986; whatwg matches both rules. Tester: not testable. | TESTED: raw target matches the raw rule only; whatwg flips both rows. OBSERVED B3: raw rule matches nothing (r1 ours `D` under none, rfc3986 disagrees; whatwg agrees); raw target not escaped (r2 `A` agrees under none, rfc3986). | TESTED: as Bing. OBSERVED Y4: raw rule matches nothing (r1 disagrees under none, rfc3986); the tester escapes a raw target in upper case (r2 prohibited, ours `A` disagrees under none, rfc3986; whatwg agrees on r1 and r2). |
| Combining mark (c1 to c3) | TESTED: as raw Latin-1; no NFC (c3). Tester: not testable. | TESTED: as raw Latin-1; no NFC. Tester: not tested: BING-snztgvmf. | TESTED: as Bing. Tester: not tested: YDX-vakiowhn. |
| Cyrillic (y1, y2) | TESTED: y1 as r1, y2 `D:5` in every mode. Tester: not testable. | TESTED: y1 `D:5` under none and rfc3986, y2 `A`. Tester: not tested: BING-snztgvmf. | TESTED: as Bing. OBSERVED Y4 (`каталог`): raw rule matches neither target (y1 disagrees under none, rfc3986; y2 agrees). |
| CJK (j1, j2) | TESTED: as Cyrillic. Tester: not testable. | TESTED: as Cyrillic. Tester: not tested: BING-snztgvmf. | TESTED: as Cyrillic. Tester: not tested: YDX-vakiowhn. |
| Upper-case escape of non-ASCII (r3, r4) | TESTED: matches both rules (r3, r4 `D`). Tester: not testable. | TESTED: r3 `A`, r4 `D:3`. OBSERVED B3 controls: both agree. | TESTED: as Bing. OBSERVED Y4 control: both agree. |
| Lower-case escape of non-ASCII (r5, r6) | INFERRED: rule upper-cased, target not. TESTED: `A` everywhere. Tester: not testable. | TESTED: `A` everywhere. OBSERVED B3 control: `%C3%A9` rule does not match `%c3%a9` (agrees). | TESTED: `A` everywhere. OBSERVED Y4 control: `%C3%A9` rule prohibits `%c3%a9` (r6 disagrees in every mode). |
| Mixed-case escape (r7, r8) | TESTED: `A` everywhere. Tester: not testable. | TESTED: `A` everywhere. Tester: not tested: BING-snztgvmf / BING-mabpuxza. | TESTED: `A` everywhere. INFERRED from Y7 (target escapes upper-cased): r8 would be prohibited. Tester: not tested: YDX-vakiowhn. |
| ASCII escape case, `%3c` (h1 to h4) | INFERRED and TESTED: rule upper-cased; h2, h4 `D`; h1, h3 `A`. Tester: not testable. | TESTED: as Google. OBSERVED rule side (class 11, `body-sr2-bingbot-hexcase-*`): rule upper-cased, agrees. Target side: not tested: BING-mabpuxza. | TESTED: as written; h2, h3 `D`; h1, h4 `A`. OBSERVED Y7: h1 prohibited (disagrees), h2 agrees, h3 allowed (disagrees), h4 agrees. |
| `%2F` and `/` (s1 to s4) | TESTED: only s1 `D`; INFERRED: never decoded (library-comparison class 13). Tester: not testable. | TESTED: as Google. Tester: not tested: BING-mabpuxza. | TESTED: as Google. OBSERVED Y7 control: `%2F` rule prohibits `%2F` and `%2f`, not `/` (s1, s2 agree; s4 disagrees); s3: not tested: YDX-vakiowhn. |
| `%7E` and `~` (t1 to t4) | TESTED: only t1 `D`; catalog rows agree. Tester: not testable. | TESTED: as Google. Tester: not tested: BING-mabpuxza. | TESTED: as Google. Tester: not tested: YDX-vakiowhn. |
| Raw space and `%20` (w1 to w4) | TESTED: mode decides (w1, w3 flip under whatwg). Tester: not testable. | TESTED: as Google. Tester: not tested: BING-mabpuxza. | TESTED: as Google. Tester: not tested: YDX-vakiowhn. |
| Double encoding (d1 to d3) | TESTED: `%252e` never decoded; d3 only under whatwg. Tester: not testable. | TESTED: as Google. Tester: not tested: BING-mabpuxza. | TESTED: as Google. Tester: not tested: YDX-vakiowhn. |
| Backslash (b1, b2) | TESTED: whatwg reads `\` as `/`, both directions. Tester: not testable. | TESTED: as Google. Tester: not tested: BING-mabpuxza. | TESTED: as Google. Tester: not tested: YDX-vakiowhn. |
| Query serialization (q1 to q3) | TESTED: whatwg encodes space, `'`, non-ASCII. Tester: not testable. | TESTED: as Google. Tester: not tested: BING-mabpuxza. | TESTED: as Google. Tester: not tested: YDX-vakiowhn. |
| Equal-decision controls (k1, k2, c3) | TESTED: equal in every mode. Tester: not testable. | TESTED: equal. Tester: not tested: BING-mabpuxza. | TESTED: equal. Tester: not tested: YDX-vakiowhn. |
| Invalid UTF-8 (i1) | TESTED: evaluated, `A`; whatwg fails with its note. Tester: not testable. | TESTED: as Google. Tester: not testable: the tester's JSON transport carries text, not arbitrary bytes. | TESTED: as Google. Tester: not testable: the analyzer's form carries text, not arbitrary bytes. |

## Symmetry check

Each one-engine finding, with its counterparts on the other two engines.

| Finding | Google | Bing | Yandex |
|---|---|---|---|
| Y4: the Yandex tester escapes a raw target, upper case; a raw rule matches nothing | not testable (no tester); INFERRED: raw rule escaped, target as given; TESTED r1, r2 | OBSERVED B3: raw rule matches nothing, raw target not escaped | the finding |
| Y7: the Yandex tester upper-cases target escapes, keeps the rule's case | not testable; INFERRED: rule upper-cased, target not; TESTED h1 to h4 | OBSERVED B3 control: target escape case kept; class 11: rule upper-cased | the finding |
| B3: Bing's raw rule matches nothing; raw target not escaped | not testable; TESTED r1, r3 | the finding | OBSERVED Y4: same rule finding, opposite target finding |
| engine-disagreements class 6 (raw non-ASCII rule) | TESTED r1, c1, y1, j1 | TESTED same rows | TESTED same rows |
| engine-disagreements class 11 (lower-case escape rule) | TESTED h3, h4 | TESTED h3, h4; OBSERVED rule side | TESTED h3, h4; OBSERVED Y7 |
| library-comparison class 13 (`%2F`, `%7E`, escape case) | TESTED s, t, h rows | TESTED same rows | TESTED same rows |
| library-comparison class 14 (lower-case escape rule) | TESTED h3, h4 | TESTED h3, h4 | TESTED h3, h4 |
| library-comparison class 15 (raw non-ASCII URL or rule) | TESTED r1, r2 | TESTED r1, r2 | TESTED r1, r2 |
| library-comparison class 16 (raw space in a rule) | TESTED w3, w4 | TESTED w3, w4 | TESTED w3, w4 |
| library-comparison class 20 (query serialization) | TESTED q1 to q3 | TESTED q1 to q3 | TESTED q1 to q3 |

The two testers disagree with each other on the target side: Yandex's escapes a raw target and
upper-cases escapes, Bing's does neither. They agree on the rule side: a raw non-ASCII rule
matches nothing. Neither is crawler evidence.

## Crawler-request probe (for ROBO-oxfpgdrx)

A fixture set to serve on the test origins next to the dot-segment probes from ROBO-bnvdmdjr, so
that one run answers both. It answers the ticket's two crawler questions: what each crawler
requests for a link written in a given spelling (1), and which form it compares with robots.txt
(2). Synthetic paths only.

**Serving.** `/robots.txt` and an HTML page `/tv/links.html` (`<meta charset="utf-8">`, served as
`text/html; charset=utf-8`), linked from the origin's crawled pages, plus a sitemap listing the
same URLs, so the link and sitemap channels can be told apart (an `<a href>` with raw UTF-8 and a
sitemap `<loc>` may be read differently). Log, for every request: the date, the `User-Agent`, the
reverse-DNS verification of the client, and the request-target bytes exactly as received (before
any server normalization). A request the edge rewrites before logging is useless.

**Question 1: what is requested.** Links under `/tv/a/`, with no rule covering them:

| Id | Link as written |
|---|---|
| a1 | `/tv/a/1/café` (raw UTF-8) |
| a2 | `/tv/a/2/caf%c3%a9` |
| a3 | `/tv/a/3/caf%C3%A9` |
| a4 | `/tv/a/4/caf%C3%a9` |
| a5 | `/tv/a/5/cafe` + U+0301 (raw) |
| a6 | `/tv/a/6/кат` (raw) |
| a7 | `/tv/a/7/路` (raw) |
| a8 | `/tv/a/8/a b` (raw space) |
| a9 | `/tv/a/9/%7Ejoe` |
| a10 | `/tv/a/10/a%2Fb` |
| a11 | `/tv/a/11/a%3cb` |
| a12 | `/tv/a/12/%252e%252e/x` |
| a13 | `/tv/a/13/a\b` |
| a14 | `/tv/a/14/p?q=a b` |
| a15 | `/tv/a/15/p?a='x'` |
| a16 | `/tv/a/16/p?q=café` |

**Question 2: which form is compared.** Each directory has one rule, in one spelling, and links in
the other spellings. A link that is not fetched while the allowed control is fetched in the same
session means the crawler matched it to the rule.

| Rule in `/robots.txt` | Links | Reading |
|---|---|---|
| `Disallow: /tv/q1/caf%C3%A9` | `/tv/q1/café`, `/tv/q1/caf%c3%a9` | raw link blocked: the crawler escapes it before comparing; lower-case link blocked: it folds escape case |
| `Disallow: /tv/q2/caf%c3%a9` | `/tv/q2/caf%C3%A9`, `/tv/q2/caf%c3%a9`, `/tv/q2/café` | which spellings a lower-case rule reaches (Google and Bing upper-case it, Yandex's tester keeps it) |
| `Disallow: /tv/q3/café` | `/tv/q3/café`, `/tv/q3/caf%C3%A9`, `/tv/q3/caf%c3%a9` | whether a raw rule is live (B3, Y4: not in the testers) |
| `Disallow: /tv/q4/a%3Cb` | `/tv/q4/a%3cb`, `/tv/q4/a%3Cb` | target escape case for ASCII (Y7) |
| `Disallow: /tv/q5/a%3cb` | `/tv/q5/a%3cb`, `/tv/q5/a%3Cb` | rule escape case for ASCII (class 11) |
| `Disallow: /tv/q6/%7Ejoe` | `/tv/q6/~joe`, `/tv/q6/%7ejoe` | unreserved escapes decoded (RFC 9309 §2.2.2) |
| `Disallow: /tv/q7/a%20b` | `/tv/q7/a b`, `/tv/q7/a%20b` | space encoded before comparing |
| `Disallow: /tv/q8/a%2Fb` | `/tv/q8/a/b`, `/tv/q8/a%2fb` | reserved escape kept; target escape case |
| `Disallow: /tv/qc/` | `/tv/qc/x` | blocked control: shows the crawler read this robots.txt |
| (none) | `/tv/ok/x` | allowed control: shows the crawler visited in this session |

A link that is fetched in a spelling different from the one written answers question 1 for that
link, and then the question-2 reading applies to the form requested, not the form written.
Record the requested bytes with each fetch, so the two can be separated.

## Proposal for the maintainer (not implemented)

What the evidence supports so far: no client changes an escape's case, so a target's escape case
is the link author's choice and reaches the matcher unchanged; clients disagree on how they
escape raw bytes (curl and libcurl lower case, the rest upper case, Python and Java refusing
some); Google's matcher assumes an RFC 3986-encoded target; and only the Yandex tester
canonicalizes the target. No crawler has been observed. The proposal therefore keeps every
default as it is until ROBO-oxfpgdrx reports.

- **Google: an opt-in step that escapes raw bytes the way `MaybeEscapePattern` escapes a rule.**
  Each byte at or above `0x80` becomes upper-case `%HH`; existing escapes, their case, `%2F` and
  `%7E` stay as they are. It would be recorded like dot-segment removal: `matcher_url` keeps the
  escaped form and `url_preprocessing_note` says the raw bytes were escaped. With it, r1, r2, c1,
  y1, j1 and q3 decide as their upper-case escaped spellings do, as `src/robots.h` assumes. Today
  `"whatwg"` does this and more (backslash, query `'`, `%2e` segments, host); the narrower step
  isolates the encoding. Whether a raw space also becomes `%20` is part of the decision: RFC 3986
  requires it, `MaybeEscapePattern` does not do it to rules, and w3 shows the decision moving.
- **Bing: no target conversion.** B3 shows Bing's tester neither escapes a raw target nor folds
  escape case, which the backend already does. The rule-side finding (a raw rule matches nothing)
  belongs to BING-snztgvmf and BING-yhfmjkuj, not the evaluator.
- **Yandex: target canonicalization in the backend, not the evaluator.** Y4 and Y7 show the
  analyzer escaping a raw target and upper-casing the target's escapes. That is Yandex matching
  semantics, so it belongs in robotstxtyandex (YDX-vakiowhn, then YDX-vgomfspr; ROBO-polznjqh),
  and `matcher_url` keeps the caller's form. If the sibling declines it, the fallback is an
  evaluator step for the yandex backend, recorded with a note.
- **rfc9309 backend:** `capability_unavailable`; no proposal. No engine here follows RFC 9309
  §2.2.2 on unreserved escapes (t2 to t4).
- **Optional: client families in `disagreement_clients`.** When the `"rfc3986"` and `"whatwg"`
  forms differ only in how raw bytes are escaped, name the surveyed families (curl and libcurl:
  lower-case escapes; wget, Go, Java, Node, Chrome: upper case), as ADR 0002 §7 does for dot
  segments.

Decisions asked of the maintainer:

1. Google: add the opt-in escape step (and whether it covers a raw space), and whether it may
   become the google default once crawler evidence agrees.
2. Yandex: confirm that target canonicalization belongs to the sibling backend.
3. Whether to extend `disagreement_clients` with the escape families.

Any of these amends ADR 0002 or takes a new ADR, and is filed as its own implementation issue
once decided. The C-locale extraction effect above is a separate defect candidate.

## Reproducing

From the package root, on the commit named above:

```sh
Rscript data-raw/target-encoding-matrix.R > matrix.md
sed -n '/^<!-- matrix:begin/,/^<!-- matrix:end/p' design/target-encoding-matrix.md > doc.md
diff matrix.md doc.md
```

An empty diff means the embedded block is the script's output. Under `LC_ALL=C`,
`LC_ALL=en_US.UTF-8` and `LC_ALL=tr_TR.UTF-8` the output is the same. A different `rurl` changes
the `whatwg` columns, and a backend release changes its revision line and possibly its decisions;
regenerate and re-read then.
