#!/usr/bin/env Rscript
#
# Corpus harness entry point (ROBO-qbxsydcf). Usage: dev/corpus/README.md.
#
#   Rscript dev/corpus/run.R <mode> [--pkg <path>] [--seed N] [--run-id ID]
#     [--workers 1|2] [--chunk-size N] [--max-rule-paths N]
#     [--random-paths N] [--subset K/N] [--max-hosts N] [--manifest ID]
#   Rscript dev/corpus/run.R compare --a <run-id> --b <run-id> [--run-id ID]
#
# Needs ROBOTSTXTR_CORPUS (read-only input) and ROBOTSTXTR_CORPUS_OUT (outside
# any git work tree); writes its outputs only under
# ROBOTSTXTR_CORPUS_OUT/<run-id>/. The one write outside it: validate,
# evaluate and size load --pkg with pkgload::load_all(), which compiles src/
# inside that package tree (its object files and shared library).

script_dir <- local({
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (!length(file_arg)) {
    stop("Run this script with Rscript.")
  }
  dirname(normalizePath(sub("^--file=", "", file_arg[[1L]])))
})
source(file.path(script_dir, "harness.R"))
source(file.path(script_dir, "modes.R"))

write_record <- function(run_dir, record) {
  saveRDS(record, file.path(run_dir, "record.rds"))
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    writeLines(
      jsonlite::toJSON(record, auto_unbox = TRUE, pretty = TRUE, digits = NA,
                       null = "null", na = "null"),
      file.path(run_dir, "record.json")
    )
  }
}

harness_main <- function(args) {
  t0 <- proc.time()[["elapsed"]]
  gc(reset = TRUE)
  opts <- parse_harness_args(args)
  cfg <- corpus_env_config(need_corpus = opts$mode != "compare")
  # Everything that can refuse runs before the run directory exists, so a
  # refusal leaves no "running" record behind: the --manifest run, the --pkg
  # tree, every compare check and the chunk plan.
  frozen <- if (!is.na(opts$manifest)) {
    frozen_run(cfg$out, opts$manifest)
  }
  package <- if (opts$mode %in% c("validate", "evaluate", "size")) {
    package_git_facts(opts$pkg)
  }
  if (opts$mode == "compare") {
    prepared <- prepare_compare(cfg$out, opts)
  } else {
    hosts <- list_host_dirs(cfg$corpus)
    chunks <- plan_chunks(hosts, opts)
    # The start manifest right after the listing, before the package
    # compiles: a planned directory gone by now is caught as gone.
    start <- corpus_manifest(cfg$corpus, plan_frame(hosts, chunks))
  }
  if (is.na(opts$run_id)) {
    opts$run_id <- paste0(
      opts$mode, "-", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
    )
  }
  run_dir <- create_run_dir(cfg$out, opts$run_id)
  message("run dir: ", run_dir)
  record <- list(
    run_id = opts$run_id,
    mode = opts$mode,
    started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    corpus = cfg$corpus,
    params = opts[setdiff(names(opts), "run_id")],
    r_version = R.version.string,
    platform = R.version$platform,
    harness = harness_git_facts(script_dir),
    status = "running"
  )
  write_record(run_dir, record)

  ctx <- list(opts = opts, out = cfg$out, corpus = cfg$corpus,
              run_dir = run_dir)
  if (opts$mode %in% c("validate", "evaluate", "size")) {
    record$package <- package
    pkgload::load_all(
      opts$pkg, quiet = TRUE, export_all = FALSE, helpers = FALSE,
      attach_testthat = FALSE
    )
    ns <- "robotstxtr"
    ctx$fns <- list(
      evaluate = getExportedValue(ns, "robots_evaluate_text_v1"),
      validate = getExportedValue(ns, "robots_validate_text"),
      contract = getExportedValue(ns, "robots_engine_contract_v1"),
      resolve = getExportedValue(ns, "robots_resolve_matcher_profile_v1")
    )
    contract <- ctx$fns$contract()
    record$contract <- contract[c(
      "contract_id", "schema_revision", "policy_revisions",
      "matcher_revisions", "matcher_availability"
    )]
    record$package$version <- as.character(utils::packageVersion(ns))
  }
  if (opts$mode %in% c("evaluate", "size")) {
    combos <- evaluation_combos(contract, ctx$fns$resolve)
    ctx$combos <- combos$combos
    if (opts$mode == "size") {
      ctx$combos <- size_combos(combos$combos)
      combos$size_combos <- ctx$combos
    }
    ctx$random <- random_paths(opts$random_paths, opts$seed)
    saveRDS(combos, file.path(run_dir, "combos.rds"))
    record$params$combos <- nrow(ctx$combos)
    record$params$random_paths_sha256 <- tools::sha256sum(
      bytes = charToRaw(paste(ctx$random, collapse = "\n"))
    )
    record$params$fixed_paths_sha256 <- tools::sha256sum(
      bytes = charToRaw(enc2utf8(paste(fixed_paths(), collapse = "\n")))
    )
    record$params$tokens <- harness_tokens()
    record$params$size_targets <- size_targets()
  }

  if (opts$mode == "compare") {
    ctx$compare <- prepared
    res <- mode_compare(ctx)
    record$compare <- res
  } else {
    ctx$hosts <- hosts
    ctx$chunks <- chunks
    saveRDS(start, file.path(run_dir, "manifest.rds"), compress = "xz")
    record$manifest <- list(start_hash = manifest_hash(start))
    write_record(run_dir, record)
    runner <- switch(
      opts$mode,
      manifest = mode_manifest, validate = mode_validate,
      evaluate = mode_evaluate, size = mode_size
    )
    record <- run_and_check(record, ctx, runner, start)
    if (!is.null(frozen)) {
      # On the host directories both runs cover, when either is partial.
      match <- same_input_set(
        start, frozen$manifest, is_partial_run(opts),
        !is.null(frozen$params) && is_partial_run(frozen$params)
      )
      record$manifest$frozen_run <- opts$manifest
      record$manifest$matches_frozen <- match$same
      record$manifest$frozen_rows_compared <- match$rows
    }
  }

  record$versions <- loaded_versions()
  record$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  record$wall_seconds <- proc.time()[["elapsed"]] - t0
  worker_gc <- if (is.null(record$chunks)) NA else {
    max(record$chunks$gc_peak_mb)
  }
  worker_rss <- if (is.null(record$chunks)) NA else {
    max(record$chunks$rss_mb, na.rm = TRUE)
  }
  record$memory <- list(
    main_gc_peak_mb = gc_peak_mb(),
    main_rss_mb = rss_mb(),
    worker_gc_peak_mb = worker_gc,
    worker_rss_end_of_chunk_max_mb = worker_rss
  )
  invalid <- opts$mode != "compare" && !isTRUE(record$manifest$valid)
  record$status <- if (invalid) "invalid" else "finished"
  write_record(run_dir, record)

  message(sprintf("%s %s in %.0f s", opts$run_id, record$status,
                  record$wall_seconds))
  if (opts$mode == "compare") {
    # Only the differing-row counts; row totals and detail stay in the run.
    shown <- c("table", "shards_compared", "shards_only_a", "shards_only_b",
               "rows_differing")
    print(record$compare$summary[, shown], row.names = FALSE)
    if (record$compare$unmatched_shards) {
      message("A full run lacks shards the other run holds.")
    }
    if (!record$compare$harness_same) {
      message(
        "NOTE: the two runs came from different, dirty or unknown ",
        "harness trees."
      )
    }
    message(if (record$compare$identical) "IDENTICAL" else "DIFFERENT")
  } else if (invalid) {
    message("INVALID RUN: ", record$invalid_cause, ".")
  } else if (!is.null(record$manifest$matches_frozen) &&
               !record$manifest$matches_frozen) {
    message("WARNING: the corpus no longer matches the frozen manifest.")
  }
  invisible(record)
}

if (sys.nframe() == 0L) {
  status <- tryCatch({
    rec <- harness_main(commandArgs(TRUE))
    if (identical(rec$status, "invalid")) 3L else 0L
  }, corpus_harness_refusal = function(e) {
    message("refused: ", conditionMessage(e))
    2L
  })
  quit(status = status)
}
