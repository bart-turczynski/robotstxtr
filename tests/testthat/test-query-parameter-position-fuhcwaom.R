# ROBO-fuhcwaom: an Allow or Disallow whose pattern names a query parameter
# right after its first `?` (`/items/*?sort=`). The matchers read `?` as a
# literal byte, so the rule may miss a URL where that parameter follows
# another one (`/items/x?a=1&sort=1`). These pins record today's codes on
# every shape the check will read, before the check exists.

qp_codes <- function(body) {
  robots_validate_text(body)$diagnostics$code
}

qp_one <- function(type, value) {
  qp_codes(paste0("User-agent: *\n", type, ": ", value, "\n"))
}

# One rule line per value, with the codes it gets today.
qp_today <- list(
  "/items/*?sort=" = character(0),
  "/search?page=" = character(0),
  "*?q=" = character(0),
  "/search?page=*&view=list" = character(0),
  "/*?*sort=" = character(0),
  "/items*?" = character(0),
  "/v?$" = character(0),
  "/v?page=2$" = character(0),
  "/p?" = character(0),
  "/items?back=?sort=" = character(0),
  "/p?%C3%A9=1" = character(0),
  "/a/./p?q=" = "rule_dot_segment",
  "/p?q=%" = "rule_invalid_percent_escape"
)

test_that("ROBO-fuhcwaom: today's codes on one query-parameter rule", {
  for (type in c("Allow", "Disallow")) {
    for (value in names(qp_today)) {
      expect_identical(qp_one(type, value), qp_today[[value]],
                       label = paste(type, value))
    }
  }
})

test_that("ROBO-fuhcwaom: today's codes on twins and merged groups", {
  expect_identical(
    qp_codes("User-agent: *\nDisallow: /*?page=\nDisallow: /*&page=\n"),
    character(0)
  )
  expect_identical(
    qp_codes(paste0("User-agent: Foo/1.0\nDisallow: /*?q=\n\n",
                    "User-agent: Foo\nDisallow: /*&q=\n")),
    c("user_agent_cut", "user_agent_repeated_group")
  )
  expect_identical(
    qp_codes("User-agent: *\nDisallow: /p?q=%2b\nDisallow: /p?q=%2B\n"),
    "rule_lowercase_escape_twin"
  )
  expect_identical(
    qp_codes("User-agent: *\nDisallow: /p?q=%2b\nDisallow: /p&q=%2B\n"),
    "rule_lowercase_escape"
  )
  expect_identical(
    qp_codes("User-agent: *\nDisallow: /*?q=\nDisallow: /*?q=\n"),
    "duplicate_rule"
  )
})

# The premise, on google, bing and yandex alike with the v1 default
# `url_normalization = "rfc3986"`: `?` is a literal byte and `*` any run, so
# `/items/*?sort=` matches the control, misses the parameter in a later
# position, and matches where a `*` reaches a later `?`. The rfc9309
# backend is capability_unavailable (ADR 0002), so it is not testable here.
qp_engines <- list(google = "Googlebot", bing = "bingbot", yandex = "Yandex")
qp_urls <- paste0("https://example.com/items/x?",
                  c("sort=1", "a=1&sort=1", "a=?sort=1"))

test_that("ROBO-fuhcwaom: the matchers read `?` as a literal byte", {
  for (backend in names(qp_engines)) {
    disallow <- robots_evaluate_text_v1(
      "User-agent: *\nDisallow: /items/*?sort=\n", qp_urls,
      qp_engines[[backend]], backend, backend
    )$results
    expect_identical(disallow$url_decision,
                     c("disallow", "allow", "disallow"), label = backend)
    allow <- robots_evaluate_text_v1(
      "User-agent: *\nDisallow: /\nAllow: /items/*?sort=\n", qp_urls,
      qp_engines[[backend]], backend, backend
    )$results
    expect_identical(allow$url_decision,
                     c("allow", "disallow", "allow"), label = backend)
  }
})
