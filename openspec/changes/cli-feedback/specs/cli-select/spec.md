## ADDED Requirements

### Requirement: selectコマンドでユーザーの選択を取得する
`chirami select <text> <option1> <option2> ...` が実行されたとき、システムはMarkdownコンテンツを表示し下部に選択肢ボタンを配置したフローティングウィンドウを開かなければならない（SHALL）。ユーザーがボタンを押した場合は選択されたオプションのテキストをstdoutに出力しexit code 0で終了する。

#### Scenario: 選択肢を選択する
- **WHEN** ユーザーが `chirami select "レビュー結果" "承認" "差し戻し" "保留"` を実行し、「承認」ボタンを押した場合
- **THEN** stdoutに `承認` が出力され、exit code 0で終了する

#### Scenario: ウィンドウを閉じた場合
- **WHEN** ユーザーが選択肢を選ばずにウィンドウを閉じた場合
- **THEN** stdoutには何も出力されず、exit code 1で終了する

### Requirement: selectコマンドのキーボード操作
selectウィンドウが表示されているとき、システムは数字キー(1-9)で対応する選択肢を直接選択でき、Escでキャンセルできなければならない（SHALL）。

#### Scenario: 数字キーで選択する
- **WHEN** 3つの選択肢が表示された状態でユーザーが `2` キーを押した場合
- **THEN** 2番目の選択肢が選択され、そのテキストがstdoutに出力される

#### Scenario: 範囲外の数字キーは無視する
- **WHEN** 3つの選択肢が表示された状態でユーザーが `5` キーを押した場合
- **THEN** 何も起きない

#### Scenario: Escキーでキャンセルする
- **WHEN** selectウィンドウが表示された状態でEscキーを押した場合
- **THEN** ウィンドウが閉じられ、exit code 1で終了する

### Requirement: selectコマンドの選択肢指定
`chirami select` は最初の引数（またはstdin/`--file`）をMarkdown本文として扱い、2番目以降の引数を選択肢として扱わなければならない（SHALL）。選択肢は最低2つ必要である。

#### Scenario: 引数で選択肢を渡す
- **WHEN** ユーザーが `chirami select "どちらにしますか？" "はい" "いいえ"` を実行した場合
- **THEN** Markdown本文と2つの選択肢ボタンが表示される

#### Scenario: stdinで本文を渡し引数で選択肢を指定する
- **WHEN** ユーザーが `echo "説明文" | chirami select -- "選択A" "選択B"` を実行した場合
- **THEN** stdinの内容がMarkdown本文として表示され、2つの選択肢ボタンが表示される

#### Scenario: 選択肢が1つ以下の場合
- **WHEN** ユーザーが `chirami select "質問" "唯一の選択肢"` を実行した場合
- **THEN** stderrにエラーメッセージが表示され、exit code 1で終了する

### Requirement: selectコマンドのコンテンツ入力
`chirami select` は `display` と同じ入力方式（引数テキスト、`--file`、stdin）でMarkdownコンテンツを受け取らなければならない（SHALL）。コンテンツは常に読み取り専用で表示される。

#### Scenario: コンテンツなしで実行した場合
- **WHEN** ユーザーが `chirami select` のみを実行した場合
- **THEN** stderrにusageメッセージが表示され、exit code 1で終了する

### Requirement: selectコマンドは常にブロッキング動作する
`chirami select` は選択肢が選択されるかウィンドウが閉じられるまでプロセスをブロックしなければならない（SHALL）。

#### Scenario: ブロッキング動作
- **WHEN** ユーザーが `chirami select "質問" "A" "B"` を実行した場合
- **THEN** ユーザーが選択するかウィンドウを閉じるまでプロセスが終了しない
