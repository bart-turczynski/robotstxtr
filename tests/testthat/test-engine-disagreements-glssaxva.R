# ROBO-glssaxva: the cross-engine disagreement classes. Each test pins, for
# one synthesized body and path, what the google backend says (with the
# Yandex token and with the bingbot token), what the yandex backend says
# (token Yandex) and what the bing backend says (token bingbot). Every row
# goes through robots_evaluate_text_v1() under the google ruleset: a supplied
# body is `use_rules` under every ruleset, so any difference is the backend's.
# Class numbers, verdicts and sources: design/engine-disagreements.md. These
# pin current behavior; no class here is a known bug of ours.

dg_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

# One "decision reason line" string per backend, for one path on example.com.
dg_outcome <- function(body, path) {
  url <- paste0("https://example.com", path)
  run <- function(backend, token) {
    r <- robots_evaluate_text_v1(body, url, token, "google", backend)$results
    paste(r$url_decision, r$reason, r$matched_line)
  }
  c(
    google_yandex = run("google", "Yandex"),
    yandex = run("yandex", "Yandex"),
    google_bingbot = run("google", "bingbot"),
    bing = run("bing", "bingbot")
  )
}

dg_expect <- function(google_yandex, yandex, google_bingbot, bing) {
  c(
    google_yandex = google_yandex, yandex = yandex,
    google_bingbot = google_bingbot, bing = bing
  )
}

dg_disallow <- function(line) paste("disallow rule_disallow", line)
dg_allow_rule <- function(line) paste("allow rule_allow", line)
dg_default <- "allow default_allow NA"

test_that("class 1: a non-rule line ends bingbot's stacked group on bing", {
  # Google reads every line that is not a rule as transparent and merges the
  # next User-agent into bingbot's group; bing seals the group (BING-aosnpswm).
  # yandex keeps stacking, as google does.
  for (directive in c("Crawl-delay: 10", "Sitemap: https://example.com/s.xml",
                      "Host: example.com", "Clean-param: ref /x")) {
    for (gap in c("", "\n")) {
      body <- paste0(
        "User-agent: bingbot\n", directive, "\n", gap,
        "User-agent: *\nDisallow: /private\n"
      )
      line <- if (nzchar(gap)) 5L else 4L
      expect_identical(
        dg_outcome(body, "/private"),
        dg_expect(dg_disallow(line), dg_disallow(line), dg_disallow(line),
                  dg_default),
        info = paste(directive, if (nzchar(gap)) "with blank" else "")
      )
    }
  }
})

test_that("class 1: a comment line does not end the stacked group", {
  body <- dg_lines("User-agent: bingbot", "# note", "User-agent: *",
                   "Disallow: /private")
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_disallow(4), dg_disallow(4), dg_disallow(4), dg_disallow(4))
  )
})

test_that("class 1: bing seals the run at Request-rate and Noindex too", {
  # Both are unknown fields to bing (bing-v2-spec §9.2 knows only user-agent,
  # allow, disallow, sitemap and crawl-delay), so rule 2a applies.
  for (directive in c("Request-rate: 1/5", "Noindex: /x")) {
    body <- dg_lines("User-agent: bingbot", directive, "User-agent: *",
                     "Disallow: /private")
    expect_identical(
      dg_outcome(body, "/private"),
      dg_expect(dg_disallow(4), dg_disallow(4), dg_disallow(4), dg_default),
      info = directive
    )
  }
})

test_that("class 1: yandex keeps a stacked Yandex run across non-rule lines", {
  # The Yandex token's own run: `Other` stacks onto `Yandex`, so line 4
  # applies to Yandex. Foo is an unknown field to yandex, Host too; Crawl-delay,
  # Clean-param and Sitemap are known fields that are not rules.
  for (directive in c("Crawl-delay: 5", "Clean-param: ref /x",
                      "Host: example.com", "Sitemap: https://example.com/s.xml",
                      "Foo: bar", "# note")) {
    body <- dg_lines("User-agent: Yandex", directive, "User-agent: Other",
                     "Disallow: /private")
    expect_identical(
      dg_outcome(body, "/private"),
      dg_expect(dg_disallow(4), dg_disallow(4), dg_default, dg_default),
      info = directive
    )
  }
})

test_that("class 1: a later bingbot group then decides bing's answer", {
  body <- dg_lines(
    "User-agent: bingbot", "Crawl-delay: 1", "User-agent: *",
    "Disallow: /private", "", "User-agent: bingbot", "Allow: /priv"
  )
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_disallow(4), dg_disallow(4), dg_disallow(4),
              dg_allow_rule(7))
  )
  # The same shape the other way round: google allows, bing disallows.
  body <- dg_lines(
    "User-agent: bingbot", "Crawl-delay: 10", "User-agent: *",
    "Allow: /private", "", "User-agent: bingbot", "Disallow: /private"
  )
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_allow_rule(4), dg_allow_rule(4), dg_allow_rule(4),
              dg_disallow(7))
  )
})

test_that("class 1: an unknown field seals a `*` run before a policy token", {
  # The aipref shape (ROBO-kzyfejcv): google and yandex stack
  # `__usage_ai-training` onto `*`, so its Disallow reaches every crawler;
  # bing seals `*` at Content-Signal, an unknown field.
  tail <- c("", "", "User-agent: __usage_ai-training", "Disallow: /")
  body <- dg_lines("User-agent: *", "Content-Signal: ai-train=no",
                   "Sitemap: https://example.com/sitemap.xml", tail)
  expect_identical(
    dg_outcome(body, "/"),
    dg_expect(dg_disallow(7), dg_disallow(7), dg_disallow(7), dg_default)
  )
  # Content-Signal alone seals it on bing.
  body <- dg_lines("User-agent: *", "Content-Signal: ai-train=no", tail)
  expect_identical(
    dg_outcome(body, "/"),
    dg_expect(dg_disallow(6), dg_disallow(6), dg_disallow(6), dg_default)
  )
  # The blank lines alone do not: all four rows stack.
  body <- dg_lines("User-agent: *", tail)
  expect_identical(
    dg_outcome(body, "/"),
    dg_expect(dg_disallow(5), dg_disallow(5), dg_disallow(5), dg_disallow(5))
  )
})

test_that("class 2: a leading BOM hides line 1 from yandex and bing", {
  # Marked "bytes", so the body reaches the matchers as these bytes under any
  # locale; an unmarked "\xef\xbb\xbf" would be re-encoded under LC_ALL=C.
  dg_bom <- function(body) {
    body <- paste0("\xef\xbb\xbf", body)
    Encoding(body) <- "bytes"
    body
  }
  body <- dg_bom(dg_lines("User-agent: *", "Disallow: /private"))
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_disallow(2), dg_default, dg_disallow(2), dg_default)
  )
  # The BOM costs a line only: before a comment, nothing is lost.
  body <- dg_bom(dg_lines("# c", "User-agent: *", "Disallow: /private"))
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_disallow(3), dg_disallow(3), dg_disallow(3), dg_disallow(3))
  )
})

test_that("class 3: a User-agent value with a suffix matches on google only", {
  for (suffix in c("/2.0", " 2.0", "*")) {
    body <- dg_lines(
      paste0("User-agent: bingbot", suffix),
      paste0("User-agent: Yandex", suffix),
      "Disallow: /private"
    )
    expect_identical(
      dg_outcome(body, "/private"),
      dg_expect(dg_disallow(3), dg_default, dg_disallow(3), dg_default),
      info = suffix
    )
  }
  # Google reads the first token of a list; neither engine splits it.
  body <- dg_lines("User-agent: bingbot, Yandex", "Disallow: /private")
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_default, dg_default, dg_disallow(2), dg_default)
  )
})

test_that("class 4: whitespace before the colon voids the line on yandex", {
  for (line in c("Disallow : /private", "Disallow\t: /private")) {
    body <- dg_lines("User-agent: *", line)
    expect_identical(
      dg_outcome(body, "/private"),
      dg_expect(dg_disallow(2), dg_default, dg_disallow(2), dg_disallow(2)),
      info = line
    )
  }
  body <- dg_lines("User-agent : *", "Disallow: /private")
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_disallow(2), dg_default, dg_disallow(2), dg_disallow(2))
  )
})

test_that("class 6: a raw non-ASCII rule is escaped by google only", {
  body <- dg_lines("User-agent: *", "Disallow: /café")
  expect_identical(
    dg_outcome(body, "/caf%C3%A9"),
    dg_expect(dg_disallow(2), dg_default, dg_disallow(2), dg_default)
  )
  # The other way round with a raw URL, which google never escapes.
  expect_identical(
    dg_outcome(body, "/café"),
    dg_expect(dg_default, dg_disallow(2), dg_default, dg_disallow(2))
  )
  # With an escaped Allow beside it, yandex and bing answer from the Allow.
  body <- dg_lines("User-agent: *", "Disallow: /café/",
                   "Allow: /caf%C3%A9")
  expect_identical(
    dg_outcome(body, "/caf%C3%A9/x"),
    dg_expect(dg_disallow(2), dg_allow_rule(3), dg_disallow(2),
              dg_allow_rule(3))
  )
})

test_that("class 7: CR CR LF keeps a CR in every line on yandex and bing", {
  body <- "User-agent: *\r\r\nDisallow: /private\r\r\n"
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_disallow(3), dg_default, dg_disallow(3), dg_default)
  )
  body <- "User-agent: *\nDisallow: /private\r\r\n"
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_disallow(2), dg_default, dg_disallow(2), dg_default)
  )
})

test_that("class 8: lone CR line endings make one line on yandex and bing", {
  body <- "User-agent: *\rDisallow: /private\r"
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_disallow(2), dg_default, dg_disallow(2), dg_default)
  )
  body <- "User-agent: *\rDisallow: /a\nDisallow: /private\n"
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_disallow(3), dg_default, dg_disallow(3), dg_default)
  )
})

test_that("class 10: yandex does not count * or a final $ in rule length", {
  body <- dg_lines("User-agent: *", "Disallow: /page", "Allow: /pag*")
  expect_identical(
    dg_outcome(body, "/page"),
    dg_expect(dg_allow_rule(3), dg_disallow(2), dg_allow_rule(3),
              dg_allow_rule(3))
  )
  body <- dg_lines("User-agent: *", "Allow: /p", "Disallow: /p$")
  expect_identical(
    dg_outcome(body, "/p"),
    dg_expect(dg_disallow(3), dg_allow_rule(2), dg_disallow(3),
              dg_disallow(3))
  )
  # The `*%*` shape: one counted byte ties `Allow: /`, and Allow wins a tie.
  body <- dg_lines("User-agent: *", "Allow: /", "Disallow: *%*")
  expect_identical(
    dg_outcome(body, "/%24"),
    dg_expect(dg_disallow(3), dg_allow_rule(2), dg_disallow(3),
              dg_disallow(3))
  )
})

test_that("class 11: yandex keeps a lower-case escape in a rule as written", {
  body <- dg_lines("User-agent: *", "Disallow: /a%3cb")
  expect_identical(
    dg_outcome(body, "/a%3cb"),
    dg_expect(dg_default, dg_disallow(2), dg_default, dg_default)
  )
  expect_identical(
    dg_outcome(body, "/a%3Cb"),
    dg_expect(dg_disallow(2), dg_default, dg_disallow(2), dg_disallow(2))
  )
})

test_that("class 12: an empty User-agent value ends the group on yandex", {
  body <- dg_lines("User-agent: *", "User-agent:", "Disallow: /private")
  expect_identical(
    dg_outcome(body, "/private"),
    dg_expect(dg_disallow(3), dg_default, dg_disallow(3), dg_disallow(3))
  )
})

test_that("class 13: google reads a key starting with disallow as Disallow", {
  # Google's KeyIsDisallow and KeyIsAllow accept a key by prefix
  # (ROBO-xglcoagv); yandex and bing ignore the unknown field.
  body <- dg_lines("User-agent: *", "DisallowAITraining: /")
  expect_identical(
    dg_outcome(body, "/x"),
    dg_expect(dg_disallow(2), dg_default, dg_disallow(2), dg_default)
  )
  # An Allow-prefixed key: the other way round.
  body <- dg_lines("User-agent: *", "Disallow: /", "AllowAITraining: /x")
  expect_identical(
    dg_outcome(body, "/x"),
    dg_expect(dg_allow_rule(3), dg_disallow(2), dg_allow_rule(3),
              dg_disallow(2))
  )
})

# Class 14 (ROBO-fslaxaep): Google's KeyIsUserAgent accepts any key that
# starts with `user-agent`, or with the typos `useragent` and `user agent`;
# yandex and bing compare the whole field name, so each is an unknown field.
dg_ua_keys <- c("User-agentfoo", "User-agent-x", "USER-AGENTS", "Useragent",
                "Useragents", "User agent")

test_that("class 14: google reads a user-agent-prefixed key as User-agent", {
  for (key in dg_ua_keys) {
    body <- dg_lines(paste0(key, ": *"), "Disallow: /private")
    expect_identical(
      dg_outcome(body, "/private"),
      dg_expect(dg_disallow(2), dg_default, dg_disallow(2), dg_default),
      info = key
    )
  }
})

test_that("class 14: the prefixed key seals bingbot's stacked run on bing", {
  # An unknown field to bing, so rule 2a seals the run (class 1); google
  # stacks it as a User-agent line, and yandex keeps the run across it.
  for (key in dg_ua_keys) {
    body <- dg_lines("User-agent: bingbot", paste0(key, ": x"),
                     "User-agent: *", "Disallow: /private")
    expect_identical(
      dg_outcome(body, "/private"),
      dg_expect(dg_disallow(4), dg_disallow(4), dg_disallow(4), dg_default),
      info = key
    )
  }
})

test_that("class 14: after a rule the prefixed key starts a group on google", {
  # The ydx-parser-user-agent-space shape: google starts an `Other` group, so
  # line 5 leaves the Yandex and bingbot group; yandex and bing keep it there.
  for (key in dg_ua_keys) {
    body <- dg_lines("User-agent: Yandex", "User-agent: bingbot",
                     "Disallow: /a", paste0(key, ": Other"),
                     "Disallow: /private")
    expect_identical(
      dg_outcome(body, "/private"),
      dg_expect(dg_default, dg_disallow(5), dg_default, dg_disallow(5)),
      info = key
    )
  }
})

test_that("class 14: the prefixed key in a stacked Yandex run agrees", {
  # Refuted for the Yandex token: google stacks it, yandex keeps the run.
  for (key in dg_ua_keys) {
    body <- dg_lines("User-agent: Yandex", paste0(key, ": x"),
                     "User-agent: Other", "Disallow: /private")
    expect_identical(
      dg_outcome(body, "/private"),
      dg_expect(dg_disallow(4), dg_disallow(4), dg_default, dg_default),
      info = key
    )
  }
})

test_that("class 14 control: a key starting with sitemap reads as Sitemap", {
  # Refuted: KeyIsSitemap also matches by prefix (and `site-map`), but a
  # Sitemap line and an unknown field read alike on every backend, so each
  # prefixed key answers as the exact `Sitemap` key does in class 1.
  for (key in c("Sitemap", "Sitemapx", "Sitemaps", "Site-map")) {
    value <- paste0(key, ": https://example.com/s.xml")
    body <- dg_lines("User-agent: bingbot", value, "User-agent: *",
                     "Disallow: /private")
    expect_identical(
      dg_outcome(body, "/private"),
      dg_expect(dg_disallow(4), dg_disallow(4), dg_disallow(4), dg_default),
      info = key
    )
    body <- dg_lines("User-agent: Yandex", value, "User-agent: Other",
                     "Disallow: /private")
    expect_identical(
      dg_outcome(body, "/private"),
      dg_expect(dg_disallow(4), dg_disallow(4), dg_default, dg_default),
      info = key
    )
    body <- dg_lines("User-agent: *", value, "Disallow: /private")
    expect_identical(
      dg_outcome(body, "/private"),
      dg_expect(dg_disallow(3), dg_disallow(3), dg_disallow(3),
                dg_disallow(3)),
      info = key
    )
  }
})
