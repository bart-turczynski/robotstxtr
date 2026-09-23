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
# THIS SNAPSHOT: taken 2026-09-23, before SEOR-dyzgzyot/SEOR-wqxhftpv landed.
# It pins today's file, gap included -- .r-binaries does not yet reorder
# .libPaths(), and the deploy job's filter is a fixed 4-name deny list that
# does not catch an unlisted family. Both assertions are meant to be flipped
# to the opposite requirement in the same commit that fixes the YAML.
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

if (has_reorder) {
  fail(paste0(
    ".r-binaries already reorders .libPaths() -- this snapshot pins the ",
    "PRE-fix state (SEOR-dyzgzyot). Update the assertion to require the ",
    "reorder now that the fix has landed."
  ))
}
ok(paste0(
  ".r-binaries does not yet reorder .libPaths() (pins the known ",
  "SEOR-dyzgzyot gap: R_LIBS_USER is set but installs still land in ",
  "site-library and the cache never holds a built library)"
))

# ---- check 2: agent-instruction .md filter ----------------------------------
#
# pkgdown:::package_mds() hardcodes its own skip list (README/LICENSE(/CE)/
# NEWS) and its no_render list (cran-comments.md, issue/PR templates); nothing
# else is safe by default. Every OTHER top-level *.md gets rendered as a page
# and folded into search.json. Today's deploy job removes exactly four named
# files (AGENTS.md, CLAUDE.md, FP_AGENTS.md, FP_CLAUDE.md) -- a deny list,
# which by construction cannot cover a family it does not name. That gap is
# pinned here with a synthetic "GEMINI.md" sentinel.

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

remaining <- sort(list.files(scratch))
known_agent_files <- c("AGENTS.md", "CLAUDE.md", "FP_AGENTS.md", "FP_CLAUDE.md")
site_keep_list <- c(
  "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "LICENSE.md", "NEWS.md",
  "README.md", "SECURITY.md", "THIRD_PARTY_NOTICES.md", "cran-comments.md"
)

still_present <- intersect(known_agent_files, remaining)
if (length(still_present) > 0) {
  fail(paste0(
    "known agent-instruction file(s) survive the filter and would be ",
    "published by pkgdown: ", paste(still_present, collapse = ", ")
  ))
}
ok(paste0(
  "all of ", paste(known_agent_files, collapse = ", "),
  " are removed by today's filter"
))

if (!(sentinel %in% remaining)) {
  fail(paste0(
    sentinel, " (a stand-in for a future agent-file family) did NOT ",
    "survive the filter -- this snapshot expects today's deny list to miss ",
    "it. Either the filter changed (update this assertion to require it be ",
    "caught, SEOR-wqxhftpv) or the sentinel logic broke."
  ))
}
ok(paste0(
  sentinel, " (a new, unlisted agent-file family) survives today's deny-",
  "list filter -- the known SEOR-wqxhftpv gap"
))

missing_keep <- setdiff(intersect(site_keep_list, real_root_md), remaining)
if (length(missing_keep) > 0) {
  fail(paste0(
    "file(s) meant for the public site were removed from the root ",
    "unexpectedly: ", paste(missing_keep, collapse = ", ")
  ))
}
ok("files meant for the site (README/NEWS/LICENSE/... ) are left in place")

unlink(scratch, recursive = TRUE)
unlink(staging, recursive = TRUE)

cat("PASS: dev/check-ci-config.R\n")
