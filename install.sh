#!/bin/bash
# Seeybot installer — build from source, install to /Applications, auto-start at login.
#
# One-line install (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/7757/Seeybot/main/install.sh | bash
#
# Or from a checkout:  ./install.sh
set -euo pipefail

REPO_URL="https://github.com/7757/Seeybot"
LABEL="com.seeybot.notch"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

# --- Self-bootstrap: if we're not inside a checkout, clone it first. ------------
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo '.')"
if [ ! -d "$SELF_DIR/Sources" ]; then
  echo "▸ Fetching Seeybot…"
  TMP="$(mktemp -d)/Seeybot"
  git clone --depth 1 "$REPO_URL" "$TMP" >/dev/null 2>&1
  exec bash "$TMP/install.sh"
fi
ROOT="$SELF_DIR"

# --- Requirements --------------------------------------------------------------
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "✗ Swift toolchain not found. Install the Command Line Tools first:"
  echo "    xcode-select --install"
  exit 1
fi

echo "▸ Building…"
"$ROOT/build.sh" >/dev/null
echo "  ✓ built"

# Stop any running copy / previously installed agent.
launchctl unload "$AGENT" 2>/dev/null || true
pkill -x Seeybot 2>/dev/null || true
sleep 0.4

# Install to /Applications, falling back to ~/Applications if it isn't writable.
if APP_DST="/Applications/Seeybot.app"; rm -rf "$APP_DST" 2>/dev/null && cp -R "$ROOT/build/Seeybot.app" "$APP_DST" 2>/dev/null; then
  echo "▸ Installed to /Applications/Seeybot.app"
else
  mkdir -p "$HOME/Applications"
  APP_DST="$HOME/Applications/Seeybot.app"
  rm -rf "$APP_DST"; cp -R "$ROOT/build/Seeybot.app" "$APP_DST"
  echo "▸ /Applications not writable — installed to ~/Applications/Seeybot.app"
fi

codesign --force --deep --sign - "$APP_DST" >/dev/null 2>&1 || true
xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true
BIN="$APP_DST/Contents/MacOS/Seeybot"

echo "▸ Creating login agent (auto-start; restart only on crash)…"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$BIN</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Interactive</string>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PLIST

launchctl load -w "$AGENT" 2>/dev/null || launchctl load "$AGENT"
sleep 1.2

if pgrep -x Seeybot >/dev/null; then
  echo "✓ Seeybot is installed and running (look for the gauge icon in your menu bar)."
  echo "  It will start automatically at login. Quit any time from the menu-bar icon."
else
  echo "  agent loaded; launching directly…"; open "$APP_DST"
fi
echo
echo "Uninstall:  launchctl unload \"$AGENT\"; rm -f \"$AGENT\"; rm -rf \"$APP_DST\""
