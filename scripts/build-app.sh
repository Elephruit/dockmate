#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_path="$PWD/build/DockMate.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_dir/DockMate" "$app_path/Contents/MacOS/DockMate"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
plutil -lint "$app_path/Contents/Info.plist"
# Ad-hoc signing is sufficient for this local personal build. For distribution,
# use a Developer ID identity and notarize the resulting bundle.
codesign --force --sign "${DOCKMATE_SIGN_IDENTITY:--}" "$app_path"
codesign --verify --strict "$app_path"
printf 'Built %s\n' "$app_path"
