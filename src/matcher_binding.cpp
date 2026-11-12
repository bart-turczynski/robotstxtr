// cpp11 binding for the vendored googlebot robots.txt matcher.
//
// This file is NOT part of the vendored upstream snapshot; it is the R package's
// own glue and carries no Google/Apache header. The vendored engine
// (robots.{cc,h}, reporting_robots.{cc,h}) preserves its Apache-2.0 headers
// verbatim.
//
// Slice R1 surface: a scalar robots.txt body and scalar matcher user agent
// are matched against a vector of URLs. Each element yields the matcher's
// allow/deny decision plus the upstream one-based matching line, computed from a
// single matcher run per URL so the R layer can classify the happy-path
// decision_source (rule_allow / rule_disallow / default_allow) without a second
// pass. matching_line() itself is not surfaced as the R-facing matched_line
// column here; that (and full callback correlation) is slice R3.
//
// The batch surface (ROBO-iooslxvj): robotstxtr_google_eval_batch_() parses
// each distinct body once and answers every (URL, product token) row that
// selects it. See the comment above it. robotstxtr_batch_body_groups_() at
// the end serves the shared batch module (R/matcher-batch-v1.R) of all three
// engines: it only groups bodies, and touches no engine.
//
// The crawler-token layer (ROBO-fbbmvbob): robotstxtr_google_crawler_row_()
// and the batch run a second matcher for a crawler's parent token and read
// ever_seen_specific_agent() and disallow_ignore_global(), so the v1 google
// ruleset can follow Google's crawler tokens. The two single-token functions
// first below stay as they are, for the legacy functions.

#include <cstddef>
#include <memory>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include <cpp11.hpp>

#include "binding_bytes.h"
#include "robots.h"

namespace googlebot {
// Defined in the vendored robots.cc outside its anonymous namespace ("to allow
// testing") but not declared by robots.h. Declared here, not in the vendored
// header, so the vendored sources stay untouched.
std::string GetPathParamsQuery(const std::string& url);
}  // namespace googlebot

// Returns TRUE/FALSE per URL: is `url` allowed for `user_agent` under `body`.
[[cpp11::register]]
cpp11::writable::logicals robotstxtr_allowed_text_(std::string body,
                                                   cpp11::strings url,
                                                   std::string user_agent) {
  cpp11::writable::logicals out(static_cast<R_xlen_t>(url.size()));
  googlebot::RobotsMatcher matcher;
  const std::string_view body_view(body);
  for (R_xlen_t i = 0; i < static_cast<R_xlen_t>(url.size()); ++i) {
    const std::string u(url[i]);
    const bool allowed =
        matcher.OneAgentAllowedByRobots(body_view, user_agent, u);
    out[i] = allowed ? TRUE : FALSE;
  }
  return out;
}

// Returns the upstream one-based matching line per URL, or 0 when no directive
// matched (the matcher's own sentinel). Used by R only to split rule_allow from
// default_allow; the R-facing matched_line column stays NA until slice R3.
[[cpp11::register]]
cpp11::writable::integers robotstxtr_matching_line_text_(std::string body,
                                                         cpp11::strings url,
                                                         std::string user_agent) {
  cpp11::writable::integers out(static_cast<R_xlen_t>(url.size()));
  googlebot::RobotsMatcher matcher;
  const std::string_view body_view(body);
  for (R_xlen_t i = 0; i < static_cast<R_xlen_t>(url.size()); ++i) {
    const std::string u(url[i]);
    matcher.OneAgentAllowedByRobots(body_view, user_agent, u);
    out[i] = matcher.matching_line();
  }
  return out;
}

namespace {

// Which token's group decided a crawler-aware row (ROBO-fbbmvbob). R maps
// these onto `group_token`: the caller's token, the parent token, "*", or NA.
enum GroupKind : int {
  kGroupNone = 0,    // a `*`-ignoring crawler with no group of its own
  kGroupOwn = 1,     // a group names the caller's token
  kGroupParent = 2,  // no group names it; one names its parent token
  kGroupGlobal = 3,  // no specific group: the `*` rules, if any
};

struct CrawlerDecision {
  bool allowed;
  int line;
  int group;
};

// The crawler-token layer over finished matchers (ROBO-fbbmvbob). `own` ran
// the caller's token; `parent` ran the parent token, or is null when the
// crawler lists none. "No specific group" is the matcher's own
// ever_seen_specific_agent(), never inferred from a decision, and groups are
// never merged: the own group wins, else the parent's, else `*`. A crawler
// that ignores `*` decides from its specific group alone
// (disallow_ignore_global()) and, with no group of its own, reports no line:
// matching_line() would report the `*` line there.
CrawlerDecision decide_crawler_row(const googlebot::RobotsMatcher& own,
                                   const googlebot::RobotsMatcher* parent,
                                   bool ignore_global) {
  if (own.ever_seen_specific_agent()) {
    const bool disallowed =
        ignore_global ? own.disallow_ignore_global() : own.disallow();
    return {!disallowed, own.matching_line(), kGroupOwn};
  }
  if (parent != nullptr && parent->ever_seen_specific_agent()) {
    return {!parent->disallow(), parent->matching_line(), kGroupParent};
  }
  if (ignore_global) {
    return {!own.disallow_ignore_global(), 0, kGroupNone};
  }
  return {!own.disallow(), own.matching_line(), kGroupGlobal};
}

}  // namespace

// One crawler-aware row (ROBO-fbbmvbob), the reference for the batch below:
// `url` (one string) under `body` for `user_agent`, with `parent` the parent
// token ("" for none) and `ignore_global` whether the crawler ignores `*`.
// Each token gets its own matcher and its own parse, as
// OneAgentAllowedByRobots() runs it. Returns `allowed`, `matching_line` (0
// when no directive matched or none is reported) and `group` (GroupKind).
[[cpp11::register]]
cpp11::writable::list robotstxtr_google_crawler_row_(std::string body,
                                                     cpp11::strings url,
                                                     std::string user_agent,
                                                     std::string parent,
                                                     bool ignore_global) {
  if (url.size() != 1) {
    cpp11::stop("`url` must be a single string");
  }
  const std::string u(url[0]);
  const std::string_view body_view(body);
  googlebot::RobotsMatcher own;
  own.OneAgentAllowedByRobots(body_view, user_agent, u);
  googlebot::RobotsMatcher parent_matcher;
  const googlebot::RobotsMatcher* parent_ptr = nullptr;
  if (!parent.empty()) {
    parent_matcher.OneAgentAllowedByRobots(body_view, parent, u);
    parent_ptr = &parent_matcher;
  }
  const CrawlerDecision d = decide_crawler_row(own, parent_ptr, ignore_global);
  using namespace cpp11::literals;
  return cpp11::writable::list({
      "allowed"_nm = cpp11::as_sexp(d.allowed),
      "matching_line"_nm = cpp11::as_sexp(d.line),
      "group"_nm = cpp11::as_sexp(d.group),
  });
}

namespace {

// One row's matcher. It overrides nothing: it only makes public the parse
// callbacks and InitUserAgentsAndPath() that RobotsMatcher keeps protected, so
// the fan-out handler below can drive many matchers from one parse. Each
// callback runs RobotsMatcher's own code on this row's path and agent, as
// AllowedByRobots() would on its own parse of the same body.
class RowMatcher : public googlebot::RobotsMatcher {
 public:
  using googlebot::RobotsMatcher::InitUserAgentsAndPath;
  using googlebot::RobotsMatcher::HandleRobotsStart;
  using googlebot::RobotsMatcher::HandleRobotsEnd;
  using googlebot::RobotsMatcher::HandleUserAgent;
  using googlebot::RobotsMatcher::HandleAllow;
  using googlebot::RobotsMatcher::HandleDisallow;
  using googlebot::RobotsMatcher::HandleSitemap;
  using googlebot::RobotsMatcher::HandleUnknownAction;
  using googlebot::RobotsMatcher::ReportLineMetadata;
};

// Forwards every parse callback, unchanged and in order, to each row matcher.
// The string_views are the parser's own (NUL-terminated, which
// RobotsMatcher::ExtractUserAgent relies on), passed through as they are.
class FanOutHandler : public googlebot::RobotsParseHandler {
 public:
  explicit FanOutHandler(const std::vector<RowMatcher*>& matchers)
      : matchers_(matchers) {}

  void HandleRobotsStart() override {
    for (RowMatcher* m : matchers_) m->HandleRobotsStart();
  }
  void HandleRobotsEnd() override {
    for (RowMatcher* m : matchers_) m->HandleRobotsEnd();
  }
  void HandleUserAgent(int line_num, std::string_view value) override {
    for (RowMatcher* m : matchers_) m->HandleUserAgent(line_num, value);
  }
  void HandleAllow(int line_num, std::string_view value) override {
    for (RowMatcher* m : matchers_) m->HandleAllow(line_num, value);
  }
  void HandleDisallow(int line_num, std::string_view value) override {
    for (RowMatcher* m : matchers_) m->HandleDisallow(line_num, value);
  }
  void HandleSitemap(int line_num, std::string_view value) override {
    for (RowMatcher* m : matchers_) m->HandleSitemap(line_num, value);
  }
  void HandleUnknownAction(int line_num, std::string_view action,
                           std::string_view value) override {
    for (RowMatcher* m : matchers_) {
      m->HandleUnknownAction(line_num, action, value);
    }
  }
  void ReportLineMetadata(int line_num,
                          const LineMetadata& metadata) override {
    for (RowMatcher* m : matchers_) m->ReportLineMetadata(line_num, metadata);
  }

 private:
  const std::vector<RowMatcher*>& matchers_;
};

}  // namespace

// One URL as the batch's request target: the string cpp11 makes of it for the
// row path's `cpp11::strings url` (translated to UTF-8 by R, so a
// "bytes"-marked URL fails here exactly as it fails there), returned as a
// UTF-8 string whose bytes the batch module hands back as raw.
[[cpp11::register]]
cpp11::writable::strings robotstxtr_google_request_target_(
    cpp11::strings url) {
  if (url.size() != 1) {
    cpp11::stop("`url` must be a single string");
  }
  const std::string u(url[0]);
  cpp11::writable::strings out(1);
  // cpp11::r_string makes the CHARSXP (marked UTF-8) under unwind protection.
  out[0] = cpp11::r_string(u);
  return out;
}

// The Google batch (ROBO-iooslxvj): parse each DISTINCT body once and answer
// every row that selects it.
//
// `bodies` are the distinct matcher strings (already cut to Google's window
// and decoded by R: the strings the row path hands robotstxtr_allowed_text_);
// `ids` is the 1-based body per row; `agents` the product token per row;
// `urls` the full URL per row as raw bytes (raw(0) for none), from which
// the matcher's own GetPathParamsQuery() takes the path. Each row gets its own
// RobotsMatcher, set up as AllowedByRobots() sets it up, and one
// ParseRobotsTxt() per body drives all of that body's matchers through the
// fan-out handler.
//
// The crawler-token layer (ROBO-fbbmvbob): `parents` is the parent token per
// row ("" for none) and `ignore_global` whether the row's crawler ignores
// `*`. A row with a parent gets a second matcher, for the parent token, on
// the same parse, so a body is still parsed once; decide_crawler_row()
// above picks between them as the row function does. A row with neither
// decides as AllowedByRobots() would. Returns, per row, `allowed`,
// `matching_line` (0 when no directive matched or none is reported) and
// `group` (GroupKind), plus the scalar `n_parse_calls`, the number of
// ParseRobotsTxt() runs.
[[cpp11::register]]
cpp11::writable::list robotstxtr_google_eval_batch_(cpp11::strings bodies,
                                                    cpp11::integers ids,
                                                    cpp11::strings agents,
                                                    cpp11::list urls,
                                                    cpp11::strings parents,
                                                    cpp11::logicals
                                                        ignore_global) {
  const R_xlen_t n = ids.size();
  if (agents.size() != n || urls.size() != n || parents.size() != n ||
      ignore_global.size() != n) {
    cpp11::stop(
        "`ids`, `agents`, `urls`, `parents` and `ignore_global` need one "
        "element per row");
  }
  const R_xlen_t n_bodies = bodies.size();
  std::vector<std::vector<R_xlen_t>> rows_by_body(
      static_cast<std::size_t>(n_bodies));
  for (R_xlen_t i = 0; i < n; ++i) {
    const int id = ids[i];
    if (id == NA_INTEGER || id < 1 || id > n_bodies) {
      cpp11::stop("body id out of range at row %d", static_cast<int>(i + 1));
    }
    rows_by_body[static_cast<std::size_t>(id - 1)].push_back(i);
  }

  cpp11::writable::logicals allowed(n);
  cpp11::writable::integers matching_line(n);
  cpp11::writable::integers group(n);
  int n_parse_calls = 0;

  for (R_xlen_t b = 0; b < n_bodies; ++b) {
    const std::vector<R_xlen_t>& rows =
        rows_by_body[static_cast<std::size_t>(b)];
    const std::size_t k = rows.size();

    // Sized up front and never resized: each matcher keeps pointers into its
    // row's path and agent vectors for the whole parse.
    std::vector<std::string> paths(k);
    std::vector<std::vector<std::string>> row_agents(k);
    std::vector<std::vector<std::string>> parent_agents(k);
    std::vector<std::unique_ptr<RowMatcher>> owned(k);
    std::vector<std::unique_ptr<RowMatcher>> parent_owned(k);
    std::vector<RowMatcher*> matchers;
    matchers.reserve(2 * k);
    for (std::size_t j = 0; j < k; ++j) {
      const R_xlen_t i = rows[j];
      const std::string url =
          robotstxtr_binding::raw_sexp_to_bytes(urls[i]);
      paths[j] = googlebot::GetPathParamsQuery(url);
      row_agents[j].push_back(std::string(agents[i]));
      owned[j] = std::make_unique<RowMatcher>();
      matchers.push_back(owned[j].get());
      const std::string parent(parents[i]);
      if (!parent.empty()) {
        parent_agents[j].push_back(parent);
        parent_owned[j] = std::make_unique<RowMatcher>();
        matchers.push_back(parent_owned[j].get());
      }
    }
    for (std::size_t j = 0; j < k; ++j) {
      owned[j]->InitUserAgentsAndPath(&row_agents[j], paths[j].c_str());
      if (parent_owned[j]) {
        parent_owned[j]->InitUserAgentsAndPath(&parent_agents[j],
                                               paths[j].c_str());
      }
    }

    const std::string body(bodies[b]);
    FanOutHandler handler(matchers);
    googlebot::ParseRobotsTxt(std::string_view(body), &handler);
    ++n_parse_calls;

    for (std::size_t j = 0; j < k; ++j) {
      const R_xlen_t i = rows[j];
      const CrawlerDecision d = decide_crawler_row(
          *owned[j], parent_owned[j].get(), ignore_global[i] == TRUE);
      allowed[i] = d.allowed ? TRUE : FALSE;
      matching_line[i] = d.line;
      group[i] = d.group;
    }
  }

  using namespace cpp11::literals;
  return cpp11::writable::list({
      "allowed"_nm = allowed,
      "matching_line"_nm = matching_line,
      "group"_nm = group,
      "n_parse_calls"_nm = cpp11::as_sexp(n_parse_calls),
  });
}

// The shared batch module's body grouping (ROBO-iooslxvj), for every engine:
// for each element of `bodies`, the 1-based id of its group, ids numbered in
// order of first appearance. Raw bodies group on their exact bytes alone
// (embedded NUL, invalid UTF-8 and attributes are just bytes and ignored);
// the bytes of each distinct R object are hashed once, and a later element
// that is the same object takes its group at once, so rows that share one
// body object cost one lookup each. Any other element (NULL included) is a
// group of its own, never joined, so the engine sees it and refuses it.
[[cpp11::register]]
cpp11::writable::integers robotstxtr_batch_body_groups_(cpp11::list bodies) {
  const R_xlen_t n = bodies.size();
  cpp11::writable::integers out(n);
  std::unordered_map<SEXP, int> by_object;
  // Views into the bodies' own bytes, which `bodies` keeps alive.
  std::unordered_map<std::string_view, int> by_bytes;
  int groups = 0;
  for (R_xlen_t i = 0; i < n; ++i) {
    SEXP body = bodies[i];
    if (TYPEOF(body) != RAWSXP) {
      out[i] = ++groups;
      continue;
    }
    const auto same_object = by_object.find(body);
    if (same_object != by_object.end()) {
      out[i] = same_object->second;
      continue;
    }
    const R_xlen_t size = Rf_xlength(body);
    const std::string_view bytes(
        size == 0 ? "" : reinterpret_cast<const char*>(RAW(body)),
        static_cast<std::size_t>(size));
    const auto found = by_bytes.emplace(bytes, groups + 1);
    if (found.second) ++groups;
    by_object.emplace(body, found.first->second);
    out[i] = found.first->second;
  }
  return out;
}
