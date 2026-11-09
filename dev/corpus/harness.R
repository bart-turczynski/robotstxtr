# Corpus harness: one repeatable scan of a private corpus of robots.txt
# records against a robotstxtr source tree (ROBO-qbxsydcf).
#
# This file only defines functions; dev/corpus/run.R is the entry point and
# dev/corpus/README.md the usage. It is sourceable on its own, without the
# package loaded, so tests/testthat/test-corpus-harness-qbxsydcf.R can reach
# the path generator and the refusal rules.
#
# Nothing here names a corpus, a host or a figure: the corpus location comes
# from ROBOTSTXTR_CORPUS and every output goes under
# ROBOTSTXTR_CORPUS_OUT/<run-id>/, which must lie outside any git work tree.

# ---------------------------------------------------------------------------
# Refusals

harness_refuse <- function(message) {
  stop(structure(
    class = c("corpus_harness_refusal", "error", "condition"),
    list(message = message, call = NULL)
  ))
}

# The nearest existing ancestor of `path` (itself included), normalized.
existing_ancestor <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  repeat {
    if (file.exists(path)) {
      return(normalizePath(path, winslash = "/", mustWork = TRUE))
    }
    parent <- dirname(path)
    if (identical(parent, path)) {
      return(path)
    }
    path <- parent
  }
}

# The root of the git work tree containing `path`, or NULL. A `.git` entry,
# directory or file (a worktree's gitdir pointer), marks a work tree root,
# which is how git itself finds one.
git_work_tree_root <- function(path) {
  dir <- existing_ancestor(path)
  repeat {
    if (file.exists(file.path(dir, ".git"))) {
      return(dir)
    }
    parent <- dirname(dir)
    if (identical(parent, dir)) {
      return(NULL)
    }
    dir <- parent
  }
}

path_is_within <- function(path, root) {
  path <- existing_ancestor(path)
  root <- existing_ancestor(root)
  identical(path, root) || startsWith(path, paste0(sub("/$", "", root), "/"))
}

# Read and check the two environment variables. `getenv` is injectable for
# tests. `need_corpus = FALSE` serves the compare mode, which reads only
# earlier runs.
corpus_env_config <- function(getenv = Sys.getenv, need_corpus = TRUE) {
  corpus <- getenv("ROBOTSTXTR_CORPUS")
  out <- getenv("ROBOTSTXTR_CORPUS_OUT")
  if (need_corpus && (is.na(corpus) || !nzchar(corpus))) {
    harness_refuse("ROBOTSTXTR_CORPUS is unset: name the corpus directory.")
  }
  if (is.na(out) || !nzchar(out)) {
    harness_refuse(
      "ROBOTSTXTR_CORPUS_OUT is unset: name the private output directory."
    )
  }
  if (need_corpus && !dir.exists(corpus)) {
    harness_refuse("ROBOTSTXTR_CORPUS does not name an existing directory.")
  }
  root <- git_work_tree_root(out)
  if (!is.null(root)) {
    harness_refuse(paste0(
      "ROBOTSTXTR_CORPUS_OUT lies inside a git work tree (", root,
      "): corpus outputs must never be committable."
    ))
  }
  if (need_corpus && !(is.na(corpus) || !nzchar(corpus)) &&
        path_is_within(out, corpus)) {
    harness_refuse(
      "ROBOTSTXTR_CORPUS_OUT lies inside ROBOTSTXTR_CORPUS: the corpus is read-only."
    )
  }
  list(
    corpus = if (need_corpus) existing_ancestor(corpus) else NA_character_,
    out = normalizePath(out, winslash = "/", mustWork = FALSE)
  )
}

validate_run_id <- function(run_id) {
  if (!is.character(run_id) || length(run_id) != 1L || is.na(run_id) ||
        !grepl("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", run_id)) {
    harness_refuse(paste0(
      "A run id is 1-128 characters of letters, digits, '.', '_' and '-', ",
      "starting with a letter or digit."
    ))
  }
  run_id
}

# Create OUT/<run-id>/ and return it; an existing run is never overwritten.
# The leaf is created with recursive = FALSE, so its creation is the
# existence check: of two runs racing for one id, only one gets the
# directory.
create_run_dir <- function(out, run_id) {
  validate_run_id(run_id)
  if (!dir.exists(out)) {
    dir.create(out, recursive = TRUE, mode = "0700")
  }
  if (!dir.exists(out)) {
    harness_refuse(paste0("Cannot create ROBOTSTXTR_CORPUS_OUT: ", out))
  }
  dir <- file.path(out, run_id)
  if (!suppressWarnings(dir.create(dir, recursive = FALSE, mode = "0700"))) {
    harness_refuse(paste0(
      if (file.exists(dir)) "Run directory already exists: " else {
        "Cannot create the run directory: "
      },
      dir
    ))
  }
  # Re-check after creation, through any symlink the parent may carry.
  if (!is.null(git_work_tree_root(dir))) {
    unlink(dir, recursive = TRUE)
    harness_refuse("The run directory resolved into a git work tree.")
  }
  if (!dir.create(file.path(dir, "shards"))) {
    harness_refuse(paste0("Cannot create the shards directory in ", dir))
  }
  normalizePath(dir, winslash = "/", mustWork = TRUE)
}

# The start-manifest hash of the earlier run --manifest names, checked before
# any work: a plain run id (never a path), a run that exists under OUT and
# finished, with a manifest.
frozen_manifest_hash <- function(out, run_id) {
  validate_run_id(run_id)
  path <- file.path(out, run_id, "record.rds")
  if (!file.exists(path)) {
    harness_refuse(paste0(
      "--manifest names no run under ROBOTSTXTR_CORPUS_OUT: ", run_id
    ))
  }
  rec <- tryCatch(readRDS(path), error = function(e) NULL)
  hash <- if (is.list(rec)) rec$manifest$start_hash
  if (!identical(rec$status, "finished") || !is.character(hash) ||
        length(hash) != 1L) {
    harness_refuse(paste0(
      "--manifest must name a finished run with a manifest: ", run_id
    ))
  }
  hash
}

# ---------------------------------------------------------------------------
# Arguments

harness_modes <- function() {
  c("manifest", "validate", "evaluate", "size", "compare")
}

harness_defaults <- function() {
  list(
    pkg = NA_character_,
    seed = 20261109L,
    run_id = NA_character_,
    workers = 1L,
    chunk_size = 100L,
    max_rule_paths = 16L,
    random_paths = 8L,
    size_rule_paths = 4L,
    large_bytes = 65536L,
    subset = NA_character_,
    max_hosts = NA_integer_,
    manifest = NA_character_,
    a = NA_character_,
    b = NA_character_
  )
}

parse_harness_args <- function(args) {
  if (length(args) == 0L || !(args[[1L]] %in% harness_modes())) {
    harness_refuse(paste0(
      "First argument is the mode: ", paste(harness_modes(), collapse = ", ")
    ))
  }
  opts <- harness_defaults()
  opts$mode <- args[[1L]]
  rest <- args[-1L]
  integer_opts <- c(
    "seed", "workers", "chunk_size", "max_rule_paths", "random_paths",
    "size_rule_paths", "large_bytes", "max_hosts"
  )
  while (length(rest)) {
    key <- rest[[1L]]
    if (!startsWith(key, "--") || length(rest) < 2L) {
      harness_refuse(paste0("Expected --option value, got: ", key))
    }
    name <- gsub("-", "_", substring(key, 3L), fixed = TRUE)
    if (!(name %in% names(harness_defaults()))) {
      harness_refuse(paste0("Unknown option: ", key))
    }
    value <- rest[[2L]]
    if (name %in% integer_opts) {
      value <- suppressWarnings(as.integer(value))
      if (is.na(value) || value < 0L) {
        harness_refuse(paste0(key, " takes a non-negative integer."))
      }
    }
    opts[[name]] <- value
    rest <- rest[-(1:2)]
  }
  if (opts$workers < 1L || opts$workers > 2L) {
    harness_refuse("--workers is 1 or 2: peers need the other cores.")
  }
  if (opts$chunk_size < 1L) {
    harness_refuse("--chunk-size is at least 1.")
  }
  if (!is.na(opts$subset)) {
    kn <- suppressWarnings(
      as.integer(strsplit(opts$subset, "/", fixed = TRUE)[[1L]])
    )
    if (!grepl("^[0-9]+/[1-9][0-9]*$", opts$subset) || anyNA(kn) ||
          kn[[1L]] >= kn[[2L]]) {
      harness_refuse(
        "--subset is K/N with K < N: the chunks whose index mod N is K."
      )
    }
  }
  if (!is.na(opts$max_hosts) && opts$max_hosts < 1L) {
    harness_refuse("--max-hosts is at least 1.")
  }
  # Every run id is a plain name under OUT, never a path.
  for (id in c("run_id", "a", "b", "manifest")) {
    if (!is.na(opts[[id]])) {
      validate_run_id(opts[[id]])
    }
  }
  if (opts$mode == "compare") {
    if (is.na(opts$a) || is.na(opts$b)) {
      harness_refuse("compare needs --a <run-id> --b <run-id>.")
    }
    if (!is.na(opts$manifest)) {
      harness_refuse("--manifest belongs to a scan mode, not to compare.")
    }
  } else if (opts$mode != "manifest" && is.na(opts$pkg)) {
    harness_refuse(paste0(opts$mode, " needs --pkg <package source path>."))
  }
  opts
}

# ---------------------------------------------------------------------------
# Path generator. It reads robots.txt bytes with its own line regex, never the
# package's parser, so the path set is the same whichever tree is evaluated.

# Percent-encode the bytes a request target cannot carry raw: controls, space,
# DEL, '#' (it would start a fragment) and every byte >= 0x80, uppercase hex.
encode_path_bytes <- function(bytes) {
  if (!length(bytes)) {
    return("")
  }
  ints <- as.integer(bytes)
  enc <- ints <= 0x20L | ints >= 0x7fL | ints == 0x23L
  out <- character(length(ints))
  if (any(!enc)) {
    out[!enc] <- strsplit(rawToChar(bytes[!enc]), "", fixed = TRUE)[[1L]]
  }
  out[enc] <- sprintf("%%%02X", ints[enc])
  paste(out, collapse = "")
}

# The values of the Allow and Disallow lines of a body, as raw vectors, in
# file order. Keys are matched ASCII-case-insensitively; comments are cut.
rule_values <- function(body) {
  if (!length(body)) {
    return(list())
  }
  body <- body[body != as.raw(0L)]
  txt <- rawToChar(body)
  Encoding(txt) <- "bytes"
  lines <- strsplit(txt, "\r\n|\r|\n", useBytes = TRUE)[[1L]]
  lines <- sub("#.*$", "", lines, useBytes = TRUE)
  pattern <- "^[ \t]*([Aa][Ll][Ll][Oo][Ww]|[Dd][Ii][Ss][Aa][Ll][Ll][Oo][Ww])[ \t]*:[ \t]*(.*?)[ \t]*$"
  hit <- grepl(pattern, lines, perl = TRUE, useBytes = TRUE)
  values <- sub(pattern, "\\2", lines[hit], perl = TRUE, useBytes = TRUE)
  lapply(values, charToRaw)
}

# Two probe paths per rule value: the literal path a pattern names (wildcards
# dropped, a trailing '$' dropped, a leading '/' ensured) and that path with
# one more segment character, which an end-anchored pattern no longer
# matches. Unique, in file order, capped at `cap`.
rule_paths <- function(body, cap) {
  values <- rule_values(body)
  out <- character()
  for (value in values) {
    if (length(out) >= cap) {
      break
    }
    if (!length(value)) {
      next
    }
    value <- value[value != charToRaw("*")]
    if (length(value) && value[[length(value)]] == charToRaw("$")) {
      value <- value[-length(value)]
    }
    path <- encode_path_bytes(value)
    if (!startsWith(path, "/")) {
      path <- paste0("/", path)
    }
    out <- unique(c(out, path, paste0(path, "x")))
  }
  utils::head(out, cap)
}

# A fixed probe list: the matcher's special characters, percent-escapes in
# both cases, letter case, index files, non-ASCII, the empty path and queries.
fixed_paths <- function() {
  c(
    "", "/", "/index.html", "/Index.HTML", "/a", "/A", "/a$", "/$", "/%24",
    "/*", "/a*b", "/%2A", "/%2a", "/%2F", "/%2f", "/a%2Fb", "/%7Euser",
    "/%7euser", "/~user", "/caf%C3%A9", "/caf%c3%a9", "/café",
    "/日本", "/?q=1", "/a?b=c&d=e", "/search?q=%2F"
  )
}

# A seeded random path set that depends on nothing but the seed: 1-4
# segments over letters of both cases, digits, unreserved marks, percent
# escapes in both cases and the two pattern characters, sometimes a query.
random_paths <- function(n, seed) {
  if (n <= 0L) {
    return(character())
  }
  had_seed <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (had_seed) {
    saved <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
  }
  old_kind <- RNGkind()
  on.exit({
    RNGkind(old_kind[[1L]], old_kind[[2L]], old_kind[[3L]])
    if (had_seed) {
      assign(".Random.seed", saved, envir = globalenv())
    } else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      rm(".Random.seed", envir = globalenv())
    }
  })
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(seed)
  atoms <- c(
    letters, LETTERS, as.character(0:9), "-", "_", ".", "~", "*", "$",
    "%2F", "%2f", "%41", "%7e", "%E2%82%AC", "%e2%82%ac"
  )
  vapply(seq_len(n), function(i) {
    segments <- vapply(seq_len(sample.int(4L, 1L)), function(j) {
      paste(sample(atoms, sample.int(6L, 1L), replace = TRUE), collapse = "")
    }, character(1))
    path <- paste0("/", paste(segments, collapse = "/"))
    if (sample.int(4L, 1L) == 1L) {
      path <- paste0(path, "?", paste(sample(atoms, 3L), collapse = ""))
    }
    path
  }, character(1))
}

# The probe set for one body: rule paths, then the fixed list, then the
# random set, de-duplicated with the first source kept.
path_set <- function(body, max_rule_paths, random) {
  rule <- rule_paths(body, max_rule_paths)
  fixed <- fixed_paths()
  path <- c(rule, fixed, random)
  source <- c(
    rep("rule", length(rule)), rep("fixed", length(fixed)),
    rep("random", length(random))
  )
  keep <- !duplicated(path)
  data.frame(
    path_id = seq_len(sum(keep)),
    path = path[keep],
    source = source[keep],
    stringsAsFactors = FALSE
  )
}

probe_origin <- function() {
  "https://example.com"
}

# ---------------------------------------------------------------------------
# Synthetic boundary bodies for size mode. Each is longer than the boundary,
# with one line straddling it, so cuts at the sizes around it fall inside
# that line.

size_targets <- function() {
  c(511999L, 512000L, 512001L)
}

# A body whose byte `offset` (0-based) starts `line`, padded with comment
# lines, followed by a closing rule.
straddle_body <- function(line, offset) {
  head <- "User-agent: *\nAllow: /\n"
  need <- offset - nchar(head, type = "bytes")
  filler <- character()
  while (need > 0L) {
    width <- min(need, 100L)
    if (need - width == 1L) {
      width <- width - 1L
    }
    filler <- c(filler, paste0(strrep("#", width - 1L), "\n"))
    need <- need - width
  }
  body <- paste0(
    head, paste(filler, collapse = ""), line, "\nDisallow: /after-cut/\n"
  )
  charToRaw(body)
}

# Two synthetic bodies: the cut through a rule line leaves "Disallow:",
# "Disallow: " and "Disallow: /" at 511,999, 512,000 and 512,001 bytes; the
# cut through a percent-escape leaves "/a", "/a%" and "/a%2".
synthetic_size_bodies <- function() {
  boundary <- 512000L
  rule_line <- "Disallow: /private-drafts/"
  pct_line <- "Disallow: /a%2Fb/"
  list(
    rule_line = straddle_body(rule_line, boundary - 10L),
    percent_escape = straddle_body(pct_line, boundary - 13L)
  )
}

# The size variants of one body: a cut at each target it is long enough for,
# plus the whole body when it is not itself one of the targets.
size_variants <- function(body) {
  n <- length(body)
  targets <- size_targets()
  targets <- targets[targets <= n]
  out <- lapply(targets, function(t) body[seq_len(t)])
  names(out) <- paste0("cut_", targets)
  if (!(n %in% targets)) {
    out[["full"]] <- body
  }
  out
}

# ---------------------------------------------------------------------------
# Corpus access

list_host_dirs <- function(corpus) {
  dirs <- list.dirs(corpus, full.names = FALSE, recursive = FALSE)
  sort(dirs, method = "radix")
}

# Read one robots.rds: its sha256 and the record, from one read of the file.
# A file that does not decompress or unserialize gives `record = NULL`, which
# the files table records as readable = FALSE; it never stops the run.
read_corpus_record <- function(path) {
  bytes <- readBin(path, "raw", n = file.size(path))
  sha <- tools::sha256sum(bytes = bytes)
  magic <- bytes[seq_len(min(3L, length(bytes)))]
  type <- if (length(magic) >= 2L && magic[[1L]] == as.raw(0x1f) &&
                magic[[2L]] == as.raw(0x8b)) {
    "gzip"
  } else if (length(magic) == 3L && rawToChar(magic) == "BZh") {
    "bzip2"
  } else if (length(magic) >= 2L && magic[[1L]] == as.raw(0xfd)) {
    "xz"
  } else {
    "none"
  }
  record <- tryCatch({
    data <- if (type == "none") bytes else memDecompress(bytes, type)
    unserialize(data)
  }, error = function(e) NULL)
  list(sha256 = sha, bytes = length(bytes), record = record)
}

# The manifest of the planned host directories: one row per directory, with
# `has_rds` and, when it has one, its robots.rds's sha256 and size, sorted by
# host. Every listed directory is in it, those without a robots.rds too:
# file ids and chunk membership come from the whole listing, so two listings
# that differ only in an empty directory are different input sets. `plan` is
# a frame with a `host` column (plan_frame() adds `file_id` and `chunk`), or
# a character vector of host directories.
corpus_manifest <- function(corpus, plan) {
  if (is.character(plan)) {
    plan <- data.frame(host = plan, stringsAsFactors = FALSE)
  }
  plan <- plan[order(plan$host, method = "radix"), , drop = FALSE]
  paths <- file.path(corpus, plan$host, "robots.rds")
  has <- file.exists(paths)
  sha <- rep(NA_character_, length(paths))
  bytes <- rep(NA_integer_, length(paths))
  if (any(has)) {
    sha[has] <- unname(tools::sha256sum(paths[has]))
    bytes[has] <- as.integer(file.size(paths[has]))
  }
  plan$has_rds <- has
  plan$rds_sha256 <- sha
  plan$rds_bytes <- bytes
  rownames(plan) <- NULL
  plan
}

manifest_hash <- function(manifest) {
  manifest <- manifest[order(manifest$host, method = "radix"), , drop = FALSE]
  sha <- ifelse(is.na(manifest$rds_sha256), "-", manifest$rds_sha256)
  lines <- paste0(manifest$host, "/robots.rds\t", sha, "\n")
  tools::sha256sum(bytes = charToRaw(enc2utf8(paste(lines, collapse = ""))))
}

# How `after` differs from `before`: one row per host directory that
# vanished, appeared or changed (its robots.rds bytes, or whether it has
# one). Zero rows when the two name the same snapshot.
manifest_diff <- function(before, after) {
  b <- stats::setNames(before$rds_sha256, before$host)
  a <- stats::setNames(after$rds_sha256, after$host)
  vanished <- setdiff(names(b), names(a))
  appeared <- setdiff(names(a), names(b))
  common <- intersect(names(b), names(a))
  x <- b[common]
  y <- a[common]
  same <- (is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & x == y)
  changed <- common[!same]
  data.frame(
    host = c(vanished, appeared, changed),
    change = c(
      rep("vanished", length(vanished)), rep("appeared", length(appeared)),
      rep("changed", length(changed))
    ),
    stringsAsFactors = FALSE
  )
}

# The two input checks of a run: the manifest taken at the start against the
# hashes of the bytes the run actually processed, and against a fresh
# manifest taken at the end. Any vanished, appeared or changed file (a
# quarantine, a resync) makes the run invalid.
verify_run_inputs <- function(start, during, end) {
  d_during <- manifest_diff(start, during)
  d_end <- manifest_diff(start, end)
  list(
    start_hash = manifest_hash(start),
    during_hash = manifest_hash(during),
    end_hash = manifest_hash(end),
    during_ok = nrow(d_during) == 0L,
    end_ok = nrow(d_end) == 0L,
    valid = nrow(d_during) == 0L && nrow(d_end) == 0L,
    changes = rbind(
      if (nrow(d_during)) cbind(check = "during", d_during),
      if (nrow(d_end)) cbind(check = "end", d_end)
    )
  )
}

# Refuse to compare two runs whose inputs differ. Full runs must name the same
# snapshot; when either run covered only part of the corpus, every file the
# partial run read must appear, byte-identical, in the other run's manifest.
check_input_sets <- function(manifest_a, manifest_b, partial_a, partial_b) {
  if (!partial_a && !partial_b) {
    same <- identical(manifest_hash(manifest_a), manifest_hash(manifest_b)) &&
      !nrow(manifest_diff(manifest_a, manifest_b))
    if (!same) {
      harness_refuse(
        "The two runs read different input sets: their manifests differ."
      )
    }
    return(invisible(TRUE))
  }
  small <- if (partial_b) manifest_b else manifest_a
  big <- if (partial_b) manifest_a else manifest_b
  if (partial_a && partial_b) {
    big <- big[big$host %in% small$host, , drop = FALSE]
    small <- small[small$host %in% big$host, , drop = FALSE]
  }
  d <- manifest_diff(small, big[big$host %in% small$host, , drop = FALSE])
  if (nrow(d) || !nrow(small)) {
    harness_refuse(
      "The two runs read different input sets on the files they share."
    )
  }
  invisible(TRUE)
}

# Refuse to compare two runs whose shared chunks cover different host
# directories or file ids: shards are diffed chunk by chunk, so a chunk must
# name the same hosts in both. This catches a different directory listing
# behind a --subset run, and a --max-hosts run cut mid-chunk compared with a
# run that holds the whole chunk.
check_chunk_plans <- function(manifest_a, manifest_b) {
  need <- c("file_id", "host", "chunk")
  if (!all(need %in% names(manifest_a)) || !all(need %in% names(manifest_b))) {
    harness_refuse("A run's manifest carries no chunk plan: rerun it.")
  }
  members <- function(m) {
    m <- m[order(m$file_id), , drop = FALSE]
    split(paste(m$file_id, m$host, sep = "\t"), m$chunk)
  }
  a <- members(manifest_a)
  b <- members(manifest_b)
  shared <- intersect(names(a), names(b))
  same <- vapply(shared, function(k) identical(a[[k]], b[[k]]), logical(1))
  if (!all(same)) {
    harness_refuse(paste0(
      "The two runs planned chunk ", paste(shared[!same], collapse = ", "),
      " over different host directories (a different listing, or a ",
      "--max-hosts cut mid-chunk)."
    ))
  }
  invisible(TRUE)
}

scalar_or_na <- function(x, na) {
  if (is.null(x) || length(x) != 1L) na else x
}

# One files-table row for a read record. Columns come from the record when
# present, else NA.
file_row <- function(file_id, host, read) {
  r <- read$record
  body <- if (is.list(r)) r$body else NULL
  data.frame(
    file_id = file_id,
    host = host,
    has_rds = TRUE,
    rds_sha256 = read$sha256,
    rds_bytes = read$bytes,
    readable = is.list(r),
    fetch_outcome = as.character(scalar_or_na(r$fetch_outcome, NA)),
    http_status = as.integer(scalar_or_na(r$http_status, NA)),
    content_type = as.character(scalar_or_na(r$content_type, NA)),
    content_flag = as.character(scalar_or_na(r$content_flag, NA)),
    body_truncated = as.logical(scalar_or_na(r$body_truncated, NA)),
    body_present = is.raw(body),
    body_bytes = if (is.raw(body)) length(body) else NA_integer_,
    nul_bytes = if (is.raw(body)) sum(body == as.raw(0L)) else NA_integer_,
    error = NA_character_,
    stringsAsFactors = FALSE
  )
}

skipped_file_row <- function(file_id, host) {
  data.frame(
    file_id = file_id, host = host, has_rds = FALSE,
    rds_sha256 = NA_character_, rds_bytes = NA_integer_, readable = NA,
    fetch_outcome = NA_character_, http_status = NA_integer_,
    content_type = NA_character_, content_flag = NA_character_,
    body_truncated = NA, body_present = FALSE, body_bytes = NA_integer_,
    nul_bytes = NA_integer_, error = NA_character_,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Table helpers

bind_frames <- function(frames) {
  frames <- Filter(function(f) !is.null(f) && nrow(f) > 0L, frames)
  if (!length(frames)) {
    return(NULL)
  }
  cols <- names(frames[[1L]])
  out <- lapply(cols, function(col) {
    unlist(lapply(frames, `[[`, col), use.names = FALSE)
  })
  names(out) <- cols
  as.data.frame(out, stringsAsFactors = FALSE)
}

# Integer-code every character column for storage.
encode_frame <- function(df) {
  if (is.null(df)) {
    return(NULL)
  }
  for (col in names(df)) {
    if (is.character(df[[col]])) {
      df[[col]] <- factor(df[[col]], exclude = NULL)
    }
  }
  df
}

decode_frame <- function(df) {
  if (is.null(df)) {
    return(NULL)
  }
  for (col in names(df)) {
    if (is.factor(df[[col]])) {
      df[[col]] <- as.character(df[[col]])
    }
  }
  df
}

write_shard <- function(run_dir, table, chunk, df) {
  path <- file.path(run_dir, "shards", sprintf("%s-%05d.rds", table, chunk))
  saveRDS(encode_frame(df), path, compress = "xz")
  invisible(path)
}

shard_index <- function(run_dir) {
  files <- list.files(file.path(run_dir, "shards"), pattern = "\\.rds$")
  data.frame(
    file = files,
    table = sub("-[0-9]+\\.rds$", "", files),
    chunk = as.integer(sub("^.*-([0-9]+)\\.rds$", "\\1", files)),
    stringsAsFactors = FALSE
  )
}

raw_hex <- function(x) {
  if (is.null(x)) NA_character_ else paste(as.character(x), collapse = "")
}

# ---------------------------------------------------------------------------
# Package, git and process facts for the run record

git_out <- function(dir, ...) {
  out <- suppressWarnings(system2(
    "git", c("-C", shQuote(dir), ...), stdout = TRUE, stderr = FALSE
  ))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    return(NA_character_)
  }
  paste(out, collapse = "\n")
}

package_git_facts <- function(pkg) {
  top <- git_out(pkg, "rev-parse", "--show-toplevel")
  if (is.na(top)) {
    harness_refuse(paste0("--pkg is not inside a git work tree: ", pkg))
  }
  pkg_norm <- normalizePath(pkg, winslash = "/", mustWork = TRUE)
  top <- normalizePath(top, winslash = "/", mustWork = TRUE)
  prefix <- if (identical(pkg_norm, top)) "" else {
    paste0(substring(pkg_norm, nchar(top) + 2L), "/")
  }
  spec <- function(p) paste0("HEAD:", prefix, p)
  status <- git_out(
    pkg, "status", "--porcelain", "--untracked-files=all", "--", "R", "src",
    "DESCRIPTION"
  )
  status_all <- git_out(pkg, "status", "--porcelain")
  list(
    pkg_path = pkg_norm,
    git_sha = git_out(pkg, "rev-parse", "HEAD"),
    git_branch = git_out(pkg, "rev-parse", "--abbrev-ref", "HEAD"),
    tree_R = git_out(pkg, "rev-parse", spec("R")),
    tree_src = git_out(pkg, "rev-parse", spec("src")),
    blob_DESCRIPTION = git_out(pkg, "rev-parse", spec("DESCRIPTION")),
    dirty_package_code = !is.na(status) && nzchar(status),
    dirty_any = !is.na(status_all) && nzchar(status_all)
  )
}

harness_git_facts <- function(harness_dir) {
  list(
    harness_git_sha = git_out(harness_dir, "rev-parse", "HEAD"),
    harness_tree = git_out(harness_dir, "rev-parse", "HEAD:./"),
    harness_dirty = {
      s <- git_out(harness_dir, "status", "--porcelain", "--", ".")
      !is.na(s) && nzchar(s)
    }
  )
}

loaded_versions <- function() {
  ns <- sort(loadedNamespaces(), method = "radix")
  vapply(ns, function(p) {
    tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA)
  }, character(1))
}

rss_mb <- function() {
  out <- suppressWarnings(system2(
    "ps", c("-o", "rss=", "-p", Sys.getpid()), stdout = TRUE, stderr = FALSE
  ))
  value <- suppressWarnings(as.numeric(trimws(out[1L])))
  if (is.na(value)) NA_real_ else value / 1024
}

# The R heap's peak since the last gc(reset = TRUE): the "(Mb)" column that
# follows "max used" (later R versions add a "limit" column after it).
gc_peak_mb <- function() {
  g <- gc()
  sum(g[, match("max used", colnames(g)) + 1L])
}

# ---------------------------------------------------------------------------
# Evaluate combinations, from the live contract

harness_tokens <- function() {
  c("*", "Googlebot", "Googlebot-Image", "Yandex", "bingbot", "zzcorpusprobe")
}

# Every ruleset x available backend x token the facade will take. Each
# backend is offered the fixed token list plus the tokens the contract
# publishes for it (a bounded backend's profiles), and
# robots_resolve_matcher_profile_v1() decides which it accepts. Unavailable
# backends and unresolvable tokens are listed apart in `pairs`.
evaluation_combos <- function(contract, resolve) {
  rulesets <- contract$robots_policy_rulesets
  backends <- contract$matcher_backends
  pairs <- bind_frames(lapply(backends, function(backend) {
    own <- contract$matcher_capability[[backend]]$supported_profiles
    tokens <- unique(c(harness_tokens(), own$accepted_token))
    data.frame(token = tokens, backend = backend, stringsAsFactors = FALSE)
  }))
  tokens <- unique(pairs$token)
  pairs$availability <- unname(contract$matcher_availability[pairs$backend])
  pairs$resolves <- vapply(seq_len(nrow(pairs)), function(i) {
    ok <- tryCatch({
      resolve(pairs$backend[[i]], pairs$token[[i]])
      TRUE
    }, robotstxtr_unresolvable_matcher_profile = function(e) FALSE)
    ok
  }, logical(1))
  pairs$included <- pairs$availability == "available" & pairs$resolves
  kept <- pairs[pairs$included, c("backend", "token"), drop = FALSE]
  grid <- merge(
    data.frame(ruleset = rulesets, stringsAsFactors = FALSE), kept,
    by = NULL
  )
  grid <- grid[order(
    match(grid$ruleset, rulesets), match(grid$backend, backends),
    match(grid$token, tokens)
  ), , drop = FALSE]
  grid$combo_id <- seq_len(nrow(grid))
  rownames(grid) <- NULL
  list(
    combos = grid[, c("combo_id", "ruleset", "backend", "token")],
    pairs = pairs
  )
}

# The narrow grid: every ruleset x available backend, each backend with the
# first named token of the full grid it accepts, keeping the full grid's
# combo ids. The package parses a body once per result row, so a row of a
# body near the 512,000-byte window costs far more than a small body's; size
# mode and the large tier of evaluate mode use this grid.
size_combos <- function(combos) {
  named <- combos[combos$token != "*", , drop = FALSE]
  first <- named[!duplicated(named$backend), c("backend", "token")]
  keep <- paste(combos$backend, combos$token) %in%
    paste(first$backend, first$token)
  out <- combos[keep, , drop = FALSE]
  rownames(out) <- NULL
  out
}

# The fixed probes of the narrow path set: the paths the synthetic boundary
# lines name, and a few of the fixed list.
size_probe_paths <- function() {
  c(
    "/", "", "/a", "/private-drafts/", "/after-cut/", "/a%2Fb/", "/a%2fb/",
    "/index.html"
  )
}

size_path_set <- function(body, max_rule_paths) {
  rule <- rule_paths(body, max_rule_paths)
  fixed <- size_probe_paths()
  path <- c(rule, fixed)
  source <- c(rep("rule", length(rule)), rep("fixed", length(fixed)))
  keep <- !duplicated(path)
  data.frame(
    path_id = seq_len(sum(keep)), path = path[keep], source = source[keep],
    stringsAsFactors = FALSE
  )
}

# The columns of a v1 result stored per row; the rest are recoverable from
# the path and combo ids and are checked instead.
compact_results <- function(res, paths, combos, n_paths) {
  r <- res$results
  combo_idx <- rep(seq_len(nrow(combos)), each = n_paths)
  path_idx <- rep(seq_len(n_paths), times = nrow(combos))
  stopifnot(
    identical(r$robots_product_token, combos$token[combo_idx]),
    identical(r$robots_policy_ruleset, combos$ruleset[combo_idx]),
    identical(r$matcher_backend, combos$backend[combo_idx]),
    identical(r$url, paste0(probe_origin(), paths$path[path_idx]))
  )
  raw_col <- vapply(r$matched_rule_value_raw, raw_hex, character(1))
  drop <- c(
    "input_id", "url", "robots_product_token", "robots_policy_ruleset",
    "matcher_backend", "matched_rule_value_raw"
  )
  out <- r[, setdiff(names(r), drop), drop = FALSE]
  out$matched_rule_value_raw_hex <- raw_col
  cbind(
    data.frame(
      path_id = paths$path_id[path_idx], combo_id = combos$combo_id[combo_idx]
    ),
    out
  )
}

# Evaluate one body over its path set and every combination.
evaluate_body <- function(body, paths, combos, fns) {
  txt <- rawToChar(body[body != as.raw(0L)])
  Encoding(txt) <- "bytes"
  n_paths <- nrow(paths)
  urls <- paste0(probe_origin(), paths$path)
  res <- fns$evaluate(
    txt,
    rep(urls, times = nrow(combos)),
    rep(combos$token, each = n_paths),
    rep(combos$ruleset, each = n_paths),
    rep(combos$backend, each = n_paths)
  )
  compact_results(res, paths, combos, n_paths)
}

validate_body <- function(body, fns) {
  v <- fns$validate(body)
  docs <- v$documents
  docs <- docs[, setdiff(names(docs), c("source_id", "source_type")),
               drop = FALSE]
  diags <- v$diagnostics
  diags <- diags[, setdiff(names(diags), c("source_id", "input_id")),
                 drop = FALSE]
  list(documents = docs, diagnostics = diags)
}

with_ids <- function(df, ...) {
  if (is.null(df) || !nrow(df)) {
    return(NULL)
  }
  ids <- list(...)
  cbind(
    as.data.frame(lapply(ids, rep, length.out = nrow(df))),
    df
  )
}
