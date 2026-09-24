# check-bugreports v1
"""BugReports / tracker-link split gate.

Ported from pagerankr's `scripts/check-bugreports.py` (SEOR-ocbtrrnl) and
adapted to robotstxtr's file set; the reasoning below is unchanged.

WHY THIS EXISTS. CRAN runs two checks over a GitLab `BugReports:` URL and
they contradict each other. `tools::check_url_db()` actually fetches the
address; GitLab moved issue reporting to a new work-items UI, so the classic
`.../-/issues` path 404s for a signed-out client (the exact client CRAN's
check uses) while `.../-/work_items` serves 200. `tools:::.check_package_CRAN_incoming()`
never fetches anything -- it is a hardcoded string test on the path
(`!grepl("/issues(/new)?/?$", z$path)`) that only accepts the `/-/issues`
form and flags anything else, `/-/work_items` included, with a "should
likely be .../issues" NOTE. No URL satisfies both.

Both complaints are NOTEs, neither blocks acceptance, and this is not
hypothetical: the first pslr 1.2.1 upload declared `/-/work_items` in
`DESCRIPTION` and was ARCHIVED at the CRAN pretest on 2026-09-12; the
resubmission with `/-/issues` was accepted (pslr commit 509c776). So the
field the incoming check string-tests keeps the CRAN-safe form, and every
file a HUMAN actually clicks through -- which the incoming check never reads
-- points at the address that is not a dead link. See SEOR-ocbtrrnl.

`man/robotstxtr-package.Rd`'s "Report bugs at" link, when there is one, is
not a separate decision: roxygen2's `"_PACKAGE"` sentinel generates that
"Useful links" section verbatim from `DESCRIPTION`'s own `URL:`/`BugReports:`
fields. It therefore MUST agree with `DESCRIPTION`, never with the
human-facing files, or `devtools::document()` was not re-run. In robotstxtr
today the page carries NO such line: `R/robotstxtr-package.R` writes its own
`@seealso`, and roxygen2 then omits the generated links. An absent line is
therefore accepted; a present one must match.

WHAT IT CHECKS.

1. `DESCRIPTION`'s `BugReports:` is the CRAN-incoming-safe form: it ends in
   `/-/issues`, optionally `/new`, optionally a trailing slash, and does not
   name `/-/work_items`.
2. `man/robotstxtr-package.Rd`'s "Report bugs at" link, if present, is
   IDENTICAL to `DESCRIPTION`'s `BugReports:` value.
3. Every HUMAN-FACING file that must carry the tracker link names
   `/-/work_items` for it (REQUIRED_FILES: codemeta.json's `"issueTracker"`).
4. No human-facing file still carries a `/-/issues` link (HUMAN_FACING_FILES
   plus the vignettes and the .gitlab/ templates). SECURITY.md, the READMEs
   and the rest name no tracker at all today, which is fine; the check is
   that a link added later is the right one.

WHAT IT DOES NOT CHECK, ON PURPOSE.

* `NEWS.md` and `cran-comments.md` are point-in-time records of what was
  actually announced or submitted (AGENTS.md: "spec and code disagree ->
  code and ADR win" is about specs, but the same reasoning applies to a
  record of a past submission). A historical bullet or paragraph that quotes
  an old `/-/issues` form, including one arguing FOR that form, is not
  drift, so both files are exempt. So is `design/`, which holds dated
  audits and the tracker snapshot.
* `codemeta.json`'s `"issueTracker"` is deliberately NOT compared against
  `DESCRIPTION`'s `BugReports:` for equality -- `scripts/check-citation.py`
  does not enforce that either, and the two are SUPPOSED to differ (that is
  the whole point of the split).
* Nothing here touches the network. Whether a URL currently resolves is a
  fact about the rest of the world; `R CMD check --as-cran` already fetches
  declared URLs, and a network call in a pre-push gate fails on a train.

Stdlib only, so it runs in any bare Python CI image, same shape as
`scripts/check-citation.py` (which this file does not import from or
modify -- that script is owned by a separate, fleet-wide dedup decision).

    python3 scripts/check-bugreports.py              # exit 1 on drift
    python3 scripts/check-bugreports.py --self-test  # positive/negative cases
"""

from __future__ import annotations

import re
import sys
import tempfile
from pathlib import Path

PACKAGE = "robotstxtr"

ISSUES_RE = re.compile(
    r"https://gitlab\.com/[\w.-]+/[\w.-]+/-/issues(?:/new)?/?(?=[\s)\]\"'>]|$)"
)
WORK_ITEMS_RE = re.compile(r"https://gitlab\.com/[\w.-]+/[\w.-]+/-/work_items\b")

# CRAN-incoming-safe shape: DESCRIPTION's BugReports: value, in full, must
# match this (mirrors tools:::.check_package_CRAN_incoming()'s own regex).
BUGREPORTS_SAFE_RE = re.compile(r"^https://gitlab\.com/[\w.-]+/[\w.-]+/-/issues(?:/new)?/?$")

# Human-facing files that must name the /-/work_items tracker link.
REQUIRED_FILES = ("codemeta.json",)

# Files a human clicks through; the incoming check never reads any of them.
# None may carry a /-/issues link. Missing files are skipped.
HUMAN_FACING_FILES = (
    "codemeta.json",
    "SECURITY.md",
    "SECURITY-INSIGHTS.yml",
    "README.Rmd",
    "README.md",
    "CONTRIBUTING.md",
    "CITATION.cff",
    ".zenodo.json",
    "_pkgdown.yml",
    "inst/CITATION",
)
HUMAN_FACING_GLOBS = ("vignettes/*.Rmd", ".gitlab/**/*.md")

# Point-in-time records of what was actually submitted/announced -- exempt.
EXEMPT_FILES = ("NEWS.md", "cran-comments.md")


def read_dcf(path: Path) -> dict[str, str]:
    """Flat DCF fields, joining RFC-822 style continuation lines."""
    fields: dict[str, str] = {}
    key: str | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            key = None
            continue
        if line[0].isspace():
            if key is not None:
                fields[key] += " " + line.strip()
            continue
        name, sep, value = line.partition(":")
        if not sep:
            key = None
            continue
        key = name.strip()
        fields[key] = value.strip()
    return fields


def human_facing_paths(root: Path) -> list[Path]:
    paths = [root / name for name in HUMAN_FACING_FILES]
    for pattern in HUMAN_FACING_GLOBS:
        paths.extend(sorted(root.glob(pattern)))
    return [p for p in paths if p.is_file() and p.name not in EXEMPT_FILES]


def check_repo(root: Path) -> list[str]:
    """Findings for one repository; empty when the split is intact."""
    errors: list[str] = []

    description = root / "DESCRIPTION"
    if not description.exists():
        return ["DESCRIPTION is missing; nothing to check the BugReports split against"]
    desc = read_dcf(description)
    bugreports = desc.get("BugReports", "")
    if not bugreports:
        return []  # No BugReports: field is a separate question, not drift here.

    if not BUGREPORTS_SAFE_RE.match(bugreports):
        errors.append(
            f"DESCRIPTION BugReports: is '{bugreports}', which is not the "
            f"CRAN-incoming-safe /-/issues form (optionally /new, optionally "
            f"a trailing slash). tools:::.check_package_CRAN_incoming() string-"
            f"tests this field and archived the first pslr 1.2.1 upload for "
            f"declaring /-/work_items here (pslr commit 509c776)."
        )

    man_name = f"man/{PACKAGE}-package.Rd"
    man_path = root / man_name
    if man_path.exists():
        text = man_path.read_text(encoding="utf-8")
        match = re.search(r"Report bugs at \\url\{([^}]*)\}", text)
        # No line at all is accepted: a hand-written @seealso makes roxygen2
        # omit the generated "Useful links" section (see the docstring).
        if match is not None and match.group(1) != bugreports:
            errors.append(
                f"{man_name}'s 'Report bugs at' link is "
                f"'{match.group(1)}', but DESCRIPTION's BugReports: is "
                f"'{bugreports}'. This link is generated verbatim from "
                f"DESCRIPTION by roxygen2's \"_PACKAGE\" sentinel -- re-run "
                f"devtools::document(), do not hand-edit the .Rd."
            )

    for path in human_facing_paths(root):
        name = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8")
        if ISSUES_RE.search(text):
            errors.append(
                f"{name} still links a /-/issues form, which 404s for a "
                f"signed-out client. Repoint it at /-/work_items."
            )
        if name in REQUIRED_FILES and not WORK_ITEMS_RE.search(text):
            errors.append(
                f"{name} does not name the project's /-/work_items tracker "
                f"link anywhere -- expected the human-facing tracker URL."
            )

    for name in REQUIRED_FILES:
        if not (root / name).is_file():
            errors.append(f"{name} is missing; it must carry the /-/work_items tracker link.")

    return errors


# --- self-test (positive + negative coverage, executable) --------------------


def _fixture(directory: Path, bugreports: str, man_url: str | None, human: dict[str, str]) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "DESCRIPTION").write_text(
        f"Package: fixture\nVersion: 0.1.0\nBugReports: {bugreports}\n",
        encoding="utf-8",
    )
    man_dir = directory / "man"
    man_dir.mkdir(parents=True, exist_ok=True)
    seealso = "" if man_url is None else f"Report bugs at \\url{{{man_url}}}\n"
    (man_dir / f"{PACKAGE}-package.Rd").write_text(
        f"\\seealso{{\n{seealso}}}\n", encoding="utf-8"
    )
    for name, content in human.items():
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    return directory


def self_test() -> None:
    org = "https://gitlab.com/bart-turczynski/fixture"
    issues = f"{org}/-/issues"
    work_items = f"{org}/-/work_items"

    def run(tag: str, **kwargs) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            return check_repo(_fixture(Path(tmp) / tag, **kwargs))

    def expect_clean(tag: str, **kwargs) -> None:
        found = run(tag, **kwargs)
        if found:
            raise SystemExit(f"self-test FAILED ({tag}): {found}")

    def expect_flagged(tag: str, needle: str, **kwargs) -> None:
        found = run(tag, **kwargs)
        if not any(needle in f for f in found):
            raise SystemExit(f"self-test FAILED ({tag}): expected {needle!r}, got {found}")

    # robotstxtr's real shape: only codemeta.json names the tracker; the
    # other human-facing files carry no tracker link at all.
    human_target = {
        "codemeta.json": f'{{"issueTracker": "{work_items}"}}',
        "SECURITY.md": "Report security issues privately to the project maintainer.",
        "README.Rmd": "robotstxtr is not on CRAN yet.",
        "README.md": "robotstxtr is not on CRAN yet.",
        "NEWS.md": f"* `BugReports:` is now `{issues}` (historical).",
    }

    # POSITIVE: the intended split, man page without generated links (the
    # hand-written @seealso case) and an exempt NEWS.md quoting /-/issues.
    expect_clean("split-intact", bugreports=issues, man_url=None, human=human_target)

    # POSITIVE: man page WITH a generated link that mirrors DESCRIPTION.
    expect_clean("man-mirrors", bugreports=issues, man_url=issues, human=human_target)

    # NEGATIVE: DESCRIPTION regressed to /-/work_items (the pslr pretest
    # archival case) even though it satisfies the URL-form regex.
    expect_flagged(
        "description-regressed",
        "not the CRAN-incoming-safe",
        bugreports=work_items,
        man_url=None,
        human=human_target,
    )

    # NEGATIVE: man page not regenerated after a hypothetical DESCRIPTION edit.
    expect_flagged(
        "man-stale",
        "generated verbatim from",
        bugreports=issues,
        man_url=work_items,
        human=human_target,
    )

    # NEGATIVE: codemeta.json reverted to /-/issues (the "prove it bites"
    # case this gate exists for).
    reverted = dict(human_target)
    reverted["codemeta.json"] = f'{{"issueTracker": "{issues}"}}'
    expect_flagged("codemeta-reverted", "still links a /-/issues form", bugreports=issues, man_url=None, human=reverted)

    # NEGATIVE: a README gains a /-/issues/new link.
    readme = dict(human_target)
    readme["README.md"] = f"Report bugs at <{issues}/new>."
    expect_flagged("readme-issues", "README.md still links", bugreports=issues, man_url=None, human=readme)

    # NEGATIVE: a vignette (glob-matched file) gains a /-/issues link.
    vignette = dict(human_target)
    vignette["vignettes/intro.Rmd"] = f"File a report at [the tracker]({issues})."
    expect_flagged("vignette-issues", "vignettes/intro.Rmd still links", bugreports=issues, man_url=None, human=vignette)

    # NEGATIVE: codemeta.json never names /-/work_items at all.
    missing = dict(human_target)
    missing["codemeta.json"] = '{"name": "fixture"}'
    expect_flagged(
        "codemeta-missing-work-items",
        "does not name the project's /-/work_items",
        bugreports=issues,
        man_url=None,
        human=missing,
    )

    print("check-bugreports self-test: PASS (2 positive + 6 negative cases)")


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        self_test()
        return 0

    root = Path(__file__).resolve().parent.parent
    errors = check_repo(root)
    if errors:
        print("check-bugreports failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print("check-bugreports: BugReports split (DESCRIPTION vs human-facing files) is intact.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
