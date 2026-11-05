---
status: proposed
date: 2026-11-05
tracking: ROBO-xdlzicrq
---

# ADR 0001: The safety level and the engine ruleset are separate settings

Proposed as a replacement for the `[application_choice: local safety dominates]` cell in
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
  every modeled engine and none from robotstxtr.
- **Private, loopback, link-local and cloud-metadata addresses are refused.** That is right
  for a server fetching URLs it does not trust, and the default stays. The only way to reopen
  them is the deprecated `ssrf_guard = FALSE`. ssrfr has no off switch, so that argument
  already maps onto a permissive policy (`allow_ranges = c("0.0.0.0/0", "::/0")` plus ssrfr's
  metadata host names) and warns (`warn_ssrf_guard_deprecated()` in `R/fetch-policy.R`).
- The evidence frame records the policy with two fixed columns: `ssrf_guard` (the argument as
  passed) and `https_downgrade_guard` (always `TRUE`, `source_results_to_evidence_v1()`).

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
  puts the HTTPS → HTTP downgrade among the `safety_refused` causes. sitemapr ADR-003 itself
  never mentions the downgrade.
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
  IPv6 forms that embed one: `ipv4-mapped`, `ipv4-translated`, `ipv4-compatible`, `nat64`,
  `6to4`, `teredo`, `isatap`) is never dialed. As before, no packet leaves the machine. The
  result is recorded as `fetch_outcome = network_error`,
  `transport_error_kind = network_error` and `evidence_status = transport_fail`, and
  `safety_block_reason` still carries the code so the refusal can be audited.

  This is what a public crawler sees: it cannot route to your RFC 1918 network or your
  metadata endpoint, and the connection fails. The engine ruleset then gives the outcome the
  meaning that engine gives an unreachable file. That is `context_required` for `rfc9309` and
  `google`, and `documentation_gap` for `yandex` and `bing` (engine-profiles.md §4 network
  row). Under today's tables, then, no address refusal becomes an allow or a deny under
  `crawler` either.
- **URL-shape refusals stay `safety_refused` at both levels.** These are `scheme` (and so
  `non_http_target`), `userinfo`, `port`, `parse`, `numeric-literal` and
  `malformed-address`. They are refusals of how the URL is spelled, not of where it points, and
  no engine documents a behavior for them. `host-denied` and `range-denied` are still not
  admitted (robotstxtr sets no deny rules).

### 4. The hop budget stays one fetch setting

Every engine that documents a robots.txt redirect count documents five (research record).
Google's "up to 10 redirect hops" is for general crawling, and its own robots.txt page sends
readers to the five-hop rule. So the budget stays `acquire_redirect_limit = 5L` for every
ruleset and both levels, and stays an L0 fact (`redirect_limit` in the evidence). The ruleset
only interprets `over_budget`. Yandex's and Bing's counts are `documentation_gap`. They use
five as a labeled `application_choice` fallback, never reported as documented.

### 5. Oversized files belong to the ruleset

A body over `max_bytes` stays an L0 fact (`body_too_large`, `termination_reason = ceiling`).
The ruleset decides what it means:

- **`yandex`:** when the acquisition limit is at least 500,000 bytes, the body provably exceeds
  Yandex's documented 500 KB. The site is then "considered open", so the result is
  `allow_all` `[documented]`. Below that limit the overflow proves nothing, and the result
  stays `incomplete`.
- **`google`:** Google parses the first 500 KiB. robotstxtr cannot, because ssrfr returns no
  part of an oversized body, so the result stays `incomplete` until ssrfr can keep a prefix
  (engine-profiles.md §7 and §9(c), unchanged).
- **`rfc9309`, `assumed_rfc9309`, `bing`:** no source says what happens beyond the limit, so the
  result stays `incomplete`.

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
  guard logic of its own (ARCHITECTURE.md: nothing but `R/acquire.R` calls ssrfr).

### 7. The downgrade needs one ssrfr change

ssrfr refuses `https` → `http` whenever a hop is prepared with `from` an `https` binding, and its
policy has no setting to permit it. robotstxtr asks ssrfr for an opt-in policy flag, default
off, that permits the downgrade. ssrfr ADR 0001 §4 already says the refusal applies "by
default", and its spec says it protects response integrity, not credentials, which an opt-in
leaves intact for every other caller. `crawler` ships only after that flag exists.

The fallback, if ssrfr declines: robotstxtr prepares the `http` target as a new chain
(`from = NULL`) and carries the remaining time budget and the hop count itself. It is rejected
as the plan of record because it moves chain bookkeeping that ssrfr owns (the chain-scoped
`total_timeout`) into robotstxtr.

### 8. Published shape

- `robots_engine_contract_v1()` publishes the `safety_level` value set.
- The evidence frame gains `safety_level` (character) and `fetch_allow_ranges` (list column).
  `https_downgrade_guard` becomes `safety_level == "strict"`. `ssrf_guard` keeps recording the
  deprecated argument until it is removed.
- These need a new schema revision (engine-contract-v1.md, "Registering another matcher
  backend", step 5) and a contract-doc entry.
- `as_legacy_robots_decisions_v1()` is unchanged. `crawler` rows convert like any other.

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
  answer that no crawler gets. `transport_fail` with `safety_block_reason` kept is both true to
  the crawler and auditable.
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
- The safety guarantee is unchanged at both levels: robotstxtr never connects to an internal
  address unless the caller names its range.
- **This ADR alone does not override sitemapr ADR-009 §3** for robotstxtr, since engine-profiles.md
  is governed by it. Accepting this ADR needs a sitemapr ADR that scopes ADR-009 §3 to
  `safety_level = "strict"` (slice 6).
- Revisit if an engine documents a robots.txt hop count other than five, documents refusing a
  downgrade, or documents a behavior for a URL-shape refusal.

## Changes to engine-profiles.md on acceptance

Applied by slice 2. Do not apply before then.

1. **Header, "Owns:" line.** Append: "the `safety_level` value set and what each level may do
   (§3a; ADR 0001)".

2. **§2, `evidence_status` table.** Replace three rows:

   | `evidence_status` | Trigger | → decision path |
   |---|---|---|
   | `http_protocol_error` | 1xx received, or malformed redirect (`no_location`/`loop`) | §3 terminal-reason handling |
   | `transport_fail` | DNS/connect/TLS/timeout/reset/chunk (`transport_error_kind` set), OR under `safety_level = crawler` an address-class refusal (`safety_block_reason` kept; no connection made; §3a) | §4 network row |
   | `safety_refused` | under `safety_level = strict`: any ssrfr refusal incl. HTTPS→HTTP downgrade; under `crawler`: URL-shape refusals only (`scheme`, `userinfo`, `port`, `parse`, `numeric-literal`, `malformed-address`) | never allow/deny; §3a (ADR 0001); sitemapr ADR-003 governs the guard |

   (`non_http_target` leaves the `http_protocol_error` trigger: the code has always made it
   `safety_refused` through `safety_block_reason = scheme`.)

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
     exhaustion → `allow_all` `[application_choice]` (basis: the documented "file doesn't meet
     the requirements → site open" rule applied to a chain that never reaches 200).
   - `bing`: `[documentation_gap]`; robotstxtr follows 5 `[application_choice]`; no verdict.

   Add after the bullet: "The hop budget is one L0 setting, 5, for every ruleset: every engine
   that documents a robots.txt count documents five. Google's 10-hop figure is for general
   crawling (`design/engine-fetch-rules-sources.md`)."

6. **New §3a, after §3:**

   > ### 3a. Safety level (ADR 0001)
   >
   > `safety_level` is independent of `robots_policy_ruleset`. It decides what the fetch may
   > do; the ruleset decides what an outcome means.
   >
   > | `safety_level` | HTTPS→HTTP redirect | address-class refusal | URL-shape refusal |
   > |---|---|---|---|
   > | `strict` (default) | refused → `safety_refused` / `https_downgrade` | `safety_refused` | `safety_refused` |
   > | `crawler` | followed as an ordinary hop | not dialed → `transport_fail`, `safety_block_reason` kept | `safety_refused` |
   >
   > Address-class codes: `loopback`, `private`, `link-local`, `cloud-metadata`, `shared`,
   > `unspecified`, `this-network`, `multicast`, `reserved`, `ipv4-mapped`, `ipv4-translated`,
   > `ipv4-compatible`, `nat64`, `6to4`, `teredo`, `isatap`. URL-shape codes: `scheme`,
   > `userinfo`, `port`, `parse`, `numeric-literal`, `malformed-address`.
   > `fetch_allow_ranges` reopens the listed ranges at either level.

7. **§3, "Within budget" paragraph.** Append: "None of the engines conditions a redirect on its
   scheme: an HTTPS→HTTP hop is followed `[inferred]` for `rfc9309`, `google` and `yandex`, and
   is `[documentation_gap]` for `bing`."

8. **§7.** Replace the "**Over-limit body**" bullet with:
   "**Over-limit body** (`body_too_large`, an L0 fact) — by ruleset: `yandex` with
   `acquisition_max_bytes ≥ 500000` → `allow_all` `[documented]` (the file provably exceeds
   500 KB); `yandex` below that, `google`, `rfc9309`, `assumed_rfc9309`, `bing` →
   `evidence_status = incomplete`. Google parses the ≤-limit prefix; robotstxtr cannot, because
   `ssrfr` returns no part of an over-limit body (implementation delta, §9). A 4xx/5xx over the
   limit is classified by its status (§4)."
   And replace the `yandex` bullet's "500 KB file" with "500 KB file (read as 500,000 bytes;
   the unit is not stated `[documentation_gap]`)".

9. **§10.** Add: "**Fetch rules (redirect count, size, downgrade, per engine)** —
   `design/engine-fetch-rules-sources.md` (read 2026-11-05). **Safety level** —
   `design/adr/0001-safety-level-vs-engine-ruleset.md`; sitemapr
   `docs/decisions/ADR-003-network-safety-policy.md` (the guard) and `ADR-009` §3 as amended
   (precedence)."

## Implementation slices

To be filed as fp issues once this ADR is accepted. Each one is an outcome with its own
acceptance test.

1. **ssrfr permits an opt-in downgrade** (in ssrfr). Acceptance: a policy built with the new
   flag lets `ssrf_prepare_hop()` from an `https` binding to an `http` target return a binding.
   The default policy still refuses it as `downgrade`. The vocabulary is unchanged, and
   ssrfr's corpus passes.
2. **`safety_level` exists, `strict` is unchanged** (robotstxtr). Depends on nothing.
   Acceptance: the four entry points accept `safety_level = "strict"` (the default) and reject
   any other value, except `"crawler"` once slice 3 lands, with a classed error. The full test
   suite passes unmodified. The evidence carries `safety_level`. The contract publishes the
   value set under a new schema revision. engine-profiles.md gets the changes above, and
   engine-contract-v1.md gets the schema entry.
3. **`crawler` follows downgrades** (robotstxtr). Depends on 1 and 2. Acceptance: with the fake
   ssrfr, `https` → 301 → `http` → 200 under `crawler` yields `usable_body`,
   `redirect_count = 1`, the hop in `redirect_hops` and `https_downgrade_guard = FALSE`. The
   same chain under `strict` still yields `safety_refused` / `https_downgrade`.
4. **`crawler` records internal addresses as unreachable** (robotstxtr). Depends on 2.
   Acceptance: for every address-class code in ssrfr's vocabulary, a refused first hop and a
   refused redirect target under `crawler` yield `transport_fail`, the code in
   `safety_block_reason`, and no `acquire_fetch()` call. `google` and `rfc9309` resolve to
   `context_required`, never `allow` or `deny`. URL-shape codes stay `safety_refused`. A test
   walks the vocabulary, so a new code fails until it is classed.
5. **`fetch_allow_ranges` replaces `ssrf_guard = FALSE`** (robotstxtr). Depends on 2.
   Acceptance: a listed range is fetched at both levels, and an unlisted one is not. The
   metadata names stay refused. `ssrf_guard = FALSE` still behaves as today and its warning
   names the replacement. `ssrf_guard = TRUE` is silent.
6. **sitemapr scopes ADR-009 §3 to `strict` and stops passing `ssrf_guard`** (in sitemapr).
   Depends on 2. Acceptance: a sitemapr ADR records the amendment. `robots-facts.R` no longer
   passes `ssrf_guard`, and its tests pass against a robotstxtr with and without the argument.
7. **`ssrf_guard` is removed** (robotstxtr). Depends on 5 and 6, plus one minor release.
   Acceptance: passing it is an unused-argument error. The evidence column `ssrf_guard` is
   dropped under a new schema revision.
8. **The `yandex` ruleset reads an oversized file as open** (robotstxtr). Depends on 2.
   Acceptance: `body_too_large` with `max_bytes ≥ 500000` under `yandex` resolves `allow_all`
   (`[documented]`). With `max_bytes < 500000` it stays `incomplete`. Other rulesets are
   unchanged. If the maintainer adopts it, the `yandex` × `redirect_over_budget` cell becomes
   `allow_all` `[application_choice]` in the same slice.

A Google prefix parse for oversized files stays outside this list. It needs ssrfr to keep a
body prefix and is engine-profiles.md §9(c)'s existing delta. File it top-level, depending on
the ssrfr work, if it is wanted.

## Open for the maintainer

1. **Argument names.** `safety_level` with `"strict"` / `"crawler"`, and `fetch_allow_ranges`.
   Alternatives: `fetch_safety`, and `allow_ranges` to match ssrfr. The names are public API.
2. **Should the URL-shape refusals follow the crawler under `crawler`?** For example, a public
   crawler probably follows a `Location` carrying userinfo. This ADR keeps them
   `safety_refused` because no engine documents them.
3. **Yandex `over_budget` → `allow_all` `[application_choice]`** (slice 8, change 5). It applies
   a documented open fallback to an undocumented trigger. It can be dropped without affecting
   the rest of the ADR. If dropped, the cell stays `documentation_gap`.
4. **The Yandex "500 KB" unit.** 500,000 bytes (the current reading) or 512,000 bytes?
5. **If ssrfr declines the downgrade flag**, is the robotstxtr-side new-chain fallback (§7)
   acceptable, or does `crawler` wait?
6. **The sitemapr ADR (slice 6)** is a change in another repository's accepted ADR set. Confirm
   it should be written as a new sitemapr ADR amending ADR-009 §3, not as an edit.
7. **Bing.** Still no primary source for any fetch rule (research record). Keep searching each
   release, or treat Bing's fetch as permanently `assumed_rfc9309`-only?
