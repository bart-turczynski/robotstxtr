# Validation profile implemented by the exported validation APIs. Keep this a
# stable machine-readable token; prose documentation explains its boundaries.
robots_validation_profile <- "google-parser-compatible"

validation_unsupported <- c(
  "clean-param", "content-signal", "content-usage", "crawl-delay", "domain",
  "host", "license", "noarchive", "nofollow", "noindex", "request-rate",
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
#' In `documents`, `encoding` says only whether the bytes are valid UTF-8
#' (`"utf-8"` or `"invalid-utf-8"`); a NUL byte counts as valid, so UTF-16
#' ASCII text can read `"utf-8"`. `encoding_signature` names the encoding the
#' bytes point to: `"utf-8-bom"`, `"utf-16le"`, `"utf-16be"`, `"utf-32le"`,
#' `"utf-32be"`, or `NA`. `encoding_signature_basis` says how: `"bom"` for a
#' byte-order mark, `"byte_pattern"` for the heuristic that reads the zero
#' bytes of ASCII text in UTF-16 or UTF-32. The signature describes a raw or
#' fetched body; character input, even marked `"bytes"`, is text the caller
#' already decoded, so both are `NA` for it. `has_bom` can still flag a
#' leading byte-order mark character in character input while
#' `encoding_signature` stays `NA`.
#'
#' @section Diagnostic codes:
#' Every `code` the validator emits, by the order a document is read. The
#' checks describe the Google-compatible parser; the package's Bing and Yandex
#' matchers agree on both pattern effects (a pattern not led by `/` or `*`
#' never matches, and `$` anchors only as the last character). The sitemap
#' checks are syntax-only: no sitemap is fetched, which is the `sitemapr`
#' package's job. `body_truncated` and the codes starting `acquisition_` or
#' `redirect_` come only from [robots_validate_url()]; a `redirect_` row
#' follows the body's own rows.
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
#'     first \code{#}. A NUL byte counts as a character of its own, so a
#'     NUL inside a multi-byte sequence breaks it. When every bad byte lies
#'     after the line's first NUL, the message says Google's matcher never
#'     reads them while Bing and Yandex do. \cr
#'   \code{invalid_utf8_comment} \tab warning \tab
#'     A line's bytes that are not well-formed UTF-8 all sit in its comment,
#'     after the first \code{#}; no rule changes. A \code{#} after a NUL
#'     counts: Bing and Yandex read past the NUL, and Google's matcher reads
#'     nothing after it, which the message then says. \cr
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
#'   \code{rsl_license_directive} \tab info or warning \tab
#'     A \code{License} line, the directive of Really Simple Licensing (RSL
#'     1.0 section 4.4) that points to licensing terms; it counts as an
#'     unsupported directive. The message says the line changes no crawl
#'     access, that no crawler operator is documented as reading it, and its
#'     scope: before the first User-agent line it is global, otherwise it
#'     applies only to the crawlers that select the group it sits in (blank
#'     lines end no group), a group's own License lines replace the global
#'     ones, and a group of only empty User-agent lines reaches no crawler.
#'     A warning only when the value is not an absolute URI
#'     (RFC 3986 section 4.3); the value is read up to the line's first
#'     \code{#}, so it holds no fragment. \code{X-RSL} and other keys stay
#'     \code{unknown_directive}. \cr
#'   \code{unknown_directive} \tab warning \tab
#'     A directive this profile does not recognize. A key that is valid
#'     UTF-8 and holds a look-alike character, as \code{user_agent_cut}
#'     lists them, names it and gives the ASCII spelling
#'     (\code{Disallow} for a key written with a Cyrillic a). \cr
#'   \code{empty_user_agent} \tab error \tab
#'     A User-agent line with an empty value. \cr
#'   \code{user_agent_cut} \tab warning or info \tab
#'     A User-agent value Google's matcher reads only up to its first
#'     character outside letters, \code{_} and \code{-}, such as
#'     \code{Foo Bot} or \code{Googlebot/2.1}; the message names the token
#'     read, or says it names no crawler (\code{*bot}), and states the
#'     effect: there the written value does not match its own record, so a
#'     crawler going by it gets another group naming it, else
#'     \code{User-agent: *}, else no rules. A warning only when the token
#'     read is a documented Google crawler token the value did not mean
#'     (\code{Googlebot Image}, read as \code{Googlebot}); a version suffix
#'     (\code{Googlebot/2.1}) or a trailing \code{*} is info, as the token
#'     read is the crawler the value names, and any other token is info, as
#'     Google's crawlers do not go by it; a value holding a look-alike
#'     character (below) is a warning whatever the token, as no byte
#'     compare matches it. The Bing and Yandex
#'     matchers do not cut the value. A value that is valid UTF-8 and holds
#'     a look-alike character, from a closed list of common ones (Unicode
#'     hyphens and dashes such as U+2011, U+2212 and U+FF0D, U+FF3F
#'     FULLWIDTH LOW LINE, and some Cyrillic and Greek letters that look
#'     like one ASCII letter, such as U+0430 and U+03BF)
#'     adds a sentence naming each by code point and name with its byte
#'     offset, at most ten, and giving the ASCII spelling, which no byte
#'     compare matches; U+00AD SOFT HYPHEN is named as invisible and dropped
#'     from the spelling. The sentence names the package's Bing or Yandex
#'     matcher only when the spelling is a crawler that backend evaluates
#'     (\code{bingbot} written with a Cyrillic o). Latin letters with
#'     diacritics are not look-alikes. Every other code names the agent as
#'     written, and a code that names a cut value adds a sentence pointing
#'     to this row; \code{duplicate_rule} names the token read. \cr
#'   \code{rule_without_user_agent} \tab error \tab
#'     An Allow or Disallow in no group a non-empty User-agent opened: before
#'     any, or after an empty User-agent that follows a rule. \cr
#'   \code{allow_all_disallow} \tab info \tab
#'     An empty Disallow value, the allow-all idiom: the line adds no
#'     restriction. In a group that names a crawler and not \code{*}, the
#'     message adds that those crawlers follow this group, merged with any
#'     other group naming them, and not the \code{User-agent: *} group
#'     when the file has one. \cr
#'   \code{empty_rule_value} \tab warning \tab
#'     An empty Allow value, which the matcher ignores, or an empty Disallow
#'     value outside any group or on a line holding a NUL byte. When a NUL
#'     byte right after the colon hides the path, the message says that the
#'     first NUL ends the line, so the directive imposes no restriction and
#'     the text after the NUL is ignored. \cr
#'   \code{rule_missing_leading_slash} \tab warning \tab
#'     A pattern not led by \code{/} or \code{*}; it never matches. \cr
#'   \code{rule_cut_by_comment} \tab warning \tab
#'     A \code{#} with no space or tab before it starts a comment inside an
#'     Allow or Disallow value, cutting the rule at the \code{#}. A vertical
#'     tab or form feed before the \code{#} still counts as no space. \cr
#'   \code{rule_cut_by_nul} \tab warning \tab
#'     A NUL byte inside an Allow or Disallow value: Google's matcher ends
#'     the line at its first NUL, so the rule is cut there, while Bing and
#'     Yandex read the NUL as a byte of the rule, even one at the value's
#'     end. A NUL in a comment, which every engine ignores, right after the
#'     colon (\code{empty_rule_value}) or past the line buffer is not
#'     reported. \cr
#'   \code{rule_inner_dollar} \tab warning \tab
#'     A \code{$} before a pattern's end; it matches a literal \code{$}. \cr
#'   \code{rule_inner_whitespace} \tab warning \tab
#'     A pattern holds a space, tab, vertical tab or form feed; crawlers
#'     request URLs with it percent-encoded, so the rule never matches. \cr
#'   \code{rule_control_character} \tab warning \tab
#'     A pattern holds an ASCII control byte, 0x01 to 0x08 or 0x0E to 0x1F.
#'     RFC 9309 section 2.2 excludes it from a path pattern and RFC 3986 bars
#'     it from a URL, so crawlers request it percent-encoded, and Google's
#'     matcher, which compares the pattern as written, matches no URL they
#'     send. NUL, tab, VT and FF have their own codes; DEL (0x7F) is allowed
#'     and gets none. One per rule line; a byte the parser never reads, such
#'     as one after a NUL or in a comment, is not reported. \cr
#'   \code{rule_escaped_unreserved} \tab warning \tab
#'     A pattern percent-escapes an unreserved character, such as \code{\%7E}
#'     for \code{~}. Google matches only the escape, never the character,
#'     though RFC 9309 section 2.2.2 decodes it. One per rule line. \cr
#'   \code{rule_lowercase_escape} \tab warning \tab
#'     A pattern holds a lower-case percent-escape, such as \code{\%3c}.
#'     Google upper-cases the escape in a pattern but not in the URL, so a URL
#'     written with it never matches the rule; Bing upper-cases it too, and
#'     the package's Yandex matcher compares the pattern as written. One per
#'     rule line. A line whose group already has the rule in upper case gets
#'     \code{rule_lowercase_escape_twin} instead. \cr
#'   \code{rule_lowercase_escape_twin} \tab info \tab
#'     A pattern with a lower-case percent-escape whose own group has the
#'     same rule with the escape in upper case, as Shopify's default writes
#'     \code{\%2b} beside \code{\%2B}. Google and Bing upper-case the escape,
#'     so the line repeats that rule and a URL written with the lower-case
#'     escape matches neither; the package's Yandex matcher compares the
#'     pattern as written. The message names the twin's line, and the line
#'     gets no \code{duplicate_rule} row. Not reported for a line holding a
#'     NUL byte. \cr
#'   \code{rule_replacement_character} \tab info \tab
#'     A pattern holds U+FFFD, the
#'     replacement character a decoder writes for bytes it could not read.
#'     One per rule line. \cr
#'   \code{rule_invisible_character} \tab info \tab
#'     A pattern holds an
#'     invisible or formatting character, such as U+200B or U+2066. One per
#'     rule line, naming up to ten. \cr
#'   \code{rule_possible_mojibake} \tab info \tab
#'     A pattern holds two or
#'     more sequences that read like UTF-8 decoded as Latin-1 and encoded
#'     again. One per rule line, naming up to ten. \cr
#'   \code{empty_sitemap_value} \tab warning \tab
#'     A Sitemap line with an empty value. \cr
#'   \code{invalid_sitemap_url} \tab warning \tab
#'     A Sitemap value that is not a valid absolute URL. \cr
#'   \code{unsupported_sitemap_scheme} \tab warning \tab
#'     A Sitemap scheme other than \code{http}, \code{https} or \code{ftp}. \cr
#'   \code{wildcard_disallows_not_inherited} \tab warning or info \tab
#'     A named User-agent group lacks \code{User-agent: *} Disallows that
#'     block a path its own rules allow, so its crawlers may crawl it: the
#'     group replaces \code{User-agent: *} for them instead of adding to it.
#'     Says so when the group holds no Disallow. Info, not a warning, for an
#'     explicit grant: \code{Allow: /} or an empty \code{Disallow:} and no
#'     other Disallow. Not for a full block, nor for
#'     \code{AdsBot-Google}, \code{AdsBot-Google-Mobile},
#'     \code{Mediapartners-Google} and \code{APIs-Google}, which ignore
#'     \code{User-agent: *} anyway. Anchored on the group's first User-agent
#'     line. Not reported for a body cut at \code{max_bytes}. \cr
#'   \code{allow_reopens_wildcard_disallow} \tab warning or info \tab
#'     An Allow in a named User-agent group reopens a path that
#'     \code{User-agent: *} disallows and the group's own Disallows block
#'     (\code{Disallow: /} with \code{Allow: /company}, where
#'     \code{User-agent: *} disallows \code{/company/search/}). Names each
#'     path with the Allow and the \code{User-agent: *} Disallow, ten at
#'     most. Info, not a warning, when only an every-path Allow such as
#'     \code{Allow: /} reopens them (an explicit grant). Not for
#'     \code{AdsBot-Google}, \code{AdsBot-Google-Mobile},
#'     \code{Mediapartners-Google} and \code{APIs-Google}. Anchored on the
#'     group's first User-agent line. Not reported for a body cut at
#'     \code{max_bytes}. \cr
#'   \code{wildcard_rules_not_inherited} \tab info \tab
#'     A named User-agent group lacks some \code{User-agent: *} rules, which
#'     its crawlers therefore do not obey; rules
#'     \code{wildcard_disallows_not_inherited} and
#'     \code{allow_reopens_wildcard_disallow} report are left out. Where
#'     the merged named groups disallow \code{/} and hold no non-empty
#'     \code{Allow}, only the lost \code{User-agent: *} Allow rules are
#'     listed. Groups with the same remaining rules share one row, anchored
#'     on the earliest group's first User-agent line. Not reported for a body
#'     cut at \code{max_bytes}. \cr
#'   \code{ai_training_preference} \tab info \tab
#'     A User-agent line names the AI-training policy token
#'     \code{__usage_ai-training}; the message lists its group's own rules.
#'     One per group, on its first such line. \cr
#'   \code{ai_training_token_near_miss} \tab warning \tab
#'     A User-agent value close to the policy token that does not match it
#'     exactly, such as \code{__usage_ai_training} or
#'     \code{__usage_ai-training/1.0}. \cr
#'   \code{ai_training_group_extra_line} \tab warning \tab
#'     A directive such as \code{Crawl-delay} in a group that names only the
#'     policy token, before its last rule or anywhere in the file's last
#'     group; file-level Sitemap, Host and \code{Clean-param} lines are left
#'     out.
#'     \cr
#'   \code{ai_training_token_stacked} \tab warning \tab
#'     A policy-token User-agent line (\code{__usage_}, or a near miss)
#'     shares a group with \code{User-agent: *}, or with a crawler or other
#'     policy token from which a directive line separates it, so the group's
#'     rules reach them too. \cr
#'   \code{user_agent_joined_across_directive} \tab warning \tab
#'     A User-agent line joins the open group across a directive such as
#'     Sitemap or Crawl-delay, so that group's rules also reach the agents
#'     before it; the message names those agents, the rule lines, a full
#'     block, and where Bing (and, where tested, Yandex) ends the group.
#'     Anchored on the joined line. \cr
#'   \code{user_agent_joined_across_blank} \tab info \tab
#'     A User-agent line shares a group with the agents before it across
#'     blank or comment lines only: Google and Bing join them, Yandex ends
#'     the group at the first such line. Anchored on the joined line. \cr
#'   \code{user_agent_repeated_group} \tab info \tab
#'     A crawler (or \code{*}) is named in a later group as well as an
#'     earlier one, so Google, Bing and Yandex merge the groups. Anchored on
#'     the later group's first line naming it; the message lists the earlier
#'     lines. \cr
#'   \code{user_agent_duplicate_in_group} \tab info \tab
#'     A User-agent line repeats a name, in any case or \code{*}, already in
#'     its own group, which changes nothing (RFC 9309 section 2.2.1). Anchored
#'     on the repeated line; the message names the first line naming it. Blank,
#'     comment, Crawl-delay and unknown-field lines between the two names were
#'     checked against the Bing and Yandex testers (2026-11-21). \cr
#'   \code{empty_disallow_with_full_block} \tab warning \tab
#'     The rules one crawler follows hold an empty \code{Disallow:} and a
#'     full block (\code{Disallow: /}, no non-empty Allow): Google and Bing
#'     block every path, Yandex allows the paths no longer Disallow matches.
#'     Anchored on the full-block line. \cr
#'   \code{disallow_tied_by_allow} \tab warning \tab
#'     A Disallow never takes effect: an Allow with the identical pattern
#'     applies to the same crawlers and wins the tie. Anchored on the
#'     Disallow line; the message names the Allow line. \cr
#'   \code{duplicate_rule} \tab info \tab
#'     An Allow or Disallow repeats an earlier rule of the same type and
#'     pattern for the same crawlers, so it has no effect. Anchored on the
#'     repeat; the message names the earlier line. When the groups share
#'     the crawler only because Google's matcher cuts two written User-agent
#'     values to one token, the message says the repeat is Google's only and
#'     names the values, and that a matcher comparing the whole value keeps
#'     those groups apart. \cr
#'   \code{missing_user_agent} \tab error \tab
#'     Allow or Disallow rules exist but no line names a non-empty
#'     User-agent. \cr
#'   \code{html_body} \tab warning \tab
#'     The body looks like an HTML page, not a robots.txt; its lines are still
#'     read and reported one by one. \cr
#'   \code{xml_body} \tab warning \tab
#'     The body starts with markup (\code{<}), such as XML, not a robots.txt;
#'     its lines are still read and reported one by one. A body that opens
#'     with a markup comment (\code{<!--}) is treated as a robots.txt that
#'     starts with a comment, so it draws no \code{xml_body}; the comment line
#'     keeps its own \code{malformed_line} row. Only the first 4,096 bytes are
#'     sniffed. A body whose reads are binary (a NUL byte, or mostly invalid
#'     UTF-8, in those bytes) draws neither \code{xml_body} nor
#'     \code{json_body}; a body cut at \code{max_bytes} is also sniffed on its
#'     stored bytes: binary bytes in the cut-off part alone do not hide markup
#'     or JSON in the readable lines. \cr
#'   \code{json_body} \tab warning \tab
#'     The body looks like a JSON object or array, such as an API error, not a
#'     robots.txt; its lines are still read and reported one by one. Only the
#'     first 4,096 bytes are sniffed, and a binary read draws neither
#'     \code{json_body} nor \code{xml_body}, as described for \code{xml_body}.
#'     At most one of \code{html_body}, \code{xml_body} and \code{json_body} is
#'     reported per document, in that order of precedence. \cr
#'   \code{utf16_or_utf32_encoding} \tab warning \tab
#'     A raw or fetched body is UTF-16 or UTF-32, not UTF-8 (RFC 9309 section
#'     2.3): it starts with the byte-order mark of that encoding (a UTF-32
#'     mark is tested before the UTF-16 mark it starts with), or, with no
#'     mark, its first 4,096 bytes hold at least 8 code units, 90 percent or
#'     more of them one ASCII character each, and no byte but zero, printable
#'     ASCII, tab, carriage return or line feed. The message says which
#'     basis it is; the byte
#'     pattern is a heuristic and cannot know the intended encoding. Not
#'     reported for character input. \cr
#'   \code{no_rules} \tab info \tab
#'     The parser read no Allow or Disallow rule, so the document restricts
#'     nothing; when NUL bytes hide rules, \code{rules_after_nul_removal} is
#'     reported instead.
#'     Not reported for a body cut at \code{max_bytes}. \cr
#'   \code{rules_after_nul_removal} \tab warning \tab
#'     The NUL bytes hide Allow or Disallow rules: with them removed, the
#'     body holds rules that the parser and Google's matcher, which both end
#'     a line at its first NUL, never read. When the parser read no rule,
#'     every NUL-free rule is counted; UTF-16 text does this, and should be
#'     re-saved as UTF-8; reported in place of \code{no_rules}. Otherwise
#'     only grouped rules (after a User-agent line) on lines the parser does
#'     not read as rules, or in a group the NUL changes, are counted; a value
#'     the NUL only shortens is not. Reported even for a body cut at
#'     \code{max_bytes}. \cr
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
#'   \code{acquisition_http_other_2xx} \tab info \tab
#'     A 2xx other than 200, such as 203 or 204; the body is still validated.
#'     \code{message} names how Google, Yandex and Bing read the status. \cr
#'   \code{acquisition_limit_exceeded} \tab error \tab
#'     A body with a 3xx status, an unknown status, or a 2xx whose libcurl and
#'     status-line statuses disagree exceeded \code{max_bytes} and was refused
#'     whole. \cr
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
#'   \code{redirect_other_path} \tab info \tab
#'     The fetch redirected to another path on the same host, such as the
#'     home page; a warning when the page reached is HTML. \cr
#'   \code{redirect_same_site} \tab info \tab
#'     The fetch redirected to another host of the same registrable domain,
#'     such as \code{www} and the bare domain; a warning when the page
#'     reached is HTML. \cr
#'   \code{redirect_cross_site} \tab warning \tab
#'     The fetch redirected to another registrable domain, whose file is
#'     applied to this host. \cr
#'   \code{redirect_downgrade_followed} \tab info \tab
#'     Under \code{safety_level = "crawler"}, the fetch followed an
#'     \code{https} to \code{http} redirect, so part of the redirect chain
#'     went over plain \code{http}; \code{message} names each such hop. \cr
#'   \code{content_type_malformed} \tab warning \tab
#'     The fetched response's \code{Content-Type} is not one
#'     \code{type/subtype} media type with \code{name=value} parameters (RFC
#'     9110 section 8.3.1), or holds a comma outside a quoted string, as
#'     repeated fields joined with \code{", "} do (the same media type sent
#'     twice gets advice to send one field). \code{raw_text} holds the
#'     header as received. A missing header gives no row. \cr
#'   \code{content_type_not_text_plain} \tab warning \tab
#'     The fetched response's media type is not \code{text/plain} (RFC 9309
#'     section 2.3), compared ignoring ASCII case. The body is still read and
#'     validated; crawlers may still read it as a robots.txt. \cr
#'   \code{content_type_charset_unsupported} \tab warning \tab
#'     The \code{Content-Type} declares a \code{charset} other than
#'     \code{utf-8} or \code{us-ascii} and its aliases (a nonstandard UTF-8
#'     label such as \code{utf8} included), an empty one, or two different
#'     ones. The body is read as UTF-8 regardless, without conversion. \cr
#'   \code{content_type_charset_conflict} \tab warning \tab
#'     The \code{Content-Type} declares \code{charset=us-ascii}, or one of its
#'     registered aliases such as \code{ascii}, over a body holding a byte of
#'     0x80 or above. Not reported for a UTF-16 or UTF-32 body, which
#'     \code{utf16_or_utf32_encoding} reports. \cr
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
#' matching every path is not listed, because the named group's own rules are
#' what the crawler follows. Such an Allow is `/` with any `*`s after it, or a
#' run of `*`s with an optional `/` before and an optional final `$` (`/`,
#' `/*`, `*`, `/*$`, `*$`; `/$` is not one). A trailing `*` is ignored (`/x`
#' equals `/x*`, and `*` and `/*` equal `/`), `$` is not, and empty values are
#' left out. The message lists the missing `*` rules, ten at most. A crawler
#' whose rules are all explicit allow-all (an empty `Disallow:` or an
#' every-path `Allow`, as above) is not reported; an empty `Allow:` is ignored,
#' and a crawler whose groups have no other rule is reported. A crawler whose
#' merged groups disallow `/` (a `Disallow` of `/`, `/*`, `*`, `**` or `/**`,
#' not one ending in `$`) and hold no non-empty `Allow` is in a full block:
#' the `*` Disallows it lacks add nothing, so only its lost `*` Allow rules are
#' listed, as rules that may be meant as exceptions. An empty `Allow:` does not
#' cancel a full block.
#'
#' A lost `*` Disallow is a `wildcard_disallows_not_inherited` warning when a
#' path it matches (the pattern with each `*` as nothing or `x`, and unless it
#' ends in `$`, with `x` or `/x` appended) is disallowed under the `*` groups
#' and allowed by the Disallows of the crawler's merged groups alone, as
#' Google's matcher reads both; a `*` Allow that reopens every such path
#' leaves no warning, and a path only the crawler's own Allow reopens (an
#' `Allow: /company` under `Disallow: /`) is left to
#' `allow_reopens_wildcard_disallow`. A group
#' of only Allows warns too. An explicit grant (`Allow: /`, or an empty
#' `Disallow:`, with no other Disallow) lifts every `*` Disallow but is almost
#' always deliberate, so it is reported as info. The crawlers that ignore
#' `User-agent: *` whether or not a group names them get no warning, and
#' their info row says the `*` rules never applied to them.
#'
#' `allow_reopens_wildcard_disallow` reports a `*` Disallow when a path is
#' disallowed by it under the `*` groups, allowed under the crawler's merged
#' groups, and disallowed by those groups' Disallows alone, so an Allow of
#' the crawler's reopens it. The candidate paths are the witness paths of
#' the `*` Disallow, those of the crawler's Allows, and the `*` Disallow read
#' under the literal prefix of each Allow (`/creativegroup/_print.html` for
#' `Allow: /creativegroup/` and `Disallow: /*_print.html`). Google's matcher
#' decides every read, so a reported path is exact; an overlap no candidate
#' shows is skipped. A `*` Disallow the crawler loses outright is
#' `wildcard_disallows_not_inherited`'s, not this code's. When every path is
#' reopened by an every-path Allow (`Disallow: /` with `Allow: /`), the group
#' grants everything on purpose, so the row is info.
#'
#' The three wildcard codes name each crawler by its value as written. When
#' Google's matcher cuts that value (`Peer39_Crawler`, read as `Peer`), the
#' message adds a sentence naming the cut values and their lines, five at
#' most, and pointing to their `user_agent_cut` rows: on Google's matcher a
#' crawler going by the full value does not match the group the row names.
#' A merged row names only its cut values there.
#'
#' The `ai_training_` codes follow
#' draft-kelley-aipref-training-preference-signal-00 (dated 2026-10-30), an
#' Internet-Draft: a `User-agent: __usage_ai-training` group states an
#' AI-training preference, a disallowed path one against training on it and
#' an allowed path one in favor. The draft matches the token exactly, apart
#' from ASCII case, and a `User-agent: *` group never applies to it, so the
#' token is never reported as `wildcard_rules_not_inherited`, nor is a value
#' Google's matcher reads as the token (`__usage_ai-training/1.0`). A near
#' miss is a value whose leading run of letters, `_` and `-`, with the `_`
#' and `-` removed, is `usageaitraining` in any case. The Google and Yandex
#' parsers join User-agent lines that no Allow or Disallow line separates
#' into one group; the Bing parser joins them only across blank and comment
#' lines and ends the group at any other directive
#' (`design/engine-disagreements.md` classes 1 and 1b). So a training
#' opt-out after a `*` group that holds no rule can become a Disallow for
#' every crawler, and `ai_training_token_stacked` says so, naming which
#' parsers join the lines. Another policy token or crawler a directive line
#' separates from the token is reported too. Blank and comment lines
#' separate nothing, and the draft lets a group mix tokens, so consecutive
#' or comment-headed User-agent lines that name crawlers stay silent. A
#' line after a token group's last rule may head the next group, so
#' `ai_training_group_extra_line` leaves it out unless the group is the
#' file's last. A key such as `DisallowAITraining` is
#' `accepted_directive_prefix`. A body cut at `max_bytes` is checked, and
#' the info then says the lines past the cut were not read. On a document
#' holding a NUL byte they follow Google's reading, as the other group
#' checks do.
#' Which crawler operators read the token, and from when, is recorded with
#' dates in `design/engine-profiles.md` section 7a.
#'
#' For `user_agent_joined_across_directive` and
#' `user_agent_joined_across_blank`, Google's parser starts a new group only
#' after an Allow or Disallow line, so every User-agent line before a group's
#' first rule joins that group, and its rules reach every agent named there.
#' Consecutive User-agent lines are the deliberate way to share rules and stay
#' silent. A break between two User-agent lines of one group is reported on
#' the later line: a warning when a directive (`Sitemap`, `Crawl-delay`,
#' `Host`, `Clean-param`, `Content-Signal` or any unknown field) lies between,
#' since Bing ends the group at the directive (`design/engine-disagreements.md`
#' class 1); an info when only blank or comment lines do, which Google and Bing
#' join and Yandex's tester splits; it names only the agents since the last
#' directive, since Bing ended the group of any agent before it. Yandex is
#' named only for a blank, comment or `Crawl-delay` line, the lines its
#' tester was seen to end a group at; its reading of a Sitemap or unknown
#' field is untested. A policy-token line is
#' left to `ai_training_token_stacked` and is never named as an earlier agent;
#' a line naming no crawler, a line whose only earlier agents share its name
#' and a group with no rule or only empty ones draw nothing, and the info is
#' left out when a directive follows later in the run. For agents not meant
#' to get the rules, the message suggests an empty `Disallow:` ending their
#' group; moving a Sitemap out of the run is offered only to agents meant to
#' share them, since it makes the User-agent lines adjacent. Each message
#' names at most five earlier agents and three directive lines, and counts
#' the rest. An agent whose value Google's matcher cuts (`Foo Bar`, read as
#' `Foo`) is named as written, and the message adds a sentence pointing to
#' its `user_agent_cut` row, as `ai_training_token_stacked` does for the
#' crawler it names. On a document
#' holding a NUL byte the check follows Google's reading, as the other group
#' checks do.
#'
#' For `user_agent_repeated_group` and `empty_disallow_with_full_block`, every
#' engine merges the groups that name one crawler (`design/engine-profiles.md`
#' section 5e): a repeat is reported once per later group with a rule and
#' crawler, and a line a `user_agent_joined_*`, `user_agent_cut` or
#' `wildcard_rules_not_inherited` report already owns, or a policy-token
#' line, draws nothing but still counts for later groups. The warning fires
#' within one group too, where the engines split the same way. An every-path
#' Allow beside `Disallow: /` is no split (every engine allows) and draws
#' neither. A cut line draws no `user_agent_repeated_group` row; an
#' `empty_disallow_with_full_block` row naming a cut value adds the sentence
#' pointing to its `user_agent_cut` row, as the wildcard codes do.
#'
#' For `user_agent_duplicate_in_group`, a User-agent line that repeats a name
#' already in its own group, in any case (`*` included), is reported on the
#' repeated line; the row is info, so `validation_status` is unchanged. RFC 9309
#' section 2.2.1 matches a product token case-insensitively, so the repeat
#' changes nothing and the line can be deleted. Blank, comment, Crawl-delay and
#' unknown-field lines between the two names were checked against the Bing and
#' Yandex testers (2026-11-21). Names are compared as written, folded to ASCII
#' lowercase, so `Foo Bot` and `foo` stay apart: Google reads only `Foo` from
#' the first. A line that a `user_agent_joined_*`, `user_agent_cut` or
#' `wildcard_rules_not_inherited` report already owns draws nothing but still
#' counts as an earlier name; a policy-token line is left to `ai_training_*` and
#' never counts as an earlier name. A group with no rule line draws nothing. A
#' repeat across a blank or a directive that still joins the group counts as
#' in-group, unless a join row owns that line.
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
#' User-agent line from joining its group. The canonical value has its
#' escapes in upper case, so a line that differs only by a lower-case escape
#' from a line in the same group that writes the escape in upper case is the
#' same rule. It is reported as `rule_lowercase_escape_twin` instead, and it
#' neither gets a `duplicate_rule` row nor counts as the earlier rule of
#' one. In other groups, such a line keeps `rule_lowercase_escape` and may
#' get `duplicate_rule`. Groups merge as Google's matcher merges them, so
#' `Foo web spider` and `Foo blog`, both read as `Foo`, share their rules. A
#' repeat that exists only through such a cut (no earlier line with the rule
#' sits in a group that shares a whole User-agent value, folded to ASCII
#' lower case, with the repeat's group) does not say the rule has no effect:
#' its message says the repeat is Google's only, names the tokens read (five
#' at most, then a count) and the values written for them up to the
#' repeat's group (five at most, one of that group's for each token named,
#' then a count), says a matcher comparing the whole
#' value keeps the groups apart, and points to the `user_agent_cut` rows.
#' It names the package's Bing matcher only when the token is a crawler the
#' Bing backend evaluates (`bingbot`, `adidxbot`), and its Yandex matcher
#' only for `Yandex` or `YandexAdditionalBot`. When an earlier group with the
#' rule shares a whole value with the repeat's group, as `User-agent: Foo`
#' beside `User-agent: Foo` and `User-agent: 1bot` does, a matcher that
#' compares the whole value merges them too, and the row keeps the plain
#' message.
#'
#' On a document holding a NUL byte, `wildcard_rules_not_inherited`,
#' `disallow_tied_by_allow`, `duplicate_rule` and the AI-training codes
#' follow Google's reading: the parser and Google's matcher end a line at its
#' first NUL, while the Bing and Yandex matchers read the NUL as an ordinary
#' byte, so each such message says it is Google's reading, unless every NUL
#' sits in a comment. `user_agent_cut` runs too; its message already names
#' Google's matcher.
#'
#' The validator adds three info codes for text that may have
#' been damaged on its way into the file. They are advisories, not validity
#' findings: they change no status, no parse and no match, and each message
#' says the character may be meant. Some damage is already visible without
#' them: mixed UTF-8 and Latin-1 bytes are usually malformed UTF-8, which
#' `invalid_utf8` reports. Text that is valid UTF-8 can neither prove nor
#' disprove corruption, so the check reads only a closed set of indicators
#' in the raw value of an active Allow or Disallow line, as the parser reads
#' it (cut at the first `#`, at a NUL and at the line buffer):
#' `rule_replacement_character` for U+FFFD; `rule_invisible_character` for
#' U+00AD, U+200B to U+200F, U+202A to U+202E, U+2060 to U+2064, U+2066 to
#' U+2069, U+FEFF and the C1 controls U+0080 to U+009F; and
#' `rule_possible_mojibake` for two or more sequences of a Latin-1
#' character U+00C2 to U+00F4 followed by the U+0080 to U+00BF characters
#' that, read back as bytes, make one well-formed UTF-8 character (U+00C3
#' U+00A9 for an e-acute). The mojibake check is a heuristic and can flag
#' intended text: `2` U+00D7 U+00BD (a multiplication sign and a vulgar
#' half) twice in one value, or capitals such as U+00C9 each followed by a
#' no-break space U+00A0, read the same way. A single such sequence is not
#' reported as mojibake; one whose second character is U+0080 to U+009F is
#' still a C1 control and gets `rule_invisible_character`. No other
#' non-ASCII character is matched, so most paths with accented letters, a
#' path in Japanese, or a Latin-1 string converted to UTF-8 on input stay
#' silent, as do a typed escape such as `%E2%80%8B`, a comment, a
#' User-agent value (a cut one names its look-alike characters on its
#' `user_agent_cut` row instead), a Sitemap value, and a rule value that is
#' not valid UTF-8
#' (bytes after the cut, in a comment or past a NUL, do not count; a
#' character the line buffer splits is dropped). Each message quotes code
#' points as `U+XXXX` with byte offsets counted from 1 at the value's first
#' byte after the blanks that follow the colon, listing at most ten, and a
#' line gets at most one row per code. A U+200B or U+FEFF that leads the
#' value is left to `rule_missing_leading_slash`, which names it. A document
#' gets at most 100 such rows; the last one counts the rest. Only the
#' Latin-1 mojibake pattern is read: a Windows-1252 decoding, NFC or NFD
#' normalization and the intended original text are out of scope, and
#' nothing is repaired.
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
    fetch_outcome = "supplied",
    raw_input = is.raw(robots_txt)
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
#' or refetch is introduced; the one exception is the opt-in
#' `destination_robots = TRUE`, which reads a cross-site redirect
#' destination's own robots.txt as [robots_fetch()] describes and validates
#' each destination row apart, so a destination that reuses an origin's
#' result has that body validated once more, under its own `source_id`.
#' Acquisition failures are retained as evidence and
#' produce `"not_validated"` document rows. A 2xx body over `max_bytes` is cut
#' at the limit: its first `max_bytes` bytes are validated up to their last
#' complete line (the partial line after the last line break is not read), as
#' RFC 9309 section 2.5 allows a crawler to parse. The document row reports
#' the cut with `body_truncated` and `limit_exceeded` both `TRUE` and
#' `final_newline = NA` (the file's end was never read), `byte_size` is the
#' stored size, and a warning diagnostic with code `body_truncated` says most
#' of the file may not have been validated. A body over `max_bytes` with a 3xx
#' status, an unknown status, or a 2xx whose libcurl and status-line statuses
#' disagree is refused whole and reported as `acquisition_limit_exceeded`, and a
#' 4xx or 5xx keeps its status outcome whatever its body size.
#'
#' A status that leaves no body gets a code for its class (404 and 410
#' `acquisition_missing`, another 4xx `acquisition_http_4xx`, 429
#' `acquisition_http_429`, 5xx `acquisition_http_5xx`, 1xx
#' `acquisition_http_protocol`). Its message names the status, what Google,
#' Yandex and Bing may do with it, and any `Retry-After` delay; the policy
#' behind it is in [robots_engine_contract_v1()]. The document stays
#' `"not_validated"`, so an `acquisition_http_4xx` row (a 4xx other than 404,
#' 410 and 429) has `warning_count` 1 and `error_count` 0. A 2xx other than 200
#' (203 or 204, say) keeps its body, which is validated as a 200's is, and also
#' gets `acquisition_http_other_2xx`, an info whose message names how Google,
#' Yandex and Bing read that status. A 206 is a partial response with no body,
#' so it keeps `acquisition_partial_response`.
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
#' gives no engine verdict for it. The exception is a refusal of an internal
#' address (loopback, private, link-local and the like) under
#' `safety_level = "crawler"`: a public crawler could not reach that address
#' either, so the message reads it as an unreachable file and names each
#' engine's reading of an unreachable file.
#'
#' A fetch that succeeded after redirecting away from the robots.txt URL is
#' reported beside the body's own diagnostics, from the source row's
#' `robots_url`, `effective_url` and `content_flag`: `redirect_other_path`
#' (same host, another path; info, or a warning when the page reached is
#' HTML), `redirect_same_site` (another host of the same registrable domain;
#' info, or a warning when the page reached is HTML) and
#' `redirect_cross_site` (another registrable domain; warning). A
#' change of scheme or port alone, such as `http` to `https`, is not
#' reported by these, but an `https` to `http` redirect that was followed
#' (only `safety_level = "crawler"` follows one), anywhere in the chain, is
#' reported as `redirect_downgrade_followed` (info), naming each such hop,
#' from the source row's `redirect_hops`. The registrable domain comes from
#' the Public Suffix List through `rurl::get_domain()`, so
#' `a.example.co.uk` and `b.example.co.uk` are one site; an IP literal, or a
#' host with no registrable domain, is compared whole. RFC 9309 section
#' 2.3.1.2 and Yandex document applying the file reached to the requested
#' host, Google is inferred to, and Bing
#' does not document it; when the page reached is HTML, the message says
#' the robots.txt is effectively missing. The fetch itself is unchanged,
#' unless `destination_robots = TRUE` asks for the destination's own
#' robots.txt as well.
#'
#' With `destination_robots = TRUE`, each destination robots.txt read (see
#' "Destination robots.txt" in [robots_fetch()]) is validated as an origin
#' body is, the same redirect and `Content-Type` rows included, and reported
#' in its own components: `destination_documents` and
#' `destination_diagnostics`, keyed by the destination's `source_id`
#' (`destination_1` and so on), and `destination_map`, linking each origin
#' followed up to its destination. `map`, `documents` and `diagnostics` stay
#' the origin's: a destination's findings never change its origin's
#' `validation_status`.
#'
#' After those rows, a fetched body's `Content-Type` (the source row's
#' `content_type`) is checked: `content_type_malformed`,
#' `content_type_not_text_plain`, `content_type_charset_unsupported` and
#' `content_type_charset_conflict` (`charset=us-ascii` or an alias of it over
#' bytes of 0x80 or above, except a UTF-16 or UTF-32 body), all warnings that
#' change no parse or decision. Every response whose body is validated is
#' checked, an empty 2xx body (a 203 or 204, say) included; a response with
#' no `Content-Type` gets no row, and an outcome left with no body (a 4xx,
#' 5xx, or failed or refused fetch) is not checked.
#'
#' This function validates the acquired robots.txt document. It does not answer
#' whether any target URL is allowed; use [allowed_by_robots_url()] for that
#' separate question. It also does not infer webmaster intent or check whether
#' declared remote sitemaps exist.
#'
#' Each validated body is also read for the info codes
#' [robots_validate_text()] describes; their rows come before the redirect and
#' `Content-Type` rows.
#'
#' @inheritParams robots_fetch
#'
#' @return An S3 object of class `robots_validations`, containing `map` (one row
#'   per input URL), `documents` (one row per distinct fetch source), and
#'   `diagnostics` data frames. With `destination_robots = TRUE` it also has
#'   `destination_documents`, `destination_diagnostics` (the columns of
#'   `documents` and `diagnostics`) and `destination_map`.
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
                                safety_level = "strict",
                                fetch_allow_ranges = character(),
                                destination_robots = FALSE) {
  # destination_robots first, as robots_fetch() checks it (ROBO-ybhwztid).
  validate_destination_robots(destination_robots)
  safety_level <- validate_safety_level(safety_level)
  fetched <- robots_fetch(
    url = url,
    timeout = timeout,
    max_bytes = max_bytes,
    fetch_user_agent = fetch_user_agent,
    ssrf_guard = ssrf_guard,
    safety_level = safety_level,
    fetch_allow_ranges = fetch_allow_ranges,
    destination_robots = destination_robots
  )
  validate_fetched_documents(fetched, safety_level = safety_level)
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

new_robots_validations <- function(map, documents, diagnostics,
                                   destinations = NULL) {
  structure(
    c(
      list(map = map, documents = documents, diagnostics = diagnostics),
      destinations
    ),
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

# The message of each body-kind advisory (ROBO-ccfsanhq, ROBO-mgtngbpm), keyed
# by the kind the content sniffer reads. Each says the lines were read anyway.
body_kind_messages <- c(
  html = paste0("The body looks like an HTML page, not a robots.txt; its ",
                "lines were read as directives anyway."),
  xml = paste0("The body starts with markup (`<`), such as XML, not a ",
               "robots.txt; its lines were read as directives anyway."),
  json = paste0("The body looks like a JSON object or array, such as an API ",
                "error, not a robots.txt; its lines were read as directives ",
                "anyway.")
)

# A body that opens with a markup comment is treated as a robots.txt that starts
# with a comment (ROBO-isbpzgqn), so the sniffer's "xml" read for it draws no
# xml_body (ROBO-mgtngbpm). The check reads the bytes the read came from, after
# an optional UTF-8 BOM, with the sniffer's own `^\s*<` whitespace and flags
# (R/content-check.R), so the two agree in every locale.
body_opens_with_comment <- function(body) {
  window <- body[seq_len(min(length(body), content_check_bytes))]
  if (length(window) >= 3L &&
        identical(window[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) {
    window <- window[-(1:3)]
  }
  grepl("^\\s*<!--", rawToChar(window), perl = TRUE, useBytes = TRUE)
}

# One read of a body as an advisory kind: the content flag, except that an
# "xml" read of a body opening with a markup comment is no kind (ROBO-mgtngbpm).
body_read_kind <- function(body) {
  flag <- robots_content_flag(body)
  if (identical(flag, "xml") && body_opens_with_comment(body)) {
    return(NA_character_)
  }
  flag
}

# The body-kind advisory a document draws, or NA (ROBO-mgtngbpm). Both reads of
# the content sniffer count: the stored bytes, so a body cut mid-line keeps its
# kind, and the validated bytes, so a NUL or invalid UTF-8 in the partial line a
# cut drops does not hide it. The first of html, xml and json that either read
# gives is the advisory, so a document draws at most one. A "binary" read is
# none of these: a body whose reads are binary draws none, and nul_byte or
# invalid_utf8 reports it.
body_kind_advisory <- function(stored_flag, flag) {
  kinds <- intersect(c("html", "xml", "json"), c(stored_flag, flag))
  if (length(kinds) == 0L) {
    return(NA_character_)
  }
  kinds[[1L]]
}

validate_document_bytes <- function(bytes, source_id, source_type,
                                    robots_url = NA_character_,
                                    effective_url = NA_character_,
                                    http_status = NA_integer_,
                                    fetch_outcome = "supplied",
                                    max_bytes = NA_integer_,
                                    body_truncated = FALSE,
                                    raw_input = TRUE) {
  # A 2xx body cut at max_bytes (RFC 9309 section 2.5, ROBO-ldpahknv) is
  # validated up to its last complete line: the partial line after it is not
  # the site's. `byte_size` stays the stored size; the file's real end was
  # never read, so `final_newline` is NA.
  stored_size <- length(bytes)
  stored_bytes <- bytes
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

  # The diagnostics are kept as chunks of column vectors, in emission order:
  # one chunk per row or batch. The frame is built once, at the end
  # (ROBO-dbvmxcfw), so the cost stays linear in the number of rows. Each chunk
  # is bound under its index: appending to a list held in the environment
  # would copy the whole list on every append.
  diag_env <- new.env(parent = emptyenv())
  diag_env$n_chunks <- 0L
  add_chunk <- function(line, severity, code, directive, raw_text, message) {
    n <- length(line)
    # Each column is one value per row or one value for the whole chunk;
    # rep_len() would silently cut or pad any other length.
    stopifnot(all(lengths(list(severity, code, directive, raw_text, message))
                  %in% c(1L, n)))
    diag_env$n_chunks <- diag_env$n_chunks + 1L
    assign(as.character(diag_env$n_chunks), list(
      line = rep_len(as.integer(line), n),
      severity = rep_len(as.character(severity), n),
      code = rep_len(as.character(code), n),
      directive = rep_len(as.character(directive), n),
      raw_text = rep_len(as.character(raw_text), n),
      message = rep_len(as.character(message), n)
    ), envir = diag_env)
  }
  add_diagnostic <- function(line, severity, code, directive, message) {
    raw_text <- if (!is.na(line) && line <= line_count) {
      render_validation_line(raw_lines[[line]])
    } else {
      NA_character_
    }
    add_chunk(line, severity, code, directive, raw_text, message)
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
  # document is well-formed exactly when every line is. NUL is a one-byte
  # UTF-8 character (nul_byte reports it), so a line is checked as it is
  # written: each run of bytes between NULs must be well-formed, and a
  # sequence a NUL splits (`\xC3\0\xA9`) is not (ROBO-xuusttbp). The parser
  # cuts a line at its first `#` (GetKeyAndValueFrom), and `#` is never part
  # of a multi-byte sequence, so bad bytes only after it change no rule
  # (ROBO-sniltuap). Google's parser and matcher end a line at its first NUL
  # (ROBO-pvqrfvol) and never read bytes after it; the Bing and Yandex
  # matchers read past the NUL and cut at `#` too. So the code follows the
  # line as written, as Bing and Yandex read it, and the message says when
  # every bad byte lies after the first NUL, where Google reads nothing.
  # Its rows go in as one frame: a file can hold thousands of bad lines.
  nul_free_lines <- lapply(raw_lines, nul_free_bytes)
  bad_lines <- which(!vapply(raw_lines, validation_utf8_line, logical(1L)))
  encoding_valid <- length(bad_lines) == 0L
  if (!encoding_valid) {
    in_comment <- vapply(raw_lines[bad_lines], function(line_bytes) {
      hash <- match(as.raw(0x23), line_bytes)
      !is.na(hash) &&
        validation_utf8_line(validation_raw_slice(line_bytes, 1L, hash - 1L))
    }, logical(1L))
    # Indexed by 1 + in_comment + 2 * past_nul.
    utf8_messages <- c(
      "Line bytes are not well-formed UTF-8.",
      paste0("Only a comment holds bytes that are not well-formed UTF-8; ",
             "no rule changes."),
      paste0("Bytes after the line's first NUL are not well-formed ",
             "UTF-8: Google's matcher ends the line at the NUL and never ",
             "reads them; Bing and Yandex read past it."),
      paste0("Only bytes after the line's first NUL are not well-formed ",
             "UTF-8, in a comment as Bing and Yandex read the line; ",
             "Google's matcher ends the line at the NUL and never reads ",
             "them; no rule changes.")
    )
    # A `#` before the first NUL is a comment Google reads too, so only a
    # NUL before any `#` makes the message name the engines.
    past_nul <- vapply(raw_lines[bad_lines], function(line_bytes) {
      nul <- match(as.raw(0x00), line_bytes)
      hash <- match(as.raw(0x23), line_bytes)
      !is.na(nul) && (is.na(hash) || nul < hash) &&
        validation_utf8_line(validation_raw_slice(line_bytes, 1L, nul - 1L))
    }, logical(1L))
    add_chunk(
      bad_lines, ifelse(in_comment, "warning", "error"),
      ifelse(in_comment, "invalid_utf8_comment", "invalid_utf8"),
      NA_character_,
      vapply(raw_lines[bad_lines], render_validation_line, "",
             USE.NAMES = FALSE),
      utf8_messages[1L + in_comment + 2L * past_nul]
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
  # Computed once here: the empty-Disallow note (ROBO-vyystald) reads it in
  # the loop below, and the group checks after it.
  groups <- validation_groups(parsed, raw_lines)
  # Groups not naming `*` whose User-agent lines name at least one crawler
  # (a token Google reads), and whether the file has a `*` group.
  named_groups <- setdiff(groups$agents$group[nzchar(groups$agents$key)],
                          groups$groups$group[groups$groups$global])
  has_global_group <- any(groups$groups$global)
  # By line: TRUE for a rule line in such a group (a lookup, not a scan per
  # line, so the loop stays linear).
  rule_in_named_group <- logical(max(c(0L, parsed$line)))
  rule_in_named_group[groups$rules$line] <- groups$rules$group %in%
    named_groups
  # The lower-case escapes of each Allow or Disallow line, by line
  # (ROBO-kormmfyg), and, for a line holding any, the first line of its group
  # with the same rule written without one: Google and Bing upper-case the
  # escape, so the line repeats that twin (ROBO-nvzzjubl).
  rule_escapes <- vector("list", max(c(0L, parsed$line)))
  for (i in which(parsed$has_directive &
                    parsed$type %in% c("allow", "disallow"))) {
    line <- parsed$line[[i]]
    rule_escapes[line] <- list(rule_lowercase_escapes(
      raw_lines[[line]], line == 1L, parsed$missing_colon[[i]]
    ))
  }
  escape_twin <- rule_lowercase_escape_twins(groups$rules, rule_escapes,
                                              raw_lines, nul_counts)
  # RSL License lines (ROBO-ahqpndzq): their scope needs every License line
  # and the groups, so the rows are built once here and looked up by line.
  # A known key's action is its type, never "license".
  is_license <- which(parsed$has_directive & vapply(
    seq_len(nrow(parsed)), function(i) {
      identical(validation_ascii_action(parsed$action[[i]], "unknown"),
                "license")
    }, logical(1L)
  ))
  rsl <- rsl_license_rows(
    parsed$line[is_license], parsed$value[is_license],
    lapply(is_license, function(i) {
      line <- parsed$line[[i]]
      rule_raw_value(raw_lines[[line]], line == 1L, parsed$missing_colon[[i]])
    }),
    groups
  )
  unsupported <- logical(nrow(parsed))
  advisory_count <- 0L
  advisory_chunk <- 0L
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
      } else if (identical(action, "license")) {
        k <- match(line, rsl$line)
        add_diagnostic(line, rsl$severity[[k]], "rsl_license_directive",
                       action, rsl$message[[k]])
      } else if (unsupported[[i]]) {
        add_diagnostic(
          line, "warning", "unsupported_directive", action,
          paste0("Directive is known but ignored by this validation profile; ",
                 "another crawler may use it.")
        )
      } else {
        # A key holding a look-alike (`Dis<U+0430>llow`) names it and the
        # ASCII spelling (ROBO-wtixhwlo).
        key_note <- lookalike_note(parsed$action[[i]], "key")
        add_diagnostic(
          line, "warning", "unknown_directive", action,
          paste0("Directive is not recognized by this validation profile.",
                 if (!is.null(key_note)) paste0(" ", key_note$sentence, "."))
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
      if (!nzchar(value) && identical(type, "disallow") && group_open &&
            nul_counts[[line]] == 0L) {
        # An empty Disallow is the allow-all idiom (robotstxt.org's original
        # standard; RFC 9309 section 2.2 admits an empty pattern), so it is
        # info, not a warning (ROBO-vyystald). It still ends the User-agent
        # run, so a named group's crawlers leave `*` for it (section 2.2.1).
        # A line holding a NUL, and one outside any group, keep
        # empty_rule_value below.
        add_diagnostic(
          line, "info", "allow_all_disallow", type,
          paste0(
            "An empty Disallow value adds no restriction; the group's other ",
            "rules still apply.",
            if (rule_in_named_group[[line]]) {
              paste0(" The crawlers this group names follow it, merged with ",
                     "any other group naming them",
                     if (has_global_group) {
                       ", and not the `User-agent: *` group"
                     },
                     ".")
            }
          )
        )
      } else if (!nzchar(value)) {
        # A NUL right after the colon empties the value: the parser and
        # Google's matcher both end the line at its first NUL (ROBO-pvqrfvol),
        # so the path after it is never read. The message says so, quotes no
        # value and names no decision; raw_text keeps the line.
        add_diagnostic(
          line, "warning", "empty_rule_value", type,
          if (nul_counts[[line]] > 0L &&
                nul_hidden_rule(nul_free_lines[[line]], type)) {
            paste0("The first NUL ends this line, so the value is empty and ",
                   "the directive imposes no restriction; the text after the ",
                   "NUL is ignored.")
          } else {
            "Empty Allow or Disallow value is ignored by the matcher."
          }
        )
      }
      # The parser cuts the line at its first `#` (ROBO-gjhpykcj), so
      # `Disallow: /a#b` is the wider rule `/a`. Gated on has_comment: the
      # parser, like Google's matcher, never sees a `#` after a NUL
      # (ROBO-pvqrfvol) or past its line buffer.
      if (parsed$has_comment[[i]] && nzchar(value) &&
            rule_cut_by_comment(raw_lines[[line]])) {
        add_diagnostic(
          line, "warning", "rule_cut_by_comment", type,
          paste0("A '#' with no space or tab before it starts a comment, ",
                 "so the rule is cut at the '#'.")
        )
      }
      # A NUL inside the value cuts it the same way, on Google's reading
      # only: the Bing and Yandex matchers read the NUL as a byte of the
      # rule (ROBO-xuusttbp).
      if (nzchar(value) && nul_counts[[line]] > 0L &&
            rule_cut_by_nul(raw_lines[[line]])) {
        add_diagnostic(
          line, "warning", "rule_cut_by_nul", type,
          paste0("Google's matcher ends this line at its first NUL, so the ",
                 "rule is cut at the NUL; Bing and Yandex read the NUL as a ",
                 "byte of the rule. Remove the NUL.")
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
    # Google upper-cases a rule's escapes but never the URL's, so a
    # lower-case one misses the path written (ROBO-kormmfyg). The parser's
    # value is already upper-cased, so the check reads the raw line. When
    # the group already has the rule in upper case, the line is that rule's
    # twin: info naming it, not advice to write it (ROBO-nvzzjubl).
    if (type %in% c("allow", "disallow")) {
      escapes <- rule_escapes[[line]]
      if (length(escapes) > 0L && !is.na(escape_twin[[line]])) {
        add_diagnostic(
          line, "info", "rule_lowercase_escape_twin", type,
          rule_lowercase_escape_twin_message(escapes, escape_twin[[line]])
        )
      } else if (length(escapes) > 0L) {
        add_diagnostic(
          line, "warning", "rule_lowercase_escape", type,
          rule_lowercase_escape_message(escapes)
        )
      }
    }
    # Info advisories on the raw value (ROBO-qxcwxtbm), capped per document;
    # the last row kept is noted with the count left out.
    if (type %in% c("allow", "disallow") && nzchar(value)) {
      for (found in rule_unicode_advisories(
        rule_raw_value(raw_lines[[line]], line == 1L,
                       parsed$missing_colon[[i]])
      )) {
        advisory_count <- advisory_count + 1L
        if (advisory_count <= validation_unicode_advisory_cap) {
          add_diagnostic(line, "info", found$code, type, found$message)
          advisory_chunk <- diag_env$n_chunks
        }
      }
    }
  }
  if (advisory_count > validation_unicode_advisory_cap) {
    key <- as.character(advisory_chunk)
    chunk <- get(key, envir = diag_env)
    chunk$message <- paste0(
      chunk$message, " Unicode advisories stop at ",
      validation_unicode_advisory_cap, " rows per document; ",
      advisory_count - validation_unicode_advisory_cap,
      " more were not reported."
    )
    assign(key, chunk, envir = diag_env)
  }

  # The group checks read the parser's groups. With a NUL in the file (already
  # a `nul_byte` error) those are Google's groups only: the parser and
  # Google's matcher end a line at its first NUL (ROBO-pvqrfvol), while the
  # Bing and Yandex matchers read the NUL as an ordinary byte. So each such
  # finding names Google's reading (ROBO-xuusttbp).
  # A NUL after a line's first `#` sits in a comment every engine ignores,
  # so it changes no group and needs no note.
  nul_active <- vapply(raw_lines[nul_lines], function(line_bytes) {
    hash <- match(as.raw(0x23), line_bytes)
    is.na(hash) || match(as.raw(0x00), line_bytes) < hash
  }, logical(1L))
  nul_reading <- if (any(nul_active)) {
    paste0(" This is Google's reading, which ends each line at its first ",
           "NUL; Bing and Yandex read the NUL as an ordinary byte.")
  } else {
    ""
  }
  # Google's matcher reads a User-agent value only up to its first byte
  # outside [A-Za-z_-], so the group names another crawler than written,
  # or none (ROBO-zvhrayhx); the row states the effect and is a warning
  # only when a Google crawler reads the cut (ROBO-txnzyugl).
  agents <- groups$agents
  found <- user_agent_cut_rows(agents, has_global_group,
                               groups$groups$group[groups$groups$global])
  if (nrow(found) > 0L) {
    add_chunk(
      found$line, found$severity, found$code, found$directive,
      vapply(raw_lines[found$line], render_validation_line, "",
             USE.NAMES = FALSE),
      found$message
    )
  }
  # The AI-training policy token (ROBO-kzyfejcv). A cut body is checked on
  # the lines before the cut: a User-agent line past it could still join
  # the last group (stacking the token, or making a token-only group
  # mixed), and rules past it are unread, which the info says.
  found <- ai_training_diagnostics(groups, parsed,
                                   truncated = body_truncated)
  if (nrow(found) > 0L) {
    add_chunk(
      found$line, found$severity, found$code, found$directive,
      vapply(raw_lines[found$line], render_validation_line, "",
             USE.NAMES = FALSE),
      paste0(found$message, nul_reading)
    )
  }
  # A User-agent line Google joins to the open group across a directive, or
  # across blank and comment lines only (ROBO-xepnhfgs).
  found <- joined_user_agent_diagnostics(groups, parsed)
  joined_lines <- found$line
  if (nrow(found) > 0L) {
    add_chunk(
      found$line, found$severity, found$code, found$directive,
      vapply(raw_lines[found$line], render_validation_line, "",
             USE.NAMES = FALSE),
      paste0(found$message, nul_reading)
    )
  }
  # A named group drops the `*` rules for its crawlers (ROBO-gfjotdrr). On
  # a cut body a group's rules may lie past the cut, so it is skipped. Its
  # rows are added below; its lines are known here for the repeat check.
  inheritance <- if (body_truncated) list() else
    wildcard_inheritance_diagnostics(groups)
  # A crawler named again in a later group (ROBO-vnhirero); a line a join,
  # cut or inheritance report owns is skipped (one line, one report).
  owned_lines <- c(joined_lines, agents$line[agents$cut],
                   unlist(lapply(inheritance, `[[`, "owned")))
  found <- repeated_group_diagnostics(groups, skip = owned_lines)
  if (nrow(found) > 0L) {
    add_chunk(
      found$line, found$severity, found$code, found$directive,
      vapply(raw_lines[found$line], render_validation_line, "",
             USE.NAMES = FALSE),
      paste0(found$message, nul_reading)
    )
  }
  # A name repeated within one group (ROBO-wnuttuit), skipping the same lines.
  found <- user_agent_duplicate_in_group_diagnostics(groups,
                                                     skip = owned_lines)
  if (nrow(found) > 0L) {
    add_chunk(
      found$line, found$severity, found$code, found$directive,
      vapply(raw_lines[found$line], render_validation_line, "",
             USE.NAMES = FALSE),
      paste0(found$message, nul_reading)
    )
  }
  # An empty Disallow and a full block one crawler follows: Google and Bing
  # block, Yandex allows (ROBO-vnhirero). A cut body is skipped: lines past
  # the cut could add an Allow.
  if (!body_truncated) {
    found <- empty_disallow_full_block_diagnostics(groups)
    if (nrow(found) > 0L) {
      add_chunk(
        found$line, "warning", "empty_disallow_with_full_block", "disallow",
        vapply(raw_lines[found$line], render_validation_line, "",
               USE.NAMES = FALSE),
        paste0(found$message, nul_reading)
      )
    }
  }
  for (found in inheritance) {
    add_diagnostic(
      found$line, found$severity, found$code, "user-agent",
      paste0(found$message, nul_reading)
    )
  }
  # A Disallow an identical Allow ties never applies (ROBO-fdhmlvwm).
  # Lines past a cut can only add Allows or groups, which cannot revive
  # it, so a cut body is checked too.
  for (found in tied_disallow_diagnostics(groups)) {
    add_diagnostic(
      found$line, "warning", "disallow_tied_by_allow", "disallow",
      paste0(found$message, nul_reading)
    )
  }
  # A rule an earlier identical rule already gives the same crawlers has
  # no effect (ROBO-xexjgecr). Lines past a cut cannot give it one, so a
  # cut body is checked too.
  # Its rows go in as one frame: a file can repeat thousands of rules.
  # A lower-case-escape twin's own row reports it (ROBO-nvzzjubl), so it
  # is left out here, as a duplicate and as the earlier line one names.
  found <- duplicate_rule_diagnostics(
    groups, skip = which(!is.na(escape_twin))
  )
  if (nrow(found) > 0L) {
    add_chunk(
      found$line, "info", "duplicate_rule", found$type,
      vapply(raw_lines[found$line], render_validation_line, "",
             USE.NAMES = FALSE),
      paste0(found$message, nul_reading)
    )
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
  # A body that is HTML, XML or JSON in place of a robots.txt gets one
  # document-level warning (ROBO-ccfsanhq, ROBO-mgtngbpm), chosen by
  # body_kind_advisory() from the fetch row's sniffer (ROBO-nhuirvrd), read on
  # the stored bytes, so a page cut mid-line is still seen, and on the
  # validated bytes, so a NUL or invalid UTF-8 in the partial line a cut drops
  # does not hide it (ROBO-qquftxcx). Its per-line rows stay: a real rule
  # inside it is still enforced. Where the validated bytes hold the NUL or
  # mostly invalid UTF-8, the flag is "binary", and nul_byte or invalid_utf8
  # reports it instead.
  body_kind <- body_kind_advisory(body_read_kind(stored_bytes),
                                  body_read_kind(bytes))
  if (!is.na(body_kind)) {
    add_diagnostic(
      NA_integer_, "warning", paste0(body_kind, "_body"), NA_character_,
      body_kind_messages[[body_kind]]
    )
  }
  # A UTF-16 or UTF-32 body (ROBO-cvpkzckn) gets one document-level warning,
  # from a byte-order mark or, without one, from the byte pattern of ASCII
  # text in that encoding; the stored bytes are read, so a body cut mid
  # code unit keeps its mark; the UTF-8 mark is read there too, so a cut
  # before the first LF keeps it, while has_bom describes the validated
  # lines. `encoding` still says only whether the bytes are valid UTF-8. The
  # signature describes a raw or fetched body; character input is text the
  # caller already decoded, so it is not identified.
  wide <- if (raw_input) {
    validation_encoding_signature(stored_bytes, cut = body_truncated)
  }
  if (!is.null(wide)) {
    add_diagnostic(
      NA_integer_, "warning", "utf16_or_utf32_encoding", NA_character_,
      validation_encoding_signature_message(wide)
    )
  }
  encoding_signature <- NA_character_
  encoding_signature_basis <- NA_character_
  if (!is.null(wide)) {
    encoding_signature <- wide$signature
    encoding_signature_basis <- wide$basis
  } else if (raw_input && length(stored_bytes) >= 3L &&
               identical(stored_bytes[1:3], validation_bom)) {
    encoding_signature <- "utf-8-bom"
    encoding_signature_basis <- "bom"
  }
  # The parser and Google's matcher both end a line at its first NUL
  # (ROBO-pvqrfvol), so rules that appear only once the NULs are removed, as
  # in UTF-16 text, are hidden from both; they are reported instead of
  # no_rules (ROBO-igrkabdb), since the file's author most likely meant them.
  # Rules read before a cut are real, so a cut body is checked too. When the
  # parser reads rules of its own, the NUL-free read is reported only for the
  # grouped rules it adds: a grouped rule on a line the parser does not read
  # as one, or in a group the NUL changes (ROBO-ctdkqawi). A rule before the
  # first User-agent is in no group and is not counted; nor is a value the
  # NUL only shortens, which keeps its rule and group. That read is built
  # line by line, each line NUL-free and ended by LF, so its line N is raw
  # line N: a NUL dropped from the whole body would turn `\r\0\n` into one
  # CRLF and move every later line up by one.
  nul_free_rules <- 0L
  hidden_rules <- 0L
  if (length(nul_lines) > 0L) {
    if (rule_count == 0L) {
      nul_free_parsed <- robotstxtr_validation_parse_(nul_free_bytes(bytes))
      nul_free_rules <- sum(nul_free_parsed$type %in% c("allow", "disallow"))
    } else {
      nul_free_text <- unlist(lapply(nul_free_lines, function(line_bytes) {
        c(line_bytes, as.raw(0x0a))
      }), use.names = FALSE)
      nul_free_parsed <- as.data.frame(
        robotstxtr_validation_parse_(nul_free_text),
        stringsAsFactors = FALSE
      )
      nul_free_parsed <- nul_free_parsed[nul_free_parsed$line <= line_count, ,
                                         drop = FALSE]
      hidden_rules <- sum(!validation_rule_keys(nul_free_parsed) %in%
                            validation_rule_keys(parsed))
    }
  }
  if (hidden_rules > 0L) {
    add_diagnostic(
      NA_integer_, "warning", "rules_after_nul_removal", NA_character_,
      sprintf(
        paste0(
          "The NUL bytes hide %d Allow or Disallow rule(s) or move them to ",
          "another group: Google's matcher ends each line at its first NUL; ",
          "remove the NUL bytes."
        ),
        hidden_rules
      )
    )
  } else if (nul_free_rules > 0L) {
    add_diagnostic(
      NA_integer_, "warning", "rules_after_nul_removal", NA_character_,
      sprintf(
        paste0(
          "The NUL bytes hide %d Allow or Disallow rule(s): Google's matcher ",
          "ends each line at its first NUL and never reads them; if this is ",
          "a UTF-16 file, re-save it as UTF-8 (RFC 9309 section 2.3)."
        ),
        nul_free_rules
      )
    )
  } else if (rule_count == 0L && !body_truncated) {
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
  # A fetched 2xx other than 200 keeps its body, which is validated as a 200's
  # is; the code says how each ruleset reads the status (ROBO-yvhqvthd). A 206
  # never comes here fetched: classify_status() gives it partial_response with
  # no body. http_status_category_v1() still counts 206 as 2xx other, and a
  # missing status is protocol_error, so the category test drops that too.
  other_2xx <- identical(fetch_outcome, "fetched") &&
    identical(http_status_category_v1(http_status), "status_other_2xx")
  if (other_2xx) {
    add_diagnostic(
      NA_integer_, "info", "acquisition_http_other_2xx", NA_character_,
      paste(
        paste0("HTTP ", http_status, ": ",
               status_engine_readings("status_other_2xx"), "."),
        "See robots_engine_contract_v1()."
      )
    )
  }

  diagnostic_frame <- if (diag_env$n_chunks == 0L) {
    empty_validation_diagnostics()
  } else {
    chunks <- mget(as.character(seq_len(diag_env$n_chunks)), envir = diag_env)
    chunk_column <- function(name) {
      unlist(lapply(chunks, `[[`, name), use.names = FALSE)
    }
    validation_diagnostic(
      source_id, chunk_column("line"), chunk_column("severity"),
      chunk_column("code"), chunk_column("directive"),
      chunk_column("raw_text"), chunk_column("message")
    )
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
    encoding_signature = encoding_signature,
    encoding_signature_basis = encoding_signature_basis,
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

# TRUE for a License value that is an RFC 3986 section 4.3 absolute-URI as
# RSL 1.0 section 4.4 requires: a scheme, `:`, then only unreserved and
# reserved characters and `%HH` escapes, so no whitespace, no non-ASCII byte
# and no malformed `%`. The parser cuts the line at its first `#`, so the
# value never holds a fragment. The parser %-escapes a non-ASCII byte in the
# value it hands R, so `raw_values` (each value's bytes as the parser read
# them, from rule_raw_value()) is read for one.
rsl_license_uri <- function(value, raw_values) {
  ascii <- vapply(raw_values, function(bytes) {
    !any(as.integer(bytes) > 0x7fL)
  }, logical(1L))
  ascii & grepl(paste0("^[A-Za-z][A-Za-z0-9+.-]*:",
                       "([A-Za-z0-9._~:/?#@!$&'()*+,;=\\[\\]-]|",
                       "%[0-9A-Fa-f]{2})*$"),
                value, perl = TRUE, useBytes = TRUE)
}

# One row per License line (ROBO-ahqpndzq; design/engine-profiles.md section
# 7b), as list(line, severity, message), computed before the per-directive
# loop. RSL 1.0 section 4.4 scopes a License line by placement under RFC
# 9309 groups, which blank and unknown lines never end: before the first
# User-agent line it is global, otherwise it belongs to the last group that
# opened before it (`groups` from validation_groups()). A client whose group
# has its own License lines ignores the global ones. Info when the value is
# an absolute URI, warning otherwise; the placement is never an error.
# A License line is never a group's first line, so findInterval() needs no
# tie rule. The agent names are rendered once per group, so the cost stays
# linear in the file (ROBO-dbvmxcfw).
rsl_license_rows <- function(lines, values, raw_values, groups) {
  group_at <- findInterval(lines, groups$groups$first_line)
  global <- group_at == 0L
  local_groups <- sort(unique(group_at[!global]))
  valid <- rsl_license_uri(values, raw_values)
  agents <- groups$agents
  shown <- agents$global | nzchar(agents$name)
  rendered <- ifelse(agents$global, "*", ai_training_name(agents$name))
  names <- lapply(split(rendered[shown], factor(
    agents$group[shown], levels = groups$groups$group
  )), unique)
  lead <- ifelse(
    valid,
    paste0("License is the RSL 1.0 section 4.4 directive that points to ",
           "licensing terms."),
    paste0("License value is not an absolute URI, which RSL 1.0 section 4.4 ",
           "requires: a scheme such as `https:`, then no space, non-ASCII ",
           "byte or malformed %-escape.")
  )
  lead[!nzchar(values)] <- paste0("License value is empty; RSL 1.0 section ",
                                  "4.4 requires an absolute URI.")
  scope <- vapply(group_at, rsl_license_scope, "",
                  first = groups$groups$first_line, names = names,
                  has_global = any(global), local_groups = local_groups)
  list(line = lines, severity = ifelse(valid, "info", "warning"),
       message = paste(lead, paste0(
         "It changes no crawl access, which Allow and Disallow alone decide, ",
         "and no crawler operator is documented as reading it."
       ), scope))
}

# The scope sentence of a License line in group row `at` of `groups$groups`
# (0 for a line before the first User-agent line). `first` is each group's
# first line and `names` each group's rendered agents (`*` for a global
# line; empty User-agent lines left out).
rsl_license_scope <- function(at, first, names, has_global, local_groups) {
  if (at == 0L) {
    k <- length(local_groups)
    return(paste0(
      "Before the first User-agent line, it applies to every crawler under ",
      "RSL",
      if (k > 0L) {
        paste0(", except one that selects a group with its own License ",
               "line (the ", if (k == 1L) "group on line " else
                 "groups on lines ",
               joined_and(utils::head(first[local_groups], 5L), k - 5L), ")")
      },
      "."
    ))
  }
  group_names <- names[[at]]
  if (length(group_names) == 0L) {
    # Only empty User-agent lines: no crawler can select the group.
    return(sprintf(paste0(
      "It sits in the group on line %d, whose User-agent lines are all ",
      "empty, so no crawler selects that group and the line reaches none."
    ), first[[at]]))
  }
  listed <- joined_and(utils::head(group_names, 5L), length(group_names) - 5L)
  paste0(
    sprintf(paste0("Under RSL it applies only to the crawlers that select ",
                   "the group on line %d (%s)."), first[[at]], listed),
    if (has_global) {
      paste0(" For them it replaces the License lines before the first ",
             "User-agent line.")
    } else {
      paste0(" Crawlers outside that group find no License in this file ",
             "unless their own group has one; a License line before the ",
             "first User-agent line applies to every crawler.")
    }
  )
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
#   written, or nothing; ROBO-zvhrayhx) and `name` (the value as written,
#   ASCII-safe as `raw_text` renders it, for messages that name the agent:
#   the cut token is Google's reading only, ROBO-txnzyugl) and `uncut` (the
#   merge key of a matcher that compares the whole value: `key`, except on
#   a cut line, where it is the full value folded to ASCII lower case,
#   written as `#` and hex bytes; ROBO-qwfoyouo) and `value` (the value as
#   the parser kept it, its bytes unchanged, less a character the line
#   buffer split when the value reaches the buffer, which needs `raw_lines`,
#   the document's lines by number; read for look-alike characters,
#   ROBO-wtixhwlo).
# - `rules`: one row per Allow or Disallow inside a group (rules before the
#   first User-agent are dropped): `group`, `line`, `type` ("allow" or
#   "disallow"), `value` (canonical, as parsed), `empty` and `key` (type and
#   value with a trailing `*` run removed, `/` for a value of only `*` or
#   `/` then only `*`, NA when `empty`).
validation_groups <- function(parsed, raw_lines = NULL) {
  kept <- parsed[parsed$type %in% c("user-agent", "allow", "disallow"),
                 intersect(c("line", "type", "value", "line_too_long",
                             "missing_colon"), names(parsed)), drop = FALSE]
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
    name = vapply(agent_bytes, render_validation_line, ""),
    stringsAsFactors = FALSE
  )
  agents$uncut <- validation_uncut_keys(agent_bytes, agents$key,
                                        agents$cut)
  agents$value <- lookalike_agent_values(agent_rows, agent_bytes, raw_lines)

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

# The merge key of each User-agent line for a matcher that compares the
# whole value (ROBO-qwfoyouo): `key` where Google's matcher reads the value
# whole (and "" for a global line), else the full value with ASCII upper
# case folded, as `#` and hex bytes, also where Google reads no token
# (`1bot`). The hex form is exact for any byte, where `name` renders the
# text `\xE9` and the byte 0xE9 alike, and `#` keeps it apart from every
# token key.
validation_uncut_keys <- function(agent_bytes, key, cut) {
  uncut <- key
  uncut[cut] <- vapply(agent_bytes[cut], function(bytes) {
    upper <- bytes >= as.raw(0x41) & bytes <= as.raw(0x5a)
    bytes[upper] <- as.raw(as.integer(bytes[upper]) + 32L)
    paste0("#", paste(as.character(bytes), collapse = ""))
  }, "")
  uncut
}

# The robots.txt tokens Google documents for its crawlers
# (design/engine-profiles.md, "What Google documents"): the tokens of
# google_crawler_tokens_v1(), their parents, and the two crawlers whose
# group selection is the plain matcher's.
validation_google_tokens <- function() {
  table <- google_crawler_tokens_v1()
  unique(c(table$crawler_token, stats::na.omit(table$parent_token),
           "Storebot-Google", "Google-Extended"))
}

# One user_agent_cut row per cut User-agent line (ROBO-zvhrayhx), as
# ai_training_rows(). The message names the token Google's matcher reads
# (ASCII; `raw_text` carries the value) and states the effect: the written
# value no longer matches its record there, so a crawler going by it gets
# another group naming it, else `*`, else no rules (`has_global` says which;
# in a group in `global_groups` it still gets that group).
# Only Google's parser cuts, and a Google crawler goes only by its own
# tokens, so the row is a warning only when the token read is a documented
# Google token and the rest of the value is neither a version suffix (`/2.1`,
# ` 1.0`) nor a run of `*`: `Googlebot Image` is read as `Googlebot`, and
# Googlebot follows the group. A value holding a look-alike character is a
# warning too (ROBO-wtixhwlo). Every other cut is info (ROBO-txnzyugl, owner
# decision 2026-11-18).
user_agent_cut_rows <- function(agents, has_global, global_groups) {
  agents <- agents[agents$cut, , drop = FALSE]
  if (nrow(agents) == 0L) {
    return(ai_training_rows())
  }
  token <- agents$token
  rest <- substring(agents$name, nchar(token, "bytes") + 1L)
  google <- nzchar(token) &
    agents$key %in% ascii_lower(validation_google_tokens())
  # Meant: a run of `*` (`Mediapartners-Google*`, `Googlebot *`), or after a
  # space or `/`, a version (`/2.1`, ` 1.0`), a comment (` (+http://...)`)
  # or nothing (`Googlebot/`).
  meant <- grepl("^([ /]|\\\\t)*\\*+$", rest) |
    grepl("^([ /]|\\\\t)+([vV]?[0-9]+(\\.[0-9]+)*($|[^A-Za-z0-9])|\\(|$)",
          rest)
  read_as <- ifelse(
    nzchar(token),
    sprintf(paste0(
      "User-agent value is read as '%s' by Google's matcher, which stops at ",
      "the first character outside letters, '_' and '-'. There the full ",
      "written value does not match this record, and a crawler whose token ",
      "is '%s' matches it instead."
    ), token, token),
    paste0("User-agent value names no crawler for Google's matcher, which ",
           "reads a product token only from a leading run of letters, '_' ",
           "and '-', so there this line matches no crawler.")
  )
  fallback <- if (has_global) {
    paste0("Unless another group names it, a crawler going by the full ",
           "value gets the `User-agent: *` group from Google's matcher.")
  } else {
    paste0("Unless another group names it, a crawler going by the full ",
           "value gets no rules from Google's matcher: the file has no ",
           "`User-agent: *` group.")
  }
  # In a group that is itself `*`, such a crawler still gets this group.
  fallback <- rep(fallback, nrow(agents))
  fallback[agents$group %in% global_groups] <- paste0(
    "Unless another group names it, a crawler going by the full value ",
    "still gets this group from Google's matcher, since the group also ",
    "names `User-agent: *`."
  )
  warn <- google & !meant
  effect <- rep(paste0("Only Google's parser shortens the value, and ",
                       "Google's crawlers do not go by it, so nothing ",
                       "changes for them; how the named crawler's own ",
                       "parser reads it is unknown."), length(token))
  effect[google] <- sprintf(paste0("'%s' is the Google crawler token the ",
                                   "value names, so nothing changes for ",
                                   "that crawler."), token[google])
  effect[warn] <- sprintf(paste0("'%s' is a Google crawler token, so that ",
                                 "Google crawler follows this group."),
                          token[warn])
  message <- paste(read_as, fallback, effect)
  lookalike <- user_agent_lookalike_notes(agents$value)
  message[nzchar(lookalike)] <- paste(message[nzchar(lookalike)],
                                      lookalike[nzchar(lookalike)])
  # A value holding a look-alike is matched by no byte compare, so its row
  # is a warning whatever the token (ROBO-wtixhwlo, maintainer decision).
  warn <- warn | nzchar(lookalike)
  ai_training_rows(agents$line, ifelse(warn, "warning", "info"),
                   "user_agent_cut", "user-agent", message)
}

# One key per grouped Allow or Disallow of a parsed document (ROBO-ctdkqawi):
# its line, its type and the sorted crawler keys of its group (`*` for a
# global User-agent line). The value is left out, so a rule whose value
# alone differs between two reads of the same bytes keeps its key.
validation_rule_keys <- function(parsed) {
  groups <- validation_groups(parsed)
  agents <- groups$agents
  agent_key <- ifelse(agents$global, "*", agents$key)
  group_agents <- vapply(split(agent_key, agents$group), function(keys) {
    paste(sort(unique(keys)), collapse = " ")
  }, character(1L))
  rules <- groups$rules
  paste(rules$line, rules$type,
        group_agents[as.character(rules$group)])
}

# TRUE when a line the parser reads as an empty rule of `type` holds a value
# once its NUL bytes are dropped: the NUL right after the colon ended the line
# before the path, which neither the parser nor Google's matcher reads
# (ROBO-nrnucnru, ROBO-pvqrfvol). `nul_free_line` is the line's bytes without
# NULs (`nul_free_lines[[line]]`), parsed alone.
nul_hidden_rule <- function(nul_free_line, type) {
  parsed <- robotstxtr_validation_parse_(c(nul_free_line, as.raw(0x0a)))
  identical(parsed$type[[1L]], type) && nzchar(parsed$value[[1L]])
}

# The AI-training policy token of draft-kelley-aipref-training-preference-
# signal-00 (an Internet-Draft, 2026-10-30; ROBO-kzyfejcv), cited by name.
ai_training_token <- "__usage_ai-training"
ai_training_draft <- "draft-kelley-aipref-training-preference-signal-00"

# The four AI-training checks over a document's groups (ROBO-kzyfejcv), as a
# data frame of `line`, `severity`, `code`, `directive` and `message`, in
# line order. The draft matches the token exactly, apart from ASCII case, so
# a User-agent line names it when its whole (trimmed) value is the token: its
# token spells the value whole (`cut` is FALSE) and its key is the token.
# - ai_training_token_near_miss: a line whose token, with `_` and `-`
#   removed, is `usageaitraining` but which does not name the token exactly
#   (`__usage_ai_training`, `__usage_ai-training/1.0`).
# - ai_training_token_stacked: a policy-token line (a `__usage_` key, the
#   token or a near miss) in a group that also names `*`, or a crawler or
#   another policy token (not the same class) with a directive line between
#   the two. Parsers that join User-agent lines no rule separates give the
#   group's rules to those crawlers too. Blank and comment lines are RFC 9309
#   emptylines and the draft lets a group mix tokens, so consecutive or
#   comment-headed User-agent lines stay silent.
# - ai_training_group_extra_line: a directive other than Allow, Disallow or
#   User-agent, and not file-level (Sitemap, Host, Clean-param), in a group
#   that names only the token: before its last rule, or anywhere in the
#   file's last group. A line after the last rule of an earlier group may
#   head the next group, so it is not counted.
# - ai_training_preference: one info per group naming the token, on its first
#   such line, listing the group's own rules; `*` rules are never merged in.
#   `truncated` adds that lines past a `max_bytes` cut were not read.
# Like the other group checks, it reads Google's lines on a body with a NUL.
ai_training_diagnostics <- function(groups, parsed, truncated = FALSE) {
  agents <- groups$agents
  kind <- ai_training_kind(agents)
  exact <- kind$exact
  near <- kind$near
  family <- kind$family
  class <- ifelse(exact | near, "usageaitraining", agents$key)
  found <- list(
    ai_training_near_miss_rows(agents, near, exact),
    ai_training_stacked_rows(agents, parsed, family, class),
    ai_training_extra_line_rows(groups, parsed, exact, truncated),
    ai_training_preference_rows(groups, exact, truncated)
  )
  found <- do.call(rbind, c(list(ai_training_rows()), found))
  found[order(found$line), , drop = FALSE]
}

# Which agent lines name the policy token exactly, a near miss of it, or any
# policy token (a `__usage_` key, the token or a near miss).
ai_training_kind <- function(agents) {
  exact <- !agents$cut & agents$key == ai_training_token
  near <- !exact & gsub("[_-]", "", agents$key) == "usageaitraining"
  list(exact = exact, near = near,
       family = exact | near | startsWith(agents$key, "__usage_"))
}

ai_training_rows <- function(line = integer(), severity = character(),
                             code = character(), directive = character(),
                             message = character()) {
  data.frame(line = as.integer(line), severity = severity, code = code,
             directive = directive, message = message,
             stringsAsFactors = FALSE)
}

# An agent name as the ai_training_ messages render it: elided past `max`
# characters (its first `max - 4` and "..."), so a message stays bounded
# however long a User-agent value is.
ai_training_name <- function(name, max = 64L) {
  long <- nchar(name, "bytes") > max
  name[long] <- paste0(substr(name[long], 1L, max - 4L), "...")
  name
}

# The message names the token read (ASCII) only; `raw_text` carries the
# value, which may not be valid UTF-8. When the group also names the exact
# token, that line carries the preference, and the message says so.
ai_training_near_miss_rows <- function(agents, near, exact) {
  token_line <- agents$line[exact][match(agents$group[near],
                                         agents$group[exact])]
  near <- agents[near, , drop = FALSE]
  read_as_token <- near$key == ai_training_token
  token <- ai_training_name(ai_training_token)
  message <- sprintf(
    paste0("User-agent value is not the AI-training policy token `%s`, ",
           "which matches only exactly, apart from ASCII case (%s, an ",
           "Internet-Draft), so %s"),
    token, ai_training_draft,
    ifelse(is.na(token_line), "this group states no AI-training preference.",
           sprintf(paste0("this line names no policy token; the group's ",
                          "`User-agent: %s` line (line %d) carries the ",
                          "preference."), token, token_line))
  )
  message[read_as_token] <- paste(
    message[read_as_token],
    sprintf("Google's matcher still reads it as `%s`.", token)
  )
  ai_training_rows(near$line, rep("warning", nrow(near)),
                   rep("ai_training_token_near_miss", nrow(near)),
                   rep("user-agent", nrow(near)), message)
}

# Linear in the agent lines. `segment` counts the directive lines (other than
# User-agent) up to each agent line, so two agent lines have a directive
# between them exactly when their segments differ; two groups always do (a
# rule line ends a group). Agent rows are in file order, so segments never
# decrease along them, and findInterval() finds for each policy-token line
# the nearest candidate before it in an earlier segment and after it in a
# later one. A candidate of the token line's own class (the same key; the
# token and its near misses are one class) is skipped by jumping to the end
# of its run of same-class candidates. Candidates in another group are
# dropped. A `*` line in the group is named first, one in the token line's
# segment (nothing but blank or comment lines between) before any other.
# Bing ends a group at any directive (`design/engine-disagreements.md`
# class 1), so it joins the lines only when the two share a segment.
ai_training_stacked_rows <- function(agents, parsed, family, class) {
  token_rows <- which(family)
  if (length(token_rows) == 0L) {
    return(ai_training_rows())
  }
  breaks <- parsed$line[parsed$has_directive & parsed$type != "user-agent"]
  segment <- findInterval(agents$line, breaks)
  group <- agents$group[token_rows]
  token_class <- class[token_rows]

  candidates <- which(!agents$global & nzchar(agents$key))
  n <- length(candidates)
  candidate_class <- class[candidates]
  run <- if (n == 0L) {
    integer()
  } else {
    cumsum(c(TRUE, candidate_class[-1L] != candidate_class[-n]))
  }
  run_before <- match(run, run) - 1L
  run_before[run_before == 0L] <- NA_integer_
  run_after <- n + 2L - match(run, rev(run))
  run_after[run_after > n] <- NA_integer_
  at <- segment[candidates]
  before <- findInterval(segment[token_rows], at, left.open = TRUE)
  before[before == 0L] <- NA_integer_
  same <- !is.na(before) & candidate_class[before] == token_class
  before[same] <- run_before[before[same]]
  after <- findInterval(segment[token_rows], at) + 1L
  after[after > n] <- NA_integer_
  same <- !is.na(after) & candidate_class[after] == token_class
  after[same] <- run_after[after[same]]
  before <- candidates[before]
  after <- candidates[after]
  before[!is.na(before) & agents$group[before] != group] <- NA_integer_
  after[!is.na(after) & agents$group[after] != group] <- NA_integer_
  distance <- function(rows) abs(agents$line[rows] - agents$line[token_rows])
  nearest <- ifelse(
    is.na(after) | (!is.na(before) & distance(before) <= distance(after)),
    before, after
  )

  global_rows <- which(agents$global)
  star_joined <- global_rows[match(segment[token_rows], segment[global_rows])]
  star_joined[!is.na(star_joined) &
                agents$group[star_joined] != group] <- NA_integer_
  star <- global_rows[match(group, agents$group[global_rows])]
  star[!is.na(star_joined)] <- star_joined[!is.na(star_joined)]
  other <- ifelse(is.na(star), nearest, star)
  fire <- !is.na(other)
  token_rows <- token_rows[fire]
  other <- other[fire]
  joined <- !is.na(star_joined[fire])
  star <- !is.na(star[fire])
  named <- ifelse(star, "*", ai_training_name(agents$name[other]))
  message <- sprintf(
    paste0("`User-agent: %s` shares a group with `User-agent: %s` (line ",
           "%d): Google's and Yandex's parsers join User-agent lines that no ",
           "Allow or Disallow line separates, so this group's rules also ",
           "apply to %s. %s Give the policy token a separate group, after a ",
           "group that ends in an Allow or Disallow line."),
    ai_training_name(agents$name[token_rows]), named, agents$line[other],
    ifelse(star, "every crawler no group names", named),
    ifelse(joined, "Bing's parser joins them too.",
           paste("Bing's parser ends the group at the directive line",
                 "between the two."))
  )
  # A crawler whose value Google's matcher cuts (ROBO-zqyqbudf); `*` and
  # another policy token are no such crawler.
  cut <- which(!star & agents$cut[other] & !family[other])
  message[cut] <- paste0(message[cut], vapply(cut, function(j) {
    cut_agent_note(agents$name[[other[[j]]]], agents$line[[other[[j]]]])
  }, ""))
  ai_training_rows(agents$line[token_rows], rep("warning", length(token_rows)),
                   rep("ai_training_token_stacked", length(token_rows)),
                   rep("user-agent", length(token_rows)), message)
}

# A group's span starts at its first User-agent line. A line after the
# group's last rule may head the next group, so it counts only in the last
# group, where nothing follows. A User-agent line naming no crawler (empty,
# or led by a byte outside [A-Za-z_-]) or one Google reads as the token
# (`__usage_ai-training/1.0`) does not make the group mixed.
ai_training_extra_line_rows <- function(groups, parsed, exact,
                                        truncated = FALSE) {
  agents <- groups$agents
  rules <- groups$rules
  group_ids <- groups$groups$group
  mixed <- (agents$global | nzchar(agents$key)) &
    agents$key != ai_training_token
  token_only <- group_ids %in% agents$group[exact] &
    !group_ids %in% agents$group[mixed]
  if (!any(token_only)) {
    return(ai_training_rows())
  }
  last <- !duplicated(rules$group, fromLast = TRUE)
  last_rule <- rules$line[last][match(group_ids, rules$group[last])]
  # Before a `max_bytes` cut, the last group read is not the file's last.
  final <- !truncated & seq_along(group_ids) == length(group_ids)
  lines <- parsed[parsed$has_directive & !parsed$type %in% c(
    "user-agent", "allow", "disallow", "sitemap"
  ), c("line", "type", "action"), drop = FALSE]
  span <- findInterval(lines$line, groups$groups$first_line)
  inside <- span > 0L
  lines <- lines[inside, , drop = FALSE]
  span <- span[inside]
  keep <- token_only[span] & (final[span] |
    (!is.na(last_rule[span]) & lines$line < last_rule[span]))
  lines <- lines[keep, , drop = FALSE]
  directive <- vapply(seq_len(nrow(lines)), function(i) {
    validation_ascii_action(lines$action[[i]], lines$type[[i]])
  }, "")
  file_level <- directive %in% c("host", "clean-param")
  lines <- lines[!file_level, , drop = FALSE]
  directive <- directive[!file_level]
  message <- sprintf(
    paste0("Line has no defined meaning in a group that names only the ",
           "AI-training policy token `%s`: %s (an Internet-Draft) adds no ",
           "directive and keeps RFC 9309's group structure, so only Allow ",
           "and Disallow state the preference."),
    ai_training_name(ai_training_token), ai_training_draft
  )
  ai_training_rows(lines$line, rep("warning", nrow(lines)),
                   rep("ai_training_group_extra_line", nrow(lines)),
                   directive, rep(message, nrow(lines)))
}

# Linear in the rules: they are split by group once, and at most `cap` per
# group are rendered.
ai_training_preference_rows <- function(groups, exact, truncated,
                                        cap = 10L) {
  agents <- groups$agents[exact, , drop = FALSE]
  agents <- agents[!duplicated(agents$group), , drop = FALSE]
  rules <- groups$rules
  by_group <- split(seq_len(nrow(rules)),
                    factor(rules$group, levels = unique(agents$group)))
  listed <- vapply(by_group, function(rows) {
    k <- length(rows)
    if (k == 0L) {
      return("This group has no Allow or Disallow rule.")
    }
    shown <- rows[seq_len(min(k, cap))]
    allow <- rules$type[shown] == "allow"
    value <- vapply(rules$value[shown], function(value) {
      render_validation_line(charToRaw(value))
    }, "", USE.NAMES = FALSE)
    value[!nzchar(value)] <- ifelse(allow[!nzchar(value)],
                                    "(empty; ignored)",
                                    "(empty; no restriction)")
    items <- sprintf("%s: %s (line %d)",
                     ifelse(allow, "Allow", "Disallow"), value,
                     rules$line[shown])
    sprintf("This group's rules: %s%s.", toString(items),
            if (k > cap) sprintf(", and %d more", k - cap) else "")
  }, "", USE.NAMES = FALSE)
  message <- sprintf(
    paste0("`User-agent: %s` states an AI-training preference (%s, an ",
           "Internet-Draft): a disallowed path is a preference against ",
           "training on it, an allowed one a preference for it. %s ",
           "`User-agent: *` rules never apply to the token."),
    rep(ai_training_name(ai_training_token), nrow(agents)),
    ai_training_draft, listed
  )
  if (truncated && length(message) > 0L) {
    message <- paste(message,
                     "Lines past the max_bytes cut were not read.")
  }
  ai_training_rows(agents$line, rep("info", nrow(agents)),
                   rep("ai_training_preference", nrow(agents)),
                   rep("user-agent", nrow(agents)), message)
}

# User-agent lines joined into one group across a non-rule line
# (ROBO-xepnhfgs), as a data frame like ai_training_rows(). Google's parser
# starts a new group only after an Allow or Disallow line (src/robots.cc,
# HandleUserAgent and seen_separator_), so each User-agent line of a group
# but the first joins the agents before it. Consecutive lines are the
# deliberate way to share rules and stay silent; a break between two agent
# lines of one group is reported on the later line:
# - user_agent_joined_across_directive (warning): a directive sits between
#   them. Bing ends the run at any directive (design/engine-disagreements.md
#   class 1). Yandex ends it at a blank, comment or Crawl-delay line
#   (tester Y5, ROBO-bpywsjwv), and is named only when one of those lies
#   between: its reading of a Sitemap or unknown field is untested
#   (ROBO-traxexwm).
# - user_agent_joined_across_blank (info): only blank or comment lines sit
#   between. Google and Bing join; Yandex splits (Y5).
# Policy-token lines are left to ai_training_token_stacked (one line, one
# report), and never count as earlier agents. A line naming no crawler, a
# line whose only earlier agents share its name and a group with no rule (or
# only empty ones) draw nothing. Linear in the lines: each message names at
# most five agents and three directive lines, and counts the rest.
joined_user_agent_diagnostics <- function(groups, parsed, cap = 5L) {
  agents <- groups$agents
  rules <- groups$rules
  n <- nrow(agents)
  if (n < 2L || nrow(rules) == 0L) {
    return(ai_training_rows())
  }
  family <- ai_training_kind(agents)$family
  names_crawler <- (agents$global | nzchar(agents$key)) & !family
  id <- ifelse(agents$global, "*", agents$key)
  # The line of each crawler whose value Google's matcher cuts, for the
  # sentence a row naming it adds (ROBO-zqyqbudf); NA otherwise. A value
  # Google reads no token from (`1bot`, `*bot`) names no crawler there, as
  # its user_agent_cut row says, so it is not one.
  agents$cut_line <- ifelse(agents$cut & nzchar(agents$key) & !family,
                            agents$line, NA_integer_)

  last_line <- max(parsed$line, agents$line)
  is_directive <- logical(last_line)
  is_directive[parsed$line[parsed$has_directive &
                             parsed$type != "user-agent"]] <- TRUE
  is_blank <- logical(last_line)
  is_blank[parsed$line[parsed$is_empty | parsed$is_comment]] <- TRUE
  action <- ifelse(parsed$type == "unknown",
                   ascii_lower(ifelse(Encoding(parsed$action) == "bytes", "",
                                      parsed$action)),
                   parsed$type)
  ends_yandex <- is_blank
  ends_yandex[parsed$line[parsed$has_directive &
                            action == "crawl-delay"]] <- TRUE
  # next_*[l]: the first such line after line l, NA when none; so each
  # report finds its lines without scanning the file.
  next_after <- function(flags) {
    at <- ifelse(flags, seq_along(flags), NA_integer_)
    nxt <- rev(cummin(rev(ifelse(is.na(at), .Machine$integer.max, at))))
    nxt <- c(nxt[-1L], .Machine$integer.max)
    nxt[nxt == .Machine$integer.max] <- NA_integer_
    nxt
  }
  lines <- list(
    next_directive = next_after(is_directive),
    next_yandex = next_after(ends_yandex),
    row_of = match(seq_len(last_line), parsed$line)
  )
  blank_count <- cumsum(is_blank)
  # Directives that belong to a group, not the file: moving one out of the
  # run would change its meaning.
  group_level <- is_directive
  group_level[parsed$line[action %in% c("sitemap", "host", "clean-param")]] <-
    FALSE
  group_count <- cumsum(group_level)
  directive_count <- cumsum(is_directive)
  group_first_rule <- integer(max(agents$group))
  group_first_rule[rev(rules$group)] <- rev(rules$line)

  # The rule summary of each group, once.
  by_group <- split(seq_len(nrow(rules)), rules$group)
  rule_text <- vapply(by_group, function(rows) {
    # Empty values restrict nothing, so sharing them changes nothing.
    if (all(rules$empty[rows])) {
      return(NA_character_)
    }
    joined_rule_lines(rules$line[rows])
  }, "")
  block_text <- vapply(by_group, function(rows) {
    root <- rows[!is.na(rules$key[rows]) & rules$key[rows] == "disallow /"]
    allows <- rules$type[rows] == "allow" & !rules$empty[rows]
    if (length(root) == 0L || any(allows)) {
      return("")
    }
    sprintf(", including a full block (`Disallow: %s`, line %d)",
            render_validation_line(charToRaw(rules$value[[root[[1L]]]])),
            rules$line[[root[[1L]]]])
  }, "")

  # Indexed by group number; NA for a group with no rule, or none that
  # restricts anything.
  group_rules <- rep(NA_character_, max(agents$group))
  group_rules[as.integer(names(by_group))] <- rule_text
  group_block <- character(max(agents$group))
  group_block[as.integer(names(by_group))] <- block_text

  # Two trackers of the distinct agents named so far: in the group (Google's
  # reading, for the warning) and since its last directive break (the run
  # Bing still joins, for the info). An agent is seen in a span when
  # seen_*[its id] is the span's number, so no reset is needed; `firsts_*`
  # keeps the first cap + 1 distinct agents, enough to name `cap` besides
  # the joined one.
  # Plain vectors, not a list: assigning into a vector held in a list (or
  # passed to a function) would copy it on every agent line.
  id_index <- match(id, unique(id))
  seen_group <- integer(max(id_index))
  seen_run <- integer(max(id_index))
  span_group <- 0L
  span_run <- 0L
  firsts_group <- integer()
  firsts_run <- integer()
  distinct_group <- 0L
  distinct_run <- 0L
  out <- list()
  for (i in seq_len(n)) {
    g <- agents$group[[i]]
    k <- id_index[[i]]
    if (i == 1L || agents$group[[i - 1L]] != g) {
      span_group <- span_group + 1L
      firsts_group <- integer()
      distinct_group <- 0L
      span_run <- span_run + 1L
      firsts_run <- integer()
      distinct_run <- 0L
      group_start <- i
    } else {
      prev <- agents$line[[i - 1L]]
      cur <- agents$line[[i]]
      span <- cur - prev - 1L
      directives <- directive_count[[cur]] - directive_count[[prev]]
      blanks <- blank_count[[cur]] - blank_count[[prev]]
      kind <- if (directives > 0L) {
        "directive"
      } else if (span > 0L && blanks == span &&
                   group_first_rule[[g]] > 0L &&
                   directive_count[[group_first_rule[[g]] - 1L]] ==
                     directive_count[[cur]]) {
        # A directive later in the run ends this part of it for Bing; that
        # break's warning names these agents.
        "blank"
      } else {
        NA_character_
      }
      if (!is.na(kind) && names_crawler[[i]] && !is.na(group_rules[[g]])) {
        if (identical(kind, "directive")) {
          own_seen <- seen_group[[k]] == span_group
          earlier <- firsts_group
          total <- distinct_group - own_seen
        } else {
          own_seen <- seen_run[[k]] == span_run
          earlier <- firsts_run
          total <- distinct_run - own_seen
        }
        earlier <- earlier[id_index[earlier] != k]
        shown <- min(cap, length(earlier))
        if (total > 0L) {
          out[[length(out) + 1L]] <- joined_user_agent_row(
            kind, agents, i, group_start, earlier[seq_len(shown)],
            total - shown, prev, cur, directives,
            group_count[[cur]] == group_count[[prev]], lines, parsed, action,
            group_rules[[g]], group_block[[g]]
          )
        }
      }
      if (identical(kind, "directive")) {
        span_run <- span_run + 1L
        firsts_run <- integer()
        distinct_run <- 0L
      }
    }
    if (names_crawler[[i]]) {
      if (seen_group[[k]] != span_group) {
        seen_group[[k]] <- span_group
        distinct_group <- distinct_group + 1L
        if (length(firsts_group) <= cap) firsts_group <- c(firsts_group, i)
      }
      if (seen_run[[k]] != span_run) {
        seen_run[[k]] <- span_run
        distinct_run <- distinct_run + 1L
        if (length(firsts_run) <= cap) firsts_run <- c(firsts_run, i)
      }
    }
  }
  if (length(out) == 0L) {
    return(ai_training_rows())
  }
  ai_training_rows(
    vapply(out, `[[`, 0L, "line"), vapply(out, `[[`, "", "severity"),
    vapply(out, `[[`, "", "code"), "user-agent",
    vapply(out, `[[`, "", "message")
  )
}

# A crawler named in a later group as well as an earlier one
# (ROBO-vnhirero): Google merges every group that names it (src/robots.cc;
# RFC 9309 section 2.2.1), and so do Bing (tester, bing-corpus
# `body-sel-bingbot-repeated-tier`) and Yandex (tester, ydx-02). A token is
# `*` for a global line and the merge key otherwise; groups are Google's, so
# a line joined into a group (ROBO-xepnhfgs) counts there. One info per
# later group and token, on the first line of that group naming it, listing
# the first line naming it in each earlier group (five at most, then a
# count). A later group with no rule line draws nothing. Policy-token lines
# are left to ai_training_token_stacked, and a line in `skip` (one a join,
# cut or inheritance report already owns) draws nothing but still counts for
# later groups: one line, one report.
repeated_group_diagnostics <- function(groups, skip = integer(), cap = 5L) {
  agents <- groups$agents
  if (nrow(agents) < 2L) {
    return(ai_training_rows())
  }
  family <- ai_training_kind(agents)$family
  keep <- (agents$global | nzchar(agents$key)) & !family
  id <- ifelse(agents$global, "*", agents$key)[keep]
  line <- agents$line[keep]
  group <- agents$group[keep]
  token <- agents$name[keep]
  global <- agents$global[keep]
  # The crawler a row names is its written value the token spells whole,
  # when one exists (ROBO-txnzyugl).
  written <- written_agent_names(id, token, agents$cut[keep])
  first <- !duplicated(paste(id, group, sep = "\n"))
  id <- id[first]
  line <- line[first]
  group <- group[first]
  token <- token[first]
  global <- global[first]
  # Rows are in file order, so a token's rows come in group order. A later
  # group with no rule line adds no rules, so it is not reported.
  rank <- stats::ave(seq_along(id), id, FUN = seq_along)
  later <- which(rank > 1L & !line %in% skip & group %in% groups$rules$group)
  if (length(later) == 0L) {
    return(ai_training_rows())
  }
  by_id <- split(seq_along(id), id)
  message <- vapply(later, function(i) {
    earlier <- by_id[[id[[i]]]]
    earlier <- earlier[seq_len(rank[[i]] - 1L)]
    shown <- line[earlier[seq_len(min(cap, length(earlier)))]]
    more <- length(earlier) - length(shown)
    several <- length(earlier) > 1L
    named <- if (global[[i]]) {
      "every crawler without a group of its own"
    } else {
      ai_training_name(written[[id[[i]]]][[1L]])
    }
    follows <- if (global[[i]]) {
      "those crawlers follow"
    } else {
      paste(named, "follows")
    }
    sprintf(
      paste0("`User-agent: %s` (line %d) names %s, as %s %s in %s already ",
             "%s. Google, Bing and Yandex merge every group that names the ",
             "same crawler, so %s the rules of %s together. If the groups ",
             "came from separate blocks, put their rules in one group."),
      if (global[[i]]) "*" else ai_training_name(token[[i]]), line[[i]],
      named, if (several) "lines" else "line",
      joined_and(as.character(shown), more),
      if (several) "earlier groups" else "an earlier group",
      if (several) "do" else "does", follows,
      if (several) "all these groups" else "both groups"
    )
  }, "")
  ai_training_rows(line[later], "info", "user_agent_repeated_group",
                   "user-agent", message)
}

# A User-agent line that repeats a name already in its own group
# (ROBO-wnuttuit). RFC 9309 section 2.2.1 matches a product token
# case-insensitively, so the group names the same crawler with or without the
# line, and the line can be deleted. The blank, comment, Crawl-delay and
# unknown-field shapes between the two names were probed on the Bing and
# Yandex testers (2026-11-21) and change no probed decision. The name compared
# is the value as written, folded to ASCII lowercase, and `*` for a global
# line; a cut value keeps its full text, so `Foo Bot` and `foo` stay apart
# (ROBO-txnzyugl). Policy-token lines are dropped here and left to
# ai_training_*. A line in `skip` draws nothing but still counts as an earlier
# name; a group with no rule line draws nothing, as in
# repeated_group_diagnostics(). One info per repeated line, naming the first
# line of its group with the same name.
user_agent_duplicate_in_group_diagnostics <- function(groups,
                                                      skip = integer()) {
  agents <- groups$agents
  family <- ai_training_kind(agents)$family
  keep <- (agents$global | nzchar(agents$key)) & !family
  agents <- agents[keep, , drop = FALSE]
  folded <- ifelse(agents$global, "*", ascii_lower(agents$name))
  pair <- paste(agents$group, folded, sep = "\n")
  first <- match(pair, pair)
  repeated <- which(first < seq_along(pair))
  repeated <- repeated[!agents$line[repeated] %in% skip &
                         agents$group[repeated] %in% groups$rules$group]
  if (length(repeated) == 0L) {
    return(ai_training_rows())
  }
  message <- sprintf(
    paste0("`User-agent: %s` (line %d) repeats `User-agent: %s` (line %d) ",
           "in the same group. Product tokens match case-insensitively (RFC ",
           "9309 section 2.2.1), so the group names the same crawler with or ",
           "without this line, and the line can be deleted."),
    ai_training_name(agents$name[repeated]), agents$line[repeated],
    ai_training_name(agents$name[first[repeated]]),
    agents$line[first[repeated]]
  )
  ai_training_rows(agents$line[repeated], rep("info", length(repeated)),
                   "user_agent_duplicate_in_group", "user-agent", message)
}

# An empty `Disallow:` and a full block in the rules one crawler follows
# (ROBO-vnhirero): Google ignores the empty value, and Bing does too
# (tester, bing-corpus `body-ea-bingbot-empty-disallow-before-rule`), so
# both block every path; Yandex reads it as allowing every path that no
# longer Disallow matches (tester, ydx-11). Tokens merge as in
# tied_disallow_diagnostics(), within one group or across groups. A full
# block is as in wildcard_inheritance_diagnostics(): a `disallow /` key and
# no non-empty Allow. An every-path Allow is no such split: every engine
# allows, and `Allow: /` is disallow_tied_by_allow's. One warning per
# full-block line, on the first one a token follows, naming every token
# whose first it is. Linear in the agent and rule lines: flags are summed
# per group, then per token. Returns a data frame of `line` and `message`.
empty_disallow_full_block_diagnostics <- function(groups, cap = 5L) {
  none <- data.frame(line = integer(), message = character(),
                     stringsAsFactors = FALSE)
  rules <- groups$rules
  agents <- groups$agents
  if (nrow(rules) == 0L || !any(rules$type == "disallow" & rules$empty)) {
    return(none)
  }
  family <- ai_training_kind(agents)$family
  keep <- (agents$global | nzchar(agents$key)) & !family
  pair <- data.frame(
    id = ifelse(agents$global, "*", agents$key)[keep],
    group = agents$group[keep],
    stringsAsFactors = FALSE
  )
  # Every value written for a crawler, as written (ROBO-txnzyugl), and the
  # cut lines behind them (ROBO-zqyqbudf; none for `*`, which is not cut).
  kept_name <- agents$name[keep]
  kept_line <- agents$line[keep]
  written <- written_agent_names(pair$id, kept_name, agents$cut[keep])
  cut_rows <- written_cut_rows(pair$id, agents$cut[keep])
  pair <- pair[!duplicated(paste(pair$id, pair$group, sep = "\n")), ,
               drop = FALSE]
  if (nrow(pair) == 0L) {
    return(none)
  }
  n_groups <- max(agents$group)
  is_empty <- rules$type == "disallow" & rules$empty
  is_root <- !is.na(rules$key) & rules$key == "disallow /"
  per_group <- function(flag) {
    tabulate(rules$group[flag], n_groups)[pair$group] > 0L
  }
  first_root <- rep(NA_integer_, n_groups)
  first_root[rev(rules$group[is_root])] <- rev(rules$line[is_root])
  per_id <- function(x) rowsum(as.integer(x), pair$id, reorder = FALSE)[, 1L]
  has_empty <- per_id(per_group(is_empty)) > 0L
  has_root <- per_id(per_group(is_root)) > 0L
  has_allow <- per_id(per_group(rules$type == "allow" & !rules$empty)) > 0L
  hit <- names(has_empty)[has_empty & has_root & !has_allow]
  if (length(hit) == 0L) {
    return(none)
  }
  # Every crawler a group names, before the pairs are cut to the hits.
  ids_of_group <- split(pair$id, pair$group)
  pair <- pair[pair$id %in% hit, , drop = FALSE]
  root_at <- first_root[pair$group]
  anchor <- vapply(split(root_at, pair$id), min, 0L, na.rm = TRUE)
  groups_of <- split(pair$group, pair$id)
  # A group's rule lines that a set's message names.
  lines_in <- function(flag, gs) sort(rules$line[flag & rules$group %in% gs])
  sets <- split(names(anchor), factor(anchor, sort(unique(anchor))))
  message <- vapply(sets, function(ids) {
    names <- unlist(lapply(ids, function(id) {
      if (id == "*") "*" else ai_training_name(written[[id]])
    }), use.names = FALSE)
    cut_at <- unlist(cut_rows[ids], use.names = FALSE)
    note <- cut_agent_note(kept_name[cut_at], kept_line[cut_at])
    global_only <- identical(names, "*")
    several <- global_only || length(names) > 1L
    crawlers <- if (global_only) {
      "every crawler without a group of its own"
    } else {
      shown <- names[seq_len(min(cap, length(names)))]
      shown[shown == "*"] <- "every crawler without a group of its own"
      joined_and(shown, length(names) - length(shown))
    }
    gs <- unique(unlist(groups_of[ids], use.names = FALSE))
    empties <- lines_in(is_empty, gs)
    roots <- lines_in(is_root, gs)
    at <- as.integer(anchor[[ids[[1L]]]])
    anchor_group <- rules$group[[match(at, rules$line)]]
    signature <- vapply(groups_of[ids], function(g) {
      paste(sort(rules$line[is_empty & rules$group %in% g]), collapse = " ")
    }, "")
    reach <- if (all(rules$group[rules$line %in% c(empties, roots)] ==
                       anchor_group)) {
      if (length(empties) == 1L) "is in the same group" else
        "are in the same group"
    } else if (length(unique(signature)) > 1L) {
      "each reach some of them through the group merge"
    } else {
      sprintf("%s %s through the group merge",
              if (length(empties) == 1L) "reaches" else "reach",
              if (global_only) "the same crawlers" else crawlers)
    }
    longer <- any(rules$type == "disallow" & !rules$empty & !is_root &
                    rules$group %in% gs)
    yandex <- if (longer) {
      "allowing every path that no longer `Disallow` matches"
    } else {
      "allowing every path and blocks nothing"
    }
    # Deleting a line is offered only when its group names no crawler
    # outside this report; otherwise it would change their rules too.
    only_these <- function(lines) {
      lg <- unique(rules$group[rules$line %in% lines])
      all(unlist(ids_of_group[as.character(lg)], use.names = FALSE) %in% ids)
    }
    advice <- function(lines) {
      if (only_these(lines)) {
        paste("delete", joined_rule_lines(lines))
      } else {
        sprintf(paste0("give %s a group of %s own without %s, which other ",
                       "crawlers share"),
                if (several) "them" else "it",
                if (several) "their" else "its", joined_rule_lines(lines))
      }
    }
    paste0(sprintf(
      paste0("`Disallow: %s` (line %d) blocks every path for %s, and the ",
             "empty `Disallow:` on %s %s. Google and Bing ignore an empty ",
             "`Disallow:` and block every path; Yandex reads it as %s. If ",
             "%s meant to be let in, %s; if %s meant to be kept out, %s."),
      ai_training_name(render_validation_line(charToRaw(
        rules$value[[match(at, rules$line)]]
      ))),
      at, crawlers, joined_rule_lines(empties), reach, yandex,
      if (several) "these crawlers are" else paste(names[[1L]], "is"),
      advice(roots), if (several) "they are" else "it is", advice(empties)
    ), note)
  }, "")
  data.frame(line = as.integer(names(sets)), message = unname(message),
             stringsAsFactors = FALSE)
}

# The lines of a group's rules for a message: up to five as written, with
# consecutive lines as a range, and more as a range plus a count.
joined_rule_lines <- function(lines, cap = 5L) {
  if (length(lines) > cap) {
    return(sprintf("lines %d-%d (%d rules)", min(lines), max(lines),
                   length(lines)))
  }
  run <- cumsum(c(TRUE, diff(lines) != 1L))
  parts <- vapply(split(lines, run), function(x) {
    if (length(x) == 1L) as.character(x) else sprintf("%d-%d", x[[1L]],
                                                       x[[length(x)]])
  }, "", USE.NAMES = FALSE)
  paste(if (length(lines) == 1L) "line" else "lines",
        joined_and(parts, 0L))
}

# "a", "a and b", "a, b and c", with "and k more" for a count left out.
joined_and <- function(items, more) {
  if (more > 0L) {
    items <- c(items, sprintf("%d more", more))
  }
  k <- length(items)
  if (k == 1L) {
    return(items)
  }
  paste(toString(items[-k]), "and", items[[k]])
}

# One report as list(line, severity, code, message). `n_directives` counts
# the directive lines between `prev` and `cur`; `lines` holds the next-line
# lookups of joined_user_agent_diagnostics().
joined_user_agent_row <- function(kind, agents, i, group_start, earlier, more,
                                  prev, cur, n_directives, file_level, lines,
                                  parsed, action, rule_text, block_text) {
  name <- function(rows) {
    ifelse(agents$global[rows], "*", ai_training_name(agents$name[rows]))
  }
  crawlers <- function(rows) {
    ifelse(agents$global[rows], "every crawler without a group of its own",
           ai_training_name(agents$name[rows]))
  }
  plural <- length(earlier) + more > 1L
  agent <- name(i)
  yandex <- lines$next_yandex[[prev]]
  if (!is.na(yandex) && yandex >= cur) {
    yandex <- NA_integer_
  }
  if (identical(kind, "blank")) {
    shared <- joined_and(
      sprintf("`User-agent: %s` (line %d)", name(earlier),
              agents$line[earlier]), more
    )
    short <- joined_and(
      ifelse(agents$global[earlier], "`*`", name(earlier)), more
    )
    message <- sprintf(
      paste0("`User-agent: %s` (line %d) shares a group with %s: only blank ",
             "or comment lines come between them, and a `User-agent` line ",
             "starts a new group only after an `Allow` or `Disallow` line. ",
             "Google and Bing read one group, so the rules on %s apply to ",
             "%s%s. Yandex ends a group at every blank or comment line, as ",
             "at line %d, and gives %s no rules. ",
             "If %s meant to share these rules, remove the blank or comment ",
             "lines; if not, give %s %s own rules before line %d."),
      agent, cur, shared, rule_text, if (plural) "all of them" else "both",
      block_text, yandex, short, if (plural) "they are all" else "both are",
      short, if (plural) "their" else "its", cur
    )
    named_rows <- c(i, earlier)
    message <- paste0(message, cut_agent_note(agents$name[named_rows],
                                              agents$cut_line[named_rows]))
    return(list(line = cur, severity = "info",
                code = "user_agent_joined_across_blank", message = message))
  }

  # The first three directive lines between; n_directives counts them all.
  between <- integer()
  at <- lines$next_directive[[prev]]
  while (length(between) < 3L && at < cur) {
    between <- c(between, at)
    at <- lines$next_directive[[at]]
    if (is.na(at)) break
  }
  rows <- lines$row_of[between]
  # A key not in printable ASCII is not quoted; `raw_text` carries it.
  key <- parsed$action[rows]
  unprintable <- Encoding(key) == "bytes" |
    !grepl("^[ -~]+$", key, useBytes = TRUE)
  key[unprintable] <- "unknown field"
  key[!unprintable] <- ai_training_name(key[!unprintable])
  key[parsed$type[rows] == "sitemap"] <- "Sitemap"
  more_lines <- n_directives - length(between)
  named <- joined_and(
    sprintf("the `%s` on line %d", key, between), more_lines
  )
  if (more_lines > 0L) {
    named <- paste(named, "lines")
  }
  verb <- if (n_directives == 1L) "does" else "do"
  first_line <- agents$line[[group_start]]
  gainers <- joined_and(crawlers(earlier), more)
  bing <- between[[1L]]
  engines <- if (is.na(yandex)) {
    sprintf("Bing ends the group at line %d, so it does not give", bing)
  } else if (yandex == prev + 1L && yandex == bing) {
    sprintf("Bing and Yandex end the group at line %d, so neither gives",
            bing)
  } else {
    sprintf("Bing ends the group at line %d, and Yandex %s line %d, so %s",
            bing, if (yandex == prev + 1L) "at" else "by", yandex,
            "neither gives")
  }
  ticks <- joined_and(sprintf("`%s`", name(earlier)), more)
  fix <- sprintf(
    paste0("end %s group before line %d with an empty `Disallow:` line, ",
           "which blocks nothing%s"),
    if (plural) "their" else "its", cur,
    if (file_level && i - group_start == 1L) {
      sprintf(", or delete line %d if it is there only to hold %s",
              first_line, if (n_directives == 1L) {
                sprintf("the `%s`", key)
              } else {
                "the lines after it"
              })
    } else {
      ""
    }
  )
  if (file_level) {
    moved <- if (n_directives == 1L) {
      sprintf("line %d", between)
    } else {
      paste("lines", joined_and(as.character(between), more_lines))
    }
    fix <- sprintf(paste0("%s; if %s meant to, move %s out from between the ",
                          "`User-agent` lines, so Bing reads one group too"),
                   fix, if (plural) "they were" else "it was", moved)
  }
  opener <- name(group_start)
  opener <- if (nzchar(opener)) {
    sprintf("`User-agent: %s` opened", opener)
  } else {
    "opened"
  }
  message <- sprintf(
    paste0("`User-agent: %s` (line %d) joins the group that ",
           "%s on line %d. For Google, a `User-agent` ",
           "line starts a new group only after an `Allow` or `Disallow` ",
           "line, and lines %d-%d have none; %s %s not end a group. So the ",
           "rules on %s apply to %s as well as to %s%s. %s these rules to ",
           "%s. If %s %s not meant to get these rules, %s."),
    agent, cur, opener, first_line, first_line, cur, named, verb,
    rule_text, gainers, crawlers(i), block_text, engines, gainers, ticks,
    if (plural) "were" else "was", fix
  )
  # The message names the opener as well, which may also be in `earlier`.
  named_rows <- unique(c(i, group_start, earlier))
  message <- paste0(message, cut_agent_note(agents$name[named_rows],
                                            agents$cut_line[named_rows]))
  list(line = cur, severity = "warning",
       code = "user_agent_joined_across_directive", message = message)
}

# A crawler obeys only the groups that name it (merged, as Google does) and
# never the `*` group (ROBO-gfjotdrr). For each named agent, the `*` rules
# missing from its effective rules, as a list of list(line, code, severity,
# agents, missing, message): `line` is the first User-agent line of the
# first group naming the agents, `code` wildcard_disallows_not_inherited
# (warning, lost `*` Disallows; ROBO-pbwijkdq) or
# wildcard_rules_not_inherited (info, the rest), `agents` their values as
# written, `missing` the lines of the rules the row reports (uncapped) and
# `message` the capped text. An agent whose rules are all explicit allow-all
# (an empty Disallow, or a `*` Allow matching every path) gets no info row,
# only the warning; an empty Allow is a no-op and is not
# counted, so an agent with no other rule is not exempt. A `*` Allow matching
# every path is never a missing rule (ROBO-gkuuwbgc): the named group's own
# rules are what the crawler follows. Rows come in anchor-line order: agents
# are visited in the order they are first named. A full block (ROBO-bwpacxtq)
# is a named agent whose merged groups disallow `/` (rule key `disallow /`,
# so a `$`-anchored value is not one) and hold no non-empty Allow; an empty
# Allow does not cancel it. Its lost `*` Disallows add nothing, so only its
# lost `*` Allows are listed.
wildcard_inheritance_diagnostics <- function(groups) {
  rules <- groups$rules
  # An empty key (a global line, or one led by a byte outside [A-Za-z_-])
  # names no crawler. The AI-training policy token is no crawler either, and
  # `*` never applies to it (ROBO-kzyfejcv): the key is what Google reads, so
  # `__usage_ai-training/1.0` is left out too.
  agents <- groups$agents[nzchar(groups$agents$key) &
                            groups$agents$key != ai_training_token, ,
                          drop = FALSE]
  # A `*` Allow matching every path is not compared, and the named side's
  # allow-all test uses the same vector (ROBO-gkuuwbgc). It is tested on the
  # value, not the key: the key drops a trailing `*` run, which would also
  # take `/*$*`, where a `$` before the end is literal. `/$` is not one.
  every_path <- rules$type == "allow" & wildcard_every_path(rules$value)
  global <- rules[!rules$empty & !every_path &
                    rules$group %in% groups$groups$group[groups$groups$global],
                  , drop = FALSE]
  global <- global[!duplicated(global$key), , drop = FALSE]
  no_op <- rules$type == "allow" & rules$empty
  allow_all <- (rules$type == "disallow" & rules$empty) |
    (!rules$empty & every_path)

  # Every value written for a crawler, as written (ROBO-txnzyugl), and the
  # cut lines behind them (ROBO-zqyqbudf). Both are in the order of `keys`,
  # so a crawler reads its own by position.
  keys <- unique(agents$key)
  written <- written_agent_names(agents$key, agents$name, agents$cut)
  cut_rows <- written_cut_rows(agents$key, agents$cut)
  # Crawlers that ignore `*` whether or not a group names them
  # (ROBO-fbbmvbob): a named group loosens nothing for them.
  table <- google_crawler_tokens_v1()
  exempt_keys <- ascii_lower(
    table$crawler_token[table$group_selection == "exact_only"]
  )
  losers <- lapply(seq_along(keys), function(k) {
    key <- keys[[k]]
    agent_groups <- unique(agents$group[agents$key == key])
    in_effect <- rules$group %in% agent_groups
    judged <- in_effect & !no_op
    root_block <- in_effect & !is.na(rules$key) & rules$key == "disallow /"
    list(
      names = written[[k]],
      cut_names = agents$name[cut_rows[[k]]],
      cut_lines = agents$line[cut_rows[[k]]],
      groups = agent_groups,
      first_group = min(agent_groups),
      one_group = length(agent_groups) == 1L,
      open = any(judged) && all(allow_all[judged]),
      allow_only = !any(in_effect & rules$type == "disallow" & !rules$empty),
      # An explicit grant: `Allow: /` (any every-path Allow) or an empty
      # `Disallow:`, and no other Disallow (owner decision, 2026-11-18).
      grant = !any(in_effect & rules$type == "disallow" & !rules$empty) &&
        any(in_effect & (every_path | (rules$type == "disallow" &
                                          rules$empty))),
      full_block = any(root_block) &&
        !any(in_effect & rules$type == "allow" & !rules$empty),
      exempt = key %in% exempt_keys,
      missing = which(!global$key %in% rules$key[in_effect])
    )
  })
  lost <- wildcard_lost_disallows(losers, rules, global, groups)
  reopened <- wildcard_reopened_disallows(losers, lost, rules, global, groups)
  reported <- Map(function(a, b) union(a, b$global), lost, reopened)
  rows <- c(
    wildcard_disallow_rows(losers, lost, global, groups),
    wildcard_reopen_rows(losers, reopened, groups),
    wildcard_inheritance_rows(losers, reported, global, groups)
  )
  code <- vapply(rows, `[[`, "", "code")
  rows[order(vapply(rows, `[[`, 0L, "line"),
             match(code, c("wildcard_disallows_not_inherited",
                           "allow_reopens_wildcard_disallow",
                           "wildcard_rules_not_inherited")))]
}

# The `*` Disallows each crawler of wildcard_inheritance_diagnostics() loses
# (ROBO-pbwijkdq), as a list parallel to `losers` of indices into `global`.
# A missing `*` Disallow is lost when a witness path (wildcard_witness_paths())
# is disallowed under the `*` groups' rules and allowed by the Disallows of
# the crawler's merged groups alone, both read by Google's matcher. A path
# only an Allow of the crawler's reopens is ROBO-cufxicmz's
# (allow_reopens_wildcard_disallow), not this loss. A crawler that ignores
# `*`, or whose groups are a full block, loses none. Crawlers whose groups
# hold the same Disallows share one check.
wildcard_lost_disallows <- function(losers, rules, global, groups) {
  out <- rep(list(integer()), length(losers))
  is_disallow <- global$type == "disallow"
  checked <- which(vapply(losers, function(x) {
    !x$exempt && !x$full_block && any(is_disallow[x$missing])
  }, TRUE))
  if (length(checked) == 0L) {
    return(out)
  }
  need <- sort(unique(unlist(lapply(losers[checked], `[[`, "missing"))))
  need <- need[is_disallow[need]]
  star <- rules$group %in% groups$groups$group[groups$groups$global]
  blocked <- rep(list(character()), nrow(global))
  blocked[need] <- wildcard_star_blocked(global$value[need], rules, star)
  bodies <- vapply(losers[checked], function(x) {
    wildcard_witness_body(rules, rules$group %in% x$groups &
                            rules$type == "disallow")
  }, "")
  for (body in unique(bodies)) {
    members <- checked[bodies == body]
    miss <- unique(unlist(lapply(losers[members], `[[`, "missing")))
    miss <- miss[lengths(blocked[miss]) > 0L]
    open <- miss[wildcard_named_open(body, blocked[miss])]
    for (m in members) {
      out[[m]] <- losers[[m]]$missing[losers[[m]]$missing %in% open]
    }
  }
  out
}

# For each `*` Disallow value, its witness paths (or the given `paths`, a
# parallel list) that value disallows under the `*` groups: read against
# that Disallow and the `*` Allows that could match the path. Disallowed
# there, the path stays disallowed under every `*` rule, as more Disallows
# only lengthen the longest match; allowed
# there, a `*` Allow beats this Disallow, and a block by another `*`
# Disallow is that rule's, not this one's (review of 2a1a5a4). An Allow
# can match a path only if its pattern up to the first `*` (or `$`) starts
# the path, so only those Allows enter each body: one body per value, as
# small as the Allows that bear on it, decided by Google's matcher.
wildcard_star_blocked <- function(values, rules, star,
                                  paths = lapply(values,
                                                 wildcard_witness_paths)) {
  allows <- which(star & rules$type == "allow" & !rules$empty)
  prefix <- wildcard_allow_prefix(rules$value[allows])
  # An Allow led by `*` may match any path: it enters every body. (Its
  # empty key could not be selected by name from a split list; second
  # review of 205f60d.)
  everywhere <- allows[!nzchar(prefix)]
  by_prefix <- split(allows[nzchar(prefix)], prefix[nzchar(prefix)])
  near <- lapply(paths, function(p) {
    if (length(by_prefix) == 0L) {
      return(everywhere)
    }
    starts <- substring(rep(p, nchar(p, "bytes") + 1L), 1L,
                        unlist(lapply(nchar(p, "bytes"), seq.int, from = 0L)))
    sort(c(everywhere, unlist(by_prefix[intersect(starts, names(by_prefix))],
                              use.names = FALSE)))
  })
  lines <- paste0(ifelse(rules$type == "allow", "Allow: ", "Disallow: "),
                  rules$value, "\n")
  bodies <- paste0("User-agent: witness\n",
                   vapply(near, function(i) paste(lines[i], collapse = ""),
                          ""),
                   "Disallow: ", values, "\n")
  ids <- rep(seq_along(values), lengths(paths))
  flat <- unlist(paths, use.names = FALSE)
  allowed <- wildcard_witness_eval(bodies, ids, flat)
  unname(split(flat[!allowed], factor(ids[!allowed], seq_along(values))))
}

# The part of each Allow pattern a path must start with: up to the first
# `*`, with a final `$` dropped. Google's matcher also lets an Allow whose
# last segment starts with `index.htm` (`/d/index.html`, `/d/index.htmx`)
# match its directory (src/robots.cc), so that segment is dropped first. A
# pattern led by neither `/` nor `*` never matches and gets a key no path
# starts with. Values are canonical (escapes upper-cased, non-ASCII
# escaped), as the witness paths are, so a prefix compares byte for byte.
wildcard_allow_prefix <- function(values) {
  prefix <- sub("/index\\.htm[^/]*$", "/", values)
  prefix <- sub("\\*.*$", "", prefix)
  prefix <- sub("\\$$", "", prefix)
  led <- startsWith(values, "/") | startsWith(values, "*")
  prefix[!led] <- "\n"
  prefix
}

# Whether each element of `paths` (a list of character vectors) holds a path
# Google's matcher allows under `body`: the first path of each is read
# first, the others only for elements not yet shown.
wildcard_named_open <- function(body, paths) {
  open <- logical(length(paths))
  if (length(paths) == 0L) {
    return(open)
  }
  first <- vapply(paths, `[[`, "", 1L)
  open <- wildcard_witness_eval(body, rep(1L, length(first)), first)
  rest <- which(!open & lengths(paths) > 1L)
  if (length(rest) > 0L) {
    more <- lapply(paths[rest], `[`, -1L)
    hit <- wildcard_witness_eval(body, rep(1L, sum(lengths(more))),
                                 unlist(more, use.names = FALSE))
    open[rest] <- vapply(split(hit, rep(seq_along(more), lengths(more))),
                         any, TRUE)
  }
  open
}

# Paths a pattern matches, for a witness (ROBO-pbwijkdq): the pattern with
# each `*` as nothing and as `x`, then, unless it ends in `$`, also with `x`
# and `/x` appended (with `suffixes`), so a `$` or a longer rule in the
# named group that covers the bare path still leaves one it does not.
wildcard_witness_paths <- function(value, suffixes = TRUE) {
  dollar <- endsWith(value, "$")
  if (dollar) {
    value <- substr(value, 1L, nchar(value, "bytes") - 1L)
  }
  bases <- unique(c(gsub("*", "", value, fixed = TRUE),
                    gsub("*", "x", value, fixed = TRUE)))
  led <- startsWith(bases, "/")
  bases[!led] <- paste0("/", bases[!led])
  if (!dollar && suffixes) {
    bases <- c(bases, paste0(bases, "x"), sprintf("%s/x", bases))
  }
  unique(bases)
}

# A robots.txt body of the Allow and Disallow rules in `keep`, in file order,
# under one group naming the witness crawler.
wildcard_witness_body <- function(rules, keep) {
  rows <- which(keep)
  paste0("User-agent: witness\n",
         paste0(ifelse(rules$type[rows] == "allow", "Allow: ", "Disallow: "),
                rules$value[rows], "\n", collapse = ""))
}

# Whether Google's matcher allows each path for the witness crawler, path
# `i` read under `bodies[[ids[[i]]]]`; each body is parsed once.
wildcard_witness_eval <- function(bodies, ids, paths) {
  wildcard_witness_decide(bodies, ids, paths)$allowed
}

# wildcard_witness_eval() with the deciding line too: `allowed`, and
# `line`, the body line of the rule that decided (0 when none matched).
wildcard_witness_decide <- function(bodies, ids, paths) {
  n <- length(paths)
  if (n == 0L) {
    return(list(allowed = logical(), line = integer()))
  }
  found <- robotstxtr_google_eval_batch_(
    bodies = bodies,
    per_row = list(ids = as.integer(ids), agents = rep("witness", n),
                   urls = lapply(paste0("http://example.com", paths),
                                 charToRaw),
                   parents = rep("", n), ignore_global = rep(FALSE, n))
  )
  list(allowed = found$allowed, line = found$matching_line)
}

# The `*` Disallows an Allow of each crawler reopens (ROBO-cufxicmz), as a
# list parallel to `losers` of data frames with one row per `*` Disallow:
# `global` (its index in `global`), `path` (a witness), `star_line` and
# `star_value` (that Disallow) and `allow_line` and `allow_value` (the
# crawler's Allow that allows the path). A witness is a path Google's
# matcher allows under the crawler's merged groups, disallows under those
# groups' Disallows alone (so the Allow causes the opening), and disallows
# under the `*` Disallow and the `*` Allows that could match it
# (wildcard_star_blocked(): then every `*` rule disallows it). Each read is
# the matcher's, so a reported witness is exact; an overlap no candidate
# path (wildcard_reopen_paths()) shows is skipped, never guessed. A `*`
# Disallow the crawler loses (wildcard_lost_disallows()) is that warning's,
# not this one's. Crawlers that ignore `*` reopen nothing. Crawlers whose
# groups hold the same rules share one check, and each cites its own Allow
# line (review of bc71586). A `*`-side read does not depend on the crawler,
# so it is made once per `*` Disallow and path, across checks.
wildcard_reopened_disallows <- function(losers, lost, rules, global, groups) {
  out <- rep(list(wildcard_reopen_none()), length(losers))
  star_disallows <- which(global$type == "disallow")
  has_allow <- vapply(losers, function(x) {
    !x$exempt && any(rules$group %in% x$groups & rules$type == "allow" &
                       !rules$empty)
  }, TRUE)
  checked <- which(has_allow)
  if (length(checked) == 0L || length(star_disallows) == 0L) {
    return(out)
  }
  star <- rules$group %in% groups$groups$group[groups$groups$global]
  bodies <- vapply(losers[checked], function(x) {
    wildcard_witness_body(rules, rules$group %in% x$groups)
  }, "")
  cache <- new.env(parent = emptyenv())
  cache$done <- rep(list(character()), nrow(global))
  cache$hit <- rep(list(character()), nrow(global))
  for (body in unique(bodies)) {
    members <- checked[bodies == body]
    in_effect <- rules$group %in% losers[[members[[1L]]]]$groups
    found <- wildcard_reopen_witnesses(rules, in_effect, star, global,
                                       star_disallows, cache)
    for (m in members) {
      # The same body lists the same rules in the same order, so the
      # Allow's position among the crawler's own rules gives its line.
      own <- which(rules$group %in% losers[[m]]$groups)[found$allow_at]
      out[[m]] <- data.frame(
        found[c("global", "path", "star_line", "star_value")],
        allow_line = rules$line[own], allow_value = rules$value[own]
      )[!found$global %in% lost[[m]], , drop = FALSE]
    }
  }
  out
}

wildcard_reopen_none <- function() {
  data.frame(global = integer(), path = character(), star_line = integer(),
             star_value = character(), allow_at = integer())
}

# Candidate paths for each `*` Disallow in `disallows`, as a list: the
# Disallow's witness paths (wildcard_witness_paths()); the witness paths of
# each Allow that start with the Disallow's literal part (up to its first
# `*`); and, for a Disallow with a `*`, the Disallow read under each Allow's
# literal prefix that starts with that part (`Allow: /creativegroup/` with
# `Disallow: /*_print.html` gives `/creativegroup/*_print.html`).
wildcard_reopen_paths <- function(allows, disallows) {
  prefix <- wildcard_allow_prefix(allows)
  prefix <- unique(prefix[nzchar(prefix) & prefix != "\n"])
  allow_paths <- unique(unlist(lapply(allows, wildcard_witness_paths),
                               use.names = FALSE))
  literal <- sub("\\*.*$", "", disallows)
  lapply(seq_along(disallows), function(i) {
    if (!grepl("^[/*]", disallows[[i]])) {
      return(character())
    }
    stem <- sub("\\$$", "", literal[[i]])
    combos <- character()
    if (grepl("*", disallows[[i]], fixed = TRUE)) {
      under <- prefix[startsWith(prefix, literal[[i]])]
      rest <- substring(disallows[[i]], nchar(literal[[i]], "bytes") + 1L)
      # Base forms only (no `x` or `/x` appended): a third of the paths,
      # which matters with many Allows and `*`-led Disallows.
      combos <- unlist(lapply(paste0(under, rest), wildcard_witness_paths,
                              suffixes = FALSE), use.names = FALSE)
    }
    unique(c(wildcard_witness_paths(disallows[[i]]), combos,
             allow_paths[startsWith(allow_paths, stem)]))
  })
}

# The witnesses for wildcard_reopened_disallows() of the crawler whose rules
# are `in_effect`, one per `*` Disallow (`star_disallows`, indices into
# `global`): a path without an empty segment (`//`) if there is one, then
# the shortest, then the first in byte order. `allow_at` is the deciding
# Allow's position among the crawler's rules. The named reads come first,
# on each candidate path once; only the paths the crawler's Allows reopen
# reach the `*` side, read through `cache` (wildcard_reopen_star()).
wildcard_reopen_witnesses <- function(rules, in_effect, star, global,
                                      star_disallows, cache) {
  full <- which(in_effect)
  read <- function(rows, at) {
    wildcard_witness_decide(
      wildcard_witness_body(rules, seq_len(nrow(rules)) %in% rows),
      rep(1L, length(at)), at
    )
  }
  candidates <- wildcard_reopen_paths(
    rules$value[in_effect & rules$type == "allow" & !rules$empty],
    global$value[star_disallows]
  )
  paths <- unique(unlist(candidates, use.names = FALSE))
  named <- read(full, paths)
  # Line 0: no rule matched. Such a path is allowed by the Disallows alone
  # too, so it drops out below; NA keeps the vectors aligned until then.
  at <- named$line[named$allowed]
  allow_at <- ifelse(at > 1L, at - 1L, NA)
  paths <- paths[named$allowed]
  reopened <- !read(which(in_effect & rules$type == "disallow"),
                    paths)$allowed
  allow_at <- allow_at[reopened]
  paths <- paths[reopened]
  # One membership test over every (Disallow, path) pair, not one per
  # Disallow against every reopened path.
  ids <- rep(seq_along(candidates), lengths(candidates))
  flat <- unlist(candidates, use.names = FALSE)
  kept <- flat %in% paths
  candidates <- unname(split(flat[kept],
                             factor(ids[kept], seq_along(candidates))))
  some <- which(lengths(candidates) > 0L)
  if (length(some) == 0L) {
    return(wildcard_reopen_none())
  }
  blocked <- wildcard_reopen_star(star_disallows[some], candidates[some],
                                  rules, star, global, cache)
  hit <- lengths(blocked) > 0L
  if (!any(hit)) {
    return(wildcard_reopen_none())
  }
  witness <- vapply(blocked[hit], function(p) {
    p[order(grepl("//", p, fixed = TRUE), nchar(p, "bytes"), p,
            method = "radix")][[1L]]
  }, "")
  g <- star_disallows[some][hit]
  found <- data.frame(
    global = g, path = witness, star_line = global$line[g],
    star_value = global$value[g], allow_at = allow_at[match(witness, paths)]
  )
  found[order(found$star_line), , drop = FALSE]
}

# wildcard_star_blocked() for `*` Disallows `g` (indices into `global`) and
# their candidate `paths`, reading only the (Disallow, path) pairs `cache`
# has not seen; `cache$hit` keeps the blocked paths per Disallow.
wildcard_reopen_star <- function(g, paths, rules, star, global, cache) {
  fresh <- Map(setdiff, paths, cache$done[g])
  todo <- which(lengths(fresh) > 0L)
  if (length(todo) > 0L) {
    found <- wildcard_star_blocked(global$value[g[todo]], rules, star,
                                   fresh[todo])
    cache$done[g[todo]] <- Map(c, cache$done[g[todo]], fresh[todo])
    cache$hit[g[todo]] <- Map(c, cache$hit[g[todo]], found)
  }
  Map(intersect, paths, cache$hit[g])
}

# One wildcard_disallows_not_inherited row per group and set of lost `*`
# Disallows (ROBO-pbwijkdq), as list(line, code, severity, message). It is a
# warning, or info for an explicit grant (`Allow: /` or an empty
# `Disallow:` and no other Disallow), which is almost always deliberate
# (owner decision, 2026-11-18). These rows never merge across groups.
wildcard_disallow_rows <- function(losers, lost, global, groups) {
  hit <- which(lengths(lost) > 0L)
  signature <- vapply(hit, function(i) {
    paste(losers[[i]]$first_group, losers[[i]]$allow_only, losers[[i]]$grant,
          paste(lost[[i]], collapse = ","))
  }, "")
  lapply(unname(split(hit, factor(signature, unique(signature)))), function(i) {
    members <- losers[i]
    tokens <- ai_training_name(unlist(lapply(members, `[[`, "names"),
                                      use.names = FALSE))
    list(
      line = wildcard_group_line(groups, members[[1L]]$first_group),
      code = "wildcard_disallows_not_inherited",
      severity = if (members[[1L]]$grant) "info" else "warning",
      agents = tokens, missing = global$line[lost[[i[[1L]]]]],
      owned = wildcard_group_line(groups, members[[1L]]$first_group),
      message = paste0(wildcard_disallows_message(
        tokens, all(vapply(members, `[[`, TRUE, "one_group")),
        global[lost[[i[[1L]]]], , drop = FALSE], members[[1L]]$allow_only
      ), wildcard_cut_note(members))
    )
  })
}

# An Allow or Disallow value that matches every path: `/`, `/*`, `*`, `/*$`,
# `*$` and the like (`/$` is not one). Tested on the value, not the key: the
# key drops a trailing `*` run, which would also take `/*$*`.
wildcard_every_path <- function(values) {
  grepl("^(/\\**|/?\\*+\\$?)$", values)
}

# One allow_reopens_wildcard_disallow row (a warning, or info when only
# every-path Allows reopen) per group and set of
# reopened `*` Disallows (ROBO-cufxicmz), as list(line, code, severity,
# agents, missing, owned, message), anchored on the group's first
# User-agent line. Crawlers stacked on one group share its row when their
# paths, cited lines and group count are the same.
wildcard_reopen_rows <- function(losers, reopened, groups) {
  hit <- which(vapply(reopened, nrow, 0L) > 0L)
  signature <- vapply(hit, function(i) {
    # Crawlers merge only when every cited line and the wording agree
    # (review of bc71586).
    paste(losers[[i]]$first_group, losers[[i]]$one_group,
          paste(reopened[[i]]$global, collapse = ","),
          paste(reopened[[i]]$allow_line, collapse = ","),
          paste(reopened[[i]]$path, collapse = "\n"))
  }, "")
  lapply(unname(split(hit, factor(signature, unique(signature)))), function(i) {
    members <- losers[i]
    tokens <- ai_training_name(unlist(lapply(members, `[[`, "names"),
                                      use.names = FALSE))
    line <- wildcard_group_line(groups, members[[1L]]$first_group)
    found <- reopened[[i[[1L]]]]
    list(
      line = line, code = "allow_reopens_wildcard_disallow",
      # Info when only a blanket Allow (`Allow: /`) reopens the paths: an
      # explicit grant, as for wildcard_disallows_not_inherited (owner
      # decision, 2026-11-18).
      severity = if (all(wildcard_every_path(found$allow_value))) "info" else
        "warning",
      agents = tokens, missing = found$star_line,
      owned = line,
      message = paste0(wildcard_reopen_message(
        tokens, all(vapply(members, `[[`, TRUE, "one_group")), found
      ), wildcard_cut_note(members))
    )
  })
}

# The wildcard_rules_not_inherited info rows (ROBO-gfjotdrr): each crawler's
# missing `*` rules less those its warning reports, only its lost `*`
# Allows for a full block, and none for an allow-all crawler. Crawlers with
# the same remaining rules share one row, across groups too (ROBO-pbwijkdq),
# anchored on the earliest group's first User-agent line.
wildcard_inheritance_rows <- function(losers, lost, global, groups) {
  remaining <- lapply(seq_along(losers), function(i) {
    x <- losers[[i]]
    if (x$open) {
      return(integer())
    }
    keep <- setdiff(x$missing, lost[[i]])
    if (x$full_block && !x$exempt) {
      keep <- keep[global$type[keep] == "allow"]
    }
    keep
  })
  hit <- which(lengths(remaining) > 0L)
  signature <- vapply(hit, function(i) {
    paste(losers[[i]]$full_block, losers[[i]]$exempt,
          paste(remaining[[i]], collapse = ","))
  }, "")
  lapply(unname(split(hit, factor(signature, unique(signature)))), function(i) {
    members <- losers[i]
    first <- vapply(members, `[[`, 0L, "first_group")
    missing <- global[remaining[[i[[1L]]]], , drop = FALSE]
    tokens <- ai_training_name(unlist(lapply(members, `[[`, "names"),
                                      use.names = FALSE))
    labels <- if (length(unique(first)) > 1L) {
      wildcard_group_labels(members, first, groups)
    }
    list(
      line = wildcard_group_line(groups, min(first)),
      code = "wildcard_rules_not_inherited", severity = "info",
      agents = tokens, missing = missing$line,
      # Every merged group's first line stays this report's (one line, one
      # report), not only the anchor's.
      owned = vapply(sort(unique(first)), wildcard_group_line, 0L,
                     groups = groups),
      message = paste0(wildcard_inheritance_message(
        tokens, all(vapply(members, `[[`, TRUE, "one_group")), missing,
        full_block = members[[1L]]$full_block, exempt = members[[1L]]$exempt,
        labels = labels
      ), wildcard_cut_note(members))
    )
  })
}

wildcard_group_line <- function(groups, group) {
  groups$groups$first_line[[match(group, groups$groups$group)]]
}

# The groups of a merged info row, in file order, as "A and B (line 5); and
# C (line 9)", five at most, then "and N more groups": semicolons part the
# groups, since a group's own names are joined with "and".
wildcard_group_labels <- function(members, first, groups, cap = 5L) {
  by_group <- split(seq_along(members), factor(first, sort(unique(first))))
  labels <- vapply(names(by_group), function(g) {
    names <- ai_training_name(unlist(lapply(members[by_group[[g]]], `[[`,
                                            "names"), use.names = FALSE))
    sprintf("%s (line %d)", joined_and(names, 0L),
            wildcard_group_line(groups, as.integer(g)))
  }, "", USE.NAMES = FALSE)
  shown <- labels[seq_len(min(cap, length(labels)))]
  more <- length(labels) - length(shown)
  if (more > 0L) {
    shown <- c(shown, sprintf("and %d more %s", more,
                              if (more == 1L) "group" else "groups"))
  } else {
    shown[[length(shown)]] <- paste("and", shown[[length(shown)]])
  }
  paste(shown, collapse = "; ")
}

# The distinct values written for each crawler id, as a list named by id:
# messages name an agent as written, not as Google's matcher cuts it, so
# `Peer39_Crawler` and `Peer42` (both read as `Peer`) are named apart
# (ROBO-txnzyugl). A value the token spells whole is the crawler's own name,
# so when an id has one, its cut values (`Googlebot/2.1` beside `googlebot`)
# are left out. Values differing only in ASCII case count once, the first
# written.
written_agent_names <- function(id, name, cut) {
  rows <- split(seq_along(id), factor(id, unique(id)))
  lapply(rows, function(i) {
    if (!all(cut[i])) {
      i <- i[!cut[i]]
    }
    x <- name[i]
    x[!duplicated(ascii_lower(x))]
  })
}

# The cut lines behind the values written_agent_names() names, as a list of
# row indexes in the same order (ROBO-zqyqbudf): every row of an id whose
# values are all cut, and none of an id with an uncut value, which is the
# name shown. A value written on several lines, in any case, keeps each
# line: each has its own user_agent_cut row.
written_cut_rows <- function(id, cut) {
  rows <- split(seq_along(id), factor(id, unique(id)))
  lapply(rows, function(i) if (all(cut[i])) i else integer())
}

# The sentence a row that names agents adds for those whose value Google's
# matcher cuts (ROBO-zqyqbudf): it reads only a product token from the value
# and takes the agent to be that token, which the line's user_agent_cut row
# states. `names` are the values as written and `lines` their lines, NA for
# a value the row names that is not cut; "" when none is. Five values at
# most, in line order, then a count. It speaks of Google's reading only: the
# Bing and Yandex backends evaluate only their own crawlers' tokens.
cut_agent_note <- function(names, lines, cap = 5L) {
  cut <- which(!is.na(lines))
  if (length(cut) == 0L) {
    return("")
  }
  cut <- cut[order(lines[cut])]
  shown <- cut[seq_len(min(cap, length(cut)))]
  several <- length(cut) > 1L
  sprintf(
    paste0(" Google's matcher reads only a product token from %s and takes ",
           "%s to be %s; see the user_agent_cut %s."),
    joined_and(sprintf("`%s` (line %d)", ai_training_name(names[shown]),
                       lines[shown]), length(cut) - length(shown)),
    if (several) "each agent" else "the agent",
    if (several) "its token" else "that token",
    if (several) "rows" else "row"
  )
}

# cut_agent_note() for the crawlers of a wildcard row, as
# wildcard_inheritance_diagnostics() gives them: each member's `cut_names`
# and their `cut_lines`.
wildcard_cut_note <- function(members) {
  cut_agent_note(
    unlist(lapply(members, `[[`, "cut_names"), use.names = FALSE),
    unlist(lapply(members, `[[`, "cut_lines"), use.names = FALSE)
  )
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
# ROBO-xexjgecr): `*` for a global User-agent line, the merge key otherwise
# (`key`, Google's by default; ROBO-qwfoyouo passes `agents$uncut`); a line
# naming no token is dropped, and a `*` token never stands for a named one.
# Returns a function that crosses a vector of rule group ids with the token
# classes of each group, as list(owner, class): `owner` indexes the input
# (ascending, so rows keep its order) and `class` is the token class.
validation_token_expander <- function(groups, key = groups$agents$key) {
  agents <- groups$agents
  token <- ifelse(agents$global, "*", key)
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
# line when a User-agent line follows it are skipped, and so are the lines
# in `skip` (lower-case-escape twins, ROBO-nvzzjubl), which neither get a row
# nor count as the earlier rule. Returns a data frame of `line`, `type` and
# `message`, in line order; the message names the smallest line among each
# token's first identical rule.
# A row is a repeat only through a cut when no earlier line holding the rule
# sits in a group sharing a whole value with the repeat's group
# (duplicate_rule_cut_only()): Google's matcher merged the groups of values
# it cuts to one token, and the message says so instead of calling the rule
# a no-op (ROBO-qwfoyouo).
duplicate_rule_diagnostics <- function(groups, skip = integer()) {
  rules <- groups$rules
  # Any rule line, empty or not, ends its group. A group's only rule line
  # keeps the next User-agent line from joining it, so it is not reported
  # when a User-agent line follows it: deleting it would merge the groups.
  rule_lines <- tabulate(match(rules$group, groups$groups$group),
                         nrow(groups$groups))
  rules$sole <- rule_lines[match(rules$group, groups$groups$group)] == 1L &
    rules$line < max(groups$agents$line, -Inf)
  rules <- rules[substr(rules$value, 1L, 1L) %in% c("/", "*") &
                   !rules$line %in% skip, , drop = FALSE]
  found <- duplicate_rule_repeats(rules, validation_token_expander(groups))
  owner <- found$owner
  first <- found$first

  type <- rules$type[owner]
  message <- sprintf(
    "Rule has no effect: line %d already has the same %s.",
    first, ifelse(type == "allow", "Allow", "Disallow")
  )
  cut_only <- duplicate_rule_cut_only(groups, rules, owner)
  if (any(cut_only)) {
    message[cut_only] <- duplicate_rule_cut_message(
      groups$agents, rules, owner[cut_only], first[cut_only]
    )
  }
  data.frame(
    line = rules$line[owner], type = type, message = message,
    stringsAsFactors = FALSE
  )
}

# The repeats among `rules` for the token classes `expand` gives, as
# list(owner, first): `owner` indexes `rules` (ascending) and `first` is the
# smallest line among each token's first identical rule.
duplicate_rule_repeats <- function(rules, expand) {
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
  list(owner = owner[keep], first = first[keep])
}

# Which repeats in `owner` (indexes of `rules`) are repeats only for Google's
# matcher. A matcher that compares the whole value merges two groups for a
# crawler whose value both name, so the repeat is Google's only when no
# earlier line holding the same rule sits in a group sharing a whole value
# (`agents$uncut`, `*` for a global line) with the repeat's group. Where one
# does, a crawler going by that value gets the rule twice there too, and the
# row keeps the plain text.
duplicate_rule_cut_only <- function(groups, rules, owner) {
  agents <- groups$agents
  if (length(owner) == 0L || all(agents$uncut == agents$key)) {
    return(logical(length(owner)))
  }
  by_rule <- validation_token_expander(groups, agents$uncut)(rules$group)
  held <- by_rule$owner
  key <- paste(by_rule$class, rules$type[held], rules$value[held],
               sep = "\n")
  # Rows are in file order, so a key's first row has its smallest line.
  shared <- held[rules$line[held[match(key, key)]] < rules$line[held]]
  !owner %in% shared
}

# The message of a repeat that exists only because Google's matcher cuts
# written User-agent values to one token and merges their groups. The
# wording depends on the repeat's group only, so it is built once per group.
duplicate_rule_cut_message <- function(agents, rules, owner, first) {
  group <- rules$group[owner]
  wanted <- unique(group)
  parts <- duplicate_rule_cut_names(agents, wanted)
  at <- match(group, wanted)
  sprintf(paste0(
    "This %s repeats line %d only for Google's matcher, which reads %s ",
    "and merges their groups. %s, so there it is not a repeat; see the ",
    "user_agent_cut rows."
  ), ifelse(rules$type[owner] == "allow", "Allow", "Disallow"), first,
  parts[1L, at], parts[2L, at])
}

# The crawlers each bounded backend evaluates, by engine name: its accepted
# selectors (engine_backend_capability_v1()), folded to ASCII lower case as
# the backend compares them.
duplicate_rule_cut_engines <- function() {
  capability <- engine_backend_capability_v1()
  lapply(c(Bing = "bing", Yandex = "yandex"), function(backend) {
    ascii_lower(capability[[backend]]$supported_profiles$accepted_token)
  })
}

# Who keeps the merged groups apart, for the tokens Google reads (`keys`).
# An engine is named only when a token is one of the crawlers its backend
# evaluates (`engines`, from duplicate_rule_cut_engines()); otherwise the
# sentence names no engine.
duplicate_rule_cut_apart <- function(keys, engines) {
  hit <- vapply(engines, function(accepted) any(keys %in% accepted),
                logical(1L))
  engines <- names(engines)[hit]
  if (length(engines) == 0L) {
    return(paste("A matcher that compares the whole User-agent value keeps",
                 "the groups apart"))
  }
  if (length(engines) == 1L) {
    return(sprintf(paste("The package's %s matcher compares the whole value",
                         "and keeps the groups apart"), engines))
  }
  paste("The package's Bing and Yandex matchers compare the whole value and",
        "keep the groups apart")
}

# For each group in `wanted`, a column of two message parts. The first is
# "<values> as <tokens>": the tokens the group names that more than one
# whole value cuts to in the groups up to and including it (Google merges
# all of them), as first written (five at most, then a count), and their
# written values in file order (five at most, then a count): one of the
# group's own for each token named, then the earliest others. Values
# differing only in ASCII case count once, the first written. A line
# reading no token (`1bot`) is left out. The second part is
# duplicate_rule_cut_apart() for those tokens.
# The lookups are integer vectors built once, and a group reads only its own
# lines and the values it shows, so the cost is linear in the agent lines
# (ROBO-dbvmxcfw).
duplicate_rule_cut_names <- function(agents, wanted, cap = 5L) {
  keep <- !agents$global & nzchar(agents$key)
  key <- match(agents$key[keep], unique(agents$key[keep]))
  pair <- paste(agents$key[keep], agents$uncut[keep], sep = "\n")
  first_of <- match(pair, pair)
  is_first <- first_of == seq_along(pair)
  distinct <- which(is_first)
  # Each token's first `cap` distinct whole values, as agent indexes in line
  # order, by integer token id.
  ids <- factor(key[distinct], seq_len(max(key, 0L)))
  heads <- lapply(split(distinct, ids), utils::head, cap)
  group <- agents$group[keep]
  runs <- rle(group)
  ends <- cumsum(runs$lengths)
  look <- list(
    key = key, name = agents$name[keep], token = agents$token[keep],
    first_of = first_of, heads = heads,
    # The distinct whole values of a line's token up to and including it.
    seen = stats::ave(as.integer(is_first), key, FUN = cumsum),
    engines = duplicate_rule_cut_engines(),
    folded = agents$key[keep]
  )
  at <- match(wanted, runs$values)
  vapply(seq_along(wanted), function(i) {
    own <- seq.int(ends[[at[[i]]]] - runs$lengths[[at[[i]]]] + 1L,
                   ends[[at[[i]]]])
    duplicate_rule_cut_group_names(look, own, cap)
  }, character(2L), USE.NAMES = FALSE)
}

duplicate_rule_cut_group_names <- function(look, own, cap) {
  # A token's last line in the group holds its count up to the group. Every
  # token the group names has more than one: Google's repeat needs an
  # earlier group naming it, and one with the same whole value would make
  # the repeat a plain one (duplicate_rule_cut_only()).
  last <- own[!duplicated(look$key[own], fromLast = TRUE)]
  heads <- look$heads[look$key[last]]
  firsts <- vapply(heads, `[[`, 0L, 1L)
  order_by <- order(firsts)
  last <- last[order_by]
  heads <- heads[order_by]
  firsts <- firsts[order_by]
  merged <- look$key[last]
  # One own value for each token named, then the earliest others.
  named <- utils::head(seq_along(merged), cap)
  mine <- vapply(named, function(j) {
    min(look$first_of[own][look$key[own] == merged[[j]]])
  }, 0L)
  others <- unlist(Map(function(h, n) h[seq_len(min(cap, n))],
                       heads[named], look$seen[last][named]),
                   use.names = FALSE)
  others <- sort.int(others[!others %in% mine])
  shown <- sort.int(c(mine, others[seq_len(min(length(others),
                                               cap - length(mine)))]))
  total <- sum(look$seen[last])
  quote <- function(x) sprintf("'%s'", ai_training_name(x))
  tokens <- look$token[firsts]
  c(
    paste(
      joined_and(quote(look$name[shown]), total - length(shown)), "as",
      if (length(tokens) == 1L) {
        sprintf("one token, %s,", quote(tokens))
      } else {
        sprintf("the tokens %s,", joined_and(
          quote(utils::head(tokens, cap)), length(tokens) - cap
        ))
      }
    ),
    duplicate_rule_cut_apart(look$folded[firsts], look$engines)
  )
}

wildcard_inheritance_message <- function(tokens, one_group, missing,
                                         full_block = FALSE, cap = 10L,
                                         exempt = FALSE, labels = NULL) {
  who <- wildcard_inheritance_who(tokens, one_group, labels)
  k <- nrow(missing)
  listed <- wildcard_rule_list(missing, cap)
  if (exempt) {
    return(wildcard_exempt_message(who, k, listed))
  }
  if (full_block) {
    text <- sprintf(
      paste0(
        "%s %s only %s, which %s `/`, so %s `User-agent: *` Allow %s may be ",
        "meant as %s and %s not apply to %s: %s. A stricter policy for a ",
        "named crawler may be deliberate."
      ),
      who$named, who$obey, who$where, who$disallow,
      if (k == 1L) "this" else "these", if (k == 1L) "rule" else "rules",
      if (k == 1L) "an exception" else "exceptions",
      if (k == 1L) "does" else "do", who$it, listed
    )
  } else {
    text <- sprintf(
      "%s %s only %s, so %s `User-agent: *` %s not apply to %s: %s.",
      who$named, who$obey, who$where,
      if (k == 1L) "this" else "these",
      if (k == 1L) "rule does" else "rules do", who$it, listed
    )
  }
  paste(text, paste0(
    "A crawler obeys only the groups that name it and ignores ",
    "`User-agent: *` once any group does; `User-agent: *` applies only to ",
    "crawlers no group names."
  ))
}

# The words an inheritance info row names its crawlers with: `named` (the
# agents, or the merged groups' labels), `several`, `where`, `obey`, `it`
# and `disallow` (the full-block verb).
wildcard_inheritance_who <- function(tokens, one_group, labels) {
  merged <- !is.null(labels)
  several <- length(tokens) > 1L || merged
  single <- one_group && !merged
  list(
    named = if (merged) labels else joined_and(tokens, 0L),
    several = several,
    where = if (single) "this group" else
      paste("the groups that name", if (several) "them" else "it"),
    obey = if (merged) "each obey" else if (several) "obey" else "obeys",
    it = if (several) "them" else "it",
    disallow = if (single) "disallows" else if (merged) "disallow" else
      "together disallow"
  )
}

# The info row of the crawlers that ignore `*` whether or not a group names
# them (ROBO-pbwijkdq): the `*` rules never applied to them.
wildcard_exempt_message <- function(who, k, listed) {
  sprintf(
    paste0("%s %s `User-agent: *` whether or not a group names %s (%s), ",
           "so %s never applied to %s: %s."),
    who$named, if (who$several) "ignore" else "ignores", who$it,
    if (who$several) "Google's special-case crawlers" else
      "one of Google's special-case crawlers",
    if (k == 1L) "this `User-agent: *` rule" else
      "these `User-agent: *` rules", who$it, listed
  )
}

# The wildcard_disallows_not_inherited message (ROBO-pbwijkdq): the lost `*`
# Disallows, whether the crawler's groups hold no Disallow at all, and what
# a named group does, without calling the loss a mistake.
wildcard_disallows_message <- function(tokens, one_group, lost, allow_only,
                                       cap = 10L) {
  several <- length(tokens) > 1L
  named <- if (several) {
    paste(toString(tokens[-length(tokens)]), "and", tokens[[length(tokens)]])
  } else {
    tokens
  }
  it <- if (several) "them" else "it"
  k <- nrow(lost)
  text <- sprintf(
    "%s %s only %s, so %s `User-agent: *` %s not apply to %s: %s.",
    named, if (several) "obey" else "obeys",
    if (one_group) "this group" else
      paste("the groups that name", it),
    if (k == 1L) "this" else "these",
    if (k == 1L) "Disallow does" else "Disallows do", it,
    wildcard_rule_list(lost, cap)
  )
  if (allow_only) {
    text <- paste(text, sprintf(
      "%s no Disallow, so %s nothing for %s.",
      if (one_group) "This group holds" else "These groups hold",
      if (one_group) "it blocks" else "they block", it
    ))
  }
  paste(text, sprintf(paste0(
    "A named group replaces `User-agent: *` for the crawlers it names ",
    "instead of adding to it (RFC 9309 section 2.2.1). If %s meant to add ",
    "to `User-agent: *`, repeat %s in %s."
  ), if (one_group) "the group was" else "the groups were",
  if (k == 1L) "this Disallow" else "these Disallows",
  if (one_group) "it" else "them"))
}

# The allow_reopens_wildcard_disallow message (ROBO-cufxicmz): each
# reopened path with the Allow that allows it and the `*` Disallow that
# disallows it, `cap` at most, without calling the opening a mistake.
wildcard_reopen_message <- function(tokens, one_group, found, cap = 10L) {
  several <- length(tokens) > 1L
  k <- nrow(found)
  shown <- seq_len(min(k, cap))
  show <- function(values) {
    vapply(values, function(value) render_validation_line(charToRaw(value)),
           "", USE.NAMES = FALSE)
  }
  listed <- toString(sprintf(
    paste0("%s (allowed by Allow: %s on line %d; disallowed for `*` by ",
           "Disallow: %s on line %d)"),
    show(found$path[shown]), show(found$allow_value[shown]),
    found$allow_line[shown], show(found$star_value[shown]),
    found$star_line[shown]
  ))
  if (k > cap) {
    listed <- sprintf("%s, and %d more", listed, k - cap)
  }
  sprintf(
    paste0("%s %s only %s, so Allows there reopen %s, which `User-agent: *` ",
           "disallows: %s. A named group replaces `User-agent: *` for the ",
           "crawlers it names instead of adding to it (RFC 9309 section ",
           "2.2.1). If %s meant to stay blocked for %s, add %s to %s longer ",
           "than the Allow matching %s."),
    joined_and(tokens, 0L), if (several) "obey" else "obeys",
    if (one_group) "this group" else
      paste("the groups that name", if (several) "them" else "it"),
    if (k == 1L) "this path" else "these paths", listed,
    if (k == 1L) "this path was" else "these paths were",
    if (several) "them" else "it",
    if (k == 1L) "a Disallow" else "Disallows",
    if (one_group) "this group" else "these groups",
    if (k == 1L) "the path" else "each path"
  )
}

# Rules as "Disallow: /a (line 2), Allow: /b (line 3)", `cap` at most, then
# "and N more".
wildcard_rule_list <- function(missing, cap = 10L) {
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
  listed
}

# The parser's value is canonical: non-ASCII bytes are already %XX escapes,
# so an invisible leading character shows as its escaped UTF-8 bytes.
validation_invisible_prefixes <- c(
  "U+200B" = "%E2%80%8B",
  "U+FEFF" = "%EF%BB%BF"
)

validation_bom <- as.raw(c(0xef, 0xbb, 0xbf))

# UTF-32 and UTF-16 byte-order marks (ROBO-cvpkzckn). The UTF-32 ones come
# first: FF FE 00 00 also starts with the UTF-16LE mark, and the longer
# signature wins. A body shorter than four bytes is never read as UTF-32.
validation_wide_boms <- list(
  "utf-32le" = as.raw(c(0xff, 0xfe, 0x00, 0x00)),
  "utf-32be" = as.raw(c(0x00, 0x00, 0xfe, 0xff)),
  "utf-16le" = as.raw(c(0xff, 0xfe)),
  "utf-16be" = as.raw(c(0xfe, 0xff))
)

# The BOM-less heuristic: at least this many code units, and at least this
# share of them shaped as one ASCII character (its byte non-zero, the other
# bytes of the unit zero).
validation_wide_min_units <- 8L
validation_wide_min_share <- 0.9

# Bytes a UTF-16 or UTF-32 ASCII text may hold outside its zero bytes:
# printable ASCII, tab, LF and CR.
validation_wide_text_bytes <- as.raw(c(0x09, 0x0a, 0x0d, 0x20:0x7e))

# The UTF-16 or UTF-32 encoding a body's bytes point to, as
# list(signature, basis), or NULL. A full byte-order mark is "bom"; without
# one, "byte_pattern" is a heuristic over the first `content_check_bytes`
# bytes, which only ASCII text in that encoding passes, so a NUL-cut rule,
# control bytes or binary data is never named. `cut` says the window does not
# end where the file does (a body cut at max_bytes, or one longer than the
# window), so a partial code unit at its end is dropped instead of refusing
# the body.
validation_encoding_signature <- function(bytes, cut = FALSE) {
  n <- length(bytes)
  for (name in names(validation_wide_boms)) {
    bom <- validation_wide_boms[[name]]
    if (n >= length(bom) && identical(bytes[seq_along(bom)], bom)) {
      return(list(signature = name, basis = "bom"))
    }
  }
  window <- bytes[seq_len(min(n, content_check_bytes))]
  cut <- cut || n > content_check_bytes
  if (any(window == as.raw(0)) &&
        all(window[window != as.raw(0)] %in% validation_wide_text_bytes)) {
    for (shape in list(c("utf-32le", 4L, 1L), c("utf-32be", 4L, 4L),
                       c("utf-16le", 2L, 1L), c("utf-16be", 2L, 2L))) {
      width <- as.integer(shape[[2L]])
      if (validation_wide_pattern(window, width, as.integer(shape[[3L]]),
                                  cut)) {
        return(list(signature = shape[[1L]], basis = "byte_pattern"))
      }
    }
  }
  NULL
}

# Whether `window`, read as code units of `width` bytes, is mostly units with
# a non-zero byte at `at` and zero bytes elsewhere.
validation_wide_pattern <- function(window, width, at, cut) {
  n <- length(window)
  if (cut) {
    n <- n - n %% width
  } else if (n %% width != 0L) {
    return(FALSE)
  }
  units <- n %/% width
  if (units < validation_wide_min_units) {
    return(FALSE)
  }
  grid <- matrix(as.integer(window[seq_len(n)]), nrow = width)
  shaped <- grid[at, ] != 0L & colSums(grid[-at, , drop = FALSE]) == 0L
  mean(shaped) >= validation_wide_min_share
}

# The message of the utf16_or_utf32_encoding warning.
validation_encoding_signature_message <- function(found) {
  label <- c(
    "utf-16le" = "UTF-16LE", "utf-16be" = "UTF-16BE",
    "utf-32le" = "UTF-32LE", "utf-32be" = "UTF-32BE"
  )[[found$signature]]
  evidence <- if (identical(found$basis, "bom")) {
    sprintf("The body starts with a %s byte-order mark", label)
  } else {
    sprintf(
      paste0("The byte pattern suggests %s text (heuristic; the intended ",
             "encoding cannot be known)"),
      label
    )
  }
  paste0(
    evidence, "; robots.txt must be UTF-8, so re-save it as UTF-8 ",
    "(RFC 9309 section 2.3)."
  )
}

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
  # The parser trims a value's edges, so a space, tab, VT or FF left here is
  # interior (ROBO-dlgeqluf). Bytes, not a [[:space:]] class, so the locale
  # cannot change the answer.
  if (any(bytes %in% as.raw(c(0x20, 0x09, 0x0b, 0x0c)))) {
    found[[length(found) + 1L]] <- list(
      code = "rule_inner_whitespace",
      message = paste0(
        "Pattern holds a raw space or other whitespace; crawlers request it ",
        "percent-encoded (a space is %20), so this rule matches no URL they ",
        "send."
      )
    )
  }
  # ROBO-rrzsktxc: a control byte in the value is a hazard no other code owns.
  # The parser has already cut the value at a NUL, at a `#` and at the line
  # buffer, so only bytes the parser reads reach this check.
  controls <- bytes[bytes %in% validation_control_bytes]
  if (length(controls) > 0L) {
    found[[length(found) + 1L]] <- list(
      code = "rule_control_character",
      message = rule_control_character_message(controls)
    )
  }
  escaped <- rule_escaped_unreserved_diagnostic(value)
  if (!is.null(escaped)) {
    found[[length(found) + 1L]] <- escaped
  }
  found
}

# ASCII control bytes a rule value may not hold (ROBO-rrzsktxc). RFC 9309
# section 2.2 excludes 0x00-0x20 from a path pattern. NUL is read by nul_byte
# and rule_cut_by_nul, tab, VT and FF by rule_inner_whitespace, and CR and LF
# end a line; DEL (0x7F) is allowed by the RFC's %x24-7F range.
validation_control_bytes <- as.raw(c(0x01:0x08, 0x0e:0x1f))

# At most one finding per rule line, naming up to ten distinct control bytes
# as \xNN in ascending order (ROBO-rrzsktxc). `controls` holds raw bytes.
rule_control_character_message <- function(controls) {
  bytes <- sort(unique(as.integer(controls)))
  cap <- 10L
  k <- length(bytes)
  listed <- toString(sprintf("\\x%02X", bytes[seq_len(min(k, cap))]))
  if (k > cap) {
    listed <- sprintf("%s, and %d more", listed, k - cap)
  }
  lead <- if (k == 1L) {
    "Pattern holds the control byte "
  } else {
    "Pattern holds control bytes "
  }
  paste0(
    lead, listed, ". ",
    "RFC 9309 section 2.2 excludes control bytes from a path pattern, and RFC ",
    "3986 bars them from a URL, so crawlers request them percent-encoded; ",
    "Google's matcher compares the pattern as written, so this rule matches ",
    "no URL they send."
  )
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

# The parser keeps 16,663 bytes of a line: its read buffer holds kMaxLineLen - 1
# bytes (src/robots.cc, RobotsTxtParser::Parse). A byte-order mark on line 1 is
# skipped before that count.
validation_line_bytes <- 16663L

# The raw bytes of an Allow or Disallow line's value, as the parser reads
# them, before the parser escapes non-ASCII bytes (MaybeEscapePattern,
# src/robots.cc). The line is cut at its first NUL, its first `#` and at
# 16,663 bytes. The key ends at the first `:`, or, when the colon is missing,
# at the first space or tab after the leading blanks. The blanks after the
# key are kept. Nothing here is specific to a rule, so it also gives the
# raw value of a License line (rsl_license_uri()).
rule_raw_value <- function(line_bytes, first_line, missing_colon) {
  bytes <- line_bytes
  if (first_line) {
    skip <- 0L
    while (skip < min(3L, length(bytes)) &&
             bytes[[skip + 1L]] == validation_bom[[skip + 1L]]) {
      skip <- skip + 1L
    }
    bytes <- validation_raw_slice(bytes, skip + 1L, length(bytes))
  }
  nul <- match(as.raw(0x00), bytes)
  if (!is.na(nul)) {
    bytes <- bytes[seq_len(nul - 1L)]
  }
  buffer_cut <- length(bytes) > validation_line_bytes
  bytes <- bytes[seq_len(min(length(bytes), validation_line_bytes))]
  hash <- match(as.raw(0x23), bytes)
  if (!is.na(hash)) {
    bytes <- bytes[seq_len(hash - 1L)]
    buffer_cut <- FALSE
  }
  if (missing_colon) {
    blank <- as.raw(c(0x20, 0x09, 0x0a, 0x0b, 0x0c, 0x0d))
    lead <- which(!bytes %in% blank)
    bytes <- bytes[lead[[1L]]:length(bytes)]
    stop_at <- which(bytes %in% as.raw(c(0x20, 0x09)))
  } else {
    stop_at <- which(bytes == as.raw(0x3a))
  }
  value <- bytes[-seq_len(stop_at[[1L]])]
  # Whether the value ends at the line buffer, which can split a character.
  if (buffer_cut) {
    attr(value, "buffer_cut") <- TRUE
  }
  value
}

# Drops a trailing UTF-8 sequence that is incomplete, and only that: the
# lead byte and the continuation bytes after it when fewer than the lead
# byte needs. `bytes` is non-empty.
utf8_drop_cut_tail <- function(bytes) {
  n <- length(bytes)
  values <- as.integer(bytes)
  k <- n
  while (k > max(1L, n - 3L) && values[[k]] >= 0x80L && values[[k]] <= 0xBFL) {
    k <- k - 1L
  }
  lead <- values[[k]]
  need <- if (lead >= 0xF0L) 4L else if (lead >= 0xE0L) 3L else
    if (lead >= 0xC0L) 2L else 1L
  if (n - k + 1L < need) bytes[seq_len(k - 1L)] else bytes
}

# The lower-case percent-escapes of an Allow or Disallow line's value, as the
# parser keeps it, read from the raw line bytes (ROBO-kormmfyg). The parser
# upper-cases the escapes it keeps (MaybeEscapePattern, src/robots.cc), so the
# canonical value cannot show the case. A `%` followed by two hex digits is an
# escape; one with a digit in a-f is lower-case. Returns the distinct escapes
# as written, or character(0).
rule_lowercase_escapes <- function(line_bytes, first_line, missing_colon) {
  value <- rule_raw_value(line_bytes, first_line, missing_colon)
  pct <- which(value == as.raw(0x25))
  hex <- as.raw(c(0x30:0x39, 0x41:0x46, 0x61:0x66))
  pct <- pct[value[pct + 1L] %in% hex & value[pct + 2L] %in% hex]
  lower <- as.raw(0x61:0x66)
  pct <- pct[value[pct + 1L] %in% lower | value[pct + 2L] %in% lower]
  if (length(pct) == 0L) {
    return(character())
  }
  unique(vapply(pct, function(i) rawToChar(value[i:(i + 2L)]), character(1L)))
}

# At most one finding per rule line, naming up to ten lower-case escapes with
# the upper-case form Google matches (ROBO-kormmfyg).
rule_lowercase_escape_message <- function(escapes) {
  upper <- chartr("abcdef", "ABCDEF", escapes)
  if (length(escapes) == 1L) {
    return(sprintf(
      paste0("Google upper-cases the escape '%s' in a pattern but not in the ",
             "URL, so a URL written with '%s' does not match this rule; write ",
             "it as '%s'."),
      escapes, escapes, upper
    ))
  }
  cap <- 10L
  k <- length(escapes)
  items <- sprintf("'%s' for '%s'", escapes, upper)[seq_len(min(k, cap))]
  listed <- toString(items)
  if (k > cap) {
    listed <- sprintf("%s, and %d more", listed, k - cap)
  }
  paste0(
    "These escapes are lower-case: ", listed, ". Google upper-cases each ",
    "escape in a pattern but not in the URL, so a URL written with a ",
    "lower-case escape does not match this rule; write them in upper case."
  )
}

# By line, for each grouped Allow or Disallow line holding a lower-case
# escape (`escapes`, a by-line list from rule_lowercase_escapes()): the first
# line of the same group with the same type and canonical value (the parser
# upper-cases escapes) and no lower-case escape of its own, or NA
# (ROBO-nvzzjubl). Only the same group: another group may name other
# crawlers. Both lines must be patterns led by `/` or `*` and hold no NUL
# (Bing reads a NUL as a byte, so a cut value is no twin there), and the
# twin must spell each escape in upper case, not as a raw byte (`/é` is not
# the twin of `/%C3%a9`). `raw_lines` and `nul_counts` are by line. An
# integer vector as long as `escapes`.
rule_lowercase_escape_twins <- function(rules, escapes, raw_lines,
                                        nul_counts) {
  twin <- rep(NA_integer_, length(escapes))
  usable <- substr(rules$value, 1L, 1L) %in% c("/", "*") &
    nul_counts[rules$line] == 0L
  rules <- rules[usable, , drop = FALSE]
  if (nrow(rules) == 0L) {
    return(twin)
  }
  lower <- lengths(escapes[rules$line]) > 0L
  key <- paste(rules$group, rules$type, rules$value, sep = "\n")
  found <- rules$line[!lower][match(key[lower], key[!lower])]
  lines <- rules$line[lower]
  spelled <- vapply(seq_along(lines), function(k) {
    if (is.na(found[[k]])) {
      return(FALSE)
    }
    upper <- chartr("abcdef", "ABCDEF", escapes[[lines[[k]]]])
    all(vapply(upper, function(e) {
      length(grepRaw(e, raw_lines[[found[[k]]]], fixed = TRUE)) > 0L
    }, logical(1L)))
  }, logical(1L))
  twin[lines[spelled]] <- found[spelled]
  twin
}

# The info row of a lower-case-escape line whose upper-case twin is `twin`
# (ROBO-nvzzjubl): Google and Bing upper-case the escape, so the line repeats
# the twin there and a URL written with the escape matches neither; the
# package's Yandex matcher compares the pattern as written (ROBO-kormmfyg).
rule_lowercase_escape_twin_message <- function(escapes, twin) {
  cap <- 10L
  k <- length(escapes)
  listed <- toString(sprintf("'%s'", escapes[seq_len(min(k, cap))]))
  if (k > cap) {
    listed <- sprintf("%s, and %d more", listed, k - cap)
  }
  one <- k == 1L
  sprintf(
    paste0(
      "Line %d has this rule with the %s in upper case. Google and Bing ",
      "upper-case the %s %s in a pattern, so there this line is the same ",
      "rule as line %d, and a URL written with %s matches neither. The ",
      "package's Yandex matcher compares the pattern as written, so there ",
      "this line ",
      "matches URLs written with %s, which line %d does not."
    ),
    twin, if (one) "escape" else "escapes", if (one) "escape" else "escapes",
    listed, twin, if (one) listed else "these lower-case escapes",
    if (one) listed else "them", twin
  )
}

# Unicode advisories (ROBO-qxcwxtbm). The set is closed and defined
# from Unicode properties, not from any engine's character list: U+FFFD; the
# invisible or format characters below (soft hyphen, zero-width and
# directional marks, bidi embeddings and isolates, word joiner and invisible
# operators, a byte-order mark inside a value, and the C1 controls, which
# rule_control_character, ASCII only, does not cover); and Latin-1 mojibake.
validation_unicode_advisory_cap <- 100L
validation_invisible_code_points <- c(
  0x0080:0x009F, 0x00AD, 0x200B:0x200F, 0x202A:0x202E, 0x2060:0x2064,
  0x2066:0x2069, 0xFEFF
)

# Info findings for one rule's raw value bytes, as a list of list(code,
# message): at most one per family, in the order replacement, invisible,
# mojibake. Only a value that is valid UTF-8 is read; invalid_utf8 owns the
# rest. A character the line buffer splits is dropped first, so the cut
# alone does not make the value invalid. Offsets count bytes from 1 at the
# value's first byte after the blanks that follow the colon. A U+200B or
# U+FEFF that leads the value is left to rule_missing_leading_slash, whose
# message names it.
rule_unicode_advisories <- function(value) {
  buffer_cut <- isTRUE(attr(value, "buffer_cut"))
  start <- which(!value %in% as.raw(c(0x20, 0x09, 0x0b, 0x0c)))
  if (length(start) == 0L || all(as.integer(value) < 0x80L)) {
    return(list())
  }
  value <- value[start[[1L]]:length(value)]
  if (buffer_cut) {
    value <- utf8_drop_cut_tail(value)
    if (length(value) == 0L) {
      return(list())
    }
  }
  text <- rawToChar(value)
  if (!validUTF8(text)) {
    return(list())
  }
  points <- utf8ToInt(text)
  widths <- 1L + (points >= 0x80) + (points >= 0x800) + (points >= 0x10000)
  offsets <- cumsum(c(1L, widths))[seq_along(points)]
  found <- list()

  replacement <- which(points == 0xFFFD)
  if (length(replacement) > 0L) {
    found[[length(found) + 1L]] <- list(
      code = "rule_replacement_character",
      message = paste0(
        "Pattern holds the replacement character: U+FFFD first at byte ",
        offsets[[replacement[[1L]]]], ". A decoder writes it for bytes it ",
        "could not read, so an earlier conversion may have lost the original ",
        "characters, or it may be meant. ", validation_unicode_advisory_tail
      )
    )
  }

  invisible <- points %in% validation_invisible_code_points
  if (points[[1L]] %in% names_to_points(validation_invisible_prefixes)) {
    invisible[[1L]] <- FALSE
  }
  if (any(invisible)) {
    distinct <- sort(unique(points[invisible]))
    first <- offsets[invisible][match(distinct, points[invisible])]
    items <- sprintf("U+%04X first at byte %d", distinct, first)
    words <- if (length(items) == 1L) {
      c("Pattern holds an invisible or formatting character: ", "It may",
        "it is", "it", "it")
    } else {
      c("Pattern holds invisible or formatting characters: ", "They may",
        "they are", "them", "them")
    }
    found[[length(found) + 1L]] <- list(
      code = "rule_invisible_character",
      message = paste0(
        words[[1L]], unicode_advisory_list(items), ". ", words[[2L]],
        " be meant, but ", words[[3L]], " easy to paste unseen, and the ",
        "matcher compares ", words[[4L]], " byte for byte, so a URL without ",
        words[[5L]], " may not match. ", validation_unicode_advisory_tail
      )
    )
  }

  units <- mojibake_units(points)
  if (length(units) >= 2L) {
    items <- vapply(units, function(unit) {
      sprintf("%s at byte %d", paste(sprintf("U+%04X", points[unit]),
                                     collapse = " "),
              offsets[[unit[[1L]]]])
    }, character(1L))
    found[[length(found) + 1L]] <- list(
      code = "rule_possible_mojibake",
      message = paste0(
        "Pattern holds sequences that read like UTF-8 decoded as Latin-1 and ",
        "encoded again (possible mojibake): ", unicode_advisory_list(items),
        ". This is a heuristic: the text may be meant as written and its ",
        "original cannot be known. ", validation_unicode_advisory_tail
      )
    )
  }
  found
}

validation_unicode_advisory_tail <- paste0(
  "Valid UTF-8 can neither prove nor disprove corruption; this advisory ",
  "changes no match."
)

# The code points of validation_invisible_prefixes' names ("U+200B"). The
# names are the only place that object holds them: its values are the
# parser's %XX escapes of the UTF-8 bytes.
names_to_points <- function(prefixes) {
  strtoi(substring(names(prefixes), 3L), 16L)
}

# Up to ten items, then ", and N more", as rule_control_character_message().
unicode_advisory_list <- function(items) {
  cap <- 10L
  k <- length(items)
  listed <- toString(items[seq_len(min(k, cap))])
  if (k > cap) {
    listed <- sprintf("%s, and %d more", listed, k - cap)
  }
  listed
}

# Latin-1 mojibake: a UTF-8 sequence whose bytes were each read as a Latin-1
# character and encoded again. Each unit is a code point U+00C2 to U+00F4
# (a lead byte) followed by the one to three code points U+0080 to U+00BF
# (continuation bytes) it needs, whose bytes together are well-formed UTF-8;
# U+00C3 U+00A9 is a mojibake e-acute. Units do not overlap. Returns a list
# of index vectors into `points`.
mojibake_units <- function(points) {
  units <- list()
  n <- length(points)
  next_free <- 1L
  for (i in which(points >= 0xC2 & points <= 0xF4)) {
    if (i < next_free) {
      next
    }
    lead <- points[[i]]
    need <- if (lead <= 0xDF) 1L else if (lead <= 0xEF) 2L else 3L
    if (i + need > n) {
      next
    }
    unit <- i:(i + need)
    tail <- points[unit[-1L]]
    if (all(tail >= 0x80 & tail <= 0xBF) &&
          validUTF8(rawToChar(as.raw(points[unit])))) {
      units[[length(units) + 1L]] <- unit
      next_free <- i + need + 1L
    }
  }
  units
}

# Look-alike characters (ROBO-wtixhwlo): a closed, hand-written table of
# code points that look like an ASCII `-`, `_` or letter, with the Unicode
# name and the ASCII each resembles. The hyphens and dashes are the
# characters a paste turns `-` into; the letters are a closed subset of
# common Cyrillic and Greek look-alikes, each one that Unicode's
# confusables.txt (UTS #39) maps to one ASCII letter. It is not the whole
# of that file, and the list grows only by hand. U+00AD SOFT HYPHEN is
# invisible (as validation_invisible_code_points has it), so it resembles
# nothing and is dropped from the spelling.
# Latin letters with diacritics are not look-alikes.
validation_lookalike_code_points <- data.frame(
  point = c(
    0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212, 0xFE58,
    0xFE63, 0xFF0D, 0xFF3F, 0x00AD,
    0x0430, 0x0435, 0x043E, 0x0440, 0x0441, 0x0443, 0x0445, 0x0456,
    0x0458, 0x0455, 0x0501,
    0x0410, 0x0412, 0x0415, 0x041A, 0x041C, 0x041D, 0x041E, 0x0420,
    0x0421, 0x0422, 0x0425, 0x0406, 0x0408, 0x0405,
    0x0391, 0x0392, 0x0395, 0x0396, 0x0397, 0x0399, 0x039A, 0x039C,
    0x039D, 0x039F, 0x03A1, 0x03A4, 0x03A5, 0x03A7, 0x03BF
  ),
  name = c(
    "HYPHEN", "NON-BREAKING HYPHEN", "FIGURE DASH", "EN DASH", "EM DASH",
    "HORIZONTAL BAR", "MINUS SIGN", "SMALL EM DASH", "SMALL HYPHEN-MINUS",
    "FULLWIDTH HYPHEN-MINUS", "FULLWIDTH LOW LINE", "SOFT HYPHEN",
    paste("CYRILLIC SMALL LETTER", c(
      "A", "IE", "O", "ER", "ES", "U", "HA", "BYELORUSSIAN-UKRAINIAN I",
      "JE", "DZE", "KOMI DE"
    )),
    paste("CYRILLIC CAPITAL LETTER", c(
      "A", "VE", "IE", "KA", "EM", "EN", "O", "ER", "ES", "TE", "HA",
      "BYELORUSSIAN-UKRAINIAN I", "JE", "DZE"
    )),
    paste("GREEK CAPITAL LETTER", c(
      "ALPHA", "BETA", "EPSILON", "ZETA", "ETA", "IOTA", "KAPPA", "MU",
      "NU", "OMICRON", "RHO", "TAU", "UPSILON", "CHI"
    )),
    "GREEK SMALL LETTER OMICRON"
  ),
  ascii = c(
    rep("-", 10L), "_", "",
    "a", "e", "o", "p", "c", "y", "x", "i", "j", "s", "d",
    "A", "B", "E", "K", "M", "H", "O", "P", "C", "T", "X", "I", "J", "S",
    "A", "B", "E", "Z", "H", "I", "K", "M", "N", "O", "P", "T", "Y", "X",
    "o"
  ),
  stringsAsFactors = FALSE
)

# The User-agent values of `agent_rows` (from validation_groups()) as the
# parser kept them, for lookalike_note(). Where the value itself reaches
# the 16,663-byte line buffer (rule_raw_value() says so: not when a `#`,
# a NUL or trailing blanks end it first), the buffer can split its last
# character, and that tail is dropped so the cut alone does not make the
# value invalid UTF-8. Without `raw_lines` nothing is dropped.
lookalike_agent_values <- function(agent_rows, agent_bytes, raw_lines) {
  values <- as.character(agent_rows$value)
  long <- agent_rows$line_too_long
  if (is.null(raw_lines) || is.null(long)) {
    return(values)
  }
  for (k in which(lengths(agent_bytes) > 0L & !is.na(long) & long)) {
    line <- agent_rows$line[[k]]
    raw <- rule_raw_value(raw_lines[[line]], line == 1L,
                          agent_rows$missing_colon[[k]])
    # Trailing blanks the parser trims sit before the buffer's end too. A
    # buffer cut leaves the value its non-empty parser bytes, so `raw` has
    # a last byte.
    reaches <- isTRUE(attr(raw, "buffer_cut")) &&
      !raw[[length(raw)]] %in% as.raw(c(0x20, 0x09, 0x0a:0x0d))
    if (reaches && lookalike_split_completes(agent_bytes[[k]],
                                             raw_lines[[line]], line == 1L)) {
      values[[k]] <- rawToChar(utf8_drop_cut_tail(agent_bytes[[k]]))
    }
  }
  values
}

# Whether the incomplete UTF-8 tail of a value that reaches the line buffer
# (`bytes`) is a character the buffer split: the line's bytes just past the
# buffer (`line_bytes`, after the byte-order mark Parse() skips on line 1)
# complete it as valid UTF-8. A lone lead byte followed by ASCII is invalid
# as written and keeps today's handling.
lookalike_split_completes <- function(bytes, line_bytes, first_line) {
  kept <- length(utf8_drop_cut_tail(bytes))
  dropped <- length(bytes) - kept
  if (dropped == 0L) {
    return(FALSE)
  }
  tail <- bytes[(kept + 1L):length(bytes)]
  lead <- as.integer(tail[[1L]])
  need <- if (lead >= 0xF0L) 4L else if (lead >= 0xE0L) 3L else 2L
  skip <- 0L
  if (first_line) {
    while (skip < min(3L, length(line_bytes)) &&
             line_bytes[[skip + 1L]] == validation_bom[[skip + 1L]]) {
      skip <- skip + 1L
    }
  }
  at <- skip + validation_line_bytes + seq_len(need - dropped)
  if (max(at) > length(line_bytes)) {
    return(FALSE)
  }
  after <- line_bytes[at]
  all(after != as.raw(0x00)) && validUTF8(rawToChar(c(tail, after)))
}

# The look-alike sentence for one value or key (`text`, as the parser kept
# it; `noun` names it in the message), or NULL when it holds no look-alike.
# Only text that is valid UTF-8 is read; a bytes-marked string keeps today's
# text. Each distinct look-alike is named by code point and Unicode name
# with its first byte offset, counted from 1 at the first byte, at most ten
# (unicode_advisory_list()); the message stays ASCII. Returns
# list(sentence, spelled): `spelled` is the text with each look-alike
# replaced by its ASCII (an invisible one dropped), for the caller to
# compare; the sentence quotes it rendered as render_validation_line()
# does. One pass over the text's bytes and code points.
lookalike_note <- function(text, noun) {
  bytes <- charToRaw(text)
  # A speed path only: ASCII text holds no look-alike, and most values are
  # ASCII.
  if (length(bytes) == 0L || all(as.integer(bytes) < 0x80L)) {
    return(NULL)
  }
  # utf8ToInt() reads the bytes as written (rawToChar() drops any mark) and
  # gives a single NA for text that is not valid UTF-8, which matches no
  # table row, so such text, a bytes-marked key among it, returns NULL
  # below.
  points <- utf8ToInt(rawToChar(bytes))
  table <- validation_lookalike_code_points
  at <- match(points, table$point)
  hit <- which(!is.na(at))
  if (length(hit) == 0L) {
    return(NULL)
  }
  widths <- 1L + (points >= 0x80) + (points >= 0x800) + (points >= 0x10000)
  offsets <- cumsum(c(1L, widths))[seq_along(points)]
  first <- hit[!duplicated(points[hit])]
  row <- at[first]
  ascii <- table$ascii[row]
  invisible <- !nzchar(ascii)
  spelled_points <- as.list(points)
  spelled_points[hit] <- lapply(table$ascii[at[hit]], utf8ToInt)
  spelled <- intToUtf8(unlist(spelled_points, use.names = FALSE))
  shown <- render_validation_line(charToRaw(spelled))
  named <- sprintf("U+%04X %s at byte %d", points[first], table$name[row],
                   offsets[first])
  one <- length(first) == 1L
  # How the spelling was made. The table holds one invisible character, so
  # only a single look-alike can be all invisible ("without it"). Other
  # non-ASCII characters are kept as written, and the words say whether a
  # look-alike was replaced, dropped, or both.
  spelling <- if (all(invisible)) {
    "without it"
  } else if (all(charToRaw(spelled) < as.raw(0x80))) {
    "written in ASCII"
  } else if (one) {
    "with ASCII in its place"
  } else if (any(invisible)) {
    "with ASCII for the look-alikes and the invisible one dropped"
  } else {
    "with ASCII in their place"
  }
  held <- if (one) {
    paste0(named, ", which ", if (invisible) "is invisible" else
      sprintf("looks like '%s'", ascii))
  } else {
    paste0("characters that look like ASCII",
           if (any(invisible)) " or are invisible", ": ",
           unicode_advisory_list(paste0(named, ifelse(
             invisible, " (invisible)", sprintf(" (looks like '%s')", ascii)
           ))))
  }
  list(sentence = sprintf("The %s holds %s; %s the %s is '%s'", noun, held,
                          spelling, noun, shown),
       spelled = spelled)
}

# By cut row, the look-alike sentences of its written value (`values`, as
# the parser kept them), or "" (ROBO-wtixhwlo). The ASCII spelling is
# what a matcher that compares bytes would need, so the sentence says none
# matches. Bing or Yandex is named only when the spelling, folded to ASCII
# lower case, is one of the crawlers its backend evaluates
# (duplicate_rule_cut_engines()), read once per call.
user_agent_lookalike_notes <- function(values) {
  notes <- lapply(values, lookalike_note, noun = "value")
  found <- !vapply(notes, is.null, logical(1L))
  out <- character(length(values))
  if (!any(found)) {
    return(out)
  }
  engines <- duplicate_rule_cut_engines()
  out[found] <- vapply(notes[found], function(note) {
    folded <- ascii_lower(note$spelled)
    named <- names(engines)[vapply(engines, function(accepted) {
      folded %in% accepted
    }, logical(1L))]
    paste0(
      note$sentence, ", which no byte compare matches to this value.",
      if (length(named) > 0L) {
        sprintf(paste0(" The package's %s matcher compares the whole value ",
                       "as written, so there '%s' does not match this line ",
                       "either."), named[[1L]],
                render_validation_line(charToRaw(note$spelled)))
      }
    )
  }, "")
  out
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

# TRUE when a line's bytes are well-formed UTF-8, NUL bytes included: each
# run of bytes between NULs must be well-formed on its own, since a NUL is a
# character of its own and cannot sit inside a multi-byte sequence
# (ROBO-xuusttbp). `rawToChar()` refuses an embedded NUL, so the runs are
# checked one by one.
validation_utf8_line <- function(line_bytes) {
  nul <- which(line_bytes == as.raw(0x00))
  if (length(nul) == 0L) {
    return(validUTF8(rawToChar(line_bytes)))
  }
  starts <- c(1L, nul + 1L)
  ends <- c(nul - 1L, length(line_bytes))
  all(vapply(seq_along(starts), function(k) {
    validUTF8(rawToChar(validation_raw_slice(line_bytes, starts[[k]],
                                             ends[[k]])))
  }, logical(1L)))
}

# TRUE when the first NUL of a line the parser reads as a non-empty rule
# lies before the line's first `#` and inside the parser's line buffer. The
# parser and Google's matcher end the line there (ROBO-pvqrfvol), so
# `Disallow: /private\0-drafts/` is the rule `/private`, as `#` cuts
# `Disallow: /a#b`; the Bing and Yandex matchers read the NUL as a byte of
# the rule, even a trailing one (`/a\0`), so they read another rule
# (ROBO-xuusttbp). A NUL in a comment, which every engine cuts away, or past
# the buffer, which the parser never read, is not counted. The caller checks
# that the value is non-empty, so the NUL lies after the value's start.
rule_cut_by_nul <- function(raw_line) {
  nul <- match(as.raw(0x00), raw_line)
  hash <- match(as.raw(0x23), raw_line)
  !is.na(nul) && nul <= validation_line_bytes && (is.na(hash) || nul < hash)
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

validate_fetched_documents <- function(fetched, safety_level = "strict") {
  documents <- list()
  diagnostics <- list()
  robots <- fetched$robots
  for (i in seq_len(nrow(robots))) {
    validated <- validate_fetched_source(robots, i, safety_level)
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
  destinations <- NULL
  if (!is.null(fetched$destinations)) {
    destinations <- validate_destination_documents(fetched, safety_level)
  }
  new_robots_validations(
    map, document_frame, diagnostic_frame, destinations
  )
}

# The opt-in destination components (ROBO-ybhwztid): each destination row
# validated by the per-source path origin rows take, kept apart from the
# origin's documents and diagnostics.
validate_destination_documents <- function(fetched, safety_level) {
  rows <- fetched$destinations
  validated <- lapply(seq_len(nrow(rows)), function(i) {
    validate_fetched_source(rows, i, safety_level)
  })
  documents <- lapply(validated, function(v) v$document)
  diagnostics <- Filter(
    function(d) nrow(d) > 0L, lapply(validated, function(v) v$diagnostics)
  )
  list(
    destination_documents = if (length(documents) == 0L) {
      empty_validation_documents()
    } else {
      do.call(rbind, documents)
    },
    destination_diagnostics = if (length(diagnostics) == 0L) {
      empty_validation_diagnostics()
    } else {
      do.call(rbind, diagnostics)
    },
    destination_map = fetched$destination_map
  )
}

# The validated document and its diagnostics for row `i` of a source frame
# (`robots` or `destinations`): a stored body is validated, then given its
# redirect and Content-Type rows; a source with no body gets its acquisition
# row.
validate_fetched_source <- function(robots, i, safety_level = "strict") {
  source <- robots[i, , drop = FALSE]
  body <- robots$body[[i]]
  if (is.null(body)) {
    return(unavailable_validation(source, safety_level = safety_level))
  }
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
  redirect <- redirect_host_diagnostic(source)
  if (!is.null(redirect)) {
    validated <- add_document_diagnostic(validated, redirect)
  }
  downgrade <- redirect_downgrade_diagnostic(source)
  if (!is.null(downgrade)) {
    validated <- add_document_diagnostic(validated, downgrade)
  }
  header_rows <- content_type_diagnostics(
    source$source_id, source$content_type, body,
    validated$document$encoding_signature
  )
  for (header_row in header_rows) {
    validated <- add_document_diagnostic(validated, header_row)
  }
  validated
}

unavailable_validation <- function(source, safety_level = "strict") {
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
    diagnosis <- acquisition_diagnosis(source, safety_level = safety_level)
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
#   message says so instead of giving an engine verdict. The exception is an
#   address-class refusal under `safety_level = "crawler"` (ROBO-akfbbake):
#   no public crawler could reach that address either, so its message reads
#   it as an unreachable file, with each engine's unreachable_local reading.
acquisition_diagnosis <- function(source, safety_level = "strict") {
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
    if (identical(safety_level, "crawler") &&
          safety %in% acquire_address_class_reasons()) {
      detail <- sprintf(paste(
        "robotstxtr's safety refusal (safety_block_reason \"%s\") of an",
        "internal address, which a public crawler could not reach either;",
        "read as an unreachable file: %s."
      ), safety, status_engine_readings("unreachable_local"))
    } else {
      detail <- sprintf(paste(
        "robotstxtr's safety refusal (safety_block_reason \"%s\"); nothing",
        "was requested there, so no engine reading applies."
      ), safety)
    }
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

# The diagnostic row for a robots.txt fetch that succeeded after redirecting
# away from the robots.txt URL (ROBO-gokbvzcb), or NULL. It reads only the
# source row's `robots_url`, `effective_url` and `content_flag`; the fetch
# itself is unchanged. Hosts are compared idna-encoded and ASCII-lowercased.
#
# - Same host, the path still /robots.txt (a scheme or port change, such as
#   http to https): silent, the usual case.
# - Same host, another path: `redirect_other_path`, info, or a warning when
#   the landing page is HTML (a catch-all to a page).
# - Another host, same registrable domain (www and apex, or another
#   subdomain): `redirect_same_site`, info, or a warning when the landing
#   page is HTML.
# - Another registrable domain: `redirect_cross_site`, warning: the rules
#   applied are another site's.
#
# The registrable domain comes from the Public Suffix List through
# rurl::get_domain() (so a.example.co.uk and b.example.co.uk are one site); an
# IP literal, or a host with no registrable domain, is compared whole. The
# engine readings are design/engine-profiles.md, section 3, "Within budget".
redirect_host_diagnostic <- function(source) {
  if (identical(source$robots_url, source$effective_url)) {
    return(NULL)
  }
  from <- redirect_url_parts(source$robots_url)
  to <- redirect_url_parts(source$effective_url)
  if (is.null(from) || is.null(to)) {
    return(NULL)
  }
  same_host <- identical(from$host, to$host)
  if (same_host && identical(to$path, from$path)) {
    return(NULL)
  }
  html <- identical(source$content_flag, "html")
  if (same_host) {
    code <- "redirect_other_path"
    severity <- if (html) "warning" else "info"
    where <- "another path on the same host"
  } else if (identical(redirect_site_key(from$host),
                       redirect_site_key(to$host))) {
    code <- "redirect_same_site"
    severity <- if (html) "warning" else "info"
    where <- "another host of the same site"
  } else {
    code <- "redirect_cross_site"
    severity <- "warning"
    where <- "another site"
  }
  message <- sprintf(
    paste0(
      "The robots.txt at %s redirected to %s, %s. RFC 9309 (documented) and ",
      "Yandex (documented, if the target answers 200) apply the file reached ",
      "to the requested host, Google is inferred to do the same, and Bing is ",
      "not documented."
    ),
    source$robots_url, source$effective_url, where
  )
  if (html) {
    message <- paste(
      message,
      "The page reached is HTML, so the site's robots.txt is effectively",
      "missing; any lines on it were read as directives anyway."
    )
  }
  validation_diagnostic(
    source$source_id, NA_integer_, severity, code, NA_character_,
    NA_character_, message
  )
}

# The diagnostic row for a fetch that followed at least one https to http
# redirect (ROBO-cscdbael), or NULL. Only `safety_level = "crawler"` follows
# one; `strict` refuses it as `acquisition_redirect_downgrade`, with no body.
# It reads the source row's hop log, `redirect_hops`, so a downgrade in the
# middle of the chain counts too. The log also holds a hop that was not
# followed (a refused, over-budget or looping one), so only the first
# `redirect_count` hops are read. One row names every followed downgrade as
# "from -> to"; the URLs are printed as stored. Severity info: no engine
# conditions a redirect on its scheme (design/engine-profiles.md, section 3,
# "Within budget").
redirect_downgrade_diagnostic <- function(source) {
  hops <- source$redirect_hops[[1L]]
  count <- source$redirect_count
  if (length(hops) == 0L || length(count) != 1L || is.na(count)) {
    return(NULL)
  }
  followed <- hops[seq_len(min(count, length(hops)))]
  downgrades <- Filter(function(hop) {
    identical(redirect_url_scheme(hop$from_url), "https") &&
      identical(redirect_url_scheme(hop$location_target), "http")
  }, followed)
  if (length(downgrades) == 0L) {
    return(NULL)
  }
  pairs <- vapply(downgrades, function(hop) {
    paste(hop$from_url, "->", hop$location_target)
  }, character(1L))
  message <- sprintf(
    paste0(
      "The fetch followed an https to http redirect (%s), so part of the ",
      "redirect chain went over plain http. RFC 9309, Google and Yandex ",
      "place no scheme ",
      "condition on a redirect and are inferred to follow it; Bing is not ",
      "documented."
    ),
    toString(pairs)
  )
  validation_diagnostic(
    source$source_id, NA_integer_, "info", "redirect_downgrade_followed",
    NA_character_, NA_character_, message
  )
}

# The ASCII-lowercased scheme of a URL, or NA when it has none.
redirect_url_scheme <- function(url) {
  if (!is.character(url) || length(url) != 1L || is.na(url)) {
    return(NA_character_)
  }
  # Bytes, not characters: a raw Location may not be valid UTF-8.
  # Leading C0 controls and spaces are stripped, as WHATWG URL parsing does.
  url <- sub("^[\001-\040]+", "", url, useBytes = TRUE)
  match <- regmatches(
    url, regexec("^([A-Za-z][A-Za-z0-9+.-]*):", url, useBytes = TRUE)
  )[[1L]]
  if (length(match) != 2L) {
    return(NA_character_)
  }
  ascii_lower(match[[2L]])
}

# The ASCII-lowercased idna host and the path of a URL, or NULL when it does
# not parse to a host.
redirect_url_parts <- function(url) {
  if (length(url) != 1L || is.na(url)) {
    return(NULL)
  }
  parsed <- tryCatch(
    rurl::safe_parse_url(url, host_encoding = "idna"),
    error = function(e) NULL
  )
  host <- parsed$host
  if (!is.character(host) || length(host) != 1L || is.na(host) ||
        !nzchar(host)) {
    return(NULL)
  }
  path <- parsed$path
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
        !nzchar(path)) {
    path <- "/"
  }
  # A fully qualified name's root dot is the same host (as ssrfr's
  # normalize_host_name reads it), and get_domain() finds no domain with it.
  host <- sub("\\.$", "", ascii_lower(host))
  if (!nzchar(host)) {
    return(NULL)
  }
  list(host = host, path = path)
}

# The registrable domain of a host, or the whole host when it has none (an IP
# literal, a public suffix, or a name under no listed suffix).
redirect_site_key <- function(host) {
  domain <- tryCatch(rurl::get_domain(host), error = function(e) NA_character_)
  if (length(domain) != 1L || is.na(domain) || !nzchar(domain)) {
    return(host)
  }
  ascii_lower(domain)
}

# Appends one diagnostic row to a validated document and recounts its row.
add_document_diagnostic <- function(validated, diagnostic) {
  diagnostics <- rbind(validated$diagnostics, diagnostic)
  document <- validated$document
  document$validation_status <- validation_status(diagnostics)
  document$diagnostic_count <- as.integer(nrow(diagnostics))
  document$warning_count <- as.integer(sum(diagnostics$severity == "warning"))
  document$error_count <- as.integer(sum(diagnostics$severity == "error"))
  list(document = document, diagnostics = diagnostics)
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
  } else if (identical(status, "evaluated") &&
               identical(action, "use_rules") &&
               identical(category, "status_other_2xx")) {
    # A 2xx other than 200 whose body a ruleset reads (ROBO-yvhqvthd). Google
    # documents it (design/engine-profiles.md section 4, other 2xx row); the
    # wording follows the cell's action, so a table edit that gives another
    # engine `use_rules` here still gets a phrase.
    "reads the body's rules as for a 200"
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
    encoding_signature = character(),
    encoding_signature_basis = character(),
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
