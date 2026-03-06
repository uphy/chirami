# CPU パフォーマンス問題の調査メモ

調査日: 2026-03-07
症状: 編集中に CPU が約 50%（Obsidian は 10〜20%）

## 計測結果

処理を段階的にコメントアウトして CPU 使用率を計測した。

| ステップ | 無効化した処理 | CPU |
|----------|---------------|-----|
| 元の状態 | — | ~50% |
| ステップ1〜3 | `applyStyling` 呼び出し（テキスト変更・カーソル移動）+ `storage.setAttributes` ループ | ~20% |
| ステップ4追加 | `styler.style()`（Markdown パース） | ~15% |

コストの内訳：
- `storage.setAttributes` → `endEditing()` → NSLayoutManager レイアウト再計算: **約30%**
- `styler.style()` のパース処理: **約5%**
- その他（描画・カーソル処理など）: **約15%**

主因は `setAttributes` による **ドキュメント全体のレイアウト再計算** であることが確定した。

---

## 問題一覧

### 問題1: キーストローク毎にドキュメント全体を再処理

**場所**: `LivePreviewEditor.swift` → `Coordinator.applyStyling(to:)`

カーソル移動（`textViewDidChangeSelection`）でも、テキスト変更（`textDidChange`）でも、`applyStyling` が呼ばれるたびに以下がすべて実行される。

- `Document(parsing: text)` — swift-markdown でドキュメント全体をパース
- `buildLineStarts(in: text)` — 全文字を走査してライン位置を計算
- `enumerateFoldableBlocks(from: doc)` — AST を全走査
- 全ブロックへのスタイリング — block ごとに regex マッチング + `addAttributes`
- `storage.setAttributes` × 全 attribute run — NSTextStorage がレイアウト全体を無効化・再計算

**影響**: ★★★（ドキュメントサイズに比例して重くなる。計測で約30%のコストと確認）
**対処コスト**: 高（アーキテクチャ変更が必要）
**対処案**:

- **デバウンス**（50〜150ms）で `applyStyling` の呼び出し頻度を下げる。実装は容易だが入力中にプレビューが遅れる体感が生じる可能性がある。
- **属性レベルの差分適用**（推奨）: `MarkdownStyler` は変更せずフルパースを維持し、`setAttributes` を呼ぶ前に storage の現在の属性と比較して差分のある range だけ適用する。MarkdownStyler の将来の変更に影響されず、Markdown のセマンティクスを知らない純粋な比較ロジックのため保守リスクが低い。変更箇所は `applyStyling` 内の `setAttributes` ループのみ（約30〜50行）。

---

### 問題2: `textView.needsDisplay = true` による冗長な全画面再描画

**場所**: `LivePreviewEditor.swift:471`

```swift
textView.needsDisplay = true
```

`storage.endEditing()` はすでに変更された範囲の再描画をスケジュールしている。その直後に `needsDisplay = true` を呼ぶことで、**ビュー全体の再描画**がもう1回追加される。`applyStyling` の呼び出しごとに 2 回描画が走る。

**影響**: ★★
**対処コスト**: 低（この1行を削除する）

---

### 問題3: テーブルがないノートでも `ensureLayout` が毎回強制実行

**場所**: `TableOverlayView.swift:107` ← `LivePreviewEditor.swift:470`（`overlayManager.update`）

```swift
layoutManager.ensureLayout(for: textContainer)
```

`storage.endEditing()` でレイアウトが無効化された直後に呼ばれるため、レイアウト全体を即時・同期的に強制計算させる。テーブルが存在しないノートでも `applyStyling` ごとに毎回実行される。

**影響**: ★★
**対処コスト**: 低（テーブル属性が存在するときのみ呼ぶよう条件追加）

---

### 問題4: チェックボックス用 SF Symbol 画像をキャッシュせず毎フレーム生成

**場所**: `BulletLayoutManager.swift` → `drawGlyphs(forGlyphRange:at:)` → `drawSFSymbol`

```swift
let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
let image = NSImage(systemSymbolName: name, ...)?.withSymbolConfiguration(config)
let tinted = image.tinted(with: color)  // コピー → lockFocus → 描画 → unlockFocus
```

`tinted(with:)` は毎回 NSImage をコピーして off-screen コンテキストを生成・描画・解放する。
問題2の `needsDisplay = true` により `drawGlyphs` が毎キーストロークで全チェックボックス分実行される。

**影響**: ★★
**対処コスト**: 中（(symbolName, color, size) をキーにしたキャッシュ追加）

---

### 問題5: Highlightr の同期実行（コードブロックがある場合）

**場所**: `MarkdownStyler+CodeBlock.swift:106`

```swift
highlightr.highlight(codeBody, as: lang, fastRender: false)
```

Highlightr は内部的に JavaScriptCore を使用する。カーソルがコードブロックの**外**にあるとき、毎キーストロークでコードブロック全体をシンタックスハイライトする。`fastRender: false` はより精度の高い（より遅い）モード。

**影響**: ★★（コードブロックがあるノートのみ）
**対処コスト**: 中（バックグラウンドスレッドで非同期実行 + 結果をメインスレッドで適用）

---

### 問題6: `textViewFrameDidChange` による二重 `applyStyling`（対処済み）

**場所**: `LivePreviewEditor.swift` → `Coordinator.textViewFrameDidChange`

キーストロークでテキストビューの高さが変わるたびに `textViewFrameDidChange` が発火し、`textDidChange` 経由の `applyStyling` に加えてもう1回 `applyStyling` が呼ばれていた。

コンテナ幅が変わったときのみ `applyStyling` を呼ぶよう修正済み（`lastContainerWidth` で追跡）。

---

## 根本的な設計上の課題

現在の実装はキーストロークごとにドキュメント全体を再レンダリングする設計になっている。
Obsidian（CodeMirror 6 ベース）は変更のあった行・ブロックだけをインクリメンタルに更新するため、ドキュメントサイズに関係なく CPU 使用率が低い。

NSTextStorage + NSLayoutManager の仕組み上、属性変更は `beginEditing/endEditing` でバッチ処理されるが、変更範囲が広いほどレイアウト再計算のコストが上がる。

## 対処優先度

| 優先 | 問題 | 変更量 | 期待効果 | 状態 |
|------|------|--------|----------|------|
| 1 | 問題6: `textViewFrameDidChange` 二重呼び出し | 数行 | キーストロークごとの二重処理を排除 | 対処済み |
| 2 | 問題2: `needsDisplay = true` 削除 | 1行 | 冗長な全画面再描画を排除 | 対処済み |
| 3 | 問題3: `overlayManager.update` を条件実行 | 数行 | テーブルなし時の `ensureLayout` を省略 | 対処済み |
| 4 | 問題1: 属性レベルの差分適用 | 〜50行 | **根本解決（約30%のコスト削減）** | 対処済み |
| 5 | 問題4: 画像キャッシュ | 〜30行 | 描画コストを削減 | 未対処 |
| 6 | 問題5: Highlightr 非同期化 | 中規模 | コードブロック時の遅延解消 | 未対処 |

> **注記**: 問題2・3・6は対処済みだが計測では CPU の大幅な改善は見られなかった。コスト全体の大半（約30%）は問題1（属性適用 + レイアウト再計算）が占めているため、根本解決のためには問題1への対処が必須。
