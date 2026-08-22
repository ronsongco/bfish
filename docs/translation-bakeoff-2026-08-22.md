# Thin Translation Bake-off — 2026-08-22

## Decision

Carry both `translategemma:4b` and `translategemma:12b` through the first model-neutral translation adapter. The 12B model is the provisional quality candidate; the 4B model is the provisional latency/resource candidate. Neither is the final live or offline default. The versioned multilingual benchmark and real conversational material remain the selection gate.

Apple Translation could not participate because the four source-to-English language pairs were reported as supported but not installed on this host, and an installed-only headless Japanese request failed. This is a setup prerequisite, not a quality rejection; the comparison remains open until the project owner installs the language assets. No UI-driven language download was performed.

Whisper direct translation was tested outside `bfish` through Argmax CLI because the application currently hardcodes `.transcribe`. The CLI's `--task translate` flag maps to WhisperKit's `.translate` decoding task. The 626 MB large-v3 variant returned source-language text rather than English for all four fixtures. A verbose Japanese repeat explicitly printed `Using translation task` and `Task: Translate audio` before returning Japanese, confirming that the result was not caused by accidentally selecting transcription. A follow-up with the 479 MB `small` variant did produce English, proving that direct translation is not generally broken, but it failed critical Korean and Brazilian Portuguese details.

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
| Whisper large-v3 626 MB direct | Returned Japanese | Returned Korean | Returned Chinese | Returned Portuguese | Not scored as translation | Ineligible for this tested configuration |
| Whisper `small` direct | “See you at Tokyo Station at 3 pm today.” | “See you at 5 o'clock today.” | Preserved Beijing Station and 3 p.m. | Rendered Estação da Luz as “station of the light” | Translation RTF 0.09–0.12 | Working baseline; critical Korean and Portuguese failures |
| Apple Translation | Assets not installed | Assets not installed | Assets not installed | Assets not installed | Headless installed-only Japanese request failed | Pending one-time asset installation |
| `translategemma:4b` Q4_K_M | Preserved Tokyo Station | Preserved Seoul Station | Preserved Beijing Station | Changed Estação da Luz to “Central Station” | 3.25 s Japanese cold; 0.515 s median over three warm requests | Provisional latency/resource candidate; critical entity failure recorded |
| `translategemma:12b` Q4_K_M | Preserved Tokyo Station | Preserved Seoul Station | Preserved Beijing Station | Preserved Luz station | 5.60 s Japanese cold; 0.772 s median over three warm requests | Provisional quality candidate |

The warm medians exclude the first cold Japanese request and cover Korean, Mandarin, and Brazilian Portuguese. They are directional, not p95 measurements.

## Alternative Whisper variant

The same explicit translate command was repeated with `--model small`. Its first Core ML load took 23.66 seconds; subsequent fresh CLI processes loaded it in 0.86–0.91 seconds. It produced English for all four fixtures, distinguishing the large-v3 result as model/conversion-specific rather than a general WhisperKit task-wiring failure.

Direct translation still does not satisfy the product output contract by itself because `bfish` must display authoritative source text alongside English. Separate `small` source-transcription probes measured RTF 0.09–0.14. Adding the independently measured transcription and translation RTFs gives a directional two-decode range of 0.19–0.26, excluding shared-load optimization and orchestration overhead. The Korean source pass also mistranscribed Seoul Station, while the translation pass changed 3 p.m. to 5 o'clock and omitted the station. Brazilian Portuguese translated the proper name *Estação da Luz* literally.

Therefore `small` remains a useful direct-translation baseline but does not replace the Ollama/Apple comparison. Using large-v3 for the source and `small` for English would require both the 606 MB and 479 MB model variants, while using `small` for both sacrifices source accuracy in this probe.

## Simultaneous residency probe

Ollama reported the resident 12B model as 9.5 GB and 100% GPU. With it resident, WhisperKit transcribed the 3.42-second Japanese fixture correctly with:

- 0.993 seconds recognition wall time
- 0.290 real-time factor
- 0.993 seconds to the first finalized segment
- 134.5 MB peak resident memory and 97.9 MB physical footprint for the `bfish` process

A nearby run without the Ollama model resident measured 1.055 seconds recognition wall time and 0.309 RTF. This shows only that both models can reside and complete the short probe on this 192 GiB host. The Ollama model was idle while WhisperKit inferred, so this does not measure compute contention, sustained concurrent inference, or establish causality from the small timing difference. Active-contention, memory-pressure, smaller-host, and p95 tests remain part of the benchmark harness.

## Next implementation gate

Build the model-neutral Ollama HTTP adapter around the version-2 translation-only structured response, explicit timeout and `keep_alive`, typed failure isolation, and backend token/timing diagnostics. Run both 4B and 12B through the expanded committed fixture before choosing profile defaults. Retain Whisper `small` as a measured two-pass baseline rather than treating it as an automatic replacement. Separately, install the supported Apple Translation language assets and measure that backend before closing the live-path decision.
