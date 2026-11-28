# Engine-aware robots evaluation contract v1

- Contract ID: `robotstxtr.engine-aware/v1`
- Schema revision: `2026-11-28.1`
- First package release: `robotstxtr 0.2.0`
- Normative policy source: [`engine-profiles.md`](engine-profiles.md)

This is the released integration contract for sitemapr and sitemap-validator.
It turns the accepted engine-profile design into an additive API without
changing the four legacy functions or their result schemas.

## Entry points

`robots_evaluate_text_v1()` evaluates a caller-supplied body.
`robots_evaluate_url_v1()` acquires `/robots.txt` and evaluates it. Both require
an explicit `robots_policy_ruleset` and an explicit `matcher_backend`; neither
axis defaults to Google or to the other axis, except that a `preset` fixes both
to `google` (see "Agent presets"). `robots_product_token` controls robots group
selection. `fetch_user_agent` controls only the HTTP request and is recorded
separately.

`robots_engine_contract_v1()` publishes the contract/schema revisions, policy
and matcher revisions, capability states, complete status-policy table, and
sibling compatibility ranges as data.

The return class is `robots_engine_decisions_v1`, a list with:

- `results`: one row per requested URL, in input order;
- `evidence`: one row per acquired or supplied robots source, with list columns
  for the reopened address ranges, ordered redirect hops and exact stored body
  bytes;
- `contract`: the value returned by `robots_engine_contract_v1()`.

Each result expands and persists the ruleset, ruleset revision, matcher backend,
matcher revision, robots product token, HTTP User-Agent, acquisition byte/time
limits, redirect limit, SSRF and HTTPS-downgrade guards, and engine body limit.
It then reports `evidence_status`, `policy_status`, `policy_action`, policy
reason/provenance/source, `matcher_availability`, `matcher_status`, the optional
`url_decision`, and a final reason. A missing `url_decision` is intentional and
must not be coerced to allow or deny.

## Safety level

Schema revision `2026-11-08.1` (ADR 0001, ROBO-pezlychx) adds `safety_level` to
`robots_evaluate_url_v1()` and to the three legacy functions that fetch
(`robots_fetch()`, `allowed_by_robots_url()`, `robots_validate_url()`). It
decides what the fetch may do on the network and is independent of
`robots_policy_ruleset`; neither defaults from the other. The contract
publishes the value set as `safety_levels`: `strict`, the default, and
`crawler`. `strict` is the acquisition of every earlier revision, unchanged.
`crawler` follows an `https` to `http` redirect as an ordinary hop within the
five-redirect budget (ROBO-lwdxzdhw). Every address the guard refuses is still
refused, never dialed, and keeps `fetch_outcome = ssrf_blocked` and its code in
`safety_block_reason` at both levels; under `crawler` an address-class refusal
is recorded as `evidence_status = unreachable_local` (schema revision
`2026-11-11.1`, ROBO-jqwukcog), while a URL-shape refusal stays
`safety_refused`. So does a `6to4`, `teredo` or `isatap` refusal
(ROBO-aoslfvnx): ssrfr refuses 6to4 and Teredo whatever IPv4 they wrap,
because their reachability is unknown, and ISATAP around a private IPv4 even
under a global prefix that a site's ISATAP router routes publicly, so the code
says nothing about whether the target is internal, and robotstxtr does not
unwrap the IPv4 to find out. The change moves those rows between two existing
statuses and touches no enum, column or policy-table cell, so neither the
schema revision nor a policy revision moves. Any other `safety_level` value is a
call-level error of class `robotstxtr_invalid_safety_level`. The levels and
the classes of refusal are defined in [`engine-profiles.md`](engine-profiles.md)
§3a.

The evidence frame gains two columns. `safety_level` (character) is the level a
source was fetched under. `fetch_allow_ranges` (a list column) holds the CIDR
ranges the caller passed in that argument, as passed (`character()` by
default; ROBO-bamcjvwn); a deprecated `ssrf_guard = FALSE`, which reopens every range,
is recorded in `ssrf_guard`, not here. Both are `NA` on a row with no
acquisition, a supplied body: there the list cell is `NA_character_`, length
one, so tell a supplied row by `source_kind`, not by `lengths()`. `https_downgrade_guard` is
`safety_level == "strict"` on a fetched row: `TRUE` under `strict`, as before,
`FALSE` under `crawler`, and `NA` where no acquisition was configured. The result columns and the legacy
frames are unchanged.

## Stable outcome sets

Evidence status is one of `usable_body`, `partial`, `incomplete`, `http_status`,
`http_protocol_error`, `redirect_over_budget`, `transport_fail`,
`unreachable_local`, `safety_refused`, or `not_applicable`.

A set `safety_block_reason` means `safety_refused` or `unreachable_local`, and
`unreachable_local` occurs under `safety_level = "crawler"` only: "not dialed:
the address is internal, so a public crawler could not reach it either"
(ADR 0001 §3). `transport_fail` never carries a `safety_block_reason`; a
consumer that wants "the crawler could not reach it" combines the two. Schema
revision `2026-11-11.1` (ROBO-jqwukcog) adds `unreachable_local` and an
`unreachable_local` row per ruleset to the status-policy table, with the cells
of that ruleset's `transport` row: `context_required` for `google`, `rfc9309`
and `assumed_rfc9309`, `documentation_gap` for `yandex` and `bing`, so no
ruleset reads it as allow or deny. The readings of existing evidence are
unchanged, so no policy revision moved. Under `strict` every row reads as
under `2026-11-08.1`.

Policy status is one of `evaluated`, `not_evaluated`, `context_required`, or
`documentation_gap`. An evaluated action is `use_rules` or `allow_all`.

Matcher status is one of `evaluated`, `not_needed`, `not_evaluated`, or
`capability_unavailable`. URL decision is `allow`, `disallow`, or absent (`NA`).

The absence cases are part of the contract. In particular, a safety refusal,
incomplete acquisition, lifecycle-dependent status, undocumented engine
policy, partial response, or unavailable matcher never fabricates a URL
decision. The one reading of incomplete acquisition is a ruleset's documented
meaning of a 2xx cut at `max_bytes` (`engine-profiles.md` §7): under `yandex`,
a cut that stored at least 512,000 bytes is a file over Yandex's 500 KB limit,
which is `allow_all` (ROBO-arrtietl); under `google` with the `google`
matcher backend, a cut that stored at least 512,000 bytes holds the whole
window Google parses, so it is matched on the complete lines inside that
window (ROBO-ptibdnvy).

## Backend and policy revisions

Google matching uses the vendored matcher pinned to upstream commit
`22b355ff855419e6a3ff8ff09c0ad7fdb17116f9`. The backend revision embeds that
SHA. The Google 500 KiB limit is applied at the matcher stage: the neutral
evidence retains a complete caller-supplied or within-acquisition-limit body,
and Google parses only its first 512,000 bytes, up to the last complete line
within them: a line the window cuts is dropped, as for a body cut at
`max_bytes` (ROBO-ldpahknv below), and a window with no line break feeds no
rules. `matcher_input_bytes` is the bytes fed to the matcher, after that drop;
`matcher_body_truncated` is `TRUE` whenever the body exceeded the window. A fetched 2xx body over the
acquisition limit is retained as its first `max_bytes` bytes, marked
`body_truncated` and `incomplete`, and not matched by the v1 engines, with
two exceptions for a cut of at least 512,000 bytes: under `yandex` it resolves
`allow_all` with no matcher (ROBO-arrtietl), and under `google` with the
`google` backend it is matched
on the complete lines of its first 512,000 bytes, with
`matcher_body_truncated` `TRUE` (ROBO-ptibdnvy). The legacy path matches every
cut, up to its last complete line (see "A robots.txt over `max_bytes`"
below).

The Yandex matcher backend is `available` (as of schema revision
`2026-07-18.2`). It is bounded to its supported Yandex vendor profiles
(profile `yandex-0.1.0`) and never generalizes to arbitrary tokens or falls
back to Google. Its backend revision is the composed, byte-frozen
`robotstxtyandex/0.2.0+payload.<commit>;profile=yandex-0.1.0;corpus=<rev>;evidence=<sha>;profile-source=<rev>`
string, byte-equal to `inst/vendor/robotstxtyandex/MANIFEST.dcf`'s
`MatcherRevision`. The separately inspectable library/payload/profile/corpus/
evidence/profile-source fields are published as
`robots_engine_contract_v1()$matcher_identity$yandex`.

The activation schema adds one public list column, `matched_rule_value_raw`,
with exactly one element per result row: exact owning-rule bytes for a matched
rule, `raw(0)` for an effective-empty Disallow, and `NULL` for an absent rule
(evaluated `default_allow` and every non-evaluated outcome). `raw(0)` and
`NULL` are semantically distinct and remain distinct through construction,
subsetting, and serialization. The column is populated for Yandex-evaluated
rows; Google and other rows keep `NULL`. The legacy adapter frame does not
carry this column.

For an evaluated Yandex row the published `reason` is exactly one of
`default_allow`, `rule_allow`, `rule_disallow`, or `effective_empty_disallow`
(the effective-empty case yields `url_decision = "allow"` with
`matched_rule_type = "disallow"` and an empty value). For a non-evaluated
Yandex row the matcher status is `not_evaluated` with either
`reason = "unsupported_product_token"`
(`error_class = "robots_unsupported_product_token"`) or
`reason = "invalid_request_target"`
(`error_class = "robots_invalid_request_target"`), both at
`error_stage = "input"`; `unsupported_crawler` takes precedence when both a
target and a token are invalid. A fetched body over 500,000 bytes resolves
through the documented Yandex `allow_all` policy before the matcher runs
(`matcher_status = "not_needed"`); a supplied or local body stays `use_rules`
(`supplied_body_use_rules`) at any size. A 2xx cut at `max_bytes` that stored at
least 512,000 bytes
is a file over 500 KB under either reading of the unit, so it resolves
`allow_all` too, while its `evidence_status` stays `incomplete`
(ROBO-arrtietl): a cut 200 with the same `yandex_file_over_500000_bytes`
reason, a cut non-200 2xx with `non_200_allow_all` from the policy table, as
its uncut form does. A smaller cut stays `incomplete_evidence`.

A Google row reports no line for a rule with an empty value. When the rule that
Google's matcher selects is an `Allow:` or `Disallow:` with nothing after the
colon (also `Disallow: # comment`), the row reports `url_decision = "allow"`,
`reason = "default_allow"`, `matched_rule_type = "none"`, `matched_line` and
`matched_rule_value` `NA`, and `matched_rule_value_raw` `NULL`, although the
native engine records that line as the match. This follows the PRD's "Match
metadata rules" (§6.6: an empty-path directive is ignored and surfaces as
`default_allow`); the Google adapter and its reference row matcher
`match_google_v1()` apply it to v1 Google rows, and the
legacy functions and `as_legacy_robots_decisions_v1()` report the same
`decision_source`, type, line and value. The decision equals Google's. Yandex
differs: when the selected rule is an empty `Disallow`, the row reports
`effective_empty_disallow` with that rule's line.

### Google crawler tokens (ROBO-fbbmvbob)

Under the `google` ruleset with the `google` backend, and nowhere else, the
Google row is a crawler-aware layer above the matcher. It reads Google's
crawler documentation (`engine-profiles.md` §5a, §10) as data, published as
`robots_engine_contract_v1()$matcher_capability$google$crawler_tokens`, one
row per crawler token with `crawler_token`, `parent_token`,
`group_selection`, `token_comparison` and `source`:

| `crawler_token` | `parent_token` | `group_selection` |
|---|---|---|
| `Googlebot-Image`, `Googlebot-Video`, `Googlebot-News`, `Google-InspectionTool`, `Google-CloudVertexBot` | `Googlebot` | `exact_else_parent_else_wildcard` |
| `GoogleOther-Image`, `GoogleOther-Video` | `GoogleOther` | `exact_else_parent_else_wildcard` |
| `AdsBot-Google`, `AdsBot-Google-Mobile`, `Mediapartners-Google`, `APIs-Google` | none | `exact_only` |

The caller's token is compared with `crawler_token` whole and ASCII
case-insensitively (`token_comparison = ascii_case_insensitive_exact`): no
trimming, no prefix or suffix, so `Googlebot-Image/1.0` and
`Googlebot-Imagex` are not listed. A token that is not listed selects its
group as the plain matcher does: the groups naming it, else `*`. The retired
Google Favicon and AdsBot-Google-Mobile-Apps rows are left out.

- `exact_else_parent_else_wildcard`: the groups naming the token; only if
  none does, the groups naming `parent_token`; only if none names that
  either, `*`. The groups of the two tokens are never merged, and "none
  names it" is the vendored matcher's `ever_seen_specific_agent()`, read in
  the binding, not inferred from a decision: a group naming the token with
  no rule that matches still keeps the parent out.
- `exact_only`: the groups naming the token, through the vendored
  `RobotsMatcher::disallow_ignore_global()`; `*` never decides. With no
  group of its own the row is `allow`, `default_allow`, with no line: the
  matcher's `matching_line()` would report the `*` line there, and the row
  does not.

The window and the NUL line end come first: the layer reads the body the
matcher reads (the first 512,000 bytes, each line cut at its first NUL), so
a parent group after the window is not seen.

The `results` frame gains `group_token` (character), between
`error_message` and `matched_rule_value_raw`: whose group decided a Google
row. It is the caller's token as given when a group names it, the parent
token as `crawler_tokens` spells it when the parent's group decided, `"*"`
when no specific group was seen (the `*` rules, if any), and `NA` for an
`exact_only` crawler with no group of its own, for every row of another
backend and for every row no matcher decided. A Google row under another
ruleset carries its own token or `"*"`, since no parent is consulted there.
Under an agent preset ("Agent presets" below) the token is the preset's
`matcher_token` as the preset table spells it, not the caller's: `"OAI-SearchBot"`
under `chatgpt_user`, and `"Claude-User"` under `claude_user` even for a
caller's `"claude-user"`.
The column is not one of the decision-frame columns
(`matcher_decision_columns_v1()`): the Google adapter adds it, and the
evaluator fills `NA` where an adapter does not. Schema revision
`2026-11-12.1` (both facades) adds the column and the `crawler_tokens`
field; the google policy revision moves to `google-robots-policy-2026-11-12`.

This makes `google` more than Google's matching for a token: for the listed
tokens it answers as Google documents those crawlers to select groups. It
is read from Google's documentation, not observed from the crawlers. The
legacy functions apply none of it (below).

### The URL the matcher reads (ROBO-bnvdmdjr)

Both facades take `url_normalization`, one value of `"rfc3986"` (the
default), `"whatwg"` (since `2026-11-21.2`) or `"none"`, validated like
`safety_level` ([ADR 0002](adr/0002-evaluator-url-preprocessing.md)). The
contract publishes the value set as `url_normalizations`, default first.
`evaluate_rows_v1()`
builds one matcher URL per row from it, above every backend's request-target
extractor, which stays byte-transparent; `url` keeps the input.

- `"rfc3986"`: the URL is split the RFC 3986 way (Appendix B; the authority
  ends at the first `/`, `?` or `#`) and rebuilt as the scheme, `//`, the
  host and port (userinfo left out), the path after RFC 3986 §5.2.4
  `remove_dot_segments`, and `?query`; the fragment is dropped. Only the
  literal segments `.` and `..` are dots: no byte is percent-encoded,
  decoded or case-folded, so `%2e`, `%2E`, `%252e` and `%2F` are kept, as
  are `//` and the query. A URL with no authority (the text entry point
  accepts `/a/../b` and `example.com/a/../b`) keeps the bytes before its
  first `/` and has the dot segments removed from there on, unless the
  result would start the path with `//` (`/a/..//h/x` would read as the host
  `h`): then the URL is evaluated as given. Input that is not a valid RFC
  3986 URI is still evaluated, its bytes unchanged apart from the dot
  segments.
- `"whatwg"`: the URL as `rurl::serialize_url(url, standard = "whatwg")`
  writes it, rebuilt the same way (scheme, `//`, host and port, path,
  `?query`; userinfo left out, fragment dropped). Literal and encoded
  (`%2e`, `%2E`) dot segments are removed; `%252e`, `%2F`, `//` and the
  query's dots are kept. Unlike `"rfc3986"` it changes the encoding and the
  host as the WHATWG URL Standard does. The URL's bytes are read as UTF-8
  whatever the locale (a `"latin1"`-marked URL is converted from latin1).
  A URL with no scheme is split exactly as under `"rfc3986"`: only its
  path, when that starts with `/`, is serialized (`http://h.invalid` plus
  the path and query, never resolved), and the serialized path and query
  follow the same lead, an authority or the bytes before the first `/`.
  Any other scheme-less URL is read as under `"rfc3986"`, and one whose
  serialized path would start with `//` after a lead with no authority is
  evaluated as given. A URL it cannot parse is evaluated as given.
- `"none"`: the matcher reads the URL as given, byte for byte, as before
  this revision.

The `results` frame gains two columns between `group_token` and
`matched_rule_value_raw`, both on every row:

- `matcher_url` (character): the URL handed to the matcher backend (under
  `"none"`, `url`); `NA` for an `NA` URL. A row no matcher decides still
  carries the URL it would have read.
- `url_preprocessing_note` (character): always `NA` under `"none"`. Under
  `"rfc3986"`, `NA` when the input is a valid RFC 3986 URI with an
  authority and the preprocessing changed nothing; otherwise the parts
  below that apply, in this order, joined by `"; "`: `not a valid RFC 3986
  URI: ` and the classes found (`raw space`, `raw non-ASCII`, `backslash`,
  `character outside RFC 3986` for `` "<>^`{|} `` and controls, `stray %`
  for a `%` without two hex digits); `no authority: path read from the
  first /`, or `no authority and no /: evaluated as given`; `RFC 3986
  §5.2.4 removed dot segments` (or `dot segments removed as given` on
  invalid input), or `dot segments left in place: removing them would start
  the path with // (RFC 3986 §5.2.4)`; `userinfo removed (RFC 3986
  §3.2.1)`; `fragment dropped (RFC 3986 §3.5)`. A URL whose dot segments
  were left in place is evaluated as given, fragment included. Under
  `"whatwg"`, `NA` when the rebuilt URL is the input byte for byte;
  otherwise `not a valid WHATWG URL: evaluated as given`, or the parts that
  apply of `no authority: path read from the first /`, `WHATWG URL
  serialization changed the URL` (or, when the serialized path would start
  with `//`, `WHATWG serialization left in place: it would start the path
  with //`), `userinfo removed` and `fragment dropped`, joined by `"; "`. A
  scheme-less URL whose path does not start with `/` has the `"rfc3986"`
  note.

Schema revision `2026-11-21.2` adds two more columns after
`url_preprocessing_note`, on every row and in every mode. Under `"none"`
they are never computed: a decided row has the flag `NA` and the clients
note `not compared under url_normalization = "none"`, and no `rurl` call
or second pass runs. The rest describes `"rfc3986"` and `"whatwg"`:

- `preprocessing_disagreement` (logical): on a row the matcher decided
  (`url_decision` not `NA`), `TRUE` when `"whatwg"` cannot parse the URL,
  or when the `"rfc3986"` and `"whatwg"` matcher URLs differ and the
  matcher decides them differently; `FALSE` otherwise. Any other row (an
  `NA` or empty URL, an empty token, `capability_unavailable`, a policy
  decision, a refused token or target) is always `FALSE`, and its
  `"whatwg"` form is not computed under the other modes. A second matcher
  pass reads the other URL only on rows whose two URLs differ in more than
  the scheme or host case, a default port, an empty path against `/`, or
  the fragment. That second pass is the one exception to each batch
  adapter being invoked once per evaluation: a second batch call with only
  those rows. Under `"rfc3986"`, `NA` for a decided row
  whose URL is longer than 2048 bytes, which is not compared
  (`disagreement_clients`: `not compared: URL longer than 2048 bytes`);
  `"whatwg"` compares any length.
- `disagreement_clients` (character): `NA` when the flag is `FALSE`;
  otherwise each side's decision. When the two forms differ only through
  encoded dot segments (whole `%2e`, `.%2e`, `%2e.` or `%2e%2e` segments,
  either case), it names the client families for dot segments only:
  `rfc3986 <decision> (dot segments as in: wget 1.25, curl/libcurl <
  8.13.0); whatwg <decision> (dot segments as in: Chrome 157, Node 26
  fetch, curl/libcurl >= 8.13.0)`. Otherwise it says `the forms differ in
  more than dot segments; no client survey covers this`, or, when
  `"whatwg"` cannot parse the URL, `rfc3986 <decision>; whatwg cannot parse
  the URL; no client survey covers this`. The families are the ADR's
  client survey, with the curl boundary at 8.13.0.

Under `"rfc3986"` the google, bing and yandex backends read the same
rebuilt URL: `/latam/../account/x` is matched as `/account/x`,
`/latam/%2e%2e/account/x` as given, and `https://u;v@example.com/x` as
`https://example.com/x`, which Google no longer reads from its `;`
(`GetPathParamsQuery()`). The rfc9309 backend is `capability_unavailable`
whatever the mode. `robots_evaluate_url_v1()` fetches `/robots.txt` from the
input URL's origin in every mode. Schema revision `2026-11-21.1` (both
facades) adds the argument and the first two columns, and `2026-11-21.2`
the `"whatwg"` mode, `url_normalizations` and the flag columns; no policy
revision moves.

### Agent presets (ROBO-uyfryhlz)

Both facades take `preset = NULL | "chatgpt_user" | "claude_user"`. `NULL`,
the default, changes nothing. A preset reads a file as one measured AI user
agent does, on the API surface agent-view's complete probe matrix ran on
(2026-11-26): `chatgpt_user` is ChatGPT-User behind the OpenAI Responses API
`web_search` tool, and `claude_user` is Claude-User behind the Claude API
`web_fetch` tool (`web_fetch_20260309`). The behaviors rest on probes of
2026-11-12 to 2026-11-26, each dated in the published `measured` column
(the ChatGPT group binding 2026-11-13 to 16, the Claude size refusal
2026-11-12, the URL steps and the matcher 2026-11-26). Neither preset covers
ChatGPT Chat or claude.ai: both have earlier observations (the ChatGPT
binding counts include Chat-mode asks on chatgpt.com, and the Claude size
refusal was also seen on claude.ai) but no complete probe matrix
(`access-and-blocklists/robots-parser-ports.md`, "Surface and acquisition
gaps"). `claude_user` is not the ClaudeBot crawler:
agent-view-research's `access-and-blocklists/robots-parser-ports.md` keeps
ClaudeBot as a separate, passive watch with no matched port matrix. No
preset is named for ClaudeBot, GPTBot or OAI-SearchBot as crawlers.

A preset fixes the `google` ruleset and backend, the token the matcher
selects a group with, the group selection and the URL steps. A caller may
leave `robots_product_token`, `robots_policy_ruleset` and `matcher_backend`
out; one given must agree (`"google"`, and the preset's robots token
compared ASCII case-insensitively), and `url_normalization` must be left out.
Anything else aborts with `robotstxtr_preset_conflict`; an unknown id with
`robotstxtr_invalid_preset`. The `robots_product_token` column keeps the
caller's token, or the preset's when it was left out; `group_token` is the
matcher token as the table spells it, `"*"`, or `NA`.

The group selection uses the contract's profile selection modes (the
`exact_else_wildcard` / `exact_only` table under "Accepted matcher-profile
selectors"), not
the Google crawler modes: a preset has no parent token.

| Preset | Robots token | Matcher token | Group selection | URL steps |
| --- | --- | --- | --- | --- |
| `chatgpt_user` | `ChatGPT-User` | `OAI-SearchBot` | `exact_only` | uppercase `%HH` |
| `claude_user` | `Claude-User` | `Claude-User` | own group, else `*` | uppercase `%HH`, strip a trailing `/`, query `/` to `%2F` |

- **ChatGPT-User's group.** It obeys a group naming `OAI-SearchBot` (35/35,
  also a group naming both), never a `User-agent: ChatGPT-User` group
  (26/26), `*` (31/31) or a GPTBot group (5/5) (AGEN-anxylhbt). The preset
  matches with `OAI-SearchBot` and `*` ignored, so a file with no
  `OAI-SearchBot` group gives `default_allow` with `group_token` `NA`. The
  agents are not added to the Google crawler-token table, which is read
  from Google's documentation, and ChatGPT-User's own group never binds,
  which no parent fallback expresses.
- **The URL steps** are byte operations on the URL as given (the
  `"none"` reading), never through rurl, whose normalized form also decodes
  `%2E` (ADR 0002 section 8). Uppercasing changes only the hex digits of a
  `%` followed by two hex digits: `%3cb` becomes `%3Cb`, `%2f` becomes
  `%2F` (never `/` or `%252F`), and `%zz`, `%3` and a trailing `%` are kept.
  Claude-User's strip removes one trailing `/` from a path other than `/`
  when the URL has no query and no fragment, and its query step encodes
  each `/` between the first `?` and any `#` as `%2F`. So
  `Allow: /dir/index.html` with `Disallow: /` allows `/dir/` for
  ChatGPT-User (Google's index.html shortcut) and disallows it for
  Claude-User, which reads `/dir`. ChatGPT-User keeps a `/` in the query:
  `/c13?q=/` was sent raw on the wire and allowed under
  `Allow: /c13?q=/index.html` (observed, one case, AGEN-nweunrii in
  `converters/openai.md`).
- **Unmeasured inputs are read as given.** A raw space or byte outside
  ASCII (AGEN-hdmtqpwx), a tab or other control byte, a backslash, a
  character RFC 3986 excludes (`"`, `<`, `>`, `^`, the backquote, `{`, `|`,
  `}`), a `%` without two hex digits, a `.` or `..` segment and a
  percent-encoded one (`%2e`, `.%2e`, `%2E%2E` as a whole segment;
  AGEN-hsvkltop), a `//` run, userinfo, Claude-User's trailing `/` before a
  query or fragment, and ChatGPT-User's trailing `/` (measured only against
  an index.html Allow) are left as they are. `url_preprocessing_note` names
  the steps that changed the URL, then
  `left as given, unmeasured for <preset>: ...` with each unmeasured input
  the URL holds; the inputs are joined by `", "` and those parts by `"; "`
  (`percent-escape hex digits uppercased; trailing / removed; left as given,
  unmeasured for claude_user: raw space, backslash`). NA and empty URLs pass
  with no note. Each class has an `unmeasured` row in `behaviors`.
- **No disagreement flag.** A decided preset row is
  `preprocessing_disagreement = NA` with `disagreement_clients`
  `not compared under an agent preset`, as under `"none"`.
- **Status policy.** A supplied body reads as `supplied_body_use_rules`. A
  fetched 2xx body (`status_200`, `status_other_2xx`) reads Google's
  `use_rules` cell. Every other google cell (206, 4xx, 429, 5xx,
  transport, `unreachable_local`, a redirect over the budget, a protocol
  error) is `documentation_gap` (`policy_action` `NA`, provenance
  `documentation_gap`) with source `design/engine-profiles.md#agent-presets`
  (section 5i), since no probe measured how the agents read them.
  `as_legacy_robots_decisions_v1()` keeps such a row undecided
  (`allowed = NA`, `decision_source = "policy_documentation_gap"`), so a
  preset 404 or 410 never becomes Google's `missing_allow`. The fetch is
  this call's, with `fetch_user_agent`:
  ChatGPT-User's verdict follows `OAI-SearchBot`'s stored copy, and nothing
  is checked before its first read (observed, 2026-11-15 to 16). The Claude
  API reused one robots.txt read for the next few minutes, and a refused
  host got no request for at least 8 minutes and was read again by 65
  (observed, 2026-11-12); the API and claude.ai seem to share that cached
  refusal (inferred; `access-and-blocklists/claude-blocklist.md`). No preset
  models a stored copy.
- **Body size.** Both presets read Google's 512,000-byte window, labeled as
  Google's. ChatGPT's cap is unmeasured. The Claude API refuses the whole
  host when its robots.txt is over 500,000 bytes, an allow-all file too
  (500,000 bytes fetched, 500,001 refused; AGEN-yrhoneml in
  `access-and-blocklists/claude-blocklist.md`). The preset does not model
  that refusal yet: it would add a policy action outside the stable outcome
  set, which is the owner's decision. Untested there: an HTML robots.txt at
  the line, and whether the count is taken before or after content decoding.
- **The matcher.** Both agents match Google's `robots.cc` fingerprints,
  index.htm shortcut included: 68/68 for ChatGPT-User and 74/74 for
  Claude-User on the normalized URL, 67/68 and 64/74 raw
  (`access-and-blocklists/robots-parser-ports.md`). That is
  Google-compatible lineage, not proof of the implementation.

`robots_engine_contract_v1()$agent_presets` (and the v2 accessor's) publishes
`presets`, the table above with the window and the API surface of the
complete matrix; `behaviors`, one row per preset behavior with `modeled`,
`evidence_tier`, `source`, `measured` (the date or range the cited record
gives, `NA` where the row cites none) and `note`; and `evidence_tiers`.
The tiers follow the owner's rule
on ROBO-kgqlcpjn that each behavior is labeled with the evidence it rests on:
`observed` (the request bytes in edge logs, or the agent's verdicts across a
probe matrix), `inferred` (deduced from verdicts; ChatGPT-User's uppercasing
rests on one verdict, `r103-esc1-lo`, the one raw miss of 37/38) and
`unmeasured` (never modeled). A `source` is a path in agent-view-research
(`converters/openai.md`, `access-and-blocklists/claude-blocklist.md`,
`access-and-blocklists/robots-parser-ports.md`), the agent-view probe that
has not run, or `none` where no agent-view record measures the behavior
(a `//` run, userinfo, the status cells, the control, backslash, excluded
and stray-`%` classes, ChatGPT's size cap). Schema revision `2026-11-28.1` (both facades) adds the argument
and the publication; no policy revision moves.

RFC 9309 matcher requests return `matcher_status = "capability_unavailable"`
(reason `matcher_capability_unavailable`; the rfc9309 revision is
`capability-unavailable-v1`). Bing matcher
requests are available, bounded to its supported vendor profiles
(`bounded_profiles`). The RFC 9309 and Bing policy tables still resolve
independently where the accepted design has evidence. Bing fetch/status policy
remains a `documentation_gap`; `assumed_rfc9309` is a separately named
application policy and is never reported as Bing.

## Legacy compatibility

The existing `allowed_by_robots_text()`, `allowed_by_robots_url()`,
`robots_fetch()`, and `robots_body()` remain unchanged, apart from the additive
Retry-After, Content-Type and cache-header columns below and one default:
`allowed_by_robots_url()`'s `max_bytes` is 512,000 bytes, Google's window, no
longer 524,288 (ROBO-uwveumyp; "A robots.txt over `max_bytes`" below). That
changes results only on a response whose decoded body is 512,001 to 524,288
bytes: a 2xx is now cut and read to its last complete line; a 3xx, an
unknown status or a status mismatch is now `body_too_large` (`NA`,
`fetch_unknown`) where its redirect was followed before; a 4xx or 5xx keeps
its status outcome but is built from the status alone, so `retry_after` is
`NA` (a 404 or 410 still decides `missing_allow`). `robots_fetch()`,
`robots_validate_url()` and `allowed_by_robots_url()` also take an opt-in
`destination_robots = FALSE` (ROBO-ybhwztid): `TRUE` reads a cross-site
redirect destination's own robots.txt and reports it in components and
`destination_*` columns of its own; the default makes no extra request and
returns exactly the components and columns it did before. The destination's
rules never decide the origin, and the v1 facades do not take the argument.
No v1 enum,
column, schema revision or policy revision moves. For consumers migrating
incrementally, `as_legacy_robots_decisions_v1()` explicitly converts a v1 result
whose policy and matcher are both Google into the original `robots_decisions`
schema. The adapter deliberately keeps legacy generic HTTP/redirect failures
unknown even where the new Google policy has a documented `allow_all` action;
this prevents a silent semantic change in old consumers.

The legacy functions read the caller's one token: no parent-token fallback
and no exemption from `*` ("Google crawler tokens" above). The rows
`as_legacy_robots_decisions_v1()` accepts are exactly the rows that layer
applies to, so for a listed crawler token its legacy frame can differ from
`allowed_by_robots_text()` and `allowed_by_robots_url()` on the same body:
`Googlebot-Image` with only a `Googlebot` group and a `*` group gets the
`Googlebot` group from the adapter and `*` from the legacy functions, and
`AdsBot-Google` on a `*`-only body is allowed by the adapter and obeys `*`
there. The adapter's frame does not carry `group_token`, `matcher_url`,
`url_preprocessing_note`, `preprocessing_disagreement` or
`disagreement_clients`, and its decisions follow the `url_normalization`
the v1 result was built with: under the default, a dot-segment URL can be
decided differently from the legacy functions, which read it as given.

### Retry-After on legacy fetch rows (ROBO-cthdyvlk)

Every `robots_decisions$robots` and `robots_fetches$robots` frame gains two
columns between `error_message` and `body`, so the frame has one schema
whichever function built it:

| column | type | value |
|---|---|---|
| `retry_after` | character | The final response's `Retry-After` field value as ssrfr delivers it (optional whitespace trimmed, obs-fold unfolded), several fields joined with `", "`; `NA` when not available. |
| `retry_after_seconds` | double | The delay it asks for (RFC 9110 §10.2.3): `delay-seconds` as is, or an HTTP-date (any of the three RFC 9110 §5.6.7 forms) less the response's `Date`, or less the fetch time when `Date` is absent or invalid; a past date is `0`; `NA` when not available or neither form. Unbounded, since RFC 9110 sets no maximum: the caller clamps it. |

`robots_fetch()` and `allowed_by_robots_url()`, which carries its frame
unchanged, fill them. "Final response" is the non-3xx response that ends the
chain; a redirect's `Retry-After` never counts.

`NA` means "not available", not "no delay requested". Besides a final
response without the field, that covers an outcome with no usable final
response: a refusal, a transport failure, a `redirect_error`, and a body
over `max_bytes` with a 3xx status, an unknown status, or a 2xx whose libcurl
and status-line statuses disagree. A 2xx body over `max_bytes` that is cut is a
final response (ROBO-ldpahknv below), so its `Retry-After` is kept. A 4xx or 5xx whose body
exceeds `max_bytes` keeps its
status and outcome, but ssrfr's size failure carries no headers, so its
`Retry-After` is `NA` even when the server sent one. robotstxtr never
retries; the caller decides whether to wait.

`allowed_by_robots_text()` (a supplied body) and
`as_legacy_robots_decisions_v1()` (the v1 evidence keeps no Retry-After)
always write `NA`. The v1/v2 `evidence` frame and the `robots_validate_url()`
`documents` frame (which copies named fetch fields, not the row) are
unchanged, so the engine schema revision does not move.

Decision: no generic list of the final response's headers. A header list
would publish ssrfr's header representation as robotstxtr API and carry
fields no caller acts on. Each header a caller needs gets its own typed
column: `Content-Type` and its content flags are the follow-up
ROBO-nhuirvrd, and seven cache fields the follow-up ROBO-zleohwyz ("Cache
headers on legacy fetch rows" below). This first read "keep `Retry-After`
only"; the maintainer amended it on 2026-11-21 to admit the cache fields,
each still a named, typed column chosen on purpose, never a header dump.

### Content-Type and the content flag on legacy fetch rows (ROBO-nhuirvrd)

Every `robots_decisions$robots` and `robots_fetches$robots` frame gains two
more columns, between `retry_after_seconds` and `body`, under the same "final
response" rule and the same legacy-schema scope as Retry-After above:

| column | type | value |
|---|---|---|
| `content_type` | character | The final response's `Content-Type` field value as received, several fields joined with `", "`; `NA` when absent or when there is no final response. Any status, not only 2xx. |
| `content_flag` | character | A heuristic read of the first 4096 bytes of the stored body; `NA` when there is no stored body (only `fetched` stores one), the body is empty, or nothing matches. |

`robots_fetch()` and `allowed_by_robots_url()` fill them.
`allowed_by_robots_text()` (a supplied body, no response) and
`as_legacy_robots_decisions_v1()` (the v1 evidence keeps neither) always
write `NA` in both.

`content_flag` has a closed vocabulary; the first match wins:

1. `binary`: a NUL byte, or at least 8 of the window's bytes, and more than
   10% of them, not part of valid UTF-8 (so a short Latin-1 file is not
   binary). The flag decides nothing: the Google backend still ends each
   line at its first NUL (`R/body-decode.R`, ROBO-pvqrfvol), and the Bing
   and Yandex backends read a NUL as an ordinary byte.
2. `html`: a line starting, after whitespace or a UTF-8 BOM, with
   `<!doctype html`, `<html`, `<head` or `<body`, in any letter case,
   possibly after `<?...?>` declarations and `<!--...-->` comments that close
   on that same line. An HTML error page lands here. So does a body whose
   first non-whitespace byte is `<`, whose root is HTML, and whose window
   holds `<!doctype html`, `<html`, `<head`, `<body`, `<script` or `<style`
   anywhere, in any letter case, followed by whitespace, `>`, `/` or the
   window's end: a minified page opening with inline script or style
   (ROBO-qquftxcx). The root is the first start tag after any number of
   leading items, each skipped whole (ROBO-isbpzgqn): `<?...?>` declarations;
   comments, including the abrupt `<!-->` and `<!--->` and a `--!>` closer;
   markup declarations `<!...>`, with a doctype of any kind, an internal subset
   in `[...]`, and the `<![if ...]>`, `<![endif]>` and `<![CDATA[...]]>`
   sections; and end tags. A `<!doctype html` among those items makes the root
   HTML by itself. The root's name, after any namespace prefix and in any
   letter case, is an HTML element name (the WHATWG element names, obsolete
   ones included, and the parser alias `image`, with `svg` and `math` left
   out) or a custom element name with no prefix: a letter, then a hyphen, and
   not a reserved SVG or MathML name. A name must end in whitespace, `/` or
   `>`, so a root cut right after its name at the window's end reads `xml`.
   `<title`, `<link` and `<meta` are left out, since RSS and Atom feeds use
   them. Two known limits hide the root, as no item skips them: an unclosed
   `<?php`, and a server template such as `<%@ page %>`.
3. `xml`: the first non-whitespace byte is `<`. No robots.txt line starts
   with `<`; a `<` inside a comment or a value never flags. Markup whose root
   is not HTML (an SVG, a KML, a feed, an S3 error) lands here even when it
   holds `<style` or another marker, unless a line starts with `<!doctype
   html`, `<html`, `<head` or `<body`, which item 2 matches first. Markup
   without any of the six markers above, such as tag soup, lands here too.
   A robots.txt that opens with a markup comment and then rules is `xml`
   too: no root follows the comment.
4. `json`: the body opens with a JSON object (`{` then `"` or `}`) or array
   (`[` then a value or `]`).

Decisions:

- The flag only flags. The body is matched exactly as before, so no allow or
  disallow decision, `fetch_outcome` or v1 `evidence` field depends on it.
- The flag is read from the body only. `Content-Type` is reported, never
  read: servers mislabel both ways (a robots.txt served as `text/html`, an
  HTML page as `text/plain`), and two independent columns let a caller
  compare them instead of receiving robotstxtr's blend.
  `robots_validate_url()` reads the final response's `Content-Type` for its
  own diagnostics (ROBO-plkpmoll); the v1 columns, `content_type` and
  `content_flag` are unchanged, so the engine schema revision does not move.
- One character column with a closed vocabulary, not one logical per kind:
  the kinds are exclusive under the first-match order, a new kind is a new
  value rather than a new column, and a caller filters on `!is.na()`.
- Plain-text error pages ("404 Not Found" served with a 200) are not
  detected: no cheap test separates them from a short robots.txt.

### Cache headers on legacy fetch rows (ROBO-zleohwyz)

Every `robots_decisions$robots` and `robots_fetches$robots` frame gains seven
character columns, between `content_flag` (since ROBO-rozvglkd,
`content_encoding`) and `body_truncated`, in this
order, under the same "final response" rule and the same legacy-schema scope
as Retry-After above. Each is the final response's field value, unparsed, as
ssrfr delivers it, several fields of one name joined with `", "`:

| column | field |
|---|---|
| `cache_control` | `Cache-Control` |
| `age` | `Age` |
| `date` | `Date` |
| `expires` | `Expires` |
| `etag` | `ETag` |
| `last_modified` | `Last-Modified` |
| `vary` | `Vary` |

`NA` means "not available": the final response did not send the field, or
the fetch ended without a usable final response (the Retry-After cases above,
a 4xx or 5xx over `max_bytes` included). `""` means the field was sent with
an empty value. Any status, not only 2xx; a redirect's fields never count.
`robots_fetch()` and `allowed_by_robots_url()` fill them;
`allowed_by_robots_text()` and `as_legacy_robots_decisions_v1()` always
write `NA`. One internal table, `cache_header_fields` in
`R/fetch-policy.R`, names the fields for the reader and for every frame
builder.

Decisions:

- Raw values only. No age, freshness lifetime or expiry is computed, and a
  malformed value is kept as it is; the explanation of what each field
  means lives in the `robots_fetch()` help. `Date` still feeds
  `retry_after_seconds`, unchanged.
- The columns describe this response only. They do not show what any
  crawler has cached or when it will refetch, and absent validators do not
  make a robots.txt invalid.
- The fetch stays non-conditional (no `If-None-Match` or
  `If-Modified-Since`) and nothing is cached between calls.
- The v1/v2 `evidence` frame and the `robots_validate_url()` `documents`
  frame are unchanged, so the engine schema revision does not move.

### Content-Encoding on legacy fetch rows (ROBO-rozvglkd)

Every `robots_decisions$robots` and `robots_fetches$robots` frame gains one
character column, `content_encoding`, between `content_flag` and the
cache-header columns, under the same "final response" rule and legacy-schema
scope as Retry-After above. It is the final response's `Content-Encoding`
field value as received, several fields joined with `", "`; `NA` when absent
or when there is no final response. `robots_fetch()` and
`allowed_by_robots_url()` fill it; `allowed_by_robots_text()` and
`as_legacy_robots_decisions_v1()` always write `NA`.
`robots_compare_fetches()` carries it on `observations` but does not count it
in `comparison`.

Decisions:

- Raw, and about the response, not the body. libcurl decodes a `gzip` or
  `deflate` body it asked for, so `content_encoding = "gzip"` does not mean
  the stored body is compressed. A body still compressed, as when a server
  compresses a body the fetch asked to be sent uncompressed, is stored as
  received, and the validator reports it as `compressed_body` from the bytes,
  not from this column.
- The `Accept-Encoding` the fetch sent is not recorded: ssrfr chooses it
  internally (`gzip, deflate` when libcurl has zlib, else `identity`) and
  does not expose it, so recording it needs an ssrfr change first.
- The v1/v2 `evidence` frame and the `robots_validate_url()` `documents`
  frame are unchanged, so the engine schema revision does not move.

### A robots.txt over `max_bytes` (ROBO-ldpahknv)

RFC 9309 §2.5 lets a crawler impose a parsing limit of at least 500 KiB and
parse the part of the file it read. robotstxtr fetches with ssrfr's
`truncate_body`, so a 2xx body over `max_bytes` comes back as its first
`max_bytes` decoded bytes instead of failing. The cut falls at a byte and may
split a character.

| surface | a 2xx over `max_bytes` |
|---|---|
| `fetch_outcome` (legacy `robots` and `map` rows, v1 `legacy_fetch_outcome`) | `fetched`, with no error fields |
| legacy `body`, `body_size` | the first `max_bytes` bytes; `body_size` equals `max_bytes` |
| legacy `body_truncated` | `TRUE`; `FALSE` on every other row |
| `robots_validate_url()` documents | the prefix is validated up to its last complete line; `body_truncated` and `limit_exceeded` are `TRUE`, `final_newline` is `NA`, `byte_size` is the stored size; one `body_truncated` warning diagnostic, no `acquisition_limit_exceeded` |
| legacy matching (`allowed_by_robots_url()`) | the prefix, 512,000 bytes at the default `max_bytes` (ROBO-uwveumyp), is matched up to its last CR or LF; the partial line after it, and every rule after the cut, do not exist; a prefix with no line break yields no rules |
| `content_flag` | read from the prefix; a split character at the end is at most three invalid bytes, under the eight `binary` needs |
| v1 `body_present`, `stored_bytes` | `TRUE`, `max_bytes` |
| v1 `body_truncated` | `TRUE`; `FALSE` on every other row |
| v1 `observed_bytes` | ssrfr's count of the decoded bytes reached, past the limit by up to one delivery; not the file's size, which is never read |
| v1 `termination_reason` | `ceiling` |
| v1 `evidence_status` | `incomplete`, as before: no v1 policy verdict or URL decision is made from a prefix, except for a cut of at least 512,000 bytes: the `yandex` ruleset's `allow_all` (ROBO-arrtietl) and the `google` ruleset's match, with the `google` backend, of the complete lines in its first 512,000 bytes (ROBO-ptibdnvy) |

A body over `max_bytes` with a 3xx status, an unknown status, or a 2xx whose
libcurl and status-line statuses disagree is still `body_too_large` with no
body, and a 4xx
or 5xx still keeps its status outcome with no body: ssrfr truncates only a 2xx.
A 206 stays `partial_response` with no body.

Decisions:

- `fetch_outcome` stays `fetched`; no `fetched_truncated` value. The legacy
  `fetch_outcome` set is closed in practice: `allowed_by_robots_url()` matches
  only `fetched` rows and classifies every other value it knows as a fetch
  failure, so a new value would leave the prefix unmatched and its rows with
  no `decision_source`. The cut is carried by `body_truncated`,
  `observed_bytes` and `termination_reason`, which the v1 evidence already
  publishes. No v1 enum or column changes, so the engine schema revision does
  not move. The values of a v1 row over the ceiling do change: it now carries
  `legacy_fetch_outcome = "fetched"`, `body_present = TRUE`, `stored_bytes =
  max_bytes` and `body_truncated = TRUE`, while `evidence_status` is still
  `incomplete`.
- The v1 evidence of a cut body stays `incomplete`. `engine-profiles.md`
  §2 maps `termination_reason = ceiling` there, and a prefix cannot stand in
  for a whole file under every engine: Yandex's documented over-500 KB
  `allow_all` needs the file's real size, which a prefix under a smaller
  `max_bytes` hides. The ruleset reads the cut instead (ADR 0001 §5, slice
  8; ROBO-arrtietl): a `yandex` cut that stored at least 512,000 bytes
  proves the file is over 500 KB under either reading of the unit, so
  `resolve_policy_v1()` lets it past the `incomplete` return to the policy
  table: a cut 200 reaches the existing size branch, `allow_all` /
  `yandex_file_over_500000_bytes` `[documented]`, and a cut non-200 2xx
  resolves `allow_all` / `non_200_allow_all` `[documented]`, as its uncut
  form does. The evidence row is unchanged, the schema revision does
  not move, and the yandex policy revision moves to
  `yandex-robots-policy-2026-11-09`.
- Under `google` (ADR 0001 §5, slice 9; ROBO-ptibdnvy), a cut that stored
  at least 512,000 bytes holds the whole window Google parses, so, when the
  matcher backend is `google` too, `resolve_policy_v1()` lets it past the
  `incomplete` return to the policy
  table cell of its uncut form: a cut 200 resolves `use_rules` /
  `http_200_use_rules` `[documented]` and a cut non-200 2xx `use_rules` /
  `http_2xx_use_rules` `[documented]`, with no new reason. The row is
  matched on the cut body's complete lines (the bullet on matching below),
  then on Google's 512,000-byte window, so a cut of exactly 512,000 bytes
  loses its partial last line as a longer cut does. With `max_bytes`
  exactly 512,000, a line whose break falls at byte 512,001 is dropped,
  although the uncut file would keep it inside the window: the break is not
  stored, and dropping the line is the cautious reading, tagged
  `[application_choice]` in `engine-profiles.md` §7. `matcher_body_truncated`
  is `TRUE` for every such row, since the cut proves the file exceeded the
  window. A smaller cut stays `incomplete_evidence`; a google-ruleset cut
  with another matcher backend stays `incomplete_evidence` too, since the
  reading is the google matcher's; and `rfc9309`, `assumed_rfc9309` and
  `bing` keep every cut incomplete. The evidence row
  and the schema revision do not move. The google policy revision
  `google-robots-policy-2026-11-12`, not yet released, covers the
  512,000-byte window (ROBO-phfbpfiy), this reading of the cut and the
  crawler-token layer (ROBO-fbbmvbob, "Google crawler tokens" above).
- Every legacy `robots` frame gains a logical `body_truncated` column,
  between the cache-header columns (ROBO-zleohwyz, after `content_flag` and
  `content_encoding`) and `body`, under the one-schema rule of the Retry-After and Content-Type
  columns above: `robots_fetch()` and
  `allowed_by_robots_url()` fill it from the fetch, `allowed_by_robots_text()`
  writes `FALSE` (the caller supplied the whole text), and
  `as_legacy_robots_decisions_v1()` copies the v1 evidence's `body_truncated`.
- Matching and validation stop at the cut body's last CR or LF. The cut
  usually lands inside a line, and the partial line is not the site's rule:
  `Disallow: /private-drafts/` cut to `Disallow: /` would disallow
  everything. Dropping it is the cautious reading; the stored `body`,
  `body_size` and v1 `stored_bytes` keep every byte ssrfr returned.
- `as_legacy_robots_decisions_v1()` leaves `error_class` `NA` on a cut
  source's rows. Under 512,000 stored bytes they are `fetched`,
  `allowed = NA`, `fetch_unknown`: the legacy `error_class` set has no class
  for a cut body, and the v1 `reason` `incomplete_evidence` is not a legacy
  class. At or above it the rows are matched (ROBO-ptibdnvy) and carry
  `allowed` and the match `reason` as `decision_source`, read from the first
  512,000 bytes, where `allowed_by_robots_url()` reads the whole stored
  prefix (512,000 bytes at its default `max_bytes`). Its documentation says
  so.
  `observed_bytes` stays in the v1 evidence only.
- `robots_validate_url()` validates a cut prefix and reports the cut in its
  documents frame. A body refused whole (a 3xx, an unknown status, or a 2xx
  whose libcurl and status-line statuses disagree, over `max_bytes`) is still
  `not_validated` with `acquisition_limit_exceeded`.
- `max_bytes` below RFC 9309's 500 KiB floor (`512000`) stays accepted, and
  is documented as below it. Every default meets the floor: `524288` for
  `robots_fetch()`, `robots_validate_url()` and `robots_evaluate_url_v1()`,
  and `512000` for `allowed_by_robots_url()` (ROBO-uwveumyp), which then
  reads what Google's window holds: a rule after byte 512,000, or a line
  that byte splits, is not read. Its cut is at byte 512,000 itself, so a
  line ending there whose line break is byte 512,001 is dropped, where the
  v1 google reading, with one byte to look at past the window, keeps it.
  That edge is accepted: fetching 512,001 bytes would change the recorded
  `max_bytes`. An explicit `max_bytes = 524288` reads the complete lines
  up to byte 524,288 again.

### Redirect and safety reasons in the legacy frame (ROBO-bsloeclp)

Every legacy `robots` frame gains two character columns, `terminal_redirect_reason`
and `safety_block_reason`, between `body_truncated` and `body`, under the
one-schema rule of the columns above. `robots_fetch()` and
`allowed_by_robots_url()` fill them from the fetch, `allowed_by_robots_text()`
writes `"none"` and `NA` (no fetch took place), and
`as_legacy_robots_decisions_v1()` copies the v1 evidence's columns of the same
names, which already carried both. No v1 enum or column changes, so the engine
schema revision does not move. `robots_validate_url()` reads the two columns to
give redirect, transport and safety outcomes their own diagnostic codes;
`acquisition_failed` stays the code for an outcome no class covers.

### Redirect hops in the legacy frame (ROBO-cscdbael)

Every legacy `robots` frame gains a list column, `redirect_hops`, between
`safety_block_reason` and `body`, under the same one-schema rule. Each element
is the hop log of one source, with the name and shape of the v1 evidence
column: a list with one entry per 3xx met, each a list of `from_url`
(character), `status` (integer) and `location_target` (character, `NA` when
the response named no target). The log also records a hop that was not
followed (a refused downgrade under `strict`, the over-budget hop, a loop's
closing hop, a refused scheme); the first `redirect_count` hops are the ones
followed. `robots_fetch()` and `allowed_by_robots_url()` fill it from the
fetch, `allowed_by_robots_text()` writes `list(list())` (no fetch took place),
and `as_legacy_robots_decisions_v1()` copies the evidence's `redirect_hops`. No
v1 enum or column changes, so the engine schema revision does not move.
`robots_validate_url()` reads the followed hops to report an `https` to `http`
redirect that `safety_level = "crawler"` followed as
`redirect_downgrade_followed` (info), for a fetch that reached a body.

## Sibling compatibility

The supported first-release ranges are:

- sitemapr `>= 0.0.0.9000, < 0.1.0`;
- sitemap-validator `>= 1.0.0, < 2.0.0`.

Consumers must negotiate the contract ID and schema revision, not infer support
only from the robotstxtr package version.

## Registering another matcher backend

Backend dispatch and revision/capability metadata live together in
`R/engine-contract-v1.R`. `evaluate_rows_v1()` dispatches on the registry
entry alone, never on a backend's name (ROBO-bukqpjli): it collects the rows
that need a matcher, calls each backend's adapter once with all of its rows,
and scatters the decision frame back. Google, Yandex and Bing all sit behind
the same interface. The one exception is the disagreement flag (ADR 0002,
ROBO-bnvdmdjr): under `"rfc3986"` and `"whatwg"` it calls an adapter a
second time, with only the rows whose two URL forms differ, reading the
other form.

A **matcher adapter** is `callable(bodies, urls, product_tokens)`: a list of
raw bodies and two character vectors, one element per row. It returns a
**decision frame**, a data frame with one row per input row, in input order,
carrying `matcher_status`, `url_decision`, `reason`, `matched_line`,
`matched_rule_type`, `matched_rule_value`, `matcher_input_bytes`,
`matcher_body_truncated`, `error_stage`, `error_class`, `error_message` and
the list column `matched_rule_value_raw` (`matcher_decision_columns_v1()`).
Extra columns (`native_*`) and attributes (`n_parse_calls`) are allowed and
ignored, save `group_token`, which the evaluator copies into the results
(`NA` where the frame has none). An adapter may also take an optional
fourth argument, `crawler_profiles`: a data frame with one row per input
row, `parent_token` (`NA` for none) and `ignore_global`. The evaluator
resolves it per row from `crawler_tokens` (the `google` ruleset with the
`google` backend only; no profile elsewhere) and passes it only to a
callable whose formals name it, so the dispatch still reads the entry, not
the backend's name. Google's adapter takes it; Yandex's and Bing's do not,
and a three-argument fake is called as before (ROBO-fbbmvbob). Every
per-row outcome, an unsupported profile included, is a row;
an adapter aborts only on an internal invariant violation, and the evaluator
does not catch that abort. The evaluator checks each frame's row count and
columns (`check_matcher_output_v1()`) and fails with
`robotstxtr_matcher_output_invariant` when either is wrong, as it fails on a
status outside the published set.

The evaluator hands an adapter the readable body: a body cut at `max_bytes`
(read only under the `google` ruleset with the `google` backend) has its
partial last line dropped first, and each row's own cut is OR-ed into the
frame's `matcher_body_truncated`. In the Google adapter the matcher parses
each distinct body once, cut to Google's 512,000-byte window, and the line
collector reads each body that has a matched row once more; row for row it
gives what its reference row matcher `match_google_v1()` gives, and its
`matched_rule_value_raw` is `NULL`. A row with a parent token runs a second
matcher on its body's one parse, so a body is still parsed once per adapter
call; the row matcher runs each token on its own parse. The disagreement
flag's second call parses again only the bodies of its rows.

To add a backend without changing the core result schema:

1. complete the engine-profile gate: released contract, deterministic corpus,
   ABI and version review, provenance, and compatible licensing;
2. write its matcher adapter, returning the decision frame above;
3. atomically register that adapter, its exact revision, and its `available`
   capability in `engine_matcher_registry_v1()` under the explicit backend
   name; the registry invariants reject partial or inconsistent activation.
   A backend name the registry does not have yet must also be added to
   `engine_matchers_v1()` and to `engine_backend_capability_v1()`; the
   evaluator itself needs no change;
4. add its conformance corpus and end-to-end facade tests, and run it through
   the shared adapter-output test helper
   (`tests/testthat/helper-matcher-registry-bukqpjli.R`); and
5. issue a new schema revision if any enum or column must change. Adding a
   backend implementation alone does not change the v1 result columns.

Tests swap an engine by swapping its registry entry (a fake registry passed
as `evaluate_rows_v1()`'s internal `matcher_registry` argument, or installed
for the public entry points with `local_matcher_registry()`), not by mocking
a matcher function. The public entry points take no registry.

Never route an unavailable backend to Google and never relabel Google matching
as RFC, Yandex, or Bing behavior.

A new backend must also declare its **token policy**: whether it accepts any
valid token as its own semantics (`arbitrary_valid`, as Google does for
group selection) or is bounded to a fixed set of supported vendor profiles
(`bounded_profiles`, as Yandex and Bing are; RFC 9309 uses `rfc9309`). This
boundary is published as data on the contract object as
`robots_engine_contract_v1()$matcher_capability`, keyed per backend with
`token_policy`, `matcher_semantics`, and a human-readable `note`. Google
accepting an arbitrary valid token yields Google parsing/matching semantics for
that token. Under the `google` ruleset, a token listed in `crawler_tokens`
also selects its group as Google documents for that crawler ("Google crawler
tokens" above): a crawler-aware layer, read from Google's documentation, not
from the crawler. For any other token, and under any other ruleset, the
result is never a claim of compatibility with — or a prediction of — the
crawler the token names.

## Accepted matcher-profile selectors

A backend whose `token_policy` is `bounded_profiles` accepts a closed set of
selectors and rejects everything else. As of schema revision `2026-08-25.1`
that set is published, so a consumer can validate its configuration before
evaluating anything instead of discovering the mistake in the results.

Each such backend's `matcher_capability` entry carries three additional fields:

- `product_token_role` — always `matcher_profile_selector`. The value names
  what the token IS: a robots.txt `User-agent:` group selector, not an HTTP
  `User-Agent` crawler identity. RFC 9309 treats those as one namespace;
  Yandex does not, because its umbrella label `Yandex` is a group name no
  crawler ever sends.
- `product_token_comparison` — always `ascii_case_insensitive_exact`. ASCII
  case folding, exact whole-token match, no trimming, no prefix or suffix
  matching, no aliases.
- `supported_profiles` — a data frame with columns `profile_id`,
  `accepted_token`, `group_label`, `group_selection`, `profile_revision`.

`group_selection` is normative and takes one of two values:

| value | meaning |
|---|---|
| `exact_else_wildcard` | Merge every group naming this token exactly. Only if no such group exists, merge the `User-agent: *` groups. |
| `exact_only` | Merge every group naming this token exactly, and never fall back to a wildcard group. A robots.txt containing only `User-agent: *` constrains this profile not at all. |

The published sets:

| backend | `accepted_token` | `group_selection` |
|---|---|---|
| `yandex` | `Yandex` | `exact_else_wildcard` |
| `yandex` | `YandexAdditionalBot` | `exact_only` |
| `bing` | `bingbot` | `exact_else_wildcard` |
| `bing` | `adidxbot` | `exact_only` |

The two accepted tokens within a backend are therefore **not
interchangeable**, which is why the contract publishes rows rather than a bare
token vector. The `exact_only` pattern is vendor-neutral: the Yandex
"Additional" family and Bing's AdIdxBot both behave this way.

A backend whose `token_policy` is `arbitrary_valid` (`google`) or `rfc9309`
publishes none of the three fields — its accepted set is not closed, so there
is nothing to enumerate. `rfc9309` is both `capability_unavailable` and
unbounded; it publishes no profile table for the second reason, not the first.

Its set is not closed, but it has a grammar. Since schema revision
`2026-11-22.1` (ROBO-mtmkpwuf) both backends publish
`product_token_grammar = "rfc9309_identifier"`: the token must be an RFC
9309 `identifier`, one or more of the ASCII letters, `_` and `-`, and
nothing else (§2.2.1, "MUST contain only uppercase and lowercase letters
('a-z' and 'A-Z'), underscores ('_'), and hyphens ('-')"). The ABNF's
`product-token` is `identifier / "*"`, but `*` names the wildcard group,
not a crawler, so a caller's own token must be an `identifier`. The bytes
are compared as bytes, so a letter outside ASCII, a latin1 byte or invalid
UTF-8 is not one. The contract validator refuses the field on a bounded
backend, its absence on an `arbitrary_valid` or `rfc9309` one, and any
other value.

The v1 facades screen the token against it on those two backends, under
every ruleset, as they screen an empty token: a row whose token is not an
`identifier` is `policy_status` and `matcher_status` `not_evaluated`,
`reason` and `policy_reason` `input_invalid`, `error_stage = "input"`,
`error_class = "robots_invalid_product_token"`, with no source and no
decision. `robots_evaluate_url_v1()` screens before the fetch, so the row
makes no request and an origin that would answer 404 does not turn it into
`allow_all`; a valid row on the same origin is fetched as before. An
`rfc9309`-backend row so refused moves from `capability_unavailable` to
`input_invalid`. The reason is Google's matcher: it cuts each file
`User-agent` value at its first character outside `[A-Za-z_-]`
(`ExtractUserAgent`) and compares the cut value with the caller's token as
given, so such a token (`Googlebot/2.1`, a full HTTP `User-Agent` string, a
leading or trailing space, `*`, digits) can never name a group and silently
read `*`. Upstream ships `RobotsMatcher::IsValidUserAgentToObey()` for
callers (`src/robots.cc`), but `AllowedByRobots` does not apply it;
refusing is this package's policy. The
token is never trimmed or rewritten. `error_message` says the token is not
an RFC 9309 identifier, that a crawler's own product token must be one and
`*` names no crawler, and that it is the robots.txt group token, not the
HTTP `User-Agent` string, and names the leading run of identifier bytes,
when there
is one, as a hint only (`Googlebot` for `Googlebot/2.1`, `archive` for
`archive.org_bot`); it never echoes the token, which `robots_product_token`
carries. An `NA` or empty token keeps "Robots product token is missing or
empty.", and an invalid URL still wins over an invalid token. The bounded
backends keep their own refusals (below), made after the fetch, and
`robots_resolve_matcher_profile_v1()` still returns an unbounded row for
any `google` or `rfc9309` token. The legacy functions read any token as
given.

`google` publishes `crawler_tokens` instead ("Google crawler tokens" above),
which lists not what it accepts but the tokens whose group selection the
`google` ruleset changes. Its `group_selection` takes `exact_only` or a
third value, `exact_else_parent_else_wildcard`, that only `crawler_tokens`
may use; the contract validator refuses it in a `supported_profiles` table,
and refuses `crawler_tokens` on a backend that is not `arbitrary_valid`.
`robots_resolve_matcher_profile_v1()` is unchanged: it still reports no
`group_selection` for a `google` token.

Passing an unaccepted selector is not an error at evaluation time, and the two
backends do not report it identically:

| backend | `matcher_status` | `reason` | `error_class` |
|---|---|---|---|
| `yandex` | `not_evaluated` | `unsupported_product_token` | `robots_unsupported_product_token` |
| `bing` | `unsupported_profile` | `unsupported_profile` | `robots_unsupported_profile` |

The Yandex shape is the quieter of the two: a caller who does not inspect
`reason` sees an evaluation in which nothing was decided, which reads like a
transport failure rather than a configuration mistake. That is the failure this
publication exists to prevent.
