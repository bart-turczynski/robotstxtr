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
    # deparse() at its default width, as the pinned digests were made.
    return(paste(vapply(v, function(e) {
      paste(deparse(e), collapse = "") # nolint: paste_linter.
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

test_that("ROBO-ybhwztid: by default a cross-site redirect is not followed", {
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
  # destination_robots is the last argument, FALSE by default, and the v1
  # facades and robots_compare_fetches() do not take it.
  expect_named(
    formals(robots_fetch),
    c("url", "timeout", "max_bytes", "fetch_user_agent", "ssrf_guard",
      "safety_level", "fetch_allow_ranges", "destination_robots")
  )
  expect_named(
    formals(allowed_by_robots_url),
    c("url", "user_agent", "timeout", "max_bytes", "fetch_user_agent",
      "ssrf_guard", "safety_level", "fetch_allow_ranges",
      "destination_robots")
  )
  expect_named(
    formals(robots_validate_url),
    c("url", "timeout", "max_bytes", "fetch_user_agent", "ssrf_guard",
      "safety_level", "fetch_allow_ranges", "destination_robots")
  )
  for (f in list(robots_fetch, allowed_by_robots_url, robots_validate_url)) {
    expect_false(formals(f)$destination_robots)
  }
  for (f in list(robots_evaluate_url_v1, robots_compare_fetches)) {
    expect_false("destination_robots" %in% names(formals(f)))
  }
})

# --- The opt-in destination read --------------------------------------------
#
# Symmetry rule: not testable on bing or yandex. The destination read is a
# fetch-stage option of robots_fetch(), robots_validate_url() and
# allowed_by_robots_url() only; robots_evaluate_url_v1() takes no such
# argument (the v1 evidence schema stays as it is), and
# allowed_by_robots_url() matches with the one Google matcher.

dest_fetch <- function(routes, url = dest_inputs, ...) {
  log <- dest_log()
  local_fake_ssrfr(dest_router(routes, log))
  default <- robots_fetch(url, ...)
  log$urls <- character()
  opted <- robots_fetch(url, ..., destination_robots = TRUE)
  list(default = default, opted = opted, urls = log$urls)
}

dest_three <- c(
  "http://example.com/robots.txt", "http://example.net/",
  "http://example.net/robots.txt"
)

test_that("ROBO-ybhwztid: FALSE is the default and changes nothing", {
  log <- dest_log()
  local_fake_ssrfr(dest_router(dest_routes(), log))
  f <- robots_fetch(dest_inputs, destination_robots = FALSE)
  expect_identical(dest_digest(f), "0cbb7a5399de7ce6a8db7e77cd05fafa")
  d <- allowed_by_robots_url(dest_inputs, "my-bot", destination_robots = FALSE)
  expect_identical(dest_digest(d), "13e24cbb7e0ae0f5ceda503f152b5b39")
  v <- robots_validate_url(dest_inputs, destination_robots = FALSE)
  expect_named(v, c("map", "documents", "diagnostics"))
  expect_length(log$urls, 6L)
})

test_that("ROBO-ybhwztid: a destination serving rules is read once, apart", {
  run <- dest_fetch(dest_routes())
  expect_identical(run$urls, dest_three)
  f <- run$opted
  expect_named(f, c("map", "robots", "destinations", "destination_map"))
  # The origin's own rows are those of the default call.
  expect_identical(f$map, run$default$map)
  expect_identical(f$robots, run$default$robots)
  dest <- f$destinations
  expect_named(dest, names(f$robots))
  expect_identical(dest$source_id, "destination_1")
  expect_identical(dest$source_type, "redirect_destination")
  expect_identical(dest$robots_url, "http://example.net/robots.txt")
  expect_identical(dest$effective_url, "http://example.net/robots.txt")
  expect_identical(dest$fetch_outcome, "fetched")
  expect_identical(dest$body[[1L]], charToRaw(dest_rules_body))
  expect_identical(
    f$destination_map,
    data.frame(
      origin_source_id = "robots_1", destination_source_id = "destination_1",
      stringsAsFactors = FALSE
    )
  )
})

test_that("ROBO-ybhwztid: the destination's decisions are their own columns", {
  log <- dest_log()
  local_fake_ssrfr(dest_router(dest_routes(), log))
  default <- allowed_by_robots_url(dest_inputs, "my-bot")
  d <- allowed_by_robots_url(dest_inputs, "my-bot", destination_robots = TRUE)
  expect_named(
    d, c("results", "robots", "destinations", "destination_map")
  )
  r <- d$results
  expect_identical(r[names(default$results)], default$results)
  expect_identical(d$robots, default$robots)
  expect_identical(
    setdiff(names(r), names(default$results)),
    c("destination_source_id", "destination_allowed",
      "destination_decision_source", "destination_matched_line",
      "destination_matched_rule_type", "destination_matched_rule_value")
  )
  # The origin still reads the HTML page it reached: allowed.
  expect_identical(r$allowed, c(TRUE, TRUE))
  expect_identical(r$destination_source_id, rep("destination_1", 2L))
  expect_identical(r$destination_allowed, c(TRUE, FALSE))
  expect_identical(
    r$destination_decision_source, c("default_allow", "rule_disallow")
  )
  expect_identical(r$destination_matched_line, c(NA, 2L))
  expect_identical(r$destination_matched_rule_type, c("none", "disallow"))
  expect_identical(r$destination_matched_rule_value, c(NA, "/private/"))
  expect_identical(d$destinations$source_id, "destination_1")
})

test_that("ROBO-ybhwztid: the destination is validated as a document", {
  log <- dest_log()
  local_fake_ssrfr(dest_router(dest_routes(), log))
  default <- robots_validate_url(dest_inputs)
  v <- robots_validate_url(dest_inputs, destination_robots = TRUE)
  expect_named(v, c(
    "map", "documents", "diagnostics", "destination_documents",
    "destination_diagnostics", "destination_map"
  ))
  expect_identical(v$map, default$map)
  expect_identical(v$documents, default$documents)
  expect_identical(v$diagnostics, default$diagnostics)
  expect_identical(attributes(v)[c("class", "validation_profile")],
                   attributes(default)[c("class", "validation_profile")])
  doc <- v$destination_documents
  expect_named(doc, names(v$documents))
  expect_identical(doc$source_id, "destination_1")
  expect_identical(doc$source_type, "redirect_destination")
  expect_identical(doc$validation_status, "valid")
  expect_named(v$destination_diagnostics, names(v$diagnostics))
  expect_identical(nrow(v$destination_diagnostics), 0L)
  expect_identical(v$destination_map$destination_source_id, "destination_1")
})

test_that("ROBO-ybhwztid: a missing or HTML destination is reported as such", {
  routes <- dest_routes(dest_page("not here", status = 404L))
  log <- dest_log()
  local_fake_ssrfr(dest_router(routes, log))
  d <- allowed_by_robots_url(dest_inputs, "my-bot", destination_robots = TRUE)
  expect_identical(d$destinations$fetch_outcome, "missing")
  expect_identical(d$results$destination_allowed, c(TRUE, TRUE))
  expect_identical(
    d$results$destination_decision_source, rep("missing_allow", 2L)
  )
  expect_identical(d$results$allowed, c(TRUE, TRUE))
  v <- robots_validate_url(dest_inputs, destination_robots = TRUE)
  expect_identical(v$destination_documents$validation_status, "not_validated")
  expect_identical(v$destination_diagnostics$code, "acquisition_missing")
  expect_identical(v$destination_diagnostics$source_id, "destination_1")

  run <- dest_fetch(dest_routes(dest_page(dest_html_body(), "text/html")))
  expect_identical(run$urls, dest_three)
  expect_identical(run$opted$destinations$fetch_outcome, "fetched")
  expect_identical(run$opted$destinations$content_flag, "html")
})

test_that("ROBO-ybhwztid: a redirect ending on a robots.txt is final", {
  routes <- list(
    "http://example.com/robots.txt" =
      dest_moved("http://example.net/robots.txt"),
    "http://example.net/robots.txt" = dest_page(dest_rules_body)
  )
  run <- dest_fetch(routes)
  expect_identical(
    run$urls,
    c("http://example.com/robots.txt", "http://example.net/robots.txt")
  )
  expect_identical(nrow(run$opted$destinations), 0L)
  expect_named(run$opted$destinations, names(run$opted$robots))
  expect_identical(nrow(run$opted$destination_map), 0L)
  log <- dest_log()
  local_fake_ssrfr(dest_router(routes, log))
  d <- allowed_by_robots_url(dest_inputs, "my-bot", destination_robots = TRUE)
  expect_identical(d$results$destination_source_id, rep(NA_character_, 2L))
  expect_identical(d$results$destination_allowed, c(NA, NA))
  expect_length(log$urls, 2L)
})

test_that("ROBO-ybhwztid: same-host and same-site redirects are not followed", {
  same_host <- list(
    "http://example.com/robots.txt" = dest_moved("http://example.com/home"),
    "http://example.com/home" = dest_page(dest_html_body(), "text/html")
  )
  run <- dest_fetch(same_host)
  expect_identical(
    run$urls, c("http://example.com/robots.txt", "http://example.com/home")
  )
  expect_identical(nrow(run$opted$destinations), 0L)
  same_site <- list(
    "http://example.com/robots.txt" = dest_moved("http://www.example.com/"),
    "http://www.example.com/" = dest_page(dest_html_body(), "text/html")
  )
  run <- dest_fetch(same_site)
  expect_identical(
    run$urls, c("http://example.com/robots.txt", "http://www.example.com/")
  )
  expect_identical(nrow(run$opted$destinations), 0L)
})

test_that("ROBO-ybhwztid: the guard's refusal of a destination is reported", {
  refused <- function(req) fake_refusal("private")
  run <- dest_fetch(dest_routes(refused))
  expect_identical(run$urls, dest_three)
  expect_identical(run$opted$robots, run$default$robots)
  dest <- run$opted$destinations
  expect_identical(dest$fetch_outcome, "ssrf_blocked")
  expect_identical(dest$safety_block_reason, "private")
  expect_null(dest$body[[1L]])
  log <- dest_log()
  local_fake_ssrfr(dest_router(dest_routes(refused), log))
  d <- allowed_by_robots_url(dest_inputs, "my-bot", destination_robots = TRUE)
  expect_identical(
    d$results$destination_decision_source, rep("fetch_unknown", 2L)
  )
  expect_identical(d$results$destination_allowed, c(NA, NA))
  expect_identical(d$results$allowed, c(TRUE, TRUE))
})

test_that("ROBO-ybhwztid: the destination fetch keeps the call's policy", {
  # strict refuses the destination's https to http redirect; crawler
  # follows it.
  routes <- list(
    "http://example.com/robots.txt" = dest_moved("https://example.net/"),
    "https://example.net/" = dest_page(dest_html_body(), "text/html"),
    "https://example.net/robots.txt" =
      dest_moved("http://example.net/robots.txt"),
    "http://example.net/robots.txt" = dest_page(dest_rules_body)
  )
  run <- dest_fetch(routes)
  dest <- run$opted$destinations
  expect_identical(dest$robots_url, "https://example.net/robots.txt")
  expect_identical(dest$fetch_outcome, "redirect_error")
  expect_identical(dest$terminal_redirect_reason, "downgrade")
  run <- dest_fetch(routes, safety_level = "crawler")
  dest <- run$opted$destinations
  expect_identical(dest$fetch_outcome, "fetched")
  expect_identical(dest$effective_url, "http://example.net/robots.txt")

  # The fetch user agent and max_bytes reach the destination request.
  log <- dest_log()
  agents <- new.env(parent = emptyenv())
  agents$seen <- character()
  router <- dest_router(dest_routes(dest_page(strrep("Disallow: /a\n", 20L))),
                        log)
  local_fake_ssrfr(function(req) {
    agents$seen <- c(agents$seen, req$user_agent)
    router(req)
  })
  f <- robots_fetch(
    dest_inputs, fetch_user_agent = "audit-bot/1", max_bytes = 30L,
    destination_robots = TRUE
  )
  expect_identical(agents$seen, rep("audit-bot/1", 3L))
  expect_true(f$destinations$body_truncated)
  expect_identical(f$destinations$body_size, 30L)
  expect_identical(f$destinations$max_bytes, 30L)
})

test_that("ROBO-ybhwztid: a destination that redirects again is not followed", {
  routes <- dest_routes(dest_moved("http://example.org/"))
  routes[["http://example.org/"]] <- dest_page(dest_html_body(), "text/html")
  run <- dest_fetch(routes)
  # example.org/robots.txt is never requested: the mock would stop().
  expect_identical(run$urls, c(dest_three, "http://example.org/"))
  dest <- run$opted$destinations
  expect_identical(nrow(dest), 1L)
  expect_identical(dest$effective_url, "http://example.org/")
  expect_identical(dest$content_flag, "html")
  log <- dest_log()
  local_fake_ssrfr(dest_router(routes, log))
  v <- robots_validate_url(dest_inputs, destination_robots = TRUE)
  expect_true("redirect_cross_site" %in% v$destination_diagnostics$code)
  expect_identical(
    unique(v$destination_diagnostics$source_id), "destination_1"
  )
})

test_that("ROBO-ybhwztid: origins sharing a destination share one read", {
  routes <- dest_routes()
  routes[["http://example.org/robots.txt"]] <- dest_moved("http://example.net/")
  run <- dest_fetch(routes, url = c(
    "http://example.com/a", "http://example.org/b", "http://example.com/c"
  ))
  expect_identical(run$urls, c(
    "http://example.com/robots.txt", "http://example.net/",
    "http://example.org/robots.txt", "http://example.net/",
    "http://example.net/robots.txt"
  ))
  expect_identical(nrow(run$opted$destinations), 1L)
  expect_identical(
    run$opted$destination_map,
    data.frame(
      origin_source_id = c("robots_1", "robots_2"),
      destination_source_id = rep("destination_1", 2L),
      stringsAsFactors = FALSE
    )
  )
})

test_that("ROBO-ybhwztid: a destination the call already fetched is reused", {
  run <- dest_fetch(
    dest_routes(), url = c("http://example.com/", "http://example.net/x")
  )
  # PRD 6.5: example.net/robots.txt is requested once per call.
  expect_identical(run$urls, dest_three)
  f <- run$opted
  expect_identical(f$robots, run$default$robots)
  expect_identical(nrow(f$destinations), 1L)
  expect_identical(f$destinations$source_type, "redirect_destination")
  expect_identical(f$destinations$source_id, "destination_1")
  reused <- f$destinations
  reused$source_id <- "robots_2"
  reused$source_type <- "fetched"
  rownames(reused) <- 2L
  expect_identical(reused, f$robots[2L, , drop = FALSE])
  expect_identical(f$destination_map$origin_source_id, "robots_1")
  # The reused row stays a destination: it is not followed up in turn.
  run <- dest_fetch(
    dest_routes(), url = c("http://example.net/x", "http://example.com/")
  )
  expect_identical(
    run$urls, c("http://example.net/robots.txt", dest_three[1:2])
  )
  expect_identical(run$opted$destination_map$origin_source_id, "robots_2")
})

test_that("ROBO-ybhwztid: an origin with no final response is not followed", {
  routes <- list(
    "http://example.com/robots.txt" = function(req) fake_refusal("private"),
    "http://example.org/robots.txt" = function(req) fake_failure("timeout"),
    "http://example.net/robots.txt" =
      dest_moved("http://example.net/robots.txt")
  )
  run <- dest_fetch(routes, url = c(
    "http://example.com/", "http://example.org/", "http://example.net/"
  ))
  expect_identical(nrow(run$opted$destinations), 0L)
  expect_identical(
    run$opted$robots$fetch_outcome,
    c("ssrf_blocked", "timeout", "redirect_error")
  )
  expect_identical(run$urls, c(
    "http://example.com/robots.txt", "http://example.org/robots.txt",
    "http://example.net/robots.txt"
  ))
  # The same failures after a hop to another site: still no final response.
  for (end in list(
    function(req) fake_refusal("private"),
    function(req) fake_failure("timeout"),
    dest_moved("http://example.net/a")
  )) {
    routes <- list(
      "http://example.com/robots.txt" = dest_moved("http://example.net/a"),
      "http://example.net/a" = end
    )
    run <- dest_fetch(routes)
    expect_identical(nrow(run$opted$destinations), 0L)
    expect_false("http://example.net/robots.txt" %in% run$urls)
  }
})

test_that("ROBO-ybhwztid: the trigger needs both a final URL and a status", {
  from <- "http://example.com/robots.txt"
  expect_identical(
    destination_robots_url(from, "http://example.net/", 200L),
    "http://example.net/robots.txt"
  )
  # Acquisition sets both or neither; each is checked on its own anyway.
  expect_identical(
    destination_robots_url(from, "http://example.net/", NA_integer_),
    NA_character_
  )
  expect_identical(
    destination_robots_url(from, NA_character_, 200L), NA_character_
  )
  expect_identical(
    destination_robots_url(from, "not a url", 200L), NA_character_
  )
})

test_that("ROBO-ybhwztid: any final status on another site is followed", {
  routes <- dest_routes()
  routes[["http://example.net/"]] <- dest_page("oops", status = 500L)
  run <- dest_fetch(routes)
  expect_identical(run$opted$robots$fetch_outcome, "http_error")
  expect_identical(run$urls, dest_three)
  expect_identical(run$opted$destinations$fetch_outcome, "fetched")
})

test_that("ROBO-ybhwztid: a 3xx too large after a cross-site hop is followed", {
  # body_too_large keeps the final URL and status, so it has a destination.
  routes <- dest_routes()
  routes[["http://example.net/"]] <- function(req) {
    fake_response(
      302L, url = req$url, headers = list(Location = "/elsewhere"),
      body = strrep("x", 100L)
    )
  }
  run <- dest_fetch(routes, max_bytes = 50L)
  expect_identical(run$opted$robots$fetch_outcome, "body_too_large")
  expect_identical(run$opted$robots$effective_url, "http://example.net/")
  expect_identical(run$urls, dest_three)
  expect_identical(run$opted$destinations$fetch_outcome, "fetched")
})

test_that("ROBO-ybhwztid: destination bodies go through the same readers", {
  # An empty body, a NUL byte, invalid UTF-8 and a body cut at max_bytes: the
  # destination's document and rows are those example.net/robots.txt gets
  # when it is requested as an origin, apart from the source naming.
  bodies <- list(
    raw(0), as.raw(c(0x41, 0x00, 0x0a)), as.raw(c(0xff, 0xfe, 0x0a)),
    charToRaw(strrep("Disallow: /a\n", 20L))
  )
  for (body in bodies) {
    log <- dest_log()
    local_fake_ssrfr(dest_router(dest_routes(dest_page(body)), log))
    v <- robots_validate_url(
      dest_inputs, max_bytes = 100L, destination_robots = TRUE
    )
    origin <- robots_validate_url("http://example.net/x", max_bytes = 100L)
    doc <- v$destination_documents
    expect_identical(doc$byte_size, min(length(body), 100L))
    doc$source_id <- "robots_1"
    doc$source_type <- "fetched"
    expect_identical(doc, origin$documents)
    rows <- v$destination_diagnostics
    rows$source_id <- rep("robots_1", nrow(rows))
    expect_identical(rows, origin$diagnostics)

    d <- allowed_by_robots_url(
      dest_inputs, "my-bot", max_bytes = 100L, destination_robots = TRUE
    )
    o <- allowed_by_robots_url(
      sub("example.com", "example.net", dest_inputs, fixed = TRUE), "my-bot",
      max_bytes = 100L
    )
    expect_identical(d$results$destination_allowed, o$results$allowed)
    expect_identical(
      d$results$destination_decision_source, o$results$decision_source
    )
  }
})

test_that("ROBO-ybhwztid: an IDN destination is keyed in its ASCII form", {
  routes <- list(
    "http://example.com/robots.txt" =
      dest_moved("http://xn--bcher-kva.example/"),
    "http://xn--bcher-kva.example/" =
      dest_page(dest_html_body(), "text/html"),
    "http://xn--bcher-kva.example/robots.txt" = dest_page(dest_rules_body)
  )
  run <- dest_fetch(routes)
  expect_identical(
    run$opted$destinations$robots_url,
    "http://xn--bcher-kva.example/robots.txt"
  )
})

test_that("ROBO-ybhwztid: destination_robots must be TRUE or FALSE", {
  log <- dest_log()
  local_fake_ssrfr(dest_router(dest_routes(), log))
  for (bad in list(NA, "yes", c(TRUE, FALSE), 1L, NULL)) {
    expect_error(
      robots_fetch(dest_inputs, destination_robots = bad),
      class = "robotstxtr_invalid_destination_robots"
    )
    expect_error(
      robots_validate_url(dest_inputs, destination_robots = bad),
      class = "robotstxtr_invalid_destination_robots"
    )
    expect_error(
      allowed_by_robots_url(dest_inputs, "my-bot", destination_robots = bad),
      class = "robotstxtr_invalid_destination_robots"
    )
  }
  expect_identical(log$urls, character())
})

test_that("ROBO-ybhwztid: an empty call has empty destination frames", {
  f <- robots_fetch(character(), destination_robots = TRUE)
  expect_identical(nrow(f$destinations), 0L)
  expect_named(f$destinations, names(f$robots))
  expect_named(
    f$destination_map, c("origin_source_id", "destination_source_id")
  )
  d <- allowed_by_robots_url(character(), "bot", destination_robots = TRUE)
  expect_identical(nrow(d$results), 0L)
  expect_true("destination_allowed" %in% names(d$results))
  v <- robots_validate_url(character(), destination_robots = TRUE)
  expect_identical(nrow(v$destination_documents), 0L)
})

# --- Review round 1 ---------------------------------------------------------

test_that("ROBO-ybhwztid: a robots.txt reached with a query is final too", {
  # The path decides, not the whole URL: the query and fragment are ignored.
  routes <- list(
    "http://example.com/robots.txt" =
      dest_moved("http://example.net/robots.txt?x=1"),
    "http://example.net/robots.txt?x=1" = dest_page(dest_rules_body)
  )
  run <- dest_fetch(routes)
  expect_identical(run$urls, c(
    "http://example.com/robots.txt", "http://example.net/robots.txt?x=1"
  ))
  expect_identical(nrow(run$opted$destinations), 0L)
  expect_identical(nrow(run$opted$destination_map), 0L)
  expect_identical(
    robots_url_key("http://example.net/robots.txt#f"),
    "http://example.net/robots.txt"
  )
  expect_identical(
    robots_url_key("http://example.net/Robots.txt"), NA_character_
  )
  expect_identical(robots_url_key("http://example.net/"), NA_character_)
})

test_that("ROBO-ybhwztid: a destination the origin's chain passed is reused", {
  # example.com/robots.txt -> example.net/robots.txt -> example.net/ (HTML):
  # example.net/robots.txt was already requested, so it is not asked again.
  routes <- list(
    "http://example.com/robots.txt" =
      dest_moved("http://example.net/robots.txt"),
    "http://example.net/robots.txt" = function(req) {
      fake_response(
        302L, url = req$url, headers = list(Location = "http://example.net/")
      )
    },
    "http://example.net/" = dest_page(dest_html_body(), "text/html")
  )
  run <- dest_fetch(routes)
  expect_identical(run$urls, c(
    "http://example.com/robots.txt", "http://example.net/robots.txt",
    "http://example.net/"
  ))
  origin <- run$opted$robots
  expect_identical(origin, run$default$robots)
  expect_identical(origin$redirect_count, 2L)
  dest <- run$opted$destinations
  expect_identical(dest$robots_url, "http://example.net/robots.txt")
  for (col in c("effective_url", "http_status", "fetch_outcome",
                "content_flag", "body")) {
    expect_identical(dest[[col]], origin[[col]], label = col)
  }
  # The rest of the chain from that hop: one redirect, logged from there.
  expect_identical(dest$redirect_count, 1L)
  expect_identical(
    vapply(dest$redirect_hops[[1L]], function(h) h$from_url, character(1L)),
    "http://example.net/robots.txt"
  )
  expect_identical(run$opted$destination_map$origin_source_id, "robots_1")
  expect_identical(
    run$opted$destination_map$destination_source_id, "destination_1"
  )
  # An origin chain that passed a different path is no reuse.
  expect_null(chain_from_hop(
    list(
      redirect_count = 2L,
      redirect_hops = list(
        list(from_url = "http://example.com/robots.txt"),
        list(from_url = "http://example.net/robots.txt.bak")
      )
    ),
    "http://example.net/robots.txt"
  ))
})

test_that("ROBO-ybhwztid: a reused body is copied and validated once more", {
  # The documented choice: each destination row stands on its own, so a
  # reused origin result is stored again under `destinations` and validated
  # again under the destination's source_id.
  log <- dest_log()
  local_fake_ssrfr(dest_router(dest_routes(), log))
  inputs <- c("http://example.com/", "http://example.net/x")
  v <- robots_validate_url(inputs, destination_robots = TRUE)
  expect_length(log$urls, 3L)
  expect_identical(v$documents$source_id, c("robots_1", "robots_2"))
  expect_identical(v$destination_documents$source_id, "destination_1")
  same <- v$destination_documents
  same$source_id <- "robots_2"
  same$source_type <- "fetched"
  rownames(same) <- 2L
  expect_identical(same, v$documents[2L, , drop = FALSE])
  log$urls <- character()
  d <- allowed_by_robots_url(inputs, "my-bot", destination_robots = TRUE)
  expect_identical(d$destinations$body, d$robots$body[2L])
  expect_length(log$urls, 3L)
})

test_that("ROBO-ybhwztid: robots_body() reads a destination body", {
  log <- dest_log()
  local_fake_ssrfr(dest_router(dest_routes(), log))
  d <- allowed_by_robots_url(dest_inputs, "my-bot", destination_robots = TRUE)
  id <- d$results$destination_source_id[[1L]]
  expect_identical(robots_body(d, id, raw = TRUE), charToRaw(dest_rules_body))
  expect_identical(robots_body(d, id, n = Inf), dest_rules_body)
  # NULL still means the one origin source, never a destination.
  expect_identical(robots_body(d, raw = TRUE), dest_html_body())
  expect_error(
    robots_body(d, "destination_2"),
    "available: \"robots_1\", \"destination_1\"",
    fixed = TRUE, class = "robotstxtr_unknown_source"
  )
})

test_that("ROBO-ybhwztid: a bad destination_robots is the first error", {
  # Each entry point checks it first, so one bad call raises one class.
  log <- dest_log()
  local_fake_ssrfr(dest_router(dest_routes(), log))
  calls <- list(
    function(...) robots_fetch(...),
    function(...) robots_validate_url(...),
    function(...) allowed_by_robots_url(user_agent = "my-bot", ...)
  )
  for (call in calls) {
    expect_error(
      call(url = dest_inputs, timeout = -1, destination_robots = NA),
      class = "robotstxtr_invalid_destination_robots"
    )
    expect_error(
      call(url = 1, safety_level = "nope", destination_robots = NA),
      class = "robotstxtr_invalid_destination_robots"
    )
  }
  expect_identical(log$urls, character())
})

test_that("ROBO-ybhwztid: rows with no destination get typed NA columns", {
  log <- dest_log()
  local_fake_ssrfr(dest_router(dest_routes(), log))
  # No eligible row: nothing is fetched, nothing is followed up.
  d <- allowed_by_robots_url(
    dest_inputs, c("", NA), destination_robots = TRUE
  )
  expect_identical(log$urls, character())
  r <- d$results
  expect_identical(r$destination_source_id, rep(NA_character_, 2L))
  expect_identical(r$destination_allowed, c(NA, NA))
  expect_identical(r$destination_decision_source, rep(NA_character_, 2L))
  expect_identical(r$destination_matched_line, rep(NA_integer_, 2L))
  expect_identical(r$destination_matched_rule_type, rep(NA_character_, 2L))
  expect_identical(r$destination_matched_rule_value, rep(NA_character_, 2L))
  # A row whose user agent is invalid stays detached beside one followed up.
  d <- allowed_by_robots_url(
    dest_inputs, c("my-bot", ""), destination_robots = TRUE
  )
  expect_identical(d$results$destination_source_id, c("destination_1", NA))
  expect_identical(d$results$destination_allowed, c(TRUE, NA))
})
