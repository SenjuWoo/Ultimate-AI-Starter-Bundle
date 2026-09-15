# Hermes profiles

The shared portable config is `../COPY-TO-PROVIDER-HOME/config.yaml`.
`TOOLS/Migrate-HermesProfiles.ps1` creates specialist profiles by cloning the
user's current default through Hermes itself, not by copying a maintainer dump.
Existing models, reasoning, memory limits and tool filters are preserved.

| Profile | Availability | MCP scope |
| --- | --- | --- |
| default | Hermes installed | Context7, GitHub, Headroom |
| code | codebase-memory installed | Core plus codebase-memory |
| roblox | Official Studio MCP installed | Core plus Studio |
| skyrim | houseCARL and MO2 configured | Core plus houseCARL, user's filter retained |
| rimworld | Existing RimWorldForge profile | Core updated, external server retained unchanged |

Run `hermes -p code` (or the other name). Profile YAML files here document native
descriptions; they are not live configs. RimWorldForge is a separate installation:
the bundle does not download it or guess its location.

Reviewed September 15, 2026: main DeepSeek V4.1 Flash with high reasoning,
20% compression target, free Inkling Small summarizer with high reasoning and
600-second timeout, response cache disabled, one-hour prompt cache retained,
bounded delegation. The installed provider advertises these models/efforts;
this is compatibility evidence, not a quality or token-saving benchmark.
The 160k compression cap, material-result pruning, summary-failure abort and
disabled automatic multi-model fan-out remain safeguards. `ultra` was not
promoted for Inkling: its catalog lists max/high/medium/low/minimal/none.

Personal local-model aliases, command approvals, absolute hooks/MCP paths,
generated tool inventories and update-backup disabling are not portable
defaults. Auto-routed auxiliary tasks can choose paid models, so existing
explicit low-cost auxiliary defaults remain. Current Hermes ignores the old
web-extraction model block; the starter no longer includes it.

Your code-profile memory limit of 5000 characters is retained locally. Other
profiles keep 2200; these deliberate profile preferences are not overwritten
by migration. Original exports are backed up locally, not redistributed.
