# Backend alignment and comparison work

Coordination snapshot: as of 2026-11-23 (first written 2026-11-19). The fp
tracker and the owning repository's committed evidence remain authoritative;
refresh both before dispatching work. This guide is the entry point from a
robotstxtr session for work across Google, robotstxt-cpp-bing and
robotstxtyandex. Its machine-readable companion is the
[evidence inventory](#evidence-inventory-robo-lohuovpm),
`design/backend-evidence-inventory.tsv`.

## Priority and ownership

Prioritize fidelity of each backend to its adopted evidence before interpreting
backend differences as differences between real engines. Alignment preserves
legitimate differences; it does not make the three matchers return one answer.
Google is checked against a pinned pristine upstream. Bing and Yandex are
independent compatibility implementations, bounded by their accepted evidence.
Neither their libraries nor their webmaster testers establish production crawler
parity.

Implementation issues stay in their owning repository. Robotstxtr owns adapter
integration, adopted-payload regression coverage, the comparison and downstream
impact handoff. The tables below index 15 Bing and 5 Yandex issues open at the
snapshot date, BING-jekrqonq counted among them although it merged that day,
and list the ones that landed on 2026-11-23 as closed prerequisites.
Reciprocal tracker comments point back here for the 25 issues that existed on
2026-11-19. Issues filed later (BING-jekrqonq, BING-nayqrubx, BING-sttdkzpf,
BING-zwzuhnqg, BING-zrwhebav, YDX-uawkbqtk, YDX-sosxgkbk, YDX-gqordtdu) have no
back-pointer yet. No upstream implementation issue is duplicated as an empty
coordination ticket.

## Symmetric edge-case checks

Owner rule, 2026-11-19: edge-case checks are symmetric across Google, Bing and
Yandex. A behavior found on one engine gets the same probe on the other two, or
is marked "not testable" with the reason. It is applied in
ROBO-tvcnkkdi (the target URL encoding matrix across all three engines) and in
ROBO-mtjcdmjm, where the Yandex User-agent prefix findings behind ROBO-hegmdbon
are to be mirrored in the Bing tester.

## Delivery outcomes

| Outcome | Tracker | Completion boundary |
| --- | --- | --- |
| Corrected backend integration | ROBO-xwzztzqh | Existing batched re-vendor and eight correction outcomes; remains part of ROBO-kgqlcpjn, the 0.4.0 release. |
| Reproducible comparison and study handoff | ROBO-idxyoxnv | Five child outcomes below; separate from the 0.4.0 release scope. |
| Evidence, coverage and work routing | ROBO-lohuovpm | Versioned evidence inventory; source, local-library, tester and crawler claims separated; every remaining gap owned. Delivered as `design/backend-evidence-inventory.tsv` and the section below. |
| Google source-audit conformance corpus | ROBO-zjkemhjf | Durable, reproducible selected cases from the 122-case source audit. The tracker shows it `todo` on 2026-11-23, while [the findings record](google-source-audit.md), titled for it and landed by ROBO-vxmeoqcr, calls itself the committed outcome. Which one stands is the owner's call. The record's two deferred items are routed to it in the inventory. |
| Google index-fallback boundaries | ROBO-yuqtnqbj | Done: the gf `index` family and `test-google-index-fallback-yuqtnqbj.R`. Kept here as a closed prerequisite so the family is not re-derived. |
| Versioned union replay | ROBO-tnbhhzvk | One manifest for all three backend identities, exact comparable inputs, historical versus corrected-pin outputs and explicit exclusions. |
| Comparison catalog and study-impact handoff | ROBO-gqcjmekm | Evidence-qualified catalog, old/new impact manifest and downstream ticket ownership. |

The comparison epic composes ROBO-lohuovpm, ROBO-zjkemhjf,
ROBO-yuqtnqbj, ROBO-tnbhhzvk and ROBO-gqcjmekm. ROBO-tnbhhzvk depends on
ROBO-lohuovpm, ROBO-zjkemhjf, ROBO-yuqtnqbj and ROBO-xwzztzqh; ROBO-gqcjmekm
depends on ROBO-tnbhhzvk and ROBO-lohuovpm.

Related top-level outcomes, outside the epic:

| Outcome | Tracker | Relation |
| --- | --- | --- |
| Target URL encoding before matching | ROBO-tvcnkkdi | Done: [the matrix](target-encoding-matrix.md). A closed prerequisite: its engine cells carry evidence labels and name the owner of every "not tested" cell. |
| Target-encoding proposals | ROBO-zbqwvoyb | `[USER]`: the maintainer decides the matrix's proposals (Google opt-in escape, Yandex canonicalization, client form) before any implementation. |
| Extractors under `LC_ALL=C` | ROBO-eaeawkwc | Bug found by the matrix: the Bing and Yandex extractors read an unmarked UTF-8 URL as escape text under `LC_ALL=C`. |
| Bing spec copy resync | ROBO-wlhiavfz | `design/robotstxtbing-v2-spec.md` still carries the matcher bound Bing withdrew (BING-bziohhmb) and the D2 staleness; resync to a pinned robotstxt-cpp-bing commit. |
| Encoding-variant rule families | ROBO-cpmbfgof | Corpus outcome depending on ROBO-bnvdmdjr, ROBO-tvcnkkdi and ROBO-bwjxlnud. ROBO-bnvdmdjr has landed (ADR 0002, `url_normalization`), and its mode semantics bind ROBO-tvcnkkdi. |
| Yandex group selection | ROBO-hegmdbon | Backend bug, labeled bug and backend-alignment, depending on ROBO-jtsmzesl. See "Integration ownership" below. |
| Live tester checks | ROBO-traxexwm | Intent-trap candidates and exact-case coverage checks. |
| Live crawler evidence | ROBO-oxfpgdrx | In progress. Ungated by an owner decision of 2026-11-23: serving fixtures on the test origins is authorized. |

Planning alone authorizes no live sessions or gate changes. Live sessions run
only under an owner authorization recorded in the owning repository: the
2026-11-23 unattended-capture decision (see "Owner gates" below) for the batches
it names, and a recorded owner decision for any other batch.

## Start and dispatch from robotstxtr

Read the selected ROBO outcome with `fp issue show <id> --format json`. Before
working in a sibling, enter its owning repository and read its issue there:

```sh
cd ../robotstxt-cpp-bing
fp issue show BING-mabpuxza --format json
# Return to the coordination project after the owning-repository work.
cd ../robotstxtr
```

Use the corresponding `../robotstxtyandex` folder for YDX issues. A display
prefix does not route fp to another project. The command must run from the
owning folder. Native fp dependencies cannot span projects: the cross-project
links below and issue comments are operational dependency records, not an
automatic readiness signal. Re-read source status, comments and acceptance
evidence before advancing a dependent ROBO ticket.

For captures also read the owning repository's ORACLE_PROTOCOL,
PROBE_ORCHESTRATION, evidence policy and latest DECISIONS entries. A stale issue
description is not a reason to repeat work already recorded as complete in its
comments or committed corpus.

## Work that can advance independently

| Lane | Next work | Join point |
| --- | --- | --- |
| Bing | BING-nayqrubx (the driver checks the editor's scheme before Test) is unblocked now that BING-jekrqonq landed. Then BING-snztgvmf resumes at run order 100 on the owner's go-ahead, and BING-mabpuxza runs its later-date replays, the served one through BING-jekrqonq's per-unit-host runner. BING-sttdkzpf and BING-zwzuhnqg are offline documentation and gate follow-ups. | Their finalized evidence feeds BING-yhfmjkuj, the 0.2.0 release. |
| Yandex | YDX-vakiowhn has merged plans and needs capture, finalization and replication on the YDX-sosxgkbk surface. YDX-uawkbqtk's plan is frozen (7c143a7, 2a801da): it needs an owner decision naming it, a capture, and a replication on a later UTC date before implementation. | YDX-vgomfspr, the 0.3.0/profile yandex-0.2.0 release, depends on YDX-vakiowhn and YDX-uawkbqtk. |
| Google | ROBO-yuqtnqbj is done. The source-audit families are dispositioned in [the findings record](google-source-audit.md); what remains under ROBO-zjkemhjf is the owner's call above and the record's two deferred items. | Both contribute to ROBO-tnbhhzvk. |
| Comparison inventory | Delivered by ROBO-lohuovpm (below). It is refreshed when BING-yhfmjkuj, YDX-vgomfspr or ROBO-jtsmzesl moves. | The final corrected-pin replay also waits on ROBO-xwzztzqh. |
| Target encoding | ROBO-zbqwvoyb is the maintainer's decision; ROBO-eaeawkwc can be fixed now. | ROBO-cpmbfgof, and the crawler-request questions folded into ROBO-oxfpgdrx. |

Parallel repository work does not imply concurrent authenticated captures.
The capture protocols require exclusive leases and serial execution on the
relevant browser/account surfaces. Bing and Yandex share one probe Chrome and
never run at once. Their existing daily caps and later-date replication
requirements remain in force.

Both sibling releases and owner-approved immutable pins join at
ROBO-jtsmzesl. Its USER gate and one batched re-vendor remain unchanged. The
eight existing correction tickets depend on that re-vendor; per-class fixtures
and tests can then be divided by engine/class, with shared docs integrated
centrally. They are not permission to modify frozen vendor payloads directly.

## Integration ownership and dependencies

| Robotstxtr outcome | Upstream evidence / payload owner |
| --- | --- |
| ROBO-mtjcdmjm: Bing suffix selection | BING-mabpuxza -> BING-yhfmjkuj |
| ROBO-kuxdvvpi: Yandex BOM | YDX-vakiowhn -> YDX-vgomfspr |
| ROBO-ofsrftdt: pre-colon whitespace | YDX-vakiowhn -> YDX-vgomfspr |
| ROBO-akmpmvht: Yandex stack boundary | YDX-vakiowhn -> YDX-vgomfspr |
| ROBO-polznjqh: Yandex target escape case | YDX-vakiowhn -> YDX-vgomfspr |
| ROBO-xpzkfjbj: Yandex empty agent | YDX-vakiowhn -> YDX-vgomfspr |
| ROBO-gwmdrbrv: CR line ends | BING-mabpuxza / BING-yhfmjkuj and YDX-vakiowhn / YDX-vgomfspr |
| ROBO-spssfbdo: Unicode rule/target handling | BING-snztgvmf / BING-yhfmjkuj and YDX-vakiowhn / YDX-vgomfspr |
| ROBO-hegmdbon: Yandex group selection | YDX-uawkbqtk -> YDX-vgomfspr |

The first eight sit under ROBO-xwzztzqh and in ROBO-lrertets's dependencies.
ROBO-hegmdbon depends on ROBO-jtsmzesl like them but is top-level and outside
ROBO-lrertets's dependencies; whether it joins ROBO-xwzztzqh is an open tracker
decision, not settled here.

Each correction retains corpus projection, adopted-backend regression,
evidence-qualified verdict/tag documentation and backend-specific NEWS.
ROBO-wrlaufai and ROBO-ovgfyowt remain separate validator advisories after the
Unicode correction. They do not implement matcher fixes.

## Evidence and scope to preserve

- Distinguish source predictions, executed upstream results, local compatibility
  results, submitted-body tester results, tester fetches of served files and
  verified production crawler observations. Record dates, exact bytes,
  body/target identities, tokens, transport limitations and lifecycle status.
  The inventory's `evidence_kind` column carries these six.
- The older union result (Bing's committed three-way library differential) has a
  corrected comparable denominator; its split cases are not independent mismatch
  mechanisms. Keep its fragment-bearing exclusions and original records visible.
  New pins produce new versioned results; they do not rewrite historical
  records. The denominators are recalculated below.
- The 2026-11-18 source audit's 122 cases include controls and existing families.
  Findings record: [Google source audit](google-source-audit.md). Every family
  it names is a row of the inventory, by its scratch ids. Index-specific
  coverage was ROBO-yuqtnqbj's and is done. The tracker state of ROBO-zjkemhjf
  against the record is open for the owner (see "Delivery outcomes").
- Bing field-name tolerance has measured exceptions to the shipped exact-name
  grammar: 13 in-register names honored, 14 outside not, one permanent hole
  (`User_agent:`), `Site-map:` the only open item (BING-neevqmml). Existing
  adjudications retain compatibility nonclaims; a release addressing line ends,
  suffixes and Unicode does not establish parity there.
- A blanket claim that every raw non-ASCII rule is inert is not supported for
  Bing. The partial sweep and existing working controls constrain what can be
  claimed; the adopted boundary must come from finalized evidence for each
  crawler profile. Yandex is evaluated separately.
- Bing and Yandex stack boundaries differ. In particular, do not attribute
  Yandex's observed blank/comment boundary to Bing, whose observed stack stays
  transparent across those lines.
- Yandex's main indexing robot selects a group whose value is a case-insensitive
  prefix of its identity `YandexBot/3.0` at least as long as `Yandex`, longest
  value winning. The 2026-11-19 checks are exploratory until YDX-uawkbqtk
  captures and replicates its frozen plan. Under the symmetry rule, the Bing
  tester gets the same prefix probes (ROBO-mtjcdmjm).
- Backend status, matched-line attribution, unsupported profiles and invalid
  request targets are distinct from a decided allow/disallow result.

## Shared-fixture tester work

BING-nnonuwkh and YDX-xxkuthzv own the existing shared-fixture campaign.
Its latest historical scope is 49 capturable split cells, with 10 deferred for
calibration, rather than the superseded 74-cell proposal. The shared corpus,
versioned tester-result schema and clarified join keys already exist. Do not
schedule their creation again from old descriptions. For newer pins, re-derive
the relevant candidate set and controls; the historical 49 is not a permanent
coverage limit.

ROBO-traxexwm owns additional intent-trap candidates and exact-case coverage
checks. These are related outcomes, not duplicate campaigns. Inspect existing
finalized evidence before requesting a session. ROBO-oxfpgdrx owns the separate
crawler-evidence question. Optional live follow-ups do not keep the offline
comparison epic open indefinitely. Existing parked fetch-policy work remains
parked.

## Downstream studies

ROBO-gqcjmekm must separate effects on the Google matcher, validator, fetch and
each strict backend, and name exact old/new pins, manifests and profiles.
News-ai-access NEWS-quwzwmjd owns its study re-pin under ADR 0005/0006;
NEWS-ekogkpxy records the earlier comparison-extension work. Inspect those
issues before creating a missing downstream outcome. Updating the explanatory
HTML and repeating the collected-file comparison must have explicit ownership
in news-ai-access before the handoff closes.

The historical study count applies to the old study pin, token-substituted
Claude question and tested paths. It is not a current estimate for corrected
backends, native Bing/Yandex groups or all article URLs. The study re-pin and
rerun stay in the study repository under its existing gates; they do not imply
new publisher network requests.

## Owner gates and representation findings

The robotstxtr title/label audit was clean on 2026-11-19. Two descriptions
now disagree with their titles and labels and are left for the owner: the
ROBO-jtsmzesl description keeps a "[USER] until…" gate section with no title
marker or label, and the ROBO-oxfpgdrx description still says maintainer-gated.
On 2026-11-23 the owner lifted the gates on BING-ydtqaklv, BING-drbjcjgh,
BING-cbjkxkmr, BING-bziohhmb, BING-hraozgxi, BING-glvzfsmm and BING-vhgzzhst,
each with a recorded decision on the issue, and on ROBO-oxfpgdrx. All seven
Bing issues have since landed; BING-ydtqaklv stays open until a real capture
has run through `--lease-id` and the owner has checked the recorded lease.
BING-nnonuwkh also carries no gate marker. The same 2026-11-23 decision (on
BING-ydtqaklv) authorizes tester captures to run unattended through each
repository's own automation in the dedicated, signed-in probe profile
(BING-zrwhebav; in robotstxtyandex YDX-sosxgkbk). A Yandex batch other than
YDX-vakiowhn (such as YDX-uawkbqtk's) still needs an owner decision naming it.
Every frozen-plan, lease, freshness, second-date and evidence rule still
applies, and a 429 is a stop, never a retry.

Waits that remain are decisions, not captures: BING-mabpuxza's CR acceptance
and AdIdxBot CR channel, the owner's go-ahead to resume BING-snztgvmf after its
2026-11-23 trial stopped, the BING-snztgvmf boundary before BING-yhfmjkuj, and
mechanism or residual-phase adjudication in BING-neevqmml, BING-ntcgziyl and
BING-lxsjbcdo. YDX-uawkbqtk's capture needs an owner decision naming its plan.
ROBO-jtsmzesl keeps its USER gate. Owner pin approvals, adjudications and tags
remain separate. Re-read each issue's latest comments before acting on a gate.

## All open and active sibling work

The following is a dated routing index (2026-11-23), not a promise that a
ticket is ready. The source-of-truth command for every row is
`fp issue show <id> --format json`, run from the owning folder, plus that
repository's `docs/DECISIONS.md` (Bing) or `docs/PROBE_COLLECTION_DECISION_*.md`
(Yandex). Statuses here come from each repository's main branch (Bing a05c89c,
Yandex b043687) and the tracker writes of the 2026-11-23 run; fp could not be
run in the sibling folders for this snapshot, so a closure was not re-read
there. Inspect current evidence before dispatch.

### robotstxt-cpp-bing

| Issue | Status | ROBO link | Blocker or gate | Evidence state | Next action |
|---|---|---|---|---|---|
| BING-neevqmml: Capture field-name typo permutations on the Bing tester (unknown-field-tolerance-v1) | in-progress | inventory `bing-fieldname-frame` | `Site-map:` needs capture fields `transport_ui_v1` does not collect | Frame two-date: 13 in, 14 out, 1 hole (e71181b, 3680b70) | Decide how `Site-map:` is captured; do not restart Stages 1 to 3. |
| BING-vzcqxjtx: Establish field-name tolerance as replicated Bing evidence | in-progress | inventory `bing-fieldname-frame` | Program parent | Stage 1 complete; Stages 2 and 3 replicated | Read DECISIONS and children before scheduling; keep the compatibility nonclaims visible. |
| BING-mabpuxza: Fresh in-protocol tester batch for CR and the bingbot suffix forms (B2), served files, second date | in-progress | ROBO-mtjcdmjm, ROBO-gwmdrbrv | Owner: CR acceptance, AdIdxBot CR channel | B2 served and submitted captured 2026-11-16, reviewed, one date | Later-date replay of both B2 plans; the served one runs per unit host through BING-jekrqonq's runner. |
| BING-snztgvmf: Sweep every Latin-1 and combining-mark scalar in one served robots.txt | in-progress | ROBO-spssfbdo | Owner resume decision after the 2026-11-23 trial stopped (editor on the http tab); BING-nayqrubx | Bingbot served units through run order 99 captured; AdIdxBot and submitted legs not | BING-nayqrubx, then resume at run order 100; replicate; both profiles; do not adopt a blanket non-ASCII rule. |
| BING-ntcgziyl: Recapture the Latin-1/NFD literal cells and discriminate the mechanism (unicode-latin1-v1) | in-progress | ROBO-spssfbdo | Owner adjudication | Arm A and Arm B replicated (2026-08-08, 2026-08-09) | Mechanism adjudication only; no new replication. |
| BING-lxsjbcdo: Stage 4: separate 'single substitution' from 'any single edit' | in-progress | inventory `bing-fieldname-frame` | Adjudication | Deletion replication finalized and merged | Promotion and mechanism adjudication; inspect child outcomes first. |
| BING-ydtqaklv: Plumb the pre-registered lease id through probe_batch_runner.py | todo, landed (7718062, 73e1a69, a6f9fda) | none | Closes after one real capture runs through `--lease-id` and the owner checks it | Code only | Pass `--lease-id` in the next authorized session. |
| BING-uvgursjo: Bind the run nonce to the unit set (freshness option B) | todo | none | Deferred; depends on BING-ydtqaklv | None | Nothing until BING-ydtqaklv closes; not a release prerequisite. |
| BING-yhfmjkuj: robotstxtbing 0.2.0: adopt the tester-observed line-end, suffix and non-ASCII behavior | todo | ROBO-jtsmzesl | Depends on BING-mabpuxza and BING-snztgvmf; the tag is the owner's | Behavior choices answered 2026-11-15 | Release once both finalize; supplies ROBO-jtsmzesl. |
| BING-nnonuwkh: Rigorous same-fixture three-way Google/Bing/Yandex rerun | todo | ROBO-tnbhhzvk; inventory `utw-*` | Capture half needs owner authorization and agreement with YDX-xxkuthzv | Offline foundation done; scope 49 plus 10 | Recompute the candidate set for new pins without rewriting history. |
| BING-uvdzjbkd: [PARKED] Deferred probe cells that no issue tracks | todo | none | PARKED | None | None: inventory only. |
| BING-jekrqonq: per-unit-host served plans through the runner | merged 2026-11-23 (a05c89c, MR !30) | ROBO-mtjcdmjm (via BING-mabpuxza) | None | Code only; ships no capture | Close in the tracker; first real session is BING-mabpuxza's served replay. |
| BING-nayqrubx: the driver checks the editor's scheme before Test | todo | ROBO-spssfbdo (via BING-snztgvmf) | Waited on BING-jekrqonq, now landed | None | Implement, then the sweep resumes. |
| BING-sttdkzpf: ORACLE_PROTOCOL readiness bullet | todo | none | None | Documentation | Bring "Readiness has two layers" in line with the BING-zrwhebav surface. |
| BING-zwzuhnqg: fourth `CAPTURE_FIELDS` copy | todo | none | None | Documentation and gate | Add `tools/probe_manual_finalize.py` to the correspondence gate (the BING-drbjcjgh known gap). |

Landed 2026-11-23, kept as closed prerequisites so they are not repeated:
BING-drbjcjgh (`capture_fields` not re-spelled; be8cc06, 6b242f8),
BING-bziohhmb (spec matcher bound; 586f21f, ee06ee1; robotstxtr's copy is
ROBO-wlhiavfz), BING-rkeuguxc (submission spacing and the 100-unit cap;
ae17238, cf5b360, eb0f582), BING-edooqxtd (multi-run transcription; a801205,
073cd37, 6944b15), BING-glvzfsmm (merge-commit wording; 186a286, 7a403a1),
BING-vhgzzhst (the v2 Google pin stays opt-in, v1 the default for pairwise jobs;
ab1935f), BING-zrwhebav (unattended capture in the dedicated probe profile;
6b17751, 71e4b1a, 3fa5902), BING-cbjkxkmr and BING-hraozgxi (the field-name
frame; e71181b, 3680b70). No Bing release landed.

### robotstxtyandex

| Issue | Status | ROBO link | Blocker or gate | Evidence state | Next action |
|---|---|---|---|---|---|
| YDX-xxkuthzv: Yandex leg of the same-fixture three-way rerun | in-progress | ROBO-tnbhhzvk | Depends on YDX-utevvrrc; counterpart BING-nnonuwkh | Schema and joins repaired; shared set exists; scope 49 plus 10 | Proceed with BING-nnonuwkh under an owner authorization. |
| YDX-vakiowhn: Fresh in-protocol analyzer batch for the seven 0.3.0 behaviors (Y1, Y3 to Y8), served files for BOM and CR, two dates | todo | ROBO-kuxdvvpi, ROBO-ofsrftdt, ROBO-akmpmvht, ROBO-polznjqh, ROBO-xpzkfjbj, ROBO-gwmdrbrv, ROBO-spssfbdo | Owner authorization recorded (YDX-sosxgkbk surface); never concurrent with a Bing session | Plans merged (MR !10: 23 units, 141 cases); nothing captured | Capture, later-date replication, reviewed finalization. |
| YDX-uawkbqtk: Yandex profile: select groups as the main indexing robot does | todo | ROBO-hegmdbon | Owner decision naming the plan | Plan frozen with parse controls and order twins (7c143a7, 2a801da); not captured | Capture, replicate on a later UTC date, implement; settle the profile name. |
| YDX-vgomfspr: robotstxtyandex 0.3.0, profile yandex-0.2.0 | todo | ROBO-jtsmzesl | Depends on YDX-vakiowhn and YDX-uawkbqtk | CMake version 0.3.0 alone is not a release | Release; supplies ROBO-jtsmzesl. |
| YDX-gqordtdu: attribution in the 2026-11-23 capture-surface decision | todo | none | None | Documentation | Fix in the owning repository. |

Landed 2026-11-23: YDX-vbrletsy (safety tests and `GIT_DIR`; 923be8e, 3e6e1cc),
YDX-sosxgkbk (the capture surface; 700df89, be03949, cf5b6c6,
`docs/PROBE_COLLECTION_DECISION_2026-11-23.md`), YDX-xysfgrfk (fp agent files;
b4cccb1). YDX-uefdvmwi closed the same day with no code (the memory store no
longer exists).

## Evidence inventory (ROBO-lohuovpm)

`design/backend-evidence-inventory.tsv` lists, one row per mechanism and
engine, what is known, from which kind of evidence, in which lifecycle state,
how the difference is disposed of, and who owns what is left. It is stamped as
of 2026-11-23. A refresh follows when BING-yhfmjkuj, YDX-vgomfspr or
ROBO-jtsmzesl moves, since each of those changes many rows at once. The file
is assembled from committed records and tracker reads; shipping it needs no
live session. Only committed or synthesized evidence is cited.

### Columns

The file is tab-separated, UTF-8, with a header row and no tab or line break
inside a field. Multi-valued fields use `;`; a combination of enumerated values
uses `+`.

| Column | Content |
| --- | --- |
| `schema` | `backend-evidence-inventory/1` on every row. A column change bumps it. |
| `row_id` | Stable row name. Rows from a record keep its prefix: `gsa-` the Google source audit, `ed-` the engine-disagreement classes, `utw-` the union three-way differential, `tem-` the target-encoding matrix. |
| `row_kind` | `mismatch-class`, `audit-family`, `finding`, `nonclaim`, `exclusion` or `untested`. |
| `mechanism` | What differs, in a sentence. Rows are deduplicated by mechanism and engine. |
| `engine` | `google`, `bing`, `yandex`, a comma list, or `all`. |
| `case_ids` | The exact case identities the row covers: scratch ids, `tw-` cell ids, tester question ids (B1, Y4), matrix row ids, plan names. Deduplication never drops one. |
| `body_target` | Where the bytes of the body and the target live: a fixture family, a test file, a sibling plan, a corpus record. |
| `token` | `native: <token>` when the body names the token asked about, `substituted: <how>` when a token or group was rewritten (Tier B, the audit's renamed agent), `caller token`, or `n/a`. A substituted row never joins tester evidence. |
| `evidence_kind` | One or more of the six kinds below. |
| `evidence_label` | The same evidence in [the matrix's labels](target-encoding-matrix.md#evidence-labels), plus `not-tested` and `not-testable`. |
| `lifecycle` | Where the evidence stands: pinned, refuted, a single-date tracker lead, captured on one date, replicated, adjudicated, accepted, plan frozen, deferred. |
| `disposition` | One of the six values below. |
| `provenance` | The committed file, commit, pin or tracker id the row rests on, and any transport limitation. |
| `evidence_date` | The date of the evidence the disposition rests on. |
| `owning_issue` | One issue that owns what is left, or the done issue that closed it. Every value resolves to an issue in its project. |
| `next_action` | The next executable step, or `none`. |

### Evidence kinds and labels

| `evidence_kind` | Meaning | Matrix label |
| --- | --- | --- |
| `source-prediction` | Read from vendored source, upstream source or vendor documentation, not run | INFERRED |
| `upstream-executed` | The pinned pristine upstream run (Google at 22b355ff, rebuildable from a clean checkout with `dev/google-fidelity/build-reference.sh`) | TESTED |
| `local-library` | A robotstxtr backend or a sibling library run on this machine | TESTED |
| `tester-submitted` | A webmaster tester's reading of a body pasted into its editor | OBSERVED |
| `tester-served` | A webmaster tester's fetch of a served file | OBSERVED |
| `crawler-verified` | A production crawler's request or behavior, read from the serving host's logs | OBSERVED |

`not-tested` means no evidence of that kind exists and names, through
`owning_issue`, who would produce it; `not-testable` means the channel cannot
carry the input (no Google tester gives a decision for a URL; the testers'
transports carry text, not arbitrary bytes).

### Dispositions

| `disposition` | Meaning |
| --- | --- |
| `faithful-difference` | The backend differs from another engine and does what its own evidence or contract says. |
| `local-fidelity-gap` | The local backend or adapter contradicts its engine's evidence. The fix is owned, usually upstream and then through ROBO-jtsmzesl. |
| `contradicted-claim` | A written claim (a spec copy, a document, a blanket statement) is contradicted by evidence. |
| `unresolved-case` | Evidence is missing or not yet adjudicated; no engine claim is made. |
| `refuted-candidate` | A predicted difference or cause that the evidence refuted. |
| `out-of-contract` | The input is outside the contract of the path that was asked (an unencoded fragment, a foreign token, an embedded NUL in the text API). |

### Reading rules

- No tester or crawler decision is inferred from a local replay. A row whose
  only kinds are `local-library` or `upstream-executed` says what a library
  does, nothing about an engine.
- A tester row is not crawler evidence. The 2026-11-13 tester answers
  (ROBO-bpywsjwv) are single-date tracker leads: the owning sibling issue
  finalizes them under its evidence policy before any expectation rests on
  them.
- Tier B bodies of the union differential are derived, not frozen fixtures:
  `utw-` rows with a substituted token are library statements only.
- The source audit's Bing 44/120 and Yandex 47/120 are history on synthetic
  bodies; the pins, not the counts, are current.

### The union differential's denominators, recalculated

Recalculated on 2026-11-23 from robotstxt-cpp-bing's committed records at
a05c89c (`comparisons/three-way/corpus/corpus.records` and
`comparisons/three-way/results/union-three-way.records`; the differential
document last changed in 0a08445). A cell is fragment-bearing when its
`path_query_hex` holds a `#` byte; a cell is unanimous when its three legs
return the same allow or disallow:

| Figure | As reported | Recalculated | In contract |
| --- | --- | --- | --- |
| Tier B cells | 648 | 648 | 643 |
| Tier B unanimous | 589 | 589 | 584 |
| Tier B split | 59 | 59 | 59 |
| Fragment-bearing cells | 8 Tier A, 5 Tier B | 8 Tier A, 5 Tier B, all 5 unanimous | excluded |

The recalculation matches the document's correction (BING-tywokrgm) exactly.
To re-derive it from a robotstxtr checkout next to robotstxt-cpp-bing:

```sh
git -C ../robotstxt-cpp-bing show a05c89c:comparisons/three-way/corpus/corpus.records > /tmp/corpus.records
git -C ../robotstxt-cpp-bing show a05c89c:comparisons/three-way/results/union-three-way.records > /tmp/union.records
python3 - /tmp/corpus.records /tmp/union.records <<'EOF'
import sys, collections
def recs(p):
    r = {}
    for line in open(p, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line:
            if r: yield r
            r = {}
        else:
            k, _, v = line.partition("="); r[k] = v
    if r: yield r
tier, frag, dec = {}, set(), collections.defaultdict(dict)
for r in recs(sys.argv[1]):
    if r.get("schema") == "comparison.three_way_cell_input/v1":
        tier[r["id"]] = r["tier"]
        if b"#" in bytes.fromhex(r["path_query_hex"]): frag.add(r["id"])
for r in recs(sys.argv[2]):
    if r.get("schema") == "comparison.three_way_cell/v1":
        dec[r["id"].rsplit("-", 1)[0]][r["leg"]] = r["decision"]
def tally(cells):
    v = [set(dec[c].values()) for c in cells]
    return sum(len(s) == 1 for s in v), sum(len(s) == 2 for s in v)
b = [c for c in dec if tier[c] == "B"]
print(len(b), tally(b), len([c for c in b if c not in frag]),
      tally([c for c in b if c not in frag]),
      sorted(c for c in dec if c in frag))
EOF
```

The 59 split cells are not 59 mechanisms: the inventory carries the verified
ones (`utw-cyrillic`, `utw-empty-disallow`, the stacked `Crawl-delay` cells in
`ed-01-bing`, the replay's library artifacts in `ed-06-bing` and
`bing-fieldname-frame`) and keeps the rest as `utw-tier-b-splits` for the
versioned replay (ROBO-tnbhhzvk).

### Reconciliation, 2026-11-23

Checked once, read-only, when the inventory was written:

- Every open ROBO issue labeled backend-alignment (`fp issue list --format json`
  in robotstxtr), and ROBO-zbqwvoyb, ROBO-eaeawkwc and ROBO-wlhiavfz, is
  routed in this guide or owns an inventory row.
- Every open Bing and Yandex issue known from the sibling main branches and
  this run's tracker writes, including BING-jekrqonq, BING-nayqrubx,
  BING-zrwhebav and YDX-sosxgkbk, is routed in the tables above.
- Every `owning_issue` resolves: ROBO ids in the robotstxtr tracker, BING and
  YDX ids in their repositories' commit messages or decision records.
- Every family of [the source audit](google-source-audit.md), refuted and
  deferred ones included, is a `gsa-` row naming its scratch ids.
- Every row's disposition and evidence kinds are from the enumerations above,
  and every row has the same column count.

### Unowned, proposed

New work found while reconciling, for the orchestrator to file or fold in:

- robotstxtr, a scope note on ROBO-mtjcdmjm: `design/engine-profiles.md` §5
  still tags Bing selection `bingbot` > `msnbot` > `*` as `[documented]`,
  while the Bing contract has no `msnbot` tier and robotstxt-cpp-bing dropped
  `msnbot` from scope (its DECISIONS, 2026-07-19). ROBO-mtjcdmjm already edits
  that §5 tag for the suffix forms; fold the `msnbot` qualification into it
  rather than filing a separate issue (inventory `nc-msnbot`).

## Sources and maintenance

- [Engine disagreement catalog](engine-disagreements.md): existing per-class research; historical verdicts require reconciliation with later adopted evidence. The inventory's `ed-` rows carry the later tester answers.
- [Google source audit](google-source-audit.md): the source audit's findings record, family by family; ROBO-zjkemhjf and ROBO-yuqtnqbj.
- [Target encoding matrix](target-encoding-matrix.md): target-side evidence on all three engines, with labels.
- [Evidence inventory](backend-evidence-inventory.tsv): the versioned, machine-readable ledger described above.
- Sibling Bing: docs/PROJECT_TRACKING.md, docs/DECISIONS.md and docs/UNION_THREE_WAY_LIBRARY_DIFFERENTIAL_2026-07-24.md.
- Sibling Yandex: docs/PROBE_PROGRAM.md, docs/EVIDENCE_POLICY.md, docs/PROBE_COLLECTION_DECISION_2026-11-15.md and docs/PROBE_COLLECTION_DECISION_2026-11-23.md.
- Existing study limits: news-ai-access/design/specs/claude-redirect-checks.md, “For this study”.

Refresh this routing guide and the inventory when a linked outcome changes
disposition. Raw snapshots and application logs stay outside committed
documentation. Grooming record: ROBO-rlruhqsk. Inventory: ROBO-lohuovpm.
