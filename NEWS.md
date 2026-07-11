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
