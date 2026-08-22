# WhisperKit Long-Form Probe — 2026-08-21

Two private, uncommitted Japanese podcast files were evaluated locally with `large-v3-v20240930_626MB`. No audio or transcript content is stored in the repository.

## 8:39 single-speaker fixture

- Explicit Japanese: 142 segments, 39.94 seconds recognition wall time, RTF 0.0770
- Automatic detection: Japanese at 0.9989 confidence, 41.49 seconds recognition wall time, RTF 0.0800
- Cached model load: 1.31–1.38 seconds, down from 63.1 seconds on the first Core ML load
- Peak resident memory: 211.7–215.3 MiB
- Last segment end: 514.76 seconds for 518.64 seconds of media
- One deterministic backward start jump of 1.48 seconds near 7:00
- The boundary includes a duplicated short utterance, so suppressing the diagnostic with a tolerance would hide real duplicate output
- All 142 returned VAD segments reported a zero no-speech probability

## 65:06 two-speaker scaling fixture

This run evaluated scaling only; speaker diarization is not implemented.

- 1,623 recognized segments and three centrally filtered segments
- 374.59 seconds recognition wall time, RTF 0.0959 (about 10.4 times faster than real time)
- Cached model load: 1.12 seconds
- Peak resident memory: 274.3 MiB
- 34 backward segment-start jumps, ranging from 0.86 to 14.45 seconds
- Last segment end: 3,930.02 seconds for 3,905.92 seconds of media, an overflow of 24.10 seconds
- All returned VAD segments again reported a zero no-speech probability

## Conclusions

Large-v3 batch recognition speed is viable on the target host, but it does not predict latency for isolated live utterances. Cached loading is fast; the earlier 63-second load was first-load preparation rather than steady state.

WhisperKit's returned long-form timestamps cannot yet be presented directly. The discontinuities scale with duration and include duplicate content as well as media-duration overflow. The next adapter work must preserve global media time while reconciling overlap at result boundaries. A tolerance or blind timestamp clamp is insufficient.

The pipeline performs the CLI's empty, annotation, and punctuation-only filtering centrally. At the time of the original probe recognition was batch-oriented internally; the streaming validation below supersedes that limitation.

## Reconciliation validation

Schema-v11 window instrumentation showed that the 9-minute discontinuity came from window 18 returning a segment at 421.20–421.68 seconds even though its authoritative input ended at 419.00 seconds. The next window began correctly at 419.00 seconds. This ruled out accumulated seek-offset drift: the decoder had emitted content beyond its VAD window.

Schema-v12 reconciliation now bounds returned content to each result's reported input extent, uses word timestamps when only part of a segment crosses the boundary, orders retained segments by global media time, and removes exact cross-window text only when its time ranges overlap. The repeated real-audio probe removed the single wholly out-of-window segment, reduced output from 142 to 141 segments, produced zero timeline discontinuities, and preserved the 514.76-second final extent. The removal was recorded as a transcript-free `segment_reconciled` diagnostic.

## Finalized-segment streaming validation

The file adapter now performs its own bounded VAD staging, transcribes authoritative windows sequentially, reconciles each completed window, and emits its finalized segments before reading and decoding the remainder of the file. The core recognition protocol carries segment, diagnostic, and completion events; batch recognizers retain a compatibility implementation.

On the 8:39 fixture, terminal output appeared while the process was still running: approximately three minutes of timestamped source output had been delivered well before recognition completion. The final result matched the reconciled batch baseline with 24 windows, 141 segments, one out-of-window removal, zero discontinuities, a 514.76-second final segment end, and no media overflow. Completed transcript objects are not retained by the streaming adapter; only numeric values required for final aggregate metrics remain in memory.

## Schema-v14 65-minute validation

The two-speaker fixture was normalized to a temporary 16 kHz mono PCM file because seeking the compressed MP3 directly through `AVAudioFile` raised an Objective-C Core Audio exception. The source file was not modified, and neither audio nor transcript content is retained in the repository. Direct compressed-file incremental loading remains an adapter issue to resolve separately.

The post-fix streaming run completed with:

- 177 recognition windows and 1,594 reconciled segments; 1,593 source turns were printed and one segment was centrally filtered
- 374.30 seconds recognition wall time, RTF 0.09583, effectively unchanged from the pre-reconciliation 0.0959 result
- first finalized segment at 1,973ms after recognition start
- 44 privacy-safe reconciliation events: 42 wholly outside their authoritative windows, one timestamp clip, and one word-level boundary trim
- zero timeline discontinuities, zero segments beyond the 3,905.92-second media duration, and zero retained temporal overlaps
- final segment end at 3,890.04 seconds
- 190.8 MiB peak RSS and 90.8 MiB physical footprint
- no missing/invalid seek-time repairs on this run

This closes the long-form reconciliation finding: all 34 prior backward jumps and the prior 24.10-second overflow were removed without measurable RTF regression. The zero overlapping-survivor count indicates that exact-text duplicate matching was not masking partial duplicate seams in this fixture. The active-overlap duplicate scan avoids normalizing every historical segment pair.

The pre-fix count of 1,623 segments and schema-v14 count of 1,594 are not directly comparable: the runs used different chunking mechanisms, different input representations (compressed MP3 versus normalized PCM), and different reconciliation behavior. No duplicate-removal rate should be inferred from their difference. The zero-discontinuity, zero-overflow, and zero-overlap results are absolute properties of the reconciled run.

## Schema-v15 direct-MP3 validation

Compressed-input normalization was then moved into the adapter and the original 65-minute MP3 was passed directly to `bfish`. The adapter decoded it sequentially to temporary 16-bit linear PCM in 4.41 seconds, avoided compressed seeking, and removed the temporary file at termination. The complete run reported:

- 177 recognition windows and 1,603 reconciled segments; 1,602 source turns were printed and one was centrally filtered
- 380.35 seconds recognition wall time including normalization, RTF 0.09738
- first finalized segment at 7.03 seconds including normalization
- 43 reconciliation events: 41 wholly outside their authoritative windows, one timestamp clip, and one word-level boundary trim
- zero timeline discontinuities, zero media overflow, zero retained overlaps, and zero seek repairs
- final segment end at 3,890.04 seconds, making the 15.88-second shortfall one trailing media region rather than a sum inferred from discarded segments
- 1,574 internal inter-segment gaps totaling 1,126.45 seconds, with a maximum of 22.60 seconds; these include ordinary pauses and non-speech and are not themselves evidence of lost content
- 24 of 41 discarded out-of-window ranges were not covered by a retained timestamp range, totaling 4.57 seconds across the file
- 203.9 MiB peak RSS and 93.0 MiB physical footprint

The coverage result bounds but does not semantically classify the remaining uncertainty: out-of-window decoder output is often speculative duplication or hallucination, and the fixture has no reference transcript capable of proving that all 4.57 seconds represented speech. The aggregate is small relative to the 65-minute file, while the absolute continuity, overflow, and overlap invariants remain satisfied. A future conversational golden fixture can determine whether uncovered discarded ranges correlate with meaningful words.

The schema-v14 PCM and schema-v15 direct-MP3 segment counts are also not a duplicate-removal comparison. The automatic decoder preserved the MP3's native channel/rate representation in temporary PCM, whereas the earlier manual fixture was downmixed and resampled with `ffmpeg`; that difference can change VAD boundaries and decoder segmentation.

## Schema-v16 normalized-input and VAD validation

The adapter now converts compressed input once to 16 kHz mono, 16-bit PCM and checks temporary-volume capacity before writing. A real `SIGINT` during the 65-minute file's normalization canceled the structured transcription task, exited successfully, and left no `bfish-*.caf` temporary file. The 8:39 MP3 then completed with 616ms normalization, 1.97 seconds to first finalized segment, and no leaked temporary file.

The definitive 65-minute run reported:

- 4.36 seconds normalization and 5.40 seconds to first finalized segment
- 377.54 seconds recognition wall time including normalization, RTF 0.09666
- 177 windows, 1,571 recognized segments, five centrally filtered segments, zero discontinuities, zero overflow, zero overlaps, and zero seek repairs
- 39 wholly out-of-window removals; 22 had uncovered fragments totaling 4.31 seconds
- 15 uncovered fragments crossed the staging VAD threshold, totaling 3.17 seconds
- 194.1 MiB peak RSS and 91.8 MiB physical footprint

The VAD result rejects the simple claim that all uncovered decoder overshoot occurred in silence. It still does not prove that 3.17 seconds of intelligible speech were lost: VAD also responds to boundary fragments, breathing, music, and other energetic audio, and the out-of-window timestamps are themselves decoder output. Reconciliation remains temporally stable, but meaningful-content recovery at window seams stays an explicit golden-fixture evaluation item rather than a closed finding.

The v16 segment count should not be compared mechanically with earlier runs. Although both the manual and automatic paths target 16 kHz mono PCM, Core Audio and `ffmpeg` can differ in downmix, resampling, priming, and rounding behavior, which can alter VAD boundaries.
