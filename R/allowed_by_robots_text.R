#' Match URLs against a supplied robots.txt body
#'
#' Matches one supplied robots.txt body against one or more URLs using the
#' vendored, upstream-test-validated Google robots.txt matcher. No HTTP request
#' is performed; the caller supplies the robots.txt text directly.
#'
#' The URL string is passed to the matcher unchanged. The upstream matcher
#' requires an appropriately encoded, `%`-escaped full URL (per RFC 3986);
#' callers are responsible for supplying it in that form. R does not clean,
#' decode, canonicalize, or reserialize the URL before matching.
#'
#' This is the slice R1 surface: it implements the happy path only. It expects a
#' single non-missing `robots_txt` scalar, a character `url` vector, and a
#' single matcher `user_agent`, and returns the `rule_allow`, `rule_disallow`,
#' and `default_allow` decisions. Full input validation and the per-row
#' `input_unknown` contract (R2), match-metadata correlation (R3), and all
#' fetching (R5-R8) are added by later slices; the columns those slices own are
#' present but filled with `NA` / `"unknown"`.
#'
#' @param robots_txt A single character scalar holding the robots.txt body. An
#'   empty body is valid.
#' @param url A character vector of URL strings to match, passed to the matcher
#'   unchanged.
#' @param user_agent A single matcher user-agent string, passed to the matcher
#'   unchanged (upstream extraction semantics apply, so e.g. `"Googlebot/2.1"`
#'   is not pre-trimmed by R).
#' @param source_id A single non-empty character scalar identifying the supplied
#'   body within the returned object. Defaults to `"supplied"`.
#'
#' @return An S3 object of class `robots_decisions`: a named list with two
#'   components, `results` (one row per input URL, in input order) and `robots`
#'   (one row per supplied source body). The supplied body is stored once as a
#'   raw vector in `robots$body`.
#'
#' @examples
#' allowed_by_robots_text("user-agent: *\ndisallow: /x", "http://a/x", "bot")
#'
#' @useDynLib robotstxtr, .registration = TRUE
#' @export
allowed_by_robots_text <- function(robots_txt, url, user_agent,
                                   source_id = "supplied") {
  # Slice R1 happy-path surface. Full input validation is slice R2; here we make
  # the minimal shape assumptions explicit rather than silently mis-handling.
  body_chr <- enc2utf8(as.character(robots_txt))
  user_agent <- as.character(user_agent)
  url <- as.character(url)
  n <- length(url)

  # Store the exact supplied body once, as raw UTF-8 bytes (§6.6 body handling).
  raw_body <- charToRaw(body_chr)

  allowed <- robotstxtr_allowed_text_(body_chr, url, user_agent)
  matching_line <- robotstxtr_matching_line_text_(body_chr, url, user_agent)

  # Happy-path decision_source (§6.6):
  #   Disallow won            -> rule_disallow  (allowed == FALSE)
  #   Allow won               -> rule_allow     (allowed, a rule matched)
  #   matching ran, no match  -> default_allow  (allowed, no rule matched)
  decision_source <- ifelse(
    !allowed, "rule_disallow",
    ifelse(matching_line > 0L, "rule_allow", "default_allow")
  )

  results <- data.frame(
    input_id = seq_len(n),
    url = url,
    user_agent = rep(user_agent, length.out = n),
    allowed = allowed,
    decision_source = decision_source,
    source_id = rep(source_id, length.out = n),
    # Fetch/network columns owned by later slices (R5-R8): not applicable here.
    robots_url = NA_character_,
    http_status = NA_integer_,
    fetch_outcome = "supplied",
    error_stage = NA_character_,
    error_class = NA_character_,
    error_message = NA_character_,
    # Match-metadata columns owned by slice R3: not yet correlated.
    matched_line = NA_integer_,
    matched_rule_type = "unknown",
    matched_rule_value = NA_character_,
    stringsAsFactors = FALSE
  )

  robots <- data.frame(
    source_id = source_id,
    source_type = "supplied",
    robots_url = NA_character_,
    effective_url = NA_character_,
    http_status = NA_integer_,
    fetch_outcome = "supplied",
    redirect_count = 0L,
    body_size = length(raw_body),
    timeout = NA_real_,
    max_bytes = NA_integer_,
    error_stage = NA_character_,
    error_class = NA_character_,
    error_message = NA_character_,
    stringsAsFactors = FALSE
  )
  # `body` is a list-of-raw column: the supplied body stored exactly once.
  robots$body <- list(raw_body)

  structure(
    list(results = results, robots = robots),
    class = "robots_decisions",
    package_version = as.character(getNamespaceVersion("robotstxtr"))
  )
}
