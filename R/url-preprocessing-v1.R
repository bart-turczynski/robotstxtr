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
# The agent presets (ROBO-uyfryhlz) add one internal mode each, named after
# the preset and reached only through the facades' `preset` argument, never
# through `url_normalization` (engine_url_normalizations_v1() stays the
# public set). Each starts from "none", the URL as given, and applies only
# the byte steps measured for that surface (agent_preset_url_steps_v1()):
#
#   "claude_user"   uppercase the hex digits of every valid `%HH`, encode
#                   each `/` in the query as `%2F`, and strip one trailing
#                   `/` from a non-root path with no query or fragment.
#   "chatgpt_user"  uppercase the hex digits of every valid `%HH`.
#
# Unlike "rfc3986", these encode and case-fold bytes; unlike "whatwg", they
# never go through rurl, whose normalized form also decodes `%2E` (ADR 0002).
# Nothing else is changed: a raw space or byte outside ASCII, a dot segment,
# a `//` run or userinfo is left as given, and the note names it unmeasured.
#
# Whatever the mode, every row also carries `preprocessing_disagreement`:
# whether the rfc3986 and whatwg targets decide differently, or whatwg
# cannot parse the URL, on the rows a matcher decided (url_disagreement_v1());
# NA under "rfc3986" for a URL over url_disagreement_max_bytes_v1(), and NA
# on every decided row under "none" and under a preset, which compute
# nothing extra.

# The `url_normalization` value set, default first. Adding a mode means an
# entry here, a branch in preprocess_matcher_url_v1(), and a decision in
# url_disagreement_v1() on whether, and how, that mode is compared.
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

# The longest input URL, in bytes, whose whatwg form the disagreement flag
# computes under "rfc3986" ("none" computes no flag). rurl's WHATWG
# serializer grows faster than linearly on a long path with many dot
# segments (about 53 seconds for 20,000 "/seg/.." pairs, and a tenth of a
# second for a 2,040-byte one), and "rfc3986" did not ask for it. A longer
# URL is not compared: its flag is NA. "whatwg" itself serializes any
# length.
url_disagreement_max_bytes_v1 <- function() {
  2048L
}

url_disagreement_not_compared_v1 <- function() {
  sprintf(
    "not compared: URL longer than %d bytes", url_disagreement_max_bytes_v1()
  )
}

# The clients note of a decided row under "none", where the flag is never
# computed: "none" is the old reading, with nothing extra.
url_disagreement_not_compared_none_v1 <- function() {
  "not compared under url_normalization = \"none\""
}

# The clients note of a decided row under a preset, where the flag is never
# computed either: a preset reads the URL as its surface was measured to,
# not as an rfc3986 or whatwg client would.
url_disagreement_not_compared_preset_v1 <- function() {
  "not compared under an agent preset"
}

# One matcher URL and one note per row, under the selected mode, and the
# rfc3986 target the disagreement flag compares. The whatwg form is
# computed here only under "whatwg", for every row; under "rfc3986"
# url_disagreement_v1() computes it for the rows it compares (`whatwg_url`
# and `whatwg_failed` are then NULL). Under "none" nothing is computed: the
# URL is read as given and the flag is not compared. Under a preset mode
# only that preset's byte steps run, and the flag is not compared either.
# NA and empty URLs pass as they are, with no note, in every mode.
preprocess_matcher_url_v1 <- function(url, url_normalization) {
  if (url_normalization %in% agent_preset_ids_v1()) {
    selected <- agent_matcher_urls_v1(url, url_normalization)
    return(list(
      url = url, url_normalization = url_normalization,
      matcher_url = selected$url, note = selected$note,
      rfc3986_url = NULL, whatwg_url = NULL, whatwg_failed = NULL
    ))
  }
  none <- identical(url_normalization, "none")
  rfc3986 <- if (!none) rfc3986_matcher_urls_v1(url)
  whatwg <- if (identical(url_normalization, "whatwg")) {
    whatwg_matcher_urls_v1(url)
  }
  selected <- switch(
    url_normalization,
    rfc3986 = rfc3986,
    whatwg = whatwg,
    none = list(url = url, note = rep(NA_character_, length(url)))
  )
  list(
    url = url, url_normalization = url_normalization,
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

# The URL as UTF-8 for rurl, never read through the native encoding: a
# latin1-marked string is converted from latin1, and any other string is
# taken as the bytes it holds (rurl reads them as UTF-8 whatever their
# mark). Bytes that are not valid UTF-8 give NA, which rurl cannot parse
# either (rurl would otherwise read them as U+FFFD).
url_utf8_for_rurl_v1 <- function(url) {
  latin <- Encoding(url) == "latin1"
  out <- url
  out[latin] <- enc2utf8(url[latin])
  as_bytes <- which(!latin)
  out[as_bytes[!validUTF8(url[as_bytes])]] <- NA_character_
  out
}

# `f(x)` once over the distinct values of `x`, NA where it gives none. When
# the vector call errors or returns the wrong length, each value is tried
# on its own, so one bad URL fails alone.
rurl_each_v1 <- function(x, f) {
  call <- function(v) {
    out <- tryCatch(as.character(f(v)), error = function(e) NULL)
    if (length(out) == length(v)) out else NULL
  }
  distinct <- unique(x[!is.na(x)])
  done <- call(distinct)
  if (is.null(done)) {
    done <- vapply(distinct, function(v) {
      one <- call(v)
      if (is.null(one)) NA_character_ else one
    }, "", USE.NAMES = FALSE)
  }
  done[match(x, distinct)]
}

# The placeholder origin a URL with no scheme is serialized on: the path
# and query "rfc3986" splits from it are appended to this string (never
# resolved, so a path starting with "//" stays a path).
whatwg_placeholder_origin_v1 <- function() {
  "http://h.invalid"
}

# rurl's WHATWG serialization of each URL, NA where it cannot parse one.
whatwg_serialize_v1 <- function(url) {
  input <- url_utf8_for_rurl_v1(url)
  out <- rep(NA_character_, length(url))
  ok <- which(!is.na(input))
  out[ok] <- rurl_each_v1(input[ok], function(v) {
    rurl::serialize_url(v, standard = "whatwg")
  })
  out
}

# A URL with no scheme, split exactly as "rfc3986" splits it
# (url_target_parts_v1()). NULL when that path does not start with "/" (it
# is then read as "rfc3986" reads it); else the split of its UTF-8 bytes
# (the delimiters are ASCII, so it splits where the input does), and the
# placeholder URL to serialize. A URL that is not valid UTF-8, its lead
# included, has no placeholder URL (NA) and so fails, as rurl fails on any
# other such URL.
whatwg_schemeless_input_v1 <- function(url) {
  input <- url_bytes_v1(url)
  target <- url_target_parts_v1(input$bytes)
  if (length(target$path) == 0L || target$path[[1L]] != as.raw(0x2f)) {
    return(NULL)
  }
  utf8 <- url_utf8_for_rurl_v1(url)
  if (is.na(utf8)) {
    return(list(target = target, wrapped = NA_character_))
  }
  target <- url_target_parts_v1(charToRaw(utf8))
  tail <- string_with_mark_v1(c(target$path, target$query), "UTF-8")
  list(
    target = target, encoding = "UTF-8",
    wrapped = paste0(whatwg_placeholder_origin_v1(), tail)
  )
}

whatwg_matcher_urls_v1 <- function(url) {
  out <- url
  note <- rep(NA_character_, length(url))
  failed <- rep(FALSE, length(url))
  todo <- which(!is.na(url) & nzchar(url))
  # No scheme as url_split_rfc3986_v1() reads one: no ":" after at least
  # one byte and before the first "/", "?" or "#".
  relative <- !grepl("^[^:/?#]+:", url[todo], useBytes = TRUE)
  rel <- vector("list", length(todo))
  input <- url[todo]
  for (k in which(relative)) {
    rel[k] <- list(whatwg_schemeless_input_v1(input[[k]]))
    if (!is.null(rel[[k]])) {
      input[[k]] <- rel[[k]]$wrapped
    }
  }
  serialized <- whatwg_serialize_v1(input)
  for (k in seq_along(todo)) {
    i <- todo[[k]]
    row <- if (relative[[k]] && is.null(rel[[k]])) {
      rfc3986_matcher_url_v1(url[[i]])
    } else if (is.na(serialized[[k]])) {
      failed[[i]] <- TRUE
      list(url = url[[i]], note = "not a valid WHATWG URL: evaluated as given")
    } else if (relative[[k]]) {
      whatwg_schemeless_matcher_url_v1(url[[i]], serialized[[k]], rel[[k]])
    } else {
      whatwg_matcher_url_v1(url[[i]], serialized[[k]])
    }
    out[[i]] <- row$url
    note[[i]] <- row$note
  }
  list(url = out, note = note, failed = failed)
}

# One URL with no scheme under "whatwg": the lead "rfc3986" keeps, then the
# serialized path and query; the fragment is dropped as "rfc3986" drops it.
# A serialized path that starts with "//" where the input path did not, after
# a lead with no authority, would read as an authority the input lacks, so
# the input is evaluated as given, as "rfc3986" guards its own removal. A
# path that already started with "//" is serialized as usual.
whatwg_schemeless_matcher_url_v1 <- function(url, serialized, rel) {
  parts <- url_split_rfc3986_v1(charToRaw(serialized))
  target <- rel$target
  no_authority <- if (identical(target$no_authority, "slash")) {
    "no authority: path read from the first /"
  }
  created <- path_starts_with_slashes_v1(parts$path) &&
    !path_starts_with_slashes_v1(target$path)
  if (!target$has_authority && created) {
    return(list(url = url, note = paste(c(
      no_authority,
      "WHATWG serialization left in place: it would start the path with //"
    ), collapse = "; ")))
  }
  rebuilt <- c(target$lead, parts$path, parts$query)
  note <- c(
    no_authority,
    if (target$userinfo) "userinfo removed",
    if (!identical(rebuilt, c(target$lead, target$path, target$query))) {
      "WHATWG URL serialization changed the URL"
    },
    if (target$fragment) "fragment dropped"
  )
  joined <- paste(note, collapse = "; ")
  list(
    url = string_with_mark_v1(rebuilt, rel$encoding),
    note = if (length(note) == 0L) NA_character_ else joined
  )
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

# Whether two character vectors (no NA) hold the same bytes, element by
# element.
bytes_equal_v1 <- function(a, b) {
  vapply(seq_along(a), function(i) {
    identical(charToRaw(a[[i]]), charToRaw(b[[i]]))
  }, logical(1L))
}

# `bytes` with A-Z folded to a-z.
ascii_lower_raw_v1 <- function(bytes) {
  upper <- bytes >= as.raw(0x41) & bytes <= as.raw(0x5a)
  bytes[upper] <- as.raw(as.integer(bytes[upper]) + 32L)
  bytes
}

# `path` with each complete segment that is, ASCII case folded, "%2e" read
# as "." and ".%2e", "%2e." or "%2e%2e" read as "..". A segment holding an
# encoded dot among other bytes ("a%2eb") stays as it is.
url_decode_dot_segments_v1 <- function(path) {
  edges <- c(0L, which(path == as.raw(0x2f)), length(path) + 1L)
  out <- vector("list", 2L * (length(edges) - 1L))
  for (k in seq_len(length(edges) - 1L)) {
    from <- edges[[k]] + 1L
    to <- edges[[k + 1L]] - 1L
    segment <- if (to >= from) path[from:to] else raw(0)
    if (length(segment) >= 3L && length(segment) <= 6L) {
      key <- rawToChar(ascii_lower_raw_v1(segment))
      if (identical(key, "%2e")) {
        segment <- charToRaw(".")
      } else if (key %in% c(".%2e", "%2e.", "%2e%2e")) {
        segment <- charToRaw("..")
      }
    }
    out[[2L * k - 1L]] <- if (k > 1L) as.raw(0x2f)
    out[[2L * k]] <- segment
  }
  unlist(out, use.names = FALSE)
}

# `x` with A-Z folded to a-z, on bytes, so a string that is not valid in
# the session's encoding is never translated.
ascii_lower_chr_v1 <- function(x) {
  for (k in seq_along(LETTERS)) {
    x <- gsub(LETTERS[[k]], letters[[k]], x, fixed = TRUE, useBytes = TRUE)
  }
  x
}

# The parts of each target, split in one vectorized call (RFC 3986
# Appendix B, as url_split_rfc3986_v1() reads it; a target has no
# fragment), with the differences no matcher reads apart folded: the scheme
# and host in ASCII lower case, a default port (80 for http, 443 for https)
# dropped, an empty path after an authority read as "/". A latin1 target is
# compared in UTF-8, as its twin.
url_target_keys_v1 <- function(url) {
  latin <- Encoding(url) == "latin1"
  url[latin] <- enc2utf8(url[latin])
  pattern <- "^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?[^#]*)?"
  m <- regmatches(url, regexec(pattern, url, useBytes = TRUE))
  m <- matrix(unlist(m, use.names = FALSE), ncol = 7L, byrow = TRUE)
  scheme <- ascii_lower_chr_v1(m[, 2L])
  authority <- nzchar(m[, 4L])
  host <- ascii_lower_chr_v1(sub("^.*@", "", m[, 5L], useBytes = TRUE))
  http <- scheme == "http:"
  host[http] <- sub(":80$", "", host[http], useBytes = TRUE)
  https <- scheme == "https:"
  host[https] <- sub(":443$", "", host[https], useBytes = TRUE)
  path <- m[, 6L]
  path[authority & !nzchar(path)] <- "/"
  list(
    scheme = scheme, authority = authority, host = host, path = path,
    query = m[, 7L]
  )
}

# Whether each pair of targets differs only in what url_target_keys_v1()
# folds, so no second matcher pass is needed.
url_targets_alike_v1 <- function(a, b) {
  if (length(a) == 0L) {
    return(logical(0))
  }
  ka <- url_target_keys_v1(a)
  kb <- url_target_keys_v1(b)
  ka$scheme == kb$scheme & ka$authority == kb$authority &
    ka$host == kb$host & ka$path == kb$path & ka$query == kb$query
}

# Whether the two forms differ only through encoded dot segments: the
# INPUT's path, its complete encoded dot segments read as dots, then run
# through the rfc3986 removal (RFC 3986 section 5.2.4), with its query,
# equals the whatwg path and query, under the same lead
# (url_target_parts_v1(), as url_lead_key_v1() folds it). The input, not
# the rfc3986 target: that has already had its literal dots removed, so
# "/latam/%2e/../x" would lose the "%2e" a browser reads as a dot. Only
# then do the surveyed client families apply.
url_encoded_dots_only_v1 <- function(input, whatwg) {
  r <- url_target_parts_v1(target_utf8_bytes_v1(input))
  w <- url_target_parts_v1(target_utf8_bytes_v1(whatwg))
  path <- remove_dot_segments_v1(url_decode_dot_segments_v1(r$path))
  identical(c(path, r$query), c(w$path, w$query)) &&
    identical(url_lead_key_v1(r), url_lead_key_v1(w))
}

# A target's bytes in UTF-8: a latin1-marked target is converted, any other
# is taken as it is, so a latin1 URL and its UTF-8 twin compare alike.
target_utf8_bytes_v1 <- function(url) {
  charToRaw(if (identical(Encoding(url), "latin1")) enc2utf8(url) else url)
}

# The lead of url_target_parts_v1() with the differences no matcher reads
# apart folded: ASCII lower case, and a default port (80 for http, 443 for
# https) dropped after an authority.
url_lead_key_v1 <- function(target) {
  lead <- ascii_lower_raw_v1(target$lead)
  scheme <- ascii_lower_raw_v1(target$scheme)
  default <- if (!target$has_authority) {
    NULL
  } else if (identical(scheme, charToRaw("http:"))) {
    charToRaw(":80")
  } else if (identical(scheme, charToRaw("https:"))) {
    charToRaw(":443")
  }
  n <- length(lead)
  k <- length(default)
  if (k > 0L && n > k && identical(lead[(n - k + 1L):n], default)) {
    lead <- lead[seq_len(n - k)]
  }
  lead
}

# `disagreement_clients` for flagged rows: each side's decision, and the
# client families when the two forms differ only through encoded dot
# segments (`named`); otherwise a neutral text. `failed` rows have no
# whatwg decision and are never named.
url_disagreement_text_v1 <- function(rfc3986, whatwg, failed, named) {
  families <- url_client_families_v1()
  shown <- function(x) ifelse(is.na(x), "undecided", x)
  left <- paste("rfc3986", shown(rfc3986))
  failed <- rep_len(failed, length(left))
  named <- rep_len(named, length(left))
  right <- ifelse(
    failed, "whatwg cannot parse the URL", paste("whatwg", shown(whatwg))
  )
  out <- sprintf(
    paste0(
      "%s; %s: the forms differ in more than dot segments; no client ",
      "survey covers this"
    ),
    left, right
  )
  out[failed] <- sprintf(
    "%s; %s; no client survey covers this", left[failed], right[failed]
  )
  out[named] <- sprintf(
    "%s (dot segments as in: %s); %s (dot segments as in: %s)",
    left[named], families[["rfc3986"]], right[named], families[["whatwg"]]
  )
  out
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

# The whatwg targets of `rows` (full-length vectors, NA elsewhere) and
# which of them rurl cannot parse: taken from the selected pass under
# "whatwg", computed here for those rows only otherwise.
url_compared_whatwg_v1 <- function(preprocessed, rows) {
  n <- length(preprocessed$url)
  url <- rep(NA_character_, n)
  failed <- rep(FALSE, n)
  if (is.null(preprocessed$whatwg_url)) {
    computed <- whatwg_matcher_urls_v1(preprocessed$url[rows])
    url[rows] <- computed$url
    failed[rows] <- computed$failed
  } else {
    url[rows] <- preprocessed$whatwg_url[rows]
    failed[rows] <- preprocessed$whatwg_failed[rows]
  }
  list(url = url, failed = failed)
}

# `preprocessing_disagreement` and `disagreement_clients` for every row.
# Only matcher rows the selected pass decided are compared; every other row
# is FALSE with NA clients. Under "none" every decided row is NA and
# nothing is computed. Under "rfc3986" a decided row over the cap is NA,
# and its whatwg form is never computed. A compared row is TRUE where
# whatwg cannot parse the URL, or where the two targets differ in more
# than url_targets_alike_v1() folds and the matcher decides them
# differently; a second matcher pass runs only on those rows.
# `url_decision` is the selected pass's; `decide(rows, urls)` returns the
# url_decision of `rows` when the matcher reads `urls`.
url_disagreement_v1 <- function(preprocessed, matcher_rows, url_decision,
                                decide) {
  n <- length(preprocessed$url)
  flag <- rep(FALSE, n)
  clients <- rep(NA_character_, n)
  rows <- matcher_rows[!is.na(url_decision[matcher_rows])]
  if (identical(preprocessed$url_normalization, "none")) {
    flag[rows] <- NA
    clients[rows] <- url_disagreement_not_compared_none_v1()
    return(list(flag = flag, clients = clients))
  }
  if (preprocessed$url_normalization %in% agent_preset_ids_v1()) {
    flag[rows] <- NA
    clients[rows] <- url_disagreement_not_compared_preset_v1()
    return(list(flag = flag, clients = clients))
  }
  if (identical(preprocessed$url_normalization, "rfc3986")) {
    over <- rows[
      nchar(preprocessed$url[rows], type = "bytes") >
        url_disagreement_max_bytes_v1()
    ]
    flag[over] <- NA
    clients[over] <- url_disagreement_not_compared_v1()
    rows <- setdiff(rows, over)
  }
  if (length(rows) == 0L) {
    return(list(flag = flag, clients = clients))
  }
  whatwg <- url_compared_whatwg_v1(preprocessed, rows)
  side <- function(at, target) {
    side_decision_v1(
      at, target, preprocessed$matcher_url, url_decision, decide
    )
  }
  bad <- rows[whatwg$failed[rows]]
  if (length(bad) > 0L) {
    flag[bad] <- TRUE
    clients[bad] <- url_disagreement_text_v1(
      side(bad, preprocessed$rfc3986_url), NA_character_, TRUE, FALSE
    )
  }
  ok <- rows[!whatwg$failed[rows]]
  cand <- ok[!url_targets_alike_v1(preprocessed$rfc3986_url[ok],
                                   whatwg$url[ok])]
  if (length(cand) == 0L) {
    return(list(flag = flag, clients = clients))
  }
  rfc3986 <- side(cand, preprocessed$rfc3986_url)
  other <- side(cand, whatwg$url)
  apart <- !mapply(identical, rfc3986, other, USE.NAMES = FALSE)
  hit <- cand[apart]
  named <- mapply(
    url_encoded_dots_only_v1, preprocessed$url[hit], whatwg$url[hit],
    USE.NAMES = FALSE
  )
  flag[hit] <- TRUE
  clients[hit] <- url_disagreement_text_v1(
    rfc3986[apart], other[apart], FALSE, as.logical(named)
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

# The target a backend reads, split the way "rfc3986" splits it, which
# "whatwg" reuses for a URL with no scheme: `lead` (the scheme, then "//"
# and host[:port] when there is an authority, else the bytes before the
# path's first "/"), `path` (the path the backend reads), `query` (with its
# "?"), whether userinfo or a fragment was dropped, and `no_authority`
# ("slash", "none" or NA, as url_preprocessing_note_v1() takes it).
url_target_parts_v1 <- function(bytes) {
  parts <- url_split_rfc3986_v1(bytes)
  userinfo <- FALSE
  no_authority <- NA_character_
  if (parts$has_authority) {
    host <- url_host_port_v1(parts$authority)
    userinfo <- !identical(host, parts$authority)
    lead <- c(parts$scheme, charToRaw("//"), host)
    path <- parts$path
  } else {
    # No authority (the text entry point accepts "/a/../b" and
    # "example.com/a"): the path the backend reads starts at the first "/".
    split <- url_path_after_first_slash_v1(parts$path)
    lead <- c(parts$scheme, split$lead)
    path <- split$rest
    no_authority <- split$no_authority
  }
  list(
    scheme = parts$scheme, has_authority = parts$has_authority, lead = lead,
    path = path, query = parts$query, userinfo = userinfo,
    fragment = parts$fragment, no_authority = no_authority
  )
}

# Whether `path` starts with "//", which after a lead with no authority
# would read as one.
path_starts_with_slashes_v1 <- function(path) {
  length(path) >= 2L && identical(path[1:2], charToRaw("//"))
}

# `bytes` as a string with the mark `encoding` ("unknown" leaves it
# unmarked).
string_with_mark_v1 <- function(bytes, encoding) {
  out <- rawToChar(bytes)
  if (!identical(encoding, "unknown")) {
    Encoding(out) <- encoding
  }
  out
}

# One URL under "rfc3986": the rebuilt URL and its note.
rfc3986_matcher_url_v1 <- function(url) {
  input <- url_bytes_v1(url)
  target <- url_target_parts_v1(input$bytes)
  path <- remove_dot_segments_v1(target$path)
  dots <- if (identical(path, target$path)) NA_character_ else "removed"
  rebuilt <- c(target$lead, path, target$query)
  fragment <- target$fragment
  if (!target$has_authority && identical(dots, "removed") &&
        path_starts_with_slashes_v1(path)) {
    # Removing the dots would turn the path into an authority that the
    # input does not have ("/a/..//h/x" -> "//h/x"): keep the input.
    dots <- "kept"
    rebuilt <- input$bytes
    fragment <- FALSE
  }
  note <- url_preprocessing_note_v1(
    invalid = rfc3986_invalid_classes_v1(input$bytes),
    no_authority = target$no_authority,
    dots = dots,
    userinfo = target$userinfo,
    fragment = fragment
  )
  # The rebuilt bytes take the input's mark, so an unchanged URL comes back
  # with its bytes and its mark.
  list(url = string_with_mark_v1(rebuilt, input$encoding), note = note)
}

# ---- agent presets (ROBO-uyfryhlz) ------------------------------------------

# One matcher URL and one note per row under a preset mode. NA and empty
# URLs pass as they are, with no note, as in every mode.
agent_matcher_urls_v1 <- function(url, preset) {
  out <- url
  note <- rep(NA_character_, length(url))
  steps <- agent_preset_url_steps_v1(preset)
  for (i in which(!is.na(url) & nzchar(url))) {
    row <- agent_matcher_url_v1(url[[i]], preset, steps)
    out[[i]] <- row$url
    note[[i]] <- row$note
  }
  list(url = out, note = note)
}

# The hex digits of every `%` followed by two hex digits, in upper case,
# byte by byte: no locale reads them. A `%` without two hex digits after it
# (`%zz`, `%3`, a trailing `%`) is left as it is, and nothing is decoded,
# so `%2f` becomes `%2F`, never `/` or `%252F`.
agent_upper_escapes_v1 <- function(bytes) {
  n <- length(bytes)
  if (n < 3L) {
    return(bytes)
  }
  hex <- bytes %in% as.raw(c(0x30:0x39, 0x41:0x46, 0x61:0x66))
  pct <- which(bytes[seq_len(n - 2L)] == as.raw(0x25))
  pct <- pct[hex[pct + 1L] & hex[pct + 2L]]
  digits <- c(pct + 1L, pct + 2L)
  lower <- digits[bytes[digits] %in% as.raw(0x61:0x66)]
  bytes[lower] <- as.raw(as.integer(bytes[lower]) - 32L)
  bytes
}

# Each `/` in the query (after the first `?`, before any `#`) as `%2F`. The
# fragment is left as given.
agent_encode_query_slash_v1 <- function(bytes) {
  hash <- match(as.raw(0x23), bytes)
  end <- if (is.na(hash)) length(bytes) else hash - 1L
  question <- match(as.raw(0x3f), bytes[seq_len(end)])
  if (is.na(question) || question >= end) {
    return(bytes)
  }
  query <- bytes[(question + 1L):end]
  encoded <- unlist(lapply(query, function(b) {
    if (b == as.raw(0x2f)) charToRaw("%2F") else b
  }))
  c(bytes[seq_len(question)], encoded, byte_tail_v1(bytes, end + 1L))
}

# Whether `path` (the path the backend reads) is longer than "/" and ends
# in "/".
agent_nonroot_trailing_slash_v1 <- function(path) {
  length(path) > 1L && path[[length(path)]] == as.raw(0x2f)
}

# One trailing `/` stripped from a non-root path, only when the URL has no
# query and no fragment, so the path's last byte is the URL's. A trailing
# `/` before a query or fragment was not measured and is kept.
agent_strip_trailing_slash_v1 <- function(bytes) {
  target <- url_target_parts_v1(bytes)
  if (length(target$query) > 0L || target$fragment ||
        !agent_nonroot_trailing_slash_v1(target$path)) {
    return(bytes)
  }
  bytes[-length(bytes)]
}

# Whether a `%` in `bytes` is not followed by two hex digits.
agent_stray_percent_v1 <- function(bytes) {
  pct <- which(bytes == as.raw(0x25))
  if (length(pct) == 0L) {
    return(FALSE)
  }
  hex <- c(
    bytes %in% as.raw(c(0x30:0x39, 0x41:0x46, 0x61:0x66)), FALSE, FALSE
  )
  !all(hex[pct + 1L] & hex[pct + 2L])
}

# Whether a path segment is `.` or `..` once `%2e`/`%2E` is read as `.`,
# though not written so (`%2e`, `.%2e`, `%2E%2E`, ...).
agent_encoded_dot_segment_v1 <- function(segments) {
  decoded <- gsub("%2[eE]", ".", segments, useBytes = TRUE)
  any(decoded %in% c(".", "..") & decoded != segments)
}

# The inputs a preset leaves as given because no probe measured how its
# surface reads them (AGEN-hdmtqpwx, AGEN-hsvkltop), named for the note.
# Every byte class the preset steps do not touch is named here, so a row
# that holds one never reads as fully measured.
agent_unmeasured_v1 <- function(bytes, preset) {
  target <- url_target_parts_v1(bytes)
  path <- target$path
  segments <- strsplit(
    rawToChar(path), "/", fixed = TRUE, useBytes = TRUE
  )[[1L]]
  slashes <- path == as.raw(0x2f)
  trailing <- agent_nonroot_trailing_slash_v1(path)
  code <- as.integer(bytes)
  found <- c(
    "raw byte outside ASCII" = any(code >= 0x80L),
    "raw space" = any(bytes == as.raw(0x20)),
    "control byte" = any(code < 0x20L | code == 0x7fL),
    backslash = any(bytes == as.raw(0x5c)),
    "character RFC 3986 excludes (\"<>^`{|})" =
      any(bytes %in% charToRaw("\"<>^`{|}")),
    "% without two hex digits" = agent_stray_percent_v1(bytes),
    "dot segment" = any(segments %in% c(".", "..")),
    "percent-encoded dot segment" = agent_encoded_dot_segment_v1(segments),
    "empty path segment (//)" = length(path) > 1L &&
      any(slashes[-1L] & slashes[-length(path)]),
    userinfo = target$userinfo
  )
  if (identical(preset, "claude_user")) {
    found[["trailing / before a query or fragment"]] <- trailing &&
      (length(target$query) > 0L || target$fragment)
  } else {
    # ChatGPT-User's query `/` is observed kept (converters/openai.md,
    # AGEN-nweunrii), so it is not named here.
    found[["trailing / on a non-root path"]] <- trailing
  }
  names(found)[found]
}

# Every preset URL step, in the order they run, with the note label of a
# step that changed the URL.
agent_url_steps_v1 <- function() {
  list(
    uppercase_escapes = list(
      apply = agent_upper_escapes_v1,
      label = "percent-escape hex digits uppercased"
    ),
    strip_trailing_slash = list(
      apply = agent_strip_trailing_slash_v1, label = "trailing / removed"
    ),
    encode_query_slash = list(
      apply = agent_encode_query_slash_v1,
      label = "/ in the query encoded as %2F"
    )
  )
}

# One URL under a preset: the URL with `steps` applied, in a fixed order,
# and the note naming each step that changed it, then the unmeasured inputs
# it holds.
agent_matcher_url_v1 <- function(url, preset, steps) {
  input <- url_bytes_v1(url)
  bytes <- input$bytes
  changed <- character()
  for (step in intersect(names(agent_url_steps_v1()), steps)) {
    entry <- agent_url_steps_v1()[[step]]
    after <- entry$apply(bytes)
    if (!identical(after, bytes)) {
      changed <- c(changed, entry$label)
      bytes <- after
    }
  }
  unmeasured <- agent_unmeasured_v1(input$bytes, preset)
  parts <- c(
    changed,
    if (length(unmeasured) > 0L) {
      sprintf(
        "left as given, unmeasured for %s: %s", preset, toString(unmeasured)
      )
    }
  )
  note <- if (length(parts) == 0L) {
    NA_character_
  } else {
    paste(parts, collapse = "; ")
  }
  list(url = string_with_mark_v1(bytes, input$encoding), note = note)
}
