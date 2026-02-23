# Requirements Document

## Introduction

Smart Paste は、Chirami のテキスト入力における摩擦を軽減するクリップボード自動整形機能である。`Cmd+Shift+V` でクリップボードの内容を検出し、コンテンツの種類に応じて適切な Markdown 形式に変換して挿入する。`Cmd+V` は従来通りのプレーンテキストペーストを維持する。

## Requirements

### Requirement 1: キーボードショートカット

**Objective:** ユーザーとして、通常ペーストとスマートペーストをキーボードショートカットで使い分けたい。意図しない変換が起きず、必要なときだけ整形ペーストを利用できるようにするため。

#### Acceptance Criteria

1. When `Cmd+V` が押された場合、Chirami shall クリップボードの内容をプレーンテキストとしてそのまま挿入する
2. When `Cmd+Shift+V` が押された場合、Chirami shall クリップボードの内容を解析し、適切な Markdown 形式に変換して挿入する
3. While テキストエディタにフォーカスがない場合、Chirami shall スマートペーストのキーバインドを無視する

### Requirement 2: コンテンツ種別の自動判定

**Objective:** ユーザーとして、クリップボードの内容が何であるかを意識せずにスマートペーストしたい。コンテンツの種類に応じて自動的に最適な変換が適用されるようにするため。

#### Acceptance Criteria

1. When スマートペーストが実行された場合、Chirami shall クリップボードの内容を以下の優先順位で判定する: HTML → URL → JSON → コードブロック → プレーンテキスト
2. If クリップボードの内容がいずれの特殊形式にも該当しない場合、Chirami shall 内容をプレーンテキストとしてそのまま挿入する

### Requirement 3: HTML/リッチテキスト変換

**Objective:** ユーザーとして、ブラウザなどからコピーしたリッチテキストを Markdown として貼り付けたい。見出し・リンク・リストなどの構造を維持したままノートに取り込めるようにするため。

#### Acceptance Criteria

1. When クリップボードに HTML コンテンツが含まれる場合、Chirami shall HTML を Markdown に変換して挿入する
2. When HTML に見出しタグ (`h1`-`h6`) が含まれる場合、Chirami shall 対応する Markdown 見出し (`#`-`######`) に変換する
3. When HTML にハイパーリンクが含まれる場合、Chirami shall `[テキスト](URL)` 形式の Markdown リンクに変換する
4. When HTML にリスト (`ul`/`ol`) が含まれる場合、Chirami shall Markdown のリスト形式に変換する
5. When HTML に太字・斜体などのインライン装飾が含まれる場合、Chirami shall 対応する Markdown インライン記法 (`**`, `*`) に変換する

### Requirement 4: URL 変換

**Objective:** ユーザーとして、コピーした URL を Markdown リンクとして貼り付けたい。手動でリンク記法を書く手間を省くため。

#### Acceptance Criteria

1. When クリップボードの内容が単一の URL である場合、Chirami shall `[タイトル](URL)` 形式の Markdown リンクとして挿入する
2. Where `fetch_url_title` が有効な場合、Chirami shall URL のページタイトルを非同期で取得し、リンクテキストに設定する
3. While タイトル取得中の場合、Chirami shall `[](URL)` をプレースホルダとして即座に挿入し、タイトル取得完了後にリンクテキストを更新する
4. If タイトルの取得に失敗した場合、Chirami shall URL 自身をリンクテキストとして使用する (`[URL](URL)`)
5. Where `fetch_url_title` が無効な場合、Chirami shall URL 自身をリンクテキストとして使用する

### Requirement 5: JSON/コードブロック変換

**Objective:** ユーザーとして、コピーした JSON やコードスニペットを自動的にコードブロックとして貼り付けたい。手動でバッククォートを入力する手間を省くため。

#### Acceptance Criteria

1. When クリップボードの内容が有効な JSON 文字列である場合、Chirami shall コードブロック (` ```json `) で囲んで挿入する
2. When クリップボードの内容がコードと判定される場合、Chirami shall コードブロック (` ``` `) で囲んで挿入する

### Requirement 6: 設定管理

**Objective:** ユーザーとして、スマートペーストの動作を `config.yaml` でカスタマイズしたい。自分のワークフローに合わせて機能の有効/無効やオプションを制御できるようにするため。

#### Acceptance Criteria

1. Chirami shall `config.yaml` の `smart_paste.enabled` で機能全体の有効/無効を制御できる
2. Chirami shall `config.yaml` の `smart_paste.fetch_url_title` で URL ペースト時のタイトル自動取得の有効/無効を制御できる
3. When `smart_paste` セクションが `config.yaml` に存在しない場合、Chirami shall デフォルト値 (`enabled: true`, `fetch_url_title: true`) を使用する
4. When 設定ファイルが変更された場合、Chirami shall 再起動なしで設定変更を反映する
