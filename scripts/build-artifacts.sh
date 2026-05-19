#!/usr/bin/env bash
set -euo pipefail

# build-artifacts.sh
#
# ArtTracer.aip と ArtTracerHelper.app を release 構成でビルドする。
# ArtTracerThumbnail.appex は ArtTracerHelper.app に埋め込まれるため
# 個別ビルドは不要。
#
# Usage:
#   scripts/build-artifacts.sh
#
# 配布用に Developer ID Application 証明書で署名し、Hardened Runtime を有効化する。
#
# 環境変数で上書き可能：
#   AIP_PROJECT     ArtTracer.xcodeproj       (default: ../ArtTracer/ArtTracer.xcodeproj)
#   HELPER_PROJECT  ArtTracerHelper.xcodeproj (default: ../ArtTracer/Helper/ArtTracerHelper.xcodeproj)
#   SIGN_ID         署名 ID                   (default: Developer ID Application: Motoi Kasuya (92U95PHRRW))
#   TEAM_ID         Team ID                   (default: 92U95PHRRW)
#
# 出力:
#   ../output/mac/release/ArtTracer.aip
#   ../ArtTracer/Helper/build/Release/ArtTracerHelper.app

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AIP_PROJECT="${AIP_PROJECT:-../ArtTracer/ArtTracer.xcodeproj}"
HELPER_PROJECT="${HELPER_PROJECT:-../ArtTracer/Helper/ArtTracerHelper.xcodeproj}"
SIGN_ID="${SIGN_ID:-Developer ID Application: Motoi Kasuya (92U95PHRRW)}"
TEAM_ID="${TEAM_ID:-92U95PHRRW}"

if [[ ! -e "$AIP_PROJECT" ]]; then
    echo "Error: ArtTracer.xcodeproj not found at: $AIP_PROJECT" >&2
    echo "Set AIP_PROJECT env var to override." >&2
    exit 1
fi
if [[ ! -e "$HELPER_PROJECT" ]]; then
    echo "Error: ArtTracerHelper.xcodeproj not found at: $HELPER_PROJECT" >&2
    echo "Set HELPER_PROJECT env var to override." >&2
    exit 1
fi

AIP_OUTPUT_DIR="../output/mac/release"
HELPER_OUTPUT_DIR="../ArtTracer/Helper/build/Release"

echo "==> Cleaning $AIP_OUTPUT_DIR"
rm -rf "$AIP_OUTPUT_DIR"

HELPER_ENTITLEMENTS="$ROOT/scripts/entitlements/Release.entitlements"

echo "==> Building ArtTracer.aip (release, Developer ID)"
xcodebuild \
    -project "$AIP_PROJECT" \
    -scheme ArtTracer \
    -configuration release \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_ID" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build

echo "==> Cleaning $HELPER_OUTPUT_DIR"
rm -rf "$HELPER_OUTPUT_DIR"

echo "==> Building ArtTracerHelper.app (Release, Developer ID)"
xcodebuild \
    -project "$HELPER_PROJECT" \
    -scheme ArtTracerHelper \
    -configuration Release \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_ID" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_ENTITLEMENTS="$HELPER_ENTITLEMENTS" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build

echo "==> Done"
