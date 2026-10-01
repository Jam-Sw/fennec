#!/bin/zsh
# Fennec installer. Builds Fennec from source on this Mac, signs it with a
# local identity so permission grants survive updates, installs it, and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/Jam-Sw/fennec/main/install.sh | zsh
#
# Installs or upgrades Apple's Command Line Tools when needed, repairs a known
# Command Line Tools packaging bug that stops Swift from loading any package
# manifest (both ask for your password), and builds Fennec. Run it again to
# update. Environment overrides:
#   FENNEC_REF         branch or tag to install (default: main)
#   FENNEC_SRC         where the source checkout lives (default: ~/.local/share/fennec/src)
#   FENNEC_CHECK_ONLY  set to 1 to run the checks, report the toolchain, and stop
#   FENNEC_ACCEPT_EULA set to 1 to accept the license agreement without a prompt

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

# The swift binary of a developer directory. Called directly: on a Mac without
# developer tools, xcrun and git are stubs that pop up an install dialog.
swift_binary() {
  local dir="$1"
  if [[ "$dir" == "$CLT_DIR" ]]; then
    print -r -- "$dir/usr/bin/swift"
  else
    print -r -- "$dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
  fi
}

# The Swift version (e.g. 6.2) of a developer directory, or nothing.
swift_version() {
  local swift
  swift="$(swift_binary "$1")"
  [[ -x "$swift" ]] || return 0
  "$swift" --version 2>/dev/null | sed -n 's/.*Swift version \([0-9]*\.[0-9]*\).*/\1/p' | head -1
}

swift_is_new_enough() {
  local version="$1"
  [[ -n "$version" ]] || return 1
  local major="${version%%.*}" minor="${version#*.}"
  (( major > 6 || (major == 6 && minor >= 2) ))
}

# Prints every developer directory worth trying, most preferred first: the
# Command Line Tools, then the selected developer directory, then any Xcode.
toolchain_candidates() {
  local selected app
  print -r -- "$CLT_DIR"
  selected="$(xcode-select -p 2>/dev/null || true)"
  [[ -n "$selected" && "$selected" != "$CLT_DIR" ]] && print -r -- "$selected"
  for app in /Applications/Xcode*.app/Contents/Developer(N); do
    [[ "$app" != "$selected" ]] && print -r -- "$app"
  done
  return 0
}

# Prints the first developer directory whose Swift is 6.2 or later.
find_toolchain() {
  local dir
  for dir in ${(f)"$(toolchain_candidates)"}; do
    if swift_is_new_enough "$(swift_version "$dir")"; then
      print -r -- "$dir"
      return 0
    fi
  done
  return 1
}

# The PackageDescription module of a developer directory - the files Swift
# reads to compile every Package.swift.
manifest_module_dir() {
  local dir="$1"
  if [[ "$dir" == "$CLT_DIR" ]]; then
    print -r -- "$dir/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule"
  else
    print -r -- "$dir/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule"
  fi
}

# True when this toolchain can compile and link a package manifest at all.
# Every build starts with one, so this catches a broken toolchain early. The
# last run's output is left in FENNEC_PROBE_OUT.
manifest_probe() {
  local dir="$1" probe rc=0
  probe="$(mktemp -d "${TMPDIR:-/tmp}/fennec-manifest.XXXXXX")"
  print -r -- '// swift-tools-version: 6.2
import PackageDescription

let package = Package(name: "fennec-manifest-probe")' > "$probe/Package.swift"
  FENNEC_PROBE_OUT="$( cd "$probe" && "$(swift_binary "$dir")" package dump-package 2>&1 )" || rc=$?
  rm -rf "$probe"
  return $rc
}

# Some Command Line Tools installs carry a stale second copy of the module's
# interface (…private.swiftinterface) left over from an older toolchain. Swift
# reads the stale copy, binds every manifest to a Package initializer the
# library no longer exports, and builds die with "Invalid manifest" and an
# undefined swiftLanguageVersions symbol. Moving the stale files aside is
# Apple's own workaround; nothing reads them once renamed. Requires sudo.
disable_stale_manifest_interfaces() {
  local module_dir="$1" f moved=0
  for f in "$module_dir"/*.private.swiftinterface(N); do
    sudo mv "$f" "${f}.disabled-by-fennec" || return 1
    moved=1
  done
  (( moved ))
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

# Prints a plain-language hint when the build log matches a known, fixable
# failure, so a failed install ends in something better than compiler noise.
explain_build_failure() {
  local log="$1"
  [[ -f "$log" ]] || return 0
  if grep -q 'swiftLanguageVersions' "$log" 2>/dev/null; then
    printf '    %sThe log shows Apple'"'"'s Command Line Tools manifest bug. Installing Xcode from the App Store fixes it; the installer will then use Xcode.%s\n' "$DIM" "$RESET" >&2
  fi
  if grep -qE 'Could not resolve|failed to clone|unable to access|Authentication failed' "$log" 2>/dev/null; then
    printf '    %sFennec could not download its speech SDK (github.com/Desert-Ant-Labs/desert-ant-core). Check the internet connection, then run the installer again.%s\n' "$DIM" "$RESET" >&2
  fi
  if grep -q 'No space left' "$log" 2>/dev/null; then
    printf '    %sThe disk filled up during the build. Free some space, then run the installer again.%s\n' "$DIM" "$RESET" >&2
  fi
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
  explain_build_failure "$LOG"
  printf '\n%sLast lines of the build log:%s\n' "$DIM" "$RESET" >&2
  tail -15 "$LOG" >&2
  fail "the build failed twice. The full log is at $LOG; please attach it to an issue."
}

# Asks once per run; reads the answer from the terminal because stdin is the
# piped script. FENNEC_ACCEPT_EULA=1 answers yes for unattended installs.
agree_to_license() {
  step "License agreement"
  note "Fennec is free for personal, noncommercial use. Use for a business or paid work"
  note "needs a commercial license from Jam-Sw (jam.sw.org@gmail.com)."
  note "Read the full agreement: https://github.com/Jam-Sw/fennec/blob/main/EULA.txt"
  [[ "${FENNEC_ACCEPT_EULA:-}" == 1 ]] && { note "Accepted through FENNEC_ACCEPT_EULA=1."; return; }
  [[ -r /dev/tty ]] || fail "no terminal to ask for agreement. Set FENNEC_ACCEPT_EULA=1 to accept the agreement and install."
  local answer
  printf '    Do you agree to the Fennec end user license agreement? [y/N] ' >/dev/tty
  read -r answer </dev/tty
  [[ "$answer" == [yY]* ]] || fail "you did not accept the agreement, so nothing was installed."
}

# Everything runs inside main so a piped install is fully read before it starts.
main() {
  printf '\n%s  /\\_/\\   Fennec%s\n' "$ACCENT" "$RESET"
  printf '%s ( o.o )  %shold a key, speak, release%s\n\n' "$ACCENT" "$DIM" "$RESET"
  note "Developer beta: Fennec is compiled from source on your Mac, so rough edges are expected."

  agree_to_license

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

  step "Checking that Swift can load packages"
  local manifest_ok=0 module_dir manual_hint=""
  local -a stale
  if manifest_probe "$developer_dir"; then
    manifest_ok=1
  else
    note "Swift can't load a package manifest on this Mac, so every build here would fail."
    module_dir="$(manifest_module_dir "$developer_dir")"
    stale=( "$module_dir"/*.private.swiftinterface(N) )
    if [[ "$developer_dir" == "$CLT_DIR" ]] && (( ${#stale} > 0 )); then
      note "A leftover file from an older Command Line Tools is the cause - a known Apple bug."
      note "The installer can move it aside. macOS will ask for the password you use to log in."
      if sudo -v && disable_stale_manifest_interfaces "$module_dir" && manifest_probe "$developer_dir"; then
        manifest_ok=1
        note "Repaired. The leftovers stay next to the originals with a .disabled-by-fennec suffix."
      else
        note "The repair didn't go through - no administrator access, most likely."
      fi
    fi
    if (( ! manifest_ok )); then
      local alt
      for alt in ${(f)"$(toolchain_candidates)"}; do
        [[ "$alt" == "$developer_dir" ]] && continue
        swift_is_new_enough "$(swift_version "$alt")" || continue
        if manifest_probe "$alt"; then
          developer_dir="$alt"
          export DEVELOPER_DIR="$developer_dir"
          manifest_ok=1
          note "Using the working developer tools at $developer_dir instead."
          break
        fi
      done
    fi
    if (( ! manifest_ok )); then
      mkdir -p "${LOG:h}"
      {
        printf 'Swift could not load a package manifest with %s:\n' "$developer_dir"
        print -r -- "$FENNEC_PROBE_OUT"
      } > "$LOG"
      if (( ${#stale} > 0 )); then
        manual_hint="
  2. Or move the leftover files aside by hand, then run the installer again:
     sudo mv \"$module_dir\"/*.private.swiftinterface ~/Desktop/"
      else
        manual_hint="
  2. Or reinstall Apple's Command Line Tools in System Settings → General → Software Update, then run the installer again."
      fi
      fail "Swift can't load any package manifest with Apple's developer tools on this Mac, which stops the build. The Command Line Tools look damaged - a known Apple packaging bug.
  1. Install Apple's full Xcode from the App Store, then run the installer again:
     https://apps.apple.com/app/xcode/id497799835$manual_hint

  The full error is in $LOG."
    fi
  fi

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

  You're on the developer beta build. If anything misbehaves, please say so:
  ${ISSUES}

  Config:     ~/.config/fennec/config.json
  Update:     run this installer again
  Uninstall:  zsh "$root/uninstall.sh"

DONE
}

main "$@"
