# Library comparison: robotstxtr against eight robots.txt libraries (ROBO-dqqkvwts)

- Status: comparison record, 2026-11-10
- Pins: `tests/testthat/test-library-comparison-dqqkvwts.R`
- Runner: `dev/library-comparison/run.R`; class fixtures:
  `tests/testthat/fixtures/library-comparison-dqqkvwts/` (`manifest.csv`
  records every answer)
- Related: `design/edge-case-catalog.md` (whose fixtures are the first
  input), `design/engine-profiles.md` §5b (Google fidelity),
  `design/engine-disagreements.md` (the Bing and Yandex backends);
  ROBO-wmojamln (SEO tools and online checkers, the other half)

## Method

A private sample of real robots.txt files supplied the candidate classes
below; nothing from it is recorded here. Every fixture is synthesized, on
`https://example.com`.

### Libraries

| Id | Library | Version | Runtime |
|---|---|---|---|
| `py` | Python `urllib.robotparser` | stdlib | CPython 3.15.2 |
| `pro` | `protego` | 0.7.0 | CPython 3.15.2 |
| `go` | `github.com/temoto/robotstxt` | v1.1.2 | Go 1.27.3 |
| `rs` | `texting_robots` | 0.2.2 | `rustc` 1.91.0 |
| `jv` | `crawler-commons` `SimpleRobotRulesParser` | 1.6 | OpenJDK 21 |
| `js` | `robots-parser` (npm) | 3.0.1 | Node 26.13 |
| `rtx` | rOpenSci `robotstxt` (CRAN) | 0.7.15 | R 4.6.2 |
| `spb` | `spiderbar` (CRAN) | 0.2.5 | R 4.6.2 |

The reference is the pristine upstream Google engine at `22b355ff`, the SHA
the vendored matcher pins (`design/engine-profiles.md` §5b). The libraries
ran in a pinned environment built outside the repository, one command per
library reading (body file, URL, user agent) lines and printing allowed,
disallowed or an error. robotstxtr ran under R 4.6.2 from this tree. The
runner adapts each library's API as follows:

- `py` and `pro` decode the body as UTF-8 with `surrogateescape`.
- `go` tests the escaped path plus the query (`url.URL.EscapedPath()`).
- `js` caches one parser per (body, origin).
- `jv` gets the user agent lower-cased, as `crawler-commons` expects.
- `rtx` and `spb` get the body with NUL bytes removed, and the path without
  the fragment.

`rtx` answers through `spb`: `robotstxt` 0.7.15 `NEWS.md` (0.6.0) makes the
`spiderbar`/`rep-cpp` check "the default and only method". The two columns
agree on every row but one, an error `rtx` raises in its own parser
(Errors).

### Inputs

Every row of the edge-case catalog's manifest
(`tests/testthat/fixtures/edge-cases/manifest.csv`, its URLs and tokens),
plus one synthesized fixture or more per candidate class
(`tests/testthat/fixtures/library-comparison-dqqkvwts/`; `stack-named`,
`rule-before-agent` and `q-star` reuse the catalog bodies
`grp-unknown-between-agents`, `grp-rule-before-user-agent` and
`esc-query-wildcard`). The same body, URL and token go to
every library, to the reference and to two robotstxtr paths:
`robots_evaluate_text_v1()` with the `google` ruleset and backend, and
`allowed_by_robots_text()`. A body with a NUL byte reaches robotstxtr as
the fetch path decodes it (NULs dropped, `R/body-decode.R`), since an R
string cannot hold one. Library documentation is cited from what each
library ships in its installed sources, by file relative to the package;
where nothing is shipped, the entry says "no documented intent found".

### Result

robotstxtr agrees with the reference on every row, on both paths, except
the NUL-bearing `enc-utf16le-no-bom` on `/a`: upstream ends a line at its
first NUL, robotstxtr drops every NUL. That split is deliberate
(`design/engine-profiles.md` §5b, class 5), and it is the one row the
runner's expected-split list names; the two other UTF-16 bodies bear NULs
too and must agree. No class below is a robotstxtr bug.

## Hypotheses

The candidate classes came as hypotheses; each was tested with synthesized
fixtures.

| # | Hypothesis | Outcome |
|---|---|---|
| H1 | every library ends a stacked group at a non-rule line such as `Crawl-delay` | refuted as stated: `jv` stacks as Google does; at a `Sitemap` line only `rtx` and `spb` end the group, at an unknown field `pro`, `rtx` and `spb` (class 1) |
| H2 | a leading BOM: `py` and `pro` differ | confirmed (class 2) |
| H3 | wildcards: `pro`, `go`, `spb`, `rtx`, and `py` a little | confirmed for `go` (class 4), `rtx`/`spb` (5, 8, 10), `py` (6, 9); for `pro` only a `$` side effect (class 7) |
| H4 | `go`, token `Googlebot`: a `Googlebot-News` or `Googlebot-Image` group applied to `Googlebot` | refuted for a longer group name (`grp-news-only` agrees); the cause is a group whose name is a prefix of the token, such as `Google` (class 11) |
| H5 | `js` allows a path with a query where Google disallows | confirmed: a bare `?` and an apostrophe in the query (class 20) |
| H6 | `rtx`/`spb` lean towards allow with no path feature | confirmed: lone CR line endings (class 18) and the group sealing of class 1; precedence, empty `Disallow`, letter case and longest match all agree (`prec-*` controls) |
| H7 | `py`: escape case or queries | confirmed: `py` decodes every escape before comparing (class 13) and escapes a pattern's `=` (class 20) |
| H8 | `jv` refuses `*`; `go` fails on a non-numeric `Crawl-delay` and a rule before any `User-agent`; `rtx` throws a `'names' attribute` error | confirmed, with a minimal trigger for `rtx` (Errors) |

## Matrix

`D`: the library's decision differs from the reference on the class
fixture; `E`: the library raises an error there; `r`: it differs only
through the runner's adaptation of its API; `.`: it agrees. robotstxtr
agrees with the reference in every row (class 24: see Result).

| # | Class | `py` | `pro` | `go` | `rs` | `jv` | `js` | `rtx` | `spb` |
|---|---|---|---|---|---|---|---|---|---|
| 1 | non-rule line inside a stacked `User-agent` run | D | D | D | D | . | D | D | D |
| 2 | leading BOM | D | D | . | . | . | . | . | . |
| 3 | BOM after the first byte | . | . | E | D | . | D | D | D |
| 4 | wildcard pattern matched mid-path | . | . | D | . | . | . | . | . |
| 5 | `/*$` | . | . | . | . | . | . | D | D |
| 6 | `$` inside a pattern | D | . | D | D | D | . | D | D |
| 7 | `$` rule also blocks `%24` | . | D | . | . | . | . | . | . |
| 8 | `Disallow: $` | . | . | D | . | . | . | D | D |
| 9 | wildcard rule priority | D | . | . | . | . | . | . | . |
| 10 | Allow on a tie; trailing `*` | . | . | D | . | . | . | D | D |
| 11 | group named by a prefix of the token | D | D | D | . | . | . | . | . |
| 12 | file `User-agent` value cut | D | D | D | D | D | D | D | D |
| 13 | escapes compared octet for octet | D | D | . | . | D | D | D | D |
| 14 | lower-case escape in a rule | D | D | D | D | D | D | D | D |
| 15 | raw non-ASCII URL or rule | D | D | D | D | D | D | D | D |
| 16 | raw space in a rule | D | D | D | D | D | D | D | D |
| 17 | line past 16,663 bytes | D | D | D | D | D | D | D | D |
| 18 | lone CR line endings | . | . | . | . | . | . | D | D |
| 19 | rule before the first `User-agent` | . | . | E | . | . | . | D | D |
| 20 | query rewritten by the URL parser | D | . | r | D | D | D | . | . |
| 21 | dot segment in the path | . | . | . | D | . | D | . | . |
| 22 | `Allow: /index.html` | D | . | D | D | . | D | D | D |
| 23 | `go` tokenizer | . | . | D | . | . | . | . | . |
| 24 | UTF-16 body | . | . | . | . | D | . | r | r |
| 25 | Latin-1 byte in a rule | . | E | D | D | D | D | . | . |

## Classes

Each entry gives the fixture (body lines separated by `/`; token `FooBot`
and `User-agent: *` unless shown), the reference's decision, the libraries
that differ, each library's documented intent, and the verdict. "Library
deviation" means the library departs from Google's engine; where RFC 9309
reads otherwise, the entry says so. The Google side is the vendored
`src/robots.cc`, symbol named.

### 1. A non-rule line inside a stacked `User-agent` run

Fixture `stack-crawl-delay`: `User-agent: FooBot` / `Crawl-delay: 5` /
blank / `User-agent: *` / `Disallow: /x`, path `/x`. Reference: disallow.
Google keeps the run open until a rule (`HandleUserAgent` resets the group
only after `seen_separator_`, which only `HandleAllow` and
`HandleDisallow` set), so FooBot shares the `*` group.

| Line between the two `User-agent` lines | Libraries that allow |
|---|---|
| `Crawl-delay: 5` (also `stack-named`, catalog `grp-unknown-between-agents`) | `py` `pro` `go` `rs` `js` `rtx` `spb` |
| `Sitemap: …` (`stack-sitemap`) | `rtx` `spb` |
| `Foo: bar` (`stack-unknown`) | `pro` `rtx` `spb` |
| `# note` (`stack-comment`, control) | none |

Documented intent:

- `py`: no documented intent found for `Crawl-delay`. CPython 3.15.2
  `Lib/urllib/robotparser.py` moves its parser to the rule state on a
  `crawl-delay` line, and says for `sitemap` that "we do not change the
  state of the parser".
- `pro`: protego 0.7.0 `protego/_protego.py`: "Sitemap and Host are
  site-wide directives and don't matter for record grouping"; any other
  field ends the run.
- `rs`: texting_robots 0.2.2 `src/lib.rs` keeps only "User-Agent, Allow,
  Disallow, or CrawlDelay" lines, noting the "CONFLICT" with reppy's test
  on unknown keys.
- `js`: no documented intent found. robots-parser 3.0.1 `Robots.js` makes
  a `crawl-delay` line create the agent's rule list, so FooBot has an
  empty group of its own.
- `go`: no documented intent found (temoto/robotstxt v1.1.2 `parser.go`
  marks the group non-empty on `Crawl-delay`).
- `rtx`, `spb`: no documented intent found.

Verdict: library deviation in every case. RFC 9309 §2.2.4 says a Sitemaps
record "MUST NOT terminate a group", so `rtx` and `spb` also break the RFC
on `stack-sitemap`. The investigation the brief asked for: not every
library differs (`jv` stacks as Google does), and robotstxtr's answer is
upstream's. Source for Google: the spec's "Rules other than allow,
disallow, and user-agent are ignored by the robots.txt parser", with its
example of a `sitemap` line inside a group of two `user-agent` lines
(`design/edge-case-catalog.md` "Sources"); `design/engine-disagreements.md`
class 1 records the same shape against Bing and the two RFC readings.
Deliberate: robotstxtr keeps Google's behavior.

### 2. A leading UTF-8 BOM

Fixture `bom-start`: `EF BB BF` then `User-agent: FooBot` / `Disallow: /x`,
path `/x`. Reference: disallow (`ParseRobotsTxt` skips one leading
`utf_bom`). `py` and `pro` allow: the first field name keeps the BOM and
is unknown, so the rule has no group. Control `bom-comment-first` (a
comment as line 1): every library disallows.

Documented intent: none found for either. Verdict: library deviation; RFC
9309 never mentions a BOM, and Google's spec says a leading BOM is ignored.

### 3. A BOM after the first byte

Catalog fixtures. `enc-bom-mid-file` (`Disallow: /a` behind a BOM on line
2): reference allow, `js` disallow. `enc-bom-before-user-agent`: reference
disallow on `/a`, `js` allow. `js` trims each line with JavaScript's
`String.prototype.trim()`, which removes a BOM at the start of any line. `enc-bom-doubled`
(two BOMs, then the rules): reference allow (the second BOM hides the
`User-agent` line); `rs`, `js`, `rtx`, `spb` disallow; `go` fails the parse
(Errors).

Documented intent: none found. Verdict: library deviation.

### 4. A wildcard pattern matched mid-path (`go`)

Fixture `wc-mid-star`: `Disallow: /a*b`, paths `/axxb` (all disallow) and
`/x/axxb`; `wc-dollar`: `Disallow: /a$`, path `/x/a`. Reference: allow
on `/x/axxb` and `/x/a` (`RobotsMatchStrategy::Matches` matches from the
path's first octet). `go` disallows: temoto/robotstxt v1.1.2 `parser.go`
compiles a pattern with `*` or `$` into a regular expression without a
leading anchor, and `robotstxt.go` `findRule` calls `MatchString`.

Documented intent: none found. Verdict: library deviation (RFC 9309 §2.2.2
also matches from the first octet).

### 5. `/*$` (`rtx`, `spb`)

Catalog `esc-star-dollar`: `Disallow: /*$`, paths `/` and `/anything`.
Reference: disallow both. `rtx` and `spb` allow both. Documented intent:
none found. Verdict: library deviation.

### 6. A `$` inside a pattern

Catalog `esc-dollar-then-star`: `Disallow: /a$*`. Reference: `/a` allow,
`/a$` and `/a$b` disallow (`Matches` treats a `$` that is not last as a
literal). `py`, `go`, `rs`, `rtx`, `spb` disallow `/a`; `py`, `go`, `rs`,
`jv`, `rtx`, `spb` allow `/a$` and `/a$b`. CPython 3.15.2
`Lib/urllib/robotparser.py` `RuleLine` collapses `$*` into a final `$`.

Documented intent: none found. Verdict: library deviation; RFC 9309 leaves
an inner `$` unspecified, and the validator flags it
(`rule_inner_dollar`).

### 7. A `$` rule also blocks `%24` (`pro`)

Fixture `wc-dollar`: `Disallow: /a$`, path `/a%24`. Reference: allow.
`pro` disallows: protego 0.7.0 `protego/_ruleset.py` `disallow()` (and
`allow()`) add a second rule with each `$` escaped to `%24`. Documented
intent: none found (the code carries no comment). Verdict: library
deviation.

### 8. `Disallow: $`

Catalog `esc-lone-dollar`, path `/`. Reference: allow (the pattern never
matches a path, which always starts `/`). `go`, `rtx`, `spb` disallow: they
prefix a missing `/`, so the rule becomes `/$`. temoto/robotstxt v1.1.2
`parser.go`: "add leading "/" if missing". Verdict: library deviation; the
validator flags the line (`rule_missing_leading_slash`).

### 9. A wildcard rule's priority (`py`)

Fixture `wc-star-vs-allow`: `Allow: /abc` / `Disallow: /*`, path
`/abcdef`. Reference: allow (priority is the pattern's length,
`LongestMatchRobotsMatchStrategy`: 4 against 2). `py` disallows. Fixture
`wc-trailing-star`: `Disallow: /p*` / `Allow: /p`, path `/p`: reference
disallow (3 against 2), `py` allows. CPython 3.15.2
`Lib/urllib/robotparser.py` `RuleLine.applies_to`: "return the matching
length plus 1", the length of the path text the pattern matched.

Verdict: library deviation from Google, which counts the octets of the
pattern. RFC 9309 §2.2.2 ("the match that has the most octets") does not say
whether the pattern or the matched text is counted, so `py`'s reading is not
clearly an RFC break.

### 10. Allow on a tie, and a trailing `*`

Fixture `tie-disallow-first`: `Disallow: /x` / `Allow: /x`, path `/x`.
Reference: allow (`RobotsMatcher::disallow()` disallows only on a strictly
higher priority). `go`, `rtx`, `spb` disallow: the first rule wins a tie.
Control `tie-allow-first`: every library allows. Catalog
`esc-star-longer-pattern-wins` (`Disallow: /p` / `Allow: /p*`): reference
allow on `/p` and `/px`; `go`, `rtx`, `spb` drop the trailing `*`, tie, and
disallow. temoto/robotstxt v1.1.2 `parser.go`: "remove trailing "*""; its
`findRule` keeps the first of two rules of one length.

Verdict: library deviation; RFC 9309 §2.2.2 prefers Allow on a tie.

### 11. A group named by a prefix of the token

Fixtures `grp-prefix-name` (`User-agent: Foo` / `Disallow: /x`, then
`User-agent: *` / `Allow: /`, token `FooBot`) and `grp-google-prefix`
(`User-agent: Google`, token `Googlebot`). Reference: allow (the `*`
group; `HandleUserAgent` compares the whole token). `py`, `pro`, `go`
disallow. Fixture `grp-suffix-name` (`User-agent: Bot`): only `py`
disallows. Control `grp-news-only` (`User-agent: Googlebot-News`, token
`Googlebot`): every library allows. Catalog `grp-googlebot-image-fallback`,
token `Googlebot-Image`: the reference reads `*`; `py`, `pro`, `go` take the
`Googlebot` group.

Documented intent:

- `pro`: protego 0.7.0 `METADATA` (`can_fetch`): "a group applies when its
  product token appears in *user_agent* at a token boundary". The boundary
  is defined in `protego/_ruleset.py`: a start or a character outside
  letters, digits, `-` and `_`. The intent is matching a whole
  `User-Agent` header.
- `go`: temoto/robotstxt v1.1.2 `robotstxt.go` `FindGroup` quotes Google's
  spec ("the most specific user-agent that still matches") and implements
  it as the longest group name that prefixes the agent.
- `py`: CPython 3.15.2 `Lib/urllib/robotparser.py` `Entry.applies_to`
  takes a group whose name occurs anywhere in the agent's name token.

Verdict: library deviation. RFC 9309 §2.2.1 matches the product token
case-insensitively, whole.

### 12. Google cuts a file's `User-agent` value

`ExtractUserAgent` keeps the value's leading run of `[A-Za-z_-]`.
Catalog `grp-token-version-in-file` (`User-agent: Googlebot/2.1`, token
`Googlebot`): reference disallow; `py`, `pro`, `go`, `rs`, `rtx`, `spb`
allow. `grp-user-agent-with-space` (`User-agent: Foo Bot`): as `Foo`,
reference disallow, `py`, `pro`, `rs`, `js`, `rtx`, `spb` allow; as
`FooBot`, reference allow, `go` disallows (its value ends at the space, and
`foo` prefixes `foobot`, class 11). `grp-digit-in-token` (`User-agent: Bot2`): as `Bot2`,
reference allow and **every library disallows**; as `Bot`, reference
disallow and every library but `jv` allows.

Documented intent: robots-parser 3.0.1 `Robots.js` `formatUserAgent`
"removing any version numbers" (so `js` agrees on the version form);
texting_robots 0.2.2 `src/lib.rs` compares the lower-cased agent to the
whole value. Others: none found.

Verdict: library deviation. The `Bot2` row is a class where every library
agrees against the reference and robotstxtr; investigated below.

### 13. Escapes compared octet for octet

The matcher compares escapes as written, upper-casing those in a rule only
(`MaybeEscapePattern`). Libraries normalize instead:

| Fixture, path | Reference | Libraries that disallow |
|---|---|---|
| catalog `esc-pct2f-rule-slash-url` (`Disallow: /a%2Fb`), `/a/b` | allow | `py` `rtx` `spb` |
| catalog `esc-slash-rule-pct2f-url` (`Disallow: /a/b`), `/a%2Fb` | allow | `py` `rtx` `spb` |
| `esc-query-slash` (`Disallow: /p?q=a%2Fb`), `/p?q=a/b` | allow | `py` `rtx` `spb` |
| catalog `esc-pct7e-rule-tilde-url` (`Disallow: /%7Ejoe`), `/~joe` | allow | `py` `pro` `jv` `rtx` `spb` |
| catalog `esc-tilde-rule-pct7e-url` (`Disallow: /~joe`), `/%7Ejoe`, `/%7ejoe` | allow | `py` `pro` `jv` `rtx` `spb` |
| `esc-upper-rule` (`Disallow: /a%3Cb`), `/a%3cb` | allow | `py` `pro` `jv` `js` `rtx` `spb` |

Documented intent: protego 0.7.0 `protego/_utils.py` `_quote`: "Escapes
other than those of the characters in *kept* are decoded" (it keeps `%2F`
and `%25`); CPython 3.15.2 `Lib/urllib/robotparser.py` `normalize` decodes
and re-escapes both sides; robots-parser 3.0.1 `Robots.js`
`urlEncodeToUpper` upper-cases escapes on both sides. Others: none found.

Verdict: library deviation. RFC 9309 §2.2.2 decodes an unreserved escape
such as `%7E` and keeps a reserved one such as `%2F`. Every library in the
table above that decodes `%7E` follows the RFC there; `py`, `rtx` and `spb`
break it on `%2F`.
`design/edge-case-catalog.md` records the Google side, and the validator
warns on such a rule with `rule_escaped_unreserved` (ROBO-gaczsrgj).

### 14. A lower-case escape in a rule: every library differs

Catalog `esc-lower-hex-rule`: `Disallow: /a%3cb`. Path `/a%3cb`:
reference allow, **every library disallows**. Path `/a%3Cb`: reference
disallow, `go` and `rs` allow (they compare the rule as written). Investigated
below.

### 15. Raw non-ASCII in the URL or the rule

Catalog `enc-escaped-rule-raw-url` (`Disallow: /caf%C3%A9`), URL with a raw
`é`: reference allow, **every library disallows**: each escapes the URL
before matching; the matcher never does. Catalog
`enc-nonascii-rule-raw-url` (`Disallow: /café`): on the raw URL every
library but `go` disallows; on `/caf%C3%A9` reference disallow and `go`
allows, since `go` escapes the URL but not the rule. texting_robots 0.2.2
`src/lib.rs`: "Paths outside ASCII must be percent encoded" (both sides).
Investigated below.

### 16. A raw space in a rule: every library differs

Catalog `esc-space-in-rule`: `Disallow: /a b`. Path `/a%20b`: reference
allow (the rule keeps its raw space; `MaybeEscapePattern` escapes only
non-ASCII bytes), **every library disallows**. Path `/a`: `go` disallows
(its tokenizer ends the value at the space). Investigated below.

### 17. A line past 16,663 bytes: every library differs

Catalog `size-long-line`: `Disallow: /` + 16,700 `a` + `/secret`, its long
path. Reference: disallow (`ParseRobotsTxt` cuts the line at `kMaxLineLen`,
leaving a shorter prefix rule); **every library allows**: none cuts a line.
Investigated below.

### 18. Lone CR line endings (`rtx`, `spb`)

Fixture `cr-only`: `User-agent: *` CR `Disallow: /x` CR, path `/x`; catalog
`blank-cr-only`, `blank-mixed-endings`. Reference: disallow
(`ParseRobotsTxt` ends a line at CR, LF or CR LF). `rtx` and `spb` allow,
as if a CR alone did not end a line and the rules ran into one line; on
the LF-terminated lines of `blank-mixed-endings` they agree.
This is the allow-leaning class with no path feature. Documented intent:
none found. Verdict: library deviation; RFC 9309 §2.2 counts a CR as a
line end.

### 19. A rule before the first `User-agent`

Fixture `rule-before-agent`: `Disallow: /x` / `User-agent: *` /
`Disallow: /y`. Reference: `/x` allow (`HandleDisallow` ignores a rule
before any agent, `seen_any_agent()`), `/y` disallow. `rtx` and `spb`
disallow `/x`: the orphan rule joins the `*` group (with a named group
instead of `*`, they agree). `go` fails the parse (Errors). Documented
intent: temoto/robotstxt v1.1.2 `parser.go`: "Error if no current group".
Verdict: library deviation.

### 20. The query as the URL parser rewrites it

| Fixture (rule), path | Reference | Libraries that allow | Cause |
|---|---|---|---|
| `q-empty` (`Disallow: /p?`), `/p?` | disallow | `js`; `go` (runner) | the empty query and its `?` are dropped |
| `q-apostrophe` (`Disallow: /p?a='x'`), `/p?a='x'` | disallow | `rs` `js` | the URL parser escapes `'` in a query to `%27`, the rule keeps it |
| `q-quote` (`Disallow: /p?a="x"`), `/p?a="x"` | disallow | `jv` | not isolated: `crawler-commons` ships no source |
| `q-equals` (`Disallow: /*sort=`), `/a?sort=1` | disallow | `py` | `py` escapes `=` in a pattern's path part, not in the URL's query |

Controls `q-star` (`Disallow: /*?`), `q-literal`, `q-dollar`: every library
agrees. Documented intent: robots-parser 3.0.1 `Robots.js` `_getRule`
matches `pathname + search` of a WHATWG `URL`; texting_robots 0.2.2
`src/lib.rs`: "The Url library performs percent encoding". Others: none
found.

Verdict: library deviation, except `go` on `q-empty`: temoto takes a path
string, and the runner appends `?` and the query only when the query is
not empty, so that row is the runner's adaptation, not temoto's.

### 21. A dot segment in the path (`rs`, `js`)

Fixture `dot-segment`: `Disallow: /a/./b`, path `/a/./b`. Reference:
disallow. `rs` and `js` allow: their URL parsers remove `/.` before
matching. Documented intent: as class 20. Verdict: library deviation.

### 22. `Allow: /index.html` also allows the directory

Fixture `index-html`: `Disallow: /` / `Allow: /index.html`, path `/`.
Reference: allow (`HandleAllow`'s "Google-specific optimization": an
allowed `index.htm` or `index.html` also allows its directory, as `/$`). `pro` and `jv` agree; `py`,
`go`, `rs`, `js`, `rtx`, `spb` disallow. protego 0.7.0
`protego/_ruleset.py` `allow()`: "If index.html is allowed, we interpret
this as / being allowed too". Verdict: library deviation from a
Google-specific rule that RFC 9309 does not have.

### 23. Lines `go`'s tokenizer reads differently

Catalog `cmt-hash-in-rule` (`Disallow: /a#b`): reference disallow on `/a`
and `/abc`; `go` allows (a `#` starts a comment only at a token's start,
so the rule stays `/a#b`). Catalog `oth-space-before-colon`
(`Disallow : /a`): reference disallow; `go` allows (the key is not
recognized). temoto/robotstxt v1.1.2 `scanner.go` splits a line into
whitespace-separated tokens. Documented intent: none found. Verdict:
library deviation; RFC 9309 §2.2 allows whitespace before the colon and
starts a comment at any `#`.

### 24. UTF-16 bodies

Catalog `enc-utf16le-bom`, `enc-utf16be-bom`, `enc-utf16le-no-bom`, path
`/a`. Reference: allow on all three. `jv` disallows the two with a BOM (it
decodes them as UTF-16). `rtx` and `spb` disallow all three, an effect of
the runner, which drops NUL bytes as robotstxtr's fetch path does.
robotstxtr disallows `enc-utf16le-no-bom` for the same reason, the one
deliberate split from the reference (Result). Documented intent: none
found. Verdict: library deviation (`jv`); runner adaptation (`rtx`,
`spb`). RFC 9309 §2.3 requires UTF-8.

### 25. A Latin-1 byte in a rule

Catalog `enc-latin1-rule`: `Disallow: /caf` + byte `E9`. Path `/caf%E9`:
reference disallow (`MaybeEscapePattern` escapes the byte); `go`, `rs`,
`jv`, `js` allow; `pro` fails (Errors). Path `/caf%C3%A9`: reference allow;
`pro` fails, the others allow. Documented intent: none found. Verdict:
library deviation; the file breaks RFC 9309 §2.3, which leaves its reading
to the implementor.

## Every library against the reference

Five rows have all eight libraries agreeing with each other and against
the reference, robotstxtr siding with the reference. Each was investigated:

| Class | Row | Verdict and source |
|---|---|---|
| 12 | `User-agent: Bot2`, token `Bot2` | Deliberate. Upstream `ExtractUserAgent` keeps `[A-Za-z_-]` only, and RFC 9309 §2.2.1 allows only letters, `_` and `-` in a product token, so `Bot2` is not a valid token. The validator warns `user_agent_cut`, naming `Bot` (ROBO-zvhrayhx). |
| 14 | `Disallow: /a%3cb`, path `/a%3cb` | Deliberate fidelity to upstream (`MaybeEscapePattern` upper-cases the rule's escape, never the URL's). The validator gap is ROBO-kormmfyg. |
| 15 | `Disallow: /caf%C3%A9`, raw `é` in the URL | Deliberate: a caller contract. The matcher never escapes the URL, and `allowed_by_robots_text()` leaves supplying an escaped URL to the caller (`design/edge-case-catalog.md`, `enc-nonascii-rule-raw-url`). RFC 9309 §2.2.2 escapes both sides, as every library does. |
| 16 | `Disallow: /a b`, path `/a%20b` | Deliberate fidelity to upstream (`MaybeEscapePattern` escapes non-ASCII bytes only). A space is not valid in an RFC 9309 path pattern (§2.2). The validator warns (`rule_inner_whitespace`). |
| 17 | `size-long-line` | Deliberate: upstream's `kMaxLineLen` line buffer; the validator reports it (`line_too_long`). RFC 9309 sets no line limit. |

Class 1 was handed over as a sixth such class; it is not one, since `jv`
stacks as Google does. Its verdict (deliberate, Google's documented
behavior) is in class 1.

## Errors and API constraints

| Library | Input | What happens |
|---|---|---|
| `jv` | the token `*` (`err-star-token`) | `IllegalArgumentException`: "Parameter 'robotNames': the wildcard user-agent ('*') should not be included". An API constraint: every other token runs. |
| `go` | `Crawl-delay: soon` (`err-crawl-delay-text`) | the whole parse fails ("strconv.ParseFloat: parsing "soon": invalid syntax"), so no URL gets an answer |
| `go` | a rule before any `User-agent` (`rule-before-agent`, catalog `grp-rule-before-user-agent`, and `enc-bom-doubled`, whose BOM hides the `User-agent` line) | the whole parse fails ("Disallow before User-agent") |
| `rtx` | a line whose field name is empty (`:` or `: x`) as the first field line (`err-empty-field`: `:` / `User-agent: *` / `Disallow: /x`; `:` alone also triggers it) | "'names' attribute [2] must be the same length as the vector [0]", from `robotstxt`'s own parser; `spb` reads the same body |
| `pro` | a byte that is not UTF-8 in a rule (catalog `enc-latin1-rule`) | `UnicodeEncodeError` ("surrogates not allowed") while quoting the rule, on every URL; an effect of the runner's `surrogateescape` decoding meeting protego's UTF-8 encode |

Every library ran on every input; none was left out. The rows above are
the only ones without an answer.

## Reproducing

```sh
Rscript dev/library-comparison/run.R <libcmp> [out_dir]
```

`<libcmp>` is the one-command-per-library runner (its interface is in the
script's header). The script rebuilds the manifests from the committed
fixtures, writes `matrix.tsv`, and exits 1 when a class fixture's live
answer drifts from the answer recorded in its `manifest.csv`, when
robotstxtr differs from the reference on a row its expected-split list does
not name, or when a named row stops differing. It stops with a message
when `google-ref` gives no answers. The pinned test reads the same fixtures
and checks robotstxtr's recorded answer on every class row, with no
runner.
