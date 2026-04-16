#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FocusedDayPlanner"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
INSTALL_DIRECT=false
SKIP_INSTALL_PROMPT=false

for arg in "$@"; do
    case "$arg" in
        --install)
            INSTALL_DIRECT=true
            ;;
        --no-install|--ci)
            SKIP_INSTALL_PROMPT=true
            ;;
        --help|-h)
            echo "Usage: $0 [--install] [--no-install]"
            echo "  --install   Install to /Applications without prompting"
            echo "  --no-install  Build app bundle only (no install prompt)"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Usage: $0 [--install] [--no-install]" >&2
            exit 1
            ;;
    esac
done

cd "$ROOT_DIR"
swift build -c release

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

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

while IFS= read -r -d '' IMAGE_FILE; do
    cp "$IMAGE_FILE" "$APP_DIR/Contents/Resources/$(basename "$IMAGE_FILE")"
done < <(find "$ROOT_DIR/assets" -type f -name 'image-*.png' -print0 2>/dev/null || true)

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.divjot.focuseddayplanner</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "Created app bundle: $APP_DIR"
echo "Version: $MARKETING_VERSION ($BUILD_NUMBER)"

if [[ "$INSTALL_DIRECT" == true ]]; then
    cp -R "$APP_DIR" /Applications/
    echo "Installed to /Applications/$APP_NAME.app"
elif [[ "$SKIP_INSTALL_PROMPT" == true || "${CI:-}" == "true" ]]; then
    echo "Skipped install (non-interactive mode)."
else
    read -r -p "Install to /Applications? (Y/N): " INSTALL_REPLY
    if [[ "$INSTALL_REPLY" =~ ^[Yy]$ ]]; then
        cp -R "$APP_DIR" /Applications/
        echo "Installed to /Applications/$APP_NAME.app"
    else
        echo "Skipped install. To install later: cp -R \"$APP_DIR\" /Applications/"
    fi
fi
