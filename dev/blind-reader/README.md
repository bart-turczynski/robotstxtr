# Blind-reader pilot

Tooling for ROBO-nvgtqdlu: a small model reads real robots.txt files with
no access to robotstxtr, answers three fixed questions per file, and each
answer is set beside robotstxtr's own reading of the same file so a person
can look for what the package misses. The method and the classification
vocabulary are in the parent epic, ROBO-gqkhoogt.

Every input and output is private (the corpus privacy rule, ROBO-qbxsydcf):
corpus files, host names, the sample list, rendered prompts, answers and
score tables live in the private store, never in git or the tracker. Each
script refuses an output directory inside a git work tree, or one that
already exists. A finding goes into the repository only as a synthetic
`example.com` reproduction.

## Files

- `prompt.md`: the prompt one reader gets, between its `PROMPT START` and
  `PROMPT END` markers, with the RFC 9309 passages and the answer format. A
  stage-1 change to the prompt is a diff of this file.
- `sample.R`: draws the seeded sample and writes one file per body.
- `render.R`: fills the prompt for each sampled file.
- `score.R`: checks each answer's format and compares it with the package.
- `common.R`: shared helpers; it reuses `dev/corpus/harness.R`.
- `selftest.R`: the tools' own check, on synthetic data only (below).

## Self-test

```sh
Rscript dev/blind-reader/selftest.R
```

It builds a tiny synthetic corpus (`.example` hosts, plus records the pool
must skip: a 404, a missing body, a body that is not raw bytes, a file that
is not a record) and a synthetic answer set in a temporary directory outside
any git work tree, runs `sample.R` and `score.R` on them, and exits 1 when
any check fails: `score.R` accepts well-formed answers and rejects each
malformed class with its own code; no host an `--exclude` source names
reaches the sample; the same seed reproduces the sample list and another
seed does not. Run it after changing any script here.

## Steps

Below, `<store>` is the pilot's directory in the private store, and
`<corpus>` the snapshot's host directories (one directory per host, each
with a `robots.rds`, as `dev/corpus/README.md` describes).

1. Draw the sample. `--exclude` takes an earlier private sample, repeated
   once per source: an `.rds` with a `host` column, a text report whose
   `--- ` header lines name the host in their fourth field, a plain list of
   hosts, or a directory whose file and directory names name hosts.

   ```sh
   Rscript dev/blind-reader/sample.R --corpus <corpus> \
     --out <store>/sample --seed <seed> --n 100 \
     --exclude <earlier sample> [--exclude ...]
   ```

   It draws `--pool` host directories (default 2,000) at random, keeps the
   status-200 bodies that are not empty, not over `--max-bytes` (default
   32,768, so the prompt stays small) and not a duplicate of another body,
   and runs the package on each: `robots_validate_text()` for the
   diagnostic codes, and the Google backend against the Bing and Yandex
   backends (on `bingbot` and `Yandex`) over the harness's rule paths and
   fixed probes for the disagreement classes. Half of `--n` is drawn from
   the bodies with no diagnostic; the other half round-robin over every
   `diag:<code>` and `disagree:<pair>:<reason>><reason>` stratum, one body
   per stratum per round. Each file's token is one its user-agent lines
   name (else `Googlebot`, `bingbot` or `Yandex`), and its path comes from
   a rule holding `*`, `$` or `%` where there is one, sometimes with one
   more character so an end anchor is tested.

   It adds anchors from `tests/testthat/fixtures/edge-cases/manifest.csv`:
   every row where the RFC 9309 decision and Google's differ, and
   `--anchors-silent` (default 3) rows where the RFC is silent. They are
   synthetic and show which way the reader leans.

   Ids `br-001` ... are in random order; the first `--stage1` (default 20),
   plus every anchor (`an-01` ...), make stage 1. The output holds
   `files/<id>.bin` (the stored bytes, NULs included), `manifest.tsv` and
   `sample.rds` (the sample list), `pool.rds` (the pool's readings) and
   `record.rds` (seed, arguments, exclusion and pool counts, the package's
   git state).

2. Check the seed reproduces the list, which the ticket's verification
   asks for. The list depends on the package's readings and on the corpus
   as well as on the seed, so a rerun is `SAME` only on the same package
   commit and the same corpus: check out the package at the `git_sha` that
   `<store>/sample/record.rds` records (`$package$git_sha`), with no
   uncommitted changes, and run step 1 again with the same arguments, into
   another directory, adding `--verify <store>/sample` (and `--pkg <that
   tree>` if it is not the tree holding the script). It prints `SAME` and
   exits 0 when both the sample list and the package commit match, or
   `DIFFERENT` (naming a commit mismatch) and exits 1. `record.rds` also
   counts, per `--exclude` source, the corpus hosts it named; a source that
   names none is warned about at run time.

3. Render the stage-1 prompts:

   ```sh
   Rscript dev/blind-reader/render.R --sample <store>/sample \
     --out <store>/prompts/stage1 --stage stage1
   ```

   Each `<id>.txt` is the whole prompt for one file, and the directory
   keeps a copy of the `prompt.md` it was rendered from. A backslash in
   the file appears as `\\`, and bytes that cannot be shown as text
   (controls, invalid UTF-8, and the bytes of a byte order mark, a C1
   control, U+2028 or U+2029) as `\xHH`; encoding questions are answered
   from the bytes, by `pool.rds` and the validator, not by the reader.

4. Read. Answers go in one directory per stage, `<store>/answers/<stage>/`
   (`stage1`, then `stage2`). For each rendered prompt, spawn one reader on
   model `haiku` and give it only this one-line instruction, where `<prompt>`
   is the absolute path of `<store>/prompts/<stage>/<id>.txt`:

   ```text
   Read all of <prompt> with the Read tool, paging with offset and limit while it says more lines remain, then answer the prompt it holds. The numbers in the Read tool's left margin are not the robots.txt line numbers: cite the number before "| " on each file line. Use no other tool and read no other file.
   ```

   Save its reply, unedited, as `<store>/answers/<stage>/<id>.txt`. Spawn
   it from an agent definition that grants the Read tool and nothing else,
   where that is possible.

   Before spawning, check each prompt's longest line and its line count.
   The Read tool truncates a line longer than 2,000 characters, so the
   reader would not see the whole file: a sample with such a line is
   recorded as not read; it is not spawned, and its answer is not guessed.
   The Read tool returns at most 2,000 lines per call by default, so a
   prompt (the prompt text, about 215 lines, plus the file) longer than
   that needs more than one Read call; record its line count, which the
   validity check below needs. This prints each prompt's path, longest line
   in bytes (never less than its length in characters, so a line it puts
   under 2,000 is safe) and line count:

   ```sh
   awk 'FNR==1&&NR>1{print f, m, n} FNR==1{f=FILENAME;m=0} {if(length($0)>m)m=length($0);n=FNR} END{print f, m, n}' <store>/prompts/<stage>/*.txt
   ```

   `<store>/answers/<stage>/run-meta.txt` records the model alias and,
   where the transcript shows it, the resolved model id; then, per id, the
   prompt's line count and the tool calls the transcript shows, or `not
   read` and why. A read is valid only when every tool call the transcript
   shows is a Read of that id's own prompt path, and together those calls
   cover every line of the prompt. A reply from a read that is not valid is
   not saved as an answer, so `score.R` reports that id as `missing`. No
   API calls and no keys.

   Holding a Read tool weakens blindness slightly: the reader could read
   something besides its prompt. That is accepted because the alternative,
   retyping the prompt into the spawn call, cannot be checked byte for byte
   and fails on very long lines; the check that every call is a Read of the
   reader's own prompt catches a reader that reads anything else.

5. Score:

   ```sh
   Rscript dev/blind-reader/score.R --sample <store>/sample \
     --answers <store>/answers/stage1 --out <store>/score/stage1 \
     --stage stage1
   ```

   An answer passes the format check only when it is exactly the format in
   `prompt.md`: a `decision:` line with one of `allow`, `disallow`,
   `unspecified` or `cannot_tell`, an em dash and a `§` section; one to
   three `issue:` lines (`L<n> "<quote>" — <at most 15 words>`) or
   `issue: none`; a `surprise:` line of at most 15 words; no other lines,
   no blank line, no fence, no NUL byte, LF line ends. A missing file fails
   as `missing`; a broken answer never stops the others being scored.
   `score.tsv`
   has one row per answer: the format result, the reader's decision and
   section, the google, bing and yandex readings (`n/a` where a bounded
   backend does not take the token), the catalog's RFC 9309 decision on an
   anchor, the validator's lines and codes, and `read_reasons`, why the row
   needs a person (`format`, `google_differs`, `rfc_differs`,
   `issue_unflagged`, `misquote`, `surprise`). `issues.tsv` has one row per
   issue line: whether the quote matches the file's line and which
   validator codes that line has.

6. Tune. Read every stage-1 answer beside its score row, change
   `prompt.md` (commit the change; the reasons go in the tracker,
   corpus-free), then render, read and score stage 2 the same way with
   `--stage stage2` and `.../stage2` directories.

7. Classify each candidate in one line on the epic, resolved against the
   RFC text or observed engine behavior before it is called a finding.

The RFC 9309 passages in `prompt.md` are quoted word for word from the RFC;
only the sentence on the case of record names is not RFC 9309 text, and the
prompt says so.

## Changes after stage 1

- The surprise question drew remarks on group selection working as RFC
  9309 describes (a crawler falling back to the `*` group, or its own group
  overriding `*`) on nearly every file, which buries real surprises. The
  prompt now asks only for something a validator should warn about that the
  issue lines do not cover, names group selection, the `*` fallback and
  longest-match precedence as not surprises, and asks for `surprise: none`
  then.
- A few answers broke the format: a surprise line over the word limit and a
  decision line citing three sections. The prompt now states the 15-word
  limit next to the format block and says plainly that the decision cites at
  most two sections. The answer format and what `score.R` checks are
  unchanged.
- The stage-1 prompts reached the readers by being retyped into each spawn
  call, which cannot be checked byte for byte and fails on very long lines.
  Each reader now reads its own rendered prompt file with the Read tool
  (step 4), paging when the prompt runs past the tool's per-call line
  limit, and cites the prompt's own line numbers, not the tool's margin
  numbers. A read is valid only when every tool call is a Read of that
  prompt and together they cover it, and a prompt with a line the Read tool
  would truncate is recorded as not read. Since
  the reader now holds a tool, the prompt's opening says to use no tool
  from there on instead of saying it has none.
- Answers are kept per stage, under `answers/<stage>/`.
