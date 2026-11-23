# Backend alignment and comparison work

Coordination snapshot: as of 2026-11-23 (first written 2026-11-19). The fp
tracker and the owning repository's committed evidence remain authoritative;
refresh both before dispatching work. This guide is the entry point from a
robotstxtr session for work across Google, robotstxt-cpp-bing and
robotstxtyandex.

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
impact handoff. The tables below index the 19 Bing and 7 Yandex issues open
at the snapshot date (YDX-uefdvmwi has closed since); reciprocal tracker comments point back here for the 25
that existed on 2026-11-19. YDX-uawkbqtk, filed later, has no back-pointer yet. No upstream implementation issue is duplicated as an
empty coordination ticket.

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
| Evidence, coverage and work routing | ROBO-lohuovpm | Versioned evidence inventory; source, local-library, tester and crawler claims separated; every remaining gap owned. |
| Google source-audit conformance corpus | ROBO-zjkemhjf | Durable, reproducible selected cases from the 122-case source audit. Its dependency ROBO-wnuttuit is done, so it is unblocked. |
| Google index-fallback boundaries | ROBO-yuqtnqbj | Index suffix, priority, asymmetry and query-slash regressions; can progress separately from other Google families. |
| Versioned union replay | ROBO-tnbhhzvk | One manifest for all three backend identities, exact comparable inputs, historical versus corrected-pin outputs and explicit exclusions. |
| Comparison catalog and study-impact handoff | ROBO-gqcjmekm | Evidence-qualified catalog, old/new impact manifest and downstream ticket ownership. |

The comparison epic composes ROBO-lohuovpm, ROBO-zjkemhjf,
ROBO-yuqtnqbj, ROBO-tnbhhzvk and ROBO-gqcjmekm. ROBO-tnbhhzvk depends on
ROBO-lohuovpm, ROBO-zjkemhjf, ROBO-yuqtnqbj and ROBO-xwzztzqh; ROBO-gqcjmekm
depends on ROBO-tnbhhzvk and ROBO-lohuovpm.

Related top-level outcomes, outside the epic:

| Outcome | Tracker | Relation |
| --- | --- | --- |
| Target URL encoding before matching | ROBO-tvcnkkdi | Labeled backend-alignment, comparison and google-source-research. An offline matrix of target forms across all three engines and the `none`, `rfc3986` and `whatwg` preprocessing modes, under the symmetry rule. A normalization proposal goes to the maintainer before any implementation. |
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
fp issue show BING-edooqxtd --format json
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
| Bing | BING-edooqxtd multi-run transcription and BING-rkeuguxc pacing can ship independently. BING-snztgvmf now depends natively on BING-edooqxtd. Continue BING-mabpuxza and BING-snztgvmf only under their existing capture protocols and current offsets. | Their finalized evidence feeds BING-yhfmjkuj, the 0.2.0 release. |
| Yandex | YDX-vbrletsy isolates safety tests from inherited git variables before using the affected worktree verification flow. YDX-vakiowhn has merged plans and needs capture/finalization/replication. YDX-uawkbqtk needs a frozen plan replicated on a later UTC date before implementation. | YDX-vgomfspr, the 0.3.0/profile yandex-0.2.0 release, depends on YDX-vakiowhn and YDX-uawkbqtk. |
| Google | ROBO-yuqtnqbj owns index fixtures; ROBO-zjkemhjf owns other source-audit families. Partition fixture ownership to avoid unnecessary ordering. | Both contribute to ROBO-tnbhhzvk. |
| Comparison inventory | ROBO-lohuovpm can reconcile current evidence and prepare the integration design while upstream work proceeds. | The final corrected-pin replay also waits on ROBO-xwzztzqh. |
| Target encoding | ROBO-tvcnkkdi research and its matrix need no approval. | ROBO-cpmbfgof, and the crawler-request questions folded into ROBO-oxfpgdrx. |

Parallel repository work does not imply concurrent authenticated captures.
The capture protocols require exclusive leases and serial execution on the
relevant browser/account surfaces. Their existing daily caps and later-date
replication requirements remain in force.

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
- The older union result (Bing's committed three-way library differential) has a
  corrected comparable denominator; its split cases are not independent mismatch
  mechanisms. Keep its fragment-bearing exclusions and original records visible.
  New pins produce new versioned results; they do not rewrite historical
  records.
- The 2026-11-18 source audit's 122 cases include controls and existing families.
  The scratch result is not a durable conformance corpus until ROBO-zjkemhjf
  delivers its accepted outcome. Index-specific coverage stays ROBO-yuqtnqbj.
  Findings record: [Google source audit](google-source-audit.md).
- Bing field-name tolerance has measured exceptions to the shipped exact-name
  grammar. Existing adjudications retain compatibility nonclaims; a release
  addressing line ends, suffixes and Unicode does not establish parity there.
- A blanket claim that every raw non-ASCII rule is inert is not supported for
  Bing. The partial sweep and existing working controls constrain what can be
  claimed; the adopted boundary must come from finalized evidence for each
  crawler profile. Yandex is evaluated separately.
- Bing and Yandex stack boundaries differ. In particular, do not attribute
  Yandex's observed blank/comment boundary to Bing, whose observed stack stays
  transparent across those lines.
- Yandex's main indexing robot selects a group whose value is a case-insensitive
  prefix of its identity `YandexBot/3.0` at least as long as `Yandex`, longest
  value winning. The 2026-11-19
  checks are exploratory until YDX-uawkbqtk replicates them. Under the symmetry
  rule, the Bing tester gets the same prefix probes (ROBO-mtjcdmjm).
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
marker or label, and the ROBO-oxfpgdrx description still says maintainer-gated. On 2026-11-23 the
owner lifted the gates on BING-ydtqaklv, BING-drbjcjgh, BING-cbjkxkmr,
BING-bziohhmb, BING-hraozgxi, BING-glvzfsmm and BING-vhgzzhst, each with a
recorded decision on the issue, and on ROBO-oxfpgdrx. BING-nnonuwkh also carries
no gate marker. The same 2026-11-23 decision (on BING-ydtqaklv) authorizes
tester captures to run unattended through each repository's own automation in
the owner's signed-in profile. In robotstxtyandex the capture surface is
recorded by YDX-sosxgkbk; a Yandex batch other than YDX-vakiowhn (such as
YDX-uawkbqtk's) still needs an owner decision naming it. Every frozen-plan, lease, freshness, second-date
and evidence rule still applies, and a 429 is a stop, never a retry.

Waits that remain are decisions, not captures: BING-mabpuxza's CR acceptance
and AdIdxBot CR channel, the BING-snztgvmf boundary before BING-yhfmjkuj, and
mechanism or residual-phase adjudication in BING-neevqmml, BING-ntcgziyl and
BING-lxsjbcdo. YDX-uawkbqtk's capture needs an owner decision naming its plan.
ROBO-jtsmzesl keeps its USER gate. Owner pin approvals, adjudications and tags
remain separate. Re-read each issue's latest comments before acting on a gate.

## All open and active sibling work

The following is a dated routing index (2026-11-23), not a promise that a
ticket is ready. Run its owning-project issue-show and inspect current evidence
before dispatch.

### robotstxt-cpp-bing

| Issue | Status | Routing | Current disposition / next action |
|---|---|---|---|
| BING-neevqmml — Capture field-name typo permutations on the Bing tester (unknown-field-tolerance-v1) | in-progress | Field-name evidence | Only Site-map/analyzer observability residue remains; earlier stages have completed replications. Do not restart Stage 1/2 from the old description. |
| BING-vzcqxjtx — Establish field-name tolerance as replicated Bing evidence (unknown-field-tolerance-v1) | in-progress | Field-name evidence | Program parent; original Stage 1 outcome is complete. Read DECISIONS and children before scheduling; keep intended compatibility nonclaims visible. |
| BING-mabpuxza — Fresh in-protocol tester batch for CR and the bingbot suffix forms (B2), served files, second date | in-progress | Bing release critical path | B2 served/submitted observations landed 2026-11-16. Remaining: later-date replay, accepted expectations, AdIdxBot CR, and Bingbot CR evidence disposition. Read latest comments before capture. |
| BING-snztgvmf — Sweep every Latin-1 and combining-mark scalar in one served robots.txt: which raw rules Bing ignores | in-progress | Bing release critical path | Partial sweep captured; resume from the offset in the latest comment. Depends on BING-edooqxtd for transcription. Requires replication and both crawler profiles; do not adopt the blanket non-ASCII rule. |
| BING-ntcgziyl — Recapture the Latin-1/NFD literal cells and discriminate the mechanism (unicode-latin1-v1) | in-progress | Bing evidence adjudication | Arm B later-date replication is complete (2026-08-09); only mechanism/owner adjudication remains. Do not schedule another replication from stale description. |
| BING-lxsjbcdo — Stage 4: separate 'single substitution' from 'any single edit' with the deferred deletion and insertion cells | in-progress | Field-name evidence | Deletion replication finalized and merged; parent remains open for residue. Promotion and mechanism adjudication are separate; inspect all child outcomes before scheduling. |
| BING-ydtqaklv — Plumb the pre-registered lease id through probe_batch_runner.py (freshness option A) | todo | Capture integrity | Gate lifted 2026-11-23. Lands at the head of the first authorized Bing capture session, after BING-rkeuguxc. |
| BING-drbjcjgh — capture_fields declares two field names no run has ever emitted (corpus-wide) | todo | Capture contract decision | Gate lifted 2026-11-23: do not re-spell capture_fields; record that in DECISIONS, then close. |
| BING-cbjkxkmr — 'Disambiguate:' is not structurally unclosable under the 2026-08-09 nonclaim reading, but the 2026-08-08 entry still says it is | todo | Evidence adjudication | Gate lifted 2026-11-23: close the Disambiguate hole and correct the 2026-08-08 counts. Related BING-hraozgxi; keep both acceptance criteria. |
| BING-uvgursjo — Bind the run nonce to the unit set: run-level freshness attestation (freshness option B) | todo | Capture integrity | Deferred option B depends on BING-ydtqaklv; not a release prerequisite unless an explicit existing rule makes it one. |
| BING-bziohhmb — Spec §10 promises linear matching; the matcher is O(p×t) with a budget | todo | Matcher contract decision | Gate lifted 2026-11-23: amend the spec to the budget-bounded matcher. A complexity/limit claim, not a semantic disagreement. |
| BING-yhfmjkuj — robotstxtbing 0.2.0: adopt the tester-observed line-end, suffix and non-ASCII behavior | todo | Bing release critical path | 0.2.0 release depends on mabpuxza and snztgvmf. All three Nov-15 behavior choices were answered; tag still belongs to owner. Supplies ROBO-jtsmzesl. |
| BING-edooqxtd — Transcribe one plan captured across several run directories | todo | Bing release critical path | Independent offline outcome: multi-run-directory transcription, preserving each run provenance and rejecting gaps/duplicates. Blocks finalizing sweep evidence; does not block continued capture. |
| BING-nnonuwkh — Rigorous same-fixture three-way Google/Bing/Yandex rerun (unified Google pin) | todo | Shared-fixture tester comparison | Offline foundation done. Latest scope is 49 capturable splits plus 10 calibration-deferred cells, not the superseded 74-cell proposal. Counterpart YDX-xxkuthzv. Recompute candidate set for new pins without rewriting historical evidence. |
| BING-uvdzjbkd — [PARKED] Deferred probe cells that no issue tracks | todo | Parked evidence tail | Preserve PARKED. Inventory only; do not start or propose execution under this consolidation. |
| BING-hraozgxi — Spec §9.2.3 still says the Stage 2 and 3 replications are owed | todo | Evidence adjudication | Gate lifted 2026-11-23: revise §9.2.3 (Stage 2/3 done, Site-map open) with a DECISIONS entry. |
| BING-glvzfsmm — DELIVERY_WORKFLOW says squash-merge; the project uses merge commits | todo | Repository maintenance | Gate lifted 2026-11-23: change DELIVERY_WORKFLOW to say merge commits. Not a backend semantic blocker. |
| BING-vhgzzhst — Record a DECISIONS.md entry for the v2 Google comparison pin (674471d) | todo | Comparison provenance decision | Gate lifted 2026-11-23: the v2 Google pin stays opt-in, v1 the default for new pairwise jobs. Preserve historical pin files. |
| BING-rkeuguxc — Space every runner submission, retries included, and cap a session at 100 | todo | Capture integrity | Independent offline pacing/cap outcome: retries count, submissions spaced, session cap enforced. Lands before runner campaigns resume. |

### robotstxtyandex

| Issue | Status | Routing | Current disposition / next action |
|---|---|---|---|
| YDX-xxkuthzv — Yandex leg: same-fixture three-way Google/Bing/Yandex rerun (counterpart to BING-nnonuwkh) | in-progress | Shared-fixture tester comparison | Counterpart to BING-nnonuwkh; schema/join defects repaired, shared set exists, latest scope 49+10. Depends on YDX-utevvrrc. |
| YDX-xysfgrfk — Drop fp-generated agent files and stale fp guidance | todo | Repository maintenance | Remove generated fp instruction imports/files only via owning Yandex issue. No new backend-semantic dependency. |
| YDX-vbrletsy — Repository-safety tests inherit GIT_DIR: a push from a worktree writes into the real repo | todo | Yandex execution safety | Offline isolation fix: GIT_DIR inherited by safety tests can mutate real repository during worktree pushes. Address before using affected worktree verification flow; no implied new semantic release gate. |
| YDX-vakiowhn — Fresh in-protocol analyzer batch for the seven 0.3.0 behaviors (Y1, Y3-Y8), served files for BOM and CR, two dates | todo | Yandex release critical path | Plans merged MR !10: 23 units/141 cases. Captures, later-date replication and reviewed finalization remain; preserve owner profile exception and served-file evidence rules. |
| YDX-uawkbqtk — Yandex profile: select groups as the main indexing robot does (prefix of YandexBot/3.0, longest wins) | todo | Yandex release critical path | Bug behind ROBO-hegmdbon. Freeze a plan from the 2026-11-19 exploratory bodies, replicate on a later UTC date, then implement; settle the profile name. Ships in YDX-vgomfspr. |
| YDX-vgomfspr — robotstxtyandex 0.3.0, profile yandex-0.2.0: adopt the seven tester-observed behaviors | todo | Yandex release critical path | Depends on YDX-vakiowhn and YDX-uawkbqtk; release 0.3.0/profile yandex-0.2.0. CMake version 0.3.0 alone is not proof of release. Supplies ROBO-jtsmzesl. |
| YDX-uefdvmwi — Retire the Claude auto-memory store: promote what is durable, delete the rest | done (closed 2026-11-23: the store no longer exists) | Repository maintenance | Memory retirement stays in Yandex; audit and archive before deletion. Not a new parser release blocker. |

## Sources and maintenance

- [Engine disagreement catalog](engine-disagreements.md): existing per-class research; historical verdicts require reconciliation with later adopted evidence.
- [Google source-audit outcome](tracker-snapshot.md): ROBO-zjkemhjf and ROBO-yuqtnqbj acceptance criteria and source references.
- Sibling Bing: docs/PROJECT_TRACKING.md, docs/DECISIONS.md and docs/UNION_THREE_WAY_LIBRARY_DIFFERENTIAL_2026-07-24.md.
- Sibling Yandex: docs/PROBE_PROGRAM.md, docs/EVIDENCE_POLICY.md and docs/PROBE_COLLECTION_DECISION_2026-11-15.md.
- Existing study limits: news-ai-access/design/specs/claude-redirect-checks.md, “For this study”.

Refresh this routing guide when a linked outcome changes disposition. The
versioned evidence inventory and ongoing semantic coverage belong to ROBO-lohuovpm;
this grooming pass only establishes the coordination map. Raw snapshots and
application logs stay outside committed documentation. Grooming record: ROBO-rlruhqsk.
