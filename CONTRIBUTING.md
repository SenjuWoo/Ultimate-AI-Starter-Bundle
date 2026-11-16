# Contributing

Thanks for taking the time to contribute! This is a personal, hobby-maintained project, so please be patient with response times.

## Ground rules

- Open an issue first for anything non-trivial — a feature, a refactor, or a bug you plan to fix — so we can agree on the approach before you write a lot of code.
- Keep changes small and focused. One logical change per pull request makes review much easier.
- Match the existing style of the code around you (formatting, naming, structure).

## Bugs and features

1. Search the issues to make sure it hasn't already been reported.
2. Open an issue describing the problem or idea clearly, including how to reproduce bugs.
3. If you want to implement it, say so in the issue and link your pull request to it.

## Pull requests

1. Fork the repo (or push a branch if you have write access).
2. Make your change.
3. If the project has tests or CI, make sure they pass.
4. Open a pull request with a clear title and a description of what and why.
5. Keep the PR scoped; reviewers will ask for changes if something is unclear.

## Security issues

Do **not** report security problems in a public issue. Report them privately through
[GitHub private vulnerability reporting](https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/security/advisories/new), and never put a live
credential in an issue, pull request or commit. The default branch and the latest
release are supported; older releases are not patched in place. A Dependabot,
code-scanning or secret-scanning finding is fixed at the cause, never dismissed; a
leaked secret is rotated.

## Personal data boundary

This repository is public. Never commit AI chat exports or history, account
records, anything under `LOCAL-ONLY/` or named `*.local.md` / `*.local.json`, real
names, personal e-mail addresses, credentials, or a home path with a real account
name. `.gitignore` blocks these classes and `TESTS/test_privacy_boundary.py`
enforces it in CI. If something personal lands: remove it, purge it from history
and rotate anything secret.

By contributing, you agree that your contributions are licensed under the same license as this project.
