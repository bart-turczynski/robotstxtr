# v1 results stay byte-identical across the matcher seam refactor
# (ROBO-bukqpjli). The digests in fixtures/matcher-seam-pin-bukqpjli.csv
# were computed before the refactor; helper-matcher-seam-pin-bukqpjli.R
# says what each case evaluates and how a frame is digested.

test_that("ROBO-bukqpjli: every pinned case still yields its pinned digest", {
  skip_if_not(
    is.function(tryCatch(robotstxtr_checked_batch_, error = function(e) NULL)),
    "native binding not built (pure-R install)"
  )
  pinned <- seam_pin_read()
  now <- seam_pin_compute()
  expect_identical(now$case, pinned$case)
  for (k in seq_len(nrow(pinned))) {
    expect_identical(
      now$md5[now$case == pinned$case[[k]]], pinned$md5[[k]],
      label = pinned$case[[k]]
    )
  }
})

test_that("ROBO-bukqpjli: the pinned cases reach every matcher path", {
  skip_if_not(
    is.function(tryCatch(robotstxtr_checked_batch_, error = function(e) NULL)),
    "native binding not built (pure-R install)"
  )
  cases <- seam_cases()
  text <- cases[["text:several-tokens"]]()
  for (backend in c("google", "yandex", "bing")) {
    expect_true(
      any(text$matcher_backend == backend &
            text$matcher_status == "evaluated"),
      label = backend
    )
  }
  expect_true(any(text$matcher_status == "capability_unavailable"))
  expect_true(any(text$reason == "input_invalid"))
  # A cut the google ruleset reads is matched, flagged as cut.
  cut <- cases[["url:cut-at-default-max-bytes"]]()
  read <- cut$robots_policy_ruleset == "google" &
    cut$matcher_backend == "google" & !is.na(cut$url)
  expect_true(all(cut$matcher_status[read] == "evaluated"))
  expect_true(all(cut$matcher_body_truncated[read]))
  # A body over Google's window is matched on the window, flagged.
  over <- cases[["url:over-google-window-uncut"]]()
  google <- over$matcher_backend == "google" &
    over$matcher_status == "evaluated"
  expect_true(any(google))
  expect_true(all(over$matcher_body_truncated[google]))
  expect_true(any(lengths(text$matched_rule_value_raw) > 0L))
})
