#!/usr/bin/env bash
set -euo pipefail

# gh-release.sh
#
# GitHub Releases へ成果物をアップロードするまでの一連の流れ
# (コミット → タグ付け → gh アカウント切替 → リリース作成 → 戻す)
# を 1 本にまとめたサンプル。
#
# 使い方:
#   scripts/gh-release.sh <VERSION> [<COMMIT_MESSAGE>] [<RELEASE_NOTES_FILE>]
#   例: scripts/gh-release.sh 0.0.3 "v0.0.3 リリース準備"
#
# 前提:
#   - ArtTracerPackage リポジトリのルートで実行する (cwd = リポジトリルート)
#   - dist/ArtTracerPackage-<VERSION>.dmg がビルド済み
#     (まだなら scripts/release.sh <VERSION> を先に走らせる想定)
#   - gh CLI でリリース先 (roundshape) にログイン済み
#     ※ 個人常用 Mac では kasuya / roundshape の両方にログインしておく
#       (このスクリプトは元アカウントを記録し、終了時に trap で自動復帰する)

# ---- 設定 ----------------------------------------------------------------
RELEASE_ACCOUNT="roundshape"          # release を作成する gh アカウント
ASSET_DIR="dist"                      # アップロードする成果物の置き場 (cwd 相対)
ASSET_NAME_TEMPLATE="ArtTracerPackage-%s.dmg"   # %s = VERSION

# このスクリプトは ArtTracerPackage リポジトリ内 (cwd) で実行する前提。
# 誤った場所で実行したときのエラーメッセージに表示する想定パス。
# 既定はスクリプト自身の位置 (scripts/ の親 = リポジトリルート) から導出する。
# 環境変数 PACKAGE_DIR で上書き可。
PACKAGE_DIR="${PACKAGE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ---- ヘルプ表示 ----------------------------------------------------------
usage() {
  cat <<'EOF'
Usage:
  gh-release.sh [--skip-commit] <VERSION> [<COMMIT_MESSAGE>] [<RELEASE_NOTES_FILE>]
  gh-release.sh -h | --help

オプション:
  --skip-commit         コミットステップを完全にスキップする
                        現在の HEAD にタグを付けて push & リリースのみ実行
                        (手動でコミット済みで、作業ツリーに残った変更を
                         巻き込みたくない場合に使う)

引数:
  <VERSION>             バージョン番号。例: 0.0.3 → タグ v0.0.3 を作成
  <COMMIT_MESSAGE>      省略可。省略時は "v<VERSION> リリース準備"
                        スペースを含む場合はクォートで囲む
                        --skip-commit 指定時は無視される
  <RELEASE_NOTES_FILE>  省略可。GitHub Release の本文として読み込むファイル
                        指定なしの場合は --generate-notes で自動生成
                        相対パスはカレントディレクトリ基準

実行例:
  # 最小: コミットメッセージはデフォルト、リリースノートは自動生成
  gh-release.sh 0.0.3

  # コミットメッセージを指定
  gh-release.sh 0.0.3 "v0.0.3 リリース準備"

  # コミットメッセージ + リリースノートをファイルから読む
  gh-release.sh 0.0.3 "v0.0.3 リリース準備" CHANGELOG-0.0.3.md

  # 手動でコミット済み: コミットをスキップして HEAD をリリース
  gh-release.sh --skip-commit 0.0.3

前提:
  - プロジェクトルートで cd してから実行する
  - dist/ArtTracerPackage-<VERSION>.dmg がビルド済み
    (まだなら ./scripts/release.sh <VERSION> を先に実行)
  - gh CLI で kasuya / roundshape の両方にログイン済み
EOF
}

# ---- 引数パース ----------------------------------------------------------
SKIP_COMMIT=0
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --skip-commit|--no-commit)
      SKIP_COMMIT=1
      shift
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do POSITIONAL+=("$1"); shift; done
      ;;
    -*)
      echo "ERROR: 不明なオプション: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]:-}"

if [ -z "${1:-}" ]; then
  usage >&2
  exit 1
fi

VERSION="$1"
TAG="v${VERSION}"
COMMIT_MSG="${2:-${TAG} リリース準備}"
RELEASE_NOTES_FILE="${3:-}"
ASSET_PATH="${ASSET_DIR}/$(printf "$ASSET_NAME_TEMPLATE" "$VERSION")"

# ---- 事前チェック (副作用の前にすべて済ませる) ---------------------------
if [ -n "${RELEASE_NOTES_FILE}" ] && [ ! -f "${RELEASE_NOTES_FILE}" ]; then
  echo "ERROR: リリースノートファイル ${RELEASE_NOTES_FILE} が見つかりません。" >&2
  exit 1
fi

if [ ! -f "${ASSET_PATH}" ]; then
  echo "ERROR: ${ASSET_PATH} (cwd: $(pwd)) が見つかりません。" >&2
  echo "" >&2
  echo "このスクリプトは ArtTracerPackage リポジトリ内で実行する必要があります。" >&2
  echo "次のようにカレントディレクトリを移動してから実行してください:" >&2
  echo "" >&2
  echo "    cd \"${PACKAGE_DIR}\"" >&2
  echo "    $(basename "$0") ${VERSION}" >&2
  echo "" >&2
  echo "(dmg が未ビルドの場合は先に scripts/release.sh ${VERSION} を実行)" >&2
  exit 1
fi

# ---- gh アカウント切替 (失敗しても必ず戻す) -------------------------------
ORIGINAL_ACCOUNT="$(gh api user --jq .login 2>/dev/null || true)"
if [ -z "${ORIGINAL_ACCOUNT}" ]; then
  echo "ERROR: 現在の gh アカウントを取得できませんでした。gh auth status を確認してください。" >&2
  exit 1
fi

restore_account() {
  local current
  current="$(gh api user --jq .login 2>/dev/null || true)"
  if [ "${current}" != "${ORIGINAL_ACCOUNT}" ]; then
    echo "==> gh アカウントを ${ORIGINAL_ACCOUNT} に戻します"
    gh auth switch --user "${ORIGINAL_ACCOUNT}"
  fi
}
trap restore_account EXIT

# ---- 1. コミット ---------------------------------------------------------
if [ "${SKIP_COMMIT}" -eq 1 ]; then
  echo "==> --skip-commit 指定: コミットステップをスキップ (HEAD をそのまま使用)"
elif ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "==> コミット: ${COMMIT_MSG}"
  git add -A
  git commit -m "${COMMIT_MSG}"
else
  echo "==> 変更なし。コミットはスキップ"
fi

# ---- 2. タグ付け ---------------------------------------------------------
if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "==> タグ ${TAG} は既に存在。スキップ"
else
  echo "==> タグ付け: ${TAG}"
  git tag "${TAG}"
fi

echo "==> push (commit & tag)"
git push origin HEAD
git push origin "${TAG}"

# ---- 3. gh アカウントを切替 ----------------------------------------------
echo "==> gh アカウントを ${RELEASE_ACCOUNT} に切替"
gh auth switch --user "${RELEASE_ACCOUNT}"

# ---- 4. Release 作成 & 成果物アップロード ---------------------------------
echo "==> GitHub Release を作成: ${TAG}"
if [ -n "${RELEASE_NOTES_FILE}" ]; then
  gh release create "${TAG}" \
    "${ASSET_PATH}" \
    --title "ArtTracerPackage ${VERSION}" \
    --notes-file "${RELEASE_NOTES_FILE}"
else
  gh release create "${TAG}" \
    "${ASSET_PATH}" \
    --title "ArtTracerPackage ${VERSION}" \
    --generate-notes
fi

# ---- 5. アカウントを戻す (trap で自動実行) --------------------------------
echo "==> 完了"
