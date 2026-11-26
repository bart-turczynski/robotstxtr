# The wildcard-inheritance and empty-Disallow checks in time linear in the
# number of distinct crawlers (ROBO-hmpzayxr, under ROBO-dbvmxcfw's
# linear-cost rule). The pins hold today's rows (line, code, severity and
# message, in order) for bodies that reach each lookup the builders index:
# one crawler named in groups that are not adjacent, crawlers with the same
# rules, a cut value beside its uncut name, a Google token that ignores `*`,
# crawler ids holding `_` and `-` (their order in a message is the session
# collation's), the group-merge and other-crawler advice branches.

dc_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

dc_code <- c(
  lost = "wildcard_disallows_not_inherited",
  reopen = "allow_reopens_wildcard_disallow",
  info = "wildcard_rules_not_inherited",
  empty = "empty_disallow_with_full_block"
)

dc_rows <- function(body) {
  d <- robots_validate_text(body)$diagnostics
  d <- d[d$code %in% dc_code, c("line", "code", "severity", "message")]
  rownames(d) <- NULL
  d
}

dc_frame <- function(line, code, severity, message) {
  data.frame(line = as.integer(line), code = unname(dc_code[code]),
             severity = severity, message = message,
             stringsAsFactors = FALSE)
}

dc_replaces <- paste0(
  "A named group replaces `User-agent: *` for the crawlers it names ",
  "instead of adding to it (RFC 9309 section 2.2.1). "
)

dc_ignores <- paste0(
  "A crawler obeys only the groups that name it and ignores ",
  "`User-agent: *` once any group does; `User-agent: *` applies only to ",
  "crawlers no group names."
)

dc_reopen_one <- function(who, path, allow_line, star) {
  paste0(
    who, " obeys only this group, so Allows there reopen this path, which ",
    "`User-agent: *` disallows: ", path, " (allowed by Allow: ", path,
    " on line ", allow_line, "; disallowed for `*` by ", star, "). ",
    dc_replaces, "If this path was meant to stay blocked for it, add a ",
    "Disallow to this group longer than the Allow matching the path."
  )
}

dc_lost_one <- function(who, rules) {
  paste0(
    who, " obeys only this group, so these `User-agent: *` Disallows do ",
    "not apply to it: ", rules, ". ", dc_replaces, "If the group was meant ",
    "to add to `User-agent: *`, repeat these Disallows in it."
  )
}

dc_empty_tail <- paste0(
  "Google and Bing ignore an empty `Disallow:` and block every path; ",
  "Yandex reads it as allowing every path"
)

# One crawler (`Alpha`, `alpha`) in groups 1 and 3 of the named ones, with
# Allows on both sides of its Disallows: each reopened path cites the line
# of its own Allow. `Foo1` and `foo` share a key; `AdsBot-Google` ignores
# `*`.
dc_split_key <- dc_lines(
  "User-agent: *", "Disallow: /a", "Disallow: /p", "Allow: /p/open",
  "Allow: /x", "",
  "User-agent: Alpha", "Disallow: /p", "Allow: /a/one", "Disallow: /a", "",
  "User-agent: Beta", "Disallow: /a", "Disallow: /p", "Allow: /p/b", "",
  "User-agent: alpha", "Allow: /p/two", "Disallow: /s", "",
  "User-agent: Foo1", "User-agent: foo", "Disallow: /a", "Disallow: /p",
  "Allow: /a/f", "",
  "User-agent: AdsBot-Google", "Disallow: /a", "Allow: /a/g"
)

test_that("wildcard rows hold for a crawler in groups apart", {
  expect_identical(dc_rows(dc_split_key), dc_frame(
    c(7, 7, 12, 21, 27), c("reopen", "info", "reopen", "reopen", "info"),
    c("warning", "info", "warning", "warning", "info"),
    c(
      paste0(
        "Alpha obeys only the groups that name it, so Allows there ",
        "reopen these paths, which `User-agent: *` disallows: /a/one ",
        "(allowed by Allow: /a/one on line 9; disallowed for `*` by ",
        "Disallow: /a on line 2), /p/two (allowed by Allow: /p/two on ",
        "line 18; disallowed for `*` by Disallow: /p on line 3). ",
        dc_replaces, "If these paths were meant to stay blocked for it, ",
        "add Disallows to these groups longer than the Allow matching each ",
        "path."
      ),
      paste0(
        "Alpha (line 7); Beta (line 12); and foo (line 21) each obey ",
        "only the groups that name them, so these `User-agent: *` ",
        "rules do not apply to them: Allow: /p/open (line 4), Allow: ",
        "/x (line 5). ", dc_ignores
      ),
      dc_reopen_one("Beta", "/p/b", 15, "Disallow: /p on line 3"),
      dc_reopen_one("foo", "/a/f", 25, "Disallow: /a on line 2"),
      paste0(
        "AdsBot-Google ignores `User-agent: *` whether or not a group ",
        "names it (one of Google's special-case crawlers), so these ",
        "`User-agent: *` rules never applied to it: Disallow: /p (line ",
        "3), Allow: /p/open (line 4), Allow: /x (line 5)."
      )
    )
  ))
})

# Crawlers whose groups hold the same rules share one check: three that
# reopen `/a` (each citing its own Allow line), two that lose both `*`
# Disallows, and a full block that loses only the `*` Allow.
dc_shared <- dc_lines(
  "User-agent: *", "Disallow: /a", "Disallow: /k", "Allow: /x", "",
  "User-agent: a_bot", "Disallow: /a", "Allow: /a/c", "Disallow: /k", "",
  "User-agent: a-bot", "Disallow: /a", "Allow: /a/c", "Disallow: /k", "",
  "User-agent: abot", "Disallow: /a", "Allow: /a/c", "Disallow: /k", "",
  "User-agent: Kappa", "Disallow: /b", "",
  "User-agent: Lambda", "Disallow: /b", "",
  "User-agent: Gamma", "Disallow: /", ""
)

test_that("wildcard rows hold for crawlers with the same rules", {
  star <- "Disallow: /a on line 2"
  lost <- "Disallow: /a (line 2), Disallow: /k (line 3)"
  expect_identical(dc_rows(dc_shared), dc_frame(
    c(6, 6, 11, 16, 21, 24, 27),
    c("reopen", "info", "reopen", "reopen", "lost", "lost", "info"),
    c("warning", "info", "warning", "warning", "warning", "warning", "info"),
    c(
      dc_reopen_one("a_bot", "/a/c", 8, star),
      paste0(
        "a_bot (line 6); a-bot (line 11); abot (line 16); Kappa (line ",
        "21); and Lambda (line 24) each obey only the groups that name ",
        "them, so this `User-agent: *` rule does not apply to them: ",
        "Allow: /x (line 4). ", dc_ignores
      ),
      dc_reopen_one("a-bot", "/a/c", 13, star),
      dc_reopen_one("abot", "/a/c", 18, star),
      dc_lost_one("Kappa", lost),
      dc_lost_one("Lambda", lost),
      paste0(
        "Gamma obeys only this group, which disallows `/`, so this ",
        "`User-agent: *` Allow rule may be meant as an exception and ",
        "does not apply to it: Allow: /x (line 4). A stricter policy ",
        "for a named crawler may be deliberate. ", dc_ignores
      )
    )
  ))
})

# Four ids on one full block, written in an order that is neither C's nor
# a dictionary collation's: the message names them in sort() order of the
# ids, as factor() levels them in this session. `Foo1` is cut to `foo`.
dc_empty_shared <- dc_lines(
  "User-agent: abot", "User-agent: a-bot", "User-agent: a_bot",
  "User-agent: Foo1", "Disallow:", "Disallow: /", "",
  "User-agent: Zeta", "Disallow:", "Disallow: /"
)

test_that("empty-Disallow rows name a set's crawlers in id order", {
  written <- c(abot = "abot", "a-bot" = "a-bot", a_bot = "a_bot",
               foo = "Foo1")
  shown <- unname(written[sort(names(written))])
  expect_identical(dc_rows(dc_empty_shared), dc_frame(
    c(6, 10), c("empty", "empty"), c("warning", "warning"),
    c(
      paste0(
        "`Disallow: /` (line 6) blocks every path for ", shown[[1L]], ", ",
        shown[[2L]], ", ", shown[[3L]], " and ", shown[[4L]], ", and the ",
        "empty `Disallow:` on line 5 is in the same group. ", dc_empty_tail,
        " and blocks nothing. If these crawlers are meant to be let in, ",
        "delete line 6; if they are meant to be kept out, delete line 5. ",
        "Google's matcher reads only a product token from `Foo1` (line 4) ",
        "and takes the agent to be that token; see the user_agent_cut row."
      ),
      paste0(
        "`Disallow: /` (line 10) blocks every path for Zeta, and the ",
        "empty `Disallow:` on line 9 is in the same group. ", dc_empty_tail,
        " and blocks nothing. If Zeta is meant to be let in, delete line ",
        "10; if it is meant to be kept out, delete line 9."
      )
    )
  ))
})

# The empty Disallow reaches the full block through the group merge, and
# each line to delete sits in a group that also names a crawler outside
# the report (`b-bot`, `Other`, `Omega`): those get "a group of its own".
dc_empty_merge <- dc_lines(
  "User-agent: b_bot", "User-agent: b-bot", "Disallow: /", "",
  "User-agent: b_bot", "Disallow:", "",
  "User-agent: b-bot", "User-agent: Other", "Disallow:", "Allow: /k", "",
  "User-agent: Delta", "Disallow: /", "Disallow: /longer", "",
  "User-agent: Delta", "User-agent: Omega", "Disallow:", "",
  "User-agent: Omega", "Allow: /z"
)

test_that("empty-Disallow rows hold through the group merge", {
  expect_identical(dc_rows(dc_empty_merge), dc_frame(
    c(3, 14), c("empty", "empty"), c("warning", "warning"),
    c(
      paste0(
        "`Disallow: /` (line 3) blocks every path for b_bot, and the ",
        "empty `Disallow:` on line 6 reaches b_bot through the group ",
        "merge. ", dc_empty_tail, " and blocks nothing. If b_bot is meant ",
        "to be let in, give it a group of its own without line 3, which ",
        "other crawlers share; if it is meant to be kept out, delete ",
        "line 6."
      ),
      paste0(
        "`Disallow: /` (line 14) blocks every path for Delta, and the ",
        "empty `Disallow:` on line 19 reaches Delta through the group ",
        "merge. ", dc_empty_tail, " that no longer `Disallow` matches. ",
        "If Delta is meant to be let in, delete line 14; if it is meant ",
        "to be kept out, give it a group of its own without line 19, ",
        "which other crawlers share."
      )
    )
  ))
})

# `*` beside named crawlers whose empty Disallows differ by group (each
# reaches some of them), and a crawler left with only an empty Disallow.
dc_empty_global <- dc_lines(
  "User-agent: *", "Disallow:", "Disallow: /", "",
  "User-agent: c_bot", "User-agent: cbot", "Disallow: /", "",
  "User-agent: c-bot", "User-agent: cbot", "Disallow:", "",
  "User-agent: c_bot", "Disallow:"
)

test_that("empty-Disallow rows hold for `*` and split signatures", {
  shown <- sort(c("c_bot", "cbot"))
  expect_identical(dc_rows(dc_empty_global), dc_frame(
    c(3, 7, 9), c("empty", "empty", "lost"),
    c("warning", "warning", "info"),
    c(
      paste0(
        "`Disallow: /` (line 3) blocks every path for every crawler ",
        "without a group of its own, and the empty `Disallow:` on line ",
        "2 is in the same group. ", dc_empty_tail, " and blocks nothing. ",
        "If these crawlers are meant to be let in, delete line 3; if ",
        "they are meant to be kept out, delete line 2."
      ),
      paste0(
        "`Disallow: /` (line 7) blocks every path for ", shown[[1L]],
        " and ", shown[[2L]], ", and the empty `Disallow:` on lines 11 ",
        "and 14 each reach some of them through the group merge. ",
        dc_empty_tail, " and blocks nothing. If these crawlers are meant ",
        "to be let in, delete line 7; if they are meant to be kept out, ",
        "give them a group of their own without lines 11 and 14, which ",
        "other crawlers share."
      ),
      paste0(
        "c-bot obeys only this group, so this `User-agent: *` Disallow ",
        "does not apply to it: Disallow: / (line 3). This group holds ",
        "no Disallow, so it blocks nothing for it. ", dc_replaces,
        "If the group was meant to add to `User-agent: *`, repeat this ",
        "Disallow in it."
      )
    )
  ))
})

# A rule value over R's 10,000-byte cap on variable names (Google keeps
# lines up to 16,663 bytes), and two values whose combined candidate path
# passes it: the reopen check reads them as it does a short value.
dc_long_a <- strrep("a", 10050L)
dc_long_b <- strrep("b", 6000L)
dc_long_c <- strrep("c", 6000L)

test_that("reopen rows hold for values over 10,000 bytes", {
  path <- paste0("/", dc_long_a)
  expect_identical(
    dc_rows(dc_lines("User-agent: *", paste0("Disallow: ", path), "",
                     "User-agent: examplebot", "Disallow: /",
                     paste0("Allow: ", path))),
    dc_frame(4, "reopen", "warning", dc_reopen_one(
      "examplebot", path, 6, paste0("Disallow: ", path, " on line 2")
    ))
  )
  star <- paste0("/*", dc_long_c)
  allow <- paste0("/", dc_long_b, "/")
  expect_identical(
    dc_rows(dc_lines("User-agent: *", paste0("Disallow: ", star), "",
                     "User-agent: examplebot", "Disallow: /",
                     paste0("Allow: ", allow))),
    dc_frame(4, "reopen", "warning", paste0(
      "examplebot obeys only this group, so Allows there reopen this path, ",
      "which `User-agent: *` disallows: ", allow, dc_long_c, " (allowed by ",
      "Allow: ", allow, " on line 6; disallowed for `*` by Disallow: ", star,
      " on line 2). ", dc_replaces, "If this path was meant to stay blocked ",
      "for it, add a Disallow to this group longer than the Allow matching ",
      "the path."
    ))
  )
})

# Groups with no rule a crawler is judged on: an empty Disallow and an
# empty Allow (W4), or an empty Allow alone (W5). Neither is allow-all, so
# W4 draws only its lost row and W5 keeps its info row.
test_that("wildcard rows hold for groups of empty rules", {
  star <- c("User-agent: *", "Disallow: /a", "Allow: /x", "")
  lost <- paste0(
    "Foo obeys only this group, so this `User-agent: *` Disallow does not ",
    "apply to it: Disallow: /a (line 2). This group holds no Disallow, so ",
    "it blocks nothing for it. ", dc_replaces, "If the group was meant to ",
    "add to `User-agent: *`, repeat this Disallow in it."
  )
  expect_identical(
    dc_rows(dc_lines(star, "User-agent: Foo", "Disallow:", "Allow:")),
    dc_frame(5, "lost", "info", lost)
  )
  expect_identical(
    dc_rows(dc_lines(star, "User-agent: Foo", "Allow:")),
    dc_frame(c(5, 5), c("lost", "info"), c("warning", "info"), c(
      lost,
      paste0(
        "Foo obeys only this group, so this `User-agent: *` rule does not ",
        "apply to it: Allow: /x (line 3). ", dc_ignores
      )
    ))
  )
})

# E1: a first group that names no crawler (`1bot` holds no token Google
# reads), so group numbers and the groups naming crawlers do not line up;
# line 6 is shared with Other, so a let-in Foo gets a group of its own.
# E16: two anchor sets, each anchor's value read from its own rule row.
test_that("empty-Disallow rows hold for group numbers and anchor values", {
  expect_identical(
    dc_rows(dc_lines("User-agent: 1bot", "Disallow: /q", "",
                     "User-agent: Foo", "User-agent: Other", "Disallow: /",
                     "", "User-agent: Foo", "Disallow:", "",
                     "User-agent: Other", "Allow: /k")),
    dc_frame(6, "empty", "warning", paste0(
      "`Disallow: /` (line 6) blocks every path for Foo, and the empty ",
      "`Disallow:` on line 9 reaches Foo through the group merge. ",
      dc_empty_tail, " and blocks nothing. If Foo is meant to be let in, ",
      "give it a group of its own without line 6, which other crawlers ",
      "share; if it is meant to be kept out, delete line 9."
    ))
  )
  expect_identical(
    dc_rows(dc_lines("User-agent: Foo", "Disallow:", "Disallow: /*", "",
                     "User-agent: Bar", "Disallow:", "Disallow: /")),
    dc_frame(c(3, 7), c("empty", "empty"), c("warning", "warning"), c(
      paste0(
        "`Disallow: /*` (line 3) blocks every path for Foo, and the empty ",
        "`Disallow:` on line 2 is in the same group. ", dc_empty_tail,
        " and blocks nothing. If Foo is meant to be let in, delete line 3; ",
        "if it is meant to be kept out, delete line 2."
      ),
      paste0(
        "`Disallow: /` (line 7) blocks every path for Bar, and the empty ",
        "`Disallow:` on line 6 is in the same group. ", dc_empty_tail,
        " and blocks nothing. If Bar is meant to be let in, delete line 7; ",
        "if it is meant to be kept out, delete line 6."
      )
    ))
  )
})

# Timing guards: `n` distinct crawlers (letter-only tokens, so each is its
# own key), each builder timed on its own.
dc_letters <- function(n) {
  paste0("T", chartr("0123456789", "abcdefghij", seq_len(n)))
}

dc_groups <- function(body) {
  validation_groups(as.data.frame(
    robotstxtr_validation_parse_(charToRaw(body)), stringsAsFactors = FALSE
  ))
}

dc_elapsed <- function(check, groups) {
  system.time(check(groups))[["elapsed"]]
}

dc_shapes <- list(
  # Each crawler loses the `*` Disallow /k, reopens /a with its own Allow
  # (through the `*`-side reopen cache) and misses the `*` Allow: every row
  # kind, and no two crawlers share a body.
  wildcard = list(
    body = function(n) {
      t <- dc_letters(n)
      dc_lines("User-agent: *", "Disallow: /a", "Disallow: /k", "Allow: /x",
               sprintf("User-agent: %s\nDisallow: /a\nAllow: /a/%s", t, t))
    },
    keys = function(n) n + 1L,
    check = wildcard_inheritance_diagnostics,
    code = "allow_reopens_wildcard_disallow"
  ),
  # Each crawler its own full block that loses the `*` Allow: one info row
  # merging every crawler's group, which names five and counts the rest.
  full_block = list(
    body = function(n) {
      dc_lines("User-agent: *", "Disallow: /a", "Allow: /x",
               sprintf("User-agent: %s\nDisallow: /", dc_letters(n)))
    },
    keys = function(n) n + 1L,
    check = wildcard_inheritance_diagnostics,
    code = "wildcard_rules_not_inherited"
  ),
  # Each crawler its own full block with an empty Disallow: one row and
  # one anchor set per crawler.
  empty = list(
    body = function(n) {
      dc_lines(sprintf("User-agent: %s\nDisallow:\nDisallow: /",
                       dc_letters(n)))
    },
    keys = function(n) n,
    check = empty_disallow_full_block_diagnostics,
    code = NULL
  )
)

for (shape in names(dc_shapes)) {
  test_that(paste("time is linear in distinct crawlers:", shape), {
    skip_on_cran()
    x <- dc_shapes[[shape]]
    small <- dc_groups(x$body(1000L))
    large <- dc_groups(x$body(8000L))
    expect_length(unique(small$agents$key), x$keys(1000L))
    expect_length(unique(large$agents$key), x$keys(8000L))
    if (!is.null(x$code)) {
      rows <- x$check(dc_groups(x$body(20L)))
      expect_true(x$code %in% vapply(rows, `[[`, "", "code"))
    }
    # Eight times the crawlers: linear is about eight times the time,
    # quadratic sixty-four. 14x and a 0.05 s floor leave room for load.
    # Best of five on each side; the large side stops at its first run
    # under the bound.
    bound <- 14 * max(min(replicate(5L, dc_elapsed(x$check, small))), 0.05)
    best <- Inf
    for (i in 1:5) {
      best <- min(best, dc_elapsed(x$check, large))
      if (best < bound) break
    }
    expect_lt(best, bound)
  })
}
