# Generator presets

`presets.json` contains 47 operator-provided entries with titles, descriptions
and `param_map` settings. It is preset data, not a ComfyUI node-graph workflow.
Do not submit it to a workflow API or assume it installs models/custom nodes.

Keep a backup before importing into a matching frontend. Resolve the selected
model, VAE, sampler and scheduler against the installed backend; preserve local
choices when names differ. Hardware/model-specific descriptions are tuning
intent, not controlled quality or speed benchmarks. JSON parsing was checked;
GPU generation and frontend import are not certified by the bundle gates.
