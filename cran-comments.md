## Resubmission

CRAN returned the first submission, 0.3.0, on 2026-10-08, asking that every
copyright holder be listed in `Authors@R`. This resubmission is 0.3.1: the
version moved on because 0.3.0 had already been tagged and deposited on
Zenodo. 0.3.1 also carries two changes made since, listed in `NEWS.md`: an
SSRF guard fix, and an `httr2 (>= 1.2.0)` floor.

* The bundled matcher, `src/robots.cc`, `src/robots.h`,
  `src/reporting_robots.cc` and `src/reporting_robots.h`, is derived from
  Google's Apache-2.0 `robotstxt` project, and each file carries Google LLC's
  copyright notice. Google LLC is now in `Authors@R` with the `cph` role, and
  its comment names those four files. The upstream sources name no individual
  authors, so there is no `ctb` entry for them.
* The maintainer, who wrote the local changes to those files, is now listed
  as `cph` as well. The rest of the package is the maintainer's own work,
  including the bundled Bing matcher under `src/vendor/robotstxtbing/`
  (Apache-2.0, its own LICENSE and NOTICE alongside) and the Yandex matcher
  under `src/vendor/robotstxtyandex/` (MIT).
* `DESCRIPTION` gains `Copyright: file inst/COPYRIGHTS`. That file gives the
  copyright holder, license and notice of every bundled component, since the
  `License:` field (MIT) covers the package's own code and the Google and
  Bing components keep the Apache License 2.0.
* The source repository and pinned commits of the Google files are in
  `inst/PROVENANCE`. The Apache License 2.0 text and the package's notice for
  those files ship as `inst/APACHE-2.0-LICENSE` and `inst/NOTICE`.

## R CMD check results

Every check below ran on the same package source, the one submitted.

* **local**, macOS Tahoe 26.7, aarch64-apple-darwin23, R 4.6.0:
  `R CMD check --as-cran` with `_R_CHECK_CRAN_INCOMING_=true` and
  `_R_CHECK_CRAN_INCOMING_REMOTE_=true`, with every direct dependency at the
  version CRAN serves today. 0 errors | 0 warnings | 1 note.
* **win-builder**, x86_64-w64-mingw32, 0 errors | 0 warnings | 1 note on each:
  * R-release, R 4.6.1 (2026-06-24 ucrt)
  * R-devel, R Under development (2026-10-14 r90673 ucrt)
  * R-oldrelease, R 4.5.3 (2026-03-11 ucrt)
* **R-hub** (R Consortium runners), R-devel, Status: OK on each:
  * linux: Ubuntu 24.04.5 LTS, x86_64-pc-linux-gnu, 2026-10-13 r90668
    (`--as-cran`)
  * macos: macOS Sequoia 15.7.9, x86_64-apple-darwin20, 2026-10-14 r90673
    (`--as-cran`)
  * macos-arm64: macOS Tahoe 26.6.2, aarch64-apple-darwin23, 2026-10-14
    r90673 (`--as-cran`)
  * clang-asan: Ubuntu 22.04.5 LTS, AddressSanitizer, 2026-10-13 r90668, no
    reports
  * clang-ubsan: Ubuntu 22.04.5 LTS, UndefinedBehaviorSanitizer, 2026-10-13
    r90668, no reports

The note is the incoming feasibility note below; R-hub does not run that
check, so it reports none. The local run shows its "New submission" and
`BugReports:` items but not the spelling item, because this machine has no
English dictionary for R's spell check; win-builder shows all three.

---

### Note

`checking CRAN incoming feasibility ... NOTE` covers three items.

* **New submission.**

  ```
  Maintainer: 'Bart Turczynski <bartek@turczynski.pl>'

  New submission
  ```

  This is the informational note expected for a first submission; there is no
  package defect behind it.

* **Possibly misspelled words in DESCRIPTION: `Matcher`, `matcher`.** Both
  are spelled correctly. "Matcher" is the technical term for the component
  that decides whether a URL is allowed, and it is the name Google gives the
  library the package bundles: the "Robots.txt Parser and Matcher Library".

* **`BugReports:` reported as a 404.**

      Found the following (possibly) invalid URLs:
        URL: https://gitlab.com/bart-turczynski/robotstxtr/-/issues
          From: DESCRIPTION
          Status: 404

  This is the address the incoming check itself asks for. GitLab has migrated
  issues to work items and answers `/-/issues` with 404 to any signed-out,
  non-browser client, on every project on the site: GitLab's own tracker,
  `https://gitlab.com/gitlab-org/gitlab/-/issues`, answers 404 identically. A
  browser is redirected (302) to `/-/work_items`, so the link works for a
  reader.

  No gitlab.com address clears both checks.
  `tools:::.check_package_CRAN_incoming()` accepts a gitlab.com `BugReports:`
  only when its path ends in `/-/issues`, and every such path, with or without
  a query string, is the 404 above. A sibling package's first upload declared
  `/-/work_items`, which returns 200, and was archived at the pretest for that
  reason; it was accepted on resubmission with `/-/issues`. The field here
  follows the check's suggestion, as the dependency `rurl` 3.0.1 does on CRAN.
  The `NEWS.md` bullet gives the address as code rather than as a link, so the
  404 is reported once, from `DESCRIPTION` only. `codemeta.json` keeps the
  `/-/work_items` address that a reader can click; it is in `.Rbuildignore`,
  so it is not part of this tarball.

## Dependencies

`robotstxtr` depends on R (>= 4.1.0) and imports `rurl (>= 3.0.1)` and
`httr2 (>= 1.2.0)`, both available from CRAN. Both floors are satisfiable
from CRAN today, and the package's full test suite passes against the
versions CRAN serves.

## Downstream dependencies

None — this is a new package.

## Submission history

### 0.3.0: first submission

* Submitted 2026-09-28 12:47:19 UTC with `devtools::submit_cran()`, from a
  clean clone of `main` at `289df00941fdc09f163d9e036d977724489459d4`
  (recorded in `CRAN-SUBMISSION`).
* Submitted tarball `robotstxtr_0.3.0.tar.gz`, SHA-256
  `643a0777bb4ef02549943ff34974e96abe69718759eeb2a2c0502c7c1e4c7cb2`.
* Checks on the same package source (`98e71e0`; only this file changed
  after it):
  * win-builder R-release <https://win-builder.r-project.org/agdw99MSIgci>,
    R-devel <https://win-builder.r-project.org/8NIOAvpR3O6j>, R-oldrelease
    <https://win-builder.r-project.org/UWX7pupev67b>. win-builder deletes
    these about 72 hours after the check.
  * R-hub build `paragonit-crow`:
    <https://github.com/r-hub2/roasted-eel-robotstxtr/actions/runs/36416901099>.
    Its windows, nosuggests and valgrind jobs failed for platform reasons,
    which are recorded in the project's release issue, ROBO-lvddphcx.

### 0.3.1: resubmission

* Checks on `main` at `678759c4aff3c254a6ec4cd799d887ca9e846b1b`; only this
  file changed after it.
  * win-builder R-release <https://win-builder.r-project.org/HCc2dAx0SA38>,
    R-devel <https://win-builder.r-project.org/3M2WtaNcYG7i>, R-oldrelease
    <https://win-builder.r-project.org/BG1u9BhfV2A5>. win-builder deletes
    these about 72 hours after the check.
  * R-hub build `auspicious-sheep`:
    <https://github.com/r-hub2/roasted-eel-robotstxtr/actions/runs/38709189237>.
    Its valgrind job failed with `Status: OK` from R CMD check: every
    valgrind error has its frames in R's TRE regex code or in the test-only
    dependencies jsonlite and httpuv, none in robotstxtr code.
