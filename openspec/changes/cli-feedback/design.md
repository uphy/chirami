## Context

`chirami display` は URI scheme + Go CLI 方式でフローティングウィンドウにMarkdownを表示する。Go CLIが入力前処理とFIFO管理を担い、Chirami.appがウィンドウ表示を担当する。FIFOプロトコルは現在 `CLOSED\n` のみ。

この基盤の上に `confirm`, `input`, `select` サブコマンドを追加する。各コマンドはMarkdown本文の表示に加えて、下部にフィードバックUI（ボタン、テキスト入力）を配置し、ユーザーの応答をFIFO経由でCLIに返す。

## Goals / Non-Goals

**Goals:**

- `chirami confirm`, `chirami input`, `chirami select` サブコマンドを追加する
- FIFOプロトコルを拡張して応答メッセージを返せるようにする
- フィードバックUIはMarkdownコンテンツ領域の下部に分離して配置する
- 各コマンドの共通処理（コンテンツ取得・URI構築・FIFO待機）を既存コードと共有する

**Non-Goals:**

- 複数フィードバック要素の組み合わせ（confirm + input 同時表示など）
- フォームUI（複数フィールドの構造化入力）
- フィードバックUIのカスタムスタイリング

## Decisions

### URIホストによるモード分岐

**決定**: `chirami://confirm`, `chirami://input`, `chirami://select` として、URIのホスト部分でモードを分岐する。

```
chirami://confirm?content=...&callback_pipe=...
chirami://input?content=...&placeholder=...&callback_pipe=...
chirami://select?content=...&options=opt1,opt2,opt3&callback_pipe=...
```

**理由**: 既存の `chirami://display` と同じパターンで、`DisplayWindowManager` のルーティングを自然に拡張できる。`display?mode=confirm` のようなクエリパラメータ方式よりもURLの意図が明確。

### FIFOプロトコルの拡張

**決定**: FIFOメッセージを `KEY:VALUE\n` 形式に統一する。

| メッセージ | 送信タイミング | 意味 |
|-----------|--------------|------|
| `CLOSED\n` | ウィンドウ閉じ（既存） | ウィンドウが閉じられた |
| `CONFIRMED\n` | OKボタン押下 | ユーザーが承認した |
| `CANCELLED\n` | Cancelボタン押下 | ユーザーがキャンセルした |
| `RESULT:<value>\n` | Submit/ボタン押下 | ユーザーの入力値/選択値 |

Go CLI側の処理:

| コマンド | 受信メッセージ | exit code | stdout |
|---------|--------------|-----------|--------|
| confirm | `CONFIRMED` | 0 | なし |
| confirm | `CANCELLED` or `CLOSED` | 1 | なし |
| input | `RESULT:<value>` | 0 | `<value>` |
| input | `CLOSED` | 1 | なし |
| select | `RESULT:<value>` | 0 | `<value>` |
| select | `CLOSED` | 1 | なし |

**後方互換性**: `display --wait` は従来通り `CLOSED` を受け取りexit 0。既存コードへの影響なし。

### RESULT値のエスケープ

**決定**: `RESULT:` の値はURLエンコード（percent-encoding）する。

input で改行やコロンを含む入力が可能なため、行ベースのプロトコルと衝突しないようにする。Swift側で `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` でエンコードし、Go側で `url.QueryUnescape` でデコードする。

### Go CLIの共通処理抽出

**決定**: `display.go` から共通処理を抽出し、各コマンドで再利用する。

```
cmd/chirami/
├── main.go            // エントリーポイント・サブコマンド登録
├── common.go          // 共通処理: getContent, openURI, waitForResult
├── display.go         // display サブコマンド (既存、commonを利用するようリファクタ)
├── confirm.go         // confirm サブコマンド
├── input.go           // input サブコマンド
├── select.go          // select サブコマンド
└── internal/
    ├── uri.go
    └── fifo.go        // WaitForResponse 追加 (RESULT/CONFIRMED/CANCELLEDを解釈)
```

**共通関数:**

- `getContent(args, fileFlag)` — 既存。引数/ファイル/stdinからコンテンツ取得
- `openURI(subcommand, params)` — URI構築 → `open -g` 実行
- `internal.WaitForResponse(pipePath)` — FIFOからメッセージを1行読み取り、パース済みの `Response` 構造体を返す

### フィードバックUIのレイアウト

**決定**: `DisplayPanel` の `contentView` を上下2段構成にする。上段がMarkdownコンテンツ（既存の `DisplayContentView`）、下段がフィードバックUI。

```
┌─────────────────────────┐
│ 🔒 chirami          [×] │  ← タイトルバー
├─────────────────────────┤
│                         │
│  Markdown コンテンツ     │  ← DisplayContentView (既存)
│                         │
├─────────────────────────┤
│  [Cancel]        [OK]   │  ← FeedbackBarView (新規, confirm)
│  [入力欄____] [Submit]  │  ← FeedbackBarView (新規, input)
│  [opt1] [opt2] [opt3]   │  ← FeedbackBarView (新規, select)
└─────────────────────────┘
```

**FeedbackBarView の実装方針:**

AppKitベースの NSView サブクラスとして実装する。理由:

- DisplayPanelの他のコンポーネント（DisplayContentView）と統一
- NSPanel の `contentView` に直接追加できる
- ボタンのキーボードショートカット割り当てが容易

### confirm のキーボード操作

**決定**: confirm モードではEnterでOK、EscでCancelを割り当てる。

- Enter / Return → `CONFIRMED` 送信 → ウィンドウ閉じ
- Esc → `CANCELLED` 送信 → ウィンドウ閉じ
- ウィンドウの閉じるボタン（×）→ `CANCELLED` 送信 → ウィンドウ閉じ

### input のキーボード操作

**決定**: input モードではCmd+EnterでSubmit、EscでCancel（ウィンドウ閉じ）を割り当てる。

単体のEnterはテキスト入力の改行に使用するため、Submitには Cmd+Enter を使う。ただし `--single-line` フラグ時はEnterでSubmitする。

### select のキーボード操作

**決定**: 数字キー(1-9)で選択肢を直接選択できる。Escでウィンドウ閉じ。

### フィードバックコマンドの暗黙的 --wait

**決定**: `confirm`, `input`, `select` は常にブロッキング動作する。`--wait` フラグは不要（暗黙的にtrue）。

フィードバックコマンドは結果を返すことが目的であり、ノンブロッキングで実行する意味がない。

### select のオプション渡し方式

**決定**: 選択肢はpositional argumentsの2番目以降で渡す。

```bash
chirami select "質問文" "選択肢1" "選択肢2" "選択肢3"
```

stdinから質問文を渡す場合は `--` で区切る:

```bash
echo "質問文" | chirami select -- "選択肢1" "選択肢2"
```

**代替案（却下）**: `--option opt1 --option opt2` — 冗長。カンマ区切り `--options "opt1,opt2,opt3"` — 選択肢にカンマを含む場合に問題。

### タイトルバー表示

**決定**: フィードバックコマンドのウィンドウも読み取り専用として `🔒 chirami` を表示する。Markdown本文はすべて読み取り専用。

### DisplayPanel の拡張: notifyResult

**決定**: `DisplayPanel.notifyClosed()` に加えて `notifyResult(_ message: String)` を追加する。

`notifyResult` はFIFOに任意のメッセージを書き込んでからウィンドウを閉じる。`notifyClosed` は従来通り `CLOSED\n` を送信する。

フィードバックボタンからは `notifyResult` を呼び、閉じるボタン（×）やEscは `notifyClosed` を呼ぶことで、「結果を返した」のか「閉じただけ」なのかを区別できる。実装として `notifyResult` は内部で `didNotifyClosed = true` を設定し、その後 `close()` を呼ぶことで `notifyClosed` の二重送信を防ぐ。

## Risks / Trade-offs

- **フィードバックコマンドはFIFO必須** → `callback_pipe` なしだと結果を返せない。Go CLI側で常にFIFOを作成するため問題にはならないが、URIを直接叩くユースケースでは `callback_pipe` がないと結果が失われる。これは許容する（CLIがプライマリインターフェース）
- **select の選択肢数制限** → ウィンドウ幅に収まる数（実用上5-6個程度）。多すぎる場合はボタンが折り返し表示される。UIの破綻は起きないが見栄えは悪い。ドキュメントで推奨数を記載する
- **input の長文入力** → テキスト入力欄はデフォルトで1行表示。`--single-line` なしの場合は複数行入力可能で高さが自動調整されるが、下部バーの占有面積が大きくなりMarkdownコンテンツ領域が狭まる。最大高さを制限する
