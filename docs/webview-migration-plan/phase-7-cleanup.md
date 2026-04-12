# Phase 7: 旧実装削除とクリーンアップ

## 目的

Phase 6 までで WebView + CodeMirror 版がすべての機能を満たしている前提で、旧 NSTextView ベースの実装と関連依存を削除する。コードベースを整理し、保守コストを下げる。

## 前提

- Phase 6 までのすべての機能が動作していること
- 1 週間以上、Phase 6 の状態で実機運用してリグレッションがないこと
- ユーザー（開発者本人）が WebView 版の体験に納得していること

## スコープ

### 含む

- 旧 Editor/ ディレクトリの削除
- 旧 LivePreviewEditor / MarkdownTextView の削除
- 不要になった依存（`swift-markdown`, `Highlightr`）の削除
- `project.yml` / `Package.swift` の更新
- `xcodegen generate` の再実行
- `CLAUDE.md` の更新
- `README.md` の更新
- `docs/` の関連ドキュメントの更新
- `docs/performance-issues.md` への移行報告追記
- `docs/webview-migration-plan/` の各ドキュメントに「実装完了」マークを追加

### 含まない

- 機能追加
- バグ修正（移行と無関係なものは別 PR）

## 削除対象ファイル

### Chirami/Views/

- [ ] `LivePreviewEditor.swift`
- [ ] `MarkdownTextView.swift`
- [ ] `MarkdownTextView+ListEditing.swift`

### Chirami/Editor/

- [ ] `BulletLayoutManager.swift`
- [ ] `MarkdownStyler.swift`
- [ ] `MarkdownStyler+Attributes.swift`
- [ ] `MarkdownStyler+RangeUtils.swift`
- [ ] `MarkdownStyler+Inline.swift`
- [ ] `MarkdownStyler+Heading.swift`
- [ ] `MarkdownStyler+CodeBlock.swift`
- [ ] `MarkdownStyler+BlockQuote.swift`
- [ ] `MarkdownStyler+List.swift`
- [ ] `MarkdownStyler+Table.swift`
- [ ] `MarkdownStyler+Folding.swift`
- [ ] `MarkdownStyler+ThematicBreak.swift`
- [ ] `TableOverlayView.swift`
- [ ] `InlineMarkupRenderer.swift`
- [ ] `EditorStatePreservable.swift`

### 検証が必要なファイル

以下は他から参照されている可能性があるため、依存関係を確認してから削除を判断する。

- [ ] `ImageCache.swift` — Swift 側の画像配信で使われるか確認
- [ ] `ImagePasteService.swift` — 画像保存ロジックは Phase 6 でも流用しているため部分削除のみ

## 削除対象依存

### Package.swift

- [ ] `swift-markdown` を `dependencies` から削除
- [ ] `Highlightr` を `dependencies` から削除
- [ ] 上記をターゲットの `dependencies` からも削除

### project.yml

- [ ] `swift-markdown`, `Highlightr` の SPM 参照を削除
- [ ] 削除したファイルが `sources` に含まれていないことを確認

### `xcodegen generate` 後の確認

- [ ] ビルドが成功する
- [ ] アプリが起動する
- [ ] 既存ノートがすべて表示・編集できる

## タスク一覧

### 削除作業

- [ ] 削除対象ファイルが import / 参照されている箇所を grep で確認
- [ ] 参照元（NoteWindow.swift など）から呼び出しを削除
- [ ] 削除対象ファイルを `git rm`
- [ ] `Package.swift` 編集
- [ ] `project.yml` 編集
- [ ] `xcodegen generate` 再実行
- [ ] ビルド確認
- [ ] 実機で全機能の動作確認

### ドキュメント更新

- [ ] `CLAUDE.md` の「Live Preview エディタ」節を全面書き換え
  - LivePreviewEditor / MarkdownStyler / BulletLayoutManager の記述を削除
  - `NoteWebView`, `NoteWebViewBridge`, `editor-web/` の構成を記載
- [ ] `CLAUDE.md` の「依存ライブラリ」表から `swift-markdown`, `Highlightr` を削除し、JS 側依存（CodeMirror, turndown）への参照を追加
- [ ] `CLAUDE.md` の「注意: MarkdownStyler では UTF-8 と String.Index/NSRange...」記述を削除し、JS ↔ Swift のオフセット扱いに関する新しい注意を追加
- [ ] `CLAUDE.md` の Logger 例から `MarkdownTextView` 参照を除去し、`NoteWebView` / `NoteWebViewBridge` の例に差し替え
- [ ] `README.md` の依存ライブラリ表を更新
- [ ] `README.md` の Development セクションに `mise run editor-build` を追加
- [ ] `docs/performance-issues.md` に「WebView + CodeMirror 6 への移行による根本解決」節を追加
- [ ] `docs/features.md` を実装後の挙動に合わせて微調整
- [ ] `docs/advanced.md` の Images セクションを画像 widget の挙動に合わせて更新
- [ ] `docs/webview-migration-plan/README.md` の各 Phase 状態を「完了」に更新
- [ ] `docs/webkit-crash-investigation.md` を「解決」状態にマーク

### `CLAUDE.md` の "Fusen" → "Chirami" 修正

- [ ] L11, L21, L25 の "Fusen" 残骸を "Chirami" に修正（移行作業と独立して先行実施可）

## 削除手順の詳細

### 1. 参照確認

```bash
# 削除予定クラスが他から使われていないか確認
grep -rn "LivePreviewEditor" Chirami/
grep -rn "MarkdownStyler" Chirami/
grep -rn "MarkdownTextView" Chirami/
grep -rn "BulletLayoutManager" Chirami/
grep -rn "TableOverlayView" Chirami/
grep -rn "EditorStatePreservable" Chirami/
```

参照元が `NoteWindow.swift` 内の `LivePreviewEditor` 呼び出しのみであるべき。Phase 1 で `NoteWebView` に置き換え済みなので、参照は残っていないはず。

### 2. 段階的削除

依存関係の浅いファイルから順に削除する。

1. `MarkdownStyler+*.swift`（拡張ファイル群）
2. `MarkdownStyler.swift`
3. `BulletLayoutManager.swift`
4. `TableOverlayView.swift`
5. `InlineMarkupRenderer.swift`
6. `MarkdownTextView+ListEditing.swift`
7. `MarkdownTextView.swift`
8. `LivePreviewEditor.swift`
9. `EditorStatePreservable.swift`

各削除後に `xcodegen generate` + ビルドで確認する。

### 3. 依存ライブラリ削除

`Package.swift` から `swift-markdown` と `Highlightr` を削除した後、`swift package resolve` を実行して `Package.resolved` を更新する。

```bash
swift package resolve
```

### 4. 最終確認

- [ ] アプリ起動
- [ ] 全テスト項目（Phase 6 の確認手順を再実施）
- [ ] 1 週間程度の実運用でリグレッションなし

## 動作確認手順

Phase 6 までの確認手順を全て再実施し、リグレッションがないことを確認する。

加えて以下を確認する。

- [ ] 削除した swift-markdown / Highlightr 由来のシンボルが残っていない（`grep -rn "swift_markdown" Chirami/` 等）
- [ ] バンドルサイズが減っている（Release ビルドの .app サイズを比較）
- [ ] 起動時間が変わっていない、または改善している
- [ ] CPU 使用率が改善している（旧実装で問題だった連続入力時の負荷を比較）

## 終了条件

- [ ] 削除対象ファイルがすべて削除されている
- [ ] `swift-markdown` / `Highlightr` 依存が削除されている
- [ ] `xcodegen generate` で project.pbxproj が正しく更新される
- [ ] ビルドが成功する
- [ ] すべての機能が動作する（リグレッションなし）
- [ ] CLAUDE.md / README.md / docs/ が更新されている
- [ ] `docs/performance-issues.md` に移行報告が追加されている

## 想定されるリスク

### リスク 1: 削除対象が他から参照されている

**内容**: `EditorStatePreservable` などのプロトコルが想定外の場所で使われている可能性。

**対策**:

- 削除前に必ず grep で参照確認
- 1 つずつ削除してビルドエラーで確認
- 一括削除は避ける

### リスク 2: ImageCache.swift / ImagePasteService.swift の取り扱い

**内容**: 一部メソッドだけ Phase 6 で流用している場合、ファイル全体を削除できない。

**対策**:

- 削除ではなく不要メソッドのみ除去
- `ImagePasteService` は WebView 版のために refactor して残す

### リスク 3: SPM 依存削除後のキャッシュ

**内容**: Xcode の DerivedData にキャッシュされた依存が残ってビルドが通ってしまう（嘘のグリーン）。

**対策**:

- `rm -rf ~/Library/Developer/Xcode/DerivedData/Chirami-*`
- クリーンビルドで動作確認

### リスク 4: バンドルサイズ削減で意図しないリソースまで削除

**内容**: project.yml の `Copy Bundle Resources` から正規表現削除を使うと editor/ が消える可能性。

**対策**:

- `git diff project.yml` で変更箇所を必ず目視確認
- xcodegen 再生成後の `project.pbxproj` も差分確認

## 移行完了後

- [ ] `feat/web-view2` ブランチを `main` にマージ
- [ ] 移行記念のアナウンス（Issue / リリースノート）
- [ ] 過去の `feat/web-view` ブランチは保留（履歴として残す）
- [ ] `docs/webview-migration-plan/` を「完了」状態にして残す（将来の参照のため）
