# Hermes model guidance

Catalog check: **2026-10-19**. Consult the [public OpenRouter catalog](https://openrouter.ai/api/v1/models)
for current IDs, pricing, modalities and supported parameters, and
[Hermes provider documentation](https://hermes-agent.nousresearch.com/docs/integrations/providers)
for API, subscription/OAuth and local-endpoint routes. Metadata is compatibility
evidence, not a quality benchmark or guaranteed availability.

## Choose deliberately; keep existing preferences

`hermes model` opens the provider/model picker. `hermes model --refresh` clears
its cache and refetches catalogs; `/model` switches inside a chat. Compare task
accuracy, latency, modalities and budget, not release date alone. The starter
default is `deepseek/deepseek-v4.1-flash-1017`: 1,048,576-token context,
$0.15 / $0.60 per 1M input/output tokens, and text plus image input on
OpenRouter's listing. Upgrades do not replace an existing main or auxiliary
choice with a newer paid model.

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

## Auxiliary tasks follow the main model

Every `auxiliary.*` task ships as `provider: auto` with an empty `model`, which
means "use the main model". No auxiliary task carries a pinned model ID any
more. The reason is empirical: the old free chain went text-only, then hit
quotas, then was retired, and each failure was silent — vision dropped images,
compression fell back to a weaker summary, approvals ran on a model that no
longer existed. A pin is a promise to revisit it; `auto` has nothing to retire.

The vision task is safe to auto-route only because the default main model
accepts images. If you switch to a text-only main model, set
`auxiliary.vision.model` to a multimodal model explicitly, or images will fail
rather than silently disappear.

`auxiliary.vision.fallback_chain` is **not a recognized Hermes key**. Older
configs carried it, and it did nothing; the pack no longer ships it. Use
`fallback_providers` if you want failover, and only with models that accept the
same modalities as the main model.

## No shipped failover chain

`fallback_providers` ships empty. The previous four-entry free chain
(`laguna-s`, `inkling`, `inkling-small`, `laguna-xs`) was weaker than the main
model and text-only in places, so a 429 quietly downgraded the answer instead
of failing loudly. If you want failover, add entries yourself and check their
modalities and quotas first; a free model is not a drop-in replacement for a
multimodal paid one.

## Compression tuning for a 1M-token window

`compression.threshold_tokens: 320000` is an absolute cap: compaction fires at
the lower of `threshold × context` and that count. On a 1,048,576-token window
the ratio would otherwise wait until ~524k tokens, which is a long, expensive
turn and past the range where most models hold quality. 320k keeps the working
set large enough for multi-file work while bounding per-turn input cost
(~$0.048 at $0.15/1M before caching) and cache invalidation frequency.

`proactive_prune_tokens: 80000` reclaims stale large tool results before a
summary is needed; `target_ratio: 0.20`, `tail_mode: lean`, `protect_last_n: 20`
and `min_tail_user_messages: 3` keep recent turns and user messages intact.
`abort_on_summary_failure: true` means a failed summary never replaces retained
context. Raise the cap only after measuring your own turns; lower it if
latency or spend matters more than long-range recall.

## Shipped aliases are shortcuts, not a ranking

Existing mappings are retained. `sol` and `opus` are not moving "latest" pointers:

| Alias | Shipped model ID |
| --- | --- |
| `v4.1-flash` | `deepseek/deepseek-v4.1-flash` |
| `flash` | `deepseek/deepseek-v4-flash-0731` |
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
limits differ, and paid/free variants can have different limits.

## Local endpoints and privacy

Use actual loaded IDs and server context settings, not guessed aliases. LM Studio
budget tools estimate GPU/KV fit; measure full GPU residency for the model, cache
type, concurrency and desktop VRAM load. A local main model does not make hosted
compression, vision, search or MCP calls local. Review each auxiliary/tool route
for tasks that must stay on-device.
