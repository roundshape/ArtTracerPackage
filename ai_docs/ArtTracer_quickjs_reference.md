# ArtTracer QuickJS スクリプト リファレンス

ArtTracer プラグインに組み込まれた QuickJS (quickjs-ng) から呼び出せる
グローバル関数のリファレンス。

選定経緯は [`script_language_choice.md`](./script_language_choice.md) を参照。

---

## 実行方法

### 手動実行

1. Illustrator で ArtTracer パネルを開く
2. パネル右上のハンバーガーメニュー →「JS スクリプトを実行…」
3. `.js` ファイルを選択

スクリプトはモーダルで同期実行され、完了後にパネルのステータス欄へ
結果（ログ件数・最後の `console.log` 出力・エラー有無）が表示される。

### inbox フォルダ監視（自動実行）

ハンバーガーメニュー →「JS inbox 監視を開始…」でフォルダを選ぶと、その
フォルダ内の **`.js` ファイルの作成・更新を検知して自動実行**する。AI
エージェント（Claude 等）や外部ツールがスクリプトを書き込むだけで実行される、
会話的デザインの実行経路。「JS inbox 監視を停止」で止まる。

- **監視中はメニューの「JS inbox 監視を開始…」にチェックマークが付く**。
  いま監視が動いているかはここで確認する（メニューを開くたびに実状態を
  引き直すので常に正確）
- 監視フォルダと ON/OFF は永続化され、ON のまま Illustrator を終了したら
  次回起動時に自動で監視を再開する。再開時はステータス欄に何も出さない
  （状態はチェックマークで確認）。再開できなかった場合（フォルダが消えた等）
  だけ理由をステータス欄に表示する
- **監視開始前から置いてあったファイルは実行しない**（開始後の変更のみ）
- 書き込み途中の誤実行は 2 段の安全弁で防ぐ（FSEvents の 0.5 秒イベント
  集約 + size/mtime の安定確認）。**同一内容の二重実行はしない** — 同じ
  スクリプトを再実行したいときはファイルを書き直す（touch でも可）
- 実行のされ方は手動実行と完全に同じ（hermetic / Undo 1 回 / ログ規約）

#### 完了通知: `<script>.js.status.json`

実行が終わるたび（成功でも失敗でも）スクリプトの隣に **status ファイル**を
書く。スクリプトを投入した側は「このファイルの出現 = 実行完了」で検知し、
中身で成否を判定できる（手動実行でも同じく書かれる）:

```json
{
  "ok": true,
  "errors": 0,
  "warnings": 0,
  "logCount": 1,
  "writeLogCount": 6,
  "startedAt": "2026-06-11T16:38:45+0900",
  "finishedAt": "2026-06-11T16:38:46+0900"
}
```

- 実行開始時に前回の `.js.log` / `.js.out.log` / `.js.status.json` を削除し、
  status は**他のログをすべて書き終えてから最後に**書く。status が見えた
  時点で他のログの完全性が保証される
- `ok: false` のとき、エラー詳細は従来どおり `<script>.js.log`（JSON）にある

---

## 実行環境

- ランタイム: QuickJS (quickjs-ng)
- 言語仕様: ES2020 相当（`let` / `const` / アロー関数 / `for...of` /
  `Array.prototype.forEach` 等が使える）
- 1 回の実行ごとに新規の JSRuntime + JSContext が生成される
  （前回実行時のグローバル状態・`setConfig` の設定は残らない）
- 描画設定は `setConfig()` で JS の中から宣言する。**UI パネルの設定・レイヤ
  選択・CSV には一切依存しない**（hermetic 実行 = 同じスクリプトは常に同じ結果）
- ワーカ・並列実行は非対応
- DOM / Node.js API（`require`, `fs`, `setTimeout` 等）は **無し**
- 提供されるのは下記のグローバル関数のみ
- **Undo はスクリプト実行全体で 1 回**。スクリプト内で何回 `place()` しても
  Illustrator の取り消し 1 回（「ArtTracer JS の取り消し」）で全配置が消える

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
> 混同しないこと（LLM がここを取り違えてアートボード外に配置する事故が
> 実際に起きた）。

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
| `x` | number | 配置基準点の X 座標（ポイント単位） |
| `y` | number | 配置基準点の Y 座標（ポイント単位） |
| `override` | object | （任意）`setConfig()` と同じ形のオブジェクト。**この 1 呼び出しだけ**直近の設定を上書きする。グローバル設定（`setConfig()` の蓄積値）は変更しないので、次の `place()` は元の設定に戻る。データ駆動配置では `{ fields: row }` を渡してテンプレへ `{key}` 流し込みするのが典型用途（後述） |

#### 戻り値

- 成功時: `undefined`
- 失敗時: JS 例外をスロー（`InternalError` または `TypeError`）

#### 失敗するケース

- 引数が 3 個未満 → `TypeError`
- `filename` が文字列でない / `x`, `y` が数値でない → `TypeError`
- `override` がオブジェクトでない / 未知のキーを含む → `TypeError`（`setConfig()` と同じ検証）
- `.artx` の読み込み・XML パース失敗 / `<artx>` ルート要素が無い → `InternalError("place(...): load: ...")`
- `setConfig({layer})` で指定したレイヤ名が見つからない → `InternalError("place(...): layer: ...")`
- Illustrator SDK の描画 (Render) でエラー → `InternalError("place(...): render: N error(s) — log: ...")`

例外はキャッチされなければスクリプト全体の実行を中断する（それより前に描画した
アートはドキュメントに残るが、スクリプト実行全体が 1 つの Undo なので ⌘Z 1 回で
まとめて取り消せる）。

エラーの出力先:

- パネルのステータス欄に先頭エラーメッセージとログパスが表示される
- スクリプト（`.js`）と同じ場所の `<script>.js.log` に全エラー + スタックが JSON で残る
- 描画フェーズまで到達したエラーは `.artx` と同じ場所の `<artx>.log` にも書かれる
- ただし `try/catch` で捕捉した場合はどちらにも残らない（`e.message` を自分で扱う）

#### 例

```javascript
// スクリプトと同じディレクトリの header.artx を原点に配置
place("header.artx", 0, 0);

// 10 個縦並びに配置（Y 上向きなので、下へ並べるには y を減らす）
const b = getArtboards().find(a => a.active);
for (let i = 0; i < 10; i++) {
    place("item.artx", b.left + 24, b.top - 24 - i * 50);
}

// 絶対パス指定も可能
place("/Users/me/templates/footer.artx", 0, 500);

// この 1 回だけグループ化・0.5 倍で配置（次の place は元の設定に戻る）
setConfig({ scale: 1.0 });
place("a.artx", 0, 0);                          // scale=1.0, group=false
place("a.artx", 0, 100, { group: true, scale: 0.5 });  // この行だけ上書き
place("a.artx", 0, 200);                        // scale=1.0, group=false に戻る

// 例外ハンドリングしたい場合
try {
    place("missing.artx", 0, 0);
} catch (e) {
    console.log("配置失敗:", e.message);
}
```

#### 補足: 設定は `setConfig()` で（UI とは独立）

`place()` のグループ化・スケール・溢れ自動調整・描画先レイヤなどの設定は、
**UI パネルの「設定…」やレイヤ popup とは一切連動しない**。これらは
`setConfig()`（下記）で JS の中から宣言する（hermetic 実行）。

同じ `.js` + `.artx` は、パネルの状態が何であっても常に同じ結果を出す。
未指定の項目はコード定義のデフォルトになる。

---

### `loadCsv(path)`

CSV ファイルをその場で読み込み、行オブジェクトの配列を返す。データ駆動
レイアウト用。スクリプトが返ってきた配列を自分でループして座標を計算し、
`place()` で配置する想定。

**UI パネルの「CSV を開く」でロードした CSV とは完全に独立**（hermetic 実行）。
パーサは共有するが、読み込んだデータは JS 実行に閉じる。UI で何をロード
していても、していなくても、同じ `loadCsv("data.csv")` は同じ結果を返す。

#### 引数

| 引数 | 型 | 説明 |
|------|-----|------|
| `path` | string | CSV ファイルのパス。相対パスは `place()` と同じくスクリプトファイルの親ディレクトリ基準で解決される |

#### 戻り値

行オブジェクトの配列。各行は `{ ヘッダー名: セル値 }`。

```javascript
const rows = loadCsv("items.csv");
// rows = [ { name: "りんご", price: "120" },
//          { name: "みかん", price: "80" } ]
```

- **値は常に文字列**。数値が必要なら JS 側で `Number(row.price)` する
- 1 行目はヘッダーとして扱う（RFC 4180 サブセット: LF/CRLF・`"..."` クォート・`""` エスケープ）
- **空ヘッダーの列は除外**される（キーにならない）
- 同名ヘッダーが複数ある場合は最後の列の値が残る

#### 失敗するケース

- `path` が文字列でない → `TypeError`
- ファイルが開けない / パース失敗 → `InternalError("loadCsv(...): ...")`

例外はキャッチされなければスクリプト全体を中断する（`place()` と同じ）。

#### 例

```javascript
// CSV を読み込んで縦に並べ、各行の値をテンプレへ流し込む
const rows = loadCsv("items.csv");
rows.forEach((row, i) => {
    console.log(row.name, row.price);
    // card.artx 内の {name} {price} が row の値に置換される
    place("card.artx", 0, i * 80, { fields: row });
});
```

`loadCsv()` が返す行オブジェクトはそのまま `place()` の `{ fields: row }` に
渡せる（`setConfig` の `fields` キー参照）。座標計算はスクリプトが行い、値の
差し込みは `fields` が担う、という分担。

---

### `loadJson(path)`

JSON ファイルをその場で読み込み、パース結果をそのまま返す（`JSON.parse` と
同じ挙動）。`loadCsv()` がフラットな表しか表現できないのに対し、ネストした
構造（カテゴリごとの一覧・設定オブジェクト等）をスクリプトに渡せる。

`loadCsv()` と同じく **UI の状態とは完全に独立**（hermetic 実行）。

#### 引数

| 引数 | 型 | 説明 |
|------|-----|------|
| `path` | string | JSON ファイルのパス。相対パスは `place()` と同じくスクリプトファイルの親ディレクトリ基準で解決される |

#### 戻り値

JSON のルート値そのまま。`loadCsv()` と違い形は固定しない — ルートが配列なら
配列、オブジェクトならオブジェクトが返る。

```javascript
// items.json = [ {"name": "りんご", "price": 120}, ... ]
const rows = loadJson("items.json");

// config.json = { "gap": 10, "items": [...] }
const data = loadJson("config.json");
data.items.forEach(...);
```

- 値の型は JSON のまま（数値は number、真偽値は boolean）。`loadCsv()` の
  「常に文字列」とは異なる
- `place()` の `{ fields: row }` に渡す場合はフラットなオブジェクトにする
  こと（`fields` の値は文字列化される。ネストしたオブジェクトを値に持つと
  `[object Object]` になる）

#### 失敗するケース

- `path` が文字列でない → `TypeError`
- ファイルが開けない → `InternalError("loadJson(...): ...")`
- JSON として不正 → `SyntaxError`（エラー位置にファイルパスが入る）

例外はキャッチされなければスクリプト全体を中断する（`place()` と同じ）。

#### 例

```javascript
// カテゴリごとに列を分け、カテゴリ内で縦に並べる（ネスト構造の活用例）
const catalog = loadJson("catalog.json");
// catalog = [ { "category": "果物", "items": [ {...}, ... ] }, ... ]
catalog.forEach((cat, col) => {
    cat.items.forEach((item, row) => {
        place("card.artx", col * 140, row * 80,
              { fields: { name: item.name, price: item.price } });
    });
});
```

---

### `getDocumentInfo()` / `getLayers()` / `getArtboards()` — ドキュメント読み取り

ドキュメントの状態を**スナップショット**（呼んだ瞬間の値をコピーした素の
オブジェクト/配列）として返す読み取り系 API。SDK の生のハンドルは渡さない。
座標・寸法は `place()` の x, y と同じドキュメント座標系 / pt。

> hermetic 原則との関係: これらの戻り値はドキュメントの内容で変わるが、
> 「UI **パネル**の状態に暗黙依存しない」という原則は維持される。入力が
> パネルではなくドキュメントそのものになるだけで、同じドキュメント + 同じ
> スクリプトなら常に同じ結果になる。

#### `getDocumentInfo()`

```javascript
const doc = getDocumentInfo();
// { name: "カタログ2026.ai", colorMode: "cmyk" }
```

| キー | 型 | 説明 |
|------|-----|------|
| `name` | string | ドキュメントのファイル名 |
| `colorMode` | string | `"rgb"` / `"cmyk"` / `"gray"` |

```javascript
// CMYK 前提のスクリプトを RGB ドキュメントで実行したら止めるガード
if (getDocumentInfo().colorMode !== "cmyk")
    throw new Error("このスクリプトは CMYK ドキュメント専用です");
```

#### `getLayers()`

レイヤ情報の配列を返す。並びはレイヤパネルと同じ上から下。

```javascript
const layers = getLayers();
// [ { name: "背景", visible: true, locked: false, current: false },
//   { name: "配置", visible: true, locked: false, current: true } ]

// place の layer: は見つからないとエラーで止まるので、事前確認に使える
const target = layers.some(l => l.name === "配置") ? "配置" : "";
setConfig({ layer: target });  // 無ければ現アクティブレイヤにフォールバック
```

| キー | 型 | 説明 |
|------|-----|------|
| `name` | string | レイヤ名 |
| `visible` | boolean | 表示中か |
| `locked` | boolean | ロック中か（= 編集不可） |
| `current` | boolean | 現在のアクティブレイヤか |

#### `getArtboards()`

アートボード情報の配列を返す（ドキュメントの定義順）。アートボードは
独立した座標系ではなく**ドキュメント座標空間に置かれた矩形**なので、
bounds が分かれば `place()` の座標計算は足し算だけでできる。

```javascript
const boards = getArtboards();
// [ { name: "表面", left: 0, top: 0, width: 257.95, height: 155.91, active: true },
//   { name: "裏面", left: 300, top: 0, width: 257.95, height: 155.91, active: false } ]

// アートボード 1 枚 = CSV 1 行 で流し込む（面付け的な使い方）
const rows = loadCsv("members.csv");
boards.forEach((b, i) => {
    if (i < rows.length)
        place("card.artx", b.left, b.top, { fields: rows[i] });
});
```

| キー | 型 | 説明 |
|------|-----|------|
| `name` | string | アートボード名。未設定なら `"Artboard N"` |
| `left` / `top` | number | 左上角（`place()` と同じ座標系の生値） |
| `width` / `height` | number | 寸法（pt、常に正） |
| `active` | boolean | アクティブなアートボードか |

#### 失敗するケース（3 関数共通）

- ドキュメントが開かれていない → `InternalError("...: ドキュメントが開かれていません")`

---

### `getSelectedPaths([options])` — 選択パスの形状

ドキュメントで**選択中の closed path** の形状をスナップショットで返す。
収集規則は UI の自動配置と同じ: closed な path だけを集め、グループは中身へ
再帰展開し、open path / 複合パス / テキストは黙って無視する。

形状は**多角形近似**（曲線を線分の列に flatten したもの）のみで、ベジェの
制御点情報は返さない。包含判定・面積計算・パッキングといった幾何処理に
そのまま使える形を返すのが目的。座標は `place()` の x, y と同じドキュメント
座標系の生値（Y は上向き正。`bbox.top > bbox.bottom` になる）。

> **アピアランス（ライブエフェクト）は反映されない**: 返すのはパスの素の
> 幾何データであって、描画結果ではない。「効果 > スタイライズ > 角を丸くする」
> 等を適用したパスは、見た目が角丸でも**鋭角のままの形状**が返る（効果は
> appearance 側に乗っていて、パスデータを変えないため）。これは UI の自動配置
> の包含判定と同じ挙動。見た目どおりの形状が必要なら、Illustrator 側で
> 「オブジェクト > アピアランスを分割」してから選択する。

```javascript
const paths = getSelectedPaths();
// [ {
//     closed: true,
//     bbox: { left: 100, top: 400, right: 300, bottom: 200 },
//     points: [ {x: 100, y: 200}, {x: 300, y: 200}, {x: 200, y: 400} ]
//   }, ... ]
```

| キー | 型 | 説明 |
|------|-----|------|
| `closed` | boolean | 常に `true`（closed path のみ収集するため。open path を返す拡張をした場合の判別用） |
| `bbox` | object | `points` の外接矩形 `{ left, top, right, bottom }` |
| `points` | object[] | flatten 済み頂点列 `[{x, y}, ...]`。閉じているが先頭点を末尾に重複させない |

#### `options.tolerance` — 近似の細かさ

曲線の線分近似の許容誤差（pt、デフォルト `0.5`）。小さいほど頂点が増えて
正確になる。footprint 包含判定の用途ならデフォルトで十分。

```javascript
const rough = getSelectedPaths({ tolerance: 2.0 });  // 粗く・軽く
```

```javascript
// 選択した closed path それぞれの bbox 左上に artx を 1 枚ずつ配置
for (const p of getSelectedPaths())
    place("stamp.artx", p.bbox.left, p.bbox.top);
```

#### 失敗するケース

- ドキュメントが開かれていない → `InternalError("getSelectedPaths(): ドキュメントが開かれていません")`
- `options` がオブジェクトでない / 未知のキーがある → `TypeError`
- `tolerance` が有限数でない・0 以下 → `TypeError`

選択が空、または closed path を含まない選択は**エラーではなく空配列**
（スクリプト側で「選択がありません」を出すかどうか決められる）。

---

### `getArtxInfo(path)` — テンプレートのメタ情報

artx テンプレートの**メタ情報**（寸法・プレースホルダ一覧）をスナップショット
で返す。アートの中身（パス・色・画像データ）は返さない — メタは artx に冗長
保持せず、呼ばれるたびにコンテンツから導出する（artx は手書き / LLM 生成され
る形式なので、導出値の写しを持つと同期漏れで嘘をつくため）。

**配置計算の前に必ずこれで実寸を取得すること。** 寸法を仮定・推測して
レイアウトすると、実物との差で重なりやはみ出しが起きる（LLM が寸法を
仮定して配置した実例あり）。

```javascript
const info = getArtxInfo("card.artx");
// {
//   width: 100, height: 50,        // <bounds> の w / h (pt)
//   version: "1.0.2",              // artx フォーマットバージョン
//   fields: ["name", "price"],     // テキスト中の {key} 一覧（文書順・重複なし）
//   imageFields: ["photo"]         // <image name="..."> の画像差し替えキー一覧
// }
```

| キー | 型 | 説明 |
|------|-----|------|
| `width` / `height` | number | `<bounds>` の寸法（pt）。`place(x, y)` の配置点 = bounds 左上なので、これで footprint が完全に決まる |
| `version` | string | `<artx version="...">` の値 |
| `fields` | string[] | テキスト中の `{key}` プレースホルダのキー一覧（`{{` `}}` エスケープは除外） |
| `imageFields` | string[] | `<image name="...">` の差し替えキー一覧（値はファイルパスとして解釈される側） |

`path` は `place()` と同じくスクリプト親ディレクトリ基準で相対解決。読み込みと
検証は `place()` の load と同じ経路を通す。

```javascript
// 流し込み前に CSV の列がテンプレの要求を満たしているか検証（fail fast）
const info = getArtxInfo("card.artx");
const rows = loadCsv("items.csv");
const missing = info.fields.filter(f => !(f in rows[0]));
if (missing.length)
    throw new Error(`CSV に列が足りません: ${missing.join(", ")}`);

// アートボード中央に配置（getArtboards との合わせ技）
const b = getArtboards().find(b => b.active);
place("card.artx", b.left + (b.width  - info.width)  / 2,
                   b.top  + (b.height - info.height) / 2);
```

#### 失敗するケース

- `path` が文字列でない → `TypeError`
- ファイルが開けない / XML パース失敗 / `<artx>` ルート欠落 → `InternalError("getArtxInfo(...): ...")`

---

### `setConfig(config)`

`place()` の描画設定を宣言する。指定したキーだけを上書きし（merge）、未指定の
キーは現在値を保持する。設定は以降の `place()` 呼び出しすべてに適用される。

設定は **UI パネルとは独立**（hermetic）。1 回のスクリプト実行ごとにデフォルトへ
リセットされ、実行をまたいで持ち越さない。

#### 設定キー

| キー | 型 | デフォルト | 説明 |
|------|-----|-----------|------|
| `scale` | number | `1.0` | artx 全体の拡縮率（1.0 = 原寸）。**0 より大きい有限数のみ**。**`group: true` が必要**（下記） |
| `rotate` | number | `0` | 配置 artx の回転角（度、正 = 反時計回り、有限数のみ）。**`group: true` が必要**（下記） |
| `rotateCenter` | string \| object | `"base"` | 回転中心。`"base"` = 配置点 / `"bounds"` = 描画結果の bounds 中心 / `{x, y}` = 任意点。下記参照 |
| `group` | boolean | `false` | 各 artx を 1 グループに wrap し、Dictionary に ArtTracer 属性を書く。scale / rotate の前提条件 |
| `footprint` | boolean | `false` | footprint を赤線でデバッグ重ね描き |
| `layer` | string | `""` | 描画先レイヤ名。`""` は現在のアクティブレイヤ。見つからなければ `place()` がエラー |
| `autoFit` | object | 下記 | テキスト溢れ自動調整（ネストオブジェクト） |
| `fields` | object | `{}` | テンプレート中の `{key}` を流し込む値（`{ ヘッダー名: 値 }`）。下記参照 |

`autoFit` のサブキー:

| キー | 型 | デフォルト | 説明 |
|------|-----|-----------|------|
| `enabled` | boolean | `false` | 溢れ自動調整を有効化 |
| `tracking` | boolean | `true` | トラッキングを詰める |
| `hScale` | boolean | `true` | 水平比率（長体）を詰める |
| `leading` | boolean | `true` | 行送りを詰める |
| `trackingMin` | number | `-50` | トラッキング下限（1/1000 em） |
| `hScaleMin` | number | `0.9` | 水平比率の下限（1.0 = 100%） |
| `leadingMin` | number | `14.0` | 行送りの下限（pt） |

#### `scale` / `rotate` には `group: true` が必要

scale / rotate は「グループ = 配置単位」に対する変換、という整理。ドキュメント
の構造（グループの有無）は `group` だけが決め、scale / rotate で暗黙にグループ
が生えることはない。

`group: true` が無いまま `scale` ≠ 1.0 / `rotate` ≠ 0 を指定した場合、その
`place()` は**変換を適用せず素描画**になり、警告が `.js.log` に出る
（パネルステータスにも警告件数が表示される）。**スクリプトは止まらない** —
途中で例外停止すると部分配置のまま終わるため、完走優先の設計。

```javascript
setConfig({ group: true });           // ← scale / rotate を使うなら宣言
place("card.artx", 0, 0, { scale: 0.5, rotate: 15 });
```

#### `rotate` / `rotateCenter` — 配置 artx の回転

`place()` 1 回で配置される artx（の描画結果）を回転する。grid やドキュメント
全体を回すものではない。`scale` 併用時は **scale（配置点基準）→ rotate** の順に
適用される。

`rotateCenter` で回転の軸を選ぶ:

| 値 | 回転中心 |
|----|----------|
| `"base"`（デフォルト） | 配置点（`place(x, y)` で渡した点 = artx の原点）。ピンで留めて振り回すイメージ |
| `"bounds"` | 描画結果（スケール適用後）の外接矩形の中心。「その場で傾く」イメージ |
| `{ x: 100, y: 50 }` | 任意点。**`place()` の x, y と同じ座標系**。複数の artx を共通の中心で放射状に回す用途など |

```javascript
// その場で 15° 傾けて並べる
setConfig({ group: true, rotateCenter: "bounds" });
for (let i = 0; i < 5; i++) {
    place("card.artx", i * 120, 0, { rotate: 15 });
}

// 共通の中心 (0, 0) のまわりに 12 枚を放射状に配置
setConfig({ group: true });
for (let i = 0; i < 12; i++) {
    place("card.artx", 0, 100,
          { rotate: i * 30, rotateCenter: { x: 0, y: 0 } });
}
```

- `group: true` が前提（前節参照）。回転はグループに対してかかる
- 線幅は変わらない（回転のみ）
- `footprint: true` のデバッグ赤線は回転を反映しない（配置点基準のまま）

#### `fields` — テンプレートへの `{key}` 流し込み

`fields` はテンプレート（`.artx`）の中に置いた `{ヘッダー名}` プレースホルダを
実際の値に置換するためのデータ。**`loadCsv()` が返す行オブジェクトをそのまま
渡す**のが想定用途（データ駆動レイアウト）。

```javascript
const rows = loadCsv("items.csv");
rows.forEach((row, i) => {
    // card.artx 内の {name} {price} が row の値に置換される
    place("card.artx", 0, i * 80, { fields: row });
});
```

- 通常は `place()` の第 4 引数（override）で**1 呼び出しごとに**渡す
  （行ごとに値が違うため）。`setConfig({ fields: {...} })` で全 `place()` 共通の
  固定値として宣言することもできる。
- **値は文字列化される**（数値を渡しても `"123"` になる）。
- **JS オブジェクトの宣言順（プロパティ順）が保持される**。`group: true` のときの
  グループ名・id は「1 列目（＝最初のプロパティ）のキー-値」になる規約なので、
  ID にしたいフィールドを先頭に置く。
- `fields` を渡さない / 空オブジェクトのときは流し込みなし（`{key}` はそのまま残る）。
- `group: true` を併用すると、CSV 流し込み時（UI）と同じく `{key}` 値・id・
  フィールドが描画グループの Dictionary に記録される（トレーサビリティ）。

#### 画像フィールド（リンク配置）

テンプレートに `<image name="photo">` のように `name` 属性付きの画像を置いておくと、
`fields` の同名キーの値を**画像ファイルのパス**として差し替えられる（`{}` は不要、
`name` は素のキー名）。差し替えた画像は **Illustrator の「ファイル > 配置（リンク）」
と同等のリンク配置**になる（埋め込みではない）。配置は枠を縦横比維持で覆う
（cover）+ 中央寄せ。

```javascript
place("card.artx", 0, 0, {
    fields: { photo: "images/apple.png", name: "りんご" }
});
```

- パスの解決基準は **スクリプト（`.js`）の親ディレクトリ**。`place()` / `loadCsv()`
  の相対パスと同じ基準なので、プロジェクトを丸ごと持ち運べる。
  - 絶対パス（`/...`）はそのまま使う。
  - UI の CSV 流し込みは「CSV ファイルの場所」基準だが、JS の `fields` はデータが
    特定の CSV ファイルに結びつかない（複数 CSV の合成・手書きオブジェクト等もある）
    ため、JS では一貫してスクリプト基準にしている。
- 解決したパスにファイルが無い場合は、テンプレートに埋め込まれた元画像へ静かに
  フォールバックする（差し替え失敗は警告ログに残る）。

#### 失敗するケース

- 引数がオブジェクトでない → `TypeError`
- 未知のキー（タイポ等）→ `TypeError("setConfig: unknown key '...'")`
- `scale` 等の数値キーに数値でない値・`NaN`・`±Infinity` → `TypeError("... must be a finite number")`
- `scale` が 0 以下 → `TypeError("setConfig: 'scale' must be > 0")`。SDK の変換は
  `scale: 0` でもエラーを返さず 1 点に潰れたアートを作ってしまうため、ここで弾く
- `rotateCenter` が `"base"` / `"bounds"` / `{x, y}` のどれでもない → `TypeError`
- `fields` がオブジェクトでない → `TypeError("setConfig: 'fields' must be an object")`

未知キーで弾くのはタイポを早期に検出するため（hermetic スクリプトの信頼性を保つ）。

#### 例

```javascript
// 既定（group なし・原寸）で 1 個
place("a.artx", 0, 0);

// 以降はグループ化 ON
setConfig({ group: true });
place("a.artx", 0, 100);

// scale だけ追加（group: true は merge で保持される）
setConfig({ scale: 0.5 });
place("a.artx", 0, 200);

// レイヤ指定 + 溢れ自動調整
setConfig({
    layer: "Layer 1",
    autoFit: { enabled: true, tracking: true, hScale: true }
});
place("label.artx", 0, 300);
```

---

### `console.log(...args)`

引数を空白区切りで連結し、1 行のログとして出力する。

#### 引数

- 任意個数の値。各値は文字列に変換されて連結される。

#### 出力先

- スクリプト実行完了後、**最後の 1 行** がパネルのステータス欄に表示される
- 出力されたログの総件数もステータス欄に表示される（例:
  `JS 実行完了 (5 log) — last: 配置完了`）
- 標準出力やファイルへは書き出されない

#### 例

```javascript
console.log("開始");
console.log("配置回数:", 10, "件");
console.log({ x: 100, y: 200 });   // -> [object Object] と表示される（JSON.stringify は自分で呼ぶ）
```

オブジェクトを見やすく出したい場合は `JSON.stringify` を併用する。

```javascript
const obj = { x: 100, y: 200 };
console.log("data:", JSON.stringify(obj));
```

---

### `writeLog(...args)`

`console.log` と同じく引数を空白区切りで連結するが、出力先が違う。**全行が
ファイルに残る**ので、データ確認やデバッグの記録に使う。`console.log` は画面
（ステータス欄の最後の 1 行）専用、`writeLog` はファイル専用、と役割を分けている。

#### 引数

- 任意個数の値。各値は文字列に変換されて連結される（`console.log` と同じ）。

#### 出力先

- スクリプトと同じ場所の **`<script>.js.out.log`** にプレーンテキストで書き出す
  （例: `foo.js` → `foo.js.out.log`）
- その実行で呼ばれた `writeLog` の**全行**が 1 ファイルに溜まる（途中の行も全部残る）
- **実行のたびに上書き**される（前回実行のログは消える）
- 1 行も呼ばれなければファイルは作られない
- ステータス欄には件数と出力先が出る（例:
  `JS 実行完了 (2 log, 5 writeLog) — out: .../foo.js.out.log`）

#### 例

```javascript
// loadCsv の中身を全行ファイルで確認する
const rows = loadCsv("items.csv");
writeLog("rows:", rows.length);
rows.forEach((row, i) => {
    writeLog(i, JSON.stringify(row));
});
// → foo.js.out.log に各行が残る
```

---

## パス解決の詳細

`place()` の第 1 引数に渡したパスは、以下のルールで解決される。

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
- **実行開始時に前回の `.js.log` / `.js.out.log` を削除する**。エラーも
  `writeLog()` も無いクリーンな実行ではログファイルは作られないので、
  「ログファイルが存在する = 直近の実行で出たもの」が常に成立する

---

## サンプル

### CSV を 1 行ずつ縦に並べ、各行の値を流し込む

```javascript
// items.csv の各行を 60pt 間隔で縦に配置し、row.artx 内の
// {name} / {price} を行の値に置換する（データ駆動レイアウト）
const rows = loadCsv("items.csv");
rows.forEach((row, i) => {
    place("row.artx", 0, i * 60, { fields: row });
});
console.log(`配置完了: ${rows.length} 行`);
```

### グリッド配置

```javascript
const cols = 4;
const rows = 3;
const w = 120;
const h = 80;

for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
        place("card.artx", c * w, r * h);
    }
}

console.log(`配置完了: ${cols * rows} 個`);
```

---

## 今後の拡張余地（未実装）

当初挙げていた候補（`loadJson` / Undo 境界 / `rotate`）はすべて実装済み。
読み取り系も `getDocumentInfo` / `getLayers` / `getArtboards` / `getArtxInfo`
まで実装済み。

次の候補（自動配置の JS 化に向けて）:

- `getSelectedPaths()` — 選択中の closed path の形状（頂点列・bbox）。
  これが揃うと grid 計算・footprint 包含テストが JS で書ける（Free Packing /
  領域分割の JS 移植の前提インフラ）

新しい関数・設定キーは要件が固まった段階で `JsRuntime` に登録する関数 /
`JsPlaceConfig` のキーとして足していく。
