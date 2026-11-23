#!/usr/bin/env python3
"""Refuse a tracker snapshot that names the private study corpus.

    python3 data-raw/snapshot-tracker-guard.py <snapshot-file>

data-raw/snapshot-tracker.sh runs this on its output before it replaces
design/tracker-snapshot.md (ROBO-hgbqedwt). The corpus belongs to an embargoed
study (ROBO-qbxsydcf): its hosts and its files' hashes never go into a commit.
Tracker comments are copied verbatim, so a comment that names a study file
would otherwise reach git on the next regeneration.

Inputs, all read at run time and none of them in git:

- ROBOTSTXTR_CORPUS: the corpus directory dev/corpus/ reads, one directory per
  host (`<host>` or `<host>~<id>`), each holding a robots.rds. Required.
- ROBOTSTXTR_SNAPSHOT_PUBLIC_HOSTS: optional path to a list of hosts the
  snapshot may name although the corpus holds them: sites the maintainer
  fetched live, or a paper names, and an issue cites as a public example. One
  host per line, `#` comments. It lives beside the corpus, not in git, since
  the list itself would say which hosts the study holds.

It refuses, printing line numbers and kinds only, never the matched text,
when the snapshot holds:

- a study host, or any subdomain of one: every dot-separated run of letters,
  digits and hyphens is tried with each of its parent domains;
- a run of 12 or more hex digits that starts a study file's SHA-256, taken
  both over each stored file and over each decoded robots.rds body.

A public host, its subdomains and the hashes of its files are exempt, and so
is a hash that a public host's file shares with study hosts (a platform's
shared robots.txt): a live fetch of the public file cites that hash.

It refuses when ROBOTSTXTR_CORPUS is unset or holds no host directory with a
robots.rds. On a machine without the corpus, SNAPSHOT_SKIP_CORPUS_CHECK=1
writes the snapshot unchecked, knowingly.

Reading the corpus takes a few minutes, so the index (hosts and hashes) is
cached under ~/.cache/robotstxtr-snapshot-guard/, outside every repository,
and rebuilt when the corpus directory changes.

It does not catch corpus figures (counts, shares) or a corpus file's lines
quoted without its host or hash: tracker text keeps those out by the privacy
rule.
"""

import hashlib
import json
import os
import re
import subprocess
import sys

TOKEN = re.compile(r"[a-z0-9.-]+", re.I)
HEXRUN = re.compile(r"[0-9a-f]{12,}", re.I)
CACHE = os.path.expanduser("~/.cache/robotstxtr-snapshot-guard")

# Decoded bodies: robots.rds holds the body as a raw vector, so its hash is
# not the hash of any file on disk. Prints "<dir>\t<sha256>" per body.
R_BODIES = r"""
root <- commandArgs(TRUE)[1]
for (d in list.dirs(root, recursive = FALSE, full.names = FALSE)) {
  f <- file.path(root, d, "robots.rds")
  if (!file.exists(f)) next
  b <- tryCatch(readRDS(f)$body, error = function(e) NULL)
  if (is.raw(b)) cat(d, "\t", digest::digest(b, "sha256", serialize = FALSE),
                     "\n", sep = "")
}
"""


def host_of(dirname):
    host = dirname.split("~", 1)[0].lower().rstrip(".")
    return host[4:] if host.startswith("www.") else host


def build_index(root):
    files = {}
    for entry in os.scandir(root):
        if not entry.is_dir():
            continue
        hashes = files.setdefault(entry.name, [])
        for f in os.scandir(entry.path):
            if f.is_file():
                with open(f.path, "rb") as fh:
                    hashes.append(hashlib.sha256(fh.read()).hexdigest())
    out = subprocess.run(["Rscript", "-e", R_BODIES, root],
                         capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        d, _, h = line.partition("\t")
        if d in files and h:
            files[d].append(h.strip())
    return files


def load_index(root):
    st = os.stat(root)
    key = hashlib.sha1(os.path.abspath(root).encode()).hexdigest()[:16]
    path = os.path.join(CACHE, f"index-{key}.json")
    stamp = [st.st_mtime_ns, len(os.listdir(root))]
    try:
        with open(path, encoding="utf-8") as f:
            cached = json.load(f)
        if cached.get("stamp") == stamp:
            return cached["files"]
    except (OSError, ValueError):
        pass
    files = build_index(root)
    os.makedirs(CACHE, mode=0o700, exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        json.dump({"stamp": stamp, "files": files}, f)
    os.replace(path + ".tmp", path)
    return files


def read_public():
    path = os.environ.get("ROBOTSTXTR_SNAPSHOT_PUBLIC_HOSTS", "")
    out = set()
    if path:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if line:
                    out.add(host_of(line))
    return out


def is_corpus(root):
    with os.scandir(root) as it:
        return any(e.is_dir() and
                   os.path.isfile(os.path.join(e.path, "robots.rds"))
                   for e in it)


def host_hit(token, hosts, public):
    labels = [x for x in token.lower().strip(".-").split(".") if x]
    for i in range(len(labels) - 1):
        cand = ".".join(labels[i:])
        if cand in public:
            return False
        if cand in hosts:
            return True
    return False


def main(argv):
    if len(argv) != 2:
        print("usage: python3 data-raw/snapshot-tracker-guard.py <file>",
              file=sys.stderr)
        return 2
    if os.environ.get("SNAPSHOT_SKIP_CORPUS_CHECK") == "1":
        print("guard: SNAPSHOT_SKIP_CORPUS_CHECK=1, snapshot not checked "
              "against the corpus", file=sys.stderr)
        return 0
    root = os.environ.get("ROBOTSTXTR_CORPUS", "")
    # Errors below are reported without paths: a corpus path names a host.
    try:
        if not root or not os.path.isdir(root) or not is_corpus(root):
            print("guard: ROBOTSTXTR_CORPUS is unset or holds no host "
                  "directory with a robots.rds, so the snapshot cannot be "
                  "checked. Set it to the corpus directory, or set "
                  "SNAPSHOT_SKIP_CORPUS_CHECK=1 on a machine without the "
                  "corpus.", file=sys.stderr)
            return 1
        files = load_index(root)
        public = read_public()
    except (OSError, subprocess.CalledProcessError, ValueError) as e:
        print(f"guard: could not read the corpus or the public host list "
              f"({type(e).__name__}); snapshot refused", file=sys.stderr)
        return 1
    hosts = {host_of(d) for d in files}
    shared = {h for d, hs in files.items() if host_of(d) in public for h in hs}
    study = {h for d, hs in files.items() if host_of(d) not in public
             for h in hs} - shared
    prefixes = {h[:12] for h in study}
    found = []
    with open(argv[1], encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            for m in TOKEN.finditer(line):
                if "." in m.group(0) and host_hit(m.group(0), hosts, public):
                    found.append((n, "study host"))
            for m in HEXRUN.finditer(line):
                run = m.group(0).lower()
                if run[:12] in prefixes and any(h.startswith(run)
                                                for h in study):
                    found.append((n, "hash of a corpus file"))
    if found:
        for n, kind in found:
            print(f"guard: line {n}: {kind}", file=sys.stderr)
        print(f"guard: {len(found)} corpus reference(s); scrub the tracker "
              "text they come from (fp comment update / fp issue update), "
              "or list a live-fetched public host in the file "
              "ROBOTSTXTR_SNAPSHOT_PUBLIC_HOSTS names", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
