#!/bin/zsh

set -euo pipefail

if (( $# < 3 )); then
  print -u2 "usage: $0 <model> <language> <audio-file> [audio-file ...]"
  exit 64
fi

model=$1
language=$2
shift 2

repository_root=${0:A:h:h}
binary="$repository_root/.build/release/bfish"
if [[ ! -x "$binary" ]]; then
  print -u2 "missing release binary: run 'swift build -c release' first"
  exit 69
fi
if ! command -v jq >/dev/null; then
  print -u2 "jq is required"
  exit 69
fi

temporary_directory=$(mktemp -d /tmp/bfish-utterance-latency.XXXXXX)
trap 'rm -rf "$temporary_directory"' EXIT

fixture_index=0
for audio_file in "$@"; do
  fixture_index=$((fixture_index + 1))
  diagnostics="$temporary_directory/diagnostics-$fixture_index.jsonl"
  "$binary" transcribe "$audio_file" \
    --model "$model" \
    --language "$language" \
    --incremental \
    > /dev/null \
    2> "$diagnostics"

  jq -c \
    --argjson fixtureIndex "$fixture_index" \
    --arg model "$model" \
    --arg language "$language" \
    'select(.event == "recognition_completed")
      | {
          fixtureIndex: $fixtureIndex,
          model: $model,
          language: $language,
          audioDurationSeconds: .details.audioDurationSeconds,
          recognitionMilliseconds: ([.timings[] | select(.stage == "whisper_recognition_wall")][0].milliseconds),
          modelLoadMilliseconds: ([.timings[] | select(.stage == "whisper_model_load_wall")][0].milliseconds),
          realTimeFactor: .details.realTimeFactor,
          segmentCount: .details.segmentCount,
          selectedLanguage: .details.selectedLanguage
        }' \
    "$diagnostics"
done
