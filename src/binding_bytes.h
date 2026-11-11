// Byte transport shared by the package's own cpp11 bindings (ROBO-iwmtdutk):
// collector_binding.cpp and matcher_binding.cpp (Google; the latter for the
// batch's raw URL targets, ROBO-iooslxvj), yandex_matcher_binding.cpp and
// bing_binding.cpp.
//
// This header is NOT part of any vendored upstream snapshot; it is the R
// package's own glue. It holds only the moving of bytes between R and C++ and
// the UTF-8 check that decides how a value is marked. No parser, group
// selector, access matcher or URL normalizer lives here, and none is shared
// between the engines (design/robotstxtbing-integration-v2-spec.md section 4).
//
// Header-only (every function `inline`), so src/Makevars lists no new object.

#ifndef ROBOTSTXTR_BINDING_BYTES_H_
#define ROBOTSTXTR_BINDING_BYTES_H_

#include <cstddef>
#include <cstdint>
#include <string>

#include <cpp11.hpp>

namespace robotstxtr_binding {

// Minimal, self-contained UTF-8 well-formedness check (rejects overlong forms,
// UTF-16 surrogates, and code points above U+10FFFF). The bindings use it only
// to decide how a value reaches R: the Google collector marks a callback value
// CE_UTF8 or CE_BYTES, and the Yandex and Bing bindings surface a rule value as
// a UTF-8 character scalar or NA. The exact bytes are never altered.
inline bool is_valid_utf8(const std::string& s) {
  const unsigned char* b = reinterpret_cast<const unsigned char*>(s.data());
  const std::size_t n = s.size();
  std::size_t i = 0;
  while (i < n) {
    const unsigned char c = b[i];
    if (c < 0x80) {
      i += 1;
    } else if ((c >> 5) == 0x6) {  // 110xxxxx: 2-byte sequence
      if (c < 0xC2) return false;  // overlong
      if (i + 1 >= n || (b[i + 1] & 0xC0) != 0x80) return false;
      i += 2;
    } else if ((c >> 4) == 0xE) {  // 1110xxxx: 3-byte sequence
      if (i + 2 >= n || (b[i + 1] & 0xC0) != 0x80 ||
          (b[i + 2] & 0xC0) != 0x80) {
        return false;
      }
      if (c == 0xE0 && b[i + 1] < 0xA0) return false;  // overlong
      if (c == 0xED && b[i + 1] > 0x9F) return false;  // surrogate
      i += 3;
    } else if ((c >> 3) == 0x1E) {  // 11110xxx: 4-byte sequence
      if (i + 3 >= n || (b[i + 1] & 0xC0) != 0x80 ||
          (b[i + 2] & 0xC0) != 0x80 || (b[i + 3] & 0xC0) != 0x80) {
        return false;
      }
      if (c == 0xF0 && b[i + 1] < 0x90) return false;               // overlong
      if (c > 0xF4 || (c == 0xF4 && b[i + 1] > 0x8F)) return false;  // >U+10FFFF
      i += 4;
    } else {
      return false;
    }
  }
  return true;
}

// Copy a RAWSXP's bytes into an owning std::string verbatim -- preserving
// embedded NUL and invalid UTF-8 with no translation or NUL termination.
inline std::string raw_sexp_to_bytes(SEXP x) {
  if (TYPEOF(x) != RAWSXP) {
    cpp11::stop("expected a raw vector");
  }
  const R_xlen_t n = Rf_xlength(x);
  const Rbyte* p = RAW(x);
  return std::string(reinterpret_cast<const char*>(p),
                     static_cast<std::size_t>(n));
}

// Build an owning R raw vector carrying the exact bytes (raw(0) for empty).
inline cpp11::writable::raws bytes_to_raws(const std::string& s) {
  cpp11::writable::raws out(static_cast<R_xlen_t>(s.size()));
  for (std::size_t i = 0; i < s.size(); ++i) {
    out[static_cast<R_xlen_t>(i)] = static_cast<uint8_t>(s[i]);
  }
  return out;
}

// Exact rule-value bytes as a convenience UTF-8 character scalar -- but only
// when the bytes are valid UTF-8 with no embedded NUL; otherwise NA_character_
// (the exact bytes remain available via the raw column). An empty value is a
// valid UTF-8 empty string "".
inline cpp11::r_string value_utf8_or_na(const std::string& s) {
  if (is_valid_utf8(s) && s.find('\0') == std::string::npos) {
    return cpp11::r_string(
        Rf_mkCharLenCE(s.data(), static_cast<int>(s.size()), CE_UTF8));
  }
  return cpp11::r_string(NA_STRING);
}

}  // namespace robotstxtr_binding

#endif  // ROBOTSTXTR_BINDING_BYTES_H_
