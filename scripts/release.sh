#!/usr/bin/env bash
set -euo pipefail

# release.sh
#
# ArtTracer.aip / ArtTracerHelper.app をビルドし、dmg を作成して公証する。
# 「release.sh を叩く = 配布用本番リリース」というセマンティクス。
#
# Usage:
#   scripts/release.sh [VERSION]
#
# 出力: dist/ArtTracerPackage-<VERSION>.dmg （署名・公証・staple 済み）

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-0.0.0}"

"$ROOT/scripts/build-artifacts.sh"
NOTARIZE=1 "$ROOT/scripts/build-dmg.sh" "$VERSION"
