# Match-metadata correlation (slice R3).
#
# The matcher reports a positive one-based `matching_line()` for a matched row.
# To turn that line number into the callback-derived rule type and the canonical
# (post-MaybeEscapePattern) rule value, ParseRobotsTxt() is run once per
# distinct source body with a private, read-only collector (the C++ binding
# `robotstxtr_collect_directives_`), and the line number is joined to the
# resulting per-source lookup.

# Build a per-line directive lookup for one robots.txt body by running the
# vendored parser once. Returns a data frame with columns `line` (integer),
# `type` (character), and `value` (character; elements may carry
# `Encoding = "bytes"` when a callback value is not valid UTF-8). The
# `body_utf8` argument is the same UTF-8 (or byte-verbatim) string handed to the
# matcher.
collect_directive_lookup <- function(body_utf8) {
  collected <- robotstxtr_collect_directives_(body_utf8)
  data.frame(
    line = collected$line,
    type = collected$type,
    value = collected$value,
    stringsAsFactors = FALSE
  )
}

# Correlate matched rows against per-source directive lookups.
#
# For each row with a positive `matching_line` (non-NA), look up its source's
# per-line directive table and overwrite `matched_rule_type` with the callback-
# derived type and `matched_rule_value` with the canonical callback value. Rows
# with no positive matching line are left untouched (their decision-derived type
# and NA value stand).
#
# `lookups` is a named list keyed by `source_id`; each element is the data frame
# returned by `collect_directive_lookup()`. A positive matching line absent from
# its source lookup is an internal invariant failure and raises a package error
# (never NA), per PRD 6.6.
#
# Returns a list with the updated `matched_rule_type` and `matched_rule_value`
# vectors.
correlate_match_metadata <- function(matching_line, source_id,
                                     matched_rule_type, matched_rule_value,
                                     lookups) {
  matched_rows <- which(!is.na(matching_line) & matching_line > 0L)
  for (i in matched_rows) {
    lookup <- lookups[[source_id[[i]]]]
    line <- matching_line[[i]]
    j <- match(line, lookup$line)
    if (is.na(j)) {
      robots_abort(
        sprintf(
          paste0(
            "matched line %d for source \"%s\" has no collected directive; ",
            "the matcher and parse collector disagree."
          ),
          line, source_id[[i]]
        ),
        "robotstxtr_missing_collected_line"
      )
    }
    matched_rule_type[[i]] <- lookup$type[[j]]
    matched_rule_value[[i]] <- lookup$value[[j]]
  }
  list(
    matched_rule_type = matched_rule_type,
    matched_rule_value = matched_rule_value
  )
}
