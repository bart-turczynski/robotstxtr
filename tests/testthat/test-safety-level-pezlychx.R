# `safety_level` exists, and "strict" is today's acquisition unchanged
# (ADR 0001 slice 2, ROBO-pezlychx). "crawler" is published but refused until
# it lands (ROBO-lwdxzdhw).

sl_entry_points <- list(
  robots_fetch = function(...) robots_fetch("http://a/x", ...),
  allowed_by_robots_url = function(...) {
    allowed_by_robots_url("http://a/x", "Googlebot", ...)
  },
  robots_validate_url = function(...) robots_validate_url("http://a/x", ...),
  robots_evaluate_url_v1 = function(...) {
    robots_evaluate_url_v1("http://a/x", "Googlebot", "google", "google", ...)
  }
)

test_that("every fetching entry point refuses a bad safety_level", {
  # The fake fails the test if any request is made: validation comes first.
  local_fake_ssrfr(function(req) stop("no request expected"))
  bad <- list("lax", "STRICT", NA_character_, c("strict", "strict"),
              character(), 1, NULL, TRUE)
  for (name in names(sl_entry_points)) {
    for (value in bad) {
      expect_error(
        sl_entry_points[[name]](safety_level = value),
        class = "robotstxtr_invalid_safety_level",
        info = paste(name, deparse(value))
      )
    }
  }
})

test_that("crawler is refused as not available yet, a subclass", {
  local_fake_ssrfr(function(req) stop("no request expected"))
  for (name in names(sl_entry_points)) {
    err <- expect_error(
      sl_entry_points[[name]](safety_level = "crawler"),
      class = "robotstxtr_unavailable_safety_level",
      info = name
    )
    expect_s3_class(err, "robotstxtr_invalid_safety_level")
    expect_s3_class(err, "robotstxtr_error")
  }
})

test_that("an explicit strict is the default, on every entry point", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, body = "user-agent: *\ndisallow: /x\n")
  })
  for (name in names(sl_entry_points)) {
    expect_identical(
      sl_entry_points[[name]](safety_level = "strict"),
      sl_entry_points[[name]](),
      info = name
    )
  }
})

test_that("the contract publishes the safety level value set", {
  expect_identical(
    robots_engine_contract_v1()$safety_levels, c("strict", "crawler")
  )
  expect_identical(
    robots_engine_contract_v2()$safety_levels, c("strict", "crawler")
  )
})

test_that("a fetched evidence row records the level it was fetched under", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, body = "user-agent: *\ndisallow: /x\n")
  })
  x <- robots_evaluate_url_v1("http://a/x", "Googlebot", "google", "google")
  expect_identical(x$evidence$safety_level, "strict")
  expect_identical(x$evidence$fetch_allow_ranges, list(character()))
  expect_true(x$evidence$https_downgrade_guard)
  expect_true(x$results$https_downgrade_guard)
})

test_that("a refused origin's evidence row records the level too", {
  x <- robots_evaluate_url_v1(
    "http://127.0.0.1/x", "Googlebot", "google", "google"
  )
  expect_identical(x$evidence$evidence_status, "safety_refused")
  expect_identical(x$evidence$safety_level, "strict")
  expect_identical(x$evidence$fetch_allow_ranges, list(character()))
})

test_that("a row with no acquisition has NA safety fields", {
  x <- robots_evaluate_text_v1(
    "user-agent: *\n", "https://example.com/", "Googlebot", "google", "google"
  )
  expect_identical(x$evidence$safety_level, NA_character_)
  expect_identical(x$evidence$fetch_allow_ranges, list(NA_character_))
  expect_identical(x$evidence$https_downgrade_guard, NA)
  expect_identical(x$results$https_downgrade_guard, NA)
})

test_that("an evidence frame with no rows still has both columns", {
  x <- robots_evaluate_url_v1("not-a-url", "Googlebot", "google", "google")
  expect_identical(nrow(x$evidence), 0L)
  expect_type(x$evidence$safety_level, "character")
  expect_type(x$evidence$fetch_allow_ranges, "list")
})

test_that("a named strict reads as the default", {
  local_fake_ssrfr(function(req) {
    fake_response(200L, body = "user-agent: *\ndisallow: /x\n")
  })
  for (name in names(sl_entry_points)) {
    expect_identical(
      sl_entry_points[[name]](safety_level = c(nm = "strict")),
      sl_entry_points[[name]](),
      info = name
    )
  }
})
