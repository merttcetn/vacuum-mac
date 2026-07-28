#!/bin/bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
    echo "Usage: $0 /path/to/Vacuum.app VERSION OUTPUT_DIR" >&2
    exit 64
fi

readonly APP_PATH="$1"
readonly VERSION="$2"
readonly OUTPUT_DIR="$3"
readonly ZIP_NAME="Vacuum-${VERSION}.zip"
readonly DMG_NAME="Vacuum-${VERSION}.dmg"
readonly ZIP_PATH="${OUTPUT_DIR}/${ZIP_NAME}"
readonly DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

mkdir -p "${OUTPUT_DIR}"
"$(dirname "$0")/verify-universal.sh" "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/vacuum-dmg.XXXXXX")"
trap 'rm -rf "${staging_directory}"' EXIT
ditto "${APP_PATH}" "${staging_directory}/Vacuum.app"
ln -s /Applications "${staging_directory}/Applications"
hdiutil create \
    -volname "Vacuum" \
    -srcfolder "${staging_directory}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

pushd "${OUTPUT_DIR}" >/dev/null
shasum -a 256 "${ZIP_NAME}" "${DMG_NAME}" > "SHA256SUMS.txt"
popd >/dev/null
echo "Created ${ZIP_PATH}, ${DMG_PATH}, and SHA256SUMS.txt"
