# .artx フォーマット仕様

`.artx` は ArtTracer プラグインで使う **テンプレート XML** ファイル形式です。Adobe Illustrator のアート（パス・複合パス・グループ・テキスト・配置画像）と塗り/線の情報を、座標系を正規化したうえで保存・復元します。テキストは `{キー}` 形式のプレースホルダで CSV データ流し込みにも対応しています。

このドキュメントは、AI（LLM）がこの仕様を読んで `.artx` ファイルを直接生成できるよう設計されています。

---

## 1. 共通ルール

### 1.1 ファイル形式

- XML 1.0 / UTF-8
- インデント: 半角スペース 2 つ
- ルート要素: `<artx version="1">`

### 1.2 座標系

`.artx` 内の座標は **左上原点 (0,0) / Y下向き / 単位 pt (ポイント)**。

- Illustrator の AI 座標系は Y 上向きですが、`.artx` 側では Y 下向きに正規化されています
- `<bounds>` の左上が (0,0)、右下が (w, h)
- 描画時はユーザーがクリックした「基準点」が (0,0) として扱われます

### 1.3 角度の符号規約

`<fill kind="gradient">` の `angle` / `hiliteAngle` は **度 (degrees)** で記述しますが、Y下向きに合わせて符号を反転します。

- AI 内部のグラデーション角度が +30° であれば、`.artx` には `angle="-30"` と書きます
- 読み込み時は再度符号反転するため、ラウンドトリップで一致します

### 1.4 数値の整形

すべての数値は `%.4f` 相当で出力後、末尾の `0` と `.` を除去した形式（例: `123.4500` → `123.45`、`5.0000` → `5`）。`-0` は `0` に正規化されます。

### 1.5 描画順序 (z-order)

> **生成時のルール: 背景は最後に書く。前景 (テキスト・装飾) を最初に書く。**

アート要素は **XML 上の出現順 = 前面 → 背面** で並びます。Illustrator のレイヤーパネルと同じ順序：

- XML で **先に書いたものが前面 (top of z-order)**、**後に書いたものが背面 (bottom)**
- Illustrator のレイヤーパネル表示順と一致（パネル上で上にある項目ほど前面）
- **SVG とは逆**（SVG は painter's algorithm で「先=背面、後=前面」）

```xml
<artx version="1">
  <bounds .../>
  <text>最前面のロゴ</text>  <!-- ← 一番前面 (パネル最上段) -->
  <path>中間レイヤー</path>
  <path>背景</path>          <!-- ← 一番背面 (パネル最下段) -->
</artx>
```

このルールはあらゆる入れ子レベルで一貫します：

- `<artx>` 直下のアート要素間
- `<group>` 内のアート要素間
- `<path clipMask="true">` / `<compound clipMask="true">` の **クリップ対象子** 同士の間
- `<compound>` の `<subs>` 内のサブパス同士は重ね順ではなく even-odd ルールに従うので無関係

クリップマスク要素 (`<path clipMask="true">` または `<compound clipMask="true">`) 自身はマスク形状なので z-order に表示として現れません（描画されるのは内部のクリップ対象子のみ）。

> 内部メモ: AI SDK の `GetArtFirstChild` が返す最初の子が z-order 最前面という設計に従っています。Writer はこの順で出力し、Reader は逆変換時に各子を `kPlaceInsideOnBottom`（尾側）で順次追加することで同じ順序を再現します。

---

## 2. ドキュメント構造

```xml
<?xml version="1.0" encoding="UTF-8"?>
<artx version="1">
  <bounds x="0" y="0" w="WIDTH" h="HEIGHT"/>
  <!-- アートのトップレベル要素を直接並べる (<items> ラッパは無い) -->
  <path .../>
  <group>
    ...
  </group>
</artx>
```

| 要素 | 意味 |
|---|---|
| `<bounds>` | テンプレート全体の最小包囲矩形。原点は常に `x="0" y="0"`、`w` / `h` は pt 単位。 |
| アート要素 | `<path>` / `<compound>` / `<group>` / `<text>` / `<image>` を `<artx>` 直下に直接並べる。**記述順 = 前面 → 背面** (Illustrator のレイヤーパネル順) — 詳細は §1.5。 |

> 子要素の判定ルール: タグ名で機械的に分けます。`<bounds>` `<fill>` `<stroke>` `<segments>` `<subs>` `<run>` `<content>` `<stop>` `<color>` `<s>` などは「自要素のプロパティ系タグ」。`<path>` `<compound>` `<group>` `<text>` は「描画対象のアート要素」です。

---

## 3. アート要素

### 3.1 `<path>` — 単一パス

```xml
<path closed="true">
  <fill .../>
  <stroke .../>
  <segments>
    <s p="X,Y" in="X,Y" out="X,Y" corner="true"/>
    ...
  </segments>
</path>
```

| 属性 | 型 | 既定 | 意味 |
|---|---|---|---|
| `closed` | bool | `false` | パスを閉じるか |
| `clipMask` | bool | `false` | クリップマスク化する。`true` のとき、自身がマスク形状となり、その**子としてぶら下げたアート要素がクリップされる**（§3.5 参照） |

#### `<segments>` / `<s>`

`<s>` 1 個 = 1 アンカーポイント。

| 属性 | 型 | 既定 | 意味 |
|---|---|---|---|
| `p` | `"x,y"` | 必須 | アンカーポイントの位置 |
| `in` | `"x,y"` | `p` と同じ | 入力ハンドル位置（前のセグメントから来る側）。`p` と同値なら省略可 |
| `out` | `"x,y"` | `p` と同じ | 出力ハンドル位置（次のセグメントへ出る側）。`p` と同値なら省略可 |
| `corner` | bool | `true` | コーナー (`true`) かスムーズ (`false`) か |

ハンドル省略時は直線セグメント扱い。

### 3.2 `<compound>` — 複合パス

複合パスは「自身が style を持ち、子の `<path>` をサブパスとして列挙」する構造。

```xml
<compound>
  <fill .../>
  <stroke .../>
  <subs>
    <path closed="true">
      <segments>...</segments>
    </path>
    <path closed="true">
      <segments>...</segments>
    </path>
  </subs>
</compound>
```

| 属性 | 型 | 既定 | 意味 |
|---|---|---|---|
| `clipMask` | bool | `false` | クリップマスク化する。複合形状をマスクとして使うとき。詳細は §3.5 |

- `<subs>` 直下の `<path>` には `<fill>` / `<stroke>` を書かない（親 `<compound>` の塗り線が全サブパスに適用される）
- 偶奇規則 (even-odd) で穴抜き

### 3.3 `<group>` — グループ

```xml
<group>
  <!-- 子のアート要素を直接並べる -->
  <path .../>
  <text .../>
</group>
```

`<group>` は属性を持ちません。クリッピングは `<group>` を使わず、`<path clipMask="true">` / `<compound clipMask="true">` で表現します（§3.5）。

### 3.4 `<text>` — テキスト

3 種類のテキストフレームをサポート:

| `type` | 意味 | 必須属性 |
|---|---|---|
| (省略) | ポイントテキスト | `x`, `y`（アンカー位置） |
| `area` | エリアテキスト（パス内に流し込み） | 子要素 `<path>` で境界を定義 |
| `path` | パステキスト（パス上に配置） | 子要素 `<path>` で配置パス、属性 `startT` / `endT` |

```xml
<text type="path" align="center" orient="vertical" startT="0" endT="3">
  <path closed="false">
    <segments>...</segments>
  </path>
  <run font="HelveticaNeue-Bold" fontSize="24">
    <fill kind="rgb" v="0,0,0"/>
    <stroke kind="none"/>
    <content>Hello</content>
  </run>
  <run font="HelveticaNeue" fontSize="24">
    <fill kind="rgb" v="1,0,0"/>
    <stroke kind="none"/>
    <content> world</content>
  </run>
</text>
```

| 属性 | 型 | 既定 | 意味 |
|---|---|---|---|
| `type` | `area` / `path` / (省略) | ポイント | テキストフレームの種類 |
| `x`, `y` | 数値 | — | ポイントテキスト時のアンカー位置 |
| `startT`, `endT` | 数値 | `0` / `(セグメント数-1)` | パステキスト時のパス上の開始/終了 t 値 |
| `align` | `left` / `center` / `right` / `justify` | `left` | 段落揃え（テキスト全体に適用） |
| `orient` | `vertical` | 横書き | 縦書きにするとき `vertical`。横書きが既定 |

#### `<run>` — テキストラン

| 属性 | 型 | 既定 | 意味 |
|---|---|---|---|
| `font` | PostScript 名 | 既定フォント | 例: `"HelveticaNeue-Bold"` |
| `fontSize` | 数値 (pt) | フレーム値継承 | 例: `"24"` |
| `tracking` | 整数 | `0` | 字送り (1/1000 em、符号付き)。例: `"50"` |
| `hScale` | 正の実数 | `1` | 水平方向スケール。`1.0` = 100%。例: `"0.95"` |
| `vScale` | 正の実数 | `1` | 垂直方向スケール。`1.0` = 100% |
| `baselineShift` | 実数 (pt) | `0` | ベースラインシフト。正で上、負で下 |
| `kerningType` | `none` / `metrics` / `optical` / `metricsRoman` | `metrics` | オートカーニング方式。Writer は `metrics` (既定) なら省略 |
| `leading` | 正の実数 (pt) | (auto) | 行送り。属性が無ければ自動行送り (auto leading)。明示すると固定値となる |

子要素:
- `<fill>` / `<stroke>` — このランの塗り/線（フレームの style を上書き）
- `<content>` — このランのテキスト本体（UTF-8）

ラン分割は連続するスタイルが共通の範囲ごと。文字列を 1 つの `<run>` にまとめても構わない。

> Writer の挙動: ATE (Illustrator のテキストエンジン) は ASCII / CJK の境界などで内部的にラン分割するが、それらが artx 上の可視属性 (`font` / `fontSize` / `<fill>` / `<stroke>`) すべて一致するなら 1 ラン に統合して出力する。これによりプレースホルダ `{商品名}` (ASCII の `{` `}` と CJK の `商品名`) のような ASCII / CJK 跨ぎの記述が常に 1 ラン内に収まる。

#### プレースホルダ (CSV 流し込み)

`<run>` の `<content>` 内には以下の記法でデータ流し込み用のプレースホルダを書ける:

| 書き方 | 解釈 |
|---|---|
| `{キー}` | 描画時、Reader 呼び出し側が渡す `FieldMap` (= CSV ヘッダー → 値) で置換される。CSV にキーが存在しない場合は何も置換せず元の `{キー}` をそのまま残す |
| `{{` | 文字 `{` (エスケープ) |
| `}}` | 文字 `}` (エスケープ) |

- 1 つの `{...}` は 1 つの `<run>` 内で完結している必要がある (ラン境界をまたぐプレースホルダは不可)。
- `{` の閉じが見つからない、`{` 内に `{` が混ざるなど不正形は元の文字列のまま出力される。
- 未定義キーは Reader が `outUnknownFields` (Render API の out パラメータ) に重複なく積む。Reader 自身はログには記録しない (呼び出し側で UI 表示等に使う想定)。
- マルチラン (1 つの `<text>` に複数の `<run>`) を使えば 1 テキストアートに複数フィールドを混ぜられる。各ランは独立にスタイルを持ち、置換結果はランのスタイルを保つ。

#### 溢れ自動調整 (エリアテキストのみ)

ArtTracer パネルの右上ハンバーガーメニュー → 「設定…」で **溢れ自動調整** を ON にすると、Reader は描画後にエリアテキスト (`type="area"`) およびパステキスト (`type="path"`) の各フレームについて以下を実行します。パステキストはパス長より文字列が長い場合に末尾が表示されない状態を「溢れ」とみなす。ポイントテキストは溢れの概念がないので対象外。

| Phase | 操作する属性 | 粗ステップ | 精ステップ | 下限値 |
|---|---|---|---|---|
| 1 | `tracking` | -5 | +1 | `trackingMin` (既定 -50) |
| 2 | `hScale`   | -0.05 | +0.01 | `hScaleMin` (既定 0.9) |

各 Phase は次のように動作する:

1. 現在値からデフォルト方向の反対 (tracking なら 0 → 負方向、hScale なら 1.0 → 0 方向) に**粗ステップ**で値を減らし、溢れ (`ITextFrame::GetTextRange(true).GetSize()` > `(false).GetSize()`) が解消するまで繰り返す。
2. 解消したら、**精ステップ**でデフォルト方向に 1 段ずつ戻す。再び溢れたら 1 段戻して確定。
3. Phase 1 が下限値に到達してもまだ溢れていれば、tracking は下限値で固定して Phase 2 に進む。
4. Phase 2 も下限値に到達してまだ溢れていれば、最低値のまま放置し、ログに `auto-fit reached limits but text still overflows` 警告を残す。

調整値はフレーム全体に対して一律で適用される (`ReplaceOrAddLocalCharFeatures` で tracking / hScale のみセット)。`<run>` 単位で書き出した tracking / hScale 属性はこの操作で上書きされる点に注意。

### 3.5 クリップマスク

クリッピングは「マスク形状の要素を親、クリップされる要素群を子」という構造で表現します。Illustrator の「クリッピングマスクを作成」と同じ意味論です。

```xml
<path clipMask="true" closed="true">
  <fill kind="none"/>
  <stroke kind="none"/>
  <segments>...</segments>           <!-- マスク形状 -->
  <!-- ↓ ここからクリップされる子アート -->
  <path>...</path>
  <text>...</text>
</path>
```

- 親要素は **マスク形状自身**（`<path>` か `<compound>`）
- **`clipMask="true"` のときは `closed="true"` 必須** — クリップマスクは閉じた領域でなければ意味をなさないため。ロード時に検証エラーになる
- 親要素の `<fill>` / `<stroke>` / `<segments>` はマスク形状自身のプロパティ。クリップされた表示には現れない（Illustrator の挙動）
- 親要素の **アート要素子** (`<path>` / `<compound>` / `<group>` / `<text>` / `<image>`) がクリップされる対象
- 入れ子可能: `<path clipMask="true">` の中に別の `<path clipMask="true">` を置いてもよい

`<compound clipMask="true">` も同形（複合形状をマスクとして使うとき）:

```xml
<compound clipMask="true">
  <fill kind="none"/>
  <stroke kind="none"/>
  <subs>
    <path closed="true"><segments>...</segments></path>
    <path closed="true"><segments>...</segments></path>
  </subs>
  <!-- ↓ 複合形状にクリップされる子 -->
  <text>...</text>
</compound>
```

> 内部実装メモ: Reader はこの構造を読むと「クリップグループ + マスク子 + 兄弟」という Illustrator 内部形式に展開します。Writer は逆の変換を行います。利用者は内部形式を意識する必要はありません。

### 3.6 `<image>` — 配置画像

「ファイル > 配置」で配置した画像 (`kPlacedArt`) を artx に書き出す要素。base64 エンコードした PNG を `<data>` に常時埋め込み、加えて元ファイルパスを `href` 属性に任意で記録する。

```xml
<image x="50" y="60" w="200" h="150" format="png" href="/Users/me/Assets/photo.psd">
  <data>iVBORw0KGgo...(base64)</data>
</image>
```

href 無し (元ファイルパスが取れなかった、または手書きで作る場合):
```xml
<image x="50" y="60" w="200" h="150" format="png">
  <data>iVBORw0KGgoAAAANSUhEUgAAAGQ...(base64)</data>
</image>
```

| 属性 | 型 | 意味 |
|---|---|---|
| `x`, `y` | real | 配置 bbox の左上座標 (Y下向き、pt)。**必須** |
| `w`, `h` | real | 配置 bbox の幅・高さ (pt、正値)。**必須** |
| `format` | enum | `png` または `jpeg` (`jpg` も許容)。**必須** |
| `href` | 文字列 | 元ファイルの絶対パス (任意)。Reader が現環境でアクセス可能なら優先採用 |

| 子要素 | 意味 |
|---|---|
| `<data>` | base64 (RFC 4648) でエンコードされた画像バイト列。`href` が無いときは **必須**。空白・改行はデコード時に無視される |

**z-order**: 他のアート要素と同じ「先=前面」ルール (§1.5)。

#### Reader の動作 (href フォールバック)

1. `href` が指定されていて、現環境でそのファイルが読めるなら、**そのファイルを `ExecPlaceRequest` (kVanillaPlace, m_filemethod=1=link) で配置**する。元が PSD でもリンク状態のまま `kPlacedArt` として置かれ、Illustrator の「ファイル > 配置」と同じ結果になる (round-trip)。
2. 上記が成立しない (href 不在 / ファイル無し / 読めない) 場合は、`<data>` の PNG を一時ファイルに書き出して `ExecPlaceRequest` (m_filemethod=0=embed) で埋め込み配置する。

いずれの場合も、配置直後に artx の `x`/`y`/`w`/`h` (および任意の `transform`) に基づき `SetPlacedMatrix` でマトリクスを再適用し、`viewBounds` の差分から最終位置を補正する 2 段階方式で正確な位置を確定する。

つまり「テンプレートはどこでも開ける (`<data>` フォールバック)、ただし元アセットがある環境では本物が使われる」というハイブリッド方式。

#### Writer の動作

- **対象は `kPlacedArt` のみ**。`kRasterArt` (オブジェクト > ラスタライズ等で作るネイティブラスター) はテンプレート対象外でスキップ。
- `<data>` には **常に** 元アートを **72dpi (1pt = 1px) でラスタライズ**した PNG を埋め込む。`AIRasterizeSuite` が `kRasterizeARGB` で正規化するので、ソースが PSD/EPS/PDF/AI/SVG/PNG/JPEG どれでも RGBA8 PNG が得られる。
- `href` には `AIPlacedSuite::GetPlacedFilePathFromArt` で取得した元ファイルパスを書く。リンク状態でも埋め込み状態でも Illustrator がパスを記憶していれば取れる。取得失敗時は属性自体を省略。
- 配置形状は AI ドキュメント座標の bbox にぴったり収まる軸並行画像なので、常に `x`/`y`/`w`/`h` で出力する (回転・反転・シアーは表現しない)。

**書き出し方針**:
- 軽量化のため写真等で JPEG を使いたい場合は手で `<data>` を差し替えれば Reader 側で読める (Writer は常に PNG)。
- リンク切れに備えて `<data>` は常に保持される — テンプレートを別マシンで開いても描画は保証される。

---

### 3.7 `<preview>` — Finder / QuickLook 用プレビュー (任意)

`<artx>` 直下、`<bounds>` の隣に置かれる**メタデータ要素**。Writer は保存時に
選択全体を **長辺 1024px** でラスタライズした PNG をここに base64 で埋め込む。
ArtTracerHelper.app の QuickLook Extension がこれを取り出して Finder のサム
ネイル / Space キープレビューに使う。

```xml
<artx version="1">
  <bounds x="0" y="0" w="800" h="600"/>

  <preview format="png" w="1024" h="768">
    <data>iVBORw0KGgoAAAANSUhEUgAA...(base64 PNG)...AAAAElFTkSuQmCC</data>
  </preview>

  <!-- アート要素はこの下に続く -->
</artx>
```

属性:

| 属性 | 型 | 必須 | 説明 |
|---|---|---|---|
| `format` | "png" | ○ | 画像フォーマット (現状 PNG のみ) |
| `w` | 正整数 | ○ | ピクセル幅 |
| `h` | 正整数 | ○ | ピクセル高さ |

子要素:
- `<data>` — base64 エンコード済み画像バイト列 (改行は無視される)

**Reader (Illustrator プラグイン側)** は `<preview>` を完全に無視する。アート
要素として再現せず、Validate も警告を出さない (子要素フィルタで自動的に
スキップされる構造のため)。

**ファイルサイズ影響**: シンプルなパスのみのテンプレで +数十 KB、配置画像
を含む複雑なものでも +200〜500 KB 程度。

---

## 4. 塗り / 線 (`<fill>` / `<stroke>`)

`<fill>` と `<stroke>` は同じスキーマ（`<stroke>` は追加で `width` 属性）。

### 4.1 共通: `kind` 属性

| `kind` | 追加属性 | 例 |
|---|---|---|
| `none` | — | `<fill kind="none"/>` |
| `cmyk` | `v="C,M,Y,K"` (各 0..1) | `<fill kind="cmyk" v="0,0.5,1,0"/>` |
| `rgb` | `v="R,G,B"` (各 **0..1**, 0=黒/無色, 1=全開) | `<fill kind="rgb" v="1,0,0"/>` (純赤) |
| `gray` | `v="G"` (0..1, 0=白/1=黒 の AI 内部慣習) | `<fill kind="gray" v="0.5"/>` |
| `gradient` | 詳細は §4.2 | `<fill kind="gradient" type="linear">...</fill>` |

> ⚠️ **注意**: RGB / CMYK / Gray の数値はすべて **0..1 の正規化値**です。0..255 や 0..100 ではありません。RGB 255 表記からの変換は 255 で割るだけです（例: `135` → `0.529`）。

`<stroke>` は `kind != "none"` のとき `width` 属性を持つ:

```xml
<stroke kind="rgb" v="0,0,0" width="2"/>
```

### 4.2 グラデーション

```xml
<fill kind="gradient" type="linear" origin="X,Y" length="L" angle="DEG">
  <stop offset="0" midpoint="0.5">
    <color kind="rgb" v="1,0,0"/>
  </stop>
  <stop offset="1" midpoint="0.5">
    <color kind="rgb" v="0,0,1"/>
  </stop>
</fill>
```

| 属性 | 型 | 必須 | 意味 |
|---|---|---|---|
| `type` | `linear` / `radial` | 任意 (既定 `linear`) | グラデーションの種類 |
| `origin` | `"x,y"` | 必須 | 線形なら開始点、円形なら中心点 |
| `length` | 数値 (pt) | 必須 | 線形ならベクトル長、円形なら半径 |
| `angle` | 度 | 必須 | 線形のベクトル角（Y下向きに合わせて符号反転） |
| `hiliteAngle` | 度 | 円形のみ | ハイライト方向角度 |
| `hiliteLength` | 0..1 | 円形のみ | 半径に対するハイライトの距離（0=中心） |

#### `<stop>`

| 属性 | 型 | 既定 | 意味 |
|---|---|---|---|
| `offset` | 0..1 | — | ランプ上の位置（0=開始、1=終了） |
| `midpoint` | 0..1 | `0.5` | 次の stop との中点位置 |
| `opacity` | 0..1 | `1` | この stop の不透明度。`1` なら省略可 |

子要素 `<color>` は §4.1 の単色 (cmyk / rgb / gray / none) のみ。グラデーション内グラデーションは不可。

---

## 5. 完成例

### 5.1 最小例: 単一パスに単色塗り

```xml
<?xml version="1.0" encoding="UTF-8"?>
<artx version="1">
  <bounds x="0" y="0" w="100" h="100"/>
  <path closed="true">
    <fill kind="rgb" v="1,0,0"/>
    <stroke kind="none"/>
    <segments>
      <s p="0,0"/>
      <s p="100,0"/>
      <s p="100,100"/>
      <s p="0,100"/>
    </segments>
  </path>
</artx>
```

### 5.2 中間例: 複合パスに線形グラデーション

ドーナツ形（外円 + 内円）に左→右の青→透明グラデ:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<artx version="1">
  <bounds x="0" y="0" w="200" h="200"/>
  <compound>
    <fill kind="gradient" type="linear" origin="0,100" length="200" angle="0">
      <stop offset="0">
        <color kind="rgb" v="0,0.5,1"/>
      </stop>
      <stop offset="1" opacity="0">
        <color kind="rgb" v="0,0.5,1"/>
      </stop>
    </fill>
    <stroke kind="none"/>
    <subs>
      <path closed="true">
        <segments>
          <s p="0,100"   in="0,55.23"   out="0,144.77"   corner="false"/>
          <s p="100,200" in="44.77,200" out="155.23,200" corner="false"/>
          <s p="200,100" in="200,144.77" out="200,55.23" corner="false"/>
          <s p="100,0"   in="155.23,0"  out="44.77,0"    corner="false"/>
        </segments>
      </path>
      <path closed="true">
        <segments>
          <s p="50,100"  in="50,72.39"  out="50,127.61"  corner="false"/>
          <s p="100,150" in="72.39,150" out="127.61,150" corner="false"/>
          <s p="150,100" in="150,127.61" out="150,72.39" corner="false"/>
          <s p="100,50"  in="127.61,50" out="72.39,50"   corner="false"/>
        </segments>
      </path>
    </subs>
  </compound>
</artx>
```

### 5.3 複合例: クリップマスク + 円形グラデ + テキスト

外側矩形をマスクとして使い、その中に円形グラデの背景とテキストを配置:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<artx version="1">
  <bounds x="0" y="0" w="300" h="200"/>
  <!-- 矩形をマスクに、内側の要素をクリップ。clipMask="true" は closed="true" 必須 -->
  <path clipMask="true" closed="true">
    <fill kind="none"/>
    <stroke kind="none"/>
    <segments>
      <s p="0,0"/>
      <s p="300,0"/>
      <s p="300,200"/>
      <s p="0,200"/>
    </segments>

    <!-- z-order: 先に書いたものが前面。テキストを背景より先に書く -->
    <text x="20" y="120" align="left">
      <run font="HelveticaNeue-Bold" fontSize="48">
        <fill kind="rgb" v="0,0,0"/>
        <stroke kind="none"/>
        <content>Hello</content>
      </run>
    </text>

    <!-- 背景: 円形グラデーション (マスクの外側にはみ出してもクリップされる) -->
    <path closed="true">
      <fill kind="gradient" type="radial" origin="150,100" length="180" angle="0" hiliteAngle="0" hiliteLength="0">
        <stop offset="0">
          <color kind="rgb" v="1,1,0.78"/>
        </stop>
        <stop offset="1">
          <color kind="rgb" v="0.78,0.39,0.2"/>
        </stop>
      </fill>
      <stroke kind="none"/>
      <segments>
        <s p="-50,-50"/>
        <s p="350,-50"/>
        <s p="350,250"/>
        <s p="-50,250"/>
      </segments>
    </path>
  </path>
</artx>
```

---

## 6. 制限・既知の非対応

以下は現バージョンでは出力 / 復元されません:

- **パターン塗り (`kPattern`)** — 完全非対応
- **グラデーションの変形 (matrix)** — `gradientMatrix` はスキップ。origin / length / angle / hilite のみ
- **アピアランス効果**（ドロップシャドウ・ぼかし・ワープ等）
- **シンボル / メッシュ / ネイティブラスター** — `kSymbolArt`, `kMeshArt`, `kRasterArt` (オブジェクト > ラスタライズや「リンク解除」の画像)。`kRasterArt` は Writer でスキップされ、ユーザー向け警告として `<path>.log` に JSON 出力される。`kPlacedArt` (リンク / 埋め込み配置画像) は対応済み — §3.6 参照
- **不透明度マスク・描画モード** — `<group>` レベルの `opacity` / `blendMode` 等
- **段落属性のうち `align` 以外**（段組など）。キャラクタ単位の字送り (`tracking`) / 縦横スケール / ベースラインシフト / カーニング種別 / 行送り (`leading`) は §3.4 で対応済み
- **手動ペアカーニング** (特定の 2 文字間だけ補正した値) はラン単位で表現できないため未対応
- **スポットカラー / カスタムカラー** — `kCustomColor` は出力されない

ストロークの線端 (cap) / 接合 (join) / 破線 (dash) は現状未対応。

---

## 7. AI に向けた生成ガイド

このフォーマットを生成する際は:

1. **必ず `<bounds>` を最初に置く** — 値はテンプレート全体を覆う矩形（左上 0,0、単位 pt）
2. **`<items>` ラッパは存在しない** — アート要素 (`path` / `compound` / `group` / `text`) は `<artx>` や `<group>` の直接子として並べる
3. **すべての座標は左上原点 / Y下向き** — Illustrator の AI 座標 (Y上向き) ではない
4. **色は 0..1 の正規化値**（RGB / CMYK / Gray とも）。0..255 や 0..100 ではない
5. **角度 (`angle`, `hiliteAngle`) は Y下向きに合わせて符号反転** — 視覚的に「右上に向かう線形グラデ」を描きたいなら `angle="-30"` のように負の値を使う（標準数学の +30° に相当）
6. **`<segments>` の最初の `<s>` の `in` は使われない**（始点の入力ハンドルは無意味）
7. **複合パス内のサブパスには塗り/線を書かない** — 親 `<compound>` のものが全サブに適用される
8. **クリップマスクは `<path clipMask="true">` または `<compound clipMask="true">` の中にクリップ対象アートを直接ぶら下げる** — `<group>` で囲む必要はない。マスク要素自身の `<fill>` / `<stroke>` は表示されない。**`clipMask="true"` のとき `closed="true"` 必須**（compound の場合はすべてのサブパスが `closed="true"`）
9. **テキストは `<run>` を 1 つ以上必ず置く** — `<content>` が空でも `<run>` は省略しない
10. **数値は不要な末尾ゼロを書かない** — `5.0` ではなく `5`、ただし整数でも `0` は OK
11. **省略可能な属性は省略してよい** — Reader 側で既定値が補完される
12. **背景は最後に書く / 前景は最初に書く** — `.artx` の z-order は **記述順 = 前面 → 背面**（Illustrator のレイヤーパネルと同じ順、SVG / Canvas / PDF など painter's algorithm 系とは逆）。生成時は **テキスト・前景の装飾 → 中間レイヤー → 背景の塗り** の順に並べる。SVG の感覚で「背景を先に書く」と全要素が背景に隠れて見えなくなる。詳細 §1.5
13. **`<image>` は形式 1 (x/y/w/h) と形式 2 (transform) が排他** — 軸並行 (回転・反転なし) なら形式 1、回転・シアー・反転を含むなら形式 2。両方混ぜたり、片方の必須属性を欠いたりすると load エラー。詳細 §3.6
