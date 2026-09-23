#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

say -f fixtures/long-paragraph.txt -o fixtures/long.aiff
afconvert -f WAVE -d LEI16@16000 -c 1 fixtures/long.aiff fixtures/long.wav

json=$(swift run -c release fennec transcribe fixtures/long.wav --json)
text=$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["text"])')
count=$(printf '%s' "$text" | wc -w | tr -d ' ')
echo "long utterance word count: $count (expected at least 61)"
[[ "$count" -ge 61 ]] || { echo "too few words"; exit 1; }
[[ "$text" == *"middle window"* ]] || { echo "the middle of the paragraph is missing"; exit 1; }
echo "middle of the paragraph present"

silence=$(swift run -c release fennec transcribe fixtures/silence.wav)
trimmed=$(printf '%s' "$silence" | tr -d '[:space:]')
[[ -z "$trimmed" ]] || { echo "silence produced text: $silence"; exit 1; }
echo "silence check: clean"
