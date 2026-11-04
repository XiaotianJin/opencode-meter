#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# The widget extension only loads through ExtensionKit when it carries the
# development entitlements Xcode injects, so the build has to go through
# xcodebuild instead of a bare swiftc invocation.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export SDKROOT=macosx

if command -v xcodegen >/dev/null 2>&1; then
  # Keep the generated project in sync with new source files.
  xcodegen generate >/dev/null
elif [ ! -d OpenCodeMeter.xcodeproj ]; then
  echo "缺少 OpenCodeMeter.xcodeproj，请先安装 xcodegen（brew install xcodegen）" >&2
  exit 1
fi

xcodebuild \
  -project OpenCodeMeter.xcodeproj \
  -scheme OpenCodeMeter \
  -configuration Release \
  -derivedDataPath build/xcode \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  build >/tmp/opencode-meter-build.log 2>&1 || {
    echo "构建失败，日志：/tmp/opencode-meter-build.log" >&2
    tail -30 /tmp/opencode-meter-build.log >&2
    exit 1
  }

echo "已构建: build/xcode/Build/Products/Release/OpenCodeMeter.app"
