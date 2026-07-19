# robotstxtr 0.2.0

* Added `robots_validate_text()` and `robots_validate_url()` for stable,
  machine-readable document validation under an explicit
  `google-parser-compatible` profile. Reports include document byte/line and
  directive evidence, per-line syntax and group diagnostics, BOM/NUL/UTF-8
  hazards, and acquisition-limit outcomes without parsing truncated bodies
  (#ROBO-htvtajbr).

* Added the parallel `robotstxtr.engine-aware/v1` evaluation contract through
  `robots_evaluate_text_v1()` and `robots_evaluate_url_v1()`. Policy rulesets,
  matcher backends, robots product tokens, HTTP User-Agents, and acquisition
  limits are explicit, independent, and persisted in every result
  (#ROBO-unowhvjx).
* Added neutral acquisition evidence and explicit non-decision states for
  safety refusal, incomplete or partial evidence, crawler lifecycle context,
  documentation gaps, and unavailable matchers. The pinned Google matcher is
  the first available end-to-end backend; it applies its 500 KiB prefix limit
  without relabeling itself as another engine (#ROBO-unowhvjx).
* Added `robots_engine_contract_v1()` for revision/capability negotiation and
  `as_legacy_robots_decisions_v1()` as the explicit bridge to the unchanged
  Google-oriented legacy schema (#ROBO-unowhvjx).
* Added the Yandex `matcher_backend` as an available end-to-end backend as of
  schema revision `2026-07-18.2`, bounded to profile `yandex-0.1.0` and the
  crawlers `Yandex` and `YandexAdditionalBot`; every other Yandex-backend
  product token resolves to a checked `unsupported_crawler` non-decision.
  Yandex-evaluated results expose the new public `matched_rule_value_raw` list
  column (exact owning-rule bytes, `raw(0)` for an effective-empty `Disallow`,
  `NULL` for an absent rule), and structured backend identity is published at
  `robots_engine_contract_v1()$matcher_identity$yandex`. This is an
  independent, unofficial compatibility profile and does not claim
  production-crawler parity (#ROBO-sbyndsws, #ROBO-mhzmembp).
* Development installs and CI now resolve the pre-CRAN `rurl` dependency chain
  through the author's CRAN-like R-universe instead of nested GitHub remotes
  (#ROBO-yasmzyhl).

* The fetch policy now enforces a structural SSRF guard: `robots_fetch()` and
  `allowed_by_robots_url()` refuse — before opening any socket — both the
  initial origin and every redirect target that resolves to a private,
  loopback, link-local, or cloud-metadata address (including IPv6 loopback,
  IPv4-in-IPv6 embeddings, and numeric/hex/octal literal obfuscation). Such a
  URL is reported with the new `ssrf_blocked` fetch outcome and yields a
  `fetch_unknown` (`NA`) decision, never a silent allow (#ROBO-quovenef).
* The guard can be disabled per call with the new `ssrf_guard` argument
  (`TRUE` by default) on `robots_fetch()` and `allowed_by_robots_url()`, for
  deliberate use against trusted intranet hosts (#ROBO-quovenef).

# robotstxtr 0.1.0

* Initial release.
* Public API:
  * `allowed_by_robots_text()` — evaluate crawl permission against a
    `robots.txt` document supplied as text.
  * `allowed_by_robots_url()` — evaluate crawl permission for a URL, fetching
    the relevant `robots.txt` as needed.
  * `robots_fetch()` — fetch a `robots.txt` document under a deterministic,
    conservative policy.
  * `robots_body()` — preview or extract a stored `robots.txt` body.
