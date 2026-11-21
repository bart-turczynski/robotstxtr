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
#   "none"     The URL as given, byte for byte.

# The `url_normalization` value set, default first. Adding a mode is one
# entry here and one branch in preprocess_matcher_url_v1().
engine_url_normalizations_v1 <- function() {
  c("rfc3986", "none")
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

# One matcher URL and one note per row. NA and empty URLs pass as they are,
# with no note.
preprocess_matcher_url_v1 <- function(url, url_normalization) {
  n <- length(url)
  note <- rep(NA_character_, n)
  if (identical(url_normalization, "none") || n == 0L) {
    return(list(matcher_url = url, note = note))
  }
  matcher_url <- url
  for (i in which(!is.na(url) & nzchar(url))) {
    row <- rfc3986_matcher_url_v1(url[[i]])
    matcher_url[[i]] <- row$url
    note[[i]] <- row$note
  }
  list(matcher_url = matcher_url, note = note)
}

# The bytes the native bindings read: a latin1 string arrives as its UTF-8
# bytes (cpp11), every other string as written. `encoding` is the mark a
# rebuilt string takes.
url_bytes_v1 <- function(url) {
  encoding <- Encoding(url)
  if (identical(encoding, "latin1")) {
    return(list(bytes = charToRaw(enc2utf8(url)), encoding = "UTF-8"))
  }
  list(bytes = charToRaw(url), encoding = encoding)
}

# `bytes` from position `from` to the end; raw(0) past the end.
byte_tail_v1 <- function(bytes, from) {
  if (from > length(bytes)) {
    return(raw(0))
  }
  bytes[from:length(bytes)]
}

# The first position at or after `from` holding one of `set`, or NA.
first_byte_of_v1 <- function(bytes, set, from = 1L) {
  if (from > length(bytes)) {
    return(NA_integer_)
  }
  hit <- which(bytes[from:length(bytes)] %in% set)
  if (length(hit) == 0L) NA_integer_ else from + hit[[1L]] - 1L
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
# segment and its preceding /" pops one entry. Linear in the path length.
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
  out <- vector("list", 0L)
  i <- 1L
  while (i <= n) {
    if (at(i, c(dot, dot, slash))) {
      i <- i + 3L # A: "../"
    } else if (at(i, c(dot, slash))) {
      i <- i + 2L # A: "./"
    } else if (at(i, c(slash, dot, slash))) {
      i <- i + 2L # B: "/./" -> "/"
    } else if (rest_is(i, c(slash, dot))) {
      out[[length(out) + 1L]] <- slash # B: "/." -> "/"
      break
    } else if (at(i, c(slash, dot, dot, slash))) {
      out <- out[-length(out)] # C: "/../" -> "/", pop
      i <- i + 3L
    } else if (rest_is(i, c(slash, dot, dot))) {
      out <- out[-length(out)] # C: "/.." -> "/", pop
      out[[length(out) + 1L]] <- slash
      break
    } else if (rest_is(i, dot) || rest_is(i, c(dot, dot))) {
      break # D
    } else {
      # E: move the first segment, with its leading "/", to the output.
      end <- first_byte_of_v1(path, slash, i + 1L)
      end <- if (is.na(end)) n else end - 1L
      out[[length(out) + 1L]] <- path[i:end]
      i <- end + 1L
    }
  }
  if (length(out) == 0L) raw(0) else unlist(out, use.names = FALSE)
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

# The row note: what is invalid, then each change, joined by "; "; NA when
# the input is valid and nothing changed.
url_preprocessing_note_v1 <- function(invalid, no_authority, dots, userinfo,
                                      fragment) {
  section <- "§"
  parts <- c(
    if (length(invalid) > 0L) {
      paste0("not a valid RFC 3986 URI: ", toString(invalid))
    },
    if (no_authority) "no scheme or authority: path read from the first /",
    if (dots && length(invalid) > 0L) "dot segments removed as given",
    if (dots && length(invalid) == 0L) {
      paste0("RFC 3986 ", section, "5.2.4 removed dot segments")
    },
    if (userinfo) paste0("userinfo removed (RFC 3986 ", section, "3.2.1)"),
    if (fragment) paste0("fragment dropped (RFC 3986 ", section, "3.5)")
  )
  if (length(parts) == 0L) NA_character_ else paste(parts, collapse = "; ")
}

# One URL under "rfc3986": the rebuilt URL and its note.
rfc3986_matcher_url_v1 <- function(url) {
  input <- url_bytes_v1(url)
  parts <- url_split_rfc3986_v1(input$bytes)
  userinfo <- FALSE
  if (parts$has_authority) {
    host <- url_host_port_v1(parts$authority)
    userinfo <- !identical(host, parts$authority)
    lead <- c(parts$scheme, charToRaw("//"), host)
    before <- parts$path
  } else {
    # No authority (the text entry point accepts "/a/../b" and
    # "example.com/a"): the path the backend reads starts at the first "/".
    slash <- match(as.raw(0x2f), parts$path)
    keep <- if (is.na(slash)) length(parts$path) else slash - 1L
    lead <- c(parts$scheme, parts$path[seq_len(keep)])
    before <- byte_tail_v1(parts$path, keep + 1L)
  }
  path <- remove_dot_segments_v1(before)
  rebuilt <- c(lead, path, parts$query)
  note <- url_preprocessing_note_v1(
    invalid = rfc3986_invalid_classes_v1(input$bytes),
    no_authority = !parts$has_authority,
    dots = !identical(path, before),
    userinfo = userinfo,
    fragment = parts$fragment
  )
  if (identical(rebuilt, input$bytes)) {
    return(list(url = url, note = note))
  }
  out <- rawToChar(rebuilt)
  if (!identical(input$encoding, "unknown")) {
    Encoding(out) <- input$encoding
  }
  list(url = out, note = note)
}
