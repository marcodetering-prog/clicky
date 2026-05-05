#!/usr/bin/env bash
set -euo pipefail

SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.1}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_DIR="${REPO_ROOT}/sparkle_tools/${SPARKLE_VERSION}"

mkdir -p "${TOOLS_DIR}"

if [[ -x "${TOOLS_DIR}/bin/sign_update" && -x "${TOOLS_DIR}/bin/generate_keys" ]]; then
  echo "${TOOLS_DIR}"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

ARCHIVE_NAME="Sparkle-${SPARKLE_VERSION}.tar.xz"
ARCHIVE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/${ARCHIVE_NAME}"

echo "Downloading Sparkle tools ${SPARKLE_VERSION}..."
curl -L -o "${TMP_DIR}/${ARCHIVE_NAME}" "${ARCHIVE_URL}"

tar -xf "${TMP_DIR}/${ARCHIVE_NAME}" -C "${TMP_DIR}"

mkdir -p "${TOOLS_DIR}/bin"
cp "${TMP_DIR}/bin/sign_update" "${TOOLS_DIR}/bin/sign_update"
cp "${TMP_DIR}/bin/generate_keys" "${TOOLS_DIR}/bin/generate_keys"
chmod +x "${TOOLS_DIR}/bin/sign_update" "${TOOLS_DIR}/bin/generate_keys"

echo "${TOOLS_DIR}"

