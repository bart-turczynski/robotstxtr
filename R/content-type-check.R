# Content-Type diagnostics for a fetched robots.txt (ROBO-plkpmoll).
#
# robots_validate_url() reads the fetch row's `content_type` (the final
# response's field value as received, several fields joined with ", ") and
# reports what the header gets wrong. The header changes nothing else: the
# body is parsed, matched and flagged exactly as before
# (design/engine-contract-v1.md, "Content-Type and the content flag").
#
# The parse follows RFC 9110 section 8.3.1, on bytes and ASCII only, so a
# header with non-ASCII bytes, or invalid UTF-8, is no error:
#
#   media-type = type "/" subtype parameters
#   parameters = *( OWS ";" OWS [ parameter ] )
#   parameter  = name "=" ( token / quoted-string )
#
# Type, subtype, parameter names and the charset value are compared
# ASCII-case-insensitively; a quoted charset is unquoted first.

# RFC 9110 tchar, as bytes.
content_type_tchar <- as.raw(c(
  0x21, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2a, 0x2b, 0x2d, 0x2e, 0x5e, 0x5f,
  0x60, 0x7c, 0x7e, 0x30:0x39, 0x41:0x5a, 0x61:0x7a
))

# The engine's encoding: utf-8, and us-ascii, which is a subset of it.
content_type_charsets_supported <- c("utf-8", "us-ascii")

# The four signatures `utf16_or_utf32_encoding` reports on.
content_type_wide_signatures <- c("utf-16le", "utf-16be", "utf-32le",
                                  "utf-32be")

# ASCII-lowercases bytes and returns them as a string (bytes 0x80 and above
# are kept as they are).
content_type_lower <- function(bytes) {
  upper <- bytes >= as.raw(0x41) & bytes <= as.raw(0x5a)
  bytes[upper] <- as.raw(as.integer(bytes[upper]) + 32L)
  rawToChar(bytes)
}

content_type_is_token <- function(bytes) {
  length(bytes) > 0L && all(bytes %in% content_type_tchar)
}

# Drops leading and trailing spaces and tabs.
content_type_trim <- function(bytes) {
  ows <- bytes %in% as.raw(c(0x20, 0x09))
  keep <- which(!ows)
  if (length(keep) == 0L) {
    return(raw())
  }
  bytes[keep[[1L]]:keep[[length(keep)]]]
}

# The content of a quoted-string that spans `bytes` exactly, with its
# quoted-pairs undone, or NULL when `bytes` is not one.
content_type_unquote <- function(bytes) {
  n <- length(bytes)
  if (n < 2L || bytes[[1L]] != as.raw(0x22) || bytes[[n]] != as.raw(0x22)) {
    return(NULL)
  }
  out <- raw()
  i <- 2L
  while (i < n) {
    byte <- bytes[[i]]
    if (byte == as.raw(0x5c)) {
      if (i + 1L >= n) {
        return(NULL)
      }
      i <- i + 1L
      byte <- bytes[[i]]
    } else if (byte == as.raw(0x22)) {
      return(NULL)
    }
    out <- c(out, byte)
    i <- i + 1L
  }
  out
}

# Splits the header at the `;` bytes outside quoted-strings. Returns a list
# with `parts` (a list of raw segments), or `reason` "comma" (a comma outside
# a quoted-string) or "syntax" (an unterminated quoted-string).
content_type_split <- function(bytes) {
  cuts <- integer()
  quoted <- FALSE
  i <- 1L
  n <- length(bytes)
  while (i <= n) {
    byte <- bytes[[i]]
    if (quoted) {
      if (byte == as.raw(0x5c)) {
        i <- i + 1L
      } else if (byte == as.raw(0x22)) {
        quoted <- FALSE
      }
    } else if (byte == as.raw(0x22)) {
      quoted <- TRUE
    } else if (byte == as.raw(0x2c)) {
      return(list(reason = "comma"))
    } else if (byte == as.raw(0x3b)) {
      cuts <- c(cuts, i)
    }
    i <- i + 1L
  }
  if (quoted) {
    return(list(reason = "syntax"))
  }
  starts <- c(1L, cuts + 1L)
  ends <- c(cuts - 1L, n)
  parts <- Map(function(from, to) {
    if (to < from) raw() else bytes[from:to]
  }, starts, ends)
  list(parts = parts)
}

# Parses a Content-Type field value. Returns a list with `reason` (NA when
# the value parses, else "comma" or "syntax"), `media_type` (lowercased) and
# `charsets` (each `charset` parameter's value, unquoted and lowercased).
content_type_parse <- function(value) {
  malformed <- function(reason) {
    list(reason = reason, media_type = NA_character_, charsets = character())
  }
  split <- content_type_split(charToRaw(value))
  if (!is.null(split$reason)) {
    return(malformed(split$reason))
  }
  media <- content_type_trim(split$parts[[1L]])
  slash <- which(media == as.raw(0x2f))
  if (length(slash) != 1L ||
        !content_type_is_token(media[seq_len(slash - 1L)]) ||
        !content_type_is_token(media[-seq_len(slash)])) {
    return(malformed("syntax"))
  }
  charsets <- character()
  for (part in split$parts[-1L]) {
    part <- content_type_trim(part)
    if (length(part) == 0L) {
      next
    }
    equals <- match(as.raw(0x3d), part)
    if (is.na(equals) || !content_type_is_token(part[seq_len(equals - 1L)])) {
      return(malformed("syntax"))
    }
    name <- content_type_lower(part[seq_len(equals - 1L)])
    value_bytes <- part[-seq_len(equals)]
    unquoted <- content_type_unquote(value_bytes)
    if (is.null(unquoted)) {
      if (length(value_bytes) > 0L && !content_type_is_token(value_bytes)) {
        return(malformed("syntax"))
      }
      unquoted <- value_bytes
    }
    if (identical(name, "charset")) {
      charsets <- c(charsets, content_type_lower(unquoted))
    } else if (length(unquoted) == 0L && length(value_bytes) == 0L) {
      return(malformed("syntax"))
    }
  }
  list(
    reason = NA_character_, media_type = content_type_lower(media),
    charsets = charsets
  )
}

# The Content-Type diagnostic rows for one fetched body: a list of zero to
# two rows, in the order malformed or (media type, then charset, then the
# us-ascii conflict). A missing header (NA) gives none: the bytes cannot
# establish what a server left out. `encoding_signature` is the document
# column validate_document_bytes() filled; a UTF-16 or UTF-32 body is
# `utf16_or_utf32_encoding`'s, so it gets no us-ascii conflict.
content_type_diagnostics <- function(source_id, content_type, body,
                                     encoding_signature) {
  if (length(content_type) != 1L || is.na(content_type)) {
    return(list())
  }
  raw_text <- render_validation_line(charToRaw(content_type))
  row <- function(code, message) {
    validation_diagnostic(
      source_id, NA_integer_, "warning", code, NA_character_, raw_text,
      message
    )
  }
  parsed <- content_type_parse(content_type)
  if (!is.na(parsed$reason)) {
    why <- if (identical(parsed$reason, "comma")) {
      paste(
        "It holds a comma outside a quoted string: the response sent",
        "several Content-Type fields (joined here with \", \") or one field",
        "listing several values."
      )
    } else {
      paste(
        "It is not one type/subtype media type with name=value parameters",
        "(RFC 9110 section 8.3.1)."
      )
    }
    return(list(row("content_type_malformed", paste(
      "The response's Content-Type header is malformed.", why,
      "Serve robots.txt as text/plain (RFC 9309 section 2.3). The body was",
      "still validated, and robotstxtr's results do not depend on the",
      "header."
    ))))
  }
  rows <- list()
  if (!identical(parsed$media_type, "text/plain")) {
    rows[[length(rows) + 1L]] <- row("content_type_not_text_plain", sprintf(
      paste(
        "The response's Content-Type is %s, not text/plain, which RFC 9309",
        "section 2.3 asks for. Crawlers may still read the body as a",
        "robots.txt, and robotstxtr validated it as one; its results do not",
        "depend on the header."
      ),
      render_validation_line(charToRaw(parsed$media_type))
    ))
  }
  charsets <- parsed$charsets
  if (length(charsets) > 1L) {
    rows[[length(rows) + 1L]] <- row("content_type_charset_unsupported", paste(
      "The response's Content-Type declares charset more than once, so the",
      "declared encoding is ambiguous. Declare charset=utf-8 once (RFC 9309",
      "section 2.3); the body is read as UTF-8 either way."
    ))
  } else if (length(charsets) == 1L && !nzchar(charsets)) {
    rows[[length(rows) + 1L]] <- row("content_type_charset_unsupported", paste(
      "The response's Content-Type declares an empty charset. Declare",
      "charset=utf-8 (RFC 9309 section 2.3); the body is read as UTF-8",
      "either way."
    ))
  } else if (length(charsets) == 1L &&
               !charsets %in% content_type_charsets_supported) {
    rows[[length(rows) + 1L]] <- row("content_type_charset_unsupported",
      sprintf(
        paste(
          "The response's Content-Type declares charset %s, not UTF-8 (RFC",
          "9309 section 2.3). The body is read as UTF-8 regardless, with no",
          "transcoding, so text in that charset may not read as intended."
        ),
        render_validation_line(charToRaw(charsets))
      )
    )
  } else if (identical(charsets, "us-ascii") &&
               any(body >= as.raw(0x80)) &&
               !encoding_signature %in% content_type_wide_signatures) {
    rows[[length(rows) + 1L]] <- row("content_type_charset_conflict", paste(
      "The response's Content-Type declares charset us-ascii, but the body",
      "holds bytes of 0x80 or above, which US-ASCII does not have. Declare",
      "charset=utf-8 (RFC 9309 section 2.3); the bytes are validated as",
      "UTF-8 as before."
    ))
  }
  rows
}
