# Google source audit: findings record (ROBO-zjkemhjf)

What the 2026-11-18 source audit of the pristine google/robotstxt matcher
found, and where each of its families now lives: already covered by a
committed test, newly pinned, refuted or corrected, or deferred. The audit's
evidence (bodies, manifest, results, comparison) stayed in gitignored scratch;
this record and the fixtures it names are the committed outcome
(ROBO-vxmeoqcr). It decides nothing about Googlebot in production: every
answer here is the library's.

## The run, as history

- **Reference.** google/robotstxt at `22b355ff855419e6a3ff8ff09c0ad7fdb17116f9`,
  the SHA the vendored matcher pins. `robots.cc` SHA-256
  `d05a7fa74c0e8b9fc440d15f4c3ae9a80873c0d950e569de2926303fd75ed473`, `robots.h`
  SHA-256 `912f3a5c6821f8a9a97269f9598b7f29ac1edf1ee20e173f1dd2d9ca48fb0bd5`,
  built fresh for the run; `RobotsMatcher::OneAgentAllowedByRobots()` on the raw
  body bytes, then `matching_line()`.
- **Date and package.** 2026-11-18, robotstxtr `main` at `c36db93`.
- **Scope.** 122 cases in 11 families: index 39, colon 14, longline 12,
  agents 11, groups 9, keys 8, escapes 8, bom 7, lines 6, priority 6, url 2.
  Counts are cases, neighboring controls included, not independent findings.
- **robotstxtr's side.** `robots_evaluate_text_v1(body, url, token, "google",
  backend)` for the `google`, `bing` and `yandex` backends, the neutral agent
  renamed `bingbot` and `Yandex` for the last two. The vendored backends were
  Bing library 0.1.0 (`inst/vendor/robotstxtbing/PROVENANCE`) and Yandex
  library 0.2.0 (`inst/vendor/robotstxtyandex/PROVENANCE`), unchanged since
  `af46733` and `055880e`.
- **Counts.** Google agreed with the reference on 122/122 decisions. Bing
  differed on 44/120 and Yandex on 47/120 (the two NUL cases ran on Google
  only). These are local compatibility-backend results on the scratch bodies,
  not vendor observations, and they are history: the pins below record the
  backends' current answers on the cases this record promotes, and a
  deliberate backend correction (ROBO-traxexwm, ROBO-oxfpgdrx) changes those
  pins, not these counts.
- **Since then.** ADR 0002 (`design/adr/0002-evaluator-url-preprocessing.md`)
  made `url_normalization = "rfc3986"` the v1 default after the run. Under it
  the v1 facades leave userinfo out, so today `https://u;v@example.com/x` is
  disallowed on v1 where the run, and the reference, allowed it. The 122/122
  was measured before that change.

## Where the families live now

The committed fixtures are `gf_cases()` in
`tests/testthat/fixtures/google-fidelity-deehqhlc/cases.R`. Each promoted case
carries its scratch id as a trailing comment, and
`tests/testthat/test-google-fidelity-deehqhlc.R` pins every robotstxtr Google
path against the reference answer it records; `dev/google-fidelity/differential.R`
re-derives those answers from a reference binary (`design/engine-profiles.md`
§5b).

| Scratch family (cases) | Disposition | Where |
|---|---|---|
| index (39): index-0 to index-29, index-priority-tie, index-priority-loses, index-asymmetry, review-index-95 to review-index-100 | ROBO-yuqtnqbj's | the `index` family; the promoted cases name their scratch ids. That ticket disposes of the rest |
| bom (7): bom-33 to bom-39 | already covered | the partial-BOM note in `test-prefix-key-xglcoagv.R` ("a leading BOM is not part of the first key"), `test-misplaced-bom-atkmqcov.R`, gf `eol-bom` and `eol-bom-crlf` |
| keys (8): key-Disallow, key-Disallowed, key-Disallowance, key-DisallowAITraining, key-DissallowXYZ, key-DisalowSuffix, key-Disallox, key-XDisallow | already covered | `test-prefix-key-xglcoagv.R`, `test-engine-disagreements-glssaxva.R` classes 13 and 14 (`design/engine-disagreements.md`), gf `typo-*` |
| groups (9): group-54 to group-62 | already covered | `test-wildcard-inheritance-gfjotdrr.R`, `test-engine-disagreements-glssaxva.R` class 1 |
| agents (11): ua-63 to ua-69 | already covered | gf `ua-*`, `test-user-agent-cut-zvhrayhx.R`, `test-user-agent-cut-effect-txnzyugl.R` |
| agents: star-70 to star-73 | already covered | "`*` followed by any isspace byte is global, as in the matcher" in `test-wildcard-inheritance-gfjotdrr.R` |
| escapes (8): escape-74 to escape-81 | already covered | gf `target` family |
| lines (6): eol-89 to eol-92 | already covered | gf `eol-*` |
| lines: nul-ua, nul-value | already covered, with a caveat | gf `nul` family (class 5, resolved). The scratch NUL cases went through robotstxtr's acquired-body decoding before the text facade; the public text API takes no embedded NUL, so they test the fetched paths' decoding, not the text API |
| longline: long-85 to long-88 | already covered | gf `long-*`, catalog `size-long-line` |
| longline: review-truncation-110 to 113, review-truncation-control-118 and 119, review-truncation-fullvalue-120 and 121 | newly pinned | gf `truncation` |
| colon: colon-49, colon-51, colon-52, review-colon-101 to review-colon-106 | newly pinned | gf `colon`; colon-49 and review-colon-105, and colon-52 and review-colon-106, are one case each |
| colon: colon-48 | already covered | gf `typo-no-colon` (`Disallow /x` blocks `/x`) |
| colon: colon-50, colon-53, review-whitespace-114 and 115 | newly pinned | gf `whitespace` |
| priority: review-star-107 to 109, wildcard-83, wildcard-84 | newly pinned | gf `priority` |
| priority: wildcard-82 | already covered | `wc-star-vs-allow` in `test-library-comparison-dqqkvwts.R` (`design/library-comparison.md` class 9) |
| url: review-userinfo-116, review-userinfo-117 | newly pinned on the legacy paths | gf `userinfo`; v1 and Bing/Yandex already in `test-url-preprocessing-bnvdmdjr.R` |

The newly pinned families, in the reference's words:

- **colon.** `RobotsTxtParser::GetKeyAndValueFrom()` strips the comment, then
  splits at the first `:`. Only a line with no colon falls back to the first
  space or tab, and that fallback refuses a value with a second token. A key
  that starts with `Disallow` is a Disallow. So `Disallow /ignored:/target`
  blocks `/target` and leaves `/ignored` allowed; `Disallow /x:y` blocks
  neither `/x` nor `/x:y` (its value is `y`), while `Disallow: /x:y` blocks
  `/x:y`; `Disallow /x extra` blocks nothing, and `Disallow /x # ignored`
  blocks `/x`.
- **whitespace.** The fallback separators are space and tab only, but the key
  is trimmed with `AsciiIsSpace()`, which strips a vertical tab. So
  `Disallow<VT>/x` blocks nothing, `Disallow<VT>:/x` blocks `/x`, and a tab or
  space before a second word leaves no rule (upstream's missing-colon fallback
  rejects it). A VT is no separator: `/x<VT>extra` is the whole value, a
  Disallow rule that does not match `/x`.
- **truncation.** `RobotsTxtParser::Parse()` keeps 16,663 bytes of a line
  (`kMaxLineLen - 1`, with `kMaxLineLen = 2083 * 8`). With one line of
  `Disallow /x` (11 bytes), N spaces and `: /y`, N decides what survives: N=1
  and N=16,648 (the line is exactly 16,663 bytes) keep `: /y`, so `/y` is
  blocked and `/x` is not; N=16,649 keeps `: /`, which blocks both; N=16,650
  (`: `) and N=16,651 (`:`) keep an empty value, which blocks nothing and is
  §5b class 1 (the reference reports line 2, robotstxtr no line); N=16,652
  keeps no colon, so the fallback reads `Disallow /x` and blocks `/x` only.
  N=1 and N=16,650 were not in the scratch run; their answers come from the
  reference binary.
- **userinfo.** `GetPathParamsQuery()` looks for the first `/`, `?` or `;`
  after the scheme, with no authority parse, so with `Disallow: /x` the target
  of `https://u;v@example.com/x` is `/;v@example.com/x` (allowed), while
  `https://u%3Bv@example.com/x` is `/x` (disallowed).
- **priority.** A pattern's priority is its length as written, stars
  included, and an Allow wins a tie. `Disallow: /p*` beats `Allow: /p` on `/p`
  (3 against 2), as does `/p**`; without the star, the Allow wins.
  `Disallow: /a**` ties `Allow: /abc` at 4, so the Allow wins; `/a***` wins
  at 5.

## Refuted or corrected predictions

Three scratch predictions were wrong. The observed answers above are the
reference's, and the fixtures record them; nothing is pinned as an expected
failure.

- **wildcard-83** predicted `/abc` disallowed by `Disallow: /a**` against
  `Allow: /abc`. Both patterns are 4 bytes, so the tie goes to the Allow. A
  counting error, not an exception.
- **review-truncation-113** (N=16,651, `/y`) predicted disallowed: a retained
  colon was taken to retain a value. The cut leaves `Disallow /x` plus spaces
  plus `:`, an empty value, which blocks nothing.
- **review-truncation-control-118** (N=16,649, `/x`) predicted allowed, from a
  10-byte `Disallow /x`. It is 11 bytes, so `: /` survives and `/` blocks `/x`.

## Deferred, unexecuted

No parity claim is made for either; neither was run against the reference or
robotstxtr.

- **The multi-token API.** Upstream's `AllowedByRobots()` with several agents
  shares one priority hierarchy across every matching token, where its header
  says "allowed by any member". robotstxtr exposes one caller token per row, so
  nothing here compares it.
- **Standalone `//` extraction.** `GetPathParamsQuery()` skips exactly two
  leading slashes of an input with no scheme (`//a/x` reads as `/x`). A
  scheme-less URL is already screened on the URL paths (§5b class 4), so this
  stays an upstream-only characterization.

## Layers kept apart

The fidelity fixtures compare matching. Three other layers decide some of the
same inputs, and the record does not mix them with it:

- **Facade screening.** robotstxtr refuses an empty URL or token, a URL that
  is not HTTP(S) on the URL paths, and a v1 caller token that is not an RFC
  9309 identifier (§5b class 4). No facade refuses a userinfo target URL.
- **URL preprocessing.** The legacy paths (`allowed_by_robots_text()`,
  `allowed_by_robots_url()`) match the URL as given, so they agree with the
  reference on both userinfo cases; the v1 paths leave userinfo out first
  (ADR 0002, `url_normalization`), which is preprocessing, not screening. The
  fetch side is separate again: `robots_origin` builds the robots.txt URL
  without userinfo, and a redirect that carries credentials is refused as
  `userinfo` ("a redirect carrying credentials is refused as userinfo",
  `test-acquire-jbralthm.R`).
- **Byte decoding and application limits.** A fetched body is decoded before
  matching (the NUL cases above); the 512,000-byte window and the `max_bytes`
  cut are application limits (§5b classes 2 and 3, §7). The 16,663-byte line
  buffer is the matcher's own and is pinned here as matching.

## Documentation tensions and live questions

Tensions between Google's public documentation and the library source; none
is evidence about what Googlebot does:

- **Trailing `*`.** Google's path-matching documentation treats a trailing `*`
  as ignored, yet it changes priority (`/p*` beats `Allow: /p`). Equivalent
  matching sets need not mean equivalent precedence.
- **Field-name prefixes.** The documented field list is closed, but any key
  that starts with `disallow`, `allow` or `user-agent` acts as that field
  (§5b `typo` family; `design/engine-disagreements.md` classes 13 and 14).
- **Per-line truncation.** The documentation gives the 500 KiB file limit and
  says nothing of the 16,663-byte line buffer.
- **The index fallback.** Upstream's test comment names only a final
  `index.html`; the code accepts any suffix after `/index.htm` (the `index`
  family, ROBO-yuqtnqbj).

Live questions are routed, not answered here: production-crawler evidence to
ROBO-oxfpgdrx; the field-prefix and AI-training key collisions, and an upstream
issue, to ROBO-coxzradt; Bing and Yandex tester checks to ROBO-traxexwm.

## Pins

- `tests/testthat/test-google-fidelity-deehqhlc.R` covers every gf case this record names on
  every robotstxtr Google path: the `v1_text` rows under every ruleset,
  `allowed_by_robots_text()`, `allowed_by_robots_url()` and
  `robots_evaluate_url_v1()`, save the `userinfo` cases, which run on the two
  legacy paths only (`gf_given_url_paths`).
- `tests/testthat/test-google-source-audit-zjkemhjf.R` pins the Bing and
  Yandex backends' current answers on the same cases, each with its own
  ruleset.
