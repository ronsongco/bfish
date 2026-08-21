# WhisperKit Smoke Test — 2026-08-21

## Scope

The first real model execution used macOS 26.4.1 on Apple Silicon, Argmax OSS 1.1.0, the WhisperKit `tiny` model, automatic language detection, and a 5.835-second mono Japanese fixture synthesized locally with the macOS Kyoko voice:

```text
こんにちは。今日は天気がいいですね。これは音声認識のテストです。
```

The fixture and raw run files were temporary files under `/tmp`; no audio or transcript artifact was committed. The exact fixture command was:

```console
say -v Kyoko -o /tmp/bfish-smoke-ja.aiff 'こんにちは。今日は天気がいいですね。これは音声認識のテストです。'
```

On this host, `say` produced mono 22,050 Hz, 16-bit big-endian linear PCM in an AIFF-C container. Voice assets may change across macOS releases, so the OS version and resulting media properties are part of the reproduction record.

## Cold Run

- Model acquisition/download: 21.99 seconds
- Model load: 6.42 seconds
- Recognition wall time: 0.80 seconds
- Transcription-only wall time: 0.18 seconds
- Media duration: 5.835057 seconds
- WhisperKit summed task-input duration: 5.835000 seconds
- End-to-end recognition RTF: 0.137
- Detected language: Japanese (`ja`)
- stderr: 31 of 31 lines parsed as schema-versioned JSON

The cold run exposed Whisper control tokens in source text. The adapter was corrected to set `skipSpecialTokens: true` before the cached rerun.

## Cached-Model Rerun

- Cached model resolution: 2.72 seconds
- Model load: 4.61 seconds
- Recognition wall time: 0.36 seconds
- Transcription-only wall time: 0.20 seconds
- Media duration: 5.835057 seconds
- WhisperKit summed task-input duration: 5.835000 seconds
- End-to-end recognition RTF: 0.062
- stderr: 6 of 6 lines parsed as schema-versioned JSON
- Segment timestamps within this single-chunk fixture: monotonic, with no repair or discontinuity diagnostics
- Source text: control tokens successfully removed

Output:

```text
[00:00:00] [ja]
Source: こんにちは、今日は天気がいいですね。

[00:00:03] [ja]
Source: これは本生認識のテストです。
```

`tiny` incorrectly recognized `音声` as `本生`. This confirms its role as a development/smoke model rather than the multilingual accuracy baseline.

## Conclusions

- The file adapter, automatic language selection, Core ML model loading, timestamp mapping, terminal output, and JSONL diagnostics work end to end.
- The measured recognition path is comfortably faster than real time on this host for a short synthetic fixture.
- Model initialization dominates one-shot CLI latency even with cached files; persistent-process and simultaneous-model measurements remain important.
- Source media duration and the SDK task-input sum agree within approximately 0.00006 seconds for this single-chunk fixture. This does not validate agreement across VAD chunk boundaries.
- The original run predated schema version 8, which adds selected language, language confidence, and the automatic-selection flag to `recognition_completed`. Future benchmark artifacts include these fields directly.
- Actual SDK behavior across chunk boundaries remains to be observed with a 90+ second fixture; only the application-level discontinuity guard is covered by a multi-result unit test.
- The next model-quality run should use `large-v3-v20240930_626MB` and representative legally usable speech rather than synthesized speech alone.
