# Requirements Document

## Introduction

Fusen は NSPanel ベースのフローティングウィンドウアプリであり、フォーカスしても macOS の frontmost app が切り替わらない。Karabiner-Elements の `app_if` / `app_unless` 条件は frontmost app に基づいて動作するため、Fusen フォーカス時にユーザーが意図しないキーバインドが適用される問題がある。

この機能では、Fusen のフォーカス状態に連動して Karabiner-Elements の変数を設定することで、Karabiner-Elements 側の `variable_if` / `variable_unless` 条件と組み合わせたキーバインド制御を可能にする。変数名は他のフローティングアプリでも再利用できるよう汎用的に設計する。

## Requirements

### Requirement 1: フォーカス時の変数設定

**Objective:** ユーザーとして、Fusen にフォーカスしたときに Karabiner-Elements 変数が自動的に設定されることで、Fusen 用のキーバインドを正しく適用したい

#### Acceptance Criteria

1. When Fusen のウィンドウがフォーカスを受ける, the Fusen shall Karabiner-Elements の指定変数にフォーカス時の値を設定する
2. When Fusen のすべてのウィンドウからフォーカスが外れる, the Fusen shall Karabiner-Elements の指定変数にフォーカス解除時の値を設定する

### Requirement 2: 設定による変数名・値のカスタマイズ

**Objective:** ユーザーとして、設定ファイルで変数名と値をカスタマイズできることで、自身の Karabiner-Elements 設定に合わせた運用をしたい

#### Acceptance Criteria

1. The Fusen shall `config.yaml` で Karabiner-Elements 変数名を設定可能とする
2. The Fusen shall `config.yaml` でフォーカス時に設定する値を設定可能とする
3. The Fusen shall `config.yaml` でフォーカス解除時に設定する値を設定可能とする
4. If Karabiner-Elements 連携の設定が `config.yaml` に未定義の場合, the Fusen shall Karabiner-Elements 変数の設定処理を行わない (デフォルト無効)

### Requirement 3: Karabiner-Elements CLI 連携

**Objective:** ユーザーとして、Fusen が Karabiner-Elements の公式 CLI を利用して変数を設定することで、安定した連携を実現したい

#### Acceptance Criteria

1. The Fusen shall Karabiner-Elements の CLI (`karabiner_cli`) を使用して変数を設定する
2. If `karabiner_cli` が存在しない、または実行に失敗した場合, the Fusen shall エラーをログに記録し、アプリのクラッシュや動作停止を起こさない
