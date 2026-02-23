# Requirements Document

## Introduction

Fusen の設定ファイル構造を改善し、既存の config.yaml との後方互換性を維持しつつ、`defaults:` セクションを導入する。Periodic note の対応はこの spec のスコープ外。ルートレベル構造と path ベースのハッシュ ID は維持する。

詳細設計: `docs/config.md`

## Requirements

### Requirement 1: 後方互換性

**Objective:** ユーザーとして、既存の config.yaml を変更せずにアプリを使い続けたい。設定構造の改善がアップデート時の障壁にならないようにするため。

#### Acceptance Criteria

1. The Fusen shall `defaults:` セクションが存在しない config.yaml を従来通りロードし、アプリ組込みデフォルト値を適用する
2. The Fusen shall 未知のフィールドを無視し、エラーなくロードを完了する

### Requirement 2: defaults セクション

**Objective:** ユーザーとして、ノートの外観設定をまとめて指定したい。ノートごとに同じ設定を繰り返し書かなくて済むようにするため。

#### Acceptance Criteria

1. The Fusen shall config.yaml のルートレベルに `defaults:` セクションを受け付ける
2. The Fusen shall `defaults:` で `color`, `transparency`, `font_size` の3フィールドを設定可能にする
3. When ノートエントリに個別の外観指定がある場合、the Fusen shall `defaults:` の値を個別指定で上書きする
4. When ノートエントリに個別の外観指定がない場合、the Fusen shall `defaults:` の値を適用する
5. When `defaults:` にも個別指定にも値がない場合、the Fusen shall アプリ組込みデフォルト値（color: yellow, transparency: 0.9, fontSize: 14）を適用する
6. The Fusen shall `defaults:` の `color`, `transparency`, `font_size` をすべて省略可能にする（部分指定を許容する）

### Requirement 3: ルートレベル構造の維持

**Objective:** ユーザーとして、config.yaml のトップレベル構造が変わらないことを期待する。既存設定の構造を崩さず、差分を最小限にするため。

#### Acceptance Criteria

1. The Fusen shall `hotkey` をルートレベルのフィールドとして維持する
2. The Fusen shall `karabiner` をルートレベルのフィールドとして維持する
3. The Fusen shall `notes` をルートレベルのフィールドとして維持する

### Requirement 4: デフォルト値の解決順序

**Objective:** 開発者として、デフォルト値の解決ロジックが明確であること。設定の優先度が曖昧にならないようにするため。

#### Acceptance Criteria

1. The Fusen shall 外観設定を「アプリ組込みデフォルト → `defaults:` → 個別ノート指定」の3段階で解決する
2. The Fusen shall `title` と `hotkey` を `defaults:` の対象外とする（ノート固有のフィールドのため）
