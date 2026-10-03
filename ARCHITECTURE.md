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
| Acquisition | `R/robots_fetch.R`, `R/fetch-policy.R`, `R/robots_origin.R`, `R/ssrf.R`, `R/body-decode.R` | One fetch per origin under a deterministic, conservative `httr2` policy. Origins come from `rurl`; a structural SSRF check runs before any request. |
| Validation | `R/robots_validate.R` | Document syntax and structure diagnostics, separate from URL decisions. |
| Results | `R/robots_decisions.R`, `R/robots_body.R`, `R/correlate_matches.R` | The typed, vectorized result objects and per-rule match metadata. |
| Native bindings | `src/*_binding.cpp`, `src/cpp11.cpp` (generated) | This package's cpp11 shims over the vendored matchers. |
| Vendored code | `src/robots.{cc,h}`, `src/reporting_robots.{cc,h}`, `src/vendor/` | Upstream snapshots, kept byte-for-byte; provenance in `inst/PROVENANCE`, `inst/vendor/` manifests and `THIRD_PARTY_NOTICES.md`. |

## Invariants

- Vendored trees stay identical to their pinned upstream. The
  `vendor-fidelity` gates in `dev/gates.R` check them against their manifests,
  and the hygiene hooks never rewrite them.
- Tests, examples and vignettes make no live network request: fetches are
  mocked or served locally.
- Conformance corpora under `inst/bing-corpus/` and `inst/yandex-corpus/` are
  byte-exact fixtures, regenerated only by `dev/gen-*-corpus.R`.
- `man/` and `NAMESPACE` are generated from roxygen in `R/`.
