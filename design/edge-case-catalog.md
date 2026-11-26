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
agrees on every NUL-free body, save the two `grp-googlebot-image-fallback`
rows, where that ruleset's crawler-token layer gives Googlebot-Image the
`Googlebot` group (ROBO-fbbmvbob; the test lists the v1 answers beside the
manifest's). R strings cannot carry a NUL, so a NUL-bearing
body (the UTF-16 cases) is decoded as the fetch path decodes it: each line
cut at its first NUL (`R/body-decode.R`, `decode_matcher_body()`), as
Google's own C++ reads it, then handed to the same binding (ROBO-pvqrfvol).

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
| NUL bytes: on the Google backend each line ends at its first NUL, the document is not truncated; matched on the fetch and v1 paths | `test-nul-body-hcqrzikz.R`, `test-google-nul-line-end-pvqrfvol.R` |
| An empty body; a rule-free body (blank lines, CRLF blanks, comments only, Sitemap only, both, User-agent only, Latin-1 comment) gets `no_rules` | `test-upstream-matcher-cases-r9.R` ("an empty supplied body…"), `test-no-rules-vxrzcqpe.R`, `test-robots_validate-htvtajbr.R` ("an empty document…") |
| Percent-escaped and raw-UTF-8 rules matching an escaped URL; lower-case escape canonicalized in the reported value | `test-upstream-matcher-cases-r9.R`, `test-allowed_by_robots_text-r3.R` |
| Path letter case; `*` and `$` basics; longest match; Allow wins a tie | `test-upstream-matcher-cases-r9.R` |
| Empty Allow/Disallow ignored | `test-empty-path-directives-r9.R` |
| `#` fragments and `%23` in URLs | `test-fragment-convergence-irdjzbay.R` |
| Caller token with a version suffix (`FooBot/2.1`) or other letter case | `test-upstream-matcher-cases-r9.R` ("user-agent group matching is exact…") |
| Missing colon and typo spellings accepted | `test-robots_validate-htvtajbr.R` |
| A named group drops the `*` rules (validator); a full block lists only the lost `*` Allows | ROBO-gfjotdrr: `test-wildcard-inheritance-gfjotdrr.R`; ROBO-bwpacxtq: `test-full-block-wildcard-bwpacxtq.R` |
| Rule values: missing leading slash, inner `$`, sitemap URLs | ROBO-xblfzkid: `test-robots_validate-value-checks-xblfzkid.R` |
| Rule values: ASCII control bytes 0x01-0x08 and 0x0E-0x1F (NUL, tab, VT and FF have other codes; DEL is not flagged) | ROBO-rrzsktxc: `test-control-bytes-rrzsktxc.R` |
| Rule values: a literal `.` or `..` path segment (`rule_dot_segment`; not past a `?` or `*`, not an unbounded end, not `%2E`) | ROBO-rnjfbhvn: `test-dot-segment-rnjfbhvn.R` |
| Rule values: a `%` that starts no two-hex-digit escape (`rule_invalid_percent_escape`; an unfilled `%name%` is named; a trailing `%`, `%h` or one before `*` may match an escape) | ROBO-rswdwrnp: `test-invalid-percent-escape-rswdwrnp.R` |
| UTF-16 and UTF-32 identification: all four byte-order marks (UTF-32 before its UTF-16 prefix), short and partial marks, BOM-less UTF-16BE and UTF-32, and bodies the heuristic must not name (NUL-cut rules, control bytes, binary data, Latin-1, odd lengths); `encoding_signature` and `encoding_signature_basis` | ROBO-cvpkzckn: `test-utf16-utf32-identification-cvpkzckn.R` |
| Content-Type media type, charset and `us-ascii` conflict (validator; a missing header gives no row) | ROBO-plkpmoll: `test-content-type-diagnostics-plkpmoll.R` |
| Compressed bodies: gzip, zstd and zlib signatures (`compressed_body`, in place of every line, group and rule row; a zlib header only when its FLG byte and the 16 after it are not well-formed UTF-8, so `x^` text is silent, even with a Latin-1 byte past byte 18, or when FLG `01` opens a stored deflate block whose NLEN is LEN's ones' complement (RFC 1951 §3.2.4); short and partial signatures, a cut body, a body cut to its zlib header (flagged), character input), and the fetch row's raw `content_encoding` | ROBO-rozvglkd: `test-compressed-body-rozvglkd.R` |
| Unicode advisories (always run): U+FFFD, invisible or formatting characters (C1 controls included) and two or more Latin-1 mojibake sequences in raw Allow and Disallow values; silent controls (accented and CJK paths, one mojibake sequence, typed escapes, comments, other directives, invalid UTF-8, latin1 input, UTF-16), the leading U+200B or U+FEFF left to `rule_missing_leading_slash`, and the 100-row cap | ROBO-qxcwxtbm: `test-unicode-advisories-qxcwxtbm.R` |
| No rules | ROBO-vxrzcqpe: `test-no-rules-vxrzcqpe.R` |
| Status diagnostics on fetch | ROBO-ybzbxfml: `test-validate-status-ybzbxfml.R` |
| Allow ties a Disallow | ROBO-fdhmlvwm: `test-allow-tie-disallow-fdhmlvwm.R` |
| Duplicate rules | ROBO-xexjgecr: `test-duplicate-rule-xexjgecr.R` |
| Query-parameter rules: a parameter named right after the first `?` (`rule_query_parameter_position`; silent when every crawler has a twin, the value with that `?` written `*&`, or written `&` after a `*` that stands right before it; not past a `*`, with no `name=` after the `?`, with a final `$`, a dot segment before the `?` or on a cut body) | ROBO-fuhcwaom: `test-query-parameter-position-fuhcwaom.R` |
| Query-delimiter Disallows and indexing: a non-empty Disallow led by `/` or `*` whose canonical value (cut at `#`) holds `?`, `=` or `&` (`rule_query_crawl_not_index`, one info row per file on the first such line, five lines then a count, the explanation once: robots.txt controls crawling, not indexing, per Google's documentation; a heuristic on the pattern text with no parameter-name list, so `/collections/*sort_by*` is silent; not Allow rules, values not led by `/` or `*`, a Disallow an identical Allow ties, a lower-case-escape twin, rules before any User-agent, in a group naming only the AI-training token or only an empty User-agent; a group whose User-agent Google cuts to no token, such as `360Spider`, still counts, as Bing and Yandex read the whole value; a cut body is checked on the bytes read, so a line past the cut that would tie a Disallow is not seen; stands beside `rule_query_parameter_position`) | ROBO-jnnnkyat: `test-query-index-note-jnnnkyat.R` |
| Allow or Disallow pattern led by `*`, outside RFC 9309's `path-pattern` grammar (`*.pdf`, `*?`, `*`, `**x`, `*/feed/`) (`rule_star_led_pattern`, one info row per file on the first such line, five lines then a count; one sentence for every value: Google's matcher lets a `*` match any run of bytes, none included, from the path's first byte on, and counts each `*` as one byte of the rule's length; then "Bing and Yandex may read this rule differently"; no rewrite advice, as the added byte can change which rule wins; only rules of a group some crawler reads, so one before any User-agent or under only empty User-agent lines draws `rule_without_user_agent` only; not `/`-led, empty or inner-`*` values, a `*` in a comment or after a NUL; a cut body is checked on the lines read) | ROBO-ktmnbirm: `test-star-led-pattern-ktmnbirm.R` |
| Trailing-slash rules: a literal `P` beside `P/` of one type for the same crawlers (`rule_slash_pair`, on the whole-value merge), and a crawler deciding `P` and `P/` of a literal rule `P/` differently (`rule_slash_split`; every class and both merges must agree; not with `*`, `$`, `?`, `%`, a dot segment, the root or on a cut body; past a fixed work budget, linear in the rules, one `rule_check_stopped` row per check gives the counts found, checked and skipped) | ROBO-roypaoox: `test-slash-pair-split-roypaoox.R` |
| End-anchored Disallow a query escapes: a Disallow `D$` led by `/` or `*`, with no `?` and no other `$`, that decides its path `D` (each `*` written `x`) while `D?x=1` comes out allowed, or, where another rule matches those fillers, `y` with `D?y=2` or `z` with `D?z=3` (`rule_end_anchor_query`, one row per set of crawlers, showing the pair used; every class and both merges must agree; not ending in `*$`, with a dot segment, a `%` that starts no two-hex-digit escape, a space, tab, control byte or DEL, under the AI-training token or on a cut body; past the same fixed work budget, one `rule_check_stopped` row) | ROBO-nzcvlsvk: `test-end-anchor-query-nzcvlsvk.R` |
| Allow that reopens a blocked URL through a query: an Allow led by `*` or `/*` that names a path (`*/x/`, `/*/x/`, `/**/x$`) beside a Disallow `D` (no `?`, no final `$`) the same crawlers have, where the Allow decides `D?q=/x/` while `D` (each `*` written `x`) stays blocked, and, with every such Allow left out, the line deciding `D` blocks `D?q=/x/` too (`allow_reopens_through_query`, one row per set of crawlers naming that line, which may be another Disallow than `D`; each Allow's pairs read in line order up to the first that gives a row, an Allow shorter than a Disallow never paired with it; every class and both merges must agree; not `/*/` or `/*/*` alone, `/*.css` or `*?next=`, with a dot segment, a `%` that starts no two-hex-digit escape, a space, tab, control byte or DEL in either rule, under the AI-training token or on a cut body; past the same fixed work budget, one `rule_check_stopped` row) | ROBO-micbpqbc: `test-allow-reopens-through-query-micbpqbc.R` |
| Disallow that blocks a file a page may load: a Disallow led by `/` or `*` ending in `.js`, `.mjs`, `.cjs`, `.css`, `.json` or `.wasm` (any case), then only a run of `*`, a final `$` or a query with no `/`, with no `?`, `=` or `&` before the type, and whose file name (after the last `/`, up to the type's dot) is only a run of `*` (`/*.js`, `/assets/*.css`, `*.json$`), that decides its file (the value without the final `$` and `*` run, each other `*` written `x`, then `y`, then `z`), and, with every such Disallow left out, the file comes out allowed (`rule_render_resource_blocked`, one row per set of crawlers, naming beside it every such Disallow of the same crawlers that blocks the file by itself with the others left out (`/*.js` beside `/*.js$`), on either merge, so a named line can block it only when the crawler's whole User-agent value is read, not Google's shortened one; every class and both merges must agree; Google's reading, as the package's Yandex matcher counts a pattern's length without its `*` and can decide a close pair the other way; not folder rules, endpoints with no file type, exact or named files (`/push-worker.js`, `/js/main-*.js`, `/*.min.js`), fonts, images or source maps, not with a dot segment, a `%` that starts no two-hex-digit escape, a space, tab, control byte or DEL, under the AI-training token or on a cut body; past the same fixed work budget, one `rule_check_stopped` row) | ROBO-dwywkpes: `test-render-resource-dwywkpes.R` |
| Bare-prefix rule beside a sibling it matches: a literal `P` (led by `/`, not `/`, no `*`, `$`, `?`, `%`, no dot segment, not ending in `/`) and a longer literal `M` of the same type for the same crawlers whose value goes on from `P` with a byte other than `/` (`/feed` and `/feeds`, `/login` and `/login.php`), where Google's matcher, with `M` left out, has `P` decide `M`'s path (`rule_prefix_sibling`, one row per set of crawlers of `P`'s group on the first `P` line, five pairs at most, then a count, a sibling listed for fewer crawlers naming them; the advice names `P$` together with `P/`, as either alone drops paths `P` matches; `P` is the longest such rule; pairs form on the whole User-agent value merge only, so groups with the same value count as one, groups naming different crawlers give none, and a pair only Google's cut merge joins (`Foo/1.0` beside `Foo`) gets no row; every class and both merges must agree, a repeat of `P` that Google's merge joins deciding as `P`; not a subpath (`/feed/rss`), an opposite-type pair (`Disallow: /search` beside `Allow: /searchx`), an Allow that takes over with `M` left out (`Allow: /feeds`), a later repeat of `M`, under the AI-training token or on a cut body; past the same fixed work budget, one `rule_check_stopped` row) | ROBO-otomgbge: `test-prefix-sibling-otomgbge.R` |
| Separate groups with the same rules as written, which could share one group with their User-agent lines stacked (`user_agent_groups_same_rules`, info, one row per set of equal groups on the first group's first line, five other groups and five User-agent lines and rules of the stacked group, then counts; rules compared by key in any case and value as the parser reads it, blanks dropped, order and exact repeats ignored, an empty value counted, `/x` apart from `/x*` and `%7E` from `~`; only groups written in the plain form take part: every line up to the next group, and that group's first line, is blank, comment-only, a Sitemap after the last rule, or a User-agent, Allow or Disallow line with the key exactly so in any case and its colon at once (User-agent with a value), so a typo, a longer key such as `User-agent foo` or `Disallow foo`, a blank before the colon, a missing colon, an empty User-agent value, a control byte other than tab outside a comment, or a Crawl-delay, Clean-param, Host or unknown line leaves the group out; also withheld for `*`, policy-token, joined or cut User-agent lines, a NUL-cut line, a line past the parser's buffer, a line-1 User-agent line behind a full or partial byte-order mark (Bing does not read it), groups naming one crawler set only, and a cut body; skipped for a body with a lone CR (Bing and Yandex end a line at LF only) or over 500,000 bytes (Yandex allows all past it, Google reads 512,000); non-ASCII bytes are shown as escapes and names or rules over 64 bytes are shortened, so the stacked group is a guide, not a byte-exact copy; the owner's AI-crawler example, beside a `*` group too; a test stacks each row as shown and compares decisions on the Google, Bing and Yandex backends) | ROBO-rdxgnqhw: `test-same-rules-groups-rdxgnqhw.R` |
| Near-miss key of User-agent, Allow or Disallow: an unknown ASCII key, folded to ASCII lower case, within an optimal-string-alignment distance of 1 of `allow` or 2 of `disallow` or `user-agent` (`User-agnet`, `Usr-agent`, `User--agent`, `user_agent`, `Allwo`, `Disaloow`), equal to one once the run of non-letters leading it is removed (`//Allow`, `/Disallow`), or `Deny`; a key in range of both Allow and Disallow (`Dallow`, `Sallow`) resembles neither (`unknown_directive` keeps its code and severity and adds a sentence naming the directive it resembles and the effect: a rule near miss applies on no engine (Google only in a body with a lone CR); a User-agent near miss gets Google's reading only: it starts no group, so the rules after it up to the next User-agent line stay with the group above, naming the crawlers Google's group lists from its first User-agent line (each once in any case, five, then a count, backticks escaped, long names cut); or are in no group before the first User-agent line; or, between stacked User-agent lines, Google keeps the run, so the next group's rules apply to the crawlers above too, pointing to the `user_agent_joined_across_directive` row when it fires; then "Bing and Yandex may read the following lines differently"; no rewrite is advised; a cut body says lines past the cut were not read, a body over 512,000 bytes leaves out the effect on the rules after it; a backtick in the key is written `\x60`; accepted typo and prefix keys are never unknown, and non-ASCII keys (look-alikes, a misplaced byte-order mark, invisible characters, invalid UTF-8) get no sentence; each shape's claim is pinned on the Google backend) | ROBO-klmjfsvd: `test-near-miss-key-klmjfsvd.R` |
| A directive hidden in a value, from a lost line break: a User-agent, Allow, Disallow, Sitemap, Crawl-delay or Host value holding a second directive key and its colon (blanks allowed before it), after a space or tab in any ASCII case (`User-agent: * Disallow: /private/`) or glued on in its usual spelling (`ExampleBotAllow: /`, `*Disallow:`, `/admin/Crawl-delay: 10`), a glued key only before a blank or the value's end, `/` or `*` for Allow and Disallow, a digit for Crawl-delay, `http://` or `https://` in any ASCII case for Sitemap (`*Sitemap:https://example.com/s.xml`), and for Host only before a dotted host name (`/xHost:example.com`, not `LocalHost: x`), and not after `?`, `&`, `=`, `.` or `:`; `/a:b`, `/allowance/`, `/swallow:x`, `/search?q=Allow:x`, `/Host:8080`, `/Crawl-delay:/x`, `ExampleBot/1.0`, `Example Bot`, a Sitemap URL, a key in a comment, after a NUL, past the line buffer or with its colon past Google's 512,000-byte window hold none (`directive_in_value`, warning: the key and its byte column, that Google reads the text from it on as part of the value, the directive lost, the first key named and the rest counted, a key once however it is cased; the key and values shown cut at 64 bytes before a backtick is written `\x60`; Google's reading of the line: for a User-agent line the token its matcher reads (and, as `user_agent_cut` says, that a Google crawler token the value did not mean follows the group: `Googlebot Image`), replacing the line's `user_agent_cut` row, whose pointers (joined, wildcard, empty-Disallow, AI-training and duplicate-rule rows) name this row instead; when the text before the key is a token Google does not read, which group a crawler going by it gets (this group when another line of it names the token in any ASCII case or names `*`, else the `*` group, else none); and, when the next User-agent line joins the group, whose rules then apply to this line's agent (none for a `*` line in a group another `*` line names); then "Bing and Yandex may read the line differently"; the repeated-group and duplicate-in-group rows leave such a User-agent line out, neither the name nor the group it looks like; when the key is glued onto the token Google reads (`ExampleBotAllow:`), the rows that name crawlers (wildcard, empty-Disallow, joined, AI-training stacked rows and the License, near-miss, slash and prefix-sibling crawler lists) name it as no crawler, and a spaced key (`Foo Disallow: /x`) leaves the crawler meant, named by its token `Foo` while a row quoting the line keeps its text; `no_rules`, `rule_inner_whitespace` and `invalid_sitemap_url` stay; every Google claim is pinned on the Google backend) | ROBO-bkzqgvai: `test-directive-in-value-bkzqgvai.R` |
| A non-ASCII space (U+00A0, U+1680, U+2000 to U+200A, U+202F, U+205F, U+3000) or a zero-width character (U+200B to U+200D, U+2060, U+FEFF) in a User-agent value or before a key: Google's parser strips ASCII whitespace only, so `User-agent: bingbot` padded with no-break spaces before a comment is cut to `bingbot` and a key led by U+200B is unknown (the look-alike table gains these as a space kind, spelled as an ASCII space, and an invisible kind, dropped; the character is named by code point, Unicode name and byte; a `user_agent_cut` row holding one is a warning, names no package matcher and ends "Bing and Yandex may read this value differently"; each cut row is worded from one fact record per value (Google's reading, the reading of the value with its spaces made ASCII spaces, as its note spells them, and without its invisible characters and U+00AD, or unknown for invalid UTF-8, and whether `*` leads it past ASCII blanks and non-ASCII bytes) through one decision table; a value that without them reads as a Google token Google does not read here (`<U+200B>Googlebot`) is a warning and says, on condition, that Google's crawler of that token, named as Google spells it, does not get the group through the line (or, when another line of the group still reaches it, only that Google does not read the line so; a `*` line does not reach Google's crawlers that ignore `*`, nor a crawler another group names by its token or, where none does, its parent's), never that nothing changes for Google's crawlers, a sentence any cut row now prints only for a value holding no Google token's name, even split by bytes Google does not read or spelled with a look-alike letter (not for `"Googlebot"`, `Google bot`, or `Googlebot` after or holding U+2028, a Latin-1 byte or a cut sequence); `Google<U+00A0>bot` reads as `Google bot` does and `Googlebot<U+00A0>1.0` names Googlebot as `Googlebot 1.0` does, both still warnings; a cut row in a group that also has `User-agent: *` says a crawler going by the full value still gets the group, except Google's crawlers that ignore `*` and that no User-agent line of the group reads (no exception sentence when the group's lines read all four); any cut value led by `*` (`User-agent: *<U+00A0> # all`, `*bot`, `*` before or after U+2028, U+00AD or a Latin-1 A0 byte) is not `*` on Google: in place of the fallback and effect sentences the row says that no crawler, Google's included, gets the group through the line there, and where a crawler no group names goes (the other `*` group, no rules, or this group when another of its lines is `*`, except Google's crawlers that ignore `*`), a warning, but info for a valid UTF-8 value holding no named character (`*bot`) when another line of the group is `*`; a generated sweep over Google, `*` and other targets, every listed character, U+00AD, U+2028, U+043E in place of an `o`, a Latin-1 A0, a cut sequence and a tab, four positions and five group contexts (and, beside `*` or alone, AdsBot-Google, ASCII values Google cuts and values with two inserts) checks against the Google backend each sentence a row prints that Google's crawlers keep or lose the group, "follows this group", "nothing changes for that crawler", the weak "does not read it so" (for the token it quotes), the `*` tail, the three fallback sentences and each crawler the exception names or leaves out, and for an ASCII value Google cuts asks for the token it was written for; a `directive_in_value` row names it after Google's reading and before the stack and keeps its own clause only; an `unknown_directive` key led by one says what the line is without them (and without any before its colon), distinct characters counted as named: a rule Google does not apply, a Sitemap line Google does not read, or for User-agent the near-miss row's Google reading of where the rules after it go, ending "Bing and Yandex may read the following lines differently"; the near-miss sentence stays ASCII-only and never fires on such a key; one only before the colon of `User-agent`, `Allow`, `Disallow` or `Sitemap` is no unknown key, as Google reads those by prefix; a line starting with a misplaced U+FEFF keeps `misplaced_byte_order_mark`, and the key is read past it ("without it and the byte-order mark"), a later U+FEFF named as any other; a character inside a key is named but hides no key; ASCII padding, a U+FEFF alone at the start of a line (`misplaced_byte_order_mark`), one after a NUL or in a comment, and one the line buffer splits stay as before, and U+00AD and a Latin-1 A0 byte are not named as spaces; each Google claim is pinned on the Google backend) | ROBO-jsecjjyo: `test-invisible-space-jsecjjyo.R`; ROBO-ipzkxzhg: `test-invisible-space-jsecjjyo.R`, `test-user-agent-cut-sweep-jsecjjyo.R` |
| A key that only starts with `user-agent` in any ASCII case (`User-agents`, `User-agentfoo`, `User-agent-x`, `USER-AGENTS`), which Google's `KeyIsUserAgent` reads as a User-agent line (`accepted_directive_prefix`, warning, directive `user-agent`, on the key line: the key as written, Google's reading, that RFC 9309 defines no such record, then "Bing and Yandex may read this line differently"; the bare, stacked and after-a-rule shapes of `design/engine-disagreements.md` class 14 each get it, and Google's reading of each is pinned on the Google backend; the key is cut as for Allow and Disallow, past a line-1 byte-order mark and leading blanks, at the colon or, without one, the first blank, trailing blanks trimmed, so `User-agent :` and `User-agent *` stay silent; the typo forms `Useragent`, `Useragents` and `User agent` keep `accepted_directive_typo` only; a value Google cuts or one hiding a directive keeps its `user_agent_cut` or `directive_in_value` row beside it; the Allow and Disallow prefix rows now end with the same clause in place of saying how Bing and Yandex read the key) | ROBO-lgoehhhq: `test-user-agent-prefix-key-lgoehhhq.R` |
| Lines over the 16,663-byte buffer (validator) | `test-robots_validate-htvtajbr.R` ("overlong parser lines are errors") |
| Size: the 512,000-byte Google window, a body cut at `max_bytes`, the Yandex 500 KB rule | ROBO-ldpahknv: `test-truncated-robots-ldpahknv.R`; `test-engine-contract-v1-unowhvjx.R` (window tests); ROBO-ptibdnvy: `test-google-cut-prefix-ptibdnvy.R`; ROBO-arrtietl: `test-yandex-cut-file-arrtietl.R` |
| ASCII-only case folding of tokens under any locale | `test-ascii-case-folding-tldlaxgq.R` |
| Googlebot-Image (and GoogleOther-Image) not falling back to the parent token's group, both directions | ROBO-mxsphtoo: `test-token-fallback-mxsphtoo.R` (legacy path); `grp-googlebot-image-fallback` below adds the manifest rows. The v1 `google` ruleset falls back (ROBO-fbbmvbob: `test-crawler-tokens-fbbmvbob.R`) |

## The cases

Decisions are per check: `path as token → decision`. The token is `FooBot`
unless shown. "RFC" gives the RFC 9309 outcome or says why it is
unspecified; "Google doc" is the documented behavior; "Matcher" is the
vendored matcher's decision today; "Validator" lists the codes.

### Encoding

| id | RFC 9309 | Google doc | Matcher | Validator | Surprise |
|---|---|---|---|---|---|
| `enc-bom-start` — BOM, then `Disallow: /a` | unspecified: the RFC never mentions a BOM, and BOM+`User-agent` is not valid syntax (§2.2); `/b` allow either way | leading BOM ignored ("File format") | `/a` disallow, `/b` allow | `byte_order_mark@1` (warning) | no |
| `enc-bom-mid-file` — BOM before line 2 `Disallow: /a` | unspecified | not documented; a BOM is only skipped at the start | `/a` allow: the line's key is BOM+`Disallow`, unknown | `misplaced_byte_order_mark@2`, `unknown_directive@2`, `no_rules` | yes; covered by `misplaced_byte_order_mark`, which names the hidden Disallow (ROBO-atkmqcov) |
| `enc-bom-before-user-agent` — BOM before a second group's `User-agent: FooBot` | unspecified | not documented | `/a` disallow, `/b` disallow: the FooBot line is unknown, so FooBot falls to `*`, and its `Disallow: /b` joins the `*` group | `misplaced_byte_order_mark@4`, `unknown_directive@4` | yes; covered by `misplaced_byte_order_mark`, which says the User-agent line is not read and its rules join the group before it (ROBO-atkmqcov) |
| `enc-bom-doubled` — two BOMs, then the rules | unspecified | only one leading BOM is documented as ignored | `/a` allow: the second BOM hides `User-agent`, so the rule has no group | `byte_order_mark@1`, `misplaced_byte_order_mark@1`, `unknown_directive@1`, `rule_without_user_agent@2`, `missing_user_agent` | yes; covered by `misplaced_byte_order_mark`, which names the hidden User-agent (`byte_order_mark` alone would say the BOM is skipped) |
| `enc-utf16le-bom` — UTF-16LE with BOM | not UTF-8 (§2.3, MUST); MAY bridge (§2.2.2): unspecified | must be UTF-8 | `/a` allow (each line ends at its first NUL, so no line holds a directive) | `nul_byte@1..3`, `invalid_utf8@1`, `malformed_line@1`, `utf16_or_utf32_encoding`, `rules_after_nul_removal` | yes; covered by `utf16_or_utf32_encoding` (warning), which names the UTF-16LE byte-order mark and asks for a UTF-8 file (ROBO-cvpkzckn), and `nul_byte` (errors); `rules_after_nul_removal` says the NULs hide a rule, though with them removed it has no group here |
| `enc-utf16le-no-bom` — UTF-16LE, no BOM | as above | must be UTF-8 | `/a` allow: Google's C++, and since ROBO-pvqrfvol robotstxtr's Google backend, read each line only up to its first NUL, so no line holds a directive. Until then robotstxtr dropped the NULs, read plain ASCII and disallowed | `nul_byte@1..3`, `malformed_line@1`, `utf16_or_utf32_encoding`, `rules_after_nul_removal` | yes; covered by `utf16_or_utf32_encoding` (warning), which says the byte pattern suggests UTF-16LE, as a heuristic (ROBO-cvpkzckn), and `rules_after_nul_removal` (warning), which replaces `no_rules`, says the NULs hide the rule and asks for a UTF-8 file (ROBO-igrkabdb); `encoding` stays `utf-8`, byte validity only |
| `enc-utf16be-bom` — UTF-16BE with BOM | as above | must be UTF-8 | `/a` allow | `nul_byte@1..2`, `invalid_utf8@1`, `malformed_line@1`, `utf16_or_utf32_encoding`, `rules_after_nul_removal` | yes; covered by `utf16_or_utf32_encoding` (warning), which names the UTF-16BE byte-order mark (ROBO-cvpkzckn), and `nul_byte` (errors); `rules_after_nul_removal` as for `enc-utf16le-bom` |
| `enc-latin1-rule` — `Disallow: /caf` + Latin-1 `é` (`E9`) | non-UTF-8 file (§2.3); unspecified | non-UTF-8 characters may be ignored, rules may become invalid | `/caf%E9` disallow (the byte is escaped to `%E9`), `/caf%C3%A9` allow | `invalid_utf8@2` | yes: the UTF-8 URL a browser sends is not blocked; covered by `invalid_utf8` (error) |
| `enc-latin1-comment` — Latin-1 byte inside a comment only | the file is not UTF-8 (§2.3), though only a comment holds the byte: unspecified | as above | `/a` disallow, unaffected | `invalid_utf8_comment@1` (warning) | no |
| `enc-invalid-utf8-key` — `Dis\xFFallow: /a` | not UTF-8 (§2.3): unspecified; were the file read anyway, not a valid line | invalid lines ignored | `/a` allow | `invalid_utf8@2`, `unknown_directive@2`, `no_rules` | no |
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
| `esc-pct7e-rule-tilde-url` — `Disallow: /%7Ejoe` | `~` is unreserved, so `%7E` is decoded: `/~joe` disallow (§2.2.2 states the decoding for the URI; its Figure 4 maps `/foo/bar/%62%61%7A` to `/foo/bar/baz`, which reads as the rule side too) | not documented for unreserved characters | `/~joe` **allow**, `/%7Ejoe` disallow | `rule_escaped_unreserved@2` | yes; covered by `rule_escaped_unreserved` |
| `esc-tilde-rule-pct7e-url` — `Disallow: /~joe`, URL `/%7Ejoe` or `/%7ejoe` | the URI's `%7E` MUST be decoded (§2.2.2): disallow | not documented | allow for both | none | yes, but not a validator gap: the file is correct RFC syntax and nothing in it could be flagged; the difference is the URL's form. `allowed_by_robots_text()` passes the URL to the matcher unchanged and leaves supplying an appropriately `%`-escaped URL to the caller ("R does not clean, decode, canonicalize, or reserialize the URL"), and the PRD's R-package rules say "do not normalize Unicode or percent escapes on the matcher side" (`design/PRD.md`) |
| `esc-lower-hex-rule` — `Disallow: /a%3cb` | `<` is neither reserved nor unreserved, so `%3c` stays encoded on both sides (§2.2.2): `/a%3cb` matches octet for octet, disallow; `/a%3Cb` hinges on whether `%3c` equals `%3C`, which the RFC does not say: unspecified | not documented | `/a%3Cb` disallow (rule upper-cased), `/a%3cb` **allow** (URL not normalized): the exact path the owner wrote is not blocked | `rule_lowercase_escape@2` | yes; covered by `rule_lowercase_escape` |
| `esc-path-letter-case` — `Disallow: /Private` | SHOULD be case-sensitive | case-sensitive | `/Private` disallow, `/private` allow | none | no |
| `esc-space-in-rule` — `Disallow: /a b` | a space is not allowed in `path-pattern` (§2.2); unspecified | not documented | `/a%20b` allow, `/a` allow: the rule keeps a raw space no escaped URL holds | `rule_inner_whitespace@2` | yes; covered by `rule_inner_whitespace` |
| `esc-star-leading` — `Disallow: *.pdf` | not a valid `path-pattern` (must start `/`); unspecified | `*` matches any run | `/x.pdf` disallow, `/x.html` allow | `rule_star_led_pattern@2` (info: a leading `*` is accepted; Google's `*` matches any run of bytes from the path's first byte, and each `*` counts one byte of priority) | no |
| `esc-double-star` — `Disallow: /a**b` | `*` is zero or more of any character (§2.2.3) | same | `/axxb` disallow, `/a` allow | none | no |
| `esc-star-dollar` — `Disallow: /*$` | disallow every path | same | `/` and `/anything` disallow | none | no |
| `esc-dollar-then-star` — `Disallow: /a$*` | `$` mid-pattern unspecified | `$` marks the end only | `/a` allow, `/a$` and `/a$b` disallow (literal `$`) | `rule_inner_dollar@2` | yes; covered by `rule_inner_dollar` |
| `esc-lone-dollar` — `Disallow: $` | not a valid `path-pattern` | not documented | `/`, `/a` allow (never matches) | `rule_missing_leading_slash@2` | yes; covered by `rule_missing_leading_slash` |
| `esc-query-wildcard` — `Disallow: /*?` | the query is part of the matched path | same | `/p?x=1` disallow, `/p` allow | `rule_query_crawl_not_index@2` | no |
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
| `cmt-hash-in-rule` — `Disallow: /a#b` | `#` starts a comment, so the rule is `/a` | same | `/a` **and `/abc`** disallow | `rule_cut_by_comment@2` | yes; covered by `rule_cut_by_comment` (ROBO-gjhpykcj) |

The validator side of the rule-free cases is ROBO-vxrzcqpe's; these rows add
the matcher decision for the comparison work.

### Grouping

| id | RFC 9309 | Google doc | Matcher | Validator | Surprise |
|---|---|---|---|---|---|
| `grp-shared-group` — two User-agent lines, one rule | both tokens share the group | repeated user-agent lines share a group | FooBot, BarBot `/x` disallow; BazBot allow | none | no |
| `grp-user-agent-after-rule` — `User-agent` after a rule | a new group starts | same | FooBot: `/x` disallow, `/y` allow; BarBot: `/x` allow, `/y` disallow | none | no |
| `grp-blank-line-in-group` — blank line between User-agent and rule | `emptyline` allowed inside a group (§2.2) | not documented | `/x` disallow | none | no |
| `grp-blank-line-between-agents` | as above | not documented | FooBot and BarBot `/x` disallow | `user_agent_joined_across_blank@3` (info; Yandex splits the group, Y5) | no |
| `grp-same-agent-twice` — FooBot twice (second as `foobot`), BarBot between | combined (§2.2.1) | combined | `/x`, `/y` disallow, `/z` (BarBot's) allow | `user_agent_repeated_group@7` (info; ROBO-vnhirero) | no |
| `grp-rule-before-user-agent` | a rule outside a group is not valid syntax | invalid lines ignored | `/x` allow, `/y` disallow | `rule_without_user_agent@1` | no |
| `grp-token-version-in-file` — `User-agent: Googlebot/2.1` | `/` is not allowed in a token; unspecified | `googlebot/1.2` equals `googlebot` | `/x` as `Googlebot` disallow | `user_agent_cut@1` (info since ROBO-txnzyugl: a version suffix; names `Googlebot`) | no |
| `grp-token-letter-case-in-file` — `User-agent: GOOGLEBOT`, token `googlebot` | case-insensitive | case-insensitive | disallow | none | no |
| `grp-googlebot-image-fallback` — a `Googlebot` group and a `*` group, token `Googlebot-Image` | `*` applies (no group names the token) | the common-crawlers page lists `Googlebot` as Googlebot-Image's second token, so Google's crawler follows the `Googlebot` group (engine-profiles.md §5a) | `/x` allow, `/y` disallow (the `*` group): the legacy binding reads the one token only; the v1 `google` ruleset with the `google` backend gives `/x` disallow, `/y` allow (the `Googlebot` group) | `wildcard_disallows_not_inherited@1` (`wildcard_rules_not_inherited@1` before ROBO-pbwijkdq) | yes; **known gap** on the legacy path; closed on v1 `google`/`google` by ROBO-fbbmvbob |
| `grp-user-agent-with-space` — `User-agent: Foo Bot` | not a valid token; unspecified | not documented | as `Foo` disallow, as `FooBot` allow: the value is cut at the space | `user_agent_cut@1` (info since ROBO-txnzyugl; names `Foo`) | yes; covered by `user_agent_cut` |
| `grp-digit-in-token` — `User-agent: Bot2` | digits are not allowed in a token (§2.2.1); unspecified | not documented | as `Bot2` allow, as `Bot` disallow: the value is cut at the digit | `user_agent_cut@1` (info since ROBO-txnzyugl; names `Bot`) | yes; covered by `user_agent_cut` |
| `grp-star-prefixed-token` — `User-agent: *bot` | not a valid token; unspecified | not documented | allow: `*bot` is neither global nor a token | `user_agent_cut@1` (info since ROBO-txnzyugl; names no crawler) | yes; covered by `user_agent_cut` |
| `grp-sitemap-mid-group` — Sitemap between two rules | MUST NOT terminate a group (§2.2.4) | "Rules other than allow, disallow, and user-agent are ignored by the robots.txt parser" ("Order of precedence for user agents"; its example has a sitemap line inside a group of two user-agent lines); a sitemap line between rules is not shown | `/x`, `/y` disallow | none | no |
| `grp-unknown-between-agents` — `Crawl-delay` between two User-agent lines | other records; unspecified for the first agent | unsupported fields ignored | FooBot and BarBot `/x` disallow: the unknown line does not split them | `unsupported_directive@2`, `user_agent_joined_across_directive@3` (warning; Bing and Yandex end the group at line 2) | no |

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
| `content-spam-html` — a casino/popunder page with scripts, links and an iframe served as robots.txt | no valid records: no rules | an HTML download is parsed for rules and everything else ignored | `/`, `/private/` allow | `accepted_missing_colon`, `unknown_directive` and `malformed_line` rows, `html_body` (the body looks like HTML, from the ROBO-nhuirvrd content flag), `no_rules`; `validation_status = "error"` | yes; covered by `html_body` |
| `content-html-script-first` — a one-line page opening with inline `<script>` and `<style>`, its doctype and `<html>` mid-line | no valid records: no rules | an HTML download is parsed for rules and everything else ignored | `/`, `/private/` allow | `unknown_directive`, `html_body` (the content flag is `"html"`: a body opening with `<` that holds a script, style or document marker anywhere), `no_rules` | yes; covered by `html_body` |
| `redirect-cross-host-html` — `http://a.example/robots.txt` answers 301 to `https://b.example/landing`, an HTML page | redirects followed, reached rules applied to the first authority (§2.3.1.2) | redirects followed | the fetch follows (`redirect_count = 1`, `effective_url` the landing page, `content_type = "text/html"`, `content_flag = "html"`, v1 `usable_body` / `http_200_use_rules`), and every URL is allowed | the landing page's lines (`malformed_line`, `accepted_missing_colon`, `unknown_directive`, `html_body`, `no_rules`); `robots_validate_url()` adds a `redirect_cross_site` warning (another registrable domain; the robots.txt is effectively missing, the page being HTML), then a `content_type_not_text_plain` warning for the `text/html` header (ROBO-plkpmoll) | yes; covered by `redirect_cross_site` (from the fetch) |

The redirect case runs through the ssrfr fake (`helper-fake-ssrfr.R`); its
fetch-layer values are pinned in the test file, not in the manifest.

Two bodies that are not robots.txt are catalogued here in prose, with no
fixture (ROBO-mgtngbpm). A JSON API error body such as
`{"error": "not found"}` draws `json_body` beside its `unknown_directive` and
`no_rules` rows. An S3-style XML error body, an `<?xml ...?>` declaration and
then `<Error><Code>AccessDenied</Code>...`, draws `xml_body` beside its
`malformed_line` rows. In both, the parser reads the lines as it reads any
body, and the advisory names only the kind: the sniffer cannot tell why a
server answered, so it never says access was denied.

`content-gzip-body`, a compressed body, is catalogued in prose too, with no
fixture: its fixtures are built in its test file (ROBO-rozvglkd). A gzip,
zlib or zstd stream of a robots.txt, as saved by a client that did not decode
it or stored by a fetch whose server compressed a body it was not asked to,
used to be read as lines: `nul_byte`, `invalid_utf8` and `malformed_line`
rows, and `no_rules` saying the file restricts nothing. It now draws one
`compressed_body` error and no line, group or rule row; the matcher still
reads the bytes as they are. A zlib header is told from `x^` text by its
FLG byte and the 16 bytes after it (well-formed UTF-8 reads as text), or by a
stored first block whose NLEN complements its LEN.

### Other

| id | RFC 9309 | Google doc | Matcher | Validator | Surprise |
|---|---|---|---|---|---|
| `oth-space-before-colon` — `Disallow : /a` | `rule = *WS ("allow" / "disallow") *WS ":"` allows it (§2.2): disallow | spaces optional | disallow | none | no |
| `oth-indented-lines` — leading spaces and a tab | `*WS` before the key | leading whitespace ignored | disallow | none | no |
| `oth-directive-letter-case` — `USER-AGENT`, `DISALLOW` | keys are case-insensitive ABNF strings | field names case-insensitive | disallow | none | no |

## Known gaps found

Filed 2026-11-09 unless marked. Each open gap is pinned in the test file with
a `# known gap (ROBO-xxxxxxxx):` comment naming its issue, so a fix turns its
block red. An item marked fixed names the diagnostic that now covers it.

1. ROBO-atkmqcov — `enc-bom-mid-file`, `enc-bom-before-user-agent`: a BOM after the start is
   only an `unknown_directive`; a lost User-agent group is not called out. Fixed:
   `misplaced_byte_order_mark` names the BOM and the directive it hides.
2. ROBO-igrkabdb — `enc-utf16le-no-bom`: `no_rules` said the file restricts nothing while the
   NUL-dropping matcher enforced its rules. Fixed: `rules_after_nul_removal` (warning) counts
   the rules the NULs hide. Since ROBO-pvqrfvol the Google matcher ends each line at its first
   NUL, as upstream does, so it no longer enforces them, and the warning asks for a UTF-8 file.
3. ROBO-sniltuap — `enc-latin1-comment`: `invalid_utf8` had no line and was an error even when
   only a comment held the byte. Fixed: each line is reported, and bytes only after the first
   `#` give the `invalid_utf8_comment` warning.
4. ROBO-gaczsrgj — `esc-pct7e-rule-tilde-url`: no diagnostic for an escaped unreserved
   character, which Google never matches against the raw form. Fixed:
   `rule_escaped_unreserved`.
5. ROBO-dlgeqluf — `esc-space-in-rule`: no diagnostic for a raw space inside a rule. Fixed:
   `rule_inner_whitespace`.
6. Fixed: ROBO-gjhpykcj — `cmt-hash-in-rule`: a `#` that cuts a rule into a wider prefix
   went unflagged; `rule_cut_by_comment` now reports it.
7. ROBO-zvhrayhx — `grp-user-agent-with-space`, `grp-digit-in-token`,
   `grp-star-prefixed-token`: a User-agent value the matcher cuts or never
   matches is not flagged. Fixed: `user_agent_cut` names the token
   the matcher reads, or says the value names no crawler. Since ROBO-txnzyugl
   it states the effect and is a warning only when a Google crawler reads
   a cut token the value did not mean (`Googlebot Image`), info otherwise.
8. ROBO-ccfsanhq — `content-spam-html`: no validator diagnostic names an HTML body.
   Fixed by ROBO-ccfsanhq: the `html_body` warning.
9. ROBO-fbbmvbob — `grp-googlebot-image-fallback`: the legacy binding
   ignores Googlebot-Image's documented parent token `Googlebot`. Still a
   gap on the legacy path; closed on the v1 `google` ruleset with the
   `google` backend, whose crawler-token layer falls back to the parent's
   group.
10. ROBO-kormmfyg — `esc-lower-hex-rule`: the matcher upper-cases a rule's
    lower-case escape but not the URL's, so `Disallow: /a%3cb` allows the
    exact path `/a%3cb`; no diagnostic. Fixed: `rule_lowercase_escape`.
11. ROBO-gokbvzcb (filed earlier) — `redirect-cross-host-html`: no validator
    diagnostic for a successful cross-host redirect, here to an HTML page.
    Fixed by ROBO-gokbvzcb: the `redirect_cross_site` warning, beside
    `redirect_same_site` and `redirect_other_path`.
12. ROBO-qquftxcx (filed 2026-11-10) — `content-html-script-first`: `html_body`
    needs an HTML marker at a line start, so a minified page opening with
    inline script or style is flagged `"xml"`; and a one-line page cut at
    `max_bytes` leaves nothing readable to sniff. Neither draws `html_body`.
    Fixed by ROBO-qquftxcx: a body opening with `<` is `"html"` when a
    doctype, `<html`, `<head`, `<body`, `<script` or `<style` appears
    anywhere in the window, and `html_body` sniffs the stored bytes, before
    the cut.
