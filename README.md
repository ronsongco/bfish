# bfish

`bfish` is a local, terminal-first speech translation tool for Apple Silicon Macs. It captures audio routed from applications or audio devices, transcribes the speech in its original language, translates the transcript into English, and displays both the source text and English translation in the terminal.

The project is intended for personal use on macOS 26 or later. All speech recognition and translation should run locally after the required models have been downloaded.

> **Project status:** Architecture and pre-scaffolding. No working executable exists yet.

## Goals

- Capture live audio routed through Audio Hijack.
- Transcribe multilingual speech with WhisperKit.
- Preserve and display the source-language transcript.
- Translate finalized transcript segments into English with a local LLM served by Ollama.
- Print stable, readable results in a terminal.
- Keep audio, transcripts, and translations local to the Mac.
- Build the core as reusable Swift code that can later power a native SwiftUI application.

## Initial Scope

The first interface will be a command-line executable named `bfish`. SwiftUI development is intentionally deferred until the audio, transcription, and translation pipeline is stable.

The first proof of concept will process an existing audio file. Live audio capture and Audio Hijack integration will follow after file transcription and Ollama translation are working reliably.

### Supported platform

- macOS 26 or later
- Apple Silicon
- Current Swift and Xcode toolchain supported by macOS 26
- Personal deployment to the project owner's Macs

Intel Macs and older macOS versions are out of scope.

## Language Priorities

The system will ultimately handle the multilingual languages supported by the selected WhisperKit model. Testing and optimization will prioritize these languages.

Primary languages:

1. Japanese
2. Korean
3. Mandarin Chinese
4. Brazilian Portuguese

Secondary languages:

1. Tagalog
2. Spanish
3. Italian

Source-language detection should be automatic by default, with an explicit language override available when needed. Brazilian Portuguese should be identified as `pt-BR` when that distinction is available. Mandarin source text will preserve the script produced by WhisperKit.

## User Experience

The default terminal output will always show the source transcript alongside its English translation:

```text
[00:01:42] [ja]
Source: 今日は天気がいいですね。
English: The weather is nice today.

[00:01:49] [pt-BR]
Source: Vamos começar depois do almoço.
English: Let's start after lunch.
```

Output should be committed at stable utterance boundaries rather than continuously rewriting speculative partial text. The initial latency target is an English result within approximately two to four seconds after an utterance ends, subject to model and hardware performance.

Future output modes may include JSON Lines for integration with other programs and an explicit English-only option. Neither will change the default source-plus-English presentation.

## Architecture

`bfish` will be a native Swift package built around a reusable `BFishCore` library. The terminal executable will be the first client of that library; a future SwiftUI application should use the same capture, recognition, segmentation, translation, and formatting components without moving their implementation into the UI target.

The architecture separates four concerns:

1. Acquiring audio from a file, an input device, the entire system, or a selected process.
2. Converting continuous audio into stable speech utterances.
3. Transcribing each utterance in its source language with WhisperKit.
4. Translating finalized source text to English with Ollama and presenting both forms.

### Live data flow

The planned live pipeline is:

```text
Audio file, input device, system audio, or selected application
                              ↓
                         Audio source
                              ↓
                 PCM normalization/resampling
                              ↓
              Voice activity and rolling buffer
                              ↓
          Overlapping utterance segmentation queue
                              ↓
             WhisperKit source transcription
                              ↓
       Boundary deduplication and sentence assembly
                              ↓
       Ollama translation with bounded recent context
                              ↓
          Timestamp + language + source + English
```

For an Audio Hijack workflow, the first portion becomes:

```text
Application or microphone
        ↓
Audio Hijack session
        ├──→ Speakers or headphones
        └──→ Loopback or BlackHole virtual device
                              ↓
                    bfish device capture
```

On macOS 26, `bfish` should also support direct system-wide or per-application capture through Apple's Core Audio process-tap APIs, with ScreenCaptureKit retained as an alternate backend if useful. This makes Audio Hijack optional for simple capture while preserving it for deliberate routing, mixing, channel selection, and audio processing.

### Component boundaries

The Swift package will separate reusable behavior from command-line presentation:

```text
bfish/
├── Package.swift
├── Sources/
│   ├── BFishCore/
│   │   ├── Audio/
│   │   ├── Speech/
│   │   ├── Translation/
│   │   ├── Pipeline/
│   │   └── Configuration/
│   └── bfish/
│       └── CLI entry point
├── Tests/
│   └── BFishCoreTests/
├── Fixtures/
├── docs/
└── Scripts/
```

The main integration boundaries will be protocol-based so implementations can be tested or replaced:

```swift
protocol AudioCapturing
protocol SpeechRecognizing
protocol TextTranslating
protocol SpeechSegmenting
protocol TranscriptFormatting
```

Initial implementations are expected to include:

- `FileAudioSource`
- `CoreAudioDeviceSource`
- `WhisperKitRecognizer`
- `OllamaTranslator`
- `TerminalTranscriptFormatter`

Later implementations should include:

- `CoreAudioSystemSource`
- `CoreAudioProcessSource`
- An optional `ScreenCaptureKitSource`
- `WhisperDirectTranslator` as a benchmark and fallback

This design allows a future SwiftUI target to consume `BFishCore` without moving or rewriting the transcription pipeline.

### Package dependency direction

Dependencies should point inward toward stable domain types:

```text
bfish CLI ───────────────┐
                        ↓
Future SwiftUI app → BFishCore pipeline
                        ↑
          ┌─────────────┼──────────────┐
          │             │              │
   Audio adapters  WhisperKit     Ollama client
```

`BFishCore` will own transcript segments, translations, configuration, pipeline state, and protocol definitions. Framework-specific types from WhisperKit, AVFoundation, Core Audio, or HTTP responses should be converted at adapter boundaries and should not leak through the public domain model.

### Concurrency and backpressure

Live capture must not block the real-time audio callback. Audio frames should be copied into a bounded buffer and processed by asynchronous workers outside the callback. The pipeline should have explicit limits for queued audio and pending translations.

The initial policy should favor completeness during normal load. If inference falls substantially behind live audio, the pipeline should report the lag and use an explicit recovery policy instead of silently growing memory without bound. Any decision to skip stale audio must be visible in diagnostics.

### Stable segmentation

Fixed-duration chunks tend to cut words, repeat text, and create artificial punctuation. The planned segmenter will instead:

1. Detect speech and meaningful pauses.
2. Maintain a rolling audio buffer.
3. Produce utterances with a small overlap at their boundaries.
4. Remove duplicated text created by overlapping transcription.
5. Assemble complete source-language sentences where possible.
6. Send only finalized sentences to Ollama.

An optional later streaming mode may re-transcribe the rolling tail and commit text only after consecutive decoding passes agree. Provisional text must be visually distinct and must never be treated as final translation context.

### Error isolation

Capture, transcription, and translation failures should be distinguishable:

- A recoverable Ollama failure should preserve and print the source transcript.
- A failed utterance should not necessarily terminate a healthy live capture session.
- Audio-device removal should trigger a clear state transition and reconnection attempt or controlled shutdown.
- `SIGINT` and `SIGTERM` should stop capture, drain or cancel bounded work, release audio resources, and leave terminal output valid.

## Speech Recognition

[WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) is the selected speech recognition engine. It provides a Swift-native Whisper implementation optimized for Apple Silicon and Core ML.

WhisperKit will initially transcribe speech in the source language rather than translate directly to English. A multilingual Whisper model is required; English-only `.en` models are not appropriate for this project.

Model selection will remain configurable. The anticipated development defaults are:

- `tiny` for fast development and automated tests
- `small` as the initial quality and performance candidate
- Larger models evaluated where hardware capacity and accuracy requirements justify them

Whisper's direct English translation task will remain available as a future fallback and comparison baseline.

## Local Translation with Ollama

[Ollama](https://ollama.com/) will serve the local language model used for English translation and contextual cleanup. The Swift client will communicate with Ollama through its local HTTP API using `URLSession`; no Python service or third-party Swift client is required.

The default local endpoint is expected to be:

```text
http://127.0.0.1:11434/api
```

The Ollama model will be configurable rather than hard-coded. A default will be chosen after testing installed models for:

- Translation quality across the priority languages
- End-to-end latency
- Memory consumption
- Contention with WhisperKit on the same Apple Silicon system
- Consistent preservation of names, numbers, and uncertainty

Only finalized speech segments should be submitted to Ollama. Each request may contain a small amount of recent transcript context for disambiguation, but prior context must not be retranslated or repeated.

The initial implementation should use low-temperature, non-streaming, structured responses. Conceptually, Ollama will return:

```json
{
  "source_language": "ja",
  "source_text": "今日は天気がいいですね。",
  "english_text": "The weather is nice today."
}
```

Translation prompts must instruct the model to:

- Return a translation without commentary.
- Preserve names, numbers, tone, and meaningful uncertainty.
- Avoid inventing text when transcription is incomplete or empty.
- Use previous segments only to resolve ambiguity.
- Keep source text unchanged in the structured response.

## Audio Hijack Integration

[Audio Hijack](https://www.rogueamoeba.com/audiohijack/) will select and route application or microphone audio. A planned session will branch its audio to both the listener and `bfish`:

```text
Application Source
    ├── Output Device: speakers or headphones
    └── Output Device: virtual audio device
```

The `bfish` CLI will open the virtual device as an audio input. The preferred bridge is an existing Rogue Amoeba Loopback device when available; otherwise, [BlackHole](https://github.com/ExistentialAudio/BlackHole) is the planned open-source option.

The virtual audio device is an external prerequisite and will not initially be bundled with `bfish`. This avoids building and maintaining a custom Core Audio driver and keeps third-party driver installation and licensing separate from this repository.

Audio Hijack is one supported capture path, not a required runtime dependency. The planned capture modes are:

```console
# Audio Hijack, Loopback, BlackHole, microphone, or another input device
bfish listen --device "BlackHole 2ch"

# Direct macOS system-audio capture
bfish listen --system

# Direct capture of one application
bfish listen --app com.apple.Safari
```

Direct capture is useful for simple sources and removes virtual-device setup. Audio Hijack remains preferable when the user wants to combine sources, apply effects, isolate channels, or maintain a reusable visual routing session.

## Planned CLI

The exact command syntax may evolve, but the intended interface is:

```console
# Check system dependencies, services, and model availability
bfish doctor

# List available Core Audio input devices
bfish devices

# Transcribe and translate an existing audio file
bfish translate recording.wav \
  --whisper-model small \
  --ollama-model <model>

# Listen to routed live audio
bfish listen \
  --device "BlackHole 2ch" \
  --source-language auto \
  --whisper-model small \
  --ollama-model <model>

# Compare Ollama with Whisper's direct translation
bfish listen --translator ollama --ollama-model <model>
bfish listen --translator whisper
```

`Ctrl-C` should stop capture cleanly. Operational diagnostics and model-loading progress should be written to standard error so translated output on standard output can be redirected or consumed by another process.

## Configuration

Values expected to be configurable include:

- Audio input device name or stable Core Audio UID
- WhisperKit model
- Ollama endpoint
- Ollama model
- Automatic or explicit source language
- Translation engine
- Context window duration or segment count
- Output format
- Timestamp display
- Logging verbosity

Model files and generated caches should live outside the Git repository in Application Support or another configurable cache directory.

## Reliability and Privacy Requirements

- Audio and text remain on the local Mac.
- Network access is only expected when initially downloading models or dependencies.
- Empty or low-confidence speech must not produce invented translations.
- Device disconnection and Ollama unavailability must produce clear terminal errors.
- Interrupting the CLI must stop audio capture and release resources cleanly.
- One failed segment should not necessarily terminate an otherwise healthy live session.
- Stable device identifiers should be used internally even when the CLI accepts human-readable names.

## Offline Translation Model Evaluation

Choosing the Ollama model is a separate engineering workstream from choosing a WhisperKit model. Speech-recognition quality and translation quality must not be collapsed into one measurement because an incorrect transcript can make a capable translation model appear weak.

The project will maintain a reproducible benchmark and scoreboard for local translation models. Candidate names, parameter sizes, and quantizations will remain data rather than being hard-coded into the application.

### Benchmark tracks

The evaluation suite will contain two tracks:

1. **Translation-only:** Every model receives the same curated source text. This isolates the LLM's translation behavior from speech-recognition errors.
2. **End-to-end:** Every model receives fixed WhisperKit transcripts containing realistic recognition mistakes, missing punctuation, partial words, and segmentation boundaries. This measures behavior in the actual `bfish` pipeline without rerunning WhisperKit for every model.

Live audio timing will be evaluated separately after the text benchmark is stable.

### Test corpus

The corpus should be versioned and balanced across the primary and secondary languages. Each language should include:

- Short conversational utterances
- Longer podcast and interview turns
- Multi-turn exchanges where pronouns or omitted subjects require recent context
- Multiple-speaker turns with stable anonymous speaker IDs
- Names, places, dates, money, percentages, measurements, and technical terminology
- Informal speech, slang, hesitation, and incomplete sentences
- Questions, negation, uncertainty, humor, and idiomatic language
- Clean source text and paired ASR-degraded variants
- Silence/empty-input cases that must not produce a translation

Reference translations should be human-reviewed. Automated metrics may assist comparison, but they will not be treated as sufficient evidence of conversational translation quality.

### Controlled execution

Every scored run must record:

- Host model, memory size, and macOS version
- Ollama version
- Exact model tag, parameter size, file size, and quantization
- Prompt-template version
- Temperature, context size, seed when supported, and keep-alive behavior
- Cold-load and warm-run measurements
- Whether WhisperKit or another major workload was running concurrently

All models must receive the same prompt and structured-output schema unless the run is explicitly labeled as a model-specific prompt experiment. Each fixture should be run multiple times when the backend cannot guarantee deterministic output.

### Scoring dimensions

The scoreboard will report raw measurements and a weighted score. Scores must also be shown per language so strong performance in one language cannot hide poor performance in another.

| Category | Weight | Measurements |
|---|---:|---|
| Meaning preservation | 25 | Human adequacy rating; omissions; reversals; mistranslations |
| English quality | 10 | Fluency, grammar, and natural conversational phrasing |
| Details and entities | 10 | Names, numbers, dates, units, terminology, and negation preserved |
| Hallucination control | 10 | Invented content, commentary, and non-empty answers for empty input |
| ASR robustness | 10 | Quality on noisy, incomplete, or poorly punctuated WhisperKit text |
| Context and speakers | 5 | Correct use of bounded history without merging or reassigning speakers |
| Structured-output reliability | 5 | Valid schema, unchanged source text, and no extra prose |
| Warm translation latency | 10 | Median and 95th-percentile time per finalized utterance |
| Resource use | 10 | Peak memory, model size, and contention with WhisperKit |
| Startup behavior | 5 | Cold-load time and first-result latency |

The overall score is useful for ranking, but model selection should consider two published views:

- **Quality leader:** highest language-balanced translation quality regardless of resource cost.
- **Live-use leader:** best model meeting the latency and memory budget on the target Mac.

A model that fails mandatory checks—such as frequently producing invalid output, changing source text, or hallucinating on empty input—should be marked ineligible even if its aggregate score is high.

### Benchmark artifacts

The planned benchmark layout is:

```text
Benchmarks/
├── Fixtures/
│   ├── ja/
│   ├── ko/
│   ├── zh/
│   ├── pt-BR/
│   ├── tl/
│   ├── es/
│   └── it/
├── Prompts/
├── Runs/
└── Scoreboards/
```

Fixture inputs and raw results should use JSON Lines so runs can be reproduced and re-scored. Each result must retain the source text, reference translation, model output, parsed structured response, timing, resource measurements, model metadata, and evaluator scores.

The generated scoreboard should be available as both CSV and readable Markdown, including:

- Overall and per-language scores
- Translation-only and end-to-end results
- Median and 95th-percentile latency
- Peak memory and model disk size
- Structured-output failure and hallucination rates
- Test date, host, Ollama version, prompt version, and corpus revision

Benchmark tooling should eventually be exposed through a command such as:

```console
bfish benchmark translation \
  --models <model-a>,<model-b>,<model-c> \
  --suite Benchmarks/Fixtures \
  --output Benchmarks/Runs/<run-id>
```

## Development Milestones

### 1. Project foundation

- Initialize the local Git repository.
- Create the Swift package, library target, CLI target, and tests.
- Add configuration, logging, and error conventions.
- Implement `bfish doctor`.

### 2. Audio-file proof of concept

- Load a known audio file.
- Transcribe it in the source language with WhisperKit.
- Translate the transcript through Ollama.
- Print source text and English output with timing information.

### 3. WhisperKit language evaluation

- Assemble short, legally usable test fixtures for the priority languages.
- Compare candidate WhisperKit models independently of Ollama.
- Record latency, memory usage, detected language, and transcript quality.
- Select a speech-recognition default while preserving command-line overrides.

### 4. Offline LLM translation scoreboard

- Build the versioned multilingual text and ASR-degraded fixture corpus.
- Implement repeatable Ollama model runs and structured result capture.
- Add deterministic checks and human-review fields.
- Generate per-language, quality-leader, and live-use scoreboards.
- Test WhisperKit and Ollama memory contention on the target hardware.
- Select an initial Ollama default while preserving command-line overrides.

### 5. Live Core Audio capture

- Enumerate input devices.
- Select devices by stable identifier.
- Capture and resample audio.
- Add direct system-wide and per-application capture.
- Handle device changes and clean shutdown.

### 6. Segmentation and continuous translation

- Detect speech and silence.
- Maintain a rolling audio buffer.
- Finalize utterances with limited overlap.
- Suppress duplicated transcription across chunks.
- Supply bounded context to Ollama.

### 7. Audio Hijack validation

- Document the Audio Hijack session setup.
- Validate routing through Loopback or BlackHole.
- Confirm simultaneous listening and translation.
- Measure sustained latency and resource usage.

### 8. Native macOS application

- Add a SwiftUI target consuming `BFishCore`.
- Provide device and model selection.
- Add start/stop controls and source-plus-English presentation.
- Consider menu-bar operation only after the core workflow is stable.

## Initial Acceptance Criteria

The first useful live milestone is complete when:

1. Foreign-language audio is routed through Audio Hijack to a virtual device.
2. One `bfish` command begins listening to that device.
3. WhisperKit detects and transcribes the source language locally.
4. Ollama translates finalized segments locally.
5. The terminal displays timestamps, language, source text, and stable English text.
6. The process runs continuously and stops cleanly with `Ctrl-C`.

## Current Next Step

Scaffold the Swift package and implement `bfish doctor`, then build the audio-file proof of concept before adding live capture or SwiftUI. The current host is Apple Silicon on macOS 26.4.1 with Swift 6.3.1. Only the Command Line Tools developer directory is currently selected, so full Xcode availability and selection must be resolved before WhisperKit integration is validated. Ollama is installed, but its running service and installed model list still need to be checked outside the restricted development probe.

## Related Projects and Prior Art

The design intentionally draws on existing open-source work rather than treating this pipeline as novel:

- [Live Translation](https://github.com/KazKozDev/live-translation) is the closest behavioral match: BlackHole audio, MLX Whisper, Ollama translation, VAD, overlap-aware segmentation, and bilingual output. It validates the workflow but uses Python and PyObjC rather than a reusable native Swift core.
- [hark](https://github.com/PhantomYdn/hark) is the strongest native CLI reference. It demonstrates Swift system/per-process audio capture, WhisperKit integration, device and model management, stdout/stderr conventions, and clean signal handling.
- [Parrot](https://github.com/turantekin/Parrot) demonstrates a larger native SwiftUI architecture using ScreenCaptureKit, AVAudioEngine, WhisperKit, and optional Ollama.
- [Pindrop](https://github.com/watzon/pindrop) demonstrates a native WhisperKit application with model management and optional Ollama transcript processing.
- [AudioCap](https://github.com/insidegui/AudioCap) provides focused sample code for Apple's Core Audio process-tap APIs.
- [CoreAudioTapKit](https://github.com/CJStanfield/CoreAudioTapKit) packages process-tap and aggregate-device lifecycle management as a Swift library worth evaluating before implementing those mechanics directly.

These projects are references and potential dependency candidates. Code should not be copied without reviewing its license, attribution requirements, API stability, and suitability for the narrower `bfish` architecture.

## References

- [WhisperKit / Argmax OSS](https://github.com/argmaxinc/argmax-oss-swift)
- [Ollama API documentation](https://docs.ollama.com/api)
- [Ollama structured outputs](https://docs.ollama.com/capabilities/structured-outputs)
- [Audio Hijack manual](https://www.rogueamoeba.com/support/manuals/audiohijack/)
- [BlackHole virtual audio driver](https://github.com/ExistentialAudio/BlackHole)
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
- [Live Translation](https://github.com/KazKozDev/live-translation)
- [hark](https://github.com/PhantomYdn/hark)
- [Parrot](https://github.com/turantekin/Parrot)
- [Pindrop](https://github.com/watzon/pindrop)
- [AudioCap](https://github.com/insidegui/AudioCap)
- [CoreAudioTapKit](https://github.com/CJStanfield/CoreAudioTapKit)
