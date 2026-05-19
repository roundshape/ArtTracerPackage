# リリースパイプライン技術資料

ArtTracerPackage の dmg を配布可能な状態（署名・公証・staple 済み）で生成するためのスクリプト群について解説します。

すべて macOS 専用です。`xcodebuild` / `codesign` / `hdiutil` / `xcrun notarytool` / `xcrun stapler` を内部で使用しています。

---

## 1. 全体構成

`scripts/` 配下に 3 つのシェルスクリプトと 1 つの entitlements ファイルがあります。

```
scripts/
├── release.sh                       ← 統合エントリ（本番リリース用）
├── build-artifacts.sh               ← .aip と .app をビルドする
├── build-dmg.sh                     ← dmg を組み立てる（オプションで署名・公証）
└── entitlements/
    └── Release.entitlements         ← .app/.appex の Release ビルド用 entitlements
```

呼び出し関係：

```
release.sh <VERSION>
├── build-artifacts.sh               ← 成果物 2 つをビルド
└── NOTARIZE=1 build-dmg.sh <VERSION> ← dmg 作成 + 公証
```

`release.sh` は **公証込みの本番リリース** を 1 コマンドで完結させるためのもの。`build-artifacts.sh` と `build-dmg.sh` は単独でも使えます。

---

## 2. 各スクリプトの仕様

### 2.1 `scripts/release.sh`

```bash
scripts/release.sh [VERSION]
```

「**release.sh を叩く = 配布用本番リリース**」というセマンティクスのスクリプト。内部で `build-artifacts.sh` → `build-dmg.sh` を **`NOTARIZE=1` 付き** で呼び出します。

VERSION を省略すると `0.0.0` になります。最終生成物は `dist/ArtTracerPackage-<VERSION>.dmg`（署名・公証・staple 済み）。

### 2.2 `scripts/build-artifacts.sh`

```bash
scripts/build-artifacts.sh
```

Xcode プロジェクトをビルドし、配布対象の成果物 2 つを生成します。

#### 処理内容

1. 既存の Release 出力ディレクトリを `rm -rf` でクリーン
2. `ArtTracer.aip` を Developer ID Application 証明書で署名ビルド
3. `ArtTracerHelper.app` を同様にビルド（`ArtTracerThumbnail.appex` も自動で埋め込み・署名される）

#### 環境変数（既定値あり、上書き可）

| 変数 | 既定値 | 説明 |
|---|---|---|
| `AIP_PROJECT` | `../ArtTracer/ArtTracer.xcodeproj` | ArtTracer プロジェクトのパス |
| `HELPER_PROJECT` | `../ArtTracer/Helper/ArtTracerHelper.xcodeproj` | Helper プロジェクトのパス |
| `SIGN_ID` | `Developer ID Application: Motoi Kasuya (92U95PHRRW)` | 署名 ID |
| `TEAM_ID` | `92U95PHRRW` | Team ID |

#### xcodebuild に渡している主要な設定

両ターゲット共通：

- `CODE_SIGN_STYLE=Manual` — プロジェクト側の Automatic 設定を上書き
- `CODE_SIGN_IDENTITY="$SIGN_ID"` — Developer ID Application 証明書
- `DEVELOPMENT_TEAM="$TEAM_ID"` — Team ID
- `ENABLE_HARDENED_RUNTIME=YES` — 公証必須の Hardened Runtime
- `OTHER_CODE_SIGN_FLAGS="--timestamp"` — タイムスタンプ付き署名（公証必須）

Helper のみ追加：

- `CODE_SIGN_ENTITLEMENTS="$ROOT/scripts/entitlements/Release.entitlements"` — 明示的な entitlements 指定
- `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` — Xcode による entitlements 自動注入を停止

なぜ Helper だけこの 2 つが必要かは [第 4 章](#4-get-task-allow-問題と解決) で詳述します。

#### 成果物

- `../output/mac/release/ArtTracer.aip`
- `../ArtTracer/Helper/build/Release/ArtTracerHelper.app`
  - `Contents/PlugIns/ArtTracerThumbnail.appex` を埋め込み済み

### 2.3 `scripts/build-dmg.sh`

```bash
scripts/build-dmg.sh [VERSION]
NOTARIZE=1 scripts/build-dmg.sh [VERSION]
```

`build-artifacts.sh` が生成した成果物を集めて dmg を作ります。`NOTARIZE=1` を指定した時のみ署名・公証・staple まで実行します。

#### 処理内容（共通）

1. 一時ディレクトリ（`mktemp`）にステージング：
   - `ArtTracer.aip` / `ArtTracerHelper.app`
   - `README.md` / `Install Guide.md` / `CHANGELOG.md` / `ai_docs/`
   - `/Applications` へのシンボリックリンク（Drag-to-install 演出用）
2. `hdiutil create -format UDZO` で `dist/ArtTracerPackage-<VERSION>.dmg` を生成
   - 同名 dmg があれば `rm -f` で削除してから作り直し（**上書きではなく削除→再生成**）

#### 処理内容（`NOTARIZE=1` の時のみ）

3. `codesign --force --timestamp` で dmg 自体を Developer ID 署名
4. `xcrun notarytool submit --wait` で Apple に提出（1〜5 分待機）
5. `xcrun stapler staple` で公証チケットを dmg に貼付

#### 環境変数

| 変数 | 既定値 | 説明 |
|---|---|---|
| `AIP_PATH` | `../output/mac/release/ArtTracer.aip` | dmg に入れる .aip のパス |
| `APP_PATH` | `../ArtTracer/Helper/build/Release/ArtTracerHelper.app` | dmg に入れる .app のパス |
| `NOTARIZE` | （未設定） | `1` を指定すると署名・公証・staple を実行 |
| `SIGN_ID` | `Developer ID Application: Motoi Kasuya (92U95PHRRW)` | dmg の署名 ID（`NOTARIZE=1` 時のみ使用） |
| `NOTARY_PROFILE` | `notary-profile` | notarytool キーチェーンプロファイル名（同上） |

#### バージョン番号について

`VERSION` は **dmg パッケージ自身のバージョン** にのみ使われ、ファイル名 (`ArtTracerPackage-<VERSION>.dmg`) と dmg マウント時のボリューム名 (`ArtTracerPackage <VERSION>`) に反映されます。同梱する `ArtTracer.aip` / `ArtTracerHelper.app` の内部バージョンは独立しており、それぞれ Xcode プロジェクトの設定で決まります。

### 2.4 `scripts/entitlements/Release.entitlements`

`ArtTracerHelper.app` および埋め込み `ArtTracerThumbnail.appex` の Release ビルド時に使用される entitlements ファイル。`get-task-allow` を **明示的に含めない** のがポイントです。

```xml
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
```

App Sandbox と「ユーザー選択ファイルの読み取り専用アクセス」のみを許可。`get-task-allow`（デバッガ attach 許可）は **公証で禁止されている** ため含めません。

---

## 3. 使い方

### 3.1 通常の本番リリース

```bash
cd /path/to/ArtTracerPackage
scripts/release.sh 1.0.0
```

これだけで以下が一気に実行されます：

1. `.aip` / `.app` をクリーンビルド + Developer ID 署名
2. dmg 作成
3. dmg 署名
4. Apple notary service に提出 + 公証完了まで待機
5. 公証チケットを dmg に貼付（staple）

所要時間は数分（公証の処理時間に依存）。

### 3.2 dmg だけ再生成したい時（公証なし）

成果物は再利用してパッケージ構成だけ試行錯誤したい時：

```bash
scripts/build-dmg.sh 1.0.0-test
```

`-test` などのサフィックスを付けると、公証済み dmg と混在しても識別しやすい。

### 3.3 ビルドだけ確認したい時

```bash
scripts/build-artifacts.sh
```

### 3.4 環境変数で挙動を変える例

別人のキーチェーンや別のディレクトリ構造でも動かせます：

```bash
SIGN_ID="Developer ID Application: 別の人 (XXXXXXXXXX)" \
TEAM_ID="XXXXXXXXXX" \
NOTARY_PROFILE="別のプロファイル名" \
AIP_PROJECT=/絶対パス/ArtTracer.xcodeproj \
HELPER_PROJECT=/絶対パス/ArtTracerHelper.xcodeproj \
scripts/release.sh 1.0.0
```

### 3.5 GitHub Releases に dmg を公開する

`dist/` と `*.dmg` は **`.gitignore` で git 管理対象外** にしてあります。dmg は通常の `git push` では飛ばず、**GitHub Releases に添付してダウンロード可能にする** のが配布フローです。

#### 全体の流れ

```
ローカルで scripts/release.sh 実行
    ↓
dist/ArtTracerPackage-<VERSION>.dmg ができる（git には含まれない）
    ↓
git tag v<VERSION> → push
    ↓
gh release create で dmg を添付して公開
    ↓
他人は Releases ページから dmg をダウンロード
```

#### 手順

**1. ソースの変更があれば push**

```bash
cd /path/to/ArtTracerPackage
git status                     # 未コミット変更が無いか確認
git push origin main           # 必要なら push
```

**2. タグを切って push**

```bash
git tag v1.0.0
git push origin v1.0.0
```

タグ名の慣習：先頭 `v` 付き（既存タグ `v0.0.0` と揃える）。

**3. Release を作って dmg を添付**

```bash
gh release create v1.0.0 \
    dist/ArtTracerPackage-1.0.0.dmg \
    --title "ArtTracerPackage 1.0.0" \
    --notes "初回正式リリース。詳細は CHANGELOG.md を参照。"
```

リリースノートを別ファイルから読みたい場合は `--notes-file <path>` を使用。

**4. ブラウザで確認（任意）**

```bash
gh release view v1.0.0 --web
```

#### 注意点

- **添付する dmg は必ず `scripts/release.sh` で作った公証済みのもの**。`rc1`/`rc2`/`test` 等のテスト用 dmg を上げないように
- **タグ名と dmg のバージョンを一致** させる（`v1.0.0` のタグなら dmg も `ArtTracerPackage-1.0.0.dmg`）
- 一度 publish した release のタグは原則変更しない。修正したい場合は `v1.0.1` として新リリース
- `CHANGELOG.md` は **タグを切る前** にコミットしておくと履歴が整う

#### 過去リリースを参照したい時

既存リリースの構成（添付ファイル / リリースノート）を確認：

```bash
gh release view v0.0.0
```

---

## 4. get-task-allow 問題と解決

このパイプラインを構築する過程で **公証が 2 回連続で Invalid** で拒否される問題に遭遇し、原因究明に時間を要したため記録として残します。

### 4.1 症状

`xcrun notarytool submit` の結果が `status: Invalid`。`xcrun notarytool log` の出力：

```
"message": "The executable requests the com.apple.security.get-task-allow entitlement."
```

両ターゲット（`ArtTracerHelper` 本体と `ArtTracerThumbnail` 拡張）に **`com.apple.security.get-task-allow = true`** が付いており、これは公証では絶対に許可されない entitlement。

### 4.2 真の原因

Xcode が **`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES`（デフォルト）** によって `get-task-allow=true` を自動注入していました。具体的には：

1. プロジェクトに明示的な `.entitlements` ファイルが存在しない
2. Xcode は App Sandbox 等のキャパビリティから entitlements を自動生成
3. その上に「base entitlements」として `get-task-allow=true` を **強制注入**
4. 結果として Release 構成でビルドしても `get-task-allow=true` が混入

`xcodebuild build` での挙動であり、`xcodebuild archive` を使えば自動的に除去されます。しかし archive ベースのフローは `ExportOptions.plist` 等の追加設定が必要なため、`build` を採用したまま解決する道を選びました。

### 4.3 過去の試行錯誤（失敗した仮説）

| 試したこと | 結果 | 理由 |
|---|---|---|
| `ENABLE_DEBUG_DYLIB=NO` を渡す | 失敗 | この設定は xcent 生成に影響しなかった |
| `CODE_SIGN_ENTITLEMENTS=<file>` だけ渡す | 失敗 | Xcode が自動注入を続け、ファイルの上に `get-task-allow=true` を追加 |
| `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` + `CODE_SIGN_ENTITLEMENTS=<file>` の **両方** | ✅ 成功 | base entitlements 注入を完全に停止できた |

### 4.4 採用した解決策

`scripts/entitlements/Release.entitlements` を新規作成し、`build-artifacts.sh` の Helper ビルド呼び出しに以下を追加：

```
CODE_SIGN_ENTITLEMENTS="$ROOT/scripts/entitlements/Release.entitlements"
CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
```

これで xcent ファイルから `get-task-allow` が完全に消え、公証が `Accepted` で通るようになりました。

### 4.5 確認手順

ビルド後、以下で entitlements を直接確認できます：

```bash
codesign -d --entitlements - --xml \
    ../ArtTracer/Helper/build/Release/ArtTracerHelper.app
```

`com.apple.security.get-task-allow` のキーが含まれていなければ OK。

公証完了後の最終確認：

```bash
xcrun stapler validate dist/ArtTracerPackage-1.0.0.dmg
spctl -a -t open --context context:primary-signature -v dist/ArtTracerPackage-1.0.0.dmg
```

期待される出力：

```
The validate action worked!
accepted
source=Notarized Developer ID
```

---

## 5. 必要な環境

### 5.1 macOS マシンのセットアップ

| 項目 | 内容 |
|---|---|
| macOS | これらのスクリプトは Mac 専用 |
| Xcode | コマンドラインツール含む。`xcodebuild`, `xcrun`, `codesign` が利用可能なこと |

### 5.2 キーチェーンに登録する 2 点

#### 1. Developer ID Application 証明書（秘密鍵込み）

- Apple Developer Program 加入が前提
- `.p12` 形式で他マシンから移行する場合は **秘密鍵込み** でエクスポート
- 確認コマンド：

```bash
security find-identity -p codesigning -v
```

`Developer ID Application: ...` が表示されれば OK。

#### 2. notarytool キーチェーンプロファイル

初回セットアップ：

```bash
xcrun notarytool store-credentials "notary-profile" \
    --apple-id <Apple ID> \
    --team-id 92U95PHRRW \
    --password <App-Specific Password>
```

- App-Specific Password は <https://appleid.apple.com> で発行
- プロファイル名（`notary-profile`）は `build-dmg.sh` の既定値と一致させる、または `NOTARY_PROFILE` 環境変数で上書き
- 確認コマンド：

```bash
xcrun notarytool history --keychain-profile "notary-profile"
```

エラーなく履歴（または空のレスポンス）が返れば OK。

### 5.3 ディレクトリ構造

スクリプトは相対パス前提なので、3 つのリポジトリを **同一階層の隣** に置く構成を維持してください：

```
<好きな場所>/IllustatorPlugins/
├── ArtTracer/                       ← .aip のソース
│   └── Helper/                      ← .app と .appex のソース
├── ArtTracerPackage/                ← このリポジトリ
└── output/                          ← .aip のビルド出力先（自動生成）
```

`AIP_PROJECT` / `HELPER_PROJECT` 環境変数で絶対パスを指定すれば、別の構造でも動かせます。

---

## 6. トラブルシューティング

| 症状 | 原因 / 対処 |
|---|---|
| `security find-identity` に Developer ID が無い | 証明書だけ import して秘密鍵が抜けている。`.p12` を秘密鍵込みで再エクスポート |
| 公証で `Forbidden` / `Unauthorized` | App-Specific Password が無効。Apple ID 側で再発行し `store-credentials` し直す |
| `notary-profile` が見つからない | 新マシンでは別途 `store-credentials` 必要 |
| 公証で `Invalid` + `get-task-allow` メッセージ | [4 章](#4-get-task-allow-問題と解決) の解決策が build-artifacts.sh から欠落している |
| 公証で `Invalid` + 別メッセージ | `xcrun notarytool log <id> --keychain-profile notary-profile` で詳細を確認 |
| `BUILD FAILED` | Xcode のバージョン互換、または依存リポジトリのソース不整合 |
| `ArtTracer.aip not found` / `ArtTracerHelper.app not found` | ビルドが事前に走っていない。`scripts/build-artifacts.sh` を先に実行 |

---

## 7. 設計判断のメモ

- **`build-artifacts.sh` と `build-dmg.sh` を分離した理由**: dmg だけ再生成したいケース（ステージング構成の試行錯誤など）でビルド時間を浪費しないため
- **`NOTARIZE=1` のオプトイン方式にした理由**: 公証は数分かかる + Apple サーバへの提出回数を無駄に消費したくない。普段のテストでは省略可能にした
- **`release.sh` を別に用意した理由**: 「これを叩けば本番リリース」という明確なセマンティクスを与えるため。手作業で `NOTARIZE=1` を付け忘れるリスクを排除
- **dist ディレクトリ全体を消さない理由**: 過去バージョンの dmg を履歴として残せるようにした。同一バージョンは同名ファイルを再生成する形で上書き
- **`xcodebuild archive` 方式を採用しなかった理由**: `ExportOptions.plist` の追加管理が必要で、現状のシンプルな `build` ベースで `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` 解法に到達したため不採用
