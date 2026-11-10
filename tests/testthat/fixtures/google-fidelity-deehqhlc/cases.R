# Synthesized fixtures for the Google fidelity audit (ROBO-deehqhlc).
#
# Sourced by tests/testthat/test-google-fidelity-deehqhlc.R and by the dev-only
# differential, dev/google-fidelity/differential.R. Every body, token and URL
# here is synthesized; hosts are example.com.
#
# Each case carries the answer of the pristine upstream google/robotstxt engine
# at 22b355ff855419e6a3ff8ff09c0ad7fdb17116f9
# (`RobotsMatcher::OneAgentAllowedByRobots()` on the raw body bytes, then
# `matching_line()`): `ref_allowed` and `ref_line`, 0 when no rule matched.
# The differential re-derives both from the reference binary and fails on any
# drift, so the recorded answers stay the reference's, not robotstxtr's, and on
# any difference gf_expected_difference() below does not list.
#
# `paths` names the robotstxtr entry points a case can reach: a body with a
# NUL byte cannot be an R string, so it reaches only the fetched paths.
#
# Source this file into an environment that can see the package namespace and
# tests/testthat/helper-fake-ssrfr.R (the test file's own environment, or the
# differential's), never into globalenv.

gf_text_paths <- c("v1_text", "text")
gf_url_paths <- c("url", "v1_url")
gf_all_paths <- c(gf_text_paths, gf_url_paths)

gf_b <- function(...) charToRaw(paste0(...))

# "User-agent: *\n" and one comment line, sized so that `tail` starts at byte
# `at + 1`; then `tail`, then, when `size` is given, a run of "#" with no line
# break up to `size` bytes.
gf_edge_body <- function(tail, at, size = NULL) {
  agent <- charToRaw("User-agent: *\n")
  head <- c(agent, rep(charToRaw("#"), at - length(agent) - 1L), gf_b("\n"))
  body <- c(head, charToRaw(tail))
  if (!is.null(size)) {
    body <- c(body, rep(charToRaw("#"), size - length(body)))
  }
  body
}

gf_case <- function(id, family, body, token, url, ref_allowed, ref_line,
                    paths = gf_all_paths) {
  list(
    id = id, family = family, body = body, token = token, url = url,
    ref_allowed = as.logical(ref_allowed), ref_line = as.integer(ref_line),
    paths = paths
  )
}

gf_target_body <- c(
  gf_b("User-agent: *\n"),
  gf_b("Disallow: /search?q=\n"),
  gf_b("Disallow: /frag\n"),
  gf_b("Disallow: /a%2Fb\n"),
  gf_b("Disallow: /a%2fc\n"),
  gf_b("Disallow: /caf"), as.raw(c(0xc3, 0xa9)), gf_b("\n"),
  gf_b("Disallow: /na%C3%AFve\n"),
  gf_b("Disallow: /p;jsessionid\n"),
  gf_b("Disallow: /x%3Ay\n"),
  gf_b("Disallow: /$\n")
)

gf_pattern_body <- gf_b(
  "User-agent: *\n",
  "Disallow: /*.pdf$\n",
  "Disallow: /tmp*/cache\n",
  "Allow: /tmp/public*\n",
  "Disallow: /end$\n",
  "Disallow: /a*b*c\n",
  "Allow: /**/ok$\n",
  "Disallow: /page\n",
  "Allow: /page\n",
  "Disallow: /lit$x\n"
)

gf_agent_body <- gf_b(
  "User-agent: Googlebot\n",
  "Disallow: /g\n",
  "\n",
  "User-agent: *\n",
  "Disallow: /star\n",
  "\n",
  "User-agent: googlebot-news\n",
  "Disallow: /news\n"
)

gf_split_body <- gf_b(
  "User-agent: FooBot\n",
  "Sitemap: https://example.com/sitemap.xml\n",
  "Disallow: /a\n",
  "# a comment between rules\n",
  "Crawl-delay: 5\n",
  "\n",
  "Disallow: /b\n",
  "User-agent: BarBot\n",
  "Disallow: /c\n",
  "User-agent: FooBot\n",
  "Disallow: /d\n"
)

gf_long_rule <- strrep("a", 20000L)
gf_long_body <- gf_b(
  "User-agent: *\nDisallow: /", gf_long_rule, "\nDisallow: /b\n"
)

gf_cases <- function() {
  private <- gf_b("User-agent: *\nDisallow: /private\n")
  list(
    # --- Class 1: an Allow/Disallow with an empty value -------------------
    gf_case("ev-disallow", "empty_value",
            gf_b("User-agent: FooBot\nDisallow:\n"),
            "FooBot", "https://example.com/x", 1, 2),
    gf_case("ev-allow", "empty_value",
            gf_b("User-agent: FooBot\nAllow:\n"),
            "FooBot", "https://example.com/x", 1, 2),
    gf_case("ev-both", "empty_value",
            gf_b("User-agent: FooBot\nDisallow:\nAllow:\n"),
            "FooBot", "https://example.com/x", 1, 3),
    gf_case("ev-comment", "empty_value",
            gf_b("User-agent: *\nDisallow: # nothing after the colon\n"),
            "FooBot", "https://example.com/x", 1, 2),
    gf_case("ev-beside-rule-miss", "empty_value",
            gf_b("User-agent: FooBot\nDisallow:\nDisallow: /private\n"),
            "FooBot", "https://example.com/public", 1, 2),
    gf_case("ev-beside-rule-hit", "empty_value",
            gf_b("User-agent: FooBot\nDisallow:\nDisallow: /private\n"),
            "FooBot", "https://example.com/private", 0, 3),

    # --- The 512,000-byte window and the complete-line cut ----------------
    # A rule wholly after the window, inside the URL path's 524,288 cut.
    gf_case("win-after", "window",
            gf_edge_body("Disallow: /after\n", 520000L),
            "FooBot", "https://example.com/after", 0, 3),
    # A rule after the URL path's default 524,288-byte cut too.
    gf_case("win-after-ceiling", "window",
            gf_edge_body("Disallow: /after\n", 530000L),
            "FooBot", "https://example.com/after", 0, 3),
    # A rule line straddling byte 512,000.
    gf_case("win-straddle", "window",
            gf_edge_body("Disallow: /private-drafts/\n", 512000L - 11L),
            "FooBot", "https://example.com/private-drafts/x", 0, 3),
    # Its first 11 bytes, "Disallow: /", are not a rule of their own.
    gf_case("win-straddle-prefix", "window",
            gf_edge_body("Disallow: /private-drafts/\n", 512000L - 11L),
            "FooBot", "https://example.com/public", 1, 0),
    # The rule ends at byte 512,000; its LF is byte 512,001.
    gf_case("win-edge-lf-outside", "window",
            gf_edge_body("Disallow: /private\n", 512000L - 18L, 600000L),
            "FooBot", "https://example.com/private", 0, 3),
    # The rule's LF is byte 512,000.
    gf_case("win-edge-lf-inside", "window",
            gf_edge_body("Disallow: /private\n", 512000L - 19L, 600000L),
            "FooBot", "https://example.com/private", 0, 3),

    # --- URL target extraction --------------------------------------------
    gf_case("url-query", "target", gf_target_body,
            "FooBot", "https://example.com/search?q=robots", 0, 2),
    gf_case("url-query-absent", "target", gf_target_body,
            "FooBot", "https://example.com/search", 1, 0),
    gf_case("url-fragment", "target", gf_target_body,
            "FooBot", "https://example.com/frag#section", 0, 3),
    gf_case("url-fragment-before-path", "target", gf_target_body,
            "FooBot", "https://example.com#/frag", 0, 10),
    gf_case("url-empty-path-query", "target", gf_target_body,
            "FooBot", "https://example.com?x=1", 1, 0),
    gf_case("url-bare-origin", "target", gf_target_body,
            "FooBot", "https://example.com", 0, 10),
    gf_case("url-root", "target", gf_target_body,
            "FooBot", "https://example.com/", 0, 10),
    gf_case("url-port-origin", "target", gf_target_body,
            "FooBot", "https://example.com:8443", 0, 10),
    gf_case("url-pct2f-upper", "target", gf_target_body,
            "FooBot", "https://example.com/a%2Fb", 0, 4),
    gf_case("url-pct2f-lower", "target", gf_target_body,
            "FooBot", "https://example.com/a%2fb", 1, 0),
    gf_case("url-pct2f-slash", "target", gf_target_body,
            "FooBot", "https://example.com/a/b", 1, 0),
    gf_case("url-lower-rule-upper-url", "target", gf_target_body,
            "FooBot", "https://example.com/a%2Fc", 0, 5),
    gf_case("url-lower-rule-lower-url", "target", gf_target_body,
            "FooBot", "https://example.com/a%2fc", 1, 0),
    gf_case("url-nonascii-raw", "target", gf_target_body,
            "FooBot", "https://example.com/caf\u00e9", 1, 0),
    gf_case("url-nonascii-escaped-upper", "target", gf_target_body,
            "FooBot", "https://example.com/caf%C3%A9", 0, 6),
    gf_case("url-nonascii-escaped-lower", "target", gf_target_body,
            "FooBot", "https://example.com/caf%c3%a9", 1, 0),
    gf_case("url-escaped-rule-raw-url", "target", gf_target_body,
            "FooBot", "https://example.com/na\u00efve", 1, 0),
    gf_case("url-escaped-rule-escaped-url", "target", gf_target_body,
            "FooBot", "https://example.com/na%C3%AFve", 0, 7),
    gf_case("url-params", "target", gf_target_body,
            "FooBot", "https://example.com/p;jsessionid=1", 0, 8),
    gf_case("url-params-absent", "target", gf_target_body,
            "FooBot", "https://example.com/p", 1, 0),
    gf_case("url-escaped-colon-raw-url", "target", gf_target_body,
            "FooBot", "https://example.com/x:y", 1, 0),

    # --- `$` and `*` --------------------------------------------------------
    gf_case("pat-star-dollar", "pattern", gf_pattern_body,
            "FooBot", "https://example.com/doc.pdf", 0, 2),
    gf_case("pat-star-dollar-query", "pattern", gf_pattern_body,
            "FooBot", "https://example.com/doc.pdf?v=2", 1, 0),
    gf_case("pat-mid-star", "pattern", gf_pattern_body,
            "FooBot", "https://example.com/tmp1/cache", 0, 3),
    gf_case("pat-allow-star", "pattern", gf_pattern_body,
            "FooBot", "https://example.com/tmp/public/cache", 1, 4),
    gf_case("pat-dollar", "pattern", gf_pattern_body,
            "FooBot", "https://example.com/end", 0, 5),
    gf_case("pat-dollar-longer", "pattern", gf_pattern_body,
            "FooBot", "https://example.com/endx", 1, 0),
    gf_case("pat-two-stars", "pattern", gf_pattern_body,
            "FooBot", "https://example.com/a1b2c3", 0, 6),
    gf_case("pat-double-star-dollar", "pattern", gf_pattern_body,
            "FooBot", "https://example.com/x/ok", 1, 7),
    gf_case("pat-tie-allow-wins", "pattern", gf_pattern_body,
            "FooBot", "https://example.com/page", 1, 9),
    gf_case("pat-inner-dollar-literal", "pattern", gf_pattern_body,
            "FooBot", "https://example.com/lit$x", 0, 10),

    # --- User-agent edge cases --------------------------------------------
    gf_case("ua-exact", "agent", gf_agent_body,
            "Googlebot", "https://example.com/g", 0, 2),
    gf_case("ua-lower", "agent", gf_agent_body,
            "googlebot", "https://example.com/g", 0, 2),
    gf_case("ua-upper", "agent", gf_agent_body,
            "GOOGLEBOT", "https://example.com/g", 0, 2),
    gf_case("ua-image-not-parent", "agent", gf_agent_body,
            "Googlebot-Image", "https://example.com/g", 1, 0),
    gf_case("ua-image-star", "agent", gf_agent_body,
            "Googlebot-Image", "https://example.com/star", 0, 5),
    gf_case("ua-news-own", "agent", gf_agent_body,
            "Googlebot-News", "https://example.com/news", 0, 8),
    gf_case("ua-news-not-parent", "agent", gf_agent_body,
            "Googlebot-News", "https://example.com/g", 1, 0),
    gf_case("ua-caller-version", "agent", gf_agent_body,
            "Googlebot/2.1", "https://example.com/star", 0, 5),
    gf_case("ua-caller-version-own", "agent", gf_agent_body,
            "Googlebot/2.1", "https://example.com/g", 1, 0),
    gf_case("ua-unknown", "agent", gf_agent_body,
            "ExampleBot", "https://example.com/star", 0, 5),
    gf_case("ua-caller-space", "agent", gf_agent_body,
            "Googlebot Image", "https://example.com/star", 0, 5),
    gf_case("ua-file-version", "agent",
            gf_b("User-agent: Googlebot/2.1\nDisallow: /v\n"),
            "Googlebot", "https://example.com/v", 0, 2),
    gf_case("ua-split-sitemap", "agent", gf_split_body,
            "FooBot", "https://example.com/a", 0, 3),
    gf_case("ua-split-blank", "agent", gf_split_body,
            "FooBot", "https://example.com/b", 0, 7),
    gf_case("ua-repeat-merged", "agent", gf_split_body,
            "FooBot", "https://example.com/d", 0, 11),
    gf_case("ua-other-group", "agent", gf_split_body,
            "FooBot", "https://example.com/c", 1, 0),
    gf_case("ua-shared-group", "agent",
            gf_b("User-agent: FooBot\nUser-agent: BarBot\nDisallow: /s\n"),
            "BarBot", "https://example.com/s", 0, 3),
    gf_case("ua-rule-before-agent", "agent",
            gf_b("Disallow: /early\nUser-agent: *\nDisallow: /late\n"),
            "FooBot", "https://example.com/early", 1, 0),

    # --- Line endings and the BOM -----------------------------------------
    gf_case("eol-crlf", "eol",
            gf_b("User-agent: *\r\nDisallow: /a\r\nAllow: /a/b\r\n"),
            "FooBot", "https://example.com/a/b", 1, 3),
    gf_case("eol-cr", "eol",
            gf_b("User-agent: *\rDisallow: /a\rAllow: /a/b\r"),
            "FooBot", "https://example.com/a/b", 1, 3),
    gf_case("eol-cr-disallow", "eol",
            gf_b("User-agent: *\rDisallow: /a\rAllow: /a/b\r"),
            "FooBot", "https://example.com/a/c", 0, 2),
    gf_case("eol-mixed", "eol",
            gf_b("User-agent: *\r\n\rDisallow: /a\n\r\nDisallow: /b"),
            "FooBot", "https://example.com/b", 0, 5),
    gf_case("eol-bom", "eol",
            c(as.raw(c(0xef, 0xbb, 0xbf)),
              gf_b("User-agent: *\nDisallow: /a\n")),
            "FooBot", "https://example.com/a", 0, 2),
    gf_case("eol-bom-crlf", "eol",
            c(as.raw(c(0xef, 0xbb, 0xbf)),
              gf_b("User-agent: *\r\nDisallow: /a\r\n")),
            "FooBot", "https://example.com/a", 0, 2),

    # --- Invalid UTF-8 in a rule ------------------------------------------
    gf_case("utf8-latin1-rule", "utf8",
            c(gf_b("User-agent: *\nDisallow: /caf"), as.raw(0xe9),
              gf_b("\nDisallow: /b"), as.raw(c(0xff, 0xfe)), gf_b("\n")),
            "FooBot", "https://example.com/caf%E9", 0, 2),
    gf_case("utf8-bad-bytes-rule", "utf8",
            c(gf_b("User-agent: *\nDisallow: /caf"), as.raw(0xe9),
              gf_b("\nDisallow: /b"), as.raw(c(0xff, 0xfe)), gf_b("\n")),
            "FooBot", "https://example.com/b%FF%FE", 0, 3),
    gf_case("utf8-bad-byte-agent", "utf8",
            c(gf_b("User-agent: Foo"), as.raw(0xff),
              gf_b("Bot\nDisallow: /x\n")),
            "Foo", "https://example.com/x", 0, 2),

    # --- Long lines (upstream keeps 16,663 bytes of a line) ---------------
    gf_case("long-rule-prefix", "long", gf_long_body,
            "FooBot", paste0("https://example.com/", gf_long_rule), 0, 2),
    # Shorter than the rule, longer than the part upstream keeps.
    gf_case("long-rule-cut-url", "long", gf_long_body,
            "FooBot", paste0("https://example.com/", strrep("a", 17000L)),
            0, 2),
    gf_case("long-rule-short-url", "long", gf_long_body,
            "FooBot", "https://example.com/aa", 1, 0),
    gf_case("long-rule-next-line", "long", gf_long_body,
            "FooBot", "https://example.com/b", 0, 3),
    gf_case("long-comment-then-rule", "long",
            gf_b("User-agent: *\n#", strrep("c", 40000L), "\nDisallow: /b\n"),
            "FooBot", "https://example.com/b", 0, 3),

    # --- Directive typos Google accepts -----------------------------------
    gf_case("typo-dissallow", "typo",
            gf_b("useragent: FooBot\nDissallow: /t1\nDisalow: /t2\n",
                 "Disallaw: /t3\nDiasllow: /t4\nDissalow: /t5\n",
                 "Allowance: /t1/ok\n"),
            "FooBot", "https://example.com/t1", 0, 2),
    gf_case("typo-allow-prefix", "typo",
            gf_b("useragent: FooBot\nDissallow: /t1\nDisalow: /t2\n",
                 "Disallaw: /t3\nDiasllow: /t4\nDissalow: /t5\n",
                 "Allowance: /t1/ok\n"),
            "FooBot", "https://example.com/t1/ok", 1, 7),
    gf_case("typo-diasllow", "typo",
            gf_b("useragent: FooBot\nDissallow: /t1\nDisalow: /t2\n",
                 "Disallaw: /t3\nDiasllow: /t4\nDissalow: /t5\n",
                 "Allowance: /t1/ok\n"),
            "FooBot", "https://example.com/t4", 0, 5),
    gf_case("typo-user-agent-space", "typo",
            gf_b("user agent: FooBot\nDisallow: /x\n"),
            "FooBot", "https://example.com/x", 0, 2),
    gf_case("typo-no-colon", "typo",
            gf_b("User-agent FooBot\nDisallow /x\n"),
            "FooBot", "https://example.com/x", 0, 2),
    gf_case("typo-spacing", "typo",
            gf_b("  User-Agent :  FooBot  \n\tdisallow\t:\t/x  \n"),
            "FooBot", "https://example.com/x", 0, 2),

    # --- Input shapes the entry points screen -----------------------------
    gf_case("in-empty-url", "input", private, "FooBot", "", 1, 0),
    gf_case("in-empty-token", "input", private,
            "", "https://example.com/private", 0, 2),
    gf_case("in-schemeless-url", "input", private,
            "FooBot", "example.com/private", 0, 2),
    gf_case("in-ftp-url", "input", private,
            "FooBot", "ftp://example.com/private", 0, 2),

    # --- A NUL byte (only a fetched body can carry one) -------------------
    # The reference reads each line as a NUL-terminated C string, so the
    # rule is "/a"; robotstxtr removes the NUL, so the rule is "/ab". Both
    # disallow /ab on line 2; only the reference disallows /a and /ac.
    gf_case("nul-in-rule", "nul",
            c(gf_b("User-agent: *\nDisallow: /a"), as.raw(0), gf_b("b\n")),
            "FooBot", "https://example.com/ab", 0, 2, gf_url_paths),
    gf_case("nul-in-rule-prefix", "nul",
            c(gf_b("User-agent: *\nDisallow: /a"), as.raw(0), gf_b("b\n")),
            "FooBot", "https://example.com/a", 0, 2, gf_url_paths),
    gf_case("nul-in-rule-other", "nul",
            c(gf_b("User-agent: *\nDisallow: /a"), as.raw(0), gf_b("b\n")),
            "FooBot", "https://example.com/ac", 0, 2, gf_url_paths),
    # The same C string is empty: the reference reads an empty line.
    gf_case("nul-before-key", "nul",
            c(gf_b("User-agent: *\n"), as.raw(0), gf_b("Disallow: /x\n")),
            "FooBot", "https://example.com/x", 1, 0, gf_url_paths)
  )
}

# --- The expected differences -------------------------------------------------

gf_v1_path <- function(path) startsWith(path, "v1_")

# What robotstxtr returns where it differs from the reference, by case and
# path: list(class, allowed, line, reason), or NULL where it must agree. The
# classes are design/engine-profiles.md §5b's. The pinned test and the
# differential both read this table.
gf_expected_difference <- function(id, path) {
  empty_value <- c(
    "ev-disallow", "ev-allow", "ev-both", "ev-comment", "ev-beside-rule-miss"
  )
  invalid_reason <- if (gf_v1_path(path)) "input_invalid" else "input_unknown"
  if (id %in% empty_value) {
    return(list(class = 1L, allowed = TRUE, line = NA_integer_,
                reason = "default_allow"))
  }
  if (id %in% c("win-after", "win-after-ceiling", "win-straddle") &&
        gf_v1_path(path)) {
    return(list(class = 2L, allowed = TRUE, line = NA_integer_,
                reason = "default_allow"))
  }
  if (identical(id, "win-after-ceiling") && identical(path, "url")) {
    return(list(class = 3L, allowed = TRUE, line = NA_integer_,
                reason = "default_allow"))
  }
  if (id %in% c("in-empty-url", "in-empty-token")) {
    return(list(class = 4L, allowed = NA, line = NA_integer_,
                reason = invalid_reason))
  }
  if (id %in% c("in-schemeless-url", "in-ftp-url") &&
        path %in% c("url", "v1_url:google")) {
    return(list(class = 4L, allowed = NA, line = NA_integer_,
                reason = invalid_reason))
  }
  if (identical(id, "nul-before-key")) {
    return(list(class = 5L, allowed = FALSE, line = 2L,
                reason = "rule_disallow"))
  }
  if (id %in% c("nul-in-rule-prefix", "nul-in-rule-other")) {
    return(list(class = 5L, allowed = TRUE, line = NA_integer_,
                reason = "default_allow"))
  }
  NULL
}

# --- robotstxtr's side --------------------------------------------------------

# The v1 rulesets whose google backend reaches the matcher for a supplied
# body: every ruleset reads a supplied body as `use_rules`, except that
# yandex resolves a body over its limit `allow_all` with no matcher
# (design/engine-profiles.md §7), so those rows are left out.
gf_v1_rulesets <- c("google", "rfc9309", "assumed_rfc9309", "bing", "yandex")

# The yandex limit, 500,000 bytes: the package's own policy_limit_v1()
# (R/engine-contract-v1.R), published as `policy_body_limit_bytes`. The
# allow_all rule in resolve_policy_v1() spells the same value as a literal
# (`evidence$stored_bytes > 500000L`).
gf_yandex_limit <- policy_limit_v1("yandex")

gf_body_string <- function(body) {
  out <- rawToChar(body)
  Encoding(out) <- "bytes"
  out
}

gf_row <- function(path, allowed, line, reason) {
  data.frame(
    path = path, allowed = as.logical(allowed), line = as.integer(line),
    reason = as.character(reason), stringsAsFactors = FALSE
  )
}

gf_from_v1 <- function(path, r) {
  allowed <- c(allow = TRUE, disallow = FALSE)[r$url_decision]
  gf_row(path, unname(allowed), r$matched_line, r$reason)
}

gf_from_legacy <- function(path, r) {
  gf_row(path, r$allowed, r$matched_line, r$decision_source)
}

# Serve `body` at the ssrfr boundary for the duration of `code`.
gf_with_body <- function(body, code) {
  local_fake_ssrfr(function(req) fake_response(200L, body = body))
  force(code)
}

# One row per robotstxtr path the case reaches: `allowed` (NA when no
# decision), `line` (NA when no rule is reported) and the reason.
gf_run_case <- function(case) {
  rows <- list()
  body <- case$body
  if ("v1_text" %in% case$paths) {
    rulesets <- gf_v1_rulesets
    if (length(body) > gf_yandex_limit) {
      rulesets <- setdiff(rulesets, "yandex")
    }
    x <- robots_evaluate_text_v1(
      gf_body_string(body), rep(case$url, length(rulesets)), case$token,
      rulesets, "google"
    )
    for (k in seq_along(rulesets)) {
      rows[[length(rows) + 1L]] <- gf_from_v1(
        paste0("v1_text:", rulesets[[k]]), x$results[k, , drop = FALSE]
      )
    }
  }
  if ("text" %in% case$paths) {
    x <- allowed_by_robots_text(gf_body_string(body), case$url, case$token)
    rows[[length(rows) + 1L]] <- gf_from_legacy("text", x$results)
  }
  if ("url" %in% case$paths) {
    x <- gf_with_body(body, allowed_by_robots_url(case$url, case$token))
    rows[[length(rows) + 1L]] <- gf_from_legacy("url", x$results)
  }
  if ("v1_url" %in% case$paths) {
    x <- gf_with_body(
      body, robots_evaluate_url_v1(case$url, case$token, "google", "google")
    )
    rows[[length(rows) + 1L]] <- gf_from_v1("v1_url:google", x$results)
  }
  out <- do.call(rbind, rows)
  out$id <- case$id
  out
}
