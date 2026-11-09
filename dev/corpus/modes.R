# Mode runners for the corpus harness (ROBO-qbxsydcf). Sourced by run.R after
# harness.R. Each mode walks the host directories in chunks, one shard of each
# table per chunk, so no run holds more than one chunk of results at a time.

# ---------------------------------------------------------------------------
# Chunk driver

plan_chunks <- function(hosts, opts) {
  ids <- seq_along(hosts)
  if (!is.na(opts$max_hosts)) {
    ids <- utils::head(ids, opts$max_hosts)
  }
  chunk_of <- (ids - 1L) %/% opts$chunk_size + 1L
  chunks <- split(ids, chunk_of)
  index <- as.integer(names(chunks))
  if (!is.na(opts$subset)) {
    kn <- as.integer(strsplit(opts$subset, "/", fixed = TRUE)[[1L]])
    keep <- (index %% kn[[2L]]) == kn[[1L]]
    chunks <- chunks[keep]
    index <- index[keep]
  }
  if (!length(chunks)) {
    harness_refuse(paste0(
      "The plan holds no chunks: the corpus has no host directories, or ",
      "--subset selects none."
    ))
  }
  Map(function(i, ids) list(chunk = i, ids = ids), index, chunks)
}

# The chunk plan as a frame: one row per planned host directory, with its
# file id (its position in the whole listing) and its chunk.
plan_frame <- function(hosts, chunks) {
  ids <- unlist(lapply(chunks, `[[`, "ids"))
  chunk <- unlist(lapply(chunks, function(ch) rep(ch$chunk, length(ch$ids))))
  data.frame(
    file_id = as.integer(ids), host = hosts[ids], chunk = as.integer(chunk),
    stringsAsFactors = FALSE
  )
}

# The manifest at the end of a run. A full run lists the corpus again, so a
# host directory or robots.rds that appeared during the run shows up as a
# change; a partial run re-hashes the directories it planned.
end_manifest <- function(corpus, plan, partial) {
  if (partial) {
    return(corpus_manifest(corpus, plan))
  }
  corpus_manifest(corpus, list_host_dirs(corpus))
}

is_partial_run <- function(params) {
  !is.na(params$subset) || !is.na(params$max_hosts)
}

# Why each chunk that delivered no result failed, one row per failed chunk.
# parallel::mclapply() returns NULL for a worker that died (killed, out of
# memory) and a try-error for one that raised an error.
chunk_failures <- function(chunks, results) {
  causes <- vapply(seq_along(chunks), function(i) {
    r <- if (i <= length(results)) results[[i]] else NULL
    if (is.null(r)) {
      "its worker died without a result (killed, or out of memory)"
    } else if (inherits(r, "try-error")) {
      paste0("its worker failed: ", trimws(as.character(r)))
    } else if (is.list(r)) {
      NA_character_
    } else {
      paste0("its worker returned a ", class(r)[[1L]], ", not a list")
    }
  }, character(1))
  bad <- !is.na(causes)
  data.frame(
    chunk = vapply(chunks[bad], function(ch) as.integer(ch$chunk), integer(1)),
    cause = causes[bad],
    stringsAsFactors = FALSE
  )
}

worker_failure <- function(failures) {
  msg <- paste0(
    nrow(failures), " chunk(s) delivered no result; chunk ",
    failures$chunk[[1L]], ": ", failures$cause[[1L]]
  )
  structure(
    class = c("corpus_harness_worker_failure", "error", "condition"),
    list(message = msg, call = NULL, failures = failures)
  )
}

# Run `work(chunk)` over the chunks on at most two forked workers. Each call
# returns a small list; the shards are written by the worker itself. A chunk
# without a result signals a corpus_harness_worker_failure naming it.
run_chunks <- function(chunks, work, workers) {
  task <- function(ch) {
    gc(reset = TRUE)
    t0 <- proc.time()[["elapsed"]]
    out <- work(ch)
    out$chunk <- ch$chunk
    out$seconds <- proc.time()[["elapsed"]] - t0
    out$gc_peak_mb <- gc_peak_mb()
    out$rss_mb <- rss_mb()
    out
  }
  results <- if (workers > 1L) {
    parallel::mclapply(
      chunks, task, mc.cores = workers, mc.preschedule = FALSE
    )
  } else {
    lapply(chunks, function(ch) try(task(ch), silent = TRUE))
  }
  failures <- chunk_failures(chunks, results)
  if (nrow(failures)) {
    stop(worker_failure(failures))
  }
  results
}

# Run the mode's chunks, then the input checks; return the record with the
# chunk statistics and the manifest checks, or with the failed chunks. A run
# whose worker failed is invalid for that cause alone: its missing files
# shards say nothing about the corpus.
run_and_check <- function(record, ctx, runner, start) {
  stats <- tryCatch(
    runner(ctx), corpus_harness_worker_failure = function(e) e
  )
  if (inherits(stats, "corpus_harness_worker_failure")) {
    record$worker_failures <- stats$failures
    record$invalid_cause <- conditionMessage(stats)
    record$manifest$valid <- FALSE
    return(record)
  }
  record$chunks <- bind_frames(lapply(stats, as.data.frame))
  during <- read_manifest(ctx$run_dir)
  end <- end_manifest(ctx$corpus, start, is_partial_run(ctx$opts))
  check <- verify_run_inputs(start, during$manifest, end)
  if (!check$valid) {
    saveRDS(check$changes, file.path(ctx$run_dir, "input-changes.rds"))
    record$invalid_cause <- paste0(
      "input files vanished, appeared or changed during the run ",
      "(start/during/end manifest checks; see input-changes.rds)"
    )
  }
  record$manifest <- c(
    check[setdiff(names(check), "changes")],
    list(n_changes = if (is.null(check$changes)) 0L else {
      nrow(check$changes)
    }),
    during[setdiff(names(during), "manifest")]
  )
  record
}

# Read each host of a chunk; `on_body(file_id, host, row, record)` returns a
# named list of frames to append, for records with a raw body.
walk_chunk <- function(corpus, hosts, ch, on_body = NULL) {
  files <- vector("list", length(ch$ids))
  timing <- vector("list", length(ch$ids))
  extra <- list()
  for (k in seq_along(ch$ids)) {
    id <- ch$ids[[k]]
    host <- hosts[[id]]
    path <- file.path(corpus, host, "robots.rds")
    if (!file.exists(path)) {
      files[[k]] <- skipped_file_row(id, host)
      next
    }
    read <- read_corpus_record(path)
    row <- file_row(id, host, read)
    if (!is.null(on_body) && isTRUE(row$body_present)) {
      t0 <- proc.time()[["elapsed"]]
      got <- tryCatch(
        on_body(id, host, row, read$record),
        error = function(e) e
      )
      timing[[k]] <- data.frame(
        file_id = id, seconds = proc.time()[["elapsed"]] - t0
      )
      if (inherits(got, "error")) {
        row$error <- conditionMessage(got)
      } else {
        for (nm in names(got)) {
          extra[[nm]] <- c(extra[[nm]], list(got[[nm]]))
        }
      }
    }
    files[[k]] <- row
  }
  c(
    list(files = bind_frames(files), timing = bind_frames(timing)),
    lapply(extra, bind_frames)
  )
}

# Tables whose values are measurements, not results: never compared.
nondeterministic_tables <- function() {
  "timing"
}

chunk_summary <- function(tables) {
  f <- tables$files
  list(
    n_dirs = nrow(f),
    n_skipped_no_rds = sum(!f$has_rds),
    n_unreadable = sum(f$has_rds & !f$readable, na.rm = TRUE),
    n_bodies = sum(f$body_present),
    n_errors = sum(!is.na(f$error))
  )
}

write_tables <- function(run_dir, chunk, tables, names) {
  for (nm in names) {
    write_shard(run_dir, nm, chunk, tables[[nm]])
  }
}

# ---------------------------------------------------------------------------
# Modes

mode_manifest <- function(ctx) {
  work <- function(ch) {
    tables <- walk_chunk(ctx$corpus, ctx$hosts, ch)
    write_tables(ctx$run_dir, ch$chunk, tables, "files")
    chunk_summary(tables)
  }
  run_chunks(ctx$chunks, work, ctx$opts$workers)
}

mode_validate <- function(ctx) {
  fns <- ctx$fns
  work <- function(ch) {
    tables <- walk_chunk(ctx$corpus, ctx$hosts, ch, function(id, host, row,
                                                             record) {
      v <- validate_body(record$body, fns)
      list(
        documents = with_ids(v$documents, file_id = id),
        diagnostics = with_ids(v$diagnostics, file_id = id)
      )
    })
    write_tables(
      ctx$run_dir, ch$chunk, tables,
      c("files", "timing", "documents", "diagnostics")
    )
    chunk_summary(tables)
  }
  run_chunks(ctx$chunks, work, ctx$opts$workers)
}

mode_evaluate <- function(ctx) {
  fns <- ctx$fns
  combos <- ctx$combos
  narrow <- size_combos(combos)
  work <- function(ch) {
    tables <- walk_chunk(ctx$corpus, ctx$hosts, ch, function(id, host, row,
                                                             record) {
      # A body over --large-bytes gets the narrow grid and path set: its rows
      # each cost a parse of the whole body.
      large <- length(record$body) > ctx$opts$large_bytes
      paths <- if (large) {
        size_path_set(record$body, ctx$opts$size_rule_paths)
      } else {
        path_set(record$body, ctx$opts$max_rule_paths, ctx$random)
      }
      paths$tier <- if (large) "large" else "full"
      paths$evaluated_bytes <- evaluated_bytes(record$body)
      res <- evaluate_body(
        record$body, paths, if (large) narrow else combos, fns
      )
      list(
        paths = with_ids(paths, file_id = id),
        results = with_ids(res, file_id = id)
      )
    })
    write_tables(
      ctx$run_dir, ch$chunk, tables, c("files", "timing", "paths", "results")
    )
    out <- chunk_summary(tables)
    out$n_result_rows <- if (is.null(tables$results)) 0L else {
      nrow(tables$results)
    }
    out
  }
  run_chunks(ctx$chunks, work, ctx$opts$workers)
}

# Size variants of one body: validated, then evaluated over the paths of the
# whole body under every combination.
size_tables <- function(body, origin, file_id, ctx) {
  paths <- size_path_set(body, ctx$opts$size_rule_paths)
  variants <- size_variants(body)
  out <- list(variants = NULL, paths = NULL, results = NULL,
              documents = NULL, diagnostics = NULL)
  vrows <- list()
  docs <- list()
  diags <- list()
  results <- list()
  for (name in names(variants)) {
    b <- variants[[name]]
    vrows[[name]] <- data.frame(
      origin = origin, file_id = file_id, variant = name,
      bytes = length(b), evaluated_bytes = evaluated_bytes(b),
      body_sha256 = tools::sha256sum(bytes = b),
      stringsAsFactors = FALSE
    )
    v <- validate_body(b, ctx$fns)
    docs[[name]] <- with_ids(
      v$documents, origin = origin, file_id = file_id, variant = name
    )
    diags[[name]] <- with_ids(
      v$diagnostics, origin = origin, file_id = file_id, variant = name
    )
    results[[name]] <- with_ids(
      evaluate_body(b, paths, ctx$combos, ctx$fns),
      origin = origin, file_id = file_id, variant = name
    )
  }
  out$variants <- bind_frames(vrows)
  out$paths <- with_ids(paths, origin = origin, file_id = file_id)
  out$results <- bind_frames(results)
  out$documents <- bind_frames(docs)
  out$diagnostics <- bind_frames(diags)
  out
}

mode_size <- function(ctx) {
  size_names <- c("variants", "paths", "results", "documents", "diagnostics")
  floor_bytes <- min(size_targets())
  # Chunk 0 holds the synthetic bodies, which exist in every run.
  synthetic <- synthetic_size_bodies()
  syn <- lapply(names(synthetic), function(nm) {
    size_tables(synthetic[[nm]], paste0("synthetic:", nm), NA_integer_, ctx)
  })
  syn_tables <- lapply(size_names, function(nm) {
    bind_frames(lapply(syn, `[[`, nm))
  })
  names(syn_tables) <- size_names
  write_tables(ctx$run_dir, 0L, syn_tables, size_names)

  work <- function(ch) {
    tables <- walk_chunk(ctx$corpus, ctx$hosts, ch, function(id, host, row,
                                                             record) {
      if (length(record$body) < floor_bytes) {
        return(list())
      }
      size_tables(record$body, "corpus", id, ctx)
    })
    for (nm in size_names) {
      if (is.null(tables[[nm]])) {
        tables[nm] <- list(NULL)
      }
    }
    write_tables(
      ctx$run_dir, ch$chunk, tables, c("files", "timing", size_names)
    )
    out <- chunk_summary(tables)
    out$n_size_bodies <- if (is.null(tables$variants)) 0L else {
      length(unique(tables$variants$file_id))
    }
    out
  }
  run_chunks(ctx$chunks, work, ctx$opts$workers)
}

# ---------------------------------------------------------------------------
# Manifest of a finished run, from its files shards.

# The manifest as the run read it: the hash of each file taken from the very
# bytes the run processed, collected from the files shards.
read_manifest <- function(run_dir) {
  idx <- shard_index(run_dir)
  idx <- idx[idx$table == "files", , drop = FALSE]
  files <- bind_frames(Map(function(p, chunk) {
    f <- decode_frame(readRDS(p))
    if (!is.null(f)) {
      f$chunk <- rep(chunk, nrow(f))
    }
    f
  }, file.path(run_dir, "shards", idx$file), idx$chunk))
  seen <- files[, c("file_id", "host", "chunk", "has_rds", "rds_sha256",
                    "rds_bytes")]
  seen <- seen[order(seen$host, method = "radix"), , drop = FALSE]
  rownames(seen) <- NULL
  list(
    manifest = seen,
    n_dirs = nrow(files),
    n_files = sum(files$has_rds),
    n_skipped_no_rds = sum(!files$has_rds),
    n_unreadable = sum(files$has_rds & !files$readable, na.rm = TRUE),
    n_bodies = sum(files$body_present),
    n_errors = sum(!is.na(files$error))
  )
}

# ---------------------------------------------------------------------------
# Comparison of two runs

# Rows of `a` and `b` (same shape) that differ in any column, identical()-level
# per cell: NA equals NA, and nothing else equals NA.
differing_rows <- function(a, b) {
  any_diff <- logical(nrow(a))
  cols <- character()
  for (col in names(a)) {
    x <- a[[col]]
    y <- b[[col]]
    same <- (is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & x == y)
    same[is.na(same)] <- FALSE
    if (!all(same)) {
      cols <- c(cols, col)
    }
    any_diff <- any_diff | !same
  }
  list(rows = which(any_diff), cols = cols)
}

compare_shard <- function(a, b, table, chunk, detail_cap) {
  a <- decode_frame(a)
  b <- decode_frame(b)
  na <- if (is.null(a)) 0L else nrow(a)
  nb <- if (is.null(b)) 0L else nrow(b)
  if (identical(a, b)) {
    return(list(rows = max(na, nb), differing = 0L, detail = NULL))
  }
  if (na != nb || !identical(names(a), names(b))) {
    note <- data.frame(
      table = table, chunk = chunk, row = NA_integer_,
      column = "<shape>", a = sprintf("%d rows: %s", na,
                                      paste(names(a), collapse = ",")),
      b = sprintf("%d rows: %s", nb, paste(names(b), collapse = ",")),
      stringsAsFactors = FALSE
    )
    return(list(rows = max(na, nb), differing = max(na, nb), detail = note))
  }
  d <- differing_rows(a, b)
  rows <- utils::head(d$rows, detail_cap)
  detail <- if (length(rows)) {
    bind_frames(lapply(d$cols, function(col) {
      data.frame(
        table = table, chunk = chunk, row = rows, column = col,
        a = as.character(a[[col]][rows]), b = as.character(b[[col]][rows]),
        stringsAsFactors = FALSE
      )
    }))
  }
  if (!length(d$rows)) {
    # Equal cell by cell but not identical(): attributes or types differ.
    detail <- data.frame(
      table = table, chunk = chunk, row = NA_integer_, column = "<attributes>",
      a = paste(class(a), collapse = ","), b = paste(class(b), collapse = ","),
      stringsAsFactors = FALSE
    )
    return(list(rows = na, differing = na, detail = detail))
  }
  list(rows = na, differing = length(d$rows), detail = detail)
}

# Parameters two comparable runs must share.
comparable_params <- function() {
  c("mode", "seed", "chunk_size", "max_rule_paths", "random_paths",
    "size_rule_paths", "large_bytes")
}

# What the evaluate and size modes record about their grid and path sets:
# two runs that differ here give results whose combo ids or path ids mean
# different things.
comparable_facts <- function() {
  c("combos", "random_paths_sha256", "fixed_paths_sha256", "tokens",
    "size_targets")
}

# The evaluation grid of a run (combos.rds), or NULL for a mode without one.
read_combos <- function(run_dir) {
  path <- file.path(run_dir, "combos.rds")
  if (!file.exists(path)) {
    return(NULL)
  }
  x <- readRDS(path)
  list(combos = x$combos, size_combos = x$size_combos)
}

# Refuse two runs that cannot be compared: either one unfinished or invalid,
# a compare run, or a difference in the parameters, the grid or the path
# sets.
check_comparable_runs <- function(ra, rb, dir_a, dir_b) {
  for (r in list(ra, rb)) {
    if (!identical(r$status, "finished")) {
      harness_refuse(paste0("Run ", r$run_id, " is not a valid finished run."))
    }
  }
  if (identical(ra$params$mode, "compare") ||
        identical(rb$params$mode, "compare")) {
    harness_refuse("A compare run holds no results to compare.")
  }
  for (p in comparable_params()) {
    if (!identical(ra$params[[p]], rb$params[[p]])) {
      harness_refuse(paste0("The runs differ in parameter ", p, "."))
    }
  }
  for (p in comparable_facts()) {
    if (!identical(ra$params[[p]], rb$params[[p]])) {
      harness_refuse(paste0(
        "The runs differ in ", p, ": their evaluation grids or path sets ",
        "are not the same."
      ))
    }
  }
  if (!identical(read_combos(dir_a), read_combos(dir_b))) {
    harness_refuse(paste0(
      "The runs differ in their evaluation grid (combos.rds): a combo id ",
      "names different combinations in each."
    ))
  }
  invisible(TRUE)
}

mode_compare <- function(ctx, detail_cap = 1000L) {
  dir_a <- file.path(ctx$out, ctx$opts$a)
  dir_b <- file.path(ctx$out, ctx$opts$b)
  rec_path <- function(d) file.path(d, "record.rds")
  if (!file.exists(rec_path(dir_a)) || !file.exists(rec_path(dir_b))) {
    harness_refuse("Both --a and --b must name finished runs with a record.")
  }
  ra <- readRDS(rec_path(dir_a))
  rb <- readRDS(rec_path(dir_b))
  check_comparable_runs(ra, rb, dir_a, dir_b)
  partial_a <- is_partial_run(ra$params)
  partial_b <- is_partial_run(rb$params)
  # Inputs first: no result is diffed across two different input sets, nor
  # across two chunks that name different host directories.
  manifest_a <- readRDS(file.path(dir_a, "manifest.rds"))
  manifest_b <- readRDS(file.path(dir_b, "manifest.rds"))
  check_input_sets(manifest_a, manifest_b, partial_a, partial_b)
  check_chunk_plans(manifest_a, manifest_b)
  ia <- shard_index(dir_a)
  ib <- shard_index(dir_b)
  key_a <- paste(ia$table, ia$chunk)
  key_b <- paste(ib$table, ib$chunk)
  both <- intersect(key_a, key_b)
  # Two partial runs can share no chunk at all; a verdict over zero shards
  # would read as IDENTICAL without having compared anything.
  if (length(both) == 0L) {
    harness_refuse("The runs share no shard, so there is nothing to compare.")
  }
  summary <- list()
  details <- list()
  tables <- setdiff(unique(c(ia$table, ib$table)), nondeterministic_tables())
  for (table in sort(tables, method = "radix")) {
    keys <- both[startsWith(both, paste0(table, " "))]
    rows <- 0
    differing <- 0
    for (key in keys) {
      fa <- ia$file[match(key, key_a)]
      chunk <- ia$chunk[match(key, key_a)]
      cmp <- compare_shard(
        readRDS(file.path(dir_a, "shards", fa)),
        readRDS(file.path(dir_b, "shards", fa)),
        table, chunk, detail_cap
      )
      rows <- rows + cmp$rows
      differing <- differing + cmp$differing
      if (!is.null(cmp$detail)) {
        details[[length(details) + 1L]] <- cmp$detail
      }
    }
    summary[[table]] <- data.frame(
      table = table,
      shards_compared = length(keys),
      shards_only_a = sum(ia$table == table & !(key_a %in% both)),
      shards_only_b = sum(ib$table == table & !(key_b %in% both)),
      rows_compared = rows,
      rows_differing = differing,
      stringsAsFactors = FALSE
    )
  }
  summary <- bind_frames(summary)
  detail <- bind_frames(details)
  saveRDS(summary, file.path(ctx$run_dir, "compare-summary.rds"))
  saveRDS(detail, file.path(ctx$run_dir, "compare-detail.rds"),
          compress = "xz")
  # A full run holds every shard of the corpus, so a shard the other run has
  # and it lacks is a difference; a partial run is expected to lack some.
  unmatched <- (!partial_b && sum(summary$shards_only_a) > 0) ||
    (!partial_a && sum(summary$shards_only_b) > 0)
  list(
    a = ctx$opts$a, b = ctx$opts$b,
    manifest_a = ra$manifest$start_hash,
    manifest_b = rb$manifest$start_hash,
    # Recorded, not checked: the trees that produced each run.
    harness_a = ra$harness, harness_b = rb$harness,
    package_a = ra$package, package_b = rb$package,
    harness_same = identical(
      ra$harness$harness_tree, rb$harness$harness_tree
    ),
    unmatched_shards = unmatched,
    identical = sum(summary$rows_differing) == 0 && !unmatched,
    summary = summary
  )
}
