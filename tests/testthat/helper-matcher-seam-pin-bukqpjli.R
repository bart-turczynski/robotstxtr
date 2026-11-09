# The before/after pin of the matcher seam refactor (ROBO-bukqpjli).
#
# The refactor moves every matcher backend behind one batch interface and
# must change no v1 result. These helpers evaluate the synthesized fixtures
# under fixtures/edge-cases/ (and a few synthesized fetch cases: a body cut
# at max_bytes, a body over Google's 512,000-byte window, non-2xx statuses)
# through robots_evaluate_text_v1() and robots_evaluate_url_v1(), every row
# crossed with every ruleset and every matcher backend in ONE call, so rows
# of several backends share a call and must scatter back to their own place.
# Each call's `results` frame is reduced to an MD5 of a canonical text form;
# fixtures/matcher-seam-pin-bukqpjli.csv holds the digests computed on main
# before the refactor.
#
# A change that is MEANT to change v1 results re-pins with
# seam_pin_write(), run from tests/testthat after pkgload::load_all().

seam_pin_file <- function() {
  test_path("fixtures", "matcher-seam-pin-bukqpjli.csv")
}

seam_rulesets <- c("google", "yandex", "rfc9309", "bing", "assumed_rfc9309")
seam_backends <- c("google", "yandex", "rfc9309", "bing")
# Besides each check's own token: the accepted Yandex and Bing selectors, so
# those backends evaluate rather than refuse the profile.
seam_extra_tokens <- c("Yandex", "bingbot", "adidxbot")

seam_hex_bytes <- function(path) {
  hex <- gsub("[[:space:]]", "", paste(readLines(path), collapse = ""))
  starts <- seq(1L, nchar(hex), by = 2L)
  as.raw(strtoi(substring(hex, starts, starts + 1L), 16L))
}

seam_body <- function(dir, file) {
  path <- file.path(dir, file)
  if (endsWith(file, ".hex")) {
    return(seam_hex_bytes(path))
  }
  readBin(path, "raw", file.size(path))
}

# Every (path, token) check crossed with every ruleset and backend, plus two
# input-invalid rows (no URL; an empty token).
seam_rows <- function(paths, tokens) {
  checks <- unique(rbind(
    data.frame(
      path = paths, token = rep_len(tokens, length(paths)),
      stringsAsFactors = FALSE
    ),
    expand.grid(
      path = unique(paths), token = seam_extra_tokens,
      stringsAsFactors = FALSE
    )
  ))
  grid <- expand.grid(
    check = seq_len(nrow(checks)), ruleset = seam_rulesets,
    backend = seam_backends, stringsAsFactors = FALSE
  )
  list(
    path = c(checks$path[grid$check], "/x", "/x"),
    token = c(checks$token[grid$check], "FooBot", ""),
    ruleset = c(grid$ruleset, "google", "yandex"),
    backend = c(grid$backend, "google", "bing"),
    url_ok = c(rep(TRUE, nrow(grid)), FALSE, TRUE)
  )
}

seam_url <- function(origin, rows) {
  url <- paste0(origin, rows$path)
  url[!rows$url_ok] <- NA_character_
  Encoding(url) <- "UTF-8"
  url
}

# One line per column header and per value: the type, the class, the
# encoding mark and the value, NULL and NA spelled out, raw as hex.
seam_canonical <- function(frame) {
  out <- c(sprintf("nrow %d", nrow(frame)))
  for (col in names(frame)) {
    x <- frame[[col]]
    vals <- if (is.list(x)) {
      vapply(x, function(v) {
        if (is.null(v)) {
          "<NULL>"
        } else {
          paste0(typeof(v), ":", paste(as.character(v), collapse = ","))
        }
      }, character(1L))
    } else if (is.character(x)) {
      ifelse(is.na(x), "<NA>", paste0(Encoding(x), "|", x))
    } else {
      ifelse(is.na(x), "<NA>", as.character(x))
    }
    out <- c(
      out,
      sprintf("#%s %s %s", col, typeof(x), paste(class(x), collapse = "/")),
      vals
    )
  }
  out
}

seam_digest <- function(frame) {
  file <- tempfile(fileext = ".txt")
  on.exit(unlink(file))
  con <- file(file, open = "wb")
  writeLines(seam_canonical(frame), con, useBytes = TRUE)
  close(con)
  unname(tools::md5sum(file))
}

seam_text_case <- function(bytes, paths, tokens) {
  rows <- seam_rows(paths, tokens)
  txt <- rawToChar(bytes)
  Encoding(txt) <- "bytes"
  robots_evaluate_text_v1(
    txt, seam_url("https://example.com", rows), rows$token, rows$ruleset,
    rows$backend
  )$results
}

seam_url_case <- function(bytes, paths, tokens, status = 200L,
                          max_bytes = 524288L) {
  rows <- seam_rows(paths, tokens)
  local_fake_ssrfr(function(req) fake_response(status, body = bytes))
  robots_evaluate_url_v1(
    seam_url("http://example.test", rows), rows$token, rows$ruleset,
    rows$backend, max_bytes = max_bytes, fetch_user_agent = "seam-pin/1.0"
  )$results
}

# A synthesized body of `size` bytes: rules, then `#` padding with no line
# break, then (when it fits) a late rule that only an unwindowed read sees.
seam_big_body <- function(size, late = "Allow: /private\n") {
  head <- charToRaw("User-agent: *\nDisallow: /private\n#")
  tail <- charToRaw(paste0("\n", late))
  c(head, rep(charToRaw("#"), size - length(head) - length(tail)), tail)
}

# Every case as a named list of thunks, each returning a results frame.
seam_cases <- function() {
  dir <- test_path("fixtures", "edge-cases")
  m <- utils::read.csv(
    file.path(dir, "manifest.csv"),
    colClasses = "character", na.strings = character(),
    encoding = "UTF-8", check.names = FALSE
  )
  fixture_cases <- function(file) {
    checks <- m[m$body_file == file, , drop = FALSE]
    b <- seam_body(dir, file)
    p <- checks$path
    t <- checks$token
    out <- list()
    # An R string cannot hold a NUL: such a body goes through the fetch only.
    if (!any(b == as.raw(0))) {
      out[[paste0("text:", file)]] <- function() seam_text_case(b, p, t)
    }
    out[[paste0("url:", file)]] <- function() seam_url_case(b, p, t)
    out
  }
  cases <- unlist(
    lapply(unique(m$body_file), fixture_cases),
    recursive = FALSE
  )
  paths <- c("/private", "/public")
  tokens <- "FooBot"
  small <- charToRaw("User-agent: *\nDisallow: /private\n")
  synthesized <- list(
    "url:cut-at-default-max-bytes" = function() {
      seam_url_case(seam_big_body(600000L), paths, tokens)
    },
    "url:cut-at-512000" = function() {
      seam_url_case(seam_big_body(600000L), paths, tokens,
                    max_bytes = 512000L)
    },
    "url:cut-below-window" = function() {
      seam_url_case(seam_big_body(300000L), paths, tokens,
                    max_bytes = 200000L)
    },
    "url:over-google-window-uncut" = function() {
      seam_url_case(seam_big_body(520000L), paths, tokens,
                    max_bytes = 1000000L)
    },
    "url:status-206" = function() {
      seam_url_case(small, paths, tokens, status = 206L)
    },
    "url:status-404" = function() {
      seam_url_case(small, paths, tokens, status = 404L)
    },
    "url:status-503" = function() {
      seam_url_case(small, paths, tokens, status = 503L)
    },
    "text:several-tokens" = function() {
      seam_text_case(
        small, c(paths, "/private/x"), c("FooBot", "Googlebot", "FooBot")
      )
    }
  )
  c(cases, synthesized)
}

seam_pin_compute <- function() {
  cases <- seam_cases()
  data.frame(
    case = names(cases),
    md5 = vapply(cases, function(f) seam_digest(f()), character(1L)),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

seam_pin_write <- function() {
  utils::write.csv(seam_pin_compute(), seam_pin_file(), row.names = FALSE)
}

seam_pin_read <- function() {
  utils::read.csv(
    seam_pin_file(), colClasses = "character", check.names = FALSE
  )
}
