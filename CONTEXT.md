# Context: robotstxtr's domain words

A glossary of the words this package's code, tests and design docs use with a
fixed meaning. The contract each word belongs to is linked; this file only
names things.

## Evaluation

**Engine-aware evaluation.** `robots_evaluate_text_v1()` and
`robots_evaluate_url_v1()`: each row is evaluated under an explicit policy
ruleset and an explicit matcher backend, chosen independently
([design/engine-contract-v1.md](design/engine-contract-v1.md)).

**Policy ruleset.** The vendor reading of a fetch outcome (a 404, a 5xx, a
cut body): `google`, `yandex`, `rfc9309`, `bing` or `assumed_rfc9309`. It
decides whether the rules are used at all (`policy_action`).

**Evidence.** The neutral record of how a robots.txt was acquired, one row
per source, apart from any decision (`$evidence`).

## Matching

**Matcher backend.** The engine that matches a URL against robots.txt rules
under one vendor's semantics: `google`, `yandex`, `rfc9309` or `bing`. A
backend is available or `capability_unavailable`; an unavailable backend is
never routed to another.

**Matcher registry.** `engine_matcher_registry_v1()`: per backend, its exact
revision, its availability and, when available, its matcher adapter. The
evaluator reads it once per call and dispatches on its entries alone.

**Matcher adapter.** A backend's one entry point,
`callable(bodies, urls, product_tokens)`, called once per evaluation with
every row that backend matches. It returns a decision frame. In the Google,
Yandex and Bing adapters the matcher parses each distinct body once; Google's
line collector reads each body that has a matched row once more.

**Decision frame.** What an adapter returns: one row per input row, in input
order, with the twelve columns of `matcher_decision_columns_v1()`. The
evaluator checks its row count and columns and scatters its rows back.

**Row matcher.** A function that matches one row,
`function(body, url, product_token)`, such as `match_google_v1()`. It is
never dispatched to directly; `match_google_v1()` is the reference the Google
adapter's batch must equal row for row.

**Product token.** The robots.txt `User-agent:` group selector a row is
evaluated for. It is never sent as an HTTP header; the HTTP request carries
the fetch user agent instead.

**Supported profile.** One of the closed set of product tokens a
`bounded_profiles` backend (Yandex, Bing) accepts. Any other token leaves the
row undecided (reason `unsupported_product_token` on Yandex,
`unsupported_profile` on Bing); it is not an error.

## Bodies

**Cut body.** A 2xx body stored only up to `max_bytes` (`body_truncated` in
the evidence). Only the `google` ruleset with the `google` backend matches
one, and only once it holds the whole Google window; its partial last line is
dropped first.

**Google window.** The first 512,000 bytes of a body, which Google's matcher
reads; a longer body is matched on its complete lines inside the window and
flagged `matcher_body_truncated`.
