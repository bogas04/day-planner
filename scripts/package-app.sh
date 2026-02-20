#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FocusedDayPlanner"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
INSTALL_DIRECT=false

for arg in "$@"; do
    case "$arg" in
        --install)
            INSTALL_DIRECT=true
            ;;
        --help|-h)
            echo "Usage: $0 [--install]"
            echo "  --install   Install to /Applications without prompting"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Usage: $0 [--install]" >&2
            exit 1
            ;;
    esac
done

cd "$ROOT_DIR"
swift build -c release

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
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
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

echo "Created app bundle: $APP_DIR"

if [[ "$INSTALL_DIRECT" == true ]]; then
    cp -R "$APP_DIR" /Applications/
    echo "Installed to /Applications/$APP_NAME.app"
else
    read -r -p "Install to /Applications? (Y/N): " INSTALL_REPLY
    if [[ "$INSTALL_REPLY" =~ ^[Yy]$ ]]; then
        cp -R "$APP_DIR" /Applications/
        echo "Installed to /Applications/$APP_NAME.app"
    else
        echo "Skipped install. To install later: cp -R \"$APP_DIR\" /Applications/"
    fi
fi
