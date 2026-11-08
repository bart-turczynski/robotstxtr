# ROBO-ajcacryw: a redirect whose Location is an IPv6 literal without a zone
# ID. The zoned forms are pinned in test-ssrf-atvfjuuw.R; these pin the unzoned
# literals (loopback, the documentation range, relative and uppercase-scheme
# forms) and the malformed brackets, through robots_fetch() and
# robots_evaluate_url_v1(). The "no error" pins hold because ssrfr's dep_call()
# turns a parse failure into a refusal; robotstxtr's own guard is the tryCatch
# in acquire_location_target().
#
# The fake cases check each hop with ssrf_inspect_url() at the ssrfr boundary
# (helper-fake-ssrfr.R). The loopback case drives the real ssrf_prepare_hop()
# against a webfakes server, so the target is refused before any connection.

# The fake answers the robots.txt of http://a/x with a 301 to `location`. A
# request for any other URL fails the test, so a refused target is never sent.
local_redirect_to <- function(location, env = parent.frame()) {
  force(location)
  local_fake_ssrfr(function(req) {
    if (!identical(req$url, "http://a/robots.txt")) {
      stop(sprintf("unexpected request URL in fake: %s", req$url))
    }
    fake_response(301L, headers = list(Location = location))
  }, env = env)
}

test_that("a redirect to the IPv6 loopback literal is refused, not fetched", {
  local_redirect_to("http://[::1]/robots.txt")
  x <- expect_no_error(robots_fetch("http://a/x"))
  expect_identical(x$robots$fetch_outcome, "ssrf_blocked")
  expect_identical(x$robots$redirect_count, 1L)
  expect_identical(
    x$robots$error_message, "Blocked by SSRF guard (loopback)."
  )
})

test_that("a redirect to the IPv6 documentation literal is refused", {
  local_redirect_to("http://[2001:db8::1]/robots.txt")
  x <- expect_no_error(robots_fetch("http://a/x"))
  expect_identical(x$robots$fetch_outcome, "ssrf_blocked")
  expect_identical(x$robots$redirect_count, 1L)
  expect_identical(
    x$robots$error_message, "Blocked by SSRF guard (reserved)."
  )
})

test_that("a relative or uppercase-scheme loopback Location is refused too", {
  for (location in c("//[::1]/x", "HTTP://[::1]/robots.txt")) {
    local_redirect_to(location)
    x <- expect_no_error(robots_fetch("http://a/x"))
    expect_identical(x$robots$fetch_outcome, "ssrf_blocked", info = location)
    expect_identical(x$robots$redirect_count, 1L, info = location)
    expect_identical(
      x$robots$error_message, "Blocked by SSRF guard (loopback).",
      info = location
    )
  }
})

test_that("malformed IPv6 brackets in a Location are refused as parse", {
  malformed <- c(
    "http://[::1/", "http://[]/", "http://[::1]]/", "http://[:::1]/"
  )
  for (location in malformed) {
    local_redirect_to(location)
    x <- expect_no_error(robots_fetch("http://a/x"))
    expect_identical(x$robots$fetch_outcome, "ssrf_blocked", info = location)
    expect_identical(
      x$robots$error_message, "Blocked by SSRF guard (parse).",
      info = location
    )
  }
})

test_that("a non-ASCII byte inside the brackets is refused as parse", {
  local_redirect_to("http://[::1é]/")
  x <- expect_no_error(robots_fetch("http://a/x"))
  expect_identical(x$robots$fetch_outcome, "ssrf_blocked")
  expect_identical(
    x$robots$error_message, "Blocked by SSRF guard (parse)."
  )
})

test_that("a redirect to the IPv6 loopback literal is safety_refused", {
  local_redirect_to("http://[::1]/robots.txt")
  x <- expect_no_error(
    robots_evaluate_url_v1("http://a/x", "Googlebot", "google", "google")
  )
  e <- x$evidence
  expect_identical(e$legacy_fetch_outcome, "ssrf_blocked")
  expect_identical(e$safety_block_reason, "loopback")
  expect_identical(e$evidence_status, "safety_refused")
  expect_identical(e$redirect_count, 1L)
})

test_that("a 301 to the IPv6 loopback literal on the server port is refused", {
  skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$get(webfakes::new_regexp("^/"), function(req, res) {
    port <- sub("^.*:", "", req$get_header("Host"))
    res$set_status(301L)
    res$set_header("Location", sprintf("http://[::1]:%s/robots.txt", port))
    res$send("")
  })
  server <- webfakes::local_app_process(app)
  # The port goes in the Location: local_loopback_policy() allows only this
  # port, and ssrfr checks the port before the address.
  local_loopback_policy(as.integer(server$get_port()))
  # Record each URL the real ssrfr fetches: a refused target that was requested
  # anyway would show up in this list.
  fetched <- new.env(parent = emptyenv())
  fetched$urls <- character()
  local_mocked_bindings(
    acquire_fetch = function(binding) {
      fetched$urls <- c(fetched$urls, binding$url)
      ssrfr::ssrf_fetch(binding)
    },
    .package = "robotstxtr"
  )
  x <- expect_no_error(robots_evaluate_url_v1(
    server$url("/x"), "Googlebot", "google", "google", timeout = 5
  ))
  e <- x$evidence
  expect_identical(e$legacy_fetch_outcome, "ssrf_blocked")
  expect_identical(e$safety_block_reason, "loopback")
  expect_identical(fetched$urls, server$url("/robots.txt"))
})
