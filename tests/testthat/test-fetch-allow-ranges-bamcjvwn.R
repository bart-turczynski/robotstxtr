# ROBO-bamcjvwn: `fetch_allow_ranges` replaces `ssrf_guard = FALSE` (ADR 0001
# section 6, slice 5). A listed CIDR range is passed to ssrfr's
# `allow_ranges` and fetched at both safety levels; an unlisted one is
# refused as before. The metadata host names are never reopened, and an exact
# provider endpoint is refused at validation. `ssrf_guard = FALSE` keeps its
# behavior, names the replacement in its warning, warns a second time under
# "crawler", and is a call-level error together with a non-empty
# `fetch_allow_ranges`.
#
# Every hop goes through local_fake_ssrfr(), which checks it with the real
# ssrfr::ssrf_inspect_url() under the policy acquire_policy() builds, so the
# file is offline.

robots_ok <- function(req) {
  fake_response(200L, body = "user-agent: *\ndisallow: /private\n")
}

# acquire_prepare_hop() fails the test if any hop is prepared.
local_no_hop <- function(env = parent.frame()) {
  local_mocked_bindings(
    acquire_prepare_hop = function(url, policy, request = NULL, from = NULL) {
      stop("must not prepare a hop: ", url)
    },
    .env = env
  )
}

# The value of `expr` and the first class of each warning it raised, in order.
collect_warnings <- function(expr) {
  seen <- new.env(parent = emptyenv())
  seen$classes <- character()
  value <- withCallingHandlers(expr, warning = function(w) {
    seen$classes <- c(seen$classes, class(w)[[1L]])
    invokeRestart("muffleWarning")
  })
  list(value = value, classes = seen$classes)
}

evaluate <- function(url, ...) {
  robots_evaluate_url_v1(url, "Googlebot", "google", "google", ...)
}

safety_levels <- c("strict", "crawler")
refused_status <- c(strict = "safety_refused", crawler = "unreachable_local")

test_that("a listed range is fetched at both safety levels", {
  local_fake_ssrfr(robots_ok)
  for (level in safety_levels) {
    x <- robots_fetch(
      "http://10.1.2.3/x", safety_level = level,
      fetch_allow_ranges = "10.0.0.0/8"
    )
    expect_identical(x$robots$fetch_outcome, "fetched", info = level)
    expect_true(is.na(x$robots$safety_block_reason), info = level)

    e <- evaluate(
      "http://10.1.2.3/x", safety_level = level,
      fetch_allow_ranges = "10.0.0.0/8"
    )$evidence
    expect_identical(e$evidence_status, "usable_body", info = level)
    expect_identical(e$legacy_fetch_outcome, "fetched", info = level)
    expect_true(is.na(e$safety_block_reason), info = level)
  }
})

test_that("an unlisted range is refused and never fetched", {
  local_mocked_bindings(
    acquire_fetch = function(binding) stop("must not fetch: ", binding$url)
  )
  for (level in safety_levels) {
    x <- robots_fetch(
      "http://192.168.0.1/x", safety_level = level,
      fetch_allow_ranges = "10.0.0.0/8"
    )
    expect_identical(x$robots$fetch_outcome, "ssrf_blocked", info = level)
    expect_identical(x$robots$safety_block_reason, "private", info = level)

    e <- evaluate(
      "http://192.168.0.1/x", safety_level = level,
      fetch_allow_ranges = "10.0.0.0/8"
    )$evidence
    expect_identical(e$legacy_fetch_outcome, "ssrf_blocked", info = level)
    expect_identical(e$safety_block_reason, "private", info = level)
    expect_identical(e$evidence_status, refused_status[[level]], info = level)
  }
})

test_that("an IPv6 range reopens only the addresses it lists", {
  local_fake_ssrfr(robots_ok)
  x <- robots_fetch(
    c("http://[fd00::1]/x", "http://[fe80::1]/x"),
    fetch_allow_ranges = "fd00::/8"
  )
  expect_identical(x$robots$fetch_outcome, c("fetched", "ssrf_blocked"))
  expect_identical(x$robots$safety_block_reason, c(NA, "link-local"))
})

test_that("the evidence records fetch_allow_ranges as passed", {
  local_fake_ssrfr(robots_ok)
  ranges <- c("10.0.0.0/8", "fd00::/8", "10.0.0.0/8")
  e <- evaluate("http://10.1.2.3/x", fetch_allow_ranges = ranges)$evidence
  expect_identical(e$fetch_allow_ranges, list(ranges))

  named <- c(intranet = "10.0.0.0/8")
  e <- evaluate("http://10.1.2.3/x", fetch_allow_ranges = named)$evidence
  expect_identical(e$fetch_allow_ranges, list("10.0.0.0/8"))

  e <- evaluate("https://example.com/x")$evidence
  expect_identical(e$fetch_allow_ranges, list(character()))

  supplied <- robots_evaluate_text_v1(
    "user-agent: *\n", "https://example.com/", "Googlebot", "google", "google"
  )$evidence
  expect_identical(supplied$fetch_allow_ranges, list(NA_character_))
  expect_identical(engine_schema_revision_v1(), "2026-11-11.1")
})

test_that("the metadata host names are never reopened by a range", {
  local_mocked_bindings(
    acquire_fetch = function(binding) stop("must not fetch: ", binding$url)
  )
  everything <- c("0.0.0.0/0", "::/0")
  for (level in safety_levels) {
    for (url in c("http://metadata.google.internal/x", "http://metadata/x")) {
      e <- evaluate(
        url, safety_level = level, fetch_allow_ranges = everything
      )$evidence
      info <- paste(level, url)
      expect_identical(e$legacy_fetch_outcome, "ssrf_blocked", info = info)
      expect_identical(e$safety_block_reason, "cloud-metadata", info = info)
      expect_identical(
        e$evidence_status, refused_status[[level]], info = info
      )
    }
  }
})

test_that("a provider endpoint stays refused under a broader range", {
  local_mocked_bindings(
    acquire_fetch = function(binding) stop("must not fetch: ", binding$url)
  )
  for (level in safety_levels) {
    e <- evaluate(
      c("http://169.254.169.254/x", "http://[fd00:ec2::254]/x"),
      safety_level = level,
      fetch_allow_ranges = c("169.254.0.0/16", "fd00::/8")
    )$evidence
    expect_identical(
      e$legacy_fetch_outcome, rep("ssrf_blocked", 2L), info = level
    )
    expect_identical(
      e$safety_block_reason, rep("cloud-metadata", 2L), info = level
    )
    expect_identical(
      e$evidence_status, rep(refused_status[[level]], 2L), info = level
    )
  }
})

test_that("an exact provider endpoint is refused before any fetch", {
  local_no_hop()
  endpoints <- c(
    "169.254.169.254/32", "169.254.169.254/032", "100.100.100.200/32",
    "fd00:ec2::254/128", "FD00:EC2::254/128", "fd00:0ec2::254/128",
    "fd20:ce::254/128"
  )
  for (entry in endpoints) {
    expect_error(
      robots_fetch(
        "http://169.254.169.254/x", fetch_allow_ranges = c("10.0.0.0/8", entry)
      ),
      class = "robotstxtr_invalid_fetch_allow_ranges", info = entry
    )
  }
})

test_that("an invalid fetch_allow_ranges is a classed call-level error", {
  local_no_hop()
  latin1 <- "\xe9/8"
  Encoding(latin1) <- "latin1"
  bad <- list(
    NA_character_, "", c("10.0.0.0/8", NA), 10, list("10.0.0.0/8"), NULL,
    "10.0.0.1/8", "not-a-cidr", "10.0.0.1", " 10.0.0.0/8", latin1,
    "é/8", rawToChar(as.raw(c(0xff, 0x2f, 0x38)))
  )
  for (value in bad) {
    info <- deparse1(value)
    expect_error(
      robots_fetch("http://10.1.2.3/x", fetch_allow_ranges = value),
      class = "robotstxtr_invalid_fetch_allow_ranges", info = info
    )
    err <- tryCatch(
      evaluate("http://10.1.2.3/x", fetch_allow_ranges = value),
      error = identity
    )
    expect_s3_class(err, "robotstxtr_invalid_fetch_allow_ranges")
    expect_false(inherits(err, "robotstxtr_acquisition_error"), info = info)
  }
})

test_that("every entry point validates fetch_allow_ranges", {
  local_no_hop()
  calls <- list(
    function(r) robots_fetch(character(), fetch_allow_ranges = r),
    function(r) robots_validate_url(character(), fetch_allow_ranges = r),
    function(r) {
      allowed_by_robots_url(character(), "bot", fetch_allow_ranges = r)
    },
    function(r) evaluate(character(), fetch_allow_ranges = r)
  )
  for (call in calls) {
    expect_error(
      call("not-a-cidr"), class = "robotstxtr_invalid_fetch_allow_ranges"
    )
  }
})

test_that("each entry point passes the listed ranges to the fetch", {
  local_fake_ssrfr(robots_ok)
  url <- "http://10.1.2.3/page"
  ranges <- "10.0.0.0/8"
  x <- allowed_by_robots_url(url, "bot", fetch_allow_ranges = ranges)
  expect_identical(x$results$fetch_outcome, "fetched")
  expect_identical(x$results$decision_source, "default_allow")
  v <- robots_validate_url(url, fetch_allow_ranges = ranges)
  expect_identical(v$documents$fetch_outcome, "fetched")
})

test_that("ssrf_guard = FALSE with a non-empty range is a call-level error", {
  local_no_hop()
  calls <- list(
    function(u) {
      robots_fetch(u, ssrf_guard = FALSE, fetch_allow_ranges = "10.0.0.0/8")
    },
    function(u) {
      robots_validate_url(
        u, ssrf_guard = FALSE, fetch_allow_ranges = "10.0.0.0/8"
      )
    },
    function(u) {
      allowed_by_robots_url(
        u, "bot", ssrf_guard = FALSE, fetch_allow_ranges = "10.0.0.0/8"
      )
    },
    function(u) {
      evaluate(u, ssrf_guard = FALSE, fetch_allow_ranges = "10.0.0.0/8")
    }
  )
  # Zero eligible rows too: an invalid URL, and no URL at all.
  for (url in list("http://10.1.2.3/x", "not-a-url", character())) {
    for (call in calls) {
      expect_error(
        call(url), class = "robotstxtr_invalid_ssrf_guard",
        info = paste(url, collapse = "")
      )
    }
  }
})

test_that("ssrf_guard = FALSE warns once and names fetch_allow_ranges", {
  local_fake_ssrfr(robots_ok)
  expect_warning(
    robots_fetch("http://10.1.2.3/x", ssrf_guard = FALSE),
    regexp = "fetch_allow_ranges", class = "robotstxtr_deprecated_ssrf_guard"
  )
  w <- collect_warnings(evaluate("http://10.1.2.3/x", ssrf_guard = FALSE))
  expect_identical(w$classes, "robotstxtr_deprecated_ssrf_guard")
  expect_identical(w$value$evidence$evidence_status, "usable_body")
  expect_identical(w$value$evidence$fetch_allow_ranges, list(character()))
  expect_false(w$value$evidence$ssrf_guard)
})

test_that("ssrf_guard = FALSE under crawler warns twice, once each a call", {
  local_fake_ssrfr(robots_ok)
  both <- c(
    "robotstxtr_deprecated_ssrf_guard", "robotstxtr_ssrf_guard_crawler"
  )
  urls <- c("http://10.1.2.3/x", "http://127.0.0.1/y", "http://[fd00::1]/z")
  calls <- list(
    fetch = function() {
      robots_fetch(urls, ssrf_guard = FALSE, safety_level = "crawler")
    },
    validate = function() {
      robots_validate_url(urls, ssrf_guard = FALSE, safety_level = "crawler")
    },
    allowed = function() {
      allowed_by_robots_url(
        urls, "bot", ssrf_guard = FALSE, safety_level = "crawler"
      )
    },
    evaluate = function() {
      evaluate(urls, ssrf_guard = FALSE, safety_level = "crawler")
    }
  )
  for (name in names(calls)) {
    w <- collect_warnings(calls[[name]]())
    expect_identical(w$classes, both, info = name)
  }
  w <- collect_warnings(calls$evaluate())
  expect_identical(w$value$evidence$evidence_status, rep("usable_body", 3L))
  expect_identical(
    w$value$evidence$safety_block_reason, rep(NA_character_, 3L)
  )
  expect_warning(
    expect_warning(
      calls$fetch(),
      regexp = "internal addresses reachable",
      class = "robotstxtr_ssrf_guard_crawler"
    ),
    class = "robotstxtr_deprecated_ssrf_guard"
  )
})

test_that("ssrf_guard = FALSE under strict raises no crawler warning", {
  local_fake_ssrfr(robots_ok)
  w <- collect_warnings(
    robots_fetch("http://10.1.2.3/x", ssrf_guard = FALSE)
  )
  expect_identical(w$classes, "robotstxtr_deprecated_ssrf_guard")
})

test_that("ssrf_guard = TRUE with a range is silent", {
  local_fake_ssrfr(robots_ok)
  for (level in safety_levels) {
    expect_silent(robots_fetch(
      "http://10.1.2.3/x", ssrf_guard = TRUE, safety_level = level,
      fetch_allow_ranges = "10.0.0.0/8"
    ))
    expect_silent(evaluate(
      "http://10.1.2.3/x", ssrf_guard = TRUE, safety_level = level,
      fetch_allow_ranges = "10.0.0.0/8"
    ))
  }
})

test_that("the policy reopens only the listed ranges, never the names", {
  policy <- acquire_policy(
    10, "ua", 1000L, fetch_allow_ranges = c("10.0.0.0/8", "fd00::/8")
  )
  expect_identical(policy$allow_ranges, c("10.0.0.0/8", "fd00::/8"))
  expect_length(policy$allow_hosts, 0L)
  expect_length(acquire_policy(10, "ua", 1000L)$allow_ranges, 0L)
})
