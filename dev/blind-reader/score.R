# Blind-reader scorer (ROBO-nvgtqdlu): checks each saved reader answer
# against the fixed three-line format and sets it beside robotstxtr's own
# readings of the same file, token and path: the google, bing and yandex
# backends of robots_evaluate_text_v1(), robots_validate_text()'s diagnostics
# and, on an anchor, the catalog's RFC 9309 decision. Usage:
# dev/blind-reader/README.md. Its output goes under --out, outside every git
# work tree.

br_self <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
source(file.path(dirname(normalizePath(sub("^--file=", "", br_self))),
                 "common.R"))

# ---------------------------------------------------------------------------
# The answer format

answer_decisions <- function() {
  c("allow", "disallow", "unspecified", "cannot_tell")
}

word_count <- function(x) {
  length(strsplit(trimws(x), "[[:space:]]+")[[1L]])
}

format_fail <- function(error) {
  list(ok = FALSE, error = error, decision = NA_character_,
       clause = NA_character_, issues = NULL, surprise = NA_character_)
}

# Split an answer file into lines: no NUL byte, valid UTF-8, LF line ends,
# one final line end allowed, no blank line, nothing else stripped.
answer_lines <- function(bytes) {
  if (!length(bytes)) {
    return("empty")
  }
  if (any(bytes == as.raw(0L))) {
    return("nul_byte")
  }
  txt <- rawToChar(bytes)
  if (!validUTF8(txt)) {
    return("not_utf8")
  }
  Encoding(txt) <- "UTF-8"
  if (grepl("\r", txt, fixed = TRUE)) {
    return("cr_line_end")
  }
  txt <- sub("\n$", "", txt)
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1L]]
  if (any(startsWith(lines, "```") | startsWith(lines, "~~~"))) {
    return("fenced")
  }
  if (!all(nzchar(trimws(lines))) || endsWith(txt, "\n")) {
    return("blank_line")
  }
  list(lines)
}

check_decision <- function(line) {
  sec <- "(RFC 9309 )?\u00a7[0-9]+(\\.[0-9]+)*"
  pat <- paste0("^decision: ([A-Za-z_]+) \u2014 (", sec, "(, ", sec, ")?)$")
  if (!grepl("^decision: ", line)) {
    return("decision_line")
  }
  if (!grepl(pat, line, perl = TRUE)) {
    return("decision_clause")
  }
  value <- sub(pat, "\\1", line, perl = TRUE)
  if (!value %in% answer_decisions()) {
    return("decision_value")
  }
  list(decision = value, clause = sub(pat, "\\2", line, perl = TRUE))
}

check_issues <- function(lines) {
  if (!length(lines) || length(lines) > 3L) {
    return("issue_count")
  }
  if (!all(startsWith(lines, "issue: "))) {
    return("issue_line")
  }
  if (identical(lines, "issue: none")) {
    return(list(data.frame(line = integer(), quote = character(),
                           note = character(), stringsAsFactors = FALSE)))
  }
  pat <- "^issue: L([1-9][0-9]*) \"(.*)\" \u2014 (.+)$"
  if (!all(grepl(pat, lines, perl = TRUE))) {
    return("issue_shape")
  }
  note <- sub(pat, "\\3", lines, perl = TRUE)
  if (any(vapply(note, word_count, integer(1)) > 15L)) {
    return("issue_words")
  }
  list(data.frame(
    line = as.integer(sub(pat, "\\1", lines, perl = TRUE)),
    quote = sub(pat, "\\2", lines, perl = TRUE), note = note,
    stringsAsFactors = FALSE
  ))
}

check_surprise <- function(line) {
  if (!grepl("^surprise: \\S", line, perl = TRUE)) {
    return("surprise_line")
  }
  value <- sub("^surprise: ", "", line)
  if (word_count(value) > 15L) {
    return("surprise_words")
  }
  list(value)
}

# The whole check: the first rule an answer breaks, or its parsed parts.
check_answer <- function(bytes) {
  lines <- answer_lines(bytes)
  if (is.character(lines)) {
    return(format_fail(lines))
  }
  lines <- lines[[1L]]
  if (length(lines) < 3L) {
    return(format_fail("line_count"))
  }
  dec <- check_decision(lines[[1L]])
  if (is.character(dec)) {
    return(format_fail(dec))
  }
  issues <- check_issues(lines[-c(1L, length(lines))])
  if (is.character(issues)) {
    return(format_fail(issues))
  }
  surprise <- check_surprise(lines[[length(lines)]])
  if (is.character(surprise)) {
    return(format_fail(surprise))
  }
  list(ok = TRUE, error = "", decision = dec$decision, clause = dec$clause,
       issues = issues[[1L]], surprise = surprise[[1L]])
}

# ---------------------------------------------------------------------------
# robotstxtr's readings

# One backend's decision for the sample's token and path, or why it gave
# none: a bounded backend that does not take the token reads `n/a`.
engine_decision <- function(fns, bytes, token, path, backend) {
  if (backend != "google") {
    ok <- tryCatch({
      fns$resolve(backend, token)
      TRUE
    }, error = function(e) FALSE)
    if (!ok) {
      return("n/a")
    }
  }
  r <- fns$evaluate(br_eval_text(bytes), paste0(br_probe_origin(), path),
                    token, backend, backend)$results
  if (is.na(r$url_decision)) r$matcher_status else r$url_decision
}

validator_diagnostics <- function(fns, bytes) {
  d <- fns$validate(bytes)$diagnostics
  d[, c("line", "severity", "code")]
}

# ---------------------------------------------------------------------------
# One row per sample, one row per issue line

issue_rows <- function(id, issues, shown, diags) {
  if (is.null(issues) || !nrow(issues)) {
    return(NULL)
  }
  in_range <- issues$line <= length(shown)
  quoted <- ifelse(in_range, shown[pmin(issues$line, length(shown))], NA)
  codes <- vapply(issues$line, function(n) {
    paste(diags$code[!is.na(diags$line) & diags$line == n], collapse = ";")
  }, character(1))
  data.frame(
    sample_id = id, line = issues$line,
    quote_matches = in_range & !is.na(quoted) & quoted == issues$quote,
    validator_codes = codes, flagged = nzchar(codes), note = issues$note,
    stringsAsFactors = FALSE
  )
}

# Why a row wants a human read: a broken answer, a decision robotstxtr's
# Google reading (or, on an anchor, the RFC reading) does not share, an issue
# on a line the validator leaves alone, a misquoted line, or a surprise.
read_reasons <- function(row, issues) {
  r <- character()
  if (!row$format_ok) {
    return("format")
  }
  if (row$kind == "anchor") {
    if (row$decision != row$rfc9309_decision) r <- c(r, "rfc_differs")
  } else if (row$decision != row$google) {
    r <- c(r, "google_differs")
  }
  if (!is.null(issues) && nrow(issues)) {
    if (!all(issues$flagged)) r <- c(r, "issue_unflagged")
    if (!all(issues$quote_matches)) r <- c(r, "misquote")
  }
  if (row$surprise != "none") r <- c(r, "surprise")
  paste(r, collapse = ";")
}

score_one <- function(fns, sample_dir, answers, s) {
  id <- s$sample_id
  bytes <- br_read_bytes(file.path(sample_dir, "files", paste0(id, ".bin")))
  answer_path <- file.path(answers, paste0(id, ".txt"))
  a <- if (file.exists(answer_path)) {
    check_answer(br_read_bytes(answer_path))
  } else {
    format_fail("missing")
  }
  diags <- validator_diagnostics(fns, bytes)
  issues <- issue_rows(id, a$issues, br_shown_lines(bytes), diags)
  row <- data.frame(
    sample_id = id, stage = s$stage, kind = s$kind, stratum = s$stratum,
    format_ok = a$ok, format_error = a$error, decision = a$decision,
    clause = a$clause,
    google = engine_decision(fns, bytes, s$token, s$path, "google"),
    bing = engine_decision(fns, bytes, s$token, s$path, "bing"),
    yandex = engine_decision(fns, bytes, s$token, s$path, "yandex"),
    rfc9309_decision = s$rfc9309_decision,
    n_issues = if (is.null(a$issues)) NA_integer_ else nrow(a$issues),
    validator_lines = paste(sort(unique(diags$line[!is.na(diags$line)])),
                            collapse = ";"),
    validator_codes = paste(sort(unique(diags$code)), collapse = ";"),
    surprise = a$surprise, stringsAsFactors = FALSE
  )
  row$read_reasons <- read_reasons(row, issues)
  list(row = row, issues = issues)
}

# ---------------------------------------------------------------------------
# Main

main <- function(args) {
  opts <- br_parse_args(args,
                        known = c("sample", "answers", "out", "stage", "pkg"))
  if (is.null(opts$sample) ||
      !file.exists(file.path(opts$sample, "sample.rds"))) {
    br_refuse("--sample must name a directory sample.R wrote")
  }
  if (is.null(opts$answers) || !dir.exists(opts$answers)) {
    br_refuse("--answers must name an existing directory")
  }
  stage <- if (is.null(opts$stage)) "all" else opts$stage
  if (!stage %in% c("stage1", "stage2", "all")) {
    br_refuse("--stage must be stage1, stage2 or all")
  }
  h <- br_harness()
  br_check_out(h, if (is.null(opts$out)) "" else opts$out)
  fns <- br_load_pkg(opts$pkg)
  df <- readRDS(file.path(opts$sample, "sample.rds"))
  if (stage != "all") df <- df[df$stage == stage, ]
  if (!nrow(df)) {
    br_refuse("the sample has no rows for --stage ", stage)
  }
  scored <- lapply(seq_len(nrow(df)), function(i) {
    score_one(fns, opts$sample, opts$answers, df[i, ])
  })
  rows <- do.call(rbind, lapply(scored, `[[`, "row"))
  issues <- do.call(rbind, lapply(scored, `[[`, "issues"))
  dir.create(opts$out, recursive = TRUE, mode = "0700")
  br_write_tsv(rows, file.path(opts$out, "score.tsv"))
  if (!is.null(issues)) br_write_tsv(issues, file.path(opts$out, "issues.tsv"))
  saveRDS(list(score = rows, issues = issues,
               package = h$package_git_facts(fns$path), stage = stage),
          file.path(opts$out, "score.rds"))
  cat("scored", nrow(rows), "answers;", sum(rows$format_ok), "well formed,",
      sum(nzchar(rows$read_reasons)), "to read; wrote", opts$out, "\n")
  bad <- rows[!rows$format_ok, c("sample_id", "format_error")]
  if (nrow(bad)) {
    cat("format errors:\n")
    print(bad, row.names = FALSE)
  }
}

main(commandArgs(trailingOnly = TRUE))
