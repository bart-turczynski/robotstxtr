# ROBO-fbbmvbob: Google crawler tokens on the v1 `google` ruleset with the
# `google` matcher backend.
#
# A crawler that Google's common-crawlers page lists with a parent token
# (Googlebot-Image -> Googlebot) obeys its own group, else its parent's,
# else `*`; the groups are never merged. AdsBot-Google, AdsBot-Google-Mobile,
# Mediapartners-Google and APIs-Google ignore `*` (special-case crawlers).
# `group_token` records whose group decided. The table is
# google_crawler_tokens_v1() (design/engine-profiles.md section 5a). Before
# this layer the binding read the caller's one token, so Googlebot-Image
# with only a Googlebot group obeyed `*`, and AdsBot-Google obeyed a
# `*`-only body; the legacy functions still do, pinned below and in
# test-token-fallback-mxsphtoo.R.

ct_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

ct_parent_and_star <- function(parent = "Googlebot") {
  ct_lines(
    paste("User-agent:", parent),
    "Disallow: /g/",
    "",
    "User-agent: *",
    "Disallow: /s/"
  )
}

ct_star_only <- ct_lines("User-agent: *", "Disallow: /")

ct_gs_urls <- c("https://x.com/g/a.jpg", "https://x.com/s/a.jpg")

ct_eval <- function(body, url, token, ruleset = "google",
                    backend = "google") {
  robots_evaluate_text_v1(
    body, url,
    robots_product_token = token,
    robots_policy_ruleset = ruleset,
    matcher_backend = backend
  )$results
}

ct_children <- c(
  `Googlebot-Image` = "Googlebot",
  `Googlebot-Video` = "Googlebot",
  `Googlebot-News` = "Googlebot",
  `Google-InspectionTool` = "Googlebot",
  `Google-CloudVertexBot` = "Googlebot",
  `GoogleOther-Image` = "GoogleOther",
  `GoogleOther-Video` = "GoogleOther"
)

ct_ignore_star <- c(
  "AdsBot-Google", "AdsBot-Google-Mobile", "Mediapartners-Google",
  "APIs-Google"
)

test_that("the token table is the seven children and the AdsBot family", {
  table <- google_crawler_tokens_v1()
  expect_identical(
    table$crawler_token, c(names(ct_children), ct_ignore_star)
  )
  expect_identical(
    table$parent_token,
    c(unname(ct_children), rep(NA_character_, 4L))
  )
  expect_identical(
    table$group_selection,
    c(rep("exact_else_parent_else_wildcard", 7L), rep("exact_only", 4L))
  )
  expect_identical(
    unique(table$token_comparison), "ascii_case_insensitive_exact"
  )
  # The retired crawlers are not rows.
  expect_false(any(c("AdsBot-Google-Mobile-Apps", "Googlebot-Favicon") %in%
                     table$crawler_token))
})

test_that("a child with no group of its own follows its parent's group", {
  for (token in names(ct_children)) {
    parent <- ct_children[[token]]
    r <- ct_eval(ct_parent_and_star(parent), ct_gs_urls, token)
    expect_identical(r$url_decision, c("disallow", "allow"), label = token)
    expect_identical(r$matched_line, c(2L, NA_integer_), label = token)
    expect_identical(
      r$reason, c("rule_disallow", "default_allow"), label = token
    )
    expect_identical(r$group_token, c(parent, parent), label = token)
  }
})

test_that("an own group wins over the parent's, never merged", {
  body <- ct_lines(
    "User-agent: Googlebot",
    "Disallow: /g/",
    "",
    "User-agent: Googlebot-Image",
    "Disallow: /i/",
    "",
    "User-agent: *",
    "Disallow: /s/"
  )
  urls <- c(ct_gs_urls, "https://x.com/i/a.jpg")
  r <- ct_eval(body, urls, "Googlebot-Image")
  expect_identical(r$url_decision, c("allow", "allow", "disallow"))
  expect_identical(r$matched_line, c(NA_integer_, NA_integer_, 5L))
  expect_identical(r$group_token, rep("Googlebot-Image", 3L))
})

test_that("an own group with no matching rule keeps the parent out", {
  body <- ct_lines(
    "User-agent: Googlebot-Image",
    "Allow: /nothing",
    "",
    "User-agent: Googlebot",
    "Disallow: /"
  )
  r <- ct_eval(body, "https://x.com/x", "Googlebot-Image")
  expect_identical(r$url_decision, "allow")
  expect_identical(r$reason, "default_allow")
  expect_identical(r$group_token, "Googlebot-Image")
})

test_that("no own and no parent group falls back to *", {
  r <- ct_eval(ct_parent_and_star("Googlebot"), ct_gs_urls, "Storebot-Google")
  expect_identical(r$url_decision, c("allow", "disallow"))
  expect_identical(r$group_token, c("*", "*"))
  r <- ct_eval(ct_star_only, "https://x.com/a", "Googlebot-Image")
  expect_identical(r$url_decision, "disallow")
  expect_identical(r$matched_line, 2L)
  expect_identical(r$group_token, "*")
  # A token with its own group reports itself, as the caller spelled it.
  r <- ct_eval(ct_parent_and_star("Googlebot"), ct_gs_urls, "googlebot")
  expect_identical(r$url_decision, c("disallow", "allow"))
  expect_identical(r$group_token, c("googlebot", "googlebot"))
  # An empty body: no specific group, so `*`.
  r <- ct_eval("", "https://x.com/a", "Googlebot-Image")
  expect_identical(r$url_decision, "allow")
  expect_identical(r$group_token, "*")
})

test_that("the AdsBot family ignores * and reports no * line", {
  for (token in ct_ignore_star) {
    r <- ct_eval(ct_star_only, "https://x.com/page", token)
    expect_identical(r$url_decision, "allow", label = token)
    expect_identical(r$reason, "default_allow", label = token)
    expect_identical(r$matched_line, NA_integer_, label = token)
    expect_identical(r$matched_rule_type, "none", label = token)
    expect_identical(r$matched_rule_value, NA_character_, label = token)
    expect_identical(r$group_token, NA_character_, label = token)
  }
  # An Allow in `*` is not reported either.
  r <- ct_eval(
    ct_lines("User-agent: *", "Allow: /page"), "https://x.com/page",
    "AdsBot-Google"
  )
  expect_identical(r$reason, "default_allow")
  expect_identical(r$matched_line, NA_integer_)
})

test_that("an AdsBot crawler with its own group obeys only that group", {
  body <- ct_lines(
    "User-agent: *",
    "Disallow: /",
    "",
    "User-agent: AdsBot-Google",
    "Disallow: /a/"
  )
  urls <- c("https://x.com/a/x", "https://x.com/b")
  r <- ct_eval(body, urls, "AdsBot-Google")
  expect_identical(r$url_decision, c("disallow", "allow"))
  expect_identical(r$matched_line, c(5L, NA_integer_))
  expect_identical(r$reason, c("rule_disallow", "default_allow"))
  expect_identical(r$group_token, c("AdsBot-Google", "AdsBot-Google"))
  # The plain matcher answers the same with an own group.
  legacy <- allowed_by_robots_text(body, urls, "AdsBot-Google")$results
  expect_identical(legacy$allowed, c(FALSE, TRUE))
  expect_identical(legacy$matched_line, c(5L, NA_integer_))
})

test_that("the token matches whole and ASCII case-insensitively", {
  r <- ct_eval(ct_parent_and_star(), ct_gs_urls, "googlebot-IMAGE")
  expect_identical(r$url_decision, c("disallow", "allow"))
  expect_identical(r$group_token, c("Googlebot", "Googlebot"))
  r <- ct_eval(ct_star_only, "https://x.com/page", "ADSBOT-GOOGLE")
  expect_identical(r$url_decision, "allow")
  for (token in c("Googlebot-Imagex", "Googlebot-Image/1.0",
                  "Googlebot Image", "Googlebot-Imag")) {
    r <- ct_eval(ct_parent_and_star(), ct_gs_urls, token)
    expect_identical(r$url_decision, c("allow", "disallow"), label = token)
    expect_identical(r$group_token, c("*", "*"), label = token)
  }
  r <- ct_eval(ct_star_only, "https://x.com/page", "AdsBot-Google-Mobilex")
  expect_identical(r$url_decision, "disallow")
  # A byte outside ASCII matches no row, and is not an error.
  bad <- rawToChar(c(charToRaw("Googlebot-"), as.raw(0xff), charToRaw("Image")))
  r <- ct_eval(ct_parent_and_star(), ct_gs_urls, bad)
  expect_identical(r$url_decision, c("allow", "disallow"))
})

test_that("the legacy functions keep the single-token answer", {
  x <- allowed_by_robots_text(ct_parent_and_star(), ct_gs_urls,
                              "Googlebot-Image")
  expect_identical(x$results$allowed, c(TRUE, FALSE))
  expect_false("group_token" %in% names(x$results))
  x <- allowed_by_robots_text(ct_star_only, "https://x.com/page",
                              "AdsBot-Google")
  expect_false(x$results$allowed)
  expect_identical(x$results$matched_line, 2L)
})

test_that("only the google ruleset with the google backend is layered", {
  for (ruleset in c("rfc9309", "assumed_rfc9309", "bing", "yandex")) {
    r <- ct_eval(ct_parent_and_star(), ct_gs_urls, "Googlebot-Image",
                 ruleset = ruleset)
    expect_identical(r$url_decision, c("allow", "disallow"), label = ruleset)
    expect_identical(r$group_token, c("*", "*"), label = ruleset)
    r <- ct_eval(ct_star_only, "https://x.com/page", "AdsBot-Google",
                 ruleset = ruleset)
    expect_identical(r$url_decision, "disallow", label = ruleset)
    expect_identical(r$group_token, "*", label = ruleset)
  }
})

test_that("rows no Google adapter decided carry group_token NA", {
  r <- ct_eval(ct_star_only, "https://x.com/page", "Yandex",
               ruleset = "yandex", backend = "yandex")
  expect_identical(r$matcher_status, "evaluated")
  expect_identical(r$group_token, NA_character_)
  r <- ct_eval(ct_star_only, "https://x.com/page", "bingbot",
               ruleset = "bing", backend = "bing")
  expect_identical(r$matcher_status, "evaluated")
  expect_identical(r$group_token, NA_character_)
  r <- ct_eval(ct_star_only, c("", "https://x.com/page"), "Googlebot-Image",
               backend = "rfc9309")
  expect_identical(
    r$matcher_status, c("not_evaluated", "capability_unavailable")
  )
  expect_identical(r$group_token, c(NA_character_, NA_character_))
})

test_that("the legacy adapter carries the crawler answer, not group_token", {
  engine <- robots_evaluate_text_v1(
    ct_parent_and_star(), ct_gs_urls,
    robots_product_token = "Googlebot-Image",
    robots_policy_ruleset = "google", matcher_backend = "google"
  )
  legacy <- as_legacy_robots_decisions_v1(engine)
  expect_identical(legacy$results$allowed, c(FALSE, TRUE))
  expect_false("group_token" %in% names(legacy$results))
  # allowed_by_robots_text() on the same inputs answers otherwise.
  expect_identical(
    allowed_by_robots_text(
      ct_parent_and_star(), ct_gs_urls, "Googlebot-Image"
    )$results$allowed,
    c(TRUE, FALSE)
  )
})

test_that("group_token sits just before matched_rule_value_raw", {
  r <- ct_eval(ct_star_only, "https://x.com/page", "Googlebot-Image")
  k <- match("group_token", names(r))
  expect_identical(names(r)[k - 1L], "error_message")
  expect_identical(names(r)[k + 1L], "matched_rule_value_raw")
  expect_identical(k + 1L, ncol(r))
})

test_that("the window applies before the layer", {
  head <- ct_lines("User-agent: *", "Disallow: /s/")
  filler <- strrep("#", 512000L - nchar(head) + 100L)
  body <- paste0(head, filler, "\n", ct_lines("User-agent: Googlebot",
                                              "Disallow: /g/"))
  r <- ct_eval(body, ct_gs_urls, "Googlebot-Image")
  expect_identical(r$url_decision, c("allow", "disallow"))
  expect_identical(r$group_token, c("*", "*"))
  expect_true(all(r$matcher_body_truncated))
})

test_that("a User-agent line ends at its first NUL before the layer", {
  body <- c(
    charToRaw("User-agent: Googlebot-Image"), as.raw(0L),
    charToRaw("x\nDisallow: /i/\n\nUser-agent: Googlebot\nDisallow: /g/\n")
  )
  r <- ct_eval(rawToChar(body[body != as.raw(0L)]), "https://x.com/i/a",
               "Googlebot-Image")
  # Without the NUL the value reads `Googlebot-Imagex`: the parent decides.
  expect_identical(r$group_token, "Googlebot")
  expect_identical(r$url_decision, "allow")
  urls <- c("https://x.com/i/a", "https://x.com/g/a")
  r <- evaluate_rows_v1(
    urls, rep("Googlebot-Image", 2L), rep("google", 2L), rep("google", 2L),
    rep("supplied", 2L), supplied_evidence_v1(body, "supplied"),
    rep(TRUE, 2L), rep(TRUE, 2L), NA_character_, NA_real_, NA_integer_, NA,
    NA_character_
  )
  expect_identical(r$group_token, rep("Googlebot-Image", 2L))
  expect_identical(r$url_decision, c("disallow", "allow"))
})

# Mixed crawler and plain rows sharing bodies, through the batch adapter
# and the row oracle.
ct_batch_rows <- function() {
  bodies <- lapply(
    list(
      ct_parent_and_star(), ct_star_only,
      ct_lines("User-agent: AdsBot-Google", "Disallow: /a/", "",
               "User-agent: *", "Disallow: /"),
      ct_lines("User-agent: Googlebot-Image", "Allow: /nothing", "",
               "User-agent: Googlebot", "Disallow: /"),
      ""
    ),
    charToRaw
  )
  tokens <- c(
    "Googlebot-Image", "googlebot-news", "Googlebot", "Storebot-Google",
    "AdsBot-Google", "mediapartners-google", "GoogleOther-Video", "FooBot"
  )
  urls <- c("https://x.com/g/a", "https://x.com/s/a", "https://x.com/a/b",
            "https://x.com/b")
  g <- expand.grid(
    body = seq_along(bodies), token = seq_along(tokens), url = seq_along(urls)
  )
  list(
    bodies = bodies[g$body], tokens = tokens[g$token], urls = urls[g$url],
    n_bodies = length(bodies)
  )
}

test_that("the batch adapter equals the row oracle on crawler rows", {
  g <- ct_batch_rows()
  for (layered in c(TRUE, FALSE)) {
    profiles <- google_crawler_profiles_v1(
      g$tokens, rep(layered, length(g$tokens))
    )
    batch <- match_google_batch_v1(g$bodies, g$urls, g$tokens,
                                   crawler_profiles = profiles)
    expect_identical(attr(batch, "n_parse_calls"), g$n_bodies)
    attr(batch, "n_parse_calls") <- NULL
    oracle <- row_matcher_frame_v1(
      match_google_v1, g$bodies, g$urls, g$tokens, profiles
    )
    expect_identical(batch, oracle, label = paste("layered", layered))
    if (layered) {
      expect_setequal(
        unique(batch$group_token),
        c("Googlebot", "*", NA, "Googlebot-Image", "AdsBot-Google")
      )
    } else {
      expect_false(anyNA(batch$group_token))
    }
  }
})

test_that("the evaluator's batch path equals its row path", {
  g <- ct_batch_rows()
  body <- rawToChar(g$bodies[[1L]])
  urls <- unique(g$urls)
  tokens <- unique(g$tokens)
  grid <- expand.grid(url = urls, token = tokens, stringsAsFactors = FALSE)
  rows <- robots_evaluate_text_v1(
    body, grid$url,
    robots_product_token = grid$token,
    robots_policy_ruleset = "google", matcher_backend = "google"
  )$results
  row_registry <- fake_matcher_registry(
    google = function(bodies, urls, product_tokens, crawler_profiles) {
      row_matcher_frame_v1(
        match_google_v1, bodies, urls, product_tokens, crawler_profiles
      )
    }
  )
  local_matcher_registry(row_registry)
  oracle <- robots_evaluate_text_v1(
    body, grid$url,
    robots_product_token = grid$token,
    robots_policy_ruleset = "google", matcher_backend = "google"
  )$results
  expect_identical(rows, oracle)
})

test_that("crawler profiles go by the callable's formals, not its name", {
  # A three-argument Google fake is called as before, and its rows carry
  # no group.
  three <- fake_matcher_registry(google = fake_row_adapter(match_google_v1))
  r <- evaluate_supplied_rows(
    ct_star_only, "https://x.com/page", "AdsBot-Google", "google", "google",
    three
  )
  expect_identical(r$url_decision, "disallow")
  expect_identical(r$group_token, NA_character_)

  # A Yandex entry whose callable names `crawler_profiles` receives them:
  # the dispatch reads the entry, so the backend's name decides nothing.
  calls <- new.env()
  recording <- function(bodies, urls, product_tokens, crawler_profiles) {
    calls$profiles <- crawler_profiles
    fake_decision_frame(urls)
  }
  r <- evaluate_supplied_rows(
    ct_star_only, "https://x.com/page", "Googlebot-Image", "google", "yandex",
    fake_matcher_registry(yandex = recording)
  )
  expect_identical(r$matcher_status, "evaluated")
  # Not the google backend, so the profile is empty, but it was passed.
  expect_identical(calls$profiles$parent_token, NA_character_)
  expect_false(calls$profiles$ignore_global)

  # The real Google adapter receives the resolved profile.
  calls <- new.env()
  spy <- function(bodies, urls, product_tokens, crawler_profiles) {
    calls$profiles <- crawler_profiles
    match_google_batch_v1(bodies, urls, product_tokens, crawler_profiles)
  }
  evaluate_supplied_rows(
    ct_star_only, rep("https://x.com/page", 2L),
    c("Googlebot-Image", "AdsBot-Google"), "google", "google",
    fake_matcher_registry(google = spy)
  )
  expect_identical(calls$profiles$parent_token, c("Googlebot", NA))
  expect_identical(calls$profiles$ignore_global, c(FALSE, TRUE))
})
