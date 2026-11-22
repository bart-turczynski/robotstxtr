# ROBO-rswdwrnp: an Allow or Disallow pattern with a `%` that starts no
# two-hex-digit escape. These pins record today's codes for every shape the
# new check reads, and the package's matchers on each shape.

# The validator's codes for one rule line, after a User-agent line.
ip_codes <- function(value, type = "Disallow") {
  robots_validate_text(
    paste0("User-agent: *\n", type, ": ", value, "\n")
  )$diagnostics$code
}

# A body from pieces: a string is text, a raw vector is bytes.
ip_body <- function(...) {
  parts <- list(...)
  unlist(lapply(parts, function(p) if (is.raw(p)) p else charToRaw(p)))
}

# Shapes with a stray `%`, each with the codes it gets today.
ip_stray_now <- list(
  "/*hashid=%subscriber_hash%" = character(0),
  "/a%4g" = character(0),
  "/a%$" = character(0),
  "/a%4$" = character(0),
  "/%%25" = character(0),
  "/%2%2e" = c("rule_escaped_unreserved", "rule_lowercase_escape"),
  "/a/./%zz" = "rule_dot_segment",
  "/[% name %]" = "rule_inner_whitespace",
  "/a%" = character(0),
  "/a%4" = character(0),
  "/a%*" = character(0),
  "/a%4*" = character(0),
  "*%*" = character(0)
)

# Shapes with no stray `%`, each with the codes it gets today.
ip_valid_now <- list(
  "/a%2F" = character(0),
  "/a%25" = character(0),
  "/%25%25" = character(0),
  "/a%C3%A9" = character(0),
  "/a%2f" = "rule_lowercase_escape",
  "/a/%2e/b" = c("rule_escaped_unreserved", "rule_lowercase_escape"),
  "/a/%2E%2E/b" = "rule_escaped_unreserved",
  "/p?u={{name}}" = character(0),
  "/*|NAME|*" = character(0)
)

test_that("ROBO-rswdwrnp: today a stray `%` gets no code of its own", {
  for (type in c("Allow", "Disallow")) {
    for (value in names(ip_stray_now)) {
      expect_identical(
        ip_codes(value, type), ip_stray_now[[value]],
        label = paste(type, value)
      )
    }
  }
})

test_that("ROBO-rswdwrnp: valid escapes keep their codes", {
  for (type in c("Allow", "Disallow")) {
    for (value in names(ip_valid_now)) {
      expect_identical(
        ip_codes(value, type), ip_valid_now[[value]],
        label = paste(type, value)
      )
    }
  }
})

test_that("ROBO-rswdwrnp: raw non-ASCII bytes beside a `%`, today", {
  # A raw e-acute (UTF-8 C3 A9), written with escapes to keep this file ASCII.
  e_acute <- as.raw(c(0xc3, 0xa9))
  expect_identical(
    robots_validate_text(ip_body("User-agent: *\nDisallow: /", e_acute,
                                 "\n"))$diagnostics$code,
    character(0)
  )
  expect_identical(
    robots_validate_text(ip_body("User-agent: *\nDisallow: /a%", e_acute,
                                 "\n"))$diagnostics$code,
    character(0)
  )
  # Invalid UTF-8: a lone 0xE9 after a valid escape.
  expect_identical(
    robots_validate_text(ip_body("User-agent: *\nDisallow: /a%2F",
                                 as.raw(0xe9), "\n"))$diagnostics$code,
    "invalid_utf8"
  )
  latin <- "User-agent: *\nDisallow: /a%\xe9\n"
  Encoding(latin) <- "latin1"
  expect_identical(robots_validate_text(latin)$diagnostics$code, character(0))
})

test_that("ROBO-rswdwrnp: a `%` the parser never reads as a rule, today", {
  expect_identical(
    robots_validate_text(ip_body(
      "User-agent: *\nDisallow: /a", as.raw(0), "%zz\n"
    ))$diagnostics$code,
    c("nul_byte", "rule_cut_by_nul")
  )
  expect_identical(ip_codes("/a#%zz"), "rule_cut_by_comment")
  expect_identical(
    robots_validate_text(
      "Sitemap: https://example.com/a%zz.xml\nUser-agent: *\nDisallow: /\n"
    )$diagnostics$code,
    character(0)
  )
  expect_identical(
    robots_validate_text("User-agent: bot%zz\nDisallow: /\n")$diagnostics$code,
    "user_agent_cut"
  )
})

# A value whose last kept byte, the line buffer's 16,663rd, is a `%`.
ip_cut <- function() {
  pre <- "Disallow: /"
  filler <- strrep("a", 16663L - nchar(pre) - 1L)
  robots_validate_text(
    paste0("User-agent: *\n", pre, filler, "%zz\n")
  )$diagnostics$code
}

test_that("ROBO-rswdwrnp: a `%` at the line buffer's end, today", {
  expect_identical(ip_cut(), "line_too_long")
})

# The package's matchers on each class, under the v1 default
# url_normalization = "rfc3986", on google, bing and yandex alike. The rfc9309
# backend is capability_unavailable in every mode (ADR 0002), so it is not
# testable here.
ip_engines <- list(google = "Googlebot", bing = "bingbot", yandex = "Yandex")

ip_eval <- function(rule, paths, backend, mode = "rfc3986") {
  robots_evaluate_text_v1(
    paste0("User-agent: *\nDisallow: ", rule, "\n"),
    paste0("https://example.com", paths), ip_engines[[backend]], backend,
    backend, url_normalization = mode
  )$results
}

ip_stray_note <- "not a valid RFC 3986 URI: stray %"

test_that("ROBO-rswdwrnp: a class (a) `%` matches only the raw `%`", {
  shapes <- list(
    "/a%4g" = c("/a%4g", "/a%254g"),
    "/a%$" = c("/a%", "/a%25"),
    "/*hashid=%subscriber_hash%" = c(
      "/x?hashid=%subscriber_hash%", "/x?hashid=%25subscriber_hash%25"
    )
  )
  for (backend in names(ip_engines)) {
    for (rule in names(shapes)) {
      r <- ip_eval(rule, shapes[[rule]], backend)
      label <- paste(backend, rule)
      expect_identical(r$url_decision, c("disallow", "allow"), label = label)
      expect_identical(r$url_preprocessing_note, c(ip_stray_note, NA),
                       label = label)
    }
    # A real hash value is never matched.
    expect_identical(
      ip_eval("/*hashid=%subscriber_hash%", "/x?hashid=abc",
              backend)$url_decision,
      "allow", label = backend
    )
  }
})

test_that("ROBO-rswdwrnp: a class (a) rule under whatwg keeps the raw URL", {
  skip_if_not_installed("rurl")
  for (backend in names(ip_engines)) {
    r <- ip_eval("/a%4g", c("/a%4g", "/a%254g"), backend, "whatwg")
    expect_identical(
      r$matcher_url,
      c("https://example.com/a%4g", "https://example.com/a%254g"),
      label = backend
    )
    expect_identical(r$url_decision, c("disallow", "allow"), label = backend)
  }
})

test_that("ROBO-rswdwrnp: a class (b) `%` matches every escape it begins", {
  for (backend in names(ip_engines)) {
    # A final `%` matches any escape there, `%25` included, and the raw `%`.
    r <- ip_eval("/a%", c("/a%20b", "/a%25", "/a%", "/b"), backend)
    expect_identical(r$url_decision,
                     c("disallow", "disallow", "disallow", "allow"),
                     label = paste(backend, "/a%"))
    # `/a%*` reads as `/a%`.
    r <- ip_eval("/a%*", c("/a%41", "/a%25", "/ab"), backend)
    expect_identical(r$url_decision, c("disallow", "disallow", "allow"),
                     label = paste(backend, "/a%*"))
    # A final `%4` matches `%41`, not a literal `%` (`%254`).
    r <- ip_eval("/a%4", c("/a%41", "/a%254"), backend)
    expect_identical(r$url_decision, c("disallow", "allow"),
                     label = paste(backend, "/a%4"))
    # design/engine-disagreements.md class 9: `*%*` matches any escape.
    r <- ip_eval("*%*", c("/%24", "/x"), backend)
    expect_identical(r$url_decision, c("disallow", "allow"),
                     label = paste(backend, "*%*"))
  }
})
