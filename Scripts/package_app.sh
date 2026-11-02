#!/bin/bash
set -euo pipefail

# Scripts/package_app.sh — Сборка и упаковка StageFlow.app
# Создаёт готовый .app бандл со встроенным Info.plist и entitlements

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build/release"
APP_DIR="${PROJECT_DIR}/build/StageFlow.app"

echo "==> Building StageFlow (Release configuration)..."
cd "${PROJECT_DIR}"
swift build -c release

echo "==> Preparing StageFlow.app bundle structure..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

echo "==> Copying binary and metadata..."
cp "${BUILD_DIR}/StageFlow" "${APP_DIR}/Contents/MacOS/StageFlow"
chmod +x "${APP_DIR}/Contents/MacOS/StageFlow"

cp "${PROJECT_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"
echo "APPL????" > "${APP_DIR}/Contents/PkgInfo"

echo "==> Signing application with entitlements..."
if [ -n "${DEVELOPER_ID_SIGNING_IDENTITY:-}" ]; then
    echo "Signing with Developer ID: ${DEVELOPER_ID_SIGNING_IDENTITY}"
    codesign --force --options runtime --entitlements "${PROJECT_DIR}/StageFlow.entitlements" --sign "${DEVELOPER_ID_SIGNING_IDENTITY}" "${APP_DIR}"
else
    echo "Signing with ad-hoc identity for local verification..."
    codesign --force --entitlements "${PROJECT_DIR}/StageFlow.entitlements" --sign - "${APP_DIR}"
fi

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "==> Bundle packaged successfully at: ${APP_DIR}"
