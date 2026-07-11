# Yandex robots.txt tester recipe

Status: validated pilot workflow
Last verified: 2026-07-11
Tester: <https://webmaster.yandex.com/tools/robotstxt/>

This document records how to use Yandex Webmaster as a behavioral oracle for
a documented Yandex rules profile. It is a conformance aid, not proof that the
online tester and Yandex's production crawlers are identical.

## Security and workspace boundaries

- Use a dedicated Chrome profile under `_scratch/yandex-browser`; never commit
  that directory.
- The user completes Yandex authentication in the visible browser. The agent
  must stop at the authentication wall and must not type, inspect, or store
  credentials.
- Do not copy cookies, browser-profile data, screenshots containing private
  account details, or other session material into committed files.
- Use a neutral site such as `https://example.com` for rules-only experiments.
  Tested URLs must belong to the site entered in the tool.
- Record only the test body, crawler choice, input URL, decision, displayed
  winning rule, analyzer diagnostics, and observation date.

## Browser connection

The local browser harness lives at `~/Projects/browser-harness`. Follow its
`SKILL.md` for browser operation and its `install.md` for connection problems.
The editable installation can be repaired, if necessary, with:

```bash
cd ~/Projects/browser-harness
uv tool install --force -e .
```

From the `robotstxtr` repository root, launch an isolated Chrome profile with
a debugging port:

```bash
open -na "Google Chrome" --args \
  --user-data-dir="$PWD/_scratch/yandex-browser" \
  --remote-debugging-port=9222 \
  --no-first-run
```

Run browser-harness commands with the explicit endpoint:

```bash
BU_CDP_URL=http://127.0.0.1:9222 browser-harness <<'PY'
new_tab("https://webmaster.yandex.com/tools/robotstxt/")
wait_for_load()
print(page_info())
print(capture_screenshot())
PY
```

If Yandex redirects to its authorization page, stop and ask the user to sign
in. Resume only after the user confirms that the tester is visible.

## Running a batch

1. Capture a screenshot before interacting with the page.
2. Enter a neutral same-origin site URL, such as `https://example.com`, and
   click **Check**. Wait for Yandex to finish loading the site's public
   `robots.txt`; the editor then becomes available.
3. Replace the editor contents with one deliberately isolated test body and
   click the upper **Check** button.
4. Wait for the analyzer to finish. Record its error count and crawl-rule
   summary.
5. Scroll to **Access to pages** and enter one relative URL per line. Keep each
   case under a unique path prefix so rules within the shared body do not
   interact accidentally.
6. Select the crawler profile. As of the verification date, the tool offers
   `Yandex` and `YandexAdditionalBot`.
7. Click the lower **Check** button and wait for the results table.
8. Record the decision for every URL. For prohibited URLs, also record the
   winning rule displayed by the tester.
9. Re-screenshot after every submission. Yandex rerenders the page and may
   reset the scroll position.

Use visible, screenshot-guided interaction first. If a visible **Check** click
does not register, inspect the in-viewport buttons through the DOM and invoke
the visible button only; avoid fixed selectors and pixel coordinates in the
durable recipe.

## Validated pilot

Body:

```text
User-agent: Yandex
Disallow: /blocked
Allow: /blocked/public
Disallow: /*session=
Disallow: /exact$
```

Batch:

| URL | Decision | Displayed winning rule |
|---|---|---|
| `/open` | allowed | none displayed |
| `/blocked` | prohibited | `Disallow: /blocked` |
| `/blocked/public` | allowed | none displayed |
| `/foo?session=1` | prohibited | `Disallow: /*session=*` |
| `/exact` | prohibited | `Disallow: /exact$` |
| `/exactly` | allowed | none displayed |

The analyzer reported zero errors. The six-URL batch succeeded in one
submission. The tester displayed the implicit trailing wildcard for the
`/*session=` rule as `/*session=*`.

## Suggested result schema

Store future observations in a machine-readable corpus with at least:

```text
body_id,bot,url,allowed,displayed_rule,analyzer_errors,observed_at
```

Keep the robots.txt bodies themselves in separate, named fixtures so several
URLs can reference one body without duplication. Preserve the exact input
bytes where encoding behavior is under test.

## What the tester can and cannot establish

The tester can establish:

- parser acceptance and analyzer diagnostics;
- binary allow/prohibit decisions for batches of same-site URLs;
- the winning rule for prohibited URLs;
- differences between the two crawler profiles exposed by the selector.

The tester does not establish:

- exact equivalence with Yandex's production crawler;
- the winning allow rule, because the pilot UI did not display one;
- `Clean-param` canonicalization results, because that directive does not
  change the binary crawl decision;
- behavior for Yandex crawler identities not exposed by the selector;
- fetch/cache behavior that occurs outside the analyzer.

Treat undocumented observations as dated empirical behavior. Keep published
Yandex rules, analyzer behavior, and inferred production behavior distinct in
the implementation and documentation.
