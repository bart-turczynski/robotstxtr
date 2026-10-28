# Locale-independent case folding (SEOR-tldlaxgq; the fleet's locale line,
# modeled on pslr's tests).
#
# tolower(), toupper() and casefold() follow LC_CTYPE. Under a Turkish or Azeri
# locale on glibc, "I" lowercases to the dotless "ı" and "i" uppercases to the
# dotted "İ", so an ASCII protocol token stops matching its constant: "BINGBOT"
# no longer resolves to the bingbot profile, "NOINDEX" is no longer a known
# directive. Every fold in robotstxtr is of ASCII protocol text, so it goes
# through ascii_lower(), and .lintr bans the three base functions.
#
# macOS's libc does not map "I" specially even under tr_TR, so the locale legs
# below cannot go red there; the namespace pin runs everywhere.

lf_locales <- c("tr_TR.UTF-8", "az_AZ.UTF-8")

# Run `code` with LC_CTYPE set to `locale`; skip when the platform lacks it.
lf_with_ctype <- function(locale, code) {
  old <- Sys.getlocale("LC_CTYPE")
  on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
  set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
  skip_if(!nzchar(set), paste(locale, "locale not installed"))
  force(code)
}

# The answers whose case-insensitive matching of ASCII tokens a locale could
# change. Each input carries an "I" or "i" in the part that is folded.
lf_answers <- function() {
  validation <- robots_validate_text(paste(
    "USER-AGENT: *",
    "DISALLOW: /private",
    "NOINDEX: /x",
    "VISIT-TIME: 0600-0845",
    sep = "\n"
  ))
  decision <- allowed_by_robots_text(
    "USER-AGENT: BINGBOT\nDISALLOW: /PRIVATE\nUser-Agent: *\nAllow: /",
    c("https://example.com/PRIVATE/x", "https://example.com/public"),
    "bingbot"
  )
  list(
    profile_bing = robots_resolve_matcher_profile_v1(
      "bing", c("BINGBOT", "BingBot", "ADIDXBOT")
    )$accepted_token,
    profile_yandex = robots_resolve_matcher_profile_v1(
      "yandex", c("YANDEX", "YANDEXADDITIONALBOT")
    )$accepted_token,
    validation_codes = sort(validation$diagnostics$code),
    validation_directives = sort(validation$diagnostics$directive),
    unsupported = validation$documents$unsupported_directives,
    decisions = decision$results$allowed,
    origin = robots_origin("HTTPS://WWW.WIKIPEDIA.ORG:8443/robots.txt"),
    ssrf = ssrf_check(
      "METADATA.GOOGLE.INTERNAL", "HTTP",
      raw_host = "METADATA.GOOGLE.INTERNAL"
    )$reason
  )
}

test_that("no namespace function calls a locale-dependent case fold", {
  # Locale-free: holds on every platform, including macOS where tolower() does
  # not misfold under tr_TR.
  ns <- asNamespace("robotstxtr")
  banned <- c("tolower", "toupper", "casefold")
  offenders <- character()
  for (name in ls(ns, all.names = TRUE)) {
    f <- get(name, envir = ns)
    if (is.function(f) && !is.primitive(f)) {
      used <- c(all.names(body(f)), unlist(lapply(formals(f), all.names)))
      if (any(banned %in% used)) {
        offenders <- c(offenders, name)
      }
    }
  }
  expect_identical(offenders, character())
})

lf_check_ascii_lower <- function() {
  expect_identical(ascii_lower("I"), "i")
  expect_identical(ascii_lower("BINGBOT"), "bingbot")
  expect_identical(ascii_lower("İ"), "İ") # dotted capital I stays
  expect_identical(ascii_lower("ı"), "ı") # dotless small i stays
  expect_identical(ascii_lower("École"), "École") # É stays
  expect_identical(ascii_lower(c("A", NA)), c("a", NA))
  expect_identical(ascii_lower(character()), character())
}

test_that("ascii_lower() maps A-Z only", {
  lf_check_ascii_lower()
})

for (locale in lf_locales) {
  test_that(paste("ascii_lower() maps A-Z only under", locale), {
    lf_with_ctype(locale, lf_check_ascii_lower())
  })

  test_that(paste("ASCII tokens match the same under", locale), {
    expected <- lf_answers()
    # The baseline itself, so an equal-but-wrong answer cannot pass.
    expect_identical(
      expected$profile_bing, c("bingbot", "bingbot", "adidxbot")
    )
    expect_identical(
      expected$profile_yandex, c("Yandex", "YandexAdditionalBot")
    )
    expect_identical(expected$unsupported, 2L)
    expect_identical(expected$decisions, c(FALSE, TRUE))
    expect_identical(
      expected$origin, "https://www.wikipedia.org:8443/robots.txt"
    )
    expect_identical(expected$ssrf, "cloud-metadata")

    lf_with_ctype(locale, expect_identical(lf_answers(), expected))
  })
}
