# Shared helpers for the blind-reader pilot (ROBO-nvgtqdlu): argument
# parsing, refusals, package loading, seeded draws and the line rendering
# the reader sees. Sourced by sample.R, render.R and score.R; it names no
# corpus, host or figure.
#
# It reuses the corpus harness (dev/corpus/harness.R, ROBO-qbxsydcf) for the
# git-tree refusal, the robots.rds reader, the rule-path generator and the
# package's git facts, so both tools refuse and read the same way.

br_dir <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (!length(file_arg)) {
    return(normalizePath("dev/blind-reader", mustWork = FALSE))
  }
  dirname(normalizePath(sub("^--file=", "", file_arg[[1L]])))
}

br_harness <- function() {
  env <- new.env(parent = globalenv())
  sys.source(file.path(dirname(br_dir()), "corpus", "harness.R"), envir = env)
  env
}

# ---------------------------------------------------------------------------
# Refusals: a message on stderr and exit status 2, before any output exists.

br_refuse <- function(...) {
  message("refused: ", ...)
  quit(save = "no", status = 2L)
}

# The output directory must lie outside every git work tree (so nothing a run
# writes can be committed) and outside the corpus, and must not exist yet.
br_check_out <- function(h, out, corpus = NULL) {
  if (!nzchar(out)) {
    br_refuse("--out is required")
  }
  root <- h$git_work_tree_root(out)
  if (!is.null(root)) {
    br_refuse("--out lies inside the git work tree ", root)
  }
  if (!is.null(corpus) && h$path_is_within(out, corpus)) {
    br_refuse("--out lies inside the corpus")
  }
  if (file.exists(out)) {
    br_refuse("--out already exists: ", out)
  }
}

# ---------------------------------------------------------------------------
# Arguments: `--key value` pairs; keys in `multi` may repeat, keys in `flags`
# take no value.

br_parse_args <- function(args, known, multi = character(),
                          flags = character()) {
  out <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- sub("^--", "", args[[i]])
    if (!startsWith(args[[i]], "--") || !(key %in% c(known, flags))) {
      br_refuse("unknown argument ", args[[i]])
    }
    if (key %in% flags) {
      out[[key]] <- TRUE
      i <- i + 1L
      next
    }
    if (i == length(args)) {
      br_refuse("--", key, " needs a value")
    }
    value <- args[[i + 1L]]
    out[[key]] <- if (key %in% multi) c(out[[key]], value) else value
    i <- i + 2L
  }
  out
}

br_int_arg <- function(opts, key, default = NULL, min = 0L) {
  value <- opts[[key]]
  if (is.null(value)) {
    if (is.null(default)) br_refuse("--", key, " is required")
    return(as.integer(default))
  }
  if (!grepl("^[0-9]+$", value) || as.numeric(value) > .Machine$integer.max) {
    br_refuse("--", key, " must be a whole number, got ", value)
  }
  value <- as.integer(value)
  if (value < min) {
    br_refuse("--", key, " must be at least ", min)
  }
  value
}

# ---------------------------------------------------------------------------
# The package under test: loaded from a source tree, by default the one that
# holds this script.

br_load_pkg <- function(pkg) {
  if (is.null(pkg)) {
    pkg <- dirname(dirname(br_dir()))
  }
  if (!file.exists(file.path(pkg, "DESCRIPTION"))) {
    br_refuse("--pkg is not a package source tree: ", pkg)
  }
  suppressMessages(pkgload::load_all(pkg, quiet = TRUE, export_all = FALSE))
  ns <- asNamespace("robotstxtr")
  list(
    path = normalizePath(pkg),
    validate = get("robots_validate_text", ns),
    evaluate = get("robots_evaluate_text_v1", ns),
    resolve = get("robots_resolve_matcher_profile_v1", ns)
  )
}

# ---------------------------------------------------------------------------
# Seeded draws that leave the caller's RNG state as it was.

br_with_seed <- function(seed, expr) {
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (had) saved <- get(".Random.seed", envir = globalenv())
  kind <- RNGkind()
  on.exit({
    RNGkind(kind[[1L]], kind[[2L]], kind[[3L]])
    if (had) {
      assign(".Random.seed", saved, envir = globalenv())
    } else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      rm(".Random.seed", envir = globalenv())
    }
  })
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(seed)
  expr
}

# sample() that never treats a single number as a range.
br_pick <- function(x, size) {
  if (!length(x) || size <= 0L) {
    return(x[0L])
  }
  x[sample.int(length(x), min(size, length(x)))]
}

# ---------------------------------------------------------------------------
# Lines and their rendering. Lines split at CRLF, LF or a lone CR, the line
# endings RFC 9309's NL allows; a final line ending opens no extra line.

br_split_lines <- function(bytes) {
  n <- length(bytes)
  if (!n) {
    return(list())
  }
  cr <- as.raw(0x0d)
  lf <- as.raw(0x0a)
  lines <- list()
  start <- 1L
  i <- 1L
  while (i <= n) {
    b <- bytes[[i]]
    if (b == lf || b == cr) {
      lines[[length(lines) + 1L]] <- bytes[seq_len(i - start) + start - 1L]
      if (b == cr && i < n && bytes[[i + 1L]] == lf) {
        i <- i + 1L
      }
      start <- i + 1L
    }
    i <- i + 1L
  }
  if (start <= n) {
    lines[[length(lines) + 1L]] <- bytes[start:n]
  }
  lines
}

# The length of the valid UTF-8 sequence starting at `bytes[i]`, or 0.
br_utf8_len <- function(bytes, i) {
  lead <- as.integer(bytes[[i]])
  len <- if (lead >= 0xc2 && lead <= 0xdf) {
    2L
  } else if (lead >= 0xe0 && lead <= 0xef) {
    3L
  } else if (lead >= 0xf0 && lead <= 0xf4) {
    4L
  } else {
    0L
  }
  if (!len || i + len - 1L > length(bytes)) {
    return(0L)
  }
  chunk <- bytes[i:(i + len - 1L)]
  if (validUTF8(rawToChar(chunk))) len else 0L
}

br_hex_escape <- function(bytes) {
  paste(sprintf("\\x%02X", as.integer(bytes)), collapse = "")
}

# One ASCII byte as shown: a backslash doubled, a control byte other than
# tab escaped.
br_show_ascii <- function(b) {
  if (b == 0x5c) {
    return("\\\\")
  }
  if ((b < 0x20 && b != 0x09) || b == 0x7f) {
    return(br_hex_escape(as.raw(b)))
  }
  rawToChar(as.raw(b))
}

# A valid UTF-8 character that would be invisible or break the line: a byte
# order mark, a C1 control (U+0080-U+009F), U+2028 or U+2029.
br_hidden_char <- function(chunk) {
  x <- as.integer(chunk)
  identical(x, c(0xefL, 0xbbL, 0xbfL)) ||
    (length(x) == 2L && x[[1L]] == 0xc2 && x[[2L]] <= 0x9f) ||
    identical(x, c(0xe2L, 0x80L, 0xa8L)) ||
    identical(x, c(0xe2L, 0x80L, 0xa9L))
}

# One line as the reader sees it: printable text kept, a backslash as \\,
# and as \xHH a control byte other than tab, an invalid UTF-8 byte and each
# byte of a hidden character (br_hidden_char()).
br_show_line <- function(bytes) {
  out <- character()
  i <- 1L
  while (i <= length(bytes)) {
    b <- as.integer(bytes[[i]])
    if (b < 0x80) {
      out <- c(out, br_show_ascii(b))
      i <- i + 1L
      next
    }
    len <- br_utf8_len(bytes, i)
    if (!len) {
      out <- c(out, br_hex_escape(bytes[i]))
      i <- i + 1L
      next
    }
    chunk <- bytes[i:(i + len - 1L)]
    out <- c(out, if (br_hidden_char(chunk)) br_hex_escape(chunk) else {
      rawToChar(chunk)
    })
    i <- i + len
  }
  txt <- paste(out, collapse = "")
  Encoding(txt) <- "UTF-8"
  txt
}

br_shown_lines <- function(bytes) {
  vapply(br_split_lines(bytes), br_show_line, character(1))
}

# The file as the prompt carries it: numbered lines in a backtick fence one
# longer than the longest backtick run in the file (at least three).
br_render_file <- function(bytes) {
  shown <- br_shown_lines(bytes)
  runs <- gregexpr("`+", shown)
  longest <- max(0L, unlist(lapply(runs, attr, "match.length")))
  fence <- strrep("`", max(3L, longest + 1L))
  numbered <- if (length(shown)) {
    paste0(seq_along(shown), "| ", shown)
  } else {
    character()
  }
  paste(c(fence, numbered, fence), collapse = "\n")
}

# ---------------------------------------------------------------------------
# Edge-case fixture bodies (tests/testthat/fixtures/edge-cases/): `.txt`
# verbatim, `.hex` as hexadecimal pairs.

br_fixture_body <- function(dir, file) {
  path <- file.path(dir, file)
  if (endsWith(file, ".hex")) {
    hex <- gsub("[[:space:]]", "", paste(readLines(path), collapse = ""))
    pairs <- substring(hex, seq(1L, nchar(hex), 2L), seq(2L, nchar(hex), 2L))
    return(as.raw(strtoi(pairs, 16L)))
  }
  readBin(path, "raw", file.size(path))
}

br_read_bytes <- function(path) {
  readBin(path, "raw", file.size(path))
}

# The text the evaluator takes: NUL bytes removed (an R string cannot hold
# one), bytes otherwise verbatim, as the corpus harness evaluates.
br_eval_text <- function(bytes) {
  txt <- rawToChar(bytes[bytes != as.raw(0L)])
  Encoding(txt) <- "bytes"
  txt
}

br_probe_origin <- function() {
  "https://example.com"
}

br_write_tsv <- function(df, path) {
  utils::write.table(df, path, sep = "\t", quote = TRUE, row.names = FALSE,
                     na = "", fileEncoding = "UTF-8")
}

br_read_tsv <- function(path) {
  utils::read.delim(path, colClasses = "character", na.strings = character(),
                    encoding = "UTF-8", quote = "\"")
}
