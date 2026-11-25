# ROBO-qjynmmzw: the Sitemap value checks parse a document's URLs together.
# These pins fix the rows the per-line checks gave before that change: every
# row, its line and its order, on an edge set that crosses each precheck,
# duplicates, IDN hosts, malformed UTF-8 and a value rurl throws on.

qj_edges <- function() {
  list(
    charToRaw("https://example.com/s.xml"),
    charToRaw("HTTPS://EXAMPLE.COM/S.xml"),
    charToRaw("https://bücher.example/s.xml"),
    charToRaw("https://xn--bcher-kva.example/s.xml"),
    charToRaw("https://例え.テスト/s.xml"),
    charToRaw("https:///s.xml"),
    charToRaw("https://:80/s.xml"),
    charToRaw("http://[::1]/s.xml"),
    charToRaw("http://10.0.0.1/s.xml"),
    charToRaw("https://user:pw@example.com/s.xml"),
    charToRaw("ftp://example.com/s.xml"),
    charToRaw("https://exa mple.com/s.xml"),
    charToRaw("https://example.com/site map.xml"),
    charToRaw("https://example.com/s.xml # c"),
    charToRaw("http:x.com"),
    charToRaw("/s.xml"),
    charToRaw("www.x.com/s.xml"),
    charToRaw("x.com:8080/s.xml"),
    charToRaw("mailto:a@b.c"),
    charToRaw("ftps://example.com/s.xml"),
    charToRaw("gopher://x/"),
    # A malformed UTF-8 byte in the host makes the value bytes-marked.
    c(charToRaw("https://ex"), as.raw(0xff), charToRaw("ample.com/s.xml")),
    c(charToRaw("https://example.com/s"), as.raw(0x00), charToRaw(".xml")),
    raw(0L),
    charToRaw(paste0("https://example.com/", strrep("a", 4000L), ".xml"))
  )
}

qj_sitemap_codes <- c("invalid_sitemap_url", "unsupported_sitemap_scheme",
                      "empty_sitemap_value")

# A group, a rule and a Sitemap line without its colon (so line 3 holds two
# rows), then one Sitemap line per value: line 3 + k for values[[k]].
qj_body <- function(values) {
  lines <- c(
    list(charToRaw("User-agent: *"), charToRaw("Disallow: /private/"),
         charToRaw("Sitemap /s.xml")),
    lapply(values, function(v) c(charToRaw("Sitemap: "), v))
  )
  unlist(lapply(lines, function(line) c(line, as.raw(0x0a))),
         use.names = FALSE)
}

# Every value twice: once in order, once reversed.
qj_edge_values <- function() {
  edges <- qj_edges()
  edges[c(seq_along(edges), rev(seq_along(edges)))]
}

qj_frame_extra <- function(frame) {
  c(
    paste("row.names", paste(.row_names_info(frame, 0L), collapse = ",")),
    paste("attributes", paste(sort(names(attributes(frame))), collapse = ","))
  )
}

# The Sitemap code each line holds ("" for none), for lines 4 onward.
qj_line_codes <- function(diagnostics, n) {
  rows <- diagnostics[diagnostics$code %in% qj_sitemap_codes &
                        diagnostics$line > 3L, , drop = FALSE]
  out <- character(n)
  out[rows$line - 3L] <- rows$code
  out
}

test_that("the Sitemap rows of the edge body are pinned", {
  d <- expect_no_warning(
    robots_validate_text(qj_body(qj_edge_values()))$diagnostics
  )
  # rurl reads "https:///s.xml" (lines 9 and 48) with host "s.xml", so it
  # draws no row: today's reading, pinned as it is.
  expect_identical(
    paste0(d$code, "@", d$line),
    c("nul_byte@26", "nul_byte@31", "invalid_utf8@25", "invalid_utf8@32",
      "accepted_missing_colon@3", "invalid_sitemap_url@3",
      "invalid_sitemap_url@10", "invalid_sitemap_url@15",
      "invalid_sitemap_url@16",
      "invalid_sitemap_url@18", "invalid_sitemap_url@19",
      "invalid_sitemap_url@20", "invalid_sitemap_url@21",
      "unsupported_sitemap_scheme@22", "unsupported_sitemap_scheme@23",
      "unsupported_sitemap_scheme@24", "invalid_sitemap_url@25",
      "empty_sitemap_value@27", "empty_sitemap_value@30",
      "invalid_sitemap_url@32", "unsupported_sitemap_scheme@33",
      "unsupported_sitemap_scheme@34", "unsupported_sitemap_scheme@35",
      "invalid_sitemap_url@36", "invalid_sitemap_url@37",
      "invalid_sitemap_url@38", "invalid_sitemap_url@39",
      "invalid_sitemap_url@41", "invalid_sitemap_url@42",
      "invalid_sitemap_url@47", "rule_slash_split@1")
  )
  expect_identical(seam_digest(d, qj_frame_extra(d)),
                   "7df409dc14bacb12311d756adb4f1ec5")
})

test_that("each value keeps its own row in any order and with repeats", {
  edges <- qj_edges()
  alone <- vapply(edges, function(v) {
    d <- robots_validate_text(qj_body(list(v)))$diagnostics
    qj_line_codes(d, 1L)
  }, character(1L))
  set.seed(20261125L)
  for (round in 1:4) {
    pick <- sample(c(seq_along(edges), sample(seq_along(edges), 10L)))
    d <- expect_no_warning(
      robots_validate_text(qj_body(edges[pick]))$diagnostics
    )
    expect_identical(qj_line_codes(d, length(pick)), alone[pick],
                     label = paste("round", round))
  }
})

test_that("a value rurl throws on invalidates only its own line", {
  boom <- "https://boom.example/s.xml"
  real_one <- rurl::safe_parse_url
  real_many <- rurl::safe_parse_urls
  local_mocked_bindings(
    safe_parse_url = function(url, ...) {
      if (any(url %in% boom)) stop("boom")
      real_one(url, ...)
    },
    safe_parse_urls = function(url, ...) {
      if (any(url %in% boom)) stop("boom")
      real_many(url, ...)
    },
    .package = "rurl"
  )
  values <- c(qj_edge_values(), list(charToRaw(boom)))
  n <- length(values)
  clean <- robots_validate_text(qj_body(values[-n]))$diagnostics
  d <- expect_no_warning(robots_validate_text(qj_body(values))$diagnostics)
  expected <- c(qj_line_codes(clean, n - 1L), "invalid_sitemap_url")
  expect_identical(qj_line_codes(d, n), expected)
  expect_identical(nrow(d), nrow(clean) + 1L)
})

# The edge values as the parser hands them over: a string each, bytes-marked
# where the UTF-8 is malformed. The NUL edge has no string form.
qj_edge_strings <- function() {
  edges <- qj_edges()
  edges <- edges[!vapply(edges, function(v) any(v == as.raw(0L)),
                         logical(1L))]
  vapply(edges, function(v) {
    s <- rawToChar(v)
    Encoding(s) <- if (validUTF8(s)) "UTF-8" else "bytes"
    s
  }, character(1L), USE.NAMES = FALSE)
}

test_that("the document batch gives each value the scalar finding", {
  values <- qj_edge_strings()
  set.seed(20261126L)
  for (mix in list(values, c(values, rev(values)), sample(values),
                   sample(values, 3L * length(values), replace = TRUE))) {
    batch <- expect_no_warning(sitemap_value_diagnostics(mix))
    scalar <- expect_no_warning(lapply(mix, sitemap_value_diagnostic))
    expect_identical(batch, scalar)
  }
  expect_identical(sitemap_value_diagnostics(character()), list())
})

test_that("a batch that throws falls back to the per-value checks", {
  body <- qj_body(qj_edge_values())
  clean <- robots_validate_text(body)$diagnostics
  local_mocked_bindings(sitemap_parse_batch = function(...) stop("boom"))
  d <- expect_no_warning(robots_validate_text(body)$diagnostics)
  expect_identical(d, clean)
})

# The cost of a Sitemap line next to one the prechecks reject before any URL
# parse: the same body with relative values. Best of five, interleaved, so a
# loaded machine slows both sides alike.
test_that("a thousand Sitemap lines cost about as much as relative ones", {
  skip_on_cran()
  mk <- function(v) {
    paste(c("User-agent: *", "Disallow: /private/", paste0("Sitemap: ", v)),
          collapse = "\n")
  }
  n <- 1000L
  valid <- mk(sprintf("https://www.example.com/sitemap/%d.xml", seq_len(n)))
  relative <- mk(sprintf("/sitemap/%d.xml", seq_len(n)))
  robots_validate_text(valid)
  robots_validate_text(relative)
  times <- matrix(NA_real_, 5L, 2L)
  for (k in 1:5) {
    times[k, 1L] <- system.time(robots_validate_text(valid))[["elapsed"]]
    times[k, 2L] <- system.time(robots_validate_text(relative))[["elapsed"]]
  }
  best <- apply(times, 2L, min)
  expect_lte(best[[1L]], 2 * best[[2L]] + 0.05,
             label = sprintf("valid %.3f s against relative %.3f s",
                             best[[1L]], best[[2L]]))
})
