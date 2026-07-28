#!/bin/bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 DERIVED_DATA_DIR TOOL_NAME" >&2
    exit 64
fi

readonly DERIVED_DATA="$1"
readonly TOOL_NAME="$2"
tool_path="$(find "${DERIVED_DATA}/SourcePackages" -type f -name "${TOOL_NAME}" -perm +111 -print -quit)"

if [[ -z "${tool_path}" ]]; then
    echo "Could not locate Sparkle tool '${TOOL_NAME}' under ${DERIVED_DATA}/SourcePackages" >&2
    exit 1
fi

echo "${tool_path}"
