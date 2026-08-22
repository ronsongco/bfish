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

## Version 7

Added:

- JSONL `model_status` events with typed lifecycle state and optional integer download percentage
- `sdkInputAudioSeconds` so SDK task duration can be compared with authoritative media duration
- `confidence` as a typed probability-repair field

`realTimeFactor` is end-to-end recognition wall time, including automatic language detection but excluding model acquisition and loading, divided by the source file's media duration. `whisper_transcription_wall` remains available for comparison with conventional transcription-only benchmarks. Warm recognizer reuse emits `model_status: already_resident` and omits acquisition/load timing entries rather than recording ambiguous zeroes.

## Version 8

Added `selectedLanguage`, `languageConfidence`, and `automaticLanguageDetection` to recognition-completion details. These privacy-safe fields make the selected Whisper token and the evidence behind automatic selection available to benchmark consumers without including transcript content. WhisperKit 1.1 returns language log probabilities; `bfish` exponentiates the selected language's value and reports the resulting `0...1` confidence.

## Version 9

Added privacy-safe long-form calibration details:

- `segmentCount` and `lastSegmentEndSeconds`
- aggregate `confidenceDistribution` and `noSpeechProbabilityDistribution` summaries containing count, minimum, median, 90th percentile, and maximum
- `peakResidentMemoryBytes`
- `segmentsBeyondAudioDurationCount` and `maximumTimestampOverflowSeconds`
- `previousSegmentStartSeconds`, `currentSegmentStartSeconds`, and `segmentStartDeltaSeconds` on timeline discontinuities

These fields intentionally contain no transcript text. A negative segment-start delta measures the magnitude of a detected overlap before any tolerance or timestamp-repair policy is selected.

Distribution percentiles use the nearest-index estimator over sorted values: `round((count - 1) × fraction)`. This intentionally favors a stable, dependency-free calibration summary and may differ from interpolated percentiles reported by external tools.

## Version 10

Added `physicalFootprintBytes`, obtained from Darwin's `proc_pidinfo` task information. It complements peak RSS with the macOS memory-pressure accounting needed for simultaneous WhisperKit and translation-model tests.

## Version 11 — current

Added privacy-safe `recognition_window` events. Each records the SDK result index, reported seek start, input-audio duration and end, first returned segment start, last returned segment end, and timestamp overflow beyond that result's reported input extent. These values distinguish incorrect seek offsets from decoder timestamps extending into padded audio without logging transcript content.

## Evolution Rules

- Increment `DiagnosticEvent.currentSchemaVersion` whenever fields, event kinds, or encoded meanings change incompatibly or materially.
- Update this document in the same commit.
- Prefer optional additive fields when older run artifacts should remain decodable.
- Record the schema version with every benchmark run manifest.
