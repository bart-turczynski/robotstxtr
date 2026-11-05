# robotstxtr (development version)

* The `robots` frame of `robots_fetch()` and `allowed_by_robots_*()` gains `retry_after` and `retry_after_seconds`: the final response's `Retry-After` and its delay, so a caller can honor a 429 or 503 (RFC 9110 §10.2.3) (ROBO-cthdyvlk).

* The `robots` frame of `robots_fetch()` and `allowed_by_robots_*()` gains `content_type`, as received, and `content_flag`, which marks a body that looks like HTML, XML, JSON or binary; matching is unchanged (ROBO-nhuirvrd).

* Case-insensitive matching of product tokens and robots.txt directive names no longer depends on the session locale: under `tr_TR`, `I` no longer folds to `ı` (SEOR-tldlaxgq).

* `robots_fetch()` and every URL entry point now fetch through the `ssrfr` guard: a host name is resolved once, its addresses checked, and the connection pinned to them (ROBO-jbralthm).

* `ssrfr (>= 1.0.0)` replaces `httr2` in Imports.

* `timeout` is now one budget per origin, redirects included, as documented, rounded up to whole seconds (ROBO-tyhouhua).

* `ssrf_guard = FALSE` is deprecated and warns: it reopens private and loopback ranges, but cloud-metadata endpoints and IPv6 transition forms stay refused (ROBO-jbralthm).

* A 2xx robots.txt over `max_bytes` is now `fetched` as its first `max_bytes` bytes, then matched and validated, not `body_too_large` (RFC 9309 §2.5); requires `ssrfr (>= 1.0.0.9000)` (ROBO-ldpahknv).

* Every `robots` frame gains a logical `body_truncated` column, `TRUE` for such a cut body; `robots_validate_url()` reports the cut in `body_truncated` and `limit_exceeded` (ROBO-ldpahknv).

* A v1 evidence row over the ceiling now has `legacy_fetch_outcome = "fetched"`, `body_present`, `stored_bytes = max_bytes` and `body_truncated = TRUE`; `evidence_status` stays `incomplete` (ROBO-ldpahknv).

* `safety_block_reason` gains `userinfo`, `port`, `parse`, `multicast` and `reserved`, at engine schema revision `2026-11-05.1` (ROBO-jbralthm).

* Unique local IPv6 addresses (`fd00::/8`) are now refused as `private`; they were allowed (ROBO-jbralthm).

* A malformed or zoned IPv6 literal in a redirect `Location` is now refused as `parse`, not `malformed-address`; as an origin it stays `input_invalid` (ROBO-atvfjuuw).

* An ideographic-dot or fullwidth spelling of the metadata host, such as `metadata。google。internal`, is now refused as `parse`, not `cloud-metadata`: its origin is an invalid `xn--` label (ROBO-pvntbjlb).

* GCP's IPv6 metadata endpoint `fd20:ce::254` is now refused as `cloud-metadata` (ROBO-xzbyxipg).

* A 3xx other than 301, 302, 303, 307 or 308, or one with several `Location` fields, is now `redirect_error` with `no_location`; any other response with several `Location` fields is now `network_error` (ROBO-jbralthm).

* A 3xx whose body exceeds `max_bytes` is now `body_too_large`, not followed: `ssrfr` keeps no `Location` from it. A 4xx or 5xx keeps its status outcome whatever its body size (ROBO-jbralthm).

* A response header may take up to 64 KiB and 256 fields; over either it is a `network_error` (ROBO-jbralthm).

* `fetch_user_agent` must now be a valid HTTP field value: a control character or leading or trailing whitespace is a call-level error (ROBO-jbralthm).

# robotstxtr 0.3.1

* `DESCRIPTION` now names Google LLC as copyright holder of the bundled Google matcher, and `inst/COPYRIGHTS` gives the copyright and license of every bundled component.

* The SSRF guard now blocks more spellings of the GCP metadata host: a trailing dot, the bare `metadata`, UTS #46 fullwidth forms, and upper case under `tr_TR` (ROBO-dxrljrde).

* Trailing dots are dropped before every SSRF check, so `169.254.169.254.` and `0x7f000001.` are read, and blocked, as the IPv4 literals they spell (ROBO-dxrljrde).

* `httr2` is now required at `>= 1.2.0`: under 1.1.x a fetch could leave its connection open, read past `max_bytes`, and ignore the mocked transport (SEOR-thlzqzac).

# robotstxtr 0.3.0

* `robots_engine_contract_v1()` and `robots_engine_contract_v2()`, at schema revision `2026-08-25.1`, publish which product tokens each `bounded_profiles` backend accepts, as `supported_profiles` rows (ROBO-qgxekgph).

* The Yandex backend accepts `Yandex` and `YandexAdditionalBot`, not `YandexBot`; Bing accepts `bingbot` and `adidxbot`. `YandexAdditionalBot` and `adidxbot` never fall back to a `User-agent: *` group.

* New `robots_resolve_matcher_profile_v1()` checks a product token against a backend before any fetch, raising `robotstxtr_unresolvable_matcher_profile` with the accepted selectors named (ROBO-nvuwpktu).

* Added `robots_engine_contract_v2()` and the Bing `matcher_backend`, bounded to `bingbot` and `adidxbot`, with four new non-decision statuses; an unofficial profile, not affiliated with Microsoft (ROBO-qetsyvwv).
* The SSRF guard classifies IPv6 unspecified and loopback addresses by value, so `::0.0.0.1` is loopback and `::0.0.0.0` unspecified (ROBO-pzgzxkoj).
* The SSRF guard's IPv6 link-local (`fe80::/10`) and AWS metadata (`fd00:ec2::/32`) rules match by value, so zero-padded spellings such as `fd00:0ec2::254` are blocked (ROBO-pjvypcjk).
* The SSRF guard decodes 6to4, Teredo and ISATAP IPv6 addresses and classifies the IPv4 address each wraps, so `2002:a9fe:a9fe::` is blocked (ROBO-laydgesq).
* An IPv6 literal that does not expand to exactly 8 hextets, such as `fe80:::1`, is refused as `malformed-address` (ROBO-udnyuuwn).
* An IPv6 literal ending in a single `:`, such as `::1:`, is refused as `malformed-address`; no blocked range had been reachable (ROBO-zavqklmi).
* SSRF reason codes: `100.64.0.0/10` is now `shared` (RFC 6598), not `cloud-metadata`, and the rest of `0.0.0.0/8` is `this-network` (RFC 791 §3.2); no verdict changes (ROBO-cjnsrmgd).
* A fetched `robots.txt` with an embedded NUL byte no longer aborts `robots_body()`, `allowed_by_robots_url()` or `robots_evaluate_url_v1()`: NUL bytes are dropped before decoding (ROBO-hcqrzikz).

* The documentation site is now <https://bart-turczynski.gitlab.io/robotstxtr/>, built by GitLab CI, replacing the GitHub Pages site (ROBO-qqwkldzv).

* Package metadata now points at GitLab: `URL:` names <https://gitlab.com/bart-turczynski/robotstxtr> and `BugReports:` the GitLab issue tracker (ROBO-bgcloodt).

* `rurl` is now required at `>= 3.0.1`, the lowest version on CRAN, and installation no longer needs the R-universe staging repository (ROBO-depmsgpz).

# robotstxtr 0.2.0

* Added `robots_validate_text()` and `robots_validate_url()` for machine-readable validation under the `google-parser-compatible` profile, with byte, line, directive, group and encoding diagnostics (ROBO-htvtajbr).

* Added the `robotstxtr.engine-aware/v1` evaluation contract through `robots_evaluate_text_v1()` and `robots_evaluate_url_v1()`; policy, matcher backend, product token, User-Agent and limits are explicit in every result (ROBO-unowhvjx).
* Results carry neutral acquisition evidence and explicit non-decision states; the pinned Google matcher is the first end-to-end backend and applies its 500 KiB prefix limit (ROBO-unowhvjx).
* Added `robots_engine_contract_v1()` for revision and capability negotiation, and `as_legacy_robots_decisions_v1()` as the bridge to the unchanged legacy schema (ROBO-unowhvjx).
* Added the Yandex `matcher_backend`, bounded to profile `yandex-0.1.0` and the crawlers `Yandex` and `YandexAdditionalBot`, with a new `matched_rule_value_raw` column; an unofficial compatibility profile (ROBO-sbyndsws).
* Development installs resolve the pre-CRAN `rurl` dependency chain through the author's R-universe instead of nested GitHub remotes (ROBO-yasmzyhl).

* `robots_fetch()` and `allowed_by_robots_url()` now refuse origins and redirect targets that resolve to private, loopback, link-local or cloud-metadata addresses, reporting `ssrf_blocked` and an `NA` decision (ROBO-quovenef).
* The new `ssrf_guard` argument (default `TRUE`) on `robots_fetch()` and `allowed_by_robots_url()` disables the guard for trusted intranet hosts (ROBO-quovenef).

# robotstxtr 0.1.0

* Initial release.
* Public API: `allowed_by_robots_text()`, `allowed_by_robots_url()`, `robots_fetch()` and `robots_body()`, to evaluate crawl permission and fetch or extract a `robots.txt` body.
