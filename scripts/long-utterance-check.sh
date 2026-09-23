#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

say -f fixtures/long-paragraph.txt -o fixtures/long.aiff
afconvert -f WAVE -d LEI16@16000 -c 1 fixtures/long.aiff fixtures/long.wav

count=$(swift run -c release fennec transcribe fixtures/long.wav --json \
  | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["text"].split()))')
echo "long utterance word count: $count (expected at least 61)"
[[ "$count" -ge 61 ]]
