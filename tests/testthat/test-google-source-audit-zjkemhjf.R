# The Google source audit (ROBO-zjkemhjf, ROBO-vxmeoqcr): the Bing and Yandex
# backends on the families it added to the Google fidelity fixtures.
#
# design/google-source-audit.md is the findings record. The fixtures, and the
# pristine google/robotstxt answer to each, are the `colon`, `whitespace`,
# `truncation`, `userinfo` and `priority` families of
# fixtures/google-fidelity-deehqhlc/cases.R; test-google-fidelity-deehqhlc.R
# pins the google backend against them. These tests pin what the vendored
# Bing and Yandex backends return on the same bodies today, with their own
# ruleset and the tokens the scratch comparison used (`bingbot`, `Yandex`).
# They record current behavior, not a claim about either crawler: a
# deliberate backend correction (ROBO-traxexwm, ROBO-oxfpgdrx) updates them.
# The scratch run's 44/120 (Bing) and 47/120 (Yandex) differing cases were
# measured over all eleven audited families on 2026-11-18 and are history.
#
# The userinfo rows run under the v1 default url_normalization = "rfc3986",
# which drops "u;v@" first (ADR 0002); the same two URLs under "none" are
# pinned in test-url-preprocessing-bnvdmdjr.R.

source(
  test_path("fixtures", "google-fidelity-deehqhlc", "cases.R"), local = TRUE
)

# `decision` or `decision:line`, per case id; a case missing here is `allow`
# with no line.
gsa_expected <- list(
  bing = c(
    "colon-proper-control" = "disallow:2",
    "userinfo-semicolon" = "disallow:2",
    "userinfo-escaped-semicolon" = "disallow:2",
    "prio-trailing-star-control" = "allow:3",
    "prio-trailing-star" = "disallow:2",
    "prio-trailing-stars" = "disallow:2",
    "prio-stars-tie" = "allow:2",
    "prio-stars-longer" = "disallow:3"
  ),
  yandex = c(
    "colon-proper-control" = "disallow:2",
    "userinfo-semicolon" = "disallow:2",
    "userinfo-escaped-semicolon" = "disallow:2",
    "prio-trailing-star-control" = "allow:3",
    "prio-trailing-star" = "allow:3",
    "prio-trailing-stars" = "allow:3",
    "prio-stars-tie" = "allow:2",
    "prio-stars-longer" = "allow:2"
  )
)
gsa_tokens <- c(bing = "bingbot", yandex = "Yandex")
gsa_families <- c("colon", "whitespace", "truncation", "userinfo", "priority")

gsa_cases <- Filter(function(case) case$family %in% gsa_families, gf_cases())
names(gsa_cases) <- vapply(gsa_cases, `[[`, character(1L), "id")

# One backend's answers on every audited case, as `decision[:line]`.
gsa_answers <- function(backend) {
  vapply(gsa_cases, function(case) {
    r <- robots_evaluate_text_v1(
      gf_body_string(case$body), case$url, gsa_tokens[[backend]], backend,
      backend
    )$results
    if (is.na(r$matched_line)) {
      r$url_decision
    } else {
      paste0(r$url_decision, ":", r$matched_line)
    }
  }, character(1L))
}

gsa_want <- function(backend) {
  want <- rep("allow", length(gsa_cases))
  names(want) <- names(gsa_cases)
  listed <- gsa_expected[[backend]]
  want[names(listed)] <- listed
  want
}

test_that("ROBO-vxmeoqcr: the audited families and their pins line up", {
  expect_setequal(
    unique(vapply(gsa_cases, `[[`, character(1L), "family")), gsa_families
  )
  for (backend in names(gsa_expected)) {
    expect_true(
      all(names(gsa_expected[[backend]]) %in% names(gsa_cases)),
      label = backend
    )
  }
})

test_that("ROBO-vxmeoqcr: the Bing backend's current answers", {
  # Bing reads no rule from a line with no colon, or from a key with more
  # than "Disallow" in it, so it allows everything on the colon, whitespace
  # and truncation bodies but the proper-colon control. It counts a
  # pattern's stars in its priority, as Google does.
  expect_identical(gsa_answers("bing"), gsa_want("bing"))
})

test_that("ROBO-vxmeoqcr: the Yandex backend's current answers", {
  # As Bing on the colon, whitespace and truncation bodies. On priority the
  # Allow wins every pair: "Allow: /p" against "/p*" and "/p**", and
  # "Allow: /abc" against "/a***", where Google and Bing disallow.
  expect_identical(gsa_answers("yandex"), gsa_want("yandex"))
})
