---
name: codebase-memory
description: Use when exploring a codebase graph, tracing callers/dependencies, finding structure or dead code, or indexing/re-indexing codebase-memory.
---

# Codebase Memory — Knowledge Graph Tools

Use the graph for structural questions when its root and indexed source are
current. Use text search for exact text and unsupported languages. Savings
depend on the query and index coverage; do not infer a token bill from tool size.

**Two halves to this skill.** Querying (below) is easy. **Indexing is where it goes
wrong** — a careless `index_repository` on a Skyrim mod tree produces a 200,000-node
graph of animation files that costs tokens on every query and answers nothing. Read
[references/indexing-and-install.md](references/indexing-and-install.md) before your
first `index_repository` on any repo.

## Quick Decision Matrix

| Question | Tool call |
|----------|----------|
| Who calls X? | `trace_path(direction="inbound")` |
| What does X call? | `trace_path(direction="outbound")` |
| Full call context | `trace_path(direction="both")` |
| Find by name pattern | `search_graph(name_pattern="...")` |
| Dead code | `search_graph(max_degree=0, exclude_entry_points=true)` |
| Cross-service edges | `query_graph` with Cypher |
| Impact of local changes | `detect_changes()` |
| Did the graph cover the source tree? | `check_index_coverage()` |
| Risk-classified trace | `trace_path(risk_labels=true)` |
| Text search | `search_code` or Grep |

## Exploration Workflow
1. `list_projects` — check if project is indexed and its recorded root still exists
2. `get_graph_schema` — understand node/edge types
3. `search_graph(label="Function", name_pattern=".*Pattern.*")` — find code
4. `get_code_snippet(qualified_name="project.path.FuncName")` — read source

For a moved project, verify its owner record and existing `.cbmignore`, back up
the local graph store with a consistent SQLite backup, then re-index using the
same stable project name and the new root. Verify `list_projects` and a source
query afterwards. Check the returned project identity too: naming overrides can
interact with existing registrations. Do not delete the old graph first.
Exclude private recovery folders, personal configuration, caches and generated
provider copies as well as dependencies and assets. Prefer the owner's existing
ignore rules; the Skyrim-oriented scope generator is not a generic replacement.

## Tracing Workflow
1. `search_graph(name_pattern=".*FuncName.*")` — discover exact name
2. `trace_path(function_name="FuncName", direction="both", depth=3)` — trace
3. `detect_changes()` — map git diff to affected symbols

## Quality Analysis
- Dead code: `search_graph(max_degree=0, exclude_entry_points=true)`
- Highly connected code: `search_graph(min_degree=10, relationship="CALLS")`;
  inspect the returned in/out counts or trace the chosen node to distinguish callers
  from callees. Check the installed schema before supplying additional arguments.

## 17 MCP Tools
`index_repository`, `index_status`, `list_projects`, `delete_project`,
`search_graph`, `search_code`, `trace_path`, `detect_changes`,
`query_graph`, `get_graph_schema`, `get_code_snippet`, `get_file_outline`,
`get_architecture`, `check_index_coverage`, `compare_graphs`, `manage_adr`,
`ingest_traces`

Measured on 0.12.1 (2026-10-31): 17 tools, 20,814 schema bytes, about 5,204
schema tokens (bytes/4, not measured billing). The Hermes `code` profile adds
Serena when installed (3 tools, 4,225 bytes, ~1,056 tokens), so the combined
fixed surface is ~6,260. Use Claude/Grok/trusted Codex project scope or Hermes' native
`code` profile; do not register it globally just because the executable exists.

## First check: does the graph point at the current checkout?

`list_projects` returns each project's `root_path`. A moved or renamed repo
leaves a healthy-looking graph pointing at the old path — every query then
answers about a tree that no longer exists. Back up the store, verify the current
source owner, and refresh that stable project name before retiring any old graph.
Check the returned identity, root and source query; node counts alone prove little.
An installed binary package with JSON/XML documentation is not a source checkout.
It can produce a large graph while exposing no functions from the actual program.
Archive and retire such registrations when source ownership cannot be established;
the installed tool remains usable through its native CLI or MCP.

## The `cli` mode (v0.11.0+) — every tool is terminal-drivable

v0.11.0 (installed here 2026-10-12) added `codebase-memory-mcp cli [--quiet] [--json] <tool> [--flag value]`:
one tool runs locally, then the process exits — no MCP client needed. Use it for
maintenance an agent session cannot do:

```powershell
$cbm = "$env:LOCALAPPDATA\Programs\codebase-memory-mcp\codebase-memory-mcp.exe"
& $cbm cli --quiet list_projects                                # names + quoted paths
& $cbm cli --quiet delete_project --project <Name>              # immediate, unrecoverable
& $cbm cli --quiet index_repository --repo-path <root> --mode moderate --name <Name>
```

`index_repository` returns JSON: `nodes`, `edges`, `excluded.count`,
`not_indexed_files_count`, `status`, `logfile`. Sanity-check nodes vs files.
Supports `--args-file <json>` and stdin JSON for scripted batches.

**Purge discipline — what never deserves a graph:** personal chat/export
folders, roots that were moved or deleted, and unmodified third-party tool
installs (SSEEdit/DynDOLOD-class binaries). Tool SOURCE trees the operator
works on (houseCARL, Skyrim-Forge, Grabber) DO get indexed.
**One store, every session.** The index is not per chat or per folder: a project indexed once is
queryable from any session by name. In a new project, call `list_projects` first; the operator's own
tool repositories may already be there, so query them instead of re-reading their source.
A registry of indexed projects (the operator's `%USERPROFILE%\.uabs\profile\CODEBASE-MEMORY-PROJECTS.md`,
or a workspace `_AI-SHARED-MEMORY/locations/CODEBASE-MEMORY-PROJECTS.md`), where one exists,
is the authority on what is indexed and why — check it before deleting
anything (an over-eager purge of five registry-listed tools once had to be
reverted). Never index personal exports: the graph is queryable and has no
backup.

**One-shot ignore+index rework:**

```powershell
.\TOOLS\Setup-CodebaseMemory-Index.ps1 -Path <project-or-workspace> [-Recurse] -Apply -Index
```

Writes/refreshes every `.cbmignore` (snapshot rule + source-carrier exception),
then reindexes each project in scope and prints
nodes/edges/excluded/secs/status per project; exit code = number of failures.
Prefer it over hand-running `index_repository` — it encodes the policies below.

`-Apply` is non-destructive to hand-tuned rules: custom lines survive re-runs
(kept under a `# --- custom rules ...` header) and
`-ExtraIgnore 'a/','b.json'` adds project-specific rules that persist. The base
covers `bin/`, `src/SKSE/`, `SKSEMenuFramework.h`, `zAssets/`, `zOlder/` in
addition to vendored deps and Skyrim assets.

**Auto-routing per provider:** agents enable the graph per project with
`TOOLS\Set-McpProfile.ps1 -Task code -Path <project>` (profile `code-intel`:
`coding-discipline` + `codebase-memory` + `test-driven-development` + `check-work`;
Hermes uses its native `code` profile). Claude/Grok/Codex are project-scoped by
design; Kimi needs explicit global opt-in. Never global-register it just because
the executable exists.

## Edge Types
CALLS, HTTP_CALLS, ASYNC_CALLS, IMPORTS, DEFINES, DEFINES_METHOD,
HANDLES, IMPLEMENTS, OVERRIDE, USAGE, FILE_CHANGES_WITH,
CONTAINS_FILE, CONTAINS_FOLDER, CONTAINS_PACKAGE

## Cypher Examples (for query_graph)
```
MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name, r.url_path, r.confidence LIMIT 20
MATCH (f:Function) WHERE f.name =~ '.*Handler.*' RETURN f.name, f.file_path
MATCH (a)-[r:CALLS]->(b) WHERE a.name = 'main' RETURN b.name
```

## Query Gotchas
1. `search_graph(relationship="HTTP_CALLS")` filters nodes by degree — use `query_graph` with Cypher to see actual edges.
2. `query_graph` has a 200-row cap — use `search_graph` with degree filters for counting.
3. `trace_path` needs exact names — use `search_graph(name_pattern=...)` first.
4. `direction="outbound"` misses cross-service callers — use `direction="both"`.
5. Results default to 10 per page — check `has_more` and use `offset`.

## Indexing, install and the dashboard

[references/indexing-and-install.md](references/indexing-and-install.md) holds the
rest: what the tool cannot parse, case-sensitive `.cbmignore` rules, the bloat
sources, versioned workspaces, what never to index, secrets, the indexing
procedure, reading the dashboard, backups, and install/provider wiring. Read it
before `index_repository`, `delete_project`, or registering the server anywhere.

If the MCP tools are missing: recommend the install, provider registration and a
full restart, and use ordinary search meanwhile. Never fake graph results.
