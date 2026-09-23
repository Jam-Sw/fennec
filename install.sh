#!/bin/zsh
# Fennec installer. Builds Fennec from source on this Mac, signs it with a
# local identity so permission grants survive updates, installs it, and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/Jam-Sw/fennec/main/install.sh | zsh
#
# Run it again to update. Environment overrides:
#   FENNEC_REF   branch or tag to install (default: main)
#   FENNEC_SRC   where the source checkout lives (default: ~/.local/share/fennec/src)
set -euo pipefail

REPO="${FENNEC_REPO:-https://github.com/Jam-Sw/fennec.git}"
REF="${FENNEC_REF:-main}"
SRC="${FENNEC_SRC:-$HOME/.local/share/fennec/src}"

if [[ -t 1 ]]; then
  ACCENT=$'\e[38;5;208m' BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' RESET=$'\e[0m'
else
  ACCENT="" BOLD="" DIM="" RED="" RESET=""
fi
step() { printf '%s==>%s %s%s%s\n' "$ACCENT" "$RESET" "$BOLD" "$1" "$RESET"; }
note() { printf '    %s%s%s\n' "$DIM" "$1" "$RESET"; }
fail() { printf '%serror:%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }

# Everything runs inside main so a piped install is fully read before it starts.
main() {
  printf '\n%s  /\\_/\\   Fennec%s\n' "$ACCENT" "$RESET"
  printf '%s ( o.o )  %shold a key, speak, release%s\n\n' "$ACCENT" "$DIM" "$RESET"

  [[ "$(uname -s)" == Darwin ]] || fail "Fennec runs on macOS only."
  [[ "$(uname -m)" == arm64 ]] || fail "Fennec needs an Apple Silicon Mac; the speech model runs on the Neural Engine."
  local os_major="${$(sw_vers -productVersion)%%.*}"
  (( os_major >= 15 )) || fail "Fennec needs macOS 15 or later."
  (( os_major >= 26 )) || note "Fennec is tested on macOS 26. You have $(sw_vers -productVersion); it should work, but tell us if it doesn't."

  if ! xcode-select -p >/dev/null 2>&1; then
    step "Installing Apple's Command Line Tools"
    xcode-select --install 2>/dev/null || true
    fail "Finish the Command Line Tools install in the dialog that just opened, then run this installer again."
  fi
  command -v git >/dev/null || fail "git is missing. Install the Command Line Tools: xcode-select --install"

  local swift_version
  swift_version="$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9]*\.[0-9]*\).*/\1/p' | head -1)"
  [[ -n "$swift_version" ]] || fail "Swift is missing. Install the Command Line Tools: xcode-select --install"
  local swift_major="${swift_version%%.*}" swift_minor="${swift_version#*.}"
  if (( swift_major < 6 || (swift_major == 6 && swift_minor < 2) )); then
    fail "Fennec needs Swift 6.2 or later; you have $swift_version. Update the Command Line Tools in System Settings > General > Software Update."
  fi

  local root
  local script_dir="${0:A:h}"
  if [[ "${0:t}" == install.sh && -f "$script_dir/Package.swift" ]]; then
    root="$script_dir"
    step "Using the checkout at $root"
  elif [[ -d "$SRC/.git" ]]; then
    step "Updating the source in $SRC"
    git -C "$SRC" fetch --quiet --depth 1 origin "$REF"
    git -C "$SRC" checkout --quiet --force --detach FETCH_HEAD
    root="$SRC"
  else
    step "Downloading the source to $SRC"
    mkdir -p "${SRC:h}"
    git clone --quiet --depth 1 --branch "$REF" "$REPO" "$SRC"
    root="$SRC"
  fi

  step "Building (the first build takes a few minutes)"
  "$root/scripts/build-app.sh" --install </dev/null

  local app="/Applications/Fennec.app"
  [[ -w /Applications ]] || app="$HOME/Applications/Fennec.app"
  open "$app"

  cat <<DONE

${ACCENT}Fennec is running.${RESET} Look for the fox in your menu bar.

  1. Allow ${BOLD}Microphone${RESET}, ${BOLD}Input Monitoring${RESET}, and ${BOLD}Accessibility${RESET} when macOS asks.
  2. The first launch downloads the speech model once (about 470 MB).
     The menu shows progress; the fox turns solid when it's ready.
  3. Click into any text field or terminal, hold ${BOLD}Right Option${RESET}, speak, and release.

  Config:     ~/.config/fennec/config.json
  Update:     run this installer again
  Uninstall:  zsh "$root/uninstall.sh"

DONE
}

main "$@"
