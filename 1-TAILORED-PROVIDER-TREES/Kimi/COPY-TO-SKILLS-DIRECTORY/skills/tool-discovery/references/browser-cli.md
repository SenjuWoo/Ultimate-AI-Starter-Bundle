# Browser CLI fallback

Use an already available native browser tool first. Otherwise the bundle
installs Microsoft's `playwright-cli` 0.1.20 without an MCP registration.
It is an alternative for agents with shell access, not a replacement for
Playwright MCP's interactive tool interface.

Set `NO_UPDATE_NOTIFIER=1` for this process and run `playwright-cli --help`.
Use a unique task session; the default profile is non-persistent. Never attach
to or load a personal authenticated browser profile without authorization.

```text
playwright-cli -s=my-task open https://example.com
playwright-cli -s=my-task eval "() => document.title" --raw
playwright-cli -s=my-task snapshot
playwright-cli -s=my-task close
```

Snapshots return a file link. Read/search only the portion needed, then use
the observed refs for click/fill. Reacquire refs after navigation. Screenshots
are useful for visual QA; DOM success alone does not prove presentation.
Use `--help <command>` for argument details. Never invent a selector/ref.

Close only your own named session, never `close-all` or `kill-all`. Do not run
`install --skills`: canonical skills and the bundle installer remain the
provider directory writers. Browser downloads are separate and optional;
check for an installed supported browser before fetching another.

The pinned package uses Playwright 1.63.0-alpha-2026-08-31. Windows smoke testing
proved navigation, title evaluation and session close. No standing MCP schema
is added; actual end-to-end token savings and broad site coverage are unmeasured.

[Upstream documentation](https://github.com/microsoft/playwright-cli)
