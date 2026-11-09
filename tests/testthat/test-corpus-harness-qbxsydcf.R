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

local_corpus <- function(env = parent.frame()) {
  root <- local_test_dir(env)
  for (host in c("a.test", "b.test")) {
    dir.create(file.path(root, host))
    saveRDS(
      list(fetch_outcome = "fetched", body = body_of(host)),
      file.path(root, host, "robots.rds")
    )
  }
  dir.create(file.path(root, "c.test"))
  root
}

test_that("a file changed or vanished mid-run makes the run invalid", {
  h <- load_harness()
  corpus <- local_corpus()
  hosts <- h$list_host_dirs(corpus)
  start <- h$corpus_manifest(corpus, hosts)
  expect_identical(start$host, c("a.test", "b.test"))
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

  unlink(file.path(corpus, "b.test", "robots.rds"))
  gone <- h$verify_run_inputs(start, start, h$corpus_manifest(corpus, hosts))
  expect_setequal(gone$changes$change, c("changed", "vanished"))

  # The bytes processed are checked too, apart from the end manifest.
  during <- start[1L, , drop = FALSE]
  mid <- h$verify_run_inputs(start, during, start)
  expect_false(mid$valid)
  expect_false(mid$during_ok)
  expect_identical(mid$changes$host, "b.test")
})

test_that("comparing runs with different input sets fails before diffing", {
  h <- load_harness()
  m <- data.frame(
    host = c("a.test", "b.test"), rds_sha256 = c("1", "2"),
    rds_bytes = c(1L, 1L), stringsAsFactors = FALSE
  )
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
  for (id in c("ra", "rb")) {
    dir.create(file.path(out, id, "shards"), recursive = TRUE)
    saveRDS(
      list(run_id = id, status = "finished", params = list(
        mode = "validate", seed = 1L, chunk_size = 1L, max_rule_paths = 1L,
        random_paths = 1L, subset = NA_character_, max_hosts = NA_integer_
      )),
      file.path(out, id, "record.rds")
    )
    saveRDS(data.frame(x = 1L), file.path(out, id, "shards", "files-00001.rds"))
  }
  saveRDS(m, file.path(out, "ra", "manifest.rds"))
  saveRDS(m2, file.path(out, "rb", "manifest.rds"))
  ctx <- list(out = out, run_dir = file.path(out, "cmp"),
              opts = list(a = "ra", b = "rb"))
  dir.create(ctx$run_dir)
  expect_refusal(h$mode_compare(ctx), "different input")
  expect_false(file.exists(file.path(ctx$run_dir, "compare-summary.rds")))
  saveRDS(m, file.path(out, "rb", "manifest.rds"))
  res <- h$mode_compare(ctx)
  expect_true(res$identical)
})
