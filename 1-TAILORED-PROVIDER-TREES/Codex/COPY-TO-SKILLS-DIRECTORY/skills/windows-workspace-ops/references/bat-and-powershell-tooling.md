# Windows launcher and release checks

Adapted from the operator's Hermes notes; keep environment-specific observations
separate from universal guarantees. Test the launcher extracted from the archive,
not just the working source tree.

## Batch files

- Quote paths and prefer CRLF for shipped `.bat`/`.cmd` files. Exercise both
  the argument-dispatch path and an interactive menu; stdin EOF is not evidence
  that a real user can navigate the menu.
- Parentheses and other cmd metacharacters in a parenthesized block need
  escaping. Keep dispatch simple; percent variables in a block are expanded
  before its commands run, including `%errorlevel%`.
- Return the child exit code on a separate line outside the block, or use
  a label/subroutine. Check that a failing PowerShell child makes the batch
  caller fail too. Never test only the success path.
- For native calls from Git Bash, verify argument boundaries with paths
  containing spaces and `!`. A tiny wrapper batch file can isolate quoting
  problems; do not diagnose every quoting failure as a broken target program.

## Windows PowerShell 5.1

- Capture `$PSScriptRoot` at script scope before functions need it. For a
  parameter default that depends on it, resolve after `param(...)`.
- BOM-less UTF-8 scripts can be decoded as ANSI. Use ASCII script syntax or
  UTF-8 with BOM where supported; read UTF-8 data with `[IO.File]::ReadAllText`.
- `powershell.exe -File` does not turn a comma-joined argument into an array.
  Split it deliberately only when that is the parameter's documented format.
- Report missing input roots instead of claiming a successful empty scan.
- Test an actual temporary fixture through validation, apply, and restoration
  when the tool can change user files. Resolve destructive targets first.

## Verification and publication

- Extract a release archive and exercise its real entry point. Verify its
  dependencies and data files are present in that archive.
- Native Windows Python needs Windows paths, not MSYS `/z/...` paths; convert
  explicitly or use relative names from the intended working directory.
- Match the exact output when parsing test results. Check process exit codes
  as well; empty output must never count as a pass.
- GNU `sha256sum` escapes filenames containing backslashes. Use its `-c`
  verification or hash stdin instead of stripping a filename-bearing line.
- Regenerate manifests after final edits. Push, record the exact SHA, wait
  for all required CI checks, then build/tag/publish that SHA when authorized.
- Fix release-link races in documentation checks, not by publishing before CI.
- Prefer a new patch for a faulty published artifact. Deleting releases or
  rewriting published tags needs explicit permission even with zero downloads.
- Download the public assets and compare nonempty sizes and SHA-256 values
  against the build and checksum records; two missing values are not a match.
