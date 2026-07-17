# robotstxtr

<!-- badges: start -->
[![R-CMD-check](https://github.com/bart-turczynski/robotstxtr/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/bart-turczynski/robotstxtr/actions/workflows/R-CMD-check.yml)
<!-- badges: end -->

Faithful `robots.txt` parsing and URL-allowed decisions for R, powered by
Google's own matcher.

`robotstxtr` evaluates whether a URL may be crawled according to a site's
`robots.txt` rules. It wraps a vendored, upstream-test-validated snapshot of
Google's open-source C++ `robots.txt` parser and matcher, so allow and disallow
decisions match Googlebot's behavior — including the quirky parts (longest-match
wins, `Allow`-beats-`Disallow` ties, `*`/`$` wildcards, case-sensitive paths,
percent-escape canonicalization). It can also fetch `robots.txt` for you under a
deterministic, conservative `httr2` policy, construct fetch origins with `rurl`,
and return richly typed, vectorized decisions with per-rule match metadata.

This is a faithful, upstream-test-validated replica of the pinned matcher, not a
claim of universal behavioral identity with Googlebot.

## Installation

`robotstxtr` is not on CRAN yet. Its required `rurl` version is temporarily
available from the author's R-universe while the coordinated dependency updates
progress through CRAN. Configure that repository before installing the
development version from GitHub:

```r
# Temporary until rurl >= 2.2.1 is live on CRAN.
options(repos = c(
  bart_turczynski = "https://bart-turczynski.r-universe.dev",
  CRAN = "https://cloud.r-project.org"
))

# with pak
pak::pak("bart-turczynski/robotstxtr")

# or with remotes
remotes::install_github("bart-turczynski/robotstxtr")
```

Installation compiles the vendored C++ matcher and requires a C++17 toolchain.
Once dependencies have been obtained, installing, testing, and checking the
package does not make live network requests.

## Usage

Match one or more URLs against a `robots.txt` body you already have, fully
offline, with `allowed_by_robots_text()`:

```r
library(robotstxtr)

robots <- "user-agent: *
disallow: /private
allow: /private/public
"

x <- allowed_by_robots_text(
  robots,
  c(
    "https://example.com/index.html",     # not disallowed  -> TRUE
    "https://example.com/private/report", # under /private  -> FALSE
    "https://example.com/private/public"  # re-allowed      -> TRUE
  ),
  "mybot"
)

x$results[c("url", "allowed", "decision_source")]
#>                                  url allowed decision_source
#> 1     https://example.com/index.html    TRUE   default_allow
#> 2 https://example.com/private/report   FALSE   rule_disallow
#> 3 https://example.com/private/public    TRUE      rule_allow
```

`allowed` is the `TRUE`/`FALSE`/`NA` answer; `decision_source` explains why.

If you do not already have the `robots.txt` text, `allowed_by_robots_url()`
derives the governing origin, fetches it once per origin, and matches:

```r
allowed_by_robots_url("https://example.com/some/page", "mybot")
```

See the "Introduction to robotstxtr" vignette for the full walkthrough,
including match metadata, the fetch policy, and body inspection with
`robots_body()`.
