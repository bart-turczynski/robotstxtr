#!/usr/bin/env Rscript
# Deterministic, offline generator for the Bing conformance corpus projection.
#
# Introduced by ROBO-onwulhga (BI6). Produces the shipped artefacts from a
# read-only, byte-pinned view of a sibling robotstxtbing checkout:
#   inst/bing-corpus/bodies/<body_ref>.txt   (95 body files, byte-for-byte)
#   inst/bing-corpus/cases.json              (191 records, canonical JSON)
#   inst/bing-corpus/PROVENANCE.dcf          (pins + counts + SHA manifest)
#
# This script lives under dev/ (which is .Rbuildignore'd) and never ships. It
# requires the sibling tree to be present locally and reads it exclusively via
# `git -C <sibling> show <rev>:<path>` at the frozen release payload commit. It
# performs no download and touches no network.
#
# UNLIKE the Yandex generator, the sibling Bing corpus does NOT carry matched-
# rule metadata: an accepted expectation records only the tester-observed
# allow/disallow decision (and the request target is stored hashed, with its
# plaintext under plans/*/targets/). This generator therefore loads the package
# and drives every case through the PUBLIC v2 facade to capture the engine's
# matched-rule metadata as a golden snapshot -- and ASSERTS that the engine's
# decision equals the tester-observed decision for every case, aborting on any
# divergence. The tester decision is never rewritten to fit the adapter
# (spec SS16.3). Re-running yields byte-identical outputs (idempotent), because
# it shares the one canonical writer with the shipped validator in R/bing-corpus.R.
#
# Usage:
#   Rscript dev/gen-bing-corpus.R [<sibling-path>] [<payload-commit>]

# ---- Pins (verbatim from inst/vendor/robotstxtbing/MANIFEST.dcf) ------------
BING_CORPUS_PINS <- list(
  sibling_default = "/Users/bartturczynski/Projects/robotstxt-cpp-bing",
  payload_commit = "1f2431b9d47ba25dec313eec5a396e795f00b5b8",
  payload_tag_object = "c82855d0756c748cc4770246a19282323cdfa331",
  library_version = "0.1.0",
  sibling_contract_id = "robotstxtbing-v2",
  contract_revision = "0.1.0",
  parser_revision = "0.1.0",
  bingbot_profile_revision = "bingbot-2026-07-23.1",
  adidxbot_profile_revision = "adidxbot-2026-07-23.1",
  spec_revision = "2026-07-23.1",
  evidence_cutoff = "2026-07-23",
  release_manifest_file = "releases/robotstxtbing-0.1.0.manifest",
  release_manifest_sha256 =
    "5e79ee5dcb1a22b73b5fa0f86766be529cf111fd5530d07b53fe1d6b7050a858",
  matcher_revision = paste0(
    "robotstxtbing/0.1.0",
    "+payload.c82855d0756c748cc4770246a19282323cdfa331",
    ";contract=robotstxtbing-v2;contract-rev=0.1.0;parser=0.1.0",
    ";bingbot=bingbot-2026-07-23.1;adidxbot=adidxbot-2026-07-23.1",
    ";manifest=",
    "5e79ee5dcb1a22b73b5fa0f86766be529cf111fd5530d07b53fe1d6b7050a858"
  ),
  contract_file = "design/robotstxtbing-integration-v2-spec.md",
  facade_host = "https://example.test"
)

# ---- Locate the package root and load it (facade + shared serializer) -------
find_pkg_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(file_arg) == 1L && nzchar(file_arg)) {
    root <- normalizePath(dirname(dirname(file_arg)), winslash = "/")
    if (file.exists(file.path(root, "DESCRIPTION"))) {
      return(root)
    }
  }
  cwd <- normalizePath(getwd(), winslash = "/")
  if (file.exists(file.path(cwd, "DESCRIPTION"))) {
    return(cwd)
  }
  stop("Could not locate the package root (no DESCRIPTION found).")
}

PKG_ROOT <- find_pkg_root()
if (!requireNamespace("pkgload", quietly = TRUE)) {
  stop("The 'pkgload' package is required to run the Bing corpus generator.")
}
# load_all compiles src/ so the native Bing binding + the public facade are
# available; the shared canonical serializer comes from the same namespace.
suppressMessages(pkgload::load_all(PKG_ROOT, quiet = TRUE))

# ---- git-backed, byte-exact read helpers ------------------------------------
git_available <- function() nzchar(Sys.which("git"))

require_sibling <- function(sibling, rev) {
  if (!git_available()) {
    stop("git is required on PATH to read the sibling corpus.")
  }
  if (!dir.exists(sibling)) {
    stop(sprintf(
      "Sibling robotstxtbing checkout not found: %s\n%s",
      sibling, "This generator is offline: it will not download anything."
    ))
  }
  status <- suppressWarnings(system2(
    "git", c("-C", sibling, "cat-file", "-e", paste0(rev, "^{commit}")),
    stdout = FALSE, stderr = FALSE
  ))
  if (!identical(status, 0L)) {
    stop(sprintf(
      "Frozen payload commit %s is not present in %s (no fetch performed).",
      rev, sibling
    ))
  }
  invisible(TRUE)
}

git_show_raw <- function(sibling, rev, path) {
  tf <- tempfile()
  on.exit(unlink(tf), add = TRUE)
  status <- suppressWarnings(system2(
    "git", c("-C", sibling, "show", paste0(rev, ":", path)),
    stdout = tf, stderr = FALSE
  ))
  if (!identical(status, 0L)) {
    stop(sprintf("git show failed for %s:%s", rev, path))
  }
  sz <- file.size(tf)
  if (is.na(sz)) {
    stop(sprintf("Could not read git show output for %s:%s", rev, path))
  }
  readBin(tf, "raw", n = sz)
}

git_show_text <- function(sibling, rev, path) {
  rawToChar(git_show_raw(sibling, rev, path))
}

git_ls_tree <- function(sibling, rev, path) {
  out <- system2(
    "git",
    c("-C", sibling, "ls-tree", "-r", "--name-only", rev, "--", path),
    stdout = TRUE, stderr = FALSE
  )
  out[nzchar(out)]
}

sha256_of_raw <- function(bytes) {
  tf <- tempfile()
  on.exit(unlink(tf), add = TRUE)
  writeBin(bytes, tf)
  robotstxtr:::bing_corpus_sha256_file(tf)
}

# ---- .records parsing -------------------------------------------------------
# The sibling evidence format: blank-line-separated blocks of key=value lines,
# the first being schema=<name>. Returns a list of named character lists.
parse_records <- function(text) {
  blocks <- strsplit(text, "\n[ \t]*\n", perl = TRUE)[[1L]]
  recs <- list()
  for (block in blocks) {
    lines <- strsplit(block, "\n", fixed = TRUE)[[1L]]
    lines <- lines[nzchar(trimws(lines))]
    if (length(lines) == 0L) next
    kv <- list()
    for (ln in lines) {
      pos <- regexpr("=", ln, fixed = TRUE)
      if (pos < 1L) next
      key <- substr(ln, 1L, pos - 1L)
      val <- substr(ln, pos + 1L, nchar(ln))
      kv[[key]] <- val
    }
    recs[[length(recs) + 1L]] <- kv
  }
  recs
}

# ---- Release manifest -------------------------------------------------------
read_release_manifest <- function(sibling, rev) {
  p <- BING_CORPUS_PINS
  raw <- git_show_raw(sibling, rev, p$release_manifest_file)
  got_sha <- sha256_of_raw(raw)
  if (!identical(got_sha, p$release_manifest_sha256)) {
    stop(sprintf(
      "Release manifest SHA-256 mismatch: %s vs pinned %s.",
      got_sha, p$release_manifest_sha256
    ))
  }
  lines <- strsplit(rawToChar(raw), "\n", fixed = TRUE)[[1L]]
  kv <- function(key) {
    m <- lines[startsWith(lines, paste0(key, "="))]
    sub(paste0("^", key, "="), "", m)
  }
  sets <- kv("expectation_set")
  if (length(sets) != 14L) {
    stop(sprintf("Expected 14 expectation_set entries, found %d.",
                 length(sets)))
  }
  # Verify the frozen accepted-expectation counts the manifest declares.
  exp_count <- as.integer(kv("accepted_expectation_count"))
  bing_count <- as.integer(kv("accepted_expectation_bingbot_count"))
  adidx_count <- as.integer(kv("accepted_expectation_adidxbot_count"))
  stopifnot(identical(exp_count, 57L), identical(bing_count, 29L),
            identical(adidx_count, 28L))
  list(sets = sets, exp_count = exp_count,
       bingbot = bing_count, adidxbot = adidx_count)
}

# ---- Case assembly ----------------------------------------------------------
# For one expectation_set directory (relative to repo root, e.g.
# corpus/observations/bingbot-ordinary-v1), collect the accepted tester_observed
# cells and expand each to its referenced observations as concrete cases.
assemble_unit_cases <- function(sibling, rev, set_path) {
  unit <- basename(set_path)
  exps <- parse_records(git_show_text(sibling, rev,
                                      file.path(set_path,
                                                "expectations.records")))
  accepted <- Filter(function(e) {
    identical(e[["lifecycle"]], "accepted") &&
      identical(e[["grade"]], "tester_observed")
  }, exps)

  obsrecs <- parse_records(git_show_text(sibling, rev,
                                         file.path(set_path,
                                                   "observations.records")))
  obs_final <- list()
  probe_cases <- list()
  bodies <- list()
  for (r in obsrecs) {
    schema <- r[["schema"]]
    if (identical(schema, "evidence.observation_draft/v1")) {
      oid <- r[["id"]]
      seq <- as.integer(r[["sequence"]])
      prev <- obs_final[[oid]]
      if (is.null(prev) || seq > prev$seq) {
        obs_final[[oid]] <- list(seq = seq, rec = r)
      }
    } else if (identical(schema, "evidence.probe_case/v1")) {
      probe_cases[[r[["id"]]]] <- r
    } else if (identical(schema, "evidence.body/v1")) {
      bodies[[r[["id"]]]] <- r
    }
  }

  # Map target_sha256 -> plaintext target bytes from plans/<unit>/targets/.
  targets_dir <- file.path("corpus", "plans", unit, "targets")
  target_paths <- git_ls_tree(sibling, rev, targets_dir)
  target_by_sha <- list()
  for (tp in target_paths) {
    tb <- git_show_raw(sibling, rev, tp)
    target_by_sha[[sha256_of_raw(tb)]] <- tb
  }

  cases <- list()
  for (e in accepted) {
    exp_id <- e[["id"]]
    refs <- e[["observation_refs"]]
    if (is.null(refs) || identical(refs, "none")) next
    for (oid in strsplit(refs, ",", fixed = TRUE)[[1L]]) {
      of <- obs_final[[oid]]
      if (is.null(of)) stop(sprintf("%s: observation %s has no record.",
                                    unit, oid))
      orec <- of$rec
      pcid <- orec[["probe_case_ref"]]
      pc <- probe_cases[[pcid]]
      if (is.null(pc)) stop(sprintf("%s: probe_case %s missing.", unit, pcid))
      bref <- pc[["body_ref"]]
      bmeta <- bodies[[bref]]
      if (is.null(bmeta)) stop(sprintf("%s: body %s missing.", unit, bref))
      tsha <- pc[["target_sha256"]]
      tbytes <- target_by_sha[[tsha]]
      if (is.null(tbytes)) {
        stop(sprintf("%s: no target file for probe %s (sha %s).",
                     unit, pcid, tsha))
      }
      body_bytes <- git_show_raw(sibling, rev,
                                 file.path(set_path, bmeta[["path"]]))
      got_bsha <- sha256_of_raw(body_bytes)
      if (!identical(got_bsha, tolower(bmeta[["sha256"]]))) {
        stop(sprintf("%s: body %s SHA mismatch.", unit, bref))
      }
      cases[[length(cases) + 1L]] <- list(
        case_id = oid,
        unit = unit,
        expectation_id = exp_id,
        profile = pc[["profile"]],
        probe_case_id = pcid,
        body_ref = bref,
        body_bytes = body_bytes,
        body_sha256 = tolower(bmeta[["sha256"]]),
        byte_size = as.integer(bmeta[["byte_length"]]),
        target_bytes = tbytes,
        target_sha256 = tolower(tsha),
        tester_decision = orec[["decision"]],
        terminal_outcome = orec[["terminal_outcome"]]
      )
    }
  }
  cases
}

# Merge the per-(expectation,observation) rows into distinct observation cases,
# unioning the referencing expectation_ids and asserting every other field is
# identical for a shared observation.
dedup_cases <- function(raw_cases) {
  by_id <- list()
  for (c in raw_cases) {
    prev <- by_id[[c$case_id]]
    if (is.null(prev)) {
      c$expectation_ids <- c$expectation_id
      c$expectation_id <- NULL
      by_id[[c$case_id]] <- c
    } else {
      stopifnot(
        identical(prev$profile, c$profile),
        identical(prev$body_sha256, c$body_sha256),
        identical(prev$target_sha256, c$target_sha256),
        identical(prev$tester_decision, c$tester_decision)
      )
      prev$expectation_ids <- unique(c(prev$expectation_ids, c$expectation_id))
      by_id[[c$case_id]] <- prev
    }
  }
  by_id
}

# ---- Golden matcher_expected capture (drives the public v2 facade) ----------
capture_expected <- function(case) {
  target <- rawToChar(case$target_bytes)
  Encoding(target) <- "UTF-8"
  if (is.na(validUTF8(target)) ||
        !identical(charToRaw(enc2utf8(target)), case$target_bytes)) {
    stop(sprintf("Case %s target is not clean UTF-8.", case$case_id))
  }
  url <- paste0(BING_CORPUS_PINS$facade_host, target)
  body <- rawToChar(case$body_bytes)
  Encoding(body) <- "bytes"

  res <- robots_evaluate_text_v1(
    robots_txt = body, url = url,
    robots_product_token = case$profile,
    robots_policy_ruleset = "assumed_rfc9309",
    matcher_backend = "bing"
  )$results

  status <- res$matcher_status[[1L]]
  dec <- res$url_decision[[1L]]
  reason <- res$reason[[1L]]
  line <- res$matched_line[[1L]]
  rtype <- res$matched_rule_type[[1L]]
  value <- res$matched_rule_value[[1L]]
  raw_val <- res$matched_rule_value_raw[[1L]]

  # ---- Faithfulness + shape assertions (abort, never rewrite) --------------
  if (!identical(status, "evaluated")) {
    stop(sprintf("Case %s: engine status '%s' != evaluated.", case$case_id,
                 status))
  }
  if (!dec %in% c("allow", "disallow")) {
    stop(sprintf("Case %s: engine decision '%s' invalid.", case$case_id, dec))
  }
  # SS16.3 authority link: the engine must reproduce the tester-observed
  # decision. A mismatch means the vendored engine disagrees with the standalone
  # tester -- abort rather than record a rewritten expectation.
  if (!identical(dec, case$tester_decision)) {
    stop(sprintf(
      "Case %s: engine decision '%s' != tester decision '%s' (SS16.3).",
      case$case_id, dec, case$tester_decision
    ))
  }
  if (!reason %in% c("default_allow", "rule_allow", "rule_disallow")) {
    stop(sprintf("Case %s: unexpected reason '%s' in shipped corpus.",
                 case$case_id, reason))
  }

  if (identical(reason, "default_allow")) {
    stopifnot(is.na(line), identical(rtype, "none"), is.na(value),
              is.null(raw_val))
    matched_rule <- NULL
  } else {
    stopifnot(rtype %in% c("allow", "disallow"),
              identical(reason, paste0("rule_", rtype)),
              identical(dec, rtype),
              !is.na(line), !is.na(value), !is.null(raw_val),
              length(raw_val) > 0L)
    raw_hex <- robotstxtr:::bing_corpus_bytes_to_hex(raw_val)
    if (!identical(raw_hex,
                   robotstxtr:::bing_corpus_bytes_to_hex(
                     charToRaw(enc2utf8(value))))) {
      stop(sprintf("Case %s: raw bytes != UTF-8 of value.", case$case_id))
    }
    matched_rule <- list(
      line = as.integer(line), type = rtype, value = value,
      value_raw_hex = raw_hex
    )
  }

  list(
    case_id = case$case_id,
    profile = case$profile,
    unit = case$unit,
    expectation_ids = case$expectation_ids,
    probe_case_id = case$probe_case_id,
    body_ref = case$body_ref,
    body_file = paste0("bodies/", case$body_ref, ".txt"),
    body_sha256 = case$body_sha256,
    byte_size = case$byte_size,
    request_target = target,
    request_target_sha256 = case$target_sha256,
    tester_observed = list(
      terminal_outcome = case$terminal_outcome,
      decision = case$tester_decision
    ),
    matcher_expected = list(
      matcher_status = status,
      url_decision = dec,
      reason = reason,
      matched_rule = matched_rule
    ),
    body_bytes = case$body_bytes
  )
}

# ---- Main generation --------------------------------------------------------
generate_bing_corpus <- function(sibling = BING_CORPUS_PINS$sibling_default,
                                 rev = BING_CORPUS_PINS$payload_commit,
                                 out_dir = file.path(PKG_ROOT, "inst",
                                                     "bing-corpus")) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("The 'jsonlite' package is required to generate the corpus.")
  }
  require_sibling(sibling, rev)
  manifest <- read_release_manifest(sibling, rev)

  # 1. Assemble every accepted observation-level case across the 14 sets.
  raw_cases <- list()
  for (set_path in manifest$sets) {
    raw_cases <- c(raw_cases, assemble_unit_cases(sibling, rev, set_path))
  }
  cases <- dedup_cases(raw_cases)

  # 2. Drive each case through the facade for its golden matcher_expected, and
  #    assert engine == tester.
  records <- lapply(unname(cases), capture_expected)

  # 3. Write one byte-faithful body file per distinct body_ref.
  bodies_dir <- file.path(out_dir, "bodies")
  dir.create(bodies_dir, recursive = TRUE, showWarnings = FALSE)
  for (stale in list.files(bodies_dir, full.names = TRUE)) file.remove(stale)
  body_meta <- list()
  for (rec in records) {
    bref <- rec$body_ref
    if (!is.null(body_meta[[bref]])) next
    dest <- file.path(bodies_dir, paste0(bref, ".txt"))
    writeBin(rec$body_bytes, dest)
    disk_sha <- robotstxtr:::bing_corpus_sha256_file(dest)
    if (!identical(disk_sha, rec$body_sha256)) {
      stop(sprintf("On-disk body '%s' SHA-256 mismatch after write.", bref))
    }
    body_meta[[bref]] <- list(
      body_file = rec$body_file, sha256 = rec$body_sha256,
      byte_size = rec$byte_size
    )
  }

  # 4. Serialize cases.json with the shared canonical writer (drop body_bytes).
  records_json <- lapply(records, function(r) {
    r$body_bytes <- NULL
    r
  })
  cases_json <- robotstxtr:::bing_corpus_serialize(records_json)
  cases_path <- file.path(out_dir, "cases.json")
  writeBin(charToRaw(enc2utf8(cases_json)), cases_path)

  # 5. Provenance.
  write_provenance(out_dir, cases_path, body_meta, records_json, manifest)

  # 6. Self-check via the shipped validator.
  res <- robotstxtr:::verify_bing_corpus(out_dir)
  if (!isTRUE(res$ok)) {
    stop(sprintf("Generated corpus failed verification:\n%s",
                 paste(res$errors, collapse = "\n")))
  }
  message(sprintf(
    "Generated %d records / %d bodies (bingbot=%d adidxbot=%d) into %s (ok).",
    res$n_records, res$n_bodies, res$n_bingbot, res$n_adidxbot, out_dir
  ))
  invisible(res)
}

tally <- function(records, accessor) {
  vals <- vapply(records, accessor, character(1))
  tab <- sort(table(vals))
  tab[order(names(tab), method = "radix")]
}

fmt_dist <- function(tab) {
  paste(sprintf("%s=%d", names(tab), as.integer(tab)), collapse = ", ")
}

write_provenance <- function(out_dir, cases_path, body_meta, records,
                             manifest) {
  p <- BING_CORPUS_PINS
  profile_tab <- tally(records, function(r) r$profile)
  reason_tab <- tally(records, function(r) r$matcher_expected$reason)
  decision_tab <- tally(records, function(r) r$matcher_expected$url_decision)
  unit_tab <- tally(records, function(r) r$unit)

  cases_sha <- robotstxtr:::bing_corpus_sha256_file(cases_path)
  cases_bytes <- file.size(cases_path)

  header <- c(
    "Manifest: robotstxtr projection of the accepted Bing conformance corpus",
    "ManifestFormat: 1",
    "Unit: ROBO-onwulhga (BI6)",
    sprintf("ContractFile: %s", p$contract_file),
    "Offline: true; byte-pinned; consumed with no sibling checkout or network at build, test, or install time.",
    "Frozen: true",
    sprintf("PayloadCommit: %s", p$payload_commit),
    sprintf("PayloadTagObject: %s", p$payload_tag_object),
    sprintf("LibraryVersion: %s", p$library_version),
    sprintf("SiblingContractId: %s", p$sibling_contract_id),
    sprintf("ContractRevision: %s", p$contract_revision),
    sprintf("ParserRevision: %s", p$parser_revision),
    sprintf("BingbotProfileRevision: %s", p$bingbot_profile_revision),
    sprintf("AdidxbotProfileRevision: %s", p$adidxbot_profile_revision),
    sprintf("SpecRevision: %s", p$spec_revision),
    sprintf("EvidenceCutoff: %s", p$evidence_cutoff),
    sprintf("ReleaseManifestFile: %s", p$release_manifest_file),
    sprintf("ReleaseManifestSha256: %s", p$release_manifest_sha256),
    sprintf("MatcherRevision: %s", p$matcher_revision),
    "SourceProject: robotstxtbing (independent, unofficial standalone Bing-compatibility project; not affiliated with, endorsed by, or maintained by Microsoft, Bing, Bingbot, or AdIdxBot).",
    "MatcherAvailability: available (this projection consumes the activated Bing backend to record a golden snapshot; it registers nothing and changes no availability or schema revision).",
    "Provenance: two-tier. tester_observed.decision is the standalone tester's independently observed outcome, imported byte-faithfully and never rewritten (spec SS16.3). matcher_expected is a golden snapshot of the vendored engine's public v2 facade output; the generator asserts engine decision == tester decision for every case.",
    sprintf("AcceptedExpectationGrade: tester_observed"),
    sprintf("AcceptedExpectationCount: %d", manifest$exp_count),
    sprintf("AcceptedExpectationBingbotCount: %d", manifest$bingbot),
    sprintf("AcceptedExpectationAdidxbotCount: %d", manifest$adidxbot),
    sprintf("CaseCount: %d", length(records)),
    sprintf("DistinctBodyCount: %d", length(body_meta)),
    sprintf("ProfileBreakdown: %s", fmt_dist(profile_tab)),
    sprintf("DecisionBreakdown: %s", fmt_dist(decision_tab)),
    sprintf("ReasonBreakdown: %s", fmt_dist(reason_tab)),
    sprintf("UnitBreakdown: %s", fmt_dist(unit_tab)),
    "Generator: dev/gen-bing-corpus.R",
    "VerifyCommandOffline: Rscript -e 'stopifnot(robotstxtr:::verify_bing_corpus()$ok)'"
  )

  file_records <- list()
  file_records[[1L]] <- c(
    "File: cases.json",
    sprintf("Sha256: %s", cases_sha),
    sprintf("Bytes: %d", as.integer(cases_bytes)),
    "Category: cases"
  )
  brefs <- names(body_meta)
  ord <- order(vapply(brefs, function(b) body_meta[[b]]$body_file,
                      character(1)), method = "radix")
  for (bref in brefs[ord]) {
    m <- body_meta[[bref]]
    file_records[[length(file_records) + 1L]] <- c(
      sprintf("File: %s", m$body_file),
      sprintf("Sha256: %s", m$sha256),
      sprintf("Bytes: %d", m$byte_size),
      "Category: body"
    )
  }

  blocks <- c(
    paste(header, collapse = "\n"),
    vapply(file_records, function(x) paste(x, collapse = "\n"), character(1))
  )
  text <- paste0(paste(blocks, collapse = "\n\n"), "\n")
  writeBin(charToRaw(enc2utf8(text)), file.path(out_dir, "PROVENANCE.dcf"))
  invisible(TRUE)
}

# Run when invoked as a script.
if (sys.nframe() == 0L || identical(environment(), globalenv())) {
  cli_args <- commandArgs(trailingOnly = TRUE)
  sibling <- if (length(cli_args) >= 1L) cli_args[[1L]] else
    BING_CORPUS_PINS$sibling_default
  rev <- if (length(cli_args) >= 2L) cli_args[[2L]] else
    BING_CORPUS_PINS$payload_commit
  generate_bing_corpus(sibling = sibling, rev = rev)
}
