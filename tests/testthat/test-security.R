# OSS Index dependency vulnerability audit (oysteR / Sonatype).
#
# `oysteR::audit()` checks robotstxtr's installed hard-dependency closure
# against the Sonatype OSS Index. It is a network test that requires OSS Index
# credentials (OSSINDEX_USER / OSSINDEX_TOKEN): the API rejects
# unauthenticated requests with HTTP 401.
#
# Scope: hard dependencies only -- the recursive `Depends` + `Imports` (+
# `LinkingTo`) closure, never `Suggests`.
#
# `oysteR::expect_secure()` audits `Suggests` as well, which drags in the
# recursive dependency trees of the dev tooling -- including oysteR's own. A
# vulnerability in the auditor is not a vulnerability in what robotstxtr makes
# users install, and a package's security posture is the latter. Measured
# 2026-09-10: `Depends` + `Imports` audits 25 packages, the Suggests-inclusive
# scope 84. Neither `expect_secure()` nor `audit_description()` is used: both
# expand dependencies against CRAN's index, which does not carry ssrfr, so
# they stopped auditing curl (ROBO-jvcpjstv). oss_index_audit_targets() in
# helper-security.R resolves the closure from the installed library instead.
#
# The allow-list and rules A/B/C live in helper-security.R, next to the data
# they govern. Read that file before adding a row.
#
# WHERE THIS RUNS, AND WHY THE PRECONDITIONS ARE NOT ALWAYS SKIPS.
#
# Everywhere ordinary -- a local `testthat::test_local()`, a plain
# `R CMD check --as-cran` -- a missing precondition is a skip. That is right: a
# developer without OSS Index credentials is not a security regression.
#
# A job that exists to run this audit is different. If it lacks credentials,
# `skip_if()` fires, the job reports success, and nothing has been audited --
# the failure `PUNY-rsxtbbln` records in punycoder. A green job that audited
# nothing is worse than no job, because it answers the question it was never
# asked. So under OSSINDEX_AUDIT_REQUIRED=true every precondition below
# becomes a hard failure with a message naming what is missing.
#
# That job is fleet-ci's T2 `security-audit` (the weekly deep-check schedule,
# or a T3 run). It cannot go green on nothing because it sets
# OSSINDEX_AUDIT_REQUIRED=true (SEOR-fftbjnpl). Everywhere else the flag is
# unset and the preconditions stay skips.
#
# NOTE ON THE PRE-PUSH GATE. The audit does not run on push. The gate is
# fleet-ci's local gate, and `.fleet-ci.yml` lists this whole file under
# `exclude_tests`, so neither the live audit nor the offline fixture tests
# below run there (design/ci.md). They run under a local
# `devtools::test(filter = "security")` and in the T2 jobs that set NOT_CRAN.

test_that("the OSS Index allow-list is well formed", {
  # No `expect_gt(length(oss_index_allowlist), 0)` here, although this repo
  # has rows. Emptiness is not a malformation: when curl ships a fix, rule B
  # deletes the rows and an empty list is the correct state. The other way
  # round -- rows removed while the advisories are still reported -- rule A
  # catches in the audit below, so a non-empty assertion would guard nothing
  # and would have to be remembered and deleted along with the last row.
  expect_equal(oss_index_allowlist_violations(oss_index_allowlist), character())
})

test_that("the allow-list validator rejects rows that are not decisions", {
  sound <- list(
    id = "CVE-2026-18924",
    package = "curl",
    version_seen = "8.0.0",
    review = as.Date("2026-12-01"),
    reason = paste(
      "A rationale long enough to be an argument rather than a placeholder,",
      "naming the advisory, the exposure assessed and why it is accepted."
    )
  )
  expect_equal(oss_index_allowlist_violations(list(sound)), character())

  broken <- function(field, value) {
    row <- sound
    row[[field]] <- value
    oss_index_allowlist_violations(list(row))
  }

  expect_match(
    broken("id", "GHSA-xxxx"),
    "single CVE identifier",
    fixed = TRUE
  )
  expect_match(broken("package", ""), "single package name", fixed = TRUE)
  expect_match(
    broken("version_seen", "not-a-version"),
    "parseable version",
    fixed = TRUE
  )
  expect_match(broken("review", "2026-12-01"), "single Date", fixed = TRUE)
  expect_match(
    broken("reason", "unfixable"),
    "too short to be an argument",
    fixed = TRUE
  )

  expect_match(
    oss_index_allowlist_violations(list(sound[-5])),
    "missing field(s): reason",
    fixed = TRUE
  )
  expect_match(
    oss_index_allowlist_violations(list(c(sound, list(owner = "me")))),
    "unknown field(s): owner",
    fixed = TRUE
  )
  expect_match(
    oss_index_allowlist_violations(list(sound, sound)),
    "duplicate allow-list id",
    fixed = TRUE
  )
})

# A fixture shaped like `installed.packages()`: robotstxtr imports ssrfr,
# ssrfr imports curl and links a header-only package, and robotstxtr also
# depends on a base package. It is the shape of the real closure since
# 0b78b5d, in which curl is reachable only through ssrfr.
oss_index_fixture_db <- function(drop = character()) {
  rows <- list(
    c("robotstxtr", "0.0.0.9000", NA, "R (>= 4.1), utils", "ssrfr", NA),
    c("ssrfr", "1.0.0.9001", NA, NA, "curl (>= 7.0.0)", "hdronly"),
    c("curl", "8.1.0", NA, NA, NA, NA),
    c("hdronly", "1.2.3", NA, NA, NA, NA),
    c("utils", "4.6.2", "base", NA, NA, NA)
  )
  db <- do.call(rbind, rows)
  colnames(db) <- c(
    "Package",
    "Version",
    "Priority",
    "Depends",
    "Imports",
    "LinkingTo"
  )
  rownames(db) <- db[, "Package"]
  db[!rownames(db) %in% drop, , drop = FALSE]
}

test_that("the audit targets are the installed hard-dependency closure", {
  targets <- oss_index_audit_targets("robotstxtr", db = oss_index_fixture_db())

  # curl is two hops away, through a package CRAN does not serve. The
  # expansion has to be recursive and has to read the installed db.
  expect_equal(
    targets[order(targets$package), ],
    data.frame(
      package = c("curl", "hdronly", "ssrfr"),
      version = c("8.1.0", "1.2.3", "1.0.0.9001"),
      stringsAsFactors = FALSE
    ),
    ignore_attr = "row.names"
  )

  # Base packages and R itself are not audited.
  expect_false(any(c("utils", "R", "robotstxtr") %in% targets$package))

  # What a CRAN-only `available.packages()` amounted to: a db that cannot
  # expand ssrfr. ssrfr is still named, as a direct import, but nothing it
  # imports is, and it is reported as not installed rather than dropped.
  blind <- oss_index_audit_targets(
    "robotstxtr",
    db = oss_index_fixture_db(drop = "ssrfr")
  )
  expect_false("curl" %in% blind$package)
  expect_equal(blind$package[is.na(blind$version)], "ssrfr")
})

test_that("the coverage check names every package the audit did not see", {
  targets <- oss_index_audit_targets("robotstxtr", db = oss_index_fixture_db())
  curl_row <- list(list(package = "curl"))
  audit <- function(package, version = rep("1", length(package))) {
    data.frame(package = package, version = version, stringsAsFactors = FALSE)
  }
  complete <- audit(c("ssrfr", "hdronly", "curl"))

  expect_equal(oss_index_unaudited(complete, targets, curl_row), character())
  # The shape of this ticket: curl absent from the audit while allow-list
  # rows name it.
  expect_equal(
    oss_index_unaudited(audit(c("ssrfr", "hdronly")), targets, curl_row),
    "curl"
  )
  # An allow-listed package outside the closure is reported too, so a row can
  # never be kept alive, or retired, by an audit that never looked.
  expect_equal(
    oss_index_unaudited(complete, targets, list(list(package = "openssl"))),
    "openssl"
  )
  # A row with no version was not checked: oysteR returns it unaudited.
  expect_equal(
    oss_index_unaudited(
      audit(c("ssrfr", "hdronly", "curl"), c("1", "1", NA)),
      targets,
      curl_row
    ),
    "curl"
  )
})

test_that("hard dependencies report only allow-listed OSS Index advisories", {
  # The dedicated, credentialed audit job. A precondition it cannot meet is a
  # failure there, never a skip -- see the header.
  required <- identical(Sys.getenv("OSSINDEX_AUDIT_REQUIRED"), "true")
  no_credentials <- Sys.getenv("OSSINDEX_USER") == "" ||
    Sys.getenv("OSSINDEX_TOKEN") == ""

  if (required) {
    if (!requireNamespace("oysteR", quietly = TRUE)) {
      stop(
        "OSSINDEX_AUDIT_REQUIRED is set but {oysteR} is not installed, so ",
        "this job cannot audit anything. Install it or unset the flag; do ",
        "not let the job report success."
      )
    }
    if (no_credentials) {
      stop(
        "OSSINDEX_AUDIT_REQUIRED is set but OSSINDEX_USER / OSSINDEX_TOKEN ",
        "are absent, so OSS Index would reject every request with HTTP 401 ",
        "and this job would report success having audited nothing. Add both ",
        "as CI/CD variables (project Settings > CI/CD > Variables) to the ",
        "job that sets the flag."
      )
    }
    # Deliberately no skip_if_offline() on this path: a network the job cannot
    # reach is the same vacuous green as a credential it does not have, so let
    # the audit attempt the call and fail on the transport error.
  } else {
    skip_on_cran()
    skip_if_not_installed("oysteR")
    skip_if_offline()
    skip_if(
      no_credentials,
      "OSS Index credentials (OSSINDEX_USER / OSSINDEX_TOKEN) not set"
    )
  }

  # The closure comes from the installed library, not from CRAN's index: see
  # oss_index_audit_targets() for why audit_description() stopped seeing curl.
  targets <- oss_index_audit_targets(
    "robotstxtr",
    db = utils::installed.packages() # nolint: installed_packages_linter.
  )

  # A hard dependency that is not installed cannot be audited at its version.
  # Fail rather than audit less: that is the vacuous green this file exists to
  # refuse.
  expect_equal(targets$package[is.na(targets$version)], character())
  targets <- targets[!is.na(targets$version), ]

  audit <- oysteR::audit(
    targets$package,
    targets$version,
    type = "cran",
    verbose = FALSE
  )
  found <- oss_index_reported(audit)
  allowed <- vapply(oss_index_allowlist, function(row) row$id, character(1))

  # An audit that resolved nothing, or less than the closure, is not a clean
  # audit. A package missing here satisfies rule A vacuously and fails rule B
  # for the wrong reason (ROBO-jvcpjstv), so coverage is checked first, by
  # name: every target and every package an allow-list row names.
  expect_gt(nrow(audit), 0)
  expect_equal(
    oss_index_unaudited(audit, targets, oss_index_allowlist),
    character()
  )

  # Rule A -- an advisory reported and not allow-listed.
  expect_equal(sort(setdiff(found$id, allowed)), character())

  # Rule B -- an allow-listed advisory no longer reported. The list may not
  # over-permit, so a row that has outlived its justification fails here.
  expect_equal(sort(setdiff(allowed, found$id)), character())

  # Rule C -- drift warns, never fails. See helper-security.R.
  for (row in oss_index_allowlist) {
    if (Sys.Date() > row$review) {
      warning(
        sprintf(
          "OSS Index allow-list row %s is past its %s review date.",
          row$id,
          format(row$review)
        ),
        call. = FALSE
      )
    }
    hit <- found[found$id == row$id, ]
    if (
      nrow(hit) > 0 &&
        package_version(hit$version[1]) > package_version(row$version_seen)
    ) {
      warning(
        sprintf(
          paste(
            "OSS Index allow-list row %s was written against %s %s;",
            "the audit now reports %s. Re-read the advisory."
          ),
          row$id,
          row$package,
          row$version_seen,
          hit$version[1]
        ),
        call. = FALSE
      )
    }
  }
})
