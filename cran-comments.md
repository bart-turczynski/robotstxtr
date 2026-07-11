## R CMD check results

Checked with `R CMD check --as-cran` on:

* local: macOS aarch64 (R 4.6.0)

Result: **0 errors | 0 warnings | 1 note**

---

### Note

**New submission**

```
* checking CRAN incoming feasibility ... NOTE
Maintainer: 'Bart Turczynski <bartek@turczynski.pl>'

New submission
```

This is the informational CRAN-incoming-feasibility note that is expected for
a first submission; there is no package defect behind it.

## Dependencies

`robotstxtr` depends on R (>= 4.1.0) and imports `rurl` and `httr2`. Per the
package design, `robotstxtr` requires a `rurl` version that is not yet
available on CRAN, so the CRAN release of `robotstxtr` is blocked until the
required `rurl` version is on CRAN.

## Downstream dependencies

None — this is a new package.
