# ArtTracer QuickJS スクリプト リファレンス

ArtTracer プラグインに組み込まれた QuickJS (quickjs-ng) から呼び出せる
グローバル関数のリファレンス。

選定経緯は [`script_language_choice.md`](./script_language_choice.md) を参照。

---

## 実行方法

1. Illustrator で ArtTracer パネルを開く
2. パネル右上のハンバーガーメニュー →「JS スクリプトを実行…」
3. `.js` ファイルを選択

スクリプトはモーダルで同期実行され、完了後にパネルのステータス欄へ
結果（ログ件数・最後の `console.log` 出力・エラー有無）が表示される。

---

## 実行環境

- ランタイム: QuickJS (quickjs-ng)
- 言語仕様: ES2020 相当（`let` / `const` / アロー関数 / `for...of` /
  `Array.prototype.forEach` 等が使える）
- 1 回の実行ごとに新規の JSRuntime + JSContext が生成される
  （前回実行時のグローバル状態は残らない）
- ワーカ・並列実行は非対応
- DOM / Node.js API（`require`, `fs`, `setTimeout` 等）は **無し**
- 提供されるのは下記のグローバル関数のみ

---

## グローバル関数

### `place(filename, x, y)`

`.artx` ファイルを Illustrator のアクティブドキュメントに配置する。

#### 引数

| 引数 | 型 | 説明 |
|------|-----|------|
| `filename` | string | `.artx` ファイルのパス。相対パスはスクリプトファイルの親ディレクトリ基準で解決される |
| `x` | number | 配置基準点の X 座標（ポイント単位） |
| `y` | number | 配置基準点の Y 座標（ポイント単位） |

#### 戻り値

- 成功時: `undefined`
- 失敗時: JS 例外をスロー（`InternalError` または `TypeError`）

#### 失敗するケース

- 引数が 3 個未満 → `TypeError`
- `filename` が文字列でない / `x`, `y` が数値でない → `TypeError`
- `.artx` の読み込み・XML パースに失敗 → `InternalError("place(...): load: ...")`
- `.artx` の検証 (Validate) でエラー → `InternalError("place(...): validate: ...")`
- Illustrator SDK の描画 (Render) でエラー → `InternalError("place(...): render: ...")`

例外はキャッチされなければスクリプト全体の実行を中断する。
描画フェーズのエラー詳細は `.artx` と同じ場所の `.log` ファイルにも書き出される。

#### 例

```javascript
// スクリプトと同じディレクトリの header.artx を原点に配置
place("header.artx", 0, 0);

// 10 個縦並びに配置
for (let i = 0; i < 10; i++) {
    place("item.artx", 0, i * 50);
}

// 絶対パス指定も可能
place("/Users/me/templates/footer.artx", 0, 500);

// 例外ハンドリングしたい場合
try {
    place("missing.artx", 0, 0);
} catch (e) {
    console.log("配置失敗:", e.message);
}
```

#### 補足: 設定の反映

ArtTracer の「設定…」で有効化される **テキスト溢れ自動調整**
（tracking → hScale カスケード）は、`place()` 経由の描画にも適用される。

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

---

## サンプル

### CSV テンプレを 1 行ずつ縦に並べる

```javascript
// 5 行ぶんを縦に 60pt 間隔で配置
for (let i = 0; i < 5; i++) {
    place("row.artx", 0, i * 60);
    console.log("placed row", i);
}
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

現状はミニマム API のみ。将来的に下記のような拡張余地がある。

- `place(filename, { x, y, scale, rotate, data })` 形式のオブジェクト引数
- `loadJson(path)` / `loadCsv(path)` などのデータ読み込みヘルパ
- 現在 ArtTracer パネルに読み込み済みの CSV データへのアクセス
- レイヤー指定 / Undo グループ境界の制御

これらは要件が固まった段階で `JsRuntime` に登録する関数として足していく。
