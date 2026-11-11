# Engine-aware robots evaluation contract v1

- Contract ID: `robotstxtr.engine-aware/v1`
- Schema revision: `2026-11-08.1`
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
  for the reopened address ranges, ordered redirect hops and exact stored body
  bytes;
- `contract`: the value returned by `robots_engine_contract_v1()`.

Each result expands and persists the ruleset, ruleset revision, matcher backend,
matcher revision, robots product token, HTTP User-Agent, acquisition byte/time
limits, redirect limit, SSRF and HTTPS-downgrade guards, and engine body limit.
It then reports `evidence_status`, `policy_status`, `policy_action`, policy
reason/provenance/source, `matcher_availability`, `matcher_status`, the optional
`url_decision`, and a final reason. A missing `url_decision` is intentional and
must not be coerced to allow or deny.

## Safety level

Schema revision `2026-11-08.1` (ADR 0001, ROBO-pezlychx) adds `safety_level` to
`robots_evaluate_url_v1()` and to the three legacy functions that fetch
(`robots_fetch()`, `allowed_by_robots_url()`, `robots_validate_url()`). It
decides what the fetch may do on the network and is independent of
`robots_policy_ruleset`; neither defaults from the other. The contract
publishes the value set as `safety_levels`: `strict`, the default, and
`crawler`. `strict` is the acquisition of every earlier revision, unchanged.
`crawler` follows an `https` to `http` redirect as an ordinary hop within the
five-redirect budget (ROBO-lwdxzdhw); every address the guard refuses is still
refused, as under `strict`, until ROBO-jqwukcog records an address-class
refusal as `unreachable_local`. Any other value is a call-level error of class
`robotstxtr_invalid_safety_level`. The levels are defined in
[`engine-profiles.md`](engine-profiles.md) §3a.

The evidence frame gains two columns. `safety_level` (character) is the level a
source was fetched under. `fetch_allow_ranges` (a list column) holds the CIDR
ranges the caller passed in that argument, `character()` on every fetched row
until it lands; a deprecated `ssrf_guard = FALSE`, which reopens every range,
is recorded in `ssrf_guard`, not here. Both are `NA` on a row with no
acquisition, a supplied body: there the list cell is `NA_character_`, length
one, so tell a supplied row by `source_kind`, not by `lengths()`. `https_downgrade_guard` is
`safety_level == "strict"` on a fetched row: `TRUE` under `strict`, as before,
`FALSE` under `crawler`, and `NA` where no acquisition was configured. The result columns and the legacy
frames are unchanged.

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
decision. The one reading of incomplete acquisition is a ruleset's documented
meaning of a 2xx cut at `max_bytes` (`engine-profiles.md` §7): under `yandex`,
a cut that stored at least 512,000 bytes is a file over Yandex's 500 KB limit,
which is `allow_all` (ROBO-arrtietl); under `google` with the `google`
matcher backend, a cut that stored at least 512,000 bytes holds the whole
window Google parses, so it is matched on the complete lines inside that
window (ROBO-ptibdnvy).

## Backend and policy revisions

Google matching uses the vendored matcher pinned to upstream commit
`22b355ff855419e6a3ff8ff09c0ad7fdb17116f9`. The backend revision embeds that
SHA. The Google 500 KiB limit is applied at the matcher stage: the neutral
evidence retains a complete caller-supplied or within-acquisition-limit body,
and Google parses only its first 512,000 bytes, up to the last complete line
within them: a line the window cuts is dropped, as for a body cut at
`max_bytes` (ROBO-ldpahknv below), and a window with no line break feeds no
rules. `matcher_input_bytes` is the bytes fed to the matcher, after that drop;
`matcher_body_truncated` is `TRUE` whenever the body exceeded the window. A fetched 2xx body over the
acquisition limit is retained as its first `max_bytes` bytes, marked
`body_truncated` and `incomplete`, and not matched by the v1 engines, with
two exceptions for a cut of at least 512,000 bytes: under `yandex` it resolves
`allow_all` with no matcher (ROBO-arrtietl), and under `google` with the
`google` backend it is matched
on the complete lines of its first 512,000 bytes, with
`matcher_body_truncated` `TRUE` (ROBO-ptibdnvy). The legacy path matches every
cut, up to its last complete line (see "A robots.txt over `max_bytes`"
below).

The Yandex matcher backend is `available` (as of schema revision
`2026-07-18.2`). It is bounded to its supported Yandex vendor profiles
(profile `yandex-0.1.0`) and never generalizes to arbitrary tokens or falls
back to Google. Its backend revision is the composed, byte-frozen
`robotstxtyandex/0.2.0+payload.<commit>;profile=yandex-0.1.0;corpus=<rev>;evidence=<sha>;profile-source=<rev>`
string, byte-equal to `inst/vendor/robotstxtyandex/MANIFEST.dcf`'s
`MatcherRevision`. The separately inspectable library/payload/profile/corpus/
evidence/profile-source fields are published as
`robots_engine_contract_v1()$matcher_identity$yandex`.

The activation schema adds one public list column, `matched_rule_value_raw`,
with exactly one element per result row: exact owning-rule bytes for a matched
rule, `raw(0)` for an effective-empty Disallow, and `NULL` for an absent rule
(evaluated `default_allow` and every non-evaluated outcome). `raw(0)` and
`NULL` are semantically distinct and remain distinct through construction,
subsetting, and serialization. The column is populated for Yandex-evaluated
rows; Google and other rows keep `NULL`. The legacy adapter frame does not
carry this column.

For an evaluated Yandex row the published `reason` is exactly one of
`default_allow`, `rule_allow`, `rule_disallow`, or `effective_empty_disallow`
(the effective-empty case yields `url_decision = "allow"` with
`matched_rule_type = "disallow"` and an empty value). For a non-evaluated
Yandex row the matcher status is `not_evaluated` with either
`reason = "unsupported_product_token"`
(`error_class = "robots_unsupported_product_token"`) or
`reason = "invalid_request_target"`
(`error_class = "robots_invalid_request_target"`), both at
`error_stage = "input"`; `unsupported_crawler` takes precedence when both a
target and a token are invalid. A fetched body over 500,000 bytes resolves
through the documented Yandex `allow_all` policy before the matcher runs
(`matcher_status = "not_needed"`); a supplied or local body stays `use_rules`
(`supplied_body_use_rules`) at any size. A 2xx cut at `max_bytes` that stored at
least 512,000 bytes
is a file over 500 KB under either reading of the unit, so it resolves
`allow_all` too, while its `evidence_status` stays `incomplete`
(ROBO-arrtietl): a cut 200 with the same `yandex_file_over_500000_bytes`
reason, a cut non-200 2xx with `non_200_allow_all` from the policy table, as
its uncut form does. A smaller cut stays `incomplete_evidence`.

A Google row reports no line for a rule with an empty value. When the rule that
Google's matcher selects is an `Allow:` or `Disallow:` with nothing after the
colon (also `Disallow: # comment`), the row reports `url_decision = "allow"`,
`reason = "default_allow"`, `matched_rule_type = "none"`, `matched_line` and
`matched_rule_value` `NA`, and `matched_rule_value_raw` `NULL`, although the
native engine records that line as the match. This follows the PRD's "Match
metadata rules" (§6.6: an empty-path directive is ignored and surfaces as
`default_allow`); the Google adapter and its reference row matcher
`match_google_v1()` apply it to v1 Google rows, and the
legacy functions and `as_legacy_robots_decisions_v1()` report the same
`decision_source`, type, line and value. The decision equals Google's. Yandex
differs: when the selected rule is an empty `Disallow`, the row reports
`effective_empty_disallow` with that rule's line.

RFC 9309 matcher requests return `matcher_status = "capability_unavailable"`
(reason `matcher_capability_unavailable`; the rfc9309 revision is
`capability-unavailable-v1`). Bing matcher
requests are available, bounded to its supported vendor profiles
(`bounded_profiles`). The RFC 9309 and Bing policy tables still resolve
independently where the accepted design has evidence. Bing fetch/status policy
remains a `documentation_gap`; `assumed_rfc9309` is a separately named
application policy and is never reported as Bing.

## Legacy compatibility

The existing `allowed_by_robots_text()`, `allowed_by_robots_url()`,
`robots_fetch()`, and `robots_body()` remain unchanged, apart from the additive
Retry-After and Content-Type columns below. For consumers migrating
incrementally, `as_legacy_robots_decisions_v1()` explicitly converts a v1 result
whose policy and matcher are both Google into the original `robots_decisions`
schema. The adapter deliberately keeps legacy generic HTTP/redirect failures
unknown even where the new Google policy has a documented `allow_all` action;
this prevents a silent semantic change in old consumers.

### Retry-After on legacy fetch rows (ROBO-cthdyvlk)

Every `robots_decisions$robots` and `robots_fetches$robots` frame gains two
columns between `error_message` and `body`, so the frame has one schema
whichever function built it:

| column | type | value |
|---|---|---|
| `retry_after` | character | The final response's `Retry-After` field value as ssrfr delivers it (optional whitespace trimmed, obs-fold unfolded), several fields joined with `", "`; `NA` when not available. |
| `retry_after_seconds` | double | The delay it asks for (RFC 9110 §10.2.3): `delay-seconds` as is, or an HTTP-date (any of the three RFC 9110 §5.6.7 forms) less the response's `Date`, or less the fetch time when `Date` is absent or invalid; a past date is `0`; `NA` when not available or neither form. Unbounded, since RFC 9110 sets no maximum: the caller clamps it. |

`robots_fetch()` and `allowed_by_robots_url()`, which carries its frame
unchanged, fill them. "Final response" is the non-3xx response that ends the
chain; a redirect's `Retry-After` never counts.

`NA` means "not available", not "no delay requested". Besides a final
response without the field, that covers an outcome with no usable final
response: a refusal, a transport failure, a `redirect_error`, and a body
over `max_bytes` with a 3xx status, an unknown status, or a 2xx whose libcurl
and status-line statuses disagree. A 2xx body over `max_bytes` that is cut is a
final response (ROBO-ldpahknv below), so its `Retry-After` is kept. A 4xx or 5xx whose body
exceeds `max_bytes` keeps its
status and outcome, but ssrfr's size failure carries no headers, so its
`Retry-After` is `NA` even when the server sent one. robotstxtr never
retries; the caller decides whether to wait.

`allowed_by_robots_text()` (a supplied body) and
`as_legacy_robots_decisions_v1()` (the v1 evidence keeps no Retry-After)
always write `NA`. The v1/v2 `evidence` frame and the `robots_validate_url()`
`documents` frame (which copies named fetch fields, not the row) are
unchanged, so the engine schema revision does not move.

Decision: keep `Retry-After` only, not a generic list of the final response's
headers. A header list would publish ssrfr's header representation as
robotstxtr API and carry fields no caller acts on. Each header a caller needs
gets its own typed column: `Content-Type` and its content flags are the
follow-up ROBO-nhuirvrd.

### Content-Type and the content flag on legacy fetch rows (ROBO-nhuirvrd)

Every `robots_decisions$robots` and `robots_fetches$robots` frame gains two
more columns, between `retry_after_seconds` and `body`, under the same "final
response" rule and the same legacy-schema scope as Retry-After above:

| column | type | value |
|---|---|---|
| `content_type` | character | The final response's `Content-Type` field value as received, several fields joined with `", "`; `NA` when absent or when there is no final response. Any status, not only 2xx. |
| `content_flag` | character | A heuristic read of the first 4096 bytes of the stored body; `NA` when there is no stored body (only `fetched` stores one), the body is empty, or nothing matches. |

`robots_fetch()` and `allowed_by_robots_url()` fill them.
`allowed_by_robots_text()` (a supplied body, no response) and
`as_legacy_robots_decisions_v1()` (the v1 evidence keeps neither) always
write `NA` in both.

`content_flag` has a closed vocabulary; the first match wins:

1. `binary`: a NUL byte, or at least 8 of the window's bytes, and more than
   10% of them, not part of valid UTF-8 (so a short Latin-1 file is not
   binary). NULs are still dropped before matching (`R/body-decode.R`).
2. `html`: a line starting, after whitespace or a UTF-8 BOM, with
   `<!doctype html`, `<html`, `<head` or `<body`, in any letter case,
   possibly after `<?...?>` declarations and `<!--...-->` comments that close
   on that same line. An HTML error page lands here. So does a body whose
   first non-whitespace byte is `<` and whose window holds `<!doctype html`,
   `<html`, `<head`, `<body`, `<script` or `<style` anywhere, in any letter
   case, followed by whitespace, `>`, `/` or the window's end: a minified
   page opening with inline script or style (ROBO-qquftxcx). `<title`,
   `<link` and `<meta` are left out, since RSS and Atom feeds use them.
3. `xml`: the first non-whitespace byte is `<`. No robots.txt line starts
   with `<`; a `<` inside a comment or a value never flags. Markup without
   any of the six markers above, such as a feed or tag soup, lands here, not
   in `html`.
4. `json`: the body opens with a JSON object (`{` then `"` or `}`) or array
   (`[` then a value or `]`).

Decisions:

- The flag only flags. The body is matched exactly as before, so no allow or
  disallow decision, `fetch_outcome` or v1 `evidence` field depends on it.
- The flag is read from the body only. `Content-Type` is reported, never
  read: servers mislabel both ways (a robots.txt served as `text/html`, an
  HTML page as `text/plain`), and two independent columns let a caller
  compare them instead of receiving robotstxtr's blend.
- One character column with a closed vocabulary, not one logical per kind:
  the kinds are exclusive under the first-match order, a new kind is a new
  value rather than a new column, and a caller filters on `!is.na()`.
- Plain-text error pages ("404 Not Found" served with a 200) are not
  detected: no cheap test separates them from a short robots.txt.

### A robots.txt over `max_bytes` (ROBO-ldpahknv)

RFC 9309 §2.5 lets a crawler impose a parsing limit of at least 500 KiB and
parse the part of the file it read. robotstxtr fetches with ssrfr's
`truncate_body`, so a 2xx body over `max_bytes` comes back as its first
`max_bytes` decoded bytes instead of failing. The cut falls at a byte and may
split a character.

| surface | a 2xx over `max_bytes` |
|---|---|
| `fetch_outcome` (legacy `robots` and `map` rows, v1 `legacy_fetch_outcome`) | `fetched`, with no error fields |
| legacy `body`, `body_size` | the first `max_bytes` bytes; `body_size` equals `max_bytes` |
| legacy `body_truncated` | `TRUE`; `FALSE` on every other row |
| `robots_validate_url()` documents | the prefix is validated up to its last complete line; `body_truncated` and `limit_exceeded` are `TRUE`, `final_newline` is `NA`, `byte_size` is the stored size; one `body_truncated` warning diagnostic, no `acquisition_limit_exceeded` |
| legacy matching (`allowed_by_robots_url()`) | the prefix is matched up to its last CR or LF; the partial line after it, and every rule after the cut, do not exist; a prefix with no line break yields no rules |
| `content_flag` | read from the prefix; a split character at the end is at most three invalid bytes, under the eight `binary` needs |
| v1 `body_present`, `stored_bytes` | `TRUE`, `max_bytes` |
| v1 `body_truncated` | `TRUE`; `FALSE` on every other row |
| v1 `observed_bytes` | ssrfr's count of the decoded bytes reached, past the limit by up to one delivery; not the file's size, which is never read |
| v1 `termination_reason` | `ceiling` |
| v1 `evidence_status` | `incomplete`, as before: no v1 policy verdict or URL decision is made from a prefix, except for a cut of at least 512,000 bytes: the `yandex` ruleset's `allow_all` (ROBO-arrtietl) and the `google` ruleset's match, with the `google` backend, of the complete lines in its first 512,000 bytes (ROBO-ptibdnvy) |

A body over `max_bytes` with a 3xx status, an unknown status, or a 2xx whose
libcurl and status-line statuses disagree is still `body_too_large` with no
body, and a 4xx
or 5xx still keeps its status outcome with no body: ssrfr truncates only a 2xx.
A 206 stays `partial_response` with no body.

Decisions:

- `fetch_outcome` stays `fetched`; no `fetched_truncated` value. The legacy
  `fetch_outcome` set is closed in practice: `allowed_by_robots_url()` matches
  only `fetched` rows and classifies every other value it knows as a fetch
  failure, so a new value would leave the prefix unmatched and its rows with
  no `decision_source`. The cut is carried by `body_truncated`,
  `observed_bytes` and `termination_reason`, which the v1 evidence already
  publishes. No v1 enum or column changes, so the engine schema revision does
  not move. The values of a v1 row over the ceiling do change: it now carries
  `legacy_fetch_outcome = "fetched"`, `body_present = TRUE`, `stored_bytes =
  max_bytes` and `body_truncated = TRUE`, while `evidence_status` is still
  `incomplete`.
- The v1 evidence of a cut body stays `incomplete`. `engine-profiles.md`
  §2 maps `termination_reason = ceiling` there, and a prefix cannot stand in
  for a whole file under every engine: Yandex's documented over-500 KB
  `allow_all` needs the file's real size, which a prefix under a smaller
  `max_bytes` hides. The ruleset reads the cut instead (ADR 0001 §5, slice
  8; ROBO-arrtietl): a `yandex` cut that stored at least 512,000 bytes
  proves the file is over 500 KB under either reading of the unit, so
  `resolve_policy_v1()` lets it past the `incomplete` return to the policy
  table: a cut 200 reaches the existing size branch, `allow_all` /
  `yandex_file_over_500000_bytes` `[documented]`, and a cut non-200 2xx
  resolves `allow_all` / `non_200_allow_all` `[documented]`, as its uncut
  form does. The evidence row is unchanged, the schema revision does
  not move, and the yandex policy revision moves to
  `yandex-robots-policy-2026-11-09`.
- Under `google` (ADR 0001 §5, slice 9; ROBO-ptibdnvy), a cut that stored
  at least 512,000 bytes holds the whole window Google parses, so, when the
  matcher backend is `google` too, `resolve_policy_v1()` lets it past the
  `incomplete` return to the policy
  table cell of its uncut form: a cut 200 resolves `use_rules` /
  `http_200_use_rules` `[documented]` and a cut non-200 2xx `use_rules` /
  `http_2xx_use_rules` `[documented]`, with no new reason. The row is
  matched on the cut body's complete lines (the bullet on matching below),
  then on Google's 512,000-byte window, so a cut of exactly 512,000 bytes
  loses its partial last line as a longer cut does. With `max_bytes`
  exactly 512,000, a line whose break falls at byte 512,001 is dropped,
  although the uncut file would keep it inside the window: the break is not
  stored, and dropping the line is the cautious reading, tagged
  `[application_choice]` in `engine-profiles.md` §7. `matcher_body_truncated`
  is `TRUE` for every such row, since the cut proves the file exceeded the
  window. A smaller cut stays `incomplete_evidence`; a google-ruleset cut
  with another matcher backend stays `incomplete_evidence` too, since the
  reading is the google matcher's; and `rfc9309`, `assumed_rfc9309` and
  `bing` keep every cut incomplete. The evidence row
  and the schema revision do not move. The google policy revision
  `google-robots-policy-2026-11-09`, not yet released, covers both the
  512,000-byte window (ROBO-phfbpfiy) and this reading of the cut.
- Every legacy `robots` frame gains a logical `body_truncated` column,
  between `content_flag` and `body`, under the one-schema rule of the
  Retry-After and Content-Type columns above: `robots_fetch()` and
  `allowed_by_robots_url()` fill it from the fetch, `allowed_by_robots_text()`
  writes `FALSE` (the caller supplied the whole text), and
  `as_legacy_robots_decisions_v1()` copies the v1 evidence's `body_truncated`.
- Matching and validation stop at the cut body's last CR or LF. The cut
  usually lands inside a line, and the partial line is not the site's rule:
  `Disallow: /private-drafts/` cut to `Disallow: /` would disallow
  everything. Dropping it is the cautious reading; the stored `body`,
  `body_size` and v1 `stored_bytes` keep every byte ssrfr returned.
- `as_legacy_robots_decisions_v1()` leaves `error_class` `NA` on a cut
  source's rows. Under 512,000 stored bytes they are `fetched`,
  `allowed = NA`, `fetch_unknown`: the legacy `error_class` set has no class
  for a cut body, and the v1 `reason` `incomplete_evidence` is not a legacy
  class. At or above it the rows are matched (ROBO-ptibdnvy) and carry
  `allowed` and the match `reason` as `decision_source`, read from the first
  512,000 bytes, where `allowed_by_robots_url()` reads the whole stored
  prefix. Its documentation says so.
  `observed_bytes` stays in the v1 evidence only.
- `robots_validate_url()` validates a cut prefix and reports the cut in its
  documents frame. A body refused whole (a 3xx, an unknown status, or a 2xx
  whose libcurl and status-line statuses disagree, over `max_bytes`) is still
  `not_validated` with `acquisition_limit_exceeded`.
- `max_bytes` below RFC 9309's 500 KiB floor (`512000`) stays accepted, and
  is documented as below it. The default, `524288`, meets the floor.

### Redirect and safety reasons in the legacy frame (ROBO-bsloeclp)

Every legacy `robots` frame gains two character columns, `terminal_redirect_reason`
and `safety_block_reason`, between `body_truncated` and `body`, under the
one-schema rule of the columns above. `robots_fetch()` and
`allowed_by_robots_url()` fill them from the fetch, `allowed_by_robots_text()`
writes `"none"` and `NA` (no fetch took place), and
`as_legacy_robots_decisions_v1()` copies the v1 evidence's columns of the same
names, which already carried both. No v1 enum or column changes, so the engine
schema revision does not move. `robots_validate_url()` reads the two columns to
give redirect, transport and safety outcomes their own diagnostic codes;
`acquisition_failed` stays the code for an outcome no class covers.

## Sibling compatibility

The supported first-release ranges are:

- sitemapr `>= 0.0.0.9000, < 0.1.0`;
- sitemap-validator `>= 1.0.0, < 2.0.0`.

Consumers must negotiate the contract ID and schema revision, not infer support
only from the robotstxtr package version.

## Registering another matcher backend

Backend dispatch and revision/capability metadata live together in
`R/engine-contract-v1.R`. `evaluate_rows_v1()` dispatches on the registry
entry alone, never on a backend's name (ROBO-bukqpjli): it collects the rows
that need a matcher, calls each backend's adapter once with all of its rows,
and scatters the decision frame back. Google, Yandex and Bing all sit behind
the same interface.

A **matcher adapter** is `callable(bodies, urls, product_tokens)`: a list of
raw bodies and two character vectors, one element per row. It returns a
**decision frame**, a data frame with one row per input row, in input order,
carrying `matcher_status`, `url_decision`, `reason`, `matched_line`,
`matched_rule_type`, `matched_rule_value`, `matcher_input_bytes`,
`matcher_body_truncated`, `error_stage`, `error_class`, `error_message` and
the list column `matched_rule_value_raw` (`matcher_decision_columns_v1()`).
Extra columns (`native_*`) and attributes (`n_parse_calls`) are allowed and
ignored. Every per-row outcome, an unsupported profile included, is a row;
an adapter aborts only on an internal invariant violation, and the evaluator
does not catch that abort. The evaluator checks each frame's row count and
columns (`check_matcher_output_v1()`) and fails with
`robotstxtr_matcher_output_invariant` when either is wrong, as it fails on a
status outside the published set.

The evaluator hands an adapter the readable body: a body cut at `max_bytes`
(read only under the `google` ruleset with the `google` backend) has its
partial last line dropped first, and each row's own cut is OR-ed into the
frame's `matcher_body_truncated`. In the Google adapter the matcher parses
each distinct body once, cut to Google's 512,000-byte window, and the line
collector reads each body that has a matched row once more; row for row it
gives what its reference row matcher `match_google_v1()` gives, and its
`matched_rule_value_raw` is `NULL`.

To add a backend without changing the core result schema:

1. complete the engine-profile gate: released contract, deterministic corpus,
   ABI and version review, provenance, and compatible licensing;
2. write its matcher adapter, returning the decision frame above;
3. atomically register that adapter, its exact revision, and its `available`
   capability in `engine_matcher_registry_v1()` under the explicit backend
   name; the registry invariants reject partial or inconsistent activation.
   A backend name the registry does not have yet must also be added to
   `engine_matchers_v1()` and to `engine_backend_capability_v1()`; the
   evaluator itself needs no change;
4. add its conformance corpus and end-to-end facade tests, and run it through
   the shared adapter-output test helper
   (`tests/testthat/helper-matcher-registry-bukqpjli.R`); and
5. issue a new schema revision if any enum or column must change. Adding a
   backend implementation alone does not change the v1 result columns.

Tests swap an engine by swapping its registry entry (a fake registry passed
as `evaluate_rows_v1()`'s internal `matcher_registry` argument, or installed
for the public entry points with `local_matcher_registry()`), not by mocking
a matcher function. The public entry points take no registry.

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

## Accepted matcher-profile selectors

A backend whose `token_policy` is `bounded_profiles` accepts a closed set of
selectors and rejects everything else. As of schema revision `2026-08-25.1`
that set is published, so a consumer can validate its configuration before
evaluating anything instead of discovering the mistake in the results.

Each such backend's `matcher_capability` entry carries three additional fields:

- `product_token_role` — always `matcher_profile_selector`. The value names
  what the token IS: a robots.txt `User-agent:` group selector, not an HTTP
  `User-Agent` crawler identity. RFC 9309 treats those as one namespace;
  Yandex does not, because its umbrella label `Yandex` is a group name no
  crawler ever sends.
- `product_token_comparison` — always `ascii_case_insensitive_exact`. ASCII
  case folding, exact whole-token match, no trimming, no prefix or suffix
  matching, no aliases.
- `supported_profiles` — a data frame with columns `profile_id`,
  `accepted_token`, `group_label`, `group_selection`, `profile_revision`.

`group_selection` is normative and takes one of two values:

| value | meaning |
|---|---|
| `exact_else_wildcard` | Merge every group naming this token exactly. Only if no such group exists, merge the `User-agent: *` groups. |
| `exact_only` | Merge every group naming this token exactly, and never fall back to a wildcard group. A robots.txt containing only `User-agent: *` constrains this profile not at all. |

The published sets:

| backend | `accepted_token` | `group_selection` |
|---|---|---|
| `yandex` | `Yandex` | `exact_else_wildcard` |
| `yandex` | `YandexAdditionalBot` | `exact_only` |
| `bing` | `bingbot` | `exact_else_wildcard` |
| `bing` | `adidxbot` | `exact_only` |

The two accepted tokens within a backend are therefore **not
interchangeable**, which is why the contract publishes rows rather than a bare
token vector. The `exact_only` pattern is vendor-neutral: the Yandex
"Additional" family and Bing's AdIdxBot both behave this way.

A backend whose `token_policy` is `arbitrary_valid` (`google`) or `rfc9309`
publishes none of the three fields — its accepted set is not closed, so there
is nothing to enumerate. `rfc9309` is both `capability_unavailable` and
unbounded; it publishes no profile table for the second reason, not the first.

Passing an unaccepted selector is not an error at evaluation time, and the two
backends do not report it identically:

| backend | `matcher_status` | `reason` | `error_class` |
|---|---|---|---|
| `yandex` | `not_evaluated` | `unsupported_product_token` | `robots_unsupported_product_token` |
| `bing` | `unsupported_profile` | `unsupported_profile` | `robots_unsupported_profile` |

The Yandex shape is the quieter of the two: a caller who does not inspect
`reason` sees an evaluation in which nothing was decided, which reads like a
transport failure rather than a configuration mistake. That is the failure this
publication exists to prevent.
