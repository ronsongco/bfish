# WhisperKit Integration Pre-flight

Date: 2026-08-20

Status: **COMPLETE**. The core result seam, isolated adapter target, mapping tests, and source-only CLI command are implemented. No speech model is downloaded by builds or tests; the first command invocation downloads one unless `--model-path` is supplied.

## Verified Environment

- Apple Silicon (`arm64`)
- macOS 26.4.1
- Xcode 26.6 (`17F113`)
- Swift 6.3.3
- 192 GiB physical memory
- Sufficient local disk for development and accuracy models

The package resolves Swift Argument Parser 1.8.2 and Argmax OSS 1.1.0 under the declared compatible-from-1.0.0 constraint.

## Dependency Decision

Use the renamed Argmax package and only its speech-recognition product:

```swift
.package(
    url: "https://github.com/argmaxinc/argmax-oss-swift.git",
    from: "1.0.0"
)

.product(name: "WhisperKit", package: "argmax-oss-swift")
```

Place the framework adapter in a separate `BFishWhisperKit` target depending on `BFishCore` and `WhisperKit`. Framework types must not enter the public core domain model. The CLI will depend on this adapter target.

The top-level `WhisperKit` class is not `Sendable`. `WhisperKitRecognizer` is therefore an actor that exclusively owns the SDK instance while satisfying the core `SpeechRecognizing` boundary.

## File-mode Configuration

- Development model: `tiny`
- Accuracy baseline: `large-v3-v20240930_626MB`
- Task: `.transcribe`, preserving source-language text
- Temperature: `0`
- Timestamps: enabled
- Chunking: VAD
- Long recordings: `AudioInputOptions(audioLoadingMode: .incremental)`
- Model storage: outside the repository under Application Support, with an optional explicit model-folder override

The first command will operate on audio files only:

```console
bfish transcribe <audio-file> \
  [--model tiny] \
  [--model-path <directory>] \
  [--language auto|<whisper-token>] \
  [--locale <session-locale>] \
  [--incremental]
```

It will print timestamped source text only. Translation remains a separate follow-up so model loading, audio decoding, detection, timestamps, and transcription quality can be measured independently.

## Adapter Mapping

WhisperKit 1.0.0 returns an array of `TranscriptionResult`; every contained `TranscriptionSegment` maps to one `RecognizedSegment`:

| WhisperKit | BFishCore |
|---|---|
| result `language` | validated `WhisperLanguage` |
| segment `start`, `end` | `AudioTimeRange.repairing` |
| segment `text` | `sourceText` |
| `exp(avgLogprob)` clamped to `0...1` | recognition `confidence` estimate |
| segment `noSpeechProb` | `noSpeechProbability` |
| one value created per file invocation | required `CaptureTimeline` |

WhisperKit 1.1 exposes timestamps after its VAD and incremental-file seek processing, but long-form testing shows that returned result boundaries are not reliably monotonic and may drift beyond media duration. The adapter records backward-jump magnitude and aggregate media-duration overflow without silently clamping, sorting, or deduplicating segments. Chunk-boundary reconciliation is required before timestamps can be treated as presentation-safe.

For automatic language selection, call WhisperKit's 30-second `detectLanguage(audioPath:)` first. Validate the returned token, record the selected probability as `languageConfidence`, then latch that language in `DecodingOptions` for the file. An explicit language override skips detection and uses confidence `1.0`.

Mixed-language evidence is not directly provided by the file transcription result. The first adapter will leave `containsMixedLanguages` false and will not use that field to claim code-switch detection. This limitation must be revisited before automatic English bypass is enabled for translation.

## Implemented Core Seam

`SpeechRecognizing.transcribe` returns a core-owned `SpeechRecognitionOutput`, allowing the adapter to forward timestamp-repair diagnostics and recognition timings without leaking SDK types:

```swift
public struct SpeechRecognitionOutput: Sendable {
    public let segments: [RecognizedSegment]
    public let diagnostics: [DiagnosticEvent]
    public let timings: [StageTiming]
    public let metrics: SpeechRecognitionMetrics?
}
```

The translation pipeline and source-only CLI both preserve these adapter diagnostics. Recognition metrics use the source file's media duration as the authoritative RTF denominator and retain WhisperKit's summed task-input duration separately for comparison. RTF includes language detection and transcription but excludes model acquisition/loading; timings separately report those phases and the underlying SDK stages. Model lifecycle and deduplicated integer download progress are also emitted as typed JSONL events on stderr.

## Tests Before Model Execution

- Map valid SDK-shaped segment data into core values without loading a model.
- Repair NaN, infinite, negative, and reversed timestamps and emit one diagnostic per repair.
- Reject an unknown detected-language token with a clear adapter error.
- Preserve one timeline across all chunks/results from one file.
- Propagate `noSpeechProb`, confidence estimate, and detected-language confidence.
- Reject non-file `AudioInput` values in the file adapter.

These model-free checks are implemented. The mapper tests also cover multiple SDK results, shared timeline identity, cross-result monotonicity reporting, Cantonese token coverage, probability repair, and missing-file rejection.

## First Real Smoke Test

Completed on 2026-08-21 with the `tiny` model and a short locally synthesized Japanese fixture. See [the smoke-test record](whisperkit-smoke-2026-08-21.md). The run verified model acquisition/loading, source transcription, monotonic timestamps, authoritative duration, RTF, and parseable JSONL diagnostics; it also exposed and led to correction of unsuppressed Whisper control tokens.

After the adapter builds, allow WhisperKit to download `tiny` and transcribe one short, legally usable fixture. Record:

- model download and load time
- audio duration and loading mode
- full pipeline time and real-time factor
- detected language and probability
- raw and repaired segment timestamps
- peak memory

Only after this source-transcription path is stable should the three-way translation bake-off begin.

The current `--incremental` option bounds audio loading but recognition output remains batch-oriented. Incremental finalized-segment output is required before the podcast and Ollama stages so long recordings do not wait until end-of-file or retain every segment. Language confidence gating and multi-window detection are likewise deferred until smoke-test evidence is available; explicit `--language` remains the reliable override for recordings with intros or known source languages.

## References

- [Argmax OSS Swift](https://github.com/argmaxinc/argmax-oss-swift)
- [Argmax OSS 1.0.0 release](https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.0.0)
- [WhisperKit Core ML models](https://huggingface.co/argmaxinc/whisperkit-coreml)
