# The corpus harness under dev/corpus/ (ROBO-qbxsydcf): its path generator,
# its refusal rules and its input-set checks, on synthetic inputs only.
#
# dev/ is not in the built package, so under R CMD check these tests skip
# (.fleet-ci.yml allowed_skips); they run from the source tree.

harness_file <- function(name) {
  testthat::test_path("..", "..", "dev", "corpus", name)
}

load_harness <- function(env = parent.frame()) {
  skip_if_not(
    file.exists(harness_file("harness.R")),
    "corpus harness dev/ not present (built package)"
  )
  skip_if_not(
    exists("sha256sum", where = asNamespace("tools"), inherits = FALSE),
    "tools::sha256sum() unavailable (needs R >= 4.5.0)"
  )
  h <- new.env(parent = globalenv())
  sys.source(harness_file("harness.R"), envir = h)
  sys.source(harness_file("modes.R"), envir = h)
  h
}

expect_refusal <- function(expr, pattern, info = NULL) {
  expect_error(expr, pattern, class = "corpus_harness_refusal", info = info)
}

body_of <- function(text) charToRaw(text)

# Base-R stand-ins for withr, which is not a declared dependency: a temporary
# directory removed when `env` exits.
defer_in <- function(expr, env) {
  do.call(base::on.exit, list(expr, TRUE, FALSE), envir = env)
}

local_test_dir <- function(env = parent.frame()) {
  dir <- tempfile("corpus-harness-")
  dir.create(dir)
  defer_in(bquote(unlink(.(dir), recursive = TRUE)), env)
  dir
}

# corpus_env_config() takes its getenv: a fake one stands in for the process
# environment, so no test sets an environment variable.
fake_getenv <- function(...) {
  vals <- c(...)
  function(name) {
    v <- if (name %in% names(vals)) vals[[name]] else NA_character_
    if (is.na(v)) "" else v
  }
}

# ---------------------------------------------------------------------------
# Path generator

test_that("rule paths come from Allow/Disallow values in file order", {
  h <- load_harness()
  body <- body_of(paste0(
    "User-agent: *\r\n",
    "Disallow: /priv*ate$\r",
    "  allow :  /pub # a comment\n",
    "Disallow:\n",
    "DISALLOW: rel\n",
    "Sitemap: /not-a-rule\n",
    "Crawl-delay: 5\n"
  ))
  expect_identical(
    h$rule_paths(body, 100L),
    c("/private", "/privatex", "/pub", "/pubx", "/rel", "/relx")
  )
  expect_identical(h$rule_paths(body, 3L), c("/private", "/privatex", "/pub"))
  expect_identical(h$rule_paths(raw(0), 10L), character())
})

test_that("rule paths percent-encode bytes a request cannot carry raw", {
  h <- load_harness()
  expect_identical(
    h$encode_path_bytes(as.raw(c(0x2f, 0x61, 0x20, 0x23, 0xc3, 0xa9, 0x25))),
    "/a%20%23%C3%A9%"
  )
  body <- c(body_of("Disallow: /caf"), as.raw(c(0xc3, 0xa9)), body_of("\n"))
  expect_identical(h$rule_paths(body, 1L), "/caf%C3%A9")
  expect_identical(h$encode_path_bytes(raw(0)), "")
})

test_that("rule paths ignore NUL bytes in the body", {
  h <- load_harness()
  body <- c(body_of("Disallow: /a"), as.raw(0), body_of("b\n"))
  expect_identical(h$rule_paths(body, 1L), "/ab")
})

test_that("the fixed path list covers the documented probe kinds", {
  h <- load_harness()
  p <- h$fixed_paths()
  expect_false(anyDuplicated(p) > 0L)
  for (needed in c(
    "", "/", "/$", "/*", "/%2F", "/%2f", "/%2A", "/%2a", "/A", "/a",
    "/index.html", "/Index.HTML", "/?q=1", "/café"
  )) {
    expect_true(needed %in% p, info = needed)
  }
})

test_that("random paths are seeded and leave the caller's RNG alone", {
  h <- load_harness()
  set.seed(99)
  before <- .Random.seed
  a <- h$random_paths(12L, 7L)
  expect_identical(.Random.seed, before)
  expect_identical(h$random_paths(12L, 7L), a)
  expect_false(identical(h$random_paths(12L, 8L), a))
  expect_length(a, 12L)
  expect_true(all(startsWith(a, "/")))
  expect_identical(h$random_paths(0L, 7L), character())
})

test_that("a path set de-duplicates and keeps the first source", {
  h <- load_harness()
  ps <- h$path_set(body_of("Disallow: /index.html\n"), 4L, c("/r1", "/"))
  expect_identical(ps$path_id, seq_len(nrow(ps)))
  expect_false(anyDuplicated(ps$path) > 0L)
  expect_identical(ps$source[ps$path == "/index.html"], "rule")
  expect_identical(ps$source[ps$path == "/"], "fixed")
  expect_identical(ps$source[ps$path == "/r1"], "random")
})

test_that("synthetic size bodies straddle the 512,000-byte boundary", {
  h <- load_harness()
  syn <- h$synthetic_size_bodies()
  tail_of <- function(b, n, k) rawToChar(b[(n - k + 1L):n])
  rule <- h$size_variants(syn$rule_line)
  expect_named(rule, c("cut_511999", "cut_512000", "cut_512001", "full"))
  expect_identical(lengths(rule)[1:3], c(
    cut_511999 = 511999L, cut_512000 = 512000L, cut_512001 = 512001L
  ))
  expect_identical(tail_of(rule$cut_511999, 511999L, 9L), "Disallow:")
  expect_identical(tail_of(rule$cut_512000, 512000L, 10L), "Disallow: ")
  expect_identical(tail_of(rule$cut_512001, 512001L, 11L), "Disallow: /")
  pct <- h$size_variants(syn$percent_escape)
  expect_identical(tail_of(pct$cut_511999, 511999L, 2L), "/a")
  expect_identical(tail_of(pct$cut_512000, 512000L, 3L), "/a%")
  expect_identical(tail_of(pct$cut_512001, 512001L, 4L), "/a%2")
  expect_named(h$size_variants(as.raw(rep(65L, 512000L))),
               c("cut_511999", "cut_512000"))
})

test_that("the narrow grid keeps each backend's first named token", {
  h <- load_harness()
  combos <- data.frame(
    combo_id = 1:6,
    ruleset = rep(c("r1", "r2"), each = 3L),
    backend = rep(c("g", "g", "y"), 2L),
    token = rep(c("*", "Gbot", "Ybot"), 2L),
    stringsAsFactors = FALSE
  )
  s <- h$size_combos(combos)
  expect_identical(s$token, c("Gbot", "Ybot", "Gbot", "Ybot"))
  # The full grid's ids, so every results row names one grid.
  expect_identical(s$combo_id, c(2L, 3L, 5L, 6L))
})

test_that("the narrow path set is rule paths then the boundary probes", {
  h <- load_harness()
  ps <- h$size_path_set(body_of("Disallow: /q\nDisallow: /r\n"), 3L)
  expect_identical(utils::head(ps$path, 3L), c("/q", "/qx", "/r"))
  expect_identical(ps$source[1:3], rep("rule", 3L))
  expect_true(all(c("/private-drafts/", "/a%2Fb/") %in% ps$path))
  expect_false(anyDuplicated(ps$path) > 0L)
})

# ---------------------------------------------------------------------------
# Refusal rules

local_dirs <- function(env = parent.frame()) {
  root <- local_test_dir(env)
  corpus <- file.path(root, "corpus")
  out <- file.path(root, "out")
  dir.create(corpus)
  list(root = root, corpus = corpus, out = out)
}

test_that("the harness refuses without both environment variables", {
  h <- load_harness()
  d <- local_dirs()
  env <- fake_getenv(ROBOTSTXTR_CORPUS_OUT = d$out)
  expect_refusal(h$corpus_env_config(env), "ROBOTSTXTR_CORPUS is unset")
  env <- fake_getenv(ROBOTSTXTR_CORPUS = d$corpus, ROBOTSTXTR_CORPUS_OUT = "")
  expect_refusal(h$corpus_env_config(env), "ROBOTSTXTR_CORPUS_OUT is unset")
  expect_refusal(
    h$corpus_env_config(env, need_corpus = FALSE),
    "ROBOTSTXTR_CORPUS_OUT is unset"
  )
  env <- fake_getenv(
    ROBOTSTXTR_CORPUS = d$corpus, ROBOTSTXTR_CORPUS_OUT = d$out
  )
  cfg <- h$corpus_env_config(env)
  expect_identical(basename(cfg$out), "out")
  expect_identical(basename(cfg$corpus), "corpus")
})

test_that("the harness refuses a corpus directory that does not exist", {
  h <- load_harness()
  d <- local_dirs()
  env <- fake_getenv(
    ROBOTSTXTR_CORPUS = file.path(d$root, "missing"),
    ROBOTSTXTR_CORPUS_OUT = d$out
  )
  expect_refusal(h$corpus_env_config(env), "existing directory")
})

test_that("the harness refuses an output directory inside a git work tree", {
  h <- load_harness()
  d <- local_dirs()
  repo <- file.path(d$root, "repo")
  dir.create(file.path(repo, ".git"), recursive = TRUE)
  env <- fake_getenv(
    ROBOTSTXTR_CORPUS = d$corpus,
    ROBOTSTXTR_CORPUS_OUT = file.path(repo, "not", "yet", "there")
  )
  expect_refusal(h$corpus_env_config(env), "inside a git work tree")
  # A worktree's .git is a file, and still marks a work tree.
  wt <- file.path(d$root, "wt")
  dir.create(wt)
  writeLines("gitdir: elsewhere", file.path(wt, ".git"))
  env <- fake_getenv(
    ROBOTSTXTR_CORPUS = d$corpus, ROBOTSTXTR_CORPUS_OUT = file.path(wt, "runs")
  )
  expect_refusal(h$corpus_env_config(env), "inside a git work tree")
  expect_refusal(
    h$corpus_env_config(env, need_corpus = FALSE), "inside a git work tree"
  )
})

test_that("the harness refuses an output directory inside the corpus", {
  h <- load_harness()
  d <- local_dirs()
  env <- fake_getenv(
    ROBOTSTXTR_CORPUS = d$corpus,
    ROBOTSTXTR_CORPUS_OUT = file.path(d$corpus, "runs")
  )
  expect_refusal(h$corpus_env_config(env), "inside ROBOTSTXTR_CORPUS")
})

test_that("run ids are plain names and a run is never overwritten", {
  h <- load_harness()
  d <- local_dirs()
  for (bad in c("", "../x", "a/b", ".hidden", NA_character_)) {
    expect_refusal(h$validate_run_id(bad), "run id", info = bad)
  }
  dir.create(d$out)
  run <- h$create_run_dir(d$out, "r-1")
  expect_true(dir.exists(file.path(run, "shards")))
  expect_refusal(h$create_run_dir(d$out, "r-1"), "already exists")
})

test_that("arguments are checked before any work", {
  h <- load_harness()
  expect_refusal(h$parse_harness_args(character()), "mode")
  expect_refusal(h$parse_harness_args("evaluate"), "--pkg")
  expect_refusal(
    h$parse_harness_args(c("evaluate", "--pkg", ".", "--workers", "3")),
    "--workers"
  )
  expect_refusal(h$parse_harness_args(c("compare", "--a", "x")), "--b")
  expect_refusal(
    h$parse_harness_args(c("validate", "--pkg", ".", "--bogus", "1")),
    "Unknown option"
  )
  opts <- h$parse_harness_args(
    c("evaluate", "--pkg", ".", "--seed", "5", "--subset", "0/10")
  )
  expect_identical(opts$seed, 5L)
  expect_identical(opts$subset, "0/10")
})

# ---------------------------------------------------------------------------
# Input-set checks

local_corpus <- function(env = parent.frame(), hosts = c("a.test", "b.test"),
                         empty = "c.test") {
  root <- local_test_dir(env)
  for (host in hosts) {
    dir.create(file.path(root, host))
    saveRDS(
      list(fetch_outcome = "fetched", body = body_of(host)),
      file.path(root, host, "robots.rds")
    )
  }
  for (host in empty) {
    dir.create(file.path(root, host))
  }
  root
}

fake_manifest <- function() {
  data.frame(
    file_id = 1:2, host = c("a.test", "b.test"), chunk = c(1L, 1L),
    has_rds = TRUE, rds_sha256 = c("1", "2"), rds_bytes = c(1L, 1L),
    stringsAsFactors = FALSE
  )
}

# A finished run directory under `out` with one identical files shard per
# chunk; `params` overrides the defaults.
fake_run <- function(out, id, status = "finished", params = list(),
                     chunks = 1L, manifest = fake_manifest(), combos = NULL) {
  dir.create(file.path(out, id, "shards"), recursive = TRUE)
  p <- list(
    mode = "validate", seed = 1L, chunk_size = 1L, max_rule_paths = 1L,
    random_paths = 1L, subset = NA_character_, max_hosts = NA_integer_
  )
  p[names(params)] <- params
  saveRDS(list(run_id = id, status = status, params = p),
          file.path(out, id, "record.rds"))
  for (ch in chunks) {
    saveRDS(data.frame(x = 1L),
            file.path(out, id, "shards", sprintf("files-%05d.rds", ch)))
  }
  saveRDS(manifest, file.path(out, id, "manifest.rds"))
  if (!is.null(combos)) {
    saveRDS(combos, file.path(out, id, "combos.rds"))
  }
  invisible(file.path(out, id))
}

compare_ctx <- function(out, a = "ra", b = "rb") {
  run_dir <- tempfile("cmp-", tmpdir = out)
  dir.create(run_dir)
  list(out = out, run_dir = run_dir, opts = list(a = a, b = b))
}

plan_opts <- function(chunk_size = 2L, subset = NA_character_,
                      max_hosts = NA_integer_) {
  list(chunk_size = chunk_size, subset = subset, max_hosts = max_hosts)
}

# The start manifest of a run over `corpus` with `opts`, as run.R takes it.
planned_manifest <- function(h, corpus, opts) {
  hosts <- h$list_host_dirs(corpus)
  h$corpus_manifest(corpus, h$plan_frame(hosts, h$plan_chunks(hosts, opts)))
}

test_that("a file changed or vanished mid-run makes the run invalid", {
  h <- load_harness()
  corpus <- local_corpus()
  hosts <- h$list_host_dirs(corpus)
  start <- h$corpus_manifest(corpus, hosts)
  expect_identical(start$host, c("a.test", "b.test", "c.test"))
  expect_identical(start$has_rds, c(TRUE, TRUE, FALSE))
  ok <- h$verify_run_inputs(start, start, h$corpus_manifest(corpus, hosts))
  expect_true(ok$valid)
  expect_identical(ok$start_hash, ok$end_hash)

  saveRDS(list(body = body_of("changed")),
          file.path(corpus, "a.test", "robots.rds"))
  changed <- h$verify_run_inputs(
    start, start, h$corpus_manifest(corpus, hosts)
  )
  expect_false(changed$valid)
  expect_true(changed$during_ok)
  expect_false(changed$end_ok)
  expect_identical(changed$changes$change, "changed")

  unlink(file.path(corpus, "b.test"), recursive = TRUE)
  gone <- h$verify_run_inputs(
    start, start, h$corpus_manifest(corpus, h$list_host_dirs(corpus))
  )
  expect_setequal(gone$changes$change, c("changed", "vanished"))
  # A robots.rds removed from a directory that stays is a change too.
  unlink(file.path(corpus, "a.test", "robots.rds"))
  emptied <- h$manifest_diff(start, h$corpus_manifest(corpus, hosts))
  expect_true("a.test" %in% emptied$host)

  # The bytes processed are checked too, apart from the end manifest.
  during <- start[c(1L, 3L), , drop = FALSE]
  mid <- h$verify_run_inputs(start, during, start)
  expect_false(mid$valid)
  expect_false(mid$during_ok)
  expect_identical(mid$changes$host, "b.test")
})

test_that("the manifest covers host directories without a robots.rds", {
  h <- load_harness()
  with_empty <- local_corpus()
  without <- local_corpus(empty = character())
  m1 <- planned_manifest(h, with_empty, plan_opts())
  m2 <- planned_manifest(h, without, plan_opts())
  expect_identical(m1$host, c("a.test", "b.test", "c.test"))
  expect_identical(m1$chunk, c(1L, 1L, 2L))
  expect_false(identical(h$manifest_hash(m1), h$manifest_hash(m2)))
  # Two full runs over listings that differ only in an empty directory.
  expect_refusal(h$check_input_sets(m1, m2, FALSE, FALSE), "different input")
  # A robots.rds appearing in a directory that had none is a change.
  saveRDS(list(body = raw(0)), file.path(with_empty, "c.test", "robots.rds"))
  end <- h$corpus_manifest(with_empty, m1)
  expect_identical(h$manifest_diff(m1, end)$change, "changed")
})

test_that("chunks over different host directories are never compared", {
  h <- load_harness()
  hosts <- c("a.test", "b.test", "c.test", "d.test")
  full <- local_corpus(hosts = hosts, empty = character())
  # The same files plus an empty directory sorted first: every later file
  # moves up one place, so chunk 2 holds b and c here and c and d in `full`.
  shifted <- local_corpus(hosts = hosts, empty = "0.test")
  m_full <- planned_manifest(h, full, plan_opts())
  m_sub <- planned_manifest(h, shifted, plan_opts(subset = "0/2"))
  expect_identical(m_sub$host, c("b.test", "c.test"))
  # Every file the subset run read matches the full run byte for byte ...
  expect_true(h$check_input_sets(m_full, m_sub, FALSE, TRUE))
  # ... but its chunk 2 is not the full run's chunk 2.
  expect_refusal(h$check_chunk_plans(m_full, m_sub), "chunk 2")
  expect_true(h$check_chunk_plans(
    m_full, planned_manifest(h, full, plan_opts(subset = "0/2"))
  ))

  # A --max-hosts run cut mid-chunk against a run with the whole chunk.
  cut <- planned_manifest(h, full, plan_opts(max_hosts = 3L))
  expect_true(h$check_input_sets(m_full, cut, FALSE, TRUE))
  expect_refusal(h$check_chunk_plans(m_full, cut), "mid-chunk")
  expect_true(h$check_chunk_plans(
    m_full, planned_manifest(h, full, plan_opts(max_hosts = 2L))
  ))
  expect_refusal(
    h$check_chunk_plans(m_full, m_full[, c("host", "rds_sha256")]),
    "no chunk plan"
  )
})

test_that("a manifest-mode run reads back the manifest it started from", {
  h <- load_harness()
  corpus <- local_corpus()
  run_dir <- file.path(local_test_dir(), "run")
  dir.create(file.path(run_dir, "shards"), recursive = TRUE)
  opts <- c(plan_opts(), list(workers = 1L))
  hosts <- h$list_host_dirs(corpus)
  chunks <- h$plan_chunks(hosts, opts)
  ctx <- list(opts = opts, corpus = corpus, run_dir = run_dir,
              hosts = hosts, chunks = chunks)
  start <- h$corpus_manifest(corpus, h$plan_frame(hosts, chunks))
  stats <- h$mode_manifest(ctx)
  expect_length(stats, 2L)
  during <- h$read_manifest(run_dir)
  expect_identical(during$manifest$chunk, start$chunk)
  expect_identical(during$manifest$file_id, start$file_id)
  expect_identical(during$n_skipped_no_rds, 1L)
  check <- h$verify_run_inputs(
    start, during$manifest, h$end_manifest(corpus, start, partial = FALSE)
  )
  expect_true(check$valid)
})

test_that("a chunk without a result fails the run and names its worker", {
  h <- load_harness()
  chunks <- list(list(chunk = 1L, ids = 1L), list(chunk = 2L, ids = 2L))
  fail <- function(ch) {
    if (ch$chunk == 2L) stop("boom") else list(n = 1L)
  }
  err <- tryCatch(h$run_chunks(chunks, fail, 1L), error = function(e) e)
  expect_s3_class(err, "corpus_harness_worker_failure")
  expect_identical(err$failures$chunk, 2L)
  expect_match(err$failures$cause, "boom")

  f <- h$chunk_failures(chunks, list(list(n = 1L), NULL))
  expect_identical(f$chunk, 2L)
  expect_match(f$cause, "died without a result")
  expect_match(h$chunk_failures(chunks, list(1L, list()))$cause, "integer")
  expect_identical(nrow(h$chunk_failures(chunks, list(list(), list()))), 0L)

  # A forked worker killed mid-chunk: mclapply() hands back NULL for it.
  skip_on_os("windows")
  kill <- function(ch) {
    if (ch$chunk == 2L) tools::pskill(Sys.getpid(), tools::SIGKILL)
    list(n = 1L)
  }
  err <- suppressWarnings(
    tryCatch(h$run_chunks(chunks, kill, 2L), error = function(e) e)
  )
  expect_s3_class(err, "corpus_harness_worker_failure")
  expect_identical(err$failures$chunk, 2L)
  expect_match(conditionMessage(err), "chunk 2: its worker died")
})

test_that("a run whose worker died is invalid for that cause alone", {
  h <- load_harness()
  corpus <- local_corpus()
  run_dir <- file.path(local_test_dir(), "run")
  dir.create(file.path(run_dir, "shards"), recursive = TRUE)
  opts <- c(plan_opts(chunk_size = 1L), list(workers = 1L))
  hosts <- h$list_host_dirs(corpus)
  chunks <- h$plan_chunks(hosts, opts)
  ctx <- list(opts = opts, corpus = corpus, run_dir = run_dir,
              hosts = hosts, chunks = chunks)
  start <- h$corpus_manifest(corpus, h$plan_frame(hosts, chunks))
  runner <- function(ctx) {
    h$run_chunks(ctx$chunks, function(ch) {
      if (ch$chunk == 2L) stop("worker lost")
      tables <- h$walk_chunk(ctx$corpus, ctx$hosts, ch)
      h$write_tables(ctx$run_dir, ch$chunk, tables, "files")
      h$chunk_summary(tables)
    }, 1L)
  }
  rec <- h$run_and_check(list(manifest = list()), ctx, runner, start)
  expect_false(rec$manifest$valid)
  expect_identical(rec$worker_failures$chunk, 2L)
  expect_match(rec$invalid_cause, "chunk 2: its worker failed: .*worker lost")
  expect_no_match(rec$invalid_cause, "vanished")
  expect_false(file.exists(file.path(run_dir, "input-changes.rds")))

  # The same run with every worker alive is valid.
  ok <- h$run_and_check(list(), ctx, h$mode_manifest, start)
  expect_true(ok$manifest$valid)
  expect_null(ok$invalid_cause)
  expect_identical(nrow(ok$chunks), 3L)
})

test_that("a full run's end manifest lists the corpus again", {
  h <- load_harness()
  corpus <- local_corpus()
  opts <- plan_opts(chunk_size = 10L)
  hosts <- h$list_host_dirs(corpus)
  plan <- h$plan_frame(hosts, h$plan_chunks(hosts, opts))
  start <- h$corpus_manifest(corpus, plan)
  dir.create(file.path(corpus, "new.test"))
  saveRDS(list(body = raw(0)), file.path(corpus, "new.test", "robots.rds"))
  full <- h$verify_run_inputs(
    start, start, h$end_manifest(corpus, plan, partial = FALSE)
  )
  expect_false(full$valid)
  expect_identical(full$changes$host, "new.test")
  expect_identical(full$changes$change, "appeared")
  # A partial run re-hashes only what it planned.
  part <- h$verify_run_inputs(
    start, start, h$end_manifest(corpus, plan, partial = TRUE)
  )
  expect_true(part$valid)
})

test_that("a corrupt compressed robots.rds is recorded unreadable", {
  h <- load_harness()
  corpus <- local_corpus()
  junk <- list(
    gzip = as.raw(c(0x1f, 0x8b, 1:20)),
    bzip2 = c(charToRaw("BZh"), as.raw(1:20)),
    xz = as.raw(c(0xfd, 1:20)),
    plain = as.raw(1:20)
  )
  for (kind in names(junk)) {
    path <- file.path(corpus, "a.test", "robots.rds")
    writeBin(junk[[kind]], path)
    read <- h$read_corpus_record(path)
    expect_null(read$record, info = kind)
    expect_identical(read$bytes, length(junk[[kind]]), info = kind)
    # The chunk walk carries on past it.
    tables <- h$walk_chunk(
      corpus, h$list_host_dirs(corpus), list(chunk = 1L, ids = 1:3)
    )
    expect_identical(tables$files$readable, c(FALSE, TRUE, NA), info = kind)
    expect_identical(tables$files$has_rds, c(TRUE, TRUE, FALSE), info = kind)
  }
})

test_that("comparing runs with different input sets fails before diffing", {
  h <- load_harness()
  m <- fake_manifest()
  expect_true(h$check_input_sets(m, m, FALSE, FALSE))
  m2 <- m
  m2$rds_sha256[[2L]] <- "3"
  expect_refusal(h$check_input_sets(m, m2, FALSE, FALSE), "different input")
  expect_refusal(
    h$check_input_sets(m, m[1L, ], FALSE, FALSE), "different input"
  )
  # A partial run must match the full run on every file it read.
  expect_true(h$check_input_sets(m, m[1L, ], FALSE, TRUE))
  expect_refusal(
    h$check_input_sets(m2, m[2L, ], FALSE, TRUE), "different input"
  )

  # Through the compare mode: identical result shards, different manifests.
  out <- local_test_dir()
  fake_run(out, "ra", manifest = m)
  fake_run(out, "rb", manifest = m2)
  ctx <- compare_ctx(out)
  expect_refusal(h$mode_compare(ctx), "different input")
  expect_false(file.exists(file.path(ctx$run_dir, "compare-summary.rds")))
  saveRDS(m, file.path(out, "rb", "manifest.rds"))
  res <- h$mode_compare(ctx)
  expect_true(res$identical)
})

test_that("compare refuses runs that are unfinished, invalid or unlike", {
  h <- load_harness()
  out <- local_test_dir()
  fake_run(out, "ok")
  fake_run(out, "running", status = "running")
  fake_run(out, "invalid", status = "invalid")
  for (bad in c("running", "invalid")) {
    expect_refusal(
      h$mode_compare(compare_ctx(out, "ok", bad)), "not a valid finished",
      info = bad
    )
  }
  fake_run(out, "seed", params = list(seed = 2L))
  expect_refusal(h$mode_compare(compare_ctx(out, "ok", "seed")), "seed")
  fake_run(out, "cmp-run", params = list(mode = "compare"))
  expect_refusal(
    h$mode_compare(compare_ctx(out, "cmp-run", "cmp-run")), "compare run"
  )

  # The grid and the path sets: what a combo id or a path id means.
  grid <- list(params = list(
    mode = "evaluate", combos = 2L, random_paths_sha256 = "r",
    fixed_paths_sha256 = "f", tokens = c("*", "x"), size_targets = 1:3
  ))
  combos <- list(combos = data.frame(
    combo_id = 1:2, ruleset = "r", backend = "b", token = c("*", "x"),
    stringsAsFactors = FALSE
  ))
  fake_run(out, "e1", params = grid$params, combos = combos)
  fake_run(out, "e2", params = grid$params, combos = combos)
  expect_true(h$mode_compare(compare_ctx(out, "e1", "e2"))$identical)
  for (fact in c("random_paths_sha256", "fixed_paths_sha256", "tokens",
                 "size_targets")) {
    p <- grid$params
    p[[fact]] <- c(p[[fact]], p[[fact]][[1L]])
    fake_run(out, fact, params = p, combos = combos)
    expect_refusal(
      h$mode_compare(compare_ctx(out, "e1", fact)), fact, info = fact
    )
  }
  swapped <- combos
  swapped$combos$token <- c("x", "*")
  fake_run(out, "swapped", params = grid$params, combos = swapped)
  expect_refusal(
    h$mode_compare(compare_ctx(out, "e1", "swapped")), "evaluation grid"
  )
  fake_run(out, "no-grid", params = grid$params)
  expect_refusal(
    h$mode_compare(compare_ctx(out, "e1", "no-grid")), "evaluation grid"
  )
})

test_that("a shard only one full run holds makes the runs different", {
  h <- load_harness()
  out <- local_test_dir()
  fake_run(out, "full", chunks = 1:2)
  fake_run(out, "short", chunks = 1L)
  res <- h$mode_compare(compare_ctx(out, "full", "short"))
  expect_false(res$identical)
  expect_true(res$unmatched_shards)
  expect_identical(res$summary$shards_only_a, 1L)
  expect_false(h$mode_compare(compare_ctx(out, "short", "full"))$identical)
  # A partial run is expected to lack shards the full run holds ...
  fake_run(out, "part", chunks = 1L, params = list(subset = "1/2"))
  expect_true(h$mode_compare(compare_ctx(out, "full", "part"))$identical)
  # ... but not to hold one the full run lacks.
  fake_run(out, "part-extra", chunks = 1:2, params = list(subset = "1/2"))
  expect_false(
    h$mode_compare(compare_ctx(out, "short", "part-extra"))$identical
  )
})
