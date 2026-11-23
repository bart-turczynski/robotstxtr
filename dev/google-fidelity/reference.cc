// Google fidelity reference driver (ROBO-basbqqdh). Dev only: never built by
// the package. dev/google-fidelity/build-reference.sh compiles it against the
// pristine upstream google/robotstxt robots.cc and robots.h.
//
// Usage: reference <manifest> [<out>]
//
// Each manifest line is `<body_file> TAB <agent> TAB <url>`. For each line the
// driver reads the body file as raw bytes, calls
// RobotsMatcher::OneAgentAllowedByRobots() on a fresh matcher, and writes
// `<allowed 0|1> TAB <matching_line> TAB <ever_seen_specific_agent 0|1>` to
// <out> (standard output when omitted), one line per manifest line, in order.
// This is the contract dev/google-fidelity/differential.R expects.
//
// Exit status: 0 on success; 2 on a usage error; 3 on a malformed manifest
// line; 4 on a file that cannot be opened or written.

#include <fstream>
#include <iostream>
#include <iterator>
#include <ostream>
#include <string>

#include "robots.h"

int main(int argc, char** argv) {
  if (argc != 2 && argc != 3) {
    std::cerr << "usage: reference <manifest> [<out>]\n";
    return 2;
  }
  std::ifstream manifest(argv[1], std::ios::binary);
  if (!manifest) {
    std::cerr << "reference: cannot open manifest " << argv[1] << "\n";
    return 4;
  }
  std::ofstream out_file;
  if (argc == 3) {
    out_file.open(argv[2], std::ios::binary | std::ios::trunc);
    if (!out_file) {
      std::cerr << "reference: cannot write " << argv[2] << "\n";
      return 4;
    }
  }
  std::ostream& out = argc == 3 ? out_file : std::cout;

  std::string line;
  long line_no = 0;
  while (std::getline(manifest, line)) {
    ++line_no;
    const std::string::size_type a = line.find('\t');
    const std::string::size_type b =
        a == std::string::npos ? std::string::npos : line.find('\t', a + 1);
    if (b == std::string::npos) {
      std::cerr << "reference: manifest line " << line_no
                << " is not <body_file> TAB <agent> TAB <url>\n";
      return 3;
    }
    const std::string body_file = line.substr(0, a);
    std::ifstream file(body_file, std::ios::binary);
    if (!file) {
      std::cerr << "reference: cannot open body " << body_file << "\n";
      return 4;
    }
    const std::string body((std::istreambuf_iterator<char>(file)),
                           std::istreambuf_iterator<char>());
    googlebot::RobotsMatcher matcher;
    const bool allowed = matcher.OneAgentAllowedByRobots(
        body, line.substr(a + 1, b - a - 1), line.substr(b + 1));
    out << (allowed ? 1 : 0) << '\t' << matcher.matching_line() << '\t'
        << (matcher.ever_seen_specific_agent() ? 1 : 0) << '\n';
  }
  out.flush();
  if (!out) {
    std::cerr << "reference: writing the answers failed\n";
    return 4;
  }
  return 0;
}
