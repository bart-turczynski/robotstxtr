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
# drift, so the recorded answers stay the reference's, not robotstxtr's. It
# also fails where gf_check_rows() below finds a row that differs outside the
# gf_expected table, differs from the answer the table lists, or agrees with
# the reference where the table lists a difference.
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
    # rule is "/a", which disallows /a, /ab and /ac on line 2; robotstxtr's
    # Google paths cut each line at its first NUL too (ROBO-pvqrfvol).
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

# The entry point of a row's path: "v1_text:bing" -> "v1_text".
gf_entry_point <- function(path) sub(":.*$", "", path)

gf_expect <- function(class, ids, paths, allowed, line, reason,
                      v1_reason = reason) {
  list(
    class = class, ids = ids, paths = paths, allowed = allowed,
    line = as.integer(line), reason = reason, v1_reason = v1_reason
  )
}

# What robotstxtr returns where it differs from the reference: one entry per
# set of cases, with the entry points (`paths`) where they differ and the
# answer there. `reason` is the legacy paths' `decision_source`, `v1_reason`
# the v1 paths' `reason`. The classes are design/engine-profiles.md §5b's.
# The pinned test, gf_check_rows() and the differential all read this table;
# it is the only list of the differing case ids.
gf_expected <- list(
  gf_expect(1L, c("ev-disallow", "ev-allow", "ev-both", "ev-comment",
                  "ev-beside-rule-miss"),
            gf_all_paths, TRUE, NA, "default_allow"),
  gf_expect(2L, c("win-after", "win-after-ceiling", "win-straddle"),
            c("v1_text", "v1_url"), TRUE, NA, "default_allow"),
  gf_expect(3L, "win-after-ceiling", "url", TRUE, NA, "default_allow"),
  gf_expect(4L, c("in-empty-url", "in-empty-token"), gf_all_paths,
            NA, NA, "input_unknown", "input_invalid"),
  gf_expect(4L, c("in-schemeless-url", "in-ftp-url"), gf_url_paths,
            NA, NA, "input_unknown", "input_invalid")
)

# Every case id gf_expected lists.
gf_expected_ids <- function() {
  unique(unlist(lapply(gf_expected, `[[`, "ids")))
}

# robotstxtr's answer where it differs from the reference, by case and path:
# list(class, allowed, line, reason), or NULL where it must agree.
gf_expected_difference <- function(id, path) {
  for (e in gf_expected) {
    if (id %in% e$ids && gf_entry_point(path) %in% e$paths) {
      reason <- if (gf_v1_path(path)) e$v1_reason else e$reason
      return(list(class = e$class, allowed = e$allowed, line = e$line,
                  reason = reason))
    }
  }
  NULL
}

# Checks robotstxtr's rows (gf_run_case()) against the reference's answers,
# `ref_allowed` (logical) and `ref_line` (integer, 0 for no line), one of each
# per row. A row differs from the reference when its decision does, or its
# line does (NA counts as 0). Returns `rows`, every row with the columns
# `decision_differs`, `line_differs` (the decision agrees, the line does not)
# and `class` (NA where gf_expected lists nothing), and three subsets of it:
# - `unexpected`: differs, and gf_expected lists nothing for it;
# - `mismatched`: differs, is listed, but its allowed, line or reason is not
#   the listed one;
# - `stale`: is listed, but agrees with the reference.
# All three are empty when robotstxtr matches the reference and the table.
gf_check_rows <- function(rows, ref_allowed, ref_line) {
  n <- nrow(rows)
  stopifnot(length(ref_allowed) == n, length(ref_line) == n)
  our_line <- ifelse(is.na(rows$line), 0L, rows$line)
  rows$decision_differs <- is.na(rows$allowed) | rows$allowed != ref_allowed
  rows$line_differs <- !rows$decision_differs & our_line != ref_line
  differs <- rows$decision_differs | rows$line_differs
  wants <- lapply(seq_len(n), function(k) {
    gf_expected_difference(rows$id[[k]], rows$path[[k]])
  })
  listed <- !vapply(wants, is.null, logical(1L))
  matches_want <- vapply(seq_len(n), function(k) {
    want <- wants[[k]]
    !is.null(want) &&
      identical(rows$allowed[[k]], want$allowed) &&
      identical(rows$line[[k]], want$line) &&
      identical(rows$reason[[k]], want$reason)
  }, logical(1L))
  rows$class <- vapply(wants, function(want) {
    if (is.null(want)) NA_integer_ else want$class
  }, integer(1L))
  list(
    rows = rows,
    unexpected = rows[differs & !listed, , drop = FALSE],
    mismatched = rows[differs & listed & !matches_want, , drop = FALSE],
    stale = rows[!differs & listed, , drop = FALSE]
  )
}

# --- robotstxtr's side --------------------------------------------------------

# The v1 rulesets, each with the google backend. Every ruleset reads a
# supplied body as `use_rules` (`supplied_body_use_rules`), at any size:
# resolve_policy_v1() (R/engine-contract-v1.R) returns for a supplied source
# before its yandex branch, which resolves a fetched 2xx over 500,000 bytes
# `allow_all` (design/engine-profiles.md §7). So every row reaches the
# matcher, the over-limit yandex rows included. With the google backend each
# ruleset's row therefore equals the google row by construction, so the
# `window` family's 0.5 to 0.6 MB bodies run under `google` only
# (ROBO-oxjmtaon). That a supplied body over 500,000 bytes keeps use_rules
# under yandex is pinned in test-size-status-etlkvljs.R and
# test-yandex-edge-matrices-qfytjxev.R.
gf_v1_rulesets <- c("google", "rfc9309", "assumed_rfc9309", "bing", "yandex")

gf_case_rulesets <- function(case) {
  if (identical(case$family, "window")) "google" else gf_v1_rulesets
}

gf_body_string <- function(body) {
  out <- rawToChar(body)
  Encoding(out) <- "bytes"
  out
}

# `matcher_body_truncated` and `matcher_input_bytes` are the v1 rows' (NA on
# the legacy paths), `body_truncated` the legacy paths' `robots` field (NA on
# the v1 paths).
gf_row <- function(path, allowed, line, reason,
                   matcher_body_truncated = NA, matcher_input_bytes = NA,
                   body_truncated = NA) {
  data.frame(
    path = path, allowed = as.logical(allowed), line = as.integer(line),
    reason = as.character(reason),
    matcher_body_truncated = as.logical(matcher_body_truncated),
    matcher_input_bytes = as.integer(matcher_input_bytes),
    body_truncated = as.logical(body_truncated), stringsAsFactors = FALSE
  )
}

gf_from_v1 <- function(path, r) {
  allowed <- c(allow = TRUE, disallow = FALSE)[r$url_decision]
  gf_row(
    path, unname(allowed), r$matched_line, r$reason,
    matcher_body_truncated = r$matcher_body_truncated,
    matcher_input_bytes = r$matcher_input_bytes
  )
}

gf_from_legacy <- function(path, x) {
  r <- x$results
  # A URL refused before any fetch has no `robots` row.
  truncated <- x$robots$body_truncated
  if (length(truncated) != 1L) truncated <- NA
  gf_row(
    path, r$allowed, r$matched_line, r$decision_source,
    body_truncated = truncated
  )
}

# Serve `body` at the ssrfr boundary for the duration of `code`.
gf_with_body <- function(body, code) {
  local_fake_ssrfr(function(req) fake_response(200L, body = body))
  force(code)
}

# One row per robotstxtr path the case reaches: `allowed` (NA when no
# decision), `line` (NA when no rule is reported), the reason, and the
# truncation facts gf_row() names.
gf_run_case <- function(case) {
  rows <- list()
  body <- case$body
  if ("v1_text" %in% case$paths) {
    rulesets <- gf_case_rulesets(case)
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
    rows[[length(rows) + 1L]] <- gf_from_legacy("text", x)
  }
  if ("url" %in% case$paths) {
    x <- gf_with_body(body, allowed_by_robots_url(case$url, case$token))
    rows[[length(rows) + 1L]] <- gf_from_legacy("url", x)
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
