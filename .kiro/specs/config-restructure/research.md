# Research & Design Decisions

## Summary

- **Feature**: `config-restructure`
- **Discovery Scope**: Extension（既存の設定システムへの `defaults:` セクション追加）
- **Key Findings**:
  - 変更対象は3ファイルのみ（`ConfigModels.swift`, `NoteStore.swift`, `AppConfig.swift`）
  - デフォルト値のハードコードは `NoteStore.loadFromConfig()` の1箇所に集中
  - Yams の `Codable` 準拠により、Optional フィールド追加は後方互換

## Research Log

### Yams の Optional フィールド後方互換性

- **Context**: `defaults:` セクションを `ChiramiConfig` に追加する際、既存 config.yaml との互換性を確認
- **Findings**:
  - Yams の `YAMLDecoder` は `Codable` の標準動作に従い、Optional フィールドが YAML に存在しない場合は `nil` をセットする
  - 既存の `ChiramiConfig` でも `hotkey: String?` や `karabiner: KarabinerConfig?` が同じパターンで動作済み
- **Implications**: `defaults: NoteDefaults?` を追加しても、既存 config.yaml はそのまま読み込み可能

### デフォルト値のハードコード箇所

- **Context**: 現在のデフォルト値がどこで適用されているか特定
- **Findings**:
  - `NoteStore.loadFromConfig()` 内の3行:
    - `color`: `.yellow`（39行目）
    - `transparency`: `0.9`（41行目）
    - `fontSize`: `14`（42行目）
  - `alwaysOnTop` のデフォルト `true` は state 由来（44行目）で、外観設定ではないため対象外
- **Implications**: `NoteStore` の `??` 演算子チェーンを拡張し、`noteConfig.color ?? defaults.color ?? .yellow` の3段階にすれば実現できる

### smartPaste フィールドの存在

- **Context**: `docs/config.md` に記載のない `smartPaste` フィールドが `ChiramiConfig` に存在
- **Findings**:
  - `ChiramiConfig` は `hotkey`, `notes`, `karabiner`, `smartPaste` の4フィールドを持つ
  - `docs/config.md` の推奨構造には `smartPaste` が記載されていない
- **Implications**: design.md では `smartPaste` を含む現状の `ChiramiConfig` を正確に反映する

## Design Decisions

### Decision: defaults の解決をどこで行うか

- **Context**: defaults → 個別指定の解決ロジックの配置場所
- **Alternatives Considered**:
  1. `NoteConfig` に解決メソッドを追加（`func resolved(with defaults: NoteDefaults?) -> ResolvedNote`）
  2. `NoteStore.loadFromConfig()` 内で直接解決
  3. `AppConfig` にヘルパーメソッドを追加
- **Selected Approach**: Option 2 — `NoteStore.loadFromConfig()` 内で直接解決
- **Rationale**: 現在のデフォルト値解決が既に `NoteStore.loadFromConfig()` にあるため、同じ場所で拡張するのが最も自然。変更差分が最小限で済む
- **Trade-offs**: `NoteStore` に解決ロジックが残り続けるが、3フィールドのみなので複雑性は低い

## Risks & Mitigations

- config.yaml の `defaults:` に無効な `color` 値が書かれた場合 → 既存の `NoteColor(rawValue:)` の nil チェックでフォールバックされるため問題なし
