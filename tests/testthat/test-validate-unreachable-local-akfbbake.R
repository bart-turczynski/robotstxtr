# ROBO-akfbbake: under `safety_level = "crawler"`, robots_validate_url() reads
# an address-class refusal as an unreachable file (ADR 0001 section 3; the
# evidence side is ROBO-jqwukcog). Strict refusals, and the crawler's transition
# and URL-shape refusals, keep the strict wording (ROBO-bsloeclp). The
# diagnostic code is acquisition_safety_refused throughout.
# Offline: refusals are scripted at the ssrfr boundary (helper-fake-ssrfr.R).

akf_address_codes <- c(
  "loopback", "private", "link-local", "cloud-metadata", "shared",
  "unspecified", "this-network", "multicast", "reserved", "ipv4-mapped",
  "ipv4-translated", "ipv4-compatible", "nat64"
)
akf_url_shape_codes <- c(
  "scheme", "userinfo", "port", "parse", "numeric-literal", "malformed-address"
)
# The transition literals ssrfr refuses (ROBO-aoslfvnx), by code.
akf_transition_urls <- c(
  "6to4" = "http://[2002:808:808::1]/robots.txt",
  "teredo" = "http://[2001::f7f7:f7f7]/robots.txt",
  "isatap" = "http://[2600::5efe:a00:1]/robots.txt"
)

akf_see <- " See robots_engine_contract_v1()."

# The message before ROBO-akfbbake: nothing was requested, so no reading.
akf_strict <- function(code) {
  paste0(
    "Blocked by SSRF guard (", code, "): robotstxtr's safety refusal ",
    "(safety_block_reason \"", code, "\"); nothing was requested there, so ",
    "no engine reading applies.", akf_see
  )
}

# The crawler message for an address-class refusal: the unreachable_local
# reading, as for an unreachable file (ROBO-akfbbake).
akf_gap <- paste0(
  "Google: context-dependent (may pause crawling or use its last cached ",
  "copy); Yandex: not documented; Bing: not documented."
)
akf_unreachable <- function(code) {
  paste0(
    "Blocked by SSRF guard (", code, "): robotstxtr's safety refusal ",
    "(safety_block_reason \"", code, "\") of an internal address, which a ",
    "public crawler could not reach either; read as an unreachable file: ",
    akf_gap, akf_see
  )
}

# Refuse `code` on hop `on_hop` (1: the robots URL itself; 2: the target of a
# 301 the first hop returns), then validate the robots URL at `safety_level`.
akf_refused <- function(code, on_hop, safety_level, env = parent.frame()) {
  testthat::local_mocked_bindings(
    acquire_prepare_hop = function(url, policy, request = NULL, from = NULL) {
      hop <- if (is.null(from)) 1L else from$hop + 1L
      if (hop == on_hop) {
        return(fake_refusal(code, hop = hop))
      }
      fake_prepare_hop(url, policy, from)
    },
    acquire_fetch = function(binding) {
      fake_fetch(binding, function(req) {
        fake_response(301L, headers = list(Location = "http://b/robots.txt"))
      })
    },
    .package = "robotstxtr",
    .env = env
  )
  robots_validate_url("http://a/robots.txt", safety_level = safety_level)
}

# Real ssrfr classifies `url` (hop 1), or a 301 from the robots URL to
# `location` makes the refused URL hop 2. Nothing is dialed.
akf_located <- function(url, location, safety_level, env = parent.frame()) {
  local_fake_ssrfr(function(req) {
    fake_response(301L, headers = list(Location = location))
  }, env = env)
  robots_validate_url(url, safety_level = safety_level)
}

test_that("ROBO-akfbbake: strict address refusals read as no engine reading", {
  for (code in akf_address_codes) {
    for (hop in 1:2) {
      local({
        x <- akf_refused(code, hop, "strict")
        label <- paste(code, "hop", hop)
        expect_identical(x$diagnostics$code, "acquisition_safety_refused",
                         info = label)
        expect_identical(x$diagnostics$message, akf_strict(code), info = label)
        expect_identical(x$documents$validation_status, "not_validated",
                         info = label)
      })
    }
  }
})

test_that("ROBO-akfbbake: a crawler address refusal reads as unreachable", {
  for (code in akf_address_codes) {
    for (hop in 1:2) {
      local({
        x <- akf_refused(code, hop, "crawler")
        label <- paste(code, "hop", hop)
        expect_identical(x$diagnostics$code, "acquisition_safety_refused",
                         info = label)
        expect_identical(x$diagnostics$message, akf_unreachable(code),
                         info = label)
        expect_identical(x$documents$validation_status, "not_validated",
                         info = label)
        expect_identical(x$documents$error_count, 1L, info = label)
      })
    }
  }
})

test_that("ROBO-akfbbake: real loopback refusals, origin and redirect target", {
  for (level in c("strict", "crawler")) {
    want <- if (identical(level, "crawler")) {
      akf_unreachable("loopback")
    } else {
      akf_strict("loopback")
    }
    local({
      origin <- akf_located("http://127.0.0.1/robots.txt", "http://b/", level)
      expect_identical(origin$diagnostics$message, want,
                       info = paste("origin", level))
    })
    local({
      target <- akf_located("http://a/robots.txt", "http://127.0.0.1/r", level)
      expect_identical(target$diagnostics$message, want,
                       info = paste("target", level))
    })
  }
})

test_that("ROBO-akfbbake: transition refusals keep the strict wording", {
  for (code in names(akf_transition_urls)) {
    url <- akf_transition_urls[[code]]
    for (level in c("strict", "crawler")) {
      local({
        origin <- akf_located(url, "http://b/robots.txt", level)
        target <- akf_located("http://a/robots.txt", url, level)
        expect_identical(origin$diagnostics$message, akf_strict(code),
                         info = paste("origin", code, level))
        expect_identical(target$diagnostics$message, akf_strict(code),
                         info = paste("target", code, level))
        expect_identical(target$diagnostics$code,
                         "acquisition_safety_refused",
                         info = paste("target", code, level))
      })
    }
  }
})

test_that("ROBO-akfbbake: URL-shape refusals keep the strict wording", {
  for (code in akf_url_shape_codes) {
    # A redirect to a non-HTTP(S) target has its own branch (scheme on hop 2).
    hops <- if (identical(code, "scheme")) 1L else 1:2
    for (hop in hops) {
      local({
        x <- akf_refused(code, hop, "crawler")
        label <- paste(code, "hop", hop)
        expect_identical(x$diagnostics$code, "acquisition_safety_refused",
                         info = label)
        expect_identical(x$diagnostics$message, akf_strict(code), info = label)
      })
    }
  }
})

test_that("ROBO-akfbbake: acquisition_diagnosis() reads the safety level", {
  refusal <- function(code) {
    data.frame(
      fetch_outcome = "ssrf_blocked", terminal_redirect_reason = "none",
      safety_block_reason = code,
      error_message = paste0("Blocked by SSRF guard (", code, ")."),
      stringsAsFactors = FALSE
    )
  }
  for (code in akf_address_codes) {
    crawler <- acquisition_diagnosis(refusal(code), safety_level = "crawler")
    expect_identical(crawler$code, "acquisition_safety_refused", info = code)
    expect_identical(crawler$message, akf_unreachable(code), info = code)
    strict <- acquisition_diagnosis(refusal(code))
    expect_identical(strict$message, akf_strict(code), info = code)
  }
  for (code in c(names(akf_transition_urls), akf_url_shape_codes)) {
    for (level in c("strict", "crawler")) {
      got <- acquisition_diagnosis(refusal(code), safety_level = level)
      label <- paste(code, level)
      expect_identical(got$code, "acquisition_safety_refused", info = label)
      expect_identical(got$message, akf_strict(code), info = label)
    }
  }
})

test_that("ROBO-akfbbake: an ssrf_blocked row with no reason has no refusal", {
  source <- data.frame(
    fetch_outcome = "ssrf_blocked", terminal_redirect_reason = "none",
    safety_block_reason = NA_character_, error_message = "Blocked.",
    stringsAsFactors = FALSE
  )
  expect_null(acquisition_diagnosis(source))
})

test_that("ROBO-akfbbake: the legacy robots frame has no safety_level column", {
  local_fake_ssrfr(function(req) fake_response(200L, body = "user-agent: *\n"))
  fetched <- robots_fetch("http://a/robots.txt", safety_level = "crawler")
  expect_false("safety_level" %in% names(fetched$robots))
})
