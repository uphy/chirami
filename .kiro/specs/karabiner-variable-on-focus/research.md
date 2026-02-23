# Research & Design Decisions

## Summary

- **Feature**: `karabiner-variable-on-focus`
- **Discovery Scope**: Extension
- **Key Findings**:
  - `karabiner_cli --set-variables` は JSON 文字列で変数を設定する。パスは `/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli`
  - 既存コードベースに外部プロセス実行のパターンがなく、Foundation `Process` を新規導入する必要がある
  - フォーカスイベントは `NSWindow.didBecomeKeyNotification` / `didResignKeyNotification` で検知可能 (LivePreviewEditor に実例あり)

## Research Log

### karabiner_cli の使用方法

- **Context**: Karabiner-Elements 変数を外部から設定する方法の調査
- **Sources Consulted**: [Karabiner-Elements CLI Documentation](https://karabiner-elements.pqrs.org/docs/manual/misc/command-line-interface/)
- **Findings**:
  - CLI パス: `/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli`
  - コマンド: `karabiner_cli --set-variables '{"key": value}'`
  - 値は number / boolean / string を受け付ける
  - 複数変数を一度に設定可能
- **Implications**: Foundation `Process` で実行可能。JSON 文字列の組み立てのみ必要

### フォーカスイベント検知パターン

- **Context**: Fusen ウィンドウのフォーカス状態変更を検知する方法
- **Sources Consulted**: 既存コードベース (LivePreviewEditor.swift, NoteWindow.swift)
- **Findings**:
  - `LivePreviewEditor` が `NSWindow.didBecomeKeyNotification` / `didResignKeyNotification` を NotificationCenter で監視済み
  - `NoteWindowController` は `NSWindowDelegate` を実装済みだが `windowDidBecomeKey` / `windowDidResignKey` は未使用
  - NSPanel は `nonactivatingPanel` スタイルだが `canBecomeKey = true` なので key window になれる
- **Implications**: NotificationCenter パターンが既存コードと一貫性があり、KarabinerService で全ウィンドウのフォーカスを一元監視できる

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| NoteWindowController 拡張 | デリゲートに直接 CLI 呼び出しを追加 | 変更最小 | 責務違反。全ウィンドウの集約が困難 | 不採用 |
| 新規 KarabinerService | 専用サービスで NotificationCenter 監視 + CLI 実行 | 既存パターンに整合。責務分離が明確 | 新規ファイル追加 | **採用** |
| WindowManager 拡張 | WindowManager にフォーカス追跡を追加 | 既にウィンドウを管理 | WindowManager の責務肥大化 | 不採用 |

## Design Decisions

### Decision: フォーカスイベント検知方式

- **Context**: どの仕組みでウィンドウフォーカスを検知するか
- **Alternatives Considered**:
  1. NSWindowDelegate (`windowDidBecomeKey` / `windowDidResignKey`) を NoteWindowController に追加
  2. NotificationCenter で `NSWindow.didBecomeKeyNotification` / `didResignKeyNotification` を監視
- **Selected Approach**: NotificationCenter 監視
- **Rationale**: KarabinerService が全ウィンドウのフォーカスを一元監視できる。NoteWindowController への変更が不要。LivePreviewEditor と同じパターン
- **Trade-offs**: NotePanel 以外のウィンドウの通知も受け取るため、フィルタリングが必要

### Decision: CLI 実行のスレッディング

- **Context**: `karabiner_cli` の実行がメインスレッドをブロックしないようにする
- **Selected Approach**: `Task.detached` でバックグラウンド実行
- **Rationale**: `Process` の実行は短時間だが、メインスレッドのブロックを回避するのが安全

### Decision: config.yaml スキーマ

- **Context**: Karabiner 連携設定をどのように構造化するか
- **Alternatives Considered**:
  1. `FusenConfig` のトップレベルにフラットに追加
  2. `karabiner` ネスト構造として追加
- **Selected Approach**: ネスト構造 (`karabiner` セクション)
- **Rationale**: 関連設定をグルーピングし、将来の拡張にも対応。YAML の可読性が高い
- **Follow-up**: `CodingKeys` は不要 (プロパティ名とキー名が一致)

## Risks & Mitigations

- `karabiner_cli` が未インストールの環境 — ファイル存在チェックで検知し、ログ出力のみで処理をスキップ
- フォーカスイベントの高頻度発火 — 同じ値の再設定はスキップする最適化を入れる

## References

- [Karabiner-Elements CLI Documentation](https://karabiner-elements.pqrs.org/docs/manual/misc/command-line-interface/) — `--set-variables` の公式ドキュメント
- [to.set_variable | Karabiner-Elements](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to/set-variable/) — `variable_if` / `variable_unless` 条件の仕様
