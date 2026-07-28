#!/bin/bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 /path/to/Vacuum.app" >&2
    exit 64
fi

readonly APP_PATH="$1"
readonly EXECUTABLE="${APP_PATH}/Contents/MacOS/Vacuum"

if [[ ! -x "${EXECUTABLE}" ]]; then
    echo "Vacuum executable not found at ${EXECUTABLE}" >&2
    exit 1
fi

architectures="$(lipo -archs "${EXECUTABLE}")"
for required in arm64 x86_64; do
    if [[ " ${architectures} " != *" ${required} "* ]]; then
        echo "Missing ${required} slice; found: ${architectures}" >&2
        exit 1
    fi
done

echo "Verified universal executable: ${architectures}"
