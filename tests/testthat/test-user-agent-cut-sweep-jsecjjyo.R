# ROBO-jsecjjyo: a generated sweep of cut User-agent rows against Google's
# reading. Each document puts one inserted character (every listed space
# and invisible character, U+00AD, U+2028, a Latin-1 A0 byte, a listed
# sequence cut short, a tab) at one position of a User-agent line (before
# its value, inside it, after it, before its key), or puts the look-alike
# U+043E in place of an `o`, in one group context, and every row on that
# line is checked against the Google backend for the same document with
# the target written plainly. Fixtures are built from code points and raw
# bytes, so the source stays ASCII.

sw_bytes <- function(...) {
  unlist(lapply(list(...), function(part) {
    if (is.raw(part)) part else charToRaw(enc2utf8(part))
  }), use.names = FALSE)
}

sw_table <- validation_lookalike_code_points
sw_listed <- sw_table$point[sw_table$kind %in% c("space", "invisible")]
# Inserts: name, bytes, and whether the row's repair drops it (a listed
# character or U+00AD), so the value without it is the target.
sw_insert <- function(name, bytes, repaired, positions = sw_positions) {
  list(name = name, bytes = bytes, repaired = repaired,
       positions = positions)
}
sw_positions <- c("before", "inside", "after", "key")
sw_code_point <- function(point) {
  sw_insert(sprintf("U+%04X", point), charToRaw(intToUtf8(point)), TRUE)
}
# Run in every context: one listed character of each byte width and kind,
# and each other insert.
sw_full <- c(
  lapply(c(0x00A0, 0x3000, 0x200B, 0xFEFF), sw_code_point),
  list(sw_insert("U+00AD", charToRaw(intToUtf8(0x00AD)), TRUE),
       sw_insert("U+2028", charToRaw(intToUtf8(0x2028)), FALSE),
       sw_insert("latin1 A0", as.raw(0xA0), FALSE),
       sw_insert("cut C2", as.raw(0xC2), FALSE),
       sw_insert("tab", as.raw(0x09), FALSE),
       sw_insert("U+043E for o", charToRaw(intToUtf8(0x043E)), FALSE,
                 "substitute"))
)
# Every other listed character, in the first context and before or inside
# the value only: each has the width and kind of one of the four above.
sw_rest <- lapply(setdiff(sw_listed, c(0x00A0, 0x3000, 0x200B, 0xFEFF)),
                  function(point) {
                    x <- sw_code_point(point)
                    x$positions <- c("before", "inside")
                    x
                  })

sw_targets <- c("Googlebot", "Googlebot-Image", "*", "ExampleBot",
                "Mediapartners-Google*")
sw_google <- ascii_lower(validation_google_tokens())

# The User-agent line with `x` at `position`.
sw_line <- function(target, x, position) {
  switch(position,
         before = sw_bytes("User-agent: ", x, target),
         inside = sw_bytes("User-agent: ", substr(target, 1L, 1L), x,
                           substring(target, 2L)),
         after = sw_bytes("User-agent: ", target, x, " # c"),
         key = sw_bytes(x, "User-agent: ", target),
         substitute = sw_bytes(
           "User-agent: ", sub("o.*$", "", target), x,
           sub("^[^o]*o", "", target)
         ))
}

# The document for a context, with its User-agent line, and that line's
# number.
sw_contexts <- list(
  alone = list(line = 1L, build = function(ua) {
    list(ua, "Disallow: /x")
  }),
  same_star = list(line = 2L, build = function(ua) {
    list("User-agent: *", ua, "Disallow: /x")
  }),
  other_star = list(line = 4L, build = function(ua) {
    list("User-agent: *", "Disallow: /y", "", ua, "Disallow: /x")
  }),
  named = list(line = 4L, build = function(ua) {
    list("User-agent: Googlebot", "Disallow: /y", "", ua, "Disallow: /x")
  }),
  stacked = list(line = 2L, build = function(ua) {
    list("User-agent: Googlebot", ua, "Disallow: /x")
  })
)
sw_document <- function(context, ua) {
  parts <- sw_contexts[[context]]$build(ua)
  unlist(lapply(parts, sw_bytes, "\n"), use.names = FALSE)
}

# The Google decision on /x per token, as one call per document.
sw_decide <- function(doc, tokens) {
  if (length(tokens) == 0L) {
    return(stats::setNames(character(), character()))
  }
  r <- robots_evaluate_text_v1(rawToChar(doc), rep("https://example.com/x",
                                                   length(tokens)),
                               tokens, "google", "google")$results
  stats::setNames(r$url_decision, tokens)
}

# The tokens whose loss of the group the sweep looks for: the target's own
# Google token, and for `*` any crawler.
sw_tokens <- function(target) {
  token <- sub("[^A-Za-z_-].*$", "", target)
  if (identical(target, "*")) {
    c("ExampleBot", "Googlebot", "AdsBot-Google")
  } else if (ascii_lower(token) %in% sw_google) {
    token
  } else {
    character()
  }
}

sw_spelled_google <- function(message) {
  spelled <- regmatches(message, gregexpr("value is '[^']*'", message))[[1L]]
  spelled <- trimws(sub("^value is '(.*)'$", "\\1", spelled))
  any(ascii_lower(spelled) %in% c(sw_google, "*"))
}

test_that("every generated cut row agrees with Google's reading", {
  started <- proc.time()[["elapsed"]]
  clean <- new.env(parent = emptyenv())
  documents <- 0L
  rows_checked <- 0L
  google_tokens <- validation_google_tokens()
  runs <- c(
    lapply(sw_full, function(x) list(x = x, contexts = names(sw_contexts))),
    lapply(sw_rest, function(x) list(x = x, contexts = "alone"))
  )
  for (run in runs) {
    x <- run$x
    for (context in run$contexts) {
      line <- sw_contexts[[context]]$line
      for (target in sw_targets) {
        tokens <- sw_tokens(target)
        key <- paste(context, target)
        plain <- sw_document(context, sw_line(target, "", "before"))
        if (is.null(clean[[key]])) {
          assign(key, sw_decide(plain, tokens), envir = clean)
        }
        before <- clean[[key]]
        positions <- x$positions
        # The hidden key reaches unknown_directive, not user_agent_cut:
        # one target is enough.
        if (!identical(target, "Googlebot")) {
          positions <- setdiff(positions, "key")
        }
        if (!grepl("o", target, fixed = TRUE)) {
          positions <- setdiff(positions, "substitute")
        }
        for (position in positions) {
          label <- paste(x$name, context, target, position)
          ua <- sw_line(target, x$bytes, position)
          doc <- sw_document(context, ua)
          documents <- documents + 1L
          d <- robots_validate_text(doc)$diagnostics
          d <- d[d$line == line, , drop = FALSE]
          cut <- d[d$code == "user_agent_cut", , drop = FALSE]
          rows_checked <- rows_checked + nrow(d)
          claims <- grepl("nothing changes for them|nothing changes for that",
                          cut$message)
          loses <- grepl("does not get this group", cut$message, fixed = TRUE)
          reaches <- grepl("the group still reaches every crawler",
                           cut$message, fixed = TRUE)
          # Whether the backend is needed: a claim to check, or a loss
          # that a row on the line would have to warn about.
          scoped <- x$repaired || identical(target, "*") ||
            identical(position, "key")
          need <- length(tokens) > 0L &&
            (any(claims | loses | reaches) ||
               (scoped && !any(d$severity == "warning")))
          after <- if (need) sw_decide(doc, tokens)
          lost <- if (need) {
            tokens[before[tokens] == "disallow" & after[tokens] == "allow"]
          } else {
            character()
          }
          for (k in seq_len(nrow(cut))) {
            message <- cut$message[[k]]
            # (a) a sentence that Google's crawlers keep the group holds
            # for the Google token the repaired value names; "nothing
            # changes for them" holds for every documented Google token,
            # against the document with the target written plainly.
            if (claims[[k]] && x$repaired && length(tokens) > 0L &&
                  !identical(target, "*")) {
              expect_identical(after[tokens], before[tokens], label = label)
            }
            if (grepl("nothing changes for them", message, fixed = TRUE)) {
              all_key <- paste(key, "all")
              if (is.null(clean[[all_key]])) {
                assign(all_key, sw_decide(plain, google_tokens),
                       envir = clean)
              }
              expect_identical(sw_decide(doc, google_tokens),
                               clean[[all_key]], label = label)
            }
            # (b) "does not get this group" holds on Google.
            if (loses[[k]]) {
              named <- sub("^.*Google's (\\S+) does not get this group.*$",
                           "\\1", message)
              expect_true(named %in% tokens, label = label)
              if (named %in% tokens) {
                expect_false(identical(after[[named]], before[[named]]),
                             label = label)
              }
            }
            # The `*` tail: every crawler it does not except keeps the
            # group through the group's `*` line.
            if (reaches[[k]]) {
              for (token in tokens) {
                if (!grepl(token, message, fixed = TRUE)) {
                  expect_identical(after[[token]], "disallow",
                                   label = paste(label, token))
                }
              }
            }
            # (d) the generic clause at most once.
            expect_lte(lengths(regmatches(message, gregexpr(
              "Bing and Yandex may read", message, fixed = TRUE
            ))), 1L, label = label)
            # (e) no "nothing changes" beside a spelling Google reads as
            # `*` or a Google token.
            if (grepl("nothing changes for them", message, fixed = TRUE)) {
              expect_false(sw_spelled_google(message), label = label)
            }
            # Outside the repaired kinds, no claim of what was meant.
            if (!x$repaired) {
              expect_false(grepl("If this line was meant", message,
                                 fixed = TRUE), label = label)
            }
          }
          # (c) a Google token or `*` losing the group draws a warning on
          # the line. A character that is neither listed nor U+00AD, inside
          # or before a named value, keeps the documented severity (info
          # for a token Google does not read as its crawler, ROBO-txnzyugl)
          # and is left out.
          if (scoped && length(lost) > 0L) {
            expect_true(any(d$severity == "warning"), label = label)
          }
        }
      }
    }
  }
  expect_gt(documents, 0L)
  expect_gt(rows_checked, 0L)
  if (isTRUE(getOption("robotstxtr.sweep_report"))) {
    message(sprintf("sweep: %d documents, %d rows on the line, %.1f s",
                    documents, rows_checked,
                    proc.time()[["elapsed"]] - started))
  }
})
