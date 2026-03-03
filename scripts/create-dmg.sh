#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FocusedDayPlanner"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

if [[ ! -d "$APP_DIR" ]]; then
    echo "App bundle not found at $APP_DIR" >&2
    echo "Run ./scripts/package-app.sh first." >&2
    exit 1
fi

MARKETING_VERSION="${MARKETING_VERSION:-}"
if [[ -z "$MARKETING_VERSION" && -f "$ROOT_DIR/VERSION" ]]; then
    MARKETING_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
fi
MARKETING_VERSION="${MARKETING_VERSION:-1.0.0}"

BUILD_NUMBER="${BUILD_NUMBER:-}"
if [[ -z "$BUILD_NUMBER" ]]; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        BUILD_NUMBER="$(git rev-list --count HEAD)"
    else
        BUILD_NUMBER="1"
    fi
fi

DMG_NAME="$APP_NAME-$MARKETING_VERSION-$BUILD_NUMBER.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
TMP_DIR="$DIST_DIR/dmg-staging"

rm -rf "$TMP_DIR" "$DMG_PATH"
mkdir -p "$TMP_DIR"
cp -R "$APP_DIR" "$TMP_DIR/"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$TMP_DIR"
echo "Created DMG: $DMG_PATH"
