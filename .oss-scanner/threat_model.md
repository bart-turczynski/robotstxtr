# Threat model

## What this project does and where untrusted input enters

robotstxtr is an R package that answers "may this crawler fetch this URL?" from a
`robots.txt` document. The answer always comes from compiled C++17 matchers, never from R:
a bundled snapshot of Google's open-source matcher, plus Bing and Yandex compatibility
matchers. The package can also fetch `robots.txt` itself over HTTP(S) with `httr2`, with
fetch origins built by `rurl` and a structural SSRF guard in front of every request.

Untrusted input:

- **`robots.txt` bodies** passed as text to `allowed_by_robots_text()`,
  `robots_evaluate_text_v1()` and `robots_validate_text()`. Assume any bytes: invalid UTF-8,
  CR/LF/CRLF mixes, very long lines, huge rule counts, BOMs, a `bytes`-encoded string.
- **Fetched responses** in `robots_fetch()`, `allowed_by_robots_url()`,
  `robots_evaluate_url_v1()` and `robots_validate_url()`: status, `Location` headers,
  `Content-Encoding`, and the body. Fetched bodies reach the Bing and Yandex cores as raw
  bytes, embedded NULs included; `robots_body()` renders the stored bytes.
- **URLs** (the `url` argument of `allowed_by_robots_text()`, `robots_evaluate_text_v1()`,
  `allowed_by_robots_url()`, `robots_evaluate_url_v1()`, `robots_fetch()` and
  `robots_validate_url()`), parsed by `rurl`, by `httr2`,
  and lexically by the package's own C++ request-target extractors.
- **Product tokens** (`user_agent`, `robots_product_token`), passed into the native matchers.

Trusted: the calling R code and its options (`timeout`, `max_bytes`, `fetch_user_agent`,
`ssrf_guard`, `matcher_backend`, `robots_policy_ruleset`), the R session, and the package's
bundled data under `inst/` (conformance corpora, vendor manifests, provenance records).

## Components that matter most / least

Most important: native code that parses untrusted bytes.

- `src/robots.cc`, `src/robots.h`, `src/reporting_robots.cc`, `src/reporting_robots.h`: the
  Google matcher snapshot (fixed 16,664-byte line buffer, pattern matching, path escaping).
- `src/vendor/robotstxtbing/`: the Bing core (physical scanner, directive lexer, parser,
  selection, winner, matcher). Its ceilings are in `include/robotstxtbing/limits.h`.
- `src/vendor/robotstxtyandex/`: the Yandex core (line scanner, lexer, parser IR, crawler
  selector, access matcher).
- The package's own cpp11 glue: `src/matcher_binding.cpp`, `src/collector_binding.cpp`,
  `src/bing_binding.cpp`, `src/yandex_matcher_binding.cpp`, `src/yandex_target_binding.cpp`
  (raw-to-string conversion, UTF-8 checks, `Rf_mkCharLenCE()` encoding marks, body-index
  bounds, byte-preserving request-target extraction, lifetimes of parsed policies).

Also important: the fetch path in R. `R/ssrf.R` (the guard: IPv4 ranges, IPv6 expansion,
IPv4-in-IPv6 and transition-mechanism decoding, numeric-literal obfuscation),
`R/fetch-policy.R` (manual redirect loop, scheme and HTTPS-to-HTTP downgrade checks,
five-redirect budget, streaming decoded-byte `max_bytes` limit), `R/robots_origin.R`,
`R/body-decode.R` (NUL removal before R strings), and the dispatch in
`R/engine-contract-v1.R`, `R/match-bing-v1.R`, `R/match-yandex-v1.R`.

Vendored code is in scope: the Google, Bing and Yandex sources ship in the package and are
compiled into its shared object. They are copied verbatim from pinned upstream commits:
`inst/PROVENANCE` pins the four Google files (a standard-library-only replica of
google/robotstxt), and `inst/vendor/*/PROVENANCE` plus `MANIFEST.dcf` pin the Bing and
Yandex trees with per-file SHA-256, which `R/vendor-manifest-verify.R` and
`dev/verify-*-vendor.R` check, failing the gate on any changed byte. A fix to a vendored
file therefore lands in its upstream library first and is re-vendored under a new pin; it
is never edited in place here.

Out of scope: `dev/`, `data-raw/`, `scripts/`, `design/`, `vignettes/`, test helpers, and
the dependencies (`httr2`, `curl`/libcurl, `rurl`, `cpp11`) unless robotstxtr uses them
unsafely, for example by trusting a parse that differs from the one that opens the socket.

## How to exercise it

The image has the checkout at `/src`, robotstxtr installed from it (C++ built with
`-g -O1 -fno-omit-frame-pointer` plus the default hardening flags), every Import and
Suggest installed, and `gdb` and `valgrind`. There is no network, but loopback works.
After patching any C/C++ file or header under `src/`, rebuild with
`R CMD INSTALL --preclean /src`: the image build and `test_local()`'s `load_all()` leave
object files in `/src/src`, and `src/Makevars` declares no header dependencies.

- Whole suite: `Rscript -e 'testthat::test_local("/src")'`; one area:
  `Rscript -e 'testthat::test_local("/src", filter = "ssrf")'`. Tests need no internet:
  fetches are mocked with `httr2::with_mocked_responses()` or served by a local
  `httpuv` server in a `callr` process (`tests/testthat/test-robots_fetch-r7.R`). The OSV
  and OSS Index audits (`test-osv.R`, `test-security.R`) skip offline.
- Native code under a debugger: `R -d valgrind --vanilla -f repro.R`, and
  `R -d gdb --debugger-args='-batch -ex run -ex bt' -e 'source("repro.R")'` (batch mode
  runs to the crash and prints the backtrace; plain `R -d gdb` waits at a `(gdb)` prompt).
- Entry points from `Rscript -e`:

  ```r
  library(robotstxtr)
  f <- "/src/inst/yandex-corpus/bodies/ydx-05-ties-wildcards.txt"
  body <- rawToChar(readBin(f, "raw", file.size(f)))
  allowed_by_robots_text(body, "https://example.com/a?b", "Googlebot")
  robots_evaluate_text_v1(body, "https://example.com/a", robots_product_token = "bingbot",
    robots_policy_ruleset = "bing", matcher_backend = "bing")      # or "Yandex", "yandex"
  robots_validate_text(body)
  robotstxtr:::robots_ssrf_check("http://[::ffff:7f00:1]/")        # pure, no network
  ```

- Raw bytes, NULs included, straight into the Bing and Yandex cores:
  `robotstxtr:::bing_evaluate_batch(list(bytes), 1L, "bingbot", list(charToRaw("/x")))` and
  `robotstxtr:::yandex_evaluate_checked_batch(list(bytes), 1L, "Yandex", list(charToRaw("/x")))`.
- The real streaming read (not the buffered mock) needs a local server and
  `ssrf_guard = FALSE`; copy the harness in `test-robots_fetch-r7.R`.
- Corpora worth reusing: `inst/bing-corpus/` and `inst/yandex-corpus/` (bodies plus
  `cases.json`), Google's upstream cases in `test-upstream-matcher-cases-r9.R`, the guard
  matrix in `test-ssrf-quovenef.R`, NUL bodies in `test-nul-body-hcqrzikz.R`.

## How you rate severity

- **Critical**: memory corruption in the Google, Bing or Yandex C++ or in the package glue,
  reachable from a `robots.txt` body, URL or product token given to an exported function or
  from a fetched response. An SSRF-guard bypass that reaches loopback (`127.0.0.0/8`, `::1`)
  or cloud metadata (`169.254.169.254`, `fd00:ec2::/32`, `metadata.google.internal`) with
  the default `ssrf_guard = TRUE`, on the first request or on any redirect hop.
- **High**: any other out-of-bounds read or write, use-after-free or uninitialized read
  reachable from untrusted input, even without a demonstrated exploit. A guard bypass to a
  private, link-local, shared (`100.64.0.0/10`), this-network or other blocked range,
  including a literal or IPv4-in-IPv6 spelling the guard misclassifies. A URL that the guard
  (via `rurl`) reads as one host while `httr2`/libcurl connects to another. A redirect that
  escapes the scheme check or the HTTPS-to-HTTP downgrade rejection.
- **Medium**: denial of service from small untrusted input: a body or URL that makes a
  matcher take unbounded CPU or memory (the Bing core is meant to stop at
  `kMaxMatcherWorkUnits`; the Google and Yandex matchers have no work cap), a compressed
  response whose decoded size gets past `max_bytes`, a fetch that escapes `timeout` or the
  five-redirect budget, or a crash of the R process (segfault, `std::terminate`, an
  uncaught C++ exception), as opposed to a classed R error.
- **Low**: wrong results with no security consequence: an allow/disallow that diverges from
  RFC 9309 or from the upstream engine the backend replicates (robots.txt is advisory, not
  access control; report these, they matter for fidelity). Problems that need
  `ssrf_guard = FALSE`, a hostile `fetch_user_agent`, `timeout` or `max_bytes`, or a defect
  in an internal `robotstxtr:::` routine that needs malformed index or length arguments
  (an out-of-range `body_index`, mismatched list lengths). A hostile body or target fed to
  a native core through such a call, as in the Bing and Yandex examples above, rates as if
  it had been fetched.

## Anything to leave alone

- Classed R errors (`robotstxtr_error` subclasses from `robots_abort()`) on wrong argument
  types, lengths or values: documented call-level validation, not a crash.
- `ssrf_guard = FALSE`: an explicit, documented opt-out for trusted intranet hosts.
- Names whose answer depends on DNS: the guard is structural and never resolves DNS
  (`R/ssrf.R` header), so a registered name that a resolver maps to a blocked address, and
  DNS rebinding, pass by design, pending the shared `ssrfr` package. This does not cover a
  name that reaches loopback with no DNS lookup (RFC 6761 `localhost` and `*.localhost`,
  which libcurl resolves locally) or any spelling of a hostname the guard blocks; those
  stay in scope. Deployment-configured NAT64 prefixes are out of scope.
- NUL bytes are dropped before the Google matcher and its parse collector
  (`R/body-decode.R`), a documented divergence from upstream Google;
  `robots_validate_text()` flags each line carrying one as a `nul_byte` error.
- At its ceilings (`limits.h`) the Bing core returns a parse or evaluation status and no
  decision. Under the `yandex` ruleset a body over 500,000 bytes is allow-all
  (`yandex_file_over_500000_bytes`, `design/engine-profiles.md`) and never parsed.
  Non-decisions (`capability_unavailable`, `unsupported_product_token`, `fetch_unknown`,
  `invalid_request_target`) are the contract, not failures to decide.
- The Bing and Yandex backends accept only `bingbot`/`adidxbot` and
  `Yandex`/`YandexAdditionalBot`; the Google backend accepts any valid token and applies
  Google semantics to it.
- HTTP-to-HTTPS redirect upgrades are allowed. Mocked responses skip the streaming read.
- Style or whitespace in vendored files, and outdated dependencies with no reachable path.

Patches: minimal R (base R and `httr2`, classed errors via `robots_abort()`, no new
dependency) or C++17 fixes in the package's style. For a vendored file, give the patch
against the file here and say it has to land upstream and be re-vendored. Add a `testthat`
regression test next to the existing tests for the area (for example `test-ssrf-quovenef.R`,
`test-bing-native-binding-yhfjsbzo.R`, `test-yandex-native-binding-jbhtvilo.R`), with no
live network. When the fix is a conformance fix, add a `NEWS.md` entry under the development
version that cites the standard and clause (for example RFC 9309 §2.2.2).
