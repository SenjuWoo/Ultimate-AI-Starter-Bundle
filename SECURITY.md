# Security Policy

## Reporting a Vulnerability

Report security issues privately through [GitHub private vulnerability reporting](https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/security/advisories/new).

Do not open a public issue for an unfixed vulnerability, and do not include a live credential in an issue, pull request, or commit.

You'll get a response once the report is triaged, and credit if you want it.

## Supported versions

The default branch and the latest published release are supported. Older releases are not patched in place.

## Scanner results

A Dependabot, code-scanning, or secret-scanning finding is fixed at the cause, then checked again. It is not dismissed to clear a dashboard. A secret-scanning result is rotated. The secret itself is not copied into a commit, issue, or log. Code quality that returns 403 or 404 on a repository is unavailable there; it is not turned on to clear the tab.

## Personal data boundary

This repository is a public artifact. These classes must never be committed,
and `.gitignore` blocks them by pattern:

- AI chat exports and history (Claude/ChatGPT exports, `conversations*.json`,
  `chat.html`, `memories/`, per-account `users.json`, `login_history.json`).
- Machine-private notes: anything under `LOCAL-ONLY/`, and `*.local.md` /
  `*.local.json`. Machine-specific detail belongs there, not in shipped files.
- Real names, account names, personal e-mail addresses, credentials, and
  absolute home paths of any machine (`C:\Users\<name>` style).

`TESTS/test_privacy_boundary.py` enforces this on every tracked file and runs
in CI. If something personal still lands: remove it, purge it from history
(`git filter-repo`), and rotate anything that was secret. Example paths that
only illustrate an author's layout (drive roots, sample folders) are
documentation, not personal data — but never a home directory with a real
account name.
