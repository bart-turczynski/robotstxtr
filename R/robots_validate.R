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
#'   \code{compressed_body} \tab error \tab
#'     The body starts with a compression signature: gzip (\code{1f 8b}),
#'     Zstandard (\code{28 b5 2f fd}), or a zlib header (\code{78} then
#'     \code{01}, \code{5e}, \code{9c} or \code{da}) whose second byte and
#'     the 16 after it are not well-formed UTF-8, so text that starts
#'     \code{x^} is not flagged, even with a Latin-1 byte after its first 18
#'     bytes. A zlib header \code{78 01} that opens a stored deflate block,
#'     its length then that length's ones' complement (RFC 1951 section
#'     3.2.4), is flagged whatever those bytes read as.
#'     Its bytes are not read as
#'     lines: this row replaces every line, group and rule check,
#'     \code{no_rules} included, and only \code{body_truncated},
#'     \code{acquisition_http_other_2xx} and the \code{redirect_} and
#'     \code{content_type_} rows (except
#'     \code{content_type_charset_conflict}) can join it. In
#'     \code{documents}, the byte facts (\code{byte_size}, \code{line_count},
#'     \code{encoding}, \code{has_bom}, \code{nul_byte_count},
#'     \code{final_newline}) are kept, and every directive count,
#'     \code{active_line_count} and \code{malformed_lines} are 0; on a body
#'     cut at \code{max_bytes}, the byte facts describe the stored bytes as
#'     cut, no partial line dropped. Decode the body first; the body is not
#'     decompressed, and raw deflate and brotli bodies are not detected. \cr
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
#'     \code{User-agent: *}, else no rules. A warning in two cases: the
#'     value holds a look-alike character (below), whatever the token, as
#'     no byte compare matches it; or the token read is a documented Google
#'     crawler token the value did not mean (\code{Googlebot Image}, read
#'     as \code{Googlebot}). Otherwise info: a version suffix
#'     (\code{Googlebot/2.1}) or a trailing \code{*}, as the token read is
#'     the crawler the value names, and any other token, as Google's
#'     crawlers do not go by it. The Bing and Yandex
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
#'     A pattern not led by \code{/} or \code{*}; it never matches. A full
#'     \code{http} or \code{https} URL gets a message naming the path and
#'     query to write instead; under [robots_validate_url()] it also says
#'     when the URL's origin differs from the robots.txt origin, only when
#'     the URL's host is ASCII. \cr
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
#'   \code{rule_dot_segment} \tab warning \tab
#'     A pattern holds a \code{.} or \code{..} path segment, after a
#'     \code{/} and before a \code{/}, a \code{?} or a final \code{$}. Some
#'     URL parsers remove dot segments before requesting (RFC 3986 section
#'     5.2.4), so the rule may never match; the v1 evaluators' default
#'     \code{url_normalization = "rfc3986"} removes the segment from the URL
#'     too (ADR 0002). Not checked past a \code{?} or a \code{*}; an escaped
#'     \code{\%2E} is not a dot here. One per rule line. \cr
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
#'   \code{rule_invalid_percent_escape} \tab warning \tab
#'     A pattern holds a \code{\%} that starts no two-hex-digit escape. The
#'     package's Google, Bing and Yandex matchers compare it as written, and
#'     a URL writes a literal \code{\%} as \code{\%25}, so the rule matches
#'     only URLs that carry the raw \code{\%}. A value holding a
#'     \code{\%name\%} placeholder, read as written in the file, gets that
#'     message with the placeholder named, whatever the hex digits: Google
#'     and Bing upper-case a name led by an escape, so \code{\%date\%} matches
#'     \code{\%DAte\%} there and \code{\%date\%} on Yandex. A name of only
#'     two hex digits, as in \code{\%A9\%}, is an escape and no placeholder. A
#'     \code{\%}, or \code{\%} and one hex digit, at the pattern's end or
#'     before a \code{*} matches any escape it begins, which may be meant,
#'     and gets its own message; the matchers compare the digit's case, so a
#'     lower-case digit matches only lower-case escapes, which RFC 3986
#'     section 2.1 advises against. When a NUL cuts the value, the message
#'     says that Google ends the rule there while Bing and Yandex read the
#'     NUL as a byte of the rule. One per rule line, naming up to ten
#'     \code{\%} with the two bytes after each, quoted as written in the
#'     file; a control or non-ASCII byte, or a single quote, is shown by its
#'     hex code. \cr
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
#'   \code{user_agent_groups_same_rules} \tab info \tab
#'     Separate groups written in plain User-agent, Allow and Disallow lines
#'     give their crawlers the same rules, as written, so their User-agent
#'     lines could be stacked in one group (RFC 9309 section 2.2.1).
#'     Optional cleanup. Anchored on the first group's first line; the
#'     message names the other groups and the stacked group. \cr
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
#'   \code{rule_query_parameter_position} \tab info \tab
#'     An Allow or Disallow pattern names a query parameter right after its
#'     first \code{?} (\code{/items/*?sort=}), so it may miss URLs where that
#'     parameter follows another one (\code{/items/x?a=1&sort=}); for an
#'     Allow, the gap can leave such URLs restricted. The message shows one
#'     such URL. Not reported when the same crawlers also have the rule
#'     with that \code{?} written \code{*&}, or written \code{&} when a
#'     \code{*} stands right before that \code{?} (\code{/*?sort=}, not
#'     \code{/a*b?sort=}). \cr
#'   \code{rule_query_crawl_not_index} \tab info \tab
#'     A Disallow pattern holds \code{?}, \code{=} or \code{&}, so it may
#'     target URL parameters. The note says robots.txt controls crawling,
#'     not indexing: a blocked URL may still be indexed without its content,
#'     a page-level noindex works only on a page the crawler may fetch, and
#'     \code{rel=canonical} consolidates rather than excludes. One row per
#'     file, on the first such line, listing five lines at most, then a
#'     count. A heuristic on the pattern text. \cr
#'   \code{rule_slash_pair} \tab info \tab
#'     The same crawlers have a literal Allow or Disallow pattern both
#'     without and with a trailing \code{/} (\code{/notes} and
#'     \code{/notes/}). The bare pattern also matches every path the slash
#'     pattern matches, the bare URL and paths that go on without a
#'     \code{/}. Anchored on the later line; the message names the earlier
#'     one and calls neither redundant. \cr
#'   \code{rule_slash_split} \tab info \tab
#'     A crawler gets a different decision for the bare URL \code{P} than
#'     for the slash URL \code{P/} of a literal rule \code{P/}, which a
#'     server redirect between them makes matter. An Allow that opens
#'     \code{P/} while \code{P} stays disallowed is anchored on the Allow
#'     line; Disallows that block \code{P/} while \code{P} stays allowed get
#'     one row per group of crawlers, on its first User-agent line, listing
#'     five rules at most, then a count. On a file whose rules and crawlers
#'     would make the check costly, candidates past a fixed amount of work,
#'     linear in the file's rules, get no row, and
#'     \code{rule_check_stopped} says so. \cr
#'   \code{rule_end_anchor_query} \tab info \tab
#'     A Disallow whose pattern ends in \code{$} and holds no \code{?}
#'     (\code{/x/edit$}) blocks its path but not the same path with a query
#'     added (\code{/x/edit?x=1}): the \code{$} ends the match at the end of
#'     the path and query together. Reported only when the rule decides the
#'     path and the query URL comes out allowed under every rule the
#'     crawlers have. One row per group of crawlers, on its first User-agent
#'     line, listing five rules at most, then a count. Past a fixed amount
#'     of work, as for \code{rule_slash_split}, candidates get no row and
#'     \code{rule_check_stopped} says so. \cr
#'   \code{allow_reopens_through_query} \tab info \tab
#'     An Allow that opens with \code{*} or \code{/*} and then names a path
#'     (\code{*/x/}) also matches inside a query, so it allows
#'     \code{/c?q=/x/} while a Disallow blocks \code{/c}. Reported only when
#'     the Allow decides the query URL while the path stays blocked, and
#'     with every such Allow left out the query URL would be blocked too,
#'     under every rule the crawlers have. One row per group of crawlers, on
#'     its first User-agent line: the first Allow with the URL it allows and
#'     the Disallow that blocks the path, then the lines of the other
#'     Allows, four at most, then a count.
#'     Past a fixed amount of work, as for \code{rule_slash_split}, Allows
#'     get no row and \code{rule_check_stopped} says so. \cr
#'   \code{rule_render_resource_blocked} \tab info \tab
#'     A Disallow whose pattern ends in a file type a page may load
#'     (\code{.js}, \code{.mjs}, \code{.cjs}, \code{.css}, \code{.json},
#'     \code{.wasm}) for every file of that type, such as \code{/*.js} or
#'     \code{/assets/*.css}, blocks the scripts, styles or data a page may
#'     need to show its content; an exact or named file such as
#'     \code{/app.js} is not read. Reported only when the
#'     rule decides such a file and, with every such rule left out, the
#'     file would be allowed, under every rule the crawlers have. One row
#'     per group of crawlers, on its first User-agent line: the first rule
#'     with a file it blocks, then the lines of the other rules, four at
#'     most, then a count. Past a fixed amount of work, as for
#'     \code{rule_slash_split}, rules get no row and
#'     \code{rule_check_stopped} says so. \cr
#'   \code{rule_prefix_sibling} \tab info \tab
#'     A literal rule with no trailing \code{/} or \code{$}
#'     (\code{Disallow: /feed}) also matches a longer path the same
#'     crawlers' rules list separately with the same type
#'     (\code{Disallow: /feeds}), which goes on from it without a
#'     \code{/}. Reported only when, with that line left out, the shorter
#'     rule decides its path, under every rule the crawlers have. The
#'     message names \code{P$} together with \code{P/} as the narrower
#'     spelling (either one alone drops paths \code{P} matches) and calls
#'     neither rule wrong. One row per set of crawlers of the shorter
#'     rule's group, on its line, listing five pairs at most, then a count;
#'     a sibling listed for fewer crawlers names them. Past a
#'     fixed amount of work, as for \code{rule_slash_split}, rules get no
#'     row and \code{rule_check_stopped} says so. \cr
#'   \code{rule_check_stopped} \tab info \tab
#'     The file is too large for \code{rule_slash_pair},
#'     \code{rule_slash_split}, \code{rule_end_anchor_query},
#'     \code{allow_reopens_through_query},
#'     \code{rule_render_resource_blocked} or
#'     \code{rule_prefix_sibling} to check
#'     every candidate quickly, so the check
#'     read only the first ones, in line order. The message gives the counts
#'     found, checked and skipped and names the earliest skipped rule; the
#'     skipped ones may have the same problem. At most one row per check,
#'     for the whole file (no line); each row's message says which check
#'     stopped by saying what that check looks for. \cr
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
#'     The body exceeded \code{max_bytes}; only lines before the cut were read
#'     (beside \code{compressed_body}, none was, and the row says so). \cr
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
#'     validated (beside \code{compressed_body}, it was not, and the row says
#'     so); crawlers may still read it as a robots.txt. \cr
#'   \code{content_type_charset_unsupported} \tab warning \tab
#'     The \code{Content-Type} declares a \code{charset} other than
#'     \code{utf-8} or \code{us-ascii} and its aliases (a nonstandard UTF-8
#'     label such as \code{utf8} included), an empty one, or two different
#'     ones. The body is read as UTF-8 regardless, without conversion (beside
#'     \code{compressed_body}, it was not read, and the row says so). \cr
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
#' For `user_agent_groups_same_rules`, separate groups whose sets of rules
#' are equal as written could share one group, with their User-agent lines
#' stacked and nothing between them: every engine reads each User-agent
#' line on its own, and Google, Bing and Yandex merge the groups naming one
#' crawler, so each crawler keeps its rules. A rule is compared by its key,
#' in any case, and its value as the parser reads it, blanks around them
#' dropped; order and exact repeats are ignored (an exact repeat is
#' `duplicate_rule`'s), an empty value counts, and `/x` and `/x*`, or `%7E`
#' and `~`, stay apart, since Yandex compares the pattern as written. Only
#' groups written in the plain form take part: every line from a group's
#' first User-agent line to the next group, and the next group's first
#' line, must be a blank or comment-only line, a Sitemap after the group's
#' last rule, or a plain User-agent, Allow or Disallow line: optional
#' leading spaces or tabs, the key exactly `User-agent`, `Allow` or
#' `Disallow` in any case, then its colon at once, and for User-agent a
#' value. Any other spelling Google's parser accepts (a typo, a longer key
#' such as `User-agent foo` or `Disallow foo`, a blank before the colon, a
#' missing colon, an empty User-agent value) leaves the group out, since
#' Bing or Yandex may read it otherwise; so does a `Crawl-delay`,
#' `Clean-param`, `Host` or unknown line (Yandex ends a group at
#' `Crawl-delay`). The suggestion is also withheld for a `*` group, a
#' policy-token or token-less User-agent line, a line a
#' `user_agent_joined_*` or `user_agent_cut` row reports, a line a NUL
#' cuts, a line past the parser's buffer, and a User-agent line on line 1
#' behind a byte-order mark, full or partial (Bing does not read it as
#' User-agent). Groups that name one set of crawlers only are
#' `user_agent_repeated_group`'s. One row per set of equal groups, on the
#' first group's first line, naming the other groups' first lines and the
#' stacked group (five of each, then a count). A byte outside printable
#' ASCII is shown as an escape, so the stacked group in the message is a
#' guide, not a byte-exact copy. A body cut at `max_bytes` is not
#' checked.
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
#' For `rule_query_parameter_position`, the scan reads the canonical value:
#' led by `/` or `*`, not ending in `$`, with its first `?` followed by a
#' parameter name (letters, digits, `_`, `.` and `-`) and `=`. The package's
#' Google, Bing and Yandex matchers read `?` as a literal byte and `*` as
#' any run, so `/items/*?sort=` matches `/items/x?sort=a` and misses
#' `/items/x?a=1&sort=a`. Only the first `?` counts: in `/items?back=?sort=`
#' the parameter is `back`, and a later `?` does not stop the check
#' (`/p?q=?` is reported). Not reported: a `*` before the `=` (`/*?*sort=`),
#' a first `?` with no parameter name and `=` after it (`/p?`), and a
#' `$`-anchored value. Also not reported: a value whose path before the
#' first `?` holds a `.` or `..` segment, written as is or as `%2E` in
#' either case, wherever it sits, since URL normalization removes such a
#' segment from a request. A rule is not reported when every crawler its
#' group names also has a twin, a rule of the same type whose value is the
#' same with that `?` written `*&` (`/search?page=` beside `/search*&page=`), or
#' written `&` when a `*` stands right before that `?` (`/*?page=` beside
#' `/*&page=`). Without that `*`, the `&` rule needs `&` right after the
#' text before it (`/search&page=` misses `/search?a=1&page=1` on all three
#' matchers), so it is no twin and the row stays. Nor is a rule that gets
#' `rule_cut_by_nul`: the NUL cuts it on Google's reading only, and the
#' rule Bing and Yandex read still misses the URL. The message says only
#' what the rule may miss, with its example, and suggests no rewrite.
#' Groups merge here on the whole User-agent value, folded to ASCII lower
#' case, so a twin only Google's cut merge supplies keeps the row, and `*`
#' and named crawlers are kept apart. A group no crawler reads, as under an
#' empty `User-agent:` line, gets no row, as a rule before any User-agent
#' line gets none. The example path writes each `*` as `x` and adds `a=1&`
#' after the `?`, or `b=2&` or `c=3&` where the parameter is named `a` or
#' the last byte before the `?` other than `*` is `1`, so that an `&` rule
#' with the same head cannot match the example either: the pattern matches
#' the path without the addition and misses the example. The example is
#' built from the canonical value, so an escape shows in upper case, and
#' its parameter name, the text before the `?` and the text after the `=`
#' are each cut to their first 36 characters and "..." past 40, or one or
#' two fewer where the cut would split a `%XX` escape. A
#' lower-case-escape twin gets no row, and a body cut at `max_bytes` is not
#' checked: a twin past the cut could silence the rule.
#'
#' `rule_query_crawl_not_index` reads a non-empty Disallow whose canonical
#' value, already cut at `#`, is led by `/` or `*` and holds `?`, `=` or
#' `&`. It is a heuristic on the pattern text: no list of parameter names
#' is read, so `/collections/*sort_by*` gets no row, and the check claims
#' nothing about which URLs the rule blocks or whether any is indexed. Left
#' out: Allow rules, values not led by `/` or `*`
#' (`rule_missing_leading_slash`), a Disallow an identical Allow ties
#' (`disallow_tied_by_allow`), a lower-case-escape twin, rules before any
#' User-agent line and rules of a group no crawler reads, such as one
#' naming only `User-agent: __usage_ai-training`. A group whose User-agent
#' Google cuts to no token, such as `360Spider`, still counts: Bing and
#' Yandex read the whole value. The note does not depend on group
#' selection, so a rule repeated across groups or in a repeated group adds
#' only its line, and the file gets one row, which also stands beside
#' `rule_query_parameter_position` on the same line. The statements about
#' indexing follow Google's documentation on blocking indexing, faceted
#' navigation and duplicate URLs: a URL robots.txt blocks may still be
#' indexed without its content; a noindex meta tag or `X-Robots-Tag` header
#' is read only on a page the crawler may fetch, so robots.txt is no place
#' for it; `rel=canonical` is a consolidation hint, not an exclusion; and
#' blocking faceted, sort or filter URLs can be deliberate crawl control.
#' Other search engines may differ. A body cut at `max_bytes` is checked on
#' the bytes read: a line past the cut that would tie a Disallow, such as
#' an identical Allow, is not seen.
#'
#' `rule_slash_pair` and `rule_slash_split` read only literal patterns: led
#' by `/`, of printable ASCII other than space, with no `*`, `$`, `?` or
#' `%`, and no `.` or `..` segment anywhere, the end included (`/a/.`),
#' since URL normalization would remove it from the bare URL. The root `/`,
#' a value ending in `//`, and wildcard, `$`-anchored, query, percent-encoded
#' and dot-segment values are left for a later version; they still take part
#' in the decisions. Only the first line of each type and value is read for
#' a crawler, so a `duplicate_rule` repeat is neither a pair's later line
#' nor a separate split. Google's matcher makes the decisions: for the split,
#' the rule `P/` must itself decide `P/`, and only the two URLs `P` and `P/`
#' are compared, so a deeper rule (`Allow: /x/y`) changes nothing. Groups
#' merge as the matchers merge them, every row keeps the original line
#' numbers, and a row is reported only where every crawler the group names
#' agrees. `rule_slash_pair` merges on the whole User-agent value, so a pair
#' only Google's cut merge forms gets no row; `rule_slash_split` is
#' reported only where the whole-value merge and Google's merge give the
#' same decisions and deciding lines. A body cut at `max_bytes` gets
#' `rule_slash_pair`, which a later line cannot undo, but not
#' `rule_slash_split`, which a later Allow could change. Both checks read
#' their candidates in line order within a fixed amount of work, linear in
#' the file's rules and candidates; when a check stops before the last one,
#' one `rule_check_stopped` row says how many it found, checked and
#' skipped, and names the earliest skipped rule. A
#' `User-agent: __usage_ai-training` group gets neither: it states a training
#' preference, not crawl access.
#'
#' `rule_end_anchor_query` reads a non-empty Disallow whose canonical value
#' is led by `/` or `*`, ends in its only `$` and holds no `?`. A value
#' ending in `*$` is left out, since the `*` matches every ending, and so is
#' one whose path holds a `.` or `..` segment, written as is or as `%2E`,
#' since URL normalization would remove it, or a `%` that starts no
#' two-hex-digit escape, which no correctly encoded URL carries, or a space,
#' a tab, another control byte or DEL, which no URL a crawler sends carries.
#' The path the rule blocks is the
#' value without the `$`, each `*` written `x`, and the query URL is that
#' path with `?x=1` added; where another rule matches those filler bytes,
#' the check tries `y` with `?y=2`, then `z` with `?z=3`, and the row shows
#' the pair it found. Google's matcher makes the decisions over every
#' rule of the crawler's merged groups, so a second rule that blocks the
#' query URL (`Disallow: /x/edit?`, `Disallow: /*?`), or an Allow that wins
#' the path, silences the row. A row is reported only where every crawler
#' the group names agrees, on the whole-value merge and on Google's merge.
#' The paths are built from the canonical value, so a non-ASCII byte shows
#' as its upper-case `%XX` escape, the form Google's matcher compares; the
#' package's Bing and Yandex matchers compare such a byte as written. Bing
#' upper-cases a lower-case escape as Google does, while the package's
#' Yandex matcher compares it as written, and also lets an Allow `/x` win
#' over a Disallow `/x$` for `/x`. A rule that gets `rule_cut_by_nul` takes
#' part with its value cut at the NUL, as Google's parser reads it. A body
#' cut at `max_bytes` is not checked: a later Disallow could block the
#' query URL. The check reads its candidates within a fixed amount of work,
#' as the slash checks do, and a `User-agent: __usage_ai-training` group
#' gets no row.
#'
#' `allow_reopens_through_query` reads an Allow whose pattern is led by `*`
#' or `/*` and whose rest after that run of `*` is a path: a `/` and at
#' least one more byte before any final `*` or `$` (`*/x/`, `/*/x/`,
#' `/**/x$`, `*/x/$`), so not `/*/` or `/*/*` alone, `/*.css` or
#' `*?next=`. It pairs the Allow with each non-empty
#' Disallow the same crawlers have that is led by `/` or `*` and holds no
#' `?` and no final `$`. The path the Disallow blocks is its value with each
#' `*` written `x`, and the query URL is that path, `?q=` and the path the
#' Allow names, its inner `*` written `x`. A value with a dot segment, a `%`
#' that starts no escape or a byte no URL carries is left out, as for
#' `rule_end_anchor_query`. Google's matcher makes the decisions over every
#' rule of the crawler's merged groups: the Allow must decide the query URL
#' while the path stays disallowed, every crawler the group names agreeing
#' on the line that blocks the path, on the whole-value merge and on
#' Google's merge; read again with every Allow of this shape left out, that
#' line must block the query URL too, so an Allow of another shape that
#' opens it (`Allow: /c?`) silences the row. The row names that line, which
#' may be another Disallow (`/c$`). The pairs of each Allow are read in
#' line order up to the first that gives a row, within a fixed amount of
#' work; an Allow shorter than a Disallow cannot win over it. The
#' package's Yandex matcher gives a tie of pattern lengths to the
#' Disallow, where Google gives it to the Allow. An Allow such as
#' `*/x?p=` can also get `rule_query_parameter_position`; both rows stand. A
#' body cut at `max_bytes` is not checked, and a
#' `User-agent: __usage_ai-training` group gets no row.
#'
#' `rule_render_resource_blocked` reads a non-empty Disallow whose
#' canonical value is led by `/` or `*` and ends in `.js`, `.mjs`, `.cjs`,
#' `.css`, `.json` or `.wasm`, in any case, then only a run of `*`, a final
#' `$`, or a query with no `/`, and only where the rule covers the whole
#' type: its file name, the text after its last `/` (or the whole value
#' when it has none) up to the type's dot, is only a run of `*` (`/*.js`,
#' `/*.js$`, `*.json$`, `/assets/*.css`, `/*.css?*`, `*/*.mjs`). An exact
#' file (`/push-worker.js`, `/a/b/c.json`) or a named stem
#' (`/js/main-*.js`, `/*.min.js`) is left out. The file type must sit in
#' the path, so no `?`, `=` or `&` comes before it: `/*?*.js`,
#' `/q?f=*.css` and `/*a&b/*.js` name query text and are left out.
#' The file it blocks is the value without a final `$` and
#' the run of `*` before it, each other `*` written `x` (`/*.css*` blocks
#' `/x.css`); where another rule matches that filler, the check tries `y`,
#' then `z`. A value with a dot segment, a `%` that starts no escape or a
#' byte no URL carries is left out, as for `rule_end_anchor_query`.
#' Google's matcher makes the decisions over every rule of the crawler's
#' merged groups: the rule must decide the file, so an Allow that wins it
#' (`Allow: /*.js` beside `Disallow: /*.js`) silences the
#' row, and, read again with every such rule left out, the file must come
#' out allowed, so a broader rule that blocks it anyway (`Disallow: /`,
#' `Disallow: /assets/`) silences it too. Beside the rule that decides the
#' file, the row names every other such Disallow the same crawlers have that
#' blocks it by itself, read with the others left out, so
#' `Disallow: /*.js` beside `Disallow: /*.js$` names both lines and leaving
#' out every line a row names lets the file through. The named lines are
#' read on both merges, so a named line can be one that blocks the file
#' only when the crawler's whole User-agent value is read (`Foo/1.0`), not
#' Google's shortened one (`Foo`). A row is reported only
#' where
#' every crawler the group names agrees, on the whole-value merge and on
#' Google's merge. The row is Google's reading: the package's Yandex
#' matcher counts a pattern's length without its `*`, so where an Allow and
#' a Disallow come close in length and one holds a `*` (`Disallow: /*.js`
#' beside `Allow: /x.j`), Yandex can decide the file the other way. The
#' check does not read folder rules (`Disallow: /js/`), endpoints with no
#' file type (`/api/data`), exact or named files, fonts, images or source
#' maps. A rule such as `/*.js$` can also get `rule_end_anchor_query`, and
#' `/*.json?v=*` `rule_query_parameter_position`; both rows stand. A body
#' cut at `max_bytes` is not checked, and a
#' `User-agent: __usage_ai-training` group gets no row.
#'
#' `rule_prefix_sibling` reads a literal rule `P`, as the slash checks do,
#' that does not end in `/`, and another rule of the same type, `M`, also a
#' literal, whose value goes on from `P` with a byte other than `/`
#' (`/feed` and `/feeds`, `/login` and `/login.php`). Every crawler `M`'s
#' group names must have both. Pairs form on the whole User-agent value
#' merge only: two groups with the same value count as one, two naming
#' different crawlers give none, and a pair that only Google's cut merge
#' joins (`Foo/1.0` beside `Foo`) gets no row; its `user_agent_cut` row
#' covers it. `P` is the longest such rule; a sibling
#' that goes on with `/` (`/feed/rss`), one holding `*`, `$`, `?` or `%`,
#' and a pair of opposite type (`Disallow: /search` beside
#' `Allow: /searchx`) are not read. Google's matcher reads `M`'s path with
#' `M` left out, over every rule of the crawler's merged groups, on the
#' whole-value merge and on Google's merge: `P`, or a rule of the same type
#' and value in another of the merged groups, must decide it, so an Allow
#' that would take over (`Allow: /feeds` beside the pair) silences the row.
#' A later repeat of `M` is not named. The check reads its candidates in
#' line order within a fixed amount of work, as the slash checks do. A body
#' cut at `max_bytes` is not checked, and a
#' `User-agent: __usage_ai-training` group gets no row.
#'
#' On a document holding a NUL byte, `wildcard_rules_not_inherited`,
#' `disallow_tied_by_allow`, `duplicate_rule`,
#' `rule_query_parameter_position`, `rule_query_crawl_not_index`,
#' `rule_slash_pair`, `rule_slash_split`,
#' `rule_end_anchor_query`, `allow_reopens_through_query`,
#' `rule_render_resource_blocked`, `rule_prefix_sibling`,
#' `user_agent_groups_same_rules` and the AI-training codes follow Google's
#' reading: the parser and Google's matcher end a line at its
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
#' A fetched body that is still compressed draws `compressed_body` (see
#' [robots_validate_text()]) in place of its line rows, and no
#' `content_type_charset_conflict`; its `body_truncated` and `Content-Type`
#' rows then say the body was not read as rules. libcurl decodes a gzip or
#' deflate body it asked for, so this happens when the server compressed a
#' body the fetch did not ask to be compressed, as with a libcurl built
#' without zlib, or served gzip bytes with no `Content-Encoding` at all, as
#' a `.gz` file served as the robots.txt. The response's `Content-Encoding`
#' is on the source row of [robots_fetch()] as `content_encoding`; the
#' validator does not read it. Only the validator reports such a body: the
#' matchers, [allowed_by_robots_url()] among them, still read its bytes as
#' rules. Raw deflate and brotli bodies are not detected.
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
  # A compressed body (ROBO-rozvglkd) is not read as lines at all: its bytes
  # would give noise rows and a false no_rules. It gets one error and the
  # acquisition rows only.
  compressed <- compressed_body_signature(stored_bytes, cut = body_truncated)
  if (!is.null(compressed)) {
    return(compressed_body_validation(
      compressed, stored_bytes, source_id, source_type, robots_url,
      effective_url, http_status, fetch_outcome, max_bytes, body_truncated
    ))
  }
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
    # A rule value written as a full URL names the path to write
    # (ROBO-jdnluzbb). One read of the value as written serves this and the
    # stray-% check below. A value cut at the line buffer keeps the plain
    # message; one a `#` cut inside the buffer, on a longer line, does not.
    full_url <- NULL
    if (type %in% c("allow", "disallow")) {
      written <- rule_written_value(raw_lines[[line]], line == 1L,
                                    parsed$missing_colon[[i]])
      if (!isTRUE(attr(written, "buffer_cut"))) {
        # A NUL or a glued `#` that cut the value: its rule_cut_by_nul or
        # rule_cut_by_comment row explains the cut.
        cut <- (nul_counts[[line]] > 0L &&
                  rule_cut_by_nul(raw_lines[[line]])) ||
          (parsed$has_comment[[i]] && nzchar(value) &&
             rule_cut_by_comment(raw_lines[[line]]))
        full_url <- rule_full_url_message(written, robots_url, cut)
      }
    }
    for (found in directive_value_diagnostics(type, value)) {
      message <- found$message
      if (!is.null(full_url) &&
            identical(found$code, "rule_missing_leading_slash")) {
        message <- full_url
      }
      add_diagnostic(line, "warning", found$code, type, message)
    }
    # Google upper-cases a rule's escapes but never the URL's, so a
    # lower-case one misses the path written (ROBO-kormmfyg). The parser's
    # value is already upper-cased, so the check reads the raw line. When
    # the group already has the rule in upper case, the line is that rule's
    # twin: info naming it, not advice to write it (ROBO-nvzzjubl).
    if (type %in% c("allow", "disallow")) {
      # A `%` that starts no escape (ROBO-rswdwrnp), after the value's other
      # warnings; the placeholder is read on the value as written.
      percent <- rule_invalid_percent_escape_diagnostic(
        written,
        nul_counts[[line]] > 0L && rule_cut_by_nul(raw_lines[[line]])
      )
      if (!is.null(percent)) {
        add_diagnostic(line, "warning", percent$code, type, percent$message)
      }
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
  # Separate groups with the same rules as written, which could share one
  # group (ROBO-rdxgnqhw). A line past a cut could still join a group, so a
  # cut body is skipped. A joined or cut User-agent line, and a line a NUL
  # cuts on Google's reading only, keep their group out. The rules as
  # written are read here once; the trailing-slash checks below reuse them.
  if (!body_truncated) {
    rule_line <- groups$rules$line
    written <- slash_written_rules(
      raw_lines[rule_line], rule_line,
      parsed$missing_colon[match(rule_line, parsed$line)], groups$rules$empty
    )
    found <- same_rules_group_diagnostics(
      groups, parsed, written, raw_lines,
      skip = c(joined_lines, agents$line[agents$cut], nul_lines[nul_active])
    )
    if (nrow(found) > 0L) {
      add_chunk(
        found$line, found$severity, found$code, found$directive,
        vapply(raw_lines[found$line], render_validation_line, "",
               USE.NAMES = FALSE),
        paste0(found$message, nul_reading)
      )
    }
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
  tied <- tied_disallow_diagnostics(groups)
  for (found in tied) {
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
  # A query-parameter rule that misses the parameter in a later position
  # (ROBO-fuhcwaom). An `&` twin past a cut could silence it, so a cut body
  # is skipped; a lower-case-escape twin is left out, as above.
  # A twin cut by a NUL is Google's reading only: Bing and Yandex read
  # another rule, which still misses the URL, so it silences nothing.
  if (!body_truncated) {
    nul_rules <- groups$rules$line[nul_counts[groups$rules$line] > 0L &
                                     !groups$rules$empty]
    nul_cut <- nul_rules[vapply(raw_lines[nul_rules], rule_cut_by_nul,
                                logical(1L))]
    found <- query_parameter_position_diagnostics(
      groups, skip = which(!is.na(escape_twin)), nul_cut = nul_cut
    )
    if (nrow(found) > 0L) {
      add_chunk(
        found$line, "info", "rule_query_parameter_position", found$type,
        vapply(raw_lines[found$line], render_validation_line, "",
               USE.NAMES = FALSE),
        paste0(found$message, nul_reading)
      )
    }
  }
  # Disallows whose pattern holds a query delimiter: robots.txt controls
  # crawling, not indexing (ROBO-jnnnkyat). One note for the file. A cut
  # body is checked too, on the bytes read: a line past the cut that would
  # tie a Disallow is not seen.
  found <- query_index_note_diagnostics(
    groups, skip = c(which(!is.na(escape_twin)),
                     vapply(tied, `[[`, integer(1L), "line"))
  )
  if (nrow(found) > 0L) {
    add_diagnostic(
      found$line, "info", "rule_query_crawl_not_index", "disallow",
      paste0(found$message, nul_reading)
    )
  }
  # A literal `P` and `P/` of one type for the same crawlers (ROBO-roypaoox).
  # Later lines cannot undo a pair, so a cut body is checked too.
  found <- slash_pair_diagnostics(groups)
  if (nrow(found) > 0L) {
    add_chunk(
      found$line, "info", "rule_slash_pair", found$directive,
      vapply(raw_lines[found$line], render_validation_line, "",
             USE.NAMES = FALSE),
      paste0(found$message, nul_reading)
    )
  }
  # A check that stopped at its work budget says so, once, for the file.
  if (!is.null(attr(found, "stopped"))) {
    add_diagnostic(
      NA_integer_, "info", "rule_check_stopped", NA_character_,
      slash_stop_message("pair", attr(found, "stopped"))
    )
  }
  # A crawler decides the bare URL `P` and the slash URL `P/` of a literal
  # rule differently (ROBO-roypaoox). A later Allow could change a decision,
  # so a cut body is skipped. `written` is the rules as written, read above.
  if (!body_truncated) {
    found <- slash_split_diagnostics(groups, written = written)
    if (nrow(found) > 0L) {
      add_chunk(
        found$line, "info", "rule_slash_split", found$directive,
        vapply(raw_lines[found$line], render_validation_line, "",
               USE.NAMES = FALSE),
        paste0(found$message, nul_reading)
      )
    }
    if (!is.null(attr(found, "stopped"))) {
      add_diagnostic(
        NA_integer_, "info", "rule_check_stopped", NA_character_,
        slash_stop_message("split", attr(found, "stopped"))
      )
    }
    # A `$`-anchored Disallow that the same path with a query added escapes
    # (ROBO-nzcvlsvk). A later Disallow could block the witness, so a cut
    # body is skipped too. A rule a NUL cuts is read as Google cuts it.
    found <- end_anchor_diagnostics(groups, written = written)
    if (nrow(found) > 0L) {
      add_chunk(
        found$line, "info", "rule_end_anchor_query", found$directive,
        vapply(raw_lines[found$line], render_validation_line, "",
               USE.NAMES = FALSE),
        paste0(found$message, nul_reading)
      )
    }
    if (!is.null(attr(found, "stopped"))) {
      add_diagnostic(
        NA_integer_, "info", "rule_check_stopped", NA_character_,
        slash_stop_message("end_anchor", attr(found, "stopped"))
      )
    }
    # An Allow led by `*` or `/*` that names a path and so also matches
    # inside a query, reopening a URL a Disallow blocks (ROBO-micbpqbc). A
    # later rule could decide the witness, so a cut body is skipped too.
    found <- allow_reopens_diagnostics(groups, written = written)
    if (nrow(found) > 0L) {
      add_chunk(
        found$line, "info", "allow_reopens_through_query", found$directive,
        vapply(raw_lines[found$line], render_validation_line, "",
               USE.NAMES = FALSE),
        paste0(found$message, nul_reading)
      )
    }
    if (!is.null(attr(found, "stopped"))) {
      add_diagnostic(
        NA_integer_, "info", "rule_check_stopped", NA_character_,
        slash_stop_message("allow_reopen", attr(found, "stopped"))
      )
    }
    # A Disallow that blocks a file type a page may load to show its
    # content (ROBO-dwywkpes). A later rule could decide the witness, so a
    # cut body is skipped too.
    found <- render_resource_diagnostics(groups, written = written)
    if (nrow(found) > 0L) {
      add_chunk(
        found$line, "info", "rule_render_resource_blocked", found$directive,
        vapply(raw_lines[found$line], render_validation_line, "",
               USE.NAMES = FALSE),
        paste0(found$message, nul_reading)
      )
    }
    if (!is.null(attr(found, "stopped"))) {
      add_diagnostic(
        NA_integer_, "info", "rule_check_stopped", NA_character_,
        slash_stop_message("render_resource", attr(found, "stopped"))
      )
    }
    # A literal rule whose path the same crawlers' rules also list as a
    # sibling it matches, with the same type (ROBO-otomgbge). A later rule
    # could decide the sibling's path, so a cut body is skipped too.
    found <- prefix_sibling_diagnostics(groups, written = written)
    if (nrow(found) > 0L) {
      add_chunk(
        found$line, "info", "rule_prefix_sibling", found$directive,
        vapply(raw_lines[found$line], render_validation_line, "",
               USE.NAMES = FALSE),
        paste0(found$message, nul_reading)
      )
    }
    if (!is.null(attr(found, "stopped"))) {
      add_diagnostic(
        NA_integer_, "info", "rule_check_stopped", NA_character_,
        slash_stop_message("prefix_sibling", attr(found, "stopped"))
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
  for (row in validation_acquisition_rows(bytes, max_bytes, body_truncated,
                                          fetch_outcome, http_status)) {
    add_diagnostic(NA_integer_, row$severity, row$code, NA_character_,
                   row$message)
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

# The document rows about how the body was acquired, as a list of
# list(severity, code, message), drawn whatever the body holds, a compressed
# one included (ROBO-rozvglkd).
# A 2xx body cut at max_bytes (ROBO-ldpahknv) says so. A fetched 2xx other
# than 200 keeps its body, which is validated as a 200's is; the code says
# how each ruleset reads the status (ROBO-yvhqvthd). A 206 never comes here
# fetched: classify_status() gives it partial_response with no body.
# http_status_category_v1() still counts 206 as 2xx other, and a missing
# status is protocol_error, so the category test drops that too. `read` is
# FALSE for a compressed body, whose bytes were not validated as lines.
validation_acquisition_rows <- function(bytes, max_bytes, body_truncated,
                                        fetch_outcome, http_status,
                                        read = TRUE) {
  rows <- list()
  if (body_truncated) {
    message <- if (read) {
      sprintf(
        paste0(
          "Decoded body exceeded max_bytes (%d); only its first %d bytes ",
          "up to the last complete line were validated."
        ),
        as.integer(max_bytes), length(bytes)
      )
    } else {
      sprintf(
        paste0(
          "Body exceeded max_bytes (%d); it was cut at the size limit and ",
          "was not read as rules by the validator."
        ),
        as.integer(max_bytes)
      )
    }
    rows[[length(rows) + 1L]] <- list(
      severity = "warning", code = "body_truncated", message = message
    )
  }
  other_2xx <- identical(fetch_outcome, "fetched") &&
    identical(http_status_category_v1(http_status), "status_other_2xx")
  if (other_2xx) {
    rows[[length(rows) + 1L]] <- list(
      severity = "info", code = "acquisition_http_other_2xx",
      message = paste(
        paste0("HTTP ", http_status, ": ",
               status_engine_readings("status_other_2xx"), "."),
        "See robots_engine_contract_v1()."
      )
    )
  }
  rows
}

# --- Compressed bodies (ROBO-rozvglkd) ---------------------------------------

# The signatures a compressed body opens with: gzip (RFC 1952) and Zstandard
# (RFC 8878) here, zlib (RFC 1950) below.
compressed_body_magic <- list(
  gzip = as.raw(c(0x1f, 0x8b)),
  zstd = as.raw(c(0x28, 0xb5, 0x2f, 0xfd))
)

# A zlib header is CMF 0x78 (deflate, 32 KiB window) and one of these FLG
# bytes, one per compression level. Each makes CMF * 256 + FLG a multiple of
# 31, the header checksum, so matching the list checks the checksum.
compressed_body_zlib_flags <- as.raw(c(0x01, 0x5e, 0x9c, 0xda))

compressed_body_labels <- c(
  gzip = "gzip",
  zlib = "zlib (deflate)",
  zstd = "Zstandard (zstd)"
)

# The compression format a body's first bytes name ("gzip", "zlib" or
# "zstd"), or NULL. The gzip and zstd signatures hold a byte that cannot
# start well-formed UTF-8; a zlib header can (`x^`, `x\x01`), so it counts
# only when its head window is not well-formed UTF-8. `bytes` are the stored
# bytes, before a cut drops its partial line, so a body cut to its header is
# still read; `cut` says the body ends at max_bytes, where a character may be
# split. An out-of-range raw index reads 00, which no signature holds, so a
# body shorter than a signature never matches it.
compressed_body_signature <- function(bytes, cut = FALSE) {
  for (name in names(compressed_body_magic)) {
    magic <- compressed_body_magic[[name]]
    if (identical(bytes[seq_along(magic)], magic)) {
      return(name)
    }
  }
  if (length(bytes) >= 2L && bytes[[1L]] == as.raw(0x78) &&
        bytes[[2L]] %in% compressed_body_zlib_flags &&
        (compressed_body_stored_block(bytes) ||
           !compressed_body_text(bytes, cut))) {
    return("zlib")
  }
  NULL
}

# TRUE when a zlib header with FLG 0x01 opens a stored deflate block (BTYPE
# 00, as level 0 writes) whose NLEN is the ones' complement of its LEN (RFC
# 1951 section 3.2.4). Those four bytes can happen to be well-formed UTF-8,
# so the head window alone would read such a stream as text.
compressed_body_stored_block <- function(bytes) {
  length(bytes) >= 7L && bytes[[2L]] == as.raw(0x01) &&
    bitwAnd(as.integer(bytes[[3L]]), 6L) == 0L &&
    identical(bytes[6:7], xor(bytes[4:5], as.raw(c(0xff, 0xff))))
}

# The bytes after a zlib CMF byte that compressed_body_text() reads: the FLG
# byte and the 16 after it.
compressed_body_zlib_window <- 17L

# TRUE when the zlib head window (bytes 2 to 18) is well-formed UTF-8, so the
# body reads as text. Only the window counts: a Latin-1 robots.txt that starts
# `x^` and holds one byte of 0x80 or above in a later line is text, not zlib.
# Base R cannot settle it by inflating a prefix: memDecompress() errors on
# any stream that does not end, and gzcon() reads no zlib header. Deflate
# output is close to random bytes, so 16 of them are well-formed UTF-8 only
# by rare chance. A window that ends before the body, or at the end of a cut
# body, may split its last character, so up to 3 trailing bytes may go; the
# FLG byte never does.
compressed_body_text <- function(bytes, cut) {
  n <- length(bytes)
  end <- min(n, 1L + compressed_body_zlib_window)
  window <- bytes[2L:end]
  drop <- if (end < n || cut) 0:min(3L, length(window) - 1L) else 0L
  any(vapply(drop, function(k) {
    validation_utf8_line(window[seq_len(length(window) - k)])
  }, logical(1L)))
}

compressed_body_message <- function(format) {
  sprintf(
    paste0(
      "The body starts with a %s signature: it is compressed data, not a ",
      "robots.txt, and its bytes were not read as rules. Validate the ",
      "decoded file: fetch it with decoding (such as `curl --compressed`) ",
      "or decompress the saved copy first."
    ),
    compressed_body_labels[[format]]
  )
}

# The number of lines split_validation_lines() finds, counted without
# splitting: each LF, CR or CRLF ends one, and bytes after the last end one
# more.
validation_line_total <- function(bytes) {
  n <- length(bytes)
  if (n == 0L) {
    return(0L)
  }
  lf <- bytes == as.raw(0x0a)
  cr <- bytes == as.raw(0x0d)
  crlf <- cr & c(lf[-1L], FALSE)
  as.integer(sum(lf) + sum(cr) - sum(crlf) + !(lf[[n]] || cr[[n]]))
}

# The validation of a compressed body: one compressed_body error and the
# acquisition rows, with none of the line, group or rule checks, and a
# document row that keeps the byte facts while every directive count is 0,
# since nothing was read as a directive. `bytes` are the stored bytes, a cut
# body's included: no line of it was validated, so none is dropped.
compressed_body_validation <- function(format, bytes, source_id,
                                       source_type, robots_url, effective_url,
                                       http_status, fetch_outcome, max_bytes,
                                       body_truncated) {
  rows <- c(
    list(list(severity = "error", code = "compressed_body",
              message = compressed_body_message(format))),
    validation_acquisition_rows(bytes, max_bytes, body_truncated,
                                fetch_outcome, http_status, read = FALSE)
  )
  field <- function(name) vapply(rows, `[[`, "", name)
  diagnostics <- validation_diagnostic(
    source_id, NA_integer_, field("severity"), field("code"), NA_character_,
    NA_character_, field("message")
  )
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
    validation_status = validation_status(diagnostics),
    profile = robots_validation_profile,
    byte_size = length(bytes),
    line_count = validation_line_total(bytes),
    active_line_count = 0L,
    recognized_directives = 0L,
    unknown_directives = 0L,
    malformed_lines = 0L,
    user_agent_directives = 0L,
    allow_directives = 0L,
    disallow_directives = 0L,
    sitemap_directives = 0L,
    unsupported_directives = 0L,
    # Every signature holds bytes that are not well-formed UTF-8 (a zlib
    # header counts only then), and none starts with a byte-order mark.
    encoding = "invalid-utf-8",
    encoding_signature = NA_character_,
    encoding_signature_basis = NA_character_,
    has_bom = FALSE,
    nul_byte_count = as.integer(sum(bytes == as.raw(0))),
    final_newline = final_newline,
    max_bytes = as.integer(max_bytes),
    body_truncated = body_truncated,
    limit_exceeded = body_truncated,
    diagnostic_count = as.integer(nrow(diagnostics)),
    warning_count = as.integer(sum(diagnostics$severity == "warning")),
    error_count = as.integer(sum(diagnostics$severity == "error")),
    stringsAsFactors = FALSE
  )
  list(document = document, diagnostics = diagnostics)
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

# Separate groups that give their crawlers the same rules (ROBO-rdxgnqhw).
# Consecutive User-agent lines share one group (RFC 9309 section 2.2.1), so
# their User-agent lines could be stacked over one copy of the rules. Every
# engine reads a User-agent line on its own, and Google, Bing and Yandex
# merge the groups naming one crawler (repeated_group_diagnostics()), so
# moving the lines keeps every crawler's rules, as long as each group reads
# alike everywhere. Google's parser accepts more spellings than Bing and
# Yandex read alike (a typo, a longer key, a blank before the colon, no
# colon), so only groups written in the plain form take part: every line
# from a group's first User-agent line to the next group must be a plain
# line (same_rules_line_kind()), and so must the next group's first line,
# since on Bing or Yandex a group runs on through a line they do not read
# as User-agent. So a group takes part only when:
# - it names no `*` (a `*` group is left out), no policy token, and no line
#   with an empty value or no token;
# - no line of it is in `skip` (a joined or cut User-agent line, or a line
#   holding a NUL Bing and Yandex read past);
# - from its first User-agent line to the next group, every line is a plain
#   User-agent, Allow or Disallow line within the parser's line buffer, a
#   blank or comment-only line, or a Sitemap after its last rule: a
#   Crawl-delay, Clean-param, Host or unknown line may be read as the
#   group's (Yandex ends a group at Crawl-delay), and a stacked group could
#   not keep it;
# - the next group, if any, starts at a plain User-agent line; and
# - it has a rule line.
# Two groups are equal when their sets of rules as written are: each rule is
# its key, ASCII case folded, and its value bytes the parser reads
# (`written`, slash_written_rules()), blanks around them dropped. Order and
# exact repeats are ignored, an empty value stays a member, and `/x` and
# `/x*`, or `%7E` and `~`, stay apart: Yandex compares the pattern as
# written. A class of groups naming one crawler set only is
# user_agent_repeated_group's. Signatures are hashed, so the cost is linear
# in the lines: one info per class, on the first line of its first group,
# naming the other groups' first lines (five, then a count) and the stacked
# group (five User-agent lines and five rules, then counts).
same_rules_group_diagnostics <- function(groups, parsed, written, raw_lines,
                                         skip = integer(), cap = 5L) {
  info <- groups$groups
  agents <- groups$agents
  rules <- groups$rules
  if (nrow(info) < 2L || nrow(rules) == 0L) {
    return(ai_training_rows())
  }
  pos_agent <- match(agents$group, info$group)
  pos_rule <- match(rules$group, info$group)
  ok <- !info$global & seq_len(nrow(info)) %in% pos_rule
  bad_agent <- ai_training_kind(agents)$family |
    (!agents$global & !nzchar(agents$key))
  ok[pos_agent[bad_agent]] <- FALSE
  last_rule <- integer(nrow(info))
  last_rule[pos_rule] <- rules$line
  # Every physical line from the first group on, by its group (0 before).
  line <- seq_along(raw_lines)
  at <- findInterval(line, info$first_line)
  kind <- character(length(line))
  kind[at > 0L] <- same_rules_line_kind(raw_lines[at > 0L])
  p <- match(line, parsed$line)
  too_long <- is.na(p) | parsed$line_too_long[p]
  late_sitemap <- !is.na(p) & parsed$has_directive[p] &
    parsed$type[p] == "sitemap" & at > 0L &
    line > c(0L, last_rule)[at + 1L]
  plain <- (kind %in% c("agent", "rule") & !too_long) |
    kind == "blank" | late_sitemap
  ok[at[!plain & at > 0L]] <- FALSE
  # On Bing or Yandex a group runs on through a next group's first line
  # they do not read as User-agent.
  after <- info$first_line[-1L]
  ok[-nrow(info)][kind[after] != "agent" | too_long[after]] <- FALSE
  skip_at <- findInterval(skip, info$first_line)
  ok[skip_at[skip_at > 0L]] <- FALSE
  if (sum(ok) < 2L) {
    return(ai_training_rows())
  }

  take <- ok[pos_rule]
  kept <- written[take]
  member <- same_rules_members(kept)
  rule_pos <- pos_rule[take]
  signature <- vapply(split(member, rule_pos), function(m) {
    paste(sort(unique(m), method = "radix"), collapse = " ")
  }, "")
  members <- split(as.integer(names(signature)), signature)
  members <- members[lengths(members) > 1L]
  if (length(members) == 0L) {
    return(ai_training_rows())
  }
  agent_rows <- split(seq_len(nrow(agents)), pos_agent)
  crawler_set <- vapply(agent_rows, function(rows) {
    paste(sort(unique(agents$key[rows]), method = "radix"), collapse = " ")
  }, "")
  members <- Filter(function(m) {
    length(unique(crawler_set[as.character(m)])) > 1L
  }, members)
  if (length(members) == 0L) {
    return(ai_training_rows())
  }
  members <- members[order(vapply(members, min, 0L))]
  rule_rows <- split(seq_along(rule_pos), rule_pos)
  message <- vapply(members, function(m) {
    first <- m[[1L]]
    rows <- unlist(agent_rows[as.character(m)], use.names = FALSE)
    rows <- rows[!duplicated(agents$key[rows])]
    own <- rule_rows[[as.character(first)]]
    own <- own[!duplicated(member[own])]
    same_rules_message(
      info$first_line[[first]], info$first_line[m[-1L]],
      agents$name[rows], vapply(kept[own], same_rules_shown, ""), cap
    )
  }, "")
  line <- info$first_line[vapply(members, `[[`, 0L, 1L)]
  ai_training_rows(line, "info", "user_agent_groups_same_rules",
                   "user-agent", unname(message))
}

# Each line's kind in the plain form the same-rules check takes, read on
# bytes: "agent" for a User-agent line, "rule" for an Allow or Disallow
# line, "blank" for a blank or comment-only line, "other" for any other.
# A plain line is optional leading spaces and tabs, then the key exactly
# `user-agent`, `allow` or `disallow` in any ASCII case, then its colon at
# once; a User-agent line also needs a value before any `#` (a line a NUL
# cuts is the caller's `skip`). Every other spelling the parser accepts (a
# typo, a longer key such as `User-agent foo` or `Disallow foo`, a blank
# before the colon, no colon) is "other": Bing or Yandex may read it
# otherwise, or not at all. Line 1 behind a byte-order mark, full (EF BB
# BF) or partial (EF, EF BB), starts at 0xEF, so it is "other" too: the
# parser skips the mark, but Bing does not read that line as User-agent
# (design/backend-evidence-inventory.tsv, ed-02-bing). The key is folded
# on bytes, so a byte not valid in the session's encoding is never
# translated.
same_rules_line_kind <- function(raw_lines) {
  blank <- as.raw(c(0x20, 0x09))
  agent <- charToRaw("user-agent")
  rule <- list(charToRaw("allow"), charToRaw("disallow"))
  vapply(raw_lines, function(bytes) {
    lead <- match(TRUE, !bytes %in% blank, nomatch = length(bytes) + 1L)
    bytes <- slash_drop(bytes, lead - 1L)
    if (length(bytes) == 0L || bytes[[1L]] == as.raw(0x23)) {
      return("blank")
    }
    colon <- match(as.raw(0x3a), bytes, nomatch = 0L)
    if (colon == 0L) {
      return("other")
    }
    key <- ascii_lower_raw_v1(bytes[seq_len(colon - 1L)])
    if (identical(key, agent)) {
      value <- slash_drop(bytes, colon)
      end <- match(as.raw(0x23), value, nomatch = length(value) + 1L)
      if (all(value[seq_len(end - 1L)] %in% blank)) "other" else "agent"
    } else if (any(vapply(rule, identical, NA, key))) {
      "rule"
    } else {
      "other"
    }
  }, "", USE.NAMES = FALSE)
}

# Each rule as written (`key:value`, slash_written_rules()) as the member of
# a group's rule set: its key, ASCII upper case folded, and its value,
# blanks around each dropped, as hex so any byte compares exactly. One pass
# over the bytes of all the rules: each rule's first `:` is its colon
# (a key holds none), and it ends the key.
same_rules_members <- function(written) {
  if (length(written) == 0L) {
    return(character())
  }
  # Every element is unmarked (slash_written_rules() builds each with
  # rawToChar()), so pasting them re-encodes nothing and charToRaw() keeps
  # each rule's bytes at the offsets `size` gives.
  size <- nchar(written, type = "bytes")
  bytes <- charToRaw(paste(written, collapse = ""))
  id <- rep.int(seq_along(written), size)
  pos <- seq_along(bytes)
  colon_at <- which(bytes == as.raw(0x3a))
  colon <- colon_at[match(seq_along(written), id[colon_at])][id]
  # The key, its colon included, then the value; the colon counts as a
  # blank, so the key's trailing blanks go with it.
  part <- 2L * id - (pos <= colon)
  solid <- !(bytes %in% as.raw(c(0x20, 0x09)) | pos == colon)
  seen <- cumsum(solid)
  start <- match(part, part)
  end <- length(part) + 1L - match(part, rev(part))
  keep <- seen - (seen[start] - solid[start]) > 0L & seen[end] - seen +
    solid > 0L
  upper <- pos < colon & bytes >= as.raw(0x41) & bytes <= as.raw(0x5a)
  bytes[upper] <- as.raw(as.integer(bytes[upper]) + 32L)
  token <- as.character(bytes)
  token[!keep] <- ""
  token[pos == colon] <- "-"
  width <- 2L * tabulate(id[keep], length(written)) + 1L
  last <- cumsum(width)
  substring(paste(token, collapse = ""), last - width + 1L, last)
}

# A rule as written (`key:value`, slash_written_rules()) as the message
# shows it: its key, plain (same_rules_line_kind()), and its value, blanks
# around it dropped. A byte outside printable ASCII is shown as an escape
# (render_validation_line()), so the message is a guide, not a byte-exact
# copy.
same_rules_shown <- function(written) {
  bytes <- charToRaw(written)
  colon <- match(as.raw(0x3a), bytes)
  value <- slash_drop(bytes, colon)
  keep <- which(!value %in% as.raw(c(0x20, 0x09)))
  value <- if (length(keep) == 0L) raw(0L) else value[min(keep):max(keep)]
  key <- bytes[seq_len(colon - 1L)]
  ai_training_name(paste0(
    render_validation_line(key), ":",
    if (length(value) > 0L) paste0(" ", render_validation_line(value))
  ))
}

# The message of one same-rules row: the first group's line `at`, the other
# groups' first lines `others`, the crawler names to stack and the shared
# rules as shown.
same_rules_message <- function(at, others, names, rules, cap = 5L) {
  several <- length(others) > 1L
  sprintf(
    paste0("The group at line %d and the %s %s give their crawlers the same ",
           "rules, as written. Consecutive User-agent lines share one group ",
           "(RFC 9309 section 2.2.1), and Google, Bing and Yandex read each ",
           "User-agent line the same wherever it stands, so these groups ",
           "could be one, with nothing between its User-agent lines: %s, ",
           "then %s. This is optional cleanup; each crawler keeps the same ",
           "rules."),
    at, if (several) "groups at lines" else "group at line",
    same_rules_list(as.character(others), cap, "group"),
    same_rules_list(sprintf("`User-agent: %s`", ai_training_name(names)),
                    cap, "User-agent line"),
    same_rules_list(sprintf("`%s`", rules), cap, "rule")
  )
}

# The first `cap` items, then a count of the rest named by `noun`.
same_rules_list <- function(items, cap, noun) {
  shown <- items[seq_len(min(cap, length(items)))]
  more <- length(items) - length(shown)
  if (more > 0L) {
    shown <- c(shown, sprintf("%d more %s%s", more, noun,
                              if (more > 1L) "s" else ""))
  }
  joined_and(shown, 0L)
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
# The bodies are marked UTF-8, as decode_matcher_body() marks the file's, so
# cpp11 hands the matcher their bytes: a witness line copies the written
# bytes (slash_written_rules()), and a native string holding a non-ASCII
# byte would otherwise be translated, in a C locale to `<e9>` text.
wildcard_witness_decide <- function(bodies, ids, paths) {
  n <- length(paths)
  if (n == 0L) {
    return(list(allowed = logical(), line = integer()))
  }
  Encoding(bodies) <- "UTF-8"
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

# A rule whose pattern names a query parameter right after its first `?`
# (`/items/*?sort=`) matches the parameter only where a `?` stands right
# before it: the matchers read `?` as a literal byte, so the rule may miss a
# URL where the parameter follows another one (ROBO-fuhcwaom). A candidate
# (query_parameter_candidates()) is silent when, for every crawler class its
# group names, the merged rules hold a twin that covers the later position
# (query_parameter_kept()). Groups merge on the whole User-agent
# value (`agents$uncut`), so a twin only Google's cut merge supplies keeps
# the row, and a group no crawler class reads gets none
# (query_parameter_kept()). The message shows the example path
# of query_parameter_paths(). Lines in `skip` (lower-case-escape twins,
# ROBO-nvzzjubl) get no row, and lines in `nul_cut` (rule_cut_by_nul) are
# no twin. Returns a data frame of `line`, `type` and `message`, in line
# order.
query_parameter_position_diagnostics <- function(groups, skip = integer(),
                                                 nul_cut = integer()) {
  rules <- groups$rules
  at <- query_parameter_candidates(rules, skip)
  # Most files hold no candidate: skip building the uncut expander.
  if (length(at) > 0L) {
    at <- at[query_parameter_kept(groups, at, nul_cut)]
  }
  paths <- query_parameter_paths(rules$value[at])
  data.frame(
    line = rules$line[at], type = rules$type[at],
    message = query_parameter_message(rules$type[at], paths),
    stringsAsFactors = FALSE
  )
}

# Indexes of `rules` whose canonical value, led by `/` or `*` and not ending
# in `$`, has its first `?` followed by a parameter name ([A-Za-z0-9_.-]+)
# and `=`. So a `*` between that `?` and the `=` (`/*?*sort=`), a first `?`
# with no `name=` after it (`/p?`, `/items*?`) and a later `?`
# (`/items?back=?sort=`) do not make a candidate; a `?` after the `=` does
# not matter (`/p?q=?` and `/p?q=*?` are candidates). A value whose path
# before the first `?` holds a `.` or `..` segment, literal or escaped as
# `%2E` (written in either case), wherever it sits (after a `*` too), is
# skipped: URL normalization removes such a segment from the control path
# before matching (rule_dot_segment, ROBO-rnjfbhvn, reports the literal
# ones outside a `*`). Single passes with no nested quantifier keep the
# cost linear (ROBO-dbvmxcfw).
query_parameter_candidates <- function(rules, skip) {
  value <- rules$value
  hit <- which(
    substr(value, 1L, 1L) %in% c("/", "*") & !endsWith(value, "$") &
      grepl("^[^?]*[?][A-Za-z0-9_.-]+=", value, useBytes = TRUE) &
      !rules$line %in% skip
  )
  # The path before the first `?`. The canonical value upper-cases every
  # escape, so a written `%2e` reads `%2E` here and one case is enough.
  path <- substr(value[hit], 1L,
                 regexpr("?", value[hit], fixed = TRUE, useBytes = TRUE) - 1L)
  dot <- grepl("/([.]|%2E){1,2}(/|$)", path, useBytes = TRUE)
  hit[!dot]
}

# For each candidate in `at` (indexes of `groups$rules`), whether it keeps
# its row: some crawler class its group names (whole-value merge,
# validation_token_expander() on `agents$uncut`) lacks a twin, a rule of
# the same type that covers the later position. A twin is the candidate's
# canonical value with its first `?` written `*&` (`/search*&page=`), or
# written `&` when a `*` already stands right before that `?` (`/*&sort=`
# for `/*?sort=`). Without that `*`, the `&` form needs `&` right after the
# text before it (`/search&page=` misses `/search?a=1&page=1`), so it is
# no twin, and nor is a line in `nul_cut`: a NUL cut its value on Google's
# reading only, so Bing and Yandex read another rule. A group naming no
# class has no crawler that reads the rule, so it gets no row.
query_parameter_kept <- function(groups, at, nul_cut = integer()) {
  rules <- groups$rules
  value <- rules$value[at]
  expand <- validation_token_expander(groups, groups$agents$uncut)
  held <- expand(rules$group)
  usable <- !rules$line[held$owner] %in% nul_cut
  owner <- held$owner[usable]
  have <- paste(held$class[usable], rules$type[owner], rules$value[owner],
                sep = "\n")
  q <- regexpr("?", value, fixed = TRUE, useBytes = TRUE)
  star <- substr(value, q - 1L, q - 1L) == "*"
  amp <- sub("?", "&", value, fixed = TRUE, useBytes = TRUE)
  star_amp <- sub("?", "*&", value, fixed = TRUE, useBytes = TRUE)
  mine <- expand(rules$group[at])
  key <- function(twin) {
    paste(mine$class, rules$type[at][mine$owner], twin[mine$owner],
          sep = "\n")
  }
  has <- (star[mine$owner] & key(amp) %in% have) | key(star_amp) %in% have
  seq_along(at) %in% mine$owner[!has]
}

# The witness paths of each candidate value: `control`, the value with each
# `*` written `x`, and `example`, the same with a filler parameter and `&`
# (query_parameter_filler(), `a=1&` mostly) after the first `?`, each led
# by `/`; `name` is the parameter. Both paths come from the canonical
# value, whose escapes are upper case. The control matches the pattern on
# Google's and Bing's matchers, which upper-case a pattern's escapes too:
# each `*` matches its `x` and every other byte itself, and no final `$`
# anchors it. The package's Yandex matcher compares the pattern as written,
# so there a rule with a lower-case escape (`/p?q=%2b`) matches neither
# path; the row stays, since the position gap holds for the escape as
# written as well. The example misses on every matcher:
# the pattern's first `?` cannot sit on the example's first `?`, which is
# followed by the filler, not by `name=`, nor on a later one, since the
# pattern's `?` bytes after it would need as many again after that one and
# the example has fewer left. So no matcher call is needed: Google's
# matcher costs the path's length times the pattern's on a value full of
# `*`, and the check must stay linear (ROBO-dbvmxcfw). The tests read both
# paths on every backend.
query_parameter_paths <- function(values) {
  if (length(values) == 0L) {
    return(list(name = character(), filler = character(), head = character(),
                tail = character(), control = character(),
                example = character()))
  }
  # A candidate's first `?` starts the leftmost `?name=` run.
  run <- regexpr("[?][A-Za-z0-9_.-]+=", values, useBytes = TRUE)
  start <- as.integer(run)
  end <- start + attr(run, "match.length") - 1L
  name <- substr(values, start + 1L, end - 1L)
  # `head` before the `?`, `tail` after the `=`.
  head <- substr(values, 1L, start - 1L)
  tail <- substr(values, end + 1L, nchar(values, "bytes"))
  filler <- query_parameter_filler(name, head)
  example <- paste0(head, "?", filler, "&", name, "=", tail)
  list(name = name, filler = filler, head = head, tail = tail,
       control = query_parameter_lead(values),
       example = query_parameter_lead(example))
}

# The parameter the example puts first: `a=1`, else `b=2`, else `c=3`, the
# first whose name differs from the rule's parameter (so the example's
# first `?` is not followed by `name=`) and whose last byte differs from
# the last byte of `head` that is not `*`. An `&` rule with the same head
# (`/*1&q=` beside `/*1?q=`) then cannot match the example by ending its
# head on the filler's value right before the `&` (`/x1?a=1&q=`). Two
# conditions rule out two choices at most, so one of three always fits.
query_parameter_filler <- function(name, head) {
  literal <- sub("[*]+$", "", head, useBytes = TRUE)
  n <- nchar(literal, "bytes")
  last <- substr(literal, n, n)
  pick <- rep(3L, length(name))
  pick[name != "b" & last != "2"] <- 2L
  pick[name != "a" & last != "1"] <- 1L
  c("a=1", "b=2", "c=3")[pick]
}

# A pattern as a path: each `*` written `x`, led by `/`.
query_parameter_lead <- function(x) {
  x <- gsub("*", "x", x, fixed = TRUE, useBytes = TRUE)
  ifelse(startsWith(x, "/"), x, paste0("/", x))
}

# The row's text: the `?name=` run and the example path (`paths`, from
# query_parameter_paths()), rendered ASCII-safe as `raw_text` is. It says
# what the rule misses and suggests no rewrite: each usual rewrite changes
# what the rule matches. The name, the text before the `?` and the text
# after the `=` are each elided past `cap` bytes, as ai_training_name()
# elides an agent name, so the message stays bounded however long the
# value is; the `?a=1&name=` run always shows.
query_parameter_message <- function(type, paths, cap = 40L) {
  shown <- function(x) query_parameter_render(query_parameter_cap(x, cap))
  name <- ai_training_name(paths$name, cap)
  example <- paste0(
    shown(query_parameter_lead(paths$head)), "?", paths$filler, "&", name,
    "=", shown(gsub("*", "x", paths$tail, fixed = TRUE, useBytes = TRUE))
  )
  effect <- ifelse(
    type == "allow",
    paste0("this Allow may not apply to URLs where '%s' follows another ",
           "parameter, such as %s, and the gap can leave them restricted."),
    paste0("this rule may miss URLs where '%s' follows another parameter, ",
           "such as %s.")
  )
  sprintf(paste0("Pattern holds '?%s=', which matches '%s' only where a '?' ",
                 "stands right before it, so ", effect),
          name, name, name, example)
}

# ai_training_name()'s elision (the first `cap - 4` bytes and "..." past
# `cap`), backed off one or two bytes where the cut would split a `%XX`
# escape, so an escape shows whole or not at all.
query_parameter_cap <- function(x, cap) {
  k <- cap - 4L
  keep <- rep(k, length(x))
  keep[substr(x, k - 1L, k - 1L) == "%"] <- k - 2L
  keep[substr(x, k, k) == "%"] <- k - 1L
  long <- nchar(x, "bytes") > cap
  x[long] <- paste0(substr(x[long], 1L, keep[long]), "...")
  x
}

# Values as `raw_text` renders a line: printable ASCII as is, other bytes as
# escapes.
query_parameter_render <- function(x) {
  odd <- grepl("[^ -~]", x, useBytes = TRUE)
  x[odd] <- vapply(x[odd], function(v) {
    render_validation_line(charToRaw(v))
  }, "", USE.NAMES = FALSE)
  x
}

# The Disallows whose pattern may target URL parameters, for one note per
# file that robots.txt controls crawling, not indexing (ROBO-jnnnkyat). A
# rule qualifies when it is a non-empty Disallow whose canonical value
# (already cut at `#`) is led by `/` or `*` and holds `?`, `=` or `&`. No
# list of parameter names is read, so `/collections/*sort_by*` stays
# silent: the check reads the pattern text only and claims nothing about
# the URLs it blocks. Lines in `skip` (lower-case-escape twins, Disallows an
# identical Allow ties) are left out, and so is a rule of a group no crawler
# reads: one naming only the AI-training token (slash_groups()) or an empty
# User-agent. A value Google cuts to no token (`360Spider`) still counts:
# Bing and Yandex read it whole. Rules before any User-agent line are in no
# group. On a cut body only the bytes read are judged: an Allow past the cut
# that would tie a Disallow is not seen. Returns a
# data frame of `line` (the first qualifying line) and `message`, with one
# row or none.
query_index_note_diagnostics <- function(groups, skip = integer()) {
  rules <- groups$rules
  value <- rules$value
  at <- which(
    rules$type == "disallow" & substr(value, 1L, 1L) %in% c("/", "*") &
      grepl("[?=&]", value, useBytes = TRUE) & !rules$line %in% skip
  )
  # A group some crawler reads names `*` or a non-empty whole value
  # (`agents$uncut`): Bing and Yandex read `360Spider`, which Google cuts to
  # no token.
  agents <- slash_groups(groups)$agents
  read <- agents$group[agents$global | nzchar(agents$uncut)]
  at <- at[rules$group[at] %in% read]
  if (length(at) == 0L) {
    return(data.frame(line = integer(), message = character(),
                      stringsAsFactors = FALSE))
  }
  lines <- sort(unique(rules$line[at]))
  data.frame(line = lines[[1L]],
             message = query_index_note_message(lines, value[at[[1L]]]),
             stringsAsFactors = FALSE)
}

# The note's text: the qualifying lines, five at most, then a count, and
# the first one's pattern, elided past 40 bytes and rendered ASCII-safe;
# then, once for the file, what robots.txt does and does not do, hedged
# with "may" and attributed to Google's documentation. It never suggests
# a noindex line in robots.txt, and calls deliberate crawl control fine.
query_index_note_message <- function(lines, first, cap = 5L) {
  shown <- query_parameter_render(query_parameter_cap(first, 40L))
  lead <- if (length(lines) == 1L) {
    sprintf("The Disallow on line %d ('%s') holds", lines, shown)
  } else {
    sprintf("The Disallows on lines %s (the first '%s') hold",
            joined_and(as.character(utils::head(lines, cap)),
                       length(lines) - min(length(lines), cap)),
            shown)
  }
  target <- if (length(lines) == 1L) "it may target" else "they may target"
  paste0(
    lead, " '?', '=' or '&', so ", target, " URL parameters; this reads ",
    "the pattern text only. robots.txt controls crawling, not indexing: ",
    "Google's documentation says a blocked URL may still be indexed, ",
    "without its content. To keep a page out of the index, a noindex meta ",
    "tag or X-Robots-Tag header works only on a page the crawler may ",
    "fetch, so it is not seen on a blocked URL. For duplicate parameter ",
    "URLs, rel=canonical is a consolidation hint, not an exclusion. ",
    "Blocking faceted, sort or filter URLs can be deliberate crawl control, ",
    "which is fine where that is the intent."
  )
}

# Indexes of `rules` whose canonical value is a literal path pattern for the
# trailing-slash checks (ROBO-roypaoox): led by `/`, not `/` itself, of
# printable ASCII other than space, with no `*`, `$`, `?` or `%`, not ending
# in `//`, and with no `.` or `..` segment anywhere, the unbounded end
# included (`/a/.`): URL normalization would remove it from the bare URL
# (ROBO-rnjfbhvn). A non-ASCII byte is escaped in the canonical value, so
# such a value holds `%` and is no candidate. An empty value is not led by
# `/`, so it is none either.
slash_candidates <- function(rules) {
  value <- rules$value
  which(
    startsWith(value, "/") & value != "/" &
      !grepl("[^!-~]|[*$?%]|//$", value, useBytes = TRUE) &
      !grepl("/[.][.]?(/|$)", value, useBytes = TRUE)
  )
}

# The groups the trailing-slash checks read. The AI-training policy token
# states a training preference, not crawl access, and names no crawler
# (ROBO-kzyfejcv), so its User-agent lines are left out, as
# wildcard_inheritance_diagnostics() leaves them out: on Google's key, so
# `__usage_ai-training/1.0` goes too. A group naming only the token gets no
# row.
slash_groups <- function(groups) {
  agents <- groups$agents
  groups$agents <- agents[agents$key != ai_training_token, , drop = FALSE]
  groups
}

# Each rule line's key as written (`Disallow`, `disalow`, `ALLOW`): its
# bytes from the first one that is not a space or tab up to the first `:`,
# space, tab or NUL. Google's parser accepts the same keys on the witness
# line.
slash_written_keys <- function(raw_lines) {
  stop_at <- as.raw(c(0x3a, 0x20, 0x09, 0x00))
  vapply(raw_lines, function(bytes) {
    lead <- match(TRUE, !bytes %in% as.raw(c(0x20, 0x09)), nomatch = 1L)
    bytes <- bytes[lead:length(bytes)]
    end <- match(TRUE, bytes %in% stop_at, nomatch = length(bytes) + 1L)
    rawToChar(bytes[seq_len(end - 1L)])
  }, "", USE.NAMES = FALSE)
}

# Each rule line (`raw_lines`, file lines `lines`, the parser's
# `missing_colon` and `empty` flags) as a witness line that Google's parser
# reads as it reads the file line: the key as written up to Google's key
# boundary (the first `:`, or, with no colon, the first space or tab,
# slash_written_keys()), `:`, and the value bytes as the parser reads them
# (rule_raw_value(): cut at the first NUL, `#` and the 16,663-byte line
# buffer). So `Disallow foo: /a?` keeps its key `Disallow foo`, and a padded
# line keeps only the value the buffer leaves. The value keeps its written
# bytes, not its canonical escapes, and the line is never longer than the
# part of the file line the parser reads, so the buffer cuts nothing more;
# Google's matcher escapes the pattern as it does the file's. An empty rule
# decides nothing and is never read, so it keeps its key alone.
slash_written_rules <- function(raw_lines, lines, missing_colon, empty) {
  keys <- slash_written_keys(raw_lines)
  vapply(seq_along(raw_lines), function(i) {
    if (empty[[i]]) {
      return(paste0(keys[[i]], ":"))
    }
    value <- rule_raw_value(raw_lines[[i]], lines[[i]] == 1L,
                            missing_colon[[i]])
    key <- if (missing_colon[[i]]) {
      keys[[i]]
    } else {
      slash_key_to_colon(raw_lines[[i]])
    }
    paste0(key, ":", rawToChar(as.vector(value)))
  }, "")
}

# A line's bytes before its first `:`, past its leading spaces and tabs.
slash_key_to_colon <- function(bytes) {
  bytes <- bytes[seq_len(match(as.raw(0x3a), bytes) - 1L)]
  lead <- match(TRUE, !bytes %in% as.raw(c(0x20, 0x09)),
                nomatch = length(bytes) + 1L)
  rawToChar(slash_drop(bytes, lead - 1L))
}

# `x` without its first `k` elements.
slash_drop <- function(x, k) {
  x[seq_len(max(length(x) - k, 0L)) + k]
}

# The other form of each candidate value: `P` for `P/`, `P/` for `P`.
slash_partner <- function(value) {
  slash <- endsWith(value, "/")
  out <- paste0(value, "/")
  out[slash] <- substr(value[slash], 1L, nchar(value[slash], "bytes") - 1L)
  out
}

# For candidate rows `rows` (owner, class) of `rules[at, ]`, whether each is
# the first line of its type and value in its class: only that line is read,
# so a repeat (duplicate_rule's) is not a pair's later line. Rows are in
# owner order, so a key's first row is its first line.
slash_first <- function(rules, at, rows) {
  o <- rows$owner
  key <- paste(rows$class, rules$type[at][o], rules$value[at][o], sep = "\n")
  match(key, key) == seq_along(key)
}

# The work the slash checks may do on a file: 32 units per rule and per
# candidate, plus 20,000, so the cost stays linear in the file however its
# rules and crawlers combine. A unit is one (candidate, class) read or one
# witness body line. The constants leave every case in the tests and in
# the synthetic noise bodies below the cap: 2,000 named groups of 20 rules
# whose crawlers Google's matcher merges into one class spend about half.
slash_budget <- function(rules, at) {
  32 * (nrow(rules) + length(at)) + 20000
}

# The (candidate, class) rows each of `group` (the candidates' groups) has
# under `expand`, counted per distinct group, so nothing grows with the
# product of candidates and classes.
slash_class_counts <- function(expand, group) {
  wanted <- unique(group)
  tabulate(expand(wanted)$owner, length(wanted))[match(group, wanted)]
}

# The leading items, in order, whose summed `cost` fits `budget`.
slash_within <- function(cost, budget) {
  cumsum(cost) <= budget
}

# What a check that stopped at its budget reports: `found` candidates (the
# rules at `at`), the first `checked` of them read in line order, the rest
# `skipped`, and `value`, the earliest skipped one. NULL when every
# candidate was read.
slash_stop <- function(rules, at, checked) {
  if (checked >= length(at)) {
    return(NULL)
  }
  list(found = length(at), checked = checked,
       skipped = length(at) - checked,
       value = rules$value[[at[[checked + 1L]]]])
}

# The rule_check_stopped row's text, for the split check (`kind`
# "split"), the pair check ("pair"), the end-anchor check ("end_anchor"),
# the reopen check ("allow_reopen"), the render-resource check
# ("render_resource") or the prefix-sibling check ("prefix_sibling"), in
# plain words with the file's own counts and its
# earliest skipped value.
slash_stop_message <- function(kind, stop) {
  if (kind == "end_anchor") {
    return(paste(end_anchor_stop_intro(stop),
                 slash_stop_counts(stop, "have the same problem")))
  }
  if (kind == "render_resource") {
    return(paste(render_resource_stop_intro(stop),
                 slash_stop_counts(stop, "have the same problem")))
  }
  if (kind == "prefix_sibling") {
    return(paste(prefix_sibling_stop_intro(stop),
                 slash_stop_counts(stop, "be matched that way")))
  }
  if (kind == "allow_reopen") {
    return(paste(reopen_stop_intro(stop),
                 slash_stop_counts(stop, "do the same")))
  }
  shown <- slash_shown(stop$value)
  rules <- if (stop$found == 1L) "1 rule" else sprintf("%d rules", stop$found)
  intro <- if (kind == "split") {
    sprintf(paste0(
      "This file has %s whose path ends in '/', such as '%s'. For each one, ",
      "the validator checks whether crawlers treat '%s' and '%s' differently."
    ), rules, shown$slash, shown$bare, shown$slash)
  } else {
    sprintf(paste0(
      "This file has %s that may come in pairs like '%s' and '%s'. For each ",
      "one, the validator checks whether the same crawlers have both forms."
    ), rules, shown$bare, shown$slash)
  }
  problem <- if (kind == "split") "have the same problem" else
    "be part of such a pair"
  paste(intro, slash_stop_counts(stop, problem))
}

# The counting sentences of slash_stop_message(), singular or plural.
slash_stop_counts <- function(stop, problem) {
  them <- if (stop$found == 1L) "it" else "them all"
  done <- if (stop$checked == 0L && stop$found == 1L) {
    "it was not checked"
  } else if (stop$checked == 0L) {
    "none of them were checked"
  } else if (stop$checked == 1L) {
    "only the first was checked, in line order"
  } else {
    sprintf("only the first %d were checked, in line order", stop$checked)
  }
  rest <- if (stop$checked == 0L && stop$skipped == 1L) {
    sprintf("It was skipped, and it may %s.", problem)
  } else if (stop$checked == 0L) {
    sprintf("All %d were skipped, and some of them may %s.", stop$skipped,
            problem)
  } else if (stop$skipped == 1L) {
    sprintf("The other 1 was skipped, and it may %s.", problem)
  } else {
    sprintf("The other %d were skipped, and some of them may %s.",
            stop$skipped, problem)
  }
  sprintf("This file is too large to check %s quickly, so %s. %s", them,
          done, rest)
}

# The rows whose owner (an index of `at`) passes `ok` on every row; owners
# with no row (a group no crawler class reads) never pass.
slash_every <- function(owner, ok) {
  setdiff(unique(owner), owner[!ok])
}

# A literal Allow or Disallow `P` and `P/` of the same type for the same
# crawlers (ROBO-roypaoox). `P` also matches every path `P/` matches (RFC
# 9309 section 2.2.2), and the bare URL `P` and paths that go on without
# `/` too. The row sits on the later line and names each class's first line
# of the other form (every distinct one, slash_pair_lead()); it is reported
# only when, for every crawler class its group names, the line is the first
# of its type and value and the other form sits on an earlier line. Groups
# merge on the whole User-agent value (`agents$uncut`), so a pair that only
# Google's cut merge forms gets no row (its user_agent_cut rows cover it).
# Later lines cannot undo a pair, so a cut body is checked too. Candidates
# are read in line order, one (candidate, class) row each, while the rows
# fit `budget` (slash_budget()); later ones get no row: their other form
# sits on an earlier line, so every line read has what it needs. Returns a
# data frame of `line`, `type` and `message`, in line order; when the
# budget cut candidates, its "stopped" attribute holds slash_stop()'s counts.
slash_pair_diagnostics <- function(groups, budget = NULL) {
  groups <- slash_groups(groups)
  rules <- groups$rules
  at <- slash_candidates(rules)
  if (length(at) == 0L) {
    return(slash_rows(character()))
  }
  if (is.null(budget)) {
    budget <- slash_budget(rules, at)
  }
  expand <- validation_token_expander(groups, groups$agents$uncut)
  read <- slash_within(slash_class_counts(expand, rules$group[at]), budget)
  stop <- slash_stop(rules, at, sum(read))
  at <- at[read]
  rows <- expand(rules$group[at])
  o <- rows$owner
  line <- rules$line[at]
  key <- paste(rows$class, rules$type[at][o], rules$value[at][o], sep = "\n")
  other <- line[o][match(paste(rows$class, rules$type[at][o],
                               slash_partner(rules$value[at])[o],
                               sep = "\n"), key)]
  ok <- slash_first(rules, at, rows) & !is.na(other) & other < line[o]
  hit <- sort(slash_every(o, ok))
  # Each class names its own first line of the other form; where classes
  # differ, every such line is named, so the claim holds for each crawler.
  earlier <- split(other[o %in% hit], o[o %in% hit])
  at <- at[hit]
  lead <- vapply(seq_along(at), function(i) {
    slash_pair_lead(rules$type[[at[[i]]]], sort(unique(earlier[[i]])))
  }, "")
  found <- slash_rows(
    rules$type[at],
    line = rules$line[at],
    message = paste0(
      slash_pair_message(rules$value[at], lead),
      slash_crawler_note(groups$agents, rules$group[at])
    )
  )
  attr(found, "stopped") <- stop
  found
}

slash_rows <- function(type, line = integer(), message = character(),
                       directive = type) {
  data.frame(line = line, type = type, message = message,
             directive = directive, stringsAsFactors = FALSE)
}

# The two forms of each value as the messages show them: `bare` is `P`
# elided as query_parameter_cap() elides past 40 bytes, and `slash` is the
# same text with the `/` after it, so the two stay apart however long `P`
# is.
slash_shown <- function(value) {
  bare <- ifelse(endsWith(value, "/"), slash_partner(value), value)
  bare <- query_parameter_cap(bare, 40L)
  list(bare = bare, slash = paste0(bare, "/"))
}

# The opening of a pair row: "The Disallow on line 2 has" for one earlier
# line, "The Disallows on lines 2, 5 and 8 have" for more, five lines at
# most, then a count.
slash_pair_lead <- function(type, lines, cap = 5L) {
  noun <- if (type == "allow") "Allow" else "Disallow"
  if (length(lines) == 1L) {
    return(sprintf("The %s on line %d has", noun, lines))
  }
  shown <- utils::head(lines, cap)
  sprintf("The %ss on lines %s have", noun,
          joined_and(as.character(shown), length(lines) - length(shown)))
}

# The pair row's text: what each form matches, calling neither redundant.
slash_pair_message <- function(value, lead) {
  shown <- slash_shown(value)
  slash <- endsWith(value, "/")
  this <- ifelse(slash, shown$slash, shown$bare)
  other <- ifelse(slash, shown$bare, shown$slash)
  sprintf(paste0(
    "%s '%s' and this one '%s': '%s' also matches every path '%s' matches, ",
    "and also '%s' itself and the paths that go on from it without a '/' ",
    "(RFC 9309 section 2.2.2)."
  ), lead, other, this, shown$bare, shown$slash, shown$bare)
}

# " This holds for every crawler the group names: ..." for a group naming
# more than one crawler (its written values, five at most, then a count),
# else "". Built once per group: the names come from one split.
slash_crawler_note <- function(agents, group) {
  named <- agents$global | nzchar(agents$uncut)
  # One name per crawler: values the whole-value merge reads as one class
  # key (`Googlebot`, `googlebot`) count once, as first written.
  id <- paste(agents$group, ifelse(agents$global, "*", agents$uncut),
              sep = "\n")
  named <- named & !duplicated(id)
  by_group <- split(agents$name[named], agents$group[named])
  wanted <- unique(group)
  note <- vapply(by_group[as.character(wanted)], function(names) {
    names <- unique(names)
    if (length(names) < 2L) {
      return("")
    }
    shown <- sprintf("'%s'", ai_training_name(utils::head(names, 5L)))
    sprintf(" This holds for every crawler the group names: %s.",
            joined_and(shown, length(names) - length(shown)))
  }, "", USE.NAMES = FALSE)
  note[match(group, wanted)]
}

# A literal rule `P/` whose crawlers get a different decision for the bare
# URL `P` than for the slash URL `P/` (ROBO-roypaoox). A candidate must
# decide `P/` itself in each class, which only the first line of its type
# and value does (the matcher keeps the first of equal rules, and an Allow
# wins a tie), so a repeat is no candidate. The direction follows the
# candidate's type: an Allow opens `P/` while `P`
# stays disallowed (one row on the Allow line), a Disallow blocks `P/` while
# `P` stays allowed (one row per set of crawler classes, anchored on the
# first User-agent line of the group holding the earliest listed rule, five
# rules at most, then a count). Every rule of a class takes part in the
# decisions, which are Google's matcher's (witness_pair_readings(), with
# `P` the short path and `P/` the long one the candidate decides). A row is
# reported only where every class the group names, merged on the whole
# User-agent value and on Google's token, gives the same decisions and the
# same deciding lines; the two merges coincide when no value is cut, and
# then one reading is made. A cut body is not checked: a later Allow could
# change a decision. The readings share `budget` (slash_budget()): each
# reads candidates in line order while its (candidate, class) rows and
# witness body lines fit what is left, and a candidate past it gets no row.
# Returns slash_rows() with a `directive` column; when the budget cut
# candidates, its "stopped" attribute holds slash_stop()'s counts.
slash_split_diagnostics <- function(groups, written = NULL, budget = NULL) {
  groups <- slash_groups(groups)
  rules <- groups$rules
  at <- slash_candidates(rules)
  at <- at[endsWith(rules$value[at], "/")]
  if (length(at) == 0L) {
    return(slash_rows(character()))
  }
  if (is.null(budget)) {
    budget <- slash_budget(rules, at)
  }
  value <- rules$value[at]
  read <- witness_pair_readings(groups, at, slash_partner(value), value,
                                "long", written, budget)
  found <- !is.na(read$line)
  out <- slash_split_rows(groups, at[found], read$line[found])
  attr(out, "stopped") <- slash_stop(rules, at, read$checked)
  out
}

# witness_pair_reading() on the whole-value merge (`agents$uncut`) and, when
# some value is cut, on Google's key too, the readings sharing `budget`.
# Returns list(line, ok, checked, spent): `ok` where every reading's `ok`
# holds, `line` where every reading names the same line (NA otherwise),
# `checked` the leading candidates every reading read, and `spent` the work
# done. `differ` and `group` as witness_pair_reading() takes them. With
# `share`, Google's merge rereads only where it differs
# (witness_pair_shared()).
witness_pair_readings <- function(groups, at, short, long, decides,
                                  written = NULL, budget = Inf,
                                  differ = TRUE, group = NULL,
                                  share = FALSE) {
  agents <- groups$agents
  keys <- list(agents$uncut)
  if (!all(agents$uncut == agents$key)) {
    if (share) {
      return(witness_pair_shared(groups, at, short, long, decides, written,
                                 budget, differ, group))
    }
    keys <- c(keys, list(agents$key))
  }
  line <- NULL
  ok <- rep(TRUE, length(at))
  checked <- length(at)
  spent <- 0
  for (key in keys) {
    read <- witness_pair_reading(groups, at, key, short, long, decides,
                                 written, budget - spent, differ, group)
    spent <- spent + read$spent
    ok <- ok & read$ok
    if (is.null(line)) {
      line <- read$line
    } else {
      agree <- !is.na(line) & !is.na(read$line) & line == read$line
      line[!agree] <- NA_integer_
    }
    # A candidate is checked when every reading read it.
    checked <- min(checked, read$read)
  }
  list(line = line, ok = ok, checked = checked, spent = spent)
}

# witness_pair_readings() when some value is cut, Google's merge reading
# only the candidates whose group's crawler classes differ between the two
# merges (merge_differs()): elsewhere each class holds the same groups on
# both, so the bodies and decisions are the same, and the whole-value
# reading stands for both. The whole-value reading gets the share of
# `budget` its candidates make of all the candidates both read, and
# Google's what it leaves, so neither merge starves the other.
witness_pair_shared <- function(groups, at, short, long, decides, written,
                                budget, differ, group) {
  if (is.null(group)) {
    group <- groups$rules$group[at]
  }
  n <- length(at)
  redo <- which(merge_differs(groups, group))
  share <- if (n == 0L) budget else budget * n / (n + length(redo))
  whole <- witness_pair_reading(groups, at, groups$agents$uncut, short, long,
                                decides, written, share, differ, group)
  out <- list(line = whole$line, ok = whole$ok, checked = whole$read,
              spent = whole$spent)
  redo <- redo[redo <= whole$read]
  if (length(redo) == 0L) {
    return(out)
  }
  google <- witness_pair_reading(groups, at[redo], groups$agents$key,
                                 short[redo], long[redo], decides, written,
                                 budget - whole$spent, differ, group[redo])
  out$spent <- out$spent + google$spent
  out$ok[redo] <- out$ok[redo] & google$ok
  line <- out$line[redo]
  line[is.na(google$line) | is.na(line) | line != google$line] <- NA_integer_
  out$line[redo] <- line
  if (google$read < length(redo)) {
    out$checked <- min(out$checked, redo[[google$read + 1L]] - 1L)
  }
  out
}

# For each of the groups `group`, whether its crawler classes hold other
# groups on the whole-value merge (`agents$uncut`) than on Google's
# (`agents$key`), classes built as validation_token_expander() builds them.
# Counted from the (group, class) pairs, linear in the User-agent lines.
merge_differs <- function(groups, group) {
  agents <- groups$agents
  signatures <- function(key) {
    token <- ifelse(agents$global, "*", key)
    keep <- nzchar(token)
    owner <- agents$group[keep]
    token <- token[keep]
    signature <- vapply(split(owner, token), function(g) {
      paste(unique(g), collapse = " ")
    }, "")
    list(group = owner, signature = unname(signature[token]))
  }
  whole <- signatures(agents$uncut)
  google <- signatures(agents$key)
  known <- unique(c(whole$signature, google$signature))
  classes <- function(s) {
    id <- match(s$signature, known)
    vapply(split(id, s$group), function(x) {
      paste(sort(unique(x)), collapse = " ")
    }, "")
  }
  id <- as.character(group)
  a <- classes(whole)[id]
  b <- classes(google)[id]
  unname(xor(is.na(a), is.na(b)) | (!is.na(a) & !is.na(b) & a != b))
}

# Two paths per candidate in `at` (indexes of `groups$rules`): `short`, a
# prefix of `long`, and the one named by `decides` ("short" or "long") the
# candidate must decide ("none": no line, witness_pair_verdict()). A
# (candidate, class) row is `ok` when the candidate
# is the line that decides that path and the other path gets the other
# decision, or, with `differ = FALSE`, the same decision. Returns
# list(ok, line, spent, read): `ok`, per candidate, where every class the
# group names (validation_token_expander() on `key`) is ok; `line`, where
# they are and also agree on the file line that decides the other path
# (0 when no rule matches it), that line, NA otherwise;
# `spent` the work done, and `read` how many leading candidates were read
# whole. Each row is read under a body of the class's rules that can match
# `long` (slash_split_bodies()): a rule that matches `short` can match
# `long` too once the filter drops its final `$`, so every other rule
# matches neither path, and rules keep file order, so ties resolve as in
# the whole group. One batch call reads every row. Candidates are read in
# line order while their rows and the rules of their classes
# (slash_read_plan()), then their body lines, fit `budget`; the rest stay
# NA and not ok. `group`, when given, names each candidate's group to read
# the classes of in place of its own: the removal read of
# allow_reopens_diagnostics() reads a Disallow under its Allow's crawlers.
witness_pair_reading <- function(groups, at, key, short, long, decides,
                                 written = NULL, budget = Inf,
                                 differ = TRUE, group = NULL) {
  rules <- groups$rules
  if (is.null(group)) {
    group <- rules$group[at]
  }
  expand <- validation_token_expander(groups, key)
  unread <- list(ok = rep(FALSE, length(at)),
                 line = rep(NA_integer_, length(at)))
  # An empty rule decides nothing; left in, Google's matcher could name its
  # line for a URL no other rule matches, with the same decision.
  live <- which(!rules$empty)
  plan <- slash_read_plan(expand, group, rules$group[live], budget)
  spent <- plan$spent
  rows <- expand(group[seq_len(plan$n)])
  if (length(rows$owner) == 0L) {
    return(c(unread, list(spent = spent, read = plan$n)))
  }
  held <- list(rule = live[plan$held$owner], class = plan$held$class)
  body <- slash_split_bodies(rules, held, long[rows$owner], rows$class,
                             written, rows$owner, budget - spent)
  spent <- spent + body$spent
  kept <- seq_len(body$rows)
  # Whole candidates only: all of the plan's, or those up to the last owner
  # kept (candidates before the first owner name no class).
  read_n <- if (body$rows == length(rows$owner)) {
    plan$n
  } else if (body$rows == 0L) {
    rows$owner[[1L]] - 1L
  } else {
    rows$owner[[body$rows]]
  }
  if (length(kept) == 0L) {
    return(c(unread, list(spent = spent, read = read_n)))
  }
  o <- rows$owner[kept]
  paths <- c(rbind(short[o], long[o]))
  read <- wildcard_witness_decide(body$bodies, rep(seq_along(o), each = 2L),
                                  paths)
  c(witness_pair_verdict(unread, read, body, rules$line, rules$line[at], o,
                         decides, differ),
    list(spent = spent, read = read_n))
}

# The `ok` and `line` of witness_pair_reading() from `read`, the batch's
# decisions on the (short, long) path pairs of rows `o` (their candidates,
# whose file lines are `cand_line`), and `body`, the witness bodies
# (`line` the file line of each rule). `differ`: whether the two paths
# must get different decisions (TRUE) or the same one (FALSE). With
# `decides = "none"`, no line need decide: a row is `ok` when both paths
# come out allowed, and `line` stays NA.
witness_pair_verdict <- function(out, read, body, line, cand_line, o,
                                 decides, differ = TRUE) {
  first <- seq(1L, 2L * length(o), by = 2L)
  if (decides == "none") {
    ok <- read$allowed[first] & read$allowed[first + 1L]
    out$ok[slash_every(o, ok)] <- TRUE
    return(out)
  }
  file_line <- function(k) {
    j <- read$line[k]
    found <- integer(length(j))
    hit <- j > 1L
    found[hit] <- line[body$rule[body$start[(k[hit] + 1L) %/% 2L] +
                                   j[hit] - 2L]]
    found
  }
  own <- if (decides == "long") first + 1L else first
  other <- if (decides == "long") first else first + 1L
  other_line <- file_line(other)
  ok <- file_line(own) == cand_line[o] &
    (read$allowed[first] != read$allowed[first + 1L]) == differ
  every <- slash_every(o, ok)
  out$ok[every] <- TRUE
  same <- tapply(other_line, o, function(x) all(x == x[[1L]]))
  hit <- intersect(every, as.integer(names(same)[same]))
  out$line[hit] <- other_line[match(hit, o)]
  out
}

# How many candidates (their groups `cand_group`, in line order) one
# reading takes within `budget`, as list(n, spent, held). A candidate costs
# its (candidate, class) rows, and a class costs, once, the live rules
# (their groups `live_group`) it holds, when the first candidate that needs
# it is taken: a group naming many crawlers repeats its rules in each of
# their classes. `held` gives the (rule, class) pairs of the classes taken,
# `owner` indexing `live_group`. Every count comes from the (group, class)
# pairs, which grow with the User-agent lines, not with their product with
# the rules.
slash_read_plan <- function(expand, cand_group, live_group, budget) {
  wanted <- unique(c(cand_group, live_group))
  pairs <- expand(wanted)
  per <- tabulate(pairs$owner, length(wanted))[match(cand_group, wanted)]
  rule_n <- tabulate(match(live_group, wanted), length(wanted))
  first <- match(wanted, cand_group)
  first[is.na(first)] <- Inf
  class_first <- tapply(first[pairs$owner], pairs$class, min)
  pair_first <- class_first[as.character(pairs$class)]
  joins <- pair_first <= length(cand_group)
  held_at <- numeric(length(cand_group))
  if (any(joins)) {
    sums <- rowsum(rule_n[pairs$owner][joins], pair_first[joins])
    held_at[as.integer(rownames(sums))] <- sums[, 1L]
  }
  cost <- cumsum(per) + cumsum(held_at)
  n <- sum(cost <= budget)
  # A perf filter only: a class no candidate taken needs is never read.
  taken <- pair_first <= n
  by_group <- split(pairs$class[taken],
                    factor(pairs$owner[taken], seq_along(wanted)))
  classes <- by_group[match(live_group, wanted)]
  list(n = n, spent = if (n == 0L) 0 else cost[[n]],
       held = list(owner = rep(seq_along(live_group), lengths(classes)),
                   class = unlist(classes, use.names = FALSE)))
}

# The witness bodies of witness_pair_reading(), one per row (`paths` the
# longer path of each pair, such as the slash URL `P/`, `class` the rows'
# classes, `held` the (rule, class) pairs a
# body may draw on, `rule` indexing `rules`): `bodies`, and `rule` (indexes
# of `rules`, row after row in file order) with `start`, each row's first
# position in `rule`. A rule joins a row's body when it can match `P/` (and
# so `P`, a prefix of it): its pattern (slash_rule_parts()) must start with
# its literal head and hold each later literal fragment. A rule with no
# later fragment is found by its head (slash_head_hits()), one with one
# through its longest later fragment (slash_fragment_hits()). Both keep a
# superset of the rules that match, so the decisions are the whole group's.
# A row's own rule is always in its body. Rows are kept in order, whole
# owners (`owner`, the rows' candidates) at a time, while their body lines
# fit `budget` (slash_rows_within()); `rows` counts the rows kept and
# `spent` their body lines. Without the budget the body lines could grow
# with rules times candidates: rules sharing a prefix or a fragment's first
# bytes with every candidate (ROBO-dbvmxcfw). The rest of the work is linear
# in `held` and in the bytes of the paths.
slash_split_bodies <- function(rules, held, paths, class, written = NULL,
                               owner = seq_along(paths), budget = Inf) {
  rule <- held$rule
  part <- slash_rule_parts(rules$type[rule], rules$value[rule])
  head <- part$head
  frag <- part$frag
  wide <- nzchar(frag)
  near <- slash_head_hits(rule[!wide], held$class[!wide], head[!wide],
                          paths, class)
  far <- slash_fragment_hits(rule[wide], held$class[wide], head[wide],
                             frag[wide], paths, class)
  within <- slash_rows_within(near, far, owner, budget)
  if (within$rows == 0L) {
    return(list(bodies = character(), rule = integer(), start = integer(),
                rows = 0L, spent = within$spent))
  }
  pairs <- slash_pairs_upto(near, far, paths, within$rows)
  row <- pairs$row
  rule <- pairs$rule
  order_by <- order(row, rule)
  row <- row[order_by]
  rule <- rule[order_by]
  # The rule line as written (`written`, slash_written_rules()): its key and
  # value bytes with no space after the colon, so a witness line is never
  # longer than the line it copies and a rule written at Google's line
  # buffer stays whole. Without it, `Allow` or `Disallow` and the canonical
  # value.
  line <- if (is.null(written)) {
    paste0(ifelse(rules$type[rule] == "allow", "Allow", "Disallow"), ":",
           rules$value[rule])
  } else {
    written[rule]
  }
  # A row may hold no rule (the removal read of rule_render_resource_blocked
  # leaves out its own), so no rule gives no line.
  text <- if (length(rule) == 0L) character() else paste0(line, "\n")
  kept <- seq_len(within$rows)
  bodies <- vapply(split(text, factor(row, kept)), function(x) {
    paste0("User-agent: witness\n", paste(x, collapse = ""))
  }, "", USE.NAMES = FALSE)
  list(bodies = bodies, rule = rule, start = match(kept, row),
       rows = within$rows, spent = within$spent)
}

# How many leading rows slash_split_bodies() keeps: all of them when their
# body lines fit `budget`, else the most whole owners (rows are in owner
# order) that fit, found by halving. A row's lines are its head hits'
# rules and the fragment postings up to it, counted without building them.
slash_rows_within <- function(near, far, owner, budget) {
  n <- length(owner)
  per_row <- numeric(n)
  if (length(near$row) > 0L) {
    sums <- rowsum(lengths(near$found), near$row)
    per_row[as.integer(rownames(sums))] <- sums[, 1L]
  }
  cum <- c(0, cumsum(per_row))
  far_upto <- slash_postings_upto(far)
  cost <- function(e) {
    cum[[e + 1L]] + far_upto(e)
  }
  if (cost(n) <= budget) {
    return(list(rows = n, spent = cost(n)))
  }
  ends <- which(c(owner[-1L] != owner[-n], TRUE))
  lo <- 0L
  hi <- length(ends)
  while (lo < hi) {
    mid <- (lo + hi + 1L) %/% 2L
    if (cost(ends[[mid]]) <= budget) lo <- mid else hi <- mid - 1L
  }
  e <- if (lo == 0L) 0L else ends[[lo]]
  list(rows = e, spent = cost(e))
}

# For the fragment hits `far`, a function of a row `e`: how many of all the
# rules' postings are rows up to `e`. Rules sharing a (class, gram) share
# its posting, which is counted once and weighted by those rules: the
# setup is linear in the distinct postings, and each call is one search,
# not one per rule, so the halving in slash_rows_within() never costs the
# rules times their postings.
slash_postings_upto <- function(far) {
  id <- far$id[!is.na(far$id)]
  if (length(id) == 0L) {
    return(function(e) 0)
  }
  weight <- tabulate(id, length(far$index))
  used <- which(weight > 0L)
  rows <- unlist(far$index[used], use.names = FALSE)
  each <- rep(as.numeric(weight[used]), lengths(far$index[used]))
  o <- order(rows)
  rows <- rows[o]
  total <- c(0, cumsum(each[o]))
  function(e) {
    total[[findInterval(e, rows, checkSorted = FALSE, checkNA = FALSE) + 1L]]
  }
}

# How many rows of each rule's posting in `far` are up to `last`, found
# once per distinct posting (slash_postings_upto()).
slash_posting_lengths <- function(far, last) {
  lens <- integer(length(far$found))
  hit <- !is.na(far$id)
  if (!any(hit)) {
    return(lens)
  }
  used <- unique(far$id[hit])
  upto <- vapply(far$index[used], function(p) {
    findInterval(last, p, checkSorted = FALSE, checkNA = FALSE)
  }, 0L)
  lens[hit] <- upto[match(far$id[hit], used)]
  lens
}

# The (row, rule) pairs of slash_split_bodies() for rows up to `last`: the
# head hits, and the fragment postings cut at `last`, kept where the path
# starts with the rule's head.
slash_pairs_upto <- function(near, far, paths, last) {
  k <- near$row <= last
  near_row <- rep(near$row[k], lengths(near$found[k]))
  near_rule <- unlist(near$found[k], use.names = FALSE)
  lens <- slash_posting_lengths(far, last)
  far_row <- unlist(Map(function(p, l) p[seq_len(l)], far$found, lens),
                    use.names = FALSE)
  far_row <- as.integer(far_row)
  far_rule <- rep(far$rule, lens)
  # A perf filter only: a rule whose head the path does not start with
  # cannot match it, so keeping it would change no decision.
  keep <- startsWith(paths[far_row], rep(far$head, lens))
  list(row = c(near_row, far_row[keep]), rule = c(near_rule, far_rule[keep]))
}

# Each rule's pattern as Google's matcher reads it against a candidate path,
# split for slash_split_bodies(): `head`, the literal bytes before the first
# `*`, and `frag`, the longest literal run after it ("" when none). An
# Allow ending in `/index.htm...` is cut after its last `/`, which Google's
# matcher also reads as that path with `$`; only a final `$` anchors. A `$`
# elsewhere, a `?` and a `%` are literal bytes to Google's matcher, which
# compares the path and query byte by byte, so a head or fragment holding
# one is kept only for a path that holds it too.
slash_rule_parts <- function(type, value) {
  pattern <- value
  index <- type == "allow" & grepl("/index[.]htm[^/]*$", value, useBytes = TRUE)
  pattern[index] <- sub("index[.]htm[^/]*$", "", value[index], useBytes = TRUE)
  pattern <- sub("[$]$", "", pattern, useBytes = TRUE)
  star <- regexpr("*", pattern, fixed = TRUE, useBytes = TRUE)
  wild <- star > 0L
  head <- pattern
  frag <- character(length(pattern))
  head[wild] <- substr(pattern[wild], 1L, star[wild] - 1L)
  rest <- strsplit(substring(pattern[wild], star[wild] + 1L), "*",
                   fixed = TRUE, useBytes = TRUE)
  frag[wild] <- vapply(rest, function(f) {
    if (length(f) == 0L) "" else f[[which.max(nchar(f, "bytes"))]]
  }, "")
  list(head = head, frag = frag)
}

# Where rules with no later fragment can match, unbuilt: `row`, a row
# whose path starts with some rule's head in the rule's class, and
# `found`, those rules, one vector per entry of `row`. Heads are looked up
# at their distinct lengths only, so a long path costs its length, not its
# length squared.
slash_head_hits <- function(rule, rule_class, head, paths, class) {
  if (length(rule) == 0L) {
    return(list(row = integer(), found = list()))
  }
  key <- paste(rule_class, head, sep = "\n")
  by_key <- split(rule, factor(key, unique(key)))
  sizes <- sort(unique(nchar(head, "bytes")))
  # A perf filter only: a head longer than the path is no prefix of it, so
  # looking it up too would find nothing.
  n <- findInterval(nchar(paths, "bytes"), sizes)
  row <- rep(seq_along(paths), n)
  size <- sizes[sequence(n)]
  hit <- match(paste(class[row], substr(paths[row], 1L, size), sep = "\n"),
               names(by_key))
  list(row = row[!is.na(hit)], found = unname(by_key[hit[!is.na(hit)]]))
}

# Where rules with a later fragment can match, unbuilt: for each rule, in
# `found`, the rows (ascending) whose path, in the rule's class, holds the
# fragment's first three bytes (slash_gram_index()); with `rule` and `head`,
# and, for counting, `index`, the distinct postings, and `id`, each rule's
# place in it (NA for none).
slash_fragment_hits <- function(rule, rule_class, head, frag, paths, class) {
  if (length(rule) == 0L) {
    return(list(found = list(), rule = integer(), head = character(),
                index = list(), id = integer()))
  }
  gram <- substr(frag, 1L, 3L)
  index <- slash_gram_index(paths, class, sort(unique(nchar(gram, "bytes"))))
  id <- match(paste(rule_class, gram, sep = "\n"), names(index))
  found <- index[id]
  found[lengths(found) == 0L] <- list(integer())
  list(found = unname(found), rule = rule, head = head,
       index = unname(index), id = id)
}

# The rows of each (class, run of `sizes` bytes) the paths hold, as a list
# named by "class\nrun"; a row is listed once per run. The runs number at
# most three per byte of each path.
slash_gram_index <- function(paths, class, sizes) {
  parts <- lapply(sizes, function(g) {
    k <- pmax(nchar(paths, "bytes") - g + 1L, 0L)
    row <- rep(seq_along(paths), k)
    start <- sequence(k)
    list(row = row, key = paste(class[row],
                                substr(paths[row], start, start + g - 1L),
                                sep = "\n"))
  })
  row <- unlist(lapply(parts, `[[`, "row"), use.names = FALSE)
  key <- unlist(lapply(parts, `[[`, "key"), use.names = FALSE)
  # A perf filter only: a run a path holds twice would list the row twice,
  # and the duplicate witness line would change no decision.
  keep <- !duplicated(paste(row, key, sep = "\n"))
  split(row[keep], factor(key[keep], unique(key[keep])))
}

# The split rows: one per Allow (the bare URL stays disallowed by
# `bare_line`), and one per set of crawler classes (whole-value merge) for
# the Disallows (the bare URL stays allowed), in line order.
slash_split_rows <- function(groups, at, bare_line) {
  rules <- groups$rules
  allow <- rules$type[at] == "allow"
  opened <- at[allow]
  shown <- slash_shown(rules$value[opened])
  blocked <- slash_rows(
    rules$type[opened], rules$line[opened],
    paste0(
      sprintf(paste0(
        "This Allow opens the URL '%s', but '%s' stays disallowed by line ",
        "%d.%s"
      ), shown$slash, shown$bare, bare_line[allow], slash_redirect()),
      slash_crawler_note(groups$agents, rules$group[opened])
    )
  )
  found <- rbind(blocked, slash_open_rows(groups, at[!allow]))
  found <- found[order(found$line), , drop = FALSE]
  rownames(found) <- NULL
  found
}

slash_redirect <- function() {
  paste0(" A server redirect between the two URLs changes what a crawler ",
         "reaches.")
}

# One row per set of crawler classes for Disallows `at` that block `P/` and
# leave `P` allowed, on the first User-agent line of the group holding the
# earliest one. `message` builds each row's text from the set's values and
# lines (rule_end_anchor_query passes its own).
slash_open_rows <- function(groups, at, cap = 5L,
                            message = slash_open_message) {
  rules <- groups$rules
  if (length(at) == 0L) {
    return(slash_rows(character()))
  }
  group <- rules$group[at]
  signature <- slash_open_sets(groups, group)
  sets <- split(seq_along(at), factor(signature, unique(signature)))
  first <- vapply(sets, `[[`, 0L, 1L)
  # The group's first User-agent line the check reads (slash_groups() may
  # have left out a policy-token line before it); agents are in file order.
  anchor <- groups$agents$line[match(group[first], groups$agents$group)]
  text <- vapply(sets, function(k) {
    message(rules$value[at[k]], rules$line[at[k]], cap)
  }, "", USE.NAMES = FALSE)
  slash_rows(
    rep("disallow", length(sets)), anchor,
    paste0(text, slash_crawler_note(groups$agents, group[first])),
    directive = "user-agent"
  )
}

# The set of crawler classes (whole-value merge) of each of `group`, as a
# signature: slash_open_rows() gives one row per signature.
slash_open_sets <- function(groups, group) {
  wanted <- unique(group)
  rows <- validation_token_expander(groups, groups$agents$uncut)(wanted)
  signature <- vapply(split(rows$class, factor(rows$owner,
                                               seq_along(wanted))),
                      function(x) paste(sort(x), collapse = " "), "")
  unname(signature[match(group, wanted)])
}

slash_open_message <- function(value, line, cap) {
  if (length(value) == 1L) {
    shown <- slash_shown(value)
    return(sprintf(paste0(
      "The Disallow on line %d blocks the URL '%s', but '%s' stays ",
      "allowed.%s"
    ), line, shown$slash, shown$bare, slash_redirect()))
  }
  shown <- utils::head(seq_along(value), cap)
  listed <- sprintf("'%s' (line %d)", slash_shown(value[shown])$slash,
                    line[shown])
  paste0(
    "These Disallows block the URL that ends in '/', but the URL without ",
    "it stays allowed: ", joined_and(listed, length(value) - length(shown)),
    ".", slash_redirect()
  )
}

# A Disallow whose pattern ends in `$` and holds no `?` blocks its path but
# not the same path with a query added (ROBO-nzcvlsvk): the `$` ends the
# match at the end of the path and query together. The control is the
# value as a path (end_anchor_controls()), each `*` written as a filler
# byte, and the witness the control with a query added: `x` and `?x=1`
# first, then `y` and `?y=2`, then `z` and `?z=3` (end_anchor_fillers())
# for a candidate the earlier pair left unreported, so another rule that
# happens to match one filler (`Disallow: /x/`, `Disallow: /*x=`) does not
# silence it. Each pair is read whole, and the row shows the pair that
# passed. A candidate (end_anchor_candidates()) is reported only when,
# for every crawler class its group names, merged on the whole User-agent
# value and on Google's token, it is the line that decides the control,
# so the control is disallowed, and the witness comes out allowed: every
# rule of the class takes part, so a second rule that blocks the witness
# or an Allow that wins the control silences it. The decisions are Google's
# matcher's, read by witness_pair_readings() within `budget`
# (slash_budget()) in line order, the later pairs on what the first left
# (end_anchor_reads()). Candidates count as checked up to the first one
# whose reading did not finish within it; that one and every later one get
# no row, and the stop counts say so. One row
# per set of crawler classes, on the first User-agent line the check reads
# of the group holding the earliest one (slash_open_rows()). A cut body is
# not checked: a later Disallow could block the witness. Returns
# slash_rows() with a `directive` column; when the budget cut candidates,
# its "stopped" attribute holds slash_stop()'s counts. A rule a NUL cuts
# takes part with its value cut at the NUL, as Google's parser reads it,
# so the decisions are Google's reading, which the row's NUL sentence
# names.
end_anchor_diagnostics <- function(groups, written = NULL, budget = NULL) {
  groups <- slash_groups(groups)
  rules <- groups$rules
  at <- end_anchor_candidates(rules)
  if (length(at) == 0L) {
    return(slash_rows(character()))
  }
  if (is.null(budget)) {
    budget <- slash_budget(rules, at)
  }
  read <- end_anchor_reads(groups, at, written, budget)
  # Candidates count as checked in line order up to the first one whose
  # reading did not finish; a row past it would contradict the stop row.
  checked <- match(FALSE, read$finished, nomatch = length(at) + 1L) - 1L
  pair <- read$pair
  pair[seq_along(pair) > checked] <- NA_integer_
  hit <- which(!is.na(pair))
  hit_line <- rules$line[at[hit]]
  message <- function(value, line, cap) {
    end_anchor_message(value, line, cap, pair[hit][match(line, hit_line)])
  }
  out <- slash_open_rows(groups, at[hit], message = message)
  attr(out, "stopped") <- slash_stop(rules, at, checked)
  out
}

# The filler-pair readings of the candidates `at`, sharing `budget`: each
# pair reads, in line order, the candidates every earlier pair read and
# left unreported. Returns list(pair, finished): `pair`, the first pair
# that passed (NA when none did), and `finished`, whether the candidate's
# reading is done, as it is once a pair passes or every pair has read it.
# A candidate some pair did not reach within the budget is not finished.
end_anchor_reads <- function(groups, at, written, budget) {
  fill <- end_anchor_fillers()
  rules <- groups$rules
  pair <- rep(NA_integer_, length(at))
  finished <- rep(FALSE, length(at))
  todo <- seq_along(at)
  for (k in seq_along(fill$path)) {
    control <- end_anchor_controls(rules$value[at[todo]], fill$path[[k]])
    read <- witness_pair_readings(groups, at[todo], control,
                                  paste0(control, fill$query[[k]]), "short",
                                  written, budget)
    budget <- budget - read$spent
    pair[todo[read$ok]] <- k
    finished[todo[read$ok]] <- TRUE
    # The next pair reads only the candidates this one read and left: one
    # this pair did not reach within the budget stays unfinished, so a
    # later pair never reports it without the earlier pairs' readings.
    done <- seq_len(read$checked)
    todo <- todo[done][!read$ok[done]]
    # A perf shortcut only: with no candidate left, a later pair reads
    # nothing.
    if (length(todo) == 0L) {
      break
    }
  }
  # What the last pair read and left: every pair has read it.
  if (k == length(fill$path)) {
    finished[todo] <- TRUE
  }
  list(pair = pair, finished = finished)
}

# The filler pairs, in the order tried: the byte each `*` of the control is
# written as, and the query the witness adds.
end_anchor_fillers <- function() {
  list(path = c("x", "y", "z"), query = c("?x=1", "?y=2", "?z=3"))
}

# Indexes of `rules` that are rule_end_anchor_query candidates: a non-empty
# Disallow whose canonical value is led by `/` or `*`, ends in its only
# `$` and holds no `?`, so the `$` anchors the path alone. Not one ending in
# `*$`: the `*` matches every ending, so the `$` anchors nothing. Not one
# whose control holds a `.` or `..` segment, written as is or as `%2E`
# (query_parameter_candidates()'s scan): URL normalization would remove it
# from the control before matching. Nor one whose control holds a `%` that
# starts no two-hex-digit escape (rule_invalid_percent_escape): no correctly
# encoded URL carries it, so there is no exact control to show. Nor one
# holding a space, a tab, another control byte or DEL (rule_inner_whitespace,
# rule_control_character): no URL a crawler sends carries such a byte.
end_anchor_candidates <- function(rules) {
  value <- rules$value
  hit <- which(
    rules$type == "disallow" &
      grepl("^[/*][^?$]*[$]$", value, useBytes = TRUE) &
      !endsWith(value, "*$")
  )
  hit[url_safe_path(value[hit], end_anchor_controls(value[hit]))]
}

# Whether each rule `value`, written as the URL path `path`, gives a path a
# crawler can send as is: `value` holds no space, tab, other control byte
# or DEL (rule_inner_whitespace, rule_control_character), and `path` no `.`
# or `..` segment, written as is or as `%2E` (URL normalization would
# remove it), and no `%` that starts no two-hex-digit escape
# (rule_invalid_percent_escape: no correctly encoded URL carries it).
url_safe_path <- function(value, path) {
  odd <- grepl("[\001-\040\177]", value, useBytes = TRUE)
  dot <- grepl("/([.]|%2E){1,2}(/|$)", path, useBytes = TRUE)
  stray <- grepl("%", gsub("%[0-9A-Fa-f]{2}", "", path, useBytes = TRUE),
                 fixed = TRUE)
  !odd & !dot & !stray
}

# Each candidate value as a path: without its final `$`, each `*` written
# `filler` (one for all, or one per value), led by `/`.
end_anchor_controls <- function(value, filler = "x") {
  filler <- rep_len(filler, length(value))
  x <- sub("[$]$", "", value, useBytes = TRUE)
  for (f in unique(filler)) {
    k <- filler == f
    x[k] <- gsub("*", f, x[k], fixed = TRUE, useBytes = TRUE)
  }
  ifelse(startsWith(x, "/"), x, paste0("/", x))
}

# The control and witness of filler pair `pair` (end_anchor_fillers()) as
# the messages show them: the control elided as query_parameter_cap()
# elides past 40 bytes, and the witness the same text with the pair's query
# after it. A candidate value is printable ASCII (end_anchor_candidates()
# leaves out control bytes, and the canonical value escapes the rest), so
# it shows as is.
end_anchor_shown <- function(value, pair = 1L) {
  fill <- end_anchor_fillers()
  control <- query_parameter_cap(end_anchor_controls(value, fill$path[pair]),
                                 40L)
  list(control = control, witness = paste0(control, fill$query[pair]))
}

# One row's text for the Disallows `value` on lines `line`, each shown with
# its filler pair `pair`: one names its line, more are listed, five at
# most, then a count.
end_anchor_message <- function(value, line, cap, pair = 1L) {
  shown <- end_anchor_shown(value, pair)
  blocks <- sprintf("blocks '%s' but not '%s'", shown$control, shown$witness)
  if (length(value) == 1L) {
    return(sprintf("The Disallow on line %d %s.%s", line, blocks,
                   end_anchor_why("the rule")))
  }
  k <- utils::head(seq_along(value), cap)
  paste0(
    "These Disallows block a path but not the same path with a query added: ",
    joined_and(sprintf("line %d %s", line[k], blocks[k]),
               length(value) - length(k)),
    ".", end_anchor_why("each rule")
  )
}

end_anchor_why <- function(rule) {
  paste0(" A final '$' ends the match at the end of the path and query ",
         "together, so the query shown takes the URL out of ", rule,
         ". The site may serve the same page with a query.")
}

# The opening of a stopped end-anchor check's rule_check_stopped row: what
# it looks for, with the file's count and its earliest skipped value.
end_anchor_stop_intro <- function(stop) {
  rules <- if (stop$found == 1L) "1 Disallow rule" else
    sprintf("%d Disallow rules", stop$found)
  shown <- end_anchor_shown(stop$value)
  sprintf(paste0(
    "This file has %s that this check reads (a pattern that ends in '$' ",
    "with no '?' before it), such as '%s'. For each one, the validator ",
    "checks whether the rule blocks '%s' but not '%s'."
  ), rules, query_parameter_cap(stop$value, 40L), shown$control,
  shown$witness)
}

# An Allow that opens with `*` or `/*` and then names a path (`*/x/`,
# `/*/x/`, `/**/x$`) also matches inside a URL's query (ROBO-micbpqbc): it
# can allow `/c?q=/x/` while a Disallow blocks `/c`. Candidates are
# (Allow, Disallow) pairs (reopen_lists()): the Allow a safe shape-A one
# (reopen_shape(), url_safe_path() on its literal), the Disallow a control
# (reopen_controls()) the same crawlers have. The control is the Disallow
# as a path, and the witness the control, `?q=` and the Allow's literal
# (reopen_literal()). A pair is reported when, for every crawler class the
# Allow's group names, merged on the whole User-agent value and on Google's
# token, the Allow decides the witness, which so comes out allowed, the
# control is disallowed and every class names the same line deciding it,
# and, with every shape-A Allow left out, that line decides the control
# and the witness comes out disallowed too (reopen_reads()). The row names
# that line, which may be another Disallow than the pair's (`/c$`). The
# decisions are Google's matcher's, read by witness_pair_readings() within
# `budget` (slash_budget() on the Allows). Each Allow's pairs are read in
# Disallow line order and only up to the first that proves
# (reopen_rounds()), so an Allow whose first pair proves costs one pair
# however many Disallows its crawlers have. An Allow counts as checked once
# each pair up to its first reported one finished, in line order up to the
# first unfinished Allow; that one and every later one get no row, and the
# stop counts say so. One row per set of crawler classes, on the first
# User-agent line the check reads of the group holding the earliest Allow
# (slash_open_rows()), with the first Allow's witness and four more Allows
# at most, then a count. A cut body is not checked: a later rule could
# decide the witness. `filter = FALSE` turns
# off the length filter of reopen_take(), and `chunk = Inf` reads every
# pair in one round, for the tests. Returns slash_rows() with a
# `directive` column; when the budget cut Allows, its "stopped" attribute
# holds slash_stop()'s counts.
allow_reopens_diagnostics <- function(groups, written = NULL, budget = NULL,
                                      filter = TRUE, chunk = 1) {
  groups <- slash_groups(groups)
  rules <- groups$rules
  shape <- reopen_shape(rules)
  allows <- shape[url_safe_path(rules$value[shape],
                                reopen_literal(rules$value[shape]))]
  if (length(allows) == 0L) {
    return(slash_rows(character()))
  }
  if (is.null(budget)) {
    budget <- slash_budget(rules, allows)
  }
  lists <- reopen_lists(groups, allows, reopen_controls(rules), filter)
  state <- reopen_rounds(groups, shape, allows, lists, written, budget, chunk)
  # Allows count as checked in line order up to the first one whose pairs
  # did not finish. The rounds read Allows out of line order, so a later
  # Allow can prove before an earlier one runs out of budget; a row past
  # the first unfinished Allow would contradict the stop row.
  finished <- state$status %in% c("hit", "none")
  checked <- match(FALSE, finished, nomatch = length(allows) + 1L) - 1L
  hit <- which(state$status == "hit" & seq_along(allows) <= checked)
  out <- reopen_rows(groups, allows[hit], state$control[hit],
                     state$line[hit])
  attr(out, "stopped") <- slash_stop(rules, allows, checked)
  out
}

# The Disallows each Allow may pair with, gathered lazily: `key`, per
# Allow, its set of crawler classes on the whole-value merge
# (reopen_near()), `gather(i)`, the positions in `controls` (in line
# order) of the Disallows the classes of Allow `i` hold, with the work
# that took, and the sizes the length filter compares. A pair's Disallow
# shares a crawler class with its Allow on the whole-value merge: the row
# speaks for those crawlers, and a control from another crawler's Disallow
# would say nothing about theirs. Each set of classes is gathered once, at
# one unit per group and Disallow gathered, so the work never grows with
# Allows times Disallows. With no control, nothing is built.
reopen_lists <- function(groups, allows, controls, filter = TRUE) {
  d <- controls$at
  rules <- groups$rules
  out <- list(d = d, control = controls$control, filter = filter,
              size = nchar(rules$value[d], "bytes"),
              a_size = nchar(rules$value[allows], "bytes"))
  if (length(d) == 0L) {
    return(out)
  }
  near <- reopen_near(groups, rules$group[c(allows, d)])
  by_group <- split(seq_along(d), rules$group[d])
  out$key <- near$key(rules$group[allows])
  out$gather <- function(i) {
    near_groups <- near$groups(rules$group[allows[[i]]])
    pos <- as.integer(unlist(by_group[as.character(near_groups)],
                             use.names = FALSE))
    list(pos = sort(pos), spent = length(near_groups) + length(pos))
  }
  out
}

# The next pairs of Allow `i` from its list `pos` past `cursor`, at most
# `want`, as list(idx, cursor, spent): the places in `pos` taken, the new
# cursor and the entries passed. A perf filter only: Google ranks matching
# rules by pattern length and an Allow wins a tie, and a Disallow matches
# the witness as it matches the control, a prefix of it, so an Allow
# shorter than a Disallow its crawlers have can never decide the witness;
# such a Disallow is passed over. At most four entries per pair wanted,
# and `limit`, are passed in one call, and each entry passed counts as
# work.
reopen_take <- function(lists, i, pos, cursor, want, limit = Inf) {
  rest <- min(length(pos) - cursor, limit)
  if (!lists$filter) {
    n <- min(rest, want)
    return(list(idx = cursor + seq_len(n), cursor = cursor + n, spent = n))
  }
  idx <- cursor + seq_len(min(rest, 4 * want))
  ok <- idx[lists$size[pos[idx]] <= lists$a_size[[i]]]
  if (length(ok) >= want) {
    ok <- ok[seq_len(want)]
    end <- ok[[length(ok)]]
  } else {
    end <- cursor + length(idx)
  }
  list(idx = ok, cursor = end, spent = end - cursor)
}

# Reads the Allows' pairs in rounds: round `r` takes up to `chunk` times
# 2^(r - 1) more pairs of each Allow still pending (reopen_take()), in
# Allow order, and reads them (reopen_reads()). Each round has what is left
# of `budget`: half for the lists, the takes and the first reading, the
# rest for the removal read. An Allow's first proving pair ends it
# ("hit"), as does a list read through with none ("none"; the next
# round's take finds it so, at no cost). A pair the
# round's share could not take or read is taken again in the next round,
# with what the round left; a round that moves no Allow on and gathers no
# list ends the reading, and the Allows still pending are "open". The
# chunks double, and a round that runs out of its share leaves at most
# half of what it had, so the rounds number at most about log2 of the
# longest list plus log2 of `budget`. Returns, per Allow, `status` and,
# for a hit, its pair's `control` and `line`, the line deciding the
# control.
reopen_rounds <- function(groups, shape, allows, lists, written, budget,
                          chunk = 1) {
  n <- length(allows)
  status <- rep("pending", n)
  control <- rep(NA_character_, n)
  line <- rep(NA_integer_, n)
  if (length(lists$d) == 0L) {
    status[] <- "none"
    return(list(status = status, control = control, line = line))
  }
  cursor <- integer(n)
  held <- list()
  spent <- 0
  want <- chunk
  repeat {
    pending <- which(status == "pending")
    if (length(pending) == 0L) {
      break
    }
    left <- budget - spent
    was <- list(status, cursor, names(held))
    take <- reopen_round_take(lists, pending, cursor, held, want, left / 2)
    held <- take$held
    cursor <- take$cursor
    status[take$none] <- "none"
    pairs <- take$pairs
    read <- reopen_reads(groups, shape, allows, pairs, written,
                         left - take$spent, left / 2 - take$spent)
    spent <- spent + take$spent + read$spent
    # Per Allow of the round, its first pair that did not finish or
    # proved: a proof ends it, and an unfinished pair is taken again.
    stops <- which(!read$done | read$ok)
    owners <- unique(pairs$allow)
    first <- stops[match(owners, pairs$allow[stops])]
    found <- !is.na(first)
    proved <- found & read$ok[first]
    hit <- owners[proved]
    status[hit] <- "hit"
    control[hit] <- pairs$control[first[proved]]
    line[hit] <- read$line[first[proved]]
    again <- found & !proved
    cursor[owners[again]] <- pairs$idx[first[again]] - 1L
    if (identical(list(status, cursor, names(held)), was)) {
      status[status == "pending"] <- "open"
      break
    }
    want <- want * 2
  }
  list(status = status, control = control, line = line)
}

# One round's takes for the pending Allows `pending`, in order, within
# `budget`: each gathers its list once per set of classes (`held`, by
# reopen_lists()$key) and takes its next `want` pairs (reopen_take()), as
# far as `budget` goes. The first Allow whose
# list does not fit takes nothing, nor does any later one; one whose list
# is read through with nothing taken is `none`. Returns the pairs as
# list(allow, at, control, idx), `idx` each pair's place in its Allow's
# list, with `held`, `cursor`, `none` and `spent`.
reopen_round_take <- function(lists, pending, cursor, held, want, budget) {
  allow <- list()
  idx <- list()
  pos <- list()
  none <- integer()
  spent <- 0
  for (j in seq_along(pending)) {
    i <- pending[[j]]
    key <- lists$key[[i]]
    cost <- 0
    list_pos <- held[[key]]
    if (is.null(list_pos)) {
      found <- lists$gather(i)
      cost <- found$spent
      list_pos <- found$pos
    }
    room <- floor(budget - spent - cost)
    if (room < min(1, length(list_pos) - cursor[[i]])) {
      break
    }
    got <- reopen_take(lists, i, list_pos, cursor[[i]], want, room)
    held[[key]] <- list_pos
    spent <- spent + cost + got$spent
    cursor[[i]] <- got$cursor
    if (length(got$idx) == 0L && got$cursor >= length(list_pos)) {
      none <- c(none, i)
    }
    allow[[j]] <- rep(i, length(got$idx))
    idx[[j]] <- got$idx
    pos[[j]] <- list_pos[got$idx]
  }
  pos <- as.integer(unlist(pos, use.names = FALSE))
  list(pairs = list(allow = as.integer(unlist(allow, use.names = FALSE)),
                    at = lists$d[pos], control = lists$control[pos],
                    idx = as.integer(unlist(idx, use.names = FALSE))),
       held = held, cursor = cursor, none = none, spent = spent)
}

# Indexes of `rules` that are shape-A Allows: a pattern led by `*` or `/*`
# (wildcard_allow_prefix() "" or "/") whose rest after the leading run of
# `*` starts with `/` and names at least one more byte before any final
# run of `*` and `$`. Not `/*/`, `/*/$` or `/*/*` alone, which name no path
# (a final `*` names no byte, so `/*/*` matches what `/*/` matches), nor
# `/*.css` or `*?next=`, which name no path from its start.
reopen_shape <- function(rules) {
  value <- rules$value
  rest <- sub("^/?[*]+", "", value, useBytes = TRUE)
  named <- sub("[*]*[$]?$", "", rest, useBytes = TRUE)
  which(rules$type == "allow" & grepl("^/?[*]", value, useBytes = TRUE) &
          startsWith(rest, "/") & nchar(named, "bytes") >= 2L)
}

# The path each shape-A Allow names, as the witness ends: the value after
# its leading `/` and run of `*`, without a final `$`, each later `*`
# written `x`.
reopen_literal <- function(value) {
  rest <- sub("[$]$", "", sub("^/?[*]+", "", value, useBytes = TRUE),
              useBytes = TRUE)
  gsub("*", "x", rest, fixed = TRUE, useBytes = TRUE)
}

# The Disallows that give controls, as list(at, control): `at` indexes
# `rules`, each a non-empty Disallow led by `/` or `*`, with no `?` and no
# final `$` (a final `$` could not match the witness), and `control` its
# value as a path (end_anchor_controls()). One whose control fails
# url_safe_path() gives none.
reopen_controls <- function(rules) {
  value <- rules$value
  at <- which(rules$type == "disallow" &
                grepl("^[/*][^?]*$", value, useBytes = TRUE) &
                !endsWith(value, "$"))
  control <- end_anchor_controls(value[at])
  safe <- url_safe_path(value[at], control)
  list(at = at[safe], control = control[safe])
}

# The crawler classes of the groups `wanted` on the whole-value merge
# (validation_token_expander()), as functions of group ids: `key`, one
# string per set of classes, and `groups`, for one group, every group
# sharing a class with it, itself included. The work comes from the
# (group, class) pairs, which grow with the User-agent lines.
reopen_near <- function(groups, wanted) {
  wanted <- unique(wanted)
  pairs <- validation_token_expander(groups, groups$agents$uncut)(wanted)
  by_class <- split(wanted[pairs$owner], pairs$class)
  classes <- split(pairs$class, factor(pairs$owner, seq_along(wanted)))
  key <- vapply(classes, function(x) paste(sort(x), collapse = " "), "",
                USE.NAMES = FALSE)
  list(
    key = function(g) paste0("#", key[match(g, wanted)]),
    groups = function(g) {
      held <- classes[[match(g, wanted)]]
      unique(unlist(by_class[as.character(held)], use.names = FALSE))
    }
  )
}

# The two readings of the pairs (list(allow, at, control), `allow`
# indexing `allows`), sharing `budget`: the first, within `first` (half of
# it by default), so the second always has the rest for what the first
# passed, of the Allow deciding the witness and the control getting the
# other decision; the second, for the pairs that pass it, within what is
# left, on a copy of `groups` with every
# shape-A Allow (`shape`) left out of every body (flagged empty), of the
# line the first named deciding the control and the witness getting the
# same decision, under the Allow's crawler classes (not those of the line's
# own group, which can name crawlers the Allow never covers): without such
# Allows, the witness would be blocked. An
# Allow of another shape that also opens the witness (`Allow: /c?`) fails
# it. Returns list(done, ok, line) per pair, with `spent`: `done` whether
# its readings finished, `ok` whether it passed both, `line` the line
# deciding its control.
reopen_reads <- function(groups, shape, allows, pairs, written, budget,
                         first = budget / 2) {
  rules <- groups$rules
  at <- allows[pairs$allow]
  n <- length(at)
  witness <- paste0(pairs$control, "?q=", reopen_literal(rules$value[at]))
  out <- list(done = rep(TRUE, n), ok = logical(n),
              line = rep(NA_integer_, n), spent = 0)
  if (n == 0L) {
    return(out)
  }
  first <- witness_pair_readings(groups, at, pairs$control, witness, "long",
                                 written, first, share = TRUE)
  out$line <- first$line
  out$spent <- first$spent
  read <- seq_len(n) <= first$checked
  out$done <- read
  k <- which(read & first$ok & !is.na(first$line))
  if (length(k) == 0L) {
    return(out)
  }
  removed <- groups
  removed$rules$empty[shape] <- TRUE
  second <- witness_pair_readings(
    removed, match(first$line[k], rules$line), pairs$control[k], witness[k],
    "short", written, budget - first$spent, differ = FALSE,
    group = rules$group[at[k]], share = TRUE
  )
  read <- seq_along(k) <= second$checked
  out$done[k] <- read
  out$ok[k] <- read & second$ok
  out$spent <- out$spent + second$spent
  out
}

# The rows for the reported Allows `at`, each with its pair's `control` and
# `decider`, the line deciding it: one per set of crawler classes
# (slash_open_rows()), naming four more Allows at most.
reopen_rows <- function(groups, at, control, decider) {
  line <- groups$rules$line[at]
  message <- function(value, lines, cap) {
    k <- match(lines[[1L]], line)
    reopen_message(value[[1L]], lines, cap, control[k], decider[k])
  }
  slash_open_rows(groups, at, cap = 4L, message = message)
}

# One row's text, in short sentences: the Allow `value` on `line[1]`, its
# control and the line `decider` deciding the control, then the lines of
# the row's other Allows, `cap` at most, then a count. The witness shows as
# the control, `?q=` and the Allow's literal, each elided past 40 bytes
# (query_parameter_cap()), so the text is bounded whatever the file holds.
# A value is printable ASCII (url_safe_path() leaves out control bytes, and
# the canonical value escapes the rest), so it shows as is.
reopen_message <- function(value, line, cap, control, decider) {
  control <- query_parameter_cap(control, 40L)
  witness <- paste0(control, "?q=",
                    query_parameter_cap(reopen_literal(value), 40L))
  paste0(sprintf(paste0(
    "The Allow on line %d ('%s') allows '%s'. The Disallow on line %d ",
    "blocks '%s'. The '*' at the start of the Allow also matches text in ",
    "the query."
  ), line[[1L]], query_parameter_cap(value, 40L), witness, decider, control),
  reopen_same_text(line[-1L], cap),
  " You may not mean to allow URLs like this.")
}

# " The Allows on lines 4, 5, 6, 7 and 2 more do the same.": the lines of a
# row's other rules (`noun`, "Allow" or "Disallow"), `cap` at most, then a
# count, or "" when there are none.
reopen_same_text <- function(lines, cap, noun = "Allow") {
  if (length(lines) == 0L) {
    return("")
  }
  if (length(lines) == 1L) {
    return(sprintf(" The %s on line %d does the same.", noun, lines))
  }
  shown <- utils::head(lines, cap)
  sprintf(" The %ss on lines %s do the same.", noun,
          joined_and(as.character(shown), length(lines) - length(shown)))
}

# The opening of a stopped reopen check's rule_check_stopped row: what it
# looks for, with the file's count and its earliest skipped value.
reopen_stop_intro <- function(stop) {
  rules <- if (stop$found == 1L) {
    "1 Allow rule that opens with '*' or '/*' and then names a path"
  } else {
    sprintf("%d Allow rules that open with '*' or '/*' and then name a path",
            stop$found)
  }
  sprintf(paste0(
    "This file has %s, such as '%s'. For each one, the validator checks ",
    "whether it also matches inside a URL's query and so allows a URL that ",
    "a Disallow blocks without the query."
  ), rules, query_parameter_cap(stop$value, 40L))
}

# A Disallow whose pattern ends in a file type a page may load (`.js`,
# `.mjs`, `.cjs`, `.css`, `.json`, `.wasm`) can block the scripts, styles
# and data a page needs to show its content (ROBO-dwywkpes). Candidates
# (render_resource_candidates()) are read on a witness, the value as a
# file path (render_resource_witness()): `x` for each inner `*` first,
# then `y`, then `z` for a candidate an earlier filler left unreported, so
# another rule that happens to match one filler (`Allow: /x.js`) does not
# silence it. A candidate is reported only when, for every crawler class
# its group names, merged on the whole User-agent value and on Google's
# token, it is the line that decides the witness, so the witness is
# disallowed and no Allow wins it, and, with every candidate of the file
# left out, the witness comes out allowed: a broader rule that blocks the
# file anyway (`Disallow: /`, `Disallow: /assets/`) silences it
# (render_resource_reads()). The decisions are Google's matcher's, read by
# witness_pair_readings() within `budget` (slash_budget()) in line order,
# the later fillers and the removal reads on what is left. Candidates
# count as checked up to the first one whose reading did not finish; that
# one and every later one get no row, and the stop counts say so. One row
# per set of crawler classes, on the first User-agent line the check
# reads of the group holding the earliest one (slash_open_rows()), with
# the first rule's witness and four more lines at most, then a count. The
# lines include every other candidate that blocks a reported one's witness
# by itself (render_resource_named()), read within a second `budget`; a
# row whose reading of them did not fit is not checked, from its first
# reported candidate on, so no row names part of its lines. A
# cut body is not checked: a later rule could decide the witness. Returns
# slash_rows() with a `directive` column; when the budget cut candidates,
# its "stopped" attribute holds slash_stop()'s counts.
render_resource_diagnostics <- function(groups, written = NULL,
                                        budget = NULL) {
  groups <- slash_groups(groups)
  rules <- groups$rules
  at <- render_resource_candidates(rules)
  if (length(at) == 0L) {
    return(slash_rows(character()))
  }
  if (is.null(budget)) {
    budget <- slash_budget(rules, at)
  }
  read <- render_resource_reads(groups, at, written, budget)
  # Candidates count as checked in line order up to the first one whose
  # reading did not finish; a row past it would contradict the stop row.
  checked <- match(FALSE, read$finished, nomatch = length(at) + 1L) - 1L
  pair <- read$pair
  pair[seq_along(pair) > checked] <- NA_integer_
  hit <- which(!is.na(pair))
  witness <- render_resource_witness(rules$value[at[hit]],
                                     end_anchor_fillers()$path[pair[hit]])
  # The naming has a budget of its own, so readings that use theirs up
  # leave it whole; the work stays linear in the file.
  named <- render_resource_named(groups, at, hit, witness, written, budget)
  # A row whose other lines did not fit is not checked, from its first
  # reported candidate on (render_resource_whole()).
  if (named$n < length(hit)) {
    checked <- hit[[named$n + 1L]] - 1L
    hit <- hit[seq_len(named$n)]
  }
  hit_line <- rules$line[at[hit]]
  message <- function(value, line, cap) {
    k <- match(line, hit_line)
    more <- setdiff(rules$line[unlist(named$rules[k])], line)
    render_resource_message(value[[1L]],
                            c(line[[1L]], sort(c(line[-1L], unique(more)))),
                            cap, pair[hit][k[[1L]]])
  }
  out <- slash_open_rows(groups, at[hit], cap = 4L, message = message)
  attr(out, "stopped") <- slash_stop(rules, at, checked)
  out
}

# Indexes of `rules` that are rule_render_resource_blocked candidates: a
# non-empty Disallow whose canonical value is led by `/` or `*` and ends in
# a listed file type, in any case, then only a run of `*`, a final `$`, or
# a query with no `/` (`/*.js`, `/*.js*$`, `/*.css?*`). Only a type-wide
# value: its file name, the text after its last `/` (the whole value when
# it has none) up to the type's dot, is a run of `*` (`/*.js`,
# `/assets/*.css`, `*.json$`), so an exact file (`/push-worker.js`) or a
# named stem (`/js/main-*.js`, `/*.min.js`) is left out. The type sits in
# the path, so no `?` comes before it, nor a `=` or `&`, which are query
# text too: `/*?*.js`, `/q?f=*.css` and `/*a&b/*.js` name query text, not
# a file. Not a folder (`/js/`), a longer type (`/*.jsp`)
# or a path that goes on (`/*.json/y`). Nor one whose witness fails
# url_safe_path(): a dot segment, a stray `%` or a byte no URL carries.
render_resource_candidates <- function(rules) {
  value <- rules$value
  hit <- which(
    rules$type == "disallow" & !rules$empty &
      grepl(
        paste0("^(([/*][^?=&]*)?/)?[*]+[.](m?js|cjs|css|json|wasm)",
               "([*]*[$]?|[?][^/]*)$"), value,
        ignore.case = TRUE, useBytes = TRUE
      )
  )
  hit[url_safe_path(value[hit], render_resource_witness(value[hit]))]
}

# Each candidate value as the path of a file it blocks: without its final
# `$` and the run of `*` before it, which would push the type off the end
# (`/x.cssx`), then each inner `*` written `filler`, led by `/`
# (end_anchor_controls()). `/*.css*` gives `/x.css`, `/a.json?v=*` gives
# `/a.json?v=`. A bare trailing `?` stays (`/*.js?` gives `/x.js?`): it is a
# literal byte to Google's matcher, and no `?` comes before the type
# (render_resource_candidates()), so the path without it holds no `?` and
# the rule cannot match it.
render_resource_witness <- function(value, filler = "x") {
  end_anchor_controls(sub("[*]*[$]?$", "", value, useBytes = TRUE), filler)
}

# The filler readings of the candidates `at`, sharing `budget`: each filler
# reads, in line order, the candidates every earlier filler read and left
# unreported (render_resource_pass()). Returns list(pair, finished) as
# end_anchor_reads() does: `pair`, the first filler that passed (NA when
# none did), and `finished`, whether the candidate's reading is done.
render_resource_reads <- function(groups, at, written, budget) {
  fill <- end_anchor_fillers()$path
  rules <- groups$rules
  removed <- groups
  removed$rules$empty[at] <- TRUE
  pair <- rep(NA_integer_, length(at))
  finished <- rep(FALSE, length(at))
  todo <- seq_along(at)
  for (k in seq_along(fill)) {
    witness <- render_resource_witness(rules$value[at[todo]], fill[[k]])
    read <- render_resource_pass(groups, removed, at[todo], witness, written,
                                 budget)
    budget <- budget - read$spent
    pair[todo[read$ok]] <- k
    finished[todo[read$ok]] <- TRUE
    # The next filler reads only the candidates this one read and left.
    done <- seq_len(read$checked)
    todo <- todo[done][!read$ok[done]]
    # A perf shortcut only: with no candidate left, a later filler reads
    # nothing.
    if (length(todo) == 0L) {
      break
    }
  }
  # What the last filler read and left: every filler has read it.
  if (k == length(fill)) {
    finished[todo] <- TRUE
  }
  list(pair = pair, finished = finished)
}

# One filler's two readings of the candidates `at` on their `witness`
# paths, sharing `budget`: the first, within half of it, that the
# candidate decides the witness (so it is disallowed); the second, for
# those that pass, on `removed` (every candidate flagged empty), within the
# rest, that the witness comes out allowed. With none passing, the second
# reads nothing and spends nothing. Returns list(ok, checked, spent):
# `checked` the leading candidates both readings finished.
render_resource_pass <- function(groups, removed, at, witness, written,
                                 budget) {
  first <- witness_pair_readings(groups, at, witness, witness, "long",
                                 written, budget / 2, differ = FALSE,
                                 share = TRUE)
  ok <- logical(length(at))
  checked <- first$checked
  k <- which(seq_along(at) <= checked & first$ok)
  second <- witness_pair_readings(removed, at[k], witness[k], witness[k],
                                  "none", written, budget - first$spent,
                                  differ = FALSE, share = TRUE)
  ok[k] <- seq_along(k) <= second$checked & second$ok
  # The second reading can run out where the first did not (its share of
  # the budget between the merges differs): a candidate it did not reach
  # is not checked, so no later filler and no "every filler read it" marks
  # it finished without a row.
  if (second$checked < length(k)) {
    checked <- min(checked, k[[second$checked + 1L]] - 1L)
  }
  list(ok = ok, checked = checked, spent = first$spent + second$spent)
}

# The other candidates a row must name beside each reported one `hit`
# (indexes of `at`), whose witness is `witness`: every candidate of `at`
# held by a crawler class of the reported one's group, on the whole-value
# merge or on Google's, that blocks the witness by itself, read with every
# other candidate left out. A longer candidate can decide the witness of a
# shorter one that blocks it too (`/*.js$` beside `/*.js`, an identical
# repeat), so the lines a row names without them could leave the file
# blocked once they are gone. With them, it comes out allowed: what is
# left holds the rules that are no candidate, which allow it (the removal
# read), and candidates that do not block it by themselves, so the longest
# rule left that matches it is an Allow, or ties one. Reported candidates
# are taken in line order while their reads fit `budget`
# (render_resource_pairs()). Returns list(rules, n): `rules`, per reported
# candidate, the indexes of `groups$rules` to name beside it, and `n`, how
# many leading reported candidates were read, cut back so that no row is
# read in part (render_resource_whole()). With none reported, nothing is
# read, so no expander is built.
render_resource_named <- function(groups, at, hit, witness, written,
                                  budget) {
  if (length(hit) == 0L) {
    return(list(rules = list(), n = 0L))
  }
  agents <- groups$agents
  keys <- list(agents$uncut)
  if (!all(agents$uncut == agents$key)) {
    keys <- c(keys, list(agents$key))
  }
  head <- slash_rule_parts(groups$rules$type[at], groups$rules$value[at])$head
  set <- slash_open_sets(groups, groups$rules$group[at])
  n <- length(hit)
  owner <- integer()
  named <- integer()
  for (key in keys) {
    read <- render_resource_pairs(groups, key, at, hit, head, witness,
                                  written, budget, n, set)
    budget <- budget - read$spent
    n <- read$n
    owner <- c(owner, read$owner)
    named <- c(named, read$rule)
  }
  # Entries past `n` are left in: the caller reads the first `n` only.
  list(rules = unname(split(named, factor(owner, seq_along(hit)))),
       n = render_resource_whole(set[hit], n))
}

# One merge's reading for render_resource_named(), on `key`, of the first
# `n` reported candidates: the (reported, candidate) pairs of a class
# where the witness starts with the candidate's literal head `head`
# (slash_head_hits()), counted before they are built, so many candidates
# sharing a head build no more of them than `budget`; then those whose
# candidate matches the witness on a body of that candidate alone; then
# those where it blocks the witness by itself (render_resource_alone()).
# The candidates are crossed only with the classes of those `n`, and the
# rows that makes are counted against `budget` before they are built
# (render_resource_held()): a file whose candidates sit in groups naming
# many crawlers could otherwise build candidates times crawlers rows.
# `set` is each candidate's row (slash_open_sets()): a reported candidate
# of the same row is no pair. Returns list(owner, rule, n, spent): the
# pairs kept (`owner` indexing
# `hit`, `rule` indexing `groups$rules`), the reported candidates read
# whole, and the work done.
render_resource_pairs <- function(groups, key, at, hit, head, witness,
                                  written, budget, n, set) {
  rules <- groups$rules
  expand <- validation_token_expander(groups, key)
  rows <- expand(rules$group[at[hit[seq_len(n)]]])
  held <- render_resource_held(expand, rules$group[at], rows$class, budget)
  if (is.null(held$owner)) {
    return(list(owner = integer(), rule = integer(), n = 0L,
                spent = held$spent))
  }
  # A reported candidate of the same row is named anyway: it is looked at
  # only in a class that holds reported candidates of more than one row,
  # where it can be another row's (a perf filter beside `other` below, but
  # not one to drop for `!own`: that would leave out another row's).
  reported <- seq_along(at) %in% hit
  own <- reported[held$owner]
  rows_of <- tapply(set[held$owner][own], held$class[own],
                    function(s) length(unique(s)))
  mixed <- as.integer(names(rows_of)[rows_of > 1L])
  look <- !own | held$class %in% mixed
  held <- list(owner = held$owner[look], class = held$class[look],
               spent = held$spent)
  near <- slash_head_hits(held$owner, held$class, head[held$owner],
                          witness[rows$owner], rows$class)
  per <- numeric(n)
  if (length(near$row) > 0L) {
    sums <- rowsum(lengths(near$found), rows$owner[near$row])
    per[as.integer(rownames(sums))] <- sums[, 1L]
  }
  cost <- held$spent + cumsum(per)
  n <- sum(cost <= budget)
  spent <- if (n == 0L) held$spent else cost[[n]]
  k <- rows$owner[near$row] <= n
  pair_row <- rep(near$row[k], lengths(near$found[k]))
  pair_at <- unlist(near$found[k], use.names = FALSE)
  # A perf filter only: a reported candidate of the pair's own row (left
  # in above in a class holding more than one row) is in that row anyway,
  # and the message drops a named line the row already shows, so reading
  # it by itself would change no row, only spend the budget.
  from <- hit[rows$owner[pair_row]]
  other <- !(reported[pair_at] & set[pair_at] == set[from])
  pair_row <- pair_row[other]
  pair_at <- pair_at[other]
  one <- unique(pair_at)
  read <- wildcard_witness_decide(
    paste0("User-agent: witness\n", render_resource_lines(rules, at[one],
                                                          written), "\n"),
    match(pair_at, one), witness[rows$owner[pair_row]]
  )
  hit_pair <- !read$allowed
  alone <- render_resource_alone(groups, expand, at, rows, pair_row[hit_pair],
                                 at[pair_at[hit_pair]], witness, written,
                                 budget - spent)
  if (alone$n < n) {
    n <- alone$n
  }
  blocks <- alone$blocks
  list(owner = rows$owner[pair_row[hit_pair]][blocks],
       rule = at[pair_at[hit_pair]][blocks], n = n,
       spent = spent + alone$spent)
}

# Whether each candidate `rule` (indexes of `groups$rules`) blocks the
# witness of its pair's row (`pair_row`, indexing `rows`, the (reported,
# class) rows of `expand`) by itself: read by Google's matcher on the
# rules of the row's class that are no candidate and can match the witness
# (slash_split_bodies()), with the candidate added in file order. Those
# rules are crossed only with the rows' classes, counted against `budget`
# first (render_resource_held()). Rows are read whole reported candidates
# at a time while their body lines fit `budget`. Returns list(blocks, n,
# spent): `n`, the reported candidates before the first whose rows did not
# fit (Inf when all did).
render_resource_alone <- function(groups, expand, at, rows, pair_row, rule,
                                  witness, written, budget) {
  out <- list(blocks = logical(length(rule)), n = Inf, spent = 0)
  if (length(rule) == 0L) {
    return(out)
  }
  rules <- groups$rules
  others <- setdiff(which(!rules$empty), at)
  wanted <- unique(pair_row)
  held <- render_resource_held(expand, rules$group[others],
                               rows$class[wanted], budget)
  if (is.null(held$owner)) {
    out$n <- rows$owner[pair_row[[1L]]] - 1L
    out$spent <- held$spent
    return(out)
  }
  body <- slash_split_bodies(rules, list(rule = others[held$owner],
                                         class = held$class),
                             witness[rows$owner[wanted]], rows$class[wanted],
                             written, rows$owner[wanted],
                             budget - held$spent)
  body$spent <- held$spent + body$spent
  # Each kept row's rules, from the first position of each row that holds
  # any (rows that hold none have no start).
  at_row <- which(!is.na(body$start))
  row_of <- rep(at_row, diff(c(body$start[at_row], length(body$rule) + 1L)))
  by_row <- split(body$rule, factor(row_of, seq_len(body$rows)))
  # Each pair's body copies its row's lines: counted too, in pair order.
  t <- match(pair_row, wanted)
  kept <- t <= body$rows
  len <- numeric(length(t))
  len[kept] <- lengths(by_row)[t[kept]]
  cost <- body$spent + cumsum(len + 1)
  read <- kept & cost <= budget
  first <- match(FALSE, read)
  if (!is.na(first)) {
    out$n <- rows$owner[pair_row[[first]]] - 1L
    read <- seq_along(read) < first
  }
  out$spent <- if (any(read)) cost[[sum(read)]] else body$spent
  t <- t[read]
  # Taken once: subsetting `rule` inside the loop would cost pairs squared.
  picked <- rule[read]
  text <- vapply(seq_along(t), function(i) {
    lines <- sort(c(by_row[[t[[i]]]], picked[[i]]))
    paste0("User-agent: witness\n",
           paste0(render_resource_lines(rules, lines, written), "\n",
                  collapse = ""))
  }, "")
  found <- wildcard_witness_decide(text, seq_along(text),
                                   witness[rows$owner[pair_row[read]]])
  out$blocks[read] <- !found$allowed
  out
}

# How many of the leading reported candidates, the first `n` of those whose
# rows are `row` (in line order), a check can show: the most that leave no
# row in part, so a row whose naming did not finish is dropped whole, with
# every reported candidate after its first, and the stop row counts them.
# A row shows its own candidates' lines and the others they name, so one
# cut in part could leave out a line that blocks its file.
render_resource_whole <- function(row, n) {
  if (n >= length(row)) {
    return(n)
  }
  # Where each candidate's row ends, and how far the rows begun by each
  # position reach: the first `i` hold whole rows when that is `i`.
  last <- length(row) + 1L - match(row, rev(row))
  whole <- which(cummax(last)[seq_len(n)] == seq_len(n))
  if (length(whole) == 0L) 0L else max(whole)
}

# The (rule, class) rows of rules whose groups are `group` under `expand`,
# for the classes in `classes` only, as list(owner, class, spent) like the
# expander's (`owner` indexing `group`), `spent` their count. They are
# counted per distinct group first and built only when the count fits
# `budget`; otherwise `owner` is NULL and nothing is built.
render_resource_held <- function(expand, group, classes, budget) {
  wanted <- unique(group)
  rows <- expand(wanted)
  keep <- rows$class %in% classes
  by <- split(rows$class[keep], factor(rows$owner[keep], seq_along(wanted)))
  k <- match(group, wanted)
  count <- lengths(by)[k]
  spent <- sum(as.numeric(count))
  if (spent > budget) {
    return(list(owner = NULL, class = NULL, spent = spent))
  }
  list(owner = rep(seq_along(group), count),
       class = as.integer(unlist(by[k], use.names = FALSE)), spent = spent)
}

# Rule lines `rule` (indexes of `rules`) as a witness body holds them: as
# written (slash_written_rules()) when `written` is given, else the key and
# the canonical value.
render_resource_lines <- function(rules, rule, written) {
  if (is.null(written)) {
    return(paste0(ifelse(rules$type[rule] == "allow", "Allow", "Disallow"),
                  ":", rules$value[rule]))
  }
  written[rule]
}

# One row's text, in short sentences: the Disallow `value` on `line[1]`
# with its witness for filler `pair`, then the lines of the row's other
# Disallows, `cap` at most, then a count. The value and the witness are
# each elided past 40 bytes (query_parameter_cap()), so the text is
# bounded whatever the file holds. A value is printable ASCII
# (url_safe_path() leaves out control bytes, and the canonical value
# escapes the rest), so it shows as is.
render_resource_message <- function(value, line, cap, pair = 1L) {
  witness <- render_resource_witness(value, end_anchor_fillers()$path[pair])
  paste0(
    sprintf("The Disallow on line %d ('%s') blocks '%s'.", line[[1L]],
            query_parameter_cap(value, 40L),
            query_parameter_cap(witness, 40L)),
    reopen_same_text(line[-1L], cap, "Disallow"),
    " A page may need files like this to show its content. A crawler that ",
    "cannot get them may not see the page as users do. Check a rendered ",
    "page and the files it loads. You may block a tracking script or an ",
    "API on purpose."
  )
}

# The opening of a stopped render-resource check's rule_check_stopped row:
# what it looks for, with the file's count and its earliest skipped value,
# so the counting sentences' "the same problem" names that problem.
render_resource_stop_intro <- function(stop) {
  rules <- if (stop$found == 1L) {
    "1 Disallow rule that ends in a file type a page may load"
  } else {
    sprintf("%d Disallow rules that end in a file type a page may load",
            stop$found)
  }
  sprintf(paste0(
    "This file has %s (.js, .css, .json and the like), such as '%s'. For ",
    "each one, the validator checks whether the rule blocks a file that a ",
    "page may need to show its content."
  ), rules, query_parameter_cap(stop$value, 40L))
}

# A literal rule `P` with no trailing `/` or `$` also matches every path
# that starts with it (RFC 9309 section 2.2.2): `Disallow: /feed` matches
# `/feeds` too (ROBO-otomgbge). When the same crawlers' rules also list such
# a sibling `M` with the same type, the author may have read `P` as exact,
# and the row notes that `P` already matches it. `P` is a literal
# (slash_candidates()) not ending in `/`; `M` is a literal too, longer, led
# by `P`, and the byte after `P` is not `/` (a subpath is what `P/` names).
# For each `M`, `P` is the longest such rule of its type in each crawler
# class of `M`'s group (whole-value merge), the same rule in every class.
# It is reported only when, for every class `M`'s group names, merged on the
# whole User-agent value and on Google's token, Google's matcher reads `M`'s
# path with `M` left out (every rule of its type and value flagged empty, as
# render_resource_reads() does) and line `P`, or a rule of its type and
# value in a group the merge joins, decides it: so an Allow that
# would take over (`Allow: /feeds` beside the pair, `Allow: /fe*sx` beside
# `/feed` and `/feedsx`) silences it, and so does a longer rule of the same
# type. A later repeat of `M` in the class is not reported. Pairs of
# opposite type are not looked at. The reads go in passes, so that no rule
# left out in a pass is a prefix of another one's path
# (prefix_sibling_passes()). The work shares `budget` (slash_budget()):
# first the lookup of `P`, then the passes, each also costing the file's
# rules once; candidates count as checked in line order up to the first one
# whose reading did not finish, and the stop counts say so. A cut body is
# not checked: a later rule could decide a path. One row per set of crawler
# classes of `P`'s group (prefix_sibling_rows()), on the first `P` line,
# naming five pairs at most, then a count. Returns slash_rows(); when the
# budget cut candidates, its "stopped" attribute holds slash_stop()'s
# counts.
prefix_sibling_diagnostics <- function(groups, written = NULL,
                                       budget = NULL) {
  groups <- slash_groups(groups)
  rules <- groups$rules
  cand <- prefix_sibling_candidates(rules)
  at <- cand$at
  if (length(at) == 0L) {
    return(slash_rows(character()))
  }
  if (is.null(budget)) {
    budget <- slash_budget(rules, at)
  }
  look <- prefix_sibling_lookup(groups, cand, budget)
  budget <- budget - look$spent
  finished <- seq_along(at) <= look$n & is.na(look$stem)
  ok <- logical(length(at))
  todo <- which(!is.na(look$stem))
  pass <- prefix_sibling_passes(rules, at)
  left_out <- paste(rules$type, rules$value)
  # The reading names a deciding rule by its line: each rule reads as the
  # first line of its type and value, so a repeat of `P` in another group
  # that Google's cut merge joins, which decides as `P` does, confirms it.
  same <- groups
  same$rules$line <- rules$line[match(left_out, left_out)]
  for (k in split(todo, factor(pass[todo], unique(pass[todo])))) {
    # A pass builds its expanders and flags over the file's rules once.
    budget <- budget - nrow(rules)
    if (budget < 0) {
      break
    }
    removed <- same
    removed$rules$empty[left_out %in% left_out[at[k]]] <- TRUE
    value <- rules$value[at[k]]
    read <- witness_pair_readings(removed, look$stem[k], value, value, "long",
                                  written, budget, differ = FALSE,
                                  group = rules$group[at[k]], share = TRUE)
    budget <- budget - read$spent
    done <- seq_along(k) <= read$checked
    finished[k[done]] <- TRUE
    ok[k] <- done & read$ok
  }
  checked <- match(FALSE, finished, nomatch = length(at) + 1L) - 1L
  hit <- which(ok & seq_along(at) <= checked)
  out <- prefix_sibling_rows(groups, look$stem[hit], at[hit])
  attr(out, "stopped") <- slash_stop(rules, at, checked)
  out
}

# The candidates of prefix_sibling_diagnostics(): `at`, the literal rules
# (slash_candidates()) some literal rule of the same type not ending in `/`
# leads, anywhere in the file, in line order; `lit`, every literal rule;
# `key`, each literal's type and value; `chain`, the prefix chain of the
# distinct keys `ukey` (prefix_sibling_chain(), only the `/`-less ones
# pushed); and `top`, each of `at`'s longest such prefix, indexing `ukey`.
prefix_sibling_candidates <- function(rules) {
  lit <- slash_candidates(rules)
  key <- paste0(rules$type[lit], "\t", rules$value[lit])
  ukey <- unique(key)
  stem <- !endsWith(ukey, "/")
  chain <- prefix_sibling_chain(ukey, stem)
  top <- chain$top[match(key, ukey)]
  list(at = lit[!is.na(top)], lit = lit, key = key, ukey = ukey,
       chain = chain, top = top[!is.na(top)], stem = stem)
}

# For distinct strings `key`, the ones in `push` form chains of prefixes:
# `top`, for each string, the longest pushed string that is a proper prefix
# of it (an index of `key`, NA when none), and `depth`, how many pushed
# strings are. One scan in byte order with a stack, each string pushed and
# popped once: the strings a string leads sit right after it in that order,
# so a stack top that does not lead the current string leads no later one.
prefix_sibling_chain <- function(key, push) {
  n <- length(key)
  top <- rep(NA_integer_, n)
  depth <- integer(n)
  stack <- integer(n)
  h <- 0L
  for (i in order(key, method = "radix")) {
    while (h > 0L && !startsWith(key[[i]], key[[stack[[h]]]])) {
      h <- h - 1L
    }
    if (h > 0L) {
      top[[i]] <- stack[[h]]
      depth[[i]] <- h
    }
    if (push[[i]]) {
      h <- h + 1L
      stack[[h]] <- i
    }
  }
  list(top = top, depth = depth)
}

# Each candidate's `P` (prefix_sibling_diagnostics()), as list(stem, n,
# spent): `stem`, an index of `groups$rules` (NA when the candidate has
# none, or was not looked up), and `n`, the leading candidates looked up
# within `budget`, in line order. It walks each (candidate, class) row's
# prefix chain from the longest prefix down and takes the first held by a
# rule in that class, the earliest such line. It costs the (rule, class)
# rows of the rules that lead a candidate, then one unit per row per step
# of the walk, so a long chain of prefixes is paid for as it is walked.
prefix_sibling_lookup <- function(groups, cand, budget) {
  rules <- groups$rules
  at <- cand$at
  out <- list(stem = rep(NA_integer_, length(at)), n = 0L, spent = 0)
  expand <- validation_token_expander(groups, groups$agents$uncut)
  leads <- cand$stem & seq_along(cand$ukey) %in% cand$chain$top
  p_at <- cand$lit[leads[match(cand$key, cand$ukey)]]
  p_cost <- sum(as.numeric(slash_class_counts(expand, rules$group[p_at])))
  # Only the candidates whose classes fit are expanded; each step of the
  # walk below is counted as it is taken.
  n <- sum(p_cost + cumsum(slash_class_counts(expand, rules$group[at])) <=
             budget)
  if (n == 0L) {
    out$spent <- min(p_cost, budget)
    return(out)
  }
  spent <- p_cost
  p_rows <- expand(rules$group[p_at])
  p_key <- paste(p_rows$class, cand$key[match(p_at, cand$lit)][p_rows$owner],
                 sep = "\n")
  p_rule <- p_at[p_rows$owner]
  rows <- expand(rules$group[at[seq_len(n)]])
  found <- rep(NA_integer_, length(rows$owner))
  cur <- cand$top[rows$owner]
  repeat {
    todo <- which(is.na(found) & !is.na(cur) & rows$owner <= n)
    fits <- spent + seq_along(todo) <= budget
    if (!all(fits)) {
      n <- rows$owner[todo[[match(FALSE, fits)]]] - 1L
      todo <- todo[rows$owner[todo] <= n]
    }
    if (length(todo) == 0L) {
      break
    }
    spent <- spent + length(todo)
    k <- match(paste(rows$class[todo], cand$ukey[cur[todo]], sep = "\n"),
               p_key)
    found[todo] <- p_rule[k]
    cur[todo[is.na(k)]] <- cand$chain$top[cur[todo[is.na(k)]]]
  }
  out$n <- n
  out$spent <- spent
  if (n == 0L) {
    return(out)
  }
  keep <- rows$owner <= n
  rows <- list(owner = rows$owner[keep], class = rows$class[keep])
  found <- found[keep]
  taken <- at[seq_len(n)]
  # One `P` for every class, a candidate first of its type and value in
  # each, and the byte after `P` not `/`.
  first <- found[match(seq_len(n), rows$owner)]
  same <- !is.na(found) & !is.na(first[rows$owner]) &
    found == first[rows$owner] & slash_first(rules, taken, rows)
  good <- slash_every(rows$owner, same)
  size <- nchar(rules$value[first[good]], "bytes")
  good <- good[substr(rules$value[taken[good]], size + 1L, size + 1L) != "/"]
  out$stem[good] <- first[good]
  out
}

# Each candidate's pass for prefix_sibling_diagnostics(): its value's depth
# among the candidates' distinct values (how many of them are proper
# prefixes of it, prefix_sibling_chain()) and its type. In one pass no
# value is a prefix of another's (a prefix has a smaller depth), so the
# rules a pass leaves out match none of the other paths it reads.
prefix_sibling_passes <- function(rules, at) {
  value <- rules$value[at]
  distinct <- unique(value)
  depth <- prefix_sibling_chain(distinct, rep(TRUE, length(distinct)))$depth
  paste(depth[match(value, distinct)], rules$type[at])
}

# The rows of prefix_sibling_diagnostics() for the confirmed pairs (`stem`
# the `P` rules, `sibling` the `M` rules, indexes of `groups$rules`): one
# per set of crawler classes of `P`'s group (slash_open_sets()), on its
# first `P` line, listing every sibling of those `P` lines. Where a
# sibling's group names other crawlers than `P`'s, each sibling names its
# group's crawlers, so the row's "for the same crawlers" holds pair by
# pair; otherwise the row ends with `P`'s group's crawlers
# (slash_crawler_note()).
prefix_sibling_rows <- function(groups, stem, sibling) {
  if (length(stem) == 0L) {
    return(slash_rows(character()))
  }
  rules <- groups$rules
  o <- order(rules$line[stem], rules$line[sibling])
  stem <- stem[o]
  sibling <- sibling[o]
  signature <- slash_open_sets(groups, rules$group[stem])
  narrow <- signature != slash_open_sets(groups, rules$group[sibling])
  sets <- split(seq_along(stem), factor(signature, unique(signature)))
  first <- vapply(sets, `[[`, 0L, 1L)
  by_set <- vapply(sets, function(k) any(narrow[k]), NA)
  who <- prefix_sibling_who(groups$agents, rules$group[sibling])
  text <- vapply(sets, function(k) {
    prefix_sibling_message(rules$type[stem[k]], rules$value[stem[k]],
                           rules$line[stem[k]], rules$value[sibling[k]],
                           rules$line[sibling[k]],
                           if (any(narrow[k])) who[k] else NULL)
  }, "", USE.NAMES = FALSE)
  note <- slash_crawler_note(groups$agents, rules$group[stem[first]])
  note[by_set] <- ""
  slash_rows(
    rules$type[stem[first]], rules$line[stem[first]], paste0(text, note)
  )
}

# For each of `group`, the crawlers it names as a list ("'a'", "'a' and
# 'b'"), five at most, then a count; values the whole-value merge reads as
# one count once, as first written (slash_crawler_note()).
prefix_sibling_who <- function(agents, group) {
  named <- agents$global | nzchar(agents$uncut)
  id <- paste(agents$group, ifelse(agents$global, "*", agents$uncut),
              sep = "\n")
  named <- named & !duplicated(id)
  by_group <- split(agents$name[named], agents$group[named])
  wanted <- unique(group)
  who <- vapply(by_group[as.character(wanted)], function(names) {
    names <- unique(names)
    shown <- sprintf("'%s'", ai_training_name(utils::head(names, 5L)))
    joined_and(shown, length(names) - length(shown))
  }, "", USE.NAMES = FALSE)
  who[match(group, wanted)]
}

# A sibling's value as a row shows it: past `cap` bytes, "..." and its last
# `cap - 4` bytes. A sibling starts with its `P`, so its tail is what tells
# the two apart. Values are printable ASCII (slash_candidates()).
prefix_sibling_tail <- function(x, cap = 40L) {
  n <- nchar(x, "bytes")
  long <- n > cap
  x[long] <- paste0("...", substr(x[long], n[long] - cap + 5L, n[long]))
  x
}

# One row's text: each `P` (its type, value and line) and the sibling it
# matches (value and line, and `who`, the sibling's crawlers, when given),
# five pairs at most, then a count. `P` is elided past 40 bytes
# (query_parameter_cap()) and its narrower spellings are that text with
# `$` and with `/` after it; a sibling keeps its tail
# (prefix_sibling_tail()), so no two of them print alike. It says what `P`
# matches and names `P$` together with `P/`, as either one alone stops
# matching paths `P` matches, calling no rule wrong.
prefix_sibling_message <- function(type, value, line, sib_value, sib_line,
                                   who = NULL, cap = 5L) {
  value <- query_parameter_cap(value, 40L)
  where <- if (is.null(who)) {
    sprintf("line %d", sib_line)
  } else {
    sprintf("line %d, for %s", sib_line, who)
  }
  sib <- sprintf("'%s' (%s)", prefix_sibling_tail(sib_value), where)
  shown <- utils::head(seq_along(sib), cap)
  more <- length(sib) - length(shown)
  rule <- paste0(
    " A rule with no trailing '/' or '$' matches every path that starts ",
    "with it (RFC 9309 section 2.2.2)."
  )
  if (length(unique(line)) == 1L) {
    noun <- if (type[[1L]] == "allow") "Allow" else "Disallow"
    listed <- if (length(sib) == 1L) "which is" else "which are"
    return(paste0(
      sprintf("The %s on line %d ('%s') also matches %s, %s listed ",
              noun, line[[1L]], value[[1L]],
              joined_and(sib[shown], more), listed),
      "separately for the same crawlers.", rule,
      sprintf(paste0(" If '%s' was meant as one path segment, '%s$' ",
                     "together with '%s/' is the narrower spelling."),
              value[[1L]], value[[1L]], value[[1L]])
    ))
  }
  pairs <- sprintf("line %d ('%s') matches %s", line[shown], value[shown],
                   sib[shown])
  paste0(
    "Rules for the same crawlers also match paths listed separately: ",
    joined_and(pairs, more), ".", rule,
    " If such a rule was meant as one path segment, its narrower spelling ",
    "is the rule ending in '$' together with the rule ending in '/'."
  )
}

# The opening of a stopped prefix-sibling check's rule_check_stopped row:
# what it looks for, with the file's count and its earliest skipped value.
prefix_sibling_stop_intro <- function(stop) {
  rules <- if (stop$found == 1L) {
    "1 rule whose path starts with a shorter rule of the same type"
  } else {
    sprintf("%d rules whose paths start with a shorter rule of the same type",
            stop$found)
  }
  sprintf(paste0(
    "This file has %s, such as '%s'. For each one, the validator checks ",
    "whether the shorter rule already matches its path for the same crawlers."
  ), rules, query_parameter_cap(stop$value, 40L))
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
  dot_segment <- rule_dot_segment_diagnostic(value)
  if (!is.null(dot_segment)) {
    found[[length(found) + 1L]] <- dot_segment
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

# ROBO-rnjfbhvn: a literal `.` or `..` path segment, which RFC 3986 section
# 5.2.4 and WHATWG URL parsing remove before a request. The scan reads the
# canonical value up to its first `?` and stops at its first `*`, which can
# reach into the query, so a value led by `*` is skipped. A hit is `.` or
# `..` after a `/`, followed by `/`, by `?` or by a `$` that is the value's
# last byte; an unbounded end (`/a/.` matches `/a/.well-known`) and an escaped
# `%2E` are not hits. One grepl, anchored and with no nested quantifiers,
# keeps the cost linear (ROBO-dbvmxcfw). Returns a finding or NULL.
rule_dot_segment_diagnostic <- function(value) {
  # A value not led by `/` is skipped: one led by another byte already gets
  # rule_missing_leading_slash, and one led by `*` can match in the query.
  if (!startsWith(value, "/") ||
        !grepl("^[^?*]*/[.][.]?(/|[?]|[$]$)", value, useBytes = TRUE)) {
    return(NULL)
  }
  list(
    code = "rule_dot_segment",
    message = paste0(
      "Pattern holds a '.' or '..' path segment. Some URL parsers remove ",
      "dot segments before requesting (RFC 3986 section 5.2.4), so this ",
      "rule may never match."
    )
  )
}

# ROBO-rswdwrnp: a `%` that starts no two-hex-digit escape. The test is per
# position, as rfc3986_invalid_classes_v1() (R/url-preprocessing-v1.R) reads
# a URL's stray `%`, so the validator and the URL note agree. `written` is
# the value as written in the file (rule_written_value(), raw bytes), so the
# message quotes it and the placeholder is read on it: the parser upper-cases
# a name led by two hex digits (`%date%` becomes `%DAte%`) and escapes a raw
# non-ASCII byte. The canonical value has the same stray `%` in the same
# classes: MaybeEscapePattern() copies a stray `%`, keeps an escape one, and
# writes each escape it adds with a `%`, never a hex digit. A stray `%` is
# class (b) when it, or it and one hex digit, ends the value or stands before
# a `*`: the matchers then match any escape it begins. Every other stray `%`
# is class (a), a final `$` included. One byte pass and one placeholder regex
# keep the cost linear (ROBO-dbvmxcfw). `nul_cut` is TRUE when a NUL cut the
# value, which only Google's matcher does. Returns a finding or NULL.
rule_invalid_percent_escape_diagnostic <- function(written, nul_cut = FALSE) {
  bytes <- written
  n <- length(bytes)
  hex <- charToRaw("0123456789ABCDEFabcdef")
  is_hex <- function(at) at <= n & bytes[pmin(at, n)] %in% hex
  pct <- which(bytes == as.raw(0x25))
  stray <- pct[!(is_hex(pct + 1L) & is_hex(pct + 2L))]
  if (length(stray) == 0L) {
    return(NULL)
  }
  after <- stray + 1L + is_hex(stray + 1L)
  open <- after > n | bytes[pmin(after, n)] == as.raw(0x2a)
  list(
    code = "rule_invalid_percent_escape",
    message = rule_invalid_percent_escape_message(
      bytes, stray, open, nul_cut
    )
  )
}

# The value of an Allow or Disallow line as written in the file: the raw
# value (rule_raw_value()) with the trailing blanks the parser trims removed
# (StripWhitespaceSlowly() and AsciiIsSpace(), src/robots.cc), so a final
# `%` stays final. Leading blanks are kept: no `%` check reads them, as a
# context starts at its `%` and a placeholder at its own. rule_raw_value()'s
# `buffer_cut` attribute is kept: TRUE when the value ends at the line
# buffer, not when a `#` cut it first (ROBO-jdnluzbb).
rule_written_value <- function(line_bytes, first_line, missing_colon) {
  bytes <- rule_raw_value(line_bytes, first_line, missing_colon)
  keep <- which(!bytes %in% as.raw(c(0x20, 0x09, 0x0a, 0x0b, 0x0c, 0x0d)))
  if (length(keep) == 0L) {
    return(raw(0L))
  }
  out <- bytes[seq_len(keep[[length(keep)]])]
  attr(out, "buffer_cut") <- attr(bytes, "buffer_cut")
  out
}

# ROBO-jdnluzbb: the rule_missing_leading_slash message for a value written
# as a full http(s) URL, naming the path and query to write instead, or NULL
# when the value is no such URL. `written` is rule_written_value()'s bytes;
# `robots_url` is the robots.txt requested, NA for supplied text. `cut` is
# TRUE when a NUL or a glued `#` cut the value: what the author wrote is
# then unknown, so the plain message stays. The path loses its dot
# segments, as an RFC 3986 client's request does; its case, its escapes
# and the query stay as written.
rule_full_url_message <- function(written, robots_url = NA_character_,
                                  cut = FALSE) {
  url <- if (cut) NULL else rule_full_url_bytes(written)
  if (is.null(url)) {
    return(NULL)
  }
  # The origin is read on the scheme and authority alone: rurl's parse cost
  # grows faster than the path's length, and the path is checked above. It
  # is normalized as destination_origin() does, so a root dot is no other
  # origin.
  split <- url_split_rfc3986_v1(url)
  origin <- destination_origin(rawToChar(c(
    split$scheme, charToRaw("//"), split$authority, charToRaw("/")
  )))
  if (is.na(origin)) {
    return(NULL)
  }
  path <- rule_full_url_path(split$path, length(split$query) == 0L)
  pattern <- c(path$path, split$query)
  wide <- any(as.integer(pattern) >= 0x80L)
  # The ASCII bytes a WHATWG URL parser percent-encodes in the path, and in
  # the query (space, `#` and `?` cannot reach here as path bytes).
  path_set <- charToRaw("\"<>`{}")
  query_set <- charToRaw("\"<>")
  encoded <- any(path$path %in% path_set) || any(split$query %in% query_set)
  suggestion <- paste0(rule_full_url_escape(path$path, path_set),
                       rule_full_url_escape(split$query, query_set))
  paste0(
    "Pattern does not start with '/' or '*'; URL paths always start ",
    "with '/', so this rule never matches. The value is a full URL; write ",
    "its path and query instead: '", suggestion, "'.",
    if (path$dots) " Dot segments removed (RFC 3986 section 5.2.4).",
    if (encoded) {
      paste0(" Characters a WHATWG URL parser percent-encodes written as ",
             "upper-case %XX escapes.")
    },
    if (wide) " Non-ASCII bytes written as upper-case %XX escapes.",
    rule_full_url_scope(suggestion),
    rule_full_url_origin(origin, robots_url, split$authority)
  )
}

# The path to suggest, `/` when empty, and whether dot segments were removed
# from it. A final `$` with no query after it is the end anchor, so it is
# set aside while dot segments are removed (`/a/b/..$` gives `/a/$`). A `*`
# matches any bytes, `/` and `.` among them, so dot segments are removed
# only from the segments before the one holding the first `*`; the rest
# stays as written (`/*/../a` stays `/*/../a`). A non-empty path here
# starts with `/`, as it follows an authority.
rule_full_url_path <- function(path, last) {
  anchor <- last && length(path) > 0L && path[[length(path)]] == as.raw(0x24)
  if (anchor) {
    path <- path[-length(path)]
  }
  rest <- raw(0L)
  star <- match(as.raw(0x2a), path)
  if (!is.na(star)) {
    keep <- max(which(path[seq_len(star - 1L)] == as.raw(0x2f)))
    rest <- path[(keep + 1L):length(path)]
    path <- path[seq_len(keep)]
  }
  out <- remove_dot_segments_v1(path)
  dots <- !identical(out, path)
  if (length(out) == 0L) {
    out <- charToRaw("/")
  }
  list(path = c(out, rest, if (anchor) as.raw(0x24)), dots = dots)
}

# The URL in `written` without its leading blanks, or NULL: not led by
# `http://` or `https://` (ASCII, any case), holding a blank or control byte
# (rule_inner_whitespace and rule_control_character say why), or not UTF-8.
# A value led by an invisible character is left to the plain message.
rule_full_url_bytes <- function(written) {
  lead <- which(!written %in% as.raw(c(0x20, 0x09, 0x0a, 0x0b, 0x0c, 0x0d)))
  if (length(lead) == 0L) {
    return(NULL)
  }
  url <- written[lead[[1L]]:length(written)]
  # A fast path only: robots_origin() runs the same scheme guard, but this
  # one skips the byte scans and the rurl parse for every other value.
  head <- rawToChar(url[seq_len(min(8L, length(url)))])
  if (!grepl("^[Hh][Tt][Tt][Pp][Ss]?://", head, useBytes = TRUE)) {
    return(NULL)
  }
  bad <- c(validation_control_bytes, as.raw(c(0x20, 0x09, 0x0b, 0x0c, 0x7f)))
  if (any(url %in% bad) || !validUTF8(rawToChar(url))) {
    return(NULL)
  }
  url
}

# `bytes` as text, each non-ASCII byte as the parser's upper-case `%XX`,
# and each byte of `set` likewise.
rule_full_url_escape <- function(bytes, set = raw(0L)) {
  if (length(bytes) == 0L) {
    return("")
  }
  chars <- rawToChar(bytes, multiple = TRUE)
  wide <- as.integer(bytes) >= 0x80L | bytes %in% set
  chars[wide] <- sprintf("%%%02X", as.integer(bytes[wide]))
  paste(chars, collapse = "")
}

# What the suggested pattern matches: a pattern with no `*` and no final `$`
# matches as a prefix, and `/` matches every URL. The package's Google, Bing
# and Yandex matchers read `/$` as the root path with no query.
rule_full_url_scope <- function(suggestion) {
  if (grepl("*", suggestion, fixed = TRUE) || endsWith(suggestion, "$")) {
    return(NULL)
  }
  paste0(
    " Without wildcards or an end anchor, this pattern matches any path ",
    "and query beginning with it. A trailing '$' requires matching through ",
    "the end of the path and query.",
    if (identical(suggestion, "/")) {
      paste0(" The pattern '/' matches every URL, so it applies to the ",
             "whole site; '/$' limits it to the home page, without a query.")
    }
  )
}

# A sentence when the value's origin (scheme, host, effective port) is not
# the robots.txt's; `origin` is destination_origin() of the value. Both drop
# a trailing root dot from the host. An authority holding a non-ASCII byte
# gets no sentence: robots_origin() does not fold the case of a non-ASCII
# host, and would show it in punycode, not as written.
rule_full_url_origin <- function(origin, robots_url, authority = raw(0L)) {
  served <- destination_origin(robots_url)
  if (is.na(served) || identical(served, origin) ||
        any(as.integer(authority) >= 0x80L)) {
    return(NULL)
  }
  strip <- function(key) sub("/robots[.]txt$", "", key)
  paste0(
    " Without its scheme and host, the rule applies on the origin this ",
    "robots.txt serves, ", strip(served), ", not on ", strip(origin),
    ", the one written in the value."
  )
}

# A `%name%` template placeholder, read on the value as written. A closing
# `%` followed by two hex digits starts an escape (`/%x%41`), so it closes
# no placeholder. A name of exactly two hex digits is an escape followed by
# a stray `%` (`%A9%` in `/caf%C3%A9%`), so it is no placeholder either.
validation_placeholder_pattern <- paste0(
  "%(?![0-9A-Fa-f]{2}%)[A-Za-z_][A-Za-z0-9_]*%(?![0-9A-Fa-f]{2})"
)

# The first `%name%` placeholder in `written` (raw bytes), or NULL. The name
# cannot cross a `%`, so each try ends at the next `%` and the scan stays
# linear.
rule_written_placeholder <- function(written) {
  text <- rawToChar(written)
  hit <- regexpr(validation_placeholder_pattern, text, perl = TRUE,
                 useBytes = TRUE)
  if (hit < 0L) NULL else regmatches(text, hit)
}

# The placeholder sentences. A name led by two hex digits with a lower-case
# one, as in `%date%`, starts an escape the Google and Bing matchers
# upper-case (`%DAte%`); the package's Yandex matcher compares it as
# written. Otherwise all three compare the placeholder as written.
rule_placeholder_sentences <- function(name) {
  lead <- paste0(
    " '", name, "' looks like an unfilled template placeholder: the rule ",
    "matches no filled-in value, nor the placeholder with each '%' written ",
    "'%25'."
  )
  esc <- substr(name, 1L, 3L)
  if (grepl("^%[0-9A-Fa-f]{2}", name) && grepl("[a-f]", substr(esc, 2L, 3L))) {
    upper <- paste0(chartr("abcdef", "ABCDEF", esc), substring(name, 4L))
    return(paste0(
      lead, " Google's and Bing's matchers upper-case its '", esc, "' as an ",
      "escape, so they match '", upper, "' and not the placeholder as ",
      "written; the package's Yandex matcher compares it as written."
    ))
  }
  paste0(
    lead, " The package's Google, Bing and Yandex matchers compare it as ",
    "written, so the rule matches only a URL that carries the raw placeholder."
  )
}

# Each stray `%` with up to two bytes after it, distinct, up to ten, as
# rule_control_character_message() lists, quoted from the value as written
# (`bytes`). Class (a) items come first, each class in value order, so the
# `%` that sets the message is never hidden in "and N more". A byte below
# 0x20, DEL or a non-ASCII byte is written \xNN, so the message stays ASCII,
# and so is a `'`, which would end the quoted item.
# `open` is TRUE for each stray `%` of class (b). A value holding a `%name%`
# placeholder gets the class (a) lead and the placeholder sentences, whatever
# its class. `nul_cut` is TRUE when a NUL cut the value (rule_cut_by_nul).
rule_invalid_percent_escape_message <- function(bytes, stray, open, nul_cut) {
  n <- length(bytes)
  stray <- stray[order(open)]
  open <- all(open)
  at <- function(k) {
    ifelse(stray + k <= n, as.integer(bytes[pmin(stray + k, n)]), 256L)
  }
  key <- at(1L) * 257L + at(2L)
  first <- stray[!duplicated(key)]
  cap <- 10L
  k <- length(first)
  items <- vapply(first[seq_len(min(k, cap))], function(p) {
    ctx <- as.integer(bytes[p:min(p + 2L, n)])
    shown <- ifelse(ctx < 0x20L | ctx >= 0x7fL | ctx == 0x27L,
                    sprintf("\\x%02X", ctx),
                    rawToChar(as.raw(ctx), multiple = TRUE))
    paste0("'", paste(shown, collapse = ""), "'")
  }, "")
  listed <- toString(items)
  if (k > cap) {
    listed <- sprintf("%s, and %d more", listed, k - cap)
  }
  placeholder <- rule_written_placeholder(bytes)
  if (open && is.null(placeholder)) {
    # The matchers compare a cut-short escape's digit case by case.
    # A final `%` reads itself here, which is no hex digit.
    lower <- any(bytes[pmin(stray + 1L, n)] %in% charToRaw("abcdef"))
    return(paste0(
      "Pattern holds ", listed, ": '%' cut short by a '*' or by the ",
      "pattern's end.", rule_percent_open_sentence(nul_cut),
      if (lower) {
        paste0(" A lower-case hex digit there matches only lower-case ",
               "escapes, which RFC 3986 section 2.1 advises against.")
      },
      " This may be meant; to match only a literal '%', write '%25'."
    ))
  }
  lead <- paste0(
    "Pattern holds ", listed, ": '%' that starts no two-hex-digit escape."
  )
  nul <- if (nul_cut) rule_percent_nul_sentence else ""
  if (!is.null(placeholder)) {
    return(paste0(
      lead, rule_placeholder_sentences(placeholder), nul,
      " Write '%25' for a literal '%'."
    ))
  }
  paste0(
    lead, " The package's Google, Bing and Yandex matchers compare it as a ",
    "literal '%', so this rule matches only URLs that carry the raw '%', ",
    "which correctly encoded URLs never do.", nul,
    " Write '%25' for a literal '%'."
  )
}

# The engines split at a NUL that cuts the value (rule_cut_by_nul,
# ROBO-xuusttbp): Google ends the rule there, while Bing and Yandex read the
# NUL as a byte of the rule.
rule_percent_nul_sentence <- paste0(
  " Google's matcher ends the rule at the NUL; the package's Bing and ",
  "Yandex matchers read the NUL as a byte of the rule."
)

# What the matchers do with a cut-short escape. A NUL that cuts the value
# ends the rule only on Google's reading, so then only Google is said to
# match any escape there.
rule_percent_open_sentence <- function(nul_cut) {
  if (nul_cut) {
    return(paste0(
      " Google's matcher ends the rule at the NUL and compares the rest as ",
      "written, so it matches any URL with a percent-escape that begins ",
      "there, as a final '%' matches '%20' and '%25' alike; the package's ",
      "Bing and Yandex matchers read the NUL as a byte of the rule."
    ))
  }
  paste0(
    " The package's Google, Bing and Yandex matchers compare the pattern as ",
    "written, so the rule matches any URL with a percent-escape that begins ",
    "there, as a final '%' matches '%20' and '%25' alike."
  )
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
  # A compressed body (ROBO-rozvglkd) keeps the rows about the header itself,
  # worded so they claim no read of its bytes, and draws no charset conflict,
  # which reads the bytes as text.
  header_rows <- content_type_diagnostics(
    source$source_id, source$content_type, body,
    validated$document$encoding_signature,
    compressed = "compressed_body" %in% validated$diagnostics$code
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
