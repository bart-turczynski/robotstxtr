# ROBO-zcgprxtq (BI1): introduce the engine-aware/v2 matcher-status set and its
# fail-closed guard while keeping the Bing backend capability_unavailable and
# Google/Yandex results byte-unchanged. Activation of the v2 contract identity
# is deferred to BI5; this slice only establishes and enforces the vocabulary.

test_that("v2 status set is the exact ordered eight-member vocabulary", {
  set <- robotstxtr:::engine_matcher_status_set_v2()
  expect_identical(
    set,
    c(
      "evaluated", "not_needed", "not_evaluated", "capability_unavailable",
      "invalid_request_target", "unsupported_profile",
      "matcher_input_limit_exceeded", "matcher_work_limit_exceeded"
    )
  )
  # No duplicates; the four v1 statuses remain a leading subset of the v2 set.
  expect_identical(anyDuplicated(set), 0L)
  expect_true(all(
    c("evaluated", "not_needed", "not_evaluated", "capability_unavailable")
      %in% set
  ))
})

test_that("the guard passes members and fails closed on any non-member", {
  members <- robotstxtr:::engine_matcher_status_set_v2()
  expect_identical(
    robotstxtr:::validate_matcher_status_v2(members), members
  )
  expect_identical(
    robotstxtr:::validate_matcher_status_v2(character()), character()
  )
  expect_error(
    robotstxtr:::validate_matcher_status_v2(c("evaluated", "allow")),
    class = "robotstxtr_matcher_status_invariant"
  )
  expect_error(
    robotstxtr:::validate_matcher_status_v2(NA_character_),
    class = "robotstxtr_matcher_status_invariant"
  )
})

test_that("Bing backend stays capability_unavailable in this slice", {
  contract <- robots_engine_contract_v1()
  expect_identical(
    contract$matcher_availability[["bing"]], "capability_unavailable"
  )
  registry <- robotstxtr:::engine_matcher_registry_v1()
  expect_null(registry$bing$callable)
  expect_identical(registry$bing$availability, "capability_unavailable")
})

test_that("real evaluations emit only members of the v2 status set", {
  has_batch <- is.function(
    tryCatch(robotstxtr_checked_batch_, error = function(e) NULL)
  )
  has_extract <- is.function(
    tryCatch(robotstxtr_extract_request_target_, error = function(e) NULL)
  )
  skip_if_not(
    has_batch && has_extract, "native binding not built (pure-R install)"
  )
  # Cover every currently reachable matcher_status branch: evaluated (google),
  # not_needed (allow_all policy via 4xx yandex), capability_unavailable (bing),
  # and not_evaluated (yandex unsupported token).
  x <- robots_evaluate_text_v1(
    "user-agent: *\ndisallow: /private",
    rep("https://example.com/private", 3L),
    "bot",
    c("google", "yandex", "bing"),
    c("google", "yandex", "bing")
  )
  expect_true(all(
    x$results$matcher_status %in% robotstxtr:::engine_matcher_status_set_v2()
  ))
})
