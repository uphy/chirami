# cli-display

## Purpose

TBD

## Requirements

### Requirement: コンテンツを引数から受け取る
`chirami display <text>` が実行されたとき、システムは引数として渡されたテキストをMarkdownコンテンツとして**読み取り専用**フローティングウィンドウに表示しなければならない（SHALL）。

#### Scenario: テキスト引数でウィンドウを表示する
- **WHEN** ユーザーが `chirami display "## Hello\nWorld"` を実行した場合
- **THEN** フローティングウィンドウが開き、MarkdownレンダリングされたコンテンツがAlways-on-topで**読み取り専用**表示される

### Requirement: コンテンツをファイルから受け取る
`chirami display --file <path>` が実行されたとき、システムは指定されたファイルを読み込み、Markdownコンテンツとして編集可能なフローティングウィンドウに表示しなければならない（SHALL）。

#### Scenario: ファイルパスを指定してウィンドウを表示する
- **WHEN** ユーザーが `chirami display --file ~/Notes/todo.md` を実行した場合
- **THEN** 指定ファイルの内容がMarkdownレンダリングされた**編集可能な**フローティングウィンドウに表示される

#### Scenario: 存在しないファイルを指定した場合
- **WHEN** ユーザーが存在しないファイルパスで `chirami display --file /not/exist.md` を実行した場合
- **THEN** システムはstderrにエラーメッセージを出力してexit code 1で終了する

### Requirement: ファイルモードでの自動保存
ファイルモードでウィンドウが表示されているとき、システムはテキストが変更されるたびにファイルへ自動保存しなければならない（SHALL）。

#### Scenario: 編集内容がキーストロークごとに保存される
- **WHEN** ユーザーがファイルモードで表示されたウィンドウでテキストを編集した場合
- **THEN** 変更内容は即座にファイルへ書き込まれる（既存アプリの`NoteContentModel.save()`と同じ挙動）

#### Scenario: 変更がなければ保存しない
- **WHEN** テキストが前回保存時から変更されていない場合
- **THEN** ファイルへの書き込みは行われない

### Requirement: コンテンツをstdinから受け取る
引数なしで実行され、stdinにデータがパイプされた場合、システムはstdinの内容をMarkdownコンテンツとして**読み取り専用**フローティングウィンドウに表示しなければならない（SHALL）。stdinがTTY（端末）の場合はstdinを読まない。

#### Scenario: パイプでstdinからコンテンツを渡す
- **WHEN** ユーザーが `echo "# Title" | chirami display` を実行した場合
- **THEN** stdinの内容がMarkdownレンダリングされた**読み取り専用**フローティングウィンドウに表示される

#### Scenario: stdinがTTYの場合はstdinを読まない
- **WHEN** ユーザーが端末から直接 `chirami display` を実行した場合（パイプなし）
- **THEN** stdinからの読み込みは行われない（コンテンツなしとみなされexit code 1で終了する）

### Requirement: 入力形式の優先順位
引数・ファイル・stdinが同時に指定された場合、システムは引数 > ファイル > stdin の優先順位でコンテンツを採用しなければならない（SHALL）。

#### Scenario: 引数とファイルが同時に指定された場合
- **WHEN** 引数テキストと `--file` オプションが両方指定された場合
- **THEN** 引数のテキストが採用される

### Requirement: 読み取り専用モードのレンダリング
読み取り専用モード（引数・stdinからのコンテンツ）でウィンドウが表示されたとき、システムはMarkdownを常に全面レンダリングした状態で表示しなければならない（SHALL）。Live Preview（カーソル行のみ raw Markdown 表示）は使用しない。

#### Scenario: 読み取り専用は常に全面レンダリング
- **WHEN** `chirami display "# Hello\nWorld"` でウィンドウが表示された場合
- **THEN** カーソル位置にかかわらず、全テキストがレンダリング済みMarkdownとして表示される

### Requirement: 読み取り専用モードの視覚的表示
読み取り専用モードでウィンドウが表示されたとき、システムはタイトルバーに 🔒 を表示してユーザーに読み取り専用であることを示さなければならない（SHALL）。

#### Scenario: タイトルバーに 🔒 が表示される
- **WHEN** 読み取り専用モードでウィンドウが開かれた場合
- **THEN** タイトルバーに `🔒 chirami` と表示される

#### Scenario: 編集可能モードでは 🔒 が表示されない
- **WHEN** `--file` で編集可能モードのウィンドウが開かれた場合
- **THEN** タイトルバーには 🔒 が表示されない

### Requirement: Chirami.app自動起動
`chirami display` が実行されたとき、Chirami.appが未起動であってもシステムは自動的にChirami.appを起動してウィンドウを表示しなければならない（SHALL）。

#### Scenario: Chirami.app未起動時に自動起動する
- **WHEN** Chirami.appが起動していない状態で `chirami display "## Hello"` を実行した場合
- **THEN** Chirami.appが自動的に起動し、フローティングウィンドウが表示される

### Requirement: フローティングウィンドウ表示
ウィンドウが表示されたとき、システムは他のウィンドウの前面にAlways-on-topで表示しなければならない（SHALL）。

#### Scenario: Always-on-topで表示される
- **WHEN** `chirami display` でウィンドウが開かれた場合
- **THEN** ウィンドウは他のアプリウィンドウより前面に表示される

#### Scenario: DockとApp Switcherに表示されない
- **WHEN** `chirami display` が実行されている間
- **THEN** macOSのDockおよびCmd+Tabのアプリスイッチャーにアイコンが表示されない

### Requirement: ノンブロッキング実行（デフォルト）
`--wait` フラグなしで実行されたとき、システムはウィンドウを開いた後すぐにexit code 0で終了しなければならない（SHALL）。

#### Scenario: デフォルトはノンブロッキング
- **WHEN** ユーザーが `chirami display "## Hello"` を実行した場合
- **THEN** ウィンドウが開き、プロセスはすぐにexit code 0で終了する

### Requirement: ブロッキング実行（`--wait`）
`--wait` フラグ付きで実行されたとき、システムはウィンドウが閉じられるまでプロセスをブロックしなければならない（SHALL）。

#### Scenario: `--wait` でウィンドウを閉じるまでブロックする
- **WHEN** ユーザーが `chirami display --wait "## Hello"` を実行した場合
- **THEN** ウィンドウが開き、プロセスはウィンドウが閉じられるまでブロックする

#### Scenario: `--wait` 時にウィンドウを閉じるとプロセスが終了する
- **WHEN** `--wait` で実行中にユーザーが閉じるボタン（×）またはEscキーを押した場合
- **THEN** ウィンドウが閉じられ、プロセスがexit code 0で終了する

#### Scenario: `--wait` 中にChirami.appがクラッシュした場合
- **WHEN** `--wait` で実行中にChirami.appがクラッシュした場合
- **THEN** FIFOがEOFになりread errorを検出してexit code 1で終了する

#### Scenario: `--wait` + `--file` でファイルを編集して閉じる
- **WHEN** ユーザーが `chirami display --wait --file ~/Notes/todo.md` を実行し、内容を編集してウィンドウを閉じた場合
- **THEN** 編集内容がファイルに保存された状態でウィンドウが閉じられ、プロセスがexit code 0で終了する

### Requirement: 複数ウィンドウの独立表示
`chirami display` が複数回実行されたとき、システムはそれぞれ独立したフローティングウィンドウを表示しなければならない（SHALL）。

#### Scenario: 複数回実行でそれぞれウィンドウが開く
- **WHEN** ユーザーが `chirami display "# First"` と `chirami display "# Second"` を続けて実行した場合
- **THEN** 2つの独立したフローティングウィンドウが表示される

### Requirement: CLIのサブコマンド構造
`chirami` コマンドはサブコマンド形式で提供されなければならない（SHALL）。`display` は将来の `append` などと並ぶ一サブコマンドである。

#### Scenario: サブコマンドなしで実行した場合
- **WHEN** ユーザーが `chirami` のみを実行した場合
- **THEN** 利用可能なサブコマンド一覧を含むusageがstdoutに出力され、exit code 0で終了する

### Requirement: 設定ファイルへの無依存
`chirami display` サブコマンドは`~/.config/chirami/config.yaml`および`~/.local/state/chirami/state.yaml`への読み書きを一切行ってはならない（SHALL NOT）。

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
