# Thin Translation Bake-off — 2026-08-22

## Decision

Carry both `translategemma:4b` and `translategemma:12b` through the first model-neutral translation adapter. The 12B model is the provisional quality candidate; the 4B model is the provisional latency/resource candidate. Neither is the final live or offline default. The versioned multilingual benchmark and real conversational material remain the selection gate.

Apple Translation could not participate because the four source-to-English language pairs were reported as supported but not installed on this host, and an installed-only headless Japanese request failed. This is a setup prerequisite, not a quality rejection; the comparison remains open until the project owner installs the language assets. No UI-driven language download was performed.

Whisper direct translation was tested outside `bfish` through Argmax CLI because the application currently hardcodes `.transcribe`. The CLI's `--task translate` flag maps to WhisperKit's `.translate` decoding task. It returned source-language text rather than English for all four fixtures. A verbose Japanese repeat explicitly printed `Using translation task` and `Task: Translate audio` before returning Japanese, confirming that the result was not caused by accidentally selecting transcription.

## Method

- Host: Apple Silicon Mac with 192 GiB physical memory, macOS 26, Xcode 26.6
- Ollama: 0.32.9, local-only mode
- Fixtures: [`thin-translation-v1.jsonl`](../Benchmarks/Fixtures/thin-translation-v1.jsonl)
- Prompt: [`ollama-translation-v1.txt`](../Benchmarks/Prompts/ollama-translation-v1.txt)
- Generation: temperature 0, non-streaming, explicit 10-minute `keep_alive`
- Critical review: preserve the named station, time, and meeting intent; return translation only
- Whisper command shape: `argmax-cli transcribe --audio-path <fixture> --model large-v3-v20240930_626MB --task translate --language <language> --without-timestamps`

This four-sentence probe is deliberately too small for aggregate quality scoring. Its purpose is to reject unavailable or behaviorally unsuitable paths and select a candidate for adapter development.

## Results

| Path | Japanese | Korean | Mandarin | Brazilian Portuguese | Timing/resource observation | Result |
|---|---|---|---|---|---|---|
| Whisper direct | Returned Japanese | Returned Korean | Returned Chinese | Returned Portuguese | Not scored as translation | Ineligible for this tested configuration |
| Apple Translation | Assets not installed | Assets not installed | Assets not installed | Assets not installed | Headless installed-only Japanese request failed | Pending one-time asset installation |
| `translategemma:4b` Q4_K_M | Preserved Tokyo Station | Preserved Seoul Station | Preserved Beijing Station | Changed Estação da Luz to “Central Station” | 3.25 s Japanese cold; 0.515 s median over three warm requests | Provisional latency/resource candidate; critical entity failure recorded |
| `translategemma:12b` Q4_K_M | Preserved Tokyo Station | Preserved Seoul Station | Preserved Beijing Station | Preserved Luz station | 5.60 s Japanese cold; 0.772 s median over three warm requests | Provisional quality candidate |

The warm medians exclude the first cold Japanese request and cover Korean, Mandarin, and Brazilian Portuguese. They are directional, not p95 measurements.

## Simultaneous residency probe

Ollama reported the resident 12B model as 9.5 GB and 100% GPU. With it resident, WhisperKit transcribed the 3.42-second Japanese fixture correctly with:

- 0.993 seconds recognition wall time
- 0.290 real-time factor
- 0.993 seconds to the first finalized segment
- 134.5 MB peak resident memory and 97.9 MB physical footprint for the `bfish` process

A nearby run without the Ollama model resident measured 1.055 seconds recognition wall time and 0.309 RTF. This shows only that both models can reside and complete the short probe on this 192 GiB host. The Ollama model was idle while WhisperKit inferred, so this does not measure compute contention, sustained concurrent inference, or establish causality from the small timing difference. Active-contention, memory-pressure, smaller-host, and p95 tests remain part of the benchmark harness.

## Next implementation gate

Build the model-neutral Ollama HTTP adapter around the version-2 translation-only structured response, explicit timeout and `keep_alive`, typed failure isolation, and backend token/timing diagnostics. Run both 4B and 12B through the expanded committed fixture before choosing profile defaults. Separately, install the supported Apple Translation language assets and measure that backend before closing the live-path decision.
