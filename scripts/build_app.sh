#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/dist/ClaudeUsageBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$PROJECT_DIR/.build/AppIcon.png"
ICONSET_DIR="$PROJECT_DIR/.build/AppIcon.iconset"

cd "$PROJECT_DIR"

if [[ -n "${CLAUDE_USAGE_BAR_SDKROOT:-}" ]]; then
    export SDKROOT="$CLAUDE_USAGE_BAR_SDKROOT"
else
    HOST_MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
    DEVELOPER_ROOT="$(xcode-select -p)"
    SDKROOT_CANDIDATES=(
        "$DEVELOPER_ROOT/SDKs/MacOSX${HOST_MACOS_MAJOR}.sdk"
        "$DEVELOPER_ROOT/Platforms/MacOSX.platform/Developer/SDKs/MacOSX${HOST_MACOS_MAJOR}.sdk"
    )

    for sdk_path in "${SDKROOT_CANDIDATES[@]}"; do
        if [[ -d "$sdk_path" ]]; then
            export SDKROOT="$sdk_path"
            break
        fi
    done

    if [[ -z "${SDKROOT:-}" ]]; then
        export SDKROOT="$(xcrun --show-sdk-path)"
    fi
fi

export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/module-cache/swiftpm"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache/clang"

swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --disable-sandbox --show-bin-path)"
BINARY="$BIN_DIR/ClaudeUsageBar"

# The app icon is drawn in code, so the repository needs no binary assets.
"$BINARY" --render-app-icon "$ICON_SOURCE" >/dev/null

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"
cp "$BINARY" "$MACOS_DIR/ClaudeUsageBar"
cp "$PROJECT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
"$BINARY" --create-icns "$ICONSET_DIR" "$RESOURCES_DIR/AppIcon.icns" >/dev/null

codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
