# Tests for the fail-closed vendored-payload verifier (ROBO-zfhakxcn, YI2).
#
# These tests are driven entirely by self-consistent synthetic fixtures in a
# temp dir. They do NOT depend on the sibling robotstxtyandex checkout, on the
# network, or on any real vendored tree (none exists yet at this slice).

# The verifier relies on tools::sha256sum (R >= 4.5.0); skip cleanly otherwise.
skip_if_no_sha256 <- function() {
  skip_if_not(
    exists("sha256sum", where = asNamespace("tools"), inherits = FALSE),
    "tools::sha256sum() unavailable (needs R >= 4.5.0)"
  )
}

# Base-R temp directory, cleaned up when the calling test frame exits. Avoids a
# withr dependency (this epic minimizes dependency footprint). The literal path
# is substituted into the deferred unlink, so cleanup is independent of caller
# variable names.
local_tmpdir <- function(envir = parent.frame()) {
  tmp <- tempfile("robotstxtr-vendor-")
  dir.create(tmp)
  do.call(
    "on.exit",
    list(bquote(unlink(.(tmp), recursive = TRUE, force = TRUE)), add = TRUE),
    envir = envir
  )
  tmp
}

# Build a synthetic vendor tree plus a matching DCF manifest under `dir`.
# Returns list(root = <tree dir>, manifest = <dcf path>, files = named chr of
# relative-path -> content).
make_fixture <- function(dir, vendor_root = "vendorx") {
  root <- file.path(dir, "tree")
  contents <- c(
    "include/pkg/a.h" = "public header alpha\n",
    "src/b.cc" = "translation unit beta\n",
    "src/b.h" = "private header beta\n",
    "LICENSE" = "MIT-ish synthetic license\n"
  )
  rel_paths <- names(contents)
  for (rel in rel_paths) {
    target <- file.path(root, rel)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    writeLines(sub("\n$", "", contents[[rel]]), target)
  }
  shas <- vapply(
    rel_paths,
    function(rel) unname(tolower(tools::sha256sum(file.path(root, rel)))),
    character(1)
  )

  manifest <- file.path(dir, "MANIFEST.dcf")
  header <- c(
    "Manifest: synthetic",
    paste0("VendorRoot: ", vendor_root),
    ""
  )
  records <- vapply(seq_along(rel_paths), function(i) {
    paste(
      paste0("File: ", vendor_root, "/", rel_paths[i]),
      paste0("Sha256: ", shas[i]),
      "",
      sep = "\n"
    )
  }, character(1))
  writeLines(c(header, records), manifest)

  list(root = root, manifest = manifest, contents = contents)
}

test_that("matching tree passes (positive case)", {
  skip_if_no_sha256()
  tmp <- local_tmpdir()
  fx <- make_fixture(tmp)

  res <- verify_yandex_vendor_tree(fx$root, fx$manifest)

  expect_s3_class(res, "yandex_vendor_verification")
  expect_true(res$ok)
  expect_equal(res$n_expected, length(fx$contents))
  expect_length(res$missing, 0)
  expect_length(res$extra, 0)
  expect_length(res$mismatched, 0)
  expect_length(res$matched, length(fx$contents))
})

test_that("missing file fails closed", {
  skip_if_no_sha256()
  tmp <- local_tmpdir()
  fx <- make_fixture(tmp)
  file.remove(file.path(fx$root, "src", "b.cc"))

  res <- verify_yandex_vendor_tree(fx$root, fx$manifest)

  expect_false(res$ok)
  expect_true("src/b.cc" %in% res$missing)
  expect_length(res$extra, 0)
  expect_length(res$mismatched, 0)
})

test_that("extra / package-owned file fails closed", {
  skip_if_no_sha256()
  tmp <- local_tmpdir()
  fx <- make_fixture(tmp)
  writeLines("package-owned binding", file.path(fx$root, "src", "glue.cpp"))

  res <- verify_yandex_vendor_tree(fx$root, fx$manifest)

  expect_false(res$ok)
  expect_true("src/glue.cpp" %in% res$extra)
  expect_length(res$missing, 0)
  expect_length(res$mismatched, 0)
})

test_that("changed / corrupted file fails closed", {
  skip_if_no_sha256()
  tmp <- local_tmpdir()
  fx <- make_fixture(tmp)
  writeLines("tampered content", file.path(fx$root, "include", "pkg", "a.h"))

  res <- verify_yandex_vendor_tree(fx$root, fx$manifest)

  expect_false(res$ok)
  expect_true("include/pkg/a.h" %in% res$mismatched)
  expect_length(res$missing, 0)
  expect_length(res$extra, 0)
})

test_that("multiple simultaneous anomalies all report", {
  skip_if_no_sha256()
  tmp <- local_tmpdir()
  fx <- make_fixture(tmp)
  file.remove(file.path(fx$root, "LICENSE"))
  writeLines("tampered", file.path(fx$root, "src", "b.h"))
  writeLines("stray", file.path(fx$root, "stray.txt"))

  res <- verify_yandex_vendor_tree(fx$root, fx$manifest)

  expect_false(res$ok)
  expect_true("LICENSE" %in% res$missing)
  expect_true("src/b.h" %in% res$mismatched)
  expect_true("stray.txt" %in% res$extra)
})

test_that("missing manifest fails closed with an error", {
  skip_if_no_sha256()
  tmp <- local_tmpdir()
  fx <- make_fixture(tmp)

  expect_error(
    verify_yandex_vendor_tree(fx$root, file.path(tmp, "no-such.dcf")),
    "manifest not found"
  )
})

test_that("missing tree directory fails closed with an error", {
  skip_if_no_sha256()
  tmp <- local_tmpdir()
  fx <- make_fixture(tmp)

  expect_error(
    verify_yandex_vendor_tree(file.path(tmp, "no-such-dir"), fx$manifest),
    "directory not found"
  )
})

test_that("shipped manifest is well-formed and self-describing", {
  skip_if_no_sha256()
  manifest <- yandex_vendor_manifest_path()
  skip_if(identical(manifest, ""), "installed manifest not found")

  parsed <- read_yandex_vendor_manifest(manifest)
  expect_equal(parsed$vendor_root, "src/vendor/robotstxtyandex")
  expect_equal(nrow(parsed$files), 21L)
  expect_true(all(nchar(parsed$files$sha256) == 64L))
  expect_equal(
    parsed$header[["PayloadCommit"]],
    "fdd60a7c3bc6825f3b3752562dc0d6ad9387a27e"
  )
  expect_equal(parsed$header[["ProfileId"]], "yandex-0.1.0")
  expect_equal(parsed$header[["LibraryVersion"]], "0.2.0")
})
