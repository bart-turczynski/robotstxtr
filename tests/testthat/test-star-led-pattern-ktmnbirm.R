# ROBO-ktmnbirm: an Allow or Disallow pattern led by `*` (`*.pdf`) is outside
# RFC 9309's path-pattern grammar. Google's matcher matches it as if led by
# `/`, with a priority one byte lower.

sl_code <- "rule_star_led_pattern"
sl_ua <- "User-agent: *\n"

sl_diag <- function(body) robots_validate_text(body)$diagnostics

# Each body, with the codes it draws today besides the new one.
sl_cases <- list(
  list(body = paste0(sl_ua, "Disallow: *.pdf\n"), codes = character()),
  list(body = paste0(sl_ua, "Disallow: *?\n"),
       codes = "rule_query_crawl_not_index"),
  list(body = paste0(sl_ua, "Disallow: *\n"), codes = character()),
  list(body = paste0(sl_ua, "Allow: *\n"), codes = character()),
  list(body = paste0(sl_ua, "Disallow: **x\n"), codes = character()),
  list(body = paste0(sl_ua, "Allow: *.pdf\n"), codes = character()),
  list(body = paste0(sl_ua, "Disallow: \t  *.pdf   # note\n"),
       codes = character()),
  list(body = "User-agent: *\r\nDisallow: *.pdf\r\n", codes = character()),
  list(body = "User-agent: *\rDisallow: *.pdf\r", codes = character()),
  list(body = "Disallow: *.pdf\nUser-agent: *\nAllow: /\n",
       codes = "rule_without_user_agent")
)

# Bodies that draw no new row: `/`-led, empty, a `*` inside the value or
# only in a comment, and a `*` only on User-agent lines.
sl_silent <- list(
  list(body = paste0(sl_ua, "Disallow: /*.pdf\n"), codes = character()),
  list(body = paste0(sl_ua, "Disallow:\n"), codes = "allow_all_disallow"),
  list(body = paste0(sl_ua, "Disallow: /\n"), codes = character()),
  list(body = paste0(sl_ua, "Disallow: /a*b\n"), codes = character()),
  list(body = paste0(sl_ua, "Disallow: /a # *x\n# Disallow: *.y\n"),
       codes = character()),
  list(body = "User-agent: *\nUser-agent: *bot\nDisallow: /x\n",
       codes = "user_agent_cut")
)

test_that("ROBO-ktmnbirm: today a `*`-led rule draws no row of its own", {
  for (case in sl_cases) {
    d <- sl_diag(case$body)
    expect_identical(d$code, case$codes, label = case$body)
  }
})

test_that("ROBO-ktmnbirm: `/`-led, empty and inner-`*` rules stay silent", {
  for (case in sl_silent) {
    d <- sl_diag(case$body)
    expect_identical(d$code, case$codes, label = case$body)
  }
})

test_that("ROBO-ktmnbirm: Google matches `*X` on the paths `/*X` matches", {
  paths <- c("/", "/x.pdf", "/a/b.pdf", "/x.pdfz", "/x.html", "/pdf",
             "/?q=1", "/a?q=", "/a?b=1&q=2", "/a?b=1", "/q=")
  urls <- paste0("https://example.com", paths)
  pairs <- list(c("*.pdf", "/*.pdf"), c("*?q=", "/*?q="), c("*", "/"))
  for (pair in pairs) {
    decide <- function(pattern) {
      body <- paste0(sl_ua, "Disallow: ", pattern, "\n")
      allowed_by_robots_text(body, urls, "FooBot")$results$allowed
    }
    expect_identical(decide(pair[[1L]]), decide(pair[[2L]]),
                     label = pair[[1L]])
  }
  # `*.pdf` blocks a PDF and leaves other files open.
  x <- allowed_by_robots_text(
    paste0(sl_ua, "Disallow: *.pdf\n"),
    c("https://example.com/x.pdf", "https://example.com/x.html"), "FooBot"
  )
  expect_identical(x$results$allowed, c(FALSE, TRUE))
})

test_that("ROBO-ktmnbirm: a `*` lead ranks one byte below a `/*` lead", {
  # src/robots.cc ranks a match by the pattern's byte length: `*.pdf` (5)
  # loses to `/a.pdf` (6), and `/*.pdf` (6) ties it, so the Allow wins.
  url <- "https://example.com/a.pdf"
  x <- allowed_by_robots_text(
    paste0(sl_ua, "Allow: *.pdf\nDisallow: /a.pdf\n"), url, "FooBot"
  )
  expect_identical(x$results$allowed, FALSE)
  y <- allowed_by_robots_text(
    paste0(sl_ua, "Allow: /*.pdf\nDisallow: /a.pdf\n"), url, "FooBot"
  )
  expect_identical(y$results$allowed, TRUE)
})

test_that("ROBO-ktmnbirm: several `*`-led rules draw nothing today", {
  three <- paste0(sl_ua, "Disallow: *.pdf\nAllow: /a\nDisallow: *.doc\n",
                  "Allow: *.txt\n")
  expect_identical(sl_diag(three)$code, character())
  seven <- paste0(sl_ua, paste0("Disallow: *.e", 1:7, "\n", collapse = ""))
  expect_identical(sl_diag(seven)$code, character())
})

test_that("ROBO-ktmnbirm: a `*?name=` rule draws the valueless note", {
  d <- sl_diag(paste0(sl_ua, "Disallow: *?s=\n"))
  expect_identical(d$code, c("rule_query_parameter_position",
                             "rule_query_crawl_not_index",
                             "rule_query_parameter_valueless"))
})

test_that("ROBO-ktmnbirm: NUL, malformed bytes and long lines today", {
  nul <- c(charToRaw(paste0(sl_ua, "Disallow: ")), as.raw(0),
           charToRaw("*.pdf\n"))
  expect_identical(sl_diag(nul)$code, c("nul_byte", "empty_rule_value"))
  nul_after <- c(charToRaw(paste0(sl_ua, "Disallow: /a")), as.raw(0),
                 charToRaw("*.pdf\n"))
  expect_identical(sl_diag(nul_after)$code, c("nul_byte", "rule_cut_by_nul"))
  bad <- c(charToRaw(paste0(sl_ua, "Disallow: *")), as.raw(0xe9),
           charToRaw(".pdf\n"))
  expect_identical(sl_diag(bad)$code, "invalid_utf8")
  latin1 <- c(charToRaw(paste0(sl_ua, "Disallow: *caf")), as.raw(0xe9),
              charToRaw("\n"))
  expect_identical(sl_diag(latin1)$code, "invalid_utf8")
  long <- paste0(sl_ua, "Disallow: *", strrep("x", 17000L), "\n")
  expect_identical(sl_diag(long)$code, "line_too_long")
})

test_that("ROBO-ktmnbirm: a cut body today", {
  text <- paste0(sl_ua, "Disallow: *.pdf\nAllow: /later-",
                 strrep("x", 200L), "\n")
  x <- validate_document_bytes(charToRaw(text)[seq_len(40L)], "s",
                               "supplied", max_bytes = 40L,
                               body_truncated = TRUE)
  expect_identical(x$diagnostics$code, "body_truncated")
})
