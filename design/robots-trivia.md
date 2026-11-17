# robots.txt trivia

Small things seen in real files that may interest people. Most call for no change to the
package; where one led to an issue, the entry names it. Each entry gives the file and the date it
was fetched, and the line where that helps, so it can be checked again later. Files change; an
entry describes the file as it was on that date.

Entries marked *verify* rest on a claim about a third party that still needs a dated source.

## Comments

- **YouTube's robots.txt is written by the robots.** https://www.youtube.com/robots.txt
  (2026-11-18), lines 1-3: "Created in the distant future (the year 2000) after the robotic
  uprising of the mid 90's which wiped out all humans." This quotes Flight of the Conchords'
  "The Humans Are Dead" ("It is the distant future. The year 2000…").
- **Shopify hides a job ad in its robots.txt.** https://www.shopify.com/robots.txt (2026-11-18),
  lines 1-12: an ASCII-art rocket and "No need to shop around. Board the rocketship today - great
  SEO careers to checkout at shopify.com/careers".
- **Google's file cites Google's own documentation.** https://www.google.com/robots.txt
  (2026-11-18), the comment before the second `User-agent: Yandex` group: "New user agent groups
  must also have a user agent reference in the global (*) group", with a link to the
  order-of-precedence section of Google's robots.txt docs. That is a house rule, not a protocol
  rule: it is how google.com lets Yandex keep the `*` rules and add its own on top.
- **DuckDuckGo explains the tie-break correctly.** https://duckduckgo.com/robots.txt
  (2026-11-18): `Disallow: /*?` and `Allow: /?*` are the same length, and the comment says
  "Google/Bing apply the least-restrictive rule on a tie, so Allow wins for root." That is right
  for Google (RFC 9309 §2.2.2 says only SHOULD).
- **chatgpt.com writes for two kinds of parser at once.** https://chatgpt.com/robots.txt
  (2026-11-18): "Place allows first to avoid bots skipping after Disallow: /" (for parsers that
  stop at the first match), then, after `Disallow: /`, "Specific disallows (redundant for some
  bots, but still useful for those that respect precedence)" (for longest-match parsers).
- **Shopify's default template knows AdsBot ignores `*`.** Seen on https://www.gymshark.com/robots.txt
  (2026-11-18), a Shopify store: "Google adsbot ignores robots.txt unless specifically named!",
  above a `User-agent: adsbot-google` group. The comment overstates it: AdsBot ignores
  `User-agent: *` only, not robots.txt as a whole.
- **WordPress.com asks crawlers to use its firehose.** https://wordpress.com/robots.txt
  (2026-11-18), line 1: "If you are regularly crawling WordPress.com sites, please use our
  firehose to receive real-time push updates instead." The file also ends with the time it was
  generated.

## Names that no longer exist, and look-alikes

- **Bing names a crawler Microsoft no longer lists.** https://www.bing.com/robots.txt
  (2026-11-18), line 1: `User-agent: msnbot-media`, with `Disallow: /` and `Allow: /th?`. MSNBot
  was replaced by Bingbot; *verify* that Bing's current crawler list has no msnbot-media.
- **Baidu still writes rules for MSNBot.** https://www.baidu.com/robots.txt (2026-11-18): it names
  Googlebot, MSNBot, YoudaoBot, six `Sogou …` names, Sosospider and others, then ends with
  `User-agent: *` / `Disallow: /`. Every crawler it does not name, Bingbot included, is shut out,
  unless Bingbot still reads MSNBot groups (*verify*).
- **Alexa's crawler is still blocked four years after Alexa closed.** `User-agent: ia_archiver`
  appears in https://duckduckgo.com/robots.txt, https://www.ecosia.org/robots.txt and
  https://claude.ai/robots.txt (all 2026-11-18). Amazon shut down Alexa.com in May 2022. The
  block may still be deliberate: the Internet Archive's Wayback Machine long honored
  `ia_archiver` rules when deciding what to show (*verify* whether it still does).
- **Yahoo blocks a search engine that shut down.** https://www.yahoo.com/robots.txt (2026-11-18)
  lists `Neevabot`; Neeva closed in 2023. The same group blocks the search engines Seznam,
  PetalBot (Huawei) and YouBot.
- **chatgpt.com blocks Anthropic's old names, not its current one.** https://chatgpt.com/robots.txt
  (2026-11-18) blocks `anthropic-ai` and `Claude-Web`, names Anthropic's current crawler
  documentation does not list, and does not name `ClaudeBot`, which therefore falls back to `*`.
  https://claude.ai/robots.txt (same day) blocks OpenAI's current `GPTBot`, `OAI-SearchBot` and
  `ChatGPT-User`, plus `Google-Extended`.
- **A hyphen that isn't one.** https://chatgpt.com/robots.txt (2026-11-18), line 42:
  `User-agent: Perplexity‑User` is spelled with U+2011 NON-BREAKING HYPHEN, so no parser that
  compares bytes matches it to `Perplexity-User`.
- **Blocking a tool that does not read robots.txt.** `User-agent: img2dataset` in chatgpt.com and
  yahoo.com (2026-11-18). img2dataset's README describes honoring `X-Robots-Tag` headers
  (`noai`, `noimageai`), not robots.txt (*verify*). Yoast's file blocks `Go-http-client` and
  `Node/simplecrawler`, which are HTTP client libraries rather than crawlers
  (https://yoast.com/robots.txt, 2026-11-18).
- **A Microsoft crawler with no documented name.** https://wordpress.org/robots.txt
  (2026-11-18) allows `User-agent: Copilot`; *verify* whether Microsoft documents such a token.

## Case

- **Yandex lists five casings of one path.** https://yandex.com/robots.txt (2026-11-18):
  `/MAPS/`, `/MaPS/`, `/MapS/`, `/Maps/`, `/mApS/`. Paths match case-sensitively (RFC 9309 §2.2.2,
  SHOULD), so the other eleven casings of `maps` stay open.
- **Bing does the same on a server that ignores case.** https://www.bing.com/robots.txt
  (2026-11-18): `/search` and `/Search`, `/profile/history?` and `/proFile/history?`.
- **Forbes names the same bot twice in different case.** https://www.forbes.com/robots.txt
  (2026-11-18): `CCBot` and `CCbot`, `cohere-ai` and `Cohere-AI`, `meta-externalagent` and
  `Meta-ExternalAgent`, each pair in one group. Product tokens match case-insensitively
  (RFC 9309 §2.2.1, MUST), so the second line of each pair changes nothing.

## Serving

- **Forbes sends gzip to clients that asked for none.** https://www.forbes.com/robots.txt
  (2026-11-18) answers with `Content-Encoding: gzip` even to `Accept-Encoding: identity`.
  robotstxtr's fetches go through ssrfr, which sends `Accept-Encoding: gzip, deflate` when libcurl
  has zlib, so its fetch is unaffected; a client that asks for plain text
  and doesn't decode gets 8 KB of compressed bytes instead of a 33 KB robots.txt (ROBO-rozvglkd).
- **Naver serves its robots.txt as a binary file.** https://www.naver.com/robots.txt
  (2026-11-18) comes as `application/octet-stream` and writes `Allow : /$` with a space before
  the colon. It blocks everything except the homepage, for every crawler.

## Odd shapes

- **The AI labs mostly allow everything.** openai.com, anthropic.com, mistral.ai,
  huggingface.co, x.ai and cohere.com (2026-11-18) all have `User-agent: *` with `Allow: /` or
  next to nothing blocked. x.ai adds `Content-Signal: ai-train=yes, search=yes, ai-input=yes`.
  https://www.perplexity.ai/robots.txt (same day) names only Googlebot.
- **A "welcome, AI" group that also opens the admin area.** https://wordpress.org/robots.txt
  (2026-11-18) gives GPTBot, ClaudeBot and seven others `Allow: /` groups. A named group replaces
  `*`, so those crawlers also lose the `*` group's `Disallow: /wp-admin/`, `/search` and `/?s=`.
- **Profound allows what is already allowed.** https://www.tryprofound.com/robots.txt
  (2026-11-18): `Allow: /`, then `Allow: /llms.txt`.
