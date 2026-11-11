# The Google matcher adapter parses each distinct body once (ROBO-iooslxvj).
#
# match_google_v1() stays the reference row matcher: the batch adapter must
# give, row for row, the frame row_matcher_frame_v1(match_google_v1, ...)
# gives, over a grid of synthesized example.com bodies x URLs x tokens. The
# grid holds the inputs where a parse-once rewrite can slip: the empty-value
# restatement (an empty Allow stays default_allow with no line), the
# index.htm normalization, the 512,000-byte window (a cut boundary line and a
# body of exactly the window), NUL bytes (each line cut at its first NUL
# before matching, ROBO-pvqrfvol, but counted in matcher_input_bytes), invalid UTF-8 and latin1 path bytes, two distinct
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
  twin_b = gb_bytes("User-agent: *\nDisallow: /privatg\n"),
  multi_agent = gb_bytes(
    "User-agent: BazBot\nUser-agent: FooBot\nDisallow: /multi\n",
    "Allow: /multi/ok\n\nUser-agent: *\nDisallow: /\n"
  ),
  # The bytes of `groups` again, as a separate R object: one distinct body.
  groups_copy = gb_bytes(
    "User-agent: *\nDisallow: /private\nAllow: /private/ok\n",
    "Allow: /index.html\n\n",
    "User-agent: FooBot\nDisallow: /foo\nDisallow: /dir/\n",
    "Allow: /dir/index.htm\n"
  )
)
gb_n_distinct <- length(gb_bodies) - 1L

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
  "https://example.com/multi",
  "https://example.com/multi/ok",
  "https://example.com/",
  "",
  "not a url",
  "https://example.com/private"
)

# A specific group's token, its case variant, and one only `*` selects.
gb_tokens <- c("FooBot", "foobot", "BarBot")

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

# Run the adapter with the native batch wrapped, recording its arguments.
gb_spy_run <- function(bodies, urls, tokens, seen = new.env()) {
  real <- google_evaluate_batch_v1
  local_mocked_bindings(
    google_evaluate_batch_v1 = function(bodies, body_index, product_tokens,
                                        targets) {
      seen$bodies <- bodies
      seen$targets <- targets
      real(bodies, body_index, product_tokens, targets)
    }
  )
  match_google_batch_v1(bodies, urls, tokens)
}

# The adapter frame on the grid as main gave it before the batch (593300b,
# where the adapter was row_matcher_frame_v1(match_google_v1, ...)), its
# n_parse_calls attribute aside, with the two NUL bodies read as each line
# cut at its first NUL (ROBO-pvqrfvol).
gb_pinned <- "64f27439bc2fe73d5b4818ba5452b593"

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
  g <- gb_grid()
  seen <- new.env()
  out <- gb_spy_run(g$bodies, g$urls, g$tokens, seen)
  expect_identical(attr(out, "n_parse_calls"), gb_n_distinct)
  # A byte-equal body in a separate R object joins its twin's group.
  expect_length(seen$bodies, gb_n_distinct)
  expect_identical(
    attr(match_google_batch_v1(list(), character(), character()),
         "n_parse_calls"),
    0L
  )
})

test_that("the Google frame has the decision columns and no native ones", {
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
  url <- "https://example.com/caf\xe9"
  Encoding(url) <- "latin1"
  bodies <- list(gb_bodies$latin1)
  seen <- new.env()
  out <- gb_spy_run(bodies, url, "FooBot", seen)
  expect_identical(
    seen$targets, list(gb_bytes("https://example.com/caf", 0xc3L, 0xa9L))
  )
  expect_identical(gb_strip(out), gb_oracle(bodies, url, "FooBot"))
})

test_that("a bytes-marked URL fails as it fails on the row path", {
  url <- "https://example.com/caf\xe9"
  Encoding(url) <- "bytes"
  bodies <- list(gb_bodies$latin1)
  row_error <- tryCatch(
    gb_oracle(bodies, url, "FooBot"),
    error = identity
  )
  batch_error <- tryCatch(
    match_google_batch_v1(bodies, url, "FooBot"),
    error = identity
  )
  expect_s3_class(row_error, "error")
  expect_s3_class(batch_error, class(row_error), exact = TRUE)
  expect_identical(conditionMessage(batch_error), conditionMessage(row_error))
})

test_that("an NA URL is evaluated as the empty URL", {
  bodies <- list(gb_bodies$groups, gb_bodies$empty_values)
  seen <- new.env()
  out <- gb_spy_run(bodies, rep(NA_character_, 2L), rep("FooBot", 2L), seen)
  expect_identical(seen$targets, list(raw(0), raw(0)))
  expect_identical(
    gb_strip(out), gb_oracle(bodies, c("", ""), c("FooBot", "FooBot"))
  )
})

test_that("grouping is exact on the bytes alone", {
  x <- gb_bodies$nul_value
  y <- gb_bodies$bad_utf8
  # The first body of a group stands for it as it is; attributes do not split.
  groups <- matcher_body_groups_v1(list(structure(x, foo = 1), x, y))
  expect_identical(groups$distinct_bodies, list(structure(x, foo = 1), y))
  expect_identical(groups$body_index, c(1L, 1L, 2L))
  # NULL is not a body: it keeps a group of its own, and reaches the native
  # binding as NULL, to be refused there.
  groups <- matcher_body_groups_v1(list(x, NULL, raw(0), y, raw(0), NULL))
  expect_identical(groups$distinct_bodies, list(x, NULL, raw(0), y, NULL))
  expect_identical(groups$body_index, c(1L, 2L, 3L, 4L, 3L, 5L))
  # Twins of one length, and bytes a NUL-free key alone would confuse:
  # NULs inside, and trailing NULs (which rawToChar() drops).
  twins <- list(
    gb_bodies$twin_a, gb_bodies$twin_b, gb_bytes("a", 0L, "b"),
    gb_bytes("ab", 0L), gb_bytes("a", 0L, "b"), gb_bodies$twin_a,
    gb_bytes("ab"), gb_bytes("ab", 0L, 0L), gb_bytes(0L), raw(0),
    gb_bytes("ab", 0L)
  )
  groups <- matcher_body_groups_v1(twins)
  expect_identical(
    groups$body_index, c(1L, 2L, 3L, 4L, 3L, 1L, 5L, 6L, 7L, 8L, 4L)
  )
  # A plain body whose bytes spell another body's key stays apart from it.
  spelled <- list(
    gb_bytes("a", 0L, "b"), gb_bytes("3:2:ab"), "x", gb_bytes("<character>3")
  )
  groups <- matcher_body_groups_v1(spelled)
  expect_identical(groups$body_index, 1:4)
})

# The condition an expression signals: its class, message and call.
gb_condition <- function(expr) {
  e <- tryCatch(expr, error = identity)
  if (!inherits(e, "error")) {
    return(list(class = "no error"))
  }
  list(
    class = class(e), message = conditionMessage(e),
    call = deparse(conditionCall(e))
  )
}

test_that("a non-raw body is refused as the row path refuses it", {
  url <- "https://example.com/private"
  for (body in list(NULL, "x", list(charToRaw("x")))) {
    # After an empty body, which a non-raw body must not join.
    bodies <- list(raw(0), body)
    label <- paste(typeof(body), "body")
    google <- gb_condition(
      match_google_batch_v1(bodies, url, "FooBot")
    )
    expect_true("error" %in% google$class, label = label)
    expect_identical(
      google, gb_condition(gb_oracle(bodies, rep(url, 2L), rep("FooBot", 2L))),
      label = label
    )
    for (case in list(
      list(adapter = match_yandex_v1, token = "Yandex"),
      list(adapter = match_bing_v1, token = "bingbot")
    )) {
      batch <- gb_condition(case$adapter(bodies, url, case$token))
      alone <- gb_condition(case$adapter(list(body), url, case$token))
      expect_identical(batch$message, "expected a raw vector", label = label)
      expect_identical(batch, alone, label = label)
    }
  }
})

test_that("a classed raw body gives the row path's result", {
  local_mocked_s3_method(
    "as.vector", "evil",
    function(x, mode = "any") stop("as.vector() is not for this body")
  )
  evil <- structure(gb_bodies$groups, class = "evil")
  urls <- c("https://example.com/private", "https://example.com/foo")
  bodies <- list(evil, gb_bodies$groups)
  expect_identical(
    gb_strip(match_google_batch_v1(bodies, urls, "FooBot")),
    gb_oracle(bodies, urls, rep("FooBot", 2L))
  )
  expect_adapter_output(match_google_batch_v1, bodies, urls, "FooBot", "google")
  expect_adapter_output(match_yandex_v1, bodies, urls, "Yandex", "yandex")
  expect_adapter_output(match_bing_v1, bodies, urls, "bingbot", "bing")
})

test_that("a token that is not a string fails as on the row path", {
  bodies <- list(gb_bodies$groups)
  url <- "https://example.com/private"
  for (token in list(1, 1L, TRUE)) {
    batch <- gb_condition(match_google_batch_v1(bodies, url, token))
    expect_true("error" %in% batch$class, label = typeof(token))
    expect_identical(
      batch, gb_condition(gb_oracle(bodies, url, token)),
      label = typeof(token)
    )
  }
})

test_that("the first failing row decides the error, as on the row path", {
  bytes_url <- "https://example.com/caf\xe9"
  Encoding(bytes_url) <- "bytes"
  urls <- c("https://example.com/private", bytes_url)
  tokens <- c("FooBot", "FooBot")
  for (bodies in list(
    list(NULL, gb_bodies$groups),
    list(gb_bodies$groups, NULL)
  )) {
    expect_identical(
      gb_condition(match_google_batch_v1(bodies, urls, tokens)),
      gb_condition(gb_oracle(bodies, urls, tokens))
    )
  }
  # A bad token in row 1 comes before a bad body in row 2.
  bodies <- list(gb_bodies$groups, NULL)
  urls <- rep("https://example.com/private", 2L)
  expect_identical(
    gb_condition(match_google_batch_v1(bodies, urls, list(1, "FooBot"))),
    gb_condition(gb_oracle(bodies, urls, list(1, "FooBot")))
  )
})
