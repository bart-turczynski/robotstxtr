# robotstxtr's CRAN release deltas

Follow the fleet checklist,
[seor `design/release-checklist.md`](https://gitlab.com/bart-turczynski/seor/-/blob/main/design/release-checklist.md).
robotstxtr's deltas:

- **Step 5: run every gate first.** The vendored C++ fidelity checks
  (`vendor-fidelity:yandex`, `vendor-fidelity:bing`) run only in CI's `gates`
  job, not in the pre-push hook. Confirm that job passed on the release
  commit, or run `Rscript dev/gates.R`, which runs them all.
- **Step 6 is the only Windows, macOS and valgrind check.** Every CI job is
  Linux (`.gitlab-ci.yml`): the fleet's runners are Docker on an arm64 Mac,
  which can host neither Windows nor R-hub's x86_64 valgrind image. That was
  chosen on 2026-10-08 instead of Windows and macOS CI legs (ROBO-mkuskipr).
  So step 6, on the release SHA, gates the release on:
  - win-builder devel, release and oldrelease, the Windows check, because
    they test the tarball itself;
  - R-hub `macos` and `macos-arm64`, the macOS check;
  - R-hub `linux`, `clang-asan` and `clang-ubsan`. The sanitizers matter here
    because of the compiled code.

  Three R-hub platforms fail for platform reasons and do not gate (0.3.0,
  ROBO-lvddphcx). By the owner's decision they are recorded on the release
  issue, not in `cran-comments.md`:
  - `windows`: R-hub checks the tarball out of git and `.gitattributes` is
    Rbuildignored, so line-ending conversion rewrites the byte-exact corpus
    files.
  - `valgrind`: the job fails on any valgrind error, and R's own regex and
    DCF code and the test-only dependencies report some. Read its log: an
    error with a frame in robotstxtr code blocks the release; on 0.3.0 there
    was none.
  - `nosuggests`: the vignette needs `rmarkdown`.
- **Step 7: submit from a clean clone, always.** A tarball built from a
  working copy can ship untracked files that no ignore list names
  (ROBO-bqvkezdp; `tmp/` itself is now both gitignored and Rbuildignored).
