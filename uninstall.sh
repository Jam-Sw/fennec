#!/bin/zsh
# Removes Fennec.app. With --all, also removes your config and dictionary, the
# downloaded speech model, logs, the local signing identity, the source
# checkout the installer made, and Fennec's privacy permission grants.
set -euo pipefail

BUNDLE_ID="com.jam.fennec"

if pgrep -xq Fennec; then
  osascript -e 'quit app "Fennec"' 2>/dev/null || pkill -x Fennec || true
  sleep 1
fi

for app in /Applications/Fennec.app "$HOME/Applications/Fennec.app"; do
  if [[ -d "$app" ]]; then
    rm -rf "$app"
    echo "removed $app"
  fi
done

if [[ "${1:-}" != "--all" ]]; then
  echo "Kept your config in ~/.config/fennec and the speech model cache."
  echo "Run with --all to remove everything."
  exit 0
fi

remove() {
  if [[ -e "$1" ]]; then
    rm -rf "$1"
    echo "removed $1"
  fi
}
remove "$HOME/.config/fennec"
remove "$HOME/Library/Caches/desert-ant-models/desert-ant-labs/voz"
remove "$HOME/Library/Logs/Fennec"
remove "$HOME/.local/share/fennec"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

if security find-certificate -c "Fennec Local Signing" >/dev/null 2>&1; then
  security delete-identity -c "Fennec Local Signing" >/dev/null 2>&1 \
    || security delete-certificate -c "Fennec Local Signing" >/dev/null 2>&1 || true
  echo "removed the Fennec Local Signing identity"
fi

for service in Microphone ListenEvent Accessibility; do
  tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
done
echo "reset Microphone, Input Monitoring, and Accessibility grants for Fennec"
