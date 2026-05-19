# Changelog

ArtTracer Package (dmg) のリリース履歴です。同梱する `ArtTracer.aip` / `ArtTracerHelper.app` のバージョンは独立しており、各リリース項目に併記します。

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
