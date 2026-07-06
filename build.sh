#!/bin/bash
# Build Seeybot.app — a native SwiftUI notch widget — using the Command Line Tools
# toolchain (no Xcode required). Compiles all Sources/*.swift into one binary and
# assembles a proper .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Seeybot.app"
SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos14.0"

echo "▸ Cleaning…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ Compiling Swift sources…"
swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -O \
  -framework AppKit -framework SwiftUI \
  "$ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/Seeybot"

echo "▸ Assembling bundle…"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Ad-hoc code signing…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ Built $APP"
