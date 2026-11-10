# ROBO-kzyfejcv: draft-kelley-aipref-training-preference-signal-00 (an
# Internet-Draft dated 2026-10-30) keys an AI-training preference on the
# policy token `__usage_ai-training` in a User-agent line. These pins record
# what the validator does with such a body today, before it knows the token.
# All fixtures are synthesized on example.com.

ai_lines <- function(...) paste0(paste(c(...), collapse = "\n"), "\n")

ai_codes <- function(body) robots_validate_text(body)$diagnostics$code

test_that("today a token group next to a * group draws the wildcard info", {
  d <- robots_validate_text(ai_lines(
    "User-agent: *", "Disallow: /private", "",
    "User-agent: __usage_ai-training", "Disallow: /"
  ))$diagnostics
  expect_identical(d$code, "wildcard_rules_not_inherited")
  expect_identical(d$line, 4L)
  expect_match(d$message, "__usage_ai-training obeys only this group",
               fixed = TRUE)
})

test_that("today no body draws an AI-training code", {
  bodies <- list(
    ai_lines("User-agent: __usage_ai-training", "Disallow: /"),
    ai_lines("User-agent: __usage_ai_training", "Disallow: /"),
    ai_lines("User-agent: __usage_ai-training", "Crawl-delay: 5",
             "Disallow: /"),
    ai_lines("User-agent: *", "Content-Signal: ai-train=no",
             "User-agent: __usage_ai-training", "Disallow: /")
  )
  for (body in bodies) {
    expect_false(any(startsWith(ai_codes(body), "ai_training_")), info = body)
  }
})
