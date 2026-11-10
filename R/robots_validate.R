# Validation profile implemented by the exported validation APIs. Keep this a
# stable machine-readable token; prose documentation explains its boundaries.
robots_validation_profile <- "google-parser-compatible"

validation_unsupported <- c(
  "clean-param", "content-signal", "content-usage", "crawl-delay", "domain",
  "host", "noarchive", "nofollow", "noindex", "request-rate",
  "revisit-after", "visit-time"
)

#' Validate a supplied robots.txt document
#'
#' Parses a supplied document with the package's pinned Google-compatible
#' parser and returns byte evidence, directive counts, and stable per-line
#' diagnostics. This validates document syntax and structure; it does not
#' decide whether a URL is allowed, infer webmaster intent, or fetch sitemap
#' resources declared by the document.
#'
#' The validation profile is explicitly `"google-parser-compatible"`. It
#' reports what the vendored parser recognizes (including the parser's accepted
#' typo and missing-colon variants) and adds conservative structural checks. It
#' is not a claim of universal crawler behavior or complete RFC 9309 validity.
#'
#' `robots_txt` may be text or a raw vector. Raw input is useful when validating
#' acquisition bytes that contain malformed UTF-8, a byte-order mark, or NUL
#' bytes. Character input marked UTF-8 is used as written. Unmarked input (as
#' `rawToChar()` gives) is taken as UTF-8 bytes as written when the session's
#' native encoding is UTF-8 or ASCII (the C locale), and converted from the
#' native encoding otherwise; input marked `"latin1"` is converted, and input
#' marked `Encoding = "bytes"` is used verbatim.
#'
#' The result contains three typed data frames: `map` (the validation target),
#' `documents` (one summary row per document), and `diagnostics` (zero or more
#' findings). Diagnostic severities are `"info"`, `"warning"`, and `"error"`;
#' document statuses are `"valid"`, `"warning"`, `"error"`, and
#' `"not_validated"`. An info never changes the status, so a document whose
#' only finding is `no_rules` is `"valid"`.
#'
#' @section Diagnostic codes:
#' Every `code` the validator emits, by the order a document is read. The
#' checks describe the Google-compatible parser; the package's Bing and Yandex
#' matchers agree on both pattern effects (a pattern not led by `/` or `*`
#' never matches, and `$` anchors only as the last character). The sitemap
#' checks are syntax-only: no sitemap is fetched, which is the `sitemapr`
#' package's job. `body_truncated` and the codes starting `acquisition_` come
#' only from [robots_validate_url()].
#'
#' \tabular{lll}{
#'   \strong{Code} \tab \strong{Severity} \tab \strong{Meaning} \cr
#'   \code{byte_order_mark} \tab warning \tab
#'     The document starts with a UTF-8 byte-order mark; the parser skips it.
#'     \cr
#'   \code{misplaced_byte_order_mark} \tab warning \tab
#'     A UTF-8 byte-order mark after the start of the file begins a line, so
#'     the parser reads it as part of the key and ignores that line's
#'     directive. A hidden User-agent line starts no group: the lines after
#'     it stay with the group before it until the next User-agent line. \cr
#'   \code{nul_byte} \tab error \tab
#'     A line holds NUL bytes, which can truncate parsing. \cr
#'   \code{invalid_utf8} \tab error \tab
#'     A line holds bytes that are not well-formed UTF-8 before the line's
#'     first \code{#}. \cr
#'   \code{invalid_utf8_comment} \tab warning \tab
#'     A line's bytes that are not well-formed UTF-8 all sit in its comment,
#'     after the first \code{#}; no rule changes. \cr
#'   \code{malformed_line} \tab error \tab
#'     An active line is not a key-value directive. \cr
#'   \code{line_too_long} \tab error \tab
#'     A line exceeds the parser's 16,663-byte buffer and is truncated. \cr
#'   \code{accepted_missing_colon} \tab warning \tab
#'     A directive without a colon, which the parser accepts. \cr
#'   \code{accepted_directive_typo} \tab warning \tab
#'     A directive name in an accepted typo spelling. \cr
#'   \code{accepted_directive_prefix} \tab warning \tab
#'     A key such as \code{DisallowAITraining} that only starts with
#'     \code{allow} or \code{disallow}, which the parser reads as that rule.
#'     \cr
#'   \code{unsupported_directive} \tab warning \tab
#'     A known directive this profile ignores, such as \code{crawl-delay}. \cr
#'   \code{content_signal_directive} \tab warning \tab
#'     A \code{Content-Signal} line, from an expired Internet-Draft that no
#'     crawler operator documents honoring; it counts as an unsupported
#'     directive. \cr
#'   \code{unknown_directive} \tab warning \tab
#'     A directive this profile does not recognize. \cr
#'   \code{empty_user_agent} \tab error \tab
#'     A User-agent line with an empty value. \cr
#'   \code{user_agent_cut} \tab warning \tab
#'     A User-agent value Google's matcher reads only up to its first
#'     character outside letters, \code{_} and \code{-}, such as
#'     \code{Foo Bot} or \code{Googlebot/2.1}; the message names the token
#'     read, or says it names no crawler (\code{*bot}). The Bing and Yandex
#'     matchers do not cut the value. \cr
#'   \code{rule_without_user_agent} \tab error \tab
#'     An Allow or Disallow in no group a non-empty User-agent opened: before
#'     any, or after an empty User-agent that follows a rule. \cr
#'   \code{empty_rule_value} \tab warning \tab
#'     An empty Allow or Disallow value, which the matcher ignores. \cr
#'   \code{rule_missing_leading_slash} \tab warning \tab
#'     A pattern not led by \code{/} or \code{*}; it never matches. \cr
#'   \code{rule_cut_by_comment} \tab warning \tab
#'     A \code{#} with no space or tab before it starts a comment inside an
#'     Allow or Disallow value, cutting the rule at the \code{#}. A vertical
#'     tab or form feed before the \code{#} still counts as no space. \cr
#'   \code{rule_inner_dollar} \tab warning \tab
#'     A \code{$} before a pattern's end; it matches a literal \code{$}. \cr
#'   \code{rule_escaped_unreserved} \tab warning \tab
#'     A pattern percent-escapes an unreserved character, such as \code{\%7E}
#'     for \code{~}. Google matches only the escape, never the character,
#'     though RFC 9309 section 2.2.2 decodes it. One per rule line. \cr
#'   \code{empty_sitemap_value} \tab warning \tab
#'     A Sitemap line with an empty value. \cr
#'   \code{invalid_sitemap_url} \tab warning \tab
#'     A Sitemap value that is not a valid absolute URL. \cr
#'   \code{unsupported_sitemap_scheme} \tab warning \tab
#'     A Sitemap scheme other than \code{http}, \code{https} or \code{ftp}. \cr
#'   \code{wildcard_rules_not_inherited} \tab info \tab
#'     A named User-agent group lacks some \code{User-agent: *} rules, which
#'     its crawlers therefore do not obey. Anchored on the group's first
#'     User-agent line. Not reported for a body cut at \code{max_bytes}. \cr
#'   \code{disallow_tied_by_allow} \tab warning \tab
#'     A Disallow never takes effect: an Allow with the identical pattern
#'     applies to the same crawlers and wins the tie. Anchored on the
#'     Disallow line; the message names the Allow line. \cr
#'   \code{duplicate_rule} \tab info \tab
#'     An Allow or Disallow repeats an earlier rule of the same type and
#'     pattern for the same crawlers, so it has no effect. Anchored on the
#'     repeat; the message names the earlier line. \cr
#'   \code{missing_user_agent} \tab error \tab
#'     Allow or Disallow rules exist but no line names a non-empty
#'     User-agent. \cr
#'   \code{html_body} \tab warning \tab
#'     The body looks like an HTML page, not a robots.txt; its lines are still
#'     read and reported one by one. \cr
#'   \code{no_rules} \tab info \tab
#'     The parser read no Allow or Disallow rule, so the document restricts
#'     nothing.
#'     Not reported for a body cut at \code{max_bytes}. \cr
#'   \code{body_truncated} \tab warning \tab
#'     The body exceeded \code{max_bytes}; only lines before the cut were read.
#'     \cr
#'   \code{acquisition_input_invalid} \tab error \tab
#'     An input URL could not be turned into a robots.txt origin. \cr
#'   \code{acquisition_missing} \tab info \tab
#'     A 404 or 410: no robots.txt; what that means for crawling is in
#'     \code{message}. \cr
#'   \code{acquisition_http_4xx} \tab warning \tab
#'     Another 4xx; \code{message} names the status and what Google, Yandex
#'     and Bing may do. \cr
#'   \code{acquisition_http_429} \tab error \tab
#'     A 429 Too Many Requests, with each engine's reading in
#'     \code{message}. \cr
#'   \code{acquisition_http_5xx} \tab error \tab
#'     A 5xx, with each engine's reading in \code{message}. \cr
#'   \code{acquisition_http_protocol} \tab error \tab
#'     A 1xx or a status outside 100 to 599. \cr
#'   \code{acquisition_limit_exceeded} \tab error \tab
#'     A 3xx body exceeded \code{max_bytes} and was refused whole. \cr
#'   \code{acquisition_partial_response} \tab error \tab
#'     A partial HTTP response was rejected. \cr
#'   \code{acquisition_redirect_over_budget} \tab error \tab
#'     The redirect chain went past five redirects; \code{message} says what
#'     Google, Yandex and Bing may do. \cr
#'   \code{acquisition_redirect_no_location} \tab error \tab
#'     A 3xx named no target to follow; no engine documents what it does. \cr
#'   \code{acquisition_redirect_loop} \tab error \tab
#'     A redirect led back to a URL already requested; no engine documents
#'     what it does. \cr
#'   \code{acquisition_redirect_downgrade} \tab error \tab
#'     An \code{https} to \code{http} redirect was refused for safety, which
#'     no engine documents doing. \cr
#'   \code{acquisition_redirect_non_http} \tab error \tab
#'     A redirect to a scheme other than \code{http} or \code{https} was
#'     refused for safety. \cr
#'   \code{acquisition_transport_failed} \tab error \tab
#'     A timeout, TLS, network or malformed-response failure, with each
#'     engine's reading in
#'     \code{message}. \cr
#'   \code{acquisition_safety_refused} \tab error \tab
#'     The guard refused the origin or a redirect target; \code{message}
#'     names the \code{safety_block_reason}. \cr
#'   \code{acquisition_failed} \tab error \tab
#'     Any other outcome that left no body; the reason is in
#'     \code{message}.
#' }
#'
#' For `accepted_directive_prefix`, Google's parser accepts any key that
#' starts with `allow` or `disallow`, ignoring ASCII case, so
#' `DisallowAITraining: /` is read as `Disallow: /` and blocks the group's
#' crawlers. The Bing and Yandex matchers compare the whole field name and
#' ignore the line, and RFC 9309's grammar (section 2.2) has only `allow` and
#' `disallow` rule records, leaving other records to the crawler (section
#' 2.2.4). The message names the key as written; for a Disallow key it points
#' to a separate `User-agent: __usage_ai-training` group, not stacked under
#' another User-agent line, as the AI-training opt-out.
#' An accepted typo such as `Dissallow` is reported as
#' `accepted_directive_typo` only.
#'
#' For `wildcard_rules_not_inherited`, a crawler obeys only the groups that
#' name it (combined when several do) and ignores the `User-agent: *` group,
#' as RFC 9309 section 2.2.1 says. Each `*` Allow or Disallow is compared
#' with the named crawler's rules by type and value, except that a `*` Allow
#' matching every path (`Allow: /`, `/*`, `*`, or any of these with a final
#' `$`, such as `/*$`) is not listed; a trailing `*` is ignored (`/x` equals
#' `/x*`, and `*` and `/*` equal `/`), `$` is not, and empty values are left
#' out. The message lists the missing `*` rules, ten at most. A crawler whose
#' rules are all explicit allow-all (an empty `Disallow:`, `Allow: /`,
#' `Allow: /*` or `Allow: *`) is not reported; an empty `Allow:` is ignored,
#' and a crawler whose groups have no other rule is reported.
#'
#' For `disallow_tied_by_allow`, an Allow and a Disallow with the same
#' pattern match the same paths with the same priority, and Allow wins the
#' tie (RFC 9309 section 2.2.2), so the Disallow never applies; with
#' `Allow: /`, a `Disallow: /` blocks nothing. The comparison runs on the
#' Google parser's canonical form of each value (`%aa` equals `%AA`, and a
#' raw non-ASCII byte equals its `%XX` escape), with no `*` or `$` stripping.
#' Groups that name the same crawler are combined, a `User-agent: *` Allow
#' never cancels a named crawler's Disallow, and a Disallow is reported only
#' when every crawler its group names has the identical Allow. Bing and
#' Yandex also let Allow win an identical-pattern tie. The check also runs
#' on a body cut at `max_bytes`: lines past the cut cannot revive the
#' Disallow.
#'
#' For `duplicate_rule`, two rules are the same when type and canonical
#' value are byte-identical, as for `disallow_tied_by_allow`, so `/x` and
#' `/x*` are not duplicates. Groups that name the same crawler are combined,
#' `*` and named crawlers are kept apart, and a rule is reported only when
#' every crawler its group names already has it from an earlier line. Empty
#' values and patterns that never match are skipped, and a body cut at
#' `max_bytes` is checked too. A group's only Allow or Disallow line is not
#' reported when a User-agent line follows it: that line keeps the next
#' User-agent line from joining its group.
#'
#' A document holding a NUL byte gets none of `wildcard_rules_not_inherited`,
#' `disallow_tied_by_allow` or `duplicate_rule`, because the parser stops a
#' value at the NUL while the matchers drop it and read on.
#'
#' @param robots_txt A single non-missing character string or a raw vector.
#' @param source_id A single non-empty character string identifying the supplied
#'   document. Defaults to `"supplied"`.
#'
#' @return An S3 object of class `robots_validations`, containing `map`,
#'   `documents`, and `diagnostics` data frames.
#'
#' @examples
#' report <- robots_validate_text(
#'   "user-agent: *\ndisallow: /private\n"
#' )
#' report$documents
#' report$diagnostics
#'
#' malformed <- robots_validate_text(charToRaw(
#'   "disallow: /before-agent\nunknown-field: value"
#' ))
#' malformed$diagnostics
#'
#' @seealso [robots_validate_url()] to fetch and validate, [robots_fetch()] for
#'   acquisition evidence, and [allowed_by_robots_text()] for URL decisions.
#' @export
robots_validate_text <- function(robots_txt, source_id = "supplied") {
  validate_source_id(source_id)
  bytes <- validation_body_bytes(robots_txt)
  validated <- validate_document_bytes(
    bytes = bytes,
    source_id = source_id,
    source_type = "supplied",
    fetch_outcome = "supplied"
  )
  map <- validation_map_row(
    input_id = 1L,
    url = NA_character_,
    source_id = source_id,
    robots_url = NA_character_,
    http_status = NA_integer_,
    fetch_outcome = "supplied",
    error_stage = NA_character_,
    error_class = NA_character_,
    error_message = NA_character_,
    validation_status = validated$document$validation_status
  )
  new_robots_validations(map, validated$document, validated$diagnostics)
}

#' Fetch and validate robots.txt documents for URLs
#'
#' Uses [robots_fetch()] unchanged, then validates each distinct stored raw body
#' exactly once. Shared origins therefore remain shared and no second HTTP path
#' or refetch is introduced. Acquisition failures are retained as evidence and
#' produce `"not_validated"` document rows. A 2xx body over `max_bytes` is cut
#' at the limit: its first `max_bytes` bytes are validated up to their last
#' complete line (the partial line after the last line break is not read), as
#' RFC 9309 section 2.5 allows a crawler to parse. The document row reports
#' the cut with `body_truncated` and `limit_exceeded` both `TRUE` and
#' `final_newline = NA` (the file's end was never read), `byte_size` is the
#' stored size, and a warning diagnostic with code `body_truncated` says most
#' of the file may not have been validated. A 3xx body over
#' `max_bytes` is refused whole and reported as `acquisition_limit_exceeded`,
#' and a 4xx or 5xx keeps its status outcome whatever its body size.
#'
#' A status that leaves no body gets a code for its class (404 and 410
#' `acquisition_missing`, another 4xx `acquisition_http_4xx`, 429
#' `acquisition_http_429`, 5xx `acquisition_http_5xx`, 1xx
#' `acquisition_http_protocol`). Its message names the status, what Google,
#' Yandex and Bing may do with it, and any `Retry-After` delay; the policy
#' behind it is in [robots_engine_contract_v1()]. The document stays
#' `"not_validated"`, so an `acquisition_http_4xx` row (a 4xx other than 404,
#' 410 and 429) has `warning_count` 1 and `error_count` 0.
#'
#' A redirect, transport or safety outcome gets a code of its own too, read
#' from the source row's `terminal_redirect_reason` and `safety_block_reason`
#' (see [robots_fetch()]): `acquisition_redirect_over_budget`,
#' `acquisition_redirect_no_location`, `acquisition_redirect_loop`,
#' `acquisition_redirect_downgrade`, `acquisition_redirect_non_http`,
#' `acquisition_transport_failed` (a timeout, TLS, network or malformed-response
#' failure) and
#' `acquisition_safety_refused`. The message names the outcome and what
#' Google, Yandex and Bing may do, or says that an engine's behavior is not
#' documented. A refusal is robotstxtr's own safety choice, so its message
#' gives no engine verdict for it.
#'
#' This function validates the acquired robots.txt document. It does not answer
#' whether any target URL is allowed; use [allowed_by_robots_url()] for that
#' separate question. It also does not infer webmaster intent or check whether
#' declared remote sitemaps exist.
#'
#' @inheritParams robots_fetch
#'
#' @return An S3 object of class `robots_validations`, containing `map` (one row
#'   per input URL), `documents` (one row per distinct fetch source), and
#'   `diagnostics` data frames.
#'
#' @examples
#' # A refused origin is never fetched, so its document is not validated.
#' # This runs offline.
#' refused <- robots_validate_url("http://169.254.169.254/latest")
#' refused$documents[c("source_id", "validation_status")]
#'
#' \dontrun{
#' # A live fetch of https://example.com/robots.txt, then validation.
#' fetched_validation <- robots_validate_url("https://example.com/private")
#' fetched_validation$documents
#' }
#'
#' @seealso [robots_validate_text()] for supplied bytes and [robots_fetch()] for
#'   acquisition without document validation.
#' @export
robots_validate_url <- function(url, timeout = 10, max_bytes = 524288L,
                                fetch_user_agent = NULL, ssrf_guard = TRUE,
                                safety_level = "strict") {
  fetched <- robots_fetch(
    url = url,
    timeout = timeout,
    max_bytes = max_bytes,
    fetch_user_agent = fetch_user_agent,
    ssrf_guard = ssrf_guard,
    safety_level = safety_level
  )
  validate_fetched_documents(fetched)
}

#' Print a robots.txt validation result
#'
#' @param x A `robots_validations` object.
#' @param ... Additional arguments, currently ignored.
#'
#' @return `x`, invisibly.
#' @examples
#' # A robots_validations object comes from robots_validate_url() or
#' # robots_validate_text(); validating supplied text needs no network.
#' validations <- robots_validate_text("user-agent: *\nDisallow: /private\n")
#' print(validations)
#' @export
print.robots_validations <- function(x, ...) {
  n_documents <- nrow(x$documents)
  n_diagnostics <- nrow(x$diagnostics)
  cat(sprintf(
    "<robots_validations>: %d document%s, %d diagnostic%s\n",
    n_documents, if (n_documents == 1L) "" else "s",
    n_diagnostics, if (n_diagnostics == 1L) "" else "s"
  ))
  if (n_documents > 0L) {
    print(
      x$documents[c(
        "source_id", "validation_status", "byte_size", "line_count",
        "recognized_directives", "warning_count", "error_count"
      )],
      row.names = FALSE
    )
  }
  invisible(x)
}

validation_body_bytes <- function(robots_txt) {
  if (is.raw(robots_txt)) {
    return(robots_txt)
  }
  if (!is.character(robots_txt) || length(robots_txt) != 1L ||
        is.na(robots_txt)) {
    robots_abort(
      "`robots_txt` must be a single non-missing string or a raw vector.",
      "robotstxtr_invalid_validation_document"
    )
  }
  text_body_bytes_v1(robots_txt)
}

new_robots_validations <- function(map, documents, diagnostics) {
  structure(
    list(map = map, documents = documents, diagnostics = diagnostics),
    class = "robots_validations",
    package_version = as.character(getNamespaceVersion("robotstxtr")),
    validation_profile = robots_validation_profile
  )
}

validation_map_row <- function(input_id, url, source_id, robots_url,
                               http_status, fetch_outcome, error_stage,
                               error_class, error_message, validation_status) {
  data.frame(
    input_id = as.integer(input_id),
    url = as.character(url),
    source_id = as.character(source_id),
    robots_url = as.character(robots_url),
    http_status = as.integer(http_status),
    fetch_outcome = as.character(fetch_outcome),
    error_stage = as.character(error_stage),
    error_class = as.character(error_class),
    error_message = as.character(error_message),
    validation_status = as.character(validation_status),
    stringsAsFactors = FALSE
  )
}

empty_validation_diagnostics <- function() {
  data.frame(
    source_id = character(),
    input_id = integer(),
    line = integer(),
    severity = character(),
    code = character(),
    directive = character(),
    raw_text = character(),
    message = character(),
    stringsAsFactors = FALSE
  )
}

validation_diagnostic <- function(source_id, line, severity, code, directive,
                                  raw_text, message, input_id = NA_integer_) {
  data.frame(
    source_id = as.character(source_id),
    input_id = as.integer(input_id),
    line = as.integer(line),
    severity = as.character(severity),
    code = as.character(code),
    directive = as.character(directive),
    raw_text = as.character(raw_text),
    message = as.character(message),
    stringsAsFactors = FALSE
  )
}

validation_status <- function(diagnostics, validated = TRUE) {
  if (!validated) {
    return("not_validated")
  }
  if (any(diagnostics$severity == "error")) {
    return("error")
  }
  if (any(diagnostics$severity == "warning")) {
    return("warning")
  }
  "valid"
}

validate_document_bytes <- function(bytes, source_id, source_type,
                                    robots_url = NA_character_,
                                    effective_url = NA_character_,
                                    http_status = NA_integer_,
                                    fetch_outcome = "supplied",
                                    max_bytes = NA_integer_,
                                    body_truncated = FALSE) {
  # A 2xx body cut at max_bytes (RFC 9309 section 2.5, ROBO-ldpahknv) is
  # validated up to its last complete line: the partial line after it is not
  # the site's. `byte_size` stays the stored size; the file's real end was
  # never read, so `final_newline` is NA.
  stored_size <- length(bytes)
  bytes <- readable_body(bytes, body_truncated)
  parsed <- as.data.frame(
    robotstxtr_validation_parse_(bytes),
    stringsAsFactors = FALSE
  )
  raw_lines <- split_validation_lines(bytes)
  line_count <- length(raw_lines)
  if (nrow(parsed) > 0L) {
    parsed <- parsed[parsed$line <= line_count, , drop = FALSE]
  }

  diag_env <- new.env(parent = emptyenv())
  diag_env$items <- list()
  add_diagnostic <- function(line, severity, code, directive, message) {
    raw_text <- if (!is.na(line) && line <= line_count) {
      render_validation_line(raw_lines[[line]])
    } else {
      NA_character_
    }
    diag_env$items[[length(diag_env$items) + 1L]] <- validation_diagnostic(
      source_id, line, severity, code, directive, raw_text, message
    )
  }

  has_bom <- length(bytes) >= 3L && identical(bytes[1:3], validation_bom)
  if (has_bom) {
    add_diagnostic(
      1L, "warning", "byte_order_mark", NA_character_,
      paste0("A UTF-8 byte-order mark is present; the Google-compatible ",
             "parser skips it.")
    )
  }
  # ROBO-atkmqcov: only the BOM at byte 0 is skipped; one that starts a
  # line's content anywhere else stays at the front of the key.
  for (line in misplaced_bom_lines(raw_lines, has_bom)) {
    hidden <- misplaced_bom_hidden(raw_lines[[line]], line == 1L && has_bom)
    add_diagnostic(
      line, "warning", "misplaced_byte_order_mark", hidden$directive,
      hidden$message
    )
  }

  nul_counts <- if (line_count == 0L) {
    integer()
  } else {
    vapply(raw_lines, function(line) sum(line == as.raw(0)), integer(1L))
  }
  nul_lines <- which(nul_counts > 0L)
  for (line in nul_lines) {
    add_diagnostic(
      line, "error", "nul_byte", NA_character_,
      sprintf("Line contains %d NUL byte(s), which can truncate parsing.",
              nul_counts[[line]])
    )
  }

  # RFC 9309 section 2.3: the file MUST be UTF-8. LF and CR are ASCII, so the
  # document is well-formed exactly when every line is. A line is checked
  # without its NUL bytes, as the matchers read it. The parser cuts a line at
  # its first `#` (GetKeyAndValueFrom), and `#` is never part of a multi-byte
  # sequence, so bad bytes only after it change no rule (ROBO-sniltuap).
  # Its rows go in as one frame: a file can hold thousands of bad lines.
  nul_free_lines <- lapply(raw_lines, nul_free_bytes)
  bad_lines <- which(!vapply(nul_free_lines, function(line_bytes) {
    validUTF8(rawToChar(line_bytes))
  }, logical(1L)))
  encoding_valid <- length(bad_lines) == 0L
  if (!encoding_valid) {
    in_comment <- vapply(nul_free_lines[bad_lines], function(line_bytes) {
      hash <- match(as.raw(0x23), line_bytes)
      !is.na(hash) &&
        validUTF8(rawToChar(validation_raw_slice(line_bytes, 1L, hash - 1L)))
    }, logical(1L))
    diag_env$items[[length(diag_env$items) + 1L]] <- validation_diagnostic(
      source_id, bad_lines, ifelse(in_comment, "warning", "error"),
      ifelse(in_comment, "invalid_utf8_comment", "invalid_utf8"),
      NA_character_,
      vapply(raw_lines[bad_lines], render_validation_line, "",
             USE.NAMES = FALSE),
      ifelse(
        in_comment,
        paste0("Only a comment holds bytes that are not well-formed UTF-8; ",
               "no rule changes."),
        "Line bytes are not well-formed UTF-8."
      )
    )
  }
  encoding <- if (encoding_valid) "utf-8" else "invalid-utf-8"

  active <- !parsed$is_empty & !parsed$is_comment
  malformed <- active & !parsed$has_directive
  for (i in which(malformed)) {
    add_diagnostic(
      parsed$line[[i]], "error", "malformed_line", NA_character_,
      "Active line is not a parseable key-value directive."
    )
  }
  for (i in which(parsed$line_too_long)) {
    add_diagnostic(
      parsed$line[[i]], "error", "line_too_long", parsed$type[[i]],
      "Line exceeds the parser's 16,663-byte buffer and is truncated."
    )
  }

  group_open <- FALSE
  group_has_rule <- FALSE
  nonempty_user_agents <- 0L
  unsupported <- logical(nrow(parsed))
  for (i in which(parsed$has_directive)) {
    line <- parsed$line[[i]]
    type <- parsed$type[[i]]
    value <- parsed$value[[i]]
    action <- validation_ascii_action(parsed$action[[i]], type)

    if (parsed$missing_colon[[i]]) {
      add_diagnostic(
        line, "warning", "accepted_missing_colon", action,
        "Missing colon was accepted by the Google-compatible parser."
      )
    }
    if (parsed$is_typo[[i]]) {
      add_diagnostic(
        line, "warning", "accepted_directive_typo", action,
        "Directive spelling is an accepted Google-parser typo variant."
      )
    }
    if (type %in% c("allow", "disallow") && !parsed$is_typo[[i]]) {
      prefix_key <- validation_prefix_key(
        raw_lines[[line]], line, type, parsed$missing_colon[[i]]
      )
      if (!is.null(prefix_key)) {
        add_diagnostic(
          line, "warning", "accepted_directive_prefix", action,
          validation_prefix_key_message(prefix_key, type)
        )
      }
    }

    if (identical(type, "unknown")) {
      unsupported[[i]] <- !is.na(action) &&
        action %in% validation_unsupported
      if (identical(action, "content-signal")) {
        add_diagnostic(
          line, "warning", "content_signal_directive", action,
          paste0("Content-Signal comes from an expired Internet-Draft and ",
                 "no crawler operator documents honoring it; for an ",
                 "AI-training preference use a separate ",
                 "`User-agent: __usage_ai-training` group, not stacked ",
                 "under another User-agent line.")
        )
      } else if (unsupported[[i]]) {
        add_diagnostic(
          line, "warning", "unsupported_directive", action,
          paste0("Directive is known but ignored by this validation profile; ",
                 "another crawler may use it.")
        )
      } else {
        add_diagnostic(
          line, "warning", "unknown_directive", action,
          "Directive is not recognized by this validation profile."
        )
      }
    }

    if (identical(type, "user-agent")) {
      if (group_has_rule) {
        group_open <- FALSE
        group_has_rule <- FALSE
      }
      if (nzchar(value)) {
        group_open <- TRUE
        nonempty_user_agents <- nonempty_user_agents + 1L
      } else {
        add_diagnostic(
          line, "error", "empty_user_agent", type,
          "User-agent directive has an empty value."
        )
      }
    } else if (type %in% c("allow", "disallow")) {
      if (group_open) {
        group_has_rule <- TRUE
      } else {
        add_diagnostic(
          line, "error", "rule_without_user_agent", type,
          "Allow or Disallow appears before a non-empty User-agent group."
        )
      }
      if (!nzchar(value)) {
        add_diagnostic(
          line, "warning", "empty_rule_value", type,
          "Empty Allow or Disallow value is ignored by the matcher."
        )
      }
      # The parser cuts the line at its first `#` (ROBO-gjhpykcj), so
      # `Disallow: /a#b` is the wider rule `/a`. The parser stops at a NUL,
      # but the matchers drop NULs and read on (R/body-decode.R), so a line
      # with a NUL is checked NUL-free. Otherwise it is gated on has_comment:
      # the parser never sees a `#` past its line buffer.
      has_nul <- nul_counts[[line]] > 0L
      if ((parsed$has_comment[[i]] ||
             (has_nul && !parsed$line_too_long[[i]])) &&
            nzchar(value) &&
            rule_cut_by_comment(nul_free_bytes(raw_lines[[line]]))) {
        add_diagnostic(
          line, "warning", "rule_cut_by_comment", type,
          paste0("A '#' with no space or tab before it starts a comment, ",
                 "so the rule is cut at the '#'.")
        )
      }
    } else if (identical(type, "sitemap") && !nzchar(value)) {
      add_diagnostic(
        line, "warning", "empty_sitemap_value", type,
        "Sitemap directive has an empty value."
      )
    }
    for (found in directive_value_diagnostics(type, value)) {
      add_diagnostic(line, "warning", found$code, type, found$message)
    }
  }

  # The group checks need the values the matchers read. The parser stops a
  # value at a NUL, but every matcher drops the NULs and reads on, so a
  # document with any NUL (already a `nul_byte` error) gets none of the group
  # checks.
  if (length(nul_lines) == 0L) {
    groups <- validation_groups(parsed)
    # Google's matcher reads a User-agent value only up to its first byte
    # outside [A-Za-z_-], so the group names another crawler than written,
    # or none (ROBO-zvhrayhx). The message names the token only (ASCII):
    # the value may not be valid UTF-8, and `raw_text` carries it.
    agents <- groups$agents
    for (i in which(agents$cut)) {
      token <- agents$token[[i]]
      add_diagnostic(
        agents$line[[i]], "warning", "user_agent_cut", "user-agent",
        if (nzchar(token)) {
          sprintf(paste0("User-agent value is read as '%s' by Google's ",
                         "matcher, which stops at the first character ",
                         "outside letters, '_' and '-'."), token)
        } else {
          paste0("User-agent value names no crawler: Google's matcher ",
                 "reads a product token only from a leading run of letters, ",
                 "'_' and '-'.")
        }
      )
    }
    # A named group drops the `*` rules for its crawlers (ROBO-gfjotdrr). On
    # a cut body a group's rules may lie past the cut, so it is skipped.
    if (!body_truncated) {
      inheritance <- wildcard_inheritance_diagnostics(groups)
      for (found in inheritance) {
        add_diagnostic(
          found$line, "info", "wildcard_rules_not_inherited", "user-agent",
          found$message
        )
      }
    }
    # A Disallow an identical Allow ties never applies (ROBO-fdhmlvwm).
    # Lines past a cut can only add Allows or groups, which cannot revive
    # it, so a cut body is checked too.
    for (found in tied_disallow_diagnostics(groups)) {
      add_diagnostic(
        found$line, "warning", "disallow_tied_by_allow", "disallow",
        found$message
      )
    }
    # A rule an earlier identical rule already gives the same crawlers has
    # no effect (ROBO-xexjgecr). Lines past a cut cannot give it one, so a
    # cut body is checked too.
    # Its rows go in as one frame: a file can repeat thousands of rules.
    found <- duplicate_rule_diagnostics(groups)
    if (nrow(found) > 0L) {
      diag_env$items[[length(diag_env$items) + 1L]] <- validation_diagnostic(
        source_id, found$line, "info", "duplicate_rule", found$type,
        vapply(raw_lines[found$line], render_validation_line, "",
               USE.NAMES = FALSE),
        found$message
      )
    }
  }

  # A file with no Allow or Disallow line restricts nothing (RFC 9309
  # section 2.2.1), so a missing User-agent is an error only when rules need
  # one (ROBO-vxrzcqpe). An empty or typo'd rule line still counts. A cut
  # body is not called rule-free: its rules may lie past the cut.
  rule_count <- sum(parsed$type %in% c("allow", "disallow"))
  if (nonempty_user_agents == 0L && rule_count > 0L) {
    add_diagnostic(
      NA_integer_, "error", "missing_user_agent", "user-agent",
      "Document has no non-empty User-agent directive."
    )
  }
  # A body that looks like an HTML page gets one document-level warning
  # (ROBO-ccfsanhq), from the fetch row's sniffer (ROBO-nhuirvrd) read on the
  # validated bytes. Its per-line rows stay: a real rule inside the page is
  # still enforced. A NUL or mostly invalid UTF-8 makes the flag "binary",
  # which nul_byte and invalid_utf8 already report.
  if (identical(robots_content_flag(bytes), "html")) {
    add_diagnostic(
      NA_integer_, "warning", "html_body", NA_character_,
      paste0("The body looks like an HTML page, not a robots.txt; its lines ",
             "were read as directives anyway.")
    )
  }
  if (rule_count == 0L && !body_truncated) {
    add_diagnostic(
      NA_integer_, "info", "no_rules", NA_character_,
      paste0("Document has no Allow or Disallow rules, so it places no ",
             "restrictions on crawling.")
    )
  }
  if (body_truncated) {
    add_diagnostic(
      NA_integer_, "warning", "body_truncated", NA_character_,
      sprintf(
        paste0(
          "Decoded body exceeded max_bytes (%d); only its first %d bytes ",
          "up to the last complete line were validated."
        ),
        as.integer(max_bytes), length(bytes)
      )
    )
  }

  diagnostic_frame <- if (length(diag_env$items) == 0L) {
    empty_validation_diagnostics()
  } else {
    do.call(rbind, diag_env$items)
  }
  core_recognized <- parsed$has_directive & parsed$type != "unknown"
  recognized <- sum(core_recognized) + sum(unsupported)
  unknown <- sum(parsed$has_directive & parsed$type == "unknown" & !unsupported)
  final_newline <- length(bytes) > 0L &&
    bytes[[length(bytes)]] %in% as.raw(c(0x0a, 0x0d))
  if (body_truncated) {
    final_newline <- NA
  }

  document <- data.frame(
    source_id = source_id,
    source_type = source_type,
    robots_url = robots_url,
    effective_url = effective_url,
    http_status = as.integer(http_status),
    fetch_outcome = fetch_outcome,
    validation_status = validation_status(diagnostic_frame),
    profile = robots_validation_profile,
    byte_size = as.integer(stored_size),
    line_count = as.integer(line_count),
    active_line_count = as.integer(sum(active)),
    recognized_directives = as.integer(recognized),
    unknown_directives = as.integer(unknown),
    malformed_lines = as.integer(sum(malformed)),
    user_agent_directives = as.integer(sum(parsed$type == "user-agent")),
    allow_directives = as.integer(sum(parsed$type == "allow")),
    disallow_directives = as.integer(sum(parsed$type == "disallow")),
    sitemap_directives = as.integer(sum(parsed$type == "sitemap")),
    unsupported_directives = as.integer(sum(unsupported)),
    encoding = encoding,
    has_bom = has_bom,
    nul_byte_count = as.integer(sum(nul_counts)),
    final_newline = final_newline,
    max_bytes = as.integer(max_bytes),
    body_truncated = body_truncated,
    limit_exceeded = body_truncated,
    diagnostic_count = as.integer(nrow(diagnostic_frame)),
    warning_count = as.integer(sum(diagnostic_frame$severity == "warning")),
    error_count = as.integer(sum(diagnostic_frame$severity == "error")),
    stringsAsFactors = FALSE
  )
  list(document = document, diagnostics = diagnostic_frame)
}

# Warnings about a non-empty Sitemap, Allow or Disallow value (ROBO-xblfzkid),
# as a list of list(code, message). An empty value is diagnosed by the caller.
# Allow and Disallow values arrive already %-escaped (ASCII); only a Sitemap
# value may be bytes-encoded (malformed UTF-8), so the checks work on raw
# bytes or with useBytes.
directive_value_diagnostics <- function(type, value) {
  if (!nzchar(value)) {
    return(list())
  }
  if (type %in% c("allow", "disallow")) {
    return(rule_value_diagnostics(value))
  }
  if (identical(type, "sitemap")) {
    found <- sitemap_value_diagnostic(value)
    return(if (is.null(found)) list() else list(found))
  }
  list()
}

# The User-agent groups of a parsed document, as the Google matcher forms
# them (src/robots.cc, RobotsMatcher::HandleUserAgent). A User-agent line
# opens a new group when it is the first one or follows an Allow or
# Disallow; consecutive User-agent lines share a group, and Sitemap or
# unknown lines never close one. Reused by ROBO-fdhmlvwm and ROBO-xexjgecr.
# Returns a list of three data frames:
# - `groups`: one row per group, in file order: `group` (integer id),
#   `first_line` (the group's first User-agent line) and `global` (any of
#   its User-agent lines is `*`, alone or followed by whitespace).
# - `agents`: one row per User-agent line: `group`, `line`, `global`,
#   `token` (the ExtractUserAgent run of [A-Za-z_-] as spelled, ASCII; ""
#   for a global line or one led by any other byte), `key`
#   (`ascii_lower(token)`, the merge key) and `cut` (a non-empty, non-global
#   value the token does not spell whole: the matcher reads less than was
#   written, or nothing; ROBO-zvhrayhx).
# - `rules`: one row per Allow or Disallow inside a group (rules before the
#   first User-agent are dropped): `group`, `line`, `type` ("allow" or
#   "disallow"), `value` (canonical, as parsed), `empty` and `key` (type and
#   value with a trailing `*` run removed, `/` for a value of only `*` or
#   `/` then only `*`, NA when `empty`).
validation_groups <- function(parsed) {
  kept <- parsed[parsed$type %in% c("user-agent", "allow", "disallow"),
                 c("line", "type", "value"), drop = FALSE]
  is_agent <- kept$type == "user-agent"
  opens <- is_agent & c(TRUE, !is_agent[-length(is_agent)])
  kept$group <- cumsum(opens)
  kept <- kept[kept$group > 0L, , drop = FALSE]
  is_agent <- kept$type == "user-agent"

  agent_rows <- kept[is_agent, , drop = FALSE]
  agent_bytes <- lapply(agent_rows$value, charToRaw)
  agent_global <- vapply(agent_bytes, function(bytes) {
    length(bytes) >= 1L && bytes[[1L]] == charToRaw("*") &&
      (length(bytes) == 1L || bytes[[2L]] %in% as.raw(c(0x20, 0x09:0x0d)))
  }, logical(1L))
  token_bytes <- charToRaw(paste0(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", "-_"
  ))
  agent_token <- vapply(agent_bytes, function(bytes) {
    outside <- which(!bytes %in% token_bytes)
    run <- if (length(outside) == 0L) length(bytes) else outside[[1L]] - 1L
    rawToChar(bytes[seq_len(run)])
  }, character(1L))
  agents <- data.frame(
    group = as.integer(agent_rows$group),
    line = as.integer(agent_rows$line),
    global = agent_global,
    token = agent_token,
    key = ascii_lower(agent_token),
    cut = !agent_global & lengths(agent_bytes) > nchar(agent_token, "bytes"),
    stringsAsFactors = FALSE
  )

  group_ids <- unique(agents$group)
  groups <- data.frame(
    group = group_ids,
    first_line = agents$line[match(group_ids, agents$group)],
    global = group_ids %in% agents$group[agents$global],
    stringsAsFactors = FALSE
  )

  rule_rows <- kept[!is_agent, , drop = FALSE]
  empty <- !nzchar(rule_rows$value)
  # `/x` and `/x*` match the same paths, and `*`, `**` and `/*` match every
  # path as `/` does; the empty no-op value stays apart (NA). `$` is
  # significant and kept.
  stripped <- sub("\\*+$", "", rule_rows$value, useBytes = TRUE)
  stripped[!nzchar(stripped)] <- "/"
  key <- paste(rule_rows$type, stripped)
  key[empty] <- NA_character_
  rules <- data.frame(
    group = as.integer(rule_rows$group),
    line = as.integer(rule_rows$line),
    type = as.character(rule_rows$type),
    value = as.character(rule_rows$value),
    empty = empty,
    key = key,
    stringsAsFactors = FALSE
  )
  list(groups = groups, agents = agents, rules = rules)
}

# A crawler obeys only the groups that name it (merged, as Google does) and
# never the `*` group (ROBO-gfjotdrr). For each named agent, the `*` rules
# missing from its effective rules, as a list of list(line, agents, missing,
# message): `line` is the first User-agent line of the first group naming
# the agents, `agents` their tokens as first spelled, `missing` the lines of
# every missing `*` rule (uncapped) and `message` the capped text. An agent
# whose rules are all explicit allow-all (an empty Disallow, or an Allow
# keyed `/`) is exempt; an empty Allow is a no-op and is not counted, so an
# agent with no other rule is not exempt. A `*` Allow that matches every path
# (ROBO-gkuuwbgc) is never a missing rule. Rows come in anchor-line order:
# agents are visited in the order they are first named.
wildcard_inheritance_diagnostics <- function(groups) {
  rules <- groups$rules
  # An empty key (a global line, or one led by a byte outside [A-Za-z_-])
  # names no crawler.
  agents <- groups$agents[nzchar(groups$agents$key), , drop = FALSE]
  # A `*` Allow that matches every path is not compared (ROBO-gkuuwbgc). Its
  # key drops a trailing `*` run, so `/`, `/*`, `*` and `/**` all read as
  # `allow /`; a final `$` stays in the key, so `allow /*$` and `allow *$` are
  # matched here by the `\*+\$?` tail. `allow /$` matches only `/`.
  every_path <- grepl("^allow (/|/?\\*+\\$?)$", rules$key)
  global <- rules[!rules$empty & !every_path &
                    rules$group %in% groups$groups$group[groups$groups$global],
                  , drop = FALSE]
  global <- global[!duplicated(global$key), , drop = FALSE]
  no_op <- rules$type == "allow" & rules$empty
  allow_all <- (rules$type == "disallow" & rules$empty) |
    (!rules$empty & rules$key == "allow /")

  losers <- list()
  for (key in unique(agents$key)) {
    agent_groups <- unique(agents$group[agents$key == key])
    in_effect <- rules$group %in% agent_groups
    judged <- in_effect & !no_op
    if (any(judged) && all(allow_all[judged])) {
      next
    }
    missing <- which(!global$key %in% rules$key[in_effect])
    if (length(missing) == 0L) {
      next
    }
    losers[[length(losers) + 1L]] <- list(
      token = agents$token[[match(key, agents$key)]],
      first_group = min(agent_groups),
      one_group = length(agent_groups) == 1L,
      missing = missing
    )
  }

  signature <- paste(
    vapply(losers, `[[`, integer(1L), "first_group"),
    vapply(losers, function(x) paste(x$missing, collapse = ","), "")
  )
  sets <- split(seq_along(losers), factor(signature, unique(signature)))
  lapply(unname(sets), function(i) {
    members <- losers[i]
    missing <- members[[1L]]$missing
    tokens <- vapply(members, `[[`, "", "token")
    list(
      line = groups$groups$first_line[[
        match(members[[1L]]$first_group, groups$groups$group)
      ]],
      agents = tokens,
      missing = global$line[missing],
      message = wildcard_inheritance_message(
        tokens, all(vapply(members, `[[`, TRUE, "one_group")),
        global[missing, , drop = FALSE]
      )
    )
  })
}

# Allow wins a tie in priority (src/robots.cc, RobotsMatcher::disallow() uses
# a strict `>`), so a Disallow whose canonical value an Allow repeats, in the
# rules a crawler obeys, never decides a URL (ROBO-fdhmlvwm). A crawler token
# is `*` for a global User-agent line and the merge key otherwise; groups
# naming the same token merge, and a `*` Allow never reaches a named token.
# A Disallow is reported only when, for every token its group names, a group
# naming that token holds an Allow with the byte-identical value (no `*` or
# `$` stripping: `rules$key` is not used). Empty values, patterns not led by
# `/` or `*` (they never match) and groups naming no token are skipped.
# Returns a list of list(line, allow_line, message) in Disallow line order;
# `allow_line` is the smallest line among each token's first identical Allow.
# The work is vectorized: files of hundreds of groups and rules are in scope.
tied_disallow_diagnostics <- function(groups) {
  expand <- validation_token_expander(groups)
  rules <- groups$rules
  rules <- rules[substr(rules$value, 1L, 1L) %in% c("/", "*"), , drop = FALSE]
  disallows <- rules[rules$type == "disallow", , drop = FALSE]
  allows <- rules[rules$type == "allow" & rules$value %in% disallows$value, ,
                  drop = FALSE]
  # Rules are in file order, so the first of each key has the smallest line.
  allows <- allows[!duplicated(paste(allows$group, allows$value, sep = "\n")),
                   , drop = FALSE]
  by_allow <- expand(allows$group)
  allow_key <- paste(by_allow$class, allows$value[by_allow$owner], sep = "\n")
  allow_line <- allows$line[by_allow$owner]
  first <- !duplicated(allow_key)
  allow_key <- allow_key[first]
  allow_line <- allow_line[first]

  by_disallow <- expand(disallows$group)
  hit <- allow_line[match(
    paste(by_disallow$class, disallows$value[by_disallow$owner], sep = "\n"),
    allow_key
  )]
  untied <- unique(by_disallow$owner[is.na(hit)])
  tied <- !by_disallow$owner %in% untied
  owner <- by_disallow$owner[tied]
  hit <- hit[tied]
  order_by <- order(owner, hit)
  owner <- owner[order_by]
  hit <- hit[order_by]
  first <- !duplicated(owner)
  owner <- owner[first]
  hit <- hit[first]

  value <- disallows$value[owner]
  message <- sprintf(
    paste0(
      "Disallow never takes effect: the Allow on line %d has the ",
      "identical pattern, and Allow wins ties (RFC 9309 section 2.2.2)."
    ),
    hit
  )
  root <- value == "/"
  message[root] <- paste(
    message[root], "With Allow: / this Disallow: / blocks nothing."
  )
  Map(function(line, allow_line, message) {
    list(line = line, allow_line = allow_line, message = message)
  }, disallows$line[owner], hit, message, USE.NAMES = FALSE)
}

# The crawler tokens of the groups the rule checks merge over (ROBO-fdhmlvwm,
# ROBO-xexjgecr): `*` for a global User-agent line, the merge key otherwise;
# a line naming no token is dropped, and a `*` token never stands for a named
# one. Returns a function that crosses a vector of rule group ids with the
# token classes of each group, as list(owner, class): `owner` indexes the
# input (ascending, so rows keep its order) and `class` is the token class.
validation_token_expander <- function(groups) {
  agents <- groups$agents
  token <- ifelse(agents$global, "*", agents$key)
  group <- agents$group[nzchar(token)]
  token <- token[nzchar(token)]
  # Tokens named by the same set of groups are interchangeable here, so one
  # class stands for each such set (a group of 6,000 agents is one class).
  # Rows stay in group order, as agent lines are in file order.
  signature <- vapply(split(group, token), function(g) {
    paste(unique(g), collapse = " ")
  }, "")
  class <- match(signature, unique(signature))[match(token, names(signature))]
  pair <- !duplicated(paste(group, class))
  class_group <- group[pair]
  class_id <- class[pair]
  group_ids <- unique(class_group)
  start <- match(group_ids, class_group)
  count <- tabulate(match(class_group, group_ids), length(group_ids))
  function(rule_group) {
    k <- match(rule_group, group_ids)
    n <- count[k]
    n[is.na(k)] <- 0L
    owner <- rep(seq_along(rule_group), n)
    list(owner = owner, class = class_id[start[k[owner]] + sequence(n) - 1L])
  }
}

# A rule that repeats an earlier rule, in the rules a crawler obeys, never
# changes a decision (ROBO-xexjgecr). Tokens merge as in
# tied_disallow_diagnostics(). A rule is reported when, for every token its
# group names, an earlier line in a group naming that token holds a rule of
# the same type and byte-identical canonical value (no `*` or `$` stripping:
# `rules$key` is not used, so `/x` and `/x*` differ). Empty values, patterns
# not led by `/` or `*`, groups naming no token, and a group's only rule
# line when a User-agent line follows it are skipped. Returns a data frame
# of `line`, `type` and `message`, in line order; the message names the
# smallest line among each token's first identical rule.
duplicate_rule_diagnostics <- function(groups) {
  expand <- validation_token_expander(groups)
  rules <- groups$rules
  # Any rule line, empty or not, ends its group. A group's only rule line
  # keeps the next User-agent line from joining it, so it is not reported
  # when a User-agent line follows it: deleting it would merge the groups.
  rule_lines <- tabulate(match(rules$group, groups$groups$group),
                         nrow(groups$groups))
  rules$sole <- rule_lines[match(rules$group, groups$groups$group)] == 1L &
    rules$line < max(groups$agents$line, -Inf)
  rules <- rules[substr(rules$value, 1L, 1L) %in% c("/", "*"), , drop = FALSE]
  by_rule <- expand(rules$group)
  owner <- by_rule$owner
  key <- paste(by_rule$class, rules$type[owner], rules$value[owner],
               sep = "\n")
  # Rows are in file order, so a key's first row has its smallest line.
  first <- rules$line[owner[match(key, key)]]
  uncovered <- unique(owner[first == rules$line[owner] | rules$sole[owner]])
  covered <- !owner %in% uncovered
  owner <- owner[covered]
  first <- first[covered]
  order_by <- order(owner, first)
  owner <- owner[order_by]
  first <- first[order_by]
  keep <- !duplicated(owner)
  owner <- owner[keep]
  first <- first[keep]

  type <- rules$type[owner]
  message <- sprintf(
    "Rule has no effect: line %d already has the same %s.",
    first, ifelse(type == "allow", "Allow", "Disallow")
  )
  data.frame(
    line = rules$line[owner], type = type, message = message,
    stringsAsFactors = FALSE
  )
}

wildcard_inheritance_message <- function(tokens, one_group, missing,
                                         cap = 10L) {
  several <- length(tokens) > 1L
  named <- if (several) {
    paste(toString(tokens[-length(tokens)]),
          "and", tokens[[length(tokens)]])
  } else {
    tokens
  }
  where <- if (one_group) {
    "this group"
  } else if (several) {
    "the groups that name them"
  } else {
    "the groups that name it"
  }
  k <- nrow(missing)
  shown <- seq_len(min(k, cap))
  items <- sprintf(
    "%s: %s (line %d)",
    ifelse(missing$type[shown] == "allow", "Allow", "Disallow"),
    vapply(missing$value[shown], function(value) {
      render_validation_line(charToRaw(value))
    }, "", USE.NAMES = FALSE),
    missing$line[shown]
  )
  listed <- toString(items)
  if (k > cap) {
    listed <- sprintf("%s, and %d more", listed, k - cap)
  }
  sprintf(
    paste0(
      "%s %s only %s, so %s `User-agent: *` %s not apply to %s: %s. ",
      "A crawler obeys only the groups that name it and ignores ",
      "`User-agent: *` once any group does; `User-agent: *` applies only to ",
      "crawlers no group names."
    ),
    named, if (several) "obey" else "obeys", where,
    if (k == 1L) "this" else "these", if (k == 1L) "rule does" else "rules do",
    if (several) "them" else "it", listed
  )
}

# The parser's value is canonical: non-ASCII bytes are already %XX escapes,
# so an invisible leading character shows as its escaped UTF-8 bytes.
validation_invisible_prefixes <- c(
  "U+200B" = "%E2%80%8B",
  "U+FEFF" = "%EF%BB%BF"
)

validation_bom <- as.raw(c(0xef, 0xbb, 0xbf))

# Where a BOM starts a line's content, after the ASCII blanks the parser
# strips (SP, HT, VT, FF), or 0 when none does. `skip_start` passes over the
# byte-0 BOM the parser itself skips.
misplaced_bom_offset <- function(line, skip_start) {
  first <- if (skip_start) 4L else 1L
  n <- length(line)
  while (first <= n &&
           line[[first]] %in% as.raw(c(0x20, 0x09, 0x0b, 0x0c))) {
    first <- first + 1L
  }
  # Indexing past the end of a raw vector gives 00, so a short tail never
  # equals the BOM.
  if (identical(line[first:(first + 2L)], validation_bom)) first else 0L
}

misplaced_bom_lines <- function(raw_lines, has_bom) {
  found <- vapply(seq_along(raw_lines), function(i) {
    misplaced_bom_offset(raw_lines[[i]], i == 1L && has_bom) > 0L
  }, logical(1L))
  which(found)
}

# The directive a misplaced BOM hides, learned by parsing the line again
# without it.
misplaced_bom_hidden <- function(line, skip_start) {
  at <- misplaced_bom_offset(line, skip_start)
  rest <- validation_raw_slice(line, at + 3L, length(line))
  # The binding reports at least one line, even for an empty `rest`.
  parsed <- robotstxtr_validation_parse_(rest)
  type <- parsed$type[[1L]]
  labels <- c(
    "user-agent" = "User-agent", allow = "Allow", disallow = "Disallow",
    sitemap = "Sitemap"
  )
  message <- paste0(
    "A UTF-8 byte-order mark starts this line; the Google-compatible parser ",
    "skips one only at the start of the file, so here it is part of the key."
  )
  if (!type %in% names(labels)) {
    if (isTRUE(parsed$is_comment[1L])) {
      message <- paste0(message, " This comment line is read as an active ",
                        "line.")
    }
    return(list(directive = NA_character_, message = message))
  }
  hidden <- sprintf(" This %s line is not read", labels[[type]])
  tail <- if (identical(type, "user-agent")) {
    paste0(": the parser starts no group here, so the lines after it stay ",
           "with the group before it, or with no group, until the next ",
           "User-agent line.")
  } else {
    "."
  }
  list(directive = type, message = paste0(message, hidden, tail))
}

rule_value_diagnostics <- function(value) {
  bytes <- charToRaw(value)
  found <- list()
  if (!bytes[[1L]] %in% charToRaw("/*")) {
    message <- paste0(
      "Pattern does not start with '/' or '*'; URL paths always start ",
      "with '/', so this rule never matches."
    )
    for (code_point in names(validation_invisible_prefixes)) {
      prefix <- charToRaw(validation_invisible_prefixes[[code_point]])
      if (length(bytes) >= length(prefix) &&
            identical(bytes[seq_along(prefix)], prefix)) {
        message <- paste0(
          message, " It starts with an invisible character (", code_point,
          ")."
        )
      }
    }
    found[[length(found) + 1L]] <- list(
      code = "rule_missing_leading_slash", message = message
    )
  }
  dollars <- which(bytes == charToRaw("$"))
  if (any(dollars < length(bytes))) {
    found[[length(found) + 1L]] <- list(
      code = "rule_inner_dollar",
      message = paste0(
        "'$' marks the end of the URL only as the last character; here it ",
        "matches a literal '$'."
      )
    )
  }
  escaped <- rule_escaped_unreserved_diagnostic(value)
  if (!is.null(escaped)) {
    found[[length(found) + 1L]] <- escaped
  }
  found
}

# RFC 3986 section 2.3 unreserved characters. RFC 9309 section 2.2.2 decodes
# their escapes before matching; Google's matcher compares the escape as
# written, so a rule's '%7E' never matches a URL's '~'.
validation_unreserved_bytes <- as.integer(charToRaw(paste(
  c(LETTERS, letters, 0:9, "-", ".", "_", "~"), collapse = ""
)))

# At most one finding per rule, naming each distinct escape (up to ten).
# Escapes are read left to right without overlap, so '%257E' is the escape
# '%25' and a literal '7E'. Returns a finding or NULL.
rule_escaped_unreserved_diagnostic <- function(value) {
  escapes <- regmatches(
    value, gregexpr("%[0-9A-Fa-f]{2}", value, useBytes = TRUE)
  )[[1L]]
  codes <- strtoi(substr(escapes, 2L, 3L), 16L)
  hit <- codes %in% validation_unreserved_bytes
  escapes <- unique(escapes[hit])
  if (length(escapes) == 0L) {
    return(NULL)
  }
  chars <- rawToChar(
    as.raw(strtoi(substr(escapes, 2L, 3L), 16L)), multiple = TRUE
  )
  if (length(escapes) == 1L) {
    message <- sprintf(
      paste0(
        "'%s' escapes the unreserved character '%s'. Google matches it only ",
        "against '%s' in the URL, never against '%s', though RFC 9309 ",
        "section 2.2.2 decodes it."
      ),
      escapes, chars, escapes, chars
    )
  } else {
    cap <- 10L
    k <- length(escapes)
    items <- sprintf("'%s' for '%s'", escapes, chars)[seq_len(min(k, cap))]
    listed <- toString(items)
    if (k > cap) {
      listed <- sprintf("%s, and %d more", listed, k - cap)
    }
    message <- paste0(
      "These escapes stand for unreserved characters: ", listed, ". Google ",
      "matches each only against the same escape in the URL, never against ",
      "the character, though RFC 9309 section 2.2.2 decodes them."
    )
  }
  list(code = "rule_escaped_unreserved", message = message)
}

# A syntax-only check of a Sitemap value: an absolute http, https or ftp URL
# with a host. Whether the sitemap exists is not checked (that is sitemapr's
# job). Returns at most one finding, or NULL.
sitemap_value_diagnostic <- function(value) {
  invalid <- list(
    code = "invalid_sitemap_url",
    message = "Sitemap value is not a valid absolute URL."
  )
  if (!grepl("^[A-Za-z][A-Za-z0-9+.-]*:", value, useBytes = TRUE)) {
    return(invalid)
  }
  bytes <- charToRaw(value)
  colon <- match(charToRaw(":"), bytes)
  token <- bytes[seq_len(colon - 1L)]
  # A host and port without a scheme ("x.com:8080/s.xml",
  # "localhost:8080/s.xml"): the token before ':' holds a '.' or a digit
  # follows the ':'. No scheme the check allows has either.
  port_follows <- length(bytes) > colon &&
    bytes[[colon + 1L]] %in% charToRaw("0123456789")
  if (charToRaw(".") %in% token || port_follows) {
    return(invalid)
  }
  scheme <- ascii_lower(rawToChar(token))
  if (!scheme %in% c("http", "https", "ftp")) {
    return(list(
      code = "unsupported_sitemap_scheme",
      message = sprintf(
        "Sitemap URL scheme '%s' is not http, https or ftp.", scheme
      )
    ))
  }
  # The scheme must be followed by "//" and an authority. This check does not
  # rely on rurl rejecting a scheme without "//" ("http:example.com"): a
  # more lenient rurl must not let one pass.
  if (length(bytes) < colon + 2L ||
        !identical(bytes[colon + 1:2], charToRaw("//"))) {
    return(invalid)
  }
  parsed <- tryCatch(
    rurl::safe_parse_url(value, host_encoding = "idna"),
    error = function(e) NULL
  )
  host <- parsed$host
  has_host <- is.character(host) && length(host) == 1L && !is.na(host) &&
    nzchar(host)
  if (!identical(parsed$scheme, scheme) || !has_host) {
    return(invalid)
  }
  NULL
}

validation_ascii_action <- function(action, type) {
  if (!identical(type, "unknown")) {
    return(type)
  }
  if (identical(Encoding(action), "bytes")) {
    return("unknown")
  }
  ascii_lower(action)
}

# The key of an Allow or Disallow line as the Google parser cut it
# (GetKeyAndValueFrom, src/robots.cc), rendered for a message, when it is
# not exactly `allow` or `disallow`; NULL when it is (ROBO-xglcoagv). The
# parser hands R only the type of a known key, so the key is derived again
# from the line's bytes: the BOM prefix Parse() skips on line 1, leading
# ASCII whitespace, the separator (the first `:`, or the first SP or HT when
# the parser reported a missing colon) and trailing whitespace. The parser
# also ends the line at a NUL and at `#`, but it found its separator before
# both, and that cut line is a prefix of these bytes, so the first separator
# here is the same one and neither cut can change the key.
validation_prefix_key <- function(bytes, line, type, missing_colon) {
  if (identical(line, 1L)) {
    bom <- as.raw(c(0xef, 0xbb, 0xbf))
    skip <- 0L
    while (skip < min(3L, length(bytes)) &&
             bytes[[skip + 1L]] == bom[[skip + 1L]]) {
      skip <- skip + 1L
    }
    bytes <- bytes[seq_len(length(bytes) - skip) + skip]
  }
  space <- as.raw(c(0x20, 0x09, 0x0a, 0x0b, 0x0c, 0x0d))
  # The parser found a non-empty key on this line, so `lead` is never empty.
  lead <- which(!bytes %in% space)
  bytes <- bytes[lead[[1L]]:length(bytes)]
  separator <- as.raw(if (missing_colon) c(0x20, 0x09) else 0x3a)
  stop_at <- which(bytes %in% separator)
  key <- if (length(stop_at) == 0L) {
    bytes
  } else {
    bytes[seq_len(stop_at[[1L]] - 1L)]
  }
  kept <- which(!key %in% space)
  key <- key[seq_len(if (length(kept) == 0L) 0L else max(kept))]
  folded <- as.integer(key)
  upper <- folded >= 0x41 & folded <= 0x5a
  folded[upper] <- folded[upper] + 32L
  if (identical(folded, as.integer(charToRaw(type)))) {
    return(NULL)
  }
  render_validation_line(key)
}

validation_prefix_key_message <- function(key, type) {
  name <- if (identical(type, "disallow")) "Disallow" else "Allow"
  message <- paste0(
    "Google reads key `", key, "` as ", name, " (prefix match), so for ",
    "Google this line is ", if (identical(type, "allow")) "an " else "a ",
    name, " rule; Bing and Yandex ignore it, and RFC 9309 defines no such ",
    "record."
  )
  if (identical(type, "disallow")) {
    message <- paste0(
      message, " For an AI-training opt-out, use a separate ",
      "`User-agent: __usage_ai-training` group, not stacked under another ",
      "User-agent line."
    )
  }
  message
}

split_validation_lines <- function(bytes) {
  n <- length(bytes)
  if (n == 0L) {
    return(list())
  }
  lines <- list()
  start <- 1L
  i <- 1L
  while (i <= n) {
    byte <- as.integer(bytes[[i]])
    if (byte %in% c(0x0a, 0x0d)) {
      lines[[length(lines) + 1L]] <- validation_raw_slice(bytes, start, i - 1L)
      if (byte == 0x0d && i < n && as.integer(bytes[[i + 1L]]) == 0x0a) {
        i <- i + 1L
      }
      start <- i + 1L
    }
    i <- i + 1L
  }
  if (start <= n) {
    lines[[length(lines) + 1L]] <- bytes[start:n]
  }
  lines
}

validation_raw_slice <- function(bytes, first, last) {
  if (first > last) raw() else bytes[first:last]
}

# TRUE when the first `#` of a raw line follows a byte other than a space or
# tab: a comment glued to the rule value, not one set apart from it.
# Works on bytes, so invalid UTF-8 or Latin-1 in the value is no error.
rule_cut_by_comment <- function(raw_line) {
  hash <- match(as.raw(0x23), raw_line)
  !is.na(hash) && hash > 1L &&
    !(raw_line[[hash - 1L]] %in% as.raw(c(0x20, 0x09)))
}

render_validation_line <- function(bytes) {
  if (length(bytes) == 0L) {
    return("")
  }
  paste(vapply(as.integer(bytes), function(byte) {
    if (byte >= 0x20 && byte <= 0x7e) {
      rawToChar(as.raw(byte))
    } else if (byte == 0x09) {
      "\\t"
    } else {
      sprintf("\\x%02X", byte)
    }
  }, character(1L)), collapse = "")
}

validate_fetched_documents <- function(fetched) {
  documents <- list()
  diagnostics <- list()
  robots <- fetched$robots
  for (i in seq_len(nrow(robots))) {
    source <- robots[i, , drop = FALSE]
    body <- robots$body[[i]]
    if (!is.null(body)) {
      validated <- validate_document_bytes(
        bytes = body,
        source_id = source$source_id,
        source_type = source$source_type,
        robots_url = source$robots_url,
        effective_url = source$effective_url,
        http_status = source$http_status,
        fetch_outcome = source$fetch_outcome,
        max_bytes = source$max_bytes,
        body_truncated = isTRUE(robots$body_truncated[[i]])
      )
    } else {
      validated <- unavailable_validation(source)
    }
    documents[[i]] <- validated$document
    if (nrow(validated$diagnostics) > 0L) {
      diagnostics[[length(diagnostics) + 1L]] <- validated$diagnostics
    }
  }

  map <- fetched$map
  map$validation_status <- rep("not_validated", nrow(map))
  if (length(documents) > 0L) {
    document_frame <- do.call(rbind, documents)
    status <- document_frame$validation_status[match(
      map$source_id, document_frame$source_id
    )]
    map$validation_status[!is.na(status)] <- status[!is.na(status)]
  } else {
    document_frame <- empty_validation_documents()
  }

  invalid <- which(is.na(map$source_id))
  for (i in invalid) {
    diagnostics[[length(diagnostics) + 1L]] <- validation_diagnostic(
      source_id = NA_character_,
      input_id = map$input_id[[i]],
      line = NA_integer_,
      severity = "error",
      code = "acquisition_input_invalid",
      directive = NA_character_,
      raw_text = map$url[[i]],
      message = map$error_message[[i]]
    )
  }
  diagnostic_frame <- if (length(diagnostics) == 0L) {
    empty_validation_diagnostics()
  } else {
    do.call(rbind, diagnostics)
  }
  new_robots_validations(map, document_frame, diagnostic_frame)
}

unavailable_validation <- function(source) {
  outcome <- source$fetch_outcome
  status <- source$http_status
  if (outcome %in% c("missing", "http_error") && !is.na(status)) {
    diagnosis <- status_diagnosis(status, source$retry_after_seconds)
    severity <- diagnosis$severity
    code <- diagnosis$code
    message <- diagnosis$message
  } else if (identical(outcome, "missing")) {
    severity <- "info"
    code <- "acquisition_missing"
    message <- "No robots.txt body was acquired because the resource is absent."
  } else if (identical(outcome, "body_too_large")) {
    severity <- "error"
    code <- "acquisition_limit_exceeded"
    message <- sprintf(
      "Decoded body exceeded max_bytes (%d); no truncated body was validated.",
      source$max_bytes
    )
  } else if (identical(outcome, "partial_response")) {
    severity <- "error"
    code <- "acquisition_partial_response"
    message <- "Partial HTTP response was rejected; no body was validated."
  } else {
    severity <- "error"
    diagnosis <- acquisition_diagnosis(source)
    if (!is.null(diagnosis)) {
      code <- diagnosis$code
      message <- diagnosis$message
    } else {
      code <- "acquisition_failed"
      message <- if (is.na(source$error_message)) {
        sprintf("Acquisition outcome '%s' supplied no document body.", outcome)
      } else {
        source$error_message
      }
    }
  }
  diagnostic <- validation_diagnostic(
    source$source_id, NA_integer_, severity, code, NA_character_,
    NA_character_, message
  )
  document <- empty_validation_documents()[NA_integer_, , drop = FALSE]
  document <- document[1L, , drop = FALSE]
  document$source_id <- source$source_id
  document$source_type <- source$source_type
  document$robots_url <- source$robots_url
  document$effective_url <- source$effective_url
  document$http_status <- source$http_status
  document$fetch_outcome <- outcome
  document$validation_status <- "not_validated"
  document$profile <- robots_validation_profile
  document$byte_size <- source$body_size
  document$max_bytes <- source$max_bytes
  document$body_truncated <- FALSE
  document$limit_exceeded <- identical(outcome, "body_too_large")
  document$diagnostic_count <- 1L
  document$warning_count <- as.integer(severity == "warning")
  document$error_count <- as.integer(severity == "error")
  list(document = document, diagnostics = diagnostic)
}

# The code, severity and message for a robots.txt answered by an HTTP status
# with no body (ROBO-ybzbxfml). The status is mapped to its policy-table
# category, and each engine's reading comes from engine_policy_table_v1().
status_diagnosis <- function(status, retry_after_seconds) {
  category <- http_status_category_v1(status)
  if (status %in% c(404L, 410L)) {
    severity <- "info"
    code <- "acquisition_missing"
  } else if (identical(category, "status_4xx")) {
    severity <- "warning"
    code <- "acquisition_http_4xx"
  } else if (identical(category, "status_429")) {
    severity <- "error"
    code <- "acquisition_http_429"
  } else if (identical(category, "status_5xx")) {
    severity <- "error"
    code <- "acquisition_http_5xx"
  } else {
    severity <- "error"
    code <- "acquisition_http_protocol"
  }
  message <- paste0(
    "HTTP ", status, ": ", status_engine_readings(category), "."
  )
  if (status %in% c(401L, 403L)) {
    message <- paste(
      message,
      "A 401 or 403 is often a firewall or bot filter answering this client,",
      "not the site's own robots.txt."
    )
  }
  if (length(retry_after_seconds) == 1L && is.finite(retry_after_seconds)) {
    seconds <- sprintf("%.0f", round(retry_after_seconds))
    unit <- if (identical(seconds, "1")) "second" else "seconds"
    message <- paste0(message, " Retry-After: ", seconds, " ", unit, ".")
  }
  message <- paste(message, "See robots_engine_contract_v1().")
  list(severity = severity, code = code, message = message)
}

# The code and message for a redirect, transport or safety outcome that left
# no body (ROBO-bsloeclp), or NULL for any other outcome. It reads the robots
# frame's `terminal_redirect_reason` and `safety_block_reason`, never the
# wording of `error_message`, which only opens the message.
#
# - over_budget, no_location, loop and a transport failure have a policy-table
#   category (the one resolve_policy_v1() reads for their evidence status), so
#   each engine's reading comes from engine_policy_table_v1(), as for a status
#   class: `redirect_over_budget`, `protocol_error` (no engine documents a
#   malformed redirect; design/engine-profiles.md#redirect-handling) and
#   `transport` (design/engine-profiles.md#status-policy, network row).
# - A downgrade, a non-HTTP(S) target and any other guard refusal are
#   decided by the safety level, never by a ruleset
#   (design/engine-profiles.md#redirect-handling and section 3a), so their
#   message says so instead of giving an engine verdict.
acquisition_diagnosis <- function(source) {
  terminal <- source$terminal_redirect_reason
  safety <- source$safety_block_reason
  outcome <- source$fetch_outcome
  opening <- sub("\\.$", "", source$error_message)
  readings <- function(category) {
    paste0(status_engine_readings(category), ".")
  }
  if (identical(terminal, "over_budget")) {
    code <- "acquisition_redirect_over_budget"
    detail <- readings("redirect_over_budget")
  } else if (identical(terminal, "no_location")) {
    code <- "acquisition_redirect_no_location"
    detail <- readings("protocol_error")
  } else if (identical(terminal, "loop")) {
    code <- "acquisition_redirect_loop"
    detail <- readings("protocol_error")
  } else if (identical(terminal, "downgrade")) {
    # No engine documents refusing an https-to-http robots.txt redirect;
    # Google, Yandex and RFC 9309 place no scheme condition on one
    # [inferred], Bing states nothing [documentation_gap]
    # (design/engine-fetch-rules-sources.md, Summary, `https` -> `http`).
    code <- "acquisition_redirect_downgrade"
    detail <- paste(
      "robotstxtr's safety refusal under safety_level \"strict\",",
      "not an engine reading; Google: no source says it refuses one",
      "(inferred to follow it); Yandex: no source says it refuses one",
      "(inferred to follow it); Bing: not documented."
    )
  } else if (identical(terminal, "non_http_target")) {
    code <- "acquisition_redirect_non_http"
    detail <- paste(
      "robotstxtr's safety refusal (safety_block_reason \"scheme\"),",
      "not an engine reading; Google: not documented; Yandex: not",
      "documented; Bing: not documented."
    )
  } else if (identical(outcome, "ssrf_blocked") && !is.na(safety)) {
    code <- "acquisition_safety_refused"
    detail <- sprintf(paste(
      "robotstxtr's safety refusal (safety_block_reason \"%s\"); nothing",
      "was requested there, so no engine reading applies."
    ), safety)
  } else if (outcome %in% c("timeout", "tls_error", "network_error")) {
    code <- "acquisition_transport_failed"
    detail <- readings("transport")
  } else {
    return(NULL)
  }
  if (is.na(opening) || !nzchar(opening)) {
    opening <- sprintf("Acquisition outcome '%s'", outcome)
  }
  list(
    code = code,
    message = paste0(
      opening, ": ", detail, " See robots_engine_contract_v1()."
    )
  )
}

# "Google: ...; Yandex: ...; Bing: ..." for one policy-table category.
status_engine_readings <- function(category) {
  table <- engine_policy_table_v1()
  engines <- c(google = "Google", yandex = "Yandex", bing = "Bing")
  readings <- vapply(names(engines), function(ruleset) {
    row <- table[table$category == category & table$ruleset == ruleset, ,
                 drop = FALSE]
    paste0(
      engines[[ruleset]], ": ",
      status_policy_phrase(
        ruleset, category, row$policy_status[[1L]], row$policy_action[[1L]]
      )
    )
  }, character(1L))
  paste(readings, collapse = "; ")
}

status_policy_phrase <- function(ruleset, category, status, action) {
  if (identical(status, "evaluated") && identical(action, "allow_all")) {
    if (identical(ruleset, "google") &&
          identical(category, "redirect_over_budget")) {
      # Google's robots.txt spec, 3xx: it "stops and treats it as a 404"
      # (design/engine-fetch-rules-sources.md, Google, "After the last hop").
      "may stop and treat it as a 404, which places no restrictions on crawling"
    } else if (identical(ruleset, "yandex")) {
      "places no restrictions on crawling"
    } else {
      "may treat it as no robots.txt, which places no restrictions on crawling"
    }
  } else if (identical(status, "context_required")) {
    "context-dependent (may pause crawling or use its last cached copy)"
  } else if (identical(status, "documentation_gap")) {
    if (identical(ruleset, "google") && identical(category, "status_429")) {
      "not documented for robots.txt (Google excludes 429 from its 4xx rule)"
    } else {
      "not documented"
    }
  } else {
    stop(sprintf(
      "No status phrase for policy (%s, %s).", status, action
    ), call. = FALSE)
  }
}

empty_validation_documents <- function() {
  data.frame(
    source_id = character(),
    source_type = character(),
    robots_url = character(),
    effective_url = character(),
    http_status = integer(),
    fetch_outcome = character(),
    validation_status = character(),
    profile = character(),
    byte_size = integer(),
    line_count = integer(),
    active_line_count = integer(),
    recognized_directives = integer(),
    unknown_directives = integer(),
    malformed_lines = integer(),
    user_agent_directives = integer(),
    allow_directives = integer(),
    disallow_directives = integer(),
    sitemap_directives = integer(),
    unsupported_directives = integer(),
    encoding = character(),
    has_bom = logical(),
    nul_byte_count = integer(),
    final_newline = logical(),
    max_bytes = integer(),
    body_truncated = logical(),
    limit_exceeded = logical(),
    diagnostic_count = integer(),
    warning_count = integer(),
    error_count = integer(),
    stringsAsFactors = FALSE
  )
}
