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
  `robots.rds` is skipped and counted in the run's files table.
- `ROBOTSTXTR_CORPUS_OUT`: the private store. A run writes only under
  `ROBOTSTXTR_CORPUS_OUT/<run-id>/`.

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
inside that tree.

Options: `--run-id ID` (default `<mode>-<UTC time>`), `--seed N` (the random
path set), `--workers 1|2`, `--chunk-size N` (host directories per shard),
`--max-rule-paths N` (cap on rule-derived paths per file), `--random-paths N`,
`--large-bytes N` and `--size-rule-paths N` (the narrow tier, below),
`--subset K/N` (only the chunks whose index mod N is K), `--max-hosts N`
(only the first N host directories), and `--manifest ID` (record whether the
corpus still matches an earlier run's manifest).

Exit status: 0 for a valid run, 2 for a refusal, 3 for an invalid run.

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
  The package parses a body once per result row, so a large body's rows are
  costly: a body over `--large-bytes` (default 65,536) gets the narrow tier,
  every ruleset x available backend with each backend's first named token
  (`size_combos`, same combo ids) over up to `--size-rule-paths` rule paths
  and a short fixed probe list. The `paths` table's `tier` column says which
  a file got.
- `size`: every stored body of at least 511,999 bytes cut to 511,999,
  512,000 and 512,001 bytes, plus the whole body, and two synthetic bodies
  whose cut falls through a rule line and through a percent-escape; each
  variant validated and evaluated on the narrow tier described above. These
  are supplied bodies: the acquisition path's cut at `max_bytes` is not
  exercised here.
- `compare`: two runs of one mode, shard by shard. It first refuses when the
  two runs read different input sets (different manifests for full runs; for
  a `--subset` or `--max-hosts` run, any file it read that the other run read
  differently), then diffs the result tables at `identical()` level, prints
  the count of differing rows per table and writes the detail to its own run
  directory (`compare-summary.rds`, `compare-detail.rds`).

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

Every run takes a manifest of its input files at the start, hashes each file
again from the bytes it actually processes, and takes a fresh manifest at the
end. If any file vanished, appeared or changed between the three, the run is
recorded as `invalid`, the changes go to `input-changes.rds`, and the script
exits with status 3.

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
