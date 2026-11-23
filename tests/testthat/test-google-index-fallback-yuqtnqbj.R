# Google's index.htm Allow fallback (ROBO-yuqtnqbj).
#
# RobotsMatcher::HandleAllow() (src/robots.cc, upstream google/robotstxt at
# 22b355ff855419e6a3ff8ff09c0ad7fdb17116f9): an Allow pattern that does not
# match the path is retried as `<pattern up to its last "/">$`, on the same
# line, when the pattern from that last "/" starts with "/index.htm". The
# test is case-sensitive and takes any suffix (index.htmXYZ, index.html.bak,
# index.htm?x=1); the last "/" is searched over the whole pattern, query
# included. HandleDisallow() has no such branch.
#
# The `index` family of fixtures/google-fidelity-deehqhlc/cases.R carries the
# pristine reference's decision and line for each case, and
# test-google-fidelity-deehqhlc.R pins every entry point against them. This
# file pins what those rows do not hold: which rule robotstxtr reports for a
# fallback match, and the local Bing and Yandex backends on the same bodies.
# design/library-comparison.md class 22 describes the effect.

source(
  test_path("fixtures", "google-fidelity-deehqhlc", "cases.R"), local = TRUE
)

idx_cases <- Filter(function(case) identical(case$family, "index"), gf_cases())
names(idx_cases) <- vapply(idx_cases, `[[`, character(1L), "id")

# The rule on a case's line `line` (0: none): list(type, value, line).
idx_rule_on_line <- function(case, line) {
  if (line == 0L) {
    return(list(type = "none", value = NA_character_, line = NA_integer_))
  }
  text <- strsplit(rawToChar(case$body), "\n", fixed = TRUE)[[1L]][[line]]
  key <- sub(":.*$", "", text)
  list(
    type = c(Allow = "allow", Disallow = "disallow")[[key]],
    value = sub("^[^:]*:[[:space:]]*", "", text),
    line = as.integer(line)
  )
}

# The matched rule on each Google entry point: list of list(type, value,
# line), named by path.
idx_google_rules <- function(case) {
  body <- rawToChar(case$body)
  from_v1 <- function(r) {
    list(type = r$matched_rule_type, value = r$matched_rule_value,
         line = r$matched_line)
  }
  from_legacy <- function(x) {
    r <- x$results
    list(type = r$matched_rule_type, value = r$matched_rule_value,
         line = r$matched_line)
  }
  list(
    v1_text = from_v1(robots_evaluate_text_v1(
      body, case$url, case$token, "google", "google"
    )$results),
    v1_url = from_v1(gf_with_body(case$body, robots_evaluate_url_v1(
      case$url, case$token, "google", "google"
    ))$results),
    text = from_legacy(allowed_by_robots_text(body, case$url, case$token)),
    url = from_legacy(gf_with_body(
      case$body, allowed_by_robots_url(case$url, case$token)
    ))
  )
}

# A case's v1 row on one backend, under the ruleset of the same name.
idx_v1 <- function(case, backend = "google", token = case$token) {
  robots_evaluate_text_v1(
    rawToChar(case$body), case$url, token, backend, backend
  )$results
}

test_that("ROBO-yuqtnqbj: the index family keeps its boundary cases", {
  expect_true(all(c(
    "idx-htm", "idx-html", "idx-htm-suffix", "idx-html-bak", "idx-htm-query",
    "idx-htm-dollar", "idx-htm-pct2f", "idx-upper", "idx-short",
    "idx-htm-child", "idx-html-dir-query", "idx-html-neighbor",
    "idx-priority-beats", "idx-priority-loses", "idx-disallow-asymmetry",
    "idx-query-slash-target", "idx-query-slash-not-dir",
    "idx-query-slash-blocks", "idx-query-no-slash", "idx-direct", "idx-root",
    "idx-nested", "idx-nested-parent", "idx-trailing-slash",
    "idx-query-index-twice", "idx-html-dir-empty-query",
    "idx-htm-suffix-dir-query", "idx-htm-suffix-neighbor"
  ) %in% names(idx_cases)))
  # The per-entry-point pins against the reference's answers live in
  # test-google-fidelity-deehqhlc.R.
})

test_that("ROBO-yuqtnqbj: a fallback match reports the Allow as written", {
  # The reference's matching_line() is the original Allow's line; robotstxtr
  # reports that line and the pattern on it (`/d/index.htmXYZ`), never the
  # retried `/d/$`. Every other row reports the rule on the reference's line.
  for (case in idx_cases) {
    want <- idx_rule_on_line(case, case$ref_line)
    got <- idx_google_rules(case)
    for (path in names(got)) {
      label <- paste(case$id, path)
      expect_identical(got[[path]]$type, want$type, label = label)
      expect_identical(got[[path]]$value, want$value, label = label)
      expect_identical(got[[path]]$line, want$line, label = label)
    }
    # The matcher's own line, before robotstxtr's restatement.
    expect_identical(
      robotstxtr_matching_line_text_(rawToChar(case$body), case$url,
                                     case$token),
      case$ref_line, label = case$id
    )
  }
  r <- robots_evaluate_text_v1(
    "User-agent: *\nDisallow: /\nAllow: /d/index.htmXYZ\n",
    "https://example.com/d/", "FooBot", "google", "google"
  )$results
  expect_identical(r$url_decision, "allow")
  expect_identical(r$reason, "rule_allow")
  expect_identical(r$matched_line, 3L)
  expect_identical(r$matched_rule_value, "/d/index.htmXYZ")
})

test_that("ROBO-yuqtnqbj: the retried pattern is end-anchored", {
  # `/d/$` matches the directory alone: its neighbors, and the directory
  # with a query or an empty query, keep `Disallow: /`.
  for (id in c("idx-html-dir-query", "idx-html-neighbor",
               "idx-htm-suffix-dir-query", "idx-htm-suffix-neighbor",
               "idx-html-dir-empty-query", "idx-nested-parent")) {
    r <- idx_v1(idx_cases[[id]])
    expect_identical(r$url_decision, "disallow", label = id)
    expect_identical(r$matched_rule_value, "/", label = id)
  }
})

test_that("ROBO-yuqtnqbj: Bing and Yandex have no index.htm fallback", {
  # Local-backend predictions, not vendor observations: robotstxtbing 0.1.0
  # (payload c82855d0) and robotstxtyandex 0.2.0 (payload fdd60a7), as
  # inst/vendor/*/MANIFEST.dcf pin them. Where Google opens the directory by
  # the fallback, both keep the longest Disallow (line 2). ROBO-traxexwm
  # holds the webmaster-tool checks that may revise this.
  fallback <- c(
    "idx-htm", "idx-html", "idx-htm-suffix", "idx-html-bak", "idx-htm-query",
    "idx-htm-dollar", "idx-htm-pct2f", "idx-priority-beats",
    "idx-query-slash-target", "idx-query-no-slash", "idx-query-index-twice",
    "idx-root", "idx-nested"
  )
  same <- c("idx-direct", "idx-disallow-asymmetry", "idx-upper",
            "idx-html-neighbor", "idx-priority-loses")
  backends <- c(bing = "bingbot", yandex = "Yandex")
  for (backend in names(backends)) {
    for (id in fallback) {
      case <- idx_cases[[id]]
      label <- paste(backend, id)
      expect_identical(idx_v1(case)$url_decision, "allow", label = label)
      r <- idx_v1(case, backend, backends[[backend]])
      want <- idx_rule_on_line(case, 2L)
      expect_identical(r$url_decision, "disallow", label = label)
      expect_identical(r$matched_line, 2L, label = label)
      expect_identical(r$matched_rule_value, want$value, label = label)
    }
    # Where Google needs no fallback, the three agree.
    for (id in same) {
      case <- idx_cases[[id]]
      label <- paste(backend, id)
      google <- idx_v1(case)
      r <- idx_v1(case, backend, backends[[backend]])
      expect_identical(r$url_decision, google$url_decision, label = label)
      expect_identical(r$matched_line, google$matched_line, label = label)
    }
  }
})
