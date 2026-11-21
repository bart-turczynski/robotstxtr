# Blind-reader self-test (ROBO-nvgtqdlu): runs sample.R and score.R on a
# tiny synthetic corpus and a synthetic answer set in a temporary directory
# outside any git work tree, and exits non-zero when any check fails.
#
#   Rscript dev/blind-reader/selftest.R
#
# It checks that (a) score.R accepts well-formed answers and rejects each
# malformed class with its own code, (b) no host an --exclude source names
# reaches the sample, and (c) the same seed reproduces the sample list and a
# different seed does not. Every host is an `.example` name; no corpus file
# is read.

br_self <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
here <- dirname(normalizePath(sub("^--file=", "", br_self)))

state <- new.env()
state$failures <- character()
check <- function(ok, what) {
  cat(if (isTRUE(ok)) "ok  " else "FAIL", what, "\n")
  if (!isTRUE(ok)) state$failures <- c(state$failures, what)
}

run_script <- function(script, args) {
  status <- system2(file.path(R.home("bin"), "Rscript"),
                    c(shQuote(file.path(here, script)), shQuote(args)),
                    stdout = FALSE, stderr = FALSE)
  status
}

# ---------------------------------------------------------------------------
# A synthetic corpus: four clean bodies (two of them excluded), two with
# diagnostics, and records the pool must skip without failing.

write_record <- function(corpus, host, body, status = 200L) {
  dir.create(file.path(corpus, host), recursive = TRUE)
  saveRDS(list(fetch_outcome = "ok", http_status = status,
               content_type = "text/plain", content_flag = "text",
               body_truncated = FALSE, body = body),
          file.path(corpus, host, "robots.rds"))
}

make_corpus <- function(corpus) {
  clean <- function(x) {
    charToRaw(sprintf("User-agent: *\nDisallow: /%s/\nAllow: /%s/a$\n", x, x))
  }
  write_record(corpus, "keep-a.example", clean("a"))
  write_record(corpus, "keep-b.example", clean("b"))
  write_record(corpus, "excluded-a.example", clean("c"))
  write_record(corpus, "excluded-b.example", clean("d"))
  write_record(corpus, "typo.example", charToRaw(
    "User-agent: FooBot\nDisalow: /tmp\nDisallow: /a*b\n"
  ))
  write_record(corpus, "bytes.example", c(
    as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("User-agent: *\r\nDisallow: /caf"),
    as.raw(0xe9), charToRaw("\r\n")
  ))
  write_record(corpus, "notfound.example", charToRaw("<html></html>"), 404L)
  write_record(corpus, "nobody.example", NULL)
  write_record(corpus, "notraw.example", "User-agent: *")
  dir.create(file.path(corpus, "notalist.example"))
  saveRDS("not a record", file.path(corpus, "notalist.example", "robots.rds"))
}

sample_args <- function(corpus, out, seed, exclude, verify = NULL) {
  c("--corpus", corpus, "--out", out, "--seed", seed, "--n", "6",
    "--stage1", "2", "--anchors-silent", "3", "--exclude", exclude,
    if (!is.null(verify)) c("--verify", verify))
}

# ---------------------------------------------------------------------------
# Answers: one per format class, keyed to the sample's ids in order.

answer_set <- function() {
  dash <- " \u2014 "
  sec <- "\u00a72.2.2"
  ok <- paste0("decision: allow", dash, sec, "\nissue: none\nsurprise: none\n")
  list(
    good_none = ok,
    good_issue = paste0("decision: disallow", dash, "RFC 9309 ", sec,
                        ", \u00a72.3\nissue: L2 \"Disalow: /tmp\"", dash,
                        "misspelled record name\nsurprise: none\n"),
    decision_line = paste0("Here is my answer:\n", ok),
    missing = NULL,
    decision_value = sub("allow", "maybe", ok, fixed = TRUE),
    decision_clause = "decision: allow - 2.2.2\nissue: none\nsurprise: none\n",
    line_count = paste0("decision: allow", dash, sec, "\nsurprise: none\n"),
    fenced = paste0("```\n", ok, "```\n"),
    issue_words = paste0("decision: allow", dash, sec, "\nissue: L1 \"x\"",
                         dash, paste(rep("word", 16), collapse = " "),
                         "\nsurprise: none\n"),
    issue_count = paste0("decision: allow", dash, sec, "\n",
                         paste0("issue: L", 1:4, " \"x\"", dash, "note\n",
                                collapse = ""), "surprise: none\n"),
    blank_line = paste0(ok, "\n"),
    nul_byte = "nul"
  )
}

write_answers <- function(dir, ids) {
  dir.create(dir)
  set <- answer_set()
  stopifnot(length(ids) >= length(set))
  expected <- setNames(character(length(set)), ids[seq_along(set)])
  for (i in seq_along(set)) {
    class <- names(set)[[i]]
    expected[[i]] <- if (startsWith(class, "good")) "" else class
    path <- file.path(dir, paste0(ids[[i]], ".txt"))
    if (class == "missing") next
    bytes <- if (class == "nul_byte") {
      c(charToRaw("decision: allow"), as.raw(0L), charToRaw("\n"))
    } else {
      charToRaw(enc2utf8(set[[i]]))
    }
    writeBin(bytes, path)
  }
  expected
}

# ---------------------------------------------------------------------------

main <- function() {
  tmp <- tempfile("blind-reader-selftest-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  corpus <- file.path(tmp, "corpus")
  make_corpus(corpus)
  exclude <- file.path(tmp, "prior.txt")
  writeLines(c("excluded-a.example", "excluded-b.example"), exclude)
  s1 <- file.path(tmp, "s1")

  check(run_script("sample.R", sample_args(corpus, s1, "11", exclude)) == 0L,
        "sample.R runs on the synthetic corpus")
  df <- readRDS(file.path(s1, "sample.rds"))
  check(!any(startsWith(df$host, "excluded-")),
        "(b) no --exclude host reaches the sample")
  check(sum(df$kind == "clean") == 2L,
        "(b) only the two clean hosts not excluded are drawn as clean")

  same <- run_script("sample.R", sample_args(corpus, file.path(tmp, "s2"),
                                             "11", exclude, verify = s1))
  check(same == 0L, "(c) the same seed reproduces the sample list")
  other <- run_script("sample.R", sample_args(corpus, file.path(tmp, "s3"),
                                              "12", exclude, verify = s1))
  check(other == 1L, "(c) a different seed gives a different list")

  answers <- file.path(tmp, "answers")
  expected <- write_answers(answers, sort(df$sample_id))
  st <- run_script("score.R", c("--sample", s1, "--answers", answers,
                                "--out", file.path(tmp, "score")))
  check(st == 0L, "score.R runs, a NUL-bearing answer included")
  score <- readRDS(file.path(tmp, "score", "score.rds"))$score
  got <- setNames(score$format_error, score$sample_id)[names(expected)]
  for (id in names(expected)) {
    want <- expected[[id]]
    check(identical(got[[id]], want),
          sprintf("(a) %s: %s (got %s)",
                  if (nzchar(want)) "rejects" else "accepts",
                  if (nzchar(want)) want else id, got[[id]]))
  }

  if (length(state$failures)) {
    cat(length(state$failures), "check(s) failed\n")
    quit(save = "no", status = 1L)
  }
  cat("all checks passed\n")
}

main()
