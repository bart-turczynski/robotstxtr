# Blind-reader prompt renderer (ROBO-nvgtqdlu): one filled prompt per sampled
# file, from dev/blind-reader/prompt.md and a sample written by sample.R.
# Usage: dev/blind-reader/README.md. Its output goes under --out, which must
# lie outside every git work tree: a rendered prompt holds a corpus file.

br_self <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
source(file.path(dirname(normalizePath(sub("^--file=", "", br_self))),
                 "common.R"))

# The prompt text between the PROMPT START and PROMPT END markers.
prompt_template <- function(path) {
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  start <- grep("^<!-- PROMPT START -->$", lines)
  end <- grep("^<!-- PROMPT END -->$", lines)
  if (length(start) != 1L || length(end) != 1L || end <= start + 1L) {
    br_refuse("the prompt needs one PROMPT START and one PROMPT END marker")
  }
  txt <- paste(lines[(start + 1L):(end - 1L)], collapse = "\n")
  for (ph in c("{{TOKEN}}", "{{PATH}}", "{{FILE}}")) {
    if (lengths(regmatches(txt, gregexpr(ph, txt, fixed = TRUE))) != 1L) {
      br_refuse("the prompt must hold ", ph, " exactly once")
    }
  }
  txt
}

# Replace the one `placeholder` with `value` taken literally (sub() would
# read backslashes in a file's text as escapes).
replace_once <- function(txt, placeholder, value) {
  at <- regexpr(placeholder, txt, fixed = TRUE)
  paste0(substr(txt, 1L, at - 1L), value,
         substr(txt, at + nchar(placeholder), nchar(txt)))
}

fill_prompt <- function(template, token, path, bytes) {
  txt <- replace_once(template, "{{TOKEN}}", token)
  txt <- replace_once(txt, "{{PATH}}", path)
  replace_once(txt, "{{FILE}}", br_render_file(bytes))
}

main <- function(args) {
  opts <- br_parse_args(args, known = c("sample", "out", "prompt", "stage"))
  if (is.null(opts$sample) ||
      !file.exists(file.path(opts$sample, "sample.rds"))) {
    br_refuse("--sample must name a directory sample.R wrote")
  }
  prompt <- opts$prompt
  if (is.null(prompt)) prompt <- file.path(br_dir(), "prompt.md")
  stage <- if (is.null(opts$stage)) "all" else opts$stage
  if (!stage %in% c("stage1", "stage2", "all")) {
    br_refuse("--stage must be stage1, stage2 or all")
  }
  h <- br_harness()
  br_check_out(h, if (is.null(opts$out)) "" else opts$out)
  template <- prompt_template(prompt)
  df <- readRDS(file.path(opts$sample, "sample.rds"))
  if (stage != "all") df <- df[df$stage == stage, ]
  dir.create(opts$out, recursive = TRUE, mode = "0700")
  for (i in seq_len(nrow(df))) {
    id <- df$sample_id[[i]]
    bytes <- br_read_bytes(file.path(opts$sample, "files",
                                     paste0(id, ".bin")))
    txt <- fill_prompt(template, df$token[[i]], df$path[[i]], bytes)
    con <- file(file.path(opts$out, paste0(id, ".txt")), "wb")
    writeBin(charToRaw(enc2utf8(txt)), con)
    close(con)
  }
  file.copy(prompt, file.path(opts$out, "prompt.md"))
  cat("rendered", nrow(df), "prompts to", opts$out, "\n")
}

main(commandArgs(trailingOnly = TRUE))
