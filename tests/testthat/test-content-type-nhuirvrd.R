# Content-Type and a content flag on robots.txt fetch rows (ROBO-nhuirvrd).
# Responses are scripted at the ssrfr boundary (helper-fake-ssrfr.R).

ct_router <- function(routes) {
  function(req) {
    res <- routes[[req$url]]
    if (is.null(res)) {
      return(fake_response(404L, req$url))
    }
    res
  }
}

ct_html <- paste0(
  "<!DOCTYPE html>\n<html><head><title>Not found</title></head>\n",
  "<body><p>Disallow: /</p></body></html>\n"
)

test_that("ROBO-nhuirvrd: an HTML body is matched as robots.txt", {
  local_fake_ssrfr(ct_router(list(
    "http://a/robots.txt" = fake_response(
      200L, headers = list("Content-Type" = "text/html"), body = ct_html
    )
  )))
  x <- allowed_by_robots_url("http://a/x", "bot")
  expect_identical(x$robots$fetch_outcome, "fetched")
  expect_identical(x$robots$body[[1L]], charToRaw(ct_html))
  expect_identical(x$results$allowed, TRUE)
  expect_false("content_type" %in% names(x$robots))
})
