# ROBO-bkzqgvai: a line whose value holds a second directive key, after a
# blank (`User-agent: * Disallow: /`) or glued on (`ExampleBotAllow: /`),
# from line breaks lost when the file was saved. Fixtures are synthetic.
# This first version pins what the validator says today.

dv_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")
dv_text <- function(...) robots_validate_text(dv_lines(...))
dv_codes <- function(x) {
  d <- x$diagnostics
  paste(d$line, d$code)
}

# Google's decision for `token` on `path`, the reading the rows state.
dv_google <- function(body, token, path) {
  r <- robots_evaluate_text_v1(body, paste0("https://example.com", path),
                               token, "google", "google")$results
  paste(r$url_decision, r$matched_line)
}

dv_ex1 <- dv_lines("User-agent: * Disallow: /private/",
                   "User-agent: ExampleBot", "Disallow: /")
dv_a <- dv_lines("User-agent: *", "Disallow: /", "",
                 "User-agent: ExampleBotAllow: /")
dv_b <- dv_lines("User-agent: *Disallow: /private/")
dv_c <- dv_lines("User-agent: *", "Disallow: /admin/Crawl-delay: 10")

test_that("Google's reading of the ticket's examples", {
  # Line 1 is `User-agent: *` with no rule of its own; line 2 joins its
  # group, so line 3 applies to every crawler.
  expect_identical(dv_google(dv_ex1, "OtherBot", "/private/x"), "disallow 3")
  # ExampleBot gets the `*` group: line 4 names `ExampleBotAllow` only.
  expect_identical(dv_google(dv_a, "ExampleBot", "/page"), "disallow 2")
  # No rules at all.
  expect_identical(dv_google(dv_b, "ExampleBot", "/private/x"), "allow NA")
  # The path is `/admin/Crawl-delay: 10`, which `/admin/x` does not match.
  expect_identical(dv_google(dv_c, "ExampleBot", "/admin/x"), "allow NA")
})

test_that("today: the examples draw no row about the hidden key", {
  expect_identical(dv_codes(robots_validate_text(dv_ex1)), character())
  expect_identical(dv_codes(dv_text("User-agent: * Disallow: /")),
                   "NA no_rules")
  expect_identical(dv_codes(dv_text("User-agent: ExampleBot Disallow: /")),
                   c("1 user_agent_cut", "NA no_rules"))
  expect_identical(dv_codes(robots_validate_text(dv_a)),
                   c("4 user_agent_cut", "4 wildcard_disallows_not_inherited"))
  expect_identical(dv_codes(robots_validate_text(dv_b)),
                   c("1 user_agent_cut", "NA no_rules"))
  expect_identical(dv_codes(robots_validate_text(dv_c)),
                   "2 rule_inner_whitespace")
})

test_that("today: example A's rows speak of a crawler `ExampleBotAllow`", {
  d <- robots_validate_text(dv_a)$diagnostics
  expect_true(all(grepl("ExampleBotAllow", d$message, fixed = TRUE)))
  expect_match(d$message[d$code == "wildcard_disallows_not_inherited"],
               "see the user_agent_cut row.", fixed = TRUE)
})
