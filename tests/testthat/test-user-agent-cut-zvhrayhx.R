# ROBO-zvhrayhx: the matcher reads a User-agent value only up to its first
# byte outside [A-Za-z_-] (src/robots.cc, RobotsMatcher::ExtractUserAgent).
#
# Pins the current behavior: no diagnostic says the value was cut.

uac_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

uac_codes <- function(value) {
  robots_validate_text(uac_lines(paste0("User-agent: ", value),
                                 "Disallow: /x"))$diagnostics$code
}

test_that("a cut User-agent value is not flagged today", {
  for (value in c("Foo Bot", "Bot2", "*bot", "Googlebot/2.1")) {
    expect_identical(uac_codes(value), character(), label = value)
  }
})
