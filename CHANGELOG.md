# Changelog

ArtTracer Package (dmg) のリリース履歴です。同梱する `ArtTracer.aip` / `ArtTracerHelper.app` のバージョンは独立しており、各リリース項目に併記します。

## [0.0.6] - 2026-06-07

埋め込み画像対応・テキスト溢れ調整の強化と、グリッド配置のライブ微調整を追加したリリース。

- 描画モード中に**矢印キーでグリッドの offset / gap をライブ調整**できるようにした (ゴースト表示中にマウスを動かさず微調整。⌥ で 10pt 刻み、Shift で gap 調整)
- グリッド配置の余白命名を整理し、`offset` / `gap` (x/y 軸独立) に統一 (旧 inset / margin を廃止)
- artx に**埋め込みラスター画像 (kRasterArt) の保存・復元**を追加し、artx フォーマットを 1.0.2 に更新 (flat 形式は元ファイルバイト、PSD/PDF/TIFF 等は生ピクセルで保持)
- テキスト溢れ自動調整に行送り (行間) フェーズと項目別 ON/OFF を追加

- ArtTracer.aip 0.0.0 (artx format 1.0.2)
- ArtTracerHelper.app 0.0.0

## [0.0.5] - 2026-05-30

配置の自由度を上げる機能追加リリース。

- **⌘ + 描画でスケール配置**を追加 (アスペクト比を保ったまま倍率指定で並べる)
- artx 保存確認を 3 ボタン化し、横並びのカスタムダイアログを新設

- ArtTracer.aip 0.0.0
- ArtTracerHelper.app 0.0.0

## [0.0.4] - 2026-05-27

自動配置まわりを大きく強化し、内部を大規模リファクタリングしたリリース。

- 自動配置を**クリック起点モード**に刷新し、カーソル追従の**ゴースト grid ライブプレビュー** (配置結果と完全一致) を追加
- **グループ化機能 (groupOnRender)** と CSV ID の重複検出を追加
- 描画先レイヤ指定・グリッド内アンカー配置・領域分解アルゴリズムを追加
- ArtTracerPlugin (約 2400 行の god class) を Service 群へ分割するなど内部構造を整理 (挙動変更なし)

- ArtTracer.aip 0.0.0
- ArtTracerHelper.app 0.0.0

## [0.0.3] - 2026-05-20

配布パッケージのドキュメントと artx 機能を拡充したリリース。

- 配布 dmg に同梱するドキュメント類を整備 (QuickJS スクリプティングのリファレンスを追加)
- artx に CSV による画像差し替え機能と `<image>` の name 属性を追加し、artx フォーマットを 1.0.1 に更新

- ArtTracer.aip 0.0.0 (artx format 1.0.1)
- ArtTracerHelper.app 0.0.0

## [0.0.2] - 2026-05-19

v0.0.1 で発生していた起動不可問題を修正したマイナーリリース。

- ArtTracerHelper の macOS Deployment Target を下げ、旧 macOS でも起動可能に修正 (v0.0.1 では macOS 26.4 以上を要求していたため起動できなかった)
- ビルド出力先を `build.noindex/` に変更し、Spotlight / LaunchServices の競合を回避
- リリース公開手順を `ai_docs/release-publish.md` としてドキュメント化

- ArtTracer.aip 0.0.0
- ArtTracerHelper.app 0.0.0

## [0.0.1] - 2026-05-19

配布パッケージ初版 (v0.0.0) の改善版。

- 公証 (Notarization) に対応。GitHub からダウンロードした dmg で「開発元が未確認」ブロックが出なくなった
- ビルド・署名・公証・staple までを `scripts/release.sh` に統合し、ワンコマンドで配布可能な dmg を生成できるようにした
- パイプラインの技術資料を `ai_docs/release-pipeline.md` として追加
- README に対応プラットフォーム (macOS 限定) を明記

- ArtTracer.aip 0.0.0
- ArtTracerHelper.app 0.0.0

## [0.0.0] - 2026-05-10

初回ベータリリース。

- ArtTracer.aip 0.0.0
- ArtTracerHelper.app 0.0.0
