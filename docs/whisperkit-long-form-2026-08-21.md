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

The current pipeline now performs the CLI's empty, annotation, and punctuation-only filtering centrally, but recognition remains batch-oriented internally. True finalized-segment streaming is still required before the hour-long fixture becomes a product-experience test.

## Reconciliation validation

Schema-v11 window instrumentation showed that the 9-minute discontinuity came from window 18 returning a segment at 421.20–421.68 seconds even though its authoritative input ended at 419.00 seconds. The next window began correctly at 419.00 seconds. This ruled out accumulated seek-offset drift: the decoder had emitted content beyond its VAD window.

Schema-v12 reconciliation now bounds returned content to each result's reported input extent, uses word timestamps when only part of a segment crosses the boundary, orders retained segments by global media time, and removes exact cross-window text only when its time ranges overlap. The repeated real-audio probe removed the single wholly out-of-window segment, reduced output from 142 to 141 segments, produced zero timeline discontinuities, and preserved the 514.76-second final extent. The removal was recorded as a transcript-free `segment_reconciled` diagnostic.
