# ROBO-roypaoox: a literal pattern `P` and `P/` of the same type for the same
# crawlers (`rule_slash_pair`), and a crawler whose decision differs between
# the bare URL `P` and the slash URL `P/` of a literal rule `P/`
# (`rule_slash_split`). This first part pins what each shape gets today and
# how every backend decides its two URLs.

sp_diag <- function(body) {
  robots_validate_text(body)$diagnostics
}

sp_codes <- function(body) {
  sp_diag(body)$code
}

# Each fixture: a body (`%s` stands for the crawler token, so the backends
# can read it) and the codes it gets today.
sp_fixtures <- list(
  pair = list(
    body = "User-agent: *\nDisallow: /notes/\nDisallow: /notes\n",
    today = character(0)
  ),
  bare_blocked = list(
    body = "User-agent: %s\nDisallow: /\nAllow: /gallery/\n",
    today = character(0)
  ),
  bare_allowed = list(
    body = "User-agent: *\nDisallow: /notes/\n",
    today = character(0)
  ),
  seven = list(
    body = paste0("User-agent: *\n",
                  paste0("Disallow: /", letters[1:7], "/\n", collapse = "")),
    today = character(0)
  ),
  dollar_silences = list(
    body = paste0("User-agent: %s\nDisallow: /\nAllow: /gallery/\n",
                  "Allow: /gallery$\n"),
    today = character(0)
  ),
  bare_silences = list(
    body = paste0("User-agent: %s\nDisallow: /\nAllow: /gallery/\n",
                  "Allow: /gallery\n"),
    today = character(0)
  ),
  deeper = list(
    body = "User-agent: *\nDisallow: /x/\nAllow: /x/y\n",
    today = character(0)
  ),
  tie = list(
    body = "User-agent: *\nAllow: /x/\nDisallow: /x/\n",
    today = "disallow_tied_by_allow"
  ),
  across_crawlers = list(
    body = "User-agent: *\nDisallow: /x\n\nUser-agent: %s\nDisallow: /x/\n",
    today = "wildcard_disallows_not_inherited"
  ),
  repeated_group = list(
    body = "User-agent: %s\nDisallow: /x/\n\nUser-agent: %s\nDisallow: /x\n",
    today = "user_agent_repeated_group"
  ),
  stacked = list(
    body = paste0("User-agent: %s\nUser-agent: Bar\nDisallow: /x/\n\n",
                  "User-agent: %s\nDisallow: /x\n"),
    today = "user_agent_repeated_group"
  ),
  cut_pair = list(
    body = paste0("User-agent: Foo web\nDisallow: /x\n\n",
                  "User-agent: Foo blog\nDisallow: /x/\n"),
    today = c("user_agent_cut", "user_agent_cut")
  ),
  cut_split_google = list(
    body = paste0("User-agent: Foo web\nDisallow: /\n\n",
                  "User-agent: Foo blog\nAllow: /x/\n"),
    today = c("user_agent_cut", "user_agent_cut")
  ),
  cut_split_uncut = list(
    body = paste0("User-agent: Foo web\nAllow: /x\n\n",
                  "User-agent: Foo blog\nDisallow: /\nAllow: /x/\n"),
    today = c("user_agent_cut", "user_agent_cut")
  ),
  same_value = list(
    body = paste0("User-agent: Foo web\nDisallow: /x\n\n",
                  "User-agent: foo web\nDisallow: /x/\n"),
    today = c("user_agent_cut", "user_agent_cut")
  ),
  triple = list(
    body = "User-agent: *\nDisallow: /x/\nDisallow: /x\nDisallow: /x\n",
    today = "duplicate_rule"
  ),
  pair_and_split = list(
    body = paste0("User-agent: %s\nDisallow: /\nDisallow: /x$\nAllow: /x\n",
                  "Allow: /x/\n"),
    today = character(0)
  ),
  star_key = list(
    body = "User-agent: *\nDisallow: /x*\nDisallow: /x/\n",
    today = character(0)
  ),
  no_google_token = list(
    body = "User-agent: 1bot\nDisallow: /x/\nDisallow: /x\n",
    today = "user_agent_cut"
  ),
  empty = list(
    body = "User-agent: *\nDisallow:\nAllow:\n",
    today = c("allow_all_disallow", "empty_rule_value")
  )
)

sp_body <- function(name, token = "Foo") {
  gsub("%s", token, sp_fixtures[[name]]$body, fixed = TRUE)
}

test_that("ROBO-roypaoox: each fixture's codes today", {
  for (name in names(sp_fixtures)) {
    expect_identical(sp_codes(sp_body(name)), sp_fixtures[[name]]$today,
                     label = name)
  }
})

# Values that are no candidate, alone and as an Allow under `Disallow: /`,
# with the codes each gets today.
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

test_that("ROBO-roypaoox: edge inputs today", {
  # A NUL cuts the second value to `/x/` on Google's reading.
  body <- c(charToRaw("User-agent: *\nDisallow: /x\nDisallow: /x/"),
            as.raw(0), charToRaw("zz\n"))
  expect_identical(sp_codes(body), c("nul_byte", "rule_cut_by_nul"))
  # A latin1 byte and a lone UTF-8 lead byte are escaped in the canonical
  # value.
  for (byte in as.raw(c(0xe9, 0xc3))) {
    body <- c(charToRaw("User-agent: *\nDisallow: /"), byte,
              charToRaw("/\nDisallow: /"), byte, charToRaw("\n"))
    expect_identical(sp_codes(body), c("invalid_utf8", "invalid_utf8"))
  }
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

# Fixture, the two paths and the decisions every backend gives them.
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
  list("pair", c("/notes", "/notes/"), c("disallow", "disallow"))
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

# What the pair row will say: the bare pattern matches every path the slash
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
