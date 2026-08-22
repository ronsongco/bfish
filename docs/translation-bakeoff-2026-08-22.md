# Thin Translation Bake-off — 2026-08-22

## Decision

Use `translategemma:12b` as the provisional Ollama model for the first translation adapter. This is an implementation starting point, not the final live or offline default. The versioned multilingual benchmark and real conversational material remain the selection gate.

Apple Translation could not participate because the four source-to-English language pairs were reported as supported but not installed on this host, and an installed-only headless Japanese request failed. No UI-driven language download was performed. WhisperKit direct translation was ineligible because the tested `large-v3-v20240930_626MB` path returned source-language text rather than English for all four fixtures.

## Method

- Host: Apple Silicon Mac with 192 GiB physical memory, macOS 26, Xcode 26.6
- Ollama: 0.32.9, local-only mode
- Fixtures: [`thin-translation-v1.jsonl`](../Benchmarks/Fixtures/thin-translation-v1.jsonl)
- Prompt: [`ollama-translation-v1.txt`](../Benchmarks/Prompts/ollama-translation-v1.txt)
- Generation: temperature 0, non-streaming, explicit 10-minute `keep_alive`
- Critical review: preserve the named station, time, and meeting intent; return translation only

This four-sentence probe is deliberately too small for aggregate quality scoring. Its purpose is to reject unavailable or behaviorally unsuitable paths and select a candidate for adapter development.

## Results

| Path | Japanese | Korean | Mandarin | Brazilian Portuguese | Timing/resource observation | Result |
|---|---|---|---|---|---|---|
| Whisper direct | Returned Japanese | Returned Korean | Returned Chinese | Returned Portuguese | Not scored as translation | Ineligible for this tested configuration |
| Apple Translation | Assets not installed | Assets not installed | Assets not installed | Assets not installed | Headless installed-only Japanese request failed | Unavailable on this host |
| `translategemma:4b` Q4_K_M | Preserved Tokyo Station | Preserved Seoul Station | Preserved Beijing Station | Changed Estação da Luz to “Central Station” | 3.25 s Japanese cold; 0.515 s median over three warm requests | Rejected by critical entity check |
| `translategemma:12b` Q4_K_M | Preserved Tokyo Station | Preserved Seoul Station | Preserved Beijing Station | Preserved Luz station | 5.60 s Japanese cold; 0.772 s median over three warm requests | Provisional adapter candidate |

The warm medians exclude the first cold Japanese request and cover Korean, Mandarin, and Brazilian Portuguese. They are directional, not p95 measurements.

## Simultaneous residency probe

Ollama reported the resident 12B model as 9.5 GB and 100% GPU. With it resident, WhisperKit transcribed the 3.42-second Japanese fixture correctly with:

- 0.993 seconds recognition wall time
- 0.290 real-time factor
- 0.993 seconds to the first finalized segment
- 134.5 MB peak resident memory and 97.9 MB physical footprint for the `bfish` process

A nearby run without the Ollama model resident measured 1.055 seconds recognition wall time and 0.309 RTF. This shows that both models can reside and complete the short probe on this high-memory host; it does not measure sustained concurrent inference or establish causality from the small timing difference. Active-contention, memory-pressure, and p95 tests remain part of the benchmark harness.

## Next implementation gate

Build the Ollama HTTP adapter around a translation-only structured response, explicit timeout and `keep_alive`, typed failure isolation, and backend token/timing diagnostics. Then run the committed fixture through the adapter and expand to conversational and priority-language evaluation before choosing profile defaults.
