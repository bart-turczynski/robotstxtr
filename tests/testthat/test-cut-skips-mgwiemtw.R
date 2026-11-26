# The checks a body cut at max_bytes skips (ROBO-mgwiemtw). Each fixture is
# a whole file that draws its code; read as a cut body (`body_truncated =
# TRUE`, the cut at its end, so no partial line is dropped) it draws none.

cs_fixtures <- list(
  wildcard_disallows_not_inherited = paste0(
    "User-agent: *\nDisallow: /private/\n\n",
    "User-agent: Foobot\nDisallow: /tmp/\n"
  ),
  allow_reopens_wildcard_disallow = paste0(
    "User-agent: *\nDisallow: /company/search/\n\n",
    "User-agent: Foobot\nDisallow: /\nAllow: /company\n"
  ),
  wildcard_rules_not_inherited = paste0(
    "User-agent: *\nDisallow: /\nAllow: /pub\n\n",
    "User-agent: Foobot\nDisallow: /\n"
  ),
  user_agent_groups_same_rules =
    "User-agent: Foo\nDisallow: /x\n\nUser-agent: Bar\nDisallow: /x\n",
  empty_disallow_with_full_block = "User-agent: *\nDisallow:\nDisallow: /\n",
  rule_query_parameter_position = "User-agent: *\nDisallow: /search?page=\n",
  rule_slash_split = "User-agent: *\nDisallow: /a/\n",
  rule_end_anchor_query = "User-agent: *\nDisallow: /a$\n",
  allow_reopens_through_query =
    "User-agent: *\nDisallow: /my/\nAllow: */s/\n",
  rule_render_resource_blocked = "User-agent: *\nDisallow: /*.js\n",
  rule_prefix_sibling = "User-agent: *\nDisallow: /feed\nDisallow: /feeds\n",
  no_rules = "User-agent: *\n"
)

cs_validate <- function(text, cut = FALSE) {
  body <- if (is.raw(text)) text else charToRaw(text)
  if (cut) {
    validate_document_bytes(body, "s", "supplied", max_bytes = length(body),
                            body_truncated = TRUE)
  } else {
    validate_document_bytes(body, "s", "supplied")
  }
}

cs_cut_message <- function(x) {
  d <- x$diagnostics
  d$message[d$code == "body_truncated"]
}

# The registry entry naming a fixture's code: the wildcard entry stands for
# all three wildcard inheritance codes.
cs_entry <- function(code) {
  if (startsWith(code, "wildcard_") || startsWith(code, "allow_reopens_wil")) {
    "wildcard_disallows_not_inherited"
  } else {
    code
  }
}

test_that("ROBO-mgwiemtw: each skipped code fires uncut, not on a cut body", {
  expect_true(all(names(validation_cut_skips) %in% names(cs_fixtures)))
  for (code in names(cs_fixtures)) {
    uncut <- cs_validate(cs_fixtures[[code]])$diagnostics$code
    x <- cs_validate(cs_fixtures[[code]], cut = TRUE)
    cut <- x$diagnostics$code
    expect_true(code %in% uncut, label = paste(code, "uncut"))
    expect_false(code %in% cut, label = paste(code, "cut"))
    expect_true("body_truncated" %in% cut, label = paste(code, "cut row"))
    # The cut row names the skipped check in its words.
    phrase <- validation_cut_skips[cs_entry(code)]
    expect_false(is.na(phrase), label = paste(code, "in the registry"))
    expect_true(grepl(phrase, cs_cut_message(x), fixed = TRUE),
                label = paste(code, "named"))
  }
})

test_that("ROBO-mgwiemtw: the body_truncated message of a cut body", {
  x <- cs_validate(cs_fixtures$rule_slash_split, cut = TRUE)
  expect_identical(cs_cut_message(x), paste0(
    "Decoded body exceeded max_bytes (28); only its first 28 bytes up to ",
    "the last complete line were read. Lines past the cut could change ",
    "what these checks find, so they were not run: `User-agent: *` rules a ",
    "named group does not inherit; groups that could share one set of ",
    "rules; an empty Disallow beside a full block; a query parameter rule ",
    "that misses the parameter in a later position; a path whose bare and ",
    "slash forms get different decisions; a `$` rule the same path with a ",
    "query added escapes; an Allow that reopens a blocked path through a ",
    "query; a Disallow that blocks page resources such as scripts or ",
    "styles; a rule that also matches a longer path listed separately; ",
    "whether the file has no rules."
  ))
  expect_no_match(cs_cut_message(x), "validated", fixed = TRUE)
  # The sentence says what the validator did, not what an engine does.
  expect_no_match(cs_cut_message(x), "Google|Bing|Yandex")
})

# Every `if` in validate_document_bytes() whose condition reads
# body_truncated and whose branches add rows must read it through
# cut_runs(), so a check skipped on a cut body cannot go unnamed; each
# cut_runs() call names a registry entry, and each entry is asked once.
cs_walk <- function(expr, visit) {
  if (is.call(expr)) {
    visit(expr)
    parts <- as.list(expr)[-1L]
    for (i in seq_along(parts)) {
      if (is.call(parts[[i]])) cs_walk(parts[[i]], visit)
    }
  }
}

cs_without_cut_runs <- function(expr) {
  if (!is.call(expr)) {
    return(expr)
  }
  if (identical(expr[[1L]], as.name("cut_runs"))) {
    return(TRUE)
  }
  for (i in seq_along(expr)[-1L]) {
    if (is.call(expr[[i]])) expr[[i]] <- cs_without_cut_runs(expr[[i]])
  }
  expr
}

cs_guards <- function(fun) {
  out <- new.env()
  out$bare <- character()
  out$asked <- character()
  cs_walk(body(fun), function(call) {
    head <- call[[1L]]
    if (identical(head, as.name("cut_runs"))) {
      out$asked <- c(out$asked, as.character(call[[2L]]))
    }
    if (identical(head, as.name("if"))) {
      branches <- unlist(lapply(as.list(call)[-(1:2)], all.names))
      adds <- any(grepl("_diagnostics$", branches)) ||
        any(branches %in% c("add_diagnostic", "add_chunk"))
      rest <- all.names(cs_without_cut_runs(call[[2L]]))
      if (adds && "body_truncated" %in% rest) {
        out$bare <- c(out$bare, deparse1(call[[2L]]))
      }
    }
  })
  list(bare = out$bare, asked = out$asked)
}

test_that("ROBO-mgwiemtw: every cut-body skip goes through the registry", {
  found <- cs_guards(validate_document_bytes)
  expect_identical(found$bare, character())
  expect_identical(found$asked, names(validation_cut_skips))
  # The walk sees a bare guard.
  probe <- function() {
    if (!body_truncated) found <- slash_split_diagnostics(groups)
    if (cut_runs("rule_slash_split", body_truncated)) add_chunk(1L)
    if (body_truncated) final_newline <- NA
  }
  expect_identical(cs_guards(probe)$bare, "!body_truncated")
})

test_that("ROBO-mgwiemtw: a cut before any line break reads nothing", {
  body <- c(charToRaw("Disallow: /"), rep(charToRaw("x"), 30L))
  x <- cs_validate(body, cut = TRUE)
  expect_identical(x$document$line_count, 0L)
  expect_identical(x$diagnostics$code, "body_truncated")
  expect_match(cs_cut_message(x), "only its first 0 bytes", fixed = TRUE)
  expect_match(cs_cut_message(x), "whether the file has no rules",
               fixed = TRUE)
})

test_that("ROBO-mgwiemtw: NUL-hidden rules are still reported when cut", {
  text <- "User-agent: *\nDisallow: /x\n"
  body <- c(unlist(lapply(charToRaw(text), function(b) c(b, as.raw(0L)))),
            charToRaw("\n"))
  codes <- cs_validate(body, cut = TRUE)$diagnostics$code
  expect_true("rules_after_nul_removal" %in% codes)
  expect_false("no_rules" %in% codes)
  expect_identical(codes[length(codes)], "body_truncated")
})

test_that("ROBO-mgwiemtw: a cut compressed body keeps its own message", {
  body <- memCompress(charToRaw(strrep("User-agent: *\n", 20L)), "gzip")
  x <- cs_validate(body, cut = TRUE)
  expect_true("compressed_body" %in% x$diagnostics$code)
  expect_identical(cs_cut_message(x), sprintf(paste0(
    "Body exceeded max_bytes (%d); it was cut at the size limit and was not ",
    "read as rules by the validator."
  ), length(body)))
  expect_no_match(cs_cut_message(x), "were not run", fixed = TRUE)
})
