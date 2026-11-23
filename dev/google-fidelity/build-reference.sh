#!/bin/sh
# Build the pristine Google reference matcher (ROBO-basbqqdh). Dev only: never
# run by the package, its tests or CI.
#
# Usage:
#   ROBOTSTXTR_GOOGLE_UPSTREAM=<dir> dev/google-fidelity/build-reference.sh [-o out_dir]
#   dev/google-fidelity/build-reference.sh [-o out_dir] <upstream_dir>
#
# The argument, when given, takes precedence over ROBOTSTXTR_GOOGLE_UPSTREAM.
# <upstream_dir> is a google/robotstxt source directory you provisioned at
# 22b355ff855419e6a3ff8ff09c0ad7fdb17116f9, the SHA the vendored matcher pins
# (a clone checked out at it, or its robots.cc and robots.h). Nothing is
# downloaded (design/PRD.md §7 slice C5). robots.cc and robots.h must match the
# SHA-256 values below, or the build stops before compiling.
#
# Abseil: `pkg-config absl_strings` must resolve. The general route is
# PKG_CONFIG_PATH; as a shortcut, set ABSL_PREFIX to an Abseil install prefix
# holding lib/pkgconfig/absl_strings.pc or lib64/pkgconfig/absl_strings.pc,
# which is put ahead of PKG_CONFIG_PATH. CXX (default c++; may hold several
# words, such as `ccache c++`) and CXXFLAGS (default -O2) are honored.
#
# The binary is written to <out_dir>/google-ref (default out_dir:
# tmp/google-fidelity under the repository, which is gitignored; never commit
# build output) and its path is printed on standard output. The checked
# sources are copied to a fresh temporary directory, removed on exit; nothing
# else in <out_dir> is touched.
# Then run:
#   Rscript dev/google-fidelity/differential.R <out_dir>/google-ref

set -eu

ROBOTS_CC_SHA256=d05a7fa74c0e8b9fc440d15f4c3ae9a80873c0d950e569de2926303fd75ed473
ROBOTS_H_SHA256=912f3a5c6821f8a9a97269f9598b7f29ac1edf1ee20e173f1dd2d9ca48fb0bd5
UPSTREAM_SHA=22b355ff855419e6a3ff8ff09c0ad7fdb17116f9

die() {
  printf 'build-reference: %s\n' "$*" >&2
  exit 1
}

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)

usage="usage: build-reference.sh [-o out_dir] [upstream_dir]"
out_dir=$root/tmp/google-fidelity
while getopts o: opt; do
  case $opt in
    o) out_dir=$OPTARG ;;
    *) die "$usage" ;;
  esac
done
shift $((OPTIND - 1))
[ "$#" -le 1 ] || die "$usage"
upstream=${1:-${ROBOTSTXTR_GOOGLE_UPSTREAM:-}}
[ -n "$upstream" ] || die "no upstream source directory: pass it as the argument or set ROBOTSTXTR_GOOGLE_UPSTREAM (google/robotstxt at $UPSTREAM_SHA)"
[ -d "$upstream" ] || die "upstream source directory not found: $upstream"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d ' ' -f 1
  else
    die "neither sha256sum nor shasum is available to check the sources"
  fi
}

check_source() {
  file=$upstream/$1
  [ -f "$file" ] || die "$1 not found in $upstream"
  actual=$(sha256 "$file")
  [ "$actual" = "$2" ] || die "$1 does not match google/robotstxt at $UPSTREAM_SHA: sha256 $actual, expected $2"
}
check_source robots.cc "$ROBOTS_CC_SHA256"
check_source robots.h "$ROBOTS_H_SHA256"

command -v pkg-config >/dev/null 2>&1 || die "pkg-config is required to find Abseil (absl_strings)"
if [ -n "${ABSL_PREFIX:-}" ]; then
  absl_pc_dir=
  for dir in "$ABSL_PREFIX/lib/pkgconfig" "$ABSL_PREFIX/lib64/pkgconfig"; do
    if [ -f "$dir/absl_strings.pc" ]; then
      absl_pc_dir=$dir
      break
    fi
  done
  [ -n "$absl_pc_dir" ] || die "ABSL_PREFIX=$ABSL_PREFIX holds no lib/pkgconfig/absl_strings.pc or lib64/pkgconfig/absl_strings.pc"
  PKG_CONFIG_PATH=$absl_pc_dir${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
  export PKG_CONFIG_PATH
fi
pkg-config --exists absl_strings || die "Abseil not found: pkg-config absl_strings does not resolve; add its pkgconfig directory to PKG_CONFIG_PATH or set ABSL_PREFIX to an Abseil install prefix"
absl_cflags=$(pkg-config --cflags absl_strings)
absl_libs=$(pkg-config --libs absl_strings)
absl_libdir=$(pkg-config --variable=libdir absl_strings)

mkdir -p "$out_dir"
out_dir=$(CDPATH='' cd -- "$out_dir" && pwd)

# Compile the checked bytes, not the directory: copy them first, into a
# directory this script creates and alone removes.
src=$(mktemp -d "${TMPDIR:-/tmp}/google-ref-src.XXXXXX") || die "cannot create a temporary source directory"
trap 'rm -rf "$src"' EXIT
trap 'exit 1' HUP INT TERM
cp "$upstream/robots.cc" "$upstream/robots.h" "$src/"
check_source_copy() {
  [ "$(sha256 "$src/$1")" = "$2" ] || die "$1 changed while it was copied"
}
check_source_copy robots.cc "$ROBOTS_CC_SHA256"
check_source_copy robots.h "$ROBOTS_H_SHA256"

binary=$out_dir/google-ref
# Word splitting of CXX, CXXFLAGS and the pkg-config output is intended: CXX
# may be a launcher and a compiler (`ccache c++`). The checked source
# directory comes first, so no CXXFLAGS or Abseil include path can shadow
# robots.h.
# shellcheck disable=SC2086
set -- ${CXX:-c++}
# shellcheck disable=SC2086
"$@" -std=c++17 -I"$src" ${CXXFLAGS:--O2} $absl_cflags \
  "$here/reference.cc" "$src/robots.cc" \
  $absl_libs ${absl_libdir:+-Wl,-rpath,"$absl_libdir"} \
  -o "$binary"

printf 'built the google/robotstxt %s reference\n' "$UPSTREAM_SHA" >&2
printf '%s\n' "$binary"
