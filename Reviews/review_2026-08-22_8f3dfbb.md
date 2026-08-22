# bfish Review #13 — 2026-08-22

Reviewed at commits `f64fc66 Finalize compressed audio handling` and
`8f3dfbb Record thin translation bakeoff`.
Prior reviews: `_08f7d7f` through `_f5f1f5a` (twelve prior).

`swift build` clean, `swift test` 51/51 passing.

The recognition work in `f64fc66` is clean and closes everything outstanding. The bake-off in
`8f3dfbb` reaches a decision that I do not think its evidence supports, and most of this review is
about that.

---

## 0. Disposition of review #12

**§2 16 kHz mono normalization — landed**, now writing `WhisperKit.sampleRate` mono 16-bit, with a
temporary-volume capacity check and safety margin added on top of the recommendation. First-segment
latency improved from 7.03 s to 5.40 s on the 65-minute file and 1.97 s on the 8:39 file.

**§3 signal-safe cleanup — landed and properly tested.** `SignalMonitor` uses `DispatchSourceSignal`
with structured-task cancellation, and it was validated by sending a real `SIGINT` during the
65-minute file's normalization: clean exit, no leaked `bfish-*.caf`. Testing the interrupt path by
actually interrupting is the right standard.

**§1 the VAD classification — ran, and disproved my prediction.** I argued the uncovered ranges were
likely decoder overshoot into silence. VAD found activity in **15 of 22 fragments, 3.17 seconds**.
The response was correct and restrained: VAD activity is not intelligible speech — it also fires on
breathing, music, and boundary fragments — so rather than flipping to "content was lost," the doc
records that the simple silence claim is rejected and leaves recovery as a golden-fixture item. That
is the right way to handle a test that comes back ambiguous, and it is better than what I proposed,
which assumed the answer would be clean.

Fixture hygiene in the bake-off is also good: `provenance`, `license`, and a committed generator
script mean the four fixtures are reproducible without shipping audio.

---

## 1. Whisper direct translation was eliminated by a hardcoded flag, not a capability test

`docs/translation-bakeoff-2026-08-22.md:7`

> WhisperKit direct translation was ineligible because the tested `large-v3-v20240930_626MB` path
> returned source-language text rather than English for all four fixtures.

Verified in the source:

```
Sources/BFishWhisperKit/WhisperKitRecognizer.swift:132:            task: .transcribe,
Sources/BFishWhisperKit/WhisperKitRecognizer.swift:263:            task: .transcribe,
```

Both `DecodingOptions` construction sites hardcode `task: .transcribe`, and `.translate` appears
**nowhere** in `Sources/`. A grep for the decoding task across the whole source tree returns only
`TranslationPipeline`'s call to `translator.translate`, which is the Ollama path.

So "returned source-language text for all four fixtures" is not a finding about Whisper — it is
exactly and only what the code is written to do. There is no code path in `bfish` that asks Whisper
to translate. The model was never given the opportunity to fail.

This matters more than any other item in this review because of what was eliminated. Whisper's
translate task targets English exclusively — X→en is its entire scope, which happens to be precisely
bfish's requirement — and it is supported on `large-v3`. Running it costs **zero additional memory,
zero additional model load, and zero additional latency**, because the model is already resident and
already decoding that audio. If it were competitive, the entire Ollama workstream — HTTP adapter,
structured-output prompting, keep-alive management, model residency, the 9.5 GB of RAM — would be
unnecessary.

That is the exact risk raised in review #1 §5.1: the plan treats alternatives as fallbacks when they
may be strictly better and far cheaper. The bake-off was the mechanism meant to test that, and the
cheapest candidate was disqualified without being run.

The fix is small: add `--task translate` (or an equivalent) to the transcribe path, run the same
four fixtures, and record the result. It is perhaps an hour of work and it is the highest-leverage
hour available right now.

---

## 2. Apple Translation was eliminated on setup friction, not merit

`docs/translation-bakeoff-2026-08-22.md:7`

> the four source-to-English language pairs were reported as **supported but not installed** on this
> host … No UI-driven language download was performed.

The pairs are supported. The assets were simply not downloaded, and downloading them is a one-time,
UI-driven action on a single personal machine.

So the second zero-memory, zero-cost, OS-native candidate was also excluded without being measured.
Both alternatives are now recorded as unavailable or ineligible, and neither was actually compared
against Ollama on translation quality.

For a project deploying to its author's own Macs, "install the language packs once" is a reasonable
prerequisite — considerably more reasonable than committing to an 8 GB model to avoid it. Apple
Translation would also be the strongest candidate for the live profile specifically: no cold load,
no keep-alive management, no contention with WhisperKit for the GPU or ANE, and no memory budget to
plan around.

Recommend installing the four language pairs and re-running before the adapter is built around
Ollama.

---

## 3. The deciding evidence is a single entity in a single fixture

`translategemma:4b` was rejected because it rendered *Estação da Luz* as "Central Station";
`translategemma:12b` preserved it. Every other checked property matched across both models and all
four languages.

Confirmed against a local Ollama instance, the cost difference is substantial:

| model | on-disk size | warm median |
|---|---|---|
| `translategemma:4b` | 3.30 GB | 0.515 s |
| `translategemma:12b` | 8.11 GB | 0.772 s |

So the 12b costs roughly 2.5× the memory and 1.5× the warm latency, and it was selected on **one
observation of one property in one language**. Those two axes — memory and warm latency — are
precisely the ones that matter for the live profile the project is aiming at.

The doc hedges this correctly and repeatedly: "provisional," "an implementation starting point, not
the final live or offline default," "the versioned multilingual benchmark and real conversational
material remain the selection gate." That framing is honest and I am not treating the decision as
final.

The practical concern is momentum rather than correctness. Adapter development, prompt tuning,
timeout defaults, and profile parameters will all now be shaped around a model chosen by n=1, and
those choices are stickier than the doc's caveat suggests. Given the 4b is faster and 2.5× smaller,
it is worth carrying **both** through adapter development rather than dropping the 4b now.

---

## 4. The four fixtures are one test repeated in four languages

Every fixture has the same structure: *let's meet at [place] Station at 3 p.m. today*. Collectively
they exercise proper-noun preservation, a clock time, and a simple imperative.

What they do not exercise is most of what distinguishes a conversational translator:

- **Omitted subjects.** Japanese and Korean drop subjects constantly, and recovering them requires
  the recent context the pipeline was built to supply. This is arguably *the* differentiating
  capability for this project's primary languages, and it is untested.
- ASR-degraded input — the end-to-end track the README defines (`README.md:411`).
- Multi-turn context dependence, negation, questions, hedging and uncertainty, numbers beyond a
  single clock time, and informal or disfluent speech.

The doc is explicit that the probe is "deliberately too small for aggregate quality scoring" and
exists to reject unavailable paths. Fair. But the probe did not only reject — it also *selected*, and
selection on this fixture set carries no signal about the properties that will decide the real
default.

Also worth noting: both the source text and the reference English are project-authored, so the
reference is a closed loop rather than an independent standard. FLEURS and FLORES were adopted at
`README.md:433` precisely to avoid that, and remain unused.

---

## 5. The committed prompt does not match the README's stated requirements

`Benchmarks/Prompts/ollama-translation-v1.txt` is three instruction lines plus the source text. The
README specifies more (`README.md:302-310`), and prompt version is a recorded benchmark variable, so
the gaps matter for reproducibility:

- **No structured output.** The README commits to a schema-constrained response returning
  `{"english_text": ...}`. The probe used freeform text. Model behaviour under JSON constraint often
  differs from freeform — sometimes materially in quality — so v1's results may not transfer to the
  production shape the adapter gate specifies.
- **No context slot.** `TranslationRequest.recentContext` exists and the pipeline's bounded-context
  machinery was built across several reviews, but the prompt has nowhere to put it.
- **No empty/incomplete-input instruction**, despite `README.md:306` requiring the model avoid
  inventing text when transcription is incomplete or empty — which is also the hallucination-safety
  requirement in the scoreboard.

Either v1 should be revised before any scored run, or the eventual production prompt should be
versioned as v2 with the understanding that v1's numbers do not carry over.

---

## 6. The residency probe measures residency, which was never in question

The hedging here is good — "does not measure sustained concurrent inference or establish causality
from the small timing difference" is exactly right, and the 0.993 s versus 1.055 s difference is
correctly not claimed as a result.

Two things worth making sharper:

**An idle resident model does not compete for compute.** The probe held the 12b resident while
WhisperKit ran alone. The live steady state is different in kind: Whisper transcribing utterance
*N+1* while Ollama generates the translation of utterance *N*, both contending for GPU or ANE and
memory bandwidth simultaneously. Residency tells you almost nothing about that.

**192 GiB means residency was never the question.** On this host, a 9.5 GB model and a 626 MB model
coexisting is trivially true. The finding therefore does not generalize to a smaller Mac. If the
project only ever runs on this machine that is fine — but `README.md:64` says "the project owner's
Macs," plural, and the memory-contention requirement at `README.md:441` exists because the answer is
expected to be hardware-dependent. Worth stating which host the defaults are being tuned for.

---

## 7. Smaller note

`SignalMonitor.next()` calls `stream.makeAsyncIterator()` on each invocation
(`Sources/bfish/SignalMonitor.swift:29-32`). `AsyncStream` is a single-consumer stream and multiple
iterators over one instance are undefined. Harmless as currently used — one call site, one await —
but it is the kind of thing that misbehaves quietly if a second caller is added later. Storing the
iterator or exposing the stream directly avoids it.

---

## 8. Suggested order

1. **Run Whisper `task: .translate` on the same four fixtures** (§1). One flag, an hour of work, and
   it is the only candidate that could remove the entire Ollama workstream from the project.
2. **Install the Apple Translation language pairs and re-run** (§2). One-time setup, and it is the
   strongest structural fit for the live profile.
3. **Keep `translategemma:4b` alongside the 12b** through adapter development (§3), since it is 2.5×
   smaller and 1.5× faster and was rejected on a single observation.
4. **Extend the fixtures with omitted-subject and ASR-degraded cases** (§4) before any result is
   treated as a quality signal.
5. **Align the prompt with the README's structured-output and context requirements** (§5), or accept
   that v1 results do not carry forward.

Steps 1 and 2 are the ones I would not skip. The bake-off's stated purpose was to reject unsuitable
paths before committing to a workstream — but both rejections were procedural rather than measured,
and the surviving option is the most expensive one. That is the specific outcome the exercise was
designed to prevent.
