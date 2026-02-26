# リサーチ & 設計判断ログ

## Summary

- **Feature**: `image-paste`
- **Discovery Scope**: Extension（既存システムへの機能追加）
- **Key Findings**:
  - 既存の `SmartPasteService` / `MarkdownTextView` / `ImageCache` / `BulletLayoutManager` パイプラインに統合可能。新規ライブラリ不要
  - `CryptoKit` / `SHA256` は既にプロジェクト依存に含まれており、ハッシュベースファイル名生成に流用可能
  - `.imageIcon` 属性を通じた画像レンダリングパスは、相対パスを絶対パスに解決する一箇所の変更で対応できる

## Research Log

### 既存ペースト処理パイプラインの構造

- **Context**: 画像ペーストを既存のペースト処理にどう統合するかの調査
- **Sources Consulted**: `SmartPasteService.swift`, `MarkdownTextView.swift`
- **Findings**:
  - `Cmd+Shift+V` → `performSmartPaste()` → `SmartPasteService.detectContentType()` → `convert()` → `insertSmartPasteText()`
  - `Cmd+V` → 標準の `paste(_:)` (現在オーバーライドなし)
  - `detectContentType()` は HTML → URL → JSON → Code → PlainText の優先順位。テキストがない場合は `nil` を返す
  - 画像検出はテキスト不在の場合にのみ発動すべき（要件 1.3: テキストと画像の共存時はテキスト優先）
- **Implications**: `paste(_:)` をオーバーライドして画像検出を行い、テキストがない場合のみ `ImagePasteService` に委譲する設計が最適

### 画像レンダリングパイプラインの構造

- **Context**: ペーストした画像が既存パイプラインで正しくレンダリングされるかの調査
- **Sources Consulted**: `MarkdownStyler+Inline.swift`, `ImageCache.swift`, `BulletLayoutManager.swift`
- **Findings**:
  - `applyImagePattern()` が `![alt](url)` パターンを検出し、`.imageIcon` 属性にURL文字列をセット
  - `BulletLayoutManager.drawGlyphs()` が `.imageIcon` 属性から URL を取得し、`ImageCache.shared.image(for:)` で画像を描画
  - `ImageCache` は絶対パス（`/`始まり）とHTTP URLをサポート済み。相対パスは未対応
  - **一貫性要件**: `.imageIcon` にセットする値と `ImageCache` に渡す値が完全一致する必要がある
- **Implications**: `applyImagePattern()` で相対パスを絶対パスに解決し、解決済みパスを `.imageIcon` と `ImageCache` の両方に渡す

### 設定解決パターンの分析

- **Context**: `attachments_dir` 設定をどのパターンで実装するかの調査
- **Sources Consulted**: `ConfigModels.swift` (resolve* メソッド群)
- **Findings**:
  - 既存パターン: `resolveColor(defaults:)`, `resolveTransparency(defaults:)` 等
  - 優先順位: ノート固有設定 → グローバルデフォルト → フォールバック値
  - `resolveAttachmentsDir` は `noteURL` パラメータが追加で必要（パス解決のため）
  - チルダ展開: `(dir as NSString).expandingTildeInPath` パターンが既存
- **Implications**: 既存の `resolve*` パターンを踏襲し、`resolveAttachmentsDir(noteURL:defaults:)` を追加

### Periodic Note の attachmentsDir デフォルト

- **Context**: Periodic note は日付ごとにファイルが異なるため、attachmentsDir のデフォルト計算が通常ノートと異なる
- **Sources Consulted**: `NoteStore.swift`, `PathTemplateResolver` の使用箇所
- **Findings**:
  - テンプレートパス例: `~/notes/daily/{yyyy-MM-dd}.md`
  - `PathTemplateResolver.extractBaseDirectory()` でベースディレクトリを抽出可能
  - 通常ノート: `<stem>.attachments/` → 各ファイルごとに別ディレクトリ
  - Periodic note: テンプレートの親ディレクトリ + `attachments/` → 全日付で共有
- **Implications**: `resolveAttachmentsDir` に `isPeriodicNote` と `pathTemplate` を考慮するロジックが必要。NoteStore で Note 生成時に periodic かどうかで分岐

### SHA256 ハッシュによるファイル名生成

- **Context**: 画像ファイル名の重複防止メカニズムの調査
- **Sources Consulted**: `ConfigModels.swift` (line 146-150)
- **Findings**:
  - 既存パターン: `SHA256.hash(data:)` → `digest.prefix(N).map { String(format: "%02x", $0) }.joined()`
  - `noteId` では先頭6バイト (12文字の hex) を使用
  - 画像ファイルでは衝突回避のためより長いプレフィックスを使用すべき（先頭16バイト = 32文字を推奨）
- **Implications**: 同一画像の重複保存を防止しつつ、十分な一意性を確保

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| 既存レイヤードアーキテクチャへの統合 | Services/Config/Models/Views/Editor の各層を拡張 | 既存パターンとの一貫性、学習コスト低 | 変更ファイル数が多い (8-9ファイル) | 採用。steering の構造に完全準拠 |
| 独立モジュール方式 | 画像ペースト処理を独立したモジュールに集約 | 変更ファイル数を抑制可能 | 既存のレイヤー分離原則に反する | 不採用 |

## Design Decisions

### Decision: paste(_:) オーバーライドによる画像ペースト検出

- **Context**: 画像ペーストのエントリーポイントをどこに置くか
- **Alternatives Considered**:
  1. `SmartPasteService.detectContentType()` に `.image` ケースを追加し、`performSmartPaste()` 経由で処理
  2. `paste(_:)` をオーバーライドし、画像検出時は `ImagePasteService` に直接委譲
- **Selected Approach**: Option 2 — `paste(_:)` オーバーライド
- **Rationale**: Smart Paste (Cmd+Shift+V) は明示的にテキスト変換機能。画像ペーストは通常の Cmd+V で動作すべき。`SmartPasteService` に画像処理を混ぜると責務が不明確になる
- **Trade-offs**: `paste(_:)` と `performSmartPaste()` の両方で画像チェックが必要になるが、検出ロジックは `ImagePasteService` に集約することで重複を最小化
- **Follow-up**: `performSmartPaste()` でも画像ケースをハンドルするかは実装時に判断

### Decision: コンテンツハッシュベースのファイル名

- **Context**: 画像ファイル名の一意性と重複防止
- **Alternatives Considered**:
  1. UUID ベース — 常に一意だが同一画像の重複保存が発生
  2. タイムスタンプベース — 同時ペーストで衝突の可能性
  3. SHA256 ハッシュプレフィックス — コンテンツベースのデデュプリケーション
- **Selected Approach**: SHA256 ハッシュプレフィックス (先頭16バイト = 32文字 hex)
- **Rationale**: 既存の `noteId` 計算パターンと一致。同一画像の重複保存を自然に防止
- **Trade-offs**: ハッシュ計算のオーバーヘッド（画像サイズに比例）は無視できるレベル

### Decision: 相対パス解決の実装箇所

- **Context**: Markdown 内の相対パス画像参照をどこで絶対パスに解決するか
- **Alternatives Considered**:
  1. `ImageCache.load()` 内でベース URL を受け取って解決
  2. `applyImagePattern()` 内で解決し、絶対パスを `.imageIcon` 属性にセット
- **Selected Approach**: Option 2 — `applyImagePattern()` 内で解決
- **Rationale**: `ImageCache` はパス解決の責務を持つべきではない。スタイリング段階で解決すれば、`.imageIcon` → `ImageCache` → `BulletLayoutManager` の既存パイプラインが変更なしで動作する
- **Trade-offs**: `MarkdownStyler` に `noteBaseURL` プロパティが必要になるが、単一責務の範囲内

## Risks & Mitigations

- **リスク**: 大きな画像のペーストでメインスレッドがブロックされる可能性 — PNG 変換と保存は同期処理だが、通常のスクリーンショットサイズ（数MB以下）では問題にならない。将来的に巨大画像が問題になる場合は非同期化を検討
- **リスク**: セキュリティスコープドブックマーク環境下でのファイル書き込み権限 — sandbox 下でのファイルアクセスは既存の bookmark メカニズムで管理されている。attachmentsDir が bookmark 範囲外の場合は書き込み失敗の可能性がある。エラーハンドリングで対応
- **リスク**: `.imageIcon` 属性値の不一致による画像表示の失敗 — `applyImagePattern()` で解決した絶対パスが `ImageCache` と `BulletLayoutManager` で一貫して使用されることをテストで検証
