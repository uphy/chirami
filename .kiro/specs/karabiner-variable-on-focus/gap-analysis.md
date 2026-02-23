# Gap Analysis: karabiner-variable-on-focus

## 要件と既存資産のマッピング

| 要件 | 既存資産 | ギャップ |
|------|----------|----------|
| Req 1: フォーカス時の変数設定 | `NotePanel.becomeKey()` が存在。`LivePreviewEditor` が `didBecomeKeyNotification` / `didResignKeyNotification` を監視 | `resignKey()` 未実装。フォーカスイベントを外部に伝搬する仕組みがない |
| Req 2: config.yaml でのカスタマイズ | `ChiramiConfig` / `NoteConfig` の Codable 構造体。`YAMLStore` による YAML 読み書き + FileWatcher による自動リロード | Karabiner 関連の設定フィールドが未定義 |
| Req 3: karabiner_cli 連携 | なし (外部プロセス実行のコードが一切存在しない) | `Process` クラスによる CLI 実行パターンを新規導入する必要あり |

## 既存コードベースの調査結果

### フォーカスイベント処理

- `NotePanel` (`Chirami/Views/NoteWindow.swift`) — `becomeKey()` をオーバーライドし、`MarkdownTextView` にフォーカスを移動。`resignKey()` は未実装
- `NoteWindowController` — `NSWindowDelegate` を実装済み (`windowWillClose`, `windowDidMove`, `windowDidResize`)。`windowDidBecomeKey` / `windowDidResignKey` は未実装
- `LivePreviewEditor` — `NSWindow.didBecomeKeyNotification` / `didResignKeyNotification` を NotificationCenter 経由で監視。スタイリング目的のみ

### 設定システム

- `ChiramiConfig` (`Chirami/Config/ConfigModels.swift`) — トップレベル設定。`hotkey` と `notes` のみ
- `NoteConfig` — ノート単位設定。`CodingKeys` で snake_case マッピング
- `YAMLStore<T>` — Codable + Yams + FileWatcher による汎用 YAML ストア
- `AppConfig` (`Chirami/Config/AppConfig.swift`) — `YAMLStore<ChiramiConfig>` のシングルトン

### サービス層パターン

- `@MainActor` + `static let shared` シングルトンパターン (`WindowManager`)
- `AppDelegate` でサービスをインスタンス変数として保持・初期化
- Combine (`@Published`, `AnyCancellable`) によるリアクティブ更新

### 外部プロセス実行

- 既存コードベースに `Process`, `NSTask`, シェル実行のコードは一切なし
- `karabiner_cli` のパス: `/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli`
- コマンド: `karabiner_cli --set-variables '{"variable_name": value}'`

## 実装アプローチの選択肢

### Option A: NoteWindowController を拡張

`NoteWindowController` の `NSWindowDelegate` に `windowDidBecomeKey` / `windowDidResignKey` を追加し、直接 `karabiner_cli` を呼び出す。

**Trade-offs:**
- ✅ 変更ファイル数が最小 (2-3 ファイル)
- ❌ NoteWindowController が外部プロセス実行の責務を持つ (責務違反)
- ❌ 「すべてのウィンドウからフォーカスが外れた」判定ロジックが NoteWindowController に混在

### Option B: 新規 KarabinerService を作成

新しいサービスを作成し、ウィンドウフォーカスイベントの集約と `karabiner_cli` 実行を担当させる。

**Trade-offs:**
- ✅ 責務の分離が明確 (既存サービス層のパターンに整合)
- ✅ テスト容易性が高い
- ✅ 「全ウィンドウのフォーカス状態」を一元管理できる
- ❌ 新規ファイル追加

### Option C: ハイブリッド

NoteWindowController にデリゲートメソッドを追加し、通知を WindowManager 経由で KarabinerService に伝搬。

**Trade-offs:**
- ✅ フォーカスイベント検知は NoteWindowController (自然な場所)
- ✅ 集約ロジックは WindowManager (既に window を管理)
- ✅ CLI 実行は KarabinerService (単一責務)
- ❌ 伝搬経路がやや長い

## 複雑度・リスク評価

- **Effort: S** — 既存パターン (Codable, @MainActor singleton, NSWindowDelegate) をそのまま踏襲。Foundation.Process は標準 API。
- **Risk: Low** — 使用技術はすべて既知。`karabiner_cli` の API は安定。Chirami のコア機能に影響しない独立した追加機能。

## 設計フェーズへの推奨事項

**推奨アプローチ: Option B (新規 KarabinerService)**

- 既存サービス (`GlobalHotkeyService`, `WindowManager`) と同じパターンで自然に統合できる
- 全ウィンドウのフォーカス状態を一元管理する必要があるため、専用サービスが適切
- `NoteWindowController` には `windowDidBecomeKey` / `windowDidResignKey` のデリゲート追加のみ

**設計フェーズでの検討事項:**

- フォーカスイベントの伝搬方法 (NotificationCenter vs コールバック vs Combine)
- 「すべてのウィンドウからフォーカスが外れた」の判定タイミング (即時 vs debounce)
- `karabiner_cli` 実行のスレッディング (メインスレッドブロック回避)
- config.yaml のスキーマ設計 (トップレベル vs ネスト構造)
