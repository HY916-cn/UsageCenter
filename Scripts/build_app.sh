#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="UsageCenter"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"

echo "==> Building ${APP_NAME} (Release, macOS 26+ Liquid Glass)..."
cd "${ROOT_DIR}"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources/Icons"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cp "${ROOT_DIR}/Sources/UsageCenter/Resources/Icons/"*.svg "${APP_BUNDLE}/Contents/Resources/Icons/"
if [ -f "${ROOT_DIR}/Sources/UsageCenter/Resources/AppIcon.icns" ]; then
    cp "${ROOT_DIR}/Sources/UsageCenter/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi
if [ -d "${BIN_DIR}/UsageCenter_UsageCenter.bundle" ]; then
    cp -R "${BIN_DIR}/UsageCenter_UsageCenter.bundle" "${APP_BUNDLE}/Contents/Resources/"
fi

cat > "${APP_BUNDLE}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>UsageCenter</string>
    <key>CFBundleIdentifier</key>
    <string>com.hy916.UsageCenter</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>UsageCenter</string>
    <key>CFBundleDisplayName</key>
    <string>UsageCenter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.4.4</string>
    <key>CFBundleVersion</key>
    <string>12</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>UIDesignRequiresCompatibility</key>
    <false/>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "${APP_BUNDLE}"
echo "==> Packaged signed app bundle at: ${APP_BUNDLE}"
