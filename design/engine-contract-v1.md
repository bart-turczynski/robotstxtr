# Engine-aware robots evaluation contract v1

- Contract ID: `robotstxtr.engine-aware/v1`
- Schema revision: `2026-07-17.1`
- First package release: `robotstxtr 0.2.0`
- Normative policy source: [`engine-profiles.md`](engine-profiles.md)

This is the released integration contract for sitemapr and sitemap-validator.
It turns the accepted engine-profile design into an additive API without
changing the four legacy functions or their result schemas.

## Entry points

`robots_evaluate_text_v1()` evaluates a caller-supplied body.
`robots_evaluate_url_v1()` acquires `/robots.txt` and evaluates it. Both require
an explicit `robots_policy_ruleset` and an explicit `matcher_backend`; neither
axis defaults to Google or to the other axis. `robots_product_token` controls
robots group selection. `fetch_user_agent` controls only the HTTP request and is
recorded separately.

`robots_engine_contract_v1()` publishes the contract/schema revisions, policy
and matcher revisions, capability states, complete status-policy table, and
sibling compatibility ranges as data.

The return class is `robots_engine_decisions_v1`, a list with:

- `results`: one row per requested URL, in input order;
- `evidence`: one row per acquired or supplied robots source, with list columns
  for ordered redirect hops and exact stored body bytes;
- `contract`: the value returned by `robots_engine_contract_v1()`.

Each result expands and persists the ruleset, ruleset revision, matcher backend,
matcher revision, robots product token, HTTP User-Agent, acquisition byte/time
limits, redirect limit, SSRF and HTTPS-downgrade guards, and engine body limit.
It then reports `evidence_status`, `policy_status`, `policy_action`, policy
reason/provenance/source, `matcher_availability`, `matcher_status`, the optional
`url_decision`, and a final reason. A missing `url_decision` is intentional and
must not be coerced to allow or deny.

## Stable outcome sets

Evidence status is one of `usable_body`, `partial`, `incomplete`, `http_status`,
`http_protocol_error`, `redirect_over_budget`, `transport_fail`,
`safety_refused`, or `not_applicable`.

Policy status is one of `evaluated`, `not_evaluated`, `context_required`, or
`documentation_gap`. An evaluated action is `use_rules` or `allow_all`.

Matcher status is one of `evaluated`, `not_needed`, `not_evaluated`, or
`capability_unavailable`. URL decision is `allow`, `disallow`, or absent (`NA`).

The absence cases are part of the contract. In particular, a safety refusal,
incomplete acquisition, lifecycle-dependent status, undocumented engine
policy, partial response, or unavailable matcher never fabricates a URL
decision.

## Backend and policy revisions

Google matching uses the vendored matcher pinned to upstream commit
`22b355ff855419e6a3ff8ff09c0ad7fdb17116f9`. The backend revision embeds that
SHA. The Google 500 KiB limit is applied at the matcher stage: the neutral
evidence retains a complete caller-supplied or within-acquisition-limit body,
and Google parses only its first 524,288 bytes.

Yandex, RFC 9309, and Bing matcher requests return
`capability_unavailable-v1`. Their policy tables still resolve independently
where the accepted design has evidence. Bing fetch/status policy remains a
`documentation_gap`; `assumed_rfc9309` is a separately named application policy
and is never reported as Bing.

## Legacy compatibility

The existing `allowed_by_robots_text()`, `allowed_by_robots_url()`,
`robots_fetch()`, and `robots_body()` remain unchanged. For consumers migrating
incrementally, `as_legacy_robots_decisions_v1()` explicitly converts a v1 result
whose policy and matcher are both Google into the original `robots_decisions`
schema. The adapter deliberately keeps legacy generic HTTP/redirect failures
unknown even where the new Google policy has a documented `allow_all` action;
this prevents a silent semantic change in old consumers.

## Sibling compatibility

The supported first-release ranges are:

- sitemapr `>= 0.0.0.9000, < 0.1.0`;
- sitemap-validator `>= 1.0.0, < 2.0.0`.

Consumers must negotiate the contract ID and schema revision, not infer support
only from the robotstxtr package version.

## Registering another matcher backend

Backend dispatch and revision/capability metadata live together in
`R/engine-contract-v1.R`. To add Yandex or Bing without changing the core result
schema:

1. complete the engine-profile gate: released contract, deterministic corpus,
   ABI and version review, provenance, and compatible licensing;
2. add a backend-specific matcher function that returns the existing internal
   fields (`url_decision`, reason, matched rule metadata, input bytes, and
   truncation flag);
3. atomically register that callable, its exact revision, and its `available`
   capability in `engine_matcher_registry_v1()` under the explicit backend
   name; the registry invariants reject partial or inconsistent activation;
4. add its conformance corpus and end-to-end facade tests; and
5. issue a new schema revision if any enum or column must change. Adding a
   backend implementation alone does not change the v1 result columns.

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
that token and is never a claim of compatibility with — or a prediction of — the
crawler the token names.
