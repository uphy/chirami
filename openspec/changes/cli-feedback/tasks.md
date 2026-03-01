## 1. FIFOプロトコル拡張 (Go CLI)

- [ ] 1.1 `internal/fifo.go` に `Response` 型を定義する（`Closed`, `Confirmed`, `Cancelled`, `Result(value)` を表現するenum的構造体）
- [ ] 1.2 `internal/fifo.go` に `WaitForResponse(pipePath) (Response, error)` を実装する（FIFOから1行読み、`CLOSED`, `CONFIRMED`, `CANCELLED`, `RESULT:<value>` をパースして `Response` を返す）
- [ ] 1.3 `RESULT:<value>` の値を `url.QueryUnescape` でデコードする処理を `WaitForResponse` に含める
- [ ] 1.4 既存の `WaitForClosed` は `display --wait` で引き続き使用する（変更なし）

## 2. Go CLI 共通処理の抽出

- [ ] 2.1 `display.go` の `getContent` 関数を `common.go` に移動する
- [ ] 2.2 `common.go` に `openURI(subcommand string, params map[string]string) error` を抽出する（URI構築 → `open -g` 実行）
- [ ] 2.3 `common.go` に `prepareFIFO() (pipePath string, cleanup func(), err error)` を抽出する（FIFO作成 + defer用cleanup返却）
- [ ] 2.4 `common.go` に `prepareContentParams(args []string, fileFlag string) (map[string]string, error)` を実装する（コンテンツ取得 → URIパラメータ構築を一括実行、読み取り専用固定）
- [ ] 2.5 `display.go` を `common.go` の関数を使うようリファクタリングする（既存動作に変更なし）

## 3. confirm サブコマンド (Go CLI)

- [ ] 3.1 `confirm.go` に `newConfirmCmd()` を実装する（`chirami confirm [text]` + `--file` フラグ）
- [ ] 3.2 `runConfirm` を実装する（FIFO作成 → URIパラメータ構築 → `openURI("confirm", params)` → `WaitForResponse` → `CONFIRMED` で exit 0, `CANCELLED`/`CLOSED` で exit 1）
- [ ] 3.3 `main.go` に `rootCmd.AddCommand(newConfirmCmd())` を追加する

## 4. input サブコマンド (Go CLI)

- [ ] 4.1 `input.go` に `newInputCmd()` を実装する（`chirami input [text]` + `--file`, `--single-line`, `--placeholder` フラグ）
- [ ] 4.2 `runInput` を実装する（FIFO作成 → URIパラメータ構築 → `openURI("input", params)` → `WaitForResponse` → `RESULT:<value>` で stdout出力+exit 0, `CLOSED` で exit 1）
- [ ] 4.3 `--single-line` と `--placeholder` をURIパラメータ `single_line=1`, `placeholder=<text>` として渡す
- [ ] 4.4 `main.go` に `rootCmd.AddCommand(newInputCmd())` を追加する

## 5. select サブコマンド (Go CLI)

- [ ] 5.1 `select.go` に `newSelectCmd()` を実装する（`chirami select [text] [options...]` + `--file` フラグ）
- [ ] 5.2 selectの引数パース: 最初の引数をMarkdown本文、2番目以降を選択肢として分離する。stdin/`--file` 使用時は全引数を選択肢として扱う
- [ ] 5.3 選択肢が2つ未満の場合にエラーを返す
- [ ] 5.4 選択肢をカンマ区切りでURLエンコードして `options` パラメータとしてURIに含める
- [ ] 5.5 `runSelect` を実装する（FIFO作成 → URIパラメータ構築 → `openURI("select", params)` → `WaitForResponse` → `RESULT:<value>` で stdout出力+exit 0, `CLOSED` で exit 1）
- [ ] 5.6 `main.go` に `rootCmd.AddCommand(newSelectCmd())` を追加する

## 6. DisplayWindowManager URI ルーティング拡張 (Swift)

- [ ] 6.1 `DisplayWindowManager` に `handleURI(url:)` を追加し、URLのホスト部分（`display`, `confirm`, `input`, `select`）で分岐する
- [ ] 6.2 `ChiramiApp.swift` の `application(_:open:)` を更新し、新しいホスト（`confirm`, `input`, `select`）もルーティングする
- [ ] 6.3 各モードのURIパラメータをパースする共通関数を `DisplayWindowManager` に追加する

## 7. DisplayPanel の結果通知拡張 (Swift)

- [ ] 7.1 `DisplayPanel` に `notifyResult(_ message: String)` を追加する（FIFOに任意メッセージを書き込み → `didNotifyClosed = true` → `close()`）
- [ ] 7.2 `RESULT:<value>` 送信時、value を `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` でエンコードする
- [ ] 7.3 `notifyResult` が呼ばれた後に `notifyClosed` が重複送信されないことを確認する

## 8. FeedbackBarView (Swift, confirm)

- [ ] 8.1 `FeedbackBarView` の基底クラスを作成する（NSView サブクラス、高さ固定、区切り線付き）
- [ ] 8.2 `ConfirmBarView` を実装する（左にCancelボタン、右にOKボタン、OKがデフォルトボタン）
- [ ] 8.3 OKボタン押下時に `DisplayPanel.notifyResult("CONFIRMED")` を呼ぶ
- [ ] 8.4 Cancelボタン押下時に `DisplayPanel.notifyResult("CANCELLED")` を呼ぶ
- [ ] 8.5 Enterキーで OK、Escキーで Cancel のキーボードショートカットを設定する

## 9. FeedbackBarView (Swift, input)

- [ ] 9.1 `InputBarView` を実装する（テキスト入力欄 + Submitボタン）
- [ ] 9.2 `--single-line` パラメータに応じて NSTextField（1行）/ NSTextView（複数行）を切り替える
- [ ] 9.3 `--placeholder` パラメータをプレースホルダーテキストとして設定する
- [ ] 9.4 Submitボタン押下時に `DisplayPanel.notifyResult("RESULT:<encoded-value>")` を呼ぶ
- [ ] 9.5 Cmd+Enter で Submit のキーボードショートカットを設定する（single-lineモードでは Enter で Submit）
- [ ] 9.6 複数行テキスト入力欄の最大高さを制限する（Markdownコンテンツ領域を圧迫しないよう）

## 10. FeedbackBarView (Swift, select)

- [ ] 10.1 `SelectBarView` を実装する（選択肢ボタンを横並びに配置）
- [ ] 10.2 URIの `options` パラメータをパースして選択肢ボタンを生成する
- [ ] 10.3 ボタン押下時に `DisplayPanel.notifyResult("RESULT:<encoded-option>")` を呼ぶ
- [ ] 10.4 数字キー(1-9)で対応する選択肢を選択するキーボードショートカットを設定する
- [ ] 10.5 各ボタンに番号ラベル（1., 2., ...）を付与して数字キー対応を視覚的に示す

## 11. ウィンドウ組み立て (Swift)

- [ ] 11.1 `DisplayWindowManager` の各ハンドラで `DisplayPanel` + `DisplayContentView` + `FeedbackBarView` を上下に配置する
- [ ] 11.2 contentView を NSSplitView ではなく NSStackView (vertical) で構成する（上: Markdownコンテンツ, 下: FeedbackBar）
- [ ] 11.3 フィードバックコマンドのタイトルバーを `🔒 chirami` に設定する

## 12. 検証

- [ ] 12.1 `chirami confirm "テスト"` → OK/Cancel/Esc/× でそれぞれ正しいexit codeが返ることを確認
- [ ] 12.2 `chirami input "入力"` → テキスト入力 → Submit でstdoutに出力されることを確認
- [ ] 12.3 `chirami input --single-line --placeholder "例" "入力"` → Enter で Submit されることを確認
- [ ] 12.4 `chirami select "質問" "A" "B" "C"` → ボタン・数字キーで選択結果がstdoutに出力されることを確認
- [ ] 12.5 stdin / `--file` での本文入力が各コマンドで動作することを確認
- [ ] 12.6 日本語テキストの入力・選択肢が正しくエンコード/デコードされることを確認
- [ ] 12.7 `chirami display --wait` が従来通り `CLOSED` で exit 0 になることを確認（後方互換性）
