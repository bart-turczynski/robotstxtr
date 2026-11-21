# Evaluator URL preprocessing (ROBO-bnvdmdjr; design/adr/0002). The v1
# facades take `url_normalization`: "rfc3986" (the default) applies RFC 3986
# section 5.2.4 to the path, splits the authority the RFC 3986 way and drops
# the fragment, and never encodes, decodes or case-folds an escape; "none"
# reads the URL as given, as the facades did before.

pp_body <- paste0(
  "User-agent: *\nDisallow: /account/\nAllow: /latam\nDisallow: /x\n",
  "Disallow: /a/b\n"
)

pp_eval <- function(url, backend, token, mode, body = pp_body) {
  robots_evaluate_text_v1(
    body, url, token, backend, backend, url_normalization = mode
  )$results
}

# Under "none", what the facades read before `url_normalization` existed.
pp_today <- function(url, backend, token, body = pp_body) {
  pp_eval(url, backend, token, "none", body)
}

pp_engines <- list(
  google = "Googlebot", bing = "bingbot", yandex = "Yandex"
)

sect <- "\u00a7"
pp_dots <- paste0("RFC 3986 ", sect, "5.2.4 removed dot segments")
pp_noauth <- "no authority: path read from the first /"
pp_noslash <- "no authority and no /: evaluated as given"
pp_kept <- paste0(
  "dot segments left in place: removing them would start the path with // ",
  "(RFC 3986 ", sect, "5.2.4)"
)

# ---- "none": the URL as given (the pins of the first commit) ---------------

test_that("none: dot segments are read as given on every backend", {
  for (backend in names(pp_engines)) {
    r <- pp_today(
      c(
        "https://example.com/latam/../account/x",
        "https://example.com/latam/%2e%2e/account/x",
        "https://example.com/a/./b"
      ),
      backend, pp_engines[[backend]]
    )
    expect_identical(
      r$url_decision, c("allow", "allow", "allow"),
      label = backend
    )
    expect_identical(r$matched_rule_value[1:2], c("/latam", "/latam"))
  }
})

test_that("none: Google slices a raw `;` in userinfo, Bing and Yandex do not", {
  urls <- c("https://u;v@example.com/x", "https://u%3Bv@example.com/x")
  expect_identical(
    pp_today(urls, "google", "Googlebot")$url_decision,
    c("allow", "disallow")
  )
  expect_identical(
    pp_today(urls, "bing", "bingbot")$url_decision, c("disallow", "disallow")
  )
  expect_identical(
    pp_today(urls, "yandex", "Yandex")$url_decision, c("disallow", "disallow")
  )
})

test_that("none: a path-only URL reaches Google as given", {
  r <- pp_today(c("/a/../b", "example.com/a/../b"), "google", "Googlebot")
  expect_identical(r$url_decision, c("allow", "allow"))
  expect_identical(r$reason, c("default_allow", "default_allow"))
})

pp_matrix_urls <- c(
  "https://example.com/latam/../account/x",
  "https://example.com/latam/%2e%2e/account/x",
  "https://u;v@example.com/x",
  "https://example.com/p q", "https://example.com/caf\u00e9",
  "https://example.com/a\\b", "https://example.com/x#frag",
  "/a/../b", "example.com/a/./b", "https://example.com/a/b/.."
)

test_that("none: matcher_url is the input byte for byte, with no note", {
  for (backend in names(pp_engines)) {
    r <- pp_today(pp_matrix_urls, backend, pp_engines[[backend]])
    expect_identical(r$matcher_url, pp_matrix_urls, label = backend)
    expect_identical(r$url, pp_matrix_urls)
    expect_true(all(is.na(r$url_preprocessing_note)))
  }
  latin <- "https://example.com/caf\xe9/../x"
  Encoding(latin) <- "latin1"
  r <- pp_today(latin, "google", "Googlebot")
  expect_identical(charToRaw(r$matcher_url), charToRaw(latin))
  expect_identical(Encoding(r$matcher_url), "latin1")
})

# ---- the extractors and the legacy functions stay as they are -------------

test_that("the extractors are byte-transparent: dot segments kept", {
  expect_identical(
    robotstxtr_extract_request_target_("https://example.com/a/../b"),
    "/a/../b"
  )
  expect_identical(
    bing_extract_request_target("https://example.com/a/../b"), "/a/../b"
  )
  expect_identical(
    google_request_target_v1("https://example.com/a/../b"),
    "https://example.com/a/../b"
  )
})

test_that("the legacy functions read dot segments as given", {
  legacy <- allowed_by_robots_text(
    pp_body, "https://example.com/latam/../account/x", "Googlebot"
  )
  expect_true(legacy$results$allowed)
  expect_identical(legacy$results$decision_source, "rule_allow")

  local_fake_ssrfr(function(req) fake_response(200L, body = pp_body))
  fetched <- allowed_by_robots_url(
    "http://a/latam/../account/x", "Googlebot"
  )
  expect_true(fetched$results$allowed)
  expect_identical(fetched$results$matched_rule_value, "/latam")
})

# ---- the argument ----------------------------------------------------------

test_that("url_normalization is one value from the published set", {
  expect_identical(engine_url_normalizations_v1(), c("rfc3986", "none"))
  expect_identical(
    formals(robots_evaluate_text_v1)$url_normalization, "rfc3986"
  )
  expect_identical(
    formals(robots_evaluate_url_v1)$url_normalization, "rfc3986"
  )
  for (bad in list("whatwg", c("none", "rfc3986"), NA_character_, 1, "")) {
    expect_error(
      robots_evaluate_text_v1(
        pp_body, "https://example.com/x", "Googlebot", "google", "google",
        url_normalization = bad
      ),
      class = "robotstxtr_invalid_url_normalization"
    )
    expect_error(
      robots_evaluate_url_v1(
        "https://example.com/x", "Googlebot", "google", "google",
        url_normalization = bad
      ),
      class = "robotstxtr_invalid_url_normalization"
    )
  }
  expect_false("url_normalization" %in% names(formals(allowed_by_robots_text)))
  expect_false("url_normalization" %in% names(formals(allowed_by_robots_url)))
})

# ---- "rfc3986": decisions, symmetric on google, bing and yandex -------------

test_that("rfc3986 is the default and moves the literal-dot row only", {
  for (backend in names(pp_engines)) {
    token <- pp_engines[[backend]]
    urls <- c(
      "https://example.com/latam/../account/x",
      "https://example.com/latam/%2e%2e/account/x",
      "https://example.com/latam/%2E%2E/account/x",
      "https://example.com/a/./b"
    )
    r <- robots_evaluate_text_v1(pp_body, urls, token, backend, backend)
    r <- r$results
    expect_identical(
      r$url_decision, c("disallow", "allow", "allow", "disallow"),
      label = backend
    )
    expect_identical(
      r$matcher_url,
      c(
        "https://example.com/account/x", urls[[2]], urls[[3]],
        "https://example.com/a/b"
      )
    )
    expect_identical(
      r$url_preprocessing_note, c(pp_dots, NA, NA, pp_dots)
    )
    expect_identical(r$url, urls)
  }
})

test_that("rfc3986 leaves userinfo out, so Google no longer slices `u;v@`", {
  urls <- c("https://u;v@example.com/x", "https://u%3Bv@example.com/x")
  for (backend in names(pp_engines)) {
    r <- pp_eval(urls, backend, pp_engines[[backend]], "rfc3986")
    expect_identical(
      r$url_decision, c("disallow", "disallow"), label = backend
    )
    expect_identical(r$matcher_url, rep("https://example.com/x", 2L))
    expect_identical(
      r$url_preprocessing_note,
      rep(paste0("userinfo removed (RFC 3986 ", sect, "3.2.1)"), 2L)
    )
  }
})

test_that("rfc3986 under rfc9309 is capability_unavailable, URL still noted", {
  r <- pp_eval(
    "https://example.com/a/../b", "rfc9309", "FooBot", "rfc3986"
  )
  expect_identical(r$matcher_status, "capability_unavailable")
  expect_identical(r$matcher_url, "https://example.com/b")
  expect_identical(r$url_preprocessing_note, pp_dots)
})

test_that("an already-normalized URL passes byte-identical, same decision", {
  urls <- c(
    "https://example.com/a/b?q=1", "https://example.com/latam/y",
    "https://example.com/account/z"
  )
  for (backend in names(pp_engines)) {
    token <- pp_engines[[backend]]
    new <- pp_eval(urls, backend, token, "rfc3986")
    old <- pp_today(urls, backend, token)
    expect_identical(new$matcher_url, urls, label = backend)
    expect_true(all(is.na(new$url_preprocessing_note)))
    expect_identical(new[names(old)], old)
  }
})

# ---- "rfc3986": the matcher URL and the note --------------------------------

pp_rfc3986 <- function(url) {
  pp_eval(url, "google", "Googlebot", "rfc3986")
}

test_that("rfc3986 acceptance matrix: what the matcher reads", {
  cases <- list(
    # literal, trailing and above-the-root dot segments
    c("https://example.com/a/b/../c/./d", "https://example.com/a/c/d"),
    c("https://example.com/a/b/..", "https://example.com/a/"),
    c("https://example.com/a/b/.", "https://example.com/a/b/"),
    c("https://example.com/../../x", "https://example.com/x"),
    # encoded dots, either case and mixed with literal ones, are not dots
    c("https://example.com/a/.%2E/b", "https://example.com/a/.%2E/b"),
    c("https://example.com/a/%2e./b", "https://example.com/a/%2e./b"),
    c("https://example.com/a/%2E%2e/b", "https://example.com/a/%2E%2e/b"),
    # controls every mode keeps
    rep("https://example.com/a/%252e%252e/b", 2L),
    c("https://example.com/a%2F..%2Fb", "https://example.com/a%2F..%2Fb"),
    c("https://example.com//a//b", "https://example.com//a//b"),
    rep("https://example.com/a..b/.well-known", 2L),
    c("https://example.com/p?x=../y", "https://example.com/p?x=../y"),
    c("https://example.com/a/../p?x=/../y", "https://example.com/p?x=/../y"),
    c("https://example.com:8080/a/../b", "https://example.com:8080/b"),
    c("https://example.com", "https://example.com"),
    c("https://example.com?q=1", "https://example.com?q=1"),
    c("https://example.com/x#a/../b", "https://example.com/x")
  )
  urls <- vapply(cases, `[[`, "", 1L)
  r <- pp_rfc3986(urls)
  expect_identical(r$matcher_url, vapply(cases, `[[`, "", 2L))
  expect_identical(r$url, urls)
})

test_that("rfc3986 notes the rule, and records invalid input", {
  rows <- list(
    c("https://example.com/a/../b", pp_dots),
    c("https://example.com/a/%2e%2e/b", NA),
    c("https://example.com/x#frag",
      paste0("fragment dropped (RFC 3986 ", sect, "3.5)")),
    c("https://example.com/p q", "not a valid RFC 3986 URI: raw space"),
    c("https://example.com/a/../p q",
      "not a valid RFC 3986 URI: raw space; dot segments removed as given"),
    c("https://example.com/caf\u00e9",
      "not a valid RFC 3986 URI: raw non-ASCII"),
    c("https://example.com/a\\b", "not a valid RFC 3986 URI: backslash"),
    c("https://example.com/a|b",
      "not a valid RFC 3986 URI: character outside RFC 3986"),
    c("https://example.com/a%zz", "not a valid RFC 3986 URI: stray %"),
    c("https://example.com/a%2", "not a valid RFC 3986 URI: stray %"),
    c("https://example.com/a b\\c%",
      "not a valid RFC 3986 URI: raw space, backslash, stray %"),
    c("/a/./b", paste0(pp_noauth, "; ", pp_dots)),
    c("/a/b", pp_noauth)
  )
  urls <- vapply(rows, `[[`, "", 1L)
  r <- pp_rfc3986(urls)
  expect_identical(r$url_preprocessing_note, vapply(rows, `[[`, "", 2L))
})

test_that("rfc3986 evaluates invalid input, its path bytes unchanged", {
  urls <- c(
    "https://example.com/a b", "https://example.com/caf\u00e9/x",
    "https://example.com/a\\..\\b"
  )
  for (backend in names(pp_engines)) {
    token <- pp_engines[[backend]]
    new <- pp_eval(urls, backend, token, "rfc3986")
    old <- pp_today(urls, backend, token)
    expect_identical(new$matcher_url, urls, label = backend)
    expect_identical(charToRaw(new$matcher_url[[2]]), charToRaw(urls[[2]]))
    expect_identical(new$url_decision, old$url_decision)
    expect_false(anyNA(new$url_preprocessing_note))
  }
})

test_that("rfc3986 on a URL with no scheme or authority", {
  urls <- c("/a/../b", "/a/./b", "example.com/a/../b", "a/../../x", "/x")
  r <- pp_rfc3986(urls)
  expect_identical(
    r$matcher_url, c("/b", "/a/b", "example.com/b", "a/x", "/x")
  )
  expect_identical(r$url_decision[[2]], "disallow")
  expect_identical(r$matched_rule_value[[2]], "/a/b")
  expect_true(all(startsWith(r$url_preprocessing_note, pp_noauth)))
  # Bing and Yandex refuse a target with no authority in either mode.
  for (backend in c("bing", "yandex")) {
    token <- pp_engines[[backend]]
    expect_identical(
      pp_eval("/a/./b", backend, token, "rfc3986")$reason,
      pp_today("/a/./b", backend, token)$reason
    )
  }
})

test_that("rfc3986 never makes an authority the input does not have", {
  # "/a/..//evil.com/x" would become "//evil.com/x", which a reader takes
  # as a host; "https:/q/..//h2/a/x" would become "https://h2/a/x". Both
  # are kept as given, with the reason (review round 1).
  rows <- list(
    list("/a/..//evil.com/x", "User-agent: *\nDisallow: /x\n"),
    list("https:/q/..//h2/a/x", "User-agent: *\nDisallow: /a/\n")
  )
  for (row in rows) {
    new <- pp_eval(row[[1]], "google", "Googlebot", "rfc3986", row[[2]])
    old <- pp_today(row[[1]], "google", "Googlebot", row[[2]])
    expect_identical(new$matcher_url, row[[1]])
    expect_identical(new$url_decision, old$url_decision)
    expect_identical(new$url_decision, "allow")
    expect_identical(
      new$url_preprocessing_note, paste0(pp_noauth, "; ", pp_kept)
    )
    for (backend in c("bing", "yandex")) {
      token <- pp_engines[[backend]]
      expect_identical(
        pp_eval(row[[1]], backend, token, "rfc3986", row[[2]])[
          c("matcher_status", "url_decision", "reason")
        ],
        pp_today(row[[1]], backend, token, row[[2]])[
          c("matcher_status", "url_decision", "reason")
        ],
        label = backend
      )
    }
  }
  # With an authority, a leading "//" in the path is only a path.
  r <- pp_rfc3986("https://h/a/..//x")
  expect_identical(r$matcher_url, "https://h//x")
  expect_identical(r$url_preprocessing_note, pp_dots)
})

test_that("rfc3986 notes say what the input lacks", {
  urls <- c(
    "x", "example.com", "https:", "mailto:a.b", "/a", "https:/a", "x//y"
  )
  r <- pp_rfc3986(urls)
  expect_identical(r$matcher_url, urls)
  # "x//y" has no dot segment, so nothing was left in place.
  expect_identical(
    r$url_preprocessing_note,
    c(rep(pp_noslash, 4L), rep(pp_noauth, 3L))
  )
})

test_that("rfc3986 reads a leading `:` as no scheme (Appendix B)", {
  # The scheme needs one character before its ":". Read as a scheme, ":"
  # would give "://h/a/../x" the authority "h" and the URL "://h/x".
  r <- pp_rfc3986("://h/a/../x")
  expect_identical(r$matcher_url, "://h/a/../x")
  expect_identical(r$url_preprocessing_note, paste0(pp_noauth, "; ", pp_kept))
})

test_that("rfc3986 records controls as characters outside RFC 3986", {
  r <- pp_rfc3986(c("https://example.com/a\tb", "https://example.com/a\x7fb"))
  expect_identical(
    r$url_preprocessing_note,
    rep("not a valid RFC 3986 URI: character outside RFC 3986", 2L)
  )
})

test_that("rfc3986 keeps an unchanged URL's bytes and encoding mark", {
  latin <- "https://example.com/caf\xe9"
  Encoding(latin) <- "latin1"
  utf8 <- enc2utf8(latin)
  pre <- preprocess_matcher_url_v1(c(latin, utf8), "rfc3986")
  expect_identical(Encoding(pre$matcher_url), c("latin1", "UTF-8"))
  expect_identical(charToRaw(pre$matcher_url[[1]]), charToRaw(latin))
  expect_identical(charToRaw(pre$matcher_url[[2]]), charToRaw(utf8))
})

test_that("rfc3986 rebuilds a latin1 URL in latin1, read as its UTF-8 twin", {
  latin <- "https://example.com/a/../caf\xe9"
  Encoding(latin) <- "latin1"
  utf8 <- enc2utf8(latin)
  pre <- preprocess_matcher_url_v1(c(latin, utf8), "rfc3986")
  expect_identical(Encoding(pre$matcher_url), c("latin1", "UTF-8"))
  expect_identical(enc2utf8(pre$matcher_url[[1]]), pre$matcher_url[[2]])
  # An ASCII rule, so the decision turns on the dot removal alone.
  body <- "User-agent: *\nDisallow: /caf\n"
  for (backend in names(pp_engines)) {
    token <- pp_engines[[backend]]
    expect_identical(
      pp_eval(latin, backend, token, "rfc3986", body)$url_decision,
      pp_eval(utf8, backend, token, "rfc3986", body)$url_decision,
      label = backend
    )
  }
  expect_identical(
    pp_eval(latin, "google", "Googlebot", "rfc3986", body)$url_decision,
    "disallow"
  )
})

test_that("rfc3986 stays linear when the output stack grows", {
  deep <- paste0("https://h", strrep("/a", 4000L), strrep("/..", 4000L), "/x")
  flat <- paste0("https://h", strrep("/a", 4000L))
  elapsed <- system.time({
    deep_out <- preprocess_matcher_url_v1(deep, "rfc3986")
    flat_out <- preprocess_matcher_url_v1(flat, "rfc3986")
  })[["elapsed"]]
  expect_identical(deep_out$matcher_url, "https://h/x")
  expect_identical(flat_out$matcher_url, flat)
  # Quadratic code took about six seconds here; linear code takes well
  # under one.
  expect_lt(elapsed, 2)
})

test_that("rfc3986 edge inputs: NA, empty, latin1, bytes and a long path", {
  r <- pp_rfc3986(c(NA_character_, ""))
  expect_identical(r$matcher_url, c(NA_character_, ""))
  expect_identical(r$url_preprocessing_note, c(NA_character_, NA_character_))
  expect_identical(r$reason, c("input_invalid", "input_invalid"))

  latin <- "https://example.com/caf\xe9/../a/b"
  Encoding(latin) <- "latin1"
  r <- pp_rfc3986(latin)
  expect_identical(r$matcher_url, "https://example.com/a/b")
  expect_identical(r$url_decision, "disallow")

  # A "bytes"-marked URL keeps its mark, so the Google row path treats it
  # as it did before (google_batch_refused_v1()).
  raw_url <- "https://example.com/a/./b\xff"
  Encoding(raw_url) <- "bytes"
  pre <- preprocess_matcher_url_v1(raw_url, "rfc3986")
  expect_identical(Encoding(pre$matcher_url), "bytes")
  expect_identical(
    charToRaw(pre$matcher_url), charToRaw("https://example.com/a/b\xff")
  )
  outcome <- function(mode) {
    tryCatch(
      pp_eval(raw_url, "google", "Googlebot", mode)$url_decision,
      error = function(e) class(e)
    )
  }
  expect_identical(outcome("rfc3986"), outcome("none"))

  long <- paste0(
    "https://example.com", strrep("/seg/..", 20000L), "/a/b"
  )
  r <- pp_rfc3986(long)
  expect_identical(r$matcher_url, "https://example.com/a/b")
})

# ---- remove_dot_segments ----------------------------------------------------

# RFC 3986 section 5.2.4 as written: string buffers, one step per pass.
pp_reference_rds <- function(input) {
  output <- ""
  while (nzchar(input)) {
    if (startsWith(input, "../")) {
      input <- substring(input, 4L)
    } else if (startsWith(input, "./")) {
      input <- substring(input, 3L)
    } else if (startsWith(input, "/./")) {
      input <- substring(input, 3L)
    } else if (input == "/.") {
      input <- "/"
    } else if (startsWith(input, "/../") || input == "/..") {
      input <- if (input == "/..") "/" else substring(input, 4L)
      output <- sub("/?[^/]*$", "", output)
    } else if (input %in% c(".", "..")) {
      input <- ""
    } else {
      seg <- regmatches(input, regexpr("^/?[^/]*", input))
      output <- paste0(output, seg)
      input <- substring(input, nchar(seg) + 1L)
    }
  }
  output
}

pp_rds <- function(path) {
  rawToChar(remove_dot_segments_v1(charToRaw(path)))
}

test_that("remove_dot_segments matches RFC 3986 section 5.2.4", {
  expect_identical(pp_rds("/a/b/c/./../../g"), "/a/g")
  expect_identical(pp_rds("mid/content=5/../6"), "mid/6")
  expect_identical(pp_rds("/b/c/../../../g"), "/g")
  expect_identical(pp_rds("/b/c/./g/."), "/b/c/g/")
  expect_identical(pp_rds("/b/c/g/.."), "/b/c/")
  expect_identical(pp_rds("/b/c/g.."), "/b/c/g..")
  expect_identical(pp_rds("/b/c/..g"), "/b/c/..g")
  expect_identical(pp_rds("/b/c/./../g"), "/b/g")
  expect_identical(pp_rds("/a/%2e%2e/b"), "/a/%2e%2e/b")
  expect_identical(pp_rds(""), "")
  expect_identical(pp_rds(".."), "")
  expect_identical(pp_rds("/"), "/")
})

test_that("remove_dot_segments agrees with the RFC text on generated paths", {
  pieces <- c("/", ".", "..", "a", "b", "%2e", "/./", "/../", "./", "../")
  set.seed(20261121)
  for (k in seq_len(400L)) {
    path <- paste(sample(pieces, sample(1:8, 1L), replace = TRUE),
                  collapse = "")
    expect_identical(pp_rds(path), pp_reference_rds(path), info = path)
  }
})

# ---- the other entry points --------------------------------------------------

test_that("evaluate_url_v1: the mode moves the decision, not the fetch", {
  seen <- new.env(parent = emptyenv())
  seen$hits <- 0L
  local_fake_ssrfr(function(req) {
    seen$hits <- seen$hits + 1L
    fake_response(200L, body = pp_body)
  })
  url <- "http://a/latam/../account/x"
  new <- robots_evaluate_url_v1(url, "Googlebot", "google", "google")
  old <- robots_evaluate_url_v1(
    url, "Googlebot", "google", "google", url_normalization = "none"
  )
  expect_identical(seen$hits, 2L)
  expect_identical(new$evidence$requested_url, old$evidence$requested_url)
  expect_identical(new$results$url_decision, "disallow")
  expect_identical(old$results$url_decision, "allow")
  expect_identical(new$results$matcher_url, "http://a/account/x")
  expect_identical(old$results$matcher_url, url)
})

test_that("the legacy adapter carries the decision, not the columns", {
  engine <- robots_evaluate_text_v1(
    pp_body, "https://example.com/latam/../account/x", "Googlebot",
    "google", "google"
  )
  legacy <- as_legacy_robots_decisions_v1(engine)
  expect_false(legacy$results$allowed)
  expect_false(any(
    c("matcher_url", "url_preprocessing_note", "group_token") %in%
      names(legacy$results)
  ))
})
