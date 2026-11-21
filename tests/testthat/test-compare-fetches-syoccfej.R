# ROBO-syoccfej: robots_compare_fetches(), an audit that fetches robots.txt
# for explicitly supplied variants under a hard request budget and reports how
# the responses differ. Offline: every request goes through the fake at the
# ssrfr boundary (helper-fake-ssrfr.R), and the recorder below counts them.

# --- Test helpers (file-local copies of test-robots_fetch-r6.R's) ------------

# Record every requested URL and the sent user agent, and route to a per-URL
# handler; an unexpected URL fails the test, so "no extra request" is free.
mock_router <- function(routes, recorder = NULL) {
  function(req) {
    if (!is.null(recorder)) {
      ua <- req$user_agent
      if (is.null(ua)) {
        ua <- NA_character_
      }
      recorder$urls <- c(recorder$urls, req$url)
      recorder$agents <- c(recorder$agents, ua)
      recorder$reqs <- c(recorder$reqs, list(req))
    }
    handler <- routes[[req$url]]
    if (is.null(handler)) {
      stop(sprintf("unexpected request URL in mock: %s", req$url))
    }
    handler(req)
  }
}

new_recorder <- function() {
  e <- new.env(parent = emptyenv())
  e$urls <- character(0)
  e$agents <- character(0)
  e$reqs <- list()
  e
}

ok_body <- function(body = "user-agent: *\ndisallow: /") {
  force(body)
  function(req) {
    fake_response(status_code = 200L, url = req$url, body = charToRaw(body))
  }
}

raw_body <- function(bytes) {
  force(bytes)
  function(req) fake_response(status_code = 200L, url = req$url, body = bytes)
}

status_resp <- function(code) {
  force(code)
  function(req) fake_response(status_code = code, url = req$url)
}

redirect_to <- function(location, status = 301L) {
  force(location)
  force(status)
  function(req) fake_response(status, headers = list(Location = location))
}

# A two-redirect chain ending in a 200: a -> b -> c.
chain_routes <- function() {
  list(
    "http://a/robots.txt" = redirect_to("http://b/robots.txt"),
    "http://b/robots.txt" = redirect_to("http://c/robots.txt"),
    "http://c/robots.txt" = ok_body()
  )
}

# The outcomes robots_fetch() can publish: every row of the translation
# tables, every final status, and the hop loop's own outcomes.
published_fetch_outcomes <- function() {
  refusal <- acquire_refusal_table()
  cause <- acquire_cause_table()
  statuses <- vapply(100:599, classify_status, character(1L))
  out <- unique(c(
    refusal$fetch_outcome, refusal$redirect_fetch_outcome,
    cause$fetch_outcome, statuses, "body_too_large", "redirect_error",
    "input_invalid"
  ))
  out[!is.na(out)]
}

# --- Pins: the unbudgeted acquisition is unchanged ---------------------------

test_that("acquire_robots() without a budget follows a chain hop by hop", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(chain_routes(), recorder = rec))

  r <- acquire_robots(
    "http://a/robots.txt", 10, package_fetch_user_agent(), 524288L
  )

  expect_identical(rec$urls, c(
    "http://a/robots.txt", "http://b/robots.txt", "http://c/robots.txt"
  ))
  expect_identical(r$fetch_outcome, "fetched")
  expect_identical(r$http_status, 200L)
  expect_identical(r$effective_url, "http://c/robots.txt")
  expect_identical(r$redirect_count, 2L)
  expect_length(r$redirect_hops, 2L)
  expect_identical(r$body, charToRaw("user-agent: *\ndisallow: /"))
})

test_that("robots_fetch() still makes one request per origin", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(chain_routes(), recorder = rec))

  x <- robots_fetch(c("http://a/x", "http://a/y"))

  expect_length(rec$urls, 3L)
  expect_identical(x$robots$fetch_outcome, "fetched")
  expect_identical(x$robots$redirect_count, 2L)
})

test_that("the published fetch_outcome set is pinned", {
  expect_setequal(published_fetch_outcomes(), c(
    "ssrf_blocked", "redirect_error", "timeout", "tls_error",
    "network_error", "http_error", "fetched", "partial_response", "missing",
    "body_too_large", "input_invalid"
  ))
})

# --- robots_compare_fetches() ------------------------------------------------
#
# Symmetry rule: not testable per engine. The audit computes no allow or
# disallow decision and reads no rule, so there is nothing for the google,
# bing and yandex profiles of robots_evaluate_text_v1() to differ on.

# A clock that ticks one second per read from a fixed start. Each call
# installs a fresh clock, so two runs see the same times.
local_ticking_now <- function(env = parent.frame()) {
  clock <- new.env(parent = emptyenv())
  clock$t <- 1800000000
  testthat::local_mocked_bindings(
    acquire_now = function() {
      clock$t <- clock$t + 1
      clock$t
    },
    .package = "robotstxtr", .env = env
  )
  clock
}

# A handler that answers each call with the next of `handlers`, the last one
# repeating: models a server whose answer changes over time.
in_turn <- function(...) {
  handlers <- list(...)
  state <- new.env(parent = emptyenv())
  state$i <- 0L
  function(req) {
    state$i <- min(state$i + 1L, length(handlers))
    handlers[[state$i]](req)
  }
}

test_that("max_requests counts every redirect hop", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(chain_routes(), recorder = rec))

  x <- robots_compare_fetches("http://a/", max_requests = 2)
  obs <- x$observations

  expect_identical(rec$urls, c("http://a/robots.txt", "http://b/robots.txt"))
  expect_identical(obs$observation_status, "budget_exhausted")
  expect_identical(obs$fetch_outcome, "budget_exhausted")
  # b's redirect is logged but not followed: its target was never prepared.
  expect_identical(obs$redirect_count, 1L)
  expect_length(obs$redirect_hops[[1]], 2L)
  expect_null(obs$body[[1]])
  expect_identical(attr(x, "requests_made"), 2L)

  rec2 <- new_recorder()
  local_fake_ssrfr(mock_router(chain_routes(), recorder = rec2))
  y <- robots_compare_fetches("http://a/", max_requests = 3)
  expect_length(rec2$urls, 3L)
  expect_identical(y$observations$observation_status, "response")
  expect_identical(y$observations$fetch_outcome, "fetched")
  expect_identical(y$observations$effective_url, "http://c/robots.txt")
  expect_identical(attr(y, "requests_made"), 3L)
})

test_that("repeats run in round-robin passes and a cut leaves not_requested", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = ok_body("a"),
    "http://b/robots.txt" = ok_body("b")
  ), recorder = rec))

  x <- robots_compare_fetches(
    data.frame(url = c("http://a/", "http://b/"), repeats = c(2, 2)),
    max_requests = 3
  )
  obs <- x$observations

  expect_identical(rec$urls, c(
    "http://a/robots.txt", "http://b/robots.txt", "http://a/robots.txt"
  ))
  expect_identical(obs$observation_id, 1:4)
  expect_identical(obs$variant_id, c(1L, 2L, 1L, 2L))
  expect_identical(obs$repeat_index, c(1L, 1L, 2L, 2L))
  expect_identical(obs$label, c(
    "variant_1", "variant_2", "variant_1", "variant_2"
  ))
  expect_identical(obs$observation_status, c(
    "response", "response", "response", "not_requested"
  ))
  expect_true(is.na(obs$fetch_outcome[[4]]))
  expect_true(is.na(obs$fetched_at[[4]]))
  expect_identical(obs$body_label, c("body_1", "body_2", "body_1", NA))
})

test_that("a refused target spends no budget; a redirect to one spends one", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = ok_body()
  ), recorder = rec))

  x <- robots_compare_fetches(
    c("http://127.0.0.1/", "http://a/"), max_requests = 1
  )
  expect_identical(rec$urls, "http://a/robots.txt")
  expect_identical(x$observations$observation_status, c("refused", "response"))
  expect_identical(x$observations$fetch_outcome, c("ssrf_blocked", "fetched"))
  expect_identical(x$observations$safety_block_reason[[1]], "loopback")
  expect_identical(attr(x, "requests_made"), 1L)

  rec2 <- new_recorder()
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = redirect_to("http://127.0.0.1/robots.txt")
  ), recorder = rec2))
  y <- robots_compare_fetches("http://a/", max_requests = 5)
  expect_identical(rec2$urls, "http://a/robots.txt")
  expect_identical(y$observations$observation_status, "refused")
  expect_identical(attr(y, "requests_made"), 1L)
})

test_that("bodies share a label only when byte for byte identical", {
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = ok_body("user-agent: *\ndisallow: /x"),
    "http://b/robots.txt" = ok_body("user-agent: *\ndisallow: /x"),
    "http://c/robots.txt" = ok_body("user-agent: *\ndisallow: /y"),
    "http://d/robots.txt" = raw_body(raw(0)),
    "http://e/robots.txt" = raw_body(raw(0)),
    "http://f/robots.txt" = raw_body(as.raw(c(0x00, 0xff, 0x41))),
    "http://g/robots.txt" = raw_body(as.raw(c(0x00, 0xfe, 0x41))),
    "http://h/robots.txt" = status_resp(404L)
  )))

  x <- robots_compare_fetches(
    paste0("http://", letters[1:8], "/"), max_requests = 8
  )
  expect_identical(x$observations$body_label, c(
    "body_1", "body_1", "body_2", "body_3", "body_3", "body_4", "body_5", NA
  ))
  expect_identical(x$observations$body[[6]], as.raw(c(0x00, 0xff, 0x41)))
  cmp <- x$comparison
  expect_identical(cmp$n_distinct[cmp$field == "body_label"], 6L)
})

test_that("a truncated body never shares a label, even with its own bytes", {
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = ok_body("abcdefgh"),
    "http://b/robots.txt" = ok_body("abcde"),
    "http://c/robots.txt" = ok_body("abcdefgh")
  )))

  x <- robots_compare_fetches(
    c("http://a/", "http://b/", "http://c/"), max_requests = 3,
    max_bytes = 5
  )
  obs <- x$observations
  expect_identical(obs$body_truncated, c(TRUE, FALSE, TRUE))
  expect_identical(obs$body[[1]], obs$body[[2]])
  expect_identical(obs$body_label, c("body_1", "body_2", "body_3"))
})

test_that("each variant sends its own User-Agent; NA sends the package's", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = function(req) {
      if (identical(req$user_agent, "AuditBot/1.0")) {
        status_resp(403L)(req)
      } else {
        ok_body()(req)
      }
    }
  ), recorder = rec))

  x <- robots_compare_fetches(
    data.frame(
      url = c("http://a/", "http://a/"),
      fetch_user_agent = c(NA, "AuditBot/1.0"),
      label = c("package", "custom")
    ),
    max_requests = 2
  )
  obs <- x$observations
  expect_identical(rec$agents, c(package_fetch_user_agent(), "AuditBot/1.0"))
  expect_identical(obs$http_user_agent, rec$agents)
  expect_identical(obs$label, c("package", "custom"))
  expect_identical(obs$http_status, c(200L, 403L))
  expect_identical(obs$observation_status, c("response", "response"))
  cmp <- x$comparison
  expect_identical(cmp$n_distinct[cmp$field == "http_status"], 2L)
  expect_identical(cmp$values[[which(cmp$field == "http_status")]],
                   c(200L, 403L))
})

test_that("scheme and host variants keep their own robots scope", {
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = ok_body(),
    "https://a/robots.txt" = ok_body(),
    "http://www.a/robots.txt" = function(req) fake_failure("timeout")
  )))

  x <- robots_compare_fetches(
    c("http://a/x", "https://a/y", "http://www.a/z"), max_requests = 3
  )
  obs <- x$observations
  expect_identical(obs$robots_url, c(
    "http://a/robots.txt", "https://a/robots.txt", "http://www.a/robots.txt"
  ))
  expect_identical(obs$url, c("http://a/x", "https://a/y", "http://www.a/z"))
  expect_identical(obs$observation_status, c(
    "response", "response", "acquisition_failure"
  ))
  expect_identical(obs$fetch_outcome[[3]], "timeout")
  expect_identical(obs$transport_error_kind[[3]], "timeout")
  expect_identical(obs$body_label, c("body_1", "body_1", NA))
})

test_that("a body that changes over time differs between repeats", {
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = in_turn(ok_body("one"), ok_body("two"))
  )))
  x <- robots_compare_fetches(
    data.frame(url = "http://a/", repeats = 3), max_requests = 3
  )
  expect_identical(x$observations$body_label, c("body_1", "body_2", "body_2"))
})

test_that("cache headers are carried raw and never compared", {
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = in_turn(
      function(req) {
        fake_response(200L, headers = list(Date = "d1", Age = "1"), body = "x")
      },
      function(req) {
        fake_response(200L, headers = list(Date = "d2", Age = "2"), body = "x")
      }
    )
  )))
  x <- robots_compare_fetches(
    data.frame(url = "http://a/", repeats = 2), max_requests = 2
  )
  expect_identical(x$observations$date, c("d1", "d2"))
  expect_identical(x$observations$age, c("1", "2"))
  expect_true(all(is.na(x$observations$etag)))
  expect_false(any(names(cache_header_fields) %in% x$comparison$field))
  expect_identical(x$comparison$field, c(
    "fetch_outcome", "http_status", "effective_url", "redirect_count",
    "terminal_redirect_reason", "body_label", "body_size", "content_type",
    "content_flag"
  ))
  expect_true(all(x$comparison$n_distinct == 1L))
})

test_that("an invalid URL is input_invalid and makes no request", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(list(), recorder = rec))
  x <- robots_compare_fetches(
    data.frame(url = c("not-a-url", NA), repeats = c(2, 1)), max_requests = 1
  )
  expect_length(rec$urls, 0L)
  expect_identical(x$observations$observation_status, rep("input_invalid", 3))
  expect_identical(x$observations$fetch_outcome, rep("input_invalid", 3))
  expect_true(all(is.na(x$observations$robots_url)))
  expect_identical(attr(x, "requests_made"), 0L)
  expect_true(all(x$comparison$n_distinct == 0L))
})

test_that("empty variants return an empty report with no request", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(list(), recorder = rec))
  for (v in list(character(), data.frame(url = character()))) {
    x <- robots_compare_fetches(v, max_requests = 1)
    expect_s3_class(x, "robots_fetch_comparison")
    expect_identical(nrow(x$observations), 0L)
    expect_identical(attr(x, "requests_made"), 0L)
    expect_output(print(x), "0 observations of 0 variants")
  }
  expect_length(rec$urls, 0L)
})

test_that("bad arguments are call errors before any request", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(list(), recorder = rec))
  bad_max <- list(0, 1.5, NA, c(1, 2), "1", Inf, -1)
  for (m in bad_max) {
    expect_error(
      robots_compare_fetches("http://a/", max_requests = m),
      class = "robotstxtr_invalid_max_requests"
    )
  }
  expect_error(
    robots_compare_fetches("http://a/"),
    class = "robotstxtr_invalid_max_requests"
  )
  bad_variants <- list(
    data.frame(link = "http://a/"),
    data.frame(url = "http://a/", repeats = 0),
    data.frame(url = "http://a/", repeats = 1.5),
    data.frame(url = "http://a/", repeats = NA_real_),
    data.frame(url = 1),
    list(url = "http://a/"),
    1
  )
  for (v in bad_variants) {
    expect_error(
      robots_compare_fetches(v, max_requests = 1),
      class = "robotstxtr_invalid_variants"
    )
  }
  for (ua in c("bad\nagent", " edge", "")) {
    expect_error(
      robots_compare_fetches(
        data.frame(url = c("http://a/", "http://a/"),
                   fetch_user_agent = c(NA, ua)),
        max_requests = 2
      ),
      class = "robotstxtr_invalid_fetch_user_agent"
    )
  }
  expect_error(
    robots_compare_fetches("http://a/", 1, safety_level = "loose"),
    class = "robotstxtr_invalid_safety_level"
  )
  expect_length(rec$urls, 0L)
})

test_that("two runs on the same mocks give identical reports", {
  run <- function() {
    local_ticking_now()
    local_fake_ssrfr(mock_router(list(
      "http://a/robots.txt" = in_turn(ok_body("one"), ok_body("two")),
      "http://b/robots.txt" = status_resp(503L)
    )))
    robots_compare_fetches(
      data.frame(url = c("http://a/", "http://b/"), repeats = c(2, 1)),
      max_requests = 5
    )
  }
  first <- run()
  second <- run()
  expect_identical(first, second)
  expect_identical(
    as.double(first$observations$fetched_at), c(1800000001, 1800000002,
                                                 1800000003)
  )
  expect_identical(attr(first$observations$fetched_at, "tzone"), "UTC")
})

test_that("print shows the header, statuses and differing fields", {
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = ok_body("a"),
    "http://b/robots.txt" = ok_body("b")
  )))
  x <- robots_compare_fetches(
    data.frame(url = c("http://a/", "http://b/"), repeats = c(2, 1)),
    max_requests = 2
  )
  out <- capture.output(res <- print(x))
  expect_identical(res, x)
  expect_match(out[[1]], "3 observations of 2 variants, 2 of 2 requests",
               fixed = TRUE)
  expect_match(out[[2]], "response 2, not_requested 1", fixed = TRUE)
  expect_match(out[[3]], "body_label (2)", fixed = TRUE)
  expect_false(any(grepl("user-agent", out, fixed = TRUE)))
})

# --- Fix round 1 --------------------------------------------------------------

# Count every hop prepared (the step that resolves a name, live), on top of
# local_fake_ssrfr()'s fake.
local_counting_prepare <- function(env = parent.frame()) {
  count <- new.env(parent = emptyenv())
  count$urls <- character()
  testthat::local_mocked_bindings(
    acquire_prepare_hop = function(url, policy, request = NULL, from = NULL) {
      count$urls <- c(count$urls, url)
      fake_prepare_hop(url, policy, from)
    },
    .package = "robotstxtr", .env = env
  )
  count
}

test_that("a spent budget prepares no further hop and no further origin", {
  rec <- new_recorder()
  routes <- chain_routes()
  routes[["http://d/robots.txt"]] <- ok_body()
  local_fake_ssrfr(mock_router(routes, recorder = rec))
  prepared <- local_counting_prepare()

  x <- robots_compare_fetches(c("http://a/", "http://d/"), max_requests = 2)

  expect_identical(
    prepared$urls, c("http://a/robots.txt", "http://b/robots.txt")
  )
  expect_length(rec$urls, 2L)
  expect_identical(
    x$observations$observation_status, c("budget_exhausted", "not_requested")
  )
})

test_that("sum(repeats) over 10000 is a call error before any request", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(list(), recorder = rec))
  for (v in list(
    data.frame(url = "http://a/", repeats = 10001),
    data.frame(url = c("http://a/", "http://b/"), repeats = c(5000, 5001)),
    data.frame(url = "http://a/", repeats = 2^31)
  )) {
    expect_error(
      robots_compare_fetches(v, max_requests = 1),
      class = "robotstxtr_invalid_variants"
    )
  }
  expect_length(rec$urls, 0L)
})

test_that("a 10000-observation plan stops observing once the budget is spent", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = ok_body()
  ), recorder = rec))
  calls <- new.env(parent = emptyenv())
  calls$n <- 0L
  real_observe <- compare_observe
  local_mocked_bindings(compare_observe = function(...) {
    calls$n <- calls$n + 1L
    real_observe(...)
  })

  started <- proc.time()[["elapsed"]]
  x <- robots_compare_fetches(
    data.frame(url = "http://a/", repeats = 10000), max_requests = 1
  )
  elapsed <- proc.time()[["elapsed"]] - started

  expect_identical(calls$n, 1L)
  expect_length(rec$urls, 1L)
  expect_identical(nrow(x$observations), 10000L)
  expect_identical(
    x$observations$observation_status,
    c("response", rep("not_requested", 9999L))
  )
  expect_lt(elapsed, 20)
})

test_that("max_requests and repeats reject values past the integer range", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = ok_body()
  ), recorder = rec))
  expect_error(
    robots_compare_fetches("http://a/", max_requests = 2^31),
    class = "robotstxtr_invalid_max_requests"
  )
  expect_error(
    robots_compare_fetches(
      data.frame(url = "http://a/", repeats = Inf), max_requests = 1
    ),
    class = "robotstxtr_invalid_variants"
  )
  expect_length(rec$urls, 0L)
  x <- robots_compare_fetches("http://a/", max_requests = .Machine$integer.max)
  expect_identical(attr(x, "max_requests"), .Machine$integer.max)
  expect_identical(attr(x, "requests_made"), 1L)
})

test_that("variants columns: defaults, coercions and exact names", {
  rec <- new_recorder()
  local_fake_ssrfr(mock_router(list(
    "http://a/robots.txt" = ok_body()
  ), recorder = rec))

  x <- robots_compare_fetches(
    data.frame(
      url = factor(c("http://a/", "http://a/")),
      fetch_user_agent = c(NA, NA),
      label = c("first", NA),
      stringsAsFactors = FALSE
    ),
    max_requests = 2
  )
  obs <- x$observations
  expect_identical(obs$url, c("http://a/", "http://a/"))
  expect_identical(obs$robots_url, rep("http://a/robots.txt", 2L))
  expect_identical(obs$label, c("first", "variant_2"))
  expect_identical(rec$agents, rep(package_fetch_user_agent(), 2L))

  for (col in c("fetch_user_agents", "labels", "user_agent")) {
    v <- data.frame(url = "http://a/", x = "AuditBot/1.0")
    names(v)[[2]] <- col
    expect_error(
      robots_compare_fetches(v, max_requests = 1),
      regexp = sprintf("`%s`", col), class = "robotstxtr_invalid_variants"
    )
  }
  expect_error(
    robots_compare_fetches(matrix("http://a/"), max_requests = 1),
    class = "robotstxtr_invalid_variants"
  )
  expect_length(rec$urls, 2L)
})

test_that("print: more than ten rows, no difference, and no observation", {
  local_fake_ssrfr(mock_router(list()))
  x <- robots_compare_fetches(
    data.frame(url = "http://127.0.0.1/", repeats = 11), max_requests = 1
  )
  out <- capture.output(print(x))
  expect_match(out[[1]], "11 observations of 1 variant, 0 of 1 requests",
               fixed = TRUE)
  expect_identical(out[[2]], "Status: refused 11")
  expect_identical(
    out[[3]], "Differs: nothing among the completed observations"
  )
  expect_identical(out[[length(out)]], "  ... and 1 more row")

  empty <- robots_compare_fetches(character(), max_requests = 1)
  expect_identical(
    capture.output(print(empty)),
    "<robots_fetch_comparison>: 0 observations of 0 variants, 0 of 1 requests"
  )
})
