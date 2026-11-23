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
// line; 4 on a file that cannot be opened, read or written.

#include <cstddef>
#include <cstdio>
#include <fstream>
#include <iostream>
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
    // stdio, not an ifstream: libc++'s filebuf reports a read error as end
    // of file, so the stream state cannot tell a short read from a failed one.
    std::FILE* file = std::fopen(body_file.c_str(), "rb");
    if (file == nullptr) {
      std::cerr << "reference: cannot open body " << body_file << "\n";
      return 4;
    }
    std::string body;
    char buf[1 << 16];
    std::size_t n;
    while ((n = std::fread(buf, 1, sizeof buf, file)) > 0) {
      body.append(buf, n);
    }
    const bool read_failed = std::ferror(file) != 0;
    std::fclose(file);
    if (read_failed) {
      std::cerr << "reference: cannot read body " << body_file << "\n";
      return 4;
    }
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
