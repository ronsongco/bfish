# WhisperKit Hallucination Probe — 2026-08-21

Two temporary 20-second, 16 kHz mono fixtures were generated locally: digital silence and four sequential pure tones. Neither fixture nor any transcript output is committed.

With `large-v3-v20240930_626MB`, explicit Japanese, incremental file loading, and VAD chunking, both fixtures produced the same source segment: Whisper's common Japanese “thanks for watching” hallucination. In both cases:

- `noSpeechProbability` was 0
- segment confidence was high: 0.9400 for silence and 0.9357 for tones
- compression ratio was 0.9091, below the conventional pathological-repetition ceiling

No measured scalar distinguished these hallucinations from plausible speech. This confirms that the no-speech threshold is inert on the current VAD path and that a generic confidence cutoff would reject valid podcast segments before rejecting these examples.

Schema v13 therefore adds an exact, normalized multilingual known-hallucination blocklist and a separate compression-ratio gate for repetitive decoder failure. Repeating both probes produced empty stdout and one privacy-safe `segment_filtered: knownHallucination` event per fixture.

This is a narrow safeguard, not proof of general music or silence robustness. Future fixtures must include real music, applause, room noise, and speech over music. The blocklist must remain explicit and reviewable because its phrases can occasionally occur in legitimate speech.
