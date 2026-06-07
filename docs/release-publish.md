# リリース公開手順 (GitHub Releases)

`scripts/release.sh` で生成した dmg を GitHub Releases として公開するまでの一連の手順をまとめます。間隔が空いて忘れがちなので、毎回これに沿って進めれば確実です。

ビルド・公証パイプラインそのものについては [`release-pipeline.md`](release-pipeline.md) を参照してください。本文書は **「公証済み dmg が手元にある状態」から公開完了まで** をカバーします。

---

## 1. 全体フロー

```
1. CHANGELOG.md に新バージョン項目を追記
2. ソース変更を commit & push (main)
3. dmg をビルド・公証 (scripts/release.sh <VERSION>)
4. リリースノートファイルを作成
5. git タグを切って push
6. gh のアクティブを roundshape に切り替え
7. gh release create で dmg をアップロード
8. ブラウザで内容確認
9. gh のアクティブを元のアカウントに戻す
```

ステップ 2 と 3 は順序が前後しても問題ありません（CHANGELOG.md 修正を含む commit を先に出してから dmg をビルドする方が綺麗）。

---

## 2. バージョン表記の使い分け（重要）

3 箇所で表記が違うので注意：

| 場所 | 表記 | 例 |
|---|---|---|
| `release.sh` の引数 | `v` **なし** | `scripts/release.sh 0.0.2` |
| dmg のファイル名 | `v` なし（上の引数から派生） | `ArtTracerPackage-0.0.2.dmg` |
| **git タグ** | `v` **あり** | `v0.0.2` |
| **gh release create の引数** | `v` あり（タグ名と同じ） | `gh release create v0.0.2 ...` |

ルール：「**タグ系は `v` 付き、ファイル/バージョン系は `v` なし**」

---

## 3. ステップごとの詳細

### 3.1 CHANGELOG.md 追記

新バージョン項目を追加。既存フォーマットに合わせる：

```markdown
## [0.0.2] - 2026-05-19

- 主な変更点 1
- 主な変更点 2

- ArtTracer.aip <内部バージョン>
- ArtTracerHelper.app <内部バージョン>
```

日付は ISO 8601（YYYY-MM-DD）形式。同梱する .aip / .app の内部バージョンも併記（CHANGELOG.md の冒頭にこの運用ルールが書かれている）。

### 3.2 ソース変更を commit & push

```bash
cd /path/to/ArtTracerPackage
git status                # 変更ファイル確認
git add CHANGELOG.md scripts/ ai_docs/   # 必要なファイルだけ stage
git commit -m "v0.0.2 リリース準備"
git push origin main
```

SourceTree で commit / push してもよい。

### 3.3 dmg をビルド・公証

```bash
scripts/release.sh 0.0.2
```

数分かかる。最後に以下が出れば成功：

```
status: Accepted
The staple and validate action worked!
==> Done: .../dist/ArtTracerPackage-0.0.2.dmg
```

成果物の最終検証：

```bash
xcrun stapler validate dist/ArtTracerPackage-0.0.2.dmg
spctl -a -t open --context context:primary-signature -v dist/ArtTracerPackage-0.0.2.dmg
```

`The validate action worked!` と `source=Notarized Developer ID` が出れば配布可能。

### 3.4 リリースノートファイルを作成

`/tmp/release-notes-<VERSION>.md` に保存（CHANGELOG.md の該当節をベースに少し加筆する形が楽）：

```bash
cat > /tmp/release-notes-0.0.2.md <<'EOF'
v0.0.1 で発生していた起動不可問題を修正したマイナーリリース。

主な変更点:
- ArtTracerHelper.app の macOS Deployment Target を下げ、旧 macOS でも起動可能に修正
- ビルド出力先を build.noindex/ に変更し、Spotlight / LaunchServices の競合を防止

同梱バージョン:
- ArtTracer.aip 0.0.0
- ArtTracerHelper.app 0.0.0
EOF
```

長期保管したい場合は `ai_docs/release-notes/v0.0.2.md` のようにリポジトリ内に置く運用もアリ。

### 3.5 タグを切って push

```bash
git tag v0.0.2
git push origin v0.0.2
```

SourceTree で操作する場合：

1. 対象コミットを右クリック → 「タグ」
2. タグ名: `v0.0.2`
3. **「リモートにプッシュ」をチェック** ★ 忘れがち
4. OK

タグだけ push してもブランチ本体は飛ばないので、必要なら別途 `git push origin main` も実行。

### 3.6 gh のアクティブを roundshape に切り替え

`gh` は個人アカウント (例: `motoi-kasuya773`) と組織アカウント (`roundshape`) を切り替えながら使う構成。

```bash
gh auth status                 # 現在のアクティブを確認
gh auth switch -u roundshape   # roundshape に切り替え
```

リリースは `roundshape/ArtTracerPackage` 配下なので、roundshape として操作する必要がある。

> **マシン別の運用差に注意**
> このステップ (3.6) と「戻す」ステップ (3.9) は、**個人アカウントが普段使いの Mac** を前提にしている。
> - **roundshape が通常状態の Mac** (常に roundshape でログイン運用しているマシン) では、`switch` も「戻す」(3.9) も**不要**。`gh auth login` で roundshape を一度通しておけば、そのまま 3.7 へ進める。
> - **個人アカウントが普段使いの Mac** では、本ステップで roundshape に切り替え、公開後に 3.9 で個人に戻す。
> - 新しい Mac では `gh` 自体が未インストール / 未認証のことがある。`brew install gh` → `gh auth login` (ブラウザで対象アカウントにサインインした状態で実行) でセットアップする。

### 3.7 gh release create で公開

```bash
gh release create v0.0.2 \
    dist/ArtTracerPackage-0.0.2.dmg \
    --title "ArtTracerPackage 0.0.2" \
    --notes-file /tmp/release-notes-0.0.2.md
```

成功すると Releases ページの URL が出力される。

### 3.8 ブラウザで内容確認

```bash
gh release view v0.0.2 --web
```

確認項目：

- タイトル
- リリースノート本文
- **Assets セクションに `ArtTracerPackage-0.0.2.dmg` がダウンロード可能になっている**

### 3.9 gh のアクティブを戻す

> **roundshape が通常状態の Mac ではこのステップは不要**(3.6 の注記を参照)。以下は個人アカウントが普段使いの Mac 向け。

戻し忘れると、別件で「個人で作るつもりが組織側にリポジトリが作られる」等の事故が起こり得る。

```bash
gh auth switch -u motoi-kasuya773
gh auth status                 # Active: true が個人側に戻ったか確認
```

---

## 4. よくあるハマりどころ

| 症状 | 原因 / 対処 |
|---|---|
| `gh release create` で `Failed to create release, "workflow" scope may be required` | 認証スコープ不足。`gh auth refresh -h github.com -s workflow` を実行 |
| 認証時に `error refreshing credentials for X, received credentials for Y` | ブラウザでサインインしているアカウントと、gh の対象アカウントが違う。正しいアカウントでブラウザにサインインし直してから再実行 |
| dmg のファイル名に `v` が二重に入る (`ArtTracerPackage-v0.0.2.dmg`) | `release.sh` 引数に `v` を付けてしまっている。`v` なしで実行 |
| SourceTree でタグを切ったのに GitHub に出ない | 「リモートにプッシュ」のチェックを忘れている。タグを右クリック → 「タグをプッシュ」で送信 |
| ブランチを push したが SourceTree で未 push 表示 | タグだけ push してブランチ本体を忘れている。`git push origin main` を実行 |
| `gh auth status` で個人アカウントしか出ない | roundshape を未登録。`gh auth login` で追加（→ `release-pipeline.md` の補足や本文書の 3.6 を参照） |

---

## 5. 一括コピペ用テンプレート（参考）

> **自動化スクリプトあり**: コミット → タグ → push → アカウント切替 → リリース作成 → 復帰
> までは `scripts/gh-release.sh` に 1 本化してある。dmg をビルド済みなら次の 1 コマンドで済む:
> ```bash
> cd /path/to/ArtTracerPackage
> scripts/release.sh 0.0.6                                   # ビルド + 公証 (先に必要)
> scripts/gh-release.sh 0.0.6 "v0.0.6 リリース準備" /tmp/release-notes-0.0.6.md
> ```
> 第 3 引数 (ノートファイル) を省くと `--generate-notes` で自動生成。`--skip-commit` で
> コミット段階をスキップ (手動コミット済みのとき)。元 gh アカウントへは終了時に自動復帰
> するので、roundshape 常用 Mac でも個人常用 Mac でもそのまま動く。
> 以下は同じ流れを手動で行う場合の参考。

`VERSION` を書き換えて使う：

```bash
VERSION=0.0.2
TAG="v${VERSION}"

# (1) ビルド + 公証
cd /path/to/ArtTracerPackage
scripts/release.sh "$VERSION"

# (2) リリースノートを書く（事前準備）
$EDITOR "/tmp/release-notes-${VERSION}.md"

# (3) git タグ + push
git tag "$TAG"
git push origin "$TAG"

# (4) gh を roundshape に切り替え（roundshape が通常状態の Mac では不要）
gh auth switch -u roundshape

# (5) Release 作成
gh release create "$TAG" \
    "dist/ArtTracerPackage-${VERSION}.dmg" \
    --title "ArtTracerPackage ${VERSION}" \
    --notes-file "/tmp/release-notes-${VERSION}.md"

# (6) 確認
gh release view "$TAG" --web

# (7) gh を元に戻す（roundshape が通常状態の Mac では不要）
gh auth switch -u motoi-kasuya773
gh auth status
```
