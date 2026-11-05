# Retry-After on robots.txt fetch rows (ROBO-cthdyvlk). A 429 or 503 for
# robots.txt may say when to come back (RFC 9110 section 10.2.3; RFC 9309
# sections 2.3.1.3 and 2.3.1.4). Responses are scripted at the ssrfr boundary
# (helper-fake-ssrfr.R).

# A handler serving `routes`, a list of fake_response() keyed by request URL.
ra_router <- function(routes) {
  function(req) {
    res <- routes[[req$url]]
    if (is.null(res)) {
      return(fake_response(404L, req$url))
    }
    res
  }
}

ra_robots_columns <- c(
  "source_id", "source_type", "robots_url", "effective_url", "http_status",
  "fetch_outcome", "redirect_count", "body_size", "timeout", "max_bytes",
  "error_stage", "error_class", "error_message", "retry_after",
  "retry_after_seconds", "body"
)

# Fetch http://a/robots.txt answered by `res`; the source row.
ra_fetch_one <- function(res, env = parent.frame()) {
  local_fake_ssrfr(ra_router(list("http://a/robots.txt" = res)), env = env)
  robots_fetch("http://a/")$robots
}

# A fixed fetch time: Thu, 05 Nov 2026 12:00:00 GMT.
ra_fetched_at <- as.double(as.POSIXct("2026-11-05 12:00:00", tz = "UTC"))

ra_local_now <- function(env = parent.frame()) {
  testthat::local_mocked_bindings(
    acquire_now = function() ra_fetched_at,
    .package = "robotstxtr", .env = env
  )
}

test_that("ROBO-cthdyvlk: the robots_fetch() source columns", {
  local_fake_ssrfr(ra_router(list(
    "http://a/robots.txt" = fake_response(503L)
  )))
  x <- robots_fetch("http://a/")
  expect_named(x$robots, ra_robots_columns)
  expect_type(x$robots$retry_after, "character")
  expect_type(x$robots$retry_after_seconds, "double")

  empty <- robots_fetch(character())
  expect_named(empty$robots, ra_robots_columns)
  expect_type(empty$robots$retry_after, "character")
  expect_type(empty$robots$retry_after_seconds, "double")
})

test_that("ROBO-cthdyvlk: allowed_by_robots_url() carries the fetch row", {
  local_fake_ssrfr(ra_router(list(
    "http://a/robots.txt" = fake_response(
      503L, headers = list("Retry-After" = "120")
    )
  )))
  fetched <- robots_fetch("http://a/")
  decided <- allowed_by_robots_url("http://a/", "bot")
  expect_identical(decided$robots, fetched$robots)
  expect_identical(decided$robots$retry_after, "120")
  expect_identical(decided$robots$retry_after_seconds, 120)
})

# --- delay-seconds ----------------------------------------------------------

test_that("ROBO-cthdyvlk: 429 and 503 with delay-seconds", {
  for (status in c(429L, 503L)) {
    row <- ra_fetch_one(fake_response(
      status, headers = list("Retry-After" = "120")
    ))
    expect_identical(row$http_status, status)
    expect_identical(row$fetch_outcome, "http_error")
    expect_identical(row$retry_after, "120")
    expect_identical(row$retry_after_seconds, 120)
  }
})

test_that("ROBO-cthdyvlk: delay-seconds keeps the raw value, trims OWS", {
  row <- ra_fetch_one(fake_response(
    503L, headers = list("Retry-After" = " 0 ")
  ))
  expect_identical(row$retry_after, " 0 ")
  expect_identical(row$retry_after_seconds, 0)
})

# --- HTTP-date --------------------------------------------------------------

test_that("ROBO-cthdyvlk: an HTTP-date is relative to the response's Date", {
  ra_local_now()
  row <- ra_fetch_one(fake_response(503L, headers = list(
    "Retry-After" = "Fri, 06 Nov 2026 08:49:37 GMT",
    "Date" = "Fri, 06 Nov 2026 08:47:37 GMT"
  )))
  expect_identical(row$retry_after, "Fri, 06 Nov 2026 08:49:37 GMT")
  expect_identical(row$retry_after_seconds, 120)
})

test_that("ROBO-cthdyvlk: with no valid Date, the fetch time is the base", {
  ra_local_now()
  row <- ra_fetch_one(fake_response(429L, headers = list(
    "Retry-After" = "Thu, 05 Nov 2026 12:02:00 GMT"
  )))
  expect_identical(row$retry_after_seconds, 120)

  row <- ra_fetch_one(fake_response(429L, headers = list(
    "Retry-After" = "Thu, 05 Nov 2026 12:02:00 GMT",
    "Date" = "yesterday"
  )))
  expect_identical(row$retry_after_seconds, 120)
})

test_that("ROBO-cthdyvlk: a past HTTP-date is a zero delay", {
  ra_local_now()
  row <- ra_fetch_one(fake_response(503L, headers = list(
    "Retry-After" = "Thu, 05 Nov 2026 11:00:00 GMT"
  )))
  expect_identical(row$retry_after, "Thu, 05 Nov 2026 11:00:00 GMT")
  expect_identical(row$retry_after_seconds, 0)
})

test_that("ROBO-cthdyvlk: the obsolete RFC 850 and asctime forms parse", {
  ra_local_now()
  row <- ra_fetch_one(fake_response(503L, headers = list(
    "Retry-After" = "Thursday, 05-Nov-26 12:02:00 GMT"
  )))
  expect_identical(row$retry_after_seconds, 120)

  row <- ra_fetch_one(fake_response(503L, headers = list(
    "Retry-After" = "Thu Nov  5 12:02:00 2026"
  )))
  expect_identical(row$retry_after_seconds, 120)
})

# --- invalid and absent -----------------------------------------------------

test_that("ROBO-cthdyvlk: an invalid value keeps the raw value, no delay", {
  ra_local_now()
  invalid <- c(
    "soon", "-5", "1.5", "120 seconds", "",
    "thu, 05 Nov 2026 12:02:00 GMT",
    "Thu, 31 Feb 2026 12:02:00 GMT",
    "Thu, 05 Nov 2026 24:00:00 GMT",
    "Thu, 05 Nov 2026 12:02:00 UTC"
  )
  for (value in invalid) {
    row <- ra_fetch_one(fake_response(
      503L, headers = list("Retry-After" = value)
    ))
    expect_identical(row$retry_after, value)
    expect_identical(row$retry_after_seconds, NA_real_, label = value)
  }
})

test_that("ROBO-cthdyvlk: repeated Retry-After fields are joined and invalid", {
  headers <- stats::setNames(list("120", "60"), rep("Retry-After", 2L))
  row <- ra_fetch_one(fake_response(503L, headers = headers))
  expect_identical(row$retry_after, "120, 60")
  expect_identical(row$retry_after_seconds, NA_real_)
})

test_that("ROBO-cthdyvlk: no Retry-After is NA in both columns", {
  for (status in c(200L, 404L, 429L, 503L)) {
    row <- ra_fetch_one(fake_response(status, body = "user-agent: *\n"))
    expect_identical(row$retry_after, NA_character_)
    expect_identical(row$retry_after_seconds, NA_real_)
  }
})

test_that("ROBO-cthdyvlk: a 200 keeps its Retry-After and its body", {
  row <- ra_fetch_one(fake_response(
    200L, headers = list("Retry-After" = "30"), body = "user-agent: *\n"
  ))
  expect_identical(row$fetch_outcome, "fetched")
  expect_identical(row$body[[1L]], charToRaw("user-agent: *\n"))
  expect_identical(row$retry_after_seconds, 30)
})

# --- redirects --------------------------------------------------------------

test_that("ROBO-cthdyvlk: only the final response's Retry-After counts", {
  local_fake_ssrfr(ra_router(list(
    "http://a/robots.txt" = fake_response(301L, headers = list(
      "Location" = "http://b/robots.txt", "Retry-After" = "5"
    )),
    "http://b/robots.txt" = fake_response(302L, headers = list(
      "Location" = "http://c/robots.txt", "Retry-After" = "7"
    )),
    "http://c/robots.txt" = fake_response(
      503L, headers = list("Retry-After" = "120")
    ),
    "http://d/robots.txt" = fake_response(301L, headers = list(
      "Location" = "http://e/robots.txt", "Retry-After" = "5"
    )),
    "http://e/robots.txt" = fake_response(503L)
  )))
  x <- robots_fetch(c("http://a/", "http://d/"))
  expect_identical(x$robots$redirect_count, c(2L, 1L))
  expect_identical(x$robots$retry_after, c("120", NA))
  expect_identical(x$robots$retry_after_seconds, c(120, NA))
})

test_that("ROBO-cthdyvlk: no final response, no Retry-After", {
  local_fake_ssrfr(ra_router(list(
    "http://a/robots.txt" = fake_response(
      302L, headers = list("Retry-After" = "5")
    ),
    "http://b/robots.txt" = fake_failure("timeout")
  )))
  x <- robots_fetch(c("http://a/", "http://b/", "http://127.0.0.1/"))
  expect_identical(
    x$robots$fetch_outcome, c("redirect_error", "timeout", "ssrf_blocked")
  )
  expect_identical(x$robots$retry_after, rep(NA_character_, 3L))
  expect_identical(x$robots$retry_after_seconds, rep(NA_real_, 3L))
})
