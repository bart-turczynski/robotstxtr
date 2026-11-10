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

# A one-row source as the robots frame carries it, for the cases the fake
# cannot reach (the guard refuses an IP literal and a non-default port).
redirect_source <- function(robots_url, effective_url, content_flag = NA) {
  data.frame(
    source_id = "s1", robots_url = robots_url, effective_url = effective_url,
    content_flag = as.character(content_flag), stringsAsFactors = FALSE
  )
}

redirect_case <- function(robots_url, effective_url, content_flag = NA) {
  redirect_host_diagnostic(
    redirect_source(robots_url, effective_url, content_flag)
  )
}

test_that("ROBO-gokbvzcb: a redirect to another site is a warning", {
  v <- redirect_validate(
    "http://example.com/page", "http://example.com/robots.txt",
    "http://example.net/robots.txt"
  )
  expect_identical(v$documents$effective_url, "http://example.net/robots.txt")
  d <- redirect_rows(v)
  expect_identical(d$code, "redirect_cross_site")
  expect_identical(d$severity, "warning")
  expect_identical(d$line, NA_integer_)
  expect_match(d$message, "http://example.com/robots.txt", fixed = TRUE)
  expect_match(d$message, "http://example.net/robots.txt", fixed = TRUE)
  expect_match(d$message, "Google is inferred", fixed = TRUE)
  expect_match(d$message, "Bing is not documented", fixed = TRUE)
  expect_match(d$message, "Yandex (documented", fixed = TRUE)
  expect_no_match(d$message, "effectively missing", fixed = TRUE)
  # The document row counts the warning; the rules themselves are clean.
  expect_identical(v$documents$validation_status, "warning")
  expect_identical(v$documents$warning_count, 1L)
  expect_identical(v$documents$error_count, 0L)
  expect_identical(v$documents$diagnostic_count, nrow(v$diagnostics))
  expect_identical(v$map$validation_status, "warning")
})

test_that("ROBO-gokbvzcb: another site's HTML page is a missing robots.txt", {
  v <- redirect_validate(
    "http://example.com/page", "http://example.com/robots.txt",
    "https://example.org/landing", body = redirect_html_body(),
    type = "text/html"
  )
  d <- redirect_rows(v)
  expect_identical(d$code, "redirect_cross_site")
  expect_identical(d$severity, "warning")
  expect_match(d$message, "effectively missing", fixed = TRUE)
})

test_that("ROBO-gokbvzcb: a cross-site warning does not need a body", {
  # content_flag is NA for an empty body; the warning stands on the URLs.
  v <- redirect_validate(
    "http://example.com/page", "http://example.com/robots.txt",
    "http://example.net/robots.txt", body = raw()
  )
  d <- redirect_rows(v)
  expect_identical(d$code, "redirect_cross_site")
  expect_identical(d$severity, "warning")
})

test_that("ROBO-gokbvzcb: a www redirect is the same site, info", {
  v <- redirect_validate(
    "http://example.com/page", "http://example.com/robots.txt",
    "http://www.example.com/robots.txt"
  )
  d <- redirect_rows(v)
  expect_identical(d$code, "redirect_same_site")
  expect_identical(d$severity, "info")
  expect_identical(v$documents$validation_status, "valid")
  # And back from www to the bare domain.
  v <- redirect_validate(
    "http://www.example.com/page", "http://www.example.com/robots.txt",
    "https://example.com/robots.txt"
  )
  expect_identical(redirect_rows(v)$code, "redirect_same_site")
})

test_that("ROBO-gokbvzcb: another subdomain is the same site", {
  v <- redirect_validate(
    "http://shop.example.com/page", "http://shop.example.com/robots.txt",
    "http://static.example.com/robots.txt"
  )
  expect_identical(redirect_rows(v)$code, "redirect_same_site")
})

test_that("ROBO-gokbvzcb: the Public Suffix List decides the site", {
  # co.uk is a public suffix, so the registrable domain is example.co.uk.
  v <- redirect_validate(
    "http://a.example.co.uk/page", "http://a.example.co.uk/robots.txt",
    "http://b.example.co.uk/robots.txt"
  )
  expect_identical(redirect_rows(v)$code, "redirect_same_site")
  # The last two labels agree here (co.uk), but the sites do not.
  v <- redirect_validate(
    "http://a.example.co.uk/page", "http://a.example.co.uk/robots.txt",
    "http://a.example-other.co.uk/robots.txt"
  )
  d <- redirect_rows(v)
  expect_identical(d$code, "redirect_cross_site")
  expect_identical(d$severity, "warning")
})

test_that("ROBO-gokbvzcb: another path on the same host is info", {
  v <- redirect_validate(
    "http://example.com/page", "http://example.com/robots.txt",
    "http://example.com/robots-legacy.txt"
  )
  d <- redirect_rows(v)
  expect_identical(d$code, "redirect_other_path")
  expect_identical(d$severity, "info")
  expect_identical(v$documents$validation_status, "valid")
})

test_that("ROBO-gokbvzcb: a catch-all to an HTML home page is a warning", {
  v <- redirect_validate(
    "http://example.com/page", "http://example.com/robots.txt",
    "https://example.com/", body = redirect_html_body(), type = "text/html"
  )
  d <- redirect_rows(v)
  expect_identical(d$code, "redirect_other_path")
  expect_identical(d$severity, "warning")
  expect_match(d$message, "effectively missing", fixed = TRUE)
  # The body's own html_body warning stays beside it.
  expect_identical(sum(v$diagnostics$code == "html_body"), 1L)
})

test_that("ROBO-gokbvzcb: an http to https redirect is not reported", {
  v <- redirect_validate(
    "http://example.com/page", "http://example.com/robots.txt",
    "https://example.com/robots.txt"
  )
  expect_identical(nrow(redirect_rows(v)), 0L)
  expect_identical(v$documents$validation_status, "valid")
})

test_that("ROBO-gokbvzcb: letter case and IDN in the target are no change", {
  local_fake_ssrfr(function(req) {
    if (identical(req$url, "http://example.com/robots.txt")) {
      fake_response(
        301L, url = req$url,
        headers = list(Location = "https://EXAMPLE.COM/robots.txt")
      )
    } else {
      # The hop resolves the Location, lower-casing the host.
      expect_identical(req$url, "https://example.com/robots.txt")
      fake_response(200L, url = req$url, body = redirect_rules_body)
    }
  })
  v <- robots_validate_url("http://example.com/page")
  expect_identical(nrow(redirect_rows(v)), 0L)
  expect_null(redirect_case(
    "http://example.com/robots.txt", "https://EXAMPLE.COM/robots.txt"
  ))
  expect_null(redirect_case(
    "http://xn--bcher-kva.example.com/robots.txt",
    "https://bücher.EXAMPLE.com/robots.txt"
  ))
})

test_that("ROBO-gokbvzcb: a port change alone is not reported", {
  expect_null(redirect_case(
    "http://example.com/robots.txt", "http://example.com:8080/robots.txt"
  ))
})

test_that("ROBO-gokbvzcb: an IP literal is compared as a whole host", {
  d <- redirect_case(
    "http://example.com/robots.txt", "http://192.0.2.1/robots.txt"
  )
  expect_identical(d$code, "redirect_cross_site")
  d <- redirect_case(
    "http://192.0.2.1/robots.txt", "http://192.0.2.2/robots.txt"
  )
  expect_identical(d$code, "redirect_cross_site")
  # A name under no listed suffix has no registrable domain either.
  d <- redirect_case(
    "http://a.example/robots.txt", "http://b.example/robots.txt"
  )
  expect_identical(d$code, "redirect_cross_site")
})

test_that("ROBO-gokbvzcb: no URL to compare means no diagnostic", {
  expect_null(redirect_case("http://example.com/robots.txt", NA_character_))
  expect_null(redirect_case(NA_character_, "http://example.net/robots.txt"))
  expect_null(redirect_case(
    "http://example.com/robots.txt", "http://example.com/robots.txt"
  ))
  x <- robots_validate_text(redirect_rules_body)
  expect_identical(nrow(redirect_rows(x)), 0L)
})

test_that("ROBO-gokbvzcb: a shared origin gets one diagnostic", {
  local_fake_ssrfr(redirect_handler(
    "http://example.com/robots.txt", "http://example.net/robots.txt"
  ))
  v <- robots_validate_url(
    c("http://example.com/a", "http://example.com/b")
  )
  expect_identical(nrow(v$documents), 1L)
  expect_identical(redirect_rows(v)$code, "redirect_cross_site")
  expect_identical(v$map$validation_status, c("warning", "warning"))
})

test_that("ROBO-gokbvzcb: a redirect that ends with no body is unchanged", {
  local_fake_ssrfr(function(req) {
    if (identical(req$url, "http://example.com/robots.txt")) {
      fake_response(
        301L, url = req$url,
        headers = list(Location = "http://example.net/robots.txt")
      )
    } else {
      fake_response(404L, url = req$url)
    }
  })
  v <- robots_validate_url("http://example.com/page")
  expect_identical(v$diagnostics$code, "acquisition_missing")
})
