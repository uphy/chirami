## ADDED Requirements

### Requirement: `transcript` コードブロックの認識とウィジェット表示

エディタは ` ```transcript ` フェンスコードブロックを検出し、カーソルがブロック外にある場合は録音コントロールを含むウィジェットを表示しなければならない（SHALL）。カーソルがブロック内にある場合はウィジェットを非表示にし、ブロック内のプレーンテキスト（`[MM:SS] Speaker: text` 行）を通常の Markdown として編集可能にしなければならない（SHALL）。

#### Scenario: カーソルがブロック外にある場合のウィジェット表示

- **WHEN** ユーザーが ` ```transcript ` コードブロックの外にカーソルを置いている
- **THEN** コードブロック全体が非表示になり、代わりに録音ボタン・経過時間・音量メーター・デバイス情報を含むウィジェットが表示される

#### Scenario: カーソルがブロック内にある場合

- **WHEN** ユーザーが ` ```transcript ` コードブロック内のいずれかの行にカーソルを置く
- **THEN** ウィジェットは非表示になり、ブロック内のテキストが通常の Markdown として編集可能な状態で表示される

#### Scenario: ブロックが空の場合の初期表示

- **WHEN** ` ```transcript ` コードブロックの内容が空
- **THEN** ウィジェットは Idle 状態で、録音開始ボタンとデバイス選択 UI のみを表示する

### Requirement: 録音状態マシン

`transcript` ブロックは Idle / Recording / Paused / Processing / Completed / Error の 6 状態を持ち、ユーザー操作およびシステムイベントに応じて厳密な遷移規則に従わなければならない（SHALL）。状態の真の所有者は Swift 側であり、JS ウィジェットは状態を受信して表示するのみとする。

#### Scenario: 録音開始

- **WHEN** Idle 状態のウィジェットで「録音開始」ボタンがクリックされる
- **THEN** 状態が Recording に遷移し、マイクおよびシステム音声のキャプチャが開始される

#### Scenario: 一時停止と再開

- **WHEN** Recording 状態で「一時停止」がクリックされる
- **THEN** 状態が Paused に遷移し、音声キャプチャが停止する。この状態から「再開」をクリックすると Recording に戻り、同じセッションとして録音が継続される

#### Scenario: 録音停止

- **WHEN** Recording または Paused 状態で「停止」がクリックされる
- **THEN** 状態が Processing に遷移し、末尾音声の確定処理が完了した時点で Completed に遷移する

#### Scenario: 追加録音

- **WHEN** Completed 状態で「追加録音」がクリックされる
- **THEN** ブロック末尾に `---` セパレータ行が挿入され、新規セッションとして Recording に遷移する。タイムスタンプは新セッションの 00:00 からカウントされる

#### Scenario: 重大エラー発生

- **WHEN** 任意の状態で権限拒否・モデルロード失敗・タップクラッシュ等の致命的エラーが発生する
- **THEN** 状態が Error に遷移し、ウィジェット内にエラー理由と再試行導線が表示される

#### Scenario: クリア操作

- **WHEN** 任意の非 Idle 状態で「クリア」がクリックされ、確認ダイアログで承認される
- **THEN** ブロック内のテキストが削除され、状態が Idle に戻る

### Requirement: ストリーミング書き起こし出力

書き起こしエンジンが確定（confirmed）とみなしたチャンクのみを `transcript` コードブロック内に追記しなければならない（SHALL）。確定前のチャンクはブロック本文には書き込まない（MUST NOT）。出力フォーマットは `[MM:SS] Speaker: text` とし、各チャンクを独立した 1 行として扱う。

#### Scenario: マイク音声の確定チャンク追記

- **WHEN** マイク入力から確定チャンクが得られる
- **THEN** ブロック末尾（閉じ ` ``` ` の直前）に `[MM:SS] You: <text>` 形式で 1 行追記される

#### Scenario: システム音声の確定チャンク追記

- **WHEN** システム音声から確定チャンクが得られる
- **THEN** ブロック末尾に `[MM:SS] Others: <text>` 形式で 1 行追記される

#### Scenario: 確定前チャンクの扱い

- **WHEN** WhisperKit が未確定のパーシャルチャンクを返す
- **THEN** ブロック本文には書き込まれず、ウィジェット内のライブキャプション領域（存在する場合）のみに一時表示される

#### Scenario: ユーザー編集との共存

- **WHEN** 確定チャンクの追記タイミングでユーザーが同一ノート内の別位置を編集している
- **THEN** 追記はブロック末尾に挿入され、ユーザーのカーソル位置・選択範囲は変化しない

### Requirement: 話者ラベルのカスタマイズ

マイク音声とシステム音声に付与する話者ラベルは、デフォルトで `You` および `Others` とするが、`config.yaml` の `transcript.labels.mic` および `transcript.labels.system` により上書き可能でなければならない（SHALL）。

#### Scenario: デフォルトラベルでの出力

- **WHEN** `transcript.labels` が設定されていない
- **THEN** マイク音声は `You`、システム音声は `Others` として出力される

#### Scenario: カスタムラベルでの出力

- **WHEN** `config.yaml` で `transcript.labels.mic: 自分` かつ `transcript.labels.system: 相手` が設定されている
- **THEN** マイク音声は `自分`、システム音声は `相手` として出力される

### Requirement: 音声入力デバイス選択の三段フォールバック

録音開始時のマイクおよびシステム音声ソースは、次の優先順位で決定されなければならない（SHALL）。(1) ユーザーがウィジェット UI で選択し `state.yaml` に保存された最終使用デバイス、(2) `config.yaml` の `transcript.devices.{mic,system}`、(3) macOS システムデフォルト。より優先度の高い層で指定されたデバイスが存在しない場合は、次の層へフォールバックしなければならない（SHALL）。

#### Scenario: 全層でデバイスが利用可能

- **WHEN** ウィジェットで選択したマイクが接続されており、`config.yaml` にも指定がある
- **THEN** ウィジェット選択のマイクが使用される

#### Scenario: ウィジェット選択が失われた場合のフォールバック

- **WHEN** ウィジェットで選択したマイク（例: AirPods）が切断されている
- **THEN** 警告がログに記録され、`config.yaml` に指定があればそのデバイスを、なければシステムデフォルトを使用する。ブロック内にはフォールバック発生を示すトースト表示を行う

#### Scenario: システム音声の自動選択

- **WHEN** `transcript.devices.system: auto` が設定されている
- **THEN** 録音開始時点で音声出力中のプロセスのうち最も音量の大きいものを対象に Core Audio Process Tap を作成する

#### Scenario: システム音声の無効化

- **WHEN** `transcript.devices.system: off` が設定されている
- **THEN** システム音声は一切キャプチャされず、マイクのみで録音が行われる

### Requirement: 音声キャプチャ方式

マイク音声は `AVAudioEngine` 経由でキャプチャし、システム音声は macOS 14.2 以降の Core Audio Process Taps（`CATapDescription`）を用いてプロセス単位でキャプチャしなければならない（SHALL）。仮想オーディオデバイス（BlackHole 等）への依存は行わない（MUST NOT）。

#### Scenario: macOS 14.2 以上での録音開始

- **WHEN** ユーザーの環境が macOS 14.2 以上で、マイク権限およびオーディオタップ権限が許可されている
- **THEN** マイクとシステム音声の両方がキャプチャされる

#### Scenario: macOS 14.1 以下での録音試行

- **WHEN** ユーザーの環境が macOS 14.1 以下
- **THEN** ウィジェットは Error 状態となり、「macOS 14.2 以上が必要です」というメッセージを表示する

### Requirement: WhisperKit による書き起こしエンジン

書き起こしは WhisperKit（CoreML）を用いて**完全にオンデバイス**で実行されなければならない（SHALL）。音声データは Chirami プロセス外に送信されてはならない（MUST NOT）。ただし初回のモデルダウンロード時のみ、Hugging Face（もしくはユーザー指定のモデル配布元）へのネットワーク接続が許可される。

#### Scenario: モデルのオンデバイス推論

- **WHEN** 録音中に音声チャンクが確定可能な長さに達する
- **THEN** WhisperKit が CoreML 経由でローカル推論を行い、テキストを返す。外部 API への音声アップロードは発生しない

### Requirement: 書き起こしモデルの管理

書き起こしモデルは `~/.local/state/chirami/models/whisper/<model-id>/` に保存され、未存在の場合は最初の録音開始時にダウンロードされなければならない（SHALL）。`transcript.model` に絶対パスが指定されている場合は、そのパスを直接使用し、ダウンロードは行わない（MUST NOT）。

#### Scenario: 初回録音時のモデル自動ダウンロード

- **WHEN** ユーザーが初めて録音開始し、指定されたモデルがローカルに存在しない
- **THEN** ウィジェット内にダウンロード進捗（パーセンテージおよび MB 単位）が表示され、完了後に自動的に録音が開始される

#### Scenario: モデルダウンロードのキャンセル

- **WHEN** ダウンロード中にユーザーがキャンセルを選択する
- **THEN** ダウンロードが中断され、ウィジェットは Idle 状態に戻る

#### Scenario: 絶対パス指定モデルの使用

- **WHEN** `transcript.model` が `/Users/me/models/whisper-small/` のような絶対パスに設定されている
- **THEN** そのパスのモデルが直接使用され、ネットワークアクセスは発生しない

#### Scenario: デフォルトモデル

- **WHEN** `transcript.model` が設定されていない
- **THEN** `openai_whisper-large-v3_turbo` が既定として使用される

### Requirement: 権限要求フロー

マイクアクセスおよび Core Audio Process Tap 権限は、アプリ起動時ではなく**最初の録音開始時**に要求されなければならない（SHALL）。権限が拒否された場合は、Error 状態で理由およびシステム設定への導線を表示しなければならない（SHALL）。

#### Scenario: 初回録音時のマイク権限要求

- **WHEN** マイク権限がまだ決定されていない状態で録音開始がクリックされる
- **THEN** macOS のマイク権限ダイアログが表示される

#### Scenario: マイク権限拒否

- **WHEN** ユーザーがマイク権限を拒否する
- **THEN** ウィジェットは Error 状態となり、「マイク権限がありません」というメッセージと「システム設定を開く」ボタンを表示する

#### Scenario: Core Audio Process Tap 権限の事前説明

- **WHEN** システム音声キャプチャが有効で、Process Tap 権限がまだ決定されていない
- **THEN** システムダイアログを出す前に、ウィジェット内に「別アプリの音声を取得する権限を要求します」という事前説明を表示する

### Requirement: 単一アクティブ録音の制約

同一 Chirami プロセス内では、同時に録音状態になれる `transcript` ブロックは 1 つのみでなければならない（SHALL）。

#### Scenario: 別ブロックでの録音開始試行

- **WHEN** あるブロックが Recording 状態のときに、別の `transcript` ブロックで録音開始がクリックされる
- **THEN** 確認ダイアログが表示され、承認されると進行中の録音が停止してから新しい録音が開始される

### Requirement: 書き起こし結果のプレーン Markdown 性

`transcript` ブロック内のテキストは、JSON や Base64 等のバイナリを含まない**プレーンな Markdown テキスト行**のみで構成されなければならない（SHALL）。これにより Obsidian・VS Code・grep 等の外部ツールで可読かつ編集可能であることを保証する。

#### Scenario: 外部エディタでの可読性

- **WHEN** 録音完了した `transcript` ブロックを含むノートを Obsidian で開く
- **THEN** ブロック内容は `[00:12] You: こんにちは` のような人間可読なテキストとして表示される

#### Scenario: ユーザーによる書き起こし訂正

- **WHEN** ユーザーが既存の書き起こし行を手動で編集して誤認識を訂正する
- **THEN** 編集内容は通常の Markdown 編集として保存され、以降の追加録音にも影響しない

### Requirement: 録音中のウィジェット表示要素

Recording および Paused 状態のウィジェットは、経過時間・マイク音量レベル・システム音声音量レベル・使用中デバイス名を表示しなければならない（SHALL）。

#### Scenario: 録音中の表示要素

- **WHEN** ウィジェットが Recording 状態
- **THEN** 経過時間（MM:SS）・マイク入力レベルバー・システム音声入力レベルバー・選択中デバイス名・一時停止ボタン・停止ボタンが表示される

#### Scenario: システム音声が無効な場合の表示

- **WHEN** ウィジェットが Recording 状態で `system: off` 設定
- **THEN** システム音声のレベルバーおよびデバイス情報は非表示となり、マイクの情報のみが表示される

### Requirement: `config.yaml` の `transcript` セクション

`config.yaml` は `transcript` セクションを受け入れなければならない（SHALL）。セクションが存在しない場合は全フィールドがデフォルト値として扱われ、既存の設定ファイルと後方互換でなければならない（SHALL）。

#### Scenario: セクション不在時のデフォルト

- **WHEN** `config.yaml` に `transcript:` セクションが存在しない
- **THEN** モデルは `openai_whisper-large-v3_turbo`、言語は `auto`、デバイスは `mic: default` / `system: auto`、ラベルは `You` / `Others` として扱われる

#### Scenario: 部分的な設定

- **WHEN** `config.yaml` に `transcript.model` のみが設定されている
- **THEN** 指定されたモデルが使用され、その他のフィールドはデフォルト値となる

### Requirement: Swift ↔ JS ブリッジメッセージ

`transcript` ブロックの動作に必要な JS → Swift および Swift → JS メッセージは、`NoteWebViewBridge` 経由で定義されなければならない（SHALL）。必須メッセージは以下を含む。

- JS → Swift: `transcriptRecordStart`, `transcriptRecordPause`, `transcriptRecordResume`, `transcriptRecordStop`, `transcriptRecordClear`, `transcriptDevicesRequest`, `transcriptDeviceSelect`
- Swift → JS: `transcriptStateChanged`, `transcriptChunk`, `transcriptLevelUpdate`, `transcriptDevicesList`, `transcriptModelDownloadProgress`, `transcriptError`

#### Scenario: 録音開始メッセージ

- **WHEN** JS ウィジェットが録音開始ボタンのクリックを処理する
- **THEN** `transcriptRecordStart` メッセージが Swift に送信され、対応するブロック ID と選択デバイス情報が含まれる

#### Scenario: 確定チャンク受信

- **WHEN** Swift 側で WhisperKit が確定チャンクを返す
- **THEN** `transcriptChunk` メッセージが JS に送信され、JS はブロック末尾にフォーマット済みテキスト行を挿入する
