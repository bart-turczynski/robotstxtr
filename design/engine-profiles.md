# robotstxtr engine profiles — robots.txt status-policy, matchers, limits

- Status: Accepted (governed by sitemapr ADR-009 "Per-engine validation profiles")
- Date: 2026-07-16 (accepted 2026-07-17)
- PRD scope: the version-scope amendment this requires is recorded in `design/PRD.md`
  §13 (Amendment A) — ruleset-aware, versioned entry points added alongside the pinned
  v1 surface (PRD §3: robotstxtr validates robots.txt syntax and structure for the
  Google-compatible profile, and is still not an authoring tool or a crawler; this doc adds
  no per-engine validator scope).
- Owns: the `robots_policy_ruleset` and `matcher_backend` value sets, the neutral fetch-outcome
  contract, per-engine status→policy, user-agent group selection, current policy/matcher limits, and
  the `safety_level` value set and what each level may do (§3a; ADR 0001).
  sitemapr owns the sitemap rules and the findings contract.

Provenance tags (ADR-009 §0): executable = `documented` / `inherited_protocol` / `application_choice`;
diagnostic = `inferred` / `documentation_gap` / `documentation_conflict` / `advisory`. Current guidance
supersedes historical. **A `documented` tag marks a cell the source states; selecting one behavior
among several the source merely permits (an RFC `MAY`) is an `application_choice`, even though the
permission itself is documented.** Every cell carries exactly one tag and a source (§10).

---

## 1. Scope and non-goals

**In scope:** map a completed fetch (or supplied body) to a robots decision for a selected
`robots_policy_ruleset`, and — when a `matcher_backend` is available — match a URL against the parsed
body for the selected product token.

**Non-goals (this release):**
- **Per-engine content / grammar validation** (unsupported/typo/unknown directives, the
  parsing-error catalog). robotstxtr validates syntax and structure for the Google-compatible profile
  only; this doc's per-engine policy work adds no validator scope (PRD §3; ADR-009 §8). §8 rule-count/line-length/typo items
  are future-validator reference only; nothing there executes.
- <a id="bing-policy"></a>**Bing robots policy** — no current Bing primary source publishes a robots.txt status/redirect/
  network table or an RFC-9309 conformance claim. Every Bing status/redirect cell is
  `documentation_gap`; not synthesized from RFC. A product may opt into an explicit `assumed_rfc9309`
  application policy, never presented as `bing`.
- **Crawler lifecycle emulation** (cache TTL, 30-day grace, last-known-good). Stateless; lifecycle-
  dependent cells resolve to `context_required` (§4).

<a id="neutral-fetch"></a>

## 2. Neutral fetch outcome contract (L0 — engine-agnostic)

L0 applies caller acquisition + safety limits only (never engine parse limits — those are L1) and
records a neutral fact record plus one `evidence_status`.

**Neutral fact record (all fields required; `NA` where not applicable):**
`source_kind` (`fetched` | `supplied` | `local`), `requested_url`, `effective_url`, `redirect_hops`
(ordered list of `{from_url, status, location_target}`, so cross-authority hops are directly
auditable), `redirect_count`, `terminal_redirect_reason` (`none` | `over_budget` | `no_location` |
`loop` | `non_http_target` | `downgrade`), `final_http_status`, `location_header` (on a terminal
redirect), `body_present` (bool), `observed_bytes`, `stored_bytes`, `body_truncated`,
`transport_error_kind` (`timeout` | `tls_error` | `network_error`), `safety_block_reason` (a **closed, stable enum**; any future safety
reason requires a versioned schema addition), `termination_reason` (`none` | `deadline` | `ceiling`).

`safety_block_reason` values. Schema revision `2026-08-25.1` published the code set of robotstxtr's
own guard (`R/ssrf.R`, removed): `loopback`, `private`, `link-local`, `cloud-metadata`, `shared`,
`unspecified`, `this-network`, `ipv4-mapped`, `ipv4-translated`, `ipv4-compatible`, `nat64`, `6to4`,
`teredo`, `isatap`, `malformed-address`, `numeric-literal`, `scheme` (to which `non_http_target`
maps), PLUS `https_downgrade` (ssrfr's `downgrade`). Schema revision `2026-11-05.1` (ROBO-jbralthm,
the switch to `ssrfr`) adds the refusals ssrfr makes that the old guard did not: `userinfo` (a redirect
`Location` carrying credentials), `port` (port 0), `parse` (a URL the WHATWG and libcurl parsers
read differently, a zoned IPv6 literal, an invalid `xn--` label), `multicast` and `reserved`. The
mapping from ssrfr's reason codes is data in `R/acquire-map.R`; ssrfr's `host-denied` and
`range-denied` are not admitted, since robotstxtr's policy states no deny rules. `body_truncated` is
`TRUE` only for a 2xx body over the ceiling, which ssrfr's `truncate_body` returns as its first
`max_bytes` bytes (`termination_reason = ceiling`, so `evidence_status = incomplete`; ROBO-ldpahknv); a
3xx, an unknown status or a status mismatch (libcurl and the status line
disagree) over it is `body_too_large`; a 4xx/5xx keeps its status outcome. A set `safety_block_reason` means
`evidence_status = safety_refused`, except an address-class code under `safety_level = crawler`, which
means `unreachable_local` (§3a; schema revision `2026-11-11.1`, ROBO-jqwukcog). `fetch_outcome` stays
`ssrf_blocked` at both levels.

**`evidence_status` (exhaustive):**

| `evidence_status` | Trigger | → decision path |
|---|---|---|
| `usable_body` | 2xx (excl. 206) within ceiling (`source_kind=fetched`), OR a supplied/local body (`source_kind ∈ {supplied, local}`) | fetched → §4 by `final_http_status`; supplied/local → `use_rules` `[application_choice]`, then §6 |
| `partial` | 206 | policy resolves per §4, but body unusable → `matcher_status = not_evaluated` (ADR-009 §2 row) |
| `incomplete` | body over ceiling or `termination_reason ∈ {deadline, ceiling}` | never a policy verdict, except a ruleset's §7 reading of a cut 2xx; otherwise `policy_status = not_evaluated` |
| `http_status` | final non-2xx status received (4xx/5xx) | §4 by `final_http_status` |
| `http_protocol_error` | 1xx received, or malformed redirect (`no_location`/`loop`) | §3 terminal-reason handling |
| `redirect_over_budget` | `terminal_redirect_reason = over_budget` | §3 engine exhaustion rule |
| `transport_fail` | DNS/connect/TLS/timeout/reset/chunk (`transport_error_kind` set); never with a `safety_block_reason` | §4 network row |
| `unreachable_local` | under `safety_level = crawler` only: an address-class refusal (`safety_block_reason` kept; no connection made; §3a) | §4 `unreachable_local` row (same cells as the network row) |
| `safety_refused` | under `safety_level = strict`: any ssrfr refusal incl. HTTPS→HTTP downgrade; under `crawler`: URL-shape refusals only (`scheme`, `userinfo`, `port`, `parse`, `numeric-literal`, `malformed-address`) | never allow/deny; §3a (ADR 0001); sitemapr ADR-003 governs the guard |
| `not_applicable` | no robots evaluation applies (no body and no status to interpret) | `policy_status` / `matcher_status` = `not_evaluated`; `url_decision` absent |

`evidence_status` is the ADR-009 §2 versioned set; `source_kind` (a separate fact) distinguishes where
a `usable_body` came from. Supplied/local bodies (`allowed_by_robots_text()`, local-file inputs) are
NOT `not_applicable`: they carry a usable body, so the ruleset resolves to `use_rules` (a named
`application_choice` — there is no fetch status to interpret) and the matcher produces rule/default
decisions when a backend is available (§6). `not_applicable` is reserved for the genuinely-inapplicable
case.

Note (`http_protocol_error` for 1xx): a received 1xx is an HTTP/protocol outcome, deliberately kept
distinct from `transport_fail` (DNS/TLS/network). Current code lumps 1xx into `http_error`
(`R/fetch-policy.R:88`); this contract separates them (an implementation delta, §9).

<a id="redirect-handling"></a>

## 3. Redirect handling (per terminal reason, then per engine)

RFC 9309 §2.3.1.2 says crawlers SHOULD follow **at least five** consecutive redirects, incl. across
authorities, applying reached rules to the initial authority `[documented]`. Terminal reasons do NOT
share one engine column — each has its own provenance/action:

- **`downgrade` / SSRF / non-http(s) target** → decided by the `safety_level`, never by the ruleset
  (§3a). No engine documents refusing a downgrade; refusing one is a safety choice
  `[application_choice]`, made under `strict` only.
- **`over_budget`** (documented hop exhaustion) → engine rule:
  - `rfc9309`: `allow_all` `[application_choice]` (basis: RFC §2.3.1.2's documented `MAY`-treat-unavailable).
  - `google`: treat as 404, then apply the 4xx path `[documented]`.
  - `yandex`: hop cap `[documentation_gap]`; robotstxtr follows 5 `[application_choice]`; exhaustion →
    no verdict `[documentation_gap]`, to be measured (ROBO-ogwchglq).
  - `bing`: `[documentation_gap]`; robotstxtr follows 5 `[application_choice]`; no verdict; to be
    measured (ROBO-ogwchglq).

  The hop budget is one L0 setting, 5, for every ruleset: every engine that documents a robots.txt
  count documents five. Google's 10-hop figure is for general crawling
  (`design/engine-fetch-rules-sources.md`).
- **`no_location` / `loop`** (malformed redirect) → `evidence_status = http_protocol_error`. No engine
  documents a specific action → `[documentation_gap]`; a product may choose a deterministic result via
  an explicit `application_choice`, never labeled `documented`.

Within budget: `rfc9309` follows cross-authority, reached rules → initial authority `[documented]`;
`google` follows at least five (cross-authority not separately restated → `[inferred]`); `yandex`
follows incl. cross-host, target's directives apply and the target must return 200 `[documented]`;
`bing` `[documentation_gap]`. None of the engines conditions a redirect on its scheme: an HTTPS→HTTP
hop is followed `[inferred]` for `rfc9309`, `google` and `yandex`, and is `[documentation_gap]` for
`bing`.
The validator's redirect codes (ROBO-gokbvzcb) decide "same site" by the registrable domain from
the Public Suffix List (`rurl::get_domain()`), comparing an IP literal or a host with none whole;
this is reporting only and changes no fetch.
A followed HTTPS→HTTP hop, anywhere in the chain, is reported as `redirect_downgrade_followed`
(info; ROBO-cscdbael): only `crawler` follows one, and on the reading above no engine refuses it.

### 3a. Safety level (ADR 0001)

`safety_level` is independent of `robots_policy_ruleset`. It decides what the fetch may do; the ruleset
decides what an outcome means.

| `safety_level` | HTTPS→HTTP redirect | address-class refusal | URL-shape refusal |
|---|---|---|---|
| `strict` (default) | refused → `safety_refused` / `https_downgrade` | `safety_refused` | `safety_refused` |
| `crawler` | followed as an ordinary hop | not dialed → `unreachable_local`, `safety_block_reason` kept | `safety_refused` |

Address-class codes: `loopback`, `private`, `link-local`, `cloud-metadata`, `shared`, `unspecified`,
`this-network`, `multicast`, `reserved`, `ipv4-mapped`, `ipv4-translated`, `ipv4-compatible`, `nat64`,
`6to4`, `teredo`, `isatap`. URL-shape codes: `scheme`, `userinfo`, `port`, `parse`, `numeric-literal`,
`malformed-address`. `fetch_allow_ranges` reopens the listed ranges at either level.

`crawler` follows downgrades (ROBO-lwdxzdhw) and records an address-class refusal as `unreachable_local`
(ROBO-jqwukcog); the class of each ssrfr code is data in `R/acquire-map.R`. `fetch_allow_ranges` is recorded
as empty until ROBO-bamcjvwn.

<a id="status-policy"></a>

## 4. Status → policy (per `robots_policy_ruleset`, per-cell provenance)

Maps onto ADR-009 §2. Lifecycle-dependent cells resolve to `policy_status = context_required` (with the
documented possibilities), never a fabricated single verdict. `partial` (206) resolves policy but sets
`matcher_status = not_evaluated` (§2).

| Fetch outcome | `rfc9309` | `google` | `yandex` | `bing` |
|---|---|---|---|---|
| 200 | use_rules `[documented]` | use_rules `[documented]` | use_rules `[documented]` | `[documentation_gap]` |
| other 2xx (excl. 206) | `[documentation_gap]` (RFC maps "successful download", not every 2xx) | use_rules (processes 2xx body) `[documented]` | non-200 → allow_all (open) `[documented]` | `[documentation_gap]` |
| 206 / partial | `[documentation_gap]` | policy use_rules `[documented]`; body partial → `matcher not_evaluated` | non-200 → allow_all `[documented]` | `[documentation_gap]` |
| 4xx generic | `allow_all` `[application_choice]` (basis: RFC §2.3.1.3 documented `MAY`-access) | all 4xx **except 429** → allow_all `[documented]` | non-200 → allow_all `[documented]` | `[documentation_gap]` |
| 429 | `allow_all` `[application_choice]` (429 lies within RFC §2.3.1.3's 400–499 example range; this ruleset elects to treat it as unavailable) | excluded from 4xx; robots destination not documented `[documentation_gap]` | non-200 → allow_all `[documented]` | `[documentation_gap]` |
| 5xx | MUST complete disallow, subject to cache/duration (§2.3.1.4/2.4) → `context_required` `[documented]` | stateful lifecycle (12h / 30d last-good / post-30d availability) → `context_required` `[documented]` | non-200 → allow_all `[documented]` | `[documentation_gap]` |
| network / DNS / timeout | = unreachable → MUST disallow, subject to cache/duration → `context_required` `[documented]` | = server error (same stateful lifecycle) → `context_required` `[documented]` | `[documentation_gap]` (accessibility is a file requirement; retry/cache not enumerated) | `[documentation_gap]` |
| `unreachable_local` (`crawler` only; §3a) | = unreachable → MUST disallow, subject to cache/duration → `context_required` `[documented]` | = server error (same stateful lifecycle) → `context_required` `[documented]` | `[documentation_gap]` (accessibility is a file requirement; retry/cache not enumerated) | `[documentation_gap]` |

**Non-robots advisory (`advisory`, never a verdict):** Yandex ignores `Retry-After` on 429 and
sustained 429 lowers host crawl-rate; Yandex recommends 503 to protect ordinary *pages* during
downtime. These are host/page crawl signals, not robots-file policy, and never enter `policy_action`.
(No Bing 429/5xx throttling claim is made — not established by a primary source.)

## 5. User-agent group selection (matcher/ruleset capability, per engine)

Selected **before** path matching; a capability + ruleset revision, not a context axis (ADR-009 §1).
`[documented]` per engine:
- `rfc9309` — case-insensitive product-token match; merge all matching groups; `*` fallback only if
  none match. (RFC 9309 §2.2.1)
- `google` — most-specific matching user-agent; merge that agent's groups; do NOT combine specific
  with global. (Google robots.txt spec, "Order of precedence for user agents") A crawler may list
  two tokens, matched by either (`Googlebot-Image` also by `Googlebot`; common crawlers); the
  `google` matcher binding reads the caller's one token only (§5a).
- `yandex` — specific Yandex robot entry > `Yandex` > `*`. (Yandex, User-agent)
- `bing` — `bingbot` > `msnbot` > `*`, discarding others. (Bing, "To crawl or not to crawl", 2012)

Where the backends' group selection, parsing, matching or rule precedence make the same body
answer differently, the classes, fixtures, verdicts and sources are in
`design/engine-disagreements.md` (ROBO-glssaxva).

### 5a. Google crawler-token fallback (ROBO-mxsphtoo; pages read 2026-11-09)

Question: does a Google crawler token with no group of its own (`Googlebot-Image`) fall back to a
parent token's group (`Googlebot`) before `*`, and should the `google` matcher model it?

**What the vendored matcher does.** `src/matcher_binding.cpp` calls
`RobotsMatcher::OneAgentAllowedByRobots`, which wraps the token in a one-element vector and calls
`AllowedByRobots`. `HandleUserAgent` cuts each `User-agent` value in the file at its first character
outside `[a-zA-Z_-]` (`ExtractUserAgent`; `Googlebot/2.1` reads as `Googlebot`), compares that prefix
with the caller token as given (ASCII case-insensitive), and sets `ever_seen_specific_agent_` on an
equal pair. `disallow()` reads the `*` rules only when no such group was seen. So `Googlebot-Image`
obeys a `Googlebot-Image` group, else `*`, never `Googlebot`, and `Googlebot` never reads a
`Googlebot-Image` group `[application_choice]` (the binding; pinned by
`tests/testthat/test-token-fallback-mxsphtoo.R`). The roxygen of `allowed_by_robots_text()` already
says a crawler obeys the groups whose token equals its own, else `*`; what it lacks is the sentence
that a token never reaches a parent token's group.

The multi-agent `AllowedByRobots(body, &user_agents, url)` is not an ordered fallback: every listed
token's groups count as one specific group, their rules compete by longest match, and `*` is dropped
if any token was named (`robots.h`: "allowed to be fetched by any member"). Passing
`{Googlebot-Image, Googlebot}` merges the two groups instead of preferring the first. The vendored
matcher also ships `RobotsMatcher::disallow_ignore_global()` (`src/robots.cc`), which decides from the
specific groups only and never reads `*`: the upstream hook for the `*`-ignoring crawlers below. The
binding does not call it.

**What Google documents.** The common-crawlers page gives each crawler a "User-agent token in
robots.txt" cell and says: "Some crawlers have more than one user agent token; you need to match only
one crawler token for a rule to apply."

| Crawler | Tokens listed | Tag | Source |
|---|---|---|---|
| Googlebot | `Googlebot` | `[documented]` | common crawlers |
| Googlebot Image | `Googlebot-Image`, `Googlebot` | `[documented]` | common crawlers |
| Googlebot Video | `Googlebot-Video`, `Googlebot` | `[documented]` | common crawlers |
| Googlebot News | `Googlebot-News`, `Googlebot` | `[documented]` | common crawlers |
| Google-InspectionTool | `Google-InspectionTool`, `Googlebot` | `[documented]` | common crawlers |
| Google-CloudVertexBot | `Google-CloudVertexBot`, `Googlebot` | `[documented]` | common crawlers |
| GoogleOther | `GoogleOther` | `[documented]` | common crawlers |
| GoogleOther-Image | `GoogleOther-Image`, `GoogleOther` | `[documented]` | common crawlers |
| GoogleOther-Video | `GoogleOther-Video`, `GoogleOther` | `[documented]` | common crawlers |
| Google StoreBot | `Storebot-Google` | `[documented]` | common crawlers |
| Google-Extended | `Google-Extended` | `[documented]` | common crawlers |
| Google Favicon (retired) | `Googlebot-Image`, `Googlebot` | `[documented]` (historical) | special-case crawlers |
| AdsBot-Google-Mobile-Apps (retired) | `AdsBot-Google-Mobile-Apps`; "obeyed AdsBot-Google robots rules, but ignored the global user agent (`*`)" | `[documented]` (historical) | special-case crawlers |
| AdsBot-Google, AdsBot-Google-Mobile, Mediapartners-Google, APIs-Google | own token; "The global user agent (`*`) is ignored." | `[documented]` | special-case crawlers |
| user-triggered fetchers | no robots token; they "generally ignore robots.txt rules" | `[documented]` | user-triggered fetchers |

So current guidance means a `Googlebot` group applies to Googlebot Image, Video and News,
Google-InspectionTool and Google-CloudVertexBot, and a `GoogleOther` group to GoogleOther-Image and
GoogleOther-Video `[documented]`. A crawler with a single token and no group of its own follows `*`:
the spec's precedence example says "Storebot-Google follows group 2, because there is no specific
Storebot-Google group", and, for the "Otherbot (web)" row, "Other Google crawlers follow group 2"
(group 2 being `*`) `[documented]`.

What the pages leave open:
- **Which group wins when both tokens have one** (a `Googlebot-Image` group and a `Googlebot` group).
  The spec says "Only one group is valid for a particular crawler", chosen as "the group with the most
  specific user agent that matches the crawler's user agent", and its example has `googlebot-news`
  follow its own group over a `googlebot` group "because group 1 is the most specific group". That is
  one crawler, in an example; no page states the rule for the two-token crawlers in general
  `[documentation_gap]`.
- **Whether the parent group applies at all once the child has a group of its own**; the "only one
  group is valid" sentence implies not, but no page says so for the token pairs `[documentation_gap]`.
- **The spec's "Otherbot (news)" row**: "Other Google crawlers that crawl news content, but don't
  identify as googlebot-news follow group 2. Even if there is an entry for a related crawler, it is
  only valid if it's specifically matching." Read broadly, an entry for a related crawler (`googlebot`,
  group 3 of that example) does not reach a crawler of another name, which is what the
  common-crawlers listing does for the two-token crawlers. The two agree only if "specifically
  matching" means "matching one of the crawler's listed tokens", which neither page says
  `[documentation_conflict]`.

**Divergence.** robotstxtr's single-agent binding diverges from the common-crawlers token listing for
the seven two-token crawlers: a caller asking for `Googlebot-Image` on a body with a `Googlebot` group
and a `*` group gets the `*` rules, where Google's listing applies the `Googlebot` group. It agrees for
the single-token crawlers. The `*`-ignoring special-case crawlers are a second divergence: given a
token with no group, the binding falls back to `*`. §6's `token_policy = arbitrary_valid` (Google's
matching for the token, never a prediction of the named crawler) covers both in letter, but a caller
naming a Google crawler token will reasonably read the result as that crawler's.

**Recommendation (for the maintainer; not a decision).** Options:

1. **Model the fallback with a documented token map**, as an opt-in (default unchanged): query the
   crawler's own token with the single-agent call; when `ever_seen_specific_agent()` is false and the
   map lists a parent token, query again with the parent; else `*`. This follows the common-crawlers
   listing and the spec's `googlebot-news` example (own group wins; never a merge). Costs: new binding
   code; the map is data copied from a Google page and must be versioned on the contract and
   re-checked; the own-group-wins precedence is `[inferred]` beyond the one example; the "Otherbot
   (news)" conflict stays open. Feeding the map to the multi-agent `AllowedByRobots` instead is
   cheaper but wrong: it merges the two groups by longest match, against "Only one group is valid".
   The same opt-in could route the AdsBot family through `disallow_ignore_global()`.
2. **Leave it to the caller**: no code; the docs say the matcher reads one token, and a caller who
   wants Googlebot-Image's documented behavior makes the second call with `Googlebot` itself when the
   first finds no group. Every caller re-implements the map, and the binding does not expose whether
   a specific group was seen (`ever_seen_specific_agent()` is not called from R; `decision_source =
   default_allow` covers both "own group, no rule matched" and "no group, no `*` rule matched"), so
   the caller has to scan the file's `User-agent` lines itself.
3. **Document only**: add the missing "no parent-token fallback" sentence to the
   `allowed_by_robots_text()` roxygen and point here. No behavior change; the divergence stays.

Recommended: 3 now, plus 1 as an opt-in if the maintainer wants crawler-level answers. The default
must not change silently: results for the seven two-token crawlers would move from `*` to the parent
group. Option 1 changes matcher behavior and the published contract under the opt-in, and needs a
decision issue first.

### 5b. Google fidelity audit (ROBO-deehqhlc)

**Method.** The reference is the pristine upstream google/robotstxt at
`22b355ff855419e6a3ff8ff09c0ad7fdb17116f9`, the SHA the vendored matcher pins: a maintainer-only command-line tool
calls `RobotsMatcher::OneAgentAllowedByRobots()` on the raw body bytes and reports the decision and
`matching_line()`. The same body, token and URL go to each robotstxtr Google path:
`robots_evaluate_text_v1()` with the `google` backend under every ruleset (`google`, `rfc9309`,
`assumed_rfc9309`, `bing`, `yandex`: each reads a supplied body as `use_rules` at any size, so every
row that passes input screening reaches the matcher and equals the `google` row, so the window bodies run
under `google` only); `allowed_by_robots_text()`; and `allowed_by_robots_url()` and `robots_evaluate_url_v1()`
(`google`/`google`), which take no body argument, so the body is served at the ssrfr boundary
(`tests/testthat/helper-fake-ssrfr.R`), with no network. The decision and the matched line are
compared. The inputs are synthesized: empty-value rules; the window (a rule after byte 512,000, a
line across it, a line whose line feed is byte 512,000 or 512,001, a rule past the 524,288-byte fetch cut);
URL targets (query, fragment, empty path, bare origin, port, `%2F`, escapes in both cases, raw and
escaped non-ASCII, `;` parameters); `*` and `$`; tokens (case, `Googlebot-Image` and `Googlebot-News`
beside a `Googlebot` group, a caller token with a version, an unknown token, file tokens with a
version, repeated, shared and split groups, a rule before any group); CRLF, lone CR, mixed endings,
a BOM; invalid UTF-8 in a rule and in a `User-agent` value; lines past the upstream 16,663-byte line
buffer; the typos upstream accepts; empty, scheme-less and `ftp:` URLs and an empty token; a NUL byte
before a key and inside a rule value.
Fixtures and recorded reference answers:
`tests/testthat/fixtures/google-fidelity-deehqhlc/cases.R`; pins:
`tests/testthat/test-google-fidelity-deehqhlc.R`; the differential, which re-derives the answers from
the binary: `dev/google-fidelity/differential.R`.

Every path agrees with the reference on decision and line, outside these classes:

| # | Class | Fixture | Reference | robotstxtr | Verdict |
|---|---|---|---|---|---|
| 1 | an `Allow`/`Disallow` with an empty value (also `Disallow: # comment`) matches at priority 0 | `User-agent: FooBot` / `Disallow:`, URL `/x` | allowed, line 2 | allowed, `default_allow`, no line, type `none` (all paths) | DELIBERATE: PRD §6.6 match-metadata rules ("an empty path is ignored", restated as `default_allow`), `normalize_ignored_empty_path()` for the legacy paths; `match_google_v1()` copied it into v1 in `af141e7`. Documented for v1 in `design/engine-contract-v1.md` (ROBO-dhwinnii). The Yandex backend reports an empty `Disallow` as `effective_empty_disallow` with its line, and an empty `Allow` as `default_allow` with no line, as here |
| 2 | the 512,000-byte window (v1 paths) | a rule starting at byte 520,001; `Disallow: /private-drafts/` across byte 512,000 | disallowed, line 3 (no window) | allowed, `default_allow` | DELIBERATE: §7, the window `[documented]`, the cut line dropped `[application_choice]` (ROBO-phfbpfiy) |
| 3 | the `max_bytes` cut (`allowed_by_robots_url()`) | a rule starting at byte 530,001 | disallowed, line 3 | allowed, `default_allow`, `body_truncated` | DELIBERATE: `allowed_by_robots_url()` `max_bytes` (524,288 by default; complete lines, ROBO-ldpahknv); §9 delta (c) |
| 4 | input screening | URL `""`, token `""`; on the URL paths also `example.com/private`, `ftp://example.com/private` | a decision (`""` is path `/`; `""` as agent reads `*`) | no decision, `input_unknown` / `input_invalid` | DELIBERATE: PRD §6.6 input rules; the roxygen of `allowed_by_robots_text()` and `allowed_by_robots_url()` (HTTP(S) only) |
| 5 | a NUL byte in a fetched body: upstream parses each line as a NUL-terminated C string, so the line ends at its first NUL; robotstxtr removes the NUL and reads the rest | `User-agent: *` / `\0Disallow: /x`, URL `/x`; `User-agent: *` / `Disallow: /a\0b`, URLs `/a` and `/ac` (`/ab` agrees) | `/x` allowed, no line (an empty line); `/a`, `/ac` disallowed, line 2 (the rule `/a`) | `/x` disallowed, line 2; `/a`, `/ac` allowed, `default_allow` (the rule `/ab`) | DELIBERATE: PRD §6.6, acquired bytes carrying a NUL (every NUL removed, the document never truncated at one: a NUL inside a value included); `R/body-decode.R` (ROBO-hcqrzikz) |

Classes 2 and 3 split the entry points. `allowed_by_robots_text()` has no window, so it agrees with
the reference on any over-window body. `allowed_by_robots_url()` reads a fetched body up to its
`max_bytes` cut (524,288 by default): it agrees with the reference on a rule between bytes 512,000
and the cut, which the v1 paths do not read, and not on a rule past the cut (class 3). The v1 paths
follow Google's documented 512,000-byte limit.

A private corpus run of the `google`/`google` v1 path against the same reference found class 1 and
no decision difference.

### 5c. The aipref AI-training policy token (ROBO-kzyfejcv; validator only)

draft-kelley-aipref-training-preference-signal-00 is an individual Internet-Draft (dated 2026-10-30,
expires 2027-05-03; no formal IETF standing), so everything below may change with its next revision
(https://datatracker.ietf.org/doc/draft-kelley-aipref-training-preference-signal/). It states an
AI-training preference with an ordinary group keyed by the policy token `__usage_ai-training`, and
"introduces no new directive names and no new grammar", leaving RFC 9309's path language,
precedence and group structure unchanged (abstract, §1): a disallowed path is a preference against
training on it, an allowed path one in favor, and no such group means no preference. Two rules
differ from crawler group selection: a `User-agent: *` group must not be read as matching the
token, and the token matches exactly, apart from case (§4.1, §4.2). A group may name several
policy tokens, and policy tokens and other product tokens may be mixed in a group (§4.1). The
token says nothing about crawling (§4.4). Which crawler operators read it, and from when, is the
dated vendor record in §7a; this section repeats none of it.

No matcher or decision changes here. A token group stacked onto `*` gives its rules to every
crawler on every row of `design/engine-disagreements.md` class 1b when only blank lines come
between. With a directive between (`Crawl-delay`, `Sitemap` or an unknown field such as
`Content-Signal`, class 1), the `google_yandex`, `yandex` and `google_bingbot` rows still stack
and the `bing` row ends the run there. The validator (`robots_validate_text()`,
`robots_validate_url()`) reads the draft as follows:

| Code | Severity | When |
|---|---|---|
| `ai_training_preference` | info | A User-agent value is the token whole, ASCII case aside. One per group, on its first such line; the message lists the group's own rules (an empty Disallow as no restriction), and never merges in `*` or names another group. |
| `ai_training_token_near_miss` | warning | The value's leading `[A-Za-z_-]` run, with `_` and `-` removed and ASCII-lowercased, is `usageaitraining`, but the value is not the token (`__usage_ai_training`, `usage_ai-training`, `__usage-ai-training`, `__usage_ai-training/1.0`). For a suffix the message adds that Google's matcher still reads the token. |
| `ai_training_group_extra_line` | warning | A directive other than Allow, Disallow and User-agent, and not file-level (Sitemap, Host, Clean-param), in a group that names only the token, such as `Crawl-delay`: before the group's last rule, or anywhere when the group is the file's last. |
| `ai_training_token_stacked` | warning | A policy-token User-agent line (a `__usage_` key, the token or a near miss) shares a group with `*`, or with a crawler or another policy token and a directive line sits between them. The message says Bing joins the lines only when nothing but blank or comment lines comes between, which a `*` line alone can satisfy. |

Blank and comment lines are RFC 9309 emptylines, and the draft allows mixed groups, so
consecutive or comment-headed User-agent lines naming crawlers and the token stay silent. The
token and its near misses are one class, so a repeat of the token across a directive is not
stacking. A line after the last rule of a token group that another group follows may head that
group (a `Content-Signal` line just before `User-agent: *`), so `ai_training_group_extra_line`
leaves it out; a `Crawl-delay` there is missed too. In the file's last group nothing follows, so
such a line is reported. A User-agent line naming no crawler (empty, or led by a byte outside
`[A-Za-z_-]`) is never named by `ai_training_token_stacked` and does not make a token group mixed,
and neither does a value Google reads as the token (`__usage_ai-training/1.0`). On a body cut at
`max_bytes`, the last group read is not taken as the file's last. A near miss in a group that also
names the token says the token's line carries the preference. Every agent name in these messages is
elided past 64 characters (its first 60 and `...`), so message size stays linear in the rows.

The token is never reported as `wildcard_rules_not_inherited`, and neither is a value Google's
matcher reads as the token. All four codes are skipped for a body holding a NUL byte, like the
other group checks, and kept for a body cut at `max_bytes`, where the info says lines past the cut
were not read; a User-agent line past the cut could still join the last group. A
`DisallowAITraining:`-style key is a different mistake, read by Google as `Disallow` for the whole
group: `accepted_directive_prefix` (ROBO-xglcoagv) reports it, and its message points to the
policy token group. Out of scope until the draft stabilizes: a public API answering "is training
on this path opted out?". Pinned by `tests/testthat/test-aipref-policy-token-kzyfejcv.R`.

## 6. Matcher capability availability

`robots_policy_ruleset` (§4) is pure data and always available. `matcher_backend` is separate:

| `matcher_backend` | availability | token_policy |
|---|---|---|
| `google` | **available** — vendored `robotstxt-cpp` (Google's production parser; intentionally non-strict-RFC, `src/robots.h:23-25`; PRD forbids RFC-correcting it, `design/PRD.md:75-76,202`). | `arbitrary_valid` — accepts any valid Google robots product token for group selection; the result is Google parsing/matching semantics for that token, never a prediction of the named crawler. |
| `rfc9309` | **capability_unavailable** — no strict-RFC matcher built; `google/robotstxt` is NOT an RFC reference impl and cannot back it. | `rfc9309` — RFC 9309 behavior only, and only under this backend. |
| `yandex` | **available** — as of schema revision `2026-07-18.2`; vendored, SHA-pinned `robotstxtyandex` payload bounded to profile `yandex-0.1.0` (crawlers `Yandex` + `YandexAdditionalBot`). Independent, unofficial compatibility profile; no production-crawler parity claim. Yandex Allow/Disallow **precedence is equivalent to longest-match**, so the distinct matcher is justified by group-selection/parsing/Clean-param, not precedence. | `bounded_profiles` — bounded to supported Yandex vendor profiles (`yandex-0.1.0`) only; never generalized to arbitrary tokens or backed by Google matching. |
| `bing` | **available** — since the atomic v2 activation (ROBO-qetsyvwv, `robots_engine_contract_v2()`); vendored, SHA-pinned `robotstxtbing` payload bounded to profiles `bingbot-2026-07-23.1` and `adidxbot-2026-07-23.1` (product tokens `bingbot` + `adidxbot`). Independent, unofficial compatibility profile, not affiliated with Microsoft; no production-crawler parity claim. | `bounded_profiles` — bounded to supported Bing vendor profiles only; never generalized to arbitrary tokens or backed by Google matching. |

Requesting matching/group-selection for an unavailable backend → `matcher_status =
capability_unavailable`; the §4 policy result still resolves independently (ADR-009 §2/§4).
This token/semantics boundary is published as data on
`robots_engine_contract_v1()$matcher_capability` (keyed per backend with
`token_policy`, `matcher_semantics`, and a `note`).

<a id="policy-matcher-limits"></a>

## 7. Current policy/matcher limits (executable this release)

These byte-level limits affect the current policy/matcher decision (not future-validator material):
- `google`: **500 KiB**; content after the max is ignored and the **prefix is parsed** `[documented]`:
  the window is the first 512,000 bytes `[documented]`. Google does not document how it parses a line
  the window or a cut at `max_bytes` splits; robotstxtr drops it and matches up to the last complete
  line inside the window `[application_choice]` (the cautious reading, ROBO-ldpahknv, ROBO-phfbpfiy).
- `rfc9309`: **≥500 KiB minimum parse capacity** — a floor, NOT a maximum or truncation mandate
  `[documented]`.
- `yandex`: **500 KB** file (read as 500,000 bytes; the unit is not stated `[documentation_gap]`); a
  file exceeding it fails the requirements → open fallback (allow_all) `[documented]`.
- `bing`: no size limit found `[documentation_gap]`.
- **Over-limit body**: Google parses the ≤-limit prefix. robotstxtr retains the ≤-limit prefix of a 2xx
  (ROBO-ldpahknv; `body_truncated = TRUE`, `termination_reason = ceiling`); the legacy path matches it.
  The v1 evidence records it as `incomplete`, and the ruleset decides what it means: `yandex` with
  `stored_bytes ≥ 512000` → `allow_all` `[documented]` (the file exceeds 500 KB under either reading of
  the unit; ROBO-arrtietl): a cut 200 takes the same rule and reason as a retained body over 500,000
  bytes, `yandex_file_over_500000_bytes`, and a cut non-200 2xx takes `non_200_allow_all` from §4, as
  its uncut form does; under sitemapr ADR-009 §3 as amended. `google` with the `google` matcher backend
  and `stored_bytes ≥ 512000` →
  the §4 cell of its uncut form, `use_rules` (`http_200_use_rules`, or `http_2xx_use_rules` for a non-200
  2xx) `[documented]` (the cut holds the whole window; ROBO-ptibdnvy), matched on the complete lines of
  its first 512,000 bytes with `matcher_body_truncated = TRUE`; under sitemapr ADR-011 §2. `yandex` and
  `google` below that size, `google` with any other matcher backend (the reading is the google
  matcher's), `rfc9309`, `assumed_rfc9309`, `bing` → `policy_status = not_evaluated`
  (`incomplete_evidence`). A 3xx, an unknown
  status or a status mismatch over the limit is `body_too_large`, nothing stored, `incomplete` under
  every ruleset. A 4xx/5xx over the limit is classified by its status (§4).

### 7a. Content-Signal and Content-Usage lines (ROBO-fqkgreev; pages read 2026-11-10)

Validator only: no matcher reads either line as a rule, and nothing here changes a decision (the Bing
`*`-run sealing at an unknown field is `design/engine-disagreements.md` row 1b). Both keys stay in
`validation_unsupported`, so they count in `unsupported_directives` and `recognized_directives`.

**Content-Signal** gets its own warning, `content_signal_directive`, instead of `unsupported_directive`,
whose "another crawler may use it" nothing documented supports. The message carries no date; this
section is the dated statement behind it.

- The syntax comes from draft-romm-aipref-contentsignals-00 (Cloudflare authors), an individual
  Internet-Draft: last revision 2025-10-01, expired 2026-04-04 (six months on), "Expired & archived"
  on the IETF datatracker
  (https://datatracker.ietf.org/doc/draft-romm-aipref-contentsignals/).
- The message's alternative is draft-kelley-aipref-training-preference-signal-00, an active individual
  draft (dated 2026-10-30, expires 2027-05-03; no formal IETF standing), which defines a
  `User-Agent: __usage_ai-training` group
  (https://datatracker.ietf.org/doc/draft-kelley-aipref-training-preference-signal/).
- As of 2026-11-10, no crawler operator below documents honoring Content-Signal `[documented]` (by
  absence on each page):

| Operator | Pages read 2026-11-10 | Finding |
|---|---|---|
| Google | https://developers.google.com/crawling/docs/robots-txt/robots-txt-spec ; https://developers.google.com/crawling/docs/crawlers-fetchers/google-common-crawlers ; https://www.google.com/robots.txt | No Content-Signal or Content-Usage. The spec: "Rules other than `allow`, `disallow`, and `user-agent` are ignored by the robots.txt parser." The crawlers page says Google intends to support the aipref training preference token `__usage_ai-training` in early 2027. |
| Bing | https://blogs.bing.com/search/2026/10/your-content-your-choice-clearer-preferences-for-training-and-grounding/ (2026-10-30) ; https://blogs.bing.com/webmaster/september-2023/Announcing-new-options-for-webmasters-to-control-usage-of-their-content-in-Bing-Chat ; https://www.bing.com/webmasters/help/how-to-create-a-robots-txt-file-cb7c31ec ; https://www.bing.com/robots.txt | No Content-Signal or Content-Usage on any of them. The 2026-10-30 post introduces a robots.txt AI Training preference with `User-Agent: __usage_ai-training` groups: "Starting February 1, 2027, Microsoft will honor the new preferences as it crawls". It says "These preferences will replace existing Microsoft preferences NoArchive and NoCache for training and grounding", and after 2027-03-01 "`NoArchive` and `NoCache` will no longer be read as a preference for training or grounding". The 2023 post's `nocache`/`noarchive` meta tags are the controls until then. The help page renders as a title only for the reader `[documentation_gap]`. |
| OpenAI | https://developers.openai.com/api/docs/bots (redirected from platform.openai.com/docs/bots) ; https://openai.com/robots.txt | No Content-Signal or Content-Usage; controls are robots.txt groups for GPTBot, OAI-SearchBot and ChatGPT-User. OpenAI's 2026-10-30 post https://openai.com/index/helping-websites-express-ai-training-preferences/ was not readable directly (HTTP 403 on 2026-11-10); it is cited by its URL only, and its content is not recorded here. |
| Anthropic | https://support.claude.com/en/articles/8896518-does-anthropic-crawl-data-from-the-web-and-how-can-site-owners-block-the-crawler ; https://www.anthropic.com/robots.txt | No Content-Signal or Content-Usage. "As of October 30, 2026, Anthropic has begun recognizing a machine-readable signal" for a "no AI training" preference, linking draft-kelley-aipref-training-preference-signal, and is "rolling this out across all of our services over time". |
| Apple | https://support.apple.com/en-us/119829 ; https://www.apple.com/robots.txt | No Content-Signal or Content-Usage; controls are robots.txt (Applebot, Applebot-Extended), robots meta tags and `X-Robots-Tag`. |
| Cloudflare | https://developers.cloudflare.com/bots/additional-configurations/managed-robots-txt/ ; https://contentsignals.org/ ; https://www.cloudflare.com/robots.txt | Defines Content Signals and publishes a `Content-Signal` line in its own robots.txt, but names no crawler that honors them: "`robots.txt` compliance is voluntary." |

Re-read these pages when the draft or a vendor page changes; a vendor that documents honoring
Content-Signal makes the message wrong.

**Content-Usage** (the aipref vocabulary syntax) keeps the generic `unsupported_directive`: the ticket's
default, kept unless a crawler documents it. None of the pages above does. Pinned by
`tests/testthat/test-content-signal-fqkgreev.R`.

## 8. Future-validator reference (NOT executed this release)

For the eventual validator (ADR-009 §8), not executable now: Yandex 2048 rules / 1024 chars per rule /
500 per Clean-param `[documented]`, with per-violation scope (ignore line / reject section / reject
file / open) `[documentation_gap]`; Google constrained typo tolerance `[documented]`; Sitemap as an
optional other record under RFC `[documented]`; character restrictions vs file byte encoding (Yandex
prohibits Cyrillic, Punycode/%-encoding `[documented]`; Yandex UTF-8/BOM `[documentation_gap]`).

## 9. Current-code delta (informative)

`R/fetch-policy.R::classify_status` + `R/allowed_by_robots_url.R:193`: 404/410 → `missing` → allow
(TRUE); all 2xx except 206 → `fetched` (matcher decides); 206 → `partial_response`
(`R/fetch-policy.R:91`); 1xx and generic 4xx/5xx → `http_error`. `allowed` defaults to `NA`
(`R/allowed_by_robots_url.R:176`) and only `missing`/`fetched` leave it, so every other outcome
resolves to `NA`. Deltas vs this spec: (a) generic 4xx → `NA` diverges from documented
`google`/`yandex` (allow_all); (b) 1xx → `http_error` conflates protocol with transport
(`R/fetch-policy.R:88`); (c) oversized body discarded, not retained-prefix: closed for the legacy path by ROBO-ldpahknv,
which retains and matches a 2xx prefix; the v1 ruleset reading is §7's (ADR 0001 slices 8 and 9). These are implementation slices, filed only after this
spec is accepted; ADR-009 §3 (safety precedence) and §6 (findings encoding) govern how they surface.

## 10. Sources (self-contained; per-section)

- **RFC 9309** — https://www.rfc-editor.org/rfc/rfc9309.html : §2.2.1 (user-agent selection), §2.2.2–3
  (matching), §2.3.1.2 (redirects), §2.3.1.3 (4xx/unavailable = MAY), §2.3.1.4 + §2.4 (5xx/unreachable
  + caching), §2.5 (≥500 KiB min capacity).
- **Google** — https://developers.google.com/crawling/docs/robots-txt/robots-txt-spec : status
  handling (2xx/3xx/4xx-except-429/5xx), file format (500 KiB prefix; BOM), URL matching & precedence,
  order of precedence for user agents (read again 2026-11-09 for §5a).
- **Google crawlers (§5a, all read 2026-11-09)** —
  https://developers.google.com/crawling/docs/crawlers-fetchers/overview-google-crawlers (no fallback
  rule stated);
  https://developers.google.com/crawling/docs/crawlers-fetchers/google-common-crawlers (the
  "User-agent token in robots.txt" cells, read from the page's HTML; "match only one crawler token");
  https://developers.google.com/crawling/docs/crawlers-fetchers/google-special-case-crawlers (`*`
  ignored by AdsBot family; retired Favicon and Mobile-Apps rows);
  https://developers.google.com/crawling/docs/crawlers-fetchers/google-user-triggered-fetchers
  (fetchers ignore robots.txt). Vendored code: `src/robots.h` / `src/robots.cc`
  (`AllowedByRobots`, `OneAgentAllowedByRobots`, `HandleUserAgent`, `ExtractUserAgent`, `disallow`,
  `disallow_ignore_global`, `ever_seen_specific_agent`),
  `src/matcher_binding.cpp`.
- **Yandex** —
  https://yandex.com/support/webmaster/en/controlling-robot/robots-txt (200 required, cross-site
  redirect, open fallback, 500 KB, Cyrillic, case);
  https://yandex.com/support/webmaster/en/robot-workings/allow-disallow (wildcards/precedence);
  https://yandex.com/support/webmaster/en/robot-workings/user-agent (group selection);
  https://yandex.com/support/webmaster/en/robot-workings/clean-param;
  https://yandex.com/support/webmaster/en/robot-workings/crawl-delay (ignored 2018-02-22);
  https://webmaster.yandex.ru/blog/301-y-redirekt-polnostyu-zamenil-direktivu-host (Host 2018-03-20);
  https://yandex.com/support/webmaster/en/error-dictionary/robots-txt (limits);
  https://yandex.com/support/webmaster/en/error-dictionary/http-codes (429 ignores Retry-After).
- **Bing** — https://www.bing.com/webmasters/help/how-to-create-a-robots-txt-file-cb7c31ec (directives,
  crawl-delay, encoding, cache);
  https://blogs.bing.com/webmaster/May-2012/To-crawl-or-not-to-crawl%2C-that-is-BingBot-s-questi
  (user-agent priority). No current Bing source publishes a robots status/redirect/network table.
- **Local code** — `src/robots.h:19-25` (non-strict-RFC), `design/PRD.md:74-76,199-206` (matcher
  fidelity/non-goals) + §13 (Amendment A, version scope), `R/fetch-policy.R:88,91,202` (1xx, 206,
  oversized), `R/allowed_by_robots_url.R:176,193` (allowed default `NA`; `missing` → TRUE).
- **Fetch rules (redirect count, size, downgrade, per engine)** —
  `design/engine-fetch-rules-sources.md` (read 2026-11-05). **Safety level** —
  `design/adr/0001-safety-level-vs-engine-ruleset.md`; sitemapr
  `docs/decisions/ADR-003-network-safety-policy.md` (the guard) and `ADR-009` §3 as amended
  (precedence).
