# ROBO-jsecjjyo: a generated sweep of cut User-agent rows against Google's
# reading. Each document puts one inserted character (a sample of the listed
# space and invisible characters, U+00AD, a Latin-1 A0 byte, a listed
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
# a line separator (ROBO-uphlyomt), and each other insert.
sw_full_points <- c(0x00A0, 0x3000, 0x200B, 0xFEFF, 0x2028, 0xE0041)
sw_full <- c(
  lapply(sw_full_points, sw_code_point),
  list(sw_insert("U+00AD", charToRaw(intToUtf8(0x00AD)), TRUE),
       sw_insert("latin1 A0", as.raw(0xA0), FALSE),
       sw_insert("cut C2", as.raw(0xC2), FALSE),
       sw_insert("tab", as.raw(0x09), FALSE),
       sw_insert("U+043E for o", charToRaw(intToUtf8(0x043E)), FALSE,
                 "substitute"))
)
# A sample of the other listed characters (ROBO-uphlyomt: the class has
# thousands, each read through one table), one or two of each property
# class, in the first context and before or inside the value only: each
# has the width and kind of one above. The whole table is checked in
# test-invisible-class-uphlyomt.R.
sw_rest_points <- c(0x1680, 0x2009, 0x202F, 0x2029, 0x200E, 0x202E, 0x2066,
                    0x061C, 0x180E, 0x0085, 0x009F, 0xFE0F, 0x034F, 0x3164,
                    0x2065, 0xE0080)
stopifnot(all(c(sw_full_points, sw_rest_points) %in% sw_listed))
sw_rest <- lapply(sw_rest_points,
                  function(point) {
                    x <- sw_code_point(point)
                    x$positions <- c("before", "inside")
                    x
                  })

# Values written as a whole, each for one target and in the `alone` and
# `same_star` contexts only (ROBO-ipzkxzhg): more than one insert.
sw_whole <- function(name, bytes, repaired, target) {
  x <- sw_insert(name, bytes, repaired, "whole")
  x$target <- target
  x
}
sw_multi <- list(
  sw_whole("U+200B U+2028 Googlebot",
           charToRaw(intToUtf8(c(0x200B, 0x2028, utf8ToInt("Googlebot")))),
           TRUE, "Googlebot"),
  sw_whole("G U+200B oogle U+200B bot",
           charToRaw(paste0("G", intToUtf8(0x200B), "oogle", intToUtf8(0x200B),
                            "bot")), TRUE, "Googlebot"),
  sw_whole("U+00A0 U+200B AdsBot-Google",
           charToRaw(intToUtf8(c(0x00A0, 0x200B,
                                 utf8ToInt("AdsBot-Google")))),
           TRUE, "AdsBot-Google")
)

sw_targets <- c("Googlebot", "Googlebot-Image", "*", "ExampleBot",
                "Mediapartners-Google*")
# Targets run in the `alone` and `same_star` contexts only (ROBO-ipzkxzhg):
# a crawler that ignores `*`, and ASCII values that Google cuts, with the
# Google token each was written for, independent of the code's predicates.
sw_new_targets <- c("AdsBot-Google", "\"Googlebot\"", "Google bot")
sw_new_contexts <- c("alone", "same_star")
sw_ascii_meant <- c("\"Googlebot\"" = "Googlebot", "Google bot" = "Googlebot")
sw_google <- ascii_lower(validation_google_tokens())
sw_crawlers <- google_crawler_tokens_v1()
sw_ignore_star <- sw_crawlers$crawler_token[sw_crawlers$group_selection ==
                                              "exact_only"]
# A crawler that no group of any document names.
sw_stand_in <- "ZzSweepBot"

# The User-agent line with `x` at `position`.
sw_line <- function(target, x, position) {
  switch(position,
         before = sw_bytes("User-agent: ", x, target),
         inside = sw_bytes("User-agent: ", substr(target, 1L, 1L), x,
                           substring(target, 2L)),
         after = sw_bytes("User-agent: ", target, x, " # c"),
         key = sw_bytes(x, "User-agent: ", target),
         whole = sw_bytes("User-agent: ", x),
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
# Google token, and for `*` any crawler. For an ASCII value Google cuts
# (`sw_ascii_meant`) it is the token the value was written for, but `before`
# is that value as written, which Google cuts too, so no loss against it is
# seen: check (i) asks the backend for that token directly.
sw_tokens <- function(target) {
  token <- sub("[^A-Za-z_-].*$", "", target)
  if (target %in% names(sw_ascii_meant)) {
    unname(sw_ascii_meant[[target]])
  } else if (identical(target, "*")) {
    c("ExampleBot", "Googlebot", "AdsBot-Google")
  } else if (ascii_lower(token) %in% sw_google) {
    token
  } else {
    character()
  }
}

# Google's decisions in one call, named "<token> <path>": each `quoted`
# token on /x and, with `fallback`, what the fallback sentences need: the
# stand-in crawler on /x and /y (every `*` group of a context disallows
# /y, the line's group /x), and each crawler that ignores `*` on /x.
sw_query <- function(doc, quoted, fallback) {
  tokens <- quoted
  paths <- rep("/x", length(quoted))
  if (fallback) {
    tokens <- c(tokens, sw_stand_in, sw_stand_in, sw_ignore_star)
    paths <- c(paths, "/x", "/y", rep("/x", length(sw_ignore_star)))
  }
  r <- robots_evaluate_text_v1(rawToChar(doc),
                               paste0("https://example.com", paths), tokens,
                               "google", "google")$results
  stats::setNames(r$url_decision, paste(tokens, paths))
}

# The token a row quotes in `pattern` (one `%s` group), or NA.
sw_quoted <- function(message, pattern) {
  hit <- regmatches(message, regexec(pattern, message))[[1L]]
  if (length(hit) == 2L) hit[[2L]] else NA_character_
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
    lapply(sw_full, function(x) {
      list(x = x, contexts = names(sw_contexts), new = TRUE)
    }),
    lapply(sw_rest, function(x) list(x = x, contexts = "alone", new = FALSE)),
    lapply(sw_multi, function(x) {
      list(x = x, contexts = sw_new_contexts, new = FALSE)
    })
  )
  for (run in runs) {
    x <- run$x
    for (context in run$contexts) {
      line <- sw_contexts[[context]]$line
      targets <- sw_targets
      if (run$new && context %in% sw_new_contexts) {
        targets <- c(targets, sw_new_targets)
      }
      if (!is.null(x$target)) {
        targets <- x$target
      }
      for (target in targets) {
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
          weak <- grepl("Google does not read it so.", cut$message,
                        fixed = TRUE)
          # Whether the backend is needed: a claim to check, or a loss
          # that a row on the line would have to warn about.
          scoped <- x$repaired || identical(target, "*") ||
            identical(position, "key")
          need <- length(tokens) > 0L &&
            (any(claims | loses | reaches | weak) ||
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
            # (i) the weaker "Google does not read it so" only where the
            # crawler of the token it quotes still gets the group, asked of
            # the backend for that token whatever the target (ROBO-ipzkxzhg:
            # not one that ignores the group's `*` line).
            if (weak[[k]]) {
              meant <- sub("^.*If this line was meant as `([^`]*)`.*$", "\\1",
                           message)
              expect_identical(sw_decide(doc, meant)[[meant]], "disallow",
                               label = paste(label, meant))
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
            # ... nor on a value written for a Google token that Google
            # cuts in ASCII (ROBO-ipzkxzhg), by the sweep's own list.
            if (target %in% names(sw_ascii_meant)) {
              expect_false(grepl("nothing changes for them", message,
                                 fixed = TRUE), label = label)
            }
            # (f) "follows this group" and (h) "nothing changes for that
            # crawler" quote a Google token; (g) the fallback sentence is
            # checked for a crawler no group names and, beside `*`, for
            # each crawler that ignores `*`. One backend call per row at
            # most; (g) once per context, position and token read, as no
            # other byte of the value moves a crawler the line does not
            # name.
            follows <- sw_quoted(message, paste0(
              "'([^']*)' is a Google crawler token, so that Google crawler ",
              "follows this group"
            ))
            same <- sw_quoted(message, paste0(
              "'([^']*)' is the Google crawler token the value names, so ",
              "nothing changes for that crawler"
            ))
            # (h) against the target written plainly, when it is that token.
            if (!is.na(same) && !identical(
              ascii_lower(same), ascii_lower(sub("[^A-Za-z_-].*$", "", target))
            )) {
              same <- NA_character_
            }
            kind <- if (grepl("still gets this group from Google's", message,
                              fixed = TRUE)) {
              "kept"
            } else if (grepl("value gets the `User-agent: *` group", message,
                             fixed = TRUE)) {
              "star"
            } else if (grepl("value gets no rules from Google's", message,
                             fixed = TRUE)) {
              "none"
            } else {
              NA_character_
            }
            read <- sw_quoted(message, "value is read as '([^']*)'")
            read <- if (is.na(read)) "" else ascii_lower(read)
            fb_key <- paste("fallback", context, position, read, kind)
            fb_new <- !is.na(kind) && is.null(clean[[fb_key]])
            quoted <- as.character(stats::na.omit(c(follows, same)))
            got <- if (length(quoted) > 0L || fb_new) {
              sw_query(doc, quoted, fb_new)
            }
            if (!is.na(follows)) {
              expect_identical(got[[paste(follows, "/x")]], "disallow",
                               label = paste(label, follows))
            }
            if (!is.na(same)) {
              same_key <- paste(key, "same", same)
              if (is.null(clean[[same_key]])) {
                assign(same_key, sw_decide(plain, same), envir = clean)
              }
              expect_identical(got[[paste(same, "/x")]],
                               clean[[same_key]][[same]],
                               label = paste(label, same))
            }
            if (fb_new) {
              assign(fb_key, TRUE, envir = clean)
              fb <- got[paste(sw_stand_in, c("/x", "/y"))]
              want <- switch(kind,
                             kept = c("disallow", "allow"),
                             star = c("allow", "disallow"),
                             none = c("allow", "allow"))
              expect_identical(unname(fb), want, label = label)
            }
            # Each crawler the kept fallback excepts gets no rules (allow),
            # and each crawler that ignores `*` it leaves out gets the group
            # through a line of its own (ROBO-ipzkxzhg). The `*` tail's list
            # is not checked so here; the hand pins in
            # test-invisible-space-jsecjjyo.R check it.
            if (identical(kind, "kept") && fb_new) {
              listed <- sw_quoted(message, paste0(
                "Google's crawlers? that ignores? `\\*` \\(([^)]*)\\) ",
                "do[es]{0,2} not get it through"
              ))
              listed <- if (is.na(listed)) {
                character()
              } else {
                strsplit(listed, ", | and ")[[1L]]
              }
              for (token in sw_ignore_star) {
                expect_identical(got[[paste(token, "/x")]],
                                 if (token %in% listed) "allow" else
                                   "disallow",
                                 label = paste(label, token))
              }
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
