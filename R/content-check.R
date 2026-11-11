# A quick look at a fetched robots.txt body: does it look like something other
# than a robots.txt (ROBO-nhuirvrd)? Servers answer /robots.txt with an HTML
# error or login page, an XML or JSON API error, or a binary file, often with
# a 200. The check is a heuristic and only FLAGS: the body is matched exactly
# as before, and no allow or disallow decision depends on the flag.
#
# The flag comes from the body alone. The response's Content-Type is reported
# beside it, unread here, so a caller can compare the two. The flag is read on
# fetch rows and by the validator, whose `html_body` warning is its "html"
# answer (ROBO-ccfsanhq).
#
# The closed vocabulary, first match wins:
#
# - "binary": the window holds a NUL byte, or at least
#   `content_min_invalid_bytes` of its bytes, and more than
#   `content_invalid_utf8_share` of them, are not part of valid UTF-8, so a
#   short Latin-1 robots.txt is not binary. NULs are still dropped before
#   matching (R/body-decode.R); the flag only makes them visible on the fetch
#   row.
# - "html": a line in the window starts, after optional whitespace (and a
#   UTF-8 BOM), with `<!doctype html`, `<html`, `<head` or `<body`, in any
#   letter case, possibly after XML declarations or processing instructions
#   (`<?...?>`) and markup comments (`<!--...-->`) that each close on their
#   own line. A `<` inside a robots.txt comment line never starts a line.
#   Or the first non-whitespace byte is `<`, the root is HTML (ROBO-isbpzgqn:
#   after `<?...?>` and `<!--...-->` items, an html doctype or a first start
#   tag whose name, after any namespace prefix, is in
#   `content_html_element_names`), and `<!doctype html`, `<html`, `<head`,
#   `<body`, `<script` or `<style` appears anywhere in the window, as a
#   minified page puts them mid-line (ROBO-qquftxcx). `<title`, `<link` and
#   `<meta` are left out: RSS and Atom feeds use them.
# - "xml": the first non-whitespace byte is `<` (an XML declaration, an
#   element such as an S3 `<Error>`, a root that is not HTML such as an SVG
#   or a feed, a markup comment, or HTML tag soup with none of the six markers
#   above). No robots.txt line starts with `<`.
# - "json": the first non-whitespace byte opens a JSON object (`{` then `"`
#   or `}`) or array (`[` then a JSON value or `]`).
# - NA: none of these, an empty body, or no body.
#
# Only the first `content_check_bytes` bytes are read, so the cost is bounded
# whatever the body size. A multibyte character cut at the window's end counts
# as at most three invalid bytes, which the share threshold absorbs.

content_check_bytes <- 4096L
content_invalid_utf8_share <- 0.1
content_min_invalid_bytes <- 8L

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
    # The anywhere markers count only under an HTML root (ROBO-isbpzgqn).
    if (grepl(content_html_root_pattern, text, perl = TRUE, useBytes = TRUE)) {
      if (grepl(content_html_tag_pattern, text, perl = TRUE,
                useBytes = TRUE)) {
        return("html")
      }
    }
    return("xml")
  }
  if (grepl(content_json_pattern, text, perl = TRUE, useBytes = TRUE)) {
    return("json")
  }
  NA_character_
}

# Any line (CR, LF or CRLF ended) opening, after whitespace and any
# same-line `<?...?>` or `<!--...-->`, with an HTML doctype or one of the
# three document tags, followed by whitespace, `>`, `/` or the line's end.
# Whitespace is `\s`, as in the "xml" test.
content_html_pattern <- paste0(
  "(*ANYCRLF)(?im)^\\s*",
  "(?:(?:<\\?[^\\r\\n]*?\\?>|<!--[^\\r\\n]*?-->)\\s*)*",
  "<(!doctype\\s+html|html|head|body)(?=[\\s>/]|$)"
)

# The HTML element names a root may have (ROBO-isbpzgqn): the WHATWG living
# standard's elements and its obsolete ones, matched case-insensitively. `svg`
# and `math` are foreign to HTML, so an SVG or MathML root never counts.
content_html_element_names <- c(
  "a", "abbr", "acronym", "address", "applet", "area", "article", "aside",
  "audio", "b", "base", "basefont", "bdi", "bdo", "bgsound", "big", "blink",
  "blockquote", "body", "br", "button", "canvas", "caption", "center", "cite",
  "code", "col", "colgroup", "data", "datalist", "dd", "del", "details",
  "dfn", "dialog", "dir", "div", "dl", "dt", "em", "embed", "fieldset",
  "figcaption", "figure", "font", "footer", "form", "frame", "frameset", "h1",
  "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr", "html", "i",
  "iframe", "img", "input", "ins", "isindex", "kbd", "keygen", "label",
  "legend", "li", "link", "listing", "main", "map", "mark", "marquee", "menu",
  "menuitem", "meta", "meter", "multicol", "nav", "nextid", "nobr", "noembed",
  "noframes", "noscript", "object", "ol", "optgroup", "option", "output", "p",
  "param", "picture", "plaintext", "pre", "progress", "q", "rb", "rp", "rt",
  "rtc", "ruby", "s", "samp", "script", "search", "section", "select", "slot",
  "small", "source", "spacer", "span", "strike", "strong", "style", "sub",
  "summary", "sup", "table", "tbody", "td", "template", "textarea", "tfoot",
  "th", "thead", "time", "title", "tr", "track", "tt", "u", "ul", "var",
  "video", "wbr", "xmp"
)

# The root of a body that opens with markup (ROBO-isbpzgqn). After any
# `<?...?>` and `<!--...-->` items, it is an html doctype, or a first start tag
# whose local name (after an optional namespace prefix) is an HTML element
# name. Any other doctype, or a root that is not HTML, is no match, so the
# anywhere rule below stays off. Each item ends at its own closing marker.
content_html_root_pattern <- paste0(
  "(?i)^\\s*(?:(?:<\\?(?:(?!\\?>)[\\s\\S])*\\?>",
  "|<!--(?:(?!-->)[\\s\\S])*-->)\\s*)*",
  "(?:<!doctype\\s+html(?=[\\s>/]|\\z)",
  "|<(?:[a-z_][\\w.-]*:)?(?:",
  paste(content_html_element_names, collapse = "|"),
  ")(?=[\\s/>]|\\z))"
)

# Anywhere in a window whose root is HTML: an HTML doctype or one of the
# document, script or style tags, followed by whitespace, `>`, `/` or the
# window's end, so `<header>` or `<scripts>` does not count.
content_html_tag_pattern <-
  "(?i)<(!doctype\\s+html|html|head|body|script|style)(?=[\\s>/]|\\z)"

content_json_pattern <-
  "^\\s*(\\{\\s*[\"}]|\\[\\s*([\\[{\"\\]0-9-]|true|false|null))"

# TRUE when at least `content_min_invalid_bytes` of `bytes` (NUL-free), and
# more than `content_invalid_utf8_share` of them, are not part of a valid
# UTF-8 sequence. iconv() writes each such byte as the four bytes "<xx>", so
# the count is the length gained, divided by three.
content_mostly_invalid <- function(bytes) {
  text <- rawToChar(bytes)
  marked <- iconv(text, "UTF-8", "UTF-8", sub = "byte")
  invalid <- (nchar(marked, type = "bytes") - length(bytes)) / 3
  invalid >= content_min_invalid_bytes &&
    invalid > content_invalid_utf8_share * length(bytes)
}
