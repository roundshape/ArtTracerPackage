#!/usr/bin/env bash
set -euo pipefail

# build-dmg.sh
#
# ArtTracerPackage-<VERSION>.dmg を組み立てる。
#
# Usage:
#   scripts/build-dmg.sh [VERSION]
#
# 環境変数で .aip / .app / ライセンスファイルの場所を上書き可能：
#   AIP_PATH      ArtTracer.aip            (default: ../output/mac/release/ArtTracer.aip)
#   APP_PATH      ArtTracerHelper.app      (default: ../ArtTracer/Helper/build.noindex/Release/ArtTracerHelper.app)
#   LICENSE_PATH  THIRD_PARTY_LICENSES.md  (default: ../ArtTracer/THIRD_PARTY_LICENSES.md)
#
# NOTARIZE=1 を指定すると dmg の署名・公証・staple まで行う：
#   SIGN_ID         署名 ID         (default: Developer ID Application: Motoi Kasuya (92U95PHRRW))
#   NOTARY_PROFILE  notarytool プロファイル (default: notary-profile)
#
# 出力: dist/ArtTracerPackage-<VERSION>.dmg

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-0.0.0}"

AIP_PATH="${AIP_PATH:-../output/mac/release/ArtTracer.aip}"
APP_PATH="${APP_PATH:-../ArtTracer/Helper/build.noindex/Release/ArtTracerHelper.app}"
LICENSE_PATH="${LICENSE_PATH:-../ArtTracer/THIRD_PARTY_LICENSES.md}"

if [[ ! -e "$AIP_PATH" ]]; then
    echo "Error: ArtTracer.aip not found at: $AIP_PATH" >&2
    echo "Set AIP_PATH env var to override." >&2
    exit 1
fi
if [[ ! -e "$APP_PATH" ]]; then
    echo "Error: ArtTracerHelper.app not found at: $APP_PATH" >&2
    echo "Set APP_PATH env var to override." >&2
    exit 1
fi
if [[ ! -e "$LICENSE_PATH" ]]; then
    echo "Error: THIRD_PARTY_LICENSES.md not found at: $LICENSE_PATH" >&2
    echo "Set LICENSE_PATH env var to override." >&2
    exit 1
fi

VOL_NAME="ArtTracerPackage $VERSION"
DMG_NAME="ArtTracerPackage-$VERSION.dmg"
DIST_DIR="$ROOT/dist"
STAGE="$(mktemp -d -t arttracerpkg)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging at $STAGE"
cp -R "$AIP_PATH" "$STAGE/ArtTracer.aip"
cp -R "$APP_PATH" "$STAGE/ArtTracerHelper.app"
cp "$ROOT/README.md"       "$STAGE/README.md"
cp "$ROOT/InstallGuide.md" "$STAGE/Install Guide.md"
cp "$ROOT/CHANGELOG.md"    "$STAGE/CHANGELOG.md"
cp "$LICENSE_PATH"         "$STAGE/THIRD_PARTY_LICENSES.md"
cp -R "$ROOT/ai_docs"      "$STAGE/ai_docs"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$DMG_NAME"

echo "==> Creating $DMG_NAME"
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$DMG_NAME" \
    >/dev/null

if [[ "${NOTARIZE:-}" == "1" ]]; then
    SIGN_ID="${SIGN_ID:-Developer ID Application: Motoi Kasuya (92U95PHRRW)}"
    NOTARY_PROFILE="${NOTARY_PROFILE:-notary-profile}"

    echo "==> Signing $DMG_NAME"
    codesign --force --sign "$SIGN_ID" --timestamp "$DIST_DIR/$DMG_NAME"

    echo "==> Submitting for notarization (this may take a few minutes)"
    xcrun notarytool submit "$DIST_DIR/$DMG_NAME" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$DIST_DIR/$DMG_NAME"
fi

echo "==> Done: $DIST_DIR/$DMG_NAME"
