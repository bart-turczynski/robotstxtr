# Supplied text bodies keep their bytes in every locale (ROBO-tipzbglv).
#
# A body passed as a string with no declared encoding (Encoding "unknown", as
# rawToChar() or readLines() without `encoding =` gives) is taken as UTF-8
# bytes as written. Running enc2utf8() on it re-encodes it as native-locale
# text: under LC_CTYPE C the native charset is ASCII, so each non-ASCII byte
# became a "<xx>" escape, the body grew and its rules changed. The locale is
# switched in-process, so these tests bite on any machine, not only on the
# gate's LC_ALL=C leg. Each entry point has its own assertion.

te_url <- "http://example.com/caf%C3%A9"

# Run `code` with LC_CTYPE set to the first of `locales` that the platform
# accepts; skip when it has none of them.
te_with_ctype <- function(locales, code) {
  old <- Sys.getlocale("LC_CTYPE")
  on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
  for (locale in locales) {
    set <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    if (identical(set, locale)) {
      return(force(code))
    }
  }
  skip(paste("none of", toString(locales), "is available"))
}

te_utf8_locales <- c("C.UTF-8", "en_US.UTF-8")

# The ticket's reproduction: a Disallow rule whose path holds U+00E9 as the
# two UTF-8 bytes C3 A9, in an unmarked string.
te_raw <- c(
  charToRaw("User-agent: *\nDisallow: /caf"),
  as.raw(c(0xc3, 0xa9)),
  charToRaw("\n")
)
te_body <- function() rawToChar(te_raw)

# Other unmarked shapes: a leading byte-order mark, invalid UTF-8, ASCII only,
# and the empty body.
te_unmarked_raws <- list(
  repro = te_raw,
  bom = c(
    as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("User-agent: *\nDisallow: /x\n")
  ),
  invalid = c(
    charToRaw("User-agent: *\nDisallow: /a"), as.raw(0xff), charToRaw("\n")
  ),
  ascii = charToRaw("User-agent: *\nDisallow: /x\n"),
  empty = raw(0)
)

# The bytes each entry point stores for `body`.
te_stored <- function(body) {
  list(
    evaluate = robots_evaluate_text_v1(
      body, "http://example.com/x", "bot", "google", "google"
    )$evidence$body[[1L]],
    allowed = allowed_by_robots_text(
      body, "http://example.com/x", "bot"
    )$robots$body[[1L]],
    validate = robots_validate_text(body)$documents$byte_size
  )
}

test_that("the reproduction body is unmarked", {
  expect_identical(Encoding(te_body()), "unknown")
})

test_that("robots_evaluate_text_v1() keeps unmarked bytes under LC_CTYPE C", {
  te_with_ctype("C", {
    x <- robots_evaluate_text_v1(te_body(), te_url, "bot", "google", "google")
    expect_identical(x$evidence$stored_bytes, length(te_raw))
    expect_identical(x$results$url_decision, "disallow")
  })
})

test_that("allowed_by_robots_text() keeps unmarked bytes under LC_CTYPE C", {
  te_with_ctype("C", {
    x <- allowed_by_robots_text(te_body(), te_url, "bot")
    expect_identical(x$robots$body[[1L]], te_raw)
    expect_false(x$results$allowed)
  })
})

test_that("robots_validate_text() keeps unmarked bytes under LC_CTYPE C", {
  te_with_ctype("C", {
    x <- robots_validate_text(te_body())
    expect_identical(x$documents$byte_size, length(te_raw))
  })
})

test_that("a UTF-8 locale reads the reproduction as written", {
  te_with_ctype(te_utf8_locales, {
    ev <- robots_evaluate_text_v1(te_body(), te_url, "bot", "google", "google")
    expect_identical(ev$evidence$stored_bytes, length(te_raw))
    expect_identical(ev$results$url_decision, "disallow")
    al <- allowed_by_robots_text(te_body(), te_url, "bot")
    expect_identical(al$robots$body[[1L]], te_raw)
    expect_false(al$results$allowed)
    va <- robots_validate_text(te_body())
    expect_identical(va$documents$byte_size, length(te_raw))
  })
})

test_that("unmarked bodies store identical bytes under C and UTF-8", {
  for (name in names(te_unmarked_raws)) {
    raw_body <- te_unmarked_raws[[name]]
    body <- rawToChar(raw_body)
    expect_identical(Encoding(body), "unknown", label = name)
    in_c <- te_with_ctype("C", te_stored(body))
    in_utf8 <- te_with_ctype(te_utf8_locales, te_stored(body))
    expect_identical(in_c, in_utf8, label = name)
    expect_identical(in_c$evaluate, raw_body, label = name)
    expect_identical(in_c$allowed, raw_body, label = name)
    expect_identical(in_c$validate, length(raw_body), label = name)
  }
})

test_that("bodies marked UTF-8 or bytes keep their bytes under C", {
  marked_utf8 <- rawToChar(te_raw)
  Encoding(marked_utf8) <- "UTF-8"
  marked_bytes <- rawToChar(te_raw)
  Encoding(marked_bytes) <- "bytes"
  for (body in list(marked_utf8, marked_bytes)) {
    stored <- te_with_ctype("C", te_stored(body))
    expect_identical(stored$evaluate, te_raw)
    expect_identical(stored$allowed, te_raw)
    expect_identical(stored$validate, length(te_raw))
  }
})

test_that("a body marked latin1 is still converted to UTF-8", {
  latin1 <- rawToChar(c(charToRaw("Disallow: /caf"), as.raw(0xe9)))
  Encoding(latin1) <- "latin1"
  stored <- te_stored(latin1)
  expect_identical(
    stored$allowed,
    c(charToRaw("Disallow: /caf"), as.raw(c(0xc3, 0xa9)))
  )
})

# In an 8-bit native locale an unmarked string is native text, so it is still
# converted to UTF-8: the native byte E9 (U+00E9 in both ISO-8859-1 and
# ISO-8859-15) becomes C3 A9, which is the reproduction's own UTF-8 body.
te_native_body <- function() {
  rawToChar(c(
    charToRaw("User-agent: *\nDisallow: /caf"), as.raw(0xe9), charToRaw("\n")
  ))
}

for (te_locale in c("en_US.ISO8859-1", "fr_FR.ISO8859-15")) {
  test_that(paste("robots_evaluate_text_v1() converts unmarked text under",
                  te_locale), {
    te_with_ctype(te_locale, {
      body <- te_native_body()
      expect_identical(Encoding(body), "unknown")
      x <- robots_evaluate_text_v1(body, te_url, "bot", "google", "google")
      expect_identical(x$evidence$body[[1L]], te_raw)
      expect_identical(x$results$url_decision, "disallow")
    })
  })

  test_that(paste("allowed_by_robots_text() converts unmarked text under",
                  te_locale), {
    te_with_ctype(te_locale, {
      x <- allowed_by_robots_text(te_native_body(), te_url, "bot")
      expect_identical(x$robots$body[[1L]], te_raw)
      expect_false(x$results$allowed)
    })
  })

  test_that(paste("robots_validate_text() converts unmarked text under",
                  te_locale), {
    te_with_ctype(te_locale, {
      x <- robots_validate_text(te_native_body())
      expect_identical(x$documents$byte_size, length(te_raw))
      expect_false("invalid_utf8" %in% x$diagnostics$code)
    })
  })
}
