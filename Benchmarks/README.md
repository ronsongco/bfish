# Benchmarks

This directory will contain versioned benchmark fixtures, prompt templates, raw run metadata, and generated scoreboards.

Raw run output and generated scoreboards are ignored by Git until their schemas and provenance rules are established. This is deliberate: corpus manifests, configurations, schema versions, and curated summary scoreboards will be committed, while large or privacy-sensitive raw artifacts will use an explicitly selected artifact store or Git LFS. See the project README for the planned translation-only and end-to-end evaluation tracks.

The initial public-data baseline will evaluate FLEURS read speech and corresponding FLORES text where available. Every run must record the exact dataset revision, locale configuration, license, prompt version, model identity, and whether speech recognition and translation models were loaded concurrently. A smaller conversational set will cover code-switching, overlap, music, and disfluency that read speech does not represent.

The milestone-2 probe uses the committed [`thin-translation-v1.jsonl`](Fixtures/thin-translation-v1.jsonl) fixture and [`ollama-translation-v1.txt`](Prompts/ollama-translation-v1.txt) prompt. Its narrow rule identifies unavailable backends, paths that do not produce English, and critical meaning/entity failures. See the [2026-08-22 result](../docs/translation-bakeoff-2026-08-22.md). This probe narrows adapter candidates; it does not replace the multilingual scoreboard.

Production-shaped adapter evaluation starts with [`translation-adapter-v2.jsonl`](Fixtures/translation-adapter-v2.jsonl) and [`ollama-translation-v2.txt`](Prompts/ollama-translation-v2.txt). Version 2 adds structured output, bounded context, omitted-subject cases, ASR-degraded text, uncertainty, negation, and inputs that the pipeline must suppress before translation. Version 1 remains unchanged so its measurements stay reproducible; its free-form results must not be compared directly with version 2.
