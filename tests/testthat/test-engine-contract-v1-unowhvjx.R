# ROBO-unowhvjx: versioned engine-aware policy and matcher facade.

engine_mock_router <- function(routes, recorder = NULL) {
  function(req) {
    if (!is.null(recorder)) {
      recorder$urls <- c(recorder$urls, req$url)
      recorder$agents <- c(recorder$agents, req$options$useragent)
    }
    handler <- routes[[req$url]]
    if (is.null(handler)) {
      stop(sprintf("unexpected request URL in mock: %s", req$url))
    }
    handler(req)
  }
}

engine_response <- function(status, body = "", headers = list()) {
  force(status)
  force(body)
  force(headers)
  function(req) {
    httr2::response(
      status_code = status, url = req$url, headers = headers,
      body = charToRaw(body)
    )
  }
}

engine_recorder <- function() {
  out <- new.env(parent = emptyenv())
  out$urls <- character()
  out$agents <- character()
  out
}

test_that("contract metadata publishes revisions and sibling ranges", {
  contract <- robots_engine_contract_v1()
  expect_s3_class(contract, "robots_engine_contract_v1")
  expect_identical(contract$contract_id, "robotstxtr.engine-aware/v1")
  expect_match(contract$schema_revision, "^2026-07-17\\.")
  expect_match(contract$matcher_revisions[["google"]], "22b355ff")
  expect_identical(
    contract$matcher_availability[["google"]], "available"
  )
  expect_identical(
    unname(contract$matcher_availability[c("yandex", "rfc9309", "bing")]),
    rep("capability_unavailable", 3L)
  )
  expect_named(
    contract$sibling_versions, c("sitemapr", "sitemap-validator")
  )
  expect_identical(
    contract$sibling_versions[["sitemapr"]], ">= 0.0.0.9000, < 0.1.0"
  )
  expect_identical(
    contract$sibling_versions[["sitemap-validator"]],
    ">= 1.0.0, < 2.0.0"
  )
  expect_true(all(nzchar(contract$policy_table$policy_source)))
})

test_that("Google v1 text path uses the pinned matcher end to end", {
  body <- paste(
    "user-agent: *", "allow: /private/public", "disallow: /private",
    sep = "\n"
  )
  url <- c(
    "https://example.com/", "https://example.com/private/report",
    "https://example.com/private/public"
  )
  legacy <- allowed_by_robots_text(body, url, "testbot")
  versioned <- robots_evaluate_text_v1(
    body, url, "testbot", "google", "google"
  )

  expect_s3_class(versioned, "robots_engine_decisions_v1")
  expect_identical(
    versioned$results$url_decision, c("allow", "disallow", "allow")
  )
  expect_identical(
    versioned$results$reason,
    c("default_allow", "rule_disallow", "rule_allow")
  )
  expect_identical(
    versioned$results$matcher_status, rep("evaluated", 3L)
  )
  adapted <- as_legacy_robots_decisions_v1(versioned)
  expect_identical(adapted$results, legacy$results)
  expect_identical(adapted$robots, legacy$robots)
})

test_that("policy ruleset and matcher backend remain independent", {
  x <- robots_evaluate_text_v1(
    "user-agent: *\ndisallow: /", rep("https://example.com/private", 3L),
    "bot",
    c("rfc9309", "yandex", "bing"),
    c("rfc9309", "yandex", "bing")
  )

  expect_identical(x$results$policy_status, rep("evaluated", 3L))
  expect_identical(x$results$policy_action, rep("use_rules", 3L))
  expect_identical(
    x$results$matcher_status, rep("capability_unavailable", 3L)
  )
  expect_identical(
    x$results$matcher_availability, rep("capability_unavailable", 3L)
  )
  expect_true(all(is.na(x$results$url_decision)))
  expect_identical(
    x$results$reason, rep("matcher_capability_unavailable", 3L)
  )
})

test_that("HTTP User-Agent is distinct from the robots product token", {
  recorder <- engine_recorder()
  httr2::local_mocked_responses(engine_mock_router(
    list(
      "http://example.test/robots.txt" = engine_response(
        200L, "user-agent: crawler-token\ndisallow: /private"
      )
    ),
    recorder
  ))
  x <- robots_evaluate_url_v1(
    "http://example.test/private", "crawler-token", "google", "google",
    fetch_user_agent = "fetch-client/7"
  )

  expect_identical(recorder$agents, "fetch-client/7")
  expect_identical(x$results$http_user_agent, "fetch-client/7")
  expect_identical(x$results$robots_product_token, "crawler-token")
  expect_identical(x$results$url_decision, "disallow")
  expect_identical(x$evidence$http_user_agent, "fetch-client/7")
})

test_that("engine status policies do not fabricate universal behavior", {
  httr2::local_mocked_responses(engine_mock_router(list(
    "http://example.test/robots.txt" = engine_response(404L)
  )))
  x <- robots_evaluate_url_v1(
    rep("http://example.test/path", 4L), "bot",
    c("google", "yandex", "rfc9309", "bing"),
    c("google", "yandex", "rfc9309", "bing")
  )

  expect_identical(
    x$results$policy_status,
    c("evaluated", "evaluated", "evaluated", "documentation_gap")
  )
  expect_identical(
    x$results$url_decision, c("allow", "allow", "allow", NA_character_)
  )
  expect_identical(
    x$results$matcher_status,
    c("not_needed", "not_needed", "not_needed", "not_evaluated")
  )
})

test_that("lifecycle-dependent and undocumented outcomes stay unresolved", {
  httr2::local_mocked_responses(engine_mock_router(list(
    "http://example.test/robots.txt" = engine_response(500L)
  )))
  x <- robots_evaluate_url_v1(
    rep("http://example.test/path", 4L), "bot",
    c("google", "rfc9309", "yandex", "bing"),
    c("google", "rfc9309", "yandex", "bing")
  )

  expect_identical(
    x$results$policy_status,
    c(
      "context_required", "context_required", "evaluated",
      "documentation_gap"
    )
  )
  expect_identical(
    x$results$url_decision, c(NA_character_, NA_character_, "allow", NA)
  )
  expect_identical(
    x$results$policy_provenance,
    c("documented", "documented", "documented", "documentation_gap")
  )
})

test_that("safety refusal never becomes an allow or deny", {
  x <- robots_evaluate_url_v1(
    "http://127.0.0.1/private", "bot", "google", "google"
  )

  expect_identical(x$evidence$evidence_status, "safety_refused")
  expect_identical(x$evidence$safety_block_reason, "loopback")
  expect_identical(x$results$policy_status, "not_evaluated")
  expect_identical(x$results$policy_reason, "safety_refused")
  expect_identical(x$results$matcher_status, "not_evaluated")
  expect_true(is.na(x$results$url_decision))
})

test_that("over-ceiling evidence is incomplete and never matched", {
  httr2::local_mocked_responses(engine_mock_router(list(
    "http://example.test/robots.txt" = engine_response(
      200L, "user-agent: *\ndisallow: /"
    )
  )))
  x <- robots_evaluate_url_v1(
    "http://example.test/private", "bot", "google", "google",
    max_bytes = 8L
  )

  expect_identical(x$evidence$evidence_status, "incomplete")
  expect_identical(x$evidence$termination_reason, "ceiling")
  expect_gt(x$evidence$observed_bytes, 8L)
  expect_identical(x$evidence$stored_bytes, 0L)
  expect_false(x$evidence$body_present)
  expect_identical(x$results$policy_status, "not_evaluated")
  expect_identical(x$results$reason, "incomplete_evidence")
  expect_true(is.na(x$results$url_decision))
})

test_that("partial response resolves policy but does not run a matcher", {
  httr2::local_mocked_responses(engine_mock_router(list(
    "http://example.test/robots.txt" = engine_response(
      206L, "user-agent: *\ndisallow: /"
    )
  )))
  x <- robots_evaluate_url_v1(
    "http://example.test/private", "bot", "google", "google"
  )

  expect_identical(x$evidence$evidence_status, "partial")
  expect_identical(x$results$policy_status, "evaluated")
  expect_identical(x$results$policy_action, "use_rules")
  expect_identical(x$results$matcher_status, "not_evaluated")
  expect_identical(x$results$reason, "partial_evidence")
  expect_true(is.na(x$results$url_decision))
})

test_that("redirect evidence records terminal reason and ordered hops", {
  routes <- list(
    "http://example.test/robots.txt" = engine_response(
      302L, headers = list(Location = "http://example.test/one")
    ),
    "http://example.test/one" = engine_response(301L)
  )
  httr2::local_mocked_responses(engine_mock_router(routes))
  x <- robots_evaluate_url_v1(
    "http://example.test/path", "bot", "google", "google"
  )

  expect_identical(x$evidence$evidence_status, "http_protocol_error")
  expect_identical(x$evidence$terminal_redirect_reason, "no_location")
  expect_identical(x$evidence$final_http_status, 301L)
  expect_identical(x$evidence$redirect_count, 1L)
  expect_length(x$evidence$redirect_hops[[1L]], 2L)
  expect_identical(
    x$evidence$redirect_hops[[1L]][[1L]],
    list(
      from_url = "http://example.test/robots.txt", status = 302L,
      location_target = "http://example.test/one"
    )
  )
  expect_identical(x$results$policy_status, "documentation_gap")
  expect_true(is.na(x$results$url_decision))
})

test_that("HTTPS downgrade redirect is an engine-independent safety refusal", {
  httr2::local_mocked_responses(engine_mock_router(list(
    "https://example.test/robots.txt" = engine_response(
      302L, headers = list(Location = "http://example.test/robots.txt")
    )
  )))
  x <- robots_evaluate_url_v1(
    "https://example.test/path", "bot", "yandex", "yandex"
  )

  expect_identical(x$evidence$terminal_redirect_reason, "downgrade")
  expect_identical(x$evidence$safety_block_reason, "https_downgrade")
  expect_identical(x$evidence$evidence_status, "safety_refused")
  expect_identical(x$results$policy_status, "not_evaluated")
  expect_true(is.na(x$results$url_decision))
})

test_that("Google applies its 500 KiB matcher prefix independently", {
  prefix <- paste0("user-agent: *\ndisallow: /private\n", strrep("#", 524250L))
  body <- paste0(prefix, "\nallow: /private")
  expect_gt(nchar(body, type = "bytes"), 524288L)
  x <- robots_evaluate_text_v1(
    body, "https://example.com/private", "bot", "google", "google"
  )

  expect_identical(x$results$url_decision, "disallow")
  expect_true(x$results$matcher_body_truncated)
  expect_identical(x$results$matcher_input_bytes, 524288L)
  expect_false(x$evidence$body_truncated)
  expect_identical(x$evidence$stored_bytes, nchar(body, type = "bytes"))
})

test_that("legacy adapter retains generic HTTP failures as unknown", {
  httr2::local_mocked_responses(engine_mock_router(list(
    "http://example.test/robots.txt" = engine_response(403L)
  )))
  versioned <- robots_evaluate_url_v1(
    "http://example.test/path", "bot", "google", "google"
  )
  legacy <- as_legacy_robots_decisions_v1(versioned)

  expect_identical(versioned$results$url_decision, "allow")
  expect_true(is.na(legacy$results$allowed))
  expect_identical(legacy$results$decision_source, "fetch_unknown")
  expect_identical(legacy$results$fetch_outcome, "http_error")
})

test_that("versioned axes reject implicit or unknown selections", {
  expect_error(
    robots_evaluate_text_v1("", "http://a/", "bot", "unknown", "google"),
    class = "robotstxtr_invalid_robots_policy_ruleset"
  )
  expect_error(
    robots_evaluate_text_v1("", "http://a/", "bot", "google", "unknown"),
    class = "robotstxtr_invalid_matcher_backend"
  )
  mixed <- robots_evaluate_text_v1(
    "", "http://a/", "bot", "yandex", "yandex"
  )
  expect_error(
    as_legacy_robots_decisions_v1(mixed),
    class = "robotstxtr_incompatible_legacy_adapter"
  )
})
