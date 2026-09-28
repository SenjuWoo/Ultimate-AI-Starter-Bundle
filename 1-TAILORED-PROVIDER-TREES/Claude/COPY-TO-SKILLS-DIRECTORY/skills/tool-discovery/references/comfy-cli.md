# Local image/video workflows without another MCP

Comfy-Org's optional `comfy-cli` 1.21.0 can inspect, compose, validate and run
ComfyUI workflows through shell access. It is not installed by the default
bundle, and does not replace image-generation tools already available to the
agent. First discover the user's actual ComfyUI installation and running local
server; never guess a model, node class, workflow schema, or checkpoint name.

For a process-local, pinned invocation:

```powershell
$env:COMFY_NO_TELEMETRY = '1'
uvx --python 3.13 --from comfy-cli==1.21.0 comfy --where local --version
uvx --python 3.13 --from comfy-cli==1.21.0 comfy --where local workflow ls-nodes .\workflow.json
uvx --python 3.13 --from comfy-cli==1.21.0 comfy --where local workflow validate --help
uvx --python 3.13 --from comfy-cli==1.21.0 comfy --where local run --help
```

Inspect only the relevant subcommand's help. `--help-json` describes the entire
CLI and is very large: filter its JSON locally instead of returning it to the
model. Use `--json` for a compact result envelope. Keep `--where local` explicit:
the CLI also supports cloud execution, which is not the bundle's default.

Copy the user's workflow to the project before changing it. Validate against
the real local node catalog before submitting a run, then inspect the generated
image/video. Successful JSON validation is not proof of visual quality.

Do not run setup, install, login, cloud commands, custom-node installation or
model downloads without that task being authorized. Do not install the CLI's
agent skills into provider folders; the bundle owns canonical skill fanout.

Windows evidence (2026-09-28): isolated install, version/help, offline graph
inspection, and malformed-file rejection. GPU inference and live-server
workflow validation are unverified; no ComfyUI server or models are bundled.

[Official source and documentation](https://github.com/Comfy-Org/comfy-cli)
