#!/bin/bash
set -euo pipefail

readonly XCODEGEN_VERSION="2.46.0"
readonly INSTALL_ROOT="${1:-${RUNNER_TEMP:-/tmp}/vacuum-xcodegen}"
readonly ARCHIVE="${INSTALL_ROOT}/xcodegen.zip"
readonly DOWNLOAD_URL="https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"

mkdir -p "${INSTALL_ROOT}"
curl --fail --location --silent --show-error "${DOWNLOAD_URL}" --output "${ARCHIVE}"
ditto -x -k "${ARCHIVE}" "${INSTALL_ROOT}"

readonly XCODEGEN_BIN="${INSTALL_ROOT}/bin/xcodegen"
if [[ ! -x "${XCODEGEN_BIN}" ]]; then
    echo "xcodegen was not found at ${XCODEGEN_BIN}" >&2
    exit 1
fi

actual_version="$("${XCODEGEN_BIN}" --version)"
if [[ "${actual_version}" != "Version: ${XCODEGEN_VERSION}" ]]; then
    echo "Expected XcodeGen ${XCODEGEN_VERSION}; found ${actual_version}" >&2
    exit 1
fi

if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "${INSTALL_ROOT}/bin" >> "${GITHUB_PATH}"
else
    echo "XcodeGen installed at ${XCODEGEN_BIN}"
fi
