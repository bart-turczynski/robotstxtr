# Security Policy

## Supported versions

Security fixes are made against the latest released version of `robotstxtr`
and the development version on `main`. Releases are published on r-universe
(<https://bart-turczynski.r-universe.dev/robotstxtr>), and on CRAN once it is
accepted there. Please upgrade to the most recent release before reporting.

| Version                        | Supported          |
| ------------------------------ | ------------------ |
| Latest release                 | :white_check_mark: |
| Development version (`main`)   | :white_check_mark: |
| Older releases                 | :x:                |

## Reporting a vulnerability

**Please do not report security vulnerabilities through public issues.**

Preferred channel — **email the maintainer at bartek@turczynski.pl.**

Alternatively, open a **confidential issue** on the GitLab project:

1. Go to [Issues](https://gitlab.com/bart-turczynski/robotstxtr/-/work_items) and click
   **New issue**.
2. Tick **This issue is confidential** before submitting.

A confidential issue is visible only to you, its assignees and the project
members whose role lets them see confidential issues.

Email is listed first deliberately: it works whether or not you have a GitLab
account, and it is the channel the maintainer monitors.

Do not include secrets, credentials, tokens, or private customer data in a
report, an issue, a merge request or a log.

## What to expect

- We aim to acknowledge a report within **7 days**.
- We will investigate, work on a fix, and coordinate disclosure with you.
- We are happy to credit reporters in the release notes unless you prefer to
  remain anonymous.

## Scope

`robotstxtr` is an R package that evaluates `robots.txt` crawl policy with a
vendored C++ snapshot of Google's open-source `robots.txt` matcher, plus
vendored Bing and Yandex compatibility matchers. It fetches `robots.txt` under
a deterministic, conservative `httr2` policy and handles no credentials. Its
security surface is the safe handling of untrusted `robots.txt` bodies and URLs
passed to the parsing, matching, fetching and validation functions, including
memory safety in the vendored C++ matchers as compiled and exercised through
this package's bindings. Vulnerabilities in dependencies (`httr2`, `rurl`)
belong upstream.
