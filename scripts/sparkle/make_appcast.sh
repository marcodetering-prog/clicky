#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SPARKLE_TOOLS_DIR="$("${REPO_ROOT}/scripts/sparkle/download_sparkle_tools.sh")"

SIGN_UPDATE="${SPARKLE_TOOLS_DIR}/bin/sign_update"

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <version> <build_number> <zip_path> <download_url>"
  echo "Example: $0 1.2.3 42 dist/Clicky-1.2.3.zip https://github.com/OWNER/REPO/releases/download/v1.2.3/Clicky-1.2.3.zip"
  exit 1
fi

VERSION="$1"
BUILD_NUMBER="$2"
ZIP_PATH="$3"
DOWNLOAD_URL="$4"

ED_KEY_FILE="${ED_KEY_FILE:-}"

if [[ ! -f "${ZIP_PATH}" ]]; then
  echo "Error: zip_path does not exist: ${ZIP_PATH}"
  exit 1
fi

if [[ -z "${ED_KEY_FILE}" ]]; then
  echo "Error: ED_KEY_FILE is not set (path to Sparkle private key file)."
  exit 1
fi

if [[ ! -f "${ED_KEY_FILE}" ]]; then
  echo "Error: ED_KEY_FILE does not exist: ${ED_KEY_FILE}"
  exit 1
fi

SIGNATURE_AND_LENGTH="$("${SIGN_UPDATE}" --ed-key-file "${ED_KEY_FILE}" "${ZIP_PATH}")"

ED_SIGNATURE="$(echo "${SIGNATURE_AND_LENGTH}" | sed -n 's/.*sparkle:edSignature="\\([^"]*\\)".*/\\1/p')"
FILE_LENGTH="$(echo "${SIGNATURE_AND_LENGTH}" | sed -n 's/.*length="\\([^"]*\\)".*/\\1/p')"

if [[ -z "${ED_SIGNATURE}" || -z "${FILE_LENGTH}" ]]; then
  echo "Error: failed to parse signature output from sign_update:"
  echo "${SIGNATURE_AND_LENGTH}"
  exit 1
fi

APPCAST_PATH="${REPO_ROOT}/appcast.xml"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat > "${APPCAST_PATH}" <<XML
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Clicky</title>
    <item>
      <title>${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.2</sparkle:minimumSystemVersion>
      <enclosure url="${DOWNLOAD_URL}" length="${FILE_LENGTH}" type="application/octet-stream" sparkle:edSignature="${ED_SIGNATURE}"/>
    </item>
  </channel>
</rss>
XML

"${SIGN_UPDATE}" --ed-key-file "${ED_KEY_FILE}" "${APPCAST_PATH}" >/dev/null

echo "${APPCAST_PATH}"

