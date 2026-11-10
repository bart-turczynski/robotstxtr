# The Google matcher adapter parses each distinct body once (ROBO-iooslxvj).
#
# match_google_v1() stays the reference row matcher: the batch adapter must
# give, row for row, the frame row_matcher_frame_v1(match_google_v1, ...)
# gives, over a grid of synthesized example.com bodies x URLs x tokens. The
# grid holds the inputs where a parse-once rewrite can slip: the empty-value
# restatement (an empty Allow stays default_allow with no line), the
# index.htm normalization, the 512,000-byte window (a cut boundary line and a
# body of exactly the window), NUL bytes (dropped before matching but counted
# in matcher_input_bytes), invalid UTF-8 and latin1 path bytes, two distinct
# bodies of one length, and repeated URLs.
#
# No NA URL is in the grid: the batch module turns an NA URL into the empty
# target while the row path hands cpp11 the string "NA" (decision 3a), and
# evaluate_rows_v1() never sends an NA URL to an adapter. The NA case is
# pinned on its own below.

gb_bytes <- function(...) {
  parts <- list(...)
  unlist(lapply(parts, function(p) {
    if (is.character(p)) charToRaw(p) else as.raw(p)
  }))
}

gb_window <- 512000L

# `head`, a comment line filling up to byte `at`, then `edge` from there.
gb_filled <- function(head, at, edge) {
  head <- charToRaw(head)
  filler <- rep(charToRaw("#"), at - length(head) - 1L)
  c(head, filler, charToRaw("\n"), charToRaw(edge))
}

gb_bodies <- list(
  groups = gb_bytes(
    "User-agent: *\nDisallow: /private\nAllow: /private/ok\n",
    "Allow: /index.html\n\n",
    "User-agent: FooBot\nDisallow: /foo\nDisallow: /dir/\n",
    "Allow: /dir/index.htm\n"
  ),
  empty_values = gb_bytes(
    "User-agent: *\nDisallow:\nAllow:\nDisallow: # comment\n"
  ),
  empty_allow = gb_bytes("User-agent: *\nAllow:\n"),
  comment_disallow = gb_bytes(
    "User-agent: FooBot\nDisallow: # comment\nDisallow: /foo\n"
  ),
  # The line starting 10 bytes before the window is cut by it.
  over_window = gb_filled(
    "User-agent: *\nDisallow: /private\n", gb_window - 10L,
    "Allow: /private/cut\nDisallow: /tail\n"
  ),
  # Exactly the window, ending without a newline: nothing is cut.
  at_window = gb_filled(
    "User-agent: *\nDisallow: /edge\nDisallow: /private\n",
    gb_window - nchar("Allow: /edge"), "Allow: /edge"
  ),
  empty = raw(0),
  nul_value = gb_bytes("User-agent: *\nDisallow: /n", 0L, "ul\n"),
  nul_line = gb_bytes("User-agent: *\n", 0L, "Disallow: /z\nAllow: /zz\n"),
  bad_utf8 = gb_bytes("User-agent: *\nDisallow: /a", 0xffL, "\n"),
  latin1 = gb_bytes("User-agent: *\nDisallow: /caf", 0xe9L, "\nAllow: /\n"),
  twin_a = gb_bytes("User-agent: *\nDisallow: /privatf\n"),
  twin_b = gb_bytes("User-agent: *\nDisallow: /privatg\n")
)

gb_urls <- c(
  "https://example.com/private",
  "https://example.com/private/ok",
  "https://example.com/private/cut",
  "https://example.com/index.html",
  "https://example.com/dir/",
  "https://example.com/dir/x",
  "https://example.com/foo",
  "https://example.com/edge",
  "https://example.com/n%00ul",
  "https://example.com/nul",
  "https://example.com/z",
  "https://example.com/zz",
  "https://example.com/a%FF",
  "https://example.com/caf%E9",
  "https://example.com/privatf",
  "https://example.com/",
  "",
  "not a url",
  "https://example.com/private"
)

gb_tokens <- c("FooBot", "BarBot")

gb_grid <- function() {
  g <- expand.grid(
    body = seq_along(gb_bodies), url = seq_along(gb_urls),
    token = seq_along(gb_tokens)
  )
  list(
    bodies = unname(gb_bodies[g$body]),
    urls = gb_urls[g$url],
    tokens = gb_tokens[g$token]
  )
}

gb_oracle <- function(bodies, urls, tokens) {
  row_matcher_frame_v1(match_google_v1, bodies, urls, tokens)
}

gb_strip <- function(frame) {
  attr(frame, "n_parse_calls") <- NULL
  frame
}

gb_skip_without_batch <- function() {
  skip_if_not(
    is.function(
      tryCatch(robotstxtr_google_eval_batch_, error = function(e) NULL)
    ),
    "the Google native batch is not built"
  )
}

# The adapter frame on the grid as main gave it before the batch (593300b),
# its n_parse_calls attribute aside.
gb_pinned <- "64e9634cae16bcaae8fc96c123990a0c"

test_that("the Google adapter's frame on the grid is unchanged", {
  g <- gb_grid()
  frame <- gb_strip(match_google_batch_v1(g$bodies, g$urls, g$tokens))
  expect_identical(
    check_matcher_output_v1(frame, length(g$bodies), "google"), frame
  )
  expect_identical(seam_digest(frame), gb_pinned)
})

test_that("the batch adapter equals the row matcher, row for row", {
  g <- gb_grid()
  batch <- match_google_batch_v1(g$bodies, g$urls, g$tokens)
  expect_identical(gb_strip(batch), gb_oracle(g$bodies, g$urls, g$tokens))
  # The grid reaches what it is meant to: a cut window, a body of exactly
  # the window, an empty Allow restated, an index.htm match.
  expect_true(any(batch$matcher_body_truncated))
  expect_true(any(
    !batch$matcher_body_truncated & batch$matcher_input_bytes == gb_window
  ))
  empty_allow <- vapply(
    g$bodies, identical, logical(1L), gb_bodies$empty_allow
  )
  expect_identical(unique(batch$reason[empty_allow]), "default_allow")
  expect_true(all(is.na(batch$matched_line[empty_allow])))
  expect_true(any(
    batch$reason == "rule_allow" &
      batch$matched_rule_value == "/dir/index.htm",
    na.rm = TRUE
  ))
})

test_that("zero rows give the row matcher's empty frame", {
  out <- match_google_batch_v1(list(), character(), character())
  expect_identical(
    gb_strip(out), gb_oracle(list(), character(), character())
  )
})

test_that("each distinct body is parsed once", {
  gb_skip_without_batch()
  g <- gb_grid()
  out <- match_google_batch_v1(g$bodies, g$urls, g$tokens)
  expect_identical(attr(out, "n_parse_calls"), length(gb_bodies))
  expect_identical(
    attr(match_google_batch_v1(list(), character(), character()),
         "n_parse_calls"),
    0L
  )
})

test_that("the Google frame has the decision columns and no native ones", {
  gb_skip_without_batch()
  out <- match_google_batch_v1(
    list(gb_bodies$groups), "https://example.com/", "FooBot"
  )
  expect_named(out, matcher_decision_columns_v1())
  expect_identical(
    match_google_batch_v1(list(), character(), character()),
    matcher_batch_empty_frame_v1(character())
  )
  expect_error(
    match_google_batch_v1(gb_bodies$groups, "https://example.com/", "FooBot"),
    class = "robotstxtr_invalid_google_bodies"
  )
})

test_that("a latin1 URL reaches the matcher as its UTF-8 bytes", {
  gb_skip_without_batch()
  url <- "https://example.com/caf\xe9"
  Encoding(url) <- "latin1"
  bodies <- list(gb_bodies$latin1)
  seen <- new.env()
  real <- google_evaluate_batch_v1
  local_mocked_bindings(
    google_evaluate_batch_v1 = function(bodies, body_index, product_tokens,
                                        targets) {
      seen$targets <- targets
      real(bodies, body_index, product_tokens, targets)
    }
  )
  out <- match_google_batch_v1(bodies, url, "FooBot")
  expect_identical(seen$targets, list(charToRaw(enc2utf8(url))))
  expect_identical(
    seen$targets[[1L]],
    gb_bytes("https://example.com/caf", 0xc3L, 0xa9L)
  )
  expect_identical(gb_strip(out), gb_oracle(bodies, url, "FooBot"))
})

test_that("an NA URL is evaluated as the empty URL", {
  gb_skip_without_batch()
  bodies <- list(gb_bodies$groups, gb_bodies$empty_values)
  expect_identical(
    gb_strip(match_google_batch_v1(bodies, NA_character_, "FooBot")),
    gb_oracle(bodies, c("", ""), c("FooBot", "FooBot"))
  )
})
