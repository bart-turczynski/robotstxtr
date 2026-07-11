# Porting Google's robots.txt Parser to R — Research Notes

> Working notes and findings to seed a PRD. Status: **research / scoping**, no code yet.
> Last updated: 2026-06-28.

## 1. Goal

Build an R package that wraps **Google's official robots.txt parser/matcher** (the one Googlebot
uses) so R users can check `can_fetch(url, user_agent)` with **fidelity to Googlebot's actual
behavior** — not a spec-aligned approximation.

Target distribution: **CRAN**. This constrains everything (no system deps, no network fetch at
build, must compile across CRAN's compiler matrix).

The differentiator vs. existing R packages is *fidelity*: matching Googlebot's real decisions,
including its quirks, plus the `reporting_robots` layer (which rule/line matched).

## 2. Upstream: google/robotstxt

- **Language/standard:** C++14. Apache-2.0 license (CRAN-compatible).
- **Build:** Bazel (official) + CMake (community). Neither ships in an R package.
- **Core files we care about:** `robots.cc` / `robots.h` (parser + matcher),
  `reporting_robots.cc` / `reporting_robots.h` (line-level "which rule matched" — newer).
  Also present but not needed: `robots_main.cc` (CLI), `robots_wasm.cc` (WASM), gtest files.
- **Tests:** `robots_test.cc` (~38 KB, 21 `TEST()` cases) — extensive; this is our fidelity
  oracle.
- **Activity:** quiet 2024–2025, real burst Feb–Apr 2026. Last commit **2026-04-01 `22b355f`**
  (WASM merge). ~3.5k stars, ~12 open issues. Only one release tag: **`v1.0.0`**.
- **Maintenance character:** matcher algorithm is *stable*; churn is in build system, docs,
  dependency bumps, and the supported-tags list. Notable 2026 change: `2026-02-19 4af32e5`
  added `content-signal`, `content-usage`, `domain`, `request-rate`, `revisit-after`,
  `visit-time` to `kUnsupportedTags` (sourced from HTTP Archive). Comments now cite **RFC 9309**.

**Implication:** pin to a commit SHA (no useful release cadence). Re-sync ~1–2×/year; the
diff to watch is `kUnsupportedTags` + the reporting layer, not the matcher.

## 3. The blocker: Abseil

`robots.cc` is **not** self-contained. It depends on Abseil:

```cpp
#include "absl/base/macros.h"
#include "absl/container/fixed_array.h"
#include "absl/strings/ascii.h"
#include "absl/strings/match.h"
#include "absl/strings/numbers.h"
#include "absl/strings/string_view.h"
```

CMake links `absl::base` + `absl::strings` and *downloads/builds Abseil* at configure time.
Vendoring full Abseil into a CRAN package is a non-starter (size, portability, no build-time
fetch). **Removing Abseil is the central engineering task.**

The absl surface actually used is small and behavior-neutral to replace (C++17):
- `absl::string_view` → `std::string_view`
- `absl::FixedArray` → `std::vector`
- `absl::StartsWith` / `EndsWith` / `AsciiStrToLower` → trivial local helpers
- `absl::SimpleAtoi` → `std::from_chars`
- `absl::ascii_isxdigit` / `ascii_islower` etc. → `<cctype>` helpers

## 4. R landscape — there IS a gap

- **`spiderbar`** (hrbrmstr, CRAN) — wraps `rep-cpp` (seomoz). Predates Google's 2019 release.
  Different engine.
- **`ropensci/robotstxt`** (Meissner/Ren, v0.7.15, 2024-08) — own R-level parsing; delegates
  robust checks to `spiderbar`'s `can_fetch()`. No Google logic.
- **No R package wraps Google's actual parser.** A faithful port would be **novel on CRAN**.

**Positioning:** not a competitor to `ropensci/robotstxt` — a *drop-in alternative engine*
(the role `spiderbar` plays today, but with Google's logic). Could even be pitched as a third
`can_fetch()` backend. Selling points: fidelity + `reporting_robots` line-level reporting,
neither of which the incumbents offer.

## 5. Prior-art C++ fork: nzrsky/robotstxt — evaluated, NOT adoptable as-is

The one serious fork that already removed Abseil. **Apache-2.0.** 5 stars, 0 forks, single
maintainer, last push 2026-03-08. Has a `singleheader/` amalgamation and Go/Python bindings.

**Why it does NOT fit a fidelity goal:**
- It is a **"better than Google" fork**, not a faithful one. Makes *intentional* behavioral
  changes ("RFC 9309 compliance fixes" for percent-encoding / query strings).
- **Replaces Google's hand-rolled URL slicing with the `ada` library** (WHATWG, SIMD). This
  changes matching behavior *and* swaps the Abseil dependency for a new one (`ada-url`, pinned
  v3.4.1) — i.e., renames the CRAN vendoring problem rather than solving it.
- Requires **C++20** (vs. our preferred C++17).

**Hard evidence (we diffed the test suites assertion-by-assertion):**
- All 21 Google `TEST()` cases are present (5 added) — none removed/renamed.
- **20/21 shared tests: identical** except the cosmetic `absl::string_view()` → `std::string_view()`.
- **1 test — `ID_Encoding` — has flipped expectations**, proving behavioral divergence:

  | rule | request URL | Google | nzrsky |
  |---|---|---|---|
  | `Allow: /foo/bar/ツ` | `…/foo/bar/ツ` (raw UTF-8) | `FALSE` (deny) | `TRUE` (allow) |
  | `Allow: /foo/bar/%62%61%7A` | `…/foo/bar/baz` | `FALSE` (deny) | `TRUE` (allow) |

  nzrsky justifies via RFC 9309 §2.2.2 + google/robotstxt#64. Defensible as a *different*
  product; fatal for a "matches Googlebot" product.

**Verdict:** use nzrsky **only as a reference** for the mechanical `absl::`→`std::` substitutions
(behavior-neutral, safe to crib). Do **not** adopt its matcher, its ada layer, or its tests.

## 6. Architecture decision: two rings, URLs as strings

Confirmed from `robots.cc` source: **Google has no URL object.** The whole "URL parsing" is one
~30-line string-slicing function:

```cpp
// Extracts path (with params) and query from URL. Removes scheme, authority, fragment.
// Result always starts with "/". Returns "/" if no path / invalid.
std::string GetPathParamsQuery(const std::string& url);
```

Public API is pure strings:
```cpp
bool AllowedByRobots(absl::string_view robots_body,
                     const std::vector<std::string>* user_agents,
                     const std::string& url);   // url is just a std::string
```

The only normalization is **byte-level** `MaybeEscapePattern` (e.g. `%aa`→`%AA`, `é`→`%C3%A9`),
and it is applied to **both the rule patterns and the extracted path**. That symmetry is *why*
matching works — and why pre-normalizing only the URL side breaks it. Matching itself = prefix +
`*`/`$` wildcard on the canonicalized strings.

**Two-ring design:**

| Ring | Job | Who |
|---|---|---|
| **Inner (engine)** | path extraction + allow/deny decision | Google's de-Abseil'd matcher (untouched) |
| **Outer (front door)** | validate input, build robots.txt origin to fetch, IDN, grouping | `rurl` (+ pslr + punycoder) |

**The hard rule:** the matcher is fed the **raw URL string, verbatim**. Never route matcher
input through rurl. Let Google's `GetPathParamsQuery` + `MaybeEscapePattern` do the slicing and
escaping. Unicode paths need zero handling from us — Google escapes them itself (that's the
`ID_Encoding` behavior).

**Binding is trivial:** R `character` vector → `std::string` → `AllowedByRobots` → R `logical`.
No component marshalling. Vectorize over a character vector.

## 7. rurl integration (the front door)

`rurl` (~/Projects/rurl, v1.4.1, an R-native ada-equivalent; uses pslr + punycoder) exports
accessors with rich encoding args. Relevant exports: `safe_parse_url(s)`, `get_scheme`,
`get_host`, `get_port`, `get_path`, `get_query`, `get_domain`/`get_tld`/`get_subdomain`,
`get_parse_status`, `get_clean_url` (AVOID — see below), `canonical_join`.

**Boundary contract:**

| Step | Call | Notes |
|---|---|---|
| Validate / route | `get_parse_status(url)` | skip `error`; skip non-http/https (`ok-ftp`, etc.) |
| Build robots.txt origin to **fetch** | `get_scheme` + `get_host(host_encoding="idna")` + `get_port` | → `scheme://xn--host[:port]/robots.txt` |
| **Allow/deny** | raw URL → C++ matcher | **no rurl preprocessing** |
| Reporting / grouping (optional) | `get_domain` / `get_tld` | pslr-backed |

**`clean_url` / `get_clean_url`: do NOT use** — drops all query parameters. robots.txt matching is
query-sensitive (Google's encoding tests match on `?qux=taz&baz=…`). Stripping params would
silently corrupt matching.

### Encoding findings (verified empirically against rurl)

- **`host_encoding="idna"` works** → `get_host("https://例え.jp/x", host_encoding="idna")` =
  `xn--r8jz45g.jp`. **Closes the IDN/punycode gap** — no direct punycoder call needed for the
  fetch origin. (`"unicode"`/`"keep"` return `例え.jp`.)
- **`path_encoding`** on `get_path`: `"encode"` → `/foo/bar/%E3%83%84`, `"decode"`/`"keep"` →
  `/foo/bar/ツ` (note rurl's `"keep"` actually decodes).
- **rurl re-serializes the query — no arg reproduces input bytes** (this is *why* we pass raw
  URL to the matcher, not just *that* normalization differs):
  ```
  input              : qux=taz&baz=http://foo.bar?tar&par
  decode=TRUE        : qux=taz&baz=http://foo.bar?tar&par=          (trailing '=' always added)
  decode=FALSE       : qux=taz&baz=http%3A%2F%2Ffoo.bar%3Ftar&par=  (re-encodes ://)
  ```

### rurl front-door robustness (spot-checked, holds up)
- no-scheme `example.com/path` → defaults `http`, host/path correct.
- case: scheme/host lowercased, **path case preserved** (`/Path`) — correct (paths are
  case-sensitive).
- port extracted (8443/8080), `NA` when absent.
- junk → `status=error`; non-http → `status=ok-ftp` (clean skip signal).
- IDN, IP, userinfo, scheme-relative all parse.

## 8. Build / CRAN considerations

- **C++17** target → `SystemRequirements: C++17` (modern R defaults to it; be explicit).
  Avoid C++20 (nzrsky's choice) for portability.
- **cpp11 over Rcpp**: tiny API surface (`AllowedByRobots` + optional reporting handler),
  faster compiles, no runtime dep.
- **Vendor** `robots.{cc,h}` (+ optionally `reporting_robots.{cc,h}`) into `src/`, de-Abseil'd.
  No external C++ lib linkage (CRAN can't depend on non-system libs).
- **License hygiene:** ship Google's Apache-2.0 `LICENSE`/`NOTICE`; record upstream SHA in
  `inst/` or a header comment for provenance + re-sync.
- **Tests:** port Google's `robots_test.cc` cases into `testthat` as the fidelity guarantee.

## 9. Proposed plan — two stages, **two separate GitHub projects**

Decided: this ships as **two distinct repositories**, built in order:

1. **A standalone C++ fork** (de-Abseil'd, fidelity-preserving) — usable on its own, by anyone,
   in any language's FFI. This comes first.
2. **An R library built on top of it** — a separate repo that vendors a pinned snapshot of the
   C++ fork into `src/`. This is *not* a fork of either Google's repo or the C++ fork; it's a
   fresh CRAN package.

The R package does **not** depend on the C++ repo as a live/linked dependency (CRAN forbids
non-system C++ lib linkage) — it vendors a copied, SHA-pinned snapshot. Keeping them separate
keeps the C++ fork independently reusable and keeps the "track Google + re-run gtests" loop
cleanly isolated from R packaging.

**Stage 1 — standalone de-Abseil'd C++ fork (fidelity-preserving).**
- Base on Google `master` (pin SHA). Use a clean repo with `upstream` remote for diffing
  (preferred over a literal GitHub fork, since we restructure heavily — delete Bazel/WASM/CLI).
- Strip Abseil → C++17. Keep Google's hand-rolled URL slicing (no ada).
- **Validate against Google's UNMODIFIED `robots_test.cc` — all 21 tests green, including the
  two encoding cases nzrsky flipped.** Green suite = fidelity proof. Use nzrsky's diff as the
  substitution cheat-sheet.
- Keep a minimal CMakeLists + gtest just to run the suite. Optional `singleheader` amalgamation.

**Stage 2 — R package that vendors the validated fork.**
- Not a fork of Google's repo — fresh CRAN package; copy the validated `src/` files in, pin SHA.
- cpp11 binding: `character` in → `logical` out, vectorized.
- `rurl` front door for origin construction / fetch / validation.
- Port Google's tests to `testthat`. Optionally expose `reporting_robots` for line-level matches.
- Optional: position as a `can_fetch()` backend compatible with `ropensci/robotstxt`.

## 10. Open questions

1. **Scope of v1:** matcher-only (`can_fetch`) first, or include the `reporting_robots`
   line-level layer from the start?
2. **Fetching:** does the package fetch robots.txt (httr2?) + cache, or accept robots.txt
   content as input and stay fetch-agnostic? (rurl builds the origin either way.)
3. **Vectorization API shape:** `can_fetch(robotstxt, urls, user_agents)` recycling rules;
   one matcher reused across many URLs (matcher is re-usable but **not thread-safe**).
4. **Compatibility with `ropensci/robotstxt`:** offer a drop-in `can_fetch()` backend, or
   stand fully alone? Talk to maintainers?
5. **Naming:** CRAN name (avoid clashing with `robotstxt`/`spiderbar`). e.g. `googlebot`,
   `robotstxtgoogle`, `repgoogle`?
6. **Re-sync policy:** how/when to pull upstream; automate the diff check (esp. `kUnsupportedTags`).
7. **`reporting_robots` value:** is line-level "which rule matched" worth the extra surface for
   our users (SEO/crawl auditing)?
8. **Vendoring mechanics:** how to snapshot the C++ fork into the R repo's `src/` and keep the
   pin visible (git subtree? plain copy + recorded SHA + a sync script?). *Two-repo split itself
   is decided (§9) — this is just the copy mechanism.*
9. **Confirm** nzrsky's `tests/` keeps Google's matcher tests passing for the *non-encoding*
   cases (we showed only `ID_Encoding` flipped among shared tests — good enough to trust the
   substitution map, but worth a full build if we lean on it).

## 11. References

- Google parser: https://github.com/google/robotstxt  (pin: `22b355f`, 2026-04-01)
- RFC 9309 (Robots Exclusion Protocol)
- nzrsky fork (reference only): https://github.com/nzrsky/robotstxt
- Encoding deviation context: https://github.com/google/robotstxt/issues/64
- R incumbents: https://github.com/ropensci/robotstxt , https://github.com/hrbrmstr/spiderbar
  (rep-cpp: https://github.com/seomoz/rep-cpp)
- Native ports for cross-checking behavior: https://github.com/jimsmart/grobotstxt (Go),
  https://github.com/trybyte-app/robotstxt-ts-port (TS)
- Local: `~/Projects/rurl` (v1.4.1; pslr + punycoder), this project `~/Projects/_google-robots-txt`
