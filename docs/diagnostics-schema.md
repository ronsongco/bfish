# Diagnostic JSONL Schema

`DiagnosticEvent.schemaVersion` identifies the shape of operational JSON Lines emitted by `bfish`. Diagnostic records must never contain source transcripts, translations, or audio samples.

## Version 1

Introduced typed diagnostic events and typed privacy-safe details. The detail fields were:

- `errorCode`
- `droppedChunkCount`
- `promptTokenCount`

## Version 2

Added:

- `translation_suppressed` and `timestamp_repaired` event kinds
- `contextCharacterCount`
- `timestampRepairReason`

## Version 3

Added:

- `segment_filtered` event kind
- `segmentFilterReason` with `empty`, `annotation`, and `noLetters` values

## Version 4

Renamed the `segmentFilterReason` value `noLetters` to `noContent` after numeric utterances became valid content. No version 3 benchmark artifacts existed when this correction was made.

## Version 5

Added the `recognition_completed` event kind so speech-recognition stage timings can travel through the same privacy-safe diagnostics stream as adapter warnings.

## Version 6

Added:

- `probability_repaired` and the typed `probabilityRepairField` detail
- `audioDurationSeconds` and `realTimeFactor` recognition metrics

## Version 7 — current

Added:

- JSONL `model_status` events with typed lifecycle state and optional integer download percentage
- `sdkInputAudioSeconds` so SDK task duration can be compared with authoritative media duration
- `confidence` as a typed probability-repair field

`realTimeFactor` is end-to-end recognition wall time, including automatic language detection but excluding model acquisition and loading, divided by the source file's media duration. `whisper_transcription_wall` remains available for comparison with conventional transcription-only benchmarks. Warm recognizer reuse emits `model_status: already_resident` and omits acquisition/load timing entries rather than recording ambiguous zeroes.

## Evolution Rules

- Increment `DiagnosticEvent.currentSchemaVersion` whenever fields, event kinds, or encoded meanings change incompatibly or materially.
- Update this document in the same commit.
- Prefer optional additive fields when older run artifacts should remain decodable.
- Record the schema version with every benchmark run manifest.
