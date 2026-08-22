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

## Version 11

Added privacy-safe `recognition_window` events. Each records the SDK result index, reported seek start, input-audio duration and end, first returned segment start, last returned segment end, and timestamp overflow beyond that result's reported input extent. These values distinguish incorrect seek offsets from decoder timestamps extending into padded audio without logging transcript content.

## Version 12

Added `segment_reconciled` with typed reasons for content outside its authoritative recognition window, word-timestamp trimming, timestamp clipping, and duplicate overlapping text. Reconciliation diagnostics record only counts and time ranges, never removed text. Result windows are processed by absolute seek time, timestamps are bounded to their SDK-reported input extent, and exact cross-window duplicates must overlap in media time before removal.

## Version 13

Added aggregate `compressionRatioDistribution` and the `knownHallucination` and `repetitive` segment-filter reasons. Exact multilingual variants of Whisper's common “thanks for watching” silence hallucination were initially blocked before translation. Segments above the configurable compression-ratio ceiling (2.4 by default) are treated as pathological repetition.

## Version 14

Added:

- `window_seek_repaired`, emitted when a recognition result omits or supplies an invalid seek time; the adapter uses the preceding resolved window end rather than silently treating the result as starting at zero
- `firstSegmentLatencyMilliseconds`, measured from recognition start to the first finalized segment
- `overlappingSurvivorCount`, the number of finalized segments that still overlap an earlier retained segment in media time

Known hallucination phrases are now quarantined rather than deleted: the source turn remains visible with `suspected_hallucination`, while translation and context retention are suppressed. The existing `knownHallucination` filter reason remains decodable for schema-v13 artifacts but is no longer emitted by the current pipeline.

## Version 15

Added privacy-safe reconciliation coverage metrics to `recognition_completed`:

- `internalGapCount`, `totalInternalGapSeconds`, and `maximumInternalGapSeconds`
- `trailingGapSeconds`
- `removedRangeCount`, `uncoveredRemovedRangeCount`, and `uncoveredRemovedRangeSeconds`

Internal gaps are measured between retained segment time ranges and exclude the initial and trailing media regions. Removed-range coverage compares wholly out-of-window decoder ranges against the union of retained segment ranges after clipping both to authoritative media duration. These aggregates contain no transcript or audio content.

Compressed inputs are decoded sequentially into a private temporary linear-PCM file before incremental seeking. `audio_normalization_wall` records that preprocessing cost when normalization occurs; linear-PCM inputs omit the timing rather than reporting zero.

## Version 16 — current

Added `uncoveredRemovedRangesWithVoiceCount` and `uncoveredRemovedRangesWithVoiceSeconds`. After reconciliation, the adapter applies the same voice-activity detector used for chunk staging to uncovered portions of wholly out-of-window decoder ranges. These fields report how many uncovered fragments crossed the VAD threshold and their combined duration. Voice activity is supporting evidence, not proof of intelligible speech or content loss.

Compressed inputs are now normalized once to 16 kHz mono, 16-bit PCM. Before writing, the adapter estimates the output size and requires the temporary volume to have that capacity plus a 10% or 64 MiB safety margin, whichever is larger. Insufficient capacity produces a typed error before decoding begins.

## Evolution Rules

- Increment `DiagnosticEvent.currentSchemaVersion` whenever fields, event kinds, or encoded meanings change incompatibly or materially.
- Update this document in the same commit.
- Prefer optional additive fields when older run artifacts should remain decodable.
- Record the schema version with every benchmark run manifest.
