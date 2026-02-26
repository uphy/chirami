# Requirements Document

## Project Description (Input)
# 付箋への画像ペースト機能

## Context

Chirami の付箋に画像を貼り付ける機能を追加する。現在、markdown の `![alt](url)` 構文による画像レンダリングは既に実装済みだが、クリップボードからの画像ペーストは未対応（Smart Paste 仕様でも明示的に非ゴールとされている）。

ファイルベース保存方式を採用し、画像保存先ディレクトリを設定で変更可能にする。

## 方針

1. Cmd+V で画像データを検出 → PNG ファイルとして保存
2. `![](relative/path/image-xxxx.png)` をテキストに挿入
3. 既存の ImageCache + BulletLayoutManager がレンダリング
4. 画像保存先は `config.yaml` で設定可能（デフォルト: `<note-stem>.attachments/`）

## 添付ファイル保存ディレクトリの設定

`NoteConfig` (ノートごと) と `NoteDefaults` (グローバルデフォルト) に `attachments_dir` を追加する。既存の `resolve*()` パターンに従い、ノートごと設定 → デフォルト → フォールバックの優先順位で解決する。画像に限らず、将来的に他の添付ファイル（PDF 等）にも対応可能な命名とする。

```yaml
# config.yaml の例
defaults:
  attachments_dir: ~/Pictures/chirami/  # グローバルデフォルト

notes:
  - path: ~/notes/todo.md
    attachments_dir: attachments/       # このノート専用（ノートからの相対パス）
  - path: ~/notes/daily/{yyyy-MM-dd}.md
    # attachments_dir 未指定 → デフォルトの ~/Pictures/chirami/ を使用
```

**パス解決ルール:**

- 未指定: `<note-stem>.attachments/` (ノートファイルと同じディレクトリ)
- 相対パス (例: `attachments/`): ノートファイルの親ディレクトリからの相対
- 絶対パス (例: `~/Pictures/chirami/`): そのまま使用

## 変更対象ファイル

**新規作成:**

- `Chirami/Services/ImagePasteService.swift` — 画像保存ロジック

**修正:**

- `Chirami/Config/ConfigModels.swift` — `attachments_dir` 設定追加
- `Chirami/Models/Note.swift` — `attachmentsDir: URL?` プロパティ追加
- `Chirami/Models/NoteStore.swift` — Note 生成時に `attachmentsDir` を設定
- `Chirami/Services/SmartPasteService.swift` — `.image` ケース追加
- `Chirami/Views/MarkdownTextView.swift` — `paste(_:)` オーバーライド、`noteURL` / `attachmentsDir` プロパティ追加
- `Chirami/Views/LivePreviewEditor.swift` — `noteURL` / `attachmentsDir` パラメータ追加・受け渡し
- `Chirami/Views/NoteWindow.swift` — `LivePreviewEditor` に `note.path` と `note.attachmentsDir` を渡す
- `Chirami/Editor/MarkdownStyler.swift` — `noteBaseURL` プロパティ追加
- `Chirami/Editor/MarkdownStyler+Inline.swift` — 相対パス解決処理

## 実装ステップ

### Step 1: 設定追加 (`ConfigModels.swift`)

`NoteConfig` と `NoteDefaults` に `attachmentsDir: String?` を追加。

```swift
// NoteDefaults
struct NoteDefaults: Codable {
    // ... 既存フィールド
    var attachmentsDir: String?
    enum CodingKeys: String, CodingKey {
        // ... 既存キー
        case attachmentsDir = "attachments_dir"
    }
}

// NoteConfig
struct NoteConfig: Codable {
    // ... 既存フィールド
    var attachmentsDir: String?
    enum CodingKeys: String, CodingKey {
        // ... 既存キー
        case attachmentsDir = "attachments_dir"
    }

    /// Resolve the image directory URL for a given note file path.
    /// - nil/未指定 → <note-stem>.attachments/ (ノートと同ディレクトリ)
    /// - 相対パス → ノートの親ディレクトリからの相対
    /// - 絶対パス/~ → そのまま
    func resolveAttachmentsDir(noteURL: URL, defaults: NoteDefaults?) -> URL {
        let dir = attachmentsDir ?? defaults?.attachmentsDir
        guard let dir else {
            // Default: <note-stem>.attachments/
            let stem = noteURL.deletingPathExtension().lastPathComponent
            return noteURL.deletingLastPathComponent()
                .appendingPathComponent("\(stem).attachments")
        }
        if dir.hasPrefix("~/") {
            let expanded = (dir as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        if dir.hasPrefix("/") {
            return URL(fileURLWithPath: dir)
        }
        // Relative path: resolve from note's parent directory
        return noteURL.deletingLastPathComponent()
            .appendingPathComponent(dir)
    }
}
```

### Step 2: Note モデル拡張 (`Note.swift`, `NoteStore.swift`)

`Note` に `attachmentsDir: URL?` を追加。`NoteStore` で Note 生成時に config から解決した値を設定。

### Step 3: ImagePasteService（新規）

画像を PNG ファイルとして保存し、markdown テキストを返す。

- ファイル名: `image-<sha256-prefix>.png` (コンテンツハッシュでデデュプリケーション)
- `CryptoKit` は既存の依存 (`ConfigModels.swift:2` で使用済み)
- 保存先ディレクトリは呼び出し側から渡す
- markdown に挿入するパスは、ノートファイルからの相対パスを計算して生成

### Step 4: SmartPasteService に `.image` ケース追加

`ClipboardContentType` に `.image(NSImage)` を追加。`detectContentType()` で画像を検出。

検出条件: NSPasteboard に `.tiff` / `.png` タイプがあり、かつ有意な文字列コンテンツがない場合（純粋な画像ペースト）。

### Step 5: MarkdownTextView に画像ペースト処理追加

- `noteURL: URL?` と `attachmentsDir: URL?` プロパティ追加
- `paste(_:)` をオーバーライドし、画像データ検出時に `ImagePasteService` を呼び出し
- 既存の `insertSmartPasteText()` (`MarkdownTextView.swift:453`) で markdown を挿入
- `performSmartPaste()` (`MarkdownTextView.swift:409`) でも `.image` ケースをハンドル

### Step 6: LivePreviewEditor に noteURL / attachmentsDir を通す

- `LivePreviewEditor` に `noteURL: URL?` と `attachmentsDir: URL?` パラメータ追加
- `makeNSView` / `updateNSView` で `textView.noteURL` / `textView.attachmentsDir` に設定

### Step 7: NoteContentView から値を渡す

- `NoteWindow.swift` の `LivePreviewEditor(...)` 呼び出し (`NoteWindow.swift:524`) に追加

### Step 8: 相対パス解決（画像レンダリング）

- `MarkdownStyler` (`MarkdownStyler.swift:16`) に `noteBaseURL: URL?` プロパティ追加
- `MarkdownStyler+Inline.swift` の `applyImagePattern()` (`MarkdownStyler+Inline.swift:188`) で相対パスを絶対パスに解決
- `LivePreviewEditor.applyStyling()` (`LivePreviewEditor.swift:251`) で `styler.noteBaseURL` を設定

## 再利用する既存コード

- `ImageCache` (`Chirami/Editor/ImageCache.swift`) — ローカルファイルパスからの画像読み込み・キャッシュ
- `BulletLayoutManager` — `.imageIcon` 属性による画像描画
- `MarkdownStyler+Inline.swift` の画像パターン正規表現 (`imagePattern`)
- `insertSmartPasteText()` (`MarkdownTextView.swift:453`) — テキスト挿入パイプライン
- `CryptoKit` / `SHA256` (`ConfigModels.swift:2,148`) — ハッシュ生成パターン

## スコープ外（将来対応）

- 孤立画像のクリーンアップ
- Retina 画像の自動リサイズ
- ドラッグ&ドロップによる画像追加

## 検証方法

1. アプリをビルド・起動
2. スクリーンショットをクリップボードにコピー (Cmd+Shift+4 → Ctrl+C)
3. 付箋上で Cmd+V → 設定した保存先に PNG が保存されることを確認
4. markdown に `![](relative/path/image-xxxx.png)` が挿入されることを確認
5. カーソルを画像行から離すと、画像がインラインレンダリングされることを確認
6. 同じ画像を再度ペーストして、ファイルが重複作成されないことを確認
7. `config.yaml` で `attachments_dir` を変更し、保存先が変わることを確認
8. Periodic note でもパスが正しく解決されることを確認

## Requirements

### Requirement 1: クリップボードからの画像ペースト

**Objective:** ユーザーとして、クリップボードの画像を付箋に Cmd+V でペーストしたい。スクリーンショットや他アプリからコピーした画像を素早くノートに貼り付けられるようにするため。

#### Acceptance Criteria

1. When ユーザーが画像データを含むクリップボードの状態で Cmd+V を押した場合, the Chirami shall クリップボードの画像を検出し、画像ペースト処理を開始する
2. When クリップボードに `.tiff` または `.png` タイプの画像データが存在し、かつ有意なテキストコンテンツがない場合, the Chirami shall 画像ペーストとして処理する（テキストペーストではなく）
3. When クリップボードにテキストと画像の両方が存在する場合, the Chirami shall テキストペースト（既存の Smart Paste）を優先する

### Requirement 2: 画像ファイルの保存

**Objective:** ユーザーとして、ペーストした画像が PNG ファイルとして自動的に保存されてほしい。画像データが永続化され、ノートを再度開いた際にも画像が表示されるようにするため。

#### Acceptance Criteria

1. When 画像がペーストされた場合, the Chirami shall 画像を PNG 形式でファイルとして保存する
2. The Chirami shall 保存するファイル名を `image-<SHA256ハッシュプレフィックス>.png` の形式で生成する
3. When 同じ画像コンテンツが再度ペーストされた場合, the Chirami shall 既存のファイルを再利用し、重複ファイルを作成しない
4. When 保存先ディレクトリが存在しない場合, the Chirami shall ディレクトリを自動的に作成する

### Requirement 3: Markdown テキストの挿入

**Objective:** ユーザーとして、画像ペースト時にノートのカーソル位置に Markdown 画像構文が自動挿入されてほしい。既存の Markdown レンダリングパイプラインでそのまま画像が表示されるようにするため。

#### Acceptance Criteria

1. When 画像ファイルの保存が完了した場合, the Chirami shall カーソル位置に `![](相対パス/image-xxxx.png)` 形式の Markdown 画像構文を挿入する
2. The Chirami shall 挿入する画像パスをノートファイルからの相対パスとして計算する
3. When 画像構文が挿入された場合, the Chirami shall 既存の Markdown レンダリングパイプライン（ImageCache + BulletLayoutManager）により画像をインライン表示する

### Requirement 4: 添付ファイル保存ディレクトリの設定

**Objective:** ユーザーとして、画像の保存先ディレクトリを設定で変更したい。プロジェクトやノートの運用方針に合わせて保存先を柔軟に管理できるようにするため。

#### Acceptance Criteria

1. The Chirami shall `config.yaml` の `defaults.attachments_dir` でグローバルデフォルトの保存先を設定可能にする
2. The Chirami shall ノートごとの設定（`notes[].attachments_dir`）でノート固有の保存先を設定可能にする
3. While ノートごとの `attachments_dir` が設定されている場合, the Chirami shall グローバルデフォルトよりノートごとの設定を優先する
4. While 通常ノートで `attachments_dir` がどこにも設定されていない場合, the Chirami shall `<ノートファイル名(拡張子なし)>.attachments/` をデフォルトの保存先として使用する
5. While periodic note で `attachments_dir` がどこにも設定されていない場合, the Chirami shall テンプレートパスの親ディレクトリ直下の `attachments/` を共有の保存先として使用する（例: `~/notes/daily/{yyyy-MM-dd}.md` → `~/notes/daily/attachments/`）
6. When 相対パスが指定された場合, the Chirami shall ノートファイルの親ディレクトリからの相対パスとして解決する
7. When 絶対パス（`/` または `~/` で始まる）が指定された場合, the Chirami shall そのパスをそのまま使用する（`~` はホームディレクトリに展開）

### Requirement 5: 相対パスによる画像レンダリング

**Objective:** ユーザーとして、ノート内の相対パスで指定された画像が正しくレンダリングされてほしい。ペーストした画像がエディタ上で即座にプレビュー表示されるようにするため。

#### Acceptance Criteria

1. When Markdown テキスト内に相対パスの画像参照（`![](relative/path.png)`）がある場合, the Chirami shall ノートファイルの位置を基準に相対パスを絶対パスに解決して画像を表示する
2. When カーソルが画像行から離れた場合, the Chirami shall 画像をインラインレンダリングして表示する（Live Preview 動作）
