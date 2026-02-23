# Requirements Document

## Introduction

Chirami は固定パスの `.md` ファイルを付箋として表示する macOS アプリである。現状では config.yaml にファイルパスを直接指定するため、日記や週次振り返りのような定期ノートを扱うには手動でパスを更新する必要がある。

Periodic Note 機能を導入し、`path` 内の `{...}` 日付テンプレートからパスを自動解決することで、定期ノートをシームレスに扱えるようにする。ナビゲーションはテンプレートにマッチする既存ファイルのソートに基づき、`period` フィールドは不要とする。

## Requirements

### Requirement 1: Periodic Note 設定

**Objective:** ユーザーとして、config.yaml で定期ノートを宣言的に設定したい。手動でパスを更新せずに日付ベースのノートを利用できるようにするため。

#### Acceptance Criteria

1. When `path` に `{...}` プレースホルダーが含まれるとき, the Chirami shall そのノートを periodic note として扱い、`{...}` 内を `DateFormatter` フォーマット文字列として解釈する
2. When `path` に `{...}` プレースホルダーが含まれないとき, the Chirami shall 従来どおり静的ファイルパスとして扱う（後方互換）
3. The Chirami shall 複数の `{...}` プレースホルダーを含むパステンプレートを解決できる（例: `~/notes/{yyyy}/{MM}/{dd}.md`）
4. The Chirami shall ノートの ID を path（periodic note の場合はテンプレート文字列）の SHA256 先頭6文字から自動導出する
5. The Chirami shall periodic note に `rollover_delay` フィールド（例: `2h`, `30m`）をオプションで指定できる。デフォルトは `0`（遅延なし）
6. The Chirami shall periodic note に `template` フィールド（ファイルパス）をオプションで指定できる。新規ファイル作成時のテンプレートとして使用する

### Requirement 2: パス解決とファイル管理

**Objective:** ユーザーとして、アプリ起動時に現在の日付に対応するノートファイルが自動的に用意されてほしい。手動でファイルを作成する手間を省くため。

#### Acceptance Criteria

1. When Chirami が起動したとき, the Chirami shall 現在日時から `rollover_delay` を差し引いた「論理日時」でテンプレートを解決し、対応するパスのノートを表示する
2. When 解決されたパスにファイルが存在しないとき and `template` が指定されているとき, the Chirami shall テンプレートファイルの内容をコピーして新規ファイルを作成する
3. When 解決されたパスにファイルが存在しないとき and `template` が指定されていないとき, the Chirami shall 空のファイルを自動作成する
4. When 解決されたパスの親ディレクトリが存在しないとき, the Chirami shall 親ディレクトリを自動作成する
5. The Chirami shall periodic note では security-scoped bookmark による永続的ファイルアクセスをスキップする

### Requirement 3: タイトル表示

**Objective:** ユーザーとして、ウィンドウタイトルからどのノートを表示しているか一目で分かるようにしたい。

#### Acceptance Criteria

1. While periodic note が表示されているとき, the Chirami shall タイトルを「設定タイトル — テンプレート解決済みファイル名」の形式で表示する（例: `Daily Note — 2026-02-23`）
2. While 静的ノートが表示されているとき, the Chirami shall 従来どおりのタイトル表示を維持する

### Requirement 4: ファイルナビゲーション

**Objective:** ユーザーとして、タイトルバーのボタンで前後のノートに移動したい。過去のノートを参照できるようにするため。

#### Acceptance Criteria

1. While periodic note が表示されているとき, the Chirami shall タイトルバーに前 (◀) と次 (▶) のナビゲーションボタンを表示する
2. The Chirami shall テンプレートの `{...}` を `*` に変換した glob パターンでマッチするファイルを検索し、テンプレートのフォーマットで parse 可能なファイルのみを対象とする
3. When ◀ ボタンがクリックされたとき, the Chirami shall ソート順で1つ前の既存ファイルに切り替える
4. When ▶ ボタンがクリックされたとき, the Chirami shall ソート順で1つ次の既存ファイルに切り替える
5. When 前後にファイルが存在しないとき, the Chirami shall 対応するナビゲーションボタンを無効化する
6. When ナビゲーションでファイルを切り替えたとき, the Chirami shall ファイル内容、タイトル、ファイル監視を新しいノートに切り替える
7. While 静的ノートが表示されているとき, the Chirami shall ナビゲーションボタンを非表示にする

### Requirement 5: Today ボタン

**Objective:** ユーザーとして、過去のノートにナビゲートした後、ワンクリックで今日のノートに戻りたい。

#### Acceptance Criteria

1. While 論理日時のテンプレート解決結果と異なるファイルが表示されているとき, the Chirami shall Today ボタン (●) を表示する
2. When Today ボタンがクリックされたとき, the Chirami shall 論理日時でテンプレートを再解決し、対応するノートに切り替える
3. While 論理日時のテンプレート解決結果と一致するファイルが表示されているとき, the Chirami shall Today ボタンを非表示にする

### Requirement 6: ロールオーバー

**Objective:** ユーザーとして、テンプレートの解決結果が変わったときにノートが自動的に切り替わってほしい。手動更新やアプリ再起動を不要にするため。

#### Acceptance Criteria

1. The Chirami shall テンプレートを論理日時（現在日時 − `rollover_delay`）で定期的に再評価し、解決結果が現在表示中のパスと異なった場合にロールオーバーを検出する
2. Where `rollover_delay` が指定されているとき, the Chirami shall ロールオーバーを `rollover_delay` 分だけ遅延させる（例: `2h` の場合、日付変更から2時間後にロールオーバーする）
3. While ユーザーが論理日時のノートを表示しているとき, when ロールオーバーが検出されたとき, the Chirami shall 新しい解決結果のノートに自動的に切り替える
4. While ユーザーが別のノートにナビゲートしているとき, when ロールオーバーが検出されたとき, the Chirami shall 現在の表示を維持する（自動切り替えしない）

### Requirement 7: ウィンドウ状態の保持

**Objective:** ユーザーとして、periodic note のウィンドウ位置・サイズが再起動後も保持されてほしい。毎回レイアウトし直す手間を省くため。

#### Acceptance Criteria

1. The Chirami shall periodic note のウィンドウ位置・サイズを再起動後も保持する
2. The Chirami shall ナビゲーション状態（表示中のファイル）は永続化しない（再起動時は常に論理日時でテンプレートを解決する）
