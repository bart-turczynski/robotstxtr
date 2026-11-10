#!/usr/bin/env Rscript
#
# Large-body benchmark for the Google batch adapter (ROBO-iooslxvj).
#
# Times, in one session, the row path (row_matcher_frame_v1(match_google_v1,
# ...): two matcher parses and a collector parse per row) against the batch
# adapter match_google_batch_v1() (one matcher parse per distinct body), on a
# synthesized example.com body at and above Google's 512,000-byte window with
# many URL and token rows per body. The adapter's time includes the batch
# module's distinct-body grouping, which is also timed on its own
# (matcher_body_groups_v1(), decision 3d of the dispatch addendum). It checks
# the two frames are identical before reporting.
#
# No timing is committed: the numbers depend on the machine. Record them in
# the merge request.
#
# Usage (from the package root, after the package builds):
#   Rscript dev/bench-google-batch.R [urls_per_body] [reps]

args <- commandArgs(trailingOnly = TRUE)
n_urls <- if (length(args) >= 1L) as.integer(args[[1L]]) else 100L
reps <- if (length(args) >= 2L) as.integer(args[[2L]]) else 3L

pkgload::load_all(".", quiet = TRUE)

# A body of rule groups on example.com paths, padded with more groups until
# it reaches `size` bytes.
bench_body <- function(size) {
  group <- function(k) {
    sprintf(
      paste0(
        "User-agent: bot%d\nDisallow: /section%d/\nAllow: /section%d/open\n",
        "Disallow: /*.php$\n\n"
      ),
      k, k, k
    )
  }
  head <- paste0(
    "User-agent: *\nDisallow: /private\nAllow: /private/ok\n",
    "Allow: /index.html\n\n"
  )
  text <- head
  k <- 0L
  while (nchar(text, type = "bytes") < size) {
    k <- k + 1L
    text <- paste0(text, paste(vapply(k:(k + 99L), group, ""), collapse = ""))
    k <- k + 99L
  }
  charToRaw(text)
}

bodies <- list(
  at_window = bench_body(512000L)[seq_len(512000L)],
  over_window = bench_body(600000L)
)
paths <- c(
  "/", "/private", "/private/ok", "/index.html", "/section7/",
  "/section7/open", "/page.php", "/section123/x"
)
urls <- paste0(
  "https://example.com", rep_len(paths, n_urls), "?q=", seq_len(n_urls)
)
tokens <- c("FooBot", "bot7")

grid <- expand.grid(
  body = seq_along(bodies), url = seq_along(urls), token = seq_along(tokens)
)
rows <- list(
  bodies = unname(bodies[grid$body]),
  urls = urls[grid$url],
  tokens = tokens[grid$token]
)

time_it <- function(f) {
  times <- vapply(seq_len(reps), function(i) {
    system.time(f())[["elapsed"]]
  }, numeric(1L))
  stats::median(times)
}

row_path <- function() {
  row_matcher_frame_v1(match_google_v1, rows$bodies, rows$urls, rows$tokens)
}
batch <- function() {
  match_google_batch_v1(rows$bodies, rows$urls, rows$tokens)
}
grouping <- function() matcher_body_groups_v1(rows$bodies)

expected <- row_path()
got <- batch()
attr(got, "n_parse_calls") <- NULL
stopifnot(identical(got, expected))

t_row <- time_it(row_path)
t_batch <- time_it(batch)
t_group <- time_it(grouping)

cat(sprintf(
  "rows: %d (%d distinct bodies of %s bytes)\n",
  length(rows$bodies), length(bodies),
  paste(lengths(bodies), collapse = " and ")
))
cat(sprintf("row path:  %.3f s (median of %d)\n", t_row, reps))
cat(sprintf("batch:     %.3f s (median of %d)\n", t_batch, reps))
cat(sprintf("  of which grouping: %.3f s\n", t_group))
cat(sprintf("speedup:   %.1fx\n", t_row / t_batch))
