# Hermes model guidance

Catalog check: **2026-10-02**. Consult the [public OpenRouter catalog](https://openrouter.ai/api/v1/models)
for current IDs, pricing, modalities and supported parameters, and
[Hermes provider documentation](https://hermes-agent.nousresearch.com/docs/integrations/providers)
for API, subscription/OAuth and local-endpoint routes. Metadata is compatibility
evidence, not a quality benchmark or guaranteed availability.

## Choose deliberately; keep existing preferences

`hermes model` opens the provider/model picker. `hermes model --refresh` clears
its cache and refetches catalogs; `/model` switches inside a chat. Compare task
accuracy, latency, modalities and budget, not release date alone. The starter
still uses DeepSeek V4.1 Flash; upgrades do not replace existing main or auxiliary
choices with newer paid models.

Currently listed candidates for deliberate comparison:

| Model ID | Context tokens | Base input / output USD per 1M tokens |
| --- | ---: | ---: |
| `openai/gpt-6.1-sol` | 1,050,000 | $2 / $10 |
| `anthropic/claude-sonnet-5.5` | 1,000,000 | $2 / $10 |
| `anthropic/claude-opus-5.5` | 1,000,000 | $4 / $20 |

All three advertise image/file input and tools. GPT-6.1 Sol advertises a prompt
tier at 272,000 tokens: $4 / $15. Cached input, reasoning output, search and
provider routing can change the bill. These are dated catalog rates, not task
quotes. None was benchmarked or promoted to a default by this update.

## Shipped aliases are shortcuts, not a ranking

Existing mappings are retained. `sol` and `opus` are not moving “latest” pointers:

| Alias | Shipped model ID |
| --- | --- |
| `v4.1-flash` | `deepseek/deepseek-v4.1-flash` |
| `flash` | `deepseek/deepseek-v4-flash-0731` |
| `flash-vision` | `deepseek/deepseek-v4-flash-vision-exp` |
| `muse` | `meta/muse-spark-1.2-contributor` |
| `v4-pro` | `deepseek/deepseek-v4-pro-0813` |
| `gemini-flash` | `google/gemini-3.7-flash` |
| `glm` | `z-ai/glm-5.3` |
| `grok` | `x-ai/grok-4.6` |
| `sol` | `openai/gpt-5.6-sol` |
| `opus` | `anthropic/claude-opus-5` |
| `nemotron-ultra` | `nvidia/nemotron-3-ultra-550b-a55b:free` |
| `nemotron-ultra-nofree` | `nvidia/nemotron-3-ultra-550b-a55b` |

Check the catalog before switching: not every alias accepts images, context
limits differ, and paid/free variants can have different limits. The fallback
chain is retained; free endpoints have quotas and text-only fallbacks cannot
preserve image understanding. Explicit custom chains stay untouched.

## Retired compression endpoint

`inclusionai/ling-3.0-flash-vl:free` is no longer listed. The paid sibling still
exists; the pack does **not** silently switch to it. Compression now defaults to
`thinkingmachines/inkling:free`: its listed 1,048,576-token context covers the
160,000-token cap. Its effort set includes `max`, not `ultra`; the starter uses
`max`, timeout 600, and abort-on-summary-failure. A failed summary must not
replace retained context.

The migrator repairs only that exact retired free Ling ID (including its
`openrouter/`-prefixed form), with provider `openrouter`. Only `ultra` becomes
`max`; other efforts and extra fields stay. Paid Ling, another provider/model,
the main model, custom aliases and other auxiliary models are not replaced.
The old value is rechecked at write time; existing verified backup/rollback
handling is reused. No authenticated inference or summary-quality benchmark
was run. Free does not mean lossless compression or unlimited usage.

## Local endpoints and privacy

Use actual loaded IDs and server context settings, not guessed aliases. LM Studio
budget tools estimate GPU/KV fit; measure full GPU residency for the model, cache
type, concurrency and desktop VRAM load. A local main model does not make hosted
compression, vision, search or MCP calls local. Review each auxiliary/tool route
for tasks that must stay on-device.
