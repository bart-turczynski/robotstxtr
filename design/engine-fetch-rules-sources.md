# Engine fetch rules: redirects and size, with sources

- Status: research record (ROBO-xdlzicrq), read 2026-11-05
- Feeds: [`design/adr/0001-safety-level-vs-engine-ruleset.md`](adr/0001-safety-level-vs-engine-ruleset.md)
- Scope: for each `robots_policy_ruleset` in [`engine-profiles.md`](engine-profiles.md) and
  `R/engine-contract-v1.R` (`rfc9309`, `google`, `yandex`, `bing`; `assumed_rfc9309` is
  robotstxtr's own application policy, not an engine, and inherits the `rfc9309` column), what the
  engine's own sources say about:
  1. how many redirects it follows when fetching `/robots.txt`, and what happens after the last;
  2. the robots.txt size limit, and what happens to a file over it;
  3. an `https` → `http` redirect;
  4. a redirect to another host.

Every value below carries its source, the date it was read, and a provenance tag from
engine-profiles.md (`documented`, `inherited_protocol`, `application_choice`, `inferred`,
`documentation_gap`, `documentation_conflict`). A value no primary source states stays a
`documentation_gap`. Where robotstxtr still has to act on one, the fallback is given
separately and tagged `application_choice`, with the reason for it.

Quotes are short excerpts from the page as fetched on 2026-11-05. None of the pages showed a
"last updated" date in the fetched text, so the read date is the only date recorded.

## Summary

| Question | `rfc9309` | `google` | `yandex` | `bing` |
|---|---|---|---|---|
| Hops followed | at least 5 (SHOULD) `[documented]`; robotstxtr follows exactly 5 `[application_choice]` | at least 5, "as defined by RFC 1945" (whose cap is 5) `[documented]`; robotstxtr follows exactly 5 `[application_choice]` | not stated `[documentation_gap]`; fallback 5 `[application_choice]` | not stated `[documentation_gap]`; fallback 5 `[application_choice]` |
| After the last hop | MAY assume unavailable → 4xx path, `allow_all` `[application_choice]` | stops, treats as 404 → `allow_all` `[documented]` | not stated `[documentation_gap]`; candidate `allow_all` via the documented "not 200 → open" rule `[application_choice]` | not stated `[documentation_gap]`; no fallback verdict |
| Size limit | parse at least 500 KiB (MUST); no maximum `[documented]` | 500 KiB `[documented]` | 500 KB `[documented]` | not stated `[documentation_gap]` |
| Over the limit | not specified `[documentation_gap]` | content after the limit ignored, prefix parsed `[documented]` | file fails the requirements → site open (`allow_all`) `[documented]` | not stated `[documentation_gap]` |
| `https` → `http` redirect | not restricted; the RFC places no scheme condition on a redirect `[inferred]` | not restricted; no exception to the RFC 1945 hops `[inferred]` | not restricted; not addressed `[inferred]` | not stated `[documentation_gap]` |
| Cross-host redirect | followed, "even across authorities"; rules apply to the initial authority `[documented]` | not separately stated `[inferred]` | followed; the target's directives apply, target must return 200 `[documented]` | not stated `[documentation_gap]` |

The hop count is 5 for every engine that documents one. The figure of 10 hops that Google
publishes is for general crawling, not for robots.txt (see Google below). So no engine
documents a hop budget that differs from the one robotstxtr already uses, and the budget can
stay a single engine-neutral fetch setting (ADR-009 §3: the fetch layer takes caller and
safety limits only).

## RFC 9309 (`rfc9309`)

Source: RFC 9309, <https://www.rfc-editor.org/rfc/rfc9309.html>, read 2026-11-05.

- **Hops.** §2.3.1.2: "The crawlers SHOULD follow at least five consecutive redirects, even
  across authorities". `[documented]` The requirement is a SHOULD floor. It sets no maximum.
  engine-profiles.md §3 said "requires", which is stronger than the RFC's wording; corrected
  on ADR 0001's acceptance.
- **robotstxtr's count.** robotstxtr follows exactly five and stops on the sixth 3xx
  (`acquire_redirect_limit <- 5L` in `R/acquire.R`; `max_redirects` is that budget plus one,
  so the sixth 3xx comes back as `over_budget` with its `Location`).
  `[application_choice]` Five meets the floor. It is also the figure Google cites through RFC
  1945, so one budget serves every documented engine.
- **After the last hop.** §2.3.1.2: "If there are more than five consecutive redirects,
  crawlers MAY assume that the robots.txt file is unavailable." Unavailable is §2.3.1.3, where
  a crawler MAY access any resource. robotstxtr maps `over_budget` to `allow_all`
  (`redirect_over_budget_allow_all` in `engine_policy_table_v1()`). `[application_choice]`:
  the RFC permits this mapping but does not require it.
- **Cross-authority.** §2.3.1.2: the file "MUST be fetched, parsed, and its rules followed in
  the context of the initial authority". `[documented]`
- **`https` → `http`.** §2.3.1.2 conditions a redirect only on the count and on the initial
  authority. It says nothing about the scheme. §2.3 gives the location as
  `scheme:[//authority]/robots.txt`, so the scheme of the *requested* file follows the
  service. `[inferred]`: an RFC crawler follows the downgrade. The RFC never forbids it, and
  §3 (Security Considerations) says nothing about redirects.
- **Size.** §2.5: "Crawlers SHOULD impose a parsing limit to protect their systems" and "The
  parsing limit MUST be at least 500 kibibytes." `[documented]` This is a floor on capacity,
  not a maximum or a rule for truncation.
- **Over the limit.** The RFC does not say what a crawler does with bytes beyond its own
  limit. `[documentation_gap]` §3 ("Memory management") only refers back to §2.5.

## Google (`google`)

Sources, all read 2026-11-05:

- G1 "How Google interprets the robots.txt specification",
  <https://developers.google.com/crawling/docs/robots-txt/robots-txt-spec>
- G2 "How HTTP status codes affect Google's crawlers",
  <https://developers.google.com/crawling/docs/troubleshooting/http-status-codes>
- G3 "Overview of Google crawlers and fetchers",
  <https://developers.google.com/crawling/docs/crawlers-fetchers/overview-google-crawlers>
- G4 RFC 1945 §9.3, <https://www.rfc-editor.org/rfc/rfc1945.html>
- G5 Google's open-source parser, <https://github.com/google/robotstxt>, vendored here at commit
  `22b355ff855419e6a3ff8ff09c0ad7fdb17116f9` (`inst/PROVENANCE`) as `src/robots.cc`.

Findings:

- **Hops for robots.txt.** G1, "3xx (redirection)": Google "follows at least five redirect hops
  as defined by RFC 1945 and then stops and treats it as a 404 for the robots.txt file."
  `[documented]` G4 §9.3: "A user agent should never automatically redirect a request more
  than 5 times". So the RFC Google cites puts the cap at five, while Google's own words say "at
  least". The two readings agree on five, so robotstxtr follows exactly five
  `[application_choice]`.
- **The 10-hop figure is not for robots.txt.** G2: "By default, Google's crawlers follow up to
  10 redirect hops", and "Googlebot generally follows 10 redirect hops when crawling for
  general web content". The same page sends robots.txt readers to G1 ("For robots.txt files,
  learn how Google handles a robots.txt that returns a `3xx` status code"). G1 is the specific
  rule and wins over G2 for robots.txt. The `google` ruleset therefore keeps 5, not 10.
  Checked against the maintainer's question "if Google documents 10 hops for robots.txt": it
  does not.
- **After the last hop.** G1: Google "stops and treats it as a 404", which is the 4xx path →
  `allow_all` (`redirect_over_budget_as_404`). `[documented]` G1 also says Google does not
  follow logical redirects (frame, JavaScript, meta refresh) in robots.txt files.
  `[documented]`, already true of robotstxtr, which follows HTTP 3xx only.
- **Cross-host.** G1 does not separately discuss a redirect to another host for robots.txt.
  It scopes the *rules* to "the host, protocol, and port number" on which the file was
  requested. `[inferred]`: followed, as engine-profiles.md §3 already records.
- **`https` → `http`.** None of G1, G2 or G3 mentions an `https` → `http` redirect. G1's hop
  rule refers to RFC 1945, which has no scheme restriction. `[inferred]`: Googlebot follows a
  downgrade within the five hops. No Google source says it refuses one.
- **Size.** G1, "File format": "Google enforces a robots.txt file size limit of 500 kibibytes
  (KiB)." `[documented]` G3's 15 MB (and "for example, 2MB") limits are for crawled files in
  general, not for robots.txt.
- **Over the limit.** G1: "Content which is after the maximum file size is ignored."
  `[documented]` Google parses the prefix up to 500 KiB.
- **The open-source code.** G5 is the parser and matcher only. It has no fetcher, so it holds
  no redirect logic, and no 500 KiB limit (grep of `src/robots.cc` for redirect and byte
  constants finds only the per-line buffer, `kMaxLineLen = kBrowserMaxLineLen * 8` with
  `kBrowserMaxLineLen = 2083`). The size limit is applied before the parser, which is why
  robotstxtr applies it at the matcher stage (`design/engine-contract-v1.md`, "Backend and
  policy revisions": "Google parses only its first 512,000 bytes"). The code adds no fetch
  value beyond G1.

## Yandex (`yandex`)

Sources, all read 2026-11-05:

- Y1 "Using robots.txt", <https://yandex.com/support/webmaster/en/controlling-robot/robots-txt>
  (Russian: <https://yandex.ru/support/webmaster/controlling-robot/robots-txt>)
- Y2 "Processing redirects",
  <https://yandex.com/support/webmaster/en/robot-workings/managing-redirects>
  (Russian: <https://yandex.ru/support/webmaster/robot-workings/managing-redirects.html>)
- Y3 robots.txt error dictionary,
  <https://yandex.com/support/webmaster/en/error-dictionary/robots-txt>

Findings:

- **Redirect target.** Y1 lists among the requirements that the file "redirects to another
  `robots.txt` file for which the server returns a 200 OK code". `[documented]`
- **Cross-host.** Y1: "Yandex supports redirection from the `robots.txt` file located on one
  site to the file located on another site", and "the directives in the target file are taken
  into account". `[documented]`
- **Hops.** Y1 gives no count. Y2 (redirect handling for pages) classifies 301/308 as permanent
  and 302/303/307 as temporary and describes in-host and host-to-host redirects, but states no
  maximum chain length and does not mention robots.txt. Searched in English and Russian
  ("количество перенаправлений", "robots.txt редирект"), on yandex.com and yandex.ru. No
  primary source found. `[documentation_gap]`
  - **Fallback, `[application_choice]`: follow 5.** The hop budget is one engine-neutral
    fetch setting (ADR-009 §3). Five is the RFC 9309 floor and what every documenting engine
    uses, so the Yandex evidence row is comparable with the others. A Yandex crawler that
    follows more hops would reach a file robotstxtr reports as `over_budget`. That difference
    stays visible as `redirect_over_budget` and is never shown as a Yandex result.
- **After the last hop.** Not stated. `[documentation_gap]`
  - **Candidate fallback, `[application_choice]`: `allow_all`.** Y1: "If the file doesn't meet
    the requirements, the site is considered open for indexing." `[documented]` A chain that
    never reaches a 200 fails the requirement that the target return 200. Mapping
    `over_budget` to `allow_all` therefore applies a documented Yandex rule to an undocumented
    trigger. That makes the mapping an `application_choice`, not `documented`. Today the
    `yandex` × `redirect_over_budget` cell is `documentation_gap`. Not adopted (maintainer,
    2026-11-05; ADR 0001): the cell stays `documentation_gap` until measured with served test
    files (ROBO-ogwchglq).
- **`https` → `http`.** Not addressed in Y1 or Y2. `[inferred]`: followed, since cross-site
  redirects are supported with no scheme condition.
- **Size.** Y1: "The file size doesn't exceed 500 KB." `[documented]` Y1 does not define KB.
  `design/engine-contract-v1.md` reads it as 500,000 bytes ("Bodies over 500,000 bytes resolve
  through the documented Yandex `allow_all` policy"). 500 × 1024 = 512,000 is the other
  reading. `[documentation_gap]` on the unit; robotstxtr's reading is an `application_choice`.
- **Over the limit.** Y1: a file that does not meet the requirements leaves the site "open for
  indexing" → `allow_all`. `[documented]` robotstxtr already applies this to a *retained*
  body. The Yandex branch of `resolve_policy_v1()` in `R/engine-contract-v1.R` turns
  `stored_bytes > 500000L` into `allow_all` with reason `yandex_file_over_500000_bytes`. A 2xx
  over the acquisition ceiling is now kept as its prefix (ROBO-ldpahknv), but its v1 evidence
  is `incomplete`, so it never reaches that branch today. The ADR's slice 8 lets a cut prefix of
  at least 512,000 bytes reach the same branch, a threshold that holds under either reading of
  the unit. Y3 has an error "Robots.txt file size limit
  exceeded", but defines it by rules ("The number of rules in the file exceeds 2048"), not
  bytes. That is future-validator material (engine-profiles.md §8).

## Bing (`bing`)

Sources searched 2026-11-05:

- B1 "How to create a robots.txt file",
  <https://www.bing.com/webmasters/help/how-to-create-a-robots-txt-file-cb7c31ec>. The page
  renders client-side and returned only its title to a fetch, so it could not be re-read
  today. engine-profiles.md §10 cites it for directives, crawl-delay, encoding and cache only.
- B2 "Bing Webmaster Tools makes it easy to edit and verify your robots.txt" (2020),
  <https://blogs.bing.com/webmaster/september-2020/Bing-Webmaster-Tools-makes-it-easy-to-edit-and-verify-your-robots-txt>.
  It describes the tester, which "operates as Bingbot and BingAdsBot would", and shows the
  file for "http://, https://, http://www, https://www". Nothing on redirects, size or
  status codes.
- B3 "URL Inspection", <https://www.bing.com/webmasters/help/url-inspection-55a30305>. Search
  snippets say the Live URL test does not follow redirects and that "Every redirect requires a
  brand-new fetch". That describes a Webmaster Tools test, not robots.txt fetching, and the
  page also renders client-side and could not be read directly. Not used.
- Searches for a Bing robots.txt redirect count and size limit (bing.com, blogs.bing.com,
  learn.microsoft.com, the open web) returned only forum posts and third-party pages that
  repeat Google's 500 KiB. Not primary, not used.

Findings:

- **Hops, after the last hop, `https` → `http`, cross-host.** `[documentation_gap]`, unchanged.
  - **Fallback for the fetch, `[application_choice]`: follow 5,** for the reason given under
    Yandex. The fetch has to stop somewhere, and the evidence row records what happened.
  - **No fallback verdict.** Every Bing policy cell stays `documentation_gap`
    (engine-profiles.md §1). A caller who wants an RFC-shaped answer selects
    `assumed_rfc9309`, which is never reported as Bing.
- **Size and over-limit.** `[documentation_gap]`, unchanged. The fetch stops at the caller's
  `max_bytes` (default 524,288). A body over it is `incomplete`, never a Bing verdict.
- **Next step (maintainer, 2026-11-05; ADR 0001).** No documentation search at each release.
  Bing's redirect, size and downgrade rules are to be measured with served test files
  (ROBO-ogwchglq, parked); until then the cells above stand.

## What this changes

Nothing executes differently because of this record. The ADR uses it for three things:

1. A per-engine hop budget is unnecessary. Every documented value is 5, so the budget stays one
   fetch setting.
2. No engine documents refusing an `https` → `http` redirect for robots.txt. Refusing one is
   robotstxtr's safety choice, not an engine rule. That is the gap the `crawler` safety level
   closes.
3. Oversized files are engine-specific in meaning: Google parses the prefix, Yandex opens the
   site, and the RFC and Bing say nothing. That belongs in the ruleset, not the fetch.

Corrections ADR 0001 makes to engine-profiles.md (the first on acceptance, the second with
slice 2):

- §3 says RFC 9309 "requires" at least five. The RFC says SHOULD.
- §2 lists `non_http_target` among the `http_protocol_error` triggers, while §3 and the code
  (`source_evidence_status_v1()`, which returns `safety_refused` whenever
  `safety_block_reason` is set, and `scheme` is set for it) make it `safety_refused`.
