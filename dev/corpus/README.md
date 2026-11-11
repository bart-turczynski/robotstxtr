# Corpus harness

One repeatable scan of a private corpus of fetched robots.txt records against
a robotstxtr source tree (ROBO-qbxsydcf). Validator calibration, refactor
equivalence, engine audits and library comparisons all start from it.

The corpus and every output stay private. Nothing here, and nothing a run
writes, belongs in this repository.

## Inputs and outputs

- `ROBOTSTXTR_CORPUS`: the corpus directory, read only. One directory per
  host, each holding a `robots.rds`: a list with at least `fetch_outcome`,
  `http_status`, `content_type`, `content_flag`, `body_truncated` and `body`
  (a raw vector, or `NULL` when nothing was stored). A host directory with no
  `robots.rds` is skipped, counted in the run's files table and listed in its
  manifest (`has_rds = FALSE`): file ids and chunks come from the whole
  listing, so an empty directory is part of the input set.
- `ROBOTSTXTR_CORPUS_OUT`: the private store. A run writes its outputs only
  under `ROBOTSTXTR_CORPUS_OUT/<run-id>/`; the one write outside it is the
  compiled code `--pkg` loading leaves in the package tree (below).

The harness refuses to run when either variable is unset, when the corpus
directory does not exist, when the output directory lies inside a git work
tree (so no output can ever be committed) or inside the corpus, and when the
run directory already exists.

## Usage

```sh
env ROBOTSTXTR_CORPUS=<corpus> ROBOTSTXTR_CORPUS_OUT=<store> \
  Rscript dev/corpus/run.R <mode> --pkg <package source> [options]
env ROBOTSTXTR_CORPUS_OUT=<store> \
  Rscript dev/corpus/run.R compare --a <run-id> --b <run-id>
```

`--pkg` names the package source tree to evaluate; the harness loads it with
`pkgload::load_all()`, so the same harness can run against `main` and against
a refactor branch checked out in another worktree. Loading compiles `src/`
inside that tree (object files and the shared library, which the package's
`.gitignore` covers): the one write a run makes outside its run directory.

Options: `--run-id ID` (default `<mode>-<UTC time>`), `--seed N` (the random
path set), `--workers 1|2`, `--chunk-size N` (host directories per shard),
`--max-rule-paths N` (cap on rule-derived paths per file), `--random-paths N`,
`--large-bytes N` and `--size-rule-paths N` (the narrow tier, below),
`--subset K/N` (only the chunks whose index mod N is K, K < N),
`--max-hosts N` (only the first N host directories, N >= 1), and
`--manifest ID` (record whether the corpus still matches an earlier finished
run's manifest).

Exit status: 0 for a valid run, 2 for a refusal, 3 for an invalid run. Every
refusal that can be decided before the work starts is: the arguments, every
run id (`--run-id`, `--a`, `--b`, `--manifest`: a plain name, never a path),
the run `--manifest` names (it must exist, be finished and keep its
`manifest.rds`), a `--pkg` that is missing or outside a git work tree, every
compare check (below), and an empty chunk plan all refuse before the run
directory is created, so a refusal leaves no `running` record behind.

## Modes

- `manifest`: sha256 of every `robots.rds`, nothing else.
- `validate`: `robots_validate_text()` on every stored body; the documents
  frame and the diagnostics (codes, severities, lines) per file.
- `evaluate`: `robots_evaluate_text_v1()` on every stored body, over every
  ruleset x matcher backend x product token the live contract supports:
  rulesets and backends from `robots_engine_contract_v1()`, backends whose
  availability is `available`, and the tokens `*`, `Googlebot`,
  `Googlebot-Image`, `Yandex`, `bingbot` and one unknown token, plus the
  tokens the contract publishes for each bounded backend, offered to that
  backend and kept where `robots_resolve_matcher_profile_v1()` accepts the
  pair. `combos.rds` lists the grid and the pairs left out. The paths per
  file are (a) up to `--max-rule-paths` paths derived from the file's own
  Allow and Disallow values by the harness's own line regex, never the
  package's parser, (b) a fixed list of probes (`$`, `*`, percent-escapes in
  both cases, `%2F`, letter case, `index.html`, non-ASCII, the empty path,
  queries), and (c) a seeded random set that depends only on `--seed`.
  The package parses each distinct body once per call, but every result row
  still walks every rule of its body, so a large body's rows are costly: a
  body over `--large-bytes` (default 65,536) gets the narrow tier,
  every ruleset x available backend with each backend's first named token
  (`size_combos`, same combo ids) over up to `--size-rule-paths` rule paths
  and a short fixed probe list. The `paths` table's `tier` column says which
  a file got.
  The body is evaluated with its NUL bytes removed (an R string cannot hold
  one), while `validate` sees the raw bytes, NULs included; the files table's
  `nul_bytes` counts them, and its `evaluated_bytes` (the `variants`
  table's, in size mode) gives the length actually evaluated. Runs from
  before `evaluated_bytes` moved from the `paths` table to the files table
  compare with later ones as a `<shape>` difference in the files table in
  every mode, and in the `paths` table too in evaluate mode.
- `size`: every stored body of at least 511,999 bytes cut to 511,999,
  512,000 and 512,001 bytes, plus the whole body, and two synthetic bodies
  whose cut falls through a rule line and through a percent-escape; each
  variant validated and evaluated on the narrow tier described above. These
  are supplied bodies: the acquisition path's cut at `max_bytes` is not
  exercised here.
- `compare`: two runs of one mode, shard by shard. It first refuses when the
  two runs read different input sets (different manifests for full runs; for
  a `--subset` or `--max-hosts` run, any file it read that the other run read
  differently), and when a chunk both runs hold names different host
  directories or file ids in each (a different listing behind a `--subset`
  run, or a `--max-hosts` cut mid-chunk: compare a `--max-hosts` run with a
  fuller one only when N is a multiple of `--chunk-size`). It also refuses a
  run that is not `finished`, and two runs that differ in a parameter, in the
  evaluation grid (`combos.rds`), in the random or fixed path sets (their
  sha256), in the token list or in the size targets. Every one of these
  checks runs before the compare run's own directory is created. The
  harness and package trees of each run are recorded in the compare record,
  not checked; its `harness_same` is `TRUE` only when both runs recorded the
  same harness tree and neither had uncommitted harness changes, and a
  `NOTE` is printed otherwise. It then
  diffs the result tables at `identical()` level, prints
  the count of differing rows per table and writes the detail to its own run
  directory (`compare-summary.rds`, `compare-detail.rds`). The verdict is
  `DIFFERENT` when any row differs, and when a full run lacks a shard the
  other run holds; a `--subset` or `--max-hosts` run may lack shards.

## The run directory

- `record.rds`, `record.json`: the run record. The package's git SHA, the
  git tree hashes of its `R/` and `src/` and the blob hash of its
  `DESCRIPTION` (these name the code independent of the branch), whether that
  code or the whole tree was dirty, the harness's own git state, the loaded
  package versions, the contract revisions, the parameters, the manifest
  checks, wall time, peak memory and per-chunk statistics.
- `manifest.rds`: the manifest taken at the start of the run.
- `combos.rds`: the evaluation grid (evaluate and size).
- `shards/<table>-<chunk>.rds`: the result tables, one shard per chunk of
  host directories, character columns stored as factors, xz-compressed.
  `timing` shards hold per-file seconds and are never compared.

## Input checks

Every run takes a manifest of its input files at the start, right after it
lists the corpus, hashes each file again from the bytes it actually
processes, and takes a fresh manifest at the end. A full run lists the
corpus again for the end manifest, so a host directory or `robots.rds` that
appeared during the run counts; a `--subset` or `--max-hosts` run re-hashes
the directories it planned. The manifest records whether each planned host
directory exists (`dir_exists`) apart from whether it holds a `robots.rds`,
so a planned directory already gone at the start, or gone by the end, counts
as vanished in a partial run too. A `robots.rds` that vanishes between the
existence check and the read is recorded as absent and shows up as a
change; one that is there but cannot be read (no permission, a directory in
its place) fails its chunk instead. If any file vanished, appeared or changed between the three, the run
is recorded as `invalid`, the changes go to `input-changes.rds`, and the
script exits with status 3.

`--manifest` compares the start manifest with the named run's: both full,
the two must name the same snapshot; when one is partial, every host
directory it planned must appear, byte for byte, in the other (two partial
runs: the directories both planned). `frozen_rows_compared` counts the host
directories both manifests hold; when it is 0, the run says nothing was
compared instead of warning of a mismatch.

A chunk that delivers no result (its forked worker was killed, ran out of
memory or raised an error) also makes the run `invalid` and exits 3; the
record's `worker_failures` names each such chunk and its cause, and the
input checks are skipped, since the missing shards say nothing about the
corpus. With `--workers 1` the run stops at the first such chunk. A mode
that fails outside its chunks (size mode builds its synthetic chunk 0 in
the main process) is `invalid` the same way, its error in
`invalid_cause`.

## Comparing two package trees

Run the same mode with the same parameters against each tree, then compare:

```sh
env ... Rscript dev/corpus/run.R evaluate --pkg <tree A> --run-id a-eval
env ... Rscript dev/corpus/run.R evaluate --pkg <tree B> --run-id b-eval
env ROBOTSTXTR_CORPUS_OUT=<store> Rscript dev/corpus/run.R compare \
  --a a-eval --b b-eval
```

A full `evaluate` run is long; `--subset K/N` gives a deterministic part of
it, comparable chunk by chunk with a full run.
