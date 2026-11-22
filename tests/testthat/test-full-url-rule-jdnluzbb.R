# ROBO-jdnluzbb: an Allow or Disallow value written as a full http(s) URL
# draws rule_missing_leading_slash, one row per line, as any value not led by
# `/` or `*` does. Its message names the path and query to write instead,
# as written but for dot segments (removed) and non-ASCII bytes (upper-case
# %XX); under robots_validate_url() it also names an origin that differs.
# Code, severity and row count are unchanged.

# A body from pieces: a string is text, a raw vector is bytes.
fu_body <- function(...) {
  parts <- list(...)
  unlist(lapply(parts, function(p) if (is.raw(p)) p else charToRaw(p)))
}

# The validator's rows for line 2, a rule after `User-agent: *`.
fu_rows <- function(..., type = "Disallow: ") {
  d <- robots_validate_text(
    fu_body("User-agent: *\n", type, ..., "\n")
  )$diagnostics
  d[d$line == 2L, , drop = FALSE]
}

fu_message <- function(rows) {
  rows$message[rows$code == "rule_missing_leading_slash"]
}

fu_slash <- "rule_missing_leading_slash"

fu_today <- paste0(
  "Pattern does not start with '/' or '*'; URL paths always start with '/', ",
  "so this rule never matches."
)

fu_prefix <- paste0(
  " Without wildcards or an end anchor, this pattern matches any path and ",
  "query beginning with it. A trailing '$' requires matching through the ",
  "end of the path and query."
)

fu_root <- paste0(
  fu_prefix,
  " The pattern '/' matches every URL, so it applies to the whole site; ",
  "'/$' limits it to the home page, without a query."
)

fu_dots <- " Dot segments removed (RFC 3986 section 5.2.4)."

fu_wide <- " Non-ASCII bytes written as upper-case %XX escapes."

# The message naming `pattern`, with the notes and scope sentence given.
fu_new <- function(pattern, scope = fu_prefix, notes = "", origin = "") {
  paste0(
    fu_today, " The value is a full URL; write its path and query instead: '",
    pattern, "'.", notes, scope, origin
  )
}

# Each full-URL shape: the value, the codes its line gets in row order, the
# pattern suggested, its message, and the URL a crawler sends for it (one
# per engine where the engines differ).
fu_shape <- function(value, pattern, codes = fu_slash, scope = fu_prefix,
                     notes = "", url = NULL) {
  list(
    value = value, codes = codes, pattern = pattern,
    message = fu_new(pattern, scope, notes), url = url
  )
}

fu_shapes <- list(
  natu = fu_shape(
    "https://shop.example/collections/produkty-bialko",
    "/collections/produkty-bialko"
  ),
  http = fu_shape("http://e.example/a", "/a"),
  upper = fu_shape("HTTPS://e.example/a", "/a"),
  host = fu_shape("https://e.example", "/", scope = fu_root),
  host_slash = fu_shape("https://e.example/", "/", scope = fu_root),
  host_query = fu_shape("https://e.example?x=1", "/?x=1"),
  query = fu_shape("https://e.example/a?b=1&c=2", "/a?b=1&c=2"),
  # Google and Bing upper-case the rule's escape and not the URL's
  # (rule_lowercase_escape, which the line also gets); Yandex compares the
  # escape as written.
  lower_escape = fu_shape(
    "https://e.example/a?b=C%2f", "/a?b=C%2f",
    codes = c(fu_slash, "rule_lowercase_escape"),
    url = c(google = "https://e.example/a?b=C%2F",
            bing = "https://e.example/a?b=C%2F",
            yandex = "https://e.example/a?b=C%2f")
  ),
  port = fu_shape("https://e.example:8443/a", "/a"),
  star = fu_shape("https://e.example/a*b", "/a*b", scope = ""),
  # A final `$` is read as the end anchor, so the pattern matches the URL
  # without it; a literal `$` at the end of a URL is not matched.
  dollar = fu_shape(
    "https://e.example/a$", "/a$", scope = "", url = "https://e.example/a"
  ),
  # An inner `$` is literal, and keeps its own row.
  inner_dollar = fu_shape(
    "https://e.example/a$b", "/a$b", codes = c(fu_slash, "rule_inner_dollar")
  ),
  encoded = fu_shape("https://e.example/caf%C3%A9", "/caf%C3%A9"),
  # The default normalization never encodes, so the URL is evaluated as
  # crawlers send it, percent-encoded.
  raw_utf8 = fu_shape(
    fu_body("https://e.example/caf", as.raw(c(0xc3, 0xa9))), "/caf%C3%A9",
    notes = fu_wide, url = "https://e.example/caf%C3%A9"
  ),
  raw_query = fu_shape(
    fu_body("https://e.example/a?q=", as.raw(c(0xc3, 0xa9))), "/a?q=%C3%A9",
    notes = fu_wide, url = "https://e.example/a?q=%C3%A9"
  ),
  quote = fu_shape("https://e.example/a'b", "/a'b"),
  dots = fu_shape("https://e.example/a/./b/../c", "/a/c", notes = fu_dots),
  dots_query = fu_shape(
    "https://e.example/a/./b?x=/./", "/a/b?x=/./", notes = fu_dots
  ),
  # An escaped dot is no dot segment, as in rule_dot_segment.
  escaped_dot = fu_shape(
    "https://e.example/a/%2E/b", "/a/%2E/b",
    codes = c(fu_slash, "rule_escaped_unreserved")
  ),
  only_dot = fu_shape(
    "https://e.example/.", "/", scope = fu_root, notes = fu_dots
  ),
  blanks = fu_shape("  https://e.example/a", "/a"),
  # The stray `%` stays as written, and keeps its own row.
  stray_percent = fu_shape(
    "https://e.example/a%zz", "/a%zz",
    codes = c(fu_slash, "rule_invalid_percent_escape")
  ),
  lower_path = fu_shape(
    "https://e.example/a%2f", "/a%2f",
    codes = c(fu_slash, "rule_lowercase_escape"),
    url = c(google = "https://e.example/a%2F",
            bing = "https://e.example/a%2F",
            yandex = "https://e.example/a%2f")
  )
)

test_that("ROBO-jdnluzbb: each full-URL shape keeps its codes and severity", {
  for (name in names(fu_shapes)) {
    rows <- fu_rows(fu_shapes[[name]]$value)
    expect_identical(rows$code, fu_shapes[[name]]$codes, label = name)
    expect_true(all(rows$severity == "warning"), label = name)
    expect_length(fu_message(rows), 1L)
  }
})

test_that("ROBO-jdnluzbb: a full-URL value names the path to write", {
  for (name in names(fu_shapes)) {
    rows <- fu_rows(fu_shapes[[name]]$value)
    expect_identical(fu_message(rows), fu_shapes[[name]]$message,
                     label = name)
  }
})

test_that("ROBO-jdnluzbb: the line's other rows keep their own messages", {
  for (name in names(fu_shapes)) {
    rows <- fu_rows(fu_shapes[[name]]$value)
    others <- rows$message[rows$code != fu_slash]
    expect_false(any(grepl("The value is a full URL", others, fixed = TRUE)),
                 label = name)
  }
  rows <- fu_rows("https://e.example/a$b")
  expect_identical(
    rows$message[rows$code == "rule_inner_dollar"],
    paste0("'$' marks the end of the URL only as the last character; here ",
           "it matches a literal '$'.")
  )
  rows <- fu_rows("https://e.example/a/%2E/b")
  expect_identical(
    rows$message[rows$code == "rule_escaped_unreserved"],
    paste0("'%2E' escapes the unreserved character '.'. Google matches it ",
           "only against '%2E' in the URL, never against '.', though RFC ",
           "9309 section 2.2.2 decodes it.")
  )
})

test_that("ROBO-jdnluzbb: an Allow value gets the same message", {
  rows <- fu_rows("https://e.example/a", type = "Allow: ")
  expect_identical(rows$code, fu_slash)
  expect_identical(fu_message(rows), fu_new("/a"))
})

test_that("ROBO-jdnluzbb: values that are no absolute URL keep the message", {
  for (value in c("https://", "https:/x", "http:e.example/a", "ftp://e.x/a",
                  "httpsx://e.example/a", "private/", "https:///a",
                  "https://:8443/a", "https://user@/a")) {
    rows <- fu_rows(value)
    expect_identical(rows$code, fu_slash, label = value)
    expect_identical(fu_message(rows), fu_today, label = value)
  }
})

test_that("ROBO-jdnluzbb: a fragment is cut by the parser first", {
  rows <- fu_rows("https://e.example/a#f")
  expect_identical(rows$code, c("rule_cut_by_comment", fu_slash))
  expect_identical(fu_message(rows), fu_new("/a"))
})

test_that("ROBO-jdnluzbb: a blank or control byte keeps today's message", {
  rows <- fu_rows("https://e.example/a b")
  expect_identical(rows$code, c(fu_slash, "rule_inner_whitespace"))
  expect_identical(fu_message(rows), fu_today)
  rows <- fu_rows("https://e.example/a?q=1\tb")
  expect_identical(rows$code, c(fu_slash, "rule_inner_whitespace"))
  expect_identical(fu_message(rows), fu_today)
  rows <- fu_rows(fu_body("https://e.example/a", as.raw(0x01), "b"))
  expect_identical(rows$code, c(fu_slash, "rule_control_character"))
  expect_identical(fu_message(rows), fu_today)
  rows <- fu_rows(fu_body("https://e.example/a", as.raw(0x7f)))
  expect_identical(rows$code, fu_slash)
  expect_identical(fu_message(rows), fu_today)
})

test_that("ROBO-jdnluzbb: the byte guard holds without rurl's verdict", {
  # rurl rejects these URLs too; the guard decides before it is asked.
  local_mocked_bindings(
    robots_origin = function(url) "https://e.example/robots.txt"
  )
  for (value in list("https://e.example/a b", "https://e.example/a?q=1\tb",
                     fu_body("https://e.example/a", as.raw(0x01), "b"),
                     fu_body("https://e.example/a", as.raw(0x7f)))) {
    expect_null(rule_full_url_message(fu_body(value)))
  }
  expect_identical(
    rule_full_url_message(charToRaw("https://e.example/a")), fu_new("/a")
  )
})

test_that("ROBO-jdnluzbb: an invisible prefix keeps its sentence", {
  rows <- fu_rows(fu_body(as.raw(c(0xef, 0xbb, 0xbf)), "https://e.example/a"))
  expect_identical(rows$code, fu_slash)
  expect_identical(
    fu_message(rows),
    paste0(fu_today, " It starts with an invisible character (U+FEFF).")
  )
  rows <- fu_rows(fu_body(as.raw(c(0xe2, 0x80, 0x8b)), "https://e.example/a"))
  expect_identical(
    fu_message(rows),
    paste0(fu_today, " It starts with an invisible character (U+200B).")
  )
})

test_that("ROBO-jdnluzbb: invalid UTF-8 in the URL keeps today's message", {
  rows <- fu_rows(fu_body("https://e.example/caf", as.raw(0xe9)))
  expect_identical(rows$code, c("invalid_utf8", fu_slash))
  expect_identical(fu_message(rows), fu_today)
})

test_that("ROBO-jdnluzbb: a value at the line buffer keeps today's message", {
  rows <- fu_rows("https://e.example/", strrep("a", 16663L))
  expect_identical(rows$code, c("line_too_long", fu_slash))
  expect_identical(fu_message(rows), fu_today)
  # Just inside the buffer, the message names the path.
  path <- strrep("a", 16000L)
  rows <- fu_rows("https://e.example/", path)
  expect_identical(rows$code, fu_slash)
  expect_identical(fu_message(rows), fu_new(paste0("/", path)))
})

test_that("ROBO-jdnluzbb: a NUL cuts the URL, on Google's reading", {
  # The pattern follows the parser and Google's matcher, which never read
  # past the NUL; rule_cut_by_nul names the engine split.
  rows <- fu_rows(fu_body("https://e.example/a", as.raw(0x00), "b"))
  expect_identical(rows$code, c("nul_byte", "rule_cut_by_nul", fu_slash))
  expect_identical(fu_message(rows), fu_new("/a"))
})

test_that("ROBO-jdnluzbb: the missing-colon form never reaches the check", {
  # The scheme's `:` ends the key, so the key is `Disallow https` (a prefix
  # Google accepts) and the value `//e.example/m` is led by `/`.
  rows <- fu_rows("https://e.example/m", type = "Disallow ")
  expect_identical(rows$code, "accepted_directive_prefix")
})

test_that("ROBO-jdnluzbb: an empty value draws no leading-slash row", {
  expect_identical(fu_rows("")$code, "allow_all_disallow")
})

test_that("ROBO-jdnluzbb: no full-URL value gets rule_dot_segment", {
  for (value in c("https://e.example/a/./b", "https://e.example/a%zz",
                  "https://e.example/a%2f")) {
    expect_false("rule_dot_segment" %in% fu_rows(value)$code, label = value)
  }
})

# --- Match check -------------------------------------------------------------
# The pattern, written as a Disallow, matches the URL it came from on each
# engine under the default url_normalization; the original line matches no
# URL. rfc9309 is not testable: its backend is capability_unavailable, as
# test-dot-segment-rnjfbhvn.R notes.
fu_engines <- list(google = "Googlebot", bing = "bingbot", yandex = "Yandex")

fu_decision <- function(rule, url, backend) {
  text <- rawToChar(fu_body("User-agent: *\nDisallow: ", rule, "\n"))
  Encoding(text) <- "UTF-8"
  robots_evaluate_text_v1(
    text, url,
    fu_engines[[backend]], backend, backend
  )$results$url_decision
}

# The URL a crawler sends for a shape: given, or the value itself.
fu_url <- function(shape, backend) {
  if (is.null(shape$url)) {
    return(rawToChar(fu_body(shape$value)))
  }
  if (length(shape$url) == 1L) shape$url else shape$url[[backend]]
}

# The pattern the validator's message names, read back from the message.
fu_suggested <- function(value) {
  message <- fu_message(fu_rows(value))
  hit <- regmatches(
    message, regexec("instead: '(.*?)'[.](?: |$)", message, perl = TRUE)
  )[[1L]]
  hit[[2L]]
}

test_that("ROBO-jdnluzbb: the pattern matches the URL on every engine", {
  for (name in names(fu_shapes)) {
    shape <- fu_shapes[[name]]
    pattern <- fu_suggested(shape$value)
    expect_identical(pattern, shape$pattern, label = name)
    for (backend in names(fu_engines)) {
      url <- trimws(fu_url(shape, backend))
      expect_identical(fu_decision(pattern, url, backend), "disallow",
                       label = paste(name, backend))
      expect_identical(fu_decision(shape$value, url, backend), "allow",
                       label = paste(name, backend))
    }
  }
})

test_that("ROBO-jdnluzbb: the scope sentences hold on every engine", {
  base <- "https://shop.example/collections/"
  urls <- paste0(base, c("produkty-bialko", "produkty", "produkty?x=1"))
  for (backend in names(fu_engines)) {
    # A prefix: the shortened pattern also blocks its longer siblings.
    expect_identical(
      fu_decision("/collections/produkty", urls, backend),
      rep("disallow", 3L), label = backend
    )
    # A final `$` matches through the end of the path and query.
    expect_identical(
      fu_decision("/collections/produkty$", urls, backend),
      c("allow", "disallow", "allow"), label = backend
    )
    expect_identical(
      fu_decision("/", c("https://e.example/", "https://e.example/z?q=1"),
                  backend),
      c("disallow", "disallow"), label = backend
    )
    # `/$` is the home page alone: no other path, no query.
    home <- paste0("https://e.example",
                   c("/", "", "/?x=1", "/a", "/index.html"))
    expect_identical(
      fu_decision("/$", home, backend),
      c("disallow", "disallow", "allow", "allow", "allow"), label = backend
    )
  }
})

# --- Origin sentence ---------------------------------------------------------
fu_served <- function(value, target = "https://e.example/page") {
  local_fake_ssrfr(function(req) {
    fake_response(
      200L, url = req$url,
      body = paste0("User-agent: *\nDisallow: ", value, "\n")
    )
  })
  d <- robots_validate_url(target)$diagnostics
  fu_message(d)
}

fu_origin <- function(served, written) {
  paste0(
    " Without its scheme and host, the rule applies on the origin this ",
    "robots.txt serves, ", served, ", not on ", written,
    ", the one written in the value."
  )
}

test_that("ROBO-jdnluzbb: another origin is named under robots_validate_url", {
  expect_identical(
    fu_served("https://other.example/a"),
    fu_new("/a", origin = fu_origin("https://e.example",
                                    "https://other.example"))
  )
  expect_identical(
    fu_served("http://e.example/a"),
    fu_new("/a", origin = fu_origin("https://e.example", "http://e.example"))
  )
  expect_identical(
    fu_served("https://e.example:8443/a"),
    fu_new("/a", origin = fu_origin("https://e.example",
                                    "https://e.example:8443"))
  )
  expect_identical(
    fu_served("https://e.example/a", target = "https://e.example:8443/p"),
    fu_new("/a", origin = fu_origin("https://e.example:8443",
                                    "https://e.example"))
  )
})

test_that("ROBO-jdnluzbb: the same origin, however written, is not named", {
  for (value in c("https://e.example/a", "https://e.example:443/a",
                  "https://E.EXAMPLE/a", "HTTPS://e.example/a")) {
    expect_identical(fu_served(value), fu_new("/a"), label = value)
  }
  expect_identical(
    fu_served("http://e.example:80/a", target = "http://e.example/p"),
    fu_new("/a")
  )
})

test_that("ROBO-jdnluzbb: supplied text names no origin", {
  expect_identical(fu_message(fu_rows("https://other.example/a")),
                   fu_new("/a"))
})

# --- Cost --------------------------------------------------------------------
# The helper on one value, 20 calls per run so a cost that grows with the
# value's length clears the floor; best of five.
fu_time <- function(written) {
  min(vapply(1:5, function(i) {
    system.time(for (k in 1:20) {
      rule_full_url_message(written, "https://e.example/robots.txt")
    })[["elapsed"]]
  }, 0))
}

test_that("ROBO-jdnluzbb: the helper is linear in the value's length", {
  skip_on_cran()
  # 4,000 and 16,000 bytes of path, inside the 16,663-byte buffer: dot
  # segments to remove, then non-ASCII bytes to escape.
  short <- fu_time(fu_body("https://e.example", strrep("/a/./b/../", 400L)))
  long <- fu_time(fu_body("https://e.example", strrep("/a/./b/../", 1600L)))
  expect_lt(long, 8 * max(short, 0.05))
  wide <- as.raw(c(0xc3, 0xa9))
  short <- fu_time(fu_body("https://e.example/", rep(wide, 2000L)))
  long <- fu_time(fu_body("https://e.example/", rep(wide, 8000L)))
  expect_lt(long, 8 * max(short, 0.05))
})
