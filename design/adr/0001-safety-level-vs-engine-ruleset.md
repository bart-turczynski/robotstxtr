---
status: accepted
date: 2026-11-05
accepted: 2026-11-05
tracking: ROBO-xdlzicrq
amended: 2026-11-09 (ROBO-phfbpfiy, Google's window is 512,000 bytes, not 524,288); 2026-11-11 (ROBO-aoslfvnx, 6to4, Teredo and ISATAP leave the address class)
---

# ADR 0001: The safety level and the engine ruleset are separate settings

Replaces the `[application_choice: local safety dominates]` cell in
[`design/engine-profiles.md`](../engine-profiles.md) §3 and its `safety_refused` row in §2,
within robotstxtr's scope. The sources behind every engine value used here are in
[`design/engine-fetch-rules-sources.md`](../engine-fetch-rules-sources.md).

## Context

### What "local safety dominates" does today

robotstxtr acquires `/robots.txt` under one safety policy, whatever ruleset the caller picks
(`acquire_policy()` in `R/acquire.R`). Any refusal it makes becomes
`evidence_status = safety_refused` (`source_evidence_status_v1()` in `R/engine-contract-v1.R`
returns it whenever `safety_block_reason` is set). That status never yields a policy verdict.
So, for every ruleset:

- **An `https` → `http` redirect is always refused** (`safety_block_reason = https_downgrade`).
  ssrfr refuses it whenever the previous hop was `https`: `parse_hop_policy()` in ssrfr's
  `R/parse.R` has no policy setting that permits it. No engine documents refusing one. RFC 9309
  §2.3.1.2 places no scheme condition on redirects, Google follows "at least five redirect hops
  as defined by RFC 1945", and Yandex follows redirects to another site (research record,
  summary table). A site that redirects its `https` robots.txt to `http` gets an answer from
  every engine that documents redirect handling (`rfc9309`, `google`, `yandex`) and none from
  robotstxtr. Bing's redirect handling is a `documentation_gap`.
- **Private, loopback, link-local and cloud-metadata addresses are refused.** That is right
  for a server fetching URLs it does not trust, and the default stays. The only way to reopen
  them is the deprecated `ssrf_guard = FALSE`. ssrfr has no off switch, so that argument
  already maps onto a permissive policy (`allow_ranges = c("0.0.0.0/0", "::/0")` plus ssrfr's
  metadata host names) and warns (`warn_ssrf_guard_deprecated()` in `R/fetch-policy.R`).
- The evidence frame records the policy in two columns. `ssrf_guard` is the argument as
  passed. `https_downgrade_guard` is `TRUE` on every fetched row
  (`source_results_to_evidence_v1()`) and `NA` on a supplied-body row and when no acquisition
  was configured (timeout `NA`) (`R/engine-contract-v1.R`).

### Where "ADR-003" lives

engine-profiles.md cites "ADR-003" for the guard (§2 `safety_refused` row, §3 first bullet)
without naming a repository. It is **sitemapr's** `docs/decisions/ADR-003-network-safety-policy.md`
("v1 network safety policy", accepted 2026-06-28, amended through 2026-10-23). robotstxtr has
never had an ADR file: `git log --all -- '*adr*' '*ADR*'` is empty. The string first appears in
`c913e88` (`R/ssrf.R`, "Ported from sitemapr's ADR-003 structural SSRF guard", 2026-07-15) and
in `28618d7`, which landed engine-profiles.md. Two related records:

- sitemapr `ADR-009-per-engine-validation-profiles.md` §3, "Safety precedence: safety and
  resource limits are never crawler policy". This is the rule engine-profiles.md implements,
  and that document is "governed by sitemapr ADR-009" (its header). ADR-009 §3, not ADR-003,
  puts the HTTPS → HTTP downgrade among the `safety_refused` causes. sitemapr ADR-003 does not
  decide the downgrade refusal. It mentions the downgrade only in its §3 findings mapping (an
  SSRF / scheme / downgrade refusal → `PAGE_SSRF_BLOCKED`, ADR-010 §3), which takes the
  refusal as given. ADR-009 §3 also covers resource limits: "body ceiling reached" →
  `incomplete`, and "Neither is ever `allow_all` / `disallow_all`". Its last sentence reads
  "per-engine parse limits and excess-content behavior belong to the interpretation layer,
  not the fetch layer".
- ssrfr `design/adr/0001-network-safety-policy.md` §4, which makes `downgrade` a refusal cause
  "refused by default". Its spec (`design/specs/ssrfr-v1.md`, vocabulary table) adds that "the
  refusal protects response integrity, not credentials", since the hop is cross-origin and
  ssrfr already drops credentials there.

Other repositories' ADR-0003 files (rurl, seor, ssrfr, cbb, agent-view, yandex-webmaster,
sitemap-validator) are on unrelated subjects.

### Why one setting cannot serve both callers

robotstxtr has two kinds of caller. One is a **server-side service** that evaluates URLs
someone else supplied, for which every refusal is the point. The other is an **analyst or
crawler emulator** that asks "what would Google conclude about this site?". For that caller, a
refusal no crawler would make is a wrong answer, presented as if it were a safety outcome.
Today the second caller's only lever is `ssrf_guard = FALSE`. It does the opposite of what that
caller needs: it opens internal networks, which no public crawler can reach, and leaves the
downgrade refused, which every crawler follows.

The two questions are independent:

- **What does this outcome mean?** A redirect chain over budget, a status code, a file over the
  limit. This is an engine fact, and the ruleset owns it.
- **What may this process do on the network?** Follow a downgrade, connect to this address.
  This is a property of where robotstxtr runs, and it has nothing to do with which engine is
  being modeled.

## Decision

### 1. Two settings

Every fetching entry point (`robots_fetch()`, `allowed_by_robots_url()`,
`robots_validate_url()`, `robots_evaluate_url_v1()`) gains `safety_level`, one of `"strict"`
(the default) and `"crawler"`. It is independent of `robots_policy_ruleset`. Any ruleset can be
combined with either level, and neither setting defaults from the other.

- **The engine ruleset** decides what an outcome *means*: the policy for each status, for
  `over_budget`, and for a file over the engine's size limit. It never changes what the fetch
  does.
- **The safety level** decides what the fetch *may do*: which redirects it follows and which
  addresses it connects to. It never changes what an outcome means.

### 2. `strict`: today's behavior, unchanged

`strict` is the default and is byte-for-byte today's acquisition. An `https` → `http` redirect
is refused as `safety_refused` / `https_downgrade`. Every ssrfr refusal is `safety_refused`
with its `safety_block_reason`. It is meant for server-side use on URLs the process does not
trust. Under `strict`, sitemapr ADR-009 §3 holds unchanged.

### 3. `crawler`: what a public crawler experiences

- **Downgrades are followed.** An `https` → `http` redirect counts as an ordinary hop within the
  five-hop budget. The rest of the hop rules are unchanged: loop check, `Location` required,
  `http`/`https` targets only.
- **Internal addresses are still refused, and recorded as unreachable.** A target that is, or
  resolves to, an address-class refusal (`loopback`, `private`, `link-local`,
  `cloud-metadata`, `shared`, `unspecified`, `this-network`, `multicast`, `reserved`, and the
  IPv6 forms that embed one: `ipv4-mapped`, `ipv4-translated`, `ipv4-compatible`,
  `nat64`) is never dialed. As before, no packet leaves the machine. The L0
  record is unchanged from `strict`: `fetch_outcome = ssrf_blocked` and `safety_block_reason`
  set to the code. What changes is the `evidence_status` derived from it: a new value,
  **`unreachable_local`**, "not dialed: the address is internal, so a public crawler could not
  reach it either". It is neither `safety_refused` nor `transport_fail`.

  **Every `evidence_status` keeps one meaning at both levels.** `safety_refused` stays "refused
  for safety; whether a public crawler could reach the target is not known" and
  `transport_fail` stays "a connection was tried and failed";
  a row never carries `transport_fail` with a `safety_block_reason`. Today
  `source_evidence_status_v1()` tests `safety_block_reason` first and returns `safety_refused`
  whenever it is set. Under `crawler` that test becomes class-aware: an address-class code
  returns `unreachable_local`, a URL-shape or transition code `safety_refused`. The published invariant widens
  from "`safety_block_reason` set ⇒ `safety_refused`" to "`safety_block_reason` set ⇒
  `safety_refused` or `unreachable_local`", and `unreachable_local` occurs under `crawler` only.
  Under `strict` every row reads exactly as today. A consumer that wants "the crawler could not
  reach it" combines `unreachable_local` with `transport_fail`; the reverse split would not be
  possible from one merged value. (Maintainer, 2026-11-05: keep the finer value, aggregate
  later.)

  This is what a public crawler sees: it cannot route to your RFC 1918 network or your
  metadata endpoint, and the connection fails. The engine ruleset gives `unreachable_local` the
  meaning that engine gives an unreachable file: `context_required` for `rfc9309`, `google` and
  `assumed_rfc9309`, and `documentation_gap` for `yandex` and `bing` (the same cells as
  engine-profiles.md §4's network row and the `transport` rows of `engine_policy_table_v1()`,
  added as their own `unreachable_local` rows). Under today's tables, then, no address refusal
  becomes an allow or a deny under `crawler` either.
- **URL-shape refusals stay `safety_refused` at both levels.** These are `scheme` (and so
  `non_http_target`), `userinfo`, `port`, `parse`, `numeric-literal` and
  `malformed-address`. They are refusals of how the URL is spelled, not of where it points, and
  no engine documents a behavior for them. `host-denied` and `range-denied` are still not
  admitted (robotstxtr sets no deny rules).
- **6to4, Teredo and ISATAP refusals stay `safety_refused` at both levels.** ssrfr refuses
  every 2002::/16 (`6to4`) and 2001::/32 (`teredo`) address whatever IPv4 it wraps: raddr
  leaves their global reachability unknown, and no allow range reopens them. A refusal of
  `2002:808:808::1` or `2001::f7f7:f7f7` (8.8.8.8 inside each) is therefore no statement that
  the target is internal, and `unreachable_local` would be false. `isatap` is refused around a
  private IPv4 even under a global prefix (`2600::5efe:a00:1`, 10.0.0.1 inside), which is the
  ordinary RFC 5214 deployment: the site's ISATAP router routes that prefix publicly, so a
  public crawler can reach it, and the same code also covers a link-local ISATAP literal. The
  code alone cannot tell these apart. All three are refused for safety with reachability
  unknown, which is what `safety_refused` means. robotstxtr does not unwrap the IPv4 to tell
  the cases apart, because classifying addresses is ssrfr's job; so a 6to4 literal around
  loopback (`2002:7f00:1::1`) and a link-local ISATAP literal are `safety_refused` too.
  RFC 7526 §4 deprecates only anycast 6to4, so deprecation does not make such a target
  unreachable either. (Amended 2026-11-11, ROBO-aoslfvnx; slice 4 had classed all three as
  address codes.)

### 4. The hop budget stays one fetch setting

Every engine that documents a robots.txt redirect count documents five (research record).
Google's "up to 10 redirect hops" is for general crawling, and its own robots.txt page sends
readers to the five-hop rule. So the budget stays `acquire_redirect_limit = 5L` for every
ruleset and both levels, and stays an L0 fact (`redirect_limit` in the evidence). The ruleset
only interprets `over_budget`. Yandex's and Bing's counts are `documentation_gap`. They use
five as a labeled `application_choice` fallback, never reported as documented. What either
engine does past its last hop stays `documentation_gap`: it is to be measured with served test
files (ROBO-ogwchglq, parked), not inferred. robotstxtr does not search Bing's documentation
again at each release; its `bing` cells stay `documentation_gap` with `assumed_rfc9309` beside
them until that measurement.

### 5. Oversized files belong to the ruleset

What reaches the ruleset depends on the response (main at 9fa9937; ROBO-ldpahknv):

- **A 2xx over `max_bytes`** is kept as its first `max_bytes` bytes: ssrfr's `truncate_body`
  returns the prefix, and robotstxtr records `fetch_outcome = fetched`, `body_truncated = TRUE`,
  `stored_bytes = max_bytes`, ssrfr's `observed_bytes` and `termination_reason = ceiling`. The
  legacy path matches the prefix. The v1 evidence calls it `incomplete`, so every ruleset
  resolves it `not_evaluated` / `incomplete_evidence`.
- **A 3xx, an unknown status, or a 2xx whose status libcurl and the status line disagree on**
  over `max_bytes` is `body_too_large`, `termination_reason = ceiling`, with nothing stored.
  None of these is a robots.txt file whose size an engine rule speaks to, so it stays
  `incomplete` under every ruleset.
- **A 4xx or 5xx over `max_bytes`** is classified by its status (engine-profiles.md §4), as if
  the body had fit.

The cut 2xx stays an L0 fact. The ruleset decides what it means:

- **`yandex`:** when the stored prefix is at least **512,000 bytes**, the file exceeds Yandex's
  documented "500 KB" under either reading of the unit (500,000 or 512,000 bytes; the unit is a
  `documentation_gap`). Yandex treats a file that fails its requirements as "considered open",
  so the result is `allow_all` `[documented]`. The default `max_bytes`, 524,288, is above that
  threshold. Below it, the cut does not prove the file broke Yandex's limit, and the result
  stays `incomplete`.

  This uses the existing path rather than adding a second one. The Yandex branch of
  `resolve_policy_v1()` in `R/engine-contract-v1.R` already turns a retained body with
  `stored_bytes > 500000L` into `allow_all` / `yandex_file_over_500000_bytes` `[documented]`.
  A cut 2xx never reaches it today, because its `incomplete` evidence returns first. Slice 8
  lets the `yandex` ruleset take a cut 2xx with `stored_bytes ≥ 512000` past that return and
  into the same branch, with the same reason or a sibling recorded in the schema entry.
- **`google`:** Google parses the first 500 KiB (512,000 bytes) and ignores the rest
  `[documented]`. A cut 2xx with `stored_bytes ≥ 512000` holds Google's whole parse window, and
  `match_google_v1()` reads at most 512,000 bytes. So the `google` ruleset can resolve it
  `use_rules` on the prefix `[documented]`, matched as Google would up to its last complete
  line (a line the window cuts is dropped, as for any cut body). With a smaller prefix the
  window is not all there, and the result stays `incomplete`. This was out of reach when this
  ADR was first drafted (ssrfr kept no prefix). It is slice 9, separable from the rest.
- **`rfc9309`, `assumed_rfc9309`, `bing`:** RFC 9309 §2.5 sets a parse floor of 500 KiB, not a
  maximum, and no source says what happens beyond a limit. A verdict from the prefix would be
  one compliant crawler's reading, not the protocol's. The result stays `incomplete`.

  **Both readings conflict with sitemapr ADR-009 §3 as written.** That section, as amended by
  ADR-010 §2, maps a reached body ceiling to `incomplete`, or to `partial` for an intentional
  truncate-and-retain cap, and says "Neither is ever `allow_all` / `disallow_all`; a
  `use_rules` result over a `partial`/unusable body keeps `matcher_status = not_evaluated`".
  Its last sentence leaves "per-engine parse limits and excess-content behavior" to the
  interpretation layer, and a per-ruleset reading of a ceiling-cut body is exactly that. But the
  sentence before it rules both outcomes out explicitly, so it cannot be argued away. The
  sitemapr amendment (slice 6) therefore has to cover both points: the safety level, and a
  ruleset's documented meaning for a ceiling-cut body. Until that amendment is accepted, slices
  8 and 9 do not ship.

### 6. What replaces `ssrf_guard`

`ssrf_guard` is replaced by **`fetch_allow_ranges`**, a character vector of CIDR ranges
(default `character()`). It is passed to ssrfr's `allow_ranges` and applies at both safety
levels. A target inside a listed range is fetched. One outside it is handled as §2 and §3 say.

- `ssrf_guard = TRUE` (sitemapr passes it explicitly, in `R/robots-facts.R`) is accepted
  silently until the argument is removed.
- `ssrf_guard = FALSE` keeps warning and keeps today's behavior exactly: all ranges, plus
  ssrfr's metadata host names. The warning now names `fetch_allow_ranges` as the replacement.
- The argument is removed one minor release after `fetch_allow_ranges` ships, once sitemapr no
  longer passes it.
- **How the three combine while `ssrf_guard` exists.**
  - `ssrf_guard = FALSE` together with a non-empty `fetch_allow_ranges` is a call-level error
    (`robotstxtr_invalid_ssrf_guard`): the call gives two answers to the same question.
  - `ssrf_guard = FALSE` with `safety_level = "crawler"` is allowed. It wins over the
    address-class rule: every range is reopened and dialed, exactly as under `strict` today.
    It warns twice: the existing deprecation warning, and a second one saying that under
    `crawler` it makes internal addresses reachable, which no public crawler can do.
  - The downgrade rule follows `safety_level` alone. `ssrf_guard` has never touched the
    downgrade, and it still does not.
- `fetch_allow_ranges` never reopens the metadata host names. ssrfr's exact provider endpoints
  and the transition forms it refuses whatever the policy stay refused, as they are today.

Why an allow-list and not a third level:

- The legitimate use of `ssrf_guard = FALSE` is reaching one known internal host, for example
  an intranet staging site (sitemapr ADR-003 §1, "scanning a private staging server"). A range
  the caller names grants that and nothing else. A `trusted` level would reopen every range
  plus the metadata names. That is the blanket switch ssrfr ADR-002 moved away from when it let
  a caller's allow rule override a built-in refusal one dimension at a time.
- It is orthogonal to the two settings above. A crawler emulation of an intranet search
  appliance is `safety_level = "crawler"` with one allowed range, which no fixed level
  expresses.
- It is a thin passthrough of an ssrfr argument that already exists, so robotstxtr adds no
  guard logic of its own (ARCHITECTURE.md: ssrfr's guard runs only in `R/acquire.R`), with one
  narrow exception. ssrfr reopens a provider endpoint for an exact `/32` or `/128` allow entry,
  so robotstxtr refuses, at argument validation, any `fetch_allow_ranges` under which ssrfr
  would admit an address of its `provider_endpoints` vocabulary. Each entry is checked alone and
  then all of them together, and an empty vocabulary fails closed. robotstxtr only asks ssrfr
  whether an exception admits a protected endpoint; it classifies no address itself.
  (Amended 2026-11-11, ROBO-bamcjvwn; the rule is to move into ssrfr, SSRF-ntxhdswq, after
  which this check can go.)

### 7. The downgrade needs one ssrfr change

ssrfr refuses `https` → `http` whenever a hop is prepared with `from` an `https` binding, and its
policy has no setting to permit it. robotstxtr asks ssrfr for an opt-in policy flag, default
off, that permits the downgrade. ssrfr ADR 0001 §4 already says the refusal applies "by
default", and its spec says it protects response integrity, not credentials, which an opt-in
leaves intact for every other caller. `crawler` ships only after that flag exists. The
maintainer owns ssrfr and chose the flag (2026-11-05): the option belongs in the library that
owns the chain.

### 8. Published shape

- `robots_engine_contract_v1()` publishes the `safety_level` value set.
- The evidence frame gains `safety_level` (character) and `fetch_allow_ranges` (list column).
  On a fetched row, `https_downgrade_guard` becomes `safety_level == "strict"`. On a row with
  no acquisition (a supplied body, or timeout `NA`), it stays `NA`, as `safety_level` and
  `fetch_allow_ranges` will. `ssrf_guard` keeps recording the deprecated argument until it is
  removed.
- `evidence_status` gains `unreachable_local` (§3), and `engine_policy_table_v1()` gains an
  `unreachable_local` row per ruleset. The contract doc states the widened invariant and that
  `transport_fail` never carries a `safety_block_reason`.
- These need a new schema revision (engine-contract-v1.md, "Registering another matcher
  backend", step 5) and a contract-doc entry.
- **Legacy surfaces keep `ssrf_blocked`.** `fetch_outcome` (L0) stays `ssrf_blocked` for an
  address refusal under `crawler` (§3). So `robots_fetch()`, `allowed_by_robots_url()` and
  `as_legacy_robots_decisions_v1()` (which reads `legacy_fetch_outcome`) report
  `ssrf_blocked`, not `network_error`. This is the intended behavior. The legacy schema
  predates the safety level and has no column that could say which level produced a
  `network_error`. Its consumers branch on `ssrf_blocked` to recognize a local refusal.
  Relabeling the row would make a refusal look like a real network failure to exactly the
  callers who cannot see `safety_level`. The crawler reading lives only in `evidence_status`,
  which a consumer reads alongside `safety_level`.

## Alternatives considered

- **Keep "local safety dominates"; document the gap.** Rejected. The analyst caller keeps
  getting answers no engine would give, and the only escape opens internal networks.
- **Make safety a property of the ruleset** (for example, `google` follows downgrades). Rejected.
  It ties what the process may do to which engine is modeled, so a server-side service
  choosing `google` would silently start following downgrades. The two questions are
  independent, and coupling them recreates today's problem in reverse.
- **`crawler` dials internal addresses** ("as the crawler would try"). Rejected. A public
  crawler's attempt fails because it is outside your network, and robotstxtr is inside it.
  Dialing would reach exactly what the guard exists to keep out.
- **Under `crawler`, record internal addresses as `safety_refused`.** Rejected. That keeps the
  answer that no crawler gets.
- **Under `crawler`, record internal addresses as `transport_fail`, narrowing the invariant to
  `strict`.** Rejected by the maintainer. It merges a local refusal into real network failures,
  so a consumer could tell them apart only by reading `safety_level` and `safety_block_reason`
  together. `unreachable_local` keeps them apart and can still be combined.
- **If ssrfr declined the flag, follow the downgrade in robotstxtr** by preparing the `http`
  target as a new chain (`from = NULL`) and carrying the remaining time budget and hop count
  itself. Rejected: it moves chain bookkeeping that ssrfr owns (the chain-scoped
  `total_timeout`) into robotstxtr, and the maintainer chose the ssrfr flag (§7).
- **Yandex `over_budget` → `allow_all` `[application_choice]`.** Not adopted. It would apply
  Yandex's documented "open" rule to an undocumented trigger. The cell stays
  `documentation_gap` until measured (ROBO-ogwchglq).
- **Per-ruleset hop budgets** (10 for `google`). Rejected on the evidence. Google's robots.txt
  rule is five, and no engine documents a different robots.txt count.
- **A `trusted` third level, or keeping `ssrf_guard = FALSE`.** Rejected in §6.
- **Remove `ssrf_guard` now.** Rejected. sitemapr passes `ssrf_guard = TRUE`, and removing the
  argument would make that call an error.

## Consequences

- The standing rule: **the ruleset never changes what the fetch does, and the safety level never
  changes what an outcome means.** A new engine rule about the fetch, such as a different hop
  count, goes into the ruleset as an interpretation of an L0 fact, or into the research record
  as a reason to revisit §4. It is never a per-ruleset fetch behavior.
- `strict` results do not change. Existing callers, sitemapr included, see no difference until
  they opt in.
- `crawler` can produce verdicts where `strict` produced none (a site behind a downgrade). Those
  verdicts are what the engines document. A consumer comparing the two levels sees the
  difference in `safety_level` and in the `redirect_hops` log.
- The safety guarantee is unchanged at both levels. robotstxtr never connects to an internal
  address unless the caller names its range in `fetch_allow_ranges`, or passes the deprecated
  `ssrf_guard = FALSE` while that argument exists. The second reopens every range at either
  level (§6) and warns.
- The published invariant widens to "`safety_block_reason` set ⇒ `safety_refused` or
  `unreachable_local`" (§3). Under `strict` nothing changes; a consumer that opts into `crawler`
  meets one new `evidence_status` value.
- **This ADR alone does not override sitemapr ADR-009 §3** for robotstxtr, since engine-profiles.md
  is governed by it. The `crawler` level and slices 8 and 9 need a sitemapr ADR that amends ADR-009 §3 on two
  points (slice 6): safety precedence applies under `safety_level = "strict"` (under `crawler`
  an address-class refusal is `unreachable_local`), and a ruleset may give a ceiling-cut body a
  documented meaning (§5: the Yandex `allow_all`, and Google's `use_rules` on the prefix).
- Revisit if an engine documents a robots.txt hop count other than five, documents refusing a
  downgrade, or documents a behavior for a URL-shape refusal.

## Changes to engine-profiles.md on acceptance

Changes 3 and 9 are true of today's code and were applied on acceptance. Change 8's `yandex`
and `google` readings land with slices 8 and 9; the rest land with slice 2. Do not apply them
before then.

1. **Header, "Owns:" line.** Append: "the `safety_level` value set and what each level may do
   (§3a; ADR 0001)".

2. **§2, `evidence_status` table.** Replace three rows:

   | `evidence_status` | Trigger | → decision path |
   |---|---|---|
   | `http_protocol_error` | 1xx received, or malformed redirect (`no_location`/`loop`) | §3 terminal-reason handling |
   | `transport_fail` | DNS/connect/TLS/timeout/reset/chunk (`transport_error_kind` set); never with a `safety_block_reason` | §4 network row |
   | `unreachable_local` | under `safety_level = crawler` only: an address-class refusal (`safety_block_reason` kept; no connection made; §3a) | §4 `unreachable_local` row (same cells as the network row) |
   | `safety_refused` | under `safety_level = strict`: any ssrfr refusal incl. HTTPS→HTTP downgrade; under `crawler`: URL-shape refusals (`scheme`, `userinfo`, `port`, `parse`, `numeric-literal`, `malformed-address`) and the transition codes `6to4`, `teredo`, `isatap` | never allow/deny; §3a (ADR 0001); sitemapr ADR-003 governs the guard |

   (`non_http_target` leaves the `http_protocol_error` trigger: the code has always made it
   `safety_refused` through `safety_block_reason = scheme`.)

   And in the `safety_block_reason` paragraph, append: "A set `safety_block_reason` means
   `evidence_status = safety_refused`, except an address-class code under `safety_level =
   crawler`, which means `unreachable_local` (§3a). `fetch_outcome` stays `ssrf_blocked` at
   both levels."

3. **§3, first paragraph.** Replace "requires supporting **at least five** consecutive
   redirects" with "says crawlers SHOULD follow **at least five** consecutive redirects". Leave
   the rest of the paragraph and its `[documented]` tag as they are.

4. **§3, first bullet.** Replace
   "**`downgrade` / SSRF / non-http(s) target** → `evidence_status = safety_refused`,
   engine-independent (ADR-003). Never an engine policy result. `[application_choice: local
   safety dominates]`."
   with
   "**`downgrade` / SSRF / non-http(s) target** → decided by the `safety_level`, never by the
   ruleset (§3a). No engine documents refusing a downgrade; refusing one is a safety choice
   `[application_choice]`, made under `strict` only."

5. **§3, `over_budget` bullet.** Replace the `yandex` and `bing` lines with:
   - `yandex`: hop cap `[documentation_gap]`; robotstxtr follows 5 `[application_choice]`;
     exhaustion → no verdict `[documentation_gap]`, to be measured (ROBO-ogwchglq).
   - `bing`: `[documentation_gap]`; robotstxtr follows 5 `[application_choice]`; no verdict; to
     be measured (ROBO-ogwchglq).

   Add after the bullet: "The hop budget is one L0 setting, 5, for every ruleset: every engine
   that documents a robots.txt count documents five. Google's 10-hop figure is for general
   crawling (`design/engine-fetch-rules-sources.md`)."

6. **New §3a, after §3:**

   > ### 3a. Safety level (ADR 0001)
   >
   > `safety_level` is independent of `robots_policy_ruleset`. It decides what the fetch may
   > do; the ruleset decides what an outcome means.
   >
   > | `safety_level` | HTTPS→HTTP redirect | address-class refusal | transition or URL-shape refusal |
   > |---|---|---|---|
   > | `strict` (default) | refused → `safety_refused` / `https_downgrade` | `safety_refused` | `safety_refused` |
   > | `crawler` | followed as an ordinary hop | not dialed → `unreachable_local`, `safety_block_reason` kept | `safety_refused` |
   >
   > Address-class codes: `loopback`, `private`, `link-local`, `cloud-metadata`, `shared`,
   > `unspecified`, `this-network`, `multicast`, `reserved`, `ipv4-mapped`, `ipv4-translated`,
   > `ipv4-compatible`, `nat64`. Transition codes: `6to4`, `teredo`, `isatap` (the refusal does
   > not say the target is internal, so reachability is unknown). URL-shape codes: `scheme`,
   > `userinfo`, `port`, `parse`, `numeric-literal`, `malformed-address`.
   > `fetch_allow_ranges` reopens the listed ranges at either level.

7. **§3, "Within budget" paragraph.** Append: "None of the engines conditions a redirect on its
   scheme: an HTTPS→HTTP hop is followed `[inferred]` for `rfc9309`, `google` and `yandex`, and
   is `[documentation_gap]` for `bing`."

8. **§7.** Replace the "**Over-limit body**" bullet with:
   "**Over-limit body** — robotstxtr retains the ≤-limit prefix of a 2xx (ROBO-ldpahknv;
   `body_truncated = TRUE`, `termination_reason = ceiling`); the legacy path matches it. In the
   v1 path the ruleset decides what it means: `yandex` with `stored_bytes ≥ 512000` →
   `allow_all` `[documented]` (the file exceeds 500 KB under either reading of the unit; same
   rule as a retained body over 500,000 bytes, `yandex_file_over_500000_bytes`); `google` with
   `stored_bytes ≥ 512000` → `use_rules` on the prefix `[documented]` (Google parses the first
   500 KiB); both under sitemapr ADR-009 §3 as amended. `yandex` and `google` below those sizes,
   `rfc9309`, `assumed_rfc9309`, `bing` → `evidence_status = incomplete`. A 3xx, an unknown
   status or a status mismatch over the limit is `body_too_large`, nothing stored, `incomplete`
   under every ruleset. A 4xx/5xx over the limit is classified by its status (§4)."
   And replace the `yandex` bullet's "500 KB file" with "500 KB file (read as 500,000 bytes;
   the unit is not stated `[documentation_gap]`)". And in §9(c), replace "the v1 evidence keeps
   it `incomplete` (§7)" with "the v1 ruleset reading is §7's (ADR 0001 slices 8 and 9)".

9. **§10.** Add: "**Fetch rules (redirect count, size, downgrade, per engine)** —
   `design/engine-fetch-rules-sources.md` (read 2026-11-05). **Safety level** —
   `design/adr/0001-safety-level-vs-engine-ruleset.md`; sitemapr
   `docs/decisions/ADR-003-network-safety-policy.md` (the guard) and `ADR-009` §3 as amended
   (precedence)."

10. **§4 table.** Add a row after "network / DNS / timeout": `unreachable_local` (`crawler`
    only; §3a), with the network row's cells and tags in every column.

## Implementation slices

To be filed as fp issues once this ADR is accepted. Each one is an outcome with its own
acceptance test.

1. **ssrfr permits an opt-in downgrade** (in ssrfr). Acceptance: a policy built with the new
   flag lets `ssrf_prepare_hop()` from an `https` binding to an `http` target return a binding.
   The default policy still refuses it as `downgrade`. The vocabulary is unchanged, and
   ssrfr's corpus passes.
2. **`safety_level` exists, `strict` is unchanged** (robotstxtr). Depends on nothing.
   Acceptance: the four entry points accept `safety_level = "strict"` (the default) and reject
   any other value, except `"crawler"` once slice 3 lands, with a classed error. The test suite
   passes with no change other than the schema-revision pins (the tests that assert
   `"2026-11-05.1"`). The evidence carries `safety_level` (`NA` on rows with no acquisition). The contract publishes the
   value set under a new schema revision. engine-profiles.md gets the changes above, and
   engine-contract-v1.md gets the schema entry.
3. **`crawler` follows downgrades** (robotstxtr). Depends on 1 and 2. Acceptance: with the fake
   ssrfr, `https` → 301 → `http` → 200 under `crawler` yields `usable_body`,
   `redirect_count = 1`, the hop in `redirect_hops` and `https_downgrade_guard = FALSE`. The
   same chain under `strict` still yields `safety_refused` / `https_downgrade`.
4. **`crawler` records internal addresses as `unreachable_local`** (robotstxtr). Depends on 3,
   which admits `"crawler"`. Acceptance: for every address-class code in ssrfr's vocabulary, a
   refused first hop and a refused redirect target under `crawler` yield
   `evidence_status = unreachable_local`, `fetch_outcome = ssrf_blocked`, the code in
   `safety_block_reason`, and no `acquire_fetch()` call. The value is published under a new
   schema revision with its `engine_policy_table_v1()` rows; no row has `transport_fail` with a
   `safety_block_reason`. `source_evidence_status_v1()`'s precedence is class-aware, and the same
   rows under `strict` still yield `safety_refused`. `google`, `rfc9309` and `assumed_rfc9309` resolve to
   `context_required`; `yandex` and `bing` resolve to `documentation_gap`; none to `allow` or
   `deny`. `as_legacy_robots_decisions_v1()` reports `ssrf_blocked`. URL-shape codes stay
   `safety_refused`. A test walks the vocabulary, so a new code fails until it is classed.
   (Amended 2026-11-11, ROBO-aoslfvnx: `6to4`, `teredo` and `isatap` left the address class for a
   `transition` class that is `safety_refused` at both levels; §3.)
5. **`fetch_allow_ranges` replaces `ssrf_guard = FALSE`** (robotstxtr). Depends on 3 (its
   acceptance covers `crawler`). Acceptance: a listed range is fetched at both levels, and an
   unlisted one is not. The metadata names stay refused. `ssrf_guard = FALSE` still behaves as
   today and its warning names the replacement. Under `crawler` it reopens every range and
   adds the second warning. Combined with a non-empty `fetch_allow_ranges`, it is a classed
   call-level error. `ssrf_guard = TRUE` is silent.
6. **sitemapr amends ADR-009 §3 and stops passing `ssrf_guard`** (in sitemapr). Depends on 2.
   Acceptance: a new sitemapr ADR amends ADR-009 §3 on two points. Safety precedence applies
   under `safety_level = "strict"`; under `crawler`, an address-class refusal is
   `unreachable_local`, and sitemapr's findings mapping (ADR-003 §3, ADR-010 §3) gives that
   value a finding. And a ruleset may give a ceiling-cut body a documented meaning: Yandex's
   `allow_all` for a file over 500 KB, and Google's `use_rules` on its 500 KiB prefix. `robots-facts.R` no longer passes
   `ssrf_guard`, and its tests pass against a robotstxtr with and without the argument.
7. **`ssrf_guard` is removed** (robotstxtr). Depends on 5 and 6, plus one minor release.
   Acceptance: passing it is an unused-argument error. The evidence column `ssrf_guard` is
   dropped under a new schema revision.
8. **The `yandex` ruleset reads a cut file as open** (robotstxtr). Depends on 2 and on
   slice 6's ADR being accepted. Acceptance: the existing `yandex_file_over_500000_bytes`
   branch in `resolve_policy_v1()` is reached, with no parallel branch added. With it, a cut
   2xx (`body_truncated = TRUE`) with `stored_bytes ≥ 512000` under `yandex` resolves
   `allow_all` (`[documented]`). With `stored_bytes < 512000` it stays `incomplete`, and so
   does `body_too_large` (3xx, unknown status). Retained uncut bodies over 500,000 bytes behave
   as today. Other rulesets are unchanged. The `yandex` × `redirect_over_budget` cell stays
   `documentation_gap` (ROBO-ogwchglq).
9. **The `google` ruleset reads a cut file's prefix** (robotstxtr). Depends on 2 and on slice
   6's ADR being accepted. Acceptance: a cut 2xx with `stored_bytes ≥ 512000` under `google`
   resolves `use_rules` (`[documented]`) and is matched up to its last complete line within
   the first 512,000 bytes, as `match_google_v1()` reads, a cut prefix of exactly 512,000
   bytes also passing through the same complete-lines rule so its partial last line is
   dropped; with a smaller prefix it stays `incomplete`. Other
   rulesets are unchanged.

## Maintainer answers (2026-11-05)

1. Argument names: `safety_level` (`"strict"` default, `"crawler"`) and `fetch_allow_ranges`.
2. URL-shape refusals stay `safety_refused` at both levels; each keeps its own code.
3. Yandex `over_budget` → `allow_all`: not adopted; the cell stays `documentation_gap` until
   measured with served test files (ROBO-ogwchglq, parked).
4. Yandex "500 KB": read as 500,000 bytes for an uncut body; 512,000 bytes is the threshold for
   a cut one, which holds under either reading.
5. ssrfr gets an opt-in downgrade flag, default off; no robotstxtr-side fallback (§7).
6. The sitemapr change is a new sitemapr ADR amending ADR-009 §3, not an edit.
7. Bing: `assumed_rfc9309` defaults stay; no documentation search at each release; measure
   with served test files (ROBO-ogwchglq).
8. sitemapr ADR-009 §3 (as amended by ADR-010 §2) is amended for a ruleset's documented meaning
   of a ceiling-cut body; slices 8 and 9 stay.
9. Not the narrowed invariant: a new `evidence_status`, `unreachable_local`, under a schema
   revision (§3). Keep the finer value; aggregate later.
10. Google's prefix reading stays in this ADR as slice 9.
11. A cut 2xx stays `incomplete` in the v1 evidence and the ruleset reads the prefix; robotstxtr's
    v1 `partial` (a 206) is not renamed.
