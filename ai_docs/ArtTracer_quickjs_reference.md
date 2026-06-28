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

### `placeArtxSource(xmlSource, x, y [, override])`

`place()` と同じだが、**ファイルパスでなく `.artx` の XML 文字列を直接**渡して
配置する。テンプレートをファイルに書き出さず、スクリプト内で生成した artx を
そのままメモリ上で描画できる。

`xmlSource` 以外の引数（`x` / `y` / `override`）と挙動（`setConfig()` 連動・
`{key}` 流し込み・グループ化・`group: true` 前提の scale/rotate・エラーの扱い）は
`place()` と完全に同じ。`override` に `{ fields: {...} }` を渡せば XML 内の
`{key}` に流し込める。

artx の書式は `artx-format.md` を参照（手書き / LLM 生成を前提とした形式）。
`{key}` を含めて `override.fields` で値を流し込む設計にすると再利用しやすい。

> いつ使うか・テキストの種類の選び方など**作り方の指針**は `artx_cook_book.md`
> を参照（このファイルは文法のみ）。

#### 例

```javascript
// 「こんにちはAI Chatです」を 36pt で描く最小の artx をその場で生成して配置
const xml = `<?xml version="1.0" encoding="UTF-8"?>
<artx version="1.0.2">
  <bounds x="0" y="0" w="400" h="60"/>
  <text x="0" y="44" align="left">
    <run font="HiraginoSans-W6" fontSize="36">
      <fill kind="gray" v="1"/>
      <content>{message}</content>
    </run>
  </text>
</artx>`;
const b = getArtboards().find(a => a.active);
placeArtxSource(xml, b.left + 24, b.top - 24, { fields: { message: "こんにちはAI Chatです" } });
```

#### 失敗するケース

`place()` と同じ（`xmlSource` が文字列でない → `TypeError`、XML パース失敗 /
`<artx>` ルート無し → `InternalError("placeArtxSource(): load: ...")` など）。

---

### 配置を後から直す（`deleteById` / `moveById` / `scaleById` / `stretchById` / `updateTextById` / `setFillById` / `setStrokeById` / `setAppearanceById` / `setTextColorById` / `replaceById` / `updateImageById`）

`place()` / `placeArtxSource()` で置いた要素は、**もう一度描き直さずに id を指して
直せる**。「価格を変えて」「少し右へ」のような修正で、毎回ゼロから作り直して前の
配置の上に積み上げる、という事故を避けるための仕組み。

#### id はどこから来るか

id は**自分で組み立てるものではない**。`place()` / `placeArtxSource()` が配置した
要素に内部で焼かれ、**実行結果（run_script の戻り）の `placements:` 欄**に返ってくる。
そこに出た id 文字列を**そのまま**次の呼び出しに渡す。

```
placements:
  - id="card_1" what="card" at=(24, 768) grouped=true
      parts: id="card_text_1" kind="text", id="card_path_1" kind="path"
```

- `grouped: true`（`setConfig({ group: true })`）で置くと、**丸ごと 1 個**を指す id
  が付く（上の `card_1`）。位置の移動・丸ごと削除はこれを使う。
- `parts:` は配置の**第一階層の要素**（テキスト・パスなど）。個別に直したいときは
  こちらの id を使う。
- 第一階層の要素が多すぎる複雑な配置は parts が付かない（丸ごとの id だけになる）。

> **丸ごと動かす / 消すハンドルが欲しいときは `group: true` で置いておく**。
> `group: false` だと丸ごとの id は付かず、parts だけになる。

#### `deleteById(id)`

id で指した配置を**削除**する。同じ場所に置き換えたいときは「消してから置く」で
表現する（`deleteById` → `place`）。

| 引数 | 型 | 説明 |
|------|-----|------|
| `id` | string | `placements:` で返ってきた id（丸ごとの id でも parts の id でもよい） |

- 戻り値: 成功時 `undefined` / 失敗時 例外
- 失敗するケース: `id` が文字列でない → `TypeError` ／ id が見つからない（置いて
  いない・既に削除した・⌘Z で戻した） → `InternalError`

#### `moveById(id, dx, dy)`

id で指した配置を `(dx, dy)` だけ**平行移動**する。座標系は `place()` の `x, y` と
同じ **AI 座標（Y 上向き・pt）**: `dx > 0` で右、`dy > 0` で**上**（下げるなら
`dy` を負に）。

| 引数 | 型 | 説明 |
|------|-----|------|
| `id` | string | `placements:` で返ってきた id |
| `dx` | number | 右方向の移動量（pt）。左へは負 |
| `dy` | number | **上**方向の移動量（pt）。下へは負 |

- 戻り値: 成功時 `undefined` / 失敗時 例外
- 失敗するケース: 引数 3 個未満 / `id` が文字列でない / `dx`,`dy` が数値でない・
  有限でない（NaN・∞） → `TypeError` ／ id が見つからない → `InternalError`

#### `scaleById(id, factor [, cx, cy])`

id で指した配置を `factor` 倍に**拡縮**する（線幅も比例してスケールする）。

- `cx`, `cy` を**省略**すると、その要素の**bbox 中心を固定してその場で拡縮**する
  （位置はほぼ変わらず大きさだけ変わる）。「このカードを 1.2 倍に」はこれ。
- `cx`, `cy` を**指定**すると、その点（`place()` と同じ AI 座標）を固定点に拡縮する。
  複数要素を同じアンカーで揃えて拡縮したいときなどに使う。**両方そろえて**渡すこと。

| 引数 | 型 | 説明 |
|------|-----|------|
| `id` | string | `placements:` で返ってきた id |
| `factor` | number | 拡縮率（`1.0` = 等倍、`2.0` = 2 倍、`0.5` = 半分）。**0 より大きい有限数** |
| `cx` `cy` | number | （任意）固定点。省略時は bbox 中心。指定するなら両方 |

- 戻り値: 成功時 `undefined` / 失敗時 例外
- 失敗するケース: 引数 2 個未満 / `id` が文字列でない / `factor` が数値でない・
  `0` 以下・有限でない（NaN・∞）/ `cx`,`cy` の片方だけ指定・有限でない → `TypeError`
  ／ id が見つからない → `InternalError`

```javascript
// card.artx をグループで置く → 結果の placements に id が返る
place("card.artx", 24, 768, { group: true });
// （run_script の結果で id="card_1" を確認してから）次の呼び出しで:
moveById("card_1", 0, -50);    // 50pt 下げる
scaleById("card_1", 1.2);      // その場で 1.2 倍に大きく
deleteById("card_1");          // やっぱり消す
```

#### `stretchById(id, sx, sy [, cx, cy])`

id で指した配置を **X 方向 `sx` 倍・Y 方向 `sy` 倍**に拡縮する（`scaleById` と違い
**縦横を独立**に変えられる＝**非等比**）。**artx を領域にぴったり流し込む**ときの主役
（領域の縦横比とテンプレの縦横比が違うと等比では収まらないため）。

- `cx`, `cy` の扱いは `scaleById` と同じ（省略時 bbox 中心、指定時その点を固定。両方そろえて）
- 線幅は**スケールしない**（非等比では一意に決まらないため不変）
- アスペクト比は変わる（テキスト・画像は長体／平体に歪む。それが目的の関数）

| 引数 | 型 | 説明 |
|------|-----|------|
| `id` | string | `placements:` で返ってきた id |
| `sx` | number | X 方向の倍率。**0 より大きい有限数** |
| `sy` | number | Y 方向の倍率。**0 より大きい有限数** |
| `cx` `cy` | number | （任意）固定点。省略時 bbox 中心。指定するなら両方 |

- 戻り値: 成功時 `undefined` / 失敗時 例外
- 失敗するケース: 引数 3 個未満 / `id` が文字列でない / `sx`,`sy` が数値でない・`0` 以下・
  NaN・∞ / `cx`,`cy` の片方だけ・有限でない → `TypeError` ／ id が見つからない → `InternalError`

```javascript
// artx を領域 (regionX, regionTop, regionW × regionH) にぴったり収める
const info = getArtxInfo("card.artx");          // { width, height, ... }
place("card.artx", regionX, regionTop, { group: true });
// （placements で id="card_1" を確認してから）左上を固定点に領域を埋める:
stretchById("card_1",
            regionW / info.width,               // 横の倍率
            regionH / info.height,              // 縦の倍率
            regionX, regionTop);                // place 基準点 = bbox 左上 を固定
```

#### `updateTextById(id, text)`

id で指した**テキスト要素の中身（文字列）**を `text` に丸ごと書き換える。位置・サイズ
を変える幾何系（move / scale / stretch）と違い、**中身を直す**動詞。「文言を直す」ための
安い経路。

- 文字スタイル（フォント・サイズ・色・フチ）は**元テキストの先頭文字の属性で全文を一本化**
  する。元が単一スタイルなら見た目そのままで文字だけ変わる。元が途中で色やサイズが変わる
  複数 run のテキストでも、書き換え後は先頭の属性に揃う
- **run ごとに色やサイズを作り分けたい**なら、`replaceById` でテキスト artx を丸ごと
  差し替える（AI が前の状態を読んで run を組み立てて渡す）
- `text` が空文字列ならテキストを空にする

| 引数 | 型 | 説明 |
|------|-----|------|
| `id` | string | `placements:` で返ってきた id（テキスト要素のもの） |
| `text` | string | 新しいテキスト本文（UTF-8） |

- 戻り値: 成功時 `undefined` / 失敗時 例外
- 失敗するケース: 引数 2 個未満 / `id`・`text` が文字列でない → `TypeError` ／ id が
  見つからない・**id がテキスト要素でない**・書き換え失敗 → `InternalError`

```javascript
place("price_tag.artx", x, y, { group: true });
// （placements で id="price_tag_1" のテキスト子 id を確認してから）文言だけ差し替え:
updateTextById("price_tag_text_1", "全品半額");
```

#### `replaceById(id, xmlSource [, override])`

id で指した要素の**中身を、新しい artx（XML 文字列）に丸ごと差し替える**。`updateTextById`
がテキストの文字列だけを直すのに対し、こちらは**塗り・線・グラデ・アピアランス・構成要素
まで含めて中身を入れ替える**動詞。`read_artx` で読む → XML を改変 → `replaceById` で差し替え、
という流れで「色を変えて」「デザインを差し替えて」に応える。新中身は**元要素と同じ位置・
同じ重ね順**（bbox 左上を基準）に収まる。

**id が維持されるかは対象による（「維持できる場合は維持する」）**:

| 対象（id の正体） | 動き | 返る id |
|---|---|---|
| **グループ**（`grouped=true` の丸ごと id、または入れ子グループ） | 入れ物を生かして**中の子だけ**入れ替える | **同じ id**（維持） |
| **葉**（path / text / image の単独 id） | 別オブジェクトとして**作り直す**（同じ場所に置き直し） | **新しい id**（`deleteById`+`place` 相当） |

- どちらの場合も、結果の id（維持された同じ id か、新しい id か）と新しい parts は
  **実行結果の `placements:` 欄**に返る。**次の編集には placements で返った id を使う**こと
  （葉を replace すると id は変わるので、古い id をそのまま使い続けない）
- `override` は `placeArtxSource` と同じ `{ fields: {...} }` 等の 1 回限り上書き。`scale` /
  `rotate` は無視される（中身の差し替えのみ。位置・サイズは元要素に従う）

| 引数 | 型 | 説明 |
|------|-----|------|
| `id` | string | `placements:` で返ってきた id |
| `xmlSource` | string | 新しい中身の artx XML（`placeArtxSource` と同じ書式） |
| `override` | object | （任意）`{ fields: {...} }` 等。`setConfig()` と同じ形 |

- 戻り値: 成功時 `undefined` / 失敗時 例外
- 失敗するケース: 引数 2 個未満 / `id`・`xmlSource` が文字列でない / `override` がオブジェクト
  でない・未知のキー → `TypeError` ／ id が見つからない・描画失敗 → `InternalError`

```javascript
// （placements で id="card_1" grouped=true を確認してから）中身を新デザインに差し替え:
// グループなので id="card_1" はそのまま維持される。
replaceById("card_1", '<artx version="1.1.0"> ... 改変した XML ... </artx>');
// 結果の placements で id を再確認（グループなら card_1 のまま、葉なら新 id）。
```

#### `updateImageById(id, filePath)`

id で指した**リンク画像のリンク先を、別ファイルに張り替える**。要素を**消さない**ので
**id（と位置・サイズ枠）は維持**される。「この写真を差し替えて」を、画像要素の id を保った
まま実現する安い経路（`replaceById` のように作り直さない）。

- **リンク画像（`href` 付き = `kPlacedArt`）専用**。`<data>` 埋め込み画像（`kRasterArt`）は
  リンクが無いので**張り替え不可（例外）**。埋め込み画像を変えたいときは `replaceById` で
  丸ごと差し替える（id は新しくなる）
- 内部は SDK の「リンクを再設定」（`ExecPlaceRequest kForceReplaceEx`）。同じ配置オブジェクト
  のまま表示が更新される

| 引数 | 型 | 説明 |
|------|-----|------|
| `id` | string | `placements:` で返ってきた画像の id（`kind="image"` のもの） |
| `filePath` | string | 新しい画像ファイルの**絶対パス** |

- 戻り値: 成功時 `undefined` / 失敗時 例外
- 失敗するケース: 引数 2 個未満 / `id`・`filePath` が文字列でない → `TypeError` ／ id が
  見つからない・**リンク画像でない（埋め込み）**・張り替え失敗 → `InternalError`

```javascript
// （placements で id="card_image_1" kind="image" を確認してから）リンク先を差し替え:
updateImageById("card_image_1", "/path/to/new_photo.png");   // 同じ id のまま画像が変わる
```

#### `setFillById(id, color)` / `setStrokeById(id, color [, width])`

id で指した**パス / 複合パスの塗り・線の色（線は幅も）を設定する**。`color` は artx の
`<fill>`/`<stroke>` と同じ表現（値は 0..1）:

```javascript
setFillById("sel_1",   { kind: "rgb",  v: [1, 0, 0] });          // 塗りを赤に
setFillById("sel_1",   { kind: "cmyk", v: [0, 1, 1, 0] });       // 塗りを赤(CMYK)に
setStrokeById("sel_1", { kind: "rgb",  v: [0, 0, 1] }, 2);       // 線を青・幅2pt に（1発）
setStrokeById("sel_1", { kind: "gray", v: [0] });               // 線を黒に（幅は据え置き）
setFillById("sel_1",   { kind: "none" });                        // 塗りなし
```

| 引数 | 型 | 説明 |
|------|-----|------|
| `id` | string | 対象の id（`getSelection` / `placements` の path・compound のもの） |
| `color` | object | `{ kind, v }`。`kind`=`"rgb"`(v=[r,g,b]) / `"cmyk"`(v=[c,m,y,k]) / `"gray"`(v=[g]) / `"none"`。値は **0..1** |
| `width` | number | （`setStrokeById` のみ・任意）線幅 pt。**省略すると幅は据え置き**。色＋幅を1回で指定でき、`replaceById` で作り直す必要がない（id が変わらない） |

- **対象は path / compound のみ**。**テキストの文字色・グループは未対応**（id がそれら
  だと `InternalError`）。テキストの色を変えたいときは現状 `replaceById` で丸ごと差し替える
- ドキュメントのカラーモードに合った `kind` を使う（`getDocumentInfo()` で確認）
- 戻り値: 成功時 `undefined` / 失敗時 例外（id が無い・対象が不適切・`color` が不正）

#### `setAppearanceById(id, appearance)`

id で指した要素の**アピアランス（塗り/線のスタック＋不透明度）を丸ごと設定する**。
`setFillById`/`setStrokeById` が単一の基本塗り/線なのに対し、こちらは**複数塗り/線・
フチ文字・重ね不透明度**を扱える。`appearance` は artx の `<appearance>`（§4.3）と同じ。

```javascript
setAppearanceById("sel_1", {
  opacity: 1.0,            // 任意: オブジェクト不透明度 0..1（省略 1.0）
  contentPos: -1,        // 任意: text のフチ文字用（中身がスタックの何番目か）。省略 -1
  paints: [               // 必須: 上→下（index 0 = 最前面）
    { type: "stroke", kind: "rgb", v: [0, 0, 1], width: 2 },
    { type: "stroke", kind: "rgb", v: [1, 1, 1], width: 6 },   // 白フチ等
    { type: "fill",   kind: "rgb", v: [1, 0.4, 0.7], opacity: 0.8 }
  ]
});
```

| キー | 型 | 説明 |
|------|-----|------|
| `paints` | array | 上→下の塗り/線スタック。各 `{ type:"fill"\|"stroke", kind, v, width?, opacity? }`。`kind`/`v` は `setFillById` と同じ |
| `opacity` | number | （任意）オブジェクト全体の不透明度 0..1 |
| `contentPos` | number | （任意・text）文字内容がスタックの何番目に来るか。フチ文字で文字を線の上に出すのに使う（path/compound では無視） |

- **対象は path / compound / text**。ただし**テキストの「塗り」は文字色を変えない**
  （文字色＝キャラクターカラーは `setTextColorById`）。テキストでは object の**線
  （アウトライン）と contentPos** を使い、文字色は `setTextColorById` と**併用**する
  → 「白文字＋赤フチ」は `setTextColorById(白)` ＋ `setAppearanceById(背面に赤線, contentPos:0)`
- **fx（影・ぼかし）・描画モード・グラデーション・破線/線端は未対応**（artx と同じ制限。
  複雑なものは `replaceById` で丸ごと）
- 既存のアピアランスは**置き換え**られる（差分追加ではない）
- 用途: 「二重線にして」「半透明の塗りを重ねて」など（path/compound）。テキストの
  フチは下記 `setTextColorById` と併用

#### `setTextColorById(id, fill [, stroke, strokeWidth])`

id で指した**テキストの文字色（キャラクターカラー）を設定する**。`setFillById` が
テキストを弾くのに対し、これは**文字そのものの塗り/線**を変える（テキスト専用）。
全文字に一律で当たる（run ごとの色分けはしない）。

```javascript
setTextColorById("sel_1", { kind: "rgb", v: [1, 1, 1] });                          // 白文字に
setTextColorById("sel_1", { kind: "rgb", v: [0, 0, 0] },                           // 黒文字 +
                          { kind: "rgb", v: [1, 0, 0] }, 0.5);                      //   赤い文字線(細)
```

| 引数 | 型 | 説明 |
|------|-----|------|
| `id` | string | テキストの id |
| `fill` | object | 文字の塗り `{ kind, v }`（`kind:"none"` で塗りなし） |
| `stroke` | object | （任意）文字の線の色 `{ kind, v }` |
| `strokeWidth` | number | （任意）文字の線幅 pt |

- **テキスト専用**（path/compound に投げると `InternalError`）
- **フチ文字**は「文字色 = `setTextColorById`」＋「アウトライン = `setAppearanceById`
  の背面の線 + `contentPos`」の**併用**で作る（例は cookbook 参照）

> これらは「**置いた要素を直す**」ための関数。新しく作るのは `place()` /
> `placeArtxSource()`、既にあるものを直すのが `deleteById` / `moveById` /
> `scaleById`（等比）/ `stretchById`（非等比）、中身（文字列）を直すのが
> `updateTextById`、リンク画像を張り替えるのが `updateImageById`、塗り/線の色を
> 変えるのが `setFillById`/`setStrokeById`（単色）、塗り/線スタック・重ね不透明度は
> `setAppearanceById`、テキストの文字色は `setTextColorById`、中身（artx 丸ごと）を
> 差し替えるのが `replaceById`、と使い分ける。**id を保ったまま直したいなら
> `updateTextById`（文字）・`updateImageById`（リンク画像）が第一候補、丸ごと作り直すのが
> `replaceById`**。id を持っていない（＝まだ置いていない）要素は指せない。

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

#### `getAllUids()` — 焼かれている UID 名の一覧（診断用）

ドキュメント内で **UID 名（id）が付いている art を全部**、文字列の配列で返す。各行は
`"id [種別] in 親id"` 形式（トップレベルは `in` 無し）。クリーンなドキュメントでは
「この実行で `place` した要素とその時々の状態」がそのまま並ぶので、id がどう焼かれたか・
維持されたかの**目視確認**に使える。

```javascript
const uids = getAllUids();
// 例: ["card_1 [group]", "card_text_1 [text] in card_1", "card_path_1 [path] in card_1", ...]
for (const u of uids) console.log(u);
```

- 戻り値: 文字列配列（UID 名なしの art は含まれない＝手で描いた図形等は出ない）
- 主に確認・デバッグ用途。配置の id は通常 `place` 直後の `placements:` で受け取る

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

### `getSelection()` — 選択 art を id + メタで取得（編集の起点）

現在の**トップレベル選択 art** を、自己修正系の動詞（`updateTextById` /
`moveById` / `scaleById` …）に**そのまま渡せる id 付き**で列挙する。`getSelectedPaths`
が「形状（閉じパスのみ）を読む」のに対し、こちらは「**選んだ任意の art を編集する**」
ための入口。

ユーザーが手で選んだ art には通常 id（UID 名）が無いので、**無ければ付与・あれば
再利用**して返す（これにより、自分で描いていない art も id で指して直せる）。

```javascript
const sel = getSelection();
// [
//   { id: "sel_text_1", kind: "text", closed: false,
//     bbox: { left, top, right, bottom, width, height }, zOrder: 0 },
//   { id: "sel_path_1", kind: "path", closed: true,  bbox: {...}, zOrder: 3 },
//   ...
// ]
```

| キー | 型 | 説明 |
|------|-----|------|
| `id` | string | UID 名。`updateTextById` 等にそのまま渡す。既存 id があれば再利用、無ければ `sel_<kind>_<連番>`（例 `sel_path_1`）を付与（place の `card_text_1` と同じ作法） |
| `kind` | string | `"text"` / `"path"` / `"group"` / `"compound"` / `"image"` / `"other"` |
| `closed` | boolean | `path` のとき閉じているか（**枠**判定の手がかり。閉じパス＝枠候補） |
| `bbox` | object | `{ left, top, right, bottom, width, height }`（AI 座標 Y-up: top > bottom） |
| `zOrder` | number | 親内の重ね順（**0 = 最前面**、大きいほど背面 = 枠候補） |

**使い分けの考え方**: `getSelection` は事実（id とメタ）を返すだけ。「どれが枠で
どれが中身か」「何を直すか」は、`kind` / `closed` / `bbox`（サイズ）/ `zOrder` と
`render_view`（視覚）と依頼文から **AI が推論する**。曖昧なときは確認する。

```javascript
// 例: 選択テキストを書き換える
const t = getSelection().find(s => s.kind === "text");
if (t) updateTextById(t.id, "こんにちは、はじめまして");

// 例: 選択グループを選択枠（最背面の閉じパス）に収める
const sel = getSelection();
const frame = sel.filter(s => s.kind === "path" && s.closed)
                 .sort((a, b) => b.zOrder - a.zOrder)[0];   // 最背面
const item  = sel.find(s => s.kind === "group");
if (frame && item) {
    const scale = Math.min(frame.bbox.width  / item.bbox.width,
                           frame.bbox.height / item.bbox.height);
    scaleById(item.id, scale);   // → 中央寄せは move で（bbox 再取得して調整）
}
```

副作用: id の無い選択 art に UID 名を焼く（`script` 全体の Undo 1 回に含まれる）。
ドキュメント未オープンのみ `InternalError`。選択 0 件は**空配列**。

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
//   width: 100, height: 50,            // <bounds> の w / h (pt)
//   version: "1.2.0",                  // artx フォーマットバージョン
//   fields: ["name", "price"],         // テキスト中の {key} 一覧（文書順・重複なし）
//   imageFields: ["photo"],            // <image name="..."> の画像差し替えキー一覧
//   keywords: ["冬", "クリスマス"]      // <keywords><k> の意味タグ（文書順・重複なし）
// }
```

| キー | 型 | 説明 |
|------|-----|------|
| `width` / `height` | number | `<bounds>` の寸法（pt）。`place(x, y)` の配置点 = bounds 左上なので、これで footprint が完全に決まる |
| `version` | string | `<artx version="...">` の値 |
| `fields` | string[] | テキスト中の `{key}` プレースホルダのキー一覧（`{{` `}}` エスケープは除外） |
| `imageFields` | string[] | `<image name="...">` の差し替えキー一覧（値はファイルパスとして解釈される側） |
| `keywords` | string[] | `<keywords><k>` の意味タグ一覧（季節・行事・用途など。preview から読み取れない意図情報。無ければ空配列） |

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
読み取り系も `getDocumentInfo` / `getLayers` / `getArtboards` / `getArtxInfo` /
`getAllUids` まで実装済み。自己修正系は `deleteById` / `moveById` / `scaleById` /
`stretchById` / `updateTextById` / `updateImageById` / `replaceById` まで実装済み。

次の候補（自動配置の JS 化に向けて）:

- `getSelectedPaths()` — 選択中の closed path の形状（頂点列・bbox）。
  これが揃うと grid 計算・footprint 包含テストが JS で書ける（Free Packing /
  領域分割の JS 移植の前提インフラ）

新しい関数・設定キーは要件が固まった段階で `JsRuntime` に登録する関数 /
`JsPlaceConfig` のキーとして足していく。
