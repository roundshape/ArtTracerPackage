# artx 自動配置 — 設計資料

`feature/auto_draw` ブランチで実装されている artx 配置機能の設計を整理する。

> 現役の配置方式は **クリック起点モード(Click Origin Mode)** = ユーザの
> クリック位置を grid 起点として、選択中の closed path 群に単一マスター
> grid で artx を配置する方式。
>
> 過去には **領域分解 + 各領域 grid** と **Free Packing (greedy bottom-left fill)** も
> 実装されていたが、現在は dead code として残置中。理由は本ドキュメント §9
> および `memory/arttracer_autoplace_progress.md`。

最終更新: 2026-05-27

---

## 1. 機能の概要

### 1.1 トリガー

ユーザがパネルの「描画」ボタンを押した時点で、Illustrator の選択状態を見て分岐:

| 選択状態 | モード | 挙動 |
|---|---|---|
| **closed path が 1 つ以上選択** | **クリック起点モード** | ツール起動 → ゴースト grid 追従描画 → クリック位置を grid 起点として配置 |
| **選択が空 or closed path 無し** | **従来のクリックツールモード** | クリック位置を 1 個の artx の基準点として配置 |

本ドキュメントは前者(クリック起点モード)を中心に説明する。

### 1.2 クリック起点モードでやること

1. 描画ボタン押下時に **選択 closed path 群** を AutoPlaceService に保存
2. artx の cellW/cellH/footprint を事前抽出してキャッシュ
3. ツール起動 → ユーザがカーソルを動かす度に:
   - カーソル位置を **頂点 / 辺へ階層スナップ** (閾値 4pt)
   - 全 path に対し snap 位置を grid 起点とした候補 cell を列挙
   - 採用 cell = 緑、不採用 cell = 赤 で **ゴースト矩形** を annotator drawer 経由で描画
   (ドキュメントには影響しない)
4. ユーザのクリックで確定:
   - 同じ snap 位置を grid 起点に **マスター grid** で全 path に配置
   - CSV があれば 1 セル 1 レコードで進行、レコード尽きで停止
   - 描画先レイヤ指定があれば配置の前後で 1 回だけ切替
5. ツール終了、state クリア
6. Esc キーで中止(配置せず終了)

選択 closed path 自体は変更しない(残る)。

### 1.3 マスター grid とは

「path 跨ぎでもセル位置が揃う」ための共通格子。

全 path に対し **1 つの (firstLeft, firstTop) 起点** + **共通の (stepX, stepY)** で grid を
切ることで、複数 path の間でセル位置が完全一致する。**ユーザのクリック位置と
アンカーから (firstLeft, firstTop) を逆算する** のがクリック起点モードの肝。

---

## 2. ファイル構成

```
Source/
├── ArtTracerPlugin.{h,cpp}              プラグイン本体 (lifecycle、SDK callback)
├── UI/
│   ├── ATPanelUI.{h,mm}                 パネル UI Obj-C ヘルパ
│   ├── ATSettingsDialog.{h,mm}          設定ダイアログ
│   └── PanelController.{h,mm}           ボタンハンドラ 10 個 (Phase 4)
├── Services/                            ビジネスロジック (Phase 3)
│   ├── SettingsStore.{h,mm}             NSUserDefaults R/W
│   ├── LayerService.{h,cpp}             レイヤ切替
│   ├── CsvService.{h,cpp}               CSV パース
│   ├── TemplateService.{h,cpp}          .artx ロード + Validate
│   ├── RenderService.{h,cpp}            renderTemplate (描画コア)
│   └── AutoPlaceService.{h,cpp}         クリック起点モード state + ロジック
└── Artrace/
    ├── ArtxTemplate.{h,cpp}             テンプレ Model
    ├── CsvData.{h,cpp}                  CSV Model + ページャ
    ├── AutoPlace.h                      公開 API (内部は 5 ファイルに分割)
    ├── AutoPlaceInternal.h              .cpp 群で共有する artx::internal 宣言
    ├── AutoPlaceCommon.cpp              FlattenAiPath / FootprintInsideRegion /
    │                                    FirstCellTopLeftFromCursor
    ├── AutoPlaceSnap.cpp                SnapToNearestVertex/Edge/Hierarchically +
    │                                    CollectClosedPathsFromSelection
    ├── AutoPlaceClickOrigin.cpp         現役: ComputeClickOriginCells /
    │                                    EnumerateClickOriginGridCells /
    │                                    RenderClickOriginGridOverlay /
    │                                    RenderClickMarker
    ├── AutoPlaceReference.cpp           JS リファレンス用 (§9 参照):
    │                                    ComputeGridCells / ComputePackedCells /
    │                                    ComputeRegionDecomposedCells /
    │                                    DecomposeIntoRegions /
    │                                    RenderRegionDecompositionOverlay
    ├── Footprint.{h,cpp}                artx footprint 算出
    └── Flatten.{h,cpp}                  ベジエ → 折れ線変換
```

### 公開 API (`AutoPlace.h`)

```cpp
namespace artx {

// 選択中の closed path を集める (グループ再帰、open path 等は無視)
int CollectClosedPathsFromSelection(std::vector<AIArtHandle>& outPaths);

// 階層スナップ (頂点 → 辺、閾値内ならその位置に吸着)
AIRealPoint SnapToNearestVertex(...);
AIRealPoint SnapToNearestEdge(...);
AIRealPoint SnapHierarchically(...);

// === クリック起点モード (現役) ===

// 配置位置の計算: cursor 位置を起点に複数 path に対し共通 grid を切る。
void ComputeClickOriginCells(const std::vector<AIArtHandle>& paths,
    const AIRealPoint& origin,
    double cellW, double cellH,
    const Clipper2Lib::PathsD& footprint,
    int anchor,          // 0..8: TopLeft, TopCenter, ..., BottomRight
    double padding,
    std::vector<AIRealPoint>& outBasePoints);

// ゴースト描画用: 候補 cell 全件 + 合否を返す (採用/不採用 両方)。
struct GhostGridCell { double left, top, right, bottom; bool ok; };
void EnumerateClickOriginGridCells(...);

// デバッグ用 overlay (実 kPathArt として描画、診断モード時のみ)。
void RenderClickOriginGridOverlay(...);

// 診断用: クリック位置を青い ✕ マーカーで描画。
void RenderClickMarker(const AIRealPoint& pos);

// === JS リファレンス用 (現在使われていない、§9 参照) ===
void ComputeGridCells(...);                    // 初版 grid
void ComputePackedCells(...);                  // Free Packing
void ComputeRegionDecomposedCells(...);        // 領域分解 + 各領域 grid
void RenderRegionDecompositionOverlay(...);    // ↑ のデバッグ可視化

} // namespace artx
```

---

## 3. クリック起点モードのアルゴリズム

### 3.1 全体フロー

```
[描画ボタン押下]
  ↓
PanelController::onDrawButtonClicked
  ↓
AutoPlaceService::beginClickOriginMode(paths, template)
  ├ target paths を保存
  ├ active = true
  └ artx params (cellW/cellH/footprint) をキャッシュ
  ↓
ツール起動 + annotator アクティブ化 + Esc 監視
  ↓
(ユーザ操作待ち)
  ↓
─── マウス移動 → ToolMouseDown まで ───
  TrackToolCursor → AutoPlaceService::onCursorMoved
    ├ raw cursor → SnapHierarchically (頂点 → 辺、4pt)
    ├ snap 後位置を lastCursorPos に保存
    └ invalidateArea (annotator 再描画要求)
  DrawAnnotation → AutoPlaceService::drawGhost
    ├ EnumerateClickOriginGridCells で全候補 cell 取得
    └ 各 cell を緑(採用)/赤(不採用)の矩形 outline で描画
  ↓
─── ユーザがクリック ───
  ToolMouseDown → AutoPlaceService::confirmAtCursor
    ├ snap (TrackToolCursor と同じ閾値で再計算、必ず一致)
    ├ ComputeClickOriginCells で配置 cell 列挙 (合格のみ)
    ├ LayerService::applyDrawLayer (描画先レイヤ切替)
    ├ for each cell: RenderService::renderTemplate
    │   (CSV があれば 1 セル 1 レコード、尽きたら停止)
    ├ RenderClickMarker (診断: 青い ✕ で snap 位置をマーキング)
    └ LayerService::restoreDrawLayer
  ↓
RestorePreviousTool → AutoPlaceService::cancel
  ├ ゴースト残像 invalidate
  ├ annotator OFF
  └ state クリア (paths, active, ghost params すべて)
```

### 3.2 階層スナップ (`SnapHierarchically`)

カスタムツールには Illustrator の Smart Guides / 「ポイントにスナップ」が効かない
ため、自前で実装している。

```cpp
AIRealPoint SnapHierarchically(const AIRealPoint& cursor,
    const std::vector<AIArtHandle>& paths, double threshold = 4.0)
{
    // 優先 1: anchor 頂点 (path の seg.p との距離 < threshold)
    snapped = SnapToNearestVertex(cursor, paths, threshold);
    if (snapped が cursor と異なる) return snapped;

    // 優先 2: ガイドライン (未実装 / TBD)
    // 必要になれば AIArtSet で kGuideArt を列挙して追加

    // 優先 3: 辺 (FlattenAiPath で線分列化 → ClosestPointOnSegment)
    snapped = SnapToNearestEdge(cursor, paths, threshold);
    if (snapped が cursor と異なる) return snapped;

    return cursor;  // どれにもスナップしない
}
```

閾値 4pt は経験則(8pt は緩すぎ、2pt は厳しすぎ)。

### 3.3 マスター grid 起点の逆算 (`FirstCellTopLeftFromCursor`)

ユーザの cursor 位置とアンカーから、「最初のセル(i=0, j=0)」の AI 左上座標を逆算する。

```cpp
void FirstCellTopLeftFromCursor(cursor, anchor, cellW, cellH,
                                 outLeft, outTop)
{
    aRow = anchor / 3   // 0=Top, 1=Center, 2=Bottom
    aCol = anchor % 3   // 0=Left, 1=Center, 2=Right

    // X 軸: anchor の意味は「cell の中のどこに cursor を置くか」の指示
    if (aCol == Left)   dx = 0          // cursor = cell.left
    if (aCol == Center) dx = -cellW/2   // cursor = cell の X 中央
    if (aCol == Right)  dx = -cellW     // cursor = cell.right

    // Y 軸 (AI Y-up なので Top = cell.v が大)
    if (aRow == Top)    dy = 0
    if (aRow == Center) dy = cellH/2
    if (aRow == Bottom) dy = cellH

    outLeft = cursor.h + dx
    outTop  = cursor.v + dy
}
```

これで決まる (firstLeft, firstTop) が **マスター grid の (0,0) セル左上**。
他のセルは `(firstLeft + i*stepX, firstTop - j*stepY)` で計算される
(`stepX = cellW + padding`, `stepY = cellH + padding`)。

### 3.4 候補 cell 列挙 (`EnumerateClickOriginGridCells`)

```cpp
EnumerateClickOriginGridCells(paths, origin, cellW, cellH, footprint,
                               anchor, padding, outCells)
{
    FirstCellTopLeftFromCursor(origin, anchor, cellW, cellH,
                                firstLeft, firstTop)
    stepX = cellW + padding
    stepY = cellH + padding

    for each path in paths:
        poly = FlattenAiPath(path)
        bbox = compute bbox of poly

        // この path の bbox と重なる i, j の範囲を求める
        iMin = floor((bbox.minX - firstLeft - cellW) / stepX) + 1
        iMax = floor((bbox.maxX - firstLeft) / stepX)
        jMin = floor((firstTop - bbox.maxY - cellH) / stepY) + 1
        jMax = floor((firstTop - bbox.minY) / stepY)

        // アンカーに応じて grid の展開方向を制約
        // Left → i は 0 以上、Right → i は 0 以下、Center → 制約なし (Y 軸も同様)
        ... (アンカー制約適用)

        for j in [jMin, jMax]:
            for i in [iMin, iMax]:
                cellLeft = firstLeft + i * stepX
                cellTop  = firstTop  - j * stepY
                ok = FootprintInsideRegion(poly, footprint, cellLeft, cellTop)
                outCells.push_back({cellLeft, cellTop, cellLeft+cellW,
                                    cellTop-cellH, ok})
}
```

`ComputeClickOriginCells` (配置用) は本関数の結果から `ok=true` のみ filter する
薄いラッパ。`RenderClickOriginGridOverlay` (kPathArt として overlay 描画) も同様に
本関数の結果を kPathArt 化する薄いラッパ。**走査ロジックは Enumerate が正本**。

### 3.5 ゴースト grid プレビュー (`AutoPlaceService::drawGhost`)

DrawAnnotation コールバック内で `EnumerateClickOriginGridCells` を呼び、各 cell の
4 隅を `ArtworkPointToViewPoint` で view 座標化、`sAIAnnotatorDrawer->DrawLine` x 4 で
矩形 outline を描画する。

**重要**: AIAnnotatorDrawer は **view (screen) 座標** で描画するので、文書座標
からの変換が必要。実 kPathArt は作らないので Undo に積まれず、保存にも反映されない。

実装の注意:
- `lastCursorPos` には **snap 後位置** が入っている (raw cursor ではない)
- → ゴーストの位置 = 実クリック時の配置位置で完全一致する

### 3.6 配置ループ (`AutoPlaceService::confirmAtCursor`)

```cpp
ConfirmResult confirmAtCursor(rawCursor, template, csv, settings)
{
    // snap (TrackToolCursor と同じロジック)
    origin = SnapHierarchically(rawCursor, targetPaths, 4.0)

    // artx params (キャッシュ済みなら使う、無ければ再抽出)
    if (ghostParamsReady)
        cellW, cellH, footprint = cached
    else
        extractArtxGridParams(template, &cellW, &cellH, &footprint, &err)
        (失敗時はステータスメッセージ返して早期 return)

    // 候補 cell 列挙
    ComputeClickOriginCells(targetPaths, origin, cellW, cellH, footprint,
                             anchor, padding, basePoints)
    if (basePoints.empty()):
        return "クリック位置から配置できるセルがありません"

    // レイヤ切替 (1 回だけ)
    savedLayer = LayerService::applyDrawLayer(settings)

    for each bp in basePoints:
        if (csvLoaded && csvExhausted) break
        RenderService::renderTemplate(template, csv, settings, bp, csvLoaded)
        if (csvLoaded):
            if (!csv.advance()) csvExhausted = true

    // 診断: クリック位置に青い ✕ マーカー (snap 位置目視確認用)
    RenderClickMarker(origin)

    LayerService::restoreDrawLayer(savedLayer)

    return {ok=true, statusMessage="クリック起点配置: N 件 (snap@..., 候補 N)", csvAdvanced}
}
```

### 3.7 配置可否判定 (`FootprintInsideRegion`)

各 cell 位置 `(cellLeft, cellTop)` に artx footprint を置いたとき、その footprint が
path の内側に **完全包含されるか** を判定する。

```cpp
bool FootprintInsideRegion(region, footprint, baseH, baseV)
{
    if (region empty) return false
    for each subPath in footprint:
        for each vertex (v.x, v.y) in subPath:
            // artx ローカル Y-down → AI Y-up に変換
            aiH = baseH + v.x
            aiV = baseV - v.y
            r = PointInPolygon((aiH, aiV), region[0])
            if (r == IsOutside) return false
    return true
}
```

footprint は事前に `artx::ComputeFootprint` で算出してキャッシュ済み。
artx ローカル座標 (Y-down) で持ち、各 cell 位置で AI 座標に逐次変換する。

---

## 4. 座標系の整理

| 座標系 | 原点 | Y 方向 | 使用箇所 |
|---|---|---|---|
| **AI document** | artboard 左下 | **Y-up**(上が大、下が小) | path のセグメント、bbox、配置基準点 |
| **artx ローカル** | artx 左上 | **Y-down**(上が小、下が大) | `<bounds>`、`<segments>`、footprint |
| **view (screen)** | view 左上 | Y-down (ピクセル) | annotator drawer 描画 |

### 変換式

```
artx ローカル (lx, ly) → AI Y-up:
    AI.h = basePoint.h + lx
    AI.v = basePoint.v - ly    // Y 方向反転

AI Y-up → view (screen):
    sAIDocumentView->ArtworkPointToViewPoint(view, &aiPoint, &viewPoint)
    // view 座標は zoom / rotate 後の値、符号は不定なので min/max で正規化
```

### 各処理での座標系

| 処理 | 入力 | 出力 |
|---|---|---|
| `FlattenAiPath` | AI Y-up (AIPathSegment) | AI Y-up (Point2) |
| `ComputeFootprint` | artx XML 内の Y-down | artx Y-down (Clipper2Lib::PathsD) |
| `EnumerateClickOriginGridCells` | AI Y-up (paths, origin) + artx Y-down (footprint) | AI Y-up (cells) |
| `FootprintInsideRegion` | region: AI Y-up、footprint: artx Y-down → 内部で AI に変換 | bool |
| `RenderService::renderTemplate` | AI Y-up (basePoint) | (描画副作用) |
| `drawGhost` | AI Y-up (cell 4 隅) → view 座標化 | (annotator drawer 描画副作用) |

---

## 5. UI と設定

### 5.1 設定構造体 (`ArtTracerSettings`)

```cpp
struct ArtTracerSettings {
    // 溢れ自動調整 (テキスト用)
    bool   autoFitEnabled        = false;
    int    trackingMin           = -50;
    double hScaleMin             = 0.9;

    // デバッグ可視化
    bool   showFootprint         = false;  // footprint を赤線で描画
    bool   showDecomposedRegions = false;  // 領域分解 overlay (現在は dead code)
    bool   showClickOriginGrid   = false;  // クリック起点 grid 候補を緑/赤で描画

    // 領域分解方向 (現在は dead code、UI には残っている)
    bool   regionDecomposeYPriority = true;

    // 描画先レイヤ指定 (現役、両経路に効く)
    bool        drawLayerEnabled = false;
    std::string drawLayerName    = "ArtTracer";

    // grid 内配置パラメータ
    GridAnchor gridAnchor  = GridAnchor::TopLeft;
    double     gridMargin  = 0.0;   // (現状 click-origin モードでは未使用)
    double     gridPadding = 0.0;   // (click-origin モードで効く)
};

enum class GridAnchor {
    TopLeft = 0, TopCenter, TopRight,
    CenterLeft,  Center,    CenterRight,
    BottomLeft,  BottomCenter, BottomRight,
};
```

永続化は `artx::SettingsStore::load()` / `save()` (NSUserDefaults 直叩き、
`Source/Services/SettingsStore.mm`)。キーは `ArtTracer.<FieldName>`。

### 5.2 設定ダイアログのレイアウト (`ATSettingsDialog`)

```
┌────────────────────────────────────────────┐
│           ArtTracer 設定                    │
│                                             │
│ ☐ 溢れ自動調整を有効にする                  │
│     トラッキング最低値: [   -50] ⬆⬇        │
│     水平比率最低値:     [  0.90] ⬆⬇        │
│                                             │
│ ☐ footprint をデバッグ描画する             │
│ ☐ 領域分解をデバッグ描画する               │
│ ☐ クリック起点 grid をデバッグ描画する     │
│                                             │
│ 領域分解方向:                              │
│   ◉ Y 優先 (縦並び、列揃え)                │
│   ○ X 優先 (横並び、行揃え)                │
│                                             │
│ ☐ 描画先レイヤを指定する                   │
│     レイヤ名: [ArtTracer________________]  │
│                                             │
│ グリッド内配置:                            │
│   アンカー: [Top-Left (左上)         ▼]    │
│   Margin:   [     0] pt  (現状 dead)       │
│   Padding:  [     0] pt                    │
│                                             │
│              [キャンセル]  [OK]             │
└────────────────────────────────────────────┘
```

「領域分解方向」「Margin」「領域分解をデバッグ描画する」は現状コード上 dead code
の旧領域分解モード用。**JS リファレンス方針** ([[file-splitting-ai-optimized]]) に
従い UI は残置している。

---

## 6. レイヤ指定機能

`artx::LayerService::applyDrawLayer(settings)` / `restoreDrawLayer(prev)`:

設定 `drawLayerEnabled` が ON のとき:

1. 現在のアクティブレイヤを保存
2. 指定レイヤ名を `GetLayerByTitle` で検索
3. 見つからない → `InsertLayer(NULL, kPlaceAboveAll, &target)` で**最前面に新規作成**して命名
4. `SetCurrentLayer(target)` でそのレイヤをアクティブにする
5. 戻り値 = 元のアクティブレイヤ(`restoreDrawLayer` で復元する)

3 つの描画経路に組み込み済み:

| 経路 | 切替単位 |
|---|---|
| `AutoPlaceService::confirmAtCursor` | クリック確定時に 1 回切替・復元 (ループ外側) |
| `ToolMouseDown` (従来クリックツール) | クリック 1 回毎に切替・復元 |
| `PlaceArtxAt` (JS bridge) | 1 回切替・復元 |

`AutoPlaceService::autoPlaceInClosedPaths` (dead code) でも同様に外側 1 回切替の
最適化を維持。

---

## 7. デバッグ可視化

### 7.1 footprint オーバーレイ

設定 `showFootprint` が ON のとき、各 `RenderService::renderTemplate` 後に
`RenderFootprintOverlay(doc, basePoint)` で **赤 0.5pt ストローク** で
footprint 輪郭を最前面に描画する。

### 7.2 クリック起点 grid 候補オーバーレイ

設定 `showClickOriginGrid` が ON のとき、クリック確定時に `confirmAtCursor` 内で
`RenderClickOriginGridOverlay(...)` を呼ぶ。

各候補 cell を矩形 outline で描画 (実 kPathArt として):
- **緑** (0, 0.7, 0): footprint テスト合格 = 採用
- **赤** (1, 0.2, 0.2): footprint テスト不合格 = 不採用

(これは「クリック後に永続的に残る診断 overlay」。マウス移動中のゴースト描画
(§3.5) と用途が違う — ゴーストは annotator で一時表示、こちらは kPathArt で永続)。

### 7.3 クリックマーカー

`confirmAtCursor` 内で常に `RenderClickMarker(origin)` を呼び、snap 後のクリック
位置を **青 1pt × 10pt の ✕ マーカー** で描画。アンカー指定が意図通りに効いて
いるか目視確認用。

### 7.4 領域分解オーバーレイ (dead code)

設定 `showDecomposedRegions` が ON のとき、`AutoPlaceService::autoPlaceInClosedPaths`
(dead code) で `RenderRegionDecompositionOverlay` を呼ぶ。サブ領域ごとに 6 色
ローテーションで色違いストロークで描画。

現状コードからは呼ばれない (autoPlaceInClosedPaths が dead) が、JS リファレンス
として実装は保持。

---

## 8. CSV 連携

CSV が `CsvService::loadFromFile` で読み込まれていれば、配置は **「1 セル 1 レコード」**
で進む:

1. `confirmAtCursor` 開始時の `csvLoaded` 判定: `csv.currentRowValid()`
2. 各 cell の `RenderService::renderTemplate(..., useSubstitution=csvLoaded)` で
   現在レコードの fieldMap を使ってテンプレ内の `{key}` プレースホルダを置換
3. 描画後、`csv.advance()` で次レコードへ進む(末尾なら false 返却 → `csvExhausted = true`)
4. `csvExhausted` 後は以降の cell をスキップして終了
5. 最後に `RefreshCsvUi()` でパネル上の表示を更新

CSV なし時:
- `useSubstitution = false` (プレースホルダ未置換のまま描画)
- 配置可能セルが置ける限り、同じ artx を全部に置く

---

## 9. JS リファレンス用に残置されたアルゴリズム

`Source/Artrace/AutoPlaceReference.cpp` に隔離されている、現在 dead code 扱いの
配置アルゴリズム群。**削除しない方針**(`memory/arttracer_autoplace_progress.md` /
`autoplace_future_work.md` 参照)。

理由:
- ユーザが **JavaScript レベルで両アルゴリズムを実装する予定**
- C++ 実装は仕様書 / リファレンスとして役立つ
- 将来のモード切替で C++ 版を復活させる可能性もあり (設定で
  「クリック起点 / 即時 packing / 即時領域分割」を選べるようにする等)

### 9.1 `ComputeGridCells` — 初版 grid

**概要**: closed path の AI bbox を左上から `cellW × cellH` の格子で均等分割。
各セル位置で footprint が path 内に完全包含されるかをチェックして採用判定。

**制限**: 凹型 path で「凹みを挟んだ反対側アーム」にセルが入らない場合がある。
位置 = `i * cellW` が凹みにかかると、それ以降の列は全部 NG になる。

### 9.2 `ComputePackedCells` — Free Packing (greedy bottom-left fill)

**概要**: bbox 全体を 1pt 刻みで sweep し、footprint が path 内 & 既配置 footprint と
非重複となる位置に順次置いていく。grid 構造を持たない。

**長所**: 凹型 path の凹みを挟んだ向こう側アームにもセルを置ける。

**制限**: 行が揃わず「bara-bara」に見える(sweep 順序依存)。

### 9.3 `ComputeRegionDecomposedCells` + `DecomposeIntoRegions` — 領域分解 + 各領域 grid

**概要**: closed path を Y or X 方向の slab で分解し、各サブ領域内で独立に grid を
切る方式。Hertel-Mehlhorn 風アルゴリズム。

#### Step 1: 凹頂点の検出

多角形の符号付き面積で全体の winding(CCW / CW)を取得:

```cpp
const double signedArea = Clipper2Lib::Area(polyPD);
// > 0: CCW (AI Y-up math standard)
// < 0: CW
```

各頂点 `P_i` で「入る辺ベクトル」と「出る辺ベクトル」の外積を取る:

```cpp
const double cross = (P_i.x - P_{i-1}.x) * (P_{i+1}.y - P_i.y)
                   - (P_i.y - P_{i-1}.y) * (P_{i+1}.x - P_i.x);
```

判定: **`cross * signedArea < 0` ならその頂点は凹**(reflex vertex)。

#### Step 2: cut 軸座標の収集と Width 制約

- 凹頂点の座標(yPriority なら Y、!yPriority なら X)を sort
- cut 候補列: `[bbox.lo, 凹頂点座標..., bbox.hi]`
- 隣接 cut の間隔が `minCutSpacing` 未満になるような凹頂点はスキップ
- 結果: cell が入らないほど狭いスラブが生成されない

`minCutSpacing` の値:
- yPriority=true(Y 軸で切る = 横帯)→ `cellH`
- yPriority=false(X 軸で切る = 縦帯)→ `cellW`

#### Step 3: スラブと path の交差

各隣接 cut ペアでスラブ矩形を作り、Clipper2 `Intersect(path, slab)` でサブ領域を抽出。
`inter` は連結成分が複数になる場合がある(例: 凹エリアの上スラブ → 左アーム + 右アーム)。

#### Step 4: 各サブ領域での grid 配置

各 region について bbox 算出 → アンカー × margin で usable サイズ算出 → セル数 nx, ny
算出 → grid 起点をアンカー位置に合わせて配置 → 各セルで footprint テスト。

### 9.4 なぜクリック起点モードに置き換わったか

旧 3 アルゴリズムには共通の問題があった: **「path 跨ぎでセル位置が揃わない」**
(各 path / 各サブ領域で grid 原点が独立に決まる)。

クリック起点 + マスター grid 方式は、**ユーザのクリック位置を全 path 共通の
grid 起点とする** ことで、この問題を根本解決する(複数 path 間でセル位置が完全
一致)。

また「ユーザがどこを起点にしたいか直接指示できる」UX 上のメリットもある。

### 9.5 アルゴリズムの理論的背景

**多角形分解 (Polygon Partitioning)**: 凹頂点で切る発想は
**Hertel-Mehlhorn algorithm (1983)** に由来。凸ポリゴンへの分解で、切る数が
最適解の高々 4 倍と保証される(O(n log n) 時間)。`ComputeRegionDecomposedCells`
は厳密な凸分解ではなく **「軸並行スラブ + 凹頂点座標」** の亜種で、grid 配置との
相性を優先している。

**ネスティング (Nesting)**: 「任意領域に複数図形を最大個数配置する」問題は
**2D 不規則ネスティング**(2D irregular nesting / irregular bin packing)と呼ばれ、
板金加工 / アパレル CAD / 製靴 / 印刷業界で広く扱われる NP-hard 問題。

ArtTracer は **single-piece-type nesting**(1 種類のピース)に特化し、配置数より
「整然さ」を優先している。

---

## 10. 既知の挙動・制約 (クリック起点モード)

### 何ができるか

- 任意の closed path(凸でも凹でも、矩形でも slanted でも)に対し配置可能
- **複数 path 間でセル位置が揃う**(マスター grid)
- 頂点 / 辺へのスナップ(閾値 4pt)で正確な位置決め
- リアルタイム ゴースト プレビュー(マウス移動毎に候補 cell が見える)
- footprint による「絶対にはみ出さない」配置保証
- アンカー 9 種(クリック位置をセルのどこに合わせるか)
- Padding(セル間隔)
- CSV 駆動で N 個の artx を 1 操作で配置
- 描画先レイヤ統一(整理しやすい)
- Esc キーで中止

### 何ができないか / 制約

- **Margin (grid 外周余白) は未対応**(クリック起点なので意味が薄い)
- **artx の回転なし**(常に upright)
- **多 artx 混在配置なし**(1 種類のテンプレ artx のみ)
- **斜め (rotated) grid なし**(常に AI 座標の X / Y 軸並行)
- **対称性は保証されない**(ユーザのクリック位置依存)
- **path に compound や穴**(複数のサブ path)が含まれるケースは未テスト

詳細な改善ロードマップは [`autoplace_future_work.md`](./autoplace_future_work.md) を参照。

---

## 11. 関連ファイルへのリンク

- 改善計画: [`autoplace_future_work.md`](./autoplace_future_work.md)
- artx フォーマット仕様: [`artx-format.md`](./artx-format.md)
- 設計哲学: [`めざすデザインについて.md`](./めざすデザインについて.md)
- スクリプト言語選択経緯: [`script_language_choice.md`](./script_language_choice.md)
- QuickJS リファレンス: [`ArtTracer_quickjs_reference.md`](./ArtTracer_quickjs_reference.md)

---

最終更新: 2026-05-27
