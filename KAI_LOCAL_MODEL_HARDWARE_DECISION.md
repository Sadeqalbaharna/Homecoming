# Kai Local Model Hardware Decision

Pinned: August 6, 2026

## Decision

Kai should use a hybrid intelligence architecture:

1. **Beelink ME Mini N150** as his quiet, always-on persistent core.
2. **A dedicated NVIDIA GPU workstation** as his powerful local mind and hands.
3. **OpenAI or Anthropic frontier models** only when a task genuinely benefits
   from intelligence beyond the local system.

Kai’s identity, memory, jobs, permissions, presence, handoffs, receipts, and
self-improvement evidence remain under our control. Models are replaceable
cognitive engines, not separate versions of Kai.

## Model equivalence: the honest version

OpenAI and Anthropic do not release the weights of GPT-5.6 or their current
frontier Claude systems. No personal computer can run those exact models
locally. Parameter count is also not a reliable intelligence conversion:
training, architecture, post-training, tool scaffolding, inference-time
reasoning, multimodality, and evaluation discipline all matter.

### Beelink ME Mini

The common ME Mini has 12GB RAM and an Intel N150. It is a strong continuity
server but a weak inference computer.

Realistic local models:

- 1B–3B quantized models: usable for routing, classification, summaries,
  memory-scope checks, simple home commands, and offline presence.
- 7B quantized: technically possible with compromises, but slow and tight.
- OpenAI `gpt-oss-20b`: officially requires about 16GB memory, so it does not
  comfortably fit the common 12GB configuration. Even on a 16GB version, the
  N150 CPU would make it slow.

Practical comparison: below current hosted small models such as GPT-5.6 Luna or
the current Claude Haiku class. It is Kai’s offline reflex and heartbeat, not
his maximum intelligence.

### One RTX PRO 6000 Blackwell 96GB

This is the clearest powerful local Kai configuration.

- Runs OpenAI `gpt-oss-120b`, which fits within 80GB.
- OpenAI reports `gpt-oss-120b` near `o4-mini` on core reasoning benchmarks,
  matching or exceeding it on some coding, math, tool-use, and health
  evaluations.
- Can also run strong 70B–120B open models, local speech, vision, embeddings,
  image generation, coding agents, and tool orchestration.

Practical comparison: approximately older `o4-mini` reasoning territory for
`gpt-oss-120b`, not current GPT-5.6 Sol or the strongest current Claude.

### Dual RTX PRO 6000 workstation

Two cards provide 192GB combined VRAM when software supports model sharding.

This enables:

- 120B models with more operating room.
- Some 200B-class quantized models.
- Several capable local agents concurrently.
- Separate language, speech, vision, and generation models.
- Larger contexts and more serious local fine-tuning.

Practical comparison: can replace older mini/medium hosted reasoning models for
many workloads and may reach older-frontier quality in selected domains. It is
still not a reliable across-the-board equivalent to current GPT-5.6 Sol or the
strongest Claude systems.

### Mac Studio M3 Ultra with 512GB unified memory

This is the conventional personal desktop that can hold the largest models.
Apple says it can run LLMs exceeding 600B parameters entirely in memory.

It can potentially run:

- 405B-class dense models.
- 600B+ mixture-of-experts models.
- Very large contexts.
- Several medium models simultaneously.

Its advantage is capacity. Its tradeoffs are inference speed relative to
high-end NVIDIA VRAM, macOS/Metal ecosystem constraints, and the fact that a
larger open model is not automatically more capable than a frontier hosted
model.

### Absolute maximum

NVIDIA DGX B200 contains eight B200 GPUs and 1,440GB total GPU memory. It is a
data-center system, not a realistic household computer: roughly 14.3kW maximum
power, 10U rack size, specialized cooling, and enterprise pricing.

## Recommended Kai topology

```text
Beelink ME Mini
Kai’s persistent heart
identity · memory · jobs · events · presence · handoffs · receipts
                         │
                         ▼
RTX PRO 6000 workstation
Kai’s sovereign local mind and hands
conversation · reasoning · coding · voice · vision · generation
                         │
                 only when justified
                         ▼
GPT-5.6 Sol / current Claude frontier
hardest reasoning · critical review · novel and high-value problems
```

## Recommended buying sequence

1. Buy the Beelink ME Mini N150 for Kai Core.
2. Run the persistent core, databases, event bus, handoffs, memory, queues,
   monitoring, and encrypted backups there.
3. Use an existing desktop/GPU as the first local worker if available.
4. Eventually build a Linux Threadripper Pro workstation with:
   - One RTX PRO 6000 Blackwell 96GB initially.
   - 256–512GB ECC system RAM.
   - 4–8TB NVMe storage.
   - Power delivery and cooling sized for a future second GPU.
5. Add the second RTX PRO 6000 only when measured workloads prove 96GB is the
   limiting factor.

## Operating principle

The local model is Kai’s sovereign baseline, not necessarily his ceiling.

If the internet fails, Kai remains present, remembers, routes work, protects
memory, controls safe local functions, and explains that stronger cognition is
temporarily unavailable. For normal private work, he recruits the GPU worker.
For exceptionally difficult tasks, he may recruit a frontier cloud model under
explicit privacy, cost, and authority policy.

The model can change. Kai remains Kai.

## Sources

- [OpenAI: Introducing gpt-oss](https://openai.com/index/introducing-gpt-oss/)
- [OpenAI model catalog](https://developers.openai.com/api/docs/models)
- [NVIDIA RTX PRO 6000 Blackwell](https://www.nvidia.com/en-us/products/workstations/professional-desktop-gpus/rtx-pro-6000/)
- [Apple Mac Studio with M3 Ultra](https://www.apple.com/cf/newsroom/2025/03/apple-unveils-new-mac-studio-the-most-powerful-mac-ever/)
- [NVIDIA DGX B200 documentation](https://docs.nvidia.com/dgx/dgxb200-user-guide/introduction-to-dgxb200.html)
- [Intel N150 specifications](https://www.intel.com/content/www/us/en/products/sku/241636/intel-processor-n150-6m-cache-up-to-3-60-ghz/specifications.html)
