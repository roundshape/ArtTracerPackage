# ArtTracer インストールガイド

## 必要環境

- macOS 12 以降
- Adobe Illustrator 2022 以降

## 手順

### 1. ArtTracerHelper.app を Applications にコピー

`ArtTracerHelper.app` を、同じウィンドウ内の **Applications** エイリアスにドラッグしてください。

これで Launch Services に `.artx` の UTI とアイコン・Quick Look 拡張が登録され、Finder 上で `.artx` ファイルが専用アイコンとプレビュー画像で表示されるようになります。

#### 1-a. Quick Look 拡張を有効化

サムネイル / Quick Look プレビューを担うのは `ArtTracerHelper.app` に同梱されている **App Extension** で、macOS の仕様で初回はユーザーが明示的に有効化する必要があります。

**macOS 15 (Sequoia) 以降**：

1. **システム設定** を開く
2. **一般** → **ログイン項目と機能拡張**
3. 下にスクロールして **「機能拡張」セクション** → **Quick Look**（または **クイックルック**）をクリック
4. 一覧の **ArtTracerThumbnail** をオン

**macOS 14 (Sonoma) 以前**：

1. **システム設定**（旧名: システム環境設定）を開く
2. **プライバシーとセキュリティ** → **機能拡張**（Extensions）
3. 一覧の **Quick Look** に **ArtTracerThumbnail** が出るのでオン

> **Tip:** 有効化してもサムネイル / プレビューが反映されない場合、Mac を一度再起動してください。pluginkit / launchd のキャッシュがクリアされて確実に有効になります。

### 2. ArtTracer.aip を Illustrator のプラグインフォルダにコピー

`ArtTracer.aip` を、お使いの Illustrator のプラグインフォルダにコピーしてください。

通常のインストール先：

```
/Applications/Adobe Illustrator <バージョン>/Plug-ins.localized/
```

例 (Illustrator 2026)：

```
/Applications/Adobe Illustrator 2026/Plug-ins.localized/ArtTracer.aip
```

### 3. Illustrator を再起動

Illustrator を起動し直すと **ウィンドウ → ArtTracer** からパネルを開けます。

## アンインストール

- `/Applications/ArtTracerHelper.app` を削除
- `/Applications/Adobe Illustrator <バージョン>/Plug-ins.localized/ArtTracer.aip` を削除
