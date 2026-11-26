# ROBO-dkkbwzur: the rewrite oracle of ROBO-rdxgnqhw (rewrite_oracle(),
# helper-rewrite-oracle.R) over older validator notes that advise a rewrite.
# Each note's advice is applied to every fixture that gives the note, as the
# message words it, and the package's google, bing and yandex backends must
# agree with what the advice claims: no decision changes, or only the ones
# it means to change. Agreement shows consistency with this package's
# backends only, not how Bing or Yandex read a rule. The fixtures are the
# notes' own (their test files are named beside each list) plus edge forms;
# every body is synthetic.

ro_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

ro_rows <- function(body, code) {
  d <- robots_validate_text(body)$diagnostics
  d[d$code == code, , drop = FALSE]
}

# A body's lines (rw_chunks()) with line `n` replaced by `new`, each new
# line taking line `n`'s own line end (LF when it had none). No new lines
# deletes line `n`, its line end too.
ro_replace <- function(body, n, new) {
  chunks <- rw_chunks(body)
  end <- regmatches(chunks[[n]], regexpr("(\r\n|\r|\n)$", chunks[[n]],
                                         useBytes = TRUE))
  if (length(end) == 0L) end <- "\n"
  chunks[[n]] <- if (length(new) == 0L) "" else paste0(new, end, collapse = "")
  paste(chunks, collapse = "")
}

# The line numbers a message names in "(line N)".
ro_line_of <- function(message) {
  hit <- regmatches(message, regexpr("\\(line [0-9]+\\)", message))
  as.integer(gsub("[^0-9]", "", hit))
}

# ---------------------------------------------------------------------------
# 1. user_agent_duplicate_in_group: "the line can be deleted". Identity on
# every engine.

dup_code <- "user_agent_duplicate_in_group"

# The advice: delete the repeating line, the first one the message names.
dup_rewrite <- function(body, message) {
  ro_replace(body, ro_line_of(message)[[1L]], character())
}

# test-user-agent-duplicate-in-group-wnuttuit.R's bodies that give the row,
# then edge forms.
dup_fixtures <- list(
  case = ro_lines("User-agent: Acme-Bot", "User-agent: acme-bot",
                  "Disallow: /a"),
  exact = ro_lines("User-agent: Acme-Bot", "User-agent: Acme-Bot",
                   "Disallow: /a"),
  star = ro_lines("User-agent: *", "User-agent: *", "Disallow: /a"),
  three = ro_lines("User-agent: Alpha", "User-agent: alpha",
                   "User-agent: Beta", "User-agent: beta",
                   "User-agent: Gamma", "User-agent: gamma", "Disallow: /a"),
  earlier = ro_lines("User-agent: FooBot", "Disallow: /a", "",
                     "User-agent: Bar", "User-agent: foobot",
                     "User-agent: FOOBOT", "Disallow: /b"),
  blank = ro_lines("User-agent: Acme-Bot", "", "User-agent: acme-bot",
                   "Disallow: /a"),
  comment = ro_lines("User-agent: Acme-Bot", "# note", "User-agent: acme-bot",
                     "Disallow: /a"),
  crawl_delay = ro_lines("User-agent: Acme-Bot", "Crawl-delay: 1",
                         "User-agent: acme-bot", "Disallow: /a"),
  sitemap = ro_lines("User-agent: Acme-Bot",
                     "Sitemap: https://example.com/s.xml",
                     "User-agent: acme-bot", "Disallow: /a"),
  unknown = ro_lines("User-agent: Acme-Bot", "Foobar: baz",
                     "User-agent: acme-bot", "Disallow: /a"),
  star_delay = ro_lines("User-agent: *", "Crawl-delay: 1", "User-agent: *",
                        "Disallow: /a"),
  star_text = ro_lines("User-agent: *", "User-agent: * foo", "Disallow: /a"),
  id_bot = ro_lines("User-agent: ID-Bot", "User-agent: id-bot",
                    "Disallow: /a"),
  rules = ro_lines("User-agent: Acme-Bot", "User-agent: acme-bot",
                   "Disallow: /a", "Allow: /a/b", "", "User-agent: *",
                   "Disallow: /x"),
  crlf = gsub("\n", "\r\n", ro_lines("User-agent: Acme-Bot",
                                     "User-agent: acme-bot", "Disallow: /a"),
              fixed = TRUE),
  cr = "User-agent: Acme-Bot\rUser-agent: acme-bot\rDisallow: /a\r"
)

dup_oracle <- function(body, rewrite = dup_rewrite) {
  lapply(ro_rows(body, dup_code)$message, function(msg) {
    rewrite_oracle(body, function(b) rewrite(b, msg))
  })
}

test_that("ROBO-dkkbwzur: deleting a repeated name keeps every decision", {
  rows <- 0L
  for (name in names(dup_fixtures)) {
    found <- dup_oracle(dup_fixtures[[name]])
    rows <- rows + length(found)
    expect_gt(length(found), 0L, label = name)
    for (bad in found) expect_identical(nrow(bad), 0L, label = name)
  }
  expect_gt(rows, length(dup_fixtures))
  # A cut value is user_agent_cut's: no row, nothing to rewrite.
  cut <- ro_lines("User-agent: Foo/1.0", "User-agent: foo/1.0", "Disallow: /a")
  expect_identical(nrow(ro_rows(cut, dup_code)), 0L)
})

# Known gap (design/engine-disagreements.md class 2): the package's bing and
# yandex backends keep a byte-order mark as part of line 1, so they read no
# User-agent line there, and the repeat on line 2 is the only name they
# read. Deleting it changes their decisions; Google skips the mark and keeps
# its own. The tester records (ROBO-bpywsjwv, design/tracker-snapshot.md)
# split: by B1, Bing's tester lets a leading mark spoil line 1, as the bing
# backend does, so on B1's reading "the line can be deleted" is wrong for
# Bing on a body like this one (follow-up ROBO-dmoucgpb); by Y1, Yandex's
# analyzer skips the mark, which the yandex backend does not yet
# (ROBO-kuxdvvpi). The note is not changed here.
dup_bom <- paste0("\xef\xbb\xbf", ro_lines("User-agent: Acme-Bot",
                                           "User-agent: acme-bot",
                                           "Disallow: /a"))

test_that("ROBO-dkkbwzur: known gap, a repeat behind a byte-order mark", {
  found <- dup_oracle(dup_bom)
  expect_length(found, 1L)
  bad <- found[[1L]]
  expect_gt(nrow(bad), 0L)
  expect_setequal(unique(bad$engine), c("bing", "yandex"))
})

# Known gap: a repeat that ends at a lone CR. Google ends line 2 there, so
# the Disallow is line 3 and deleting line 2 keeps its decisions. The
# package's bing and yandex backends end a line at LF only, so to them the
# Disallow sits inside the repeated User-agent line, and deleting that line
# hands the crawler the rule. B4 and Y6 (ROBO-bpywsjwv) record both testers
# ending a line at a lone CR; the backends' fix is ROBO-gwmdrbrv.
dup_cr_mid <- "User-agent: Acme-Bot\nUser-agent: acme-bot\rDisallow: /a\n"

test_that("ROBO-dkkbwzur: known gap, a repeat ended by a lone CR", {
  found <- dup_oracle(dup_cr_mid)
  expect_length(found, 1L)
  bad <- found[[1L]]
  expect_gt(nrow(bad), 0L)
  expect_setequal(unique(bad$engine), c("bing", "yandex"))
})

# The oracle's own control: the bing leg reads Foo under bingbot, so a body
# naming both must move bingbot's lines out of the way first, or Foo's
# groups would merge with bingbot's and hide a change to Foo's rules.
test_that("ROBO-dkkbwzur: the oracle sees a change to Foo beside bingbot", {
  body <- ro_lines("User-agent: Foo", "Disallow: /x", "",
                   "User-agent: bingbot", "Allow: /x")
  bad <- rewrite_oracle(body, ro_replace(body, 2L, character()))
  expect_true("Foo" %in% bad$token[bad$engine == "bing"])
  expect_false("bingbot" %in% bad$token[bad$engine == "bing"])
  # The displaced name is one the body does not hold.
  expect_identical(rw_free_name("User-agent: renamedbot\n"), "Renamedbotx")
})

# The oracle's own control for its tokens: Google reads each of these lines
# as Bar's User-agent line (a missing colon, and the `user agent` and
# `useragent` typos, KeyIsUserAgent in src/robots.cc), so deleting Bar's
# rule must show up as a change for Bar.
test_that("ROBO-dkkbwzur: the oracle reads colon-less and typo User-agents", {
  for (agent in c("User-agent Bar", "User agent: Bar", "Useragent: Bar")) {
    body <- ro_lines(agent, "Disallow: /x")
    bad <- rewrite_oracle(body, ro_replace(body, 2L, character()))
    expect_true("Bar" %in% bad$token[bad$engine == "google"], label = agent)
  }
})

# ---------------------------------------------------------------------------
# 2. user_agent_repeated_group: "put their rules in one group". The engines
# already merge the groups, so identity on every engine. The advice does not
# say where the group goes or in what order: the crawler's User-agent line
# (as its first group writes it) leaves every group that names it on the
# row's lines, a group left with no User-agent line loses its rules too
# (its blank and comment lines stay), and one group with that line and
# every such group's rules, in line order, takes the place of the first
# group, or of the last.

rep_code <- "user_agent_repeated_group"

rep_rewrite <- function(body, message, last = FALSE) {
  expect_false(grepl(" more ", message, fixed = TRUE))
  # A byte-order mark stays at the start of the body.
  bytes <- charToRaw(body)
  mark <- as.raw(c(0xef, 0xbb, 0xbf))
  bom <- ""
  if (length(bytes) >= 3L && identical(bytes[1:3], mark)) {
    bom <- rawToChar(mark)
    body <- rawToChar(bytes[-(1:3)])
  }
  chunks <- rw_chunks(body)
  chunks <- ifelse(grepl("(\r|\n)$", chunks, useBytes = TRUE), chunks,
                   paste0(chunks, "\n"))
  text <- sub("(\r\n|\r|\n)$", "", chunks, useBytes = TRUE)
  n <- length(text)
  like <- rw_agent_like(text)
  start <- which(like & !c(FALSE, like[-n]))
  end <- c(start[-1L] - 1L, n)
  earlier <- regmatches(message, regexpr("as lines? [0-9, and]+ in", message))
  earlier <- as.integer(regmatches(earlier, gregexpr("[0-9]+", earlier))[[1L]])
  at <- c(earlier, ro_line_of(message)[[1L]])
  member <- vapply(at, function(l) max(which(start <= l)), 0L)
  keep <- rep(TRUE, n)
  rules <- character()
  for (k in seq_along(at)) {
    g <- start[[member[[k]]]]:end[[member[[k]]]]
    run <- g[seq_len(match(FALSE, like[g], nomatch = length(g) + 1L) - 1L)]
    stopifnot(at[[k]] %in% run)
    plain <- g[!g %in% run & !grepl("^[ \t]*(#.*)?$", text[g],
                                     useBytes = TRUE)]
    rules <- c(rules, chunks[plain])
    keep[at[[k]]] <- FALSE
    if (all(run == at[[k]])) keep[plain] <- FALSE
  }
  into <- start[[member[[if (last) length(member) else 1L]]]]
  before <- seq_len(n) < into
  paste(c(bom, chunks[keep & before], chunks[at[[1L]]], rules, "\n",
           chunks[keep & !before]), collapse = "")
}

rg_file_e <- ro_lines(
  "# START YOAST BLOCK", "# ---------------------------",
  "User-agent: *", "Disallow:", "",
  "Sitemap: https://example.com/sitemap_index.xml",
  "# ---------------------------", "# END YOAST BLOCK", "", "",
  "User-agent: *", "Disallow: /", "",
  "User-agent: bingbot", "Allow: /", "",
  "User-agent: Applebot", "Allow: /", "",
  "User-agent: Googlebot", "Allow: /", "",
  "User-agent: ExampleBot", "Disallow: /"
)

# test-repeated-groups-vnhirero.R's and test-same-rules-groups-rdxgnqhw.R's
# bodies that give the row, then edge forms.
rep_fixtures <- list(
  file_e = rg_file_e,
  file_d = ro_lines(
    "User-agent: *", "Disallow: /wp-admin/",
    "Allow: /wp-admin/admin-ajax.php", "",
    "# GoogleBot", "User-agent: Googlebot", "Allow: /", "",
    "User-agent: Twitterbot", "Allow: /", "",
    "# crawl rate", "User-agent: *", "Crawl-delay: 10", "",
    "User-agent: *", "Disallow: /?trap", "",
    "# crawl rate", "User-agent: *", "Crawl-delay: 10", "",
    "User-agent: OAI-SearchBot", "Disallow: /", "",
    "# DotBot",
    "User-agent: DotBot", "Disallow: /", "User-agent: dotbot", "Disallow: /"
  ),
  two_repeated = ro_lines(
    "User-agent: a", "Disallow: /a", "", "User-agent: b", "Disallow: /b", "",
    "User-agent: a", "User-agent: b", "Disallow: /c"
  ),
  full_block = ro_lines("User-agent: FooBot", "Disallow: /", "",
                        "User-agent: FooBot", "Disallow:"),
  shared_full = ro_lines(
    "User-agent: a", "Disallow:", "", "User-agent: b", "Disallow:", "",
    "User-agent: a", "User-agent: b", "Disallow: /"
  ),
  star_empty = ro_lines("User-agent: *", "Disallow:", "", "User-agent: *",
                        "Disallow: /*", "Disallow: /private"),
  same_group = ro_lines("User-agent: a", "Disallow:", "Disallow: /", "",
                        "User-agent: a", "Disallow: /*"),
  repeated_only = ro_lines("User-agent: Foo", "Disallow: /x", "",
                           "User-agent: Foo", "Disallow: /x"),
  with_other = ro_lines("User-agent: Foo", "Disallow: /x", "",
                        "User-agent: Bar", "Disallow: /x", "",
                        "User-agent: Foo", "Disallow: /x"),
  elsewhere = ro_lines("User-agent: Foo", "Disallow: /x", "",
                       "User-agent: Bar", "Disallow: /x", "",
                       "User-agent: Foo", "Allow: /x/y"),
  overlap = ro_lines("User-agent: Foo", "Disallow: /", "",
                     "User-agent: Foo", "User-agent: Bar", "Disallow: /"),
  wider_first = ro_lines("User-agent: Foo", "User-agent: Bar",
                         "Disallow: /feed", "", "User-agent: Foo",
                         "Disallow: /feeds", "Allow: /feeds/a"),
  case_twins = ro_lines("User-agent: Foo", "Disallow: /x", "",
                        "User-agent: foo", "Disallow: /x"),
  tie = ro_lines("User-agent: Foo", "Disallow: /x", "", "User-agent: Foo",
                 "Allow: /x", "Allow: /*q", "Disallow: /*q"),
  three = ro_lines("User-agent: Foo", "Disallow: /a", "", "User-agent: Foo",
                   "Disallow: /b", "", "User-agent: Foo", "Allow: /a/b"),
  crlf = gsub("\n", "\r\n", ro_lines("User-agent: Foo", "Disallow: /x", "",
                                     "User-agent: Foo", "Allow: /x/y"),
              fixed = TRUE),
  cr = "User-agent: Foo\rDisallow: /x\r\rUser-agent: Foo\rAllow: /x/y\r",
  cr_end = ro_lines("User-agent: Foo", "Disallow: /x\r", "User-agent: Foo",
                    "Allow: /x/y"),
  escape = ro_lines("User-agent: Foo", "Disallow: /a%3cb", "",
                    "User-agent: Foo", "Allow: /a%3Cb")
)

# For each row of `body`, first and last placement: the oracle's result.
rep_oracle <- function(body) {
  out <- list()
  for (msg in ro_rows(body, rep_code)$message) {
    for (last in c(FALSE, TRUE)) {
      out[[if (last) "last" else "first"]] <- c(
        out[[if (last) "last" else "first"]],
        list(rewrite_oracle(body, function(b) rep_rewrite(b, msg, last)))
      )
    }
  }
  out
}

test_that("ROBO-dkkbwzur: one group per repeated crawler keeps decisions", {
  rows <- 0L
  for (name in names(rep_fixtures)) {
    found <- rep_oracle(rep_fixtures[[name]])
    rows <- rows + length(found$first)
    expect_gt(length(found$first), 0L, label = name)
    for (place in names(found)) {
      for (bad in found[[place]]) {
        expect_identical(nrow(bad), 0L, label = paste(name, place))
      }
    }
  }
  expect_gt(rows, length(rep_fixtures))
  # A cut value is user_agent_cut's: no row, nothing to rewrite.
  cut <- ro_lines("User-agent: Foo/1.0", "Disallow: /x", "",
                  "User-agent: Foo/1.0", "Allow: /x/y")
  expect_identical(nrow(ro_rows(cut, rep_code)), 0L)
})

# Known gap, the same class 2 as dup_bom: the bing and yandex backends read
# no group behind line 1's byte-order mark, so moving that group's rules
# into the later group gives the crawler rules those backends never read
# for it. The merged group at line 1 stays behind the mark: no change. By
# B1 (ROBO-bpywsjwv, design/tracker-snapshot.md), Bing's tester also lets a
# leading mark spoil line 1, so on B1's reading the last placement is wrong
# for Bing on a body like this one (follow-up ROBO-dmoucgpb); by Y1,
# Yandex's analyzer skips the mark, which the yandex backend does not yet
# (ROBO-kuxdvvpi).
rep_bom <- paste0("\xef\xbb\xbf", ro_lines("User-agent: Foo", "Disallow: /x",
                                           "", "User-agent: Foo",
                                           "Allow: /x/y"))

test_that("ROBO-dkkbwzur: known gap, a first group behind a byte-order mark", {
  found <- rep_oracle(rep_bom)
  expect_identical(nrow(found$first[[1L]]), 0L)
  bad <- found$last[[1L]]
  expect_gt(nrow(bad), 0L)
  expect_setequal(unique(bad$engine), c("bing", "yandex"))
})

# ---------------------------------------------------------------------------
# 3. rule_lowercase_escape: "write it as '%XX'". Google upper-cases a
# pattern's escape (MaybeEscapePattern, src/robots.cc), and so does the
# package's bing backend: identity on both. The package's yandex backend
# compares a pattern's escape as written, so there the rewrite may change
# the decisions of URLs that hold the escape, in either case, and no other.
# That is the yandex backend's reading, not a recorded Yandex answer, and
# the note says nothing about Yandex.

lc_code <- "rule_lowercase_escape"

lc_escapes <- function(text) {
  esc <- regmatches(text, gregexpr("%[0-9A-Fa-f]{2}", text, useBytes = TRUE))
  esc <- esc[[1L]]
  unique(grep("[a-f]", esc, value = TRUE))
}

# The advice: the line's lower-case escapes, after its key, in upper case.
lc_rewrite <- function(body, line) {
  chunks <- rw_chunks(body)
  text <- chunks[[line]]
  key <- regmatches(text, regexpr("^[^:]*:", text, useBytes = TRUE))
  if (length(key) == 0L) {
    key <- regmatches(text, regexpr("^[ \t]*[A-Za-z-]+", text,
                                    useBytes = TRUE))
  }
  rest <- rw_drop(text, nchar(key, "bytes"))
  for (esc in lc_escapes(rest)) {
    rest <- gsub(esc, chartr("abcdef", "ABCDEF", esc), rest, fixed = TRUE,
                 useBytes = TRUE)
  }
  chunks[[line]] <- paste0(key, rest)
  paste(chunks, collapse = "")
}

lc_change <- function(escapes) {
  function(engine, token, url) {
    hit <- vapply(url, function(u) {
      any(vapply(escapes, grepl, NA, x = u, ignore.case = TRUE))
    }, NA, USE.NAMES = FALSE)
    engine == "yandex" & hit
  }
}

# test-lower-escape-kormmfyg.R's bodies, then edge forms.
lc_body <- function(line) paste0("user-agent: *\n", line, "\nallow: /\n")
lc_fixtures <- c(
  lapply(c("/a%3cb", "/a%c3", "/a%aB", "/a%Ab", "/%%3c", "/caf\xc3\xa9%3c",
           "/a%3cb%3C", "/a%3cb%aa%3C"), function(v) {
    lc_body(paste0("Disallow: ", v))
  }),
  list(
    allow = "User-agent: *\nDisallow: /\nAllow: /a%3cb\n",
    no_colon = lc_body("Disallow /a%3cb"),
    typo = lc_body("Dissallow: /a%3cb"),
    allow_no_colon = lc_body("Allow /a%3cb"),
    escaped_unreserved = lc_body("Disallow: /%7ejoe%3c"),
    named = "User-agent: Foo\nDisallow: /a%3cb\nAllow: /a%3cb/c\n",
    wild = "User-agent: *\nDisallow: /*%2f$\n",
    star_led = lc_body("Disallow: *%3cb"),
    trailing_comment = lc_body("Disallow: /a%3cb # c"),
    crlf = "User-agent: *\r\nDisallow: /a%3cb\r\n",
    cr = "User-agent: *\rDisallow: /a%3cb\r",
    bom = "\xef\xbb\xbfUser-agent: *\nDisallow: /a%3cb\n",
    invalid_utf8 = "User-agent: *\nDisallow: /a\xff%3cb\n"
  )
)

test_that("ROBO-dkkbwzur: an upper-case escape keeps google and bing", {
  rows <- 0L
  yandex <- 0L
  for (k in seq_along(lc_fixtures)) {
    body <- lc_fixtures[[k]]
    label <- if (nzchar(names(lc_fixtures)[[k]])) names(lc_fixtures)[[k]] else k
    found <- ro_rows(body, lc_code)
    rows <- rows + nrow(found)
    expect_gt(nrow(found), 0L, label = label)
    for (line in found$line) {
      text <- rw_chunks(body)[[line]]
      esc <- lc_escapes(text)
      # The URLs compared hold the rewritten line's own path.
      own <- rw_url(rw_plain(rw_split(text)$value))
      expect_true(own %in% rw_urls(body), label = label)
      bad <- rewrite_oracle(body, function(b) lc_rewrite(b, line),
                            expect_change = lc_change(esc))
      expect_identical(nrow(bad), 0L, label = label)
      yandex <- yandex + sum(attr(bad, "changed")$engine == "yandex")
    }
  }
  expect_gt(rows, 0L)
  # The yandex leg does change: its backend compares escapes as written.
  expect_gt(yandex, 0L)
})

test_that("ROBO-dkkbwzur: a value before a comment loses its blanks", {
  # Written out, not taken from rw_split(): the path ends at the escape.
  urls <- rw_urls(lc_fixtures[["trailing_comment"]])
  expect_true("https://example.com/a%3cb" %in% urls)
  expect_false(any(grepl("%20", urls, fixed = TRUE)))
})

test_that("ROBO-dkkbwzur: a `*`-led value's own URLs reach the comparison", {
  # Only the URLs made from `*%3cb` hold the escape, so only they can show
  # the yandex backend's change.
  body <- lc_fixtures[["star_led"]]
  bad <- rewrite_oracle(body, function(b) lc_rewrite(b, 2L),
                        expect_change = lc_change("%3c"))
  expect_identical(nrow(bad), 0L)
  changed <- attr(bad, "changed")
  expect_gt(nrow(changed), 0L)
  expect_setequal(unique(changed$engine), "yandex")
})

# ---------------------------------------------------------------------------
# 7. rule_prefix_sibling. A rule `P` read as one path segment matches `P`,
# `P/...` and `P?...`; `P` also matches the paths that go on from it with a
# path byte other than `/`, and only those may change when advice narrows
# `P` to one segment. The row used to advise `P$` together with `P/` as the
# narrower spelling; on Google's reading `$` ends the match at the end of
# the path and query together (src/robots.cc), so that spelling also
# dropped `P?x=1`. The row now says only what `P` matches (ROBO-dkkbwzur).

ps_code <- "rule_prefix_sibling"

# The `P` lines a row names, as a data frame (line, value).
ps_named <- function(message) {
  one <- regmatches(message, regexec(
    "^The [A-Za-z]+ on line ([0-9]+) \\('([^']*)'\\) also matches", message
  ))[[1L]]
  if (length(one)) {
    return(data.frame(line = as.integer(one[[2L]]), value = one[[3L]]))
  }
  pairs <- regmatches(message, gregexpr("line [0-9]+ \\('[^']*'\\) matches",
                                        message))[[1L]]
  data.frame(line = as.integer(sub("^line ([0-9]+).*", "\\1", pairs)),
             value = sub("^[^']*'([^']*)'.*", "\\1", pairs))
}

# The `P` lines a row advises to respell as `P$` together with `P/` (the
# old wording, either form), or NULL when the row advises no spelling.
ps_advice <- function(message) {
  old <- c(
    "was meant as one path segment, '[^']*\\$' together with '[^']*/' is",
    "its narrower spelling is the rule ending in '\\$' together with"
  )
  if (!any(vapply(old, grepl, NA, x = message))) {
    return(NULL)
  }
  ps_named(message)
}

# Respell each `P` line as `P$`, then `P/`, under its own key.
ps_rewrite <- function(body, advice) {
  for (k in rev(order(advice$line))) {
    text <- sub("(\r\n|\r|\n)$", "", rw_chunks(body)[[advice$line[[k]]]],
                useBytes = TRUE)
    # The key as lc_rewrite() takes it: up to the colon, or the first word.
    key <- regmatches(text, regexpr("^[^:]*:", text, useBytes = TRUE))
    if (length(key) == 0L) {
      key <- paste0(regmatches(text, regexpr("^[ \t]*[A-Za-z-]+", text,
                                             useBytes = TRUE)), ":")
    }
    p <- advice$value[[k]]
    stopifnot(!grepl("...", p, fixed = TRUE))
    body <- ro_replace(body, advice$line[[k]],
                       paste0(key, " ", p, c("$", "/")))
  }
  body
}

# The decisions narrowing to one segment may change: a path that goes on
# from some `P` with a byte other than `/` or `?`.
ps_change <- function(values) {
  function(engine, token, url) {
    path <- sub("^https://example\\.com", "", url)
    vapply(path, function(p) {
      any(vapply(values, function(v) {
        startsWith(p, v) && nchar(p) > nchar(v) &&
          !substr(p, nchar(v) + 1L, nchar(v) + 1L) %in% c("/", "?")
      }, NA))
    }, NA, USE.NAMES = FALSE)
  }
}

ps_oracle <- function(body, advice) {
  rewrite_oracle(body, ps_rewrite(body, advice),
                 expect_change = ps_change(advice$value))
}

# test-prefix-sibling-otomgbge.R's bodies that give the row, then edge
# forms.
ps_fixtures <- list(
  one = "User-agent: *\nDisallow: /feed\nDisallow: /feeds\n",
  login = "User-agent: *\nDisallow: /login\nDisallow: /login.php\n",
  allow_pair = "User-agent: Foo\nAllow: /about\nAllow: /aboutx\n",
  split_same = paste0("User-agent: Foo\nDisallow: /feed\n\n",
                      "User-agent: Foo\nDisallow: /feeds\n"),
  comment = "User-agent: *\nDisallow: /feed#x\nDisallow: /feeds\n",
  equals = "User-agent: *\nDisallow: /a=b\nDisallow: /a=bc\n",
  seven = paste0("User-agent: *\nDisallow: /feed\n",
                 paste0("Disallow: /feed", letters[1:7], "\n", collapse = "")),
  later = "User-agent: *\nDisallow: /feeds\nDisallow: /feed\n",
  sib_slash = "User-agent: *\nDisallow: /feed\nDisallow: /feeds/\n",
  two_pairs = paste0("User-agent: Foo\nUser-agent: Bar\nDisallow: /feed\n",
                     "Disallow: /feeds\nAllow: /login\nAllow: /login.php\n"),
  chain = paste0("User-agent: *\nDisallow: /a\nDisallow: /ab\n",
                 "Disallow: /abc\nDisallow: /ab/x\n"),
  wider = paste0("User-agent: Foo\nUser-agent: Bar\nDisallow: /feed\n\n",
                 "User-agent: Foo\nDisallow: /feeds\n"),
  per_crawler = paste0("User-agent: a\nUser-agent: b\nDisallow: /feed\n\n",
                       "User-agent: a\nDisallow: /feeds\n\n",
                       "User-agent: b\nDisallow: /feeds\n"),
  full_block = "User-agent: Foo\nDisallow: /\nAllow: /about\nAllow: /aboutx\n",
  other_group = paste0("User-agent: *\nDisallow: /feed\nDisallow: /feeds\n\n",
                       "User-agent: Bar\nDisallow: /x\n"),
  cut_group = paste0("User-agent: *\nDisallow: /feed\nDisallow: /feeds\n\n",
                     "User-agent: Foo/1.0\nDisallow: /feed\n",
                     "Disallow: /feeds\n"),
  crlf = "User-agent: *\r\nDisallow: /feed\r\nDisallow: /feeds\r\n",
  cr = "User-agent: *\rDisallow: /feed\rDisallow: /feeds\r",
  bom = "\xef\xbb\xbfUser-agent: *\nDisallow: /feed\nDisallow: /feeds\n"
)

test_that("ROBO-dkkbwzur: a prefix-sibling row advises no spelling", {
  rows <- 0L
  for (name in names(ps_fixtures)) {
    body <- ps_fixtures[[name]]
    msgs <- ro_rows(body, ps_code)$message
    rows <- rows + length(msgs)
    expect_gt(length(msgs), 0L, label = name)
    for (msg in msgs) {
      expect_false(grepl("spelling|together with|meant as", msg), label = name)
      # The URLs compared hold each named `P` line's own path.
      expect_true(all(rw_url(ps_named(msg)$value) %in% rw_urls(body)),
                  label = name)
      # Any advice a row gives must pass the oracle.
      advice <- ps_advice(msg)
      expect_null(advice, label = name)
      if (!is.null(advice)) {
        expect_identical(nrow(ps_oracle(body, advice)), 0L, label = name)
      }
    }
  }
  expect_gt(rows, length(ps_fixtures))
})

test_that("ROBO-dkkbwzur: the dropped `P$` and `P/` lose `P`'s query URLs", {
  # Why the advice went: respelling each named `P` as `P$` and `P/`
  # changes, on Google's reading, the decisions of `P`'s query URLs, which
  # narrowing to one segment may not. Under `allow_pair` every path is
  # allowed with or without the Allow, so nothing changes there.
  for (name in names(ps_fixtures)) {
    body <- ps_fixtures[[name]]
    for (msg in ro_rows(body, ps_code)$message) {
      bad <- ps_oracle(body, ps_named(msg))
      path <- sub("^https://example\\.com", "", bad$url)
      expect_true(all(grepl("?", path, fixed = TRUE)), label = name)
      if (name != "allow_pair") {
        expect_true("google" %in% bad$engine, label = name)
      }
    }
  }
})
