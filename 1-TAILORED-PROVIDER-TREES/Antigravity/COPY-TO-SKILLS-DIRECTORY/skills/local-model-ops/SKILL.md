---
name: local-model-ops
description: Run a local LM Studio model as a Hermes provider - context floors, VRAM budget, aliases, and keyless web search. Load before wiring local inference or when an API model must be avoided.
metadata:
  version: 1.1.0
---

# Local model ops

Wiring a local GGUF served by LM Studio into Hermes. Runtime-dependent details
come from inspected installations; recheck them after upgrades. Historical
measurements are examples, not guarantees for another model or machine.

## Why run local at all

Choose local or hosted by measured quality, speed, budget and privacy needs.
Local inference can provide:

| Reason | What it gets you |
|---|---|
| **Model choice** | Choose models suited to adult, red-team or dark-fiction work; behavior still depends on the model and harness |
| **Local inference** | Prompts stay local only when auxiliaries, fallback routes and tools are also local or disabled |
| **No hosted inference quota** | Offline inference after setup; local servers can still reject overloaded requests |

Compare hosted options in `token-efficiency`; do not assume either route is cheaper or faster.

## Hermes speaks LM Studio natively

`lmstudio` is a **first-class provider**, not a generic OpenAI-compatible
endpoint. That buys real behaviour you do not get from a custom provider:

- Default route `http://127.0.0.1:1234/v1`, overridable with `LM_BASE_URL`.
- **No credential setup.** Hermes supplies its own placeholder key. Never put
  a real secret in an `lmstudio` provider block; there is nothing to
  authenticate to.
- Explicit preload: Hermes loads the model into LM Studio itself before the
  first turn. Set `model.lmstudio_load_mode: jit` to skip that and let LM
  Studio load on first request instead.
- The on-disk context cache is deliberately bypassed for `lmstudio`, because
  a local model's loaded context changes whenever you reload it.

## A dict-shaped `models:` does not narrow the list, it duplicates it

Leave the provider's model catalog to `discover_models: true` and write **no**
`models:` block under it. The two are not alternatives that happen to overlap:

```yaml
providers:
  lm-studio:
    discover_models: true
    models:                      # <-- delete this
      some-model@iq3_xs: {}
```

Hermes treats a **list or string** `models:` as an allowlist that narrows
discovery, and a **dict** as a saved catalog that merges *alongside* it
(`model_switch.py`: `if isinstance(value, dict): return False`). So the dict
form adds entries instead of filtering them, and the picker shows the model
twice — once discovered, once declared. The tell is that it looks correct
while nothing is loaded, because discovery has nothing to contribute yet, and
doubles the moment you load a model in LM Studio.

To pin a dict-shaped catalog on purpose, set `discover_models: false`. If you
want the list to track whatever you have loaded — the normal case when you
swap models often — keep discovery on and delete the block.

Then check the id everywhere, not just in `model.default`. A stale local model
name tends to appear in five or six places at once: `model.default`, the
provider's own `model:`, `model_aliases.<name>.model`, and every
`moa.*.aggregator.model`. Measured on the maintainer's machine 2026-08-26: six
references, **none** of which matched the id the server was serving.

```powershell
Select-String -Path "$env:LOCALAPPDATA\hermes\config.yaml" -Pattern '^\s*model:'
```

A stale name may fail or fall through to `fallback_providers`, depending on
the route and runtime. Inspect the resolved endpoint and logs before calling
an unexpectedly slow or hosted response a local-inference failure.

## The context floor is the thing that bites

Hermes normally enforces a **64,000-token** context floor at startup. A 32K
window can raise a hard `ValueError` before the first turn.

In the inspected runtime, provider `lmstudio` plus an explicit positive integer
`model.context_length` permits a smaller window. Older runtimes may reject it.
A smaller window needs a lean tool/profile scope and bounded results; measure
compression frequency and task quality rather than assuming it cannot work.

**65,536 is a tested large-context target when it fits.** The normal floor
rejects values below 64,000, not a value equal to it. Budget weights plus KV
cache first; use the explicit local exception when appropriate. Save the
chosen context in the LM Studio UI (or its per-model config) and
confirm it stuck by loading with **no** explicit context flag: the loaded
context LM Studio reports must be the new value, not the old one. Loading it
once by hand with a flag proves nothing -- the next cold start uses the saved
default, which is what Hermes' preload will pick up.

## Aliases: pin the route, do not guess it

Two alias forms exist and they are not equivalent.

`model_aliases` is a dict, checked **before** catalog resolution, and it is the
only form that pins a base URL:

```yaml
model_aliases:
  local:
    model: <the id LM Studio reports at /v1/models>
    provider: lmstudio
    base_url: http://127.0.0.1:1234/v1
```

`model.aliases` is the string form (`name: provider/model`). It has no place
for a base URL and loses to `model_aliases` on a name collision. Use it for
hosted models; use `model_aliases` for local ones.

The model id is whatever LM Studio serves it as — read it from the server, do
not derive it from the filename.

Switch with `hermes model local`, back with `hermes model <hosted-alias>`.

## Sizing: weights first, then KV, then what is left

Read the real numbers out of the GGUF header rather than trusting the label —
`references/gguf-metadata.md` has a parser and worked KV arithmetic.

Three rules that survive contact with hardware:

1. **Weights larger than VRAM means partial offload, always.** No context
   setting changes that. A mixture-of-experts model tolerates it far better
   than a dense one, because only a few experts run per token.
2. **KV cache scales linearly with context and is charged on top of weights.**
   Doubling context can cost gigabytes. Quantize the KV cache to `q8_0` before
   giving up context — it roughly halves fp16 cache storage. Verify task quality
   and runtime support instead of promising lossless quantization.
3. **Leave real headroom.** A card sitting at 94% has no room for a browser,
   let alone a game. Set a TTL so the model unloads when idle.

LM Studio's `--estimate-only` reports weights only and self-labels
`Confidence: LOW`. It does not model the KV cache, so do not use it to size a
context change. Load it and read the VRAM.

## Free web access, without an API bill

The model does not browse. **Hermes** browses, through its own `web_search` /
`web_extract` tools, and hands results to whatever model is driving. That is
why a local model gets internet at all.

This is a different mechanism from a hosted provider's own web plugin, which
may bill per search. Inspected Hermes versions offer a keyless fallback ring
across public free tiers (`web.keyless_fallback`) and a rescue retry
(`web.keyless_rescue`). Check the installed defaults and current vendor limits;
keyless does not guarantee unlimited or permanently free service. Searches
send their queries to those external services, even with a local model.

Add DuckDuckGo as a vendor-independent backstop by installing the optional
`ddgs` package into the Hermes environment. It needs no account at all, and
it runs the query in a child process so a hung native call cannot wedge the
agent. Pin it with `web.search_backend` only if the free ring gets flaky —
pinning disables the rotation.

**Verify the model actually uses it.** Ask a question whose answer changed
recently and check the cited URL. A local model can call the tool correctly
and still misread the result: a 35B answering from real search results
reported a stale release number that the source page contradicted. The
plumbing working is not the same as the answer being right.

## The same model from a chat front-end

One server can feed an agent CLI and a chat UI at once, but they disagree about
what is acceptable. A chat UI can use 32K while Hermes's normal floor rejects
it; the explicit LM Studio exception above may allow a lean agent profile.
Load at **65,536** if weights, cache and concurrency fit, then test both clients.

Two SillyTavern behaviours look like a dead connection and are not: it demands
a non-empty API key that a local server ignores, and a reasoning model returns
an **empty** message when Response Length is small, because thinking tokens come
out of the same budget. `references/sillytavern.md` has the measurements, the
exact guard in SillyTavern's source, and how to give it keyless web search.

## Checklist

- [ ] Model id read from the running server, not guessed from the filename
- [ ] Saved context fits the VRAM budget and runtime floor/explicit exception; confirmed by loading with no context flag
- [ ] Local-only intent also covers auxiliaries, fallbacks and external tools
- [ ] `model_aliases` entry pins model + provider + base_url
- [ ] No API key written into any `lmstudio` config block
- [ ] VRAM measured while generating, not while idle
- [ ] Idle TTL set so the card frees itself
- [ ] Web search proven end-to-end against a source you checked yourself
- [ ] Chat front-end: response budget large enough to survive reasoning tokens
