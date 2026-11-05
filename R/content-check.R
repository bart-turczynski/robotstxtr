# A quick look at a fetched robots.txt body: does it look like something other
# than a robots.txt (ROBO-nhuirvrd)? Servers answer /robots.txt with an HTML
# error or login page, an XML or JSON API error, or a binary file, often with
# a 200. The check is a heuristic and only FLAGS: the body is matched exactly
# as before, and no allow or disallow decision depends on the flag.
#
# The flag comes from the body alone. The response's Content-Type is reported
# beside it, unread here, so a caller can compare the two.
#
# The closed vocabulary, first match wins:
#
# - "binary": the window holds a NUL byte, or more than
#   `content_invalid_utf8_share` of its bytes are not part of valid UTF-8.
#   NULs are still dropped before matching (R/body-decode.R); the flag only
#   makes them visible on the fetch row.
# - "html": a line in the window starts, after optional spaces or tabs (and a
#   UTF-8 BOM), with `<!doctype html`, `<html`, `<head` or `<body`, in any
#   letter case. A `<` inside a comment line never starts a line.
# - "xml": the first non-whitespace byte is `<` (an XML declaration, an
#   element such as an S3 `<Error>`, a markup comment). No robots.txt line
#   starts with `<`.
# - "json": the first non-whitespace byte opens a JSON object (`{` then `"`
#   or `}`) or array (`[` then a JSON value or `]`).
# - NA: none of these, an empty body, or no body.
#
# Only the first `content_check_bytes` bytes are read, so the cost is bounded
# whatever the body size. A multibyte character cut at the window's end counts
# as at most three invalid bytes, which the share threshold absorbs.

content_check_bytes <- 4096L
content_invalid_utf8_share <- 0.1

content_flag_values <- c("binary", "html", "xml", "json")

robots_content_flag <- function(body) {
  if (is.null(body) || length(body) == 0L) {
    return(NA_character_)
  }
  window <- body[seq_len(min(length(body), content_check_bytes))]
  if (any(window == as.raw(0L)) || content_mostly_invalid(window)) {
    return("binary")
  }
  if (length(window) >= 3L &&
        identical(window[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) {
    window <- window[-(1:3)]
  }
  text <- rawToChar(window)
  if (grepl(content_html_pattern, text, perl = TRUE, useBytes = TRUE)) {
    return("html")
  }
  if (grepl("^\\s*<", text, perl = TRUE, useBytes = TRUE)) {
    return("xml")
  }
  if (grepl(content_json_pattern, text, perl = TRUE, useBytes = TRUE)) {
    return("json")
  }
  NA_character_
}

# Any line (CR, LF or CRLF ended) opening with an HTML doctype or one of the
# three document tags, followed by whitespace, `>`, `/` or the line's end.
content_html_pattern <- paste0(
  "(*ANYCRLF)(?im)^[ \\t]*",
  "<(!doctype[ \\t\\r\\n]+html|html|head|body)(?=[\\s>/]|$)"
)

content_json_pattern <-
  "^\\s*(\\{\\s*[\"}]|\\[\\s*([\\[{\"\\]0-9-]|true|false|null))"

# TRUE when more than `content_invalid_utf8_share` of `bytes` (NUL-free) are
# not part of a valid UTF-8 sequence. iconv() writes each such byte as the
# four bytes "<xx>", so the count is the length gained, divided by three.
content_mostly_invalid <- function(bytes) {
  text <- rawToChar(bytes)
  marked <- iconv(text, "UTF-8", "UTF-8", sub = "byte")
  invalid <- (nchar(marked, type = "bytes") - length(bytes)) / 3
  invalid > content_invalid_utf8_share * length(bytes)
}
