## ADDED Requirements

### Requirement: コンテンツを引数から受け取る
`chirami display <text>` が実行されたとき、システムは引数として渡されたテキストをMarkdownコンテンツとしてフローティングウィンドウに表示しなければならない（SHALL）。

#### Scenario: テキスト引数でウィンドウを表示する
- **WHEN** ユーザーが `chirami display "## Hello\nWorld"` を実行した場合
- **THEN** フローティングウィンドウが開き、MarkdownレンダリングされたコンテンツがAlways-on-topで表示される

### Requirement: コンテンツをファイルから受け取る
`chirami display --file <path>` が実行されたとき、システムは指定されたファイルを読み込み、Markdownコンテンツとしてフローティングウィンドウに表示しなければならない（SHALL）。

#### Scenario: ファイルパスを指定してウィンドウを表示する
- **WHEN** ユーザーが `chirami display --file ~/Notes/todo.md` を実行した場合
- **THEN** 指定ファイルの内容がMarkdownレンダリングされてフローティングウィンドウに表示される

#### Scenario: 存在しないファイルを指定した場合
- **WHEN** ユーザーが存在しないファイルパスで `chirami display --file /not/exist.md` を実行した場合
- **THEN** システムはstderrにエラーメッセージを出力してexit code 1で終了する

### Requirement: コンテンツをstdinから受け取る
引数なしで実行され、stdinにデータがパイプされた場合、システムはstdinの内容をMarkdownコンテンツとしてフローティングウィンドウに表示しなければならない（SHALL）。

#### Scenario: パイプでstdinからコンテンツを渡す
- **WHEN** ユーザーが `echo "# Title" | chirami display` を実行した場合
- **THEN** stdinの内容がMarkdownレンダリングされてフローティングウィンドウに表示される

### Requirement: 入力形式の優先順位
引数・ファイル・stdinが同時に指定された場合、システムは引数 > ファイル > stdin の優先順位でコンテンツを採用しなければならない（SHALL）。

#### Scenario: 引数とファイルが同時に指定された場合
- **WHEN** 引数テキストと `--file` オプションが両方指定された場合
- **THEN** 引数のテキストが採用される

### Requirement: フローティングウィンドウ表示
ウィンドウが表示されたとき、システムは他のウィンドウの前面にAlways-on-topで表示しなければならない（SHALL）。

#### Scenario: Always-on-topで表示される
- **WHEN** `chirami display` でウィンドウが開かれた場合
- **THEN** ウィンドウは他のアプリウィンドウより前面に表示される

#### Scenario: DockとApp Switcherに表示されない
- **WHEN** `chirami display` が実行されている間
- **THEN** macOSのDockおよびCmd+Tabのアプリスイッチャーにアイコンが表示されない

### Requirement: プロセスブロッキング
ウィンドウが表示されたとき、システムはウィンドウが閉じられるまでプロセスをブロックしなければならない（SHALL）。

#### Scenario: ウィンドウを閉じるとプロセスが終了する
- **WHEN** ユーザーがウィンドウの閉じるボタン（×）またはEscキーを押した場合
- **THEN** ウィンドウが閉じられ、プロセスがexit code 0で終了する

### Requirement: 設定ファイルへの無依存
システムは`~/.config/chirami/config.yaml`および`~/.local/state/chirami/state.yaml`への読み書きを一切行ってはならない（SHALL NOT）。

#### Scenario: 設定ファイルなしで動作する
- **WHEN** `~/.config/chirami/config.yaml` が存在しない環境で `chirami display "test"` を実行した場合
- **THEN** ウィンドウが正常に表示される

### Requirement: ヘルプ表示
`chirami display --help` が実行されたとき、システムは使用方法（usage）をstdoutに出力してexit code 0で終了しなければならない（SHALL）。

#### Scenario: ヘルプが表示される
- **WHEN** ユーザーが `chirami display --help` を実行した場合
- **THEN** 使用方法がstdoutに出力され、exit code 0で終了する

### Requirement: コンテンツが空の場合のエラー
引数・ファイル・stdinのいずれからもコンテンツが得られなかった場合、システムはstderrにusageメッセージを出力してexit code 1で終了しなければならない（SHALL）。

#### Scenario: コンテンツなしで実行した場合
- **WHEN** ユーザーが引数・ファイル・stdinなしで `chirami display` を端末から実行した場合
- **THEN** stderrにusageメッセージが表示され、exit code 1で終了する
