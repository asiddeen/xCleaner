#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/xCleaner.app"
DMG_PATH="${DIST_DIR}/xCleaner.dmg"
STAGING_DIR="${DIST_DIR}/dmg_staging"

# 1. Build & Bundle xCleaner.app
echo "==> Building xCleaner.app bundle..."
bash "${SCRIPT_DIR}/bundle-app.sh"

# 2. Prepare staging directory
echo "==> Preparing DMG staging environment..."
rm -rf "${STAGING_DIR}" "${DMG_PATH}" "${DMG_PATH}.sha256"
mkdir -p "${STAGING_DIR}"

cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# 3. Create compressed UDZO disk image using hdiutil
echo "==> Creating distributable DMG via hdiutil..."
hdiutil create \
  -volname "xCleaner" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

# Clean up staging folder
rm -rf "${STAGING_DIR}"

# 4. Sign the DMG with ad-hoc signature on Apple Silicon
echo "==> Applying ad-hoc Apple Silicon signature to DMG..."
codesign --force --sign - "${DMG_PATH}"

# 5. Compute SHA256 checksum
echo "==> Computing SHA256 checksum..."
shasum -a 256 "${DMG_PATH}" > "${DMG_PATH}.sha256"

DMG_SIZE=$(du -sh "${DMG_PATH}" | cut -f1)
echo "==> Successfully created: ${DMG_PATH} (${DMG_SIZE})"
cat "${DMG_PATH}.sha256"
