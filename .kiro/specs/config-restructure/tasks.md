# Implementation Plan

- [x] 1. NoteDefaults 構造体を追加し、FusenConfig に defaults フィールドを追加する
  - 外観設定（color, transparency, font_size）を保持する NoteDefaults 構造体を定義する。全フィールドを Optional にし、部分指定を許容する
  - title と hotkey はノート固有のフィールドであるため、NoteDefaults には含めない
  - FusenConfig に `defaults: NoteDefaults?` フィールドを追加する。CodingKeys にも追加する
  - YAML の snake_case（`font_size`）と Swift の camelCase（`fontSize`）の CodingKeys マッピングを設定する
  - 既存のルートレベルフィールド（hotkey, notes, karabiner, smartPaste）はそのまま維持する
  - _Requirements: 1.1, 1.2, 2.1, 2.2, 2.6, 3.1, 3.2, 3.3, 4.2_

- [x] 2. NoteStore のデフォルト値解決を3段階に拡張する
  - loadFromConfig() 内のデフォルト値解決を「ノート個別指定 → defaults → アプリ組込みデフォルト」の3段階に変更する
  - color の解決: `noteConfig.color` → `config.defaults?.color` → `"yellow"` の順で適用する
  - transparency の解決: `noteConfig.transparency` → `config.defaults?.transparency` → `0.9` の順で適用する
  - fontSize の解決: `noteConfig.fontSize` → `config.defaults?.fontSize` → `14` の順で適用する
  - defaults が nil の場合（既存の config.yaml）は従来と同じ挙動になることを確認する
  - _Requirements: 1.1, 2.3, 2.4, 2.5, 4.1_
