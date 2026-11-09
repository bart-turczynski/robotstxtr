# Edge-case catalog: odd robots.txt files under the Google matcher

- Issue: ROBO-mxermwed
- Date: 2026-11-09
- Fixtures: `tests/testthat/fixtures/edge-cases/` (one body per case, plus
  `manifest.csv`)
- Pinned by: `tests/testthat/test-edge-cases-mxermwed.R`

Every validator gap found on 2026-10-07 was an edge case nobody had written
down. This catalog is one deliberate pass over odd robots.txt files. For each
case it records what RFC 9309 says, what Google documents, what the vendored
Google matcher decides, what `robots_validate_text()` reports, and whether the
outcome would surprise the site owner. It records behavior; it fixes nothing.
Cases already pinned by earlier work are cited, not repeated.

All bodies are synthesized by hand. No fixture is a copy of a real site's
robots.txt.

## Reading the fixtures

`manifest.csv` has one row per check, so a case with three URLs has three
rows. Columns:

| column | meaning |
|---|---|
| `id` | the case id, also the body file's name without extension |
| `family` | `encoding`, `escaping`, `blank`, `comments-sitemaps`, `grouping`, `size`, `content`, `redirect` or `other` |
| `body_file` | `<id>.txt` holds the body verbatim; `<id>.hex` holds its bytes as lowercase hexadecimal, 32 bytes a line, whitespace ignored |
| `path` | the URL path checked, on `https://example.com` (UTF-8 where it holds a raw non-ASCII character) |
| `token` | the product token passed to the matcher |
| `google_decision` | `allow` or `disallow` from the vendored Google matcher today |
| `rfc9309_decision` | what RFC 9309 requires, or `unspecified` where the RFC does not settle it (often because the line is not valid RFC syntax). A body that is not UTF-8 (UTF-16, a Latin-1 byte, any invalid UTF-8 sequence) breaks §2.3's "The file MUST be UTF-8 encoded", and the RFC leaves reading one to the implementor ("MAY bridge encoding mismatches", the close of §2.2.2), so every check on such a body is `unspecified`, whichever line holds the bad bytes |
| `validator_codes` | `robots_validate_text()` diagnostics as `code@line`, in emitted order, `;`-separated; `NA` for a document-level code; empty when there are none |
| `surprise` | `yes` when a site owner reading the file would likely expect another outcome |
| `known_gap` | `ROBO-<id>: <phrase>`, the fp issue that tracks a gap in current behavior |

Every `surprise = yes` case is covered in one of three ways, and the test file
checks that none is left out:

- by an fp issue named in `known_gap`;
- by an existing validator diagnostic that already reports the surprise: a
  surprise that an existing validator diagnostic already reports counts as
  covered, and the case's row below names that code (the test asserts it
  fires);
- `esc-tilde-rule-pct7e-url` only: the difference lies in the URL, not the
  file (see its row).

A body the pre-commit hooks would rewrite (end-of-file-fixer,
trailing-whitespace, mixed-line-ending) is stored as hex: every body with a
BOM, NUL, CR, invalid UTF-8, trailing whitespace or no final newline. The
`.txt` bodies are checked to be hook-clean by the test file. A consumer such
as the library comparison (ROBO-dqqkvwts) needs only the manifest and the
hex rule above.

The Google decision comes from `allowed_by_robots_text()`, and the test also
checks that `robots_evaluate_text_v1()` with the `google` ruleset and backend
agrees on every NUL-free body. R strings cannot carry a NUL, so a NUL-bearing
body (the UTF-16 cases) is decoded as the fetch path decodes it: NUL bytes
dropped (`R/body-decode.R`, `nul_free_bytes()`), then handed to the same
binding. Google's own C++ reads the NULs instead; see `enc-utf16le-no-bom`.

## Sources

- **RFC 9309** — https://www.rfc-editor.org/rfc/rfc9309.html : §2.2 (the
  ABNF: `path-pattern = "/" *UTF8-char-noctl`; `identifier` is letters, `_`
  and `-` only; a `#` starts a comment; `EOL = *WS [comment] NL`), §2.2.1
  (product tokens: "MUST contain only uppercase and lowercase letters",
  underscores and hyphens; case-insensitive match; matching groups combined;
  `*` only when none match), §2.2.2 (match from the path's first octet,
  "SHOULD be case sensitive", longest match, Allow on a tie; non-ASCII octets
  percent-encoded before comparison; a percent-encoded US-ASCII octet decoded
  "unless it is a reserved character" or outside the unreserved range),
  §2.2.3 (`#`, `$`, `*`), §2.2.4 ("a "Sitemaps" record MUST NOT terminate a
  group"), §2.3 ("The file MUST be UTF-8 encoded"), §2.5 (parsing limit at
  least 500 KiB). The last paragraph of §2.2.2 lets implementors "bridge
  encoding mismatches if they detect that the robots.txt file is not UTF-8
  encoded". The RFC never mentions a byte-order mark.
- **Google robots.txt spec** —
  https://developers.google.com/crawling/docs/robots-txt/robots-txt-spec :
  "File format" (UTF-8; lines separated by CR, CR/LF or LF; a leading BOM is
  ignored; characters outside UTF-8 may be ignored, "potentially rendering
  robots.txt rules invalid"; 500 KiB), "Syntax" (`<field>:<value>`, leading
  and trailing whitespace ignored, `#` comments, invalid lines ignored),
  "Grouping of lines and rules" (repeated user-agent lines share a group),
  "user-agent" (case-insensitive), "sitemap" ("The sitemap field isn't tied
  to any specific user agent"), "Order of precedence for user agents" (one
  group per crawler, the most specific; `googlebot/1.2` and `googlebot*` equal
  `googlebot`; groups for one agent combined; specific and `*` groups not
  combined; unmatched crawlers take `*`; "Rules other than allow, disallow,
  and user-agent are ignored by the robots.txt parser", with an example that
  puts a `sitemap` line between two user-agent lines of one group), "URL
  matching based on path values" (case-sensitive; rules
  compared in percent-encoded form; `Disallow: /foo/bar/ツ` and
  `/foo/bar/%E3%83%84` identical; trailing `*` ignored), "Order of precedence
  for rules" (longest path wins; least restrictive on a conflict).
- **Google common crawlers** —
  https://developers.google.com/crawling/docs/crawlers-fetchers/google-common-crawlers :
  lists `Googlebot-Image` and `Googlebot` as that crawler's tokens; "you
  need to match only one crawler token for a rule to apply" (read from the
  page's HTML; design/engine-profiles.md §5a).
- **Vendored matcher** — `src/robots.cc`: `ParseRobotsTxt` skips one leading
  UTF-8 BOM (`utf_bom`) and cuts a line at `kMaxLineLen`
  (`kBrowserMaxLineLen * 8`, so 16,663 bytes of content);
  `MaybeEscapePattern` percent-escapes non-ASCII bytes and upper-cases
  existing escapes in rule values only, never in the URL;
  `ExtractUserAgent` keeps the leading run of `[A-Za-z_-]` of a User-agent
  value.

## Already covered elsewhere (cited, not repeated)

| topic | where |
|---|---|
| Content-Type and the `html`/`xml`/`json`/`binary` content flag | ROBO-nhuirvrd: `R/content-check.R`, `tests/testthat/test-content-type-nhuirvrd.R` |
| BOM at the start, NUL, malformed UTF-8 (validator evidence) | `test-robots_validate-htvtajbr.R` ("BOM, NUL, and malformed UTF-8 hazards…") |
| NUL bytes: dropped, not truncated; matched on the fetch and v1 paths | `test-nul-body-hcqrzikz.R` |
| An empty body; a rule-free body (blank lines, CRLF blanks, comments only, Sitemap only, both, User-agent only, Latin-1 comment) gets `no_rules` | `test-upstream-matcher-cases-r9.R` ("an empty supplied body…"), `test-no-rules-vxrzcqpe.R`, `test-robots_validate-htvtajbr.R` ("an empty document…") |
| Percent-escaped and raw-UTF-8 rules matching an escaped URL; lower-case escape canonicalized in the reported value | `test-upstream-matcher-cases-r9.R`, `test-allowed_by_robots_text-r3.R` |
| Path letter case; `*` and `$` basics; longest match; Allow wins a tie | `test-upstream-matcher-cases-r9.R` |
| Empty Allow/Disallow ignored | `test-empty-path-directives-r9.R` |
| `#` fragments and `%23` in URLs | `test-fragment-convergence-irdjzbay.R` |
| Caller token with a version suffix (`FooBot/2.1`) or other letter case | `test-upstream-matcher-cases-r9.R` ("user-agent group matching is exact…") |
| Missing colon and typo spellings accepted | `test-robots_validate-htvtajbr.R` |
| A named group drops the `*` rules (validator) | ROBO-gfjotdrr: `test-wildcard-inheritance-gfjotdrr.R` |
| Rule values: missing leading slash, inner `$`, sitemap URLs | ROBO-xblfzkid: `test-robots_validate-value-checks-xblfzkid.R` |
| No rules | ROBO-vxrzcqpe: `test-no-rules-vxrzcqpe.R` |
| Status diagnostics on fetch | ROBO-ybzbxfml: `test-validate-status-ybzbxfml.R` |
| Allow ties a Disallow | ROBO-fdhmlvwm: `test-allow-tie-disallow-fdhmlvwm.R` |
| Duplicate rules | ROBO-xexjgecr: `test-duplicate-rule-xexjgecr.R` |
| Lines over the 16,663-byte buffer (validator) | `test-robots_validate-htvtajbr.R` ("overlong parser lines are errors") |
| Size: the 512,000-byte Google window, a body cut at `max_bytes`, the Yandex 500 KB rule | ROBO-ldpahknv: `test-truncated-robots-ldpahknv.R`; `test-engine-contract-v1-unowhvjx.R` (window tests); ROBO-ptibdnvy: `test-google-cut-prefix-ptibdnvy.R`; ROBO-arrtietl: `test-yandex-cut-file-arrtietl.R` |
| ASCII-only case folding of tokens under any locale | `test-ascii-case-folding-tldlaxgq.R` |
| Googlebot-Image (and GoogleOther-Image) not falling back to the parent token's group, both directions | ROBO-mxsphtoo: `test-token-fallback-mxsphtoo.R`; `grp-googlebot-image-fallback` below adds the manifest rows |

## The cases

Decisions are per check: `path as token → decision`. The token is `FooBot`
unless shown. "RFC" gives the RFC 9309 outcome or says why it is
unspecified; "Google doc" is the documented behavior; "Matcher" is the
vendored matcher's decision today; "Validator" lists the codes.

### Encoding

| id | RFC 9309 | Google doc | Matcher | Validator | Surprise |
|---|---|---|---|---|---|
| `enc-bom-start` — BOM, then `Disallow: /a` | unspecified: the RFC never mentions a BOM, and BOM+`User-agent` is not valid syntax (§2.2); `/b` allow either way | leading BOM ignored ("File format") | `/a` disallow, `/b` allow | `byte_order_mark@1` (warning) | no |
| `enc-bom-mid-file` — BOM before line 2 `Disallow: /a` | unspecified | not documented; a BOM is only skipped at the start | `/a` allow: the line's key is BOM+`Disallow`, unknown | `unknown_directive@2`, `no_rules` | yes; **known gap**: no BOM diagnostic mid-file |
| `enc-bom-before-user-agent` — BOM before a second group's `User-agent: FooBot` | unspecified | not documented | `/a` disallow, `/b` disallow: the FooBot line is unknown, so FooBot falls to `*`, and its `Disallow: /b` joins the `*` group | `unknown_directive@4` | yes; **known gap**: the lost group is not reported as a BOM |
| `enc-bom-doubled` — two BOMs, then the rules | unspecified | only one leading BOM is documented as ignored | `/a` allow: the second BOM hides `User-agent`, so the rule has no group | `byte_order_mark@1`, `unknown_directive@1`, `rule_without_user_agent@2`, `missing_user_agent` | yes; covered by `rule_without_user_agent` (`byte_order_mark` alone would say the BOM is skipped) |
| `enc-utf16le-bom` — UTF-16LE with BOM | not UTF-8 (§2.3, MUST); MAY bridge (§2.2.2): unspecified | must be UTF-8 | `/a` allow (NULs dropped, the `FF FE` prefix spoils line 1, the rule has no group) | `nul_byte@1..3`, `invalid_utf8`, `malformed_line@1`, `no_rules` | yes; covered by `nul_byte` (errors) |
| `enc-utf16le-no-bom` — UTF-16LE, no BOM | as above | must be UTF-8 | `/a` **disallow**: with the NULs dropped the file is plain ASCII. Google's C++ reads the NULs and would ignore the lines (allow); robotstxtr's drop is deliberate (`R/body-decode.R`) | `nul_byte@1..3`, `malformed_line@1`, `no_rules` | yes; **known gap**: `no_rules` ("places no restrictions") while the matcher enforces `Disallow: /a` |
| `enc-utf16be-bom` — UTF-16BE with BOM | as above | must be UTF-8 | `/a` allow | `nul_byte@1..2`, `invalid_utf8`, `malformed_line@1`, `no_rules` | yes; covered by `nul_byte` (errors) |
| `enc-latin1-rule` — `Disallow: /caf` + Latin-1 `é` (`E9`) | non-UTF-8 file (§2.3); unspecified | non-UTF-8 characters may be ignored, rules may become invalid | `/caf%E9` disallow (the byte is escaped to `%E9`), `/caf%C3%A9` allow | `invalid_utf8` (no line) | yes: the UTF-8 URL a browser sends is not blocked; covered by `invalid_utf8` (error) |
| `enc-latin1-comment` — Latin-1 byte inside a comment only | the file is not UTF-8 (§2.3), though only a comment holds the byte: unspecified | as above | `/a` disallow, unaffected | `invalid_utf8` (error, no line) | no; **known gap**: a lineless error for a byte that changes nothing |
| `enc-invalid-utf8-key` — `Dis\xFFallow: /a` | not UTF-8 (§2.3): unspecified; were the file read anyway, not a valid line | invalid lines ignored | `/a` allow | `invalid_utf8`, `unknown_directive@2`, `no_rules` | no |
| `enc-nonascii-rule-raw-url` — `Disallow: /café`, URL with a raw `é` | octets percent-encoded on both sides before comparison (§2.2.2): disallow | rules compared in percent-encoded form | `/café` allow, `/caf%C3%A9` disallow: the matcher escapes the rule, never the URL; `allowed_by_robots_text()` documents that the caller supplies an escaped URL | none | no (a caller-input caveat, not a site-owner one) |
| `enc-escaped-rule-raw-url` — `Disallow: /caf%C3%A9`, raw `é` URL | disallow | as above | `/café` allow, same reason | none | no |

Engine note: Yandex prohibits Cyrillic in rules and documents a
Punycode/%-encoding requirement (`design/engine-profiles.md` §8); this
catalog does not run the Yandex matcher.

### Escaping

| id | RFC 9309 | Google doc | Matcher | Validator | Surprise |
|---|---|---|---|---|---|
| `esc-pct2f-rule-slash-url` — `Disallow: /a%2Fb` | `%2F` is reserved, stays encoded (§2.2.2): `/a/b` allow, `/a%2Fb` disallow | compared in encoded form | same | none | no |
| `esc-slash-rule-pct2f-url` — `Disallow: /a/b`, URL `/a%2Fb` | allow | as above | allow | none | no |
| `esc-pct7e-rule-tilde-url` — `Disallow: /%7Ejoe` | `~` is unreserved, so `%7E` is decoded: `/~joe` disallow (§2.2.2 states the decoding for the URI; its Figure 4 maps `/foo/bar/%62%61%7A` to `/foo/bar/baz`, which reads as the rule side too) | not documented for unreserved characters | `/~joe` **allow**, `/%7Ejoe` disallow | none | yes; **known gap**: nothing flags an escaped unreserved character |
| `esc-tilde-rule-pct7e-url` — `Disallow: /~joe`, URL `/%7Ejoe` or `/%7ejoe` | the URI's `%7E` MUST be decoded (§2.2.2): disallow | not documented | allow for both | none | yes, but not a validator gap: the file is correct RFC syntax and nothing in it could be flagged; the difference is the URL's form. `allowed_by_robots_text()` passes the URL to the matcher unchanged and leaves supplying an appropriately `%`-escaped URL to the caller ("R does not clean, decode, canonicalize, or reserialize the URL"), and the PRD's R-package rules say "do not normalize Unicode or percent escapes on the matcher side" (`design/PRD.md`) |
| `esc-lower-hex-rule` — `Disallow: /a%3cb` | `<` is neither reserved nor unreserved, so `%3c` stays encoded on both sides (§2.2.2): `/a%3cb` matches octet for octet, disallow; `/a%3Cb` hinges on whether `%3c` equals `%3C`, which the RFC does not say: unspecified | not documented | `/a%3Cb` disallow (rule upper-cased), `/a%3cb` **allow** (URL not normalized): the exact path the owner wrote is not blocked | none | yes; **known gap**: ROBO-kormmfyg |
| `esc-path-letter-case` — `Disallow: /Private` | SHOULD be case-sensitive | case-sensitive | `/Private` disallow, `/private` allow | none | no |
| `esc-space-in-rule` — `Disallow: /a b` | a space is not allowed in `path-pattern` (§2.2); unspecified | not documented | `/a%20b` allow, `/a` allow: the rule keeps a raw space no escaped URL holds | none | yes; **known gap**: nothing flags a raw space in a rule |
| `esc-star-leading` — `Disallow: *.pdf` | not a valid `path-pattern` (must start `/`); unspecified | `*` matches any run | `/x.pdf` disallow, `/x.html` allow | none (a leading `*` is accepted) | no |
| `esc-double-star` — `Disallow: /a**b` | `*` is zero or more of any character (§2.2.3) | same | `/axxb` disallow, `/a` allow | none | no |
| `esc-star-dollar` — `Disallow: /*$` | disallow every path | same | `/` and `/anything` disallow | none | no |
| `esc-dollar-then-star` — `Disallow: /a$*` | `$` mid-pattern unspecified | `$` marks the end only | `/a` allow, `/a$` and `/a$b` disallow (literal `$`) | `rule_inner_dollar@2` | yes; covered by `rule_inner_dollar` |
| `esc-lone-dollar` — `Disallow: $` | not a valid `path-pattern` | not documented | `/`, `/a` allow (never matches) | `rule_missing_leading_slash@2` | yes; covered by `rule_missing_leading_slash` |
| `esc-query-wildcard` — `Disallow: /*?` | the query is part of the matched path | same | `/p?x=1` disallow, `/p` allow | none | no |
| `esc-star-longer-pattern-wins` — `Disallow: /p`, `Allow: /p*` | both rules match `/p` and `/px` (`*` is zero or more characters, §2.2.3); the most specific match is the one with the most octets (§2.2.2), and `/p*` has three to `/p`'s two: allow | the trailing `*` is ignored, so the two rules are equivalent, and the least restrictive wins | `/p`, `/px` allow | none | no |

### Blank and empty

| id | RFC 9309 | Google doc | Matcher | Validator | Surprise |
|---|---|---|---|---|---|
| `blank-whitespace-only` — spaces, a tab, a CRLF | `emptyline` only: no rules | invalid lines ignored | `/a` allow | `no_rules` | no |
| `blank-crlf` — CRLF throughout | `NL` includes CRLF (§2.2) | CR/LF separators | `/a` disallow, `/b` allow | none | no |
| `blank-cr-only` — CR only | CR is a valid `NL` | CR separators | `/a`, `/b` disallow, `/c` allow | none | no |
| `blank-mixed-endings` — CRLF, CR, LF, then no final newline | each is a line end; the unterminated last line (`/c`) is unspecified, as below | same | `/a`, `/b`, `/c` disallow, `/d` allow | none | no |
| `blank-no-final-newline` | unspecified: the ABNF ends every line with `NL`, and the RFC says nothing of a file without one | not documented | `/a` disallow | none (`final_newline = FALSE` on the document row) | no |
| `blank-trailing-whitespace` — `User-agent: * ` and `Disallow: /a \t` | `*WS` before `EOL` | trailing spaces ignored | `/a` and `/a%20` disallow | none | no |

Zero bytes and blank-only bodies are pinned elsewhere (table above).

### Comments and sitemaps

| id | RFC 9309 | Google doc | Matcher | Validator | Surprise |
|---|---|---|---|---|---|
| `cmt-only` | no groups, no rules apply (§2.2.1) | comments ignored | `/a` allow | `no_rules` | no |
| `cmt-sitemap-only` | other records (§2.2.4) | sitemap lines are not rules | `/a` allow | `no_rules` | no |
| `cmt-comments-and-sitemap` | as above | as above | `/a` allow | `no_rules` | no |
| `cmt-user-agent-only` — `User-agent: *` and nothing else | an empty group | not documented | `/a` allow | `no_rules` | no |
| `cmt-inline-comment` — `Disallow: /a # private` | comment stripped | everything after `#` ignored | `/a` and `/a%20` disallow | none | no |
| `cmt-hash-in-rule` — `Disallow: /a#b` | `#` starts a comment, so the rule is `/a` | same | `/a` **and `/abc`** disallow | none | yes; **known gap**: nothing flags a `#` that shortens a rule into a wider prefix |

The validator side of the rule-free cases is ROBO-vxrzcqpe's; these rows add
the matcher decision for the comparison work.

### Grouping

| id | RFC 9309 | Google doc | Matcher | Validator | Surprise |
|---|---|---|---|---|---|
| `grp-shared-group` — two User-agent lines, one rule | both tokens share the group | repeated user-agent lines share a group | FooBot, BarBot `/x` disallow; BazBot allow | none | no |
| `grp-user-agent-after-rule` — `User-agent` after a rule | a new group starts | same | FooBot: `/x` disallow, `/y` allow; BarBot: `/x` allow, `/y` disallow | none | no |
| `grp-blank-line-in-group` — blank line between User-agent and rule | `emptyline` allowed inside a group (§2.2) | not documented | `/x` disallow | none | no |
| `grp-blank-line-between-agents` | as above | not documented | FooBot and BarBot `/x` disallow | none | no |
| `grp-same-agent-twice` — FooBot twice (second as `foobot`), BarBot between | combined (§2.2.1) | combined | `/x`, `/y` disallow, `/z` (BarBot's) allow | none | no |
| `grp-rule-before-user-agent` | a rule outside a group is not valid syntax | invalid lines ignored | `/x` allow, `/y` disallow | `rule_without_user_agent@1` | no |
| `grp-token-version-in-file` — `User-agent: Googlebot/2.1` | `/` is not allowed in a token; unspecified | `googlebot/1.2` equals `googlebot` | `/x` as `Googlebot` disallow | none | no |
| `grp-token-letter-case-in-file` — `User-agent: GOOGLEBOT`, token `googlebot` | case-insensitive | case-insensitive | disallow | none | no |
| `grp-googlebot-image-fallback` — a `Googlebot` group and a `*` group, token `Googlebot-Image` | `*` applies (no group names the token) | the common-crawlers page lists `Googlebot` as Googlebot-Image's second token, so Google's crawler follows the `Googlebot` group (engine-profiles.md §5a) | `/x` allow, `/y` disallow (the `*` group): the binding reads the one token only | `wildcard_rules_not_inherited@1` | yes; **known gap**, a maintainer decision: ROBO-fbbmvbob |
| `grp-user-agent-with-space` — `User-agent: Foo Bot` | not a valid token; unspecified | not documented | as `Foo` disallow, as `FooBot` allow: the value is cut at the space | none | yes; **known gap**: a cut User-agent value is not flagged |
| `grp-digit-in-token` — `User-agent: Bot2` | digits are not allowed in a token (§2.2.1); unspecified | not documented | as `Bot2` allow, as `Bot` disallow: the value is cut at the digit | none | yes; **known gap**: same |
| `grp-star-prefixed-token` — `User-agent: *bot` | not a valid token; unspecified | not documented | allow: `*bot` is neither global nor a token | none | yes; **known gap**: same |
| `grp-sitemap-mid-group` — Sitemap between two rules | MUST NOT terminate a group (§2.2.4) | "Rules other than allow, disallow, and user-agent are ignored by the robots.txt parser" ("Order of precedence for user agents"; its example has a sitemap line inside a group of two user-agent lines); a sitemap line between rules is not shown | `/x`, `/y` disallow | none | no |
| `grp-unknown-between-agents` — `Crawl-delay` between two User-agent lines | other records; unspecified for the first agent | unsupported fields ignored | FooBot and BarBot `/x` disallow: the unknown line does not split them | `unsupported_directive@2` | no |

### Size and limits

| id | RFC 9309 | Google doc | Matcher | Validator | Surprise |
|---|---|---|---|---|---|
| `size-long-line` — `Disallow: /` + 16,700 `a` + `/secret` | no line limit; the full rule does not match `…/public` | not documented | the line is cut at 16,663 bytes, so the stored rule is a shorter prefix: `/aaa…/public` **disallow**, `/a` allow | `line_too_long@2` (error) | yes; covered by `line_too_long` |
| `size-many-groups` — 1,000 groups `botaaa`…`botbml`, one rule each | each token its own group | not documented | the last group applies to `botbml` (`/p1000/` disallow, `/p999/` allow); `botaaa` allow on `/p1000/` | none | no |

A first fixture named its groups `bot1`…`bot1000`: every name cut to `bot`,
so all thousand groups merged. That is `grp-digit-in-token` again.
The 500 KiB boundaries are pinned elsewhere (table above).

### Content and redirects

| id | RFC 9309 | Google doc | Matcher | Validator | Surprise |
|---|---|---|---|---|---|
| `content-spam-html` — a casino/popunder page with scripts, links and an iframe served as robots.txt | no valid records: no rules | an HTML download is parsed for rules and everything else ignored | `/`, `/private/` allow | `accepted_missing_colon`, `unknown_directive` and `malformed_line` rows, `no_rules`; `validation_status = "error"` | yes; **known gap**: no diagnostic names the body as HTML (the content flag exists only on fetch rows, ROBO-nhuirvrd) |
| `redirect-cross-host-html` — `http://a.example/robots.txt` answers 301 to `https://b.example/landing`, an HTML page | redirects followed, reached rules applied to the first authority (§2.3.1.2) | redirects followed | the fetch follows (`redirect_count = 1`, `effective_url` the landing page, `content_type = "text/html"`, `content_flag = "html"`, v1 `usable_body` / `http_200_use_rules`), and every URL is allowed | the landing page's lines (`malformed_line`, `accepted_missing_colon`, `unknown_directive`, `no_rules`); nothing about the redirect | yes; **known gap**: ROBO-gokbvzcb |

The redirect case runs through the ssrfr fake (`helper-fake-ssrfr.R`); its
fetch-layer values are pinned in the test file, not in the manifest.

### Other

| id | RFC 9309 | Google doc | Matcher | Validator | Surprise |
|---|---|---|---|---|---|
| `oth-space-before-colon` — `Disallow : /a` | `rule = *WS ("allow" / "disallow") *WS ":"` allows it (§2.2): disallow | spaces optional | disallow | none | no |
| `oth-indented-lines` — leading spaces and a tab | `*WS` before the key | leading whitespace ignored | disallow | none | no |
| `oth-directive-letter-case` — `USER-AGENT`, `DISALLOW` | keys are case-insensitive ABNF strings | field names case-insensitive | disallow | none | no |

## Known gaps found

Filed 2026-11-09 unless marked; none is fixed here. Each is pinned in the
test file with a `# known gap (ROBO-xxxxxxxx):` comment naming its issue, so
a fix turns its block red.

1. ROBO-atkmqcov — `enc-bom-mid-file`, `enc-bom-before-user-agent`: a BOM after the start is
   only an `unknown_directive`; a lost User-agent group is not called out.
2. ROBO-igrkabdb — `enc-utf16le-no-bom`: `no_rules` says the file restricts nothing while the
   NUL-dropping matcher enforces its rules.
3. ROBO-sniltuap — `enc-latin1-comment`: `invalid_utf8` has no line and is an error even when
   only a comment holds the byte.
4. ROBO-gaczsrgj — `esc-pct7e-rule-tilde-url`: no diagnostic for an escaped unreserved
   character, which Google never matches against the raw form.
5. ROBO-dlgeqluf — `esc-space-in-rule`: no diagnostic for a raw space inside a rule.
6. ROBO-gjhpykcj — `cmt-hash-in-rule`: no diagnostic for a `#` that cuts a rule into a wider
   prefix.
7. ROBO-zvhrayhx — `grp-user-agent-with-space`, `grp-digit-in-token`,
   `grp-star-prefixed-token`: a User-agent value the matcher cuts or never
   matches is not flagged.
8. ROBO-ccfsanhq — `content-spam-html`: no validator diagnostic names an HTML body.
9. ROBO-fbbmvbob (maintainer decision) — `grp-googlebot-image-fallback`: the
   binding ignores Googlebot-Image's documented parent token `Googlebot`.
10. ROBO-kormmfyg — `esc-lower-hex-rule`: the matcher upper-cases a rule's
    lower-case escape but not the URL's, so `Disallow: /a%3cb` allows the
    exact path `/a%3cb`; no diagnostic.
11. ROBO-gokbvzcb (filed earlier) — `redirect-cross-host-html`: no validator
    diagnostic for a successful cross-host redirect, here to an HTML page.
