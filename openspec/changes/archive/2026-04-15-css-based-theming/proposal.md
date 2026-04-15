## Why

ノートの外観設定が Swift/YAML による独自パイプラインで管理されており、ユーザーがカスタマイズする手段がない。WebView ベースのエディタに移行したことで、CSS によるテーマ定義が自然な選択肢となった。CSS に移行することでユーザーがノートの外観を自由にカスタマイズできるようになる。

## What Changes

- **BREAKING** `config.yaml` の `colorScheme`、`font`、`fontSize` フィールドを削除
- `config.yaml` にグローバル CSS ファイルパス（`appearance.cssFile`）を追加
- `config.yaml` のノート設定に `theme` フィールドを追加（per-note テーマ名を指定）
- アプリ内蔵のデフォルト CSS（`--chirami-*` 変数定義 + 組み込みテーマ）を追加
- ユーザー CSS をビルトイン CSS の後にロードし、上書き可能にする
- `data-chirami-theme` 属性を `<html>` 要素に注入し、CSS セレクタでテーマを切り替え可能にする
- YAML ベースのカラースキームパイプライン（`color_schemes.yaml`、`ColorSchemeRegistry`、`ColorSchemeCSSConverter`）を削除
- Swift → JS bridge 経由のテーマ送信を廃止
- dark/light 対応は CSS `@media (prefers-color-scheme: dark)` によりユーザーが管理

## Capabilities

### New Capabilities

- `css-theming`: CSS ファイルによるノート外観のカスタマイズ。グローバル CSS ファイル指定と per-note テーマ名指定をサポートする

### Modified Capabilities

## Impact

- `Chirami/Services/ColorSchemeCSSConverter.swift` — 削除
- `Chirami/Models/ColorSchemeRegistry.swift` — 削除
- `Chirami/Resources/color_schemes.yaml` — 削除
- `Chirami/Config/ConfigModels.swift` — `colorScheme`/`font`/`fontSize` 削除、`cssFile`/`theme` 追加
- `Chirami/Views/NoteWebView.swift` — テーマ/フォント bridge 削除、CSS ロード + `data-chirami-theme` 注入に変更
- `editor-web/src/theme.ts` — 削除
- `editor-web/src/main.ts` — `setTheme`/`setFont` API 削除
- `Chirami/Resources/` — デフォルト CSS ファイルを追加
