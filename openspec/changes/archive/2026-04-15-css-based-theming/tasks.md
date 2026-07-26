## 1. 削除: YAML カラースキームパイプライン

- [x] 1.1 `Chirami/Resources/color_schemes.yaml` を削除
- [x] 1.2 `Chirami/Models/ColorSchemeRegistry.swift` を削除
- [x] 1.3 `Chirami/Services/ColorSchemeCSSConverter.swift` を削除
- [x] 1.4 `editor-web/src/theme.ts` を削除

## 2. Config モデル更新

- [x] 2.1 `ConfigModels.swift` から `colorScheme`/`font`/`fontSize` フィールドを削除
- [x] 2.2 `ConfigModels.swift` に `appearance.cssFile`（String?）フィールドを追加
- [x] 2.3 `ConfigModels.swift` の `NoteConfig` に `theme`（String?）フィールドを追加
- [x] 2.4 旧フィールドが残っていても warning ログを出してクラッシュしないことを確認

## 3. デフォルト CSS 作成

- [x] 3.1 `Chirami/Resources/chirami-default.css` を作成（`--chirami-*` 変数定義、light/dark 対応）
- [x] 3.2 組み込みテーマ（yellow, blue, green, pink, purple, gray 相当）を CSS で定義
- [x] 3.3 `project.yml` にリソースとして追加

## 4. NoteWebView CSS ロード実装

- [x] 4.1 `NoteWebView.swift` から `setTheme()`/`setFont()` メソッドを削除
- [x] 4.2 `currentColorScheme`/`currentIsDark`/`currentFontName`/`currentFontSize` プロパティを削除
- [x] 4.3 `WKUserContentController` にビルトイン CSS を `WKUserStyleSheet` として追加
- [x] 4.4 `appearance.cssFile` が設定されている場合、ユーザー CSS を読み込んで `WKUserStyleSheet` として追加（ビルトインの後）
- [x] 4.5 `cssFile` が存在しない場合は warning ログを出してビルトイン CSS のみで動作させる

## 5. per-note テーマ属性注入

- [x] 5.1 `NoteWebView.swift` に `data-chirami-theme` 属性を `<html>` 要素に注入する処理を追加（JS 経由）
- [x] 5.2 `theme` が nil のノートには属性を付与しないことを確認

## 6. Note モデルと NoteColorScheme の整理

- [x] 6.1 `Note.swift` の `colorScheme: NoteColorScheme` プロパティを `theme: String?` に変更（`NoteConfig.theme` に対応）
- [x] 6.2 `NoteColorScheme`、`NoteColorSchemeDef`、`ColorSet` 構造体を削除（`Note.swift` から）
- [x] 6.3 削除後にビルドエラーがないことを確認

## 7. Display 系の対応

- [x] 7.1 `DisplayWindowManager.swift` の `resolveNoteColorScheme()` 呼び出しを削除し、テーマ名（`String?`）を渡すように変更
- [x] 7.2 `DisplayPanel.swift` の `color: NoteColorScheme` 引数を削除し、`NSPanel.backgroundColor` をデフォルト色または透明に変更
- [x] 7.3 `DisplayContentView.swift` の `colorScheme: NoteColorScheme` プロパティを削除し、`setTheme()` 呼び出しを削除
- [x] 7.4 `DisplayContentView` の `NoteWebView` に `data-chirami-theme` 属性注入を追加（theme名がある場合）
- [x] 7.5 `DisplayPanel` / `DisplayContentView` でビルドエラーがないことを確認

## 8. NSPanel 背景色の対応

- [x] 8.1 `NoteWindow.swift` の `panel.backgroundColor = note.colorScheme.nsColor` を置き換える（design.md の「NSPanel 背景色の問題」を参照して方針を決定してから実装）
- [x] 8.2 `hostingView.layer?.backgroundColor` の設定を同様に対応
- [x] 8.3 `DisplayPanel.swift` の `backgroundColor = color.nsColor` を同様に対応
- [x] 8.4 WebView 背景と NSPanel 背景が視覚的に一致することをデフォルトテーマで確認

## 9. フォントサイズ調整（Cmd+`+`/`-`）

- [x] 9.1 `NoteWebView.swift` の `setFont()` bridge 呼び出しを `evaluateJavaScript` による `--chirami-font-size` 直接更新に置き換える
- [x] 9.2 Cmd+`+`/`-` でフォントサイズが増減することを動作確認

## 10. JS ブリッジ整理

- [x] 10.1 `editor-web/src/main.ts` から `setTheme`/`setFont` API エクスポートを削除
- [x] 10.2 `NoteWebView.swift` 側の `setTheme`/`setFont` 呼び出しをすべて削除
- [x] 10.3 ビルドエラーがないことを確認

## 11. ドキュメント

- [x] 11.1 `docs/css-theming.md` を作成（`--chirami-*` 変数リファレンス、カスタマイズ例、ビルトインテーマ一覧）
