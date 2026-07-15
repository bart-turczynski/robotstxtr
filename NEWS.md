# robotstxtr (development version)

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
