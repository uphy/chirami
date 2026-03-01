## ADDED Requirements

### Requirement: confirmコマンドでユーザーの承認を取得する
`chirami confirm <text>` が実行されたとき、システムはMarkdownコンテンツを表示し下部にOK/Cancelボタンを配置したフローティングウィンドウを開かなければならない（SHALL）。ユーザーがOKを押した場合はexit code 0、Cancelを押した場合はexit code 1で終了する。

#### Scenario: OKボタンで承認する
- **WHEN** ユーザーが `chirami confirm "デプロイしますか？"` を実行し、OKボタンを押した場合
- **THEN** プロセスはexit code 0で終了する

#### Scenario: Cancelボタンでキャンセルする
- **WHEN** ユーザーが `chirami confirm "デプロイしますか？"` を実行し、Cancelボタンを押した場合
- **THEN** プロセスはexit code 1で終了する

#### Scenario: ウィンドウを閉じた場合はキャンセル扱い
- **WHEN** ユーザーが閉じるボタン（×）でウィンドウを閉じた場合
- **THEN** プロセスはexit code 1で終了する

### Requirement: confirmコマンドのキーボード操作
confirmウィンドウが表示されているとき、システムはEnterキーでOK、Escキーでキャンセルを受け付けなければならない（SHALL）。

#### Scenario: Enterキーで承認する
- **WHEN** confirmウィンドウが表示された状態でユーザーがEnter/Returnキーを押した場合
- **THEN** OKボタンを押した場合と同じ動作をする（exit code 0）

#### Scenario: Escキーでキャンセルする
- **WHEN** confirmウィンドウが表示された状態でユーザーがEscキーを押した場合
- **THEN** Cancelボタンを押した場合と同じ動作をする（exit code 1）

### Requirement: confirmコマンドのコンテンツ入力
`chirami confirm` は `display` と同じ入力方式（引数テキスト、`--file`、stdin）でMarkdownコンテンツを受け取らなければならない（SHALL）。コンテンツは常に読み取り専用で表示される。

#### Scenario: 引数でコンテンツを渡す
- **WHEN** ユーザーが `chirami confirm "## 確認\n本番にデプロイします"` を実行した場合
- **THEN** Markdownがレンダリングされた読み取り専用のフローティングウィンドウが開き、下部にOK/Cancelボタンが表示される

#### Scenario: stdinでコンテンツを渡す
- **WHEN** ユーザーが `echo "確認内容" | chirami confirm` を実行した場合
- **THEN** stdinの内容がMarkdownとして表示され、下部にOK/Cancelボタンが表示される

#### Scenario: ファイルでコンテンツを渡す
- **WHEN** ユーザーが `chirami confirm --file ./summary.md` を実行した場合
- **THEN** ファイル内容がMarkdownとして読み取り専用で表示され、下部にOK/Cancelボタンが表示される

#### Scenario: コンテンツなしで実行した場合
- **WHEN** ユーザーが引数・ファイル・stdinなしで `chirami confirm` を端末から実行した場合
- **THEN** stderrにusageメッセージが表示され、exit code 1で終了する

### Requirement: confirmコマンドは常にブロッキング動作する
`chirami confirm` はウィンドウが閉じられるか、ボタンが押されるまでプロセスをブロックしなければならない（SHALL）。`--wait` フラグは不要で暗黙的にブロッキングする。

#### Scenario: ブロッキング動作
- **WHEN** ユーザーが `chirami confirm "確認"` を実行した場合
- **THEN** ユーザーがOK/Cancelを選択するかウィンドウを閉じるまでプロセスが終了しない
