## R CMD check results

Checked with `R CMD check --as-cran` on:

* local: macOS aarch64 (R 4.6.0)

Result: **0 errors | 0 warnings | 1 note**

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
`httr2`, both available from CRAN. The `rurl` floor is the current CRAN
release; the package's full test suite passes against it as installed from
CRAN.

## Downstream dependencies

None — this is a new package.
