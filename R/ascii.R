# Locale-independent ASCII lowercase (SEOR-tldlaxgq; modeled on pslr's
# R/ascii.R, same body as sitemapr's ascii_lower()).
#
# Base R's tolower() follows the session's LC_CTYPE. Under a Turkish or Azeri
# locale on glibc, "I" lowercases to the dotless "ı", so a comparison on a
# protocol string fails silently: "METADATA.GOOGLE.INTERNAL" stopped matching
# the blocked name (ROBO-dxrljrde), "BINGBOT" stops resolving to the bingbot
# profile, "NOINDEX" stops being a known directive. Every string robotstxtr
# folds (URL schemes and hosts, product tokens, robots.txt directive names,
# hex digests) is ASCII by definition or compared against ASCII constants, so
# only A-Z are mapped and anything else passes through unchanged. .lintr bans
# tolower(), toupper() and casefold() so a new call site cannot reintroduce
# the locale dependence.
ascii_lower <- function(x) {
  chartr(paste(LETTERS, collapse = ""), paste(letters, collapse = ""), x)
}
