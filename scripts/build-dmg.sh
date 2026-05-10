#!/usr/bin/env bash
set -euo pipefail

# build-dmg.sh
#
# ArtTracerPackage-<VERSION>.dmg を組み立てる。
#
# Usage:
#   scripts/build-dmg.sh [VERSION]
#
# 環境変数で .aip / .app の場所を上書き可能：
#   AIP_PATH  ArtTracer.aip       (default: ../output/mac/release/ArtTracer.aip)
#   APP_PATH  ArtTracerHelper.app (default: ../ArtTracer/Helper/build/Release/ArtTracerHelper.app)
#
# 出力: dist/ArtTracerPackage-<VERSION>.dmg

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-0.0.0}"

AIP_PATH="${AIP_PATH:-../output/mac/release/ArtTracer.aip}"
APP_PATH="${APP_PATH:-../ArtTracer/Helper/build/Release/ArtTracerHelper.app}"

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

echo "==> Done: $DIST_DIR/$DMG_NAME"
