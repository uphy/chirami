# Gap Analysis: transient-window

## 要件とアセットのマッピング

### Requirement 1: カーソル追従ウィンドウ表示

| 技術要件 | 既存アセット | ギャップ |
|---------|------------|---------|
| マウスカーソル位置の取得 | なし | **Missing** — `NSEvent.mouseLocation` を使用する必要がある |
| カーソル位置へのウィンドウ配置 | `NoteWindowController.init` で `savedState?.cgPoint` を使用 (`NoteWindow.swift:126-129`) | **Missing** — ホットキー押下時にカーソル位置を動的に取得・設定するロジックが必要 |
| 画面端補正 | なし | **Missing** — `NSScreen.screens` を用いた画面境界クランプロジックが必要 |
| マルチディスプレイ対応 | なし | **Missing** — カーソルが存在するスクリーンの特定と、そのスクリーンの `visibleFrame` への制限が必要 |

### Requirement 2: 自動非表示（Auto Hide）

| 技術要件 | 既存アセット | ギャップ |
|---------|------------|---------|
| フォーカス離脱検知 | `NSWindowDelegate` が `NoteWindowController` に実装済み (`NoteWindow.swift:112`) | **Missing** — `windowDidResignKey` デリゲートメソッドが未実装 |
| 自動非表示 | `NoteWindowController.hide()` が存在 (`NoteWindow.swift:192-195`) | **Constraint** — `hide()` を呼ぶだけだが、呼び出しタイミングの制御が必要 |
| 非表示時の自動保存 | `NoteContentModel.save()` が存在 (`NoteWindow.swift:283-289`) | **Constraint** — `hide()` 呼び出し前に `save()` を確実に実行する連携が必要 |
| ホットキー優先制御 | `NoteWindowController.toggle()` が存在 (`NoteWindow.swift:197-199`) | **Missing** — ホットキーによるトグルとauto-hideの競合回避フラグが必要 |

### Requirement 3: 設定ファイル拡張

| 技術要件 | 既存アセット | ギャップ |
|---------|------------|---------|
| `position` フィールド | `NoteConfig` に存在しない (`ConfigModels.swift:11-35`) | **Missing** — `position: String?` フィールドと `CodingKeys` の追加 |
| `auto_hide` フィールド | `NoteConfig` に存在しない | **Missing** — `autoHide: Bool?` フィールドと `CodingKeys` (`auto_hide`) の追加 |
| ホットリロード | `AppConfig.$data` の変更を `NoteStore` が購読済み (`NoteStore.swift:19-23`) | 既存の仕組みで対応可能 |

### Requirement 4: 状態管理

| 技術要件 | 既存アセット | ギャップ |
|---------|------------|---------|
| 位置の永続化スキップ | `NoteWindowController.saveWindowState()` で毎回位置を保存 (`NoteWindow.swift:232-239`) | **Missing** — `position: cursor` のノートでは位置保存をスキップする条件分岐が必要 |
| サイズのみ永続化 | `WindowState` は position と size をセットで保存 (`ConfigModels.swift:44-64`) | **Constraint** — 位置をスキップしつつサイズだけ保存する仕組みが必要 |
| 起動時デフォルト非表示 | `NoteWindowController.showIfNeeded()` が `isVisible` を参照 (`NoteWindow.swift:180-185`) | **Constraint** — transientノートの初回起動時は `visible: false` を強制する必要がある |

### Requirement 5: 既存機能との互換性

| 技術要件 | 既存アセット | ギャップ |
|---------|------------|---------|
| 従来動作の維持 | 全既存コードが `position`/`auto_hide` 未設定を想定 | ギャップなし — 新フィールドはOptionalで追加 |
| 全体トグルからの除外 | `WindowManager.toggleAllWindows()` が全ウィンドウ対象 (`WindowManager.swift:31-42`) | **Missing** — `auto_hide` ノートを除外するフィルタリングが必要 |
| メニューバー表示 | `NoteListView` がノート一覧を表示 | ギャップなし — 既存のリスト表示で対応可能 |

## 既存アーキテクチャの規約

- **レイヤー構造**: Config → Models → Services → Views の依存方向
- **シングルトンパターン**: `NoteStore.shared`, `WindowManager.shared`, `AppConfig.shared`
- **Combine購読**: 設定変更の伝播に `$data` / `$notes` の `Publisher` を使用
- **命名規約**: config.yamlは `snake_case`、Swiftは `camelCase`、`CodingKeys` でマッピング
- **状態分離**: ユーザー設定 (`config.yaml`) とランタイム状態 (`state.yaml`) を明確に分離

## 実装アプローチの選択肢

### Option A: 既存コンポーネントの拡張

変更対象ファイル:

- `ConfigModels.swift` — `NoteConfig` に `position: String?`, `autoHide: Bool?` を追加
- `Note.swift` — `Note` struct に `position: NotePosition`, `autoHide: Bool` を追加
- `NoteStore.swift` — `loadFromConfig()` で新フィールドをマッピング、`saveWindowState()` に条件分岐を追加
- `NoteWindow.swift` — `NoteWindowController` に `windowDidResignKey` 実装、カーソル位置配置ロジック追加
- `WindowManager.swift` — `toggleAllWindows()` に除外フィルタ、`toggleWindow()` にカーソル位置対応
- `FusenApp.swift` — ホットキーコールバックでカーソル位置を渡す仕組みの追加

**Trade-offs:**
- ✅ 既存パターンに沿った自然な拡張、新ファイル不要
- ✅ ホットリロードが既存の仕組みで動作
- ❌ `NoteWindowController` の責務が増える（カーソル配置 + auto-hide管理）

### Option B: 新コンポーネントの作成

新規ファイル:

- `TransientWindowBehavior.swift` — カーソル位置計算、画面境界クランプ、auto-hide制御を独立クラスに
- `ScreenUtilities.swift` — マルチディスプレイ対応のユーティリティ

**Trade-offs:**
- ✅ 責務分離が明確
- ❌ 現時点では過剰な抽象化（ロジックは比較的シンプル）
- ❌ 既存の `NoteWindowController` との連携で間接参照が増える

### Option C: ハイブリッド（推奨）

既存モデル・設定を拡張しつつ、ウィンドウ配置計算のみヘルパーとして切り出す:

- 既存ファイル拡張: `ConfigModels.swift`, `Note.swift`, `NoteStore.swift`, `NoteWindow.swift`, `WindowManager.swift`, `FusenApp.swift`
- カーソル位置計算・画面クランプロジックは `NoteWindowController` のprivateメソッドまたはextensionとして実装

**Trade-offs:**
- ✅ 新ファイルを作らず既存パターンに忠実
- ✅ ロジックが小さいのでextensionで十分
- ✅ テスト時にカーソル位置のモック化は考慮不要（UIテストレベルの話）

## 複雑度とリスク

- **Effort: S (1-3日)** — 変更箇所は明確で、既存パターンの拡張が中心。macOS APIの使用も標準的。
- **Risk: Low** — 既知のmacOS API (`NSEvent.mouseLocation`, `NSScreen`, `windowDidResignKey`) の使用のみ。新フィールドはOptionalで既存動作への影響なし。

## 設計フェーズへの推奨事項

**推奨アプローチ:** Option C（ハイブリッド）

- 既存の6ファイルを拡張し、新ファイルの作成は不要
- `NotePosition` enumの導入（`.fixed` / `.cursor`）で型安全性を確保

**Research Needed:**
- `NSEvent.mouseLocation` のグローバルホットキーコールバック内での精度検証（HotKeyライブラリのコールバック時点でのマウス位置が正確かどうか）
- `windowDidResignKey` が `NSPanel` (`.nonactivatingPanel`) で期待通りに発火するかの確認 — `NSPanel` の `becomesKeyOnlyIfNeeded` 挙動に注意
