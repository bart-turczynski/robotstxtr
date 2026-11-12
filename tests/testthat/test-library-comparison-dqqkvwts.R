# ROBO-dqqkvwts: the library comparison (design/library-comparison.md).
#
# Each test pins robotstxtr's own answer on one difference class: the Google
# path, robots_evaluate_text_v1() with the google ruleset and backend, and
# allowed_by_robots_text(), which must agree. The comments record what the
# pristine upstream Google engine (the reference) and each library answered
# when dev/library-comparison/run.R ran them, so no external binary is
# needed here. Library ids, as in the doc:
#   py   Python urllib.robotparser (CPython 3.15.2)
#   pro  protego 0.7.0
#   go   github.com/temoto/robotstxt v1.1.2
#   rs   texting_robots 0.2.2
#   jv   crawler-commons 1.6 SimpleRobotRulesParser
#   js   robots-parser 3.0.1
#   rtx  rOpenSci robotstxt 0.7.15 (its checks run through spiderbar)
#   spb  spiderbar 0.2.5
# "others" in a comment means every library not named. robotstxtr agrees
# with the reference on every row here, the three UTF-16 bodies included:
# since ROBO-pvqrfvol its Google matcher ends each line at its first NUL, as
# the reference does, so run.R's expected-split list is empty.
#
# The bodies are the committed fixtures: the class fixtures in
# fixtures/library-comparison-dqqkvwts/ (manifest.csv there records every
# answer, `body_file` relative to that directory) and the edge-case catalog
# in fixtures/edge-cases/. A body is `<file>.txt`, its bytes verbatim, or
# `<file>.hex`, lowercase hexadecimal (edge_hex_bytes(), helper-edge-hex.R).

lc_edge_dir <- test_path("fixtures", "edge-cases")
lc_class_dir <- test_path("fixtures", "library-comparison-dqqkvwts")

lc_class_manifest <- utils::read.csv(
  file.path(lc_class_dir, "manifest.csv"), colClasses = "character",
  na.strings = character(), encoding = "UTF-8", check.names = FALSE
)

lc_read_bytes <- function(dir, file) {
  path <- file.path(dir, file)
  if (endsWith(file, ".hex")) {
    return(edge_hex_bytes(readLines(path), file))
  }
  readBin(path, "raw", file.size(path))
}

# The bytes as a string the text entry points take verbatim. A NUL-bearing
# body is decoded as the fetch path decodes it (each line cut at its first
# NUL), since an R string cannot hold a NUL.
lc_text <- function(bytes) {
  if (any(bytes == as.raw(0))) {
    return(decode_matcher_body(bytes))
  }
  out <- rawToChar(bytes)
  Encoding(out) <- "bytes"
  out
}

# A body from the edge-case catalog, by fixture id.
lc_catalog <- function(id) {
  file <- paste0(id, ".txt")
  if (!file.exists(file.path(lc_edge_dir, file))) file <- paste0(id, ".hex")
  lc_text(lc_read_bytes(lc_edge_dir, file))
}

# A class fixture's body, by its id in the class manifest.
lc_fixture <- function(id) {
  file <- unique(lc_class_manifest$body_file[lc_class_manifest$id == id])
  stopifnot(length(file) == 1L)
  lc_text(lc_read_bytes(lc_class_dir, file))
}

# The catalog's long-line path is too long to restate here.
lc_catalog_path <- function(id, n = 1L) {
  m <- utils::read.csv(
    file.path(lc_edge_dir, "manifest.csv"), colClasses = "character",
    encoding = "UTF-8"
  )
  m$path[m$id == id][[n]]
}

# robotstxtr's answer on both Google paths, as "allow" or "disallow".
lc_answer <- function(body, path, token = "FooBot") {
  url <- paste0("https://example.com", path)
  Encoding(url) <- "UTF-8"
  v1 <- robots_evaluate_text_v1(body, url, token, "google", "google")$results
  text <- allowed_by_robots_text(body, url, token)$results$allowed
  text <- if (is.na(text)) NA_character_ else if (text) "allow" else "disallow"
  c(v1 = v1$url_decision, text = text)
}

# `v1` is the v1 google/google answer where it parts from the legacy one: the
# crawler-token layer (ROBO-fbbmvbob) applies to v1 only.
lc_expect <- function(body, path, want, token = "FooBot", v1 = want) {
  expect_identical(
    lc_answer(body, path, token), c(v1 = v1, text = want),
    info = paste(token, path)
  )
}

test_that("every class fixture row: robotstxtr's recorded answer", {
  m <- lc_class_manifest
  expect_true(all(m$robotstxtr %in% c("0", "1")))
  # No class fixture is a split from the reference (the doc's Result).
  expect_identical(m$robotstxtr, m$google_ref)
  for (k in seq_len(nrow(m))) {
    want <- if (m$robotstxtr[[k]] == "1") "allow" else "disallow"
    expect_identical(
      lc_answer(lc_text(lc_read_bytes(lc_class_dir, m$body_file[[k]])),
                m$path[[k]], m$token[[k]]),
      c(v1 = want, text = want),
      info = paste(m$id[[k]], m$token[[k]], m$path[[k]])
    )
  }
})

test_that("class 1: a non-rule line between two User-agent lines", {
  # Google keeps stacking across every line that is not a rule, so FooBot
  # shares the `*` group. Reference disallow on every body.
  # Crawl-delay: py pro go rs js rtx spb allow (they end FooBot's group);
  # jv disallow.
  body <- lc_fixture("stack-crawl-delay")
  lc_expect(body, "/x", "disallow")
  lc_expect(body, "/x", "disallow", token = "BarBot")
  # The same body without the blank line (not a fixture): as above.
  joined <- sub("\n\n", "\n", body, fixed = TRUE)
  expect_false(identical(joined, body))
  body <- joined
  lc_expect(body, "/x", "disallow")
  lc_expect(body, "/x", "disallow", token = "BarBot")
  # The second group named: as Crawl-delay above.
  lc_expect(lc_fixture("stack-named"), "/x", "disallow")
  # Sitemap: rtx spb allow; others disallow.
  lc_expect(lc_fixture("stack-sitemap"), "/x", "disallow")
  # An unknown field: pro rtx spb allow; others disallow.
  lc_expect(lc_fixture("stack-unknown"), "/x", "disallow")
  # Control, a comment line: every library disallows.
  lc_expect(lc_fixture("stack-comment"), "/x", "disallow")
})

test_that("class 2: a leading UTF-8 byte-order mark", {
  # Reference disallow (one leading BOM skipped); py pro allow.
  lc_expect(lc_fixture("bom-start"), "/x", "disallow")
  # Control, a comment as line 1: every library disallows.
  lc_expect(lc_fixture("bom-comment-first"), "/x", "disallow")
})

test_that("class 3: a byte-order mark after the first byte", {
  # enc-bom-mid-file: reference allow; js disallow (it trims the BOM).
  lc_expect(lc_catalog("enc-bom-mid-file"), "/a", "allow")
  # enc-bom-before-user-agent: reference disallow on /a; js allow.
  lc_expect(lc_catalog("enc-bom-before-user-agent"), "/a", "disallow")
  # enc-bom-doubled: reference allow; rs js rtx spb disallow; go ERR.
  lc_expect(lc_catalog("enc-bom-doubled"), "/a", "allow")
})

test_that("class 4: a wildcard pattern matched anywhere in the path", {
  body <- lc_fixture("wc-mid-star") # Disallow: /a*b
  lc_expect(body, "/axxb", "disallow") # every library disallows
  lc_expect(body, "/x/axxb", "allow") # go disallow; others allow
  lc_expect(body, "/a", "allow") # every library allows
  body <- lc_fixture("wc-dollar") # Disallow: /a$
  lc_expect(body, "/a", "disallow") # every library disallows
  lc_expect(body, "/ab", "allow") # every library allows
  lc_expect(body, "/x/a", "allow") # go disallow; others allow
})

test_that("controls: wildcard anchors every library reads alike", {
  body <- lc_fixture("wc-ext-dollar") # Disallow: /*.pdf$
  lc_expect(body, "/x.pdf", "disallow")
  lc_expect(body, "/x.pdf?y=1", "allow")
  lc_expect(body, "/x.pdfa", "allow")
  body <- lc_fixture("wc-root-dollar") # Disallow: /, Allow: /$
  lc_expect(body, "/", "allow")
  lc_expect(body, "/x", "disallow")
  body <- lc_fixture("wc-php") # Disallow: /*.php, Allow: /index.php
  lc_expect(body, "/index.php", "allow")
  lc_expect(body, "/a.php", "disallow")
})

test_that("controls: rule precedence every library reads alike", {
  body <- lc_fixture("prec-allow-longer") # Disallow: /x, Allow: /x/y
  lc_expect(body, "/x/y", "allow")
  lc_expect(body, "/x/z", "disallow")
  # Allow: /x, Disallow: /x/y
  lc_expect(lc_fixture("prec-disallow-longer"), "/x/y", "disallow")
  # Allow: /, Disallow: /x
  lc_expect(lc_fixture("prec-allow-root"), "/x", "disallow")
  # Disallow: (empty), Disallow: /x
  lc_expect(lc_fixture("prec-empty-disallow"), "/x", "disallow")
})

test_that("class 5: `/*$` matches every path", {
  body <- lc_catalog("esc-star-dollar")
  lc_expect(body, "/", "disallow") # rtx spb allow
  lc_expect(body, "/anything", "disallow") # rtx spb allow
})

test_that("class 6: a `$` inside a pattern is a literal character", {
  body <- lc_catalog("esc-dollar-then-star")
  lc_expect(body, "/a", "allow") # py go rs rtx spb disallow
  lc_expect(body, "/a$", "disallow") # py go rs jv rtx spb allow
  lc_expect(body, "/a$b", "disallow") # py go rs jv rtx spb allow
})

test_that("class 7: a final `$` does not also block the escaped `%24`", {
  # Reference allow; pro disallow (it adds a literal-dollar copy).
  lc_expect(lc_fixture("wc-dollar"), "/a%24", "allow")
})

test_that("class 8: `Disallow: $` matches nothing", {
  body <- lc_catalog("esc-lone-dollar")
  lc_expect(body, "/", "allow") # go rtx spb disallow
  lc_expect(body, "/a", "allow") # every library allows
})

test_that("class 9: a wildcard rule's priority is its pattern length", {
  # Reference allow (`/abc`, 4, beats `/*`, 2); py disallow (match length).
  body <- lc_fixture("wc-star-vs-allow")
  lc_expect(body, "/abcdef", "allow")
  lc_expect(body, "/x", "disallow") # every library disallows
  # Reference disallow (`/p*`, 3, beats `/p`, 2); py allow.
  lc_expect(lc_fixture("wc-trailing-star"), "/p", "disallow")
})

test_that("class 10: Allow wins a tie, and a trailing `*` counts", {
  # Reference allow; go rtx spb disallow (the first rule wins a tie).
  lc_expect(lc_fixture("tie-disallow-first"), "/x", "allow")
  # Control, Allow first: every library allows.
  lc_expect(lc_fixture("tie-allow-first"), "/x", "allow")
  # esc-star-longer-pattern-wins: reference allow; go rtx spb disallow
  # (they drop the trailing `*`, so the two rules tie).
  body <- lc_catalog("esc-star-longer-pattern-wins")
  lc_expect(body, "/p", "allow")
  lc_expect(body, "/px", "allow")
})

test_that("class 11: a group whose name only starts the token", {
  # Reference allow (the `*` group); py pro go disallow.
  lc_expect(lc_fixture("grp-prefix-name"), "/x", "allow")
  lc_expect(lc_fixture("grp-google-prefix"), "/x", "allow",
            token = "Googlebot")
  # A group name inside the token: py disallow (substring); others allow.
  lc_expect(lc_fixture("grp-suffix-name"), "/x", "allow")
  # Control, a longer group name: every library allows.
  lc_expect(lc_fixture("grp-news-only"), "/x", "allow", token = "Googlebot")
  # Control, a `*` group and a named one: every library allows.
  lc_expect(lc_fixture("grp-star-and-named"), "/x", "allow")
  # grp-googlebot-image-fallback: reference takes `*`; py pro go take the
  # Googlebot group (x allow / y disallow under the reference, the reverse
  # for py pro go). The legacy path keeps the reference's answer; v1
  # google/google takes the Googlebot group, as Google's common-crawlers
  # page lists it (ROBO-fbbmvbob).
  body <- lc_catalog("grp-googlebot-image-fallback")
  lc_expect(body, "/x", "allow", token = "Googlebot-Image", v1 = "disallow")
  lc_expect(body, "/y", "disallow", token = "Googlebot-Image", v1 = "allow")
})

test_that("class 12: Google cuts a file's User-agent value", {
  # The value keeps its leading run of [A-Za-z_-] (ExtractUserAgent).
  # Googlebot/2.1: reference disallow; py pro go rs rtx spb allow.
  lc_expect(lc_catalog("grp-token-version-in-file"), "/x", "disallow",
            token = "Googlebot")
  # Foo Bot: as Foo, reference disallow; py pro rs js rtx spb allow.
  # As FooBot, reference allow; go disallow.
  body <- lc_catalog("grp-user-agent-with-space")
  lc_expect(body, "/x", "disallow", token = "Foo")
  lc_expect(body, "/x", "allow", token = "FooBot")
  # Bot2: as Bot2, reference allow; every library disallows. As Bot,
  # reference disallow; every library but jv allows.
  body <- lc_catalog("grp-digit-in-token")
  lc_expect(body, "/x", "allow", token = "Bot2")
  lc_expect(body, "/x", "disallow", token = "Bot")
})

test_that("class 13: escapes compared octet for octet", {
  # A reserved %2F: reference allow; py rtx spb disallow (they decode it).
  lc_expect(lc_catalog("esc-pct2f-rule-slash-url"), "/a/b", "allow")
  lc_expect(lc_catalog("esc-slash-rule-pct2f-url"), "/a%2Fb", "allow")
  body <- lc_fixture("esc-query-slash") # Disallow: /p?q=a%2Fb
  lc_expect(body, "/p?q=a/b", "allow")
  lc_expect(body, "/p?q=a%2Fb", "disallow") # every library disallows
  # An unreserved %7E: reference allow; py pro jv rtx spb disallow.
  lc_expect(lc_catalog("esc-pct7e-rule-tilde-url"), "/~joe", "allow")
  body <- lc_catalog("esc-tilde-rule-pct7e-url")
  lc_expect(body, "/%7Ejoe", "allow")
  lc_expect(body, "/%7ejoe", "allow")
  # An upper-case rule escape, a lower-case URL escape: reference allow;
  # py pro jv js rtx spb disallow.
  lc_expect(lc_fixture("esc-upper-rule"), "/a%3cb", "allow")
})

test_that("class 14: a lower-case escape in a rule (every library differs)", {
  body <- lc_catalog("esc-lower-hex-rule")
  # Reference allow (rule upper-cased, URL not, ROBO-kormmfyg); every
  # library disallows.
  lc_expect(body, "/a%3cb", "allow")
  # Reference disallow; go rs allow (no upper-casing of the rule).
  lc_expect(body, "/a%3Cb", "disallow")
})

test_that("class 15: raw non-ASCII in the URL or the rule", {
  # A raw URL is not escaped by the matcher: reference allow; every library
  # disallows (each escapes the URL first).
  lc_expect(lc_catalog("enc-escaped-rule-raw-url"), "/café", "allow")
  body <- lc_catalog("enc-nonascii-rule-raw-url")
  lc_expect(body, "/café", "allow") # every library but go disallows
  lc_expect(body, "/caf%C3%A9", "disallow") # go allow (rule not escaped)
})

test_that("class 16: a raw space in a rule (every library differs)", {
  body <- lc_catalog("esc-space-in-rule")
  lc_expect(body, "/a%20b", "allow") # every library disallows
  lc_expect(body, "/a", "allow") # go disallow
})

test_that("class 17: a line past the buffer (every library differs)", {
  body <- lc_catalog("size-long-line")
  # Reference disallow (the line is cut, the rule shortened); every library
  # allows.
  lc_expect(body, lc_catalog_path("size-long-line"), "disallow")
  lc_expect(body, "/a", "allow") # every library allows
})

test_that("class 18: lone CR line endings", {
  lc_expect(lc_fixture("cr-only"), "/x", "disallow") # rtx spb allow
  body <- lc_catalog("blank-cr-only")
  lc_expect(body, "/a", "disallow") # rtx spb allow
  lc_expect(body, "/b", "disallow") # rtx spb allow
  body <- lc_catalog("blank-mixed-endings")
  lc_expect(body, "/a", "disallow") # rtx spb allow
  lc_expect(body, "/b", "disallow") # rtx spb allow
})

test_that("class 19: a rule before the first User-agent", {
  body <- lc_fixture("rule-before-agent")
  # Reference allow; rtx spb disallow (the rule joins `*`); go ERR.
  lc_expect(body, "/x", "allow")
  lc_expect(body, "/y", "disallow") # go ERR; others disallow
})

test_that("class 20: the query as the URL parser rewrites it", {
  # A bare `?`: reference disallow; go js allow (the `?` is dropped).
  lc_expect(lc_fixture("q-empty"), "/p?", "disallow")
  # An apostrophe: reference disallow; rs js allow (escaped to %27).
  lc_expect(lc_fixture("q-apostrophe"), "/p?a='x'", "disallow")
  # A double quote: reference disallow; jv allow.
  lc_expect(lc_fixture("q-quote"), "/p?a=\"x\"", "disallow")
  # `=` in the path part of a pattern: reference disallow; py allow (it
  # escapes the rule's `=` but not the URL's).
  lc_expect(lc_fixture("q-equals"), "/a?sort=1", "disallow")
  # Controls: every library agrees.
  body <- lc_fixture("q-star") # Disallow: /*?
  lc_expect(body, "/p?x=1", "disallow")
  lc_expect(body, "/p", "allow")
  lc_expect(lc_fixture("q-literal"), "/search?q=a", "disallow")
  # Disallow: /p$ ends at the path; a query follows it.
  lc_expect(lc_fixture("q-dollar"), "/p?x=1", "allow")
})

test_that("class 21: a dot segment in the path", {
  # Reference disallow; rs js allow (the URL parser removes `/.`).
  lc_expect(lc_fixture("dot-segment"), "/a/./b", "disallow")
})

test_that("class 22: Allow: /index.html also allows the directory", {
  body <- lc_fixture("index-html")
  # Reference allow; py go rs js rtx spb disallow; pro jv allow.
  lc_expect(body, "/", "allow")
  lc_expect(body, "/x", "disallow") # every library disallows
})

test_that("class 23: lines go's tokenizer reads differently", {
  body <- lc_catalog("cmt-hash-in-rule")
  lc_expect(body, "/a", "disallow") # go allow (`#` kept in the value)
  lc_expect(body, "/abc", "disallow") # go allow
  lc_expect(lc_catalog("oth-space-before-colon"), "/a",
            "disallow") # go allow
})

test_that("class 24: UTF-16 bodies", {
  # Reference allow on all three. jv disallow on the two with a BOM (it
  # decodes them); rtx spb disallow on all three (the runner drops NULs).
  lc_expect(lc_catalog("enc-utf16le-bom"), "/a", "allow")
  lc_expect(lc_catalog("enc-utf16be-bom"), "/a", "allow")
  # robotstxtr ends each line at its first NUL, as the reference does, so it
  # allows too (ROBO-pvqrfvol; it dropped the NULs and disallowed before).
  lc_expect(lc_catalog("enc-utf16le-no-bom"), "/a", "allow")
})

test_that("class 25: a Latin-1 byte in a rule", {
  body <- lc_catalog("enc-latin1-rule")
  lc_expect(body, "/caf%E9", "disallow") # go rs jv js allow; pro ERR
  lc_expect(body, "/caf%C3%A9", "allow") # pro ERR; others allow
})

test_that("errors: the inputs a library refuses", {
  # A `*` token: reference disallow; jv ERR (IllegalArgumentException,
  # robotNames may not hold `*`); others disallow.
  lc_expect(lc_fixture("err-star-token"), "/x", "disallow", token = "*")
  # A non-numeric Crawl-delay: reference disallow; go ERR (the whole parse
  # fails); others disallow.
  lc_expect(lc_fixture("err-crawl-delay-text"), "/x", "disallow")
  # A line with an empty field name first: reference disallow; rtx ERR
  # ("'names' attribute [2] must be the same length as the vector [0]");
  # spb and the others disallow.
  lc_expect(lc_fixture("err-empty-field"), "/x", "disallow")
})
