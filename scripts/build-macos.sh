#!/bin/bash
set -euo pipefail

# Build a self-contained Apple Silicon app. No Xcode project or NI runtime needed.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "Build Mikro MIDI on an Apple Silicon Mac (arm64)." >&2
  exit 1
fi

for tool in cargo swiftc codesign ditto plutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing $tool. Install Rust and Apple's Xcode Command Line Tools." >&2
    exit 1
  fi
done

VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' Cargo.toml | head -n 1)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a semantic version in Cargo.toml's workspace.package section." >&2
  exit 1
fi

APP="$ROOT/dist/Mikro MIDI.app"
ARCHIVE="$ROOT/dist/Mikro-MIDI-$VERSION-macOS-arm64.zip"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
if [[ -n "$NOTARY_PROFILE" && "$SIGNING_IDENTITY" == - ]]; then
  echo "Notarization requires SIGNING_IDENTITY to name a Developer ID certificate." >&2
  exit 1
fi
export MACOSX_DEPLOYMENT_TARGET=14.0

cargo build --release --locked

if [[ ! -f macos/AppIcon.icns ]]; then
  echo "Missing macos/AppIcon.icns." >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -module-name MikroMIDI \
  -target arm64-apple-macosx14.0 \
  macos/*.swift -framework SwiftUI -framework AppKit \
  -o "$APP/Contents/MacOS/Mikro MIDI"

cp target/release/driver "$APP/Contents/MacOS/mikro-driver"
cp macos/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cat > "$APP/Contents/Resources/CREDITS.txt" <<'CREDITS'
Mikro MIDI by Hannes Schneidermayer
https://github.com/schneidermayer/mikro-midi

Built on the MIT-licensed Maschine Mikro MK3 driver by r00tman (Viktor Rudnev).
https://github.com/r00tman/maschine-mikro-mk3-driver

See LICENSE for the full license.
CREDITS

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mikro MIDI</string>
  <key>CFBundleDisplayName</key><string>Mikro MIDI</string>
  <key>CFBundleExecutable</key><string>Mikro MIDI</string>
  <key>CFBundleIdentifier</key><string>com.schneidermayer.mikro-midi</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist"
if [[ "$SIGNING_IDENTITY" == - ]]; then
  codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/mikro-driver"
  codesign --force --sign - --timestamp=none "$APP"
else
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    "$APP/Contents/MacOS/mikro-driver"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

rm -f "$ARCHIVE" "$ARCHIVE.sha256"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
if [[ -n "$NOTARY_PROFILE" ]]; then
  NOTARY_RESULT="$(mktemp)"
  trap 'rm -f "$NOTARY_RESULT"' EXIT
  echo "Submitting the signed app to Apple's notarization service..."
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" \
    --wait --output-format json > "$NOTARY_RESULT"
  NOTARY_STATUS="$(plutil -extract status raw -o - "$NOTARY_RESULT")"
  if [[ "$NOTARY_STATUS" != Accepted ]]; then
    cat "$NOTARY_RESULT" >&2
    echo "Notarization was not accepted; no release archive is ready." >&2
    exit 1
  fi
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  rm -f "$ARCHIVE"
  ditto -c -k --keepParent "$APP" "$ARCHIVE"
fi
(
  cd "$ROOT/dist"
  shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
)
echo "Built $APP"
echo "Archive: $ARCHIVE"
