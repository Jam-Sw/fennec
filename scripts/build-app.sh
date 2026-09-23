#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Fennec"
BUNDLE_ID="com.jam.fennec"
VERSION="0.1.0"
IDENTITY="Fennec Local Signing"
APP_DIR=".build/release/$APP_NAME.app"

echo "==> Building"
swift build -c release --product "$APP_NAME"

echo "==> Assembling bundle"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp scripts/Info.plist "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "==> Creating signing identity '$IDENTITY' (one time; macOS may ask for keychain access)"
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
    -config "$TMP/openssl.cnf"
  "$OPENSSL" pkcs12 -export -out "$TMP/cert.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -passout pass:fennec "${LEGACY[@]}"
  security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P fennec -T /usr/bin/codesign -A
  security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem" || true
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$HOME/Library/Keychains/login.keychain-db" || true
  rm -rf "$TMP"
fi

echo "==> Signing"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP_DIR"

echo "==> Verifying"
codesign -dv --verbose=2 "$APP_DIR" 2>&1 | grep -E "Identifier|Authority" || true

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
  echo "==> Installed /Applications/$APP_NAME.app"
fi
