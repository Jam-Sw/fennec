#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p fixtures

say -o fixtures/hello.aiff "Fennec dictation test. Send this to open code. [[slnc 500]] New line. Done."
afconvert -f WAVE -d LEI16@16000 -c 1 fixtures/hello.aiff fixtures/hello.wav

python3 - <<'PY'
import wave
with wave.open('fixtures/silence.wav', 'wb') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(16000)
    w.writeframes(b'\x00\x00' * 16000 * 2)
PY

echo "wrote fixtures/hello.wav and fixtures/silence.wav"
