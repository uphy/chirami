# Requirements Document

## Introduction

Fusen は固定パスの `.md` ファイルを付箋として表示する macOS アプリである。現状では config.yaml にファイルパスを直接指定するため、日記や週次振り返りのような定期ノートを扱うには手動でパスを更新する必要がある。

Periodic Note 機能を導入し、日付テンプレートからパスを自動解決することで、daily/weekly/monthly の定期ノートをシームレスに扱えるようにする。タイトルバーにナビゲーション UI を配置し、前後の期間に移動可能にする。

## Requirements

### Requirement 1: Periodic Note 設定

**Objective:** ユーザーとして、config.yaml で定期ノートを宣言的に設定したい。手動でパスを更新せずに日付ベースのノートを利用できるようにするため。

#### Acceptance Criteria

1. The Fusen shall `period` フィールド (`daily`, `weekly`, `monthly`) をノート設定でサポートする
2. When `period` フィールドが指定されたとき, the Fusen shall `path` をテンプレート文字列として扱い、`{...}` 内を `DateFormatter` フォーマット文字列として解釈する
3. When `period` フィールドが省略されたとき, the Fusen shall 従来どおり `path` を静的ファイルパスとして扱う（後方互換）
4. The Fusen shall 複数の `{...}` プレースホルダーを含むパステンプレートを解決できる（例: `~/notes/{yyyy}/{MM}/{dd}.md`）
5. The Fusen shall ノートの ID を path（periodic note の場合はテンプレート文字列）の SHA256 先頭6文字から自動導出する

### Requirement 2: パス解決とファイル管理

**Objective:** ユーザーとして、アプリ起動時に現在の期間に対応するノートファイルが自動的に用意されてほしい。手動でファイルを作成する手間を省くため。

#### Acceptance Criteria

1. When Fusen が起動したとき, the Fusen shall 現在日時でテンプレートを解決し、対応するパスのノートを表示する
2. When 解決されたパスにファイルが存在しないとき, the Fusen shall 空のファイルを自動作成する
3. When 解決されたパスの親ディレクトリが存在しないとき, the Fusen shall 親ディレクトリを自動作成する
4. The Fusen shall periodic note では security-scoped bookmark による永続的ファイルアクセスをスキップする

### Requirement 3: タイトル表示

**Objective:** ユーザーとして、ウィンドウタイトルからどの期間のノートを表示しているか一目で分かるようにしたい。

#### Acceptance Criteria

1. While periodic note が表示されているとき, the Fusen shall タイトルを「設定タイトル — 日付文字列」の形式で表示する（例: `Daily Note — 2026-02-23`）
2. The Fusen shall 期間種別に応じた日付フォーマットを使用する（daily: `yyyy-MM-dd`, weekly: `yyyy-'W'ww`, monthly: `yyyy-MM`）
3. While 静的ノートが表示されているとき, the Fusen shall 従来どおりのタイトル表示を維持する

### Requirement 4: 期間ナビゲーション

**Objective:** ユーザーとして、タイトルバーのボタンで前後の期間に移動したい。過去のノートを参照したり、先の期間のノートを準備できるようにするため。

#### Acceptance Criteria

1. While periodic note が表示されているとき, the Fusen shall タイトルバーに前の期間 (◀)、次の期間 (▶) のナビゲーションボタンを表示する
2. When 前の期間ボタンがクリックされたとき, the Fusen shall 1つ前の期間のノートに切り替える
3. When 次の期間ボタンがクリックされたとき, the Fusen shall 1つ次の期間のノートに切り替える
4. When 期間を移動したとき, the Fusen shall ファイル内容、タイトル、ファイル監視を新しいノートに切り替える
5. While 静的ノートが表示されているとき, the Fusen shall ナビゲーションボタンを非表示にする

### Requirement 5: Today ボタン

**Objective:** ユーザーとして、過去や未来の期間にナビゲートした後、ワンクリックで現在の期間に戻りたい。

#### Acceptance Criteria

1. While 現在の期間以外が表示されているとき, the Fusen shall Today ボタン (●) を表示する
2. When Today ボタンがクリックされたとき, the Fusen shall 現在の期間のノートに切り替える
3. While 現在の期間が表示されているとき, the Fusen shall Today ボタンを非表示にする

### Requirement 6: 期間ロールオーバー

**Objective:** ユーザーとして、日付が変わったときにノートが自動的に新しい期間に切り替わってほしい。手動更新やアプリ再起動を不要にするため。

#### Acceptance Criteria

1. When 現在の期間が終了したとき, the Fusen shall 次の期間のノートへ自動的にロールオーバーする
2. While ユーザーが現在の期間を表示しているとき, when ロールオーバーが発生したとき, the Fusen shall 新しい期間のノートに自動的に切り替える
3. While ユーザーが過去または未来の期間にナビゲートしているとき, when ロールオーバーが発生したとき, the Fusen shall 現在の表示を維持する（自動切り替えしない）
4. When macOS がスリープから復帰したとき, the Fusen shall 期間終了時刻を過ぎていればロールオーバーを実行する

### Requirement 7: ウィンドウ状態の保持

**Objective:** ユーザーとして、periodic note のウィンドウ位置・サイズが再起動後も保持されてほしい。毎回レイアウトし直す手間を省くため。

#### Acceptance Criteria

1. The Fusen shall periodic note のウィンドウ位置・サイズを再起動後も保持する
2. The Fusen shall ナビゲーション状態（表示中の期間）は永続化しない（再起動時は常に現在の期間を表示する）
