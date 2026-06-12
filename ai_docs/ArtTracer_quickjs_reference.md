# ArtTracer QuickJS スクリプト リファレンス

ArtTracer プラグインに組み込まれた QuickJS (quickjs-ng) から呼び出せる
グローバル関数のリファレンス。

選定経緯は [`script_language_choice.md`](./script_language_choice.md) を参照。

---

## 実行方法

### パネルから手動実行

1. Illustrator で ArtTracer パネルを開く
2. パネル右上のハンバーガーメニュー →「JS スクリプトを実行…」
3. `.js` ファイルを選択

スクリプトはモーダルで同期実行され、完了後にパネルのステータス欄へ
結果（ログ件数・最後の `console.log` 出力・エラー有無）が表示される。

### inbox 監視による自動実行

1. ハンバーガーメニュー →「JS inbox 監視を開始…」で監視フォルダを選択
2. 監視開始後にそのフォルダへ置かれた（または更新された）`.js` が自動実行される

実行のたびに、スクリプトと同じ場所へ次のファイルが書き出される。

| ファイル | 内容 |
|------|------|
| `<script>.js.status.json` | 実行結果。`{ ok, errors, warnings, logCount, writeLogCount, startedAt, finishedAt }`。成功・失敗どちらでも必ず書かれる |
| `<script>.js.out.log` | `writeLog()` の出力（1 呼び出し = 1 行） |
| `<script>.js.log` | エラー・警告があった場合の詳細 |

---

## 実行環境

- ランタイム: QuickJS (quickjs-ng)
- 言語仕様: ES2020 相当（`let` / `const` / アロー関数 / `for...of` /
  `Array.prototype.forEach` 等が使える）
- 1 回の実行ごとに新規の JSRuntime + JSContext が生成される
  （前回実行時のグローバル状態は残らない）
- スクリプト 1 回の実行全体が Undo 1 回分になる（⌘Z で全配置が戻る）
- 描画設定はパネル UI から完全に独立（hermetic 実行）。すべてコード定義の
  デフォルトから始まり、`setConfig()` で宣言したものだけが反映される
- ワーカ・並列実行は非対応
- DOM / Node.js API（`require`, `fs`, `setTimeout` 等）は **無し**
- 提供されるのは下記のグローバル関数のみ

---

## 座標系（重要）

`place()` / `getArtboards()` / `getSelectedPaths()` が扱う座標は、すべて
**Illustrator の AI 座標系（Y 上向き・単位 pt）** の生値である。

- **y は大きいほど上**。下へ移動するには y を**減らす**
- `getArtboards()` の `top` は**上端の y（そのアートボード内で最大の y）**。
  アートボード内の y の範囲は `[top - height, top]`
- `place()` の配置基準点はテンプレートの **bbox 左上**。配置されたアートは
  y から下方向へ `height` 分を占める（下端 = `y - height`）
- 上端から d pt 下げて置く: `y = top - d`。n 段目:
  `y = top - margin - n * (cardH + gap)`
- はみ出し検証: 下端 `y - cardH >= top - height`、右端 `x + cardW <= left + width`

> **注意:** [`artx-format.md`](./artx-format.md) にある「左上原点 / Y 下向き」は
> **`.artx` ファイル内部の座標**の話。`place()` の引数とは**逆向き**なので
> 混同しないこと。

```javascript
// アートボード左上に 24pt マージンで配置（動作確認済みのパターン）
const b = getArtboards().find(a => a.active);
place("card.artx", b.left + 24, b.top - 24);
```

---

## グローバル関数

### `place(filename, x, y [, override])`

`.artx` ファイルを Illustrator のアクティブドキュメントに配置する。

#### 引数

| 引数 | 型 | 説明 |
|------|-----|------|
| `filename` | string | `.artx` ファイルのパス。相対パスはスクリプトファイルの親ディレクトリ基準で解決される |
| `x` | number | 配置基準点（テンプレート bbox 左上）の X 座標（pt） |
| `y` | number | 配置基準点（テンプレート bbox 左上）の Y 座標（pt、**Y 上向き** — 上記「座標系」参照） |
| `override` | object（省略可） | `setConfig()` と同じ形のオブジェクト。**この 1 呼び出しに限り**現在の設定に merge して適用される（グローバル設定は変更されない） |

#### 戻り値

- 成功時: `undefined`
- 失敗時: JS 例外をスロー（`InternalError` または `TypeError`）

#### 失敗するケース

- 引数が 3 個未満 → `TypeError`
- `filename` が文字列でない / `x`, `y` が数値でない → `TypeError`
- `override` のキーが不正 → `TypeError`（`setConfig` と同じ検証）
- `.artx` の読み込み・XML パースに失敗 → `InternalError("place(...): load: ...")`
- `.artx` の検証 (Validate) でエラー → `InternalError("place(...): validate: ...")`
- Illustrator SDK の描画 (Render) でエラー → `InternalError("place(...): render: ...")`

例外はキャッチされなければスクリプト全体の実行を中断する。
描画フェーズのエラー詳細は `.artx` と同じ場所の `.log` ファイルにも書き出される。

> **scale / rotate は `group: true` が前提。** グループ化なしで指定された場合、
> 変換は適用されず警告が積まれる（実行は継続する）。

#### 例

```javascript
const b = getArtboards().find(a => a.active);

// アートボード左上に配置
place("header.artx", b.left + 24, b.top - 24);

// 10 個縦並びに配置（下へ並べるので y を減らす）
for (let i = 0; i < 10; i++) {
    place("item.artx", b.left + 24, b.top - 24 - i * 50);
}

// fields でテンプレートの {key} プレースホルダに値を差し込む
place("card.artx", b.left + 24, b.top - 24, {
    fields: { title: "ブレンドコーヒー", price: "480" },
});

// 1 回だけ 50% 縮小して配置（group が必要）
place("logo.artx", b.left + 24, b.top - 24, { group: true, scale: 0.5 });

// 例外ハンドリングしたい場合
try {
    place("missing.artx", 0, 0);
} catch (e) {
    console.log("配置失敗:", e.message);
}
```

---

### `setConfig(config)`

以降の `place()` に適用される描画設定を更新する。指定したキーだけを上書きし
（merge）、未指定のキーは現在値を保持する。**未知のキーは `TypeError`**
（タイポの早期検出）。パネル UI の設定とは完全に独立。

#### 設定キー

| キー | 型 | デフォルト | 説明 |
|------|-----|------|------|
| `group` | boolean | `false` | 配置 1 回分を 1 グループに wrap する |
| `scale` | number | `1.0` | 拡縮率（1.0 = 原寸）。**0 以下は `TypeError`**。要 `group: true` |
| `rotate` | number | `0` | 回転角（度、正 = 反時計回り）。要 `group: true` |
| `rotateCenter` | `"base"` \| `"bounds"` \| `{x, y}` | `"base"` | 回転中心。`"base"` = 配置基準点、`"bounds"` = bounds 中心、`{x, y}` = 任意点（place と同じ座標系） |
| `layer` | string | `""` | 描画先レイヤ名。`""` = 現在のアクティブレイヤ |
| `fields` | object | なし | テンプレートの `{key}` プレースホルダへの差し込み値 `{ key: 値, ... }`。値は文字列化される。merge ではなく**丸ごと差し替え**（place 1 回 = 1 行データ） |
| `autoFit` | object | 無効 | テキスト溢れ自動調整。`{ enabled, tracking, hScale, leading, trackingMin, hScaleMin, leadingMin }` |
| `footprint` | boolean | `false` | footprint（占有領域）を赤線でデバッグ重ね描きする |

#### 例

```javascript
setConfig({ group: true });                       // 以降の place をグループ化
setConfig({ layer: "カード" });                    // 描画先レイヤを指定
setConfig({ autoFit: { enabled: true } });        // テキスト溢れ自動調整を有効化
```

---

### `console.log(...args)`

引数を空白区切りで連結し、1 行のログとして出力する。

- スクリプト実行完了後、**最後の 1 行**がパネルのステータス欄に表示される
- 出力件数は status の `logCount` に数えられる
- ファイルへは書き出されない（ファイルに残したい場合は `writeLog()`）

オブジェクトは `[object Object]` になるため、`JSON.stringify` を併用する。

```javascript
console.log("data:", JSON.stringify({ x: 100, y: 200 }));
```

---

### `writeLog(...args)`

引数を空白区切りで連結し、`<script>.js.out.log` へ 1 行書き出す。
実行結果の検証情報（配置座標・取得した寸法・判断の根拠など）を残す用途。
出力件数は status の `writeLogCount` に数えられる。

```javascript
writeLog("layout:", cols, "cols x", rows, "rows, start", x + "," + y);
```

---

### `loadCsv(path)`

CSV ファイルを読み込み、行オブジェクトの配列を返す。

- 戻り値: `[ { ヘッダー名: セル値, ... }, ... ]`
- 値は**常に文字列**（数値が必要なら JS 側で `Number()` する）
- 空ヘッダーの列は除外される
- パス解決は `place()` と同じ（スクリプト親ディレクトリ基準）
- パネルにロード済みの CSV とは無関係（hermetic）
- ファイル無し・パース失敗は JS 例外

```javascript
const rows = loadCsv("menu.csv");
rows.forEach((row, i) => {
    place("card.artx", x, yTop - i * 160, { fields: row });
});
```

---

### `loadJson(path)`

JSON ファイルを読み込み、パース結果を返す（`JSON.parse` と同じ挙動。
ルートが配列なら配列、オブジェクトならオブジェクト）。パス解決は `place()`
と同じ。ファイル無し・パース失敗は JS 例外。

---

### `getDocumentInfo()`

アクティブドキュメントの情報を返す。

- 戻り値: `{ name, colorMode }`（`colorMode` は `"rgb"` / `"cmyk"` 等）
- ドキュメントが開かれていなければ `InternalError`

色指定はドキュメントの `colorMode` に合わせること（CMYK ドキュメントに
RGB 色を流すと色が沈む）。

---

### `getArtboards()`

アートボード情報の配列を返す（ドキュメントの定義順）。

- 戻り値: `[ { name, left, top, width, height, active }, ... ]`
- 座標は `place()` と同じ AI 座標系の生値。**`top` は上端の y（最大値）**
- ドキュメントが開かれていなければ `InternalError`

```javascript
const b = getArtboards().find(a => a.active);  // アクティブアートボード
```

---

### `getLayers()`

レイヤ情報の配列を返す（UI のレイヤパネルと同じ、上から下の順）。

- 戻り値: `[ { name, visible, locked, current }, ... ]`

---

### `getSelectedPaths([options])`

選択中の **closed path** の形状スナップショット配列を返す。

- 戻り値: `[ { closed, bbox: { left, top, right, bottom }, points: [{x, y}, ...] }, ... ]`
- 対象は closed path のみ。グループは再帰展開、open path・複合パス・
  テキストは無視される
- 曲線は線分近似（flatten）済み。`options.tolerance`（pt、デフォルト 0.5）で
  近似の細かさを変えられる
- 座標は `place()` と同じ AI 座標系の生値
- **選択なしは空配列**（例外ではない）

```javascript
const sel = getSelectedPaths();
sel.forEach((p, i) => {
    place("card.artx", p.bbox.left, p.bbox.top, { fields: rows[i] });
});
```

---

### `getArtxInfo(path)`

`.artx` テンプレートを配置せずに調べる。**配置計算の前に必ずこれで実寸を
取得すること**（寸法を仮定しない）。

- 戻り値: `{ width, height, version, fields: [...], imageFields: [...] }`
- `width` / `height` はテンプレートの寸法（pt）
- `fields` は `{key}` プレースホルダ名の一覧、`imageFields` は画像差し込み
  フィールド名の一覧
- パス解決は `place()` と同じ

```javascript
const info = getArtxInfo("card.artx");
writeLog("template:", info.width, "x", info.height, "fields:", info.fields.join(","));
```

---

## パス解決の詳細

`place()` / `loadCsv()` / `loadJson()` / `getArtxInfo()` に渡したパスは、
以下のルールで解決される。

| 入力 | 解決結果 |
|------|----------|
| `"/abs/path/file.artx"` | そのまま絶対パスとして使う |
| `"file.artx"` | `<スクリプトの親ディレクトリ>/file.artx` |
| `"sub/file.artx"` | `<スクリプトの親ディレクトリ>/sub/file.artx` |
| `"../shared/file.artx"` | `<スクリプトの親ディレクトリ>/../shared/file.artx`（`fopen` がそのまま解釈） |

スクリプトファイルの位置を基準にした相対パスでテンプレを参照できるため、
プロジェクトディレクトリ単位での持ち運びがしやすい。

---

## エラーとログ

- JS 構文エラー・実行時例外は `message` と `stack` を結合して
  ArtTracer の `ErrorSink`（"render" フェーズ）へ積まれる
- 1 件以上のエラーや警告があれば、スクリプトと同じ場所に `.log` ファイルが
  書き出される
- パネルステータスにはエラーの先頭メッセージとログファイルパスが表示される
- inbox 実行では成功・失敗にかかわらず `<script>.js.status.json` が書かれる

---

## サンプル

### テンプレートの実寸を測ってグリッド配置（はみ出し検証つき）

```javascript
const b = getArtboards().find(a => a.active);
const info = getArtxInfo("card.artx");
const W = info.width, H = info.height, GAP = 20, MARGIN = 24;

setConfig({ group: true });

// アートボード幅に収まる列数を計算して折り返す
const cols = Math.max(1, Math.floor((b.width - MARGIN * 2 + GAP) / (W + GAP)));

const items = loadCsv("menu.csv");
items.forEach((row, i) => {
    const x = b.left + MARGIN + (i % cols) * (W + GAP);
    const y = b.top - MARGIN - Math.floor(i / cols) * (H + GAP);  // 下へは引き算
    place("card.artx", x, y, { fields: row });
    writeLog(`[${i}] (${x.toFixed(1)}, ${y.toFixed(1)}) ← ${row.title}`);
});

console.log("配置完了:", items.length, "個");
```

### 選択パスの位置にデータを流し込む

```javascript
const rows = loadCsv("menu.csv");
const sel = getSelectedPaths();
setConfig({ group: true });

sel.forEach((p, i) => {
    place("card.artx", p.bbox.left, p.bbox.top, { fields: rows[i % rows.length] });
});
```

---

## 今後の拡張余地（未実装）

- 現在 ArtTracer パネルに読み込み済みの CSV データへのアクセス
- Undo グループ境界の制御（現状はスクリプト全体で固定 1 回）
- 配置済みアートの取得・削除・移動（現状は配置のみ。やり直しはユーザーの ⌘Z）

これらは要件が固まった段階で `JsRuntime` に登録する関数として足していく。
