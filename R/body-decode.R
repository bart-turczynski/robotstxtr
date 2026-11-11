# NUL-safe decoding of acquired robots.txt bytes (PRD 6.6 body handling).
#
# R's character type cannot carry a NUL byte. `rawToChar()` raises
# "embedded nul in string" as soon as a NUL is followed by another byte, and the
# parse collector's value channel (`Rf_mkCharLenCE()`) raises the same way. So
# every decode of ACQUIRED bytes leaves the NUL bytes out before crossing into
# R's string world. Fetched bodies do carry NULs in the wild -- a
# UTF-16-encoded robots.txt, a WAF challenge page, a truncated or NUL-padded
# response -- and fetching is best-effort everywhere else in this package (a
# 404, an SSRF block and a transport failure all degrade), so a NUL-bearing
# body degrades too instead of aborting the call.
#
# Two readings, one per consumer:
# - The Google matcher (`decode_matcher_body()`, ROBO-pvqrfvol) reads the body
#   as Google's open-source parser does. That parser hands each line on as a
#   NUL-terminated C string, so a line ends at its first NUL: "\0Disallow: /x"
#   is an empty line, and "Disallow: /a\0b" is the rule "/a". Each line is cut
#   at its first NUL and the lines are joined again, so the decision and the
#   matched line equal upstream's. This is parity with the open-source parser,
#   not a claim about what Googlebot does in production.
# - The body preview (`robots_body()`) removes the NUL bytes and keeps every
#   other byte, in order (`nul_free_bytes()`, ROBO-hcqrzikz): it shows the
#   document, it does not match it.
# The Bing and Yandex bindings take the raw body and read a NUL as an ordinary
# byte; their bodies never pass through this file.
#
# The malformation stays VISIBLE rather than silent: `robots_validate_text()`
# reports a `nul_byte` diagnostic at severity "error" for every line carrying
# one (and renders it as `\x00` in the diagnostic's `raw_text`); its parser
# ends a line at its first NUL, as the Google matcher does.
nul_free_bytes <- function(bytes) {
  bytes[bytes != as.raw(0)]
}

# The body as Google's parser reads it, each line cut at its first NUL
# (src/robots.cc, RobotsTxtParser::Parse()). A body with no NUL is returned
# unchanged. Otherwise the lines are split as upstream splits them -- CR, LF
# and CRLF each end a line, and an LF right after a CR only finishes the CRLF
# -- and joined with LF. Joining with LF keeps every line number: "\r\0\n" is
# two line ends around an empty line, and dropping only the NUL would leave one
# CRLF and move every later line up by one. The BOM bytes at the start stay,
# since the matcher skips them itself, and the last line keeps or lacks its
# terminator as the body does.
nul_line_end_bytes <- function(bytes) {
  nul <- bytes == as.raw(0)
  if (!any(nul)) {
    return(bytes)
  }
  cr <- bytes == as.raw(0x0d)
  lf <- bytes == as.raw(0x0a)
  keep <- !(lf & c(FALSE, cr[-length(cr)]))
  bytes <- bytes[keep]
  nul <- nul[keep]
  ends <- cr[keep] | lf[keep]
  # A byte is kept when its line holds no NUL up to it: the NULs counted
  # through it equal the count at the line end before it.
  seen <- cumsum(nul)
  last_end <- cummax(ifelse(ends, seq_along(bytes), 0L))
  before_line <- c(0L, seen)[last_end + 1L]
  bytes[ends] <- as.raw(0x0a)
  bytes[ends | seen == before_line]
}

# Decode acquired bytes into the length-one string handed to the Google C++
# matcher and the parse collector, each line cut at its first NUL
# (`nul_line_end_bytes()`). The bytes are NOT validated as UTF-8: the result is
# marked UTF-8 so cpp11 forwards the exact bytes without translating or
# re-encoding them, which is how an invalid-UTF-8 body still reaches the
# byte-oriented matcher intact (PRD 6.2 bridge).
decode_matcher_body <- function(bytes) {
  out <- rawToChar(nul_line_end_bytes(bytes))
  Encoding(out) <- "UTF-8"
  out
}
