# Windows setup and recovery

Run `START-HERE.bat` from the bundle folder. Setup detects installed supported
apps and configures just those providers. For an explicit selection, including
a single provider, use:

```powershell
.\START-HERE.bat -Providers Claude,Codex
.\START-HERE.bat -Providers Codex
```

Supported choices are Claude, Codex, Grok, Kimi, Hermes and Antigravity. If no
app is found, setup stops with selection guidance before runtime/provider
installation. `-AllProviders` deliberately selects all six. Antigravity itself
requires installation from its vendor; the bundle does not guess a desktop
installer. Desktop detection and runnable CLI detection are separate checks.

Codex's standalone installer URL returned HTTP 404 in the reported fresh-PC
failure. A missing CLI now uses `npm.cmd install -g @openai/codex`, an
[official Windows installation method](https://developers.openai.com/codex/enterprise/windows-deployment).
Existing runnable CLIs are reused. Successful local startup is not proof of
OAuth/API authentication or a successful model request.

Git for Windows is a bundle prerequisite even for a solo Codex selection:
native plugin setup uses Git sources and plugin hooks need its Bash/sh shells.
This is separate from installing additional AI providers.

## Personal files and settings

`-WorkspaceRoot` fills missing AGENTS.md, CLAUDE.md and project-template files;
existing files and type conflicts are preserved. Source/destination junctions
and symlinks are refused to prevent writing outside the requested workspace.
Default cleanup is a preview. The standalone cleanup script's `-Apply` is an
explicit deletion operation; inspect its output and backups first.

Fresh Grok settings retain vendor permission prompts. The installer does not
change existing user permission modes to match its starter template.

Global preferences belong in the provider's user home; project conventions
belong in that project's instruction file. Codex supports user-wide
[AGENTS.md guidance](https://developers.openai.com/codex/guides/agents-md).
Keep machine paths/account details outside this public source tree.

GitHub's connected app and local `gh` authentication are separate. For durable
local access, sign in once with `gh auth login --hostname github.com
--git-protocol https --web`, then `gh auth setup-git`. Verify with
`gh auth status`. Preserve an existing Git identity; a GitHub noreply address
can be used when initially configuring a new identity. Never export connector
tokens into Git config or scripts.

## Diagnostics and checks

Installer diagnostics are saved under
`%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\logs`: `INSTALL-LAST.log`,
`INSTALL-FAILED.txt`, and timestamped transcript/details files. Preserve a failed
run before retrying. To diagnose the current installation explicitly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File TOOLS\Ensure-Provider-CLIs.ps1 -Providers Claude,Codex -CheckOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File TOOLS\Test-Installed-State.ps1 -Providers Claude,Codex
```

Development gates are `TESTS\Test-Pack.ps1` and
`python TESTS\test_release_contract.py`, plus manifest and version checks in
`.github\scripts`. Test-Pack needs the pinned MCP SDK and PyYAML dependencies
listed in CI; use a disposable test environment instead of the shared base.
Pass its interpreter through `TESTS\Test-Pack.ps1 -TestPython
<venv>\Scripts\python.exe`; leave `UABS_PYTHON` pointing to the real shared base.
Provider fixtures exercise all 63 nonempty selections and Windows paths;
they do not certify live installations/inference for providers absent from the
test machine. Record actual live checks and remaining gaps in STATE.md.

Catalog freshness is available through
`python TOOLS\audit_catalog_versions.py --json`. A newer version behind a
compatibility/security hold is a candidate requiring its own validation, not
permission to bypass the hold. Local source fixes do not update published
release archives until a new release passes its publication gates.
