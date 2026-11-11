# robots_validate_url() notes an https to http redirect that the fetch
# followed (ROBO-cscdbael): `redirect_downgrade_followed`, info. It reads the
# hop log the legacy robots frame now carries as `redirect_hops`; a hop counts
# as followed when it is one of the first `redirect_count` hops. Only a fetch
# that reached a body is checked.

rdf_body <- "user-agent: *\ndisallow: /private\n"

rdf_router <- function(routes) {
  function(req) {
    handler <- routes[[req$url]]
    if (is.null(handler)) {
      stop(sprintf("unexpected request URL in fake: %s", req$url))
    }
    handler(req)
  }
}

rdf_moved <- function(to) {
  force(to)
  function(req) fake_response(301L, headers = list(Location = to))
}

rdf_ok <- function(body = rdf_body) {
  force(body)
  function(req) fake_response(200L, body = body)
}

rdf_downgrade_chain <- function(body = rdf_body) {
  rdf_router(list(
    "https://a/robots.txt" = rdf_moved("http://a/robots.txt"),
    "http://a/robots.txt" = rdf_ok(body)
  ))
}

rdf_rows <- function(v) {
  v$diagnostics[v$diagnostics$code == "redirect_downgrade_followed", ,
                drop = FALSE]
}

rdf_hop <- function(from, to, status = 301L) {
  list(from_url = from, status = status, location_target = to)
}

rdf_source <- function(hops, redirect_count) {
  source <- data.frame(
    source_id = "robots_1", redirect_count = as.integer(redirect_count),
    stringsAsFactors = FALSE
  )
  source$redirect_hops <- list(hops)
  source
}

# --- robots_validate_url() ---------------------------------------------------

test_that("crawler: https -> 301 -> http -> 200 is noted once, as info", {
  local_fake_ssrfr(rdf_downgrade_chain())
  v <- robots_validate_url("https://a/x", safety_level = "crawler")
  rows <- rdf_rows(v)
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$severity, "info")
  expect_identical(rows$source_id, "robots_1")
  expect_true(grepl("https://a/robots.txt -> http://a/robots.txt",
                    rows$message, fixed = TRUE))
  expect_false("acquisition_redirect_downgrade" %in% v$diagnostics$code)
  # An info row leaves the document's status as the body set it.
  expect_identical(v$documents$validation_status, "valid")
  expect_identical(v$documents$diagnostic_count, nrow(v$diagnostics))
})

test_that("crawler: a downgrade in the middle of the chain is noted", {
  local_fake_ssrfr(rdf_router(list(
    "https://a/robots.txt" = rdf_moved("http://a/r2"),
    "http://a/r2" = rdf_moved("https://a/r3"),
    "https://a/r3" = rdf_ok()
  )))
  v <- robots_validate_url("https://a/x", safety_level = "crawler")
  rows <- rdf_rows(v)
  expect_identical(nrow(rows), 1L)
  expect_true(grepl("https://a/robots.txt -> http://a/r2", rows$message,
                    fixed = TRUE))
  expect_false(grepl("https://a/r3", rows$message, fixed = TRUE))
  # The file itself came back over https: the row says the chain, not the
  # file, went over plain http.
  expect_true(grepl("part of the redirect chain went over plain http",
                    rows$message, fixed = TRUE))
  expect_false(grepl("file was read over plain http", rows$message,
                     fixed = TRUE))
})

test_that("crawler: two downgrades make one row naming both hops", {
  local_fake_ssrfr(rdf_router(list(
    "https://a/robots.txt" = rdf_moved("http://a/r2"),
    "http://a/r2" = rdf_moved("https://a/r3"),
    "https://a/r3" = rdf_moved("http://a/r4"),
    "http://a/r4" = rdf_ok()
  )))
  rows <- rdf_rows(robots_validate_url("https://a/x", safety_level = "crawler"))
  expect_identical(nrow(rows), 1L)
  expect_true(grepl("https://a/robots.txt -> http://a/r2", rows$message,
                    fixed = TRUE))
  expect_true(grepl("https://a/r3 -> http://a/r4", rows$message, fixed = TRUE))
})

test_that("crawler: an HTML page at the end of a downgrade is still noted", {
  local_fake_ssrfr(rdf_downgrade_chain(
    "<!DOCTYPE html>\n<html><body>Moved</body></html>\n"
  ))
  v <- robots_validate_url("https://a/x", safety_level = "crawler")
  expect_identical(nrow(rdf_rows(v)), 1L)
})

test_that("strict refuses the chain and does not note a followed downgrade", {
  local_fake_ssrfr(rdf_downgrade_chain())
  v <- robots_validate_url("https://a/x")
  expect_true("acquisition_redirect_downgrade" %in% v$diagnostics$code)
  expect_identical(nrow(rdf_rows(v)), 0L)
  expect_identical(v$documents$validation_status, "not_validated")
})

test_that("an http -> https upgrade is noted by neither code", {
  local_fake_ssrfr(rdf_router(list(
    "http://a/robots.txt" = rdf_moved("https://a/robots.txt"),
    "https://a/robots.txt" = rdf_ok()
  )))
  for (level in c("strict", "crawler")) {
    v <- robots_validate_url("http://a/x", safety_level = level)
    expect_identical(nrow(rdf_rows(v)), 0L, label = level)
    expect_false("acquisition_redirect_downgrade" %in% v$diagnostics$code,
                 label = level)
  }
})

test_that("crawler: a downgrade that was not followed is not noted", {
  # Five same-scheme hops, then a sixth to http: over budget, no body.
  routes <- list("https://a/robots.txt" = rdf_moved("https://a/1"))
  for (i in 1:4) {
    routes[[sprintf("https://a/%d", i)]] <- rdf_moved(
      sprintf("https://a/%d", i + 1L)
    )
  }
  routes[["https://a/5"]] <- rdf_moved("http://a/6")
  local_fake_ssrfr(rdf_router(routes))
  v <- robots_validate_url("https://a/x", safety_level = "crawler")
  expect_true("acquisition_redirect_over_budget" %in% v$diagnostics$code)
  expect_identical(nrow(rdf_rows(v)), 0L)

  # A loop whose closing hop is a downgrade back to the first URL.
  local_fake_ssrfr(rdf_router(list(
    "http://a/robots.txt" = rdf_moved("https://a/r2"),
    "https://a/r2" = rdf_moved("http://a/robots.txt")
  )))
  v <- robots_validate_url("http://a/x", safety_level = "crawler")
  expect_true("acquisition_redirect_loop" %in% v$diagnostics$code)
  expect_identical(nrow(rdf_rows(v)), 0L)
})

# --- redirect_downgrade_diagnostic() -----------------------------------------

test_that("only the first redirect_count hops count as followed", {
  hops <- list(
    rdf_hop("https://a/robots.txt", "https://a/r2"),
    rdf_hop("https://a/r2", "http://a/r3")
  )
  expect_null(redirect_downgrade_diagnostic(rdf_source(hops, 1L)))
  row <- redirect_downgrade_diagnostic(rdf_source(hops, 2L))
  expect_identical(row$code, "redirect_downgrade_followed")
  expect_identical(row$severity, "info")
  expect_true(grepl("https://a/r2 -> http://a/r3", row$message, fixed = TRUE))
})

test_that("schemes compare case-insensitively; odd hops do not error", {
  row <- redirect_downgrade_diagnostic(rdf_source(
    list(rdf_hop("HTTPS://a/robots.txt", "Http://a/r")), 1L
  ))
  expect_identical(row$code, "redirect_downgrade_followed")
  expect_true(grepl("HTTPS://a/robots.txt -> Http://a/r", row$message,
                    fixed = TRUE))

  expect_null(redirect_downgrade_diagnostic(rdf_source(
    list(rdf_hop("https://a/robots.txt", NA_character_)), 1L
  )))
  expect_null(redirect_downgrade_diagnostic(rdf_source(list(), 0L)))
  expect_null(redirect_downgrade_diagnostic(rdf_source(
    list(rdf_hop("https://[::1]/robots.txt", "https://xn--bcher-kva.de/r")),
    1L
  )))
  row <- redirect_downgrade_diagnostic(rdf_source(
    list(rdf_hop("https://[2001:db8::1]/robots.txt",
                 "http://xn--bcher-kva.de/r")),
    1L
  ))
  expect_true(grepl(
    "https://[2001:db8::1]/robots.txt -> http://xn--bcher-kva.de/r",
    row$message, fixed = TRUE
  ))
})

test_that("a raw Location with invalid UTF-8 or leading space has a scheme", {
  expect_identical(redirect_url_scheme("http://a/\xff\xfe"), "http")
  expect_identical(redirect_url_scheme(" http://a/r"), "http")
  expect_identical(redirect_url_scheme("\thttps://a/r"), "https")
  expect_identical(redirect_url_scheme("/relative"), NA_character_)
  row <- redirect_downgrade_diagnostic(rdf_source(
    list(rdf_hop("https://a/robots.txt", "http://a/\xff")), 1L
  ))
  expect_identical(row$code, "redirect_downgrade_followed")
})

# --- the robots frame --------------------------------------------------------

test_that("every legacy robots frame carries redirect_hops before body", {
  local_fake_ssrfr(rdf_downgrade_chain())
  fetch <- robots_fetch("https://a/x", safety_level = "crawler")
  n <- ncol(fetch$robots)
  expect_identical(names(fetch$robots)[(n - 1L):n], c("redirect_hops", "body"))
  expect_type(fetch$robots$redirect_hops, "list")

  url <- allowed_by_robots_url("https://a/private/x", "Googlebot",
                               safety_level = "crawler")
  text <- allowed_by_robots_text(rdf_body, "https://a/private/x", "Googlebot")
  v1 <- robots_evaluate_url_v1("https://a/private/x", "Googlebot", "google",
                               "google", safety_level = "crawler")
  legacy <- as_legacy_robots_decisions_v1(v1)
  expect_named(url$robots, names(fetch$robots))
  expect_named(text$robots, names(fetch$robots))
  expect_named(legacy$robots, names(fetch$robots))

  expect_identical(fetch$robots$redirect_hops, v1$evidence$redirect_hops)
  expect_identical(url$robots$redirect_hops, v1$evidence$redirect_hops)
  expect_identical(legacy$robots$redirect_hops, v1$evidence$redirect_hops)
  hop <- fetch$robots$redirect_hops[[1L]][[1L]]
  expect_identical(hop$from_url, "https://a/robots.txt")
  expect_identical(hop$status, 301L)
  expect_identical(hop$location_target, "http://a/robots.txt")

  expect_identical(text$robots$redirect_hops, list(list()))

  empty <- robots_fetch(character())
  expect_type(empty$robots$redirect_hops, "list")
  expect_length(empty$robots$redirect_hops, 0L)
})
