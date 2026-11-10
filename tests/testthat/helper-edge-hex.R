# The `.hex` fixture decoder shared by the edge-case catalog tests
# (ROBO-mxermwed) and the library comparison tests (ROBO-dqqkvwts).
#
# Lowercase hex digits and whitespace only, an even number of digits: any
# other character or a dangling nibble is a broken fixture, not a byte.
edge_hex_bytes <- function(lines, file = "hex") {
  text <- paste(lines, collapse = "\n")
  if (grepl("[^0-9a-f[:space:]]", text)) {
    stop(sprintf("%s: a character outside [0-9a-f] and whitespace", file))
  }
  hex <- gsub("[[:space:]]", "", text)
  if (nchar(hex) %% 2L != 0L) {
    stop(sprintf("%s: an odd number of hex digits", file))
  }
  starts <- seq(1L, nchar(hex), by = 2L)
  as.raw(strtoi(substring(hex, starts, starts + 1L), 16L))
}
