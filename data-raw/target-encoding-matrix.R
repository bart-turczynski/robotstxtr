# Target-encoding matrix (ROBO-tvcnkkdi; design/target-encoding-matrix.md).
#
# Evaluates one unchanged robots.txt body against every target spelling
# below, under every url_normalization mode and the google, bing and yandex
# backends, through the public robots_evaluate_text_v1(). Prints the
# Markdown tables that design/target-encoding-matrix.md embeds between its
# "matrix:begin" and "matrix:end" markers.
#
# Run from the package root, or pass the root as the first argument:
#   Rscript data-raw/target-encoding-matrix.R [root] > <scratch>/matrix.md
# The output is byte-identical across runs and locales: every byte outside
# printable ASCII, and `|`, is shown as <HH>. Synthetic fixtures on
# example.com only.

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args) > 0L) args[[1L]] else "."
pkgload::load_all(root, quiet = TRUE, export_all = FALSE)

body_lines <- c(
  "User-agent: *",
  "Disallow: /r/café",
  "Disallow: /e/caf%C3%A9",
  "Disallow: /c/café",
  "Disallow: /y/кат",
  "Disallow: /j/路",
  "Disallow: /h/a%3Cb",
  "Disallow: /l/a%3cb",
  "Disallow: /s/a%2Fb",
  "Disallow: /p/a/b",
  "Disallow: /t/~joe",
  "Disallow: /u/%7Ejoe",
  "Disallow: /w/a%20b",
  "Disallow: /v/a b",
  "Disallow: /k/",
  "Disallow: /d/a%252eb",
  "Disallow: /b/a/",
  "Disallow: /B/a\\b",
  "Disallow: /q?k=a%20b",
  "Disallow: /q?a='x'",
  "Disallow: /q?n=caf%C3%A9"
)
# Mark every string UTF-8 explicitly: a `\u` escape parsed under LC_ALL=C
# can come out unmarked, and an unmarked non-ASCII URL reaches the bing and
# yandex adapters through the native-encoding translation (see the matrix
# doc, "Adapter extraction"). Marking keeps the table locale-independent.
mark_utf8 <- function(x) {
  Encoding(x) <- "UTF-8"
  x
}
body_lines <- mark_utf8(body_lines)
body <- mark_utf8(paste0(paste(body_lines, collapse = "\n"), "\n"))

# id, spelling family, target path (appended to https://example.com).
targets <- matrix(ncol = 3L, byrow = TRUE, c(
  "r1", "raw Latin-1 range, raw rule", "/r/café",
  "r2", "raw Latin-1 range, escaped rule", "/e/café",
  "r3", "upper escape, raw rule", "/r/caf%C3%A9",
  "r4", "upper escape, escaped rule", "/e/caf%C3%A9",
  "r5", "lower escape, raw rule", "/r/caf%c3%a9",
  "r6", "lower escape, escaped rule", "/e/caf%c3%a9",
  "r7", "mixed escape, raw rule", "/r/caf%C3%a9",
  "r8", "mixed escape, escaped rule", "/e/caf%C3%a9",
  "c1", "raw combining mark", "/c/café",
  "c2", "escaped combining mark", "/c/cafe%CC%81",
  "c3", "precomposed form of a combining rule", "/c/café",
  "y1", "raw Cyrillic", "/y/кат",
  "y2", "escaped Cyrillic", "/y/%D0%BA%D0%B0%D1%82",
  "j1", "raw CJK", "/j/路",
  "j2", "escaped CJK", "/j/%E8%B7%AF",
  "h1", "lower ASCII escape, upper rule", "/h/a%3cb",
  "h2", "upper ASCII escape, upper rule", "/h/a%3Cb",
  "h3", "lower ASCII escape, lower rule", "/l/a%3cb",
  "h4", "upper ASCII escape, lower rule", "/l/a%3Cb",
  "s1", "%2F target, %2F rule", "/s/a%2Fb",
  "s2", "/ target, %2F rule", "/s/a/b",
  "s3", "%2F target, / rule", "/p/a%2Fb",
  "s4", "lower %2f target, %2F rule", "/s/a%2fb",
  "t1", "~ target, ~ rule", "/t/~joe",
  "t2", "%7E target, ~ rule", "/t/%7Ejoe",
  "t3", "%7e target, ~ rule", "/t/%7ejoe",
  "t4", "~ target, %7E rule", "/u/~joe",
  "w1", "raw space, %20 rule", "/w/a b",
  "w2", "%20, %20 rule", "/w/a%20b",
  "w3", "raw space, raw-space rule", "/v/a b",
  "w4", "%20, raw-space rule", "/v/a%20b",
  "d1", "double encoding, control", "/d/a%252eb",
  "d2", "double-encoded dot segment", "/d/%252e%252e/k/x",
  "d3", "single-encoded dot segment", "/d/%2e%2e/k/x",
  "b1", "backslash, / rule", "/b/a\\b",
  "b2", "backslash, backslash rule", "/B/a\\b",
  "q1", "query raw space", "/q?k=a b",
  "q2", "query apostrophe", "/q?a='x'",
  "q3", "query raw non-ASCII", "/q?n=café",
  "k1", "ASCII control", "/k/x",
  "k2", "ASCII control, no rule", "/z/x"
))
targets <- rbind(
  targets,
  c("i1", "invalid UTF-8 byte (unmarked)",
    rawToChar(as.raw(c(0x2f, 0x72, 0x2f, 0x63, 0x61, 0x66, 0xe9))))
)
colnames(targets) <- c("id", "family", "path")
valid <- targets[, "id"] != "i1"
targets[valid, "path"] <- mark_utf8(targets[valid, "path"])

backends <- c(google = "Googlebot", bing = "bingbot", yandex = "Yandex")
modes <- c("none", "rfc3986", "whatwg")

show_bytes <- function(x) {
  if (is.na(x)) {
    return("NA")
  }
  b <- as.integer(charToRaw(x))
  out <- vapply(b, function(v) {
    if (v > 0x20L && v < 0x7fL && v != 0x7cL) {
      rawToChar(as.raw(v))
    } else {
      sprintf("<%02X>", v)
    }
  }, character(1L))
  paste(out, collapse = "")
}

strip_origin <- function(x) {
  sub("^https://example\\.com", "", x, useBytes = TRUE)
}

evaluate_cell <- function(url, backend, mode) {
  tryCatch(
    {
      res <- robots_evaluate_text_v1(
        body, url,
        robots_product_token = backends[[backend]],
        robots_policy_ruleset = backend,
        matcher_backend = backend,
        source_id = "target-encoding-matrix",
        url_normalization = mode
      )$results
      list(
        ok = TRUE,
        decision = res$url_decision,
        status = res$matcher_status,
        line = res$matched_line,
        matcher_url = res$matcher_url,
        note = res$url_preprocessing_note,
        revision = res$matcher_backend_revision
      )
    },
    error = function(e) list(ok = FALSE, class = class(e)[[1L]])
  )
}

format_cell <- function(cell) {
  if (!cell$ok) {
    return(paste0("error: ", cell$class))
  }
  if (is.na(cell$decision)) {
    return(cell$status)
  }
  letter <- if (identical(cell$decision, "disallow")) "D" else "A"
  if (is.na(cell$line)) letter else paste0(letter, ":", cell$line)
}

urls <- paste0("https://example.com", targets[, "path"])
urls[valid] <- mark_utf8(urls[valid])
cells <- list()
revisions <- character()
for (backend in names(backends)) {
  for (mode in modes) {
    key <- paste(backend, mode)
    cells[[key]] <- lapply(urls, evaluate_cell, backend = backend,
                           mode = mode)
    ok <- Filter(function(cell) cell$ok, cells[[key]])
    revisions[[backend]] <- ok[[1L]]$revision
  }
}

# The preprocessing sits above every backend: the matcher URL must not
# depend on the backend. Stop rather than print a table that hides it.
for (mode in modes) {
  forms <- lapply(names(backends), function(backend) {
    vapply(cells[[paste(backend, mode)]], function(cell) {
      if (cell$ok) show_bytes(cell$matcher_url) else "error"
    }, character(1L))
  })
  if (!identical(forms[[1L]], forms[[2L]]) ||
        !identical(forms[[1L]], forms[[3L]])) {
    stop("matcher_url differs between backends under ", mode, call. = FALSE)
  }
}

cat("<!-- matrix:begin -->\n\n")
cat("Generated by `data-raw/target-encoding-matrix.R`.\n\n")
cat("- robotstxtr ", as.character(utils::packageVersion("robotstxtr")),
    "; rurl ", as.character(utils::packageVersion("rurl")), "\n", sep = "")
for (backend in names(revisions)) {
  cat("- ", backend, " backend: `", revisions[[backend]], "`\n", sep = "")
}
cat("- tokens: ", paste0("`", backends, "` (", names(backends), ")",
                         collapse = ", "), "; ruleset = backend\n\n", sep = "")

cat("Body (`User-agent: *` group; line numbers as the matchers report",
    "them):\n\n")
cat("| Line | Bytes |\n|---|---|\n")
for (i in seq_along(body_lines)) {
  cat("| ", i, " | `", show_bytes(body_lines[[i]]), "` |\n", sep = "")
}

cat("\nTarget the matcher reads, per mode (the backend does not change it).",
    "`none` is the input as given.\n\n")
cat("| Id | Spelling | Input path | rfc3986 | whatwg |\n")
cat("|---|---|---|---|---|\n")
target_cell <- function(cell) {
  if (!cell$ok) {
    return(paste0("error: ", cell$class))
  }
  out <- paste0("`", show_bytes(strip_origin(cell$matcher_url)), "`")
  if (is.na(cell$note)) out else paste0(out, " (", cell$note, ")")
}
for (i in seq_len(nrow(targets))) {
  cat("| ", targets[i, "id"], " | ", targets[i, "family"], " | `",
      show_bytes(targets[i, "path"]), "` | ",
      target_cell(cells[["google rfc3986"]][[i]]), " | ",
      target_cell(cells[["google whatwg"]][[i]]), " |\n", sep = "")
}

cat("\nDecision per backend and mode. `D:n` disallowed by line n, `A` allowed",
    "by default, otherwise the matcher status or the call error.\n\n")
heads <- unlist(lapply(names(backends), paste, modes))
cat("| Id | ", paste(heads, collapse = " | "), " |\n", sep = "")
cat("|---|", strrep("---|", length(heads)), "\n", sep = "")
for (i in seq_len(nrow(targets))) {
  row <- vapply(heads, function(key) format_cell(cells[[key]][[i]]),
                character(1L))
  cat("| ", targets[i, "id"], " | ", paste(row, collapse = " | "), " |\n",
      sep = "")
}
cat("\n<!-- matrix:end -->\n")
