# Research & Design Decisions

## Summary

- **Feature**: `smart-paste`
- **Discovery Scope**: Extension (既存 NSTextView エディタへの機能追加)
- **Key Findings**:
  - `MarkdownTextView.performKeyEquivalent` に `Cmd+Shift+V` を追加するのが自然な統合ポイント
  - NSPasteboard の `.html` / `.string` タイプでコンテンツ種別を判定可能
  - HTML→Markdown 変換は SwiftHTMLToMarkdown ライブラリが軽量かつ十分な機能を提供

## Research Log

### NSPasteboard によるコンテンツ種別判定

- **Context**: クリップボードの内容を HTML / URL / JSON / コードに分類する方法
- **Sources Consulted**: [Apple NSPasteboard ドキュメント](https://developer.apple.com/documentation/appkit/nspasteboard), [Maccy clipboard manager](https://github.com/p0deje/Maccy)
- **Findings**:
  - `NSPasteboard.general.types` で利用可能なタイプを列挙できる
  - `.html` タイプが存在すれば HTML コンテンツと判定
  - `.string` タイプのみの場合、テキスト内容からURL / JSON / コードを判定
  - URL 判定: `URL(string:)` で有効な `http`/`https` スキームかチェック
  - JSON 判定: `JSONSerialization.isValidJSONObject` または `JSONSerialization.jsonObject(with:)` で検証
- **Implications**: 判定ロジックは NSPasteboard のタイプ情報をまず確認し、次にテキスト内容のパターンマッチで分類する2段階方式

### HTML → Markdown 変換ライブラリ

- **Context**: ブラウザからコピーした HTML を Markdown に変換する手段
- **Sources Consulted**: [SwiftHTMLToMarkdown](https://github.com/ActuallyTaylor/SwiftHTMLToMarkdown), [Demark](https://steipete.me/posts/2025/introducing-demark-html-to-markdown-in-swift), [jaywcjlove/HTMLToMarkdown](https://github.com/jaywcjlove/HTMLToMarkdown)
- **Findings**:
  - **SwiftHTMLToMarkdown**: 純粋 Swift 実装、MIT ライセンス、見出し・リンク・リスト・インライン装飾をサポート。テーブル非対応。軽量
  - **Demark**: WKWebView ベース。堅牢だがランタイム依存が重い
  - **HTMLToMarkdown (jaywcjlove)**: JavaScriptCore ベース。JS エンジン依存
- **Implications**: Chirami は軽量ユーティリティのため、SwiftHTMLToMarkdown が最適。テーブル変換は non-goal として許容

### 既存キーバインドパターン

- **Context**: `Cmd+Shift+V` の追加方法
- **Sources Consulted**: `MarkdownTextView.swift:185-216`
- **Findings**:
  - `performKeyEquivalent(with:)` で `modifierFlags` と `charactersIgnoringModifiers` をチェック
  - 既存ショートカット: Cmd+B (太字), Cmd+I (斜体), Cmd+L (タスクリスト) など
  - `[.command, .shift]` フラグと `"v"` キーで `Cmd+Shift+V` を検出可能
- **Implications**: 既存パターンに1分岐追加するだけで統合可能

### テキスト挿入と Undo サポート

- **Context**: 変換後テキストの挿入方法
- **Sources Consulted**: `MarkdownTextView.swift:116-144`, `LivePreviewEditor.swift:183-188`
- **Findings**:
  - `shouldChangeText(in:replacementString:)` → `storage.replaceCharacters` → `didChangeText()` パターンが必須
  - `didChangeText()` が `textDidChange` 通知をトリガーし、Combine 経由でファイル保存・再スタイリングが連鎖
  - このパターンを守れば Undo/Redo も自動的に機能
- **Implications**: SmartPasteService は変換結果の文字列を返すだけでよく、挿入は MarkdownTextView が既存パターンで処理

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Service + View Extension | SmartPasteService で変換、MarkdownTextView で呼び出し | 既存アーキテクチャと整合、責務が明確 | なし | **採用** |
| Delegate パターン | 変換ロジックを Delegate 経由で注入 | テスタビリティ | Chirami の既存パターン (Closure ベース) と不整合 | 不採用 |

## Design Decisions

### Decision: HTML→Markdown 変換ライブラリの選定

- **Context**: ブラウザからの HTML ペーストを Markdown に変換する手段が必要
- **Alternatives Considered**:
  1. SwiftHTMLToMarkdown — 純粋 Swift、軽量
  2. Demark — WKWebView ベース、堅牢
  3. 自前実装 — 完全制御可能だがコスト大
- **Selected Approach**: SwiftHTMLToMarkdown
- **Rationale**: Chirami は軽量ユーティリティであり、WKWebView や JavaScriptCore のランタイム依存は不適切。必要な変換 (見出し・リンク・リスト・インライン装飾) をカバーしており十分
- **Trade-offs**: テーブル変換非対応。必要になった場合はライブラリ変更で対応可能
- **Follow-up**: SPM で追加し、BasicHTML クラスの API を検証

### Decision: URL タイトル取得の非同期設計

- **Context**: URL ペースト時にページタイトルを取得する間、ユーザーを待たせない設計が必要
- **Alternatives Considered**:
  1. プレースホルダ挿入 → 非同期更新
  2. 同期的にタイトル取得 (ブロッキング)
- **Selected Approach**: プレースホルダ挿入 → 非同期更新
- **Rationale**: ネットワークレイテンシでエディタがブロックされるのは UX として許容できない
- **Trade-offs**: テキスト挿入後の非同期更新は、ユーザーがカーソルを移動している可能性がある
- **Follow-up**: プレースホルダ位置を NSRange で追跡し、タイトル取得後に正確に置換

## Risks & Mitigations

- HTML 変換の品質がソースによって不安定 — フォールバックとしてプレーンテキスト挿入を保証
- URL タイトル取得のネットワークエラー — タイムアウト設定 (5秒) + URL 自身をフォールバックテキストに
- SwiftHTMLToMarkdown のメンテナンス停止リスク — API が小さいため、必要なら自前実装に切り替え可能

## References

- [NSPasteboard | Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nspasteboard)
- [SwiftHTMLToMarkdown](https://github.com/ActuallyTaylor/SwiftHTMLToMarkdown)
- [Demark](https://steipete.me/posts/2025/introducing-demark-html-to-markdown-in-swift)
- [Maccy Clipboard Manager](https://github.com/p0deje/Maccy)
