## MODIFIED Requirements

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

#### Scenario: FIFOプロトコルで未知のメッセージを受信した場合
- **WHEN** `--wait` で実行中にFIFOから `CLOSED` 以外のメッセージ（`CONFIRMED`, `RESULT:...` 等）を受信した場合
- **THEN** 未知のメッセージは無視し、`CLOSED` の受信を待ち続ける
