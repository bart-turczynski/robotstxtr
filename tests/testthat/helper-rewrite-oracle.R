# The rewrite oracle (ROBO-rdxgnqhw, factored out by ROBO-dkkbwzur): apply a
# validator note's advice to a body, then read both bodies on the package's
# google, bing and yandex backends for every crawler and URL the bodies
# suggest. Where the advice claims identity, no decision may change; where it
# changes decisions on purpose, `expect_change` names the ones that may. A
# green oracle proves the advice is consistent with this package's backends,
# never how Bing or Yandex read a rule (the backends are partly guesses).
#
# The body is split as Google splits it: at LF, CR LF and a lone CR. Each
# engine still reads a body as written, its own way. robots_evaluate_text_v1()
# takes a string, so a body holding a NUL cannot be read here. The bing and
# yandex backends read each crawler under their own token (rw_rename()).

rw_lines <- function(body) {
  strsplit(body, "\r\n|\r|\n", useBytes = TRUE)[[1L]]
}

# The body's lines as Google ends them, each with its own line end, so that
# pasting them back gives the body byte for byte. A rewriter edits these and
# keeps every other line's bytes, line ends included.
rw_chunks <- function(body) {
  b <- charToRaw(body)
  n <- length(b)
  if (n == 0L) {
    return(character())
  }
  lf <- which(b == as.raw(0x0a))
  cr <- which(b == as.raw(0x0d))
  ends <- sort(c(lf, cr[!(cr + 1L) %in% lf]))
  if (length(ends) == 0L || ends[[length(ends)]] < n) {
    ends <- c(ends, n)
  }
  starts <- c(1L, ends[-length(ends)] + 1L)
  vapply(seq_along(ends), function(k) rawToChar(b[starts[[k]]:ends[[k]]]), "")
}

# Any spelling Google takes as a User-agent key.
rw_agent_like <- function(lines) {
  grepl("^[ \t]*(user-agent|useragent|user agent)([^:]*:| )", lines,
        ignore.case = TRUE, useBytes = TRUE)
}

# Every crawler named in the body (cut at the first byte outside a token),
# plus Foo and one named nowhere.
rw_tokens <- function(body) {
  lines <- rw_lines(body)
  agent <- rw_agent_like(lines) &
    grepl(":", lines, fixed = TRUE, useBytes = TRUE)
  value <- sub("^[^:]*:", "", lines[agent], useBytes = TRUE)
  value <- sub("^[ \t]*([A-Za-z_-]*).*$", "\\1", value, useBytes = TRUE)
  unique(c(value[nzchar(value)], "Foo", "Unnamedbot"))
}

# Every rule path in the body, led by `/` or `*`, as written (when led by
# `/`) and without `*` and `$`, a few fixed ones, and each with `x` and `/y`
# after it. Each path a rule spells without `*` and `$` also goes with a
# query (`?x=1`, `/?x=1`) and with `&x`, so that advice which drops the
# query URLs a rule matched shows up. A byte outside printable ASCII goes as
# its `%XX` escape.
rw_urls <- function(body) {
  lines <- rw_lines(body)
  rule <- grepl(":[ \t]*[/*]", lines, useBytes = TRUE) & !rw_agent_like(lines)
  value <- sub("^[^:]*:[ \t]*", "", lines[rule], useBytes = TRUE)
  value <- sub("[ \t]*(#.*)?$", "", value, useBytes = TRUE)
  plain <- gsub("[*$]", "", value, useBytes = TRUE)
  plain <- ifelse(startsWith(plain, "/"), plain, paste0("/", plain))
  path <- unique(c("/", "/a", "/x", "/x/y", "/y", "/z", "/X", "/x?q",
                   value[startsWith(value, "/")], plain))
  path <- unique(c(path, paste0(path, "x"), sprintf("%s/y", path),
                   paste0(plain, "?x=1"), sprintf("%s/?x=1", plain),
                   paste0(plain, "&x")))
  enc <- vapply(path, function(p) {
    paste(vapply(charToRaw(p), function(x) {
      if (x < as.raw(0x21) || x > as.raw(0x7e)) {
        sprintf("%%%02X", as.integer(x))
      } else {
        rawToChar(x)
      }
    }, ""), collapse = "")
  }, "", USE.NAMES = FALSE)
  paste0("https://example.com", enc)
}

# The bing and yandex backends answer only for their own crawlers (any other
# token is an unsupported profile, with no decision), so a body's crawler is
# read there under the backend's token instead: its User-agent lines are
# renamed to it, and lines already naming that token to one named nowhere.
rw_selector <- c(bing = "bingbot", yandex = "Yandex")

rw_rename <- function(body, token, selector) {
  if (identical(ascii_lower(token), ascii_lower(selector))) {
    return(body)
  }
  # Line 1 behind a byte-order mark is renamed too; the mark stays.
  bytes <- charToRaw(body)
  mark <- as.raw(c(0xef, 0xbb, 0xbf))
  if (length(bytes) >= 3L && identical(bytes[1:3], mark)) {
    return(paste0(rawToChar(mark),
                  rw_rename(rawToChar(bytes[-(1:3)]), token, selector)))
  }
  chunks <- rw_chunks(body)
  agent <- which(rw_agent_like(chunks) &
                   grepl(":", chunks, fixed = TRUE, useBytes = TRUE))
  for (k in agent) {
    head <- regmatches(chunks[[k]], regexpr("^[^:]*:[ \t]*", chunks[[k]],
                                            useBytes = TRUE))
    rest <- rw_drop(chunks[[k]], nchar(head, "bytes"))
    name <- regmatches(rest, regexpr("^[A-Za-z_-]*", rest, useBytes = TRUE))
    new <- if (identical(ascii_lower(name), ascii_lower(token))) {
      selector
    } else if (identical(ascii_lower(name), ascii_lower(selector))) {
      "Renamedbot"
    } else {
      next
    }
    chunks[[k]] <- paste0(head, new, rw_drop(rest, nchar(name, "bytes")))
  }
  paste(chunks, collapse = "")
}

# `x` without its first `n` bytes, whatever its encoding.
rw_drop <- function(x, n) {
  b <- charToRaw(x)
  if (n >= length(b)) "" else rawToChar(b[-seq_len(n)])
}

# One read of `body` on `engine`, kept for the next calls: each advice is
# tried in two placements, or row by row, over the same body. The last 64
# reads are kept.
rw_cache <- new.env()
rw_cache$key <- character()
rw_cache$value <- list()

rw_read <- function(body, url, token, engine) {
  key <- paste(c(engine, body, url, token), collapse = "\n\001\n")
  hit <- match(key, rw_cache$key)
  if (!is.na(hit)) {
    return(rw_cache$value[[hit]])
  }
  value <- robots_evaluate_text_v1(body, url, token, engine, engine)$results$
    url_decision
  rw_cache$key <- utils::tail(c(rw_cache$key, key), 64L)
  rw_cache$value <- utils::tail(c(rw_cache$value, list(value)), 64L)
  value
}

# The decisions on `engine` before (`was`) and after (`now`), for every
# (token, url) pair, token by token. On bing and yandex each token reads
# both bodies renamed (rw_rename()); tokens whose renamed bodies are the
# same are read once, and a pair of equal bodies is not read at all.
rw_compare <- function(body, after, tokens, urls, engine) {
  n <- length(urls)
  if (is.na(rw_selector[engine])) {
    url <- rep(urls, times = length(tokens))
    token <- rep(tokens, each = n)
    read <- function(b) rw_read(b, url, token, engine)
    return(list(was = read(body), now = read(after)))
  }
  selector <- rw_selector[[engine]]
  pairs <- lapply(tokens, function(t) {
    c(rw_rename(body, t, selector), rw_rename(after, t, selector))
  })
  key <- vapply(pairs, paste, "", collapse = "\n\001\n")
  first <- match(key, key)
  read <- function(b) rw_read(b, urls, selector, engine)
  out <- lapply(unique(first), function(k) {
    if (identical(pairs[[k]][[1L]], pairs[[k]][[2L]])) {
      same <- rep("same", n)
      return(list(was = same, now = same))
    }
    list(was = read(pairs[[k]][[1L]]), now = read(pairs[[k]][[2L]]))
  })
  pick <- out[match(first, unique(first))]
  list(was = unlist(lapply(pick, `[[`, "was")),
       now = unlist(lapply(pick, `[[`, "now")))
}

# Rewrite `body` (`rewrite`, a function of the body, or the rewritten body
# itself) and compare the decisions on `engines`, for `tokens` and `urls`
# (both bodies' by default). `expect_change`, a function of (engine, token,
# url) vectors returning a logical vector, marks the decisions that may
# change; NULL means none may. Returns the decisions that changed and may
# not, as a data frame (engine, token, url, before, after), empty when the
# advice holds; its "changed" attribute holds every changed decision, so a
# test can also require the changes it expects.
rewrite_oracle <- function(body, rewrite,
                           engines = c("google", "bing", "yandex"),
                           tokens = NULL, urls = NULL, expect_change = NULL) {
  if (is.raw(body)) body <- rawToChar(body)
  after <- if (is.function(rewrite)) rewrite(body) else rewrite
  if (is.raw(after)) after <- rawToChar(after)
  if (is.null(tokens)) tokens <- unique(c(rw_tokens(body), rw_tokens(after)))
  if (is.null(urls)) urls <- unique(c(rw_urls(body), rw_urls(after)))
  url <- rep(urls, times = length(tokens))
  token <- rep(tokens, each = length(urls))
  changed <- lapply(engines, function(engine) {
    read <- rw_compare(body, after, tokens, urls, engine)
    # Every crawler gets a decision: a leg with none would compare nothing.
    stopifnot(!anyNA(read$was), !anyNA(read$now))
    k <- which(read$was != read$now)
    data.frame(engine = rep(engine, length(k)), token = token[k],
               url = url[k], before = read$was[k], after = read$now[k],
               stringsAsFactors = FALSE)
  })
  changed <- do.call(rbind, changed)
  allowed <- if (is.null(expect_change)) {
    logical(nrow(changed))
  } else {
    expect_change(changed$engine, changed$token, changed$url)
  }
  out <- changed[!allowed, , drop = FALSE]
  rownames(out) <- NULL
  attr(out, "changed") <- changed
  out
}
