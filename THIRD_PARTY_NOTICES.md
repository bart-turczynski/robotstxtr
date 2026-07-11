# Third-Party Notices and Acknowledgments

Project: robotstxtr
Copyright (c) 2026 Bart Turczynski
Contact: bartek+robotstxtr@turczynski.pl

## Vendored source

The faithful Google robots.txt matcher is bundled as vendored C++ source
compiled into the package:

- `src/robots.cc`, `src/robots.h`, `src/reporting_robots.cc`,
  `src/reporting_robots.h`.
  - Immediate source: https://github.com/bart-turczynski/robotstxt-cpp
    @ commit `1cb8b047d81dfa0e9c1a1549b269fb5f196756c9`
  - Upstream baseline: https://github.com/google/robotstxt
    @ commit `22b355ff855419e6a3ff8ff09c0ad7fdb17116f9`
  - License: Apache License 2.0, with Google's original copyright headers
    intact.

The binding notice and the full Apache License 2.0 text ship with the package
at `inst/NOTICE` and `inst/APACHE-2.0-LICENSE`. See `inst/PROVENANCE` for the
full vendored-file manifest and checksums.

## Third-party R packages

- `rurl` (`Imports`): used to construct `robots.txt` fetch origins from URLs.
  - Homepage: https://github.com/bart-turczynski/rurl
  - License: MIT
- `httr2` (`Imports`): used for the deterministic `robots.txt` HTTP fetch
  policy.
  - Homepage: https://cran.r-project.org/package=httr2
  - License: MIT
- `cpp11` (`LinkingTo`): used for the R/C++ interface layer.
  - Homepage: https://cran.r-project.org/package=cpp11
  - License: MIT
