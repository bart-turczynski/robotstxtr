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
  # A NUL-bearing body is "binary", and its rules still match (a line ends
  # at its first NUL, R/body-decode.R): the flag decides nothing.
  local_fake_ssrfr(ct_router(list(
    "http://a/robots.txt" = fake_response(200L, body = c(
      charToRaw("user-agent: *\ndisallow: /x"), as.raw(0), charToRaw("\n")
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

test_that("ROBO-isbpzgqn: markup whose root is not HTML stays xml", {
  # HTML's markers, used by an SVG, a KML or an S3 error by design, and in
  # feeds that embed markup: none of these roots is an HTML element.
  expect_identical(ct_flag("<svg><style>p{}</style></svg>"), "xml")
  expect_identical(ct_flag("<!DOCTYPE svg><svg><style/></svg>"), "xml")
  expect_identical(
    ct_flag("<kml><Document><Style id=\"a\"/></Document></kml>"), "xml"
  )
  expect_identical(
    ct_flag("<Error><Message>x <style> y</Message></Error>"), "xml"
  )
  expect_identical(ct_flag(paste0(
    "<rss><channel><item><description><![CDATA[<script>a()</script>]]>",
    "</description></item></channel></rss>"
  )), "xml")
  expect_identical(ct_flag(paste0(
    "<?xml version=\"1.0\"?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\">",
    "<entry><content type=\"xhtml\"><div><style>p{}</style></div></content>",
    "</entry></feed>\n"
  )), "xml")
  # A robots.txt that opens with a markup comment is not an HTML page, even
  # when a rule or the comment itself holds a marker.
  expect_identical(
    ct_flag("<!-- generated -->\nUser-agent: *\nDisallow: /*<script\n"), "xml"
  )
  expect_identical(
    ct_flag("<!-- <script> -->\nUser-agent: *\nDisallow: /\n"), "xml"
  )
})

test_that("ROBO-isbpzgqn: the root decides which markers count", {
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  # A UTF-8 BOM, or an XML declaration, before a non-HTML root.
  expect_identical(ct_flag(c(bom, charToRaw("<svg><style/></svg>"))), "xml")
  expect_identical(
    ct_flag(c(bom, charToRaw("<!-- x --><svg><style/></svg>"))), "xml"
  )
  expect_identical(
    ct_flag("<?xml version=\"1.0\"?><svg><style/></svg>"), "xml"
  )
  # An XML declaration before an HTML root.
  expect_identical(
    ct_flag("<?xml version=\"1.0\"?><html><style/></html>"), "html"
  )
  # The root's name is matched in any letter case.
  expect_identical(ct_flag("<HTML><STYLE/></HTML>"), "html")
  expect_identical(ct_flag("<SVG><STYLE/></SVG>"), "xml")
  # An HTML doctype, in any case, makes the page HTML, inline SVG and all. The
  # doctype follows a comment that spans lines, so no line starts with it.
  expect_identical(
    ct_flag("<!-- saved\nfrom --> <!DOCTYPE HTML><svg><style/></svg>"), "html"
  )
  # A namespace prefix does not change the root's local name.
  expect_identical(
    ct_flag(paste0(
      "<html:html xmlns:html=\"http://www.w3.org/1999/xhtml\">",
      "<style/></html:html>"
    )), "html"
  )
  expect_identical(
    ct_flag(paste0(
      "<svg:svg xmlns:svg=\"http://www.w3.org/2000/svg\">",
      "<style/></svg:svg>"
    )), "xml"
  )
  expect_identical(
    ct_flag("<svg xmlns=\"http://www.w3.org/2000/svg\"><style/></svg>"), "xml"
  )
  # A root tag cut at the window's end: no error, and its name still decides.
  expect_identical(
    ct_flag(paste0("<svg xmlns=\"", strrep("a", content_check_bytes))), "xml"
  )
  expect_identical(
    ct_flag(paste0(strrep(" ", content_check_bytes - 2L), "<s")), "xml"
  )
  # A comment that never closes has no root, so its markers are not read.
  expect_identical(ct_flag("<!-- x <script>a()</script>"), "xml")
  # Bytes that are not UTF-8 after the root do not error.
  svg_latin1 <- c(charToRaw("<svg><style/>"), as.raw(0xe9),
                  charToRaw("</svg>"))
  div_latin1 <- c(charToRaw("<div><style/>caf"), as.raw(0xe9),
                  charToRaw("</div>"))
  expect_identical(ct_flag(svg_latin1), "xml")
  expect_identical(ct_flag(div_latin1), "html")
  # The empty body stays NA.
  expect_identical(robots_content_flag(raw()), NA_character_)
})

test_that("ROBO-isbpzgqn: leading items before the root are skipped", {
  # An XML declaration, then an HTML root: only the PI skip reads the root.
  expect_identical(
    ct_flag("<?xml version=\"1.0\"?>\n<div><script>a()</script></div>"),
    "html"
  )
  # A stray end tag before the root.
  expect_identical(ct_flag("</div><html><body>x</body></html>"), "html")
  # A custom element: a name that starts with a letter and holds a hyphen.
  expect_identical(
    ct_flag("<app-root></app-root><script src=\"a.js\"></script>"), "html"
  )
  # The abrupt comment closes, which HTML allows.
  expect_identical(ct_flag("<!--><html><style>"), "html")
  expect_identical(ct_flag("<!---><html><style>"), "html")
  # A doctype other than exactly html is skipped, and the search goes on.
  expect_identical(ct_flag("<!DOCTYPE foo><div><script>"), "html")
  expect_identical(ct_flag("<!DOCTYPE html5><head><style>"), "html")
  # font-face is an SVG element, a reserved name, not a custom element.
  expect_identical(ct_flag("<font-face><style/></font-face>"), "xml")
  # A root name cut at the window's end is not read as a root, even after a
  # marker: the window cannot tell `<s` of `<svg` from a shorter name.
  cut <- paste0("<!-- <script> -->", strrep(" ", 4077L), "<svg>")
  expect_identical(regexpr("<svg", cut, fixed = TRUE)[[1L]], 4095L)
  expect_identical(ct_flag(cut), "xml")
})

test_that("ROBO-isbpzgqn: the comment, name and declaration edges", {
  # A `--!>` closer ends a comment, as HTML's does.
  expect_identical(ct_flag("<!-- a --!><html><style>"), "html")
  # A namespace prefix is no part of a custom element name.
  expect_identical(ct_flag("<ns:my-el><style/>"), "xml")
  # The reserved SVG and MathML names are not custom elements.
  expect_identical(ct_flag("<annotation-xml><style/>"), "xml")
  expect_identical(ct_flag("<color-profile><style/>"), "xml")
  expect_identical(ct_flag("<font-face-src><style/>"), "xml")
  expect_identical(ct_flag("<font-face-uri><style/>"), "xml")
  expect_identical(ct_flag("<font-face-format><style/>"), "xml")
  expect_identical(ct_flag("<font-face-name><style/>"), "xml")
  expect_identical(ct_flag("<missing-glyph><style/>"), "xml")
  # Markup declarations and sections, and a doctype's internal subset, are
  # skipped before the root.
  expect_identical(
    ct_flag("<![if !IE]><html><![endif]><head><style>"), "html"
  )
  expect_identical(ct_flag("<![CDATA[x]]><div><script>"), "html")
  expect_identical(
    ct_flag("<!DOCTYPE x [<!ELEMENT div ANY>]><div><style>"), "html"
  )
  # An unclosed comment is no declaration, so it hides no root.
  expect_identical(ct_flag("<!-- x <html><style>"), "xml")
  # `image` and `selectedcontent` are HTML element names.
  expect_identical(ct_flag("<image><script>"), "html")
  expect_identical(ct_flag("<selectedcontent><style/>"), "html")
})

test_that("ROBO-isbpzgqn: a long run of abrupt comments hits no limit", {
  # Each leading item is atomic: no backtracking through the run, and no
  # PCRE match-limit warning.
  body <- charToRaw(paste0(strrep("<!-->\n", 22L), "<svg><style/>"))
  expect_no_warning(flag <- robots_content_flag(body))
  expect_identical(flag, "xml")
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
