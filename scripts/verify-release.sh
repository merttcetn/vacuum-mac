#!/bin/bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 /path/to/Vacuum.app /path/to/Vacuum.dmg" >&2
    exit 64
fi

readonly APP_PATH="$1"
readonly DMG_PATH="$2"

"$(dirname "$0")/verify-universal.sh" "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
spctl --assess --type execute --verbose=2 "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
xcrun stapler validate "${DMG_PATH}"

echo "Developer ID, Gatekeeper, and notarization checks passed."
