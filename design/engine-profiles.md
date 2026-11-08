# robotstxtr engine profiles — robots.txt status-policy, matchers, limits

- Status: Accepted (governed by sitemapr ADR-009 "Per-engine validation profiles")
- Date: 2026-07-16 (accepted 2026-07-17)
- PRD scope: the version-scope amendment this requires is recorded in `design/PRD.md`
  §13 (Amendment A) — ruleset-aware, versioned entry points added alongside the pinned
  v1 surface (PRD §3 keeps "not a validator"; this doc adds no validator scope).
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
- **Content / grammar validation** (unsupported/typo/unknown directives, the parsing-error catalog).
  robotstxtr stays a matcher/policy package (PRD §3; ADR-009 §8). §8 rule-count/line-length/typo items
  are future-validator reference only; nothing there executes.
- **Bing robots policy** — no current Bing primary source publishes a robots.txt status/redirect/
  network table or an RFC-9309 conformance claim. Every Bing status/redirect cell is
  `documentation_gap`; not synthesized from RFC. A product may opt into an explicit `assumed_rfc9309`
  application policy, never presented as `bing`.
- **Crawler lifecycle emulation** (cache TTL, 30-day grace, last-known-good). Stateless; lifecycle-
  dependent cells resolve to `context_required` (§4).

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
3xx over it is `body_too_large`; a 4xx/5xx keeps its status outcome. A set `safety_block_reason` means
`evidence_status = safety_refused`, except an address-class code under `safety_level = crawler`, which
means `unreachable_local` (§3a). `fetch_outcome` stays `ssrf_blocked` at both levels.

**`evidence_status` (exhaustive):**

| `evidence_status` | Trigger | → decision path |
|---|---|---|
| `usable_body` | 2xx (excl. 206) within ceiling (`source_kind=fetched`), OR a supplied/local body (`source_kind ∈ {supplied, local}`) | fetched → §4 by `final_http_status`; supplied/local → `use_rules` `[application_choice]`, then §6 |
| `partial` | 206 | policy resolves per §4, but body unusable → `matcher_status = not_evaluated` (ADR-009 §2 row) |
| `incomplete` | body over ceiling or `termination_reason ∈ {deadline, ceiling}` | never a policy verdict; `policy_status = not_evaluated` |
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

`crawler` is in the published value set but refused as a call-level error until it lands
(ROBO-lwdxzdhw, ROBO-jqwukcog), and `fetch_allow_ranges` is recorded as empty until ROBO-bamcjvwn.

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
  with global. (Google robots.txt spec, "Order of precedence for user agents")
- `yandex` — specific Yandex robot entry > `Yandex` > `*`. (Yandex, User-agent)
- `bing` — `bingbot` > `msnbot` > `*`, discarding others. (Bing, "To crawl or not to crawl", 2012)

## 6. Matcher capability availability

`robots_policy_ruleset` (§4) is pure data and always available. `matcher_backend` is separate:

| `matcher_backend` | availability | token_policy |
|---|---|---|
| `google` | **available** — vendored `robotstxt-cpp` (Google's production parser; intentionally non-strict-RFC, `src/robots.h:23-25`; PRD forbids RFC-correcting it, `design/PRD.md:75-76,202`). | `arbitrary_valid` — accepts any valid Google robots product token for group selection; the result is Google parsing/matching semantics for that token, never a prediction of the named crawler. |
| `rfc9309` | **capability_unavailable** — no strict-RFC matcher built; `google/robotstxt` is NOT an RFC reference impl and cannot back it. | `rfc9309` — RFC 9309 behavior only, and only under this backend. |
| `yandex` | **available** — as of schema revision `2026-07-18.2`; vendored, SHA-pinned `robotstxtyandex` payload bounded to profile `yandex-0.1.0` (crawlers `Yandex` + `YandexAdditionalBot`). Independent, unofficial compatibility profile; no production-crawler parity claim. Yandex Allow/Disallow **precedence is equivalent to longest-match**, so the distinct matcher is justified by group-selection/parsing/Clean-param, not precedence. | `bounded_profiles` — bounded to supported Yandex vendor profiles (`yandex-0.1.0`) only; never generalized to arbitrary tokens or backed by Google matching. |
| `bing` | **capability_unavailable** — gated on the same engine-profile activation gate; no Bing matcher built. | `bounded_profiles` — bounded to supported Bing vendor profiles only; never generalized to arbitrary tokens or backed by Google matching. |

Requesting matching/group-selection for an unavailable backend → `matcher_status =
capability_unavailable`; the §4 policy result still resolves independently (ADR-009 §2/§4).
This token/semantics boundary is published as data on
`robots_engine_contract_v1()$matcher_capability` (keyed per backend with
`token_policy`, `matcher_semantics`, and a `note`).

## 7. Current policy/matcher limits (executable this release)

These byte-level limits affect the current policy/matcher decision (not future-validator material):
- `google`: **500 KiB**; content after the max is ignored and the **prefix is parsed** `[documented]`.
- `rfc9309`: **≥500 KiB minimum parse capacity** — a floor, NOT a maximum or truncation mandate
  `[documented]`.
- `yandex`: **500 KB** file; a file exceeding it fails the requirements → open fallback (allow_all)
  `[documented]`.
- `bing`: no size limit found `[documentation_gap]`.
- **Over-limit body**: Google parses the ≤-limit prefix. robotstxtr retains the ≤-limit prefix of a 2xx
  (ROBO-ldpahknv); the legacy path matches it, the v1 evidence records it as incomplete. A 3xx over the
  limit is `body_too_large`, and a 4xx/5xx over it is classified by its status (§4).

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
which retains and matches a 2xx prefix; the v1 evidence keeps it `incomplete` (§7). These are implementation slices, filed only after this
spec is accepted; ADR-009 §3 (safety precedence) and §6 (findings encoding) govern how they surface.

## 10. Sources (self-contained; per-section)

- **RFC 9309** — https://www.rfc-editor.org/rfc/rfc9309.html : §2.2.1 (user-agent selection), §2.2.2–3
  (matching), §2.3.1.2 (redirects), §2.3.1.3 (4xx/unavailable = MAY), §2.3.1.4 + §2.4 (5xx/unreachable
  + caching), §2.5 (≥500 KiB min capacity).
- **Google** — https://developers.google.com/crawling/docs/robots-txt/robots-txt-spec : status
  handling (2xx/3xx/4xx-except-429/5xx), file format (500 KiB prefix; BOM), URL matching & precedence,
  order of precedence for user agents.
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
