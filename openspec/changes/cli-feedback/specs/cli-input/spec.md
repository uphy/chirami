## ADDED Requirements

### Requirement: inputコマンドでユーザーのテキスト入力を取得する
`chirami input <text>` が実行されたとき、システムはMarkdownコンテンツを表示し下部にテキスト入力欄とSubmitボタンを配置したフローティングウィンドウを開かなければならない（SHALL）。ユーザーがSubmitした場合は入力テキストをstdoutに出力しexit code 0で終了する。

#### Scenario: テキストを入力してSubmitする
- **WHEN** ユーザーが `chirami input "名前を入力してください"` を実行し、テキスト欄に「田中太郎」と入力してSubmitした場合
- **THEN** stdoutに `田中太郎` が出力され、exit code 0で終了する

#### Scenario: ウィンドウを閉じた場合
- **WHEN** ユーザーがテキストを入力せずにウィンドウを閉じた場合
- **THEN** stdoutには何も出力されず、exit code 1で終了する

### Requirement: inputコマンドのキーボード操作
inputウィンドウが表示されているとき、システムはCmd+EnterでSubmit、Escでキャンセルを受け付けなければならない（SHALL）。

#### Scenario: Cmd+EnterでSubmitする
- **WHEN** inputウィンドウのテキスト欄にテキストを入力した状態でCmd+Enterを押した場合
- **THEN** Submitボタンを押した場合と同じ動作をする

#### Scenario: Escキーでキャンセルする
- **WHEN** inputウィンドウが表示された状態でEscキーを押した場合
- **THEN** ウィンドウが閉じられ、exit code 1で終了する

### Requirement: inputコマンドのsingle-lineモード
`chirami input --single-line` が指定されたとき、システムはテキスト入力欄を1行入力に制限し、EnterキーでSubmitしなければならない（SHALL）。

#### Scenario: single-lineモードでEnterキーでSubmitする
- **WHEN** `chirami input --single-line "名前は？"` を実行し、テキストを入力してEnterを押した場合
- **THEN** 入力テキストがstdoutに出力され、exit code 0で終了する

#### Scenario: single-lineモードではテキスト欄が1行表示になる
- **WHEN** `chirami input --single-line "名前は？"` を実行した場合
- **THEN** テキスト入力欄は1行表示で改行は入力できない

### Requirement: inputコマンドのplaceholder
`chirami input --placeholder <text>` が指定されたとき、システムはテキスト入力欄にプレースホルダーテキストを表示しなければならない（SHALL）。

#### Scenario: placeholderが表示される
- **WHEN** `chirami input --placeholder "例: 田中太郎" "名前は？"` を実行した場合
- **THEN** テキスト入力欄にグレーの「例: 田中太郎」がプレースホルダーとして表示される

### Requirement: inputコマンドのコンテンツ入力
`chirami input` は `display` と同じ入力方式（引数テキスト、`--file`、stdin）でMarkdownコンテンツを受け取らなければならない（SHALL）。コンテンツは常に読み取り専用で表示される。

#### Scenario: コンテンツなしで実行した場合
- **WHEN** ユーザーが引数・ファイル・stdinなしで `chirami input` を端末から実行した場合
- **THEN** stderrにusageメッセージが表示され、exit code 1で終了する

### Requirement: inputコマンドは常にブロッキング動作する
`chirami input` はSubmitされるかウィンドウが閉じられるまでプロセスをブロックしなければならない（SHALL）。

#### Scenario: ブロッキング動作
- **WHEN** ユーザーが `chirami input "入力してください"` を実行した場合
- **THEN** ユーザーがSubmitするかウィンドウを閉じるまでプロセスが終了しない
