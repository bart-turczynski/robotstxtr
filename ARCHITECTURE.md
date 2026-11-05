# Architecture

The map of how `robotstxtr` is built: the layers a call passes through and
where each responsibility lives. [AGENTS.md](AGENTS.md) holds the working
rules; the specs and release audits behind the design live in
[`design/`](design/), starting with
[the engine-aware contract](design/engine-contract-v1.md) and
[the engine profiles](design/engine-profiles.md).

## What the package is

`robotstxtr` answers "may this crawler fetch this URL?" from a `robots.txt`
document. The answer comes from vendored C++ matchers, never from an R
reimplementation: Google's open-source matcher for the Google backend, and
bounded Bing and Yandex compatibility profiles behind the engine-aware facade.

## Layers

| Layer | Files | What it does |
|---|---|---|
| Public entry points | `R/allowed_by_robots_text.R`, `R/allowed_by_robots_url.R` | The Google-matcher API: match supplied text, or fetch then match. |
| Engine-aware facade | `R/engine-contract-v1.R`, `R/resolve-matcher-profile-v1.R`, `R/match-bing-v1.R`, `R/match-yandex-v1.R`, `R/yandex-checked-batch.R` | `robots_evaluate_*_v1()`: keeps fetch evidence, per-engine status policy, product token and matcher backend separate, and returns an explicit non-decision when a backend or policy is unavailable. |
| Acquisition | `R/robots_fetch.R`, `R/acquire.R`, `R/acquire-map.R`, `R/fetch-policy.R`, `R/robots_origin.R`, `R/body-decode.R`, `R/content-check.R` | One fetch per origin under a deterministic, conservative policy. Origins come from `rurl`. `R/acquire.R` is the only caller of `ssrfr`: it builds the policy, runs the prepare/fetch hop loop with robotstxtr's redirect rules, and translates ssrfr's refusal codes and failure causes into robotstxtr's published outcomes through the tables in `R/acquire-map.R` (design/engine-profiles.md §2). |
| Validation | `R/robots_validate.R` | Document syntax and structure diagnostics, separate from URL decisions. |
| Results | `R/robots_decisions.R`, `R/robots_body.R`, `R/correlate_matches.R` | The typed, vectorized result objects and per-rule match metadata. |
| Native bindings | `src/*_binding.cpp`, `src/cpp11.cpp` (generated) | This package's cpp11 shims over the vendored matchers. |
| Vendored code | `src/robots.{cc,h}`, `src/reporting_robots.{cc,h}`, `src/vendor/` | Upstream snapshots, kept byte-for-byte; provenance in `inst/PROVENANCE`, `inst/vendor/` manifests and `THIRD_PARTY_NOTICES.md`. |

## Invariants

- Vendored trees stay identical to their pinned upstream. The
  vendor-fidelity checks, `dev/verify-yandex-vendor.R` and
  `dev/verify-bing-vendor.R`, check them against their manifests in the local
  gate's full tier (`.fleet-ci.yml`), and the hygiene hooks never rewrite them.
- Tests, examples and vignettes make no live network request: fetches go
  through a fake at the ssrfr boundary (`tests/testthat/helper-fake-ssrfr.R`),
  a loopback server, or are refused before any request.
- Nothing but `R/acquire.R` calls `ssrfr`, and nothing in `R/` makes an HTTP
  request any other way.
- Conformance corpora under `inst/bing-corpus/` and `inst/yandex-corpus/` are
  byte-exact fixtures, regenerated only by `dev/gen-*-corpus.R`.
- `man/` and `NAMESPACE` are generated from roxygen in `R/`.
- `scripts/check-docs-drift.R` is seor's script, vendored byte for byte, so a
  fix goes into seor's copy and is copied here, never edited in place.
