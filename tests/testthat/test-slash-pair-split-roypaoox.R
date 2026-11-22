# ROBO-roypaoox: a literal pattern `P` and `P/` of the same type for the same
# crawlers (`rule_slash_pair`), and a crawler whose decision differs between
# the bare URL `P` and the slash URL `P/` of a literal rule `P/`
# (`rule_slash_split`). Both are info rows. Every positive fixture is
# cross-checked on the Google, Bing and Yandex backends.

sp_diag <- function(body) {
  robots_validate_text(body)$diagnostics
}

sp_codes <- function(body) {
  sp_diag(body)$code
}

sp_pair <- "rule_slash_pair"
sp_split <- "rule_slash_split"

# The rows of one code.
sp_rows <- function(body, code) {
  d <- sp_diag(body)
  d[d$code == code, , drop = FALSE]
}

sp_redirect <- paste0(" A server redirect between the two URLs changes what ",
                      "a crawler reaches.")

sp_pair_message <- function(type, earlier, other, this) {
  bare <- if (endsWith(this, "/")) other else this
  slash <- if (endsWith(this, "/")) this else other
  # One earlier line as a number; several as the written list ("lines 2 and
  # 5"), which takes the plural noun and verb.
  lead <- if (is.character(earlier)) {
    sprintf("The %ss on %s have", type, earlier)
  } else {
    sprintf("The %s on line %d has", type, earlier)
  }
  sprintf(paste0(
    "%s '%s' and this one '%s': '%s' also matches every path '%s' matches, ",
    "and also '%s' itself and the paths that go on from it without a '/' ",
    "(RFC 9309 section 2.2.2)."
  ), lead, other, this, bare, slash, bare)
}

sp_blocked_message <- function(slash, bare, line) {
  sprintf(paste0("This Allow opens the URL '%s', but '%s' stays disallowed ",
                 "by line %d.%s"), slash, bare, line, sp_redirect)
}

sp_open_message <- function(line, slash, bare) {
  sprintf(paste0("The Disallow on line %d blocks the URL '%s', but '%s' ",
                 "stays allowed.%s"), line, slash, bare, sp_redirect)
}

sp_open_list <- function(listed) {
  paste0("These Disallows block the URL that ends in '/', but the URL ",
         "without it stays allowed: ", listed, ".", sp_redirect)
}

# Each fixture: a body (`%s` stands for the crawler token, so the backends
# can read it), the codes it gets and their lines. `today` is what it got
# before ROBO-roypaoox.
sp_fixtures <- list(
  pair = list(
    body = "User-agent: *\nDisallow: /notes/\nDisallow: /notes\n",
    today = character(0),
    codes = sp_pair, lines = 3L
  ),
  bare_blocked = list(
    body = "User-agent: %s\nDisallow: /\nAllow: /gallery/\n",
    today = character(0),
    codes = sp_split, lines = 3L
  ),
  bare_allowed = list(
    body = "User-agent: *\nDisallow: /notes/\n",
    today = character(0),
    codes = sp_split, lines = 1L
  ),
  seven = list(
    body = paste0("User-agent: *\n",
                  paste0("Disallow: /", letters[1:7], "/\n", collapse = "")),
    today = character(0),
    codes = sp_split, lines = 1L
  ),
  dollar_silences = list(
    body = paste0("User-agent: %s\nDisallow: /\nAllow: /gallery/\n",
                  "Allow: /gallery$\n"),
    today = character(0),
    codes = character(0), lines = integer(0)
  ),
  bare_silences = list(
    body = paste0("User-agent: %s\nDisallow: /\nAllow: /gallery/\n",
                  "Allow: /gallery\n"),
    today = character(0),
    codes = sp_pair, lines = 4L
  ),
  deeper = list(
    body = "User-agent: *\nDisallow: /x/\nAllow: /x/y\n",
    today = character(0),
    codes = sp_split, lines = 1L
  ),
  tie = list(
    body = "User-agent: *\nAllow: /x/\nDisallow: /x/\n",
    today = "disallow_tied_by_allow",
    codes = "disallow_tied_by_allow", lines = 3L
  ),
  across_crawlers = list(
    body = "User-agent: *\nDisallow: /x\n\nUser-agent: %s\nDisallow: /x/\n",
    today = "wildcard_disallows_not_inherited",
    codes = c("wildcard_disallows_not_inherited", sp_split),
    lines = c(4L, 4L)
  ),
  repeated_group = list(
    body = "User-agent: %s\nDisallow: /x/\n\nUser-agent: %s\nDisallow: /x\n",
    today = "user_agent_repeated_group",
    codes = c("user_agent_repeated_group", sp_pair), lines = c(4L, 5L)
  ),
  stacked = list(
    body = paste0("User-agent: %s\nUser-agent: Bar\nDisallow: /x/\n\n",
                  "User-agent: %s\nDisallow: /x\n"),
    today = "user_agent_repeated_group",
    codes = c("user_agent_repeated_group", sp_pair), lines = c(5L, 6L)
  ),
  cut_pair = list(
    body = paste0("User-agent: Foo web\nDisallow: /x\n\n",
                  "User-agent: Foo blog\nDisallow: /x/\n"),
    today = c("user_agent_cut", "user_agent_cut"),
    codes = c("user_agent_cut", "user_agent_cut"), lines = c(1L, 4L)
  ),
  cut_split_google = list(
    body = paste0("User-agent: Foo web\nDisallow: /\n\n",
                  "User-agent: Foo blog\nAllow: /x/\n"),
    today = c("user_agent_cut", "user_agent_cut"),
    codes = c("user_agent_cut", "user_agent_cut"), lines = c(1L, 4L)
  ),
  cut_split_uncut = list(
    body = paste0("User-agent: Foo web\nAllow: /x\n\n",
                  "User-agent: Foo blog\nDisallow: /\nAllow: /x/\n"),
    today = c("user_agent_cut", "user_agent_cut"),
    codes = c("user_agent_cut", "user_agent_cut"), lines = c(1L, 4L)
  ),
  same_value = list(
    body = paste0("User-agent: Foo web\nDisallow: /x\n\n",
                  "User-agent: foo web\nDisallow: /x/\n"),
    today = c("user_agent_cut", "user_agent_cut"),
    codes = c("user_agent_cut", "user_agent_cut", sp_pair),
    lines = c(1L, 4L, 5L)
  ),
  triple = list(
    body = "User-agent: *\nDisallow: /x/\nDisallow: /x\nDisallow: /x\n",
    today = "duplicate_rule",
    codes = c("duplicate_rule", sp_pair), lines = c(4L, 3L)
  ),
  pair_and_split = list(
    body = paste0("User-agent: %s\nDisallow: /\nDisallow: /x$\nAllow: /x\n",
                  "Allow: /x/\n"),
    today = character(0),
    codes = c(sp_pair, sp_split), lines = c(5L, 5L)
  ),
  star_key = list(
    body = "User-agent: *\nDisallow: /x*\nDisallow: /x/\n",
    today = character(0),
    codes = character(0), lines = integer(0)
  ),
  no_google_token = list(
    body = "User-agent: 1bot\nDisallow: /x/\nDisallow: /x\n",
    today = "user_agent_cut",
    codes = c("user_agent_cut", sp_pair), lines = c(1L, 3L)
  ),
  empty = list(
    body = "User-agent: *\nDisallow:\nAllow:\n",
    today = c("allow_all_disallow", "empty_rule_value"),
    codes = c("allow_all_disallow", "empty_rule_value"), lines = 2:3
  ),
  # Rules a literal head lookup must still find: the `/x/$` Google's
  # matcher adds for an Allow ending in `/index.html`, a `*`-led rule and a
  # `$`-anchored one each decide `/x/`.
  index_allow = list(
    body = "User-agent: %s\nAllow: /x/index.html\nDisallow: /x/\n",
    codes = character(0), lines = integer(0)
  ),
  star_led = list(
    body = "User-agent: %s\nDisallow: /x/\nAllow: */x/$\n",
    codes = character(0), lines = integer(0)
  ),
  dollar_head = list(
    body = "User-agent: %s\nDisallow: /x/\nAllow: /x/$\n",
    codes = character(0), lines = integer(0)
  ),
  dup_allow = list(
    body = "User-agent: %s\nDisallow: /\nAllow: /g/\nAllow: /g/\n",
    codes = c("duplicate_rule", sp_split), lines = c(4L, 3L)
  ),
  later_group_anchor = list(
    body = "User-agent: %s\nDisallow: /a\n\nUser-agent: %s\nDisallow: /b/\n",
    codes = c("user_agent_repeated_group", sp_split), lines = c(4L, 4L)
  ),
  two_groups_listed = list(
    body = "User-agent: %s\nDisallow: /b/\n\nUser-agent: %s\nDisallow: /a/\n",
    codes = c("user_agent_repeated_group", sp_split), lines = c(4L, 1L)
  ),
  two_crawlers = list(
    body = "User-agent: %s\nUser-agent: Bar\nDisallow: /notes/\n",
    codes = sp_split, lines = 1L
  )
)

sp_body <- function(name, token = "Foo") {
  gsub("%s", token, sp_fixtures[[name]]$body, fixed = TRUE)
}

sp_groups <- function(body) {
  validation_groups(as.data.frame(
    robotstxtr_validation_parse_(charToRaw(body)),
    stringsAsFactors = FALSE
  ))
}

# The bare-URL lines one reading gives the candidates in `at`.
sp_reading <- function(groups, at, key) {
  slash_split_reading(groups, at, key)$line
}

test_that("ROBO-roypaoox: each fixture's codes and lines", {
  for (name in names(sp_fixtures)) {
    d <- sp_diag(sp_body(name))
    expect_identical(d$code, sp_fixtures[[name]]$codes, label = name)
    expect_identical(d$line, sp_fixtures[[name]]$lines, label = name)
    # A line never gets the same text twice.
    expect_false(anyDuplicated(paste(d$line, d$message)) > 0L, label = name)
  }
})

test_that("ROBO-roypaoox: the new rows are all the change", {
  for (name in names(sp_fixtures)) {
    today <- sp_fixtures[[name]]$today
    if (is.null(today)) {
      next
    }
    codes <- sp_codes(sp_body(name))
    expect_identical(codes[!codes %in% c(sp_pair, sp_split)], today,
                     label = name)
  }
})

test_that("ROBO-roypaoox: a pair is one info row on the later line", {
  x <- robots_validate_text(sp_body("pair"))
  expect_identical(x$diagnostics$severity, "info")
  expect_identical(x$diagnostics$directive, "disallow")
  expect_identical(x$diagnostics$raw_text, "Disallow: /notes")
  expect_identical(x$diagnostics$message,
                   sp_pair_message("Disallow", 2L, "/notes/", "/notes"))
  expect_identical(x$documents$validation_status, "valid")
  # Calls neither line redundant.
  expect_false(grepl("redundant|no effect", x$diagnostics$message))
  # The later line may be the slash form; Allow pairs Allow.
  d <- sp_rows(sp_body("bare_silences"), sp_pair)
  expect_identical(d$directive, "allow")
  expect_identical(d$message,
                   sp_pair_message("Allow", 3L, "/gallery/", "/gallery"))
  d <- sp_rows(sp_body("same_value"), sp_pair)
  expect_identical(d$message, sp_pair_message("Disallow", 2L, "/x", "/x/"))
  # An Allow and a Disallow are no pair.
  expect_identical(
    sp_rows("User-agent: *\nDisallow: /x/\nAllow: /x\n", sp_pair)$line,
    integer(0)
  )
})

test_that("ROBO-roypaoox: a bare-blocked split is one row per Allow", {
  x <- robots_validate_text(sp_body("bare_blocked"))
  expect_identical(x$diagnostics$severity, "info")
  expect_identical(x$diagnostics$directive, "allow")
  expect_identical(x$diagnostics$raw_text, "Allow: /gallery/")
  expect_identical(x$diagnostics$message,
                   sp_blocked_message("/gallery/", "/gallery", 2L))
  d <- sp_rows(paste0("User-agent: Foo\nDisallow: /\nAllow: /a/\n",
                      "Allow: /b/\n"), sp_split)
  expect_identical(d$line, 3:4)
  expect_identical(d$message, c(sp_blocked_message("/a/", "/a", 2L),
                                sp_blocked_message("/b/", "/b", 2L)))
})

test_that("ROBO-roypaoox: bare-allowed splits are one row per group", {
  x <- robots_validate_text(sp_body("bare_allowed"))
  expect_identical(x$diagnostics$directive, "user-agent")
  expect_identical(x$diagnostics$raw_text, "User-agent: *")
  expect_identical(x$diagnostics$message,
                   sp_open_message(2L, "/notes/", "/notes"))
  d <- sp_rows(sp_body("seven"), sp_split)
  expect_identical(d$message, sp_open_list(paste0(
    "'/a/' (line 2), '/b/' (line 3), '/c/' (line 4), '/d/' (line 5), ",
    "'/e/' (line 6) and 2 more"
  )))
  # Five list without a count.
  d <- sp_rows(paste0("User-agent: *\n", paste0("Disallow: /", letters[1:5],
                                                 "/\n", collapse = "")),
               sp_split)
  expect_identical(d$message, sp_open_list(paste0(
    "'/a/' (line 2), '/b/' (line 3), '/c/' (line 4), '/d/' (line 5) and ",
    "'/e/' (line 6)"
  )))
  # A deeper override changes `/x/y`, not the two URLs, and the row never
  # speaks of children.
  d <- sp_rows(sp_body("deeper"), sp_split)
  expect_identical(d$message, sp_open_message(2L, "/x/", "/x"))
  expect_false(grepl("child", d$message, fixed = TRUE))
  # Groups naming the same crawler share one row, anchored on the group of
  # the earliest listed rule, which need not be the crawler's first group.
  d <- sp_rows(sp_body("two_groups_listed"), sp_split)
  expect_identical(d$message,
                   sp_open_list("'/b/' (line 2) and '/a/' (line 5)"))
  d <- sp_rows(sp_body("later_group_anchor"), sp_split)
  expect_identical(d$raw_text, "User-agent: Foo")
  expect_identical(d$message, sp_open_message(5L, "/b/", "/b"))
  # Each set of crawlers gets its own row.
  d <- sp_rows(paste0("User-agent: *\nDisallow: /a/\n\nUser-agent: Foo\n",
                      "Disallow: /b/\n\nUser-agent: *\nDisallow: /c/\n"),
               sp_split)
  expect_identical(d$line, c(1L, 4L))
  expect_identical(d$message,
                   c(sp_open_list("'/a/' (line 2) and '/c/' (line 8)"),
                     sp_open_message(5L, "/b/", "/b")))
})

test_that("ROBO-roypaoox: a group naming several crawlers names them", {
  note <- " This holds for every crawler the group names: 'Foo' and 'Bar'."
  d <- sp_rows(sp_body("two_crawlers"), sp_split)
  expect_identical(d$message,
                   paste0(sp_open_message(3L, "/notes/", "/notes"), note))
  d <- sp_diag(paste0("User-agent: Foo\nUser-agent: Bar\nDisallow: /\n",
                      "Allow: /g/\nAllow: /g\n"))
  expect_identical(d$code, sp_pair)
  expect_identical(d$message,
                   paste0(sp_pair_message("Allow", 4L, "/g/", "/g"), note))
  d <- sp_rows("User-agent: Foo\nUser-agent: Bar\nDisallow: /\nAllow: /g/\n",
               sp_split)
  expect_identical(d$message,
                   paste0(sp_blocked_message("/g/", "/g", 3L), note))
  # Case twins are one crawler: no note, as for a group naming one.
  d <- sp_rows(paste0("User-agent: Googlebot\nUser-agent: googlebot\n",
                      "Disallow: /x\nDisallow: /x/\n"), sp_pair)
  expect_identical(d$message, sp_pair_message("Disallow", 3L, "/x", "/x/"))
  d <- sp_rows(paste0("User-agent: Googlebot\nUser-agent: Bar\n",
                      "User-agent: googlebot\nDisallow: /n/\n"), sp_split)
  expect_identical(d$message, paste0(
    sp_open_message(4L, "/n/", "/n"),
    " This holds for every crawler the group names: 'Googlebot' and 'Bar'."
  ))
  # Five names at most, then a count; a name written twice counts once.
  agents <- paste0("User-agent: ", c("A", "B", "C", "D", "E", "F", "G", "A"),
                   "\n", collapse = "")
  d <- sp_rows(paste0(agents, "Disallow: /n/\n"), sp_split)
  expect_identical(d$message, paste0(
    sp_open_message(9L, "/n/", "/n"),
    " This holds for every crawler the group names: 'A', 'B', 'C', 'D', ",
    "'E' and 2 more."
  ))
})

test_that("ROBO-roypaoox: the AI-training policy token gets no row", {
  # It states a training preference, not crawl access (ROBO-kzyfejcv).
  expect_identical(
    sp_codes("User-agent: __usage_ai-training\nDisallow: /kit/\n"),
    "ai_training_preference"
  )
  expect_identical(
    sp_codes(paste0("User-agent: __usage_ai-training\nDisallow: /\n",
                    "Allow: /kit/\nAllow: /kit\n")),
    "ai_training_preference"
  )
  # Left out on Google's key: a versioned token line is read as the token,
  # so it is left out too, though its whole value is another.
  expect_identical(
    sp_codes(paste0("User-agent: __usage_ai-training/1.0\nDisallow: /x/\n",
                    "Disallow: /x\n")),
    c("user_agent_cut", "ai_training_token_near_miss")
  )
  # A group row is anchored on the first User-agent line the check reads,
  # not on a token line before it.
  for (token in c("__usage_ai-training", "__usage_ai-training/1.0")) {
    body <- sprintf("User-agent: %s\nUser-agent: Googlebot\nDisallow: /x/\n",
                    token)
    d <- sp_rows(body, sp_split)
    expect_identical(d$line, 2L, label = token)
    expect_identical(d$raw_text, "User-agent: Googlebot", label = token)
    expect_identical(d$message, sp_open_message(3L, "/x/", "/x"),
                     label = token)
  }
  # A crawler's own group beside it keeps its rows.
  d <- sp_diag(paste0("User-agent: __usage_ai-training\nDisallow: /kit/\n\n",
                      "User-agent: Foo\nDisallow: /kit/\n"))
  expect_identical(d$code[d$code == sp_split], sp_split)
  expect_identical(d$line[d$code == sp_split], 4L)
})

test_that("ROBO-roypaoox: rows come in line order, empties stay out", {
  # The group row on line 1 comes before the Allow row on line 3.
  d <- sp_rows("User-agent: *\nDisallow: /a\nAllow: /a/b/\nDisallow: /c/\n",
               sp_split)
  expect_identical(d$line, c(1L, 3L))
  expect_identical(d$message, c(sp_open_message(4L, "/c/", "/c"),
                                sp_blocked_message("/a/b/", "/a/b", 2L)))
  # An empty Disallow decides nothing: `B`'s bare URL is allowed by no rule,
  # as `A`'s is, so the two classes agree.
  d <- sp_rows(paste0("User-agent: A\nUser-agent: B\nDisallow: /x/\n\n",
                      "User-agent: B\nDisallow:\n"), sp_split)
  expect_identical(d$line, 1L)
  # An empty User-agent line names no crawler, so it is not counted.
  d <- sp_rows("User-agent:\nUser-agent: Foo\nDisallow: /n/\n", sp_split)
  expect_identical(d$message, sp_open_message(3L, "/n/", "/n"))
})

test_that("ROBO-roypaoox: a line with a pair and a split row", {
  d <- sp_diag(sp_body("pair_and_split"))
  expect_identical(d$message, c(
    sp_pair_message("Allow", 4L, "/x", "/x/"),
    sp_blocked_message("/x/", "/x", 3L)
  ))
  expect_false(identical(d$message[[1L]], d$message[[2L]]))
})

test_that("ROBO-roypaoox: only the first line of a type and value is read", {
  d <- sp_diag(sp_body("triple"))
  expect_identical(d$message[d$code == sp_pair],
                   sp_pair_message("Disallow", 2L, "/x/", "/x"))
  d <- sp_diag(sp_body("dup_allow"))
  expect_identical(d$message[d$code == sp_split],
                   sp_blocked_message("/g/", "/g", 2L))
  d <- sp_rows("User-agent: *\nDisallow: /x/\nDisallow: /x/\n", sp_split)
  expect_identical(d$message, sp_open_message(2L, "/x/", "/x"))
  # Each class has the other form on its own line: both are named.
  d <- sp_rows(paste0("User-agent: A\nDisallow: /x\n\nUser-agent: B\n",
                      "Disallow: /x\n\nUser-agent: A\nUser-agent: B\n",
                      "Disallow: /x/\n"), sp_pair)
  expect_identical(d$line, 9L)
  expect_identical(d$message, paste0(
    sp_pair_message("Disallow", "lines 2 and 5", "/x", "/x/"),
    " This holds for every crawler the group names: 'A' and 'B'."
  ))
  # Six classes, each with its own `/x`: five lines, then a count, never a
  # range of lines.
  k <- 1:6
  body <- paste0(paste0("User-agent: c", k, "\nDisallow: /x\nDisallow: /f", k,
                        "\n", collapse = ""),
                 paste0("User-agent: c", k, "\n", collapse = ""),
                 "Disallow: /x/\n")
  d <- sp_rows(body, sp_pair)
  expect_identical(d$line, 25L)
  expect_identical(d$message, paste0(
    sp_pair_message("Disallow", "lines 2, 5, 8, 11, 14 and 1 more", "/x",
                    "/x/"),
    " This holds for every crawler the group names: 'c1', 'c2', 'c3', ",
    "'c4', 'c5' and 1 more."
  ))
  expect_false(grepl("rules)", d$message, fixed = TRUE))
  expect_identical(slash_pair_lead("allow", c(2L, 5L)),
                   "The Allows on lines 2 and 5 have")
  expect_identical(slash_pair_lead("disallow", 7L),
                   "The Disallow on line 7 has")
  # Two classes with the other form on the same line name it once.
  d <- sp_rows(paste0("User-agent: a\nUser-agent: b\nDisallow: /x\n\n",
                      "User-agent: a\nDisallow: /y\n\n",
                      "User-agent: a\nUser-agent: b\nDisallow: /x/\n"), sp_pair)
  expect_identical(d$line, 10L)
  expect_identical(d$message, paste0(
    sp_pair_message("Disallow", 3L, "/x", "/x/"),
    " This holds for every crawler the group names: 'a' and 'b'."
  ))
  # The pair names the earliest line of the other form.
  d <- sp_rows(paste0("User-agent: *\nDisallow: /x\nDisallow: /x\n",
                      "Disallow: /x/\n"), sp_pair)
  expect_identical(d$line, 4L)
  expect_identical(d$message, sp_pair_message("Disallow", 2L, "/x", "/x/"))
})

test_that("ROBO-roypaoox: every crawler class the group names must agree", {
  # `Bar` alone gets the bare-allowed split on line 3; `Foo` also has
  # `Disallow: /x`, so it does not: no split row.
  expect_identical(sp_rows(sp_body("stacked"), sp_split)$line, integer(0))
  d <- sp_rows(sp_body("stacked"), sp_pair)
  expect_identical(d$message, sp_pair_message("Disallow", 3L, "/x/", "/x"))
  # One class of the group has the pair, the other not: no row.
  expect_identical(
    sp_codes(paste0("User-agent: A\nDisallow: /x/\n\nUser-agent: A\n",
                    "User-agent: B\nDisallow: /x\n")),
    "user_agent_repeated_group"
  )
  # One class splits, the other has `/x/` decided by its own `Allow: /x/$`:
  # the same bare decision, no row.
  expect_identical(
    sp_codes(paste0("User-agent: A\nUser-agent: B\nDisallow: /x/\n\n",
                    "User-agent: B\nAllow: /x/$\n")),
    "user_agent_repeated_group"
  )
  # Both classes split, but different lines block `/x`: no row, as the
  # message names one line.
  expect_identical(
    sp_codes(paste0("User-agent: A\nUser-agent: B\nDisallow: /\n",
                    "Allow: /x/\n\nUser-agent: B\nDisallow: /x\n")),
    "user_agent_repeated_group"
  )
  # `*` never merges into a named crawler: no pair across them.
  expect_identical(sp_rows(sp_body("across_crawlers"), sp_pair)$line,
                   integer(0))
  expect_identical(sp_rows(sp_body("across_crawlers"), sp_split)$message,
                   sp_open_message(5L, "/x/", "/x"))
  # A pair split across two crawlers' groups is no pair.
  expect_identical(
    sp_codes("User-agent: A\nDisallow: /x\n\nUser-agent: B\nDisallow: /x\n"),
    character(0)
  )
  expect_identical(
    sp_rows("User-agent: A\nDisallow: /x\n\nUser-agent: B\nDisallow: /x/\n",
            sp_pair)$line,
    integer(0)
  )
})

# Google's matcher cuts `Foo web` and `Foo blog` to `Foo` and merges their
# groups; a matcher that compares the whole value keeps them apart. A row
# needs both readings: the pair on the whole value, the split on both.
test_that("ROBO-roypaoox: a row needs the whole-value merge too", {
  expect_identical(sp_rows(sp_body("cut_pair"), sp_pair)$line, integer(0))
  expect_identical(sp_rows(sp_body("cut_split_google"), sp_split)$line,
                   integer(0))
  expect_identical(sp_rows(sp_body("cut_split_uncut"), sp_split)$line,
                   integer(0))
  # The merges as the helper reads them: the whole-value merge splits
  # `cut_split_uncut` and not `cut_split_google`; Google's merge the reverse.
  groups <- sp_groups(sp_body("cut_split_uncut"))
  at <- 3L
  expect_identical(sp_reading(groups, at, groups$agents$uncut), 5L)
  expect_identical(sp_reading(groups, at, groups$agents$key),
                   NA_integer_)
  groups <- sp_groups(sp_body("cut_split_google"))
  at <- 2L
  expect_identical(sp_reading(groups, at, groups$agents$uncut),
                   NA_integer_)
  expect_identical(sp_reading(groups, at, groups$agents$key), 2L)
  # Both readings split, but a different line blocks `/x`: line 5 on the
  # whole value, line 2 on Google's merge. No row.
  body <- paste0("User-agent: Foo web\nDisallow: /x\n\n",
                 "User-agent: Foo blog\nDisallow: /\nAllow: /x/\n")
  groups <- sp_groups(body)
  expect_identical(sp_reading(groups, 3L, groups$agents$uncut), 5L)
  expect_identical(sp_reading(groups, 3L, groups$agents$key), 2L)
  expect_identical(sp_rows(body, sp_split)$line, integer(0))
  # The same whole value, in another ASCII case, merges on both readings.
  expect_identical(sp_rows(sp_body("same_value"), sp_pair)$line, 5L)
  d <- sp_rows(paste0("User-agent: Foo web\nDisallow: /\n\n",
                      "User-agent: foo web\nAllow: /x/\n"), sp_split)
  expect_identical(d$message, sp_blocked_message("/x/", "/x", 2L))
  # A group Google's matcher reads for no crawler (`1bot`) has a class on
  # the whole value, so the pair is reported; the split needs Google's
  # reading too and is not.
  expect_identical(sp_rows(sp_body("no_google_token"), sp_pair)$line, 3L)
  expect_identical(
    sp_rows("User-agent: 1bot\nDisallow: /\nAllow: /x/\n", sp_split)$line,
    integer(0)
  )
})

# Values that are no candidate, alone and as an Allow under `Disallow: /`,
# with the codes each gets.
sp_misses <- list(
  "/x$" = list(character(0), character(0)),
  "/x*" = list(character(0), character(0)),
  "/a*b/" = list(character(0), character(0)),
  "/" = list(character(0), "disallow_tied_by_allow"),
  "/x?y/" = list(character(0), character(0)),
  "/%41/" = list("rule_escaped_unreserved", "rule_escaped_unreserved"),
  "/a/./" = list("rule_dot_segment", "rule_dot_segment"),
  "/a/." = list(character(0), character(0)),
  "/a%2f/" = list("rule_lowercase_escape", "rule_lowercase_escape"),
  "/x//" = list(character(0), character(0))
)

test_that("ROBO-roypaoox: the shapes that are no candidate", {
  for (value in names(sp_misses)) {
    expect_identical(
      sp_codes(paste0("User-agent: *\nDisallow: ", value, "\n")),
      sp_misses[[value]][[1L]], label = value
    )
    expect_identical(
      sp_codes(paste0("User-agent: *\nDisallow: /\nAllow: ", value, "\n")),
      sp_misses[[value]][[2L]], label = value
    )
  }
})

test_that("ROBO-roypaoox: the scan makes each exclusion", {
  misses <- c("/a*b/", "/a*b", "/x$/", "/x$", "/x?y/", "/x?y", "/%41/",
              "/%41", "/x//", "/a/./", "/a/../", "/a/.", "/a/..", "/./",
              "/a b/", "/a b", "x/", "x", "/")
  groups <- sp_groups(paste0("User-agent: *\n",
                             paste0("Disallow: ", misses, "\n",
                                    collapse = ""), "Allow:\n"))
  expect_identical(groups$rules$value[-length(misses) - 1L], misses)
  expect_identical(slash_candidates(groups$rules), integer(0))
  hits <- c("/x/", "/x", "/a.b/", "/a/.b/", "/a/..b", "/a-b_c~d/", "/a;b=c/",
            "/x/y")
  groups <- sp_groups(paste0("User-agent: *\n",
                             paste0("Disallow: ", hits, "\n", collapse = "")))
  expect_identical(slash_candidates(groups$rules), seq_along(hits))
  expect_identical(slash_partner(c("/x/", "/x", "/a/b/")),
                   c("/x", "/x/", "/a/b"))
  # Only a value ending in `/` is a split candidate: `/x` decides `/x` and
  # `Allow: /*/` opens `/x/`, which is no split of `/x`'s.
  expect_identical(sp_codes("User-agent: *\nDisallow: /x\nAllow: /*/\n"),
                   character(0))
  # Each miss, beside its other form or under `Disallow: /`, draws no row.
  for (value in misses[-length(misses)]) {
    for (body in c(sprintf("User-agent: *\nDisallow: %s\nDisallow: %s/\n",
                           value, value),
                   sprintf("User-agent: *\nDisallow: /\nAllow: %s\n",
                           value))) {
      codes <- sp_codes(body)
      expect_false(any(codes %in% c(sp_pair, sp_split)), label = body)
    }
  }
})

test_that("ROBO-roypaoox: edge inputs", {
  # A NUL cuts the second value to `/x/` on Google's reading, so the pair is
  # Google's only, and the message says so. Not testable on Bing and Yandex:
  # they read the value `/x/` with the NUL and `zz`, which is another rule.
  body <- c(charToRaw("User-agent: *\nDisallow: /x\nDisallow: /x/"),
            as.raw(0), charToRaw("zz\n"))
  d <- sp_diag(body)
  expect_identical(d$code, c("nul_byte", "rule_cut_by_nul", sp_pair))
  expect_identical(d$message[[3L]], paste0(
    sp_pair_message("Disallow", 2L, "/x", "/x/"),
    " This is Google's reading, which ends each line at its first NUL; ",
    "Bing and Yandex read the NUL as an ordinary byte."
  ))
  # A split row in a body with a NUL carries the same sentence.
  body <- c(charToRaw("User-agent: *\nDisallow: /a"), as.raw(0),
            charToRaw("zz\nDisallow: /notes/\n"))
  d <- sp_diag(body)
  expect_identical(d$code, c("nul_byte", "rule_cut_by_nul", sp_split))
  expect_identical(d$message[[3L]], paste0(
    sp_open_message(3L, "/notes/", "/notes"),
    " This is Google's reading, which ends each line at its first NUL; ",
    "Bing and Yandex read the NUL as an ordinary byte."
  ))
  # A latin1 byte and a lone UTF-8 lead byte are escaped in the canonical
  # value, which then holds `%`: no candidate, no row and no error.
  for (byte in as.raw(c(0xe9, 0xc3))) {
    body <- c(charToRaw("User-agent: *\nDisallow: /"), byte,
              charToRaw("/\nDisallow: /"), byte, charToRaw("\n"))
    expect_identical(sp_codes(body), c("invalid_utf8", "invalid_utf8"))
  }
  # Rules before any User-agent and under an empty User-agent line belong
  # to no crawler.
  expect_identical(sp_codes("Disallow: /x/\nDisallow: /x\n"),
                   c("rule_without_user_agent", "rule_without_user_agent",
                     "missing_user_agent"))
  expect_false(any(sp_codes("User-agent:\nDisallow: /x/\nDisallow: /x\n") %in%
                     c(sp_pair, sp_split)))
  # No candidate: both checks return empty frames before any expander.
  local({
    local_mocked_bindings(validation_token_expander = function(...) {
      stop("expander built")
    })
    groups <- sp_groups("User-agent: *\nDisallow: /x*\n")
    for (found in list(slash_pair_diagnostics(groups),
                       slash_split_diagnostics(groups))) {
      expect_identical(nrow(found), 0L)
      expect_named(found, c("line", "type", "message", "directive"))
    }
  })
  expect_identical(nrow(slash_split_diagnostics(sp_groups(
    "User-agent: *\nDisallow: /x\n"
  ))), 0L)
})

test_that("ROBO-roypaoox: a body cut at max_bytes gets the pair, no split", {
  text <- paste0("User-agent: *\nDisallow: /a/\nDisallow: /a\n",
                 "Disallow: /b/\nDisallow: /later-", strrep("x", 200L), "\n")
  body <- charToRaw(text)[seq_len(60L)]
  x <- validate_document_bytes(body, "s", "supplied", max_bytes = 60L,
                               body_truncated = TRUE)
  expect_identical(x$diagnostics$code, c(sp_pair, "body_truncated"))
  expect_identical(x$diagnostics$line[[1L]], 3L)
  # The same bytes, not marked cut, get the split too.
  x <- validate_document_bytes(body, "s", "supplied")
  expect_identical(x$diagnostics$code,
                   c("malformed_line", sp_pair, sp_split))
  expect_identical(x$diagnostics$message[[3L]],
                   sp_open_message(4L, "/b/", "/b"))
})

test_that("ROBO-roypaoox: a rule written at the line buffer still splits", {
  # `Allow:` and no space: the line fills Google's line buffer, so a witness
  # line that added a space would lose the rule's last byte.
  body <- sprintf("User-agent: Foo\nDisallow: /\nAllow:/%s/\n",
                  strrep("a", 16655L))
  d <- sp_rows(body, sp_split)
  expect_identical(d$line, 3L)
  expect_identical(d$directive, "allow")
})

test_that("ROBO-roypaoox: a witness line keeps the key as written", {
  # Google reads the typo `disalow` as Disallow. Written `Disallow`, the
  # witness line would be a byte longer and lose the value's last `/` at
  # the line buffer.
  p <- paste0("/", strrep("a", 16653L), "/")
  bare <- substr(p, 1L, nchar(p) - 1L)
  shown <- paste0("/", strrep("a", 35L), "...")
  d <- sp_rows(paste0("User-agent: *\ndisalow:", p, "\n"), sp_split)
  expect_identical(d$line, 1L)
  expect_identical(d$message, sp_open_message(2L, paste0(shown, "/"), shown))
  # A typo line the witness would cut otherwise: its `z` is kept, so it does
  # not match the bare URL, and line 2 blocks it.
  body <- paste0("User-agent: *\nDisallow: /\ndisalow:", bare, "z\nAllow:/",
                 strrep("a", 16653L), "/\n")
  d <- sp_rows(body, sp_split)
  expect_identical(d$line, 4L)
  expect_identical(d$message,
                   sp_blocked_message(paste0(shown, "/"), shown, 2L))
  expect_identical(
    slash_written_keys(lapply(c("disalow:/x", "  ALLOW : /y", "Allow /z",
                                "\tDisallow:"), charToRaw)),
    c("disalow", "ALLOW", "Allow", "Disallow")
  )
})

test_that("ROBO-roypaoox: long values are elided in the message", {
  long <- paste0("/", strrep("a", 8000L))
  d <- sp_diag(paste0("User-agent: *\nDisallow: ", long, "/\nDisallow: ",
                      long, "\n"))
  expect_identical(d$code, sp_pair)
  # The bare form is elided, and the slash form is the same text with its
  # `/` kept, so the two stay apart.
  shown <- paste0("/", strrep("a", 35L), "...")
  expect_identical(d$message,
                   sp_pair_message("Disallow", 2L, paste0(shown, "/"), shown))
  expect_lt(nchar(d$message), 400L)
  d <- sp_diag(paste0("User-agent: *\nDisallow: /\nAllow: ", long, "/\n"))
  expect_identical(d$message,
                   sp_blocked_message(paste0(shown, "/"), shown, 2L))
  d <- sp_diag(paste0("User-agent: *\nDisallow: ", long, "/\n"))
  expect_identical(d$message, sp_open_message(2L, paste0(shown, "/"), shown))
  d <- sp_diag(paste0("User-agent: *\nDisallow: ", long, "/\nDisallow: /b/\n"))
  expect_identical(d$message, sp_open_list(sprintf(
    "'%s/' (line 2) and '/b/' (line 3)", shown
  )))
})

# The crossing check: how each backend decides the bare and the slash URL.
# Default `url_normalization` ("rfc3986"): the paths hold no dot segment,
# `%`, `?` or `#`, so it changes no byte.
sp_engines <- list(google = "Googlebot", bing = "bingbot", yandex = "Yandex")

sp_decide <- function(body, paths, backend) {
  token <- sp_engines[[backend]]
  robots_evaluate_text_v1(
    gsub("%s", token, body, fixed = TRUE),
    paste0("https://example.com", paths), token, backend, backend
  )$results$url_decision
}

# Fixture, the paths and the decisions every backend gives them, with any
# backend that decides otherwise.
sp_decisions <- list(
  list("bare_blocked", c("/gallery", "/gallery/"), c("disallow", "allow")),
  list("bare_allowed", c("/notes", "/notes/"), c("allow", "disallow")),
  list("seven", c("/g", "/g/"), c("allow", "disallow")),
  list("deeper", c("/x", "/x/", "/x/y"), c("allow", "disallow", "allow")),
  list("across_crawlers", c("/x", "/x/"), c("allow", "disallow")),
  # A backend disagreement: the package's Yandex matcher lets `Allow: /x`
  # win over `Disallow: /x$` for the URL `/x`, where Google and Bing take
  # the longer `/x$`. The check decides on Google's matcher.
  list("pair_and_split", c("/x", "/x/"), c("disallow", "allow"),
       list(yandex = c("allow", "allow"))),
  list("dollar_silences", c("/gallery", "/gallery/"), c("allow", "allow")),
  list("bare_silences", c("/gallery", "/gallery/"), c("allow", "allow")),
  list("tie", c("/x", "/x/"), c("allow", "allow")),
  list("pair", c("/notes", "/notes/"), c("disallow", "disallow")),
  list("dup_allow", c("/g", "/g/"), c("disallow", "allow")),
  list("later_group_anchor", c("/a", "/b", "/b/"),
       c("disallow", "allow", "disallow")),
  list("two_groups_listed", c("/a", "/a/", "/b", "/b/"),
       c("allow", "disallow", "allow", "disallow")),
  list("two_crawlers", c("/notes", "/notes/"), c("allow", "disallow")),
  list("star_led", c("/x", "/x/"), c("allow", "allow")),
  list("dollar_head", c("/x", "/x/"), c("allow", "allow")),
  # Google's matcher reads `Allow: /x/index.html` as also `Allow: /x/$`, so
  # `/x/` is allowed there; the package's Bing and Yandex matchers do not.
  list("index_allow", c("/x", "/x/"), c("allow", "allow"),
       list(bing = c("allow", "disallow"), yandex = c("allow", "disallow")))
)

test_that("ROBO-roypaoox: every backend decides the bare and slash URLs", {
  for (backend in names(sp_engines)) {
    for (case in sp_decisions) {
      expected <- case[[3L]]
      if (length(case) > 3L && !is.null(case[[4L]][[backend]])) {
        expected <- case[[4L]][[backend]]
      }
      expect_identical(sp_decide(sp_fixtures[[case[[1L]]]]$body, case[[2L]],
                                 backend),
                       expected, label = paste(backend, case[[1L]]))
    }
  }
})

# What the pair row says: the bare pattern matches every path the slash
# pattern matches, and also the bare URL and paths that go on without `/`,
# which the slash pattern does not.
test_that("ROBO-roypaoox: the bare pattern covers the slash pattern", {
  paths <- c("/notes", "/notesx", "/notes/", "/notes/a")
  for (backend in names(sp_engines)) {
    expect_identical(
      sp_decide("User-agent: *\nDisallow: /notes\n", paths, backend),
      rep("disallow", 4L), label = backend
    )
    expect_identical(
      sp_decide("User-agent: *\nDisallow: /notes/\n", paths, backend),
      c("allow", "allow", "disallow", "disallow"), label = backend
    )
    expect_identical(
      sp_decide("User-agent: *\nDisallow: /\nAllow: /notes\n", paths,
                backend),
      rep("allow", 4L), label = backend
    )
  }
})

# The split's decisions are Google's matcher's on the class's rules a
# literal head lookup keeps: the same as on all of them.
test_that("ROBO-roypaoox: the kept rules decide as all of them", {
  # A `%` is literal to Google's matcher, so a rule holding one never
  # matches a candidate path, which holds none: such a rule stays out.
  read <- wildcard_witness_decide(
    "User-agent: witness\nDisallow: /%41/\nDisallow: /a%20b/\n", c(1L, 1L),
    c("/A/", "/a b/")
  )
  expect_identical(read$allowed, c(TRUE, TRUE))
  read <- wildcard_witness_decide(
    c("User-agent: witness\nDisallow: /%41/\n",
      "User-agent: witness\nDisallow: /a%20b/\n"), 1:2, c("/%41/", "/a%20b/")
  )
  expect_identical(read$allowed, c(FALSE, FALSE))
  for (name in c("index_allow", "star_led", "dollar_head", "deeper",
                 "pair_and_split", "bare_blocked")) {
    groups <- sp_groups(sp_body(name))
    rules <- groups$rules
    at <- which(endsWith(rules$value, "/"))
    whole <- wildcard_witness_decide(
      wildcard_witness_body(rules, rep(TRUE, nrow(rules))), c(1L, 1L),
      c(slash_partner(rules$value[at[[1L]]]), rules$value[at[[1L]]])
    )
    live <- which(!rules$empty)
    pairs <- validation_token_expander(groups)(rules$group[live])
    held <- list(rule = live[pairs$owner], class = pairs$class)
    body <- slash_split_bodies(rules, held, rules$value[at[[1L]]], 1L)
    kept <- wildcard_witness_decide(
      body$bodies, c(1L, 1L),
      c(slash_partner(rules$value[at[[1L]]]), rules$value[at[[1L]]])
    )
    expect_identical(kept$allowed, whole$allowed, label = name)
    # Body lines map back to the same file lines.
    to_file <- function(read, rows) {
      ifelse(read$line > 1L, rules$line[rows[pmax(read$line - 1L, 1L)]], 0L)
    }
    expect_identical(to_file(kept, body$rule),
                     to_file(whole, seq_len(nrow(rules))), label = name)
  }
})

# Best of five runs, so a loaded machine cannot fail the ratio
# (test-cut-note-zqyqbudf.R).
sp_best <- function(expr_fn) {
  min(vapply(1:5, function(i) system.time(expr_fn())[["elapsed"]], 0))
}

# `n` rules in one `*` group: bare-allowed candidates and pairs, which run
# the scan, both merges' readings (a cut value adds Google's) and the rows.
sp_rules <- function(n) {
  k <- seq_len(n %/% 4L)
  paste0(
    "User-agent: *\n",
    paste0("Disallow: /d", k, "/\nDisallow: /e", k, "/\n",
           "Disallow: /p", k, "/\nDisallow: /p", k, "\n", collapse = ""),
    "\nUser-agent: Foo web\nDisallow: /\nAllow: /g/\n"
  )
}

sp_time_check <- function(body, times = 10L) {
  groups <- sp_groups(body)
  sp_best(function() {
    for (k in seq_len(times)) {
      slash_pair_diagnostics(groups)
      slash_split_diagnostics(groups)
    }
  })
}

test_that("ROBO-roypaoox: the checks are linear in the rules (ROBO-dbvmxcfw)", {
  skip_on_cran()
  groups <- sp_groups(sp_rules(1000L))
  expect_identical(nrow(slash_pair_diagnostics(groups)), 250L)
  expect_identical(nrow(slash_split_diagnostics(groups)), 2L)
  small <- sp_time_check(sp_rules(1000L), 2L)
  large <- sp_time_check(sp_rules(4000L), 2L)
  expect_lt(large, 8 * max(small, 0.05))
  # The whole validator too.
  small <- sp_best(function() robots_validate_text(sp_rules(500L)))
  large <- sp_best(function() robots_validate_text(sp_rules(2000L)))
  expect_lt(large, 8 * max(small, 0.05))
})

# `n` literal candidates beside `n` wildcard rules whose head is cut to `/`
# by an early `*`: a rule like `/*?fN=` or `/*/fN/` must not join every
# candidate's witness body.
sp_wild <- function(n) {
  k <- seq_len(n)
  paste0("User-agent: *\n",
         paste0("Disallow: /c", k, "/\n", collapse = ""),
         paste0("Disallow: /*?f", k, "=\n", collapse = ""),
         paste0("Disallow: /*/f", k, "/\n", collapse = ""))
}

test_that("ROBO-roypaoox: the split is linear beside wildcard rules", {
  skip_on_cran()
  groups <- sp_groups(sp_wild(250L))
  expect_identical(nrow(slash_split_diagnostics(groups)), 1L)
  small <- sp_time_check(sp_wild(250L), 2L)
  large <- sp_time_check(sp_wild(1000L), 2L)
  expect_lt(large, 8 * max(small, 0.05))
})

# Shapes where the witness reads alone would grow faster than the input:
# rules whose later fragment shares its first bytes with every candidate
# (`gram`, `locale`), and one group naming `n` crawlers that each have a
# group of their own, so every candidate is read once per class (`classes`).
sp_shape <- function(shape, n) {
  k <- seq_len(n)
  switch(
    shape,
    gram = paste0("User-agent: *\n",
                  paste0("Disallow: /page", k, "/\n", collapse = ""),
                  paste0("Disallow: /*page", k, "-print\n", collapse = "")),
    locale = paste0("User-agent: *\n",
                    paste0("Disallow: /c", k, "/\n", collapse = ""),
                    paste0("Disallow: /*/c", k, "/\n", collapse = "")),
    classes = paste0(paste0("User-agent: bot", k, "\n", collapse = ""),
                     paste0("Disallow: /d", k, "/\nDisallow: /d", k, "\n",
                            collapse = ""), "\n",
                     paste0("User-agent: bot", k, "\nDisallow: /z", k, "\n",
                            collapse = "\n"))
  )
}

test_that("ROBO-roypaoox: candidates past the work budget get no row", {
  # Each Allow is one (candidate, class) read, the first also pays once for
  # its class's three rules, and each has a two-line witness body
  # (`Disallow: /` and itself): 4 and 1 to plan, then 2 and 2 to read.
  # Candidates are read in line order.
  groups <- sp_groups("User-agent: Foo\nDisallow: /\nAllow: /a/\nAllow: /b/\n")
  expect_identical(slash_split_diagnostics(groups)$line, 3:4)
  expect_identical(slash_split_diagnostics(groups, budget = 9)$line, 3:4)
  expect_identical(slash_split_diagnostics(groups, budget = 8)$line, 3L)
  expect_identical(slash_split_diagnostics(groups, budget = 7)$line, 3L)
  expect_identical(slash_split_diagnostics(groups, budget = 3)$line,
                   integer(0))
  # A cut value makes two readings, and they share the budget: each costs 3
  # to plan and 2 to read, so 10 reads both and 9 leaves the second short.
  groups <- sp_groups("User-agent: Foo web\nDisallow: /\nAllow: /a/\n")
  expect_identical(slash_split_diagnostics(groups, budget = 10)$line, 3L)
  expect_identical(slash_split_diagnostics(groups, budget = 9)$line,
                   integer(0))
  # The pair check reads one row per candidate.
  groups <- sp_groups(paste0("User-agent: *\nDisallow: /a\nDisallow: /a/\n",
                             "Disallow: /b\nDisallow: /b/\n"))
  expect_identical(slash_pair_diagnostics(groups)$line, c(3L, 5L))
  expect_identical(slash_pair_diagnostics(groups, budget = 4)$line,
                   c(3L, 5L))
  expect_identical(slash_pair_diagnostics(groups, budget = 3)$line, 3L)
  # The default: 32 units per rule and per candidate, plus 20,000.
  expect_identical(slash_budget(groups$rules, 1:4), 32 * 8 + 20000)
})

# The counts a check that stopped hands out, as slash_stop() builds them.
sp_stopped <- function(found, checked, value) {
  list(found = found, checked = checked, skipped = found - checked,
       value = value)
}

test_that("ROBO-roypaoox: a check that stops says so, with its counts", {
  groups <- sp_groups("User-agent: Foo\nDisallow: /\nAllow: /a/\nAllow: /b/\n")
  expect_null(attr(slash_split_diagnostics(groups), "stopped"))
  expect_null(attr(slash_split_diagnostics(groups, budget = 9), "stopped"))
  stop <- attr(slash_split_diagnostics(groups, budget = 8), "stopped")
  expect_identical(stop, sp_stopped(2L, 1L, "/b/"))
  # One skipped: singular forms.
  expect_identical(slash_stop_message("split", stop), paste0(
    "This file has 2 rules whose path ends in '/', such as '/b/'. For each ",
    "one, the validator checks whether crawlers treat '/b' and '/b/' ",
    "differently. This file is too large to check them all quickly, so only ",
    "the first was checked, in line order. The other 1 was skipped, and it ",
    "may have the same problem."
  ))
  stop <- attr(slash_split_diagnostics(groups, budget = 3), "stopped")
  expect_identical(stop, sp_stopped(2L, 0L, "/a/"))
  expect_identical(slash_stop_message("split", stop), paste0(
    "This file has 2 rules whose path ends in '/', such as '/a/'. For each ",
    "one, the validator checks whether crawlers treat '/a' and '/a/' ",
    "differently. This file is too large to check them all quickly, so none ",
    "of them were checked. All 2 were skipped, and some of them may have ",
    "the same problem."
  ))
  # A single rule, none checked.
  one <- sp_groups("User-agent: Foo\nDisallow: /a/\n")
  stop <- attr(slash_split_diagnostics(one, budget = 0), "stopped")
  expect_identical(stop, sp_stopped(1L, 0L, "/a/"))
  expect_identical(slash_stop_message("split", stop), paste0(
    "This file has 1 rule whose path ends in '/', such as '/a/'. For each ",
    "one, the validator checks whether crawlers treat '/a' and '/a/' ",
    "differently. This file is too large to check it quickly, so it was not ",
    "checked. It was skipped, and it may have the same problem."
  ))
  # The pair check, plural.
  groups <- sp_groups(paste0("User-agent: *\nDisallow: /a\nDisallow: /a/\n",
                             "Disallow: /b\nDisallow: /b/\nDisallow: /c\n"))
  expect_null(attr(slash_pair_diagnostics(groups), "stopped"))
  stop <- attr(slash_pair_diagnostics(groups, budget = 3), "stopped")
  expect_identical(stop, sp_stopped(5L, 3L, "/b/"))
  expect_identical(slash_stop_message("pair", stop), paste0(
    "This file has 5 rules that may come in pairs like '/b' and '/b/'. For ",
    "each one, the validator checks whether the same crawlers have both ",
    "forms. This file is too large to check them all quickly, so only the ",
    "first 3 were checked, in line order. The other 2 were skipped, and ",
    "some of them may be part of such a pair."
  ))
  # A normal file gets no such row.
  for (name in names(sp_fixtures)) {
    expect_false("rule_check_stopped" %in% sp_codes(sp_body(name)),
                 label = name)
  }
})

test_that("ROBO-roypaoox: the split's checked count on each budget branch", {
  # `/a/` (line 4) is read once per class, A and B: 2 rows, and its plan
  # pays A's 2 rules and B's 3, so 7; its two bodies hold 2 lines each, so
  # 4 to read. `/b/` (line 9) is 1 row for C plus C's 6 rules: 7 more.
  groups <- sp_groups(paste0(
    "User-agent: A\nUser-agent: B\nDisallow: /\nAllow: /a/\n\n",
    "User-agent: B\nDisallow: /z\n\n",
    "User-agent: C\nAllow: /b/\n",
    paste0("Disallow: /y", 1:5, "\n", collapse = "")
  ))
  # 11: the plan takes `/a/` only (7, not 14), and its 4 body lines fit,
  # so every row built is read but the plan cut `/b/`: 1 checked.
  found <- slash_split_diagnostics(groups, budget = 11)
  expect_identical(found$line, 4L)
  expect_identical(attr(found, "stopped"), sp_stopped(2L, 1L, "/b/"))
  # 8: the plan takes `/a/` (7), but no body line fits in the 1 left, so
  # not even the first candidate's rows are read: 0 checked.
  found <- slash_split_diagnostics(groups, budget = 8)
  expect_identical(found$line, integer(0))
  expect_identical(attr(found, "stopped"), sp_stopped(2L, 0L, "/a/"))
})

test_that("ROBO-roypaoox: a file too large for the checks gets the rows", {
  d <- sp_diag(sp_shape("classes", 250L))
  stop <- d[d$code == "rule_check_stopped", , drop = FALSE]
  expect_identical(stop$line, c(NA_integer_, NA_integer_))
  expect_identical(stop$severity, c("info", "info"))
  expect_identical(stop$directive, c(NA_character_, NA_character_))
  expect_identical(stop$raw_text, c(NA_character_, NA_character_))
  expect_identical(stop$message, c(
    paste0(
      "This file has 750 rules that may come in pairs like '/d137' and ",
      "'/d137/'. For each one, the validator checks whether the same ",
      "crawlers have both forms. This file is too large to check them all ",
      "quickly, so only the first 272 were checked, in line order. The other ",
      "478 were skipped, and some of them may be part of such a pair."
    ),
    paste0(
      "This file has 250 rules whose path ends in '/', such as '/d1/'. For ",
      "each one, the validator checks whether crawlers treat '/d1' and ",
      "'/d1/' differently. This file is too large to check them all ",
      "quickly, so none of them were checked. All 250 were skipped, and some ",
      "of them may have the same problem."
    )
  ))
})

test_that("ROBO-roypaoox: the checks stay linear on costly shapes", {
  skip_on_cran()
  for (shape in c("gram", "locale", "classes")) {
    n <- if (shape == "classes") 250L else 500L
    small <- sp_time_check(sp_shape(shape, n), 1L)
    large <- sp_time_check(sp_shape(shape, 4L * n), 1L)
    expect_lt(large, 8 * max(small, 0.05), label = shape)
  }
})

# A split and a pair whose values carry the length, inside the 16,663-byte
# line buffer; the checks alone, 20 calls per run.
sp_value <- function(n) {
  value <- paste0("/", strrep("ab", n))
  sprintf(paste0("User-agent: *\nDisallow: %s/\nAllow: %s\n",
                 "Disallow: %sc\nDisallow: %sc/\n"), value, value, value, value)
}

test_that("ROBO-roypaoox: the checks are linear in the value's length", {
  skip_on_cran()
  d <- sp_diag(sp_value(10L))
  expect_identical(d$code, c(sp_pair, sp_split))
  expect_identical(d$line, c(5L, 1L))
  short <- sp_time_check(sp_value(1000L), 20L)
  long <- sp_time_check(sp_value(4000L), 20L)
  expect_lt(long, 8 * max(short, 0.05))
})
