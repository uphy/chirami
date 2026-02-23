# Research & Design Decisions

## Summary

- **Feature**: `periodic-note`
- **Discovery Scope**: Extension
- **Key Findings**:
  - 既存の `NoteConfig.noteId` は `SHA256(resolvedPath)` で導出 → periodic note ではテンプレート文字列から導出する必要がある
  - `Note.path` は既に `var` で mutable → ナビゲーション時のパス変更に対応可能
  - `WindowManager.controllers` は `noteId` をキーに管理 → 同一テンプレートの異なる日付ファイルは同一コントローラを再利用

## Research Log

### glob によるファイル検索と false positive 対策

- **Context**: テンプレートの `{...}` を `*` に変換して glob 検索する際、同一ディレクトリ内の無関係な `.md` ファイルがマッチする可能性
- **Sources Consulted**: FileManager API、Obsidian Periodic Notes プラグインの挙動
- **Findings**:
  - `FileManager.contentsOfDirectory(at:)` は単一ディレクトリのリストに適する
  - 複数階層テンプレート（`{yyyy}/{MM}/{dd}.md`）は glob が複雑になる
  - Obsidian Periodic Notes もファイルスキャン方式を採用（存在しない日はスキップ）
- **Implications**: glob 結果をテンプレートのフォーマットで re-parse してフィルタする必要がある。複数階層テンプレートはテンプレートの静的プレフィックス（`{` より前）をルートとして `FileManager.enumerator(at:)` で再帰列挙し、フィルタする方式で対応可能。実装コストは単一ディレクトリと大差ない

### rollover の polling vs 精密タイマー

- **Context**: `period` フィールドを廃止したため、期間境界を事前計算できない
- **Sources Consulted**: Apple Energy Efficiency Guide、NSTimer のスリープ復帰挙動
- **Findings**:
  - Apple は polling を非推奨としているが、60 秒間隔程度のデスクトップアプリなら実用上問題ない
  - `Timer` は fire date を過ぎていればスリープ復帰後に即座に発火する
  - テンプレートの再評価は `DateFormatter` + 文字列比較のみで軽量
- **Implications**: 60 秒間隔の polling で十分。将来的にフォーマット文字列から粒度を推論する最適化も可能だが、現時点では不要

### rollover_delay の duration パース

- **Context**: `2h`, `30m` のような人間可読な duration 文字列を `TimeInterval` に変換する必要がある
- **Findings**:
  - Swift 標準ライブラリに duration パーサーはない
  - 正規表現 `(\d+)(h|m)` で十分シンプルに実装可能
  - サポートする単位: `h`（時間）、`m`（分）
- **Implications**: 専用のユーティリティ関数として実装。外部ライブラリ不要

### 既存コードの拡張ポイント

- **Context**: 既存アーキテクチャへの統合方法
- **Findings**:
  - `NoteConfig` → `rolloverDelay` フィールド追加、`isPeriodicNote` computed property 追加
  - `Note` → `PeriodicNoteInfo` optional property 追加
  - `NoteStore.loadFromConfig()` → テンプレート検出・解決のロジック追加
  - `NotePanel.centerTitle()` → ナビゲーションボタンの追加
  - `NoteWindowController` → `displayDate` 状態とナビゲーションメソッド追加
  - `WindowManager.reloadWindows()` → rollover タイマーの管理追加

## Design Decisions

### Decision: テンプレート検出方式

- **Context**: periodic note を静的ノートと区別する方法
- **Alternatives Considered**:
  1. 正規表現 `\{[^}]+\}` で `{...}` を検出
  2. 専用の `type: periodic` フィールド追加
- **Selected Approach**: 正規表現による自動検出
- **Rationale**: config がシンプルになり、ユーザーが `period` や `type` を明示する必要がない
- **Trade-offs**: パスに literal `{` を含む場合は誤検出するが、実用上のリスクは極めて低い

### Decision: ナビゲーションはファイルソート方式

- **Context**: ◀/▶ ボタンの移動先決定方法
- **Alternatives Considered**:
  1. `period` による日付計算（+1 day, +1 week 等）
  2. 既存ファイルのソートによるナビゲーション
- **Selected Approach**: ファイルソート方式
- **Rationale**: `period` 不要でシンプル。Chirami は表示レイヤーに徹する設計思想と整合。Obsidian Periodic Notes も同様の方式
- **Trade-offs**: 未来のファイルへの ▶ ナビゲーション不可（許容）

### Decision: 論理日時による rollover_delay の実装

- **Context**: 深夜作業でのロールオーバー制御
- **Selected Approach**: `論理日時 = 現在日時 − rollover_delay` を全てのテンプレート解決で使用
- **Rationale**: テンプレート解決、Today 判定、ロールオーバー検出のすべてが同一の論理日時を参照するため一貫性が保たれる

## Risks & Mitigations

- **glob の false positive** — テンプレートフォーマットによる re-parse フィルタで対処
- **複数階層テンプレートの glob 複雑性** — `FileManager.enumerator(at:)` による再帰列挙 + `matches()` フィルタで対処。性能は daily 10年分（3,650 件）で問題ないレベル
- **polling のエネルギー消費** — 60 秒間隔で `DateFormatter` の文字列比較のみ。実測で無視できるレベル
- **security-scoped bookmark のスキップ** — periodic note のパスは `~/` 配下前提。sandbox 外のパスは静的ノートとして扱う
