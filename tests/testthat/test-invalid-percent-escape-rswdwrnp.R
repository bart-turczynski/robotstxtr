# ROBO-rswdwrnp: an Allow or Disallow pattern with a `%` that starts no
# two-hex-digit escape is rule_invalid_percent_escape, one row per rule line.
# A stray `%` is class (a), never part of an escape, unless it, or it and one
# hex digit, ends the pattern or stands before a `*`: that is class (b), and
# matches any escape it begins. Any (a) gives the (a) message; all (b) give
# the (b) message. The message lists up to ten distinct `%` with the two
# bytes after each, and an (a) message names a `%name%` placeholder.

# The validator's rows for one rule line, after a User-agent line.
ip_rows <- function(value, type = "Disallow") {
  robots_validate_text(
    paste0("User-agent: *\n", type, ": ", value, "\n")
  )$diagnostics
}

ip_codes <- function(value, type = "Disallow") {
  ip_rows(value, type)$code
}

ip_message <- function(x) {
  x$message[x$code == "rule_invalid_percent_escape"]
}

# A body from pieces: a string is text, a raw vector is bytes.
ip_body <- function(...) {
  parts <- list(...)
  unlist(lapply(parts, function(p) if (is.raw(p)) p else charToRaw(p)))
}

ip_new <- "rule_invalid_percent_escape"

ip_a <- function(listed, nul = FALSE) {
  paste0(
    "Pattern holds ", listed, ": '%' that starts no two-hex-digit escape. ",
    "The package's Google, Bing and Yandex matchers compare it as a ",
    "literal '%', so this rule matches only URLs that carry the raw '%', ",
    "which correctly encoded URLs never do.",
    if (nul) ip_nul_split,
    " Write '%25' for a literal '%'."
  )
}

# A NUL that cuts the value splits the engines (ROBO-xuusttbp).
ip_nul_split <- paste0(
  " Google's matcher ends the rule at the NUL; the package's Bing and ",
  "Yandex matchers read the NUL as a byte of the rule."
)

ip_b <- function(listed, lower = FALSE, nul = FALSE) {
  paste0(
    "Pattern holds ", listed, ": '%' cut short by a '*' or by the ",
    "pattern's end.",
    if (nul) {
      paste0(
        " Google's matcher ends the rule at the NUL and compares the rest as ",
        "written, so it matches any URL with a percent-escape that begins ",
        "there, as a final '%' matches '%20' and '%25' alike; the package's ",
        "Bing and Yandex matchers read the NUL as a byte of the rule."
      )
    } else {
      paste0(
        " The package's Google, Bing and Yandex matchers compare the pattern ",
        "as written, so the rule matches any URL with a percent-escape that ",
        "begins there, as a final '%' matches '%20' and '%25' alike."
      )
    },
    if (lower) {
      paste0(" A lower-case hex digit there matches only lower-case escapes, ",
             "which RFC 3986 section 2.1 advises against.")
    },
    " This may be meant; to match only a literal '%', write '%25'."
  )
}

ip_lead_a <- function(listed) {
  paste0(
    "Pattern holds ", listed, ": '%' that starts no two-hex-digit escape."
  )
}

ip_ph_named <- function(name) {
  paste0(
    " '", name, "' looks like an unfilled template placeholder: the rule ",
    "matches no filled-in value, nor the placeholder with each '%' written ",
    "'%25'."
  )
}

# A placeholder all three matchers compare as written.
ip_ph <- function(listed, name) {
  paste0(
    ip_lead_a(listed), ip_ph_named(name),
    " The package's Google, Bing and Yandex matchers compare it as written, ",
    "so the rule matches only a URL that carries the raw placeholder. Write ",
    "'%25' for a literal '%'."
  )
}

# A placeholder led by a lower-case escape, which Google and Bing upper-case.
ip_ph_upper <- function(listed, name, esc, upper) {
  paste0(
    ip_lead_a(listed), ip_ph_named(name),
    " Google's and Bing's matchers upper-case its '", esc, "' as an escape, ",
    "so they match '", upper, "' and not the placeholder as written; the ",
    "package's Yandex matcher compares it as written. Write '%25' for a ",
    "literal '%'."
  )
}

# Shapes with a stray `%`: their codes and the new row's message.
ip_stray <- list(
  "/*hashid=%subscriber_hash%" = list(
    ip_new, ip_ph("'%su', '%'", "%subscriber_hash%")
  ),
  "/x?d=%date%" = list(
    c(ip_new, "rule_lowercase_escape"),
    ip_ph_upper("'%'", "%date%", "%da", "%DAte%")
  ),
  "/x?d=%DAte%" = list(ip_new, ip_ph("'%'", "%DAte%")),
  "/a%4g" = list(ip_new, ip_a("'%4g'")),
  # test-escaped-unreserved-gaczsrgj.R's eu_clean held these two, which now
  # get only this code: no rule_escaped_unreserved.
  "/%zz" = list(ip_new, ip_a("'%zz'")),
  "/%7" = list(ip_new, ip_b("'%7'")),
  "/a%$" = list(ip_new, ip_a("'%$'")),
  "/a%4$" = list(ip_new, ip_a("'%4$'")),
  "/%%25" = list(ip_new, ip_a("'%%2'")),
  # Near the end a context is shorter, and so distinct: '%%' and '%' are
  # listed beside '%%%'.
  "/%%%%%%" = list(ip_new, ip_a("'%%%', '%%', '%'")),
  "/%2%2e" = list(
    c("rule_escaped_unreserved", ip_new, "rule_lowercase_escape"),
    ip_a("'%2%'")
  ),
  "/a/./%zz" = list(c("rule_dot_segment", ip_new), ip_a("'%zz'")),
  "/[% name %]" = list(
    c("rule_inner_whitespace", ip_new), ip_a("'% n', '%]'")
  ),
  "/a%zz%" = list(ip_new, ip_ph("'%zz', '%'", "%zz%")),
  "/a%" = list(ip_new, ip_b("'%'")),
  "/a%4" = list(ip_new, ip_b("'%4'")),
  "/a%F" = list(ip_new, ip_b("'%F'")),
  # A lower-case digit matches only lower-case escapes.
  "/a%f" = list(ip_new, ip_b("'%f'", lower = TRUE)),
  "/a%f*" = list(ip_new, ip_b("'%f*'", lower = TRUE)),
  "/a%F*b%f" = list(ip_new, ip_b("'%F*', '%f'", lower = TRUE)),
  "/a%*" = list(ip_new, ip_b("'%*'")),
  "/a%4*" = list(ip_new, ip_b("'%4*'")),
  "*%*" = list(ip_new, ip_b("'%*'")),
  "/a%*b%" = list(ip_new, ip_b("'%*b', '%'")),
  # A name of exactly two hex digits is an escape and a stray `%`, no
  # placeholder: the class comes from the stray `%` alone.
  "/ab%cd%" = list(c(ip_new, "rule_lowercase_escape"), ip_b("'%'")),
  "/caf%C3%A9%" = list(ip_new, ip_b("'%'")),
  "/%E2%82%AC%*" = list(ip_new, ip_b("'%*'")),
  "/a%DE%zz" = list(ip_new, ip_a("'%zz'")),
  "/x%Bb%*" = list(c(ip_new, "rule_lowercase_escape"), ip_b("'%*'"))
)

# Shapes with no stray `%`, each with the codes it got before the check.
ip_valid <- list(
  "/a%2F" = character(0),
  "/a%25" = character(0),
  "/%25%25" = character(0),
  "/a%C3%A9" = character(0),
  "/a%41*" = "rule_escaped_unreserved",
  "/a%2f" = "rule_lowercase_escape",
  "/a/%2e/b" = c("rule_escaped_unreserved", "rule_lowercase_escape"),
  "/a/%2E%2E/b" = "rule_escaped_unreserved",
  "/p?u={{name}}" = character(0),
  "/*|NAME|*" = character(0)
)

test_that("ROBO-rswdwrnp: the unfilled placeholder is one warning row", {
  x <- robots_validate_text(
    "User-agent: *\nDisallow: /*hashid=%subscriber_hash%\n"
  )
  expect_identical(x$diagnostics$code, ip_new)
  expect_identical(x$diagnostics$line, 2L)
  expect_identical(x$diagnostics$severity, "warning")
  expect_identical(x$diagnostics$directive, "disallow")
  expect_identical(x$diagnostics$raw_text,
                   "Disallow: /*hashid=%subscriber_hash%")
  expect_identical(x$documents$validation_status, "warning")
  message <- x$diagnostics$message
  expect_match(message, "'%su'", fixed = TRUE)
  expect_match(message, "'%25'", fixed = TRUE)
  expect_match(message, "'%subscriber_hash%' looks like an unfilled",
               fixed = TRUE)
})

test_that("ROBO-rswdwrnp: each stray shape gets its class's message", {
  for (type in c("Allow", "Disallow")) {
    for (value in names(ip_stray)) {
      label <- paste(type, value)
      x <- ip_rows(value, type)
      expect_identical(x$code, ip_stray[[value]][[1L]], label = label)
      expect_identical(ip_message(x), ip_stray[[value]][[2L]], label = label)
    }
  }
})

test_that("ROBO-rswdwrnp: a class (b) message never claims no URL matches", {
  for (value in c("/a%", "/a%4", "/a%*", "*%*")) {
    message <- ip_message(ip_rows(value))
    expect_no_match(message, "correctly encoded URLs never", fixed = TRUE)
    expect_match(message, "This may be meant", fixed = TRUE)
  }
})

test_that("ROBO-rswdwrnp: valid escapes keep their codes", {
  for (type in c("Allow", "Disallow")) {
    for (value in names(ip_valid)) {
      expect_identical(
        ip_codes(value, type), ip_valid[[value]],
        label = paste(type, value)
      )
    }
  }
})

test_that("ROBO-rswdwrnp: raw non-ASCII bytes are quoted as written", {
  # A raw e-acute (UTF-8 C3 A9), written with escapes to keep this file ASCII.
  # The parser writes it as `%C3%A9`, a valid escape and no placeholder; the
  # message quotes the bytes as written, as \xNN.
  e_acute <- as.raw(c(0xc3, 0xa9))
  expect_identical(
    robots_validate_text(ip_body("User-agent: *\nDisallow: /", e_acute,
                                 "\n"))$diagnostics$code,
    character(0)
  )
  x <- robots_validate_text(ip_body("User-agent: *\nDisallow: /a%", e_acute,
                                    "\n"))$diagnostics
  expect_identical(x$code, ip_new)
  expect_identical(x$message, ip_a("'%\\xC3\\xA9'"))
  # Invalid UTF-8: a lone 0xE9 after a valid escape.
  expect_identical(
    robots_validate_text(ip_body("User-agent: *\nDisallow: /a%2F",
                                 as.raw(0xe9), "\n"))$diagnostics$code,
    "invalid_utf8"
  )
  latin <- "User-agent: *\nDisallow: /a%\xe9\n"
  Encoding(latin) <- "latin1"
  # A latin1-marked body is read as UTF-8.
  x <- robots_validate_text(latin)$diagnostics
  expect_identical(x$code, ip_new)
  expect_identical(x$message, ip_a("'%\\xC3\\xA9'"))
  # Invalid UTF-8 after a stray `%`.
  x <- robots_validate_text(ip_body("User-agent: *\nDisallow: /a%",
                                    as.raw(0xe9), "\n"))$diagnostics
  expect_identical(x$code, c("invalid_utf8", ip_new))
  expect_identical(ip_message(x), ip_a("'%\\xE9'"))
  # The placeholder is read as written: a raw e-acute before it, which the
  # parser writes `%C3%A9`, leaves it named, and `/a%b` before a raw e-acute
  # (canonical `/a%b%C3%A9`) names none.
  x <- robots_validate_text(ip_body("User-agent: *\nDisallow: /", e_acute,
                                    "%subscriber%\n"))$diagnostics
  expect_identical(ip_message(x), ip_ph("'%su', '%'", "%subscriber%"))
  x <- robots_validate_text(ip_body("User-agent: *\nDisallow: /a%b", e_acute,
                                    "\n"))$diagnostics
  expect_identical(ip_message(x), ip_a("'%b\\xC3'"))
  # Edges the parser trims are not quoted: a trailing tab leaves `%` final.
  expect_identical(ip_message(ip_rows("/a%\t")), ip_b("'%'"))
})

test_that("ROBO-rswdwrnp: a control byte after a `%` is written \\xNN", {
  x <- robots_validate_text(ip_body(
    "User-agent: *\nDisallow: /a%", as.raw(1), "b\n"
  ))$diagnostics
  expect_identical(x$code, c("rule_control_character", ip_new))
  expect_identical(ip_message(x), ip_a("'%\\x01b'"))
  # A `'` would end the quoted item, so it is written \x27 too.
  expect_identical(ip_message(ip_rows("/a%'b")), ip_a("'%\\x27b'"))
  expect_identical(ip_message(ip_rows("/a%zz'")), ip_a("'%zz'"))
})

test_that("ROBO-rswdwrnp: distinct `%` are listed once, up to ten", {
  expect_identical(ip_message(ip_rows("/%zz/%zz/%zz")), ip_a("'%zz'"))
  ten <- paste0("/", paste0("%", letters[7:16], "-", collapse = ""))
  expect_identical(
    ip_message(ip_rows(ten)),
    ip_a(toString(sprintf("'%%%s-'", letters[7:16])))
  )
  eleven <- paste0("/", paste0("%", letters[7:17], "-", collapse = ""))
  expect_identical(
    ip_message(ip_rows(eleven)),
    ip_a(paste0(toString(sprintf("'%%%s-'", letters[7:16])),
                ", and 1 more"))
  )
  # The class (a) `%` that sets the message is listed first, never hidden.
  mixed <- paste0("/", paste0("%", 0:9, "*", collapse = ""), "%zz")
  expect_identical(
    ip_message(ip_rows(mixed)),
    ip_a(paste0("'%zz', ", toString(sprintf("'%%%d*'", 0:8)),
                ", and 1 more"))
  )
  # Among class (b) items, value order holds.
  expect_identical(ip_message(ip_rows("/%*a%4*b%")),
                   ip_b("'%*a', '%4*', '%'"))
})

test_that("ROBO-rswdwrnp: the placeholder wording", {
  expect_identical(
    ip_message(ip_rows("/a%_x1%b")), ip_ph("'%_x', '%b'", "%_x1%")
  )
  expect_identical(
    ip_message(ip_rows("/a?u=%a%")), ip_ph("'%a%', '%'", "%a%")
  )
  # A name led by two hex digits is named too, on the value as written; the
  # parser upper-cases its escape.
  for (name in c("date", "deal_id", "feed", "face")) {
    upper <- paste0("%", chartr("adef", "ADEF", substr(name, 1L, 2L)),
                    substring(name, 3L), "%")
    expect_identical(
      ip_message(ip_rows(paste0("/x?d=%", name, "%"))),
      ip_ph_upper("'%'", paste0("%", name, "%"),
                  paste0("%", substr(name, 1L, 2L)), upper),
      label = name
    )
  }
  # A name of exactly two hex digits is an escape, not a placeholder.
  expect_identical(ip_message(ip_rows("/%ab%zz")), ip_a("'%zz'"))
  # A closing `%` that starts a valid escape closes no placeholder.
  expect_identical(ip_message(ip_rows("/%x%41")), ip_a("'%x%'"))
  expect_identical(ip_message(ip_rows("/%x%41%y%")),
                   ip_ph("'%x%', '%y%', '%'", "%y%"))
  # The (b) value with no placeholder keeps the (b) message.
  expect_identical(ip_message(ip_rows("/x?d=%")), ip_b("'%'"))
  # `[% name %]` is not detected here (ROBO-areyzfoy).
  expect_no_match(ip_message(ip_rows("/[% name %]")), "placeholder")
})

test_that("ROBO-rswdwrnp: a `%` the parser never reads as a rule is silent", {
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

test_that("ROBO-rswdwrnp: an empty or all-blank value is no written value", {
  for (line in c("Disallow:", "Disallow:   ", "Disallow:\t \x0b")) {
    expect_identical(
      rule_written_value(charToRaw(line), FALSE, FALSE), raw(0L),
      label = line
    )
  }
  # The trailing blanks go; the value keeps its bytes up to the last one.
  expect_identical(
    rule_written_value(charToRaw("Disallow: /a% \t"), FALSE, FALSE),
    charToRaw(" /a%")
  )
  expect_identical(
    robots_validate_text("User-agent: *\nDisallow:   \n")$diagnostics$code,
    robots_validate_text("User-agent: *\nDisallow:\n")$diagnostics$code
  )
})

# A rule line whose value a NUL cuts: `pre`, a NUL, then `post`.
ip_nul_body <- function(pre, post) {
  ip_body("User-agent: *\nDisallow: ", pre, as.raw(0), paste0(post, "\n"))
}

# Each matcher's decision on each path for a raw body. An R string cannot
# hold a NUL, so the matchers are called on the bytes (test-validator-nul-
# reading-xuusttbp.R).
ip_nul_decisions <- function(body, paths) {
  urls <- paste0("https://example.com", paths)
  list(
    google = vapply(urls, function(u) {
      match_google_v1(body, u, "FooBot")$url_decision
    }, "", USE.NAMES = FALSE),
    bing = vapply(urls, function(u) {
      match_bing_v1(list(body), u, "bingbot")$url_decision
    }, "", USE.NAMES = FALSE),
    yandex = vapply(urls, function(u) {
      match_yandex_v1(list(body), u, "Yandex")$url_decision
    }, "", USE.NAMES = FALSE)
  )
}

test_that("ROBO-rswdwrnp: a NUL that cuts the value splits the engines", {
  # Class (b) on Google's reading only: the message says so.
  body <- ip_nul_body("/a%", "zz")
  x <- robots_validate_text(body)$diagnostics
  expect_identical(x$code, c("nul_byte", "rule_cut_by_nul", ip_new))
  expect_identical(ip_message(x), ip_b("'%'", nul = TRUE))
  paths <- c("/a%20b", "/a%25", "/a%", "/b")
  expect_identical(ip_nul_decisions(body, paths), list(
    google = c("disallow", "disallow", "disallow", "allow"),
    bing = rep("allow", 4L),
    yandex = rep("allow", 4L)
  ))
  # Class (a) before the NUL: the raw `%` on Google, and the split named.
  body <- ip_nul_body("/a%zz", "x")
  expect_identical(ip_message(robots_validate_text(body)$diagnostics),
                   ip_a("'%zz'", nul = TRUE))
  expect_identical(
    ip_nul_decisions(body, c("/a%zz", "/a%25zz")),
    list(google = c("disallow", "allow"), bing = c("allow", "allow"),
         yandex = c("allow", "allow"))
  )
  # A NUL in a comment cuts nothing, so no split is named.
  body <- ip_body("User-agent: *\nDisallow: /a% #c", as.raw(0), "x\n")
  expect_identical(ip_message(robots_validate_text(body)$diagnostics),
                   ip_b("'%'"))
})

# A value whose last kept byte, the line buffer's 16,663rd, is a `%`.
ip_cut <- function() {
  pre <- "Disallow: /"
  filler <- strrep("a", 16663L - nchar(pre) - 1L)
  robots_validate_text(
    paste0("User-agent: *\n", pre, filler, "%zz\n")
  )$diagnostics
}

test_that("ROBO-rswdwrnp: a `%` at the line buffer's end is class (b)", {
  x <- ip_cut()
  expect_identical(x$code, c("line_too_long", ip_new))
  expect_identical(ip_message(x), ip_b("'%'"))
})

# Best of five runs, so a loaded machine cannot fail the ratio
# (test-cut-note-zqyqbudf.R).
ip_time <- function(body) {
  min(vapply(1:5, function(i) {
    system.time(robots_validate_text(body))[["elapsed"]]
  }, 0))
}

ip_rules <- function(n) {
  paste0(
    "User-agent: *\n",
    paste0("Disallow: /p", seq_len(n), "/%zz%\n", collapse = "")
  )
}

test_that("ROBO-rswdwrnp: the check stays linear (ROBO-dbvmxcfw)", {
  skip_on_cran()
  small <- ip_time(ip_rules(1000L))
  large <- ip_time(ip_rules(4000L))
  expect_lt(large, 8 * max(small, 0.05))

  # 16,000 bytes of `%`, every one stray, against a same-length plain value.
  pct <- ip_time(paste0("User-agent: *\nDisallow: /", strrep("%", 16000L),
                        "\n"))
  plain <- ip_time(paste0("User-agent: *\nDisallow: /", strrep("a", 16000L),
                          "\n"))
  expect_lt(pct, 8 * max(plain, 0.05))
})

# The helper on one value, 20 calls per run so a cost that grows with the
# value's length clears the floor; best of five, as ip_time().
ip_time_value <- function(value) {
  written <- charToRaw(value)
  min(vapply(1:5, function(i) {
    system.time(for (k in 1:20) {
      rule_invalid_percent_escape_diagnostic(written)
    })[["elapsed"]]
  }, 0))
}

test_that("ROBO-rswdwrnp: the check is linear in the value's length", {
  skip_on_cran()
  # 4,000 and 16,000 bytes, inside the 16,663-byte buffer: a run of
  # placeholder-like names whose closing `%` starts the escape `%41`, so the
  # placeholder regex tries and refuses each; then a run of `%`, every one
  # stray.
  short <- ip_time_value(strrep("/%na_me%41", 400L))
  long <- ip_time_value(strrep("/%na_me%41", 1600L))
  expect_lt(long, 8 * max(short, 0.05))
  short <- ip_time_value(paste0("/", strrep("%", 4000L)))
  long <- ip_time_value(paste0("/", strrep("%", 16000L)))
  expect_lt(long, 8 * max(short, 0.05))
})

# The package's matchers on each class, under the v1 default
# url_normalization = "rfc3986", on google, bing and yandex alike: the
# evidence for each message. The rfc9309 backend is capability_unavailable in
# every mode (ADR 0002), so it is not testable here.
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

test_that("ROBO-rswdwrnp: a cut-short escape's digit keeps its case", {
  for (backend in names(ip_engines)) {
    expect_identical(
      ip_eval("/a%f", c("/a%F0", "/a%f0"), backend)$url_decision,
      c("allow", "disallow"), label = paste(backend, "/a%f")
    )
    expect_identical(
      ip_eval("/a%F", c("/a%F0", "/a%f0"), backend)$url_decision,
      c("disallow", "allow"), label = paste(backend, "/a%F")
    )
  }
})

test_that("ROBO-rswdwrnp: a hex-led placeholder on each matcher", {
  paths <- c("/x?d=%date%", "/x?d=%DAte%20", "/x?d=%25date%25", "/x?d=abc")
  # Google and Bing upper-case `%da`; Yandex compares it as written. None
  # matches a filled-in value or the placeholder written with `%25`.
  want <- list(
    google = c("allow", "disallow", "allow", "allow"),
    bing = c("allow", "disallow", "allow", "allow"),
    yandex = c("disallow", "allow", "allow", "allow")
  )
  for (backend in names(ip_engines)) {
    expect_identical(ip_eval("/x?d=%date%", paths, backend)$url_decision,
                     want[[backend]], label = backend)
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
    # `%25` matches only a literal `%`.
    r <- ip_eval("/a%25", c("/a%25", "/a%20b"), backend)
    expect_identical(r$url_decision, c("disallow", "allow"),
                     label = paste(backend, "/a%25"))
    # An escape then a final `%` is class (b), not a placeholder.
    r <- ip_eval("/caf%C3%A9%", "/caf%C3%A9%20x", backend)
    expect_identical(r$url_decision, "disallow",
                     label = paste(backend, "/caf%C3%A9%"))
  }
})
