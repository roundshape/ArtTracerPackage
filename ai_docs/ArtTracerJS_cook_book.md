# ArtTracer JS クックブック — 効果的なスクリプトの書き方

ArtTracer の QuickJS で良いデザインを作るための**知恵（ベストプラクティス）**。
API の文法・引数・戻り値は `ArtTracer_quickjs_reference.md`（リファレンス）を引く。
ここは「文法を知っている前提で、どう書けば意図どおりに動くか」を扱う。

## 配置の基本フロー

依頼を受けたら、原則この順で進める:

1. **テンプレを選び、寸法を決め打ちしない** — 一覧の keywords で依頼に合うテンプレ
   を選び（選び方は `artx_cook_book.md`）、使うなら `getArtxInfo()` で実寸とメタ
   （width / height / プレースホルダ一覧 / **keywords**）を取得してから配置計算する。
2. **アートボードを取得して収まりを検証** — `getArtboards()` でアクティブな
   アートボードを取り、配置がはみ出さないか確認する。座標系は **Y 上向き**
   （下に並べるには y を**減らす**）。
3. **配置する** — `place()`（既存テンプレ）/ `placeArtxSource()`（その場生成の
   artx）。artx の作り方の知恵は `artx_cook_book.md` を参照。
4. **検証情報を残して確認する** — `writeLog()` に座標・寸法・収まり判定など
   検証に使った値を出力する。実行後に status（ok / errors / warnings）と
   writeLog を確認し、エラーがあれば**原因を直して再実行**する。

## 選択した art を編集する

ユーザーが選んだ art（**自分で描いていない物も含む**）を直すときは、`getSelection()`
を起点にする。返る各要素の `id` は自己修正系の動詞（`updateTextById` / `moveById` /
`scaleById` / `stretchById` / `replaceById`）に**そのまま渡せる**。

1. **`getSelection()` で選択を取る** — `{ id, kind, closed, bbox, zOrder }` の配列。
2. **「どれを」を見極める** — `kind`（text/path/group…）・`closed`（閉じパス＝枠候補）・
   `bbox`（サイズ）・`zOrder`（**0=最前面、大きいほど背面＝枠候補**）と、必要なら
   `render_view`（実画像）と依頼文から判断する。**曖昧なときは確認する**（黙って
   当てずっぽうで直さない）。
3. **「何に」を動詞へ写像して適用** — 文字内容＝`updateTextById`、移動/拡縮＝
   `moveById`/`scaleById`、丸ごと別 artx＝`replaceById`。
4. **確認して直す** — `render_view` で結果を見て、ズレていれば調整する。

### 例: 選択テキストの差し替え
```javascript
const t = getSelection().find(s => s.kind === "text");
if (t) updateTextById(t.id, "こんにちは、はじめまして");
```

### 例: 選択グループを選択枠（閉じパス）に綺麗に収める
枠＝**最背面の閉じパス**、中身＝それ以外、と見分ける。アスペクト比を保って枠に
収め、中央へ寄せ、**最後に render_view で確認して微調整**する:
```javascript
const sel   = getSelection();
const frame = sel.filter(s => s.kind === "path" && s.closed)
                 .sort((a, b) => b.zOrder - a.zOrder)[0];      // 最背面の閉じパス
const item  = sel.find(s => frame && s.id !== frame.id);       // 中身
if (frame && item) {
    const scale = Math.min(frame.bbox.width  / item.bbox.width,
                           frame.bbox.height / item.bbox.height);
    scaleById(item.id, scale);
    // 拡縮後の bbox を取り直して、枠の中心との差だけ move（中央寄せ）
    const a  = getSelection().find(s => s.id === item.id);
    const dx = (frame.bbox.left + frame.bbox.width  / 2) - (a.bbox.left + a.bbox.width  / 2);
    const dy = (frame.bbox.top  - frame.bbox.height / 2) - (a.bbox.top  - a.bbox.height / 2);
    moveById(item.id, dx, dy);
}
```

- 「綺麗に」は**枠の bbox に矩形フィット**（アスペクト保持＋中央寄せ）まで。**非矩形に
  ぴったり充填**するのは footprint パッキングで別物（現状は bbox 近似）。
- **塗り/線の色を変える**なら `setFillById(id, color)` / `setStrokeById(id, color [, width])`
  （`color` は artx と同じ `{ kind, v }`。線は第3引数で**幅(pt)も同時に**指定でき、省略時は
  据え置き。path / compound のみ。テキストの文字色・グループは未対応で、その場合は
  `replaceById` で丸ごと差し替える）。
- **「線を青・2pt に」のような色＋幅は `setStrokeById(id, color, width)` 一発で**やる。
  幅のために `replaceById` で作り直すと **id が変わって以降の編集の連続性が切れる**ので避ける。
- **複数塗り/線・重ね不透明度**（単一の基本塗り/線で表せない見た目）は
  `setAppearanceById(id, appearance)` で**アピアランスごと**設定する（path/compound/text。
  fx/影は未対応）。参照 artx の `<appearance>` を `read_artx` で読んで渡せば
  「**この artx の見た目を真似て**」も id を保ったまま実現できる。
- **テキストの文字色**は `setTextColorById(id, fill[, stroke, width])`（文字そのものの
  塗り/線）。`setFillById`/`setAppearanceById` の object 塗りは**文字色を変えない**（別の層）。
- **テキストのフチ文字**は2手の併用:
  ```javascript
  // 「白文字＋赤フチ」
  setTextColorById(id, { kind:"rgb", v:[1,1,1] });                  // ① 文字を白に
  setAppearanceById(id, { paints:[{ type:"stroke", kind:"rgb", v:[1,0,0], width:8 }],
                          contentPos: 0 });                          // ② 背面に赤線(=フチ)、文字は最前面
  ```

## 色

- `getDocumentInfo()` でドキュメントのカラーモード（rgb / cmyk / gray）を取得し、
  **それに合った色指定**を使う。モードと食い違う色指定をしない。

## コードの書き方

- **簡潔に書く。過剰な防御コードやフォールバックは書かない。** スクリプト全体が
  Undo 1 回分なので、失敗はユーザーの ⌘Z で戻せる。try/catch で握りつぶすより、
  素直に書いて失敗はログに出す方がデバッグしやすい。
