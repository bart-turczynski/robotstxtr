# Evaluator URL preprocessing (ROBO-bnvdmdjr; design/adr/0002). The v1
# facades take `url_normalization`: "rfc3986" (the default) applies RFC 3986
# section 5.2.4 to the path, splits the authority the RFC 3986 way and drops
# the fragment, and never encodes, decodes or case-folds an escape; "whatwg"
# reads the URL as rurl's WHATWG serializer writes it; "none" reads the URL
# as given, as the facades did before. Every row carries the disagreement
# flag, which compares the rfc3986 and whatwg targets.

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
  expect_identical(
    engine_url_normalizations_v1(), c("rfc3986", "whatwg", "none")
  )
  expect_identical(
    robots_engine_contract_v1()$url_normalizations,
    engine_url_normalizations_v1()
  )
  expect_identical(
    robots_engine_contract_v2()$url_normalizations,
    engine_url_normalizations_v1()
  )
  expect_identical(
    formals(robots_evaluate_text_v1)$url_normalization, "rfc3986"
  )
  expect_identical(
    formals(robots_evaluate_url_v1)$url_normalization, "rfc3986"
  )
  bads <- list("WHATWG", c("none", "rfc3986"), NA_character_, 1, "")
  for (bad in bads) {
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

test_that("the flag columns follow the URL columns, in every mode", {
  for (mode in engine_url_normalizations_v1()) {
    r <- pp_eval(
      "https://example.com/latam/%2e%2e/account/x", "google", "Googlebot",
      mode
    )
    expect_identical(
      names(r)[ncol(r) - 4:0],
      c(
        "matcher_url", "url_preprocessing_note",
        "preprocessing_disagreement", "disagreement_clients",
        "matched_rule_value_raw"
      ),
      label = mode
    )
    expect_type(r$preprocessing_disagreement, "logical")
    expect_type(r$disagreement_clients, "character")
  }
})

# What rurl's WHATWG serializer does with the forms every client keeps or
# removes. These hold on rurl 3.0.1, 3.1.0 and main; space and non-ASCII
# encoding output is left unpinned, since it is not stable across them.
pp_whatwg_stable <- list(
  c("https://example.com/latam/../account/x", "https://example.com/account/x"),
  c("https://example.com/latam/%2e%2e/account/x",
    "https://example.com/account/x"),
  c("https://example.com/a/%2E%2E/b", "https://example.com/b"),
  c("https://example.com/a/.%2E/b", "https://example.com/b"),
  c("https://example.com/a/%2e./b", "https://example.com/b"),
  rep("https://example.com/a/%252e%252e/b", 2L),
  rep("https://example.com/a%2F..%2Fb", 2L),
  rep("https://example.com//a//b", 2L),
  rep("https://example.com/a..b/.well-known", 2L),
  rep("https://example.com/p?x=../y", 2L)
)

test_that("rurl's WHATWG serializer on the forms the modes are tested on", {
  urls <- vapply(pp_whatwg_stable, `[[`, "", 1L)
  expect_identical(
    unname(rurl::serialize_url(urls, standard = "whatwg")),
    vapply(pp_whatwg_stable, `[[`, "", 2L)
  )
  expect_true(is.na(rurl::serialize_url("/a/../b", standard = "whatwg")))
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
  # The rfc3986 targets alone: preprocess_matcher_url_v1() also asks rurl
  # for the whatwg target, whose cost is rurl's.
  elapsed <- system.time({
    deep_out <- rfc3986_matcher_urls_v1(deep)
    flat_out <- rfc3986_matcher_urls_v1(flat)
  })[["elapsed"]]
  expect_identical(deep_out$url, "https://h/x")
  expect_identical(flat_out$url, flat)
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
    c(
      "matcher_url", "url_preprocessing_note", "preprocessing_disagreement",
      "disagreement_clients", "group_token"
    ) %in% names(legacy$results)
  ))
})

# ---- "whatwg" ----------------------------------------------------------------

pp_whatwg <- function(url, backend = "google", token = "Googlebot",
                      body = pp_body) {
  pp_eval(url, backend, token, "whatwg", body)
}

pp_families <- c(
  rfc3986 = "wget 1.25, curl/libcurl < 8.13.0",
  whatwg = "Chrome 157, Node 26 fetch, curl/libcurl >= 8.13.0"
)

pp_clients <- function(rfc3986, whatwg) {
  sprintf(
    "rfc3986 %s (dot segments as in: %s); whatwg %s (dot segments as in: %s)",
    rfc3986, pp_families[["rfc3986"]], whatwg, pp_families[["whatwg"]]
  )
}

pp_neutral <- function(rfc3986, whatwg) {
  sprintf(
    paste0(
      "rfc3986 %s; whatwg %s: the forms differ in more than dot segments; ",
      "no client survey covers this"
    ),
    rfc3986, whatwg
  )
}

pp_ww_changed <- "WHATWG URL serialization changed the URL"
pp_ww_invalid <- "not a valid WHATWG URL: evaluated as given"

test_that("whatwg reads the URL as rurl serializes it (stable forms)", {
  urls <- vapply(pp_whatwg_stable, `[[`, "", 1L)
  r <- pp_whatwg(urls)
  expect_identical(r$matcher_url, vapply(pp_whatwg_stable, `[[`, "", 2L))
  expect_identical(r$url, urls)
  changed <- r$matcher_url != urls
  expect_identical(
    r$url_preprocessing_note, ifelse(changed, pp_ww_changed, NA_character_)
  )
})

test_that("whatwg removes literal and encoded dots on every backend", {
  urls <- c(
    "https://example.com/latam/../account/x",
    "https://example.com/latam/%2e%2e/account/x",
    "https://example.com/latam/%2E%2E/account/x",
    "https://example.com/latam/.%2E/account/x",
    "https://example.com/latam/%252e%252e/account/x"
  )
  for (backend in names(pp_engines)) {
    r <- pp_whatwg(urls, backend, pp_engines[[backend]])
    expect_identical(
      r$url_decision, c(rep("disallow", 4L), "allow"), label = backend
    )
    expect_identical(
      r$matcher_url[1:4], rep("https://example.com/account/x", 4L)
    )
  }
})

test_that("whatwg leaves userinfo out and drops the fragment", {
  urls <- c("https://u;v@example.com/x", "https://example.com/x#a/../b")
  for (backend in names(pp_engines)) {
    r <- pp_whatwg(urls, backend, pp_engines[[backend]])
    expect_identical(r$url_decision, c("disallow", "disallow"))
    expect_identical(r$matcher_url, rep("https://example.com/x", 2L))
    expect_identical(
      r$url_preprocessing_note, c("userinfo removed", "fragment dropped")
    )
  }
})

test_that("whatwg evaluates a URL rurl cannot parse as given", {
  urls <- c("https://[::1/x", "https://[::1/a/../b")
  for (backend in names(pp_engines)) {
    token <- pp_engines[[backend]]
    new <- pp_whatwg(urls, backend, token)
    old <- pp_today(urls, backend, token)
    expect_identical(new$matcher_url, urls, label = backend)
    expect_identical(new$url_preprocessing_note, rep(pp_ww_invalid, 2L))
    expect_identical(
      new[c("matcher_status", "url_decision", "reason")],
      old[c("matcher_status", "url_decision", "reason")]
    )
    expect_identical(new$preprocessing_disagreement, c(TRUE, TRUE))
  }
})

pp_count_dispatch <- function(env) {
  real <- dispatch_matcher_v1
  local_mocked_bindings(
    dispatch_matcher_v1 = function(registry, backend, bodies, urls, ...) {
      env$urls <- c(env$urls, urls)
      real(registry, backend, bodies, urls, ...)
    },
    .env = parent.frame()
  )
}

pp_ww_relative <- pp_noauth
pp_ww_guard <- paste0(
  pp_noauth,
  "; WHATWG serialization left in place: it would start the path with //"
)

test_that("whatwg reads a URL with no scheme on the placeholder origin", {
  # Chrome and Node request /account/x for this link.
  urls <- c(
    "/latam/../account/x", "/latam/%2e%2e/account/x", "/latam/y?q=1#f"
  )
  r <- pp_whatwg(urls)
  expect_identical(r$matcher_url, c("/account/x", "/account/x", "/latam/y?q=1"))
  expect_identical(r$url_decision, c("disallow", "disallow", "allow"))
  expect_identical(
    r$url_preprocessing_note,
    c(
      rep(paste0(pp_ww_relative, "; ", pp_ww_changed), 2L),
      paste0(pp_ww_relative, "; fragment dropped")
    )
  )
  # Not a failure: the literal-dot row is no disagreement under the default,
  # and the encoded one is named with the families.
  d <- pp_eval(urls[1:2], "google", "Googlebot", "rfc3986")
  expect_identical(d$url_decision, c("disallow", "allow"))
  expect_identical(d$preprocessing_disagreement, c(FALSE, TRUE))
  expect_identical(
    d$disagreement_clients[[2]], pp_clients("allow", "disallow")
  )
  # Bing and Yandex refuse a target with no authority in every mode.
  for (backend in c("bing", "yandex")) {
    token <- pp_engines[[backend]]
    expect_identical(
      pp_whatwg(urls[[1]], backend, token)$reason,
      pp_today(urls[[1]], backend, token)$reason
    )
  }
})

test_that("whatwg keeps a host-like lead before the first /", {
  body <- "User-agent: *\nDisallow: /a\n"
  urls <- c("example.com/a", "example.com/a/./b")
  for (mode in c("rfc3986", "whatwg")) {
    r <- pp_eval(urls, "google", "Googlebot", mode, body)
    expect_identical(
      r$matcher_url, c("example.com/a", "example.com/a/b"), label = mode
    )
    expect_identical(r$url_decision, c("disallow", "disallow"))
    expect_identical(r$preprocessing_disagreement, c(FALSE, FALSE))
  }
  # With no "/", whatwg reads it as rfc3986 does.
  r <- pp_whatwg(c("example.com", "x?q=1"))
  expect_identical(r$matcher_url, c("example.com", "x?q=1"))
  expect_identical(r$url_preprocessing_note, rep(pp_noslash, 2L))
})

test_that("whatwg never makes an authority a scheme-less input lacks", {
  # The serialized path would start with //: evaluated as given, as
  # rfc3986 guards its own removal.
  body <- "User-agent: *\nDisallow: /x\n"
  urls <- c("/a/..//h/x", "/..//h/x", "a/..//h/x")
  r <- pp_whatwg(urls, body = body)
  expect_identical(r$matcher_url, urls)
  expect_identical(r$url_decision, rep("allow", 3L))
  expect_identical(r$url_preprocessing_note, rep(pp_ww_guard, 3L))
  d <- pp_eval(urls, "google", "Googlebot", "rfc3986", body)
  expect_identical(d$url_decision, rep("allow", 3L))
  expect_identical(d$preprocessing_disagreement, rep(FALSE, 3L))
  expect_identical(r$preprocessing_disagreement, rep(FALSE, 3L))
  # An absolute URL keeps its own host.
  a <- pp_whatwg("https://example.com/a/..//h/x", body = body)
  expect_identical(a$matcher_url, "https://example.com//h/x")
  expect_identical(a$url_decision, "allow")
  # Bing and Yandex refuse every scheme-less target, in every mode.
  for (backend in c("bing", "yandex")) {
    token <- pp_engines[[backend]]
    for (mode in c("rfc3986", "whatwg")) {
      w <- pp_eval(urls, backend, token, mode, body)
      expect_identical(
        w$reason, rep("invalid_request_target", 3L),
        label = paste(backend, mode)
      )
      expect_identical(w$preprocessing_disagreement, rep(FALSE, 3L))
    }
  }
})

test_that("whatwg splits a scheme-less URL exactly as rfc3986 does", {
  body <- "User-agent: *\nDisallow: /x\nDisallow: /*..\n"
  # An authority with no scheme: host h, path /x, as rfc3986 reads it.
  urls <- c("//h/x", "//example.com/x/y")
  for (mode in c("rfc3986", "whatwg")) {
    r <- pp_eval(urls, "google", "Googlebot", mode, body)
    expect_identical(r$matcher_url, urls, label = mode)
    expect_identical(r$url_decision, c("disallow", "disallow"))
    expect_identical(r$preprocessing_disagreement, c(FALSE, FALSE))
  }
  # No path starting with "/": the query is kept as rfc3986 keeps it, and
  # the fragment is never read.
  urls <- c("foo?q=/a/../b", "?q=/a/../x", "a#/b/../c")
  ww <- pp_whatwg(urls, body = body)
  rfc <- pp_eval(urls, "google", "Googlebot", "rfc3986", body)
  expect_identical(ww$matcher_url, c("foo?q=/a/../b", "?q=/a/../x", "a"))
  expect_identical(ww[c("matcher_url", "url_preprocessing_note")],
                   rfc[c("matcher_url", "url_preprocessing_note")])
  expect_identical(ww$url_decision, c("disallow", "disallow", "allow"))
  expect_identical(rfc$preprocessing_disagreement, rep(FALSE, 3L))
  # Encoded dots after a host-like lead are named with the families.
  r <- pp_eval("example.com/%2e%2e/account/x", "google", "Googlebot",
               "rfc3986")
  expect_identical(r$url_decision, "allow")
  expect_true(r$preprocessing_disagreement)
  expect_identical(r$disagreement_clients, pp_clients("allow", "disallow"))
  expect_identical(
    pp_whatwg("example.com/%2e%2e/account/x")$matcher_url,
    "example.com/account/x"
  )
})

test_that("a latin1 scheme-less URL reads as its UTF-8 twin", {
  latin <- "caf\xe9/a"
  Encoding(latin) <- "latin1"
  twin <- enc2utf8(latin)
  ww <- pp_whatwg(c(latin, twin))
  expect_identical(ww$url_preprocessing_note, rep(pp_noauth, 2L))
  expect_identical(enc2utf8(ww$matcher_url[[1]]), ww$matcher_url[[2]])
  seen <- new.env(parent = emptyenv())
  pp_count_dispatch(seen)
  r <- pp_eval(c(latin, twin), "google", "Googlebot", "rfc3986")
  # One selected pass, no second: the two targets are the same.
  expect_length(seen$urls, 2L)
  expect_identical(r$preprocessing_disagreement, c(FALSE, FALSE))
})

test_that("whatwg reads UTF-8 bytes the same in a C locale", {
  url <- rawToChar(charToRaw("https://example.com/caf\xc3\xa9/x"))
  body <- "User-agent: *\nDisallow: /caf%C3%A9\n"
  old <- Sys.getlocale("LC_CTYPE")
  on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
  set <- suppressWarnings(Sys.setlocale("LC_CTYPE", "C"))
  skip_if(!nzchar(set), "the C locale is not available")
  pre <- preprocess_matcher_url_v1(url, "whatwg")
  expect_identical(pre$whatwg_url, "https://example.com/caf%C3%A9/x")
  expect_identical(
    pp_eval(url, "google", "Googlebot", "whatwg", body)$url_decision,
    "disallow"
  )
  # A latin1-marked URL is converted from latin1, not from the locale.
  latin <- "https://example.com/caf\xe9/x"
  Encoding(latin) <- "latin1"
  expect_identical(
    preprocess_matcher_url_v1(latin, "whatwg")$whatwg_url,
    "https://example.com/caf%C3%A9/x"
  )
  # So is one with no scheme, whose path is cut from its bytes.
  rel <- "/caf\xe9/a/../b"
  Encoding(rel) <- "latin1"
  expect_identical(
    preprocess_matcher_url_v1(rel, "whatwg")$whatwg_url, "/caf%C3%A9/b"
  )
  # An unmarked UTF-8 URL with no scheme reads the same as a marked one.
  rel <- rawToChar(charToRaw("/caf\xc3\xa9/a/../b"))
  expect_identical(
    preprocess_matcher_url_v1(rel, "whatwg")$whatwg_url, "/caf%C3%A9/b"
  )
  # A non-ASCII lead is kept with its bytes and its mark, so the matcher
  # reads it as UTF-8 here too.
  lead <- "café/a/../b"
  out <- preprocess_matcher_url_v1(lead, "whatwg")$matcher_url
  expect_identical(Encoding(out), "UTF-8")
  expect_identical(charToRaw(out), charToRaw("café/b"))
})

test_that("whatwg: an unchanged URL passes as given, with no note", {
  urls <- c("https://example.com/a/b?q=1", "https://example.com/latam/y")
  for (backend in names(pp_engines)) {
    token <- pp_engines[[backend]]
    new <- pp_whatwg(urls, backend, token)
    old <- pp_today(urls, backend, token)
    expect_identical(new$matcher_url, urls, label = backend)
    expect_true(all(is.na(new$url_preprocessing_note)))
    expect_identical(new[names(old)], old)
  }
})

test_that("whatwg: NA, empty, bytes-marked and failing URLs", {
  r <- pp_whatwg(c(NA_character_, ""))
  expect_identical(r$matcher_url, c(NA_character_, ""))
  expect_identical(r$url_preprocessing_note, c(NA_character_, NA_character_))
  expect_identical(r$preprocessing_disagreement, c(FALSE, FALSE))
  expect_identical(r$disagreement_clients, c(NA_character_, NA_character_))

  raw_url <- "https://example.com/a/%2e%2e/b\xff"
  Encoding(raw_url) <- "bytes"
  pre <- preprocess_matcher_url_v1(raw_url, "whatwg")
  expect_identical(pre$matcher_url, raw_url)
  expect_identical(Encoding(pre$matcher_url), "bytes")
  expect_true(pre$whatwg_failed)

  # An unmarked URL whose bytes are not UTF-8 fails too: rurl would read
  # the byte as U+FFFD (%EF%BF%BD).
  bad <- "https://example.com/a/%2e%2e/b\xff"
  expect_identical(Encoding(bad), "unknown")
  pre <- preprocess_matcher_url_v1(bad, "whatwg")
  expect_true(pre$whatwg_failed)
  expect_identical(pre$matcher_url, bad)
  expect_identical(pre$note, pp_ww_invalid)

  # An error on the vector is retried URL by URL, so one URL fails alone.
  local_mocked_bindings(
    serialize_url = function(url, standard) {
      if (any(grepl("boom", url, fixed = TRUE))) stop("rurl failed")
      url
    },
    .package = "rurl"
  )
  expect_identical(
    whatwg_serialize_v1(c("https://h/a", "https://h/boom", "https://h/b")),
    c("https://h/a", NA, "https://h/b")
  )
})

test_that("rurl sees each distinct URL once; a short answer is retried", {
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    serialize_url = function(url, standard) {
      seen$calls <- c(seen$calls, length(url))
      # One answer short for a vector: the length check must catch it.
      if (length(url) > 1L) url[-1L] else url
    },
    .package = "rurl"
  )
  expect_identical(
    whatwg_serialize_v1(c("https://h/a", "https://h/b", "https://h/a")),
    c("https://h/a", "https://h/b", "https://h/a")
  )
  expect_identical(seen$calls, c(2L, 1L, 1L))
})

# ---- the disagreement flag ---------------------------------------------------

pp_unparsed <- function(rfc3986) {
  sprintf(
    "rfc3986 %s; whatwg cannot parse the URL; no client survey covers this",
    rfc3986
  )
}

test_that("the client families name the curl boundary", {
  expect_identical(url_client_families_v1(), pp_families)
})

# A URL of `bytes` bytes whose rfc3986 and whatwg forms decide apart:
# padding in the query moves neither decision.
pp_sized <- function(bytes) {
  head <- "https://example.com/latam/%2e%2e/account/x?q="
  paste0(head, strrep("a", bytes - nchar(head, type = "bytes")))
}

# Rows: the encoded dots decide apart (both directions), forms that differ
# but decide alike, identical targets, literal dots (both modes remove
# them), and a URL whatwg cannot parse.
pp_flag_urls <- c(
  "https://example.com/latam/%2e%2e/account/x",
  "https://example.com/q/%2e%2e/z",
  "https://example.com/a/b",
  "https://example.com/latam/../account/x",
  "https://[::1/a/../b"
)

test_that("the families are named only when encoded dots alone differ", {
  # Each URL has a literal dot segment and differs in something else too,
  # so its disagreement is neutral.
  cafe <- "https://example.com/café/a/../b"
  rows <- list(
    list("https://example.com/./a\\b", "User-agent: *\nDisallow: /a/b\n"),
    list("https://example.com/./a/b c", "User-agent: *\nDisallow: /a/b%20c\n"),
    list("https://example.com/./p?a=b'c",
         "User-agent: *\nDisallow: /p?a=b%27c\n"),
    list(cafe, "User-agent: *\nDisallow: /café/b\n"),
    list("https://example.com/a b", "User-agent: *\nDisallow: /a%20b\n")
  )
  for (row in rows) {
    for (backend in names(pp_engines)) {
      r <- pp_eval(row[[1]], backend, pp_engines[[backend]], "rfc3986",
                   row[[2]])
      expect_true(r$preprocessing_disagreement, label = row[[1]])
      expect_identical(
        r$disagreement_clients,
        pp_neutral(r$url_decision, setdiff(c("allow", "disallow"),
                                           r$url_decision)),
        label = row[[1]]
      )
    }
  }
  # Encoded dot segments in either case, alone or with literal ones, name
  # them.
  dotted <- c(
    "https://example.com/latam/%2E%2E/account/x",
    "https://example.com/latam/.%2e/account/x",
    "https://example.com/latam/%2e./account/x",
    "https://example.com/latam/./%2e%2e/account/x"
  )
  r <- pp_eval(dotted, "google", "Googlebot", "rfc3986")
  expect_identical(
    r$disagreement_clients, rep(pp_clients("allow", "disallow"), 4L)
  )
  rd <- function(path) {
    rawToChar(url_decode_dot_segments_v1(charToRaw(path)))
  }
  expect_identical(
    vapply(
      c("/a/%2E/b", "/a/%2e%2E", "/.%2e/x", "/a%2eb/c", "/%252e/", "/x"),
      rd, "", USE.NAMES = FALSE
    ),
    c("/a/./b", "/a/..", "/../x", "/a%2eb/c", "/%252e/", "/x")
  )
  # A URL whatwg cannot parse is neutral, with the rfc3986 decision.
  r <- pp_eval("https://[::1/x", "google", "Googlebot", "rfc3986")
  expect_identical(r$disagreement_clients, pp_unparsed("disallow"))
})

test_that("the flag marks rows the two forms decide apart, in every mode", {
  for (mode in engine_url_normalizations_v1()) {
    for (backend in names(pp_engines)) {
      r <- pp_eval(pp_flag_urls, backend, pp_engines[[backend]], mode)
      expect_identical(
        r$preprocessing_disagreement, c(TRUE, FALSE, FALSE, FALSE, TRUE),
        label = paste(mode, backend)
      )
      expect_identical(
        r$disagreement_clients,
        c(pp_clients("allow", "disallow"), NA, NA, NA, pp_unparsed("allow"))
      )
    }
  }
})

test_that("the flag works the other way round: whatwg allows", {
  body <- "User-agent: *\nDisallow: /latam/%2E%2E/\n"
  url <- "https://example.com/latam/%2E%2E/account/x"
  for (backend in names(pp_engines)) {
    token <- pp_engines[[backend]]
    rfc <- pp_eval(url, backend, token, "rfc3986", body)
    ww <- pp_eval(url, backend, token, "whatwg", body)
    expect_identical(
      c(rfc$url_decision, ww$url_decision), c("disallow", "allow"),
      label = backend
    )
    expect_true(rfc$preprocessing_disagreement)
    expect_identical(rfc$disagreement_clients, pp_clients("disallow", "allow"))
    expect_identical(ww$disagreement_clients, rfc$disagreement_clients)
  }
  # Both directions in one batch: each row carries its own decisions.
  body <- paste0(
    "User-agent: *\nDisallow: /account/\nAllow: /latam\n",
    "Disallow: /b/%2E%2E/\n"
  )
  r <- pp_eval(
    c(
      "https://example.com/latam/%2E%2E/account/x",
      "https://example.com/b/%2E%2E/c"
    ),
    "google", "Googlebot", "rfc3986", body
  )
  expect_identical(
    r$disagreement_clients,
    c(pp_clients("allow", "disallow"), pp_clients("disallow", "allow"))
  )
})

test_that("rows no matcher decides are never flagged", {
  # The last row is one whatwg cannot parse, and one over the cap.
  urls <- c(pp_flag_urls, pp_sized(2049L))
  for (mode in engine_url_normalizations_v1()) {
    r <- pp_eval(urls, "rfc9309", "FooBot", mode)
    expect_identical(r$matcher_status, rep("capability_unavailable", 6L))
    expect_identical(r$preprocessing_disagreement, rep(FALSE, 6L))
    expect_identical(r$disagreement_clients, rep(NA_character_, 6L))
  }
})

test_that("an undecided side is shown as undecided", {
  url <- "https://example.com/latam/%2e%2e/account/x"
  pre <- preprocess_matcher_url_v1(url, "rfc3986")
  out <- url_disagreement_v1(
    pre, 1L, "allow", decide = function(rows, urls) NA_character_
  )
  expect_true(out$flag)
  expect_identical(out$clients, pp_clients("allow", "undecided"))
})

# Two origins with two bodies, and crawler tokens with and without a parent,
# so a second pass that reads another row's body or profile changes a
# result. Only rows 2 to 4 have targets that differ, and only row 2's
# decide apart.
pp_batch_bodies <- list(
  a = "User-agent: *\nDisallow: /account/\nAllow: /latam\n",
  b = paste0(
    "User-agent: Googlebot\nAllow: /\n\n",
    "User-agent: *\nDisallow: /account/\nAllow: /latam\n"
  )
)

test_that("the second pass reads each row's own body and crawler profile", {
  local_fake_ssrfr(function(req) {
    host <- if (grepl("^http://b/", req$url)) "b" else "a"
    fake_response(200L, body = pp_batch_bodies[[host]])
  })
  urls <- c(
    "http://a/plain", "http://a/latam/%2e%2e/account/x",
    "http://b/latam/%2e%2e/account/x", "http://b/q/%2e%2e/z"
  )
  tokens <- c("FooBot", "FooBot", "Googlebot-Image", "FooBot")
  for (mode in c("rfc3986", "none")) {
    r <- robots_evaluate_url_v1(
      urls, tokens, "google", "google", url_normalization = mode
    )$results
    expect_identical(r$url_decision, rep("allow", 4L), label = mode)
    expect_identical(
      r$preprocessing_disagreement, c(FALSE, TRUE, FALSE, FALSE)
    )
  }
  # Under whatwg, row 3 reads its parent's group (Allow: /) on body b.
  r <- robots_evaluate_url_v1(
    urls, tokens, "google", "google", url_normalization = "whatwg"
  )$results
  expect_identical(
    r$url_decision, c("allow", "disallow", "allow", "allow")
  )
  expect_identical(r$preprocessing_disagreement, c(FALSE, TRUE, FALSE, FALSE))
})


test_that("the second pass runs only on rows whose targets differ", {
  seen <- new.env(parent = emptyenv())
  pp_count_dispatch(seen)
  r <- pp_eval(pp_flag_urls, "google", "Googlebot", "rfc3986")
  # The selected pass reads the five rfc3986 targets; the second reads the
  # whatwg target of the two rows whose targets differ.
  expect_identical(
    seen$urls,
    c(
      r$matcher_url,
      "https://example.com/account/x", "https://example.com/z"
    )
  )
  seen$urls <- NULL
  pp_eval("https://example.com/a/b", "google", "Googlebot", "none")
  expect_identical(seen$urls, "https://example.com/a/b")
})

test_that("under none, each differing side is read once", {
  seen <- new.env(parent = emptyenv())
  pp_count_dispatch(seen)
  url <- "https://example.com/latam/../q/%2e%2e/account/x"
  r <- pp_eval(url, "google", "Googlebot", "none")
  expect_identical(
    seen$urls,
    c(
      url, "https://example.com/q/%2e%2e/account/x",
      "https://example.com/account/x"
    )
  )
  expect_identical(r$url_decision, "allow")
  expect_true(r$preprocessing_disagreement)
  expect_identical(r$disagreement_clients, pp_clients("allow", "disallow"))
})

pp_count_rurl <- function(env) {
  real <- rurl::serialize_url
  local_mocked_bindings(
    serialize_url = function(url, ...) {
      env$rurl <- c(env$rurl, url)
      real(url, ...)
    },
    .package = "rurl", .env = parent.frame()
  )
}

test_that("targets that differ in nothing a matcher reads get no second pass", {
  # Scheme and host case, a default port, an empty path, a fragment.
  alike <- c(
    "HTTPS://Example.COM/a", "https://example.com:443/a",
    "http://example.com:80/a", "https://example.com", "https://example.com/a#f"
  )
  for (url in alike) {
    seen <- new.env(parent = emptyenv())
    pp_count_dispatch(seen)
    r <- pp_eval(url, "google", "Googlebot", "rfc3986")
    expect_identical(seen$urls, r$matcher_url, label = url)
    expect_false(r$preprocessing_disagreement)
  }
  # A path that differs still gets the second pass.
  seen <- new.env(parent = emptyenv())
  pp_count_dispatch(seen)
  pp_eval("https://Example.com/q/%2e%2e/z", "google", "Googlebot", "rfc3986")
  expect_identical(
    seen$urls, c("https://Example.com/q/%2e%2e/z", "https://example.com/z")
  )
  expect_identical(
    url_target_key_v1("https://Example.com:8443"),
    url_target_key_v1("https://example.com:8443/")
  )
  expect_false(identical(
    url_target_key_v1("https://example.com:8443/"),
    url_target_key_v1("https://example.com/")
  ))
})

test_that("the whatwg form is computed only for the rows compared", {
  seen <- new.env(parent = emptyenv())
  pp_count_rurl(seen)
  urls <- c(
    "https://example.com/decided/%2e%2e/a", "https://example.com/token",
    "https://example.com/rfc9309", "https://example.com/refused",
    "https://example.com/long?q=", "https://example.com/decided2"
  )
  urls[[5]] <- paste0(urls[[5]], strrep("a", 2100L))
  r <- robots_evaluate_text_v1(
    pp_body, urls, c("Googlebot", "", "Googlebot", "NotAYandexBot",
                     "Googlebot", "Googlebot"),
    "google", c("google", "google", "rfc9309", "yandex", "google", "google")
  )$results
  expect_identical(
    r$reason[2:4],
    c("input_invalid", "matcher_capability_unavailable",
      "unsupported_product_token")
  )
  # Rows 2 to 4 were not decided, and row 5 is over the cap.
  expect_identical(seen$rurl, urls[c(1L, 6L)])
  expect_identical(
    r$preprocessing_disagreement, c(FALSE, FALSE, FALSE, FALSE, NA, FALSE)
  )
})

test_that("whatwg: the legacy adapter carries the decision, not the flag", {
  engine <- robots_evaluate_text_v1(
    pp_body, pp_flag_urls[1:3], "Googlebot", "google", "google",
    url_normalization = "whatwg"
  )
  legacy <- as_legacy_robots_decisions_v1(engine)
  expect_identical(legacy$results$allowed, c(FALSE, TRUE, FALSE))
  expect_false(any(
    c("preprocessing_disagreement", "disagreement_clients") %in%
      names(legacy$results)
  ))
})

test_that("evaluate_url_v1 under whatwg: same fetch, flag on the row", {
  seen <- new.env(parent = emptyenv())
  seen$hits <- 0L
  local_fake_ssrfr(function(req) {
    seen$hits <- seen$hits + 1L
    fake_response(200L, body = pp_body)
  })
  url <- "http://a/latam/%2e%2e/account/x"
  new <- robots_evaluate_url_v1(
    url, "Googlebot", "google", "google", url_normalization = "whatwg"
  )
  old <- robots_evaluate_url_v1(url, "Googlebot", "google", "google")
  expect_identical(seen$hits, 2L)
  expect_identical(new$evidence$requested_url, old$evidence$requested_url)
  expect_identical(new$results$matcher_url, "http://a/account/x")
  expect_identical(
    c(new$results$url_decision, old$results$url_decision),
    c("disallow", "allow")
  )
  expect_true(new$results$preprocessing_disagreement)
  expect_true(old$results$preprocessing_disagreement)
})

# ---- the length cap on the comparison ----------------------------------------

pp_not_compared <- "not compared: URL longer than 2048 bytes"

test_that("the cap is 2048 bytes of the input URL", {
  expect_identical(url_disagreement_max_bytes_v1(), 2048L)
  expect_identical(url_disagreement_not_compared_v1(), pp_not_compared)
  expect_identical(nchar(pp_sized(2048L), type = "bytes"), 2048L)
  expect_identical(nchar(pp_sized(2049L), type = "bytes"), 2049L)
})

test_that("rfc3986 and none compare 2048 bytes, not 2049, and skip rurl", {
  at <- pp_sized(2048L)
  over <- pp_sized(2049L)
  for (mode in c("rfc3986", "none")) {
    for (backend in names(pp_engines)) {
      seen <- new.env(parent = emptyenv())
      pp_count_rurl(seen)
      r <- pp_eval(c(at, over), backend, pp_engines[[backend]], mode)
      expect_identical(
        r$preprocessing_disagreement, c(TRUE, NA),
        label = paste(mode, backend)
      )
      expect_identical(
        r$disagreement_clients,
        c(pp_clients("allow", "disallow"), pp_not_compared)
      )
      expect_identical(seen$rurl, at)
      # The selected decision is untouched by the cap.
      expect_identical(r$url_decision, c("allow", "allow"))
    }
  }
})

test_that("a URL over the cap gets no second matcher pass", {
  seen <- new.env(parent = emptyenv())
  pp_count_dispatch(seen)
  over <- pp_sized(2049L)
  r <- pp_eval(over, "google", "Googlebot", "rfc3986")
  expect_identical(seen$urls, r$matcher_url)
  # Under "none" too, though its rfc3986 target differs from the input.
  seen$urls <- NULL
  long_dots <- paste0("https://example.com/a/../", strrep("b", 2100L))
  pp_eval(long_dots, "google", "Googlebot", "none")
  expect_identical(seen$urls, long_dots)
})

test_that("whatwg compares and serializes any length", {
  over <- pp_sized(2049L)
  seen <- new.env(parent = emptyenv())
  pp_count_rurl(seen)
  r <- pp_whatwg(over)
  expect_identical(seen$rurl, over)
  expect_true(r$preprocessing_disagreement)
  expect_identical(r$disagreement_clients, pp_clients("allow", "disallow"))
  expect_identical(r$url_decision, "disallow")
})

test_that("20,000 dot-segment pairs under the default stay fast", {
  long <- paste0("https://example.com", strrep("/seg/..", 20000L), "/a/b")
  elapsed <- system.time(
    r <- robots_evaluate_text_v1(
      pp_body, long, "Googlebot", "google", "google"
    )$results
  )[["elapsed"]]
  expect_identical(r$matcher_url, "https://example.com/a/b")
  expect_identical(r$preprocessing_disagreement, NA)
  # rurl's whatwg serializer took about 53 seconds on this URL.
  expect_lt(elapsed, 10)
})

test_that("dot-heavy URLs just under the cap stay quick", {
  head <- "https://example.com"
  url <- paste0(head, strrep("/s/..", 403L), "/x")
  url <- paste0(url, strrep("y", 2040L - nchar(url)))
  expect_identical(nchar(url, type = "bytes"), 2040L)
  elapsed <- system.time(
    r <- robots_evaluate_text_v1(
      pp_body, rep(url, 5L), "Googlebot", "google", "google"
    )$results
  )[["elapsed"]]
  expect_identical(r$preprocessing_disagreement, rep(FALSE, 5L))
  # rurl sees the URL once, however many rows repeat it.
  expect_lt(elapsed, 3)
})
