#!/bin/zsh
# Fennec installer. Builds Fennec from source on this Mac, signs it with a
# local identity so permission grants survive updates, installs it, and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/Jam-Sw/fennec/main/install.sh | zsh
#
# Installs or upgrades Apple's Command Line Tools when needed (asks for your
# password). Run it again to update. Environment overrides:
#   FENNEC_REF         branch or tag to install (default: main)
#   FENNEC_SRC         where the source checkout lives (default: ~/.local/share/fennec/src)
#   FENNEC_CHECK_ONLY  set to 1 to run the checks, report the toolchain, and stop

# Guard first, in plain sh syntax, so bash or sh stop here with a clear message.
if [ -z "${ZSH_VERSION:-}" ]; then
  echo "Please run the installer with zsh:"
  echo "  curl -fsSL https://raw.githubusercontent.com/Jam-Sw/fennec/main/install.sh | zsh"
  exit 1
fi

set -euo pipefail

REPO="${FENNEC_REPO:-https://github.com/Jam-Sw/fennec.git}"
REF="${FENNEC_REF:-main}"
SRC="${FENNEC_SRC:-$HOME/.local/share/fennec/src}"
LOG="$HOME/Library/Logs/Fennec/install.log"
ISSUES="https://github.com/Jam-Sw/fennec/issues"
CLT_DIR="/Library/Developer/CommandLineTools"
CLT_ON_DEMAND="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
SOFTWARE_UPDATE_PANE="x-apple.systempreferences:com.apple.Software-Update-Settings.extension"

if [[ -t 1 ]]; then
  ACCENT=$'\e[38;5;208m' BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' RESET=$'\e[0m'
else
  ACCENT="" BOLD="" DIM="" RED="" RESET=""
fi
step() { printf '%s==>%s %s%s%s\n' "$ACCENT" "$RESET" "$BOLD" "$1" "$RESET"; }
note() { printf '    %s%s%s\n' "$DIM" "$1" "$RESET"; }
fail() {
  printf '\n%sCan'"'"'t install Fennec yet:%s %s\n' "$RED" "$RESET" "$1" >&2
  printf '\nStuck? Open an issue with the message above: %s\n' "$ISSUES" >&2
  exit 1
}

# The Swift version (e.g. 6.2) of a developer directory, or nothing. Calls the
# swift binary directly: on a Mac without developer tools, xcrun and git are
# stubs that pop up an install dialog.
swift_version() {
  local dir="$1" swift
  if [[ "$dir" == "$CLT_DIR" ]]; then
    swift="$dir/usr/bin/swift"
  else
    swift="$dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
  fi
  [[ -x "$swift" ]] || return 0
  "$swift" --version 2>/dev/null | sed -n 's/.*Swift version \([0-9]*\.[0-9]*\).*/\1/p' | head -1
}

swift_is_new_enough() {
  local version="$1"
  [[ -n "$version" ]] || return 1
  local major="${version%%.*}" minor="${version#*.}"
  (( major > 6 || (major == 6 && minor >= 2) ))
}

# Prints the first developer directory whose Swift is 6.2 or later. Prefers the
# Command Line Tools, then the selected developer directory, then any Xcode.
find_toolchain() {
  local candidates=("$CLT_DIR")
  local selected
  selected="$(xcode-select -p 2>/dev/null || true)"
  [[ -n "$selected" ]] && candidates+=("$selected")
  candidates+=(/Applications/Xcode*.app/Contents/Developer(N))
  local dir
  for dir in "${candidates[@]}"; do
    if swift_is_new_enough "$(swift_version "$dir")"; then
      print -r -- "$dir"
      return 0
    fi
  done
  return 1
}

# Picks the newest Command Line Tools label from `softwareupdate --list` output
# as "version<TAB>label", or nothing.
newest_clt() {
  awk '
    /\* Label: Command Line Tools/ { label = $0; sub(/^.*Label: /, "", label); next }
    label != "" && /Version: / {
      match($0, /Version: [0-9.]+/)
      print substr($0, RSTART + 9, RLENGTH - 9) "\t" label
      label = ""
    }
  ' | sort -t. -k1,1n -k2,2n | tail -1
}

install_command_line_tools() {
  local have="$1"
  if [[ -n "$have" ]]; then
    step "Upgrading Apple's Command Line Tools (Swift $have is too old; Fennec needs 6.2)"
  else
    step "Installing Apple's Command Line Tools"
  fi
  note "These are Apple's free developer tools, needed to build Fennec. About 1 GB."
  note "Asking Apple's update server what's available (up to a minute)…"

  touch "$CLT_ON_DEMAND"
  trap 'rm -f "$CLT_ON_DEMAND"' EXIT
  local newest version label
  newest="$(softwareupdate --list 2>&1 | newest_clt || true)"
  version="${newest%%$'\t'*}"
  label="${newest#*$'\t'}"

  if [[ -z "$newest" ]]; then
    open "$SOFTWARE_UPDATE_PANE" 2>/dev/null || true
    fail "Apple's update server didn't offer the Command Line Tools. Check the internet connection, install any macOS updates in the Software Update window that just opened, then run the installer again."
  fi
  if (( ${version%%.*} < 26 )); then
    open "$SOFTWARE_UPDATE_PANE" 2>/dev/null || true
    fail "the newest Command Line Tools for this macOS version ($version) come with a Swift that's too old. Update macOS in the Software Update window that just opened, then run the installer again."
  fi

  note "Installing \"$label\". macOS will ask for the password you use to log in to this Mac."
  if ! sudo -v; then
    fail "installing developer tools needs an administrator account. Log in as an administrator (or ask one to run the installer), then try again."
  fi
  sudo softwareupdate --install "$label" --verbose || fail "the Command Line Tools install didn't finish. Run the installer again; it picks up where it left off."
  rm -f "$CLT_ON_DEMAND"
}

build_and_install() {
  local root="$1" attempt
  mkdir -p "${LOG:h}"
  : > "$LOG"
  for attempt in 1 2; do
    # arch -arm64 keeps the build native even from a Terminal running under Rosetta.
    if arch -arm64 /bin/zsh "$root/scripts/build-app.sh" --install </dev/null 2>&1 | tee -a "$LOG"; then
      return 0
    fi
    if (( attempt == 1 )); then
      step "The build hit a snag; trying once more"
    fi
  done
  printf '\n%sLast lines of the build log:%s\n' "$DIM" "$RESET" >&2
  tail -15 "$LOG" >&2
  fail "the build failed twice. The full log is at $LOG; please attach it to an issue."
}

# Everything runs inside main so a piped install is fully read before it starts.
main() {
  printf '\n%s  /\\_/\\   Fennec%s\n' "$ACCENT" "$RESET"
  printf '%s ( o.o )  %shold a key, speak, release%s\n\n' "$ACCENT" "$DIM" "$RESET"

  step "Checking this Mac"
  [[ "$(uname -s)" == Darwin ]] || fail "Fennec runs on macOS only."
  [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] \
    || fail "this Mac has an Intel processor. Fennec needs Apple Silicon (M1 or newer) because its speech model runs on the Neural Engine."

  local os_version os_major
  os_version="$(sw_vers -productVersion)"
  os_major="${os_version%%.*}"
  if (( os_major < 15 )); then
    open "$SOFTWARE_UPDATE_PANE" 2>/dev/null || true
    fail "Fennec needs macOS 15 Sequoia or later, and this Mac runs macOS $os_version. Update macOS in the Software Update window that just opened, then run the installer again."
  fi
  (( os_major >= 26 )) || note "Fennec is tested on macOS 26; this Mac runs $os_version. It should work, but please report problems."

  local free_gb
  free_gb="$(df -g "$HOME" | awk 'NR == 2 { print $4 }')"
  (( free_gb >= 5 )) || fail "Fennec needs about 5 GB of free disk space to build (developer tools, the build, and the speech model), and this Mac has ${free_gb} GB free."

  curl -fsSI --max-time 15 https://github.com >/dev/null 2>&1 \
    || fail "can't reach github.com. Check the internet connection and try again."
  note "Apple Silicon, macOS $os_version, ${free_gb} GB free, online"

  step "Checking the developer tools"
  local developer_dir
  if ! developer_dir="$(find_toolchain)"; then
    install_command_line_tools "$(swift_version "$CLT_DIR")"
    developer_dir="$(find_toolchain)" \
      || fail "the Command Line Tools installed, but Swift 6.2 still isn't available. Restart the Mac and run the installer again."
  fi
  export DEVELOPER_DIR="$developer_dir"
  note "Swift $(swift_version "$developer_dir") from $developer_dir"

  if [[ "${FENNEC_CHECK_ONLY:-}" == 1 ]]; then
    step "Checks passed; stopping because FENNEC_CHECK_ONLY=1"
    return 0
  fi

  local root
  local script_dir="${0:A:h}"
  if [[ "${0:t}" == install.sh && -f "$script_dir/Package.swift" ]]; then
    root="$script_dir"
    step "Using the checkout at $root"
  else
    if [[ -d "$SRC/.git" ]]; then
      step "Updating Fennec's source"
      if ! { git -C "$SRC" remote set-url origin "$REPO" \
          && git -C "$SRC" fetch --quiet --depth 1 origin "$REF" \
          && git -C "$SRC" checkout --quiet --force --detach FETCH_HEAD; }; then
        note "The existing copy couldn't update; downloading a fresh one"
        rm -rf "$SRC"
      fi
    fi
    if [[ ! -d "$SRC/.git" ]]; then
      step "Downloading Fennec's source"
      rm -rf "$SRC"
      mkdir -p "${SRC:h}"
      git clone --quiet --depth 1 --branch "$REF" "$REPO" "$SRC" \
        || fail "couldn't download Fennec from $REPO. Check the internet connection and try again."
    fi
    root="$SRC"
  fi

  # Skip the test-only packages; see Package.swift.
  export FENNEC_APP_ONLY=1
  step "Building Fennec (the first build takes a few minutes)"
  note "macOS may ask for your password once, to trust Fennec's signing certificate."
  build_and_install "$root"

  local app="/Applications/Fennec.app"
  [[ -d "$app" ]] || app="$HOME/Applications/Fennec.app"
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
