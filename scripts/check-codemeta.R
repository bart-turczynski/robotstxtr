#!/usr/bin/env Rscript
# check-codemeta v1
#
# codemeta.json names the DESCRIPTION Version, and every dependency
# constraint it records (softwareRequirements, softwareSuggestions) equals
# DESCRIPTION's Depends/Imports and Suggests. codemeta.json is hand-edited and
# never regenerated (ROBO-zghpvlxu), so nothing else keeps its requirement
# list in step.
#
#   Rscript scripts/check-codemeta.R      # from the package root
#
# A cheap gate of the fleet-ci local gate (.fleet-ci.yml), run in the full
# tier. It was the `codemeta` gate of the former dev/gates.R (ROBO-srowxxtg),
# which the `gates` CI job and the old pre-push hook ran; the rule is
# unchanged. Needs jsonlite, which the gate's run library holds (Suggests).
# Exit 1, naming each difference, on any.

description_field <- function(field) {
  unname(read.dcf("DESCRIPTION", fields = field)[1L, 1L])
}

# Named vector package -> constraint (NA when unconstrained).
description_deps <- function(fields) {
  values <- stats::na.omit(vapply(fields, description_field, character(1)))
  items <- trimws(unlist(strsplit(values, ",", fixed = TRUE)))
  items <- items[nzchar(items)]
  constraint <- ifelse(
    grepl("(", items, fixed = TRUE),
    gsub("\\s+", " ", trimws(sub("^[^(]*\\(([^)]*)\\).*$", "\\1", items))),
    NA_character_
  )
  stats::setNames(constraint, trimws(sub("\\(.*$", "", items)))
}

codemeta_deps <- function(entries) {
  # softwareRequirements also carries a plain "SystemRequirements" string.
  entries <- Filter(is.list, entries)
  constraint <- vapply(entries, function(d) {
    if (is.null(d$version)) NA_character_ else d$version
  }, character(1))
  ids <- vapply(entries, function(d) d$identifier, character(1))
  stats::setNames(constraint, ids)
}

dependency_drift <- function(what, declared, recorded) {
  drift <- character()
  for (pkg in sort(union(names(declared), names(recorded)))) {
    d <- if (pkg %in% names(declared)) declared[[pkg]] else "(absent)"
    r <- if (pkg %in% names(recorded)) recorded[[pkg]] else "(absent)"
    if (!identical(d, r)) {
      drift <- c(drift, sprintf(
        "%s %s: DESCRIPTION '%s', codemeta.json '%s'",
        what, pkg, if (is.na(d)) "(any)" else d, if (is.na(r)) "(any)" else r
      ))
    }
  }
  drift
}

version <- description_field("Version")
meta <- jsonlite::read_json("codemeta.json", simplifyVector = FALSE)
detail <- character()
if (!identical(meta$version, version)) {
  detail <- sprintf("version: DESCRIPTION '%s', codemeta.json '%s'",
                    version, format(meta$version))
}
detail <- c(
  detail,
  dependency_drift("requirement",
                   description_deps(c("Depends", "Imports")),
                   codemeta_deps(meta$softwareRequirements)),
  dependency_drift("suggestion",
                   description_deps("Suggests"),
                   codemeta_deps(meta$softwareSuggestions))
)
if (length(detail)) {
  cat(paste0("codemeta: ", detail, "\n"), sep = "")
  cat(
    "Hand-edit codemeta.json to match. Do NOT run ",
    "codemetar::write_codemeta(): the file is hand-maintained ",
    "(ROBO-zghpvlxu).\n",
    sep = ""
  )
  quit(status = 1L)
}
cat("codemeta: version '", version, "' and every dependency match ",
    "DESCRIPTION\n", sep = "")
