# Evaluator URL preprocessing for the v1 facades (ROBO-bnvdmdjr;
# design/adr/0002-evaluator-url-preprocessing.md).
#
# evaluate_rows_v1() builds one matcher URL per row from the input URL and
# hands it to the backend; the `url` column keeps the input. The extractors
# below it stay byte-transparent (BI-V2-TARGET holds at that boundary). The
# legacy functions never come here (design/PRD.md section 6.2).
#
#   "rfc3986"  RFC 3986 section 5.2.4 remove_dot_segments on the path, the
#              authority split the RFC 3986 way so userinfo is left out, the
#              fragment dropped. No byte is encoded, decoded or case-folded:
#              `%2e` is not a dot here. Input that is not a valid RFC 3986
#              URI is still evaluated; the note says why it is not.
#   "whatwg"   The WHATWG URL Standard serialization through rurl, with no
#              cherry-picking: literal and encoded dot segments removed, and
#              the encoding and host changed as the standard says. The path
#              and query are taken from rurl's result, with userinfo left
#              out and the fragment dropped. Input rurl cannot parse is
#              evaluated as given, with a note.
#   "none"     The URL as given, byte for byte.
#
# Whatever the mode, every row also carries `preprocessing_disagreement`:
# whether the rfc3986 and whatwg targets decide differently, or whatwg
# cannot parse the URL (url_disagreement_v1()).

# The `url_normalization` value set, default first. Adding a mode is one
# entry here and one branch in preprocess_matcher_url_v1().
engine_url_normalizations_v1 <- function() {
  c("rfc3986", "whatwg", "none")
}

validate_url_normalization_v1 <- function(url_normalization) {
  modes <- engine_url_normalizations_v1()
  if (!is.character(url_normalization) || length(url_normalization) != 1L ||
        is.na(url_normalization) || !url_normalization %in% modes) {
    robots_abort(
      sprintf(
        "`url_normalization` must be one of %s.",
        paste0("\"", modes, "\"", collapse = ", ")
      ),
      "robotstxtr_invalid_url_normalization"
    )
  }
  unname(url_normalization)
}

# One matcher URL and one note per row, under the selected mode, and the
# rfc3986 and whatwg targets the disagreement flag compares, whatever the
# mode. `whatwg_failed` marks the rows rurl could not parse. NA and empty
# URLs pass as they are, with no note, in every mode.
preprocess_matcher_url_v1 <- function(url, url_normalization) {
  rfc3986 <- rfc3986_matcher_urls_v1(url)
  whatwg <- whatwg_matcher_urls_v1(url)
  selected <- switch(
    url_normalization,
    rfc3986 = rfc3986,
    whatwg = whatwg,
    none = list(url = url, note = rep(NA_character_, length(url)))
  )
  list(
    matcher_url = selected$url, note = selected$note,
    rfc3986_url = rfc3986$url, whatwg_url = whatwg$url,
    whatwg_failed = whatwg$failed
  )
}

rfc3986_matcher_urls_v1 <- function(url) {
  out <- url
  note <- rep(NA_character_, length(url))
  for (i in which(!is.na(url) & nzchar(url))) {
    row <- rfc3986_matcher_url_v1(url[[i]])
    out[[i]] <- row$url
    note[[i]] <- row$note
  }
  list(url = out, note = note)
}

# ---- "whatwg" ---------------------------------------------------------------

# rurl's WHATWG serialization of each URL, NA where it cannot parse one. A
# latin1 URL is handed over as UTF-8; a "bytes"-marked one has no characters
# to parse, so it is NA. An error on the vector is retried URL by URL, so one
# bad URL fails alone.
whatwg_serialize_v1 <- function(url) {
  out <- rep(NA_character_, length(url))
  ok <- Encoding(url) != "bytes"
  if (!any(ok)) {
    return(out)
  }
  serialize <- function(x) {
    out <- tryCatch(
      as.character(rurl::serialize_url(x, standard = "whatwg")),
      error = function(e) NULL
    )
    if (length(out) == length(x)) out else NULL
  }
  input <- enc2utf8(url[ok])
  serialized <- serialize(input)
  if (is.null(serialized)) {
    serialized <- vapply(input, function(x) {
      one <- serialize(x)
      if (is.null(one)) NA_character_ else one
    }, "", USE.NAMES = FALSE)
  }
  out[ok] <- serialized
  out
}

whatwg_matcher_urls_v1 <- function(url) {
  out <- url
  note <- rep(NA_character_, length(url))
  failed <- rep(FALSE, length(url))
  todo <- which(!is.na(url) & nzchar(url))
  serialized <- whatwg_serialize_v1(url[todo])
  for (k in seq_along(todo)) {
    i <- todo[[k]]
    if (is.na(serialized[[k]])) {
      failed[[i]] <- TRUE
      note[[i]] <- "not a valid WHATWG URL: evaluated as given"
      next
    }
    row <- whatwg_matcher_url_v1(url[[i]], serialized[[k]])
    out[[i]] <- row$url
    note[[i]] <- row$note
  }
  list(url = out, note = note, failed = failed)
}

# scheme, "//" and host[:port] when there is an authority, then the path and
# the query: the URL a backend receives, userinfo and fragment left out.
url_rebuild_v1 <- function(parts) {
  host <- if (parts$has_authority) {
    c(charToRaw("//"), url_host_port_v1(parts$authority))
  }
  c(parts$scheme, host, parts$path, parts$query)
}

# One URL under "whatwg", from rurl's serialization of it: the rebuilt URL
# and its note. The note compares the rebuilt URL with the input read the
# same way (userinfo and fragment left out), so it names what the
# serialization changed apart from those two.
whatwg_matcher_url_v1 <- function(url, serialized) {
  input <- charToRaw(url)
  parts <- url_split_rfc3986_v1(charToRaw(serialized))
  rebuilt <- url_rebuild_v1(parts)
  if (identical(rebuilt, input)) {
    return(list(url = url, note = NA_character_))
  }
  given <- url_split_rfc3986_v1(input)
  userinfo <- given$has_authority &&
    !identical(url_host_port_v1(given$authority), given$authority)
  note <- c(
    if (!identical(rebuilt, url_rebuild_v1(given))) {
      "WHATWG URL serialization changed the URL"
    },
    if (userinfo) "userinfo removed",
    if (given$fragment) "fragment dropped"
  )
  list(url = rawToChar(rebuilt), note = paste(note, collapse = "; "))
}

# ---- the disagreement flag ---------------------------------------------------

# The client families on each side of the flag (ADR 0002, client survey of
# 2026-11-19, curl boundary from curl 8.13.0's changelog). Clients that send
# the URL unchanged are on neither side: the flag compares two forms.
url_client_families_v1 <- function() {
  c(
    rfc3986 = "wget 1.25, curl/libcurl < 8.13.0",
    whatwg = "Chrome 157, Node 26 fetch, curl/libcurl >= 8.13.0"
  )
}

# Whether two character vectors hold the same bytes, element by element; NA
# equals NA only.
bytes_equal_v1 <- function(a, b) {
  vapply(seq_along(a), function(i) {
    if (is.na(a[[i]]) || is.na(b[[i]])) {
      return(is.na(a[[i]]) && is.na(b[[i]]))
    }
    identical(charToRaw(a[[i]]), charToRaw(b[[i]]))
  }, logical(1L))
}

# The decision of `rows` when the matcher reads `target`: the selected pass's
# decision where the matcher already read that target, else a pass of
# `decide(rows, urls)` over the rest.
side_decision_v1 <- function(rows, target, matcher_url, decided, decide) {
  out <- decided[rows]
  again <- !bytes_equal_v1(target[rows], matcher_url[rows])
  if (any(again)) {
    out[again] <- decide(rows[again], target[rows[again]])
  }
  out
}

# `preprocessing_disagreement` and `disagreement_clients` for every row.
# The flag is TRUE where whatwg cannot parse the URL, or where the rfc3986
# and whatwg targets differ bytewise and a matcher decides them differently;
# a second matcher pass runs only on those differing matcher rows.
# `url_decision` is the selected pass's; `decide(rows, urls)` returns the
# url_decision of `rows` when the matcher reads `urls`.
url_disagreement_v1 <- function(preprocessed, matcher_rows, url_decision,
                                decide) {
  failed <- preprocessed$whatwg_failed
  flag <- failed
  clients <- rep(NA_character_, length(flag))
  families <- url_client_families_v1()
  clients[failed] <- sprintf(
    "rfc3986: %s; whatwg cannot parse the URL: %s",
    families[["rfc3986"]], families[["whatwg"]]
  )
  differ <- !failed & !bytes_equal_v1(
    preprocessed$rfc3986_url, preprocessed$whatwg_url
  )
  rows <- matcher_rows[differ[matcher_rows]]
  if (length(rows) == 0L) {
    return(list(flag = flag, clients = clients))
  }
  sides <- lapply(
    preprocessed[c("rfc3986_url", "whatwg_url")], side_decision_v1,
    rows = rows, matcher_url = preprocessed$matcher_url,
    decided = url_decision, decide = decide
  )
  apart <- !mapply(identical, sides[[1L]], sides[[2L]], USE.NAMES = FALSE)
  shown <- function(x) ifelse(is.na(x), "undecided", x)
  flag[rows[apart]] <- TRUE
  clients[rows[apart]] <- sprintf(
    "rfc3986 %s: %s; whatwg %s: %s",
    shown(sides[[1L]][apart]), families[["rfc3986"]],
    shown(sides[[2L]][apart]), families[["whatwg"]]
  )
  list(flag = flag, clients = clients)
}

# The URL's bytes as written, and the mark a rebuilt string takes. A latin1
# string is worked on in its latin1 bytes and keeps its mark: every byte
# this file looks for is ASCII, and the native bindings convert a latin1
# string to UTF-8 (cpp11) whether or not it was rebuilt.
url_bytes_v1 <- function(url) {
  list(bytes = charToRaw(url), encoding = Encoding(url))
}

# `bytes` from position `from` to the end; raw(0) past the end.
byte_tail_v1 <- function(bytes, from) {
  if (from > length(bytes)) {
    return(raw(0))
  }
  bytes[from:length(bytes)]
}

# The first position holding one of `set`, or NA: one pass over `bytes`.
first_byte_of_v1 <- function(bytes, set) {
  match(TRUE, bytes %in% set)
}

# RFC 3986 Appendix B on raw bytes: `scheme` (with its ":"), whether an
# authority is present and its bytes (without "//"), `path`, `query` (with
# its "?"), and whether a fragment was present. The authority ends at the
# first "/", "?" or "#" (section 3.2).
url_split_rfc3986_v1 <- function(bytes) {
  hash <- match(as.raw(0x23), bytes)
  fragment <- !is.na(hash)
  if (fragment) {
    bytes <- bytes[seq_len(hash - 1L)]
  }
  scheme <- raw(0)
  delim <- first_byte_of_v1(bytes, as.raw(c(0x3a, 0x2f, 0x3f)))
  if (!is.na(delim) && delim > 1L && bytes[[delim]] == as.raw(0x3a)) {
    scheme <- bytes[seq_len(delim)]
    bytes <- byte_tail_v1(bytes, delim + 1L)
  }
  has_authority <- length(bytes) >= 2L &&
    identical(bytes[1:2], charToRaw("//"))
  authority <- raw(0)
  if (has_authority) {
    bytes <- byte_tail_v1(bytes, 3L)
    end <- first_byte_of_v1(bytes, as.raw(c(0x2f, 0x3f)))
    end <- if (is.na(end)) length(bytes) else end - 1L
    authority <- bytes[seq_len(end)]
    bytes <- byte_tail_v1(bytes, end + 1L)
  }
  question <- match(as.raw(0x3f), bytes)
  if (is.na(question)) {
    path <- bytes
    query <- raw(0)
  } else {
    path <- bytes[seq_len(question - 1L)]
    query <- byte_tail_v1(bytes, question)
  }
  list(
    scheme = scheme, has_authority = has_authority, authority = authority,
    path = path, query = query, fragment = fragment
  )
}

# host[:port]: the authority after its last "@" (userinfo cannot hold one).
url_host_port_v1 <- function(authority) {
  at <- which(authority == as.raw(0x40))
  if (length(at) == 0L) {
    return(authority)
  }
  byte_tail_v1(authority, at[[length(at)]] + 1L)
}

# RFC 3986 section 5.2.4 remove_dot_segments, step for step, on raw bytes.
# Only the literal segments "." and ".." are dots; "%2e" is not decoded.
# Each output entry is one segment with its leading "/", so "remove the last
# segment and its preceding /" pops one entry. The output is a preallocated
# stack with a top index, and the slash positions are found in one pass and
# walked forward with the input pointer, so the work is linear in the path
# length: each step moves the pointer forward or ends the loop, and each
# step does a bounded amount of work apart from the segment copy in E, whose
# copies add up to the path length.
remove_dot_segments_v1 <- function(path) {
  n <- length(path)
  if (n == 0L) {
    return(path)
  }
  slash <- as.raw(0x2f)
  dot <- as.raw(0x2e)
  at <- function(i, pattern) {
    k <- length(pattern)
    i + k - 1L <= n && identical(path[i:(i + k - 1L)], pattern)
  }
  rest_is <- function(i, pattern) {
    n - i + 1L == length(pattern) && at(i, pattern)
  }
  slashes <- c(which(path == slash), n + 1L)
  next_slash <- 1L # slashes[next_slash] is the first slash past the pointer
  out <- vector("list", n)
  top <- 0L
  i <- 1L
  while (i <= n) {
    if (at(i, c(dot, dot, slash))) {
      i <- i + 3L # A: "../"
    } else if (at(i, c(dot, slash))) {
      i <- i + 2L # A: "./"
    } else if (at(i, c(slash, dot, slash))) {
      i <- i + 2L # B: "/./" -> "/"
    } else if (rest_is(i, c(slash, dot))) {
      top <- top + 1L # B: "/." -> "/"
      out[[top]] <- slash
      break
    } else if (at(i, c(slash, dot, dot, slash))) {
      top <- max(top - 1L, 0L) # C: "/../" -> "/", pop
      i <- i + 3L
    } else if (rest_is(i, c(slash, dot, dot))) {
      top <- max(top - 1L, 0L) + 1L # C: "/.." -> "/", pop, then push "/"
      out[[top]] <- slash
      break
    } else if (rest_is(i, dot) || rest_is(i, c(dot, dot))) {
      break # D
    } else {
      # E: move the first segment, with its leading "/", to the output.
      while (slashes[[next_slash]] <= i) {
        next_slash <- next_slash + 1L
      }
      end <- slashes[[next_slash]] - 1L
      top <- top + 1L
      out[[top]] <- path[i:end]
      i <- end + 1L
    }
  }
  if (top == 0L) raw(0) else unlist(out[seq_len(top)], use.names = FALSE)
}

# Why `bytes` is not a valid RFC 3986 URI, as the classes found, in a fixed
# order; character(0) when none is. Lexical only: nothing is re-encoded.
rfc3986_invalid_classes_v1 <- function(bytes) {
  code <- as.integer(bytes)
  outside <- c(0x22, 0x3c, 0x3e, 0x5e, 0x60, 0x7b, 0x7c, 0x7d) # "<>^`{|}
  percent <- which(code == 0x25)
  hex <- c(0x30:0x39, 0x41:0x46, 0x61:0x66)
  stray <- vapply(percent, function(p) {
    p + 2L > length(code) || !all(code[p + 1:2] %in% hex)
  }, logical(1L))
  found <- c(
    `raw space` = any(code == 0x20),
    `raw non-ASCII` = any(code >= 0x80),
    backslash = any(code == 0x5c),
    `character outside RFC 3986` = any(code < 0x20 | code == 0x7f) ||
      any(code %in% outside),
    `stray %` = any(stray)
  )
  names(found)[found]
}

# The row note: what is invalid, then the authority, then each change,
# joined by "; "; NA when the input is a valid RFC 3986 URI with an
# authority and preprocessing changed nothing. `no_authority` is "slash"
# (no authority, a "/" in the path), "none" (no authority and no "/") or
# NA (an authority). `dots` is "removed", "kept" (removing them would have
# started the path with "//") or NA (none found).
url_preprocessing_note_v1 <- function(invalid, no_authority, dots, userinfo,
                                      fragment) {
  section <- "\u00a7"
  parts <- c(
    if (length(invalid) > 0L) {
      paste0("not a valid RFC 3986 URI: ", toString(invalid))
    },
    switch(
      no_authority,
      slash = "no authority: path read from the first /",
      none = "no authority and no /: evaluated as given"
    ),
    switch(
      dots,
      removed = if (length(invalid) > 0L) {
        "dot segments removed as given"
      } else {
        paste0("RFC 3986 ", section, "5.2.4 removed dot segments")
      },
      kept = paste0(
        "dot segments left in place: removing them would start the path ",
        "with // (RFC 3986 ", section, "5.2.4)"
      )
    ),
    if (userinfo) paste0("userinfo removed (RFC 3986 ", section, "3.2.1)"),
    if (fragment) paste0("fragment dropped (RFC 3986 ", section, "3.5)")
  )
  if (length(parts) == 0L) NA_character_ else paste(parts, collapse = "; ")
}

# The no-authority reading of `path`: the bytes before its first "/" are
# kept, and the rest is the path the backend reads.
url_path_after_first_slash_v1 <- function(path) {
  slash <- match(as.raw(0x2f), path)
  keep <- if (is.na(slash)) length(path) else slash - 1L
  list(
    lead = path[seq_len(keep)], rest = byte_tail_v1(path, keep + 1L),
    no_authority = if (is.na(slash)) "none" else "slash"
  )
}

# One URL under "rfc3986": the rebuilt URL and its note.
rfc3986_matcher_url_v1 <- function(url) {
  input <- url_bytes_v1(url)
  parts <- url_split_rfc3986_v1(input$bytes)
  userinfo <- FALSE
  no_authority <- NA_character_
  if (parts$has_authority) {
    host <- url_host_port_v1(parts$authority)
    userinfo <- !identical(host, parts$authority)
    lead <- c(parts$scheme, charToRaw("//"), host)
    before <- parts$path
  } else {
    # No authority (the text entry point accepts "/a/../b" and
    # "example.com/a"): the path the backend reads starts at the first "/".
    split <- url_path_after_first_slash_v1(parts$path)
    lead <- c(parts$scheme, split$lead)
    before <- split$rest
    no_authority <- split$no_authority
  }
  path <- remove_dot_segments_v1(before)
  dots <- if (identical(path, before)) NA_character_ else "removed"
  rebuilt <- c(lead, path, parts$query)
  if (!parts$has_authority && identical(dots, "removed") &&
        length(path) >= 2L && identical(path[1:2], charToRaw("//"))) {
    # Removing the dots would turn the path into an authority that the
    # input does not have ("/a/..//h/x" -> "//h/x"): keep the input.
    dots <- "kept"
    rebuilt <- input$bytes
    parts$fragment <- FALSE
  }
  note <- url_preprocessing_note_v1(
    invalid = rfc3986_invalid_classes_v1(input$bytes),
    no_authority = no_authority,
    dots = dots,
    userinfo = userinfo,
    fragment = parts$fragment
  )
  # The rebuilt bytes take the input's mark, so an unchanged URL comes back
  # with its bytes and its mark.
  out <- rawToChar(rebuilt)
  if (!identical(input$encoding, "unknown")) {
    Encoding(out) <- input$encoding
  }
  list(url = out, note = note)
}
