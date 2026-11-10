# Cross-engine disagreement classes (ROBO-glssaxva)

- Status: triage record, 2026-11-10
- Pins: `tests/testthat/test-engine-disagreements-glssaxva.R`
- Tester questions for the unevidenced classes: ROBO-bpywsjwv
- Related: `design/engine-profiles.md` §5 (group selection), §5b (Google
  fidelity), §8 and §10 (sources)

## Method

The candidate list came from a private corpus run of the three backends.
Nothing from that run is recorded here: every fixture below is synthesized,
on `example.com`.

For each candidate cause, a minimal body and path go through
`robots_evaluate_text_v1()` under the `google` ruleset, four times:

| Row | `matcher_backend` | `robots_product_token` |
|---|---|---|
| `google_yandex` | `google` | `Yandex` |
| `yandex` | `yandex` | `Yandex` |
| `google_bingbot` | `google` | `bingbot` |
| `bing` | `bing` | `bingbot` |

A supplied body is `use_rules` under every ruleset (`design/engine-profiles.md`
§2, `[application_choice]`), so the ruleset never changes a row: every
difference is the backend's. Each fixture is then varied (with and without a
blank line, other directives, other suffixes, the inverse URL form) until the
cause is isolated, and the decision, reason and matched line are recorded for
each row. Every live class is pinned. Some refuted candidates are pinned too:
the Yandex form of class 1 (its own stacking test), the Bing form of class 4,
and the `*%*` shape of class 9 (pinned in class 10). Class 5 and class 9's
other forms are listed, not pinned.

Verdicts:

- **EXPECTED-SOURCED**: a source says the engine behaves as our backend does:
  a vendor document, the RFC, or a tester observation already in this
  repository (`inst/bing-corpus`, `inst/yandex-corpus`, the Bing contract in
  `design/robotstxtbing-v2-spec.md`).
- **OUR BUG**: our backend contradicts its own source or contract.
- **UNEVIDENCED**: no source either way. The backend's behavior is a project
  choice; the tester question for ROBO-bpywsjwv is given.

The Google side of every class is the vendored matcher, which
`design/engine-profiles.md` §5b checks against the pinned upstream, and Google's
robots.txt spec as `design/edge-case-catalog.md` "Sources" quotes it.

Outcomes below read `decision reason line`; `default` means
`allow default_allow`, no line.

## Summary

| # | Class | Differs on | Verdict |
|---|---|---|---|
| 1 | A non-rule line ends a stacked `User-agent` run | bing | EXPECTED-SOURCED |
| 1b | An unknown field (`Content-Signal:`) ends a stacked `*` run before a `__usage_ai-training` group | bing | EXPECTED-SOURCED |
| 2 | A leading UTF-8 BOM | yandex, bing | UNEVIDENCED |
| 3 | A `User-agent` value with a suffix | yandex, bing | Yandex space form EXPECTED-SOURCED; the rest UNEVIDENCED |
| 4 | Whitespace before the colon | yandex | UNEVIDENCED |
| 5 | A blank line inside a group | none | refuted |
| 6 | Raw non-ASCII bytes in a rule | yandex, bing | UNEVIDENCED |
| 7 | CR CR LF line endings | yandex, bing | UNEVIDENCED |
| 8 | Lone CR line endings | yandex, bing | UNEVIDENCED |
| 9 | A literal `%` in a pattern | yandex, through class 10 | refuted as a cause |
| 10 | Yandex rule length ignores `*` and a final `$` | yandex | EXPECTED-SOURCED |
| 11 | A lower-case escape in a rule | yandex | UNEVIDENCED |
| 12 | An empty `User-agent` value | yandex | UNEVIDENCED |
| 13 | A key that starts with `disallow` or `allow` | yandex, bing | EXPECTED-SOURCED |

No class is OUR BUG: every backend does what its contract says. Most rows have
Google disallowing where the other engine allows. The rows where Google allows
and the other engine disallows are class 10's `/page` shape, class 11's
`/a%3cb` path, class 6's raw `/café` path, class 1's later-`bingbot`
`Disallow` shape and class 13's `Allow`-prefixed key (below).

## Classes

### 1. A non-rule line ends a stacked `User-agent` run (bing)

Fixture: `User-agent: bingbot` / `Crawl-delay: 10` / `User-agent: *` /
`Disallow: /private`, path `/private`; the same with a blank line before the
second `User-agent`, and with `Sitemap`, `Host` or `Clean-param` in place of
`Crawl-delay`.

| Row | Outcome |
|---|---|
| `google_yandex`, `yandex`, `google_bingbot` | `disallow rule_disallow 4` (5 with the blank line) |
| `bing` | default |

Google reads every line that is not `User-agent`, `Allow` or `Disallow` as
transparent, so `bingbot` and `*` share one group. Bing seals `bingbot`'s
group at the `Crawl-delay`, `Sitemap` or unknown field; the group holds no
rule, and Bing does not fall back to `*` for a tier that has a group. Bing
knows only `User-agent`, `Allow`, `Disallow`, `Sitemap` and `Crawl-delay`
(`design/robotstxtbing-v2-spec.md` §9.2), so `Host`, `Clean-param`,
`Request-rate` and `Noindex` are unknown fields to it, and each seals the run
(the last two pinned on their own). A comment line stays transparent on all
four rows.

A later `bingbot` group then decides Bing's answer, either way round. With
`User-agent: bingbot` / `Allow: /priv` after the fixture, Bing answers
`allow rule_allow 7` where Google answers `disallow rule_disallow 4`. With
`User-agent: bingbot` / `Crawl-delay: 10` / `User-agent: *` /
`Allow: /private` / blank / `User-agent: bingbot` / `Disallow: /private`, path
`/private`, Google (and Yandex, through `*`) answers `allow rule_allow 4` and
Bing answers `disallow rule_disallow 7`.

Verdict: EXPECTED-SOURCED. Bing: `design/robotstxtbing-v2-spec.md` §9.3 rule 2a
(`BING-aosnpswm`), from the tester's `crawl-delay-stacked` cell on two dates
and the `stacked-ctl-v1` control (Crawl-delay, Sitemap and an unknown field
end the run; a blank or comment line does not). Google: the spec's "Rules
other than allow, disallow, and user-agent are ignored by the robots.txt
parser", with its `sitemap` example. RFC 9309 is read two ways here (Adjacent
findings).

The Yandex form of this candidate is refuted. Our Yandex parser knows
`User-agent`, `Allow`, `Disallow`, `Sitemap`, `Clean-param` and `Crawl-delay`
(`Host` and any other name are unknown fields to it) and keeps a stacked run
across every non-rule line: `User-agent: Yandex` / `<line>` /
`User-agent: Other` / `Disallow: /private`, with `<line>` each of
`Crawl-delay`, `Clean-param`, `Host`, `Sitemap`, `Foo: bar` and a comment, is
`disallow rule_disallow 4` for the Yandex token on both `google_yandex` and
`yandex`. Google knows neither `Host` nor `Clean-param`.

#### 1b. An unknown field seals a `*` run before a policy token (bing)

Fixture: `User-agent: *` / `Content-Signal: ai-train=no` /
`Sitemap: https://example.com/sitemap.xml` / blank / blank /
`User-agent: __usage_ai-training` / `Disallow: /`, path `/`; the same without
the `Sitemap` line; and a control with neither line.

| Row | With `Sitemap` | `Content-Signal` alone | Control |
|---|---|---|---|
| `google_yandex`, `yandex`, `google_bingbot` | `disallow rule_disallow 7` | `disallow rule_disallow 6` | `disallow rule_disallow 5` |
| `bing` | default | default | `disallow rule_disallow 5` |

Google and Yandex stack `__usage_ai-training` onto `*`, since nothing between
the two `User-agent` lines is a rule, so the `Disallow: /` applies to every
crawler. Bing seals the `*` run at `Content-Signal`, an unknown field, and the
`*` group holds no rule. The blank lines alone seal nothing: the control
stacks on all four rows.

This shape decides how an aipref `__usage_ai-training` group
(draft-kelley-aipref-training-preference-signal) reads under Google-style
stacking: a training opt-out written after a `*` group that holds only
non-rule lines becomes a full `Disallow` for every crawler. The validator side
is ROBO-kzyfejcv.

Verdict: EXPECTED-SOURCED, on class 1's sources
(`design/robotstxtbing-v2-spec.md` §9.3 rule 2a).

### 2. A leading UTF-8 BOM (yandex, bing)

Fixture: `EF BB BF` then `User-agent: *` / `Disallow: /private`, path `/private`.

| Row | Outcome |
|---|---|
| `google_yandex`, `google_bingbot` | `disallow rule_disallow 2` |
| `yandex`, `bing` | default |

Google skips one leading BOM. The Yandex and Bing backends keep it as part of
the first line, so the field name is `BOM+User-agent`, unknown, and the rules
have no group. Only the first line is lost: with a comment as line 1, all four
rows agree.

Verdict: UNEVIDENCED. Bing: `design/robotstxtbing-v2-spec.md` §9.1 ("never
strips a BOM") is project behavior, chosen "because the tester editor cannot
establish arbitrary byte identity". Yandex: `design/engine-profiles.md` §8,
Yandex UTF-8/BOM `[documentation_gap]`. Google: "File format" (a leading BOM is
ignored), `src/robots.cc` `utf_bom`. Skipping the BOM would change the Bing
contract's frozen scanner rule and the frozen `yandex-0.1.0` profile.

### 3. A `User-agent` value with a suffix (yandex, bing)

Fixture: `User-agent: bingbot<suffix>` / `User-agent: Yandex<suffix>` /
`Disallow: /private`, suffix `/2.0`, ` 2.0` or `*`; and
`User-agent: bingbot, Yandex` / `Disallow: /private`.

| Row | Suffix fixtures | List fixture |
|---|---|---|
| `google_yandex` | `disallow rule_disallow 3` | default |
| `yandex` | default | default |
| `google_bingbot` | `disallow rule_disallow 3` | `disallow rule_disallow 2` |
| `bing` | default | default |

Google's `ExtractUserAgent` keeps the leading run of `[A-Za-z_-]`, so
`bingbot/2.0`, `bingbot 2.0`, `bingbot*` and `bingbot, Yandex` all read as the
first token. Yandex and Bing compare the whole value.

Verdict, split:

- Yandex, space-separated suffix: EXPECTED-SOURCED. The accepted Yandex corpus
  case `ydx-parser-ua-trailing-token` (`User-agent: Yandex extra` does not
  select the Yandex group; observations 2026-07-15 and 2026-07-17).
- Yandex `/`, `*` and list forms; every Bing form: UNEVIDENCED. Bing's
  contract compares complete group tokens: each profile's group-selection
  table lists the "accepted complete group tokens at each tier", with no
  "substring matching" (`design/robotstxtbing-v2-spec.md` §8), and the table
  itself is the §17 `BING-V2-BINGBOT-SELECTION` evidence slot. The tester
  evidence covers only letter affixes on `adidxbot`
  (`body-sel-adidxbot-affix-*`), which Google would not reduce either.
- Google: the spec's "Order of precedence for user agents" (`googlebot/1.2` and
  `googlebot*` are equivalent to `googlebot`).

### 4. Whitespace before the colon (yandex)

Fixture: `User-agent: *` / `Disallow : /private` (also a tab before the colon,
and `User-agent : *` / `Disallow: /private`), path `/private`.

| Row | Outcome |
|---|---|
| `google_yandex`, `google_bingbot`, `bing` | `disallow rule_disallow 2` |
| `yandex` | default |

The Yandex lexer takes the field name as everything before the colon, after
leading whitespace, without trimming, so `Disallow ` is an unknown field.

Verdict: UNEVIDENCED for Yandex. The accepted corpus covers leading whitespace
before the name (`ydx-parser-leading-space-name`, accepted) and a tab after the
colon (`ydx-parser-postcolon-tab`, accepted), not whitespace before it. The Bing
form of this candidate is refuted, and sourced: the tester accepts
`Disallow : /r` (`inst/bing-corpus`, `body-prec-bingbot-ows-around-colon`).

### 5. A blank line inside a group: refuted

Fixtures: a blank line after `User-agent`, between two rules, between stacked
`User-agent` lines, a whitespace-only line, and a blank line around a
`Crawl-delay`. All four rows agree on every one. Both engines treat blank lines
as transparent: Bing by contract (§9.3 rule 5, `stacked-ctl-v1`), Yandex by the
accepted corpus (`ydx-03-blank-after-agent`, `ydx-04-blank-mid-group`,
`ydx-parser-blank-after-agent`, `ydx-parser-blank-mid-group`).

### 6. Raw non-ASCII bytes in a rule (yandex, bing)

Fixture: `User-agent: *` / `Disallow: /café` (raw UTF-8), paths `/caf%C3%A9`
and the raw `/café`; and `Disallow: /café/` / `Allow: /caf%C3%A9`, path
`/caf%C3%A9/x`.

| Row | `/caf%C3%A9` | raw `/café` | `/caf%C3%A9/x` |
|---|---|---|---|
| `google_yandex`, `google_bingbot` | `disallow rule_disallow 2` | default | `disallow rule_disallow 2` |
| `yandex`, `bing` | default | `disallow rule_disallow 2` | `allow rule_allow 3` |

Google percent-escapes the rule's non-ASCII bytes and never the URL. The Yandex
and Bing backends compare bytes as written on both sides. The same holds for a
Cyrillic rule against its escaped URL.

Verdict: UNEVIDENCED. Bing: byte transparency is project behavior "where
tester transport does not establish equivalence"
(`design/robotstxtbing-v2-spec.md` §13; §9.1). Yandex:
`design/engine-profiles.md` §8 records "Yandex prohibits Cyrillic,
Punycode/%-encoding `[documented]`", from the Yandex robots.txt page (§10,
"Cyrillic"), which makes such a rule invalid, but no source says what the
robot does with one. Google: "URL matching based on path values" (rules
compared in percent-encoded form), `MaybeEscapePattern`.

### 7. CR CR LF line endings (yandex, bing)

Fixture: `User-agent: *` CR CR LF `Disallow: /private` CR CR LF, path
`/private`; and LF endings with only the rule line ending in CR CR LF.

| Row | All CR CR LF | Rule line only |
|---|---|---|
| `google_yandex`, `google_bingbot` | `disallow rule_disallow 3` | `disallow rule_disallow 2` |
| `yandex`, `bing` | default | default |

Google ends a line at CR, at LF and at CR LF, so CR CR LF is a line and a blank
line. Yandex and Bing strip one CR before LF and keep the other in the value:
`*` plus CR is no `*`, and `/private` plus CR matches only a target holding a CR.

Verdict: UNEVIDENCED. Bing: "bare CR ... remain payload"
(`design/robotstxtbing-v2-spec.md` §9.1, project behavior). Yandex: no source;
the vendored scanner splits on LF only. Google: "File format" (lines separated
by CR, CR/LF or LF).

### 8. Lone CR line endings (yandex, bing)

Fixture: `User-agent: *` CR `Disallow: /private` CR, path `/private`; and CR
after the first line only, LF after the rest.

| Row | Outcome (both fixtures) |
|---|---|
| `google_yandex`, `google_bingbot` | `disallow rule_disallow` at line 2 or 3 |
| `yandex`, `bing` | default |

For an LF-only reader the CR-separated lines are one line, a `User-agent` whose
value runs to the next LF, so every rule on it is lost.

Verdict: UNEVIDENCED, on the same sources as class 7.

### 9. A literal `%` in a pattern: refuted as a cause

`Disallow: *%*` and `Disallow: /*%*` match `/%24` on all four rows, and so do
`Disallow: /%`, `Disallow: /a%24` and an invalid `/a%zz`. The `*%*` shape
differs only beside a short `Allow`: `Allow: /` / `Disallow: *%*`, path `/%24`,
is `disallow rule_disallow 3` on Google and Bing and `allow rule_allow 2` on
Yandex. That is class 10 (`*%*` counts one byte for Yandex and ties `/`), and
it is pinned there.

### 10. Yandex rule length ignores `*` and a final `$` (yandex)

Fixtures: `Disallow: /page` / `Allow: /pag*`, path `/page`; `Allow: /p` /
`Disallow: /p$`, path `/p`; `Allow: /` / `Disallow: *%*`, path `/%24`.

| Row | `/page` | `/p` | `/%24` |
|---|---|---|---|
| `google_yandex`, `google_bingbot`, `bing` | `allow rule_allow 3` | `disallow rule_disallow 3` | `disallow rule_disallow 3` |
| `yandex` | `disallow rule_disallow 2` | `allow rule_allow 2` | `allow rule_allow 2` |

Google and Bing rank a match by the rule's byte length, `*` and `$` included.
Yandex counts neither `*` nor a final `$`; Allow still wins an equal count. This
is one source of the rows where Google allows and Yandex disallows; the
summary lists the others.

Verdict: EXPECTED-SOURCED. The accepted Yandex corpus:
`ydx-wildcard-specificity-matrix-v1` (`Disallow: /spec/literal/ab*` beats
`Allow: /spec/literal/a**`; observations 2026-07-16 and 2026-07-17) and
`ydx-13-wildcard-specificity-replica-v1` (`Allow: /probe/anchor/exact` beats
`Disallow: /probe/anchor/exact$`; 2026-07-12 and 2026-07-16). Google: "Order of
precedence for rules" (the longest rule). Bing agrees with Google and is
tester-observed for ties (`body-win-bingbot-tie-*`).

### 11. A lower-case escape in a rule (yandex)

Fixture: `User-agent: *` / `Disallow: /a%3cb`, paths `/a%3cb` and `/a%3Cb`.

| Row | `/a%3cb` | `/a%3Cb` |
|---|---|---|
| `google_yandex`, `google_bingbot`, `bing` | default | `disallow rule_disallow 2` |
| `yandex` | `disallow rule_disallow 2` | default |

Google and Bing upper-case a rule's escape and compare it with the URL as
given; Yandex compares the rule as written.

Verdict: UNEVIDENCED for Yandex: the accepted corpus has no escape-case case.
Bing is tester-observed (`body-sr2-bingbot-hexcase-*`). The Google side is the
upstream matcher's behavior (`MaybeEscapePattern`), not a matcher bug; the gap
is the validator's, which does not yet warn about such a rule: ROBO-kormmfyg
(`design/edge-case-catalog.md`, `esc-lower-hex-rule`).

### 12. An empty `User-agent` value (yandex)

Fixture: `User-agent: *` / `User-agent:` / `Disallow: /private`, path
`/private`.

| Row | Outcome |
|---|---|
| `google_yandex`, `google_bingbot`, `bing` | `disallow rule_disallow 3` |
| `yandex` | default |

Google and Bing skip the empty value and keep the stacked group. The Yandex
backend ends the group there, so the rule after it is an orphan; its parser
calls this a deterministic recovery that fails open.

Verdict: UNEVIDENCED: no Yandex source or corpus case.

### 13. A key that starts with `disallow` or `allow` (yandex, bing)

Fixture: `User-agent: *` / `DisallowAITraining: /`, path `/x`; and
`User-agent: *` / `Disallow: /` / `AllowAITraining: /x`, path `/x`.

| Row | `DisallowAITraining` | `AllowAITraining` |
|---|---|---|
| `google_yandex`, `google_bingbot` | `disallow rule_disallow 2` | `allow rule_allow 3` |
| `yandex`, `bing` | default | `disallow rule_disallow 2` |

Google's `KeyIsDisallow` and `KeyIsAllow` (`src/robots.cc`) accept any key
that starts with `disallow` or `allow`, ignoring case, so `DisallowAITraining`
is a `Disallow` and `AllowAITraining` an `Allow`. The Yandex and Bing backends
compare the whole field name, so both keys are unknown fields with no access
effect.

Verdict: EXPECTED-SOURCED. Google's side is the upstream engine itself, which
`design/engine-profiles.md` §5b checks against the pinned upstream: the prefix
match is `StartsWithIgnoreCase` in `KeyIsAllow` and `KeyIsDisallow`, and it
does not depend on `kAllowFrequentTypos` (Allow takes no typo at all). No
Google page documents the prefix reading, and Google's documented typo
tolerance (`design/engine-profiles.md` §8) does not cover it.
Bing: field names "must exactly equal" a known name, and the grammar
"deliberately does not accept prefix/suffix field-name matching"
(`design/robotstxtbing-v2-spec.md` §9.2, project grammar). Yandex: the accepted
tester case `ydx-parser-directive-suffix` (`inst/yandex-corpus/`: a
`Disallow-extra:` line is ignored, the candidate path is allowed; observed
2026-07-15 and 2026-07-17), which the vendored lexer implements by comparing a
field name whole (`ClassifyField`, `AsciiCaseEqual`). That such a file validates clean while it
blocks everything for Google is the validator's gap, ROBO-xglcoagv, not a
matcher change.

## Adjacent findings

- **Other prefix-matched keys.** Google's `KeyIsUserAgent` and `KeyIsSitemap`
  also match by prefix, so a line such as `User-agentfoo: bingbot` is a
  `User-agent` line to Google and an unknown field to Bing and Yandex, which on
  Bing also seals a stacked run (class 1). Not probed or pinned here; filed as
  ROBO-fslaxaep.

- **A Yandex stacked-run claim our Yandex backend does not follow.**
  `design/robotstxtbing-v2-spec.md` §9.3 says the split "is corroborated
  cross-engine: Yandex ends the stack on the same directives (and, stricter
  still, on blank/comment)", citing a sibling-project differential. Our Yandex
  backend ends no stacked run on those lines (class 1's Yandex form), and the
  accepted Yandex corpus has no case for it. If the tester confirms the claim,
  the Yandex backend contradicts Yandex and a class appears; question Y5 below.
- **The Bing `msnbot` tier.** `design/engine-profiles.md` §5 lists Bing
  selection as `bingbot` > `msnbot` > `*` `[documented]` (the 2012 post). The
  Bing backend has no `msnbot` tier (`User-agent: msnbot` / `Disallow: /private`
  then `User-agent: *` / `Allow: /` answers from `*`), as its contract's
  "remove unproved historical tiers" gate says. Google with `bingbot` agrees, so
  no disagreement follows, but the two documents disagree.
- **Two readings of RFC 9309 for a line inside a stacked run.**
  `design/robotstxtbing-v2-spec.md` §9.3 says rule 2a "aligns the contract
  with the observed Bing tester and the RFC 9309 §2.2.1 literal reading": §2.2.1
  "groups *consecutive* `user-agent` lines and begins the rule section at the
  first non-`user-agent` line, so an intervening line ends the stack". RFC 9309
  §2.2.4 says "a "Sitemaps" record MUST NOT terminate a group"
  (`design/edge-case-catalog.md` "Sources"), and Google keeps the stack. The
  two documents read the RFC against each other for the `Sitemap` case;
  neither changes a verdict here, since class 1's Bing and Google sides are
  each sourced to the engine's own contract or spec.

## Tester questions (for ROBO-bpywsjwv)

Each body is entered in the tester's editor for `https://example.com`; paths are
checked one per line. "Ours" is what our backend answers today.

**B1, Bing, class 2 (BOM).** Body: the bytes `EF BB BF`, then
`User-agent: *` / `Disallow: /b1/`. Profile Bingbot; path `/b1/x`. Disallow:
Bing skips a leading BOM, as Google does, and our scanner should too. Allow
(ours): the BOM spoils line 1. The editor may drop or keep the BOM, so record
whether it kept it; if it cannot carry one, the case needs a served file
(ROBO-ogwchglq) and is "not testable" in the editor.

**B2, Bing, class 3 (suffix).** Body: `User-agent: bingbot/2.0` /
`Disallow: /b2/slash/` / blank / `User-agent: bingbot 2.0` /
`Disallow: /b2/space/` / blank / `User-agent: bingbot*` / `Disallow: /b2/star/`
/ blank / `User-agent: *` / `Disallow: /b2/wild/`. Profile Bingbot; paths
`/b2/slash/x`, `/b2/space/x`, `/b2/star/x`, `/b2/wild/x`. Ours: only
`/b2/wild/x` disallowed. A disallowed suffix path means Bing reads that form as
`bingbot`, as Google does (and then `/b2/wild/x` becomes allowed).

**B3, Bing, class 6 (raw non-ASCII).** Body: `User-agent: bingbot` /
`Disallow: /b3/café`. Paths `/b3/caf%C3%A9` and `/b3/café` typed raw. Ours:
the escaped path allowed, the raw one disallowed. Escaped disallowed means
Bing escapes the rule, as Google does. Record the target the tester displays,
since it may escape a raw path itself.

**B4, Bing, classes 7 and 8 (CR).** Body with CR CR LF after each line:
`User-agent: bingbot` / `Disallow: /b4/`; a second body with lone CR. Path
`/b4/x`. Ours: allowed for both. Disallowed means Bing ends a line at CR. As
with B1, record whether the editor kept the bytes; if it normalizes line
endings, the case needs a served file.

**Y1, Yandex, class 2 (BOM).** Body: `EF BB BF`, then `User-agent: Yandex` /
`Disallow: /y1/`. Crawler Yandex; path `/y1/x`. Ours: allowed. Prohibited
means Yandex skips a leading BOM. Same editor caveat as B1.

**Y2, Yandex, class 3 (suffix).** Body: `User-agent: Yandex/1.0` /
`Disallow: /y2/slash/` / blank / `User-agent: Yandex*` / `Disallow: /y2/star/`
/ blank / `User-agent: Yandex, Other` / `Disallow: /y2/list/`. Crawler Yandex;
paths `/y2/slash/x`, `/y2/star/x`, `/y2/list/x`. Ours: all allowed. A
prohibited path means Yandex reads that form as `Yandex`. (The space form is
already observed: not matched.)

**Y3, Yandex, class 4 (whitespace before the colon).** Body:
`User-agent: Yandex` / `Disallow : /y3/space` / `Disallow\t: /y3/tab` (a tab) /
`Disallow: /y3/control`. Paths `/y3/space`, `/y3/tab`, `/y3/control`. Ours:
only `/y3/control` prohibited. Prohibited space or tab paths mean Yandex trims
the field name, as Google and Bing do. Record the analyzer's diagnostics.

**Y4, Yandex, class 6 (raw non-ASCII).** Body: `User-agent: Yandex` /
`Disallow: /y4/каталог` / `Disallow: /y4/café`. Paths
`/y4/%D0%BA%D0%B0%D1%82%D0%B0%D0%BB%D0%BE%D0%B3`, `/y4/каталог`,
`/y4/caf%C3%A9`, `/y4/café`. Ours: only the raw paths prohibited. Escaped
paths prohibited means Yandex escapes the rule; all allowed, with an analyzer
error, means Yandex drops the rule as the docs' Cyrillic ban suggests.

**Y5, Yandex, class 1 (stacked run).** Body: `User-agent: Yandex` /
`Crawl-delay: 5` / `User-agent: Other` / `Disallow: /y5/cd` / blank /
`User-agent: Yandex` / `# note` / `User-agent: Other` / `Disallow: /y5/comment`
/ blank / `User-agent: Yandex` / blank / `User-agent: Other` /
`Disallow: /y5/blank`. Paths `/y5/cd/x`, `/y5/comment/x`, `/y5/blank/x`.
Ours: all three prohibited (the stack holds). An allowed path means that line
ends the stack for Yandex, as `design/robotstxtbing-v2-spec.md` §9.3 claims, and
our Yandex backend would then contradict Yandex.

**Y6, Yandex, classes 7 and 8 (CR).** As B4, with `User-agent: Yandex` and
path `/y6/x`. Ours: allowed for both.

**Y7, Yandex, class 11 (escape case).** Body: `User-agent: Yandex` /
`Disallow: /y7/a%3cb`. Paths `/y7/a%3cb`, `/y7/a%3Cb`. Ours: the lower-case
path prohibited, the upper-case one allowed. The reverse means Yandex
upper-cases the rule's escape, as Google and Bing do; both prohibited means it
ignores escape case.

**Y8, Yandex, class 12 (empty value).** Body: `User-agent: Yandex` /
`User-agent:` / `Disallow: /y8/`. Path `/y8/x`. Ours: allowed. Prohibited means
Yandex skips the empty value and keeps the group.

## What a fix would touch

No class is OUR BUG, so nothing is filed as a fix. Where a tester answer shows
an engine behaving as Google does, matching it changes a frozen engine profile:
for Bing the scanner, lexer or selection rules of
`design/robotstxtbing-v2-spec.md` §8, §9.1, §9.2 or §13; for Yandex the
`yandex-0.1.0` profile. Each such change is the maintainer's decision
(`[USER]`), followed by a normal code issue, as ROBO-bpywsjwv's scope says.
