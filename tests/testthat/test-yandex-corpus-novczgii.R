# Tests for the offline Yandex conformance corpus projection (ROBO-novczgii).
#
# The committed fixtures under inst/yandex-corpus/ are never mutated: every
# fail-closed test operates on a fresh copy in a tempdir.

skip_if_not_installed("jsonlite")

corpus_dir <- function() {
  yandex_corpus_dir()
}

# Copy the corpus into a fresh tempdir so mutation tests never touch the
# committed fixtures.
copy_corpus <- function() {
  src <- corpus_dir()
  dest <- file.path(tempfile("yandex-corpus-"))
  dir.create(file.path(dest, "bodies"), recursive = TRUE)
  file.copy(file.path(src, "cases.json"), file.path(dest, "cases.json"))
  file.copy(file.path(src, "PROVENANCE.dcf"), file.path(dest, "PROVENANCE.dcf"))
  for (f in list.files(file.path(src, "bodies"), full.names = TRUE)) {
    file.copy(f, file.path(dest, "bodies", basename(f)))
  }
  dest
}

test_that("the committed corpus verifies clean and offline", {
  res <- verify_yandex_corpus(corpus_dir())
  expect_true(res$ok)
  expect_equal(res$n_records, 140L)
  expect_equal(res$n_bodies, 26L)
  expect_length(res$errors, 0L)
})

test_that("corpus content matches the recorded invariants", {
  records <- read_yandex_corpus(corpus_dir())
  expect_length(records, 140L)

  crawlers <- vapply(records, function(r) r$crawler, character(1))
  expect_setequal(unique(crawlers), c("Yandex", "YandexAdditionalBot"))
  expect_equal(sum(crawlers == "Yandex"), 119L)
  expect_equal(sum(crawlers == "YandexAdditionalBot"), 21L)

  body_ids <- vapply(records, function(r) r$body_id, character(1))
  expect_length(unique(body_ids), 26L)

  case_ids <- vapply(records, function(r) r$case_id, character(1))
  expect_false(anyDuplicated(case_ids) > 0L)

  # matched_rule is null iff source == "default_allow".
  for (r in records) {
    is_default <- identical(r$expected$source, "default_allow")
    is_null <- is.null(r$expected$matched_rule)
    expect_equal(is_null, is_default)
    expect_true(r$expected$source %in% c(
      "default_allow", "rule_allow", "rule_disallow",
      "effective_empty_disallow"
    ))
  }

  # An empty matched_rule value (effective_empty_disallow) is distinct from a
  # null matched_rule (default_allow).
  empty_val <- Filter(
    function(r) identical(r$expected$source, "effective_empty_disallow"),
    records
  )
  expect_gt(length(empty_val), 0L)
  for (r in empty_val) {
    expect_false(is.null(r$expected$matched_rule))
    expect_identical(r$expected$matched_rule$value, "")
  }
})

test_that("every body file's SHA-256 matches its record", {
  dir <- corpus_dir()
  records <- read_yandex_corpus(dir)
  for (r in records) {
    path <- file.path(dir, r$body_file)
    expect_true(file.exists(path))
    expect_identical(
      yandex_corpus_sha256_file(path),
      tolower(r$body_sha256)
    )
  }
})

test_that("re-serialization is byte-identical to the committed cases.json", {
  dir <- corpus_dir()
  records <- read_yandex_corpus(dir)
  produced <- charToRaw(enc2utf8(yandex_corpus_serialize(records)))
  cases_path <- file.path(dir, "cases.json")
  committed <- readBin(cases_path, "raw", n = file.size(cases_path))
  expect_identical(produced, committed)
})

# ---- Fail-closed mutation tests (operate on a copy) -------------------------

test_that("dropping a case fails verification", {
  dir <- copy_corpus()
  on.exit(unlink(dir, recursive = TRUE))
  records <- read_yandex_corpus(dir)
  writeBin(
    charToRaw(enc2utf8(yandex_corpus_serialize(records[-1L]))),
    file.path(dir, "cases.json")
  )
  expect_false(verify_yandex_corpus(dir)$ok)
})

test_that("adding a 141st case fails verification", {
  dir <- copy_corpus()
  on.exit(unlink(dir, recursive = TRUE))
  records <- read_yandex_corpus(dir)
  extra <- records[[1L]]
  extra$case_id <- "zzz-synthetic-extra-case"
  writeBin(
    charToRaw(enc2utf8(yandex_corpus_serialize(c(records, list(extra))))),
    file.path(dir, "cases.json")
  )
  expect_false(verify_yandex_corpus(dir)$ok)
})

test_that("corrupting one body byte fails verification", {
  dir <- copy_corpus()
  on.exit(unlink(dir, recursive = TRUE))
  records <- read_yandex_corpus(dir)
  body_path <- file.path(dir, records[[1L]]$body_file)
  bytes <- readBin(body_path, "raw", n = file.size(body_path))
  bytes[[1L]] <- as.raw(bitwXor(as.integer(bytes[[1L]]), 1L))
  writeBin(bytes, body_path)
  expect_false(verify_yandex_corpus(dir)$ok)
})

test_that("flipping a recorded sha256 fails verification", {
  dir <- copy_corpus()
  on.exit(unlink(dir, recursive = TRUE))
  raw <- readLines(file.path(dir, "cases.json"), warn = FALSE)
  idx <- grep("\"body_sha256\"", raw, fixed = TRUE)[[1L]]
  raw[[idx]] <- sub(
    "[0-9a-f]{64}",
    strrep("0", 64L),
    raw[[idx]]
  )
  writeBin(charToRaw(enc2utf8(paste0(paste(raw, collapse = "\n"), "\n"))),
           file.path(dir, "cases.json"))
  expect_false(verify_yandex_corpus(dir)$ok)
})

test_that("nulling a non-default_allow matched_rule fails verification", {
  dir <- copy_corpus()
  on.exit(unlink(dir, recursive = TRUE))
  records <- read_yandex_corpus(dir)
  target <- which(vapply(
    records, function(r) !identical(r$expected$source, "default_allow"),
    logical(1)
  ))[[1L]]
  records[[target]]$expected$matched_rule <- NULL
  # Serialize by hand so the null survives (build_record would reject the
  # mismatch shape only via verify, not serialization).
  writeBin(
    charToRaw(enc2utf8(yandex_corpus_serialize(records))),
    file.path(dir, "cases.json")
  )
  expect_false(verify_yandex_corpus(dir)$ok)
})

# ---- Data-only proof: nothing about availability or schema changed ----------

test_that("Yandex is available and the schema revision is the activation one", {
  registry <- engine_matcher_registry_v1()
  expect_identical(registry$yandex$availability, "available")
  expect_type(registry$yandex$callable, "closure")
  expect_identical(engine_schema_revision_v1(), "2026-07-18.2")
})
