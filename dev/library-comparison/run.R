# Library comparison (ROBO-dqqkvwts). Dev only: never run by tests.
#
# Runs the same (body, URL, token) cases through eight robots.txt libraries,
# the pristine upstream Google engine (the reference) and robotstxtr's two
# Google paths, and writes a decision matrix. design/library-comparison.md
# reads its classes from this output.
#
# The cases are every row of the edge-case catalog
# (tests/testthat/fixtures/edge-cases/manifest.csv, on https://example.com)
# plus the synthesized class fixtures in dev/library-comparison/fixtures/
# (manifest.csv there, same body-file rules: `<id>.txt` verbatim, `<id>.hex`
# lowercase hexadecimal).
#
# Usage:
#   Rscript dev/library-comparison/run.R <libcmp> [out_dir]
#
# `<libcmp>` is the one-command-per-library runner: `libcmp <id> <manifest>
# <out>`, manifest lines `<body_file>\t<url>\t<user_agent>`, output lines `1`,
# `0` or `ERR <message>`. Its `google-ref` id takes
# `<body_file>\t<agent>\t<url>` and writes
# `<allowed>\t<matching_line>\t<ever_seen>`. `out_dir` (default: a
# fresh temporary directory) receives the bodies, the manifests, each
# library's raw output and `matrix.tsv`.
#
# Exit status 1 when a class fixture's live answer drifts from the answer its
# manifest row records (the doc and the pinned test would then be stale), or
# when robotstxtr differs from the reference on any row other than a
# NUL-bearing body (a deliberate split, below); 0 otherwise.

options(width = 160L)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) {
  stop("usage: run.R <libcmp> [out_dir]", call. = FALSE)
}
libcmp <- normalizePath(args[[1L]], mustWork = TRUE)
out_dir <- if (length(args) >= 2L) args[[2L]] else tempfile("libcmp-")
dir.create(file.path(out_dir, "bodies"), recursive = TRUE,
           showWarnings = FALSE)
out_dir <- normalizePath(out_dir, mustWork = TRUE)

script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
root <- normalizePath(file.path(dirname(script), "..", ".."), mustWork = TRUE)
pkgload::load_all(root, quiet = TRUE, export_all = FALSE)

libs <- c(
  "py-stdlib", "protego", "go-temoto", "rust-texting-robots",
  "java-crawler-commons", "js-robots-parser", "r-robotstxt", "r-spiderbar"
)
# The manifest column that records each answer: the id with `_` for `-`.
col_of <- function(id) gsub("-", "_", id, fixed = TRUE)

# --- The cases ----------------------------------------------------------------

hex_bytes <- function(lines, file) {
  text <- paste(lines, collapse = "\n")
  if (grepl("[^0-9a-f[:space:]]", text)) {
    stop(file, ": a character outside [0-9a-f] and whitespace", call. = FALSE)
  }
  hex <- gsub("[[:space:]]", "", text)
  if (nchar(hex) %% 2L != 0L) {
    stop(file, ": an odd number of hex digits", call. = FALSE)
  }
  starts <- seq(1L, nchar(hex), by = 2L)
  as.raw(strtoi(substring(hex, starts, starts + 1L), 16L))
}

read_body <- function(dir, file) {
  path <- file.path(dir, file)
  if (endsWith(file, ".hex")) {
    return(hex_bytes(readLines(path, warn = FALSE), file))
  }
  readBin(path, "raw", file.size(path))
}

read_cases <- function(dir, source) {
  m <- utils::read.csv(
    file.path(dir, "manifest.csv"), colClasses = "character",
    na.strings = character(), encoding = "UTF-8", check.names = FALSE
  )
  if (!"class" %in% names(m)) m$class <- "catalog"
  m$source <- source
  m$dir <- dir
  m
}

edge <- read_cases(
  file.path(root, "tests", "testthat", "fixtures", "edge-cases"), "catalog"
)
own <- read_cases(
  file.path(root, "dev", "library-comparison", "fixtures"), "dqqkvwts"
)
keep <- c("source", "class", "id", "dir", "body_file", "path", "token")
cases <- rbind(edge[keep], own[keep])
cases$url <- paste0("https://example.com", cases$path)
Encoding(cases$url) <- "UTF-8"

cases$body_key <- paste(cases$source, cases$body_file, sep = "-")
cases$body_path <- file.path(out_dir, "bodies",
                             paste0(cases$body_key, ".bin"))
bodies <- list()
for (k in which(!duplicated(cases$body_key))) {
  bodies[[cases$body_key[[k]]]] <- read_body(cases$dir[[k]],
                                             cases$body_file[[k]])
  writeBin(bodies[[cases$body_key[[k]]]], cases$body_path[[k]])
}
body_of <- function(k) bodies[[cases$body_key[[k]]]]

write_lines <- function(lines, file) {
  con <- file(file, open = "wb")
  on.exit(close(con))
  writeLines(enc2utf8(lines), con, sep = "\n", useBytes = TRUE)
}

manifest <- file.path(out_dir, "manifest.tsv")
write_lines(paste(cases$body_path, cases$url, cases$token, sep = "\t"),
            manifest)
ref_manifest <- file.path(out_dir, "manifest-google-ref.tsv")
write_lines(paste(cases$body_path, cases$token, cases$url, sep = "\t"),
            ref_manifest)

# --- The libraries and the reference ------------------------------------------

run_lib <- function(id, input) {
  out <- file.path(out_dir, paste0("out-", id, ".txt"))
  # system2() quotes `command` itself; `args` go to the shell as given.
  status <- system2(libcmp, shQuote(c(id, input, out)), stdout = FALSE)
  if (!identical(status, 0L) || !file.exists(out)) {
    return(rep(paste("ERR runner exit", status), nrow(cases)))
  }
  res <- readLines(out, warn = FALSE, encoding = "UTF-8")
  if (length(res) != nrow(cases)) {
    stop(id, ": ", length(res), " answers for ", nrow(cases), " cases",
         call. = FALSE)
  }
  res
}

ref <- run_lib("google-ref", ref_manifest)
ref_cols <- strsplit(ref, "\t", fixed = TRUE)
cases$google_ref <- vapply(ref_cols, `[[`, character(1L), 1L)
cases$google_ref_line <- vapply(ref_cols, `[[`, character(1L), 2L)
for (id in libs) {
  cases[[col_of(id)]] <- run_lib(id, manifest)
}

# --- robotstxtr ---------------------------------------------------------------

# R strings cannot hold a NUL: a NUL-bearing body is decoded the way the fetch
# path decodes one (R/body-decode.R, NUL bytes dropped). Every other body goes
# to the text entry points byte for byte.
body_text <- function(bytes) {
  if (any(bytes == as.raw(0))) {
    return(asNamespace("robotstxtr")$decode_matcher_body(bytes))
  }
  txt <- rawToChar(bytes)
  Encoding(txt) <- "bytes"
  txt
}
as_answer <- function(x) if (is.na(x)) "NA" else if (isTRUE(x)) "1" else "0"
cases$robotstxtr_v1 <- vapply(seq_len(nrow(cases)), function(k) {
  r <- robots_evaluate_text_v1(
    body_text(body_of(k)), cases$url[[k]], cases$token[[k]], "google",
    "google"
  )$results
  if (is.na(r$url_decision)) "NA" else as_answer(r$url_decision == "allow")
}, character(1L))
cases$robotstxtr_text <- vapply(seq_len(nrow(cases)), function(k) {
  as_answer(allowed_by_robots_text(
    body_text(body_of(k)), cases$url[[k]], cases$token[[k]]
  )$results$allowed)
}, character(1L))

# --- Output -------------------------------------------------------------------

answer_cols <- c("google_ref", "robotstxtr_v1", "robotstxtr_text",
                 col_of(libs))
matrix_out <- cases[c("source", "class", "id", "path", "token",
                      "google_ref_line", answer_cols)]
utils::write.table(
  matrix_out, file.path(out_dir, "matrix.tsv"),
  sep = "\t", quote = FALSE, row.names = FALSE, fileEncoding = "UTF-8"
)

short <- function(x) ifelse(startsWith(x, "ERR"), "ERR", x)
differs <- function(col) short(cases[[col]]) != cases$google_ref
cat(sprintf("cases: %d (catalog %d, class fixtures %d)\n", nrow(cases),
            sum(cases$source == "catalog"), sum(cases$source == "dqqkvwts")))
for (col in answer_cols[-1L]) {
  d <- differs(col)
  cat(sprintf("%-22s differs from google-ref on %3d rows (errors %d)\n", col,
              sum(d), sum(startsWith(cases[[col]], "ERR"))))
}
diff_rows <- Reduce(`|`, lapply(answer_cols[-1L], differs))
if (any(diff_rows)) {
  view <- cases[diff_rows, c("class", "id", "path", "token", answer_cols)]
  view$path <- ifelse(nchar(view$path) > 24L,
                      paste0(substr(view$path, 1L, 21L), "..."), view$path)
  view[answer_cols] <- lapply(view[answer_cols], short)
  names(view)[match(answer_cols, names(view))] <- c(
    "ref", "v1", "txt", "py", "pro", "go", "rs", "jv", "js", "rtx", "spb"
  )
  print(view, row.names = FALSE)
}
errs <- unique(unlist(lapply(col_of(libs), function(col) {
  e <- startsWith(cases[[col]], "ERR")
  if (any(e)) paste(col, cases$id[e], cases$token[e], cases[[col]][e])
})))
if (length(errs) > 0L) {
  cat("errors:\n", paste0("  ", errs, "\n"), sep = "")
}
# Rows where every library gives one answer and the reference another: the
# shape the comparison investigates when robotstxtr sides with the reference.
lib_answers <- as.matrix(as.data.frame(lapply(cases[col_of(libs)], short)))
unanimous <- apply(lib_answers, 1L, function(a) length(unique(a)) == 1L) &
  lib_answers[, 1L] != "ERR" & lib_answers[, 1L] != cases$google_ref
if (any(unanimous)) {
  cat("every library against the reference:\n", paste0(
    "  ", cases$id[unanimous], " ", substr(cases$path[unanimous], 1L, 24L),
    " ", cases$token[unanimous], ": libraries ", lib_answers[unanimous, 1L],
    ", reference ", cases$google_ref[unanimous], ", robotstxtr ",
    cases$robotstxtr_v1[unanimous], "\n"
  ), sep = "")
}
cat("output in", out_dir, "\n")

failed <- FALSE
# A NUL-bearing body is the one deliberate split from the reference: upstream
# ends a line at its first NUL, robotstxtr drops every NUL
# (design/engine-profiles.md section 5b, class 5).
has_nul <- vapply(seq_len(nrow(cases)), function(k) {
  any(body_of(k) == as.raw(0))
}, logical(1L))
ours <- (cases$robotstxtr_v1 != cases$google_ref |
           cases$robotstxtr_text != cases$google_ref) & !has_nul
if (any(ours)) {
  cat("robotstxtr differs from the reference:\n",
      paste0("  ", cases$id[ours], " ", cases$path[ours], "\n"), sep = "")
  failed <- TRUE
}
recorded <- intersect(c("google_ref", "robotstxtr", col_of(libs)), names(own))
own_rows <- which(cases$source == "dqqkvwts")
drift <- character()
for (col in recorded) {
  live <- if (col == "robotstxtr") cases$robotstxtr_v1 else cases[[col]]
  live <- short(live[own_rows])
  want <- own[[col]]
  bad <- nzchar(want) & live != want
  if (any(bad)) {
    drift <- c(drift, sprintf("%s %s %s: recorded %s, live %s", col,
                              own$id[bad], own$token[bad], want[bad],
                              live[bad]))
  }
}
if (length(drift) > 0L) {
  cat("recorded answers drifted:\n", paste0("  ", drift, "\n"), sep = "")
  failed <- TRUE
}
if (failed) {
  quit(status = 1L)
}
