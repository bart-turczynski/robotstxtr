# Content-Type and a content flag on robots.txt fetch rows (ROBO-nhuirvrd).
# The flag is a heuristic read of the body (R/content-check.R); it never
# changes a decision. Responses are scripted at the ssrfr boundary
# (helper-fake-ssrfr.R); one case goes over the wire to a loopback server.

ct_router <- function(routes) {
  function(req) {
    res <- routes[[req$url]]
    if (is.null(res)) {
      return(fake_response(404L, req$url))
    }
    res
  }
}

# Fetch http://a/robots.txt answered by `res`; the source row.
ct_fetch_one <- function(res, env = parent.frame()) {
  local_fake_ssrfr(ct_router(list("http://a/robots.txt" = res)), env = env)
  robots_fetch("http://a/")$robots
}

# The flag of a 200 serving `body` (a string or raw bytes).
ct_flag <- function(body, env = parent.frame()) {
  ct_fetch_one(fake_response(200L, body = body), env = env)$content_flag
}

ct_html <- paste0(
  "<!DOCTYPE html>\n<html><head><title>Not found</title></head>\n",
  "<body><p>Disallow: /</p></body></html>\n"
)

# --- The columns --------------------------------------------------------------

test_that("ROBO-nhuirvrd: content_type and content_flag are character", {
  local_fake_ssrfr(ct_router(list(
    "http://a/robots.txt" = fake_response(200L, body = "user-agent: *\n")
  )))
  x <- robots_fetch("http://a/")
  expect_type(x$robots$content_type, "character")
  expect_type(x$robots$content_flag, "character")
  empty <- robots_fetch(character())
  expect_type(empty$robots$content_type, "character")
  expect_type(empty$robots$content_flag, "character")
})

test_that("ROBO-nhuirvrd: an HTML body is flagged and still matched", {
  local_fake_ssrfr(ct_router(list(
    "http://a/robots.txt" = fake_response(
      200L, headers = list("Content-Type" = "text/html"), body = ct_html
    )
  )))
  x <- allowed_by_robots_url("http://a/x", "bot")
  expect_identical(x$robots$fetch_outcome, "fetched")
  expect_identical(x$robots$body[[1L]], charToRaw(ct_html))
  expect_true(x$results$allowed)
  expect_identical(x$robots$content_type, "text/html")
  expect_identical(x$robots$content_flag, "html")
  expect_identical(x$robots, robots_fetch("http://a/")$robots)
})

test_that("ROBO-nhuirvrd: a flagged body keeps the rules it spells out", {
  # A NUL-bearing body is "binary", and its rules still match (NUL removed,
  # R/body-decode.R): the flag decides nothing.
  local_fake_ssrfr(ct_router(list(
    "http://a/robots.txt" = fake_response(200L, body = c(
      charToRaw("user-agent: *\n"), as.raw(0), charToRaw("disallow: /x\n")
    ))
  )))
  x <- allowed_by_robots_url(c("http://a/x", "http://a/y"), "bot")
  expect_identical(x$robots$content_flag, "binary")
  expect_identical(x$results$allowed, c(FALSE, TRUE))
})

test_that("ROBO-nhuirvrd: the text path and the legacy adapter write NA", {
  text <- allowed_by_robots_text(ct_html, "http://a/", "bot")
  expect_identical(text$robots$content_type, NA_character_)
  expect_identical(text$robots$content_flag, NA_character_)

  engine <- robots_evaluate_text_v1(
    ct_html, "http://a/", "bot", "google", "google"
  )
  legacy <- as_legacy_robots_decisions_v1(engine)
  expect_identical(legacy$robots$content_type, NA_character_)
  expect_identical(legacy$robots$content_flag, NA_character_)

  local_fake_ssrfr(ct_router(list(
    "http://a/robots.txt" = fake_response(
      200L, headers = list("Content-Type" = "text/html"), body = ct_html
    )
  )))
  url <- allowed_by_robots_url("http://a/", "bot")
  both <- rbind(text$robots, url$robots)
  expect_identical(both$content_type, c(NA, "text/html"))
  expect_identical(both$content_flag, c(NA, "html"))
})

# --- Content-Type -----------------------------------------------------------

test_that("ROBO-nhuirvrd: Content-Type is kept as received", {
  row <- ct_fetch_one(fake_response(
    200L, headers = list("Content-Type" = "text/plain; charset=UTF-8"),
    body = "user-agent: *\n"
  ))
  expect_identical(row$content_type, "text/plain; charset=UTF-8")
  expect_identical(row$content_flag, NA_character_)
})

test_that("ROBO-nhuirvrd: no Content-Type is NA", {
  row <- ct_fetch_one(fake_response(200L, body = "user-agent: *\n"))
  expect_identical(row$content_type, NA_character_)
})

test_that("ROBO-nhuirvrd: Content-Type does not make the flag", {
  row <- ct_fetch_one(fake_response(
    200L, headers = list("Content-Type" = "text/html"),
    body = "user-agent: *\ndisallow: /x\n"
  ))
  expect_identical(row$content_type, "text/html")
  expect_identical(row$content_flag, NA_character_)
})

test_that("ROBO-nhuirvrd: an error status keeps Content-Type, no flag", {
  row <- ct_fetch_one(fake_response(
    404L, headers = list("Content-Type" = "text/html"), body = ct_html
  ))
  expect_identical(row$fetch_outcome, "missing")
  expect_identical(row$content_type, "text/html")
  expect_identical(row$content_flag, NA_character_)
})

test_that("ROBO-nhuirvrd: only the final response's Content-Type counts", {
  local_fake_ssrfr(ct_router(list(
    "http://a/robots.txt" = fake_response(301L, headers = list(
      "Location" = "http://b/robots.txt", "Content-Type" = "text/html"
    )),
    "http://b/robots.txt" = fake_response(200L, body = "user-agent: *\n"),
    "http://c/robots.txt" = fake_response(302L, headers = list(
      "Content-Type" = "text/html"
    )),
    "http://d/robots.txt" = fake_failure("timeout")
  )))
  x <- robots_fetch(c("http://a/", "http://c/", "http://d/"))
  expect_identical(
    x$robots$fetch_outcome, c("fetched", "redirect_error", "timeout")
  )
  expect_identical(x$robots$content_type, rep(NA_character_, 3L))
  expect_identical(x$robots$content_flag, rep(NA_character_, 3L))
})

# --- The flag -----------------------------------------------------------------

test_that("ROBO-nhuirvrd: HTML by doctype or by a leading tag", {
  expect_identical(ct_flag(ct_html), "html")
  expect_identical(ct_flag("  <!doctype   HTML>\n<p>x</p>"), "html")
  expect_identical(ct_flag("<HTML lang=\"en\">\n</HTML>"), "html")
  expect_identical(ct_flag("<head><title>x</title></head>"), "html")
  expect_identical(ct_flag("\r\n\t<body>\r\n"), "html")
  # An XHTML page opens with an XML declaration, and is still HTML.
  expect_identical(
    ct_flag("<?xml version=\"1.0\"?>\n<!DOCTYPE html>\n<html></html>"), "html"
  )
  # A declaration or comment before the marker on the same line.
  expect_identical(
    ct_flag("<!-- x --><!DOCTYPE html><html><body>x</body></html>"), "html"
  )
  expect_identical(
    ct_flag("<?xml version=\"1.0\"?><html xmlns=\"x\"></html>"), "html"
  )
  expect_identical(
    ct_flag("  <?xml version=\"1.0\"?> <!-- a --> <!-- b --> <head>"), "html"
  )
  # A page that does not open with markup (a PHP warning first).
  expect_identical(ct_flag("Warning: oops in x.php\n<html>\n</html>"), "html")
  # A UTF-8 BOM before the markup.
  expect_identical(
    ct_flag(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("<html>"))), "html"
  )
})

test_that("ROBO-nhuirvrd: XML when the body opens with other markup", {
  expect_identical(ct_flag("<?xml version=\"1.0\"?>\n<Error/>"), "xml")
  expect_identical(
    ct_flag("<Error><Code>NoSuchKey</Code></Error>"), "xml"
  )
  expect_identical(ct_flag("\n  <!-- nothing -->\n"), "xml")
  # A tag name that only starts like an HTML one.
  expect_identical(ct_flag("<header>x</header>"), "xml")
  # HTML tag soup without a doctype, html, head or body tag stays xml.
  expect_identical(ct_flag("<div><p>Not found</p></div>"), "xml")
  # A comment before a tag that is not one of the markers.
  expect_identical(ct_flag("<!-- x --><div>"), "xml")
})

test_that("ROBO-qquftxcx: a page opening with markup is HTML by any marker", {
  # A minified page: the markers are mid-line, after inline script or style.
  expect_identical(ct_flag("<script>var a=1;</script><html></html>"), "html")
  expect_identical(ct_flag("<style>p{}</style><body>x</body>"), "html")
  expect_identical(ct_flag("<div><script src=\"/a.js\"></script></div>"),
                   "html")
  expect_identical(ct_flag("<!-- x --><p>x</p><!DOCTYPE  html>"), "html")
  expect_identical(ct_flag("<DIV><STYLE>p{}</STYLE></DIV>"), "html")
  expect_identical(
    ct_flag(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("<script/>"))), "html"
  )
  # A body that does not open with markup needs a line-start marker.
  expect_identical(ct_flag("x <script></script>\n"), NA_character_)
})

test_that("ROBO-qquftxcx: feeds and title, link or meta tags stay xml", {
  # RSS and Atom use <title>, <link> and <meta>-like tags, never an HTML
  # document marker, so none of them makes a body html.
  atom <- paste0(
    "<?xml version=\"1.0\"?><feed xmlns=\"http://www.w3.org/2005/Atom\">",
    "<title>Example</title><link href=\"https://example.com/\"/></feed>\n"
  )
  rss <- paste0(
    "<?xml version=\"1.0\"?>\n<rss version=\"2.0\"><channel>",
    "<title>Example</title><link>https://example.com/</link>",
    "<description>x</description></channel></rss>\n"
  )
  expect_identical(ct_flag(atom), "xml")
  expect_identical(ct_flag(rss), "xml")
  expect_identical(ct_flag("<meta charset=\"utf-8\"><title>x</title>"), "xml")
  # Tag names that only start like a marker.
  expect_identical(ct_flag("<div><headline>x</headline><bodyx/></div>"), "xml")
  expect_identical(ct_flag("<div><scripts/><styles/></div>"), "xml")
})

test_that("ROBO-nhuirvrd: JSON objects and arrays", {
  expect_identical(ct_flag("{\"error\": \"not found\"}"), "json")
  expect_identical(ct_flag(" {\n}"), "json")
  expect_identical(ct_flag("[{\"a\": 1}]"), "json")
  expect_identical(ct_flag("[ ]"), "json")
  expect_identical(ct_flag("[-1, 2]"), "json")
  expect_identical(ct_flag("[true]"), "json")
  # A bracket or brace that opens no JSON value.
  expect_identical(ct_flag("[section]\nuser-agent: *\n"), NA_character_)
  expect_identical(ct_flag("{x}\nuser-agent: *\n"), NA_character_)
})

test_that("ROBO-nhuirvrd: a NUL byte is binary", {
  expect_identical(ct_flag(as.raw(c(0x75, 0x00, 0x73))), "binary")
  # UTF-16LE "user-agent: *": every other byte is NUL.
  utf16 <- as.vector(rbind(charToRaw("user-agent: *"), as.raw(0)))
  expect_identical(ct_flag(utf16), "binary")
  # Binary wins over markup.
  expect_identical(ct_flag(c(charToRaw("<html>"), as.raw(0))), "binary")
})

test_that("ROBO-nhuirvrd: invalid UTF-8 is binary above 10% of the window", {
  # 100 bytes: 10 invalid is at the threshold, 11 is over it.
  at <- c(rep(as.raw(0xff), 10L), charToRaw(strrep("a", 90L)))
  over <- c(rep(as.raw(0xff), 11L), charToRaw(strrep("a", 89L)))
  expect_identical(ct_flag(at), NA_character_)
  expect_identical(ct_flag(over), "binary")
  # A Latin-1 robots.txt has a few invalid bytes, and is no flag.
  latin1 <- c(charToRaw("user-agent: *\ndisallow: /caf"), as.raw(0xe9))
  expect_identical(ct_flag(latin1), NA_character_)
  # A short Latin-1 file: 1 invalid byte in 9 is over 10%, but under 8 bytes.
  expect_identical(
    ct_flag(c(charToRaw("# Caf"), as.raw(0xe9), charToRaw("\n"))),
    NA_character_
  )
  # 20 bytes: 7 invalid is under the minimum count, 8 reaches it.
  expect_identical(
    ct_flag(c(rep(as.raw(0xff), 7L), charToRaw(strrep("a", 13L)))),
    NA_character_
  )
  expect_identical(
    ct_flag(c(rep(as.raw(0xff), 8L), charToRaw(strrep("a", 12L)))),
    "binary"
  )
  # Valid multibyte UTF-8 counts as valid.
  expect_identical(ct_flag(strrep("é", 50L)), NA_character_)
})

test_that("ROBO-nhuirvrd: only the first 4096 bytes are read", {
  ok <- charToRaw(strrep("a", 4096L))
  expect_identical(ct_flag(c(ok, as.raw(0))), NA_character_)
  expect_identical(ct_flag(c(ok, rep(as.raw(0xff), 1000L))), NA_character_)
  expect_identical(ct_flag(c(ok, charToRaw("\n<html>"))), NA_character_)
  # A multibyte character cut at the window's end is not binary.
  cut <- c(charToRaw(strrep("a", 4095L)), charToRaw("é"))
  expect_identical(ct_flag(cut), NA_character_)
  # Within the window, the same bytes flag.
  expect_identical(
    ct_flag(c(charToRaw(strrep("a", 4095L)), as.raw(0))), "binary"
  )
})

test_that("ROBO-nhuirvrd: a robots.txt is no flag", {
  expect_identical(
    ct_flag("User-agent: *\nDisallow: /private/\nSitemap: http://a/s.xml\n"),
    NA_character_
  )
  # A '<' in a comment, a value or a non-HTML tag at a line start.
  expect_identical(ct_flag(paste0(
    "# Questions? <webmaster@a.example> or see <html> docs\n",
    "User-agent: *\nDisallow: /<script>\n"
  )), NA_character_)
  expect_identical(ct_flag(paste0(
    "User-agent: *\n# <!DOCTYPE html>\nDisallow: /x <html>\n"
  )), NA_character_)
  # An empty body.
  expect_identical(ct_flag(""), NA_character_)
})

test_that("ROBO-nhuirvrd: the flag stays in its closed vocabulary", {
  flags <- vapply(
    list(ct_html, "<x/>", "{}", as.raw(0), "user-agent: *\n"),
    function(b) {
      robots_content_flag(if (is.character(b)) charToRaw(b) else b)
    },
    character(1L)
  )
  expect_identical(flags, c("html", "xml", "json", "binary", NA))
  expect_true(all(is.na(flags) | flags %in% content_flag_values))
  expect_identical(robots_content_flag(NULL), NA_character_)
})

# --- Over the wire ------------------------------------------------------------

test_that("ROBO-nhuirvrd: ssrfr's Content-Type reaches the row", {
  skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$get(webfakes::new_regexp("^/"), function(req, res) {
    res$set_status(200L)
    res$set_header("Content-Type", "text/html; charset=utf-8")
    res$send(ct_html)
  })
  server <- webfakes::local_app_process(app)
  url <- server$url("/robots.txt")
  port <- as.integer(sub("^http://127\\.0\\.0\\.1:([0-9]+)/.*$", "\\1", url))
  local_loopback_policy(port)
  row <- robots_fetch(url)$robots
  expect_identical(row$fetch_outcome, "fetched")
  expect_identical(row$content_type, "text/html; charset=utf-8")
  expect_identical(row$content_flag, "html")
})
