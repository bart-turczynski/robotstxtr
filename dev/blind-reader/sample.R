# Blind-reader sampler (ROBO-nvgtqdlu): a seeded sample of robots.txt bodies
# from a private corpus, half that robots_validate_text() calls clean and
# half spread over the validator's diagnostic codes and the engines'
# disagreement classes, plus synthetic anchors from the edge-case catalog.
# Usage: dev/blind-reader/README.md. It names no corpus, host or figure; its
# whole output goes under --out, which must lie outside every git work tree.

br_self <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
source(file.path(dirname(normalizePath(sub("^--file=", "", br_self))),
                 "common.R"))

# ---------------------------------------------------------------------------
# Exclusions: hosts an earlier private run already sampled.

# Hosts named in one exclusion source: a directory (every path component and
# file stem under it), an .rds (a `host` column or a character vector), or a
# text file (the fourth field of `--- ` header lines, else one host a line).
exclusion_names <- function(path) {
  if (!file.exists(path)) {
    br_refuse("--exclude does not exist: ", path)
  }
  if (dir.exists(path)) {
    parts <- unlist(strsplit(list.files(path, recursive = TRUE), "/",
                             fixed = TRUE))
    stems <- c(sub("\\.[^.]*$", "", parts), sub("_.*$", "", parts))
    return(unique(c(parts, stems)))
  }
  if (grepl("\\.rds$", path, ignore.case = TRUE)) {
    x <- readRDS(path)
    if (is.data.frame(x) && "host" %in% names(x)) {
      return(unique(as.character(x$host)))
    }
    if (is.character(x)) {
      return(unique(x))
    }
    br_refuse("--exclude .rds has no host column: ", path)
  }
  lines <- readLines(path, warn = FALSE)
  head <- grep("^--- ", lines, value = TRUE)
  if (length(head)) {
    return(unique(vapply(strsplit(head, "[[:space:]]+"), function(f) {
      if (length(f) >= 4L) f[[4L]] else NA_character_
    }, character(1))))
  }
  unique(trimws(lines[nzchar(trimws(lines))]))
}

# ---------------------------------------------------------------------------
# The pool: a seeded draw of host directories, each body read once.

pool_reason <- function(read, max_bytes) {
  rec <- read$record
  if (is.null(rec)) {
    return("unreadable")
  }
  status <- suppressWarnings(as.integer(rec$http_status[1L]))
  if (!length(status) || is.na(status) || status != 200L) {
    return("not_status_200")
  }
  body <- rec$body
  if (is.null(body)) {
    return("no_body")
  }
  if (!length(body)) {
    return("empty_body")
  }
  if (length(body) > max_bytes) {
    return("over_max_bytes")
  }
  "kept"
}

read_pool <- function(h, corpus, hosts, max_bytes) {
  rows <- lapply(hosts, function(host) {
    read <- h$read_corpus_record(file.path(corpus, host, "robots.rds"))
    reason <- pool_reason(read, max_bytes)
    body <- if (reason == "kept") read$record$body else NULL
    list(host = host, reason = reason, body = body,
         truncated = isTRUE(read$record$body_truncated))
  })
  sha <- vapply(rows, function(r) {
    if (is.null(r$body)) NA_character_ else tools::sha256sum(bytes = r$body)
  }, character(1))
  reason <- vapply(rows, `[[`, character(1), "reason")
  reason[reason == "kept" & duplicated(sha)] <- "duplicate_body"
  list(
    table = data.frame(
      host = hosts, reason = reason, body_sha256 = sha,
      body_truncated = vapply(rows, `[[`, logical(1), "truncated"),
      stringsAsFactors = FALSE
    ),
    bodies = lapply(rows, `[[`, "body")
  )
}

# ---------------------------------------------------------------------------
# Current readings of each pool body: validator codes and engine
# disagreements, both from the package tree under test.

validator_codes <- function(fns, body) {
  d <- fns$validate(body)$diagnostics
  sort(unique(d$code))
}

# Engine pairs that share a token: the Google backend against each bounded
# backend, on the bounded backend's own token.
engine_pairs <- function() {
  data.frame(pair = c("bing", "yandex"), token = c("bingbot", "Yandex"),
             stringsAsFactors = FALSE)
}

# Disagreement classes of one body: `<pair>:<google reason>><other reason>`
# for every probe path where the two backends decide differently.
disagreement_classes <- function(h, fns, body, max_rule_paths) {
  paths <- unique(c(h$rule_paths(body, max_rule_paths), h$fixed_paths()))
  urls <- paste0(br_probe_origin(), paths)
  txt <- br_eval_text(body)
  out <- character()
  for (i in seq_len(nrow(engine_pairs()))) {
    p <- engine_pairs()[i, ]
    g <- fns$evaluate(txt, urls, p$token, "google", "google")$results
    o <- fns$evaluate(txt, urls, p$token, p$pair, p$pair)$results
    differ <- !is.na(g$url_decision) & !is.na(o$url_decision) &
      g$url_decision != o$url_decision
    out <- c(out, sprintf("%s:%s>%s", p$pair, g$reason[differ],
                          o$reason[differ]))
  }
  sort(unique(out))
}

# paste0() that keeps an empty vector empty.
prefixed <- function(prefix, x) {
  if (length(x)) paste0(prefix, x) else character()
}

read_pool_strata <- function(h, fns, bodies, max_rule_paths) {
  lapply(bodies, function(body) {
    codes <- validator_codes(fns, body)
    classes <- disagreement_classes(h, fns, body, max_rule_paths)
    list(clean = !length(codes),
         strata = c(prefixed("diag:", codes), prefixed("disagree:", classes)))
  })
}

# ---------------------------------------------------------------------------
# The draw: half clean, half round-robin over the strata in name order, one
# random not-yet-drawn member of each stratum per round.

draw_stratified <- function(strata, eligible, n) {
  names_all <- sort(unique(unlist(strata[eligible])), method = "radix")
  drawn <- integer()
  via <- character()
  repeat {
    added <- FALSE
    for (s in names_all) {
      if (length(drawn) >= n) break
      members <- eligible[vapply(strata[eligible], function(x) s %in% x,
                                 logical(1))]
      members <- setdiff(members, drawn)
      if (!length(members)) next
      drawn <- c(drawn, br_pick(members, 1L))
      via <- c(via, s)
      added <- TRUE
    }
    if (!added || length(drawn) >= n) break
  }
  list(index = drawn, stratum = via)
}

draw_sample <- function(kept, strata, n) {
  clean <- kept[vapply(strata[kept], `[[`, logical(1), "clean")]
  n_clean <- n %/% 2L
  pick_clean <- br_pick(clean, n_clean)
  has_stratum <- kept[lengths(lapply(strata[kept], `[[`, "strata")) > 0L]
  rest <- setdiff(has_stratum, pick_clean)
  s <- draw_stratified(lapply(strata, `[[`, "strata"), rest, n - n_clean)
  data.frame(
    index = c(pick_clean, s$index),
    kind = c(rep("clean", length(pick_clean)), rep("stratified",
                                                   length(s$index))),
    stratum = c(rep("clean", length(pick_clean)), s$stratum),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Token and path per file, from the file's own lines.

# Product tokens named on user-agent lines: the leading run of letters, `_`
# and `-` of each value (RFC 9309 section 2.2.1), case kept, the first
# spelling of each kept.
named_tokens <- function(body) {
  lines <- vapply(br_split_lines(body[body != as.raw(0L)]), function(l) {
    x <- rawToChar(l)
    Encoding(x) <- "bytes"
    x
  }, character(1))
  pat <- paste0("^[ \t]*[Uu][Ss][Ee][Rr]-[Aa][Gg][Ee][Nn][Tt]",
                "[ \t]*:[ \t]*([A-Za-z_-]+)")
  hit <- grepl(pat, lines, perl = TRUE, useBytes = TRUE)
  tokens <- sub(paste0(pat, ".*$"), "\\1", lines[hit], perl = TRUE,
                useBytes = TRUE)
  folded <- chartr(paste(LETTERS, collapse = ""),
                   paste(letters, collapse = ""), tokens)
  tokens[!duplicated(folded)]
}

choose_token <- function(body) {
  tokens <- named_tokens(body)
  if (!length(tokens)) {
    tokens <- c("Googlebot", "bingbot", "Yandex")
  }
  br_pick(tokens, 1L)
}

# A probe path from a rule that exercises matching (`*`, `$` or `%`) when the
# file has one, else from any rule; the rule's literal path or that path with
# one more character, which an end-anchored rule no longer matches.
choose_path <- function(h, body) {
  values <- Filter(length, h$rule_values(body))
  if (!length(values)) {
    return("/")
  }
  special <- vapply(values, function(v) {
    any(v %in% charToRaw("*$%"))
  }, logical(1))
  if (any(special)) values <- values[special]
  path <- probe_base(h, values[[br_pick(seq_along(values), 1L)]])
  if (br_pick(c(TRUE, FALSE), 1L)) paste0(path, "x") else path
}

# The literal path a rule value names, as the corpus harness derives it:
# wildcards and a trailing `$` dropped, unsafe bytes escaped, `/` first.
probe_base <- function(h, value) {
  value <- value[value != charToRaw("*")]
  if (length(value) && value[[length(value)]] == charToRaw("$")) {
    value <- value[-length(value)]
  }
  path <- h$encode_path_bytes(value)
  if (startsWith(path, "/")) path else paste0("/", path)
}

# ---------------------------------------------------------------------------
# Anchors: synthetic catalog rows where RFC 9309 and Google differ (all of
# them) and rows the RFC leaves unspecified (a seeded few).

anchor_rows <- function(pkg, n_silent) {
  dir <- file.path(pkg, "tests", "testthat", "fixtures", "edge-cases")
  m <- utils::read.csv(file.path(dir, "manifest.csv"), colClasses = "character",
                       na.strings = character(), encoding = "UTF-8")
  m$row <- seq_len(nrow(m))
  differ <- m[m$rfc9309_decision != "unspecified" &
                m$rfc9309_decision != m$google_decision, ]
  silent <- m[m$rfc9309_decision == "unspecified", ]
  silent <- silent[sort(br_pick(seq_len(nrow(silent)), n_silent)), ]
  a <- rbind(differ, silent)
  a$anchor <- c(rep("rfc_differs", nrow(differ)),
                rep("rfc_silent", nrow(silent)))
  a$bytes <- lapply(a$body_file, function(f) br_fixture_body(dir, f))
  a
}

# ---------------------------------------------------------------------------
# Output

sample_frame <- function(h, pool, drawn, n_stage1) {
  bodies <- pool$bodies[drawn$index]
  tokens <- vapply(bodies, choose_token, character(1))
  paths <- vapply(bodies, function(b) choose_path(h, b), character(1))
  order_ids <- br_pick(seq_len(nrow(drawn)), nrow(drawn))
  ids <- character(nrow(drawn))
  ids[order_ids] <- sprintf("br-%03d", seq_len(nrow(drawn)))
  t <- pool$table[drawn$index, ]
  df <- data.frame(
    sample_id = ids, stage = ifelse(match(ids, sort(ids)) <= n_stage1,
                                    "stage1", "stage2"),
    kind = drawn$kind, stratum = drawn$stratum, anchor = "",
    host = t$host, body_sha256 = t$body_sha256,
    bytes = lengths(bodies),
    nul_bytes = vapply(bodies, function(b) sum(b == as.raw(0L)), integer(1)),
    body_truncated = t$body_truncated, token = tokens, path = paths,
    google_decision = "", rfc9309_decision = "", fixture = "",
    stringsAsFactors = FALSE
  )
  list(frame = df, bytes = bodies)
}

anchor_frame <- function(a) {
  if (!nrow(a)) {
    return(NULL)
  }
  data.frame(
    sample_id = sprintf("an-%02d", seq_len(nrow(a))), stage = "stage1",
    kind = "anchor", stratum = a$family, anchor = a$anchor, host = "",
    body_sha256 = vapply(a$bytes, function(b) tools::sha256sum(bytes = b),
                         character(1)),
    bytes = lengths(a$bytes),
    nul_bytes = vapply(a$bytes, function(b) sum(b == as.raw(0L)), integer(1)),
    body_truncated = FALSE, token = a$token, path = a$path,
    google_decision = a$google_decision,
    rfc9309_decision = a$rfc9309_decision,
    fixture = sprintf("%s#%d", a$id, a$row),
    stringsAsFactors = FALSE
  )
}

# The columns that make up the sample list; a rerun from the same seed must
# reproduce them exactly.
sample_key <- function(df) {
  df[, c("sample_id", "stage", "kind", "stratum", "anchor", "host",
         "body_sha256", "token", "path", "fixture")]
}

write_outputs <- function(out, df, bytes, pool, record) {
  dir.create(file.path(out, "files"), recursive = TRUE, mode = "0700")
  for (i in seq_len(nrow(df))) {
    writeBin(bytes[[i]],
             file.path(out, "files", paste0(df$sample_id[[i]], ".bin")))
  }
  df <- df[order(df$sample_id), ]
  rownames(df) <- NULL
  br_write_tsv(df, file.path(out, "manifest.tsv"))
  saveRDS(df, file.path(out, "sample.rds"))
  saveRDS(pool, file.path(out, "pool.rds"))
  saveRDS(record, file.path(out, "record.rds"))
  invisible(df)
}

verify_against <- function(df, previous) {
  prev <- readRDS(file.path(previous, "sample.rds"))
  same <- identical(sample_key(df), sample_key(prev))
  cat(if (same) "SAME" else "DIFFERENT", "sample list as", previous, "\n")
  if (!same) quit(save = "no", status = 1L)
}

# ---------------------------------------------------------------------------
# Main

main <- function(args) {
  opts <- br_parse_args(
    args,
    known = c("corpus", "out", "seed", "n", "pool", "exclude", "max-bytes",
              "anchors-silent", "stage1", "max-rule-paths", "pkg", "verify"),
    multi = "exclude"
  )
  corpus <- opts$corpus
  if (is.null(corpus) || !dir.exists(corpus)) {
    br_refuse("--corpus must name an existing directory")
  }
  out <- if (is.null(opts$out)) "" else opts$out
  seed <- br_int_arg(opts, "seed")
  n <- br_int_arg(opts, "n", 100L, min = 2L)
  pool_n <- br_int_arg(opts, "pool", 2000L, min = 1L)
  max_bytes <- br_int_arg(opts, "max-bytes", 32768L, min = 1L)
  n_silent <- br_int_arg(opts, "anchors-silent", 3L)
  n_stage1 <- br_int_arg(opts, "stage1", 20L)
  max_rule_paths <- br_int_arg(opts, "max-rule-paths", 20L, min = 1L)
  h <- br_harness()
  br_check_out(h, out, corpus)
  if (!is.null(opts$verify) &&
      !file.exists(file.path(opts$verify, "sample.rds"))) {
    br_refuse("--verify names no earlier sample: ", opts$verify)
  }
  fns <- br_load_pkg(opts$pkg)
  started <- Sys.time()

  hosts <- h$list_host_dirs(corpus)
  excluded <- unique(unlist(lapply(opts$exclude, exclusion_names)))
  excluded <- intersect(hosts, excluded)
  hosts <- setdiff(hosts, excluded)
  hosts <- hosts[file.exists(file.path(corpus, hosts, "robots.rds"))]

  br_with_seed(seed, {
    pool_hosts <- sort(br_pick(hosts, pool_n), method = "radix")
    pool <- read_pool(h, corpus, pool_hosts, max_bytes)
    kept <- which(pool$table$reason == "kept")
    strata <- vector("list", nrow(pool$table))
    strata[kept] <- read_pool_strata(h, fns, pool$bodies[kept],
                                     max_rule_paths)
    drawn <- draw_sample(kept, strata, n)
    s <- sample_frame(h, pool, drawn, n_stage1)
    anchors <- anchor_rows(fns$path, n_silent)
  })
  df <- rbind(s$frame, anchor_frame(anchors))
  bytes <- c(s$bytes, anchors$bytes)
  pool$table$clean <- vapply(strata, function(s) isTRUE(s$clean), logical(1))
  pool$table$strata <- vapply(strata, function(s) {
    paste(s$strata, collapse = ";")
  }, character(1))
  record <- list(
    ticket = "ROBO-nvgtqdlu", seed = seed, n = n, pool = pool_n,
    max_bytes = max_bytes, anchors_silent = n_silent, stage1 = n_stage1,
    max_rule_paths = max_rule_paths, corpus = normalizePath(corpus),
    exclude = opts$exclude, excluded_hosts = length(excluded),
    pool_reasons = table(pool$table$reason),
    drawn = table(drawn$kind), shortfall = n - nrow(drawn),
    package = h$package_git_facts(fns$path),
    r_version = R.version.string, started = format(started, tz = "UTC"),
    seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))
  )
  pool$bodies <- NULL
  df <- write_outputs(out, df, bytes, pool$table, record)
  cat("wrote", nrow(df), "samples to", out, "\n")
  if (record$shortfall > 0L) {
    cat("NOTE: drew", record$shortfall, "fewer than --n\n")
  }
  if (!is.null(opts$verify)) verify_against(df, opts$verify)
}

main(commandArgs(trailingOnly = TRUE))
