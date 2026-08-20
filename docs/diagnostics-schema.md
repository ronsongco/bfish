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

## Version 4 — current

Renamed the `segmentFilterReason` value `noLetters` to `noContent` after numeric utterances became valid content. No version 3 benchmark artifacts existed when this correction was made.

## Evolution Rules

- Increment `DiagnosticEvent.currentSchemaVersion` whenever fields, event kinds, or encoded meanings change incompatibly or materially.
- Update this document in the same commit.
- Prefer optional additive fields when older run artifacts should remain decodable.
- Record the schema version with every benchmark run manifest.
