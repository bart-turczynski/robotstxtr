# robotstxtr (development version)

* `allowed_by_robots_url()` now reads 512,000 bytes by default (Google's 500 KiB window, not 524,288), up to the last complete line; decisions change only on files over 512,000 bytes (ROBO-uwveumyp).

* Under `safety_level = "crawler"`, `robots_validate_url()` reads a refused internal address as an unreachable file, with each engine's reading, not as having no engine reading (ROBO-akfbbake).

* On the Google backend a NUL byte in a fetched robots.txt now ends its line, as in Google's open-source parser, instead of being removed (ROBO-pvqrfvol).

* `robots_validate_text()` and `robots_validate_url()` list only the lost `User-agent: *` Allow rules, which may be exceptions, in `wildcard_rules_not_inherited` when the merged named groups disallow `/` and hold no non-empty `Allow` (ROBO-bwpacxtq).

* Under `safety_level = "crawler"`, a refused 6to4, Teredo or ISATAP address is now `evidence_status = "safety_refused"`, not `"unreachable_local"`: the refusal does not show the target is internal (ROBO-aoslfvnx).

* New `fetch_allow_ranges` argument on the four fetching entry points: the CIDR ranges listed are fetched at either safety level, replacing the deprecated `ssrf_guard = FALSE` (ROBO-bamcjvwn).

* `robots_validate_url()` notes an `https` to `http` redirect followed under `safety_level = "crawler"` as `redirect_downgrade_followed`; legacy `robots` frames gain a `redirect_hops` column (ROBO-cscdbael).

* `robots_fetch()`'s `content_flag` and `html_body` warning no longer read SVG, RSS or Atom roots, or a comment-led robots.txt, as HTML unless an `<!doctype html` or a line opens with `<html`, `<head` or `<body` (ROBO-isbpzgqn).

* Under `safety_level = "crawler"`, a refused internal address is now `evidence_status = "unreachable_local"`, which no ruleset reads as allow or deny; schema revision `2026-11-11.1` (ROBO-jqwukcog).

* `safety_level = "crawler"` is now available: it follows an `https` to `http` redirect as an ordinary hop, and needs ssrfr 1.0.0.9001 (ROBO-lwdxzdhw).

* `robots_fetch()`'s `content_flag` and the `html_body` warning now catch an HTML page opening with inline script or style, or cut at `max_bytes` on its first line (ROBO-qquftxcx).

* `robots_validate_text()` now warns `rules_after_nul_removal` when NUL bytes hide rules, even beside other rules (ROBO-ctdkqawi).

* `robots_validate_text()` and `robots_validate_url()` now take time linear in the number of diagnostics (ROBO-dbvmxcfw).

* The v1 `google` matcher parses each distinct robots.txt once per call, not once per URL (ROBO-iooslxvj).

* `robots_validate_text()` recognizes the draft aipref `__usage_ai-training` token: an info, warnings on near misses, unusable lines and stacked groups, and no `wildcard_rules_not_inherited` (ROBO-kzyfejcv).

* `robots_validate_text()` and `robots_validate_url()` warn, as `rule_lowercase_escape`, on a lower-case percent-escape in an Allow or Disallow pattern, which Google matches only in upper case (ROBO-kormmfyg).

* `robots_validate_url()` notes a 2xx status other than 200, such as 203, with an info `acquisition_http_other_2xx` naming how Google, Yandex and Bing read it (ROBO-yvhqvthd).

* `robots_validate_text()` reports `rules_after_nul_removal` instead of `no_rules` when rules appear only once NUL bytes are dropped, as in UTF-16 files (RFC 9309 §2.3) (ROBO-igrkabdb).

* `robots_validate_text()` and `robots_validate_url()` warn, as `rule_inner_whitespace`, on whitespace inside an Allow or Disallow pattern, which matches no request URL (RFC 9309 §2.2) (ROBO-dlgeqluf).

* `robots_validate_url()` reports a robots.txt fetch that redirected to another path, host or site (RFC 9309 §2.3.1.2) (ROBO-gokbvzcb).

* `robots_validate_text()` and `robots_validate_url()` report `invalid_utf8` on each line holding the bytes, and bytes only a comment holds as the new `invalid_utf8_comment` warning (RFC 9309 §2.3) (ROBO-sniltuap).

* `robots_validate_text()` reports a `Content-Signal` line as `content_signal_directive`, not `unsupported_directive`: an expired draft no crawler documents honoring (ROBO-fqkgreev).

* `robots_validate_text()` warns `rule_cut_by_comment` when a `#` with no space or tab before it starts a comment inside an Allow or Disallow value, cutting the rule there (ROBO-gjhpykcj).

* `robots_validate_text()` and `robots_validate_url()` warn `user_agent_cut` when a non-global User-agent value holds a character outside letters, `_` and `-`, naming the token Google's matcher reads (RFC 9309 §2.2.1) (ROBO-zvhrayhx).

* `robots_validate_text()` and `robots_validate_url()` warn (`accepted_directive_prefix`) on a key such as `DisallowAITraining`, which Google reads as Disallow by prefix (ROBO-xglcoagv).

* `robots_validate_text()` and `robots_validate_url()` warn with `misplaced_byte_order_mark` on a byte-order mark after the start of the file, which hides the directive on its line (ROBO-atkmqcov).

* `robots_validate_text()` and `robots_validate_url()` warn, as `rule_escaped_unreserved`, on a rule that percent-escapes an unreserved character such as `%7E`, which Google never matches against `~` (RFC 9309 §2.2.2) (ROBO-gaczsrgj).

* `robots_validate_text()` and `robots_validate_url()` warn with `html_body` when the body looks like an HTML page, not a robots.txt (ROBO-ccfsanhq).

* Text entry points no longer alter an unmarked non-ASCII `robots_txt` under `LC_ALL=C`; it is read as UTF-8, as in a UTF-8 locale (ROBO-tipzbglv).

* The `robots` frame of `robots_fetch()` and `allowed_by_robots_*()` gains `terminal_redirect_reason` and `safety_block_reason`; `robots_validate_url()` explains redirect, transport and safety outcomes per engine with their own codes instead of `acquisition_failed` (ROBO-bsloeclp).

* Under the v1 `google` ruleset and matcher backend, a robots.txt cut at `max_bytes` with at least 512,000 bytes stored is now matched on its first 512,000 bytes instead of resolving `incomplete_evidence` (ROBO-ptibdnvy).

* Under the v1 `yandex` ruleset, a robots.txt cut at `max_bytes` with at least 512,000 bytes stored now resolves `allow_all`, as a file over Yandex's 500 KB limit; the `yandex` policy revision follows (ROBO-arrtietl).

* `robots_validate_url()` reports a 4xx, 429, 5xx or 1xx robots.txt with its own code, naming the status and what Google, Yandex and Bing may do (ROBO-ybzbxfml).

* The v1 `google` matcher now reads at most a body's first 512,000 bytes (Google's 500 KiB, not 524,288), up to the last complete line; `matcher_input_bytes`, `policy_body_limit_bytes` and the google policy revision follow (ROBO-phfbpfiy).

* `robots_validate_text()` and `robots_validate_url()` report, as info, an exact duplicate Allow or Disallow for the same crawlers, which has no effect (ROBO-xexjgecr).

* `robots_validate_text()` and `robots_validate_url()` warn when a Disallow has an identical Allow, which wins the tie, so `Allow: /` plus `Disallow: /` blocks nothing (RFC 9309 §2.2.2) (ROBO-fdhmlvwm).

* `robots_validate_text()` and `robots_validate_url()` report the `wildcard_rules_not_inherited` info for a named User-agent group lacking `User-agent: *` rules, which its crawler then ignores (RFC 9309 §2.2.1) (ROBO-gfjotdrr).

* An empty, comment-only or Sitemap-only robots.txt now validates with the `no_rules` info, not the `missing_user_agent` error; that error now needs rules without a User-agent (RFC 9309 §2.2.1) (ROBO-vxrzcqpe).

* `robots_validate_text()` and `robots_validate_url()` now warn on a sitemap value that is not an absolute `http`, `https` or `ftp` URL, and on Allow/Disallow patterns that never match or hold a literal `$` (ROBO-xblfzkid).

* The fetching functions and `robots_evaluate_url_v1()` gain `safety_level`; `"strict"`, the default, fetches as before. The v1 evidence gains `safety_level` and `fetch_allow_ranges` (schema `2026-11-08.1`) (ROBO-pezlychx).

* The `robots` frame of `robots_fetch()` and `allowed_by_robots_*()` gains `retry_after` and `retry_after_seconds`: the final response's `Retry-After` and its delay, so a caller can honor a 429 or 503 (RFC 9110 §10.2.3) (ROBO-cthdyvlk).

* The `robots` frame of `robots_fetch()` and `allowed_by_robots_*()` gains `content_type`, as received, and `content_flag`, which marks a body that looks like HTML, XML, JSON or binary; matching is unchanged (ROBO-nhuirvrd).

* Case-insensitive matching of product tokens and robots.txt directive names no longer depends on the session locale: under `tr_TR`, `I` no longer folds to `ı` (SEOR-tldlaxgq).

* `robots_fetch()` and every URL entry point now fetch through the `ssrfr` guard: a host name is resolved once, its addresses checked, and the connection pinned to them (ROBO-jbralthm).

* `ssrfr (>= 1.0.0.9000)`, installed from its GitLab repository through `Remotes`, replaces `httr2` in Imports.

* `timeout` is now one budget per origin, redirects included, as documented, rounded up to whole seconds (ROBO-tyhouhua).

* `ssrf_guard = FALSE` is deprecated and warns: it reopens private and loopback ranges, but cloud-metadata endpoints and IPv6 transition forms stay refused (ROBO-jbralthm).

* A 2xx robots.txt over `max_bytes` is now `fetched` as its first `max_bytes` bytes, then matched and validated up to its last complete line, not `body_too_large` (RFC 9309 §2.5) (ROBO-ldpahknv).

* Every `robots` frame gains a logical `body_truncated` column; `robots_validate_url()` reports a cut file in `body_truncated`, `limit_exceeded` and a `body_truncated` warning (ROBO-ldpahknv).

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
