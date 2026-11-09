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
#' bytes. Character input marked with `Encoding = "bytes"` is used verbatim;
#' other character input is converted to UTF-8 once.
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
#'   \code{nul_byte} \tab error \tab
#'     A line holds NUL bytes, which can truncate parsing. \cr
#'   \code{invalid_utf8} \tab error \tab
#'     The document bytes are not well-formed UTF-8. \cr
#'   \code{malformed_line} \tab error \tab
#'     An active line is not a key-value directive. \cr
#'   \code{line_too_long} \tab error \tab
#'     A line exceeds the parser's 16,663-byte buffer and is truncated. \cr
#'   \code{accepted_missing_colon} \tab warning \tab
#'     A directive without a colon, which the parser accepts. \cr
#'   \code{accepted_directive_typo} \tab warning \tab
#'     A directive name in an accepted typo spelling. \cr
#'   \code{unsupported_directive} \tab warning \tab
#'     A known directive this profile ignores, such as \code{crawl-delay}. \cr
#'   \code{unknown_directive} \tab warning \tab
#'     A directive this profile does not recognize. \cr
#'   \code{empty_user_agent} \tab error \tab
#'     A User-agent line with an empty value. \cr
#'   \code{rule_without_user_agent} \tab error \tab
#'     An Allow or Disallow in no group a non-empty User-agent opened: before
#'     any, or after an empty User-agent that follows a rule. \cr
#'   \code{empty_rule_value} \tab warning \tab
#'     An empty Allow or Disallow value, which the matcher ignores. \cr
#'   \code{rule_missing_leading_slash} \tab warning \tab
#'     A pattern not led by \code{/} or \code{*}; it never matches. \cr
#'   \code{rule_inner_dollar} \tab warning \tab
#'     A \code{$} before a pattern's end; it matches a literal \code{$}. \cr
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
#'   \code{missing_user_agent} \tab error \tab
#'     Allow or Disallow rules exist but no line names a non-empty
#'     User-agent. \cr
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
#'     The robots.txt resource is absent; nothing was validated. \cr
#'   \code{acquisition_limit_exceeded} \tab error \tab
#'     A 3xx body exceeded \code{max_bytes} and was refused whole. \cr
#'   \code{acquisition_partial_response} \tab error \tab
#'     A partial HTTP response was rejected. \cr
#'   \code{acquisition_failed} \tab error \tab
#'     Acquisition supplied no body, for the reason in \code{message}.
#' }
#'
#' For `wildcard_rules_not_inherited`, a crawler obeys only the groups that
#' name it (combined when several do) and ignores the `User-agent: *` group,
#' as RFC 9309 section 2.2.1 says. Each `*` Allow or Disallow is compared
#' with the named crawler's rules by type and value; a trailing `*` is
#' ignored (`/x` equals `/x*`, and `*` and `/*` equal `/`), `$` is not, and
#' empty values are left out. The message lists the missing `*` rules, ten at
#' most. A crawler whose rules are all explicit allow-all (an empty
#' `Disallow:`, `Allow: /`, `Allow: /*` or `Allow: *`) is not reported; an
#' empty `Allow:` is ignored, and a crawler whose groups have no other rule
#' is reported.
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
  if (identical(Encoding(robots_txt), "bytes")) {
    charToRaw(robots_txt)
  } else {
    charToRaw(enc2utf8(robots_txt))
  }
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

  has_bom <- length(bytes) >= 3L && identical(
    bytes[1:3], as.raw(c(0xef, 0xbb, 0xbf))
  )
  if (has_bom) {
    add_diagnostic(
      1L, "warning", "byte_order_mark", NA_character_,
      paste0("A UTF-8 byte-order mark is present; the Google-compatible ",
             "parser skips it.")
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

  bytes_without_nul <- nul_free_bytes(bytes)
  encoding_valid <- validUTF8(rawToChar(bytes_without_nul))
  encoding <- if (encoding_valid) "utf-8" else "invalid-utf-8"
  if (!encoding_valid) {
    add_diagnostic(
      NA_integer_, "error", "invalid_utf8", NA_character_,
      "Document bytes are not well-formed UTF-8."
    )
  }

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

    if (identical(type, "unknown")) {
      unsupported[[i]] <- !is.na(action) &&
        action %in% validation_unsupported
      if (unsupported[[i]]) {
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

  # A named group drops the `*` rules for its crawlers (ROBO-gfjotdrr). On a
  # cut body a group's rules may lie past the cut, so the check is skipped.
  if (!body_truncated) {
    inheritance <- wildcard_inheritance_diagnostics(validation_groups(parsed))
    for (found in inheritance) {
      add_diagnostic(
        found$line, "info", "wildcard_rules_not_inherited", "user-agent",
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
# unknown lines never close one. Reused by ROBO-fdhmlvwm. Returns a list of
# three data frames:
# - `groups`: one row per group, in file order: `group` (integer id),
#   `first_line` (the group's first User-agent line) and `global` (any of
#   its User-agent lines is `*`, alone or followed by whitespace).
# - `agents`: one row per User-agent line: `group`, `line`, `global`,
#   `token` (the ExtractUserAgent run of [A-Za-z_-] as spelled, ASCII; ""
#   for a global line or one led by any other byte) and `key`
#   (`ascii_lower(token)`, the merge key).
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
# agent with no other rule is not exempt. Rows come in anchor-line order:
# agents are visited in the order they are first named.
wildcard_inheritance_diagnostics <- function(groups) {
  rules <- groups$rules
  # An empty key (a global line, or one led by a byte outside [A-Za-z_-])
  # names no crawler.
  agents <- groups$agents[nzchar(groups$agents$key), , drop = FALSE]
  global <- rules[!rules$empty &
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
  found
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
  if (identical(outcome, "missing")) {
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
    code <- "acquisition_failed"
    message <- if (is.na(source$error_message)) {
      sprintf("Acquisition outcome '%s' supplied no document body.", outcome)
    } else {
      source$error_message
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
