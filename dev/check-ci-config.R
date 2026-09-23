#!/usr/bin/env Rscript
#
# Config pin for .gitlab-ci.yml (SEOR-dyzgzyot, SEOR-wqxhftpv). This checks the
# BUILD the CI file produces, not R behavior: it parses .gitlab-ci.yml and
# asserts (1) the .libPaths() ordering the shared `.r-binaries` setup anchor
# produces, and (2) which top-level *.md files survive the pkgdown deploy
# job's agent-instruction filter.
#
# Both checks execute the ACTUAL text extracted from the YAML (a literal
# substring match for the .libPaths() line; a real `sh` run of the filter's
# shell lines against a scratch copy of the repo's real top-level *.md
# filenames, plus a synthetic "GEMINI.md" sentinel standing in for a future
# agent-file family this repo does not have a file for yet) rather than
# re-deriving what the file is supposed to do, so a change to the YAML that
# does not also update this script is caught here instead of surfacing as a
# published AGENTS.html or a cache that silently never holds a built library.
#
# THIS SNAPSHOT: updated 2026-09-23 alongside the SEOR-dyzgzyot/SEOR-wqxhftpv
# fix. It now pins the FIXED file: .r-binaries reorders .libPaths() so the
# cached directory wins, and the deploy job's filter is a keep-list that
# sweeps anything not explicitly meant for the site -- including a family it
# has never seen before, proven with a synthetic "GEMINI.md" sentinel -- while
# asserting an EXACT match against the full expected survivor set (not just a
# subset), so a file's own publish/private status (CHANGELOG.md, grandfathered
# per the coordinator's decision -- see below) cannot drift silently. An
# earlier revision of this script (see git history) pinned the opposite,
# pre-fix state and was flipped here on purpose.
#
# Usage (from the package root): Rscript dev/check-ci-config.R

library(yaml)

fail <- function(msg) {
  cat("FAIL:", msg, "\n")
  quit(status = 1)
}
ok <- function(msg) cat("OK:", msg, "\n")

cfg <- yaml::read_yaml(".gitlab-ci.yml", eval.expr = FALSE)

# ---- check 1: .libPaths() ordering ------------------------------------------
#
# rocker/r-ver's Renviron.site puts /usr/local/lib/R/site-library FIRST in
# .libPaths() and R_LIBS_USER third, so R installs land in the image and die
# with the container unless something reorders .libPaths() late enough to
# win (Rprofile.site, not the environment -- Renviron.site is read later and
# overrides R_LIBS_SITE). Verified against rocker/r-ver:4.5.1 directly:
#   before: .libPaths() == site-library, library
#   after appending the line below to Rprofile.site:
#     .libPaths() == R_LIBS_USER, site-library, library
#   and install.packages("jsonlite") landed in R_LIBS_USER.

r_binaries <- cfg[[".r-binaries"]]
if (is.null(r_binaries)) fail(".r-binaries anchor not found in .gitlab-ci.yml")

reorder_line <- '.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))'
has_reorder <- grepl(reorder_line, r_binaries, fixed = TRUE)

if (!has_reorder) {
  fail(paste0(
    ".r-binaries does not reorder .libPaths() -- R_LIBS_USER is set but ",
    "nothing puts it ahead of site-library, so installs land in the image ",
    "and the cache never holds a built library (SEOR-dyzgzyot)."
  ))
}
ok(".r-binaries reorders .libPaths() so R_LIBS_USER wins (SEOR-dyzgzyot)")

# ---- check 2: agent-instruction .md filter ----------------------------------
#
# pkgdown:::package_mds() hardcodes its own skip list (README/LICENSE(/CE)/
# NEWS) and its no_render list (cran-comments.md, issue/PR templates); nothing
# else is safe by default. Every OTHER top-level *.md gets rendered as a page
# and folded into search.json. The deploy job's filter is now a keep-list: it
# moves every top-level *.md NOT explicitly meant for the site into
# /tmp/agent-md, so an unknown file -- stood in here by a synthetic
# "GEMINI.md" sentinel this repo has no real file for -- is swept by default
# instead of published by default.

deploy_job <- cfg[[".pkgdown-site"]]
if (is.null(deploy_job)) fail(".pkgdown-site job not found in .gitlab-ci.yml")
script_lines <- deploy_job[["script"]]
if (is.null(script_lines)) fail(".pkgdown-site has no script: block")

# Only the lines that actually touch *.md / an agent-md staging dir -- skip
# the Rscript build_site() and `mv docs public` lines, which this check has no
# business running.
filter_lines <- Filter(function(l) grepl("\\.md\\b|agent-md", l), script_lines)
if (length(filter_lines) == 0) {
  fail("no *.md-filtering line found in the .pkgdown-site script")
}

real_root_md <- sort(list.files(".", pattern = "\\.md$"))
sentinel <- "GEMINI.md"

scratch <- tempfile("check-ci-config-")
staging <- "/tmp/agent-md"
dir.create(scratch)
unlink(staging, recursive = TRUE)
invisible(file.create(file.path(scratch, c(real_root_md, sentinel))))

script_path <- file.path(scratch, "filter.sh")
writeLines(filter_lines, script_path)
res <- system2(
  "sh",
  c("-c", shQuote(paste("cd", shQuote(scratch), "&&", "sh", shQuote(script_path)))),
  stdout = TRUE, stderr = TRUE
)
status <- attr(res, "status")
if (!is.null(status) && status != 0) {
  fail(paste0(
    "the .pkgdown-site filter lines exited non-zero against today's ",
    "top-level .md files:\n  ", paste(res, collapse = "\n  ")
  ))
}

# Exclude filter.sh itself (written into scratch below to run the extracted
# lines) -- it is test harness, not a file the real job's checkout would ever
# have at its root.
remaining <- sort(list.files(scratch, pattern = "\\.md$"))
moved <- if (dir.exists(staging)) sort(list.files(staging)) else character(0)
known_agent_files <- c("AGENTS.md", "CLAUDE.md", "FP_AGENTS.md", "FP_CLAUDE.md")

# The full, exact expected survivor set -- not just "these are safe if
# present" but "this is the whole list, no more, no less". Written as a
# literal here (not derived from the keep= string in the YAML) so this
# script has its own opinion, independent of the file it is checking.
#
# CHANGELOG.md is here deliberately: it is a near-empty stub, unreferenced
# by _pkgdown.yml, and distinct from the real NEWS.md -- flagged for review
# rather than silently kept when this filter was first inverted
# (SEOR-wqxhftpv). The coordinator decided GRANDFATHER, not retire:
# https://robotstxtr-de6c15.gitlab.io/CHANGELOG.html already returns 200,
# and this repo's `pages` job auto-deploys on every push to main, so
# sweeping it now would have silently taken down a live page as a
# side effect of a hygiene fix. Retiring it later is a separate, explicit
# editorial change for the owner to make on purpose, not a by-product of
# this ticket. This exact-match check exists so that a future edit to the
# `keep=` string cannot move CHANGELOG.md (or anything else) across that
# line again without this pin noticing -- the earlier, subset-only version
# of this check was blind to exactly that kind of drift.
site_keep_list <- c(
  "CHANGELOG.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "LICENSE.md",
  "NEWS.md", "README.md", "SECURITY.md", "THIRD_PARTY_NOTICES.md",
  "cran-comments.md"
)

still_present <- intersect(known_agent_files, remaining)
if (length(still_present) > 0) {
  fail(paste0(
    "known agent-instruction file(s) survive the filter and would be ",
    "published by pkgdown: ", paste(still_present, collapse = ", ")
  ))
}
not_moved <- setdiff(known_agent_files, moved)
if (length(not_moved) > 0) {
  fail(paste0(
    "known agent-instruction file(s) are gone from the root but were not ",
    "moved into ", staging, ": ", paste(not_moved, collapse = ", ")
  ))
}
ok(paste0(
  "all of ", paste(known_agent_files, collapse = ", "),
  " are moved into ", staging
))

if (sentinel %in% remaining) {
  fail(paste0(
    sentinel, " (a stand-in for a future agent-file family) survived the ",
    "filter -- the keep-list regressed to a fail-open deny list ",
    "(SEOR-wqxhftpv)."
  ))
}
if (!(sentinel %in% moved)) {
  fail(paste0(
    sentinel, " is not in the root, but it was not moved into ", staging,
    " either -- something other than the keep-list mv made it disappear."
  ))
}
ok(paste0(
  sentinel, " (a new, unlisted agent-file family) is swept into ", staging,
  " even though the filter has never seen it before"
))

# Exact-match, not subset: an expected survivor missing from `remaining` is
# a file the filter swept by mistake; anything in `remaining` NOT expected
# is a file publishing that was never decided on. Both directions matter --
# a subset-only check would have stayed silent while CHANGELOG.md moved
# from published to private (or the reverse) as a side effect of an
# unrelated edit to the keep= string.
expected_survivors <- intersect(site_keep_list, real_root_md)
extra_survivors <- setdiff(remaining, expected_survivors)
missing_survivors <- setdiff(expected_survivors, remaining)
if (length(extra_survivors) > 0 || length(missing_survivors) > 0) {
  fail(paste0(
    "the surviving top-level .md set does not match the expected site set.",
    if (length(extra_survivors) > 0) {
      paste0(
        " Published without a decision on record: ",
        paste(extra_survivors, collapse = ", "), "."
      )
    } else {
      ""
    },
    if (length(missing_survivors) > 0) {
      paste0(
        " Swept out of the root unexpectedly: ",
        paste(missing_survivors, collapse = ", "), "."
      )
    } else {
      ""
    }
  ))
}
ok(paste0(
  "surviving top-level .md set matches exactly: ",
  paste(expected_survivors, collapse = ", ")
))

unlink(scratch, recursive = TRUE)
unlink(staging, recursive = TRUE)

cat("PASS: dev/check-ci-config.R\n")
