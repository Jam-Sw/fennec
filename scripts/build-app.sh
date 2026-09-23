#!/bin/zsh
# Builds, bundles, and signs Fennec.app. With --install, copies it to
# /Applications (or ~/Applications when /Applications is not writable).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Fennec"
BUNDLE_ID="com.jam.fennec"
VERSION="$(sed -n 's/.*fennecVersion = "\(.*\)".*/\1/p' Sources/FennecCore/Version.swift)"
IDENTITY="Fennec Local Signing"
APP_DIR=".build/$APP_NAME.app"

echo "==> Building Fennec $VERSION"
swift build -c release --product "$APP_NAME"
# Ask SwiftPM where it put the binary: the build engines disagree on the layout.
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Assembling bundle"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp scripts/Info.plist "$APP_DIR/Contents/Info.plist"
cp assets/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "==> Creating a local signing identity '$IDENTITY' (one time)"
  echo "    It lets macOS remember your permission grants across updates."
  echo "    macOS will ask for your password to trust it for code signing."
  # Clear any untrusted copy left by an earlier attempt, or codesign sees two
  # identities with the same name and refuses both.
  for _ in 1 2 3 4 5; do
    security delete-identity -c "$IDENTITY" >/dev/null 2>&1 || break
  done
  TMP="$(mktemp -d)"
  OPENSSL=/usr/bin/openssl
  LEGACY=()
  BREW_OPENSSL="$(brew --prefix openssl@3 2>/dev/null || true)"
  if [[ -n "$BREW_OPENSSL" && -x "$BREW_OPENSSL/bin/openssl" ]]; then
    OPENSSL="$BREW_OPENSSL/bin/openssl"
    LEGACY=(-legacy)
  fi
  cat > "$TMP/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = codesign
prompt = no
[dn]
CN = $IDENTITY
[codesign]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
CNF
  "$OPENSSL" req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -nodes \
    -config "$TMP/openssl.cnf" 2>/dev/null
  "$OPENSSL" pkcs12 -export -out "$TMP/cert.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -passout pass:fennec "${LEGACY[@]}"
  security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P fennec -T /usr/bin/codesign || true
  security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem" || true
  rm -rf "$TMP"
fi

SIGN_AS="$IDENTITY"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "    The signing identity isn't trusted (the password prompt was probably cancelled)."
  echo "    Signing ad hoc instead: Fennec works, but you'll grant permissions again after"
  echo "    each update. Run the installer again to retry the identity."
  SIGN_AS="-"
fi

echo "==> Signing"
codesign --force --sign "$SIGN_AS" --identifier "$BUNDLE_ID" --timestamp=none "$APP_DIR"
codesign --verify "$APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications"
  [[ -w "$DEST" ]] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
  if pgrep -xq "$APP_NAME"; then
    echo "==> Quitting the running copy"
    osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || pkill -x "$APP_NAME" || true
    sleep 1
  fi
  rm -rf "$DEST/$APP_NAME.app"
  cp -R "$APP_DIR" "$DEST/$APP_NAME.app"
  echo "==> Installed $DEST/$APP_NAME.app"
else
  echo "==> Built $APP_DIR"
fi
