#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

SRC="build/xcode/Build/Products/Release/OpenCodeMeter.app"
DEST="/Applications/OpenCodeMeter.app"
if [ ! -w /Applications ]; then
  DEST="$HOME/Applications/OpenCodeMeter.app"
  mkdir -p "$HOME/Applications"
fi
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# Stop the previous version so only one menu bar item remains.
pkill -f "OpenCodeMeter.app/Contents/MacOS/OpenCodeMeter" 2>/dev/null || true
sleep 0.5
rm -rf "$DEST" "$HOME/Applications/OpenCodeMeter.app"
cp -R "$SRC" "$DEST"

# ExtensionKit discovers widgets through LaunchServices, not pluginkit.
"$LSREGISTER" -f "$DEST"

# The extension process and WidgetKit cache may still hold the previous build.
pkill -f "OpenCodeMeterWidget" 2>/dev/null || true
killall chronod 2>/dev/null || true

"$DEST/Contents/MacOS/OpenCodeMeter" --sync >/dev/null 2>&1 || true

# Show the settings window once after a fresh install so the controls are easy
# to find even when the menu bar item is hidden by the notch.
defaults delete local.metax.opencode-meter didShowSettingsWindow 2>/dev/null || true
open "$DEST"

echo "已安装: $DEST"
