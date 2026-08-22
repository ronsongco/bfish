# WhisperKit Utterance Latency Probe — 2026-08-21

Five private, temporary excerpts of 3, 4, 5, 6, and 8 seconds were taken from the 8:39 Japanese podcast fixture. The excerpts and transcripts are not committed. Each excerpt was processed in a separate release-build CLI invocation using `large-v3-v20240930_626MB`, explicit Japanese, and incremental file loading.

| Duration | Recognition wall time | RTF | Segments |
|---:|---:|---:|---:|
| 3s | 856ms | 0.285 | 1 |
| 4s | 894ms | 0.224 | 1 |
| 5s | 967ms | 0.193 | 2 |
| 6s | 1,050ms | 0.175 | 2 |
| 8s | 1,222ms | 0.153 | 4 |

Median recognition latency was 967ms. This confirms that the 0.077 long-file RTF cannot be multiplied by utterance duration to predict live latency: fixed per-inference work is significant on short input.

Each standalone process also spent approximately 1.17–1.42 seconds loading the cached model. That cost is excluded from recognition latency and is not paid per utterance by the actor-owned recognizer in a persistent CLI or app session.

The recognition result leaves approximately 2–3 seconds of a 3–4 second live subtitle budget for translation, queueing, and presentation. Translation is therefore the latency-critical stage for the forthcoming three-way bake-off.

The repeatable harness is `Scripts/benchmark-utterance-latency.sh`. It emits one privacy-safe JSON object per fixture, uses fixture indexes rather than paths, and reads timing data from schema-versioned diagnostics.
