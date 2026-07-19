#!/usr/bin/env Rscript
# Deterministic, offline generator for the Yandex conformance corpus projection.
#
# Introduced by ROBO-novczgii (YI6a). Produces the three shipped artefacts from
# a read-only, byte-pinned view of a sibling robotstxtyandex checkout:
#   inst/yandex-corpus/bodies/<basename>.txt   (26 body files, byte-for-byte)
#   inst/yandex-corpus/cases.json              (140 records, canonical JSON)
#   inst/yandex-corpus/PROVENANCE.dcf          (pins + counts + SHA manifest)
#
# This script lives under dev/ (which is .Rbuildignore'd) and never ships. It
# requires the sibling tree to be present locally and reads it exclusively via
# `git -C <sibling> show <rev>:<path>` at a frozen revision. It performs no
# download and touches no network. Re-running it yields byte-identical outputs
# (idempotent), because it shares the one canonical writer with the shipped
# validator in R/yandex-corpus.R.
#
# Usage:
#   Rscript dev/gen-yandex-corpus.R [<sibling-path>] [<corpus-rev>]

# ---- Pins (verbatim from inst/vendor/robotstxtyandex/MANIFEST.dcf) ----------
YANDEX_CORPUS_PINS <- list(
  sibling_default = "/Users/bartturczynski/Projects/robotstxtyandex",
  corpus_rev = "337b9f3b886a92d6dc08c2fce84228d0cd6b801a",
  payload_commit = "fdd60a7c3bc6825f3b3752562dc0d6ad9387a27e",
  profile_id = "yandex-0.1.0",
  accepted_corpus_revision = "337b9f3b886a92d6dc08c2fce84228d0cd6b801a",
  profile_source_revision = "337b9f3b886a92d6dc08c2fce84228d0cd6b801a",
  evidence_snapshot = paste0(
    "9d69d361db81e7d236562dc056b41865da33d467d",
    "06f316e2c9a20988e007c96"
  ),
  matcher_revision = paste0(
    "robotstxtyandex/0.2.0",
    "+payload.fdd60a7c3bc6825f3b3752562dc0d6ad9387a27e",
    ";profile=yandex-0.1.0",
    ";corpus=337b9f3b886a92d6dc08c2fce84228d0cd6b801a",
    ";evidence=9d69d361db81e7d236562dc056b41865da33d467d",
    "06f316e2c9a20988e007c96",
    ";profile-source=337b9f3b886a92d6dc08c2fce84228d0cd6b801a"
  ),
  contract_file = "design/robotstxtyandex-integration-v1-spec.md"
)

# ---- Locate the package root and load the shared serializer -----------------
find_pkg_root <- function() {
  # Prefer the directory two levels up from this script (dev/ -> root).
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
source(file.path(PKG_ROOT, "R", "yandex-corpus.R"))

# ---- git-backed, byte-exact read helpers ------------------------------------
git_available <- function() {
  nzchar(Sys.which("git"))
}

# Verify the sibling tree exists and the frozen revision is present. No fetch,
# no download; a clear error otherwise.
require_sibling <- function(sibling, rev) {
  if (!git_available()) {
    stop("git is required on PATH to read the sibling corpus.")
  }
  if (!dir.exists(sibling)) {
    stop(sprintf(
      "Sibling robotstxtyandex checkout not found: %s\n%s",
      sibling,
      "This generator is offline: it will not download anything."
    ))
  }
  status <- suppressWarnings(system2(
    "git", c("-C", sibling, "cat-file", "-e", paste0(rev, "^{commit}")),
    stdout = FALSE, stderr = FALSE
  ))
  if (!identical(status, 0L)) {
    stop(sprintf(
      "Frozen corpus revision %s is not present in %s (no fetch performed).",
      rev, sibling
    ))
  }
  invisible(TRUE)
}

# Read a pinned path from the sibling as raw bytes, byte-for-byte.
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

git_list_expectations <- function(sibling, rev) {
  out <- system2(
    "git",
    c("-C", sibling, "ls-tree", "-r", "--name-only", rev,
      "--", "corpus/expectations"),
    stdout = TRUE, stderr = FALSE
  )
  out <- out[nzchar(out)]
  out[grepl("\\.json$", out)]
}

sha256_of_raw <- function(bytes) {
  tf <- tempfile()
  on.exit(unlink(tf), add = TRUE)
  writeBin(bytes, tf)
  yandex_corpus_sha256_file(tf)
}

# ---- Main generation --------------------------------------------------------
generate_yandex_corpus <- function(sibling = YANDEX_CORPUS_PINS$sibling_default,
                                   rev = YANDEX_CORPUS_PINS$corpus_rev,
                                   out_dir = file.path(
                                     PKG_ROOT, "inst", "yandex-corpus"
                                   )) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("The 'jsonlite' package is required to generate the corpus.")
  }
  require_sibling(sibling, rev)

  # 1. Read and validate all expectation files.
  exp_paths <- git_list_expectations(sibling, rev)
  if (length(exp_paths) != 140L) {
    stop(sprintf(
      "Expected exactly 140 expectation files, found %d.", length(exp_paths)
    ))
  }
  expectations <- lapply(exp_paths, function(p) {
    obj <- jsonlite::fromJSON(git_show_text(sibling, rev, p), simplifyVector = FALSE)
    if (!identical(obj[["schema_version"]], 1L) &&
          !identical(as.integer(obj[["schema_version"]]), 1L)) {
      stop(sprintf("%s: schema_version must be 1.", p))
    }
    if (!identical(as.character(obj[["review_state"]]), "accepted")) {
      stop(sprintf("%s: review_state must be 'accepted'.", p))
    }
    obj
  })

  # 2. Read the body index and map by body_id.
  index <- jsonlite::fromJSON(
    git_show_text(sibling, rev, "corpus/bodies/index.json"),
    simplifyVector = FALSE
  )
  body_index <- list()
  for (b in index[["bodies"]]) {
    body_index[[as.character(b[["body_id"]])]] <- b
  }

  # 3. Distinct referenced bodies.
  ref_body_ids <- unique(vapply(
    expectations, function(e) as.character(e[["body_id"]]), character(1)
  ))
  ref_body_ids <- sort(ref_body_ids, method = "radix")
  if (length(ref_body_ids) != 26L) {
    stop(sprintf(
      "Expected exactly 26 distinct referenced bodies, found %d.",
      length(ref_body_ids)
    ))
  }

  # Prepare output directories.
  bodies_dir <- file.path(out_dir, "bodies")
  dir.create(bodies_dir, recursive = TRUE, showWarnings = FALSE)
  # Remove any stale body files so the projection is exact.
  for (stale in list.files(bodies_dir, full.names = TRUE)) {
    file.remove(stale)
  }

  # 4. Copy each referenced body byte-for-byte and verify against the index.
  body_meta <- list()
  for (bid in ref_body_ids) {
    b <- body_index[[bid]]
    if (is.null(b)) {
      stop(sprintf("Referenced body_id '%s' is absent from index.json.", bid))
    }
    src_path <- as.character(b[["path"]])
    if (!grepl("\\.txt$", src_path)) {
      stop(sprintf("Body '%s' path is not a .txt file: %s", bid, src_path))
    }
    if (!identical(as.character(b[["encoding"]]), "utf-8")) {
      stop(sprintf("Body '%s' encoding is not utf-8.", bid))
    }
    basename_txt <- basename(src_path)
    bytes <- git_show_raw(sibling, rev, src_path)
    got_sha <- sha256_of_raw(bytes)
    want_sha <- tolower(as.character(b[["sha256"]]))
    if (!identical(got_sha, want_sha)) {
      stop(sprintf(
        "Body '%s' SHA-256 mismatch vs index.json (%s vs %s).",
        bid, got_sha, want_sha
      ))
    }
    if (!identical(length(bytes), as.integer(b[["byte_size"]]))) {
      stop(sprintf("Body '%s' byte size mismatch vs index.json.", bid))
    }
    dest <- file.path(bodies_dir, basename_txt)
    writeBin(bytes, dest)
    # Re-verify the on-disk file's SHA-256 equals the index SHA-256.
    disk_sha <- yandex_corpus_sha256_file(dest)
    if (!identical(disk_sha, want_sha)) {
      stop(sprintf("On-disk body '%s' SHA-256 mismatch after write.", bid))
    }
    body_meta[[bid]] <- list(
      basename = basename_txt,
      body_file = paste0("bodies/", basename_txt),
      sha256 = want_sha,
      byte_size = as.integer(b[["byte_size"]])
    )
  }

  # 5. Build the records.
  records <- lapply(expectations, function(e) {
    bid <- as.character(e[["body_id"]])
    meta <- body_meta[[bid]]
    if (is.null(meta)) {
      stop(sprintf("Expectation references unknown body_id '%s'.", bid))
    }
    rec <- list(
      case_id = as.character(e[["case_id"]]),
      body_id = bid,
      body_file = meta$body_file,
      body_sha256 = meta$sha256,
      byte_size = meta$byte_size,
      crawler = as.character(e[["crawler"]]),
      request_target = as.character(e[["request_target"]]),
      expected = e[["expected"]],
      sources = e[["sources"]]
    )
    if (!is.null(e[["observation_case_ids"]])) {
      rec[["observation_case_ids"]] <- e[["observation_case_ids"]]
    }
    rec
  })

  # 6. Serialize cases.json with the shared canonical writer.
  cases_json <- yandex_corpus_serialize(records)
  cases_path <- file.path(out_dir, "cases.json")
  writeBin(charToRaw(enc2utf8(cases_json)), cases_path)

  # 7. Build PROVENANCE.dcf.
  write_provenance(
    out_dir = out_dir,
    cases_path = cases_path,
    body_meta = body_meta,
    ref_body_ids = ref_body_ids,
    records = jsonlite::fromJSON(cases_path, simplifyVector = FALSE)
  )

  # 8. Self-check via the shipped validator.
  res <- verify_yandex_corpus(out_dir)
  if (!isTRUE(res$ok)) {
    stop(sprintf(
      "Generated corpus failed verification:\n%s",
      paste(res$errors, collapse = "\n")
    ))
  }
  message(sprintf(
    "Generated %d records / %d bodies into %s (verified ok).",
    res$n_records, res$n_bodies, out_dir
  ))
  invisible(res)
}

# Distribution counts over the canonical records.
tally <- function(records, accessor) {
  vals <- vapply(records, accessor, character(1))
  tab <- sort(table(vals))
  tab <- tab[order(names(tab), method = "radix")]
  tab
}

fmt_dist <- function(tab) {
  paste(sprintf("%s=%d", names(tab), as.integer(tab)), collapse = ", ")
}

write_provenance <- function(out_dir, cases_path, body_meta, ref_body_ids,
                             records) {
  p <- YANDEX_CORPUS_PINS

  crawler_tab <- tally(records, function(r) as.character(r[["crawler"]]))
  source_tab <- tally(records, function(r) as.character(r[["expected"]][["source"]]))
  decision_tab <- tally(records, function(r) as.character(r[["expected"]][["decision"]]))

  cases_sha <- yandex_corpus_sha256_file(cases_path)
  cases_bytes <- file.size(cases_path)

  header <- c(
    "Manifest: robotstxtr projection of the accepted Yandex conformance corpus",
    "ManifestFormat: 1",
    "Unit: ROBO-novczgii (YI6a)",
    sprintf("ContractFile: %s", p$contract_file),
    "Offline: true; byte-pinned; consumed with no sibling checkout or network at build, test, or install time.",
    "Frozen: true",
    sprintf("PayloadCommit: %s", p$payload_commit),
    sprintf("ProfileId: %s", p$profile_id),
    sprintf("AcceptedCorpusRevision: %s", p$accepted_corpus_revision),
    sprintf("ProfileSourceRevision: %s", p$profile_source_revision),
    sprintf("EvidenceSnapshot: %s", p$evidence_snapshot),
    sprintf("MatcherRevision: %s", p$matcher_revision),
    "SourceProject: robotstxtyandex (independent, unofficial standalone compatibility project; not affiliated with or endorsed by Yandex)",
    "MatcherAvailability: capability_unavailable (this unit adds test data and an offline validator only; it registers no matcher and changes no availability or schema revision).",
    sprintf("CaseCount: %d", length(records)),
    sprintf("DistinctBodyCount: %d", length(ref_body_ids)),
    sprintf("CrawlerBreakdown: %s", fmt_dist(crawler_tab)),
    sprintf("DecisionBreakdown: %s", fmt_dist(decision_tab)),
    sprintf("SourceBreakdown: %s", fmt_dist(source_tab)),
    "Generator: dev/gen-yandex-corpus.R",
    "VerifyCommandOffline: Rscript -e 'stopifnot(robotstxtr:::verify_yandex_corpus()$ok)'"
  )

  # Per-file SHA-256 manifest: cases.json first, then the 26 body files in a
  # deterministic (radix-sorted by relative path) order.
  file_records <- list()
  file_records[[1]] <- c(
    "File: cases.json",
    sprintf("Sha256: %s", cases_sha),
    sprintf("Bytes: %d", as.integer(cases_bytes)),
    "Category: cases"
  )
  body_files <- vapply(ref_body_ids, function(bid) body_meta[[bid]]$body_file,
                       character(1))
  ord <- order(body_files, method = "radix")
  for (bid in ref_body_ids[ord]) {
    m <- body_meta[[bid]]
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
  sibling <- if (length(cli_args) >= 1L) cli_args[[1]] else
    YANDEX_CORPUS_PINS$sibling_default
  rev <- if (length(cli_args) >= 2L) cli_args[[2]] else
    YANDEX_CORPUS_PINS$corpus_rev
  generate_yandex_corpus(sibling = sibling, rev = rev)
}
