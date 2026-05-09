#!/bin/bash
# Build LogoLiquify as an arm64-only macOS 26+ .app bundle.
#
# Usage: ./build.sh [--no-icon]
#   --no-icon  Skip embedding LogoLiquify's own .icon (use a generic icon).

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="LogoLiquify"
APP_BUNDLE="dist/${APP_NAME}.app"
EMBED_OWN_ICON=1

for arg in "$@"; do
    case "$arg" in
        --no-icon) EMBED_OWN_ICON=0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: required tool '$1' not found in PATH." >&2
        exit 1
    fi
}
require_cmd swift
require_cmd codesign

echo "==> swift build (arm64, release)"
swift build -c release --arch arm64

BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)
BIN_PATH="${BIN_DIR}/${APP_NAME}"
if [ ! -x "$BIN_PATH" ]; then
    echo "ERROR: build did not produce ${BIN_PATH}" >&2
    exit 1
fi

echo "==> assembling ${APP_BUNDLE}"
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "$BIN_PATH" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"

if [ "$EMBED_OWN_ICON" -eq 1 ] && [ -d "Resources/AppIcon.icon" ]; then
    if command -v actool >/dev/null 2>&1; then
        echo "==> compiling Resources/AppIcon.icon for the app's own icon"
        TMPCOMP=$(mktemp -d)
        actool Resources/AppIcon.icon \
            --compile "$TMPCOMP" \
            --platform macosx \
            --minimum-deployment-target 26.0 \
            --app-icon AppIcon \
            --include-all-app-icons \
            --output-partial-info-plist "$TMPCOMP/info.plist" >/dev/null
        [ -f "$TMPCOMP/Assets.car" ] && cp "$TMPCOMP/Assets.car" "${APP_BUNDLE}/Contents/Resources/"
        [ -f "$TMPCOMP/AppIcon.icns" ] && cp "$TMPCOMP/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "${APP_BUNDLE}/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${APP_BUNDLE}/Contents/Info.plist"
        rm -rf "$TMPCOMP"
    else
        echo "==> actool not on PATH; skipping LogoLiquify's own icon."
    fi
else
    echo "==> no Resources/AppIcon.icon (or --no-icon); using default app icon"
fi

echo "==> codesigning (ad-hoc)"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE" && echo "==> verify OK"

echo
echo "Built: $(pwd)/${APP_BUNDLE}"
echo "Run:   open '$(pwd)/${APP_BUNDLE}'"
