# ROBO-ybhwztid: an opt-in read of a redirect destination's own robots.txt.
# Every host is synthetic and every request goes through the ssrfr fake
# (helper-fake-ssrfr.R), whose handler here routes by URL and logs each one,
# so a test can count requests. example.com and example.net are different
# registrable domains under the Public Suffix List; www.example.com is the
# same site as example.com.

dest_rules_body <- "User-agent: *\nDisallow: /private/\n"

dest_html_body <- function() {
  readBin(
    test_path("fixtures/edge-cases/redirect-cross-host-html.txt"), "raw",
    n = 1e5
  )
}

dest_log <- function() {
  log <- new.env(parent = emptyenv())
  log$urls <- character()
  log
}

# `routes` maps a requested URL to a function(req) giving the fake response.
dest_router <- function(routes, log) {
  function(req) {
    log$urls <- c(log$urls, req$url)
    route <- routes[[req$url]]
    if (is.null(route)) {
      stop(sprintf("unexpected request URL in mock: %s", req$url))
    }
    route(req)
  }
}

dest_moved <- function(to) {
  function(req) {
    fake_response(301L, url = req$url, headers = list(Location = to))
  }
}

dest_page <- function(body, type = "text/plain", status = 200L) {
  function(req) {
    fake_response(
      status, url = req$url, headers = list(`Content-Type` = type),
      body = body
    )
  }
}

# example.com/robots.txt moves to example.net's HTML home page.
dest_routes <- function(destination = dest_page(dest_rules_body)) {
  list(
    "http://example.com/robots.txt" = dest_moved("http://example.net/"),
    "http://example.net/" = dest_page(dest_html_body(), "text/html"),
    "http://example.net/robots.txt" = destination
  )
}

dest_values <- function(v) {
  if (is.list(v)) {
    return(paste(vapply(v, function(e) {
      paste(deparse(e), collapse = "")
    }, character(1L)), collapse = "|"))
  }
  paste(ifelse(is.na(v), "<NA>", as.character(v)), collapse = "|")
}

# A text form of every component, column, class and value of a result, and
# its md5: a pin that does not depend on R's serialization format.
dest_digest <- function(x) {
  lines <- c(paste(class(x), collapse = ","), paste(names(x), collapse = ","))
  for (nm in names(x)) {
    frame <- x[[nm]]
    lines <- c(lines, nm, paste(names(frame), collapse = ","))
    for (col in names(frame)) {
      v <- frame[[col]]
      lines <- c(lines, paste0(
        col, ":", paste(class(v), collapse = ","), ":", dest_values(v)
      ))
    }
  }
  file <- tempfile(fileext = ".txt")
  on.exit(unlink(file))
  con <- file(file, open = "wb")
  writeLines(lines, con, useBytes = TRUE)
  close(con)
  unname(tools::md5sum(file))
}

dest_inputs <- c("http://example.com/page", "http://example.com/private/x")

# --- Pins of today's default behavior (green before the argument exists) ----

test_that("ROBO-ybhwztid: by default a cross-site redirect makes no follow-up", {
  log <- dest_log()
  local_fake_ssrfr(dest_router(dest_routes(), log))
  f <- robots_fetch(dest_inputs)
  expect_identical(
    log$urls, c("http://example.com/robots.txt", "http://example.net/")
  )
  expect_named(f, c("map", "robots"))
  expect_identical(f$robots$effective_url, "http://example.net/")
  expect_identical(f$robots$content_flag, "html")
  expect_identical(dest_digest(f), "0cbb7a5399de7ce6a8db7e77cd05fafa")

  log$urls <- character()
  d <- allowed_by_robots_url(dest_inputs, "my-bot")
  expect_identical(
    log$urls, c("http://example.com/robots.txt", "http://example.net/")
  )
  expect_named(d, c("results", "robots"))
  expect_false(any(startsWith(names(d$results), "destination_")))
  expect_identical(d$results$allowed, c(TRUE, TRUE))
  expect_identical(dest_digest(d), "13e24cbb7e0ae0f5ceda503f152b5b39")

  log$urls <- character()
  v <- robots_validate_url(dest_inputs)
  expect_identical(
    log$urls, c("http://example.com/robots.txt", "http://example.net/")
  )
  expect_named(v, c("map", "documents", "diagnostics"))
  expect_true("redirect_cross_site" %in% v$diagnostics$code)
})

test_that("ROBO-ybhwztid: the fetching functions' formals", {
  expect_named(
    formals(robots_fetch),
    c("url", "timeout", "max_bytes", "fetch_user_agent", "ssrf_guard",
      "safety_level", "fetch_allow_ranges")
  )
  expect_named(
    formals(allowed_by_robots_url),
    c("url", "user_agent", "timeout", "max_bytes", "fetch_user_agent",
      "ssrf_guard", "safety_level", "fetch_allow_ranges")
  )
  expect_named(
    formals(robots_validate_url),
    c("url", "timeout", "max_bytes", "fetch_user_agent", "ssrf_guard",
      "safety_level", "fetch_allow_ranges")
  )
})
