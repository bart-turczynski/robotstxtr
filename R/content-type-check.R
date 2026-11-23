# Content-Type diagnostics for a fetched robots.txt (ROBO-plkpmoll).
#
# robots_validate_url() reads the fetch row's `content_type` (the final
# response's field value as received, several fields joined with ", ") and
# reports what the header gets wrong. The header changes nothing else: the
# body is parsed, matched and flagged exactly as before
# (design/engine-contract-v1.md, "Content-Type and the content flag on legacy
# fetch rows").
#
# The parse follows RFC 9110 sections 8.3.1 and 5.6.4, on bytes and ASCII
# only, so a header with non-ASCII bytes, or invalid UTF-8, is no error:
#
#   media-type    = type "/" subtype parameters
#   parameters    = *( OWS ";" OWS [ parameter ] )
#   parameter     = name "=" ( token / quoted-string )
#   quoted-string = DQUOTE *( qdtext / quoted-pair ) DQUOTE
#   qdtext        = HTAB / SP / %x21 / %x23-5B / %x5D-7E / obs-text
#   quoted-pair   = "\" ( HTAB / SP / VCHAR / obs-text )
#
# Type, subtype, parameter names and the charset value are compared
# ASCII-case-insensitively; a quoted charset is unquoted first. Each scan is
# one pass over the bytes, so a long header costs linear time.

# Byte lookup tables, indexed by byte + 1: RFC 9110 tchar, and the bytes a
# quoted-string may hold (HTAB, SP, VCHAR, obs-text).
content_type_tchar <- local({
  table <- logical(256L)
  table[c(0x21L, 0x23L, 0x24L, 0x25L, 0x26L, 0x27L, 0x2aL, 0x2bL, 0x2dL,
          0x2eL, 0x5eL, 0x5fL, 0x60L, 0x7cL, 0x7eL, 0x30:0x39, 0x41:0x5a,
          0x61:0x7a) + 1L] <- TRUE
  table
})
content_type_qtext <- local({
  table <- logical(256L)
  table[c(0x09L, 0x20:0x7e, 0x80:0xff) + 1L] <- TRUE
  table
})

# The IANA name and aliases of US-ASCII, lowercased; each is a subset of
# UTF-8, so a header naming one is accepted over ASCII bytes.
content_type_us_ascii <- c(
  "us-ascii", "ascii", "us", "ansi_x3.4-1968", "iso-ir-6", "ansi_x3.4-1986",
  "iso_646.irv:1991", "iso646-us", "ibm367", "cp367", "csascii"
)

# Labels that are not the registered UTF-8 name but that browsers (the WHATWG
# Encoding Standard) read as UTF-8.
content_type_utf8_nonstandard <- c(
  "utf8", "unicode-1-1-utf-8", "unicode11utf8", "unicode20utf8",
  "x-unicode20utf8"
)

# ASCII-compatible charsets: an ASCII body reads the same under them as under
# UTF-8. Shift_JIS is left out (it maps 0x5C and 0x7E elsewhere).
content_type_ascii_compatible <- paste0(
  "^(iso-?8859-[0-9]+|iso_8859-[0-9]+(:[0-9]+)?|latin[0-9]+|l[0-9]+|",
  "csisolatin[0-9]+|windows-125[0-8]|cp125[0-8]|ibm819|cp819|koi8-[ru]|",
  "macintosh|x-mac-roman|gb2312|gbk|gb18030|euc-jp|euc-kr|big5)$"
)

# The four signatures `utf16_or_utf32_encoding` reports on.
content_type_wide_signatures <- c("utf-16le", "utf-16be", "utf-32le",
                                  "utf-32be")

# ASCII-lowercases bytes (integers) and returns them as a string; bytes 0x80
# and above are kept as they are.
content_type_lower <- function(bytes) {
  upper <- bytes >= 0x41L & bytes <= 0x5aL
  bytes[upper] <- bytes[upper] + 32L
  rawToChar(as.raw(bytes))
}

content_type_is_token <- function(bytes) {
  length(bytes) > 0L && all(content_type_tchar[bytes + 1L])
}

# Drops leading and trailing spaces and tabs.
content_type_trim <- function(bytes) {
  keep <- which(!(bytes %in% c(0x20L, 0x09L)))
  if (length(keep) == 0L) {
    return(integer())
  }
  bytes[keep[[1L]]:keep[[length(keep)]]]
}

# Cuts `bytes` at the positions `at`, dropping the bytes there.
content_type_cut <- function(bytes, at) {
  starts <- c(1L, at + 1L)
  ends <- c(at - 1L, length(bytes))
  Map(function(from, to) {
    if (to < from) integer() else bytes[from:to]
  }, starts, ends)
}

# One pass over the header: the positions of the `;` and `,` bytes outside
# quoted-strings, or `reason` "syntax" for an unterminated quoted-string or
# a byte a quoted-string may not hold.
content_type_scan <- function(bytes) {
  n <- length(bytes)
  semi <- logical(n)
  comma <- logical(n)
  quoted <- FALSE
  i <- 1L
  while (i <= n) {
    byte <- bytes[[i]]
    if (quoted) {
      if (byte == 0x5cL) {
        i <- i + 1L
        if (i > n || !content_type_qtext[[bytes[[i]] + 1L]]) {
          return(list(reason = "syntax"))
        }
      } else if (byte == 0x22L) {
        quoted <- FALSE
      } else if (!content_type_qtext[[byte + 1L]]) {
        return(list(reason = "syntax"))
      }
    } else if (byte == 0x22L) {
      quoted <- TRUE
    } else if (byte == 0x2cL) {
      comma[[i]] <- TRUE
    } else if (byte == 0x3bL) {
      semi[[i]] <- TRUE
    }
    i <- i + 1L
  }
  if (quoted) {
    return(list(reason = "syntax"))
  }
  list(semi = which(semi), comma = which(comma))
}

# The content of a quoted-string that spans `bytes` exactly, with its
# quoted-pairs undone, or NULL when `bytes` is not one. The bytes themselves
# were checked by content_type_scan().
content_type_unquote <- function(bytes) {
  n <- length(bytes)
  if (n < 2L || bytes[[1L]] != 0x22L || bytes[[n]] != 0x22L) {
    return(NULL)
  }
  inner <- bytes[seq_len(n - 2L) + 1L]
  m <- length(inner)
  keep <- rep(TRUE, m)
  i <- 1L
  while (i <= m) {
    byte <- inner[[i]]
    if (byte == 0x5cL) {
      if (i == m) {
        return(NULL)
      }
      keep[[i]] <- FALSE
      i <- i + 2L
    } else if (byte == 0x22L) {
      return(NULL)
    } else {
      i <- i + 1L
    }
  }
  inner[keep]
}

# Parses a Content-Type field value. Returns a list with `reason` (NA when
# the value parses; else "repeated" for one media type sent more than once,
# "comma" for another comma, or "syntax"), `media_type` (lowercased) and
# `charsets` (each `charset` parameter's value, unquoted and lowercased).
content_type_parse <- function(value) {
  malformed <- function(reason) {
    list(reason = reason, media_type = NA_character_, charsets = character())
  }
  bytes <- as.integer(charToRaw(value))
  scan <- content_type_scan(bytes)
  if (!is.null(scan$reason)) {
    return(malformed(scan$reason))
  }
  if (length(scan$comma) > 0L) {
    pieces <- vapply(content_type_cut(bytes, scan$comma), function(piece) {
      content_type_lower(content_type_trim(piece))
    }, character(1L))
    repeated <- length(unique(pieces)) == 1L &&
      is.na(content_type_parse(pieces[[1L]])$reason)
    return(malformed(if (repeated) "repeated" else "comma"))
  }
  parts <- content_type_cut(bytes, scan$semi)
  media <- content_type_trim(parts[[1L]])
  slash <- which(media == 0x2fL)
  if (length(slash) != 1L ||
        !content_type_is_token(media[seq_len(slash - 1L)]) ||
        !content_type_is_token(media[-seq_len(slash)])) {
    return(malformed("syntax"))
  }
  charsets <- character()
  for (part in parts[-1L]) {
    part <- content_type_trim(part)
    if (length(part) == 0L) {
      next
    }
    equals <- match(0x3dL, part)
    if (is.na(equals) || !content_type_is_token(part[seq_len(equals - 1L)])) {
      return(malformed("syntax"))
    }
    name <- content_type_lower(part[seq_len(equals - 1L)])
    value_bytes <- part[-seq_len(equals)]
    # An empty value is neither a token nor a quoted-string.
    if (length(value_bytes) == 0L) {
      return(malformed("syntax"))
    }
    parameter <- if (value_bytes[[1L]] == 0x22L) {
      content_type_unquote(value_bytes)
    } else if (content_type_is_token(value_bytes)) {
      value_bytes
    }
    if (is.null(parameter)) {
      return(malformed("syntax"))
    }
    if (identical(name, "charset")) {
      charsets <- c(charsets, content_type_lower(parameter))
    }
  }
  list(
    reason = NA_character_, media_type = content_type_lower(media),
    charsets = charsets
  )
}

# The sentence a Content-Type row ends with on a compressed body
# (ROBO-rozvglkd), in place of one that says how the body was read.
content_type_compressed_note <- paste(
  "The body is compressed and was not read as rules (see compressed_body);",
  "robotstxtr's results do not depend on the header."
)

content_type_malformed_message <- function(reason, compressed = FALSE) {
  serve <- if (identical(reason, "repeated")) {
    NULL
  } else {
    "Serve robots.txt as text/plain (RFC 9309 section 2.3)."
  }
  why <- switch(
    reason,
    repeated = paste(
      "It holds the same media type more than once: the response sent",
      "several Content-Type fields (joined here with \", \"); send one",
      "Content-Type field."
    ),
    comma = paste(
      "It holds a comma outside a quoted string: the response sent",
      "several Content-Type fields (joined here with \", \") or one field",
      "listing several values."
    ),
    paste(
      "It is not one type/subtype media type with name=value parameters",
      "(RFC 9110 section 8.3.1)."
    )
  )
  read <- if (compressed) {
    content_type_compressed_note
  } else {
    paste(
      "The body was still validated, and robotstxtr's results do not depend",
      "on the header."
    )
  }
  paste(c(
    "The response's Content-Type header is malformed.", why, serve, read
  ), collapse = " ")
}

# The message of a `content_type_charset_unsupported` row for one declared
# charset, or NULL when the charset is supported. A compressed body's row
# says only what the header declares: no wording depends on its bytes.
content_type_charset_message <- function(charset, ascii_body,
                                         compressed = FALSE) {
  shown <- render_validation_line(charToRaw(charset))
  if (compressed && !(charset %in% c("utf-8", content_type_us_ascii))) {
    declared <- if (nzchar(charset)) {
      sprintf("charset %s", shown)
    } else {
      "an empty charset"
    }
    return(paste(
      sprintf("The response's Content-Type declares %s, not", declared),
      "charset=utf-8, which RFC 9309 section 2.3 asks for.",
      content_type_compressed_note
    ))
  }
  if (!nzchar(charset)) {
    paste(
      "The response's Content-Type declares an empty charset. Declare",
      "charset=utf-8 (RFC 9309 section 2.3); the body is read as UTF-8",
      "either way."
    )
  } else if (charset %in% c("utf-8", content_type_us_ascii)) {
    NULL
  } else if (charset %in% content_type_utf8_nonstandard) {
    sprintf(paste(
      "The response's Content-Type declares charset %s, a nonstandard label",
      "that browsers read as UTF-8 but not the registered name. Declare",
      "charset=utf-8 (RFC 9309 section 2.3); the body is read as UTF-8",
      "either way."
    ), shown)
  } else if (ascii_body &&
               grepl(content_type_ascii_compatible, charset, useBytes = TRUE)) {
    sprintf(paste(
      "The response's Content-Type declares charset %s, not UTF-8, which RFC",
      "9309 section 2.3 asks for. The body is plain ASCII, so it reads the",
      "same in either; declare charset=utf-8."
    ), shown)
  } else {
    sprintf(paste(
      "The response's Content-Type declares charset %s, not UTF-8 (RFC",
      "9309 section 2.3). The body is read as UTF-8 regardless, with no",
      "transcoding, so text in that charset may not read as intended."
    ), shown)
  }
}

# The Content-Type diagnostic rows for one fetched body: a list of zero to
# two rows, in the order malformed or (media type, then charset, then the
# us-ascii conflict). A missing header (NA) gives none: the bytes cannot
# establish what a server left out. `encoding_signature` is the document
# column validate_document_bytes() filled; a UTF-16 or UTF-32 body is
# `utf16_or_utf32_encoding`'s, so it gets no us-ascii conflict and is not
# called plain ASCII. `compressed` is TRUE for a body that drew
# compressed_body (ROBO-rozvglkd): its rows say the body was not read, none
# depends on its bytes, and it gets no us-ascii conflict.
content_type_diagnostics <- function(source_id, content_type, body,
                                     encoding_signature, compressed = FALSE) {
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
    return(list(row(
      "content_type_malformed",
      content_type_malformed_message(parsed$reason, compressed)
    )))
  }
  rows <- list()
  if (!identical(parsed$media_type, "text/plain")) {
    read <- if (compressed) {
      content_type_compressed_note
    } else {
      paste(
        "Crawlers may still read the body as a robots.txt, and robotstxtr",
        "validated it as one; its results do not depend on the header."
      )
    }
    rows[[length(rows) + 1L]] <- row("content_type_not_text_plain", paste(
      sprintf(
        paste(
          "The response's Content-Type is %s, not text/plain, which RFC 9309",
          "section 2.3 asks for."
        ),
        render_validation_line(charToRaw(parsed$media_type))
      ),
      read
    ))
  }
  charsets <- unique(parsed$charsets)
  wide <- encoding_signature %in% content_type_wide_signatures
  high <- any(body >= as.raw(0x80))
  if (length(charsets) > 1L) {
    read <- if (compressed) {
      paste("Declare charset=utf-8 once (RFC 9309 section 2.3).",
            content_type_compressed_note)
    } else {
      paste(
        "Declare charset=utf-8 once (RFC 9309 section 2.3); the body is read",
        "as UTF-8 either way."
      )
    }
    rows[[length(rows) + 1L]] <- row("content_type_charset_unsupported", paste(
      "The response's Content-Type declares charset more than once, with",
      "different values, so the declared encoding is ambiguous.", read
    ))
  } else if (length(charsets) == 1L) {
    message <- content_type_charset_message(
      charsets, !high && !wide, compressed
    )
    if (!is.null(message)) {
      rows[[length(rows) + 1L]] <- row(
        "content_type_charset_unsupported", message
      )
    } else if (!compressed && charsets %in% content_type_us_ascii &&
                 high && !wide) {
      declared <- if (identical(charsets, "us-ascii")) {
        "us-ascii"
      } else {
        sprintf("%s (US-ASCII)", render_validation_line(charToRaw(charsets)))
      }
      rows[[length(rows) + 1L]] <- row("content_type_charset_conflict", paste(
        "The response's Content-Type declares charset", paste0(declared, ","),
        "but the body holds bytes of 0x80 or above, which US-ASCII does not",
        "have. Declare charset=utf-8 (RFC 9309 section 2.3); the bytes are",
        "validated as UTF-8 as before."
      ))
    }
  }
  rows
}
