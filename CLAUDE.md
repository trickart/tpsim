# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

ESC/POS プロトコルで通信するサーマルプリンタのシミュレータ。TCP ポート 9100 で接続を待ち受け、受信した ESC/POS コマンドをターミナル上にレシート風にレンダリングする。Swift 6.2、Swift NIO 使用。

## ビルド・実行コマンド

```bash
swift build                    # デバッグビルド
swift build -c release         # リリースビルド
swift run tpsim                # デフォルトポート 9100 で起動
swift run tpsim 8080           # ポート指定で起動
```

テストは tpsim 側にはない。ESC/POS の解析・レンダリングのテストは依存先の ThermalPrinterCommand にある:

```bash
cd /Users/trick/ThermalPrinterCommand && swift test                      # 全テスト
cd /Users/trick/ThermalPrinterCommand && swift test --filter <test_name> # 特定テスト
```

## アーキテクチャ

```
tpsim (実行可能ターゲット)
├── Communication (内部ライブラリ)
│   └── swift-nio (NIOCore, NIOPosix)
└── ThermalPrinterCommand (外部パッケージ)
    ├── ThermalPrinterCommand ライブラリ
    │   ├── ESCPOSDecoder: Data → [ESCPOSCommand]
    │   ├── ESCPOSEncoder: コマンド → Data
    │   └── ESCPOSCommand: コマンド型定義 (enum)
    └── PrinterSimulator ライブラリ
        ├── ESCPOSPrinterSimulator: プリンター状態管理・レスポンス生成
        ├── TextReceiptRenderer: テキスト/ANSIスタイル描画
        ├── SixelEncoder: Sixelグラフィックス生成
        └── QRCodeRasterizer: QRコードラスタライズ
```

### モジュール責務

- **Communication** (`Sources/Communication/`): Swift NIO ベースの TCP サーバー。IPv4/IPv6 dual-stack。接続を `AsyncThrowingStream<TCPConnection>` で提供。
- **tpsim** (`Sources/tpsim/`): メインエントリポイント。Sixel サポート検出（DA1シーケンス）、iTerm2 セルサイズ取得（OSC 1337）、接続ごとに Decoder → Simulator → Renderer のパイプラインを構成。

### データフロー

TCP受信データ → `ESCPOSDecoder.decode()` → `[ESCPOSCommand]` → `ESCPOSPrinterSimulator.process()` → stdout描画 + レスポンスData送信

## ThermalPrinterCommand の開発

ESC/POS のデコード・レンダリングの修正は外部パッケージ ThermalPrinterCommand 側で行う。ローカル編集には `swift package edit` を使用する:

```bash
# 編集モードに入る（ローカルの ../ThermalPrinterCommand を参照）
swift package edit ThermalPrinterCommand --path ../ThermalPrinterCommand

# 編集完了後、元のバージョン固定に戻す
swift package unedit ThermalPrinterCommand
```

テストは Swift Testing フレームワーク（`@Suite`, `@Test`）を使用。
