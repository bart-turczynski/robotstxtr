# ROBO-gokbvzcb: a robots.txt fetch that redirected to another path, host or
# site. Every host is synthetic, and each case runs through the ssrfr fake
# (helper-fake-ssrfr.R): `from` answers a 301 to `to`, which answers 200.

redirect_rules_body <- "User-agent: *\nDisallow: /private/\n"

redirect_handler <- function(from, to, body = redirect_rules_body,
                             type = "text/plain") {
  function(req) {
    if (identical(req$url, from)) {
      fake_response(301L, url = req$url, headers = list(Location = to))
    } else if (identical(req$url, to)) {
      fake_response(
        200L, url = req$url, headers = list(`Content-Type` = type),
        body = body
      )
    } else {
      stop(sprintf("unexpected request URL in mock: %s", req$url))
    }
  }
}

redirect_validate <- function(input, from, to, body = redirect_rules_body,
                              type = "text/plain") {
  local_fake_ssrfr(redirect_handler(from, to, body, type))
  robots_validate_url(input)
}

redirect_rows <- function(v) {
  v$diagnostics[startsWith(v$diagnostics$code, "redirect_"), , drop = FALSE]
}

redirect_html_body <- function() {
  readBin(
    test_path("fixtures/edge-cases/redirect-cross-host-html.txt"), "raw",
    n = 1e5
  )
}

test_that("ROBO-gokbvzcb: a redirect to another site is not reported", {
  # known gap (ROBO-gokbvzcb): no diagnostic names the redirect
  v <- redirect_validate(
    "http://example.com/page", "http://example.com/robots.txt",
    "http://example.net/robots.txt"
  )
  expect_identical(v$documents$effective_url, "http://example.net/robots.txt")
  expect_identical(nrow(redirect_rows(v)), 0L)
  expect_identical(v$documents$validation_status, "valid")
})

test_that("ROBO-gokbvzcb: a www redirect is not reported", {
  # known gap (ROBO-gokbvzcb): no diagnostic names the redirect
  v <- redirect_validate(
    "http://example.com/page", "http://example.com/robots.txt",
    "http://www.example.com/robots.txt"
  )
  expect_identical(nrow(redirect_rows(v)), 0L)
})

test_that("ROBO-gokbvzcb: a redirect to the home page is not reported", {
  # known gap (ROBO-gokbvzcb): only html_body names the landing page
  v <- redirect_validate(
    "http://example.com/page", "http://example.com/robots.txt",
    "http://example.com/", body = redirect_html_body(), type = "text/html"
  )
  expect_identical(nrow(redirect_rows(v)), 0L)
  expect_true("html_body" %in% v$diagnostics$code)
})

test_that("ROBO-gokbvzcb: an http to https redirect is not reported", {
  v <- redirect_validate(
    "http://example.com/page", "http://example.com/robots.txt",
    "https://example.com/robots.txt"
  )
  expect_identical(nrow(redirect_rows(v)), 0L)
  expect_identical(v$documents$validation_status, "valid")
})
