# Idea: CLI feedback commands（confirm / input / select）

ステータス: 未実装（アイデア）

## Why

`chirami display` は CLI から Markdown を表示できるが、一方通行の「表示のみ」に留まる。AI エージェントの hook やシェルスクリプトでは、表示した内容に対してユーザーの判断（承認/却下）・テキスト入力・選択肢からの選択を受け取りたい。付箋 UI でフィードバックを受け取れれば、別アプリのダイアログへ切り替えずに human-in-the-loop を実現でき、"without breaking your flow" に合致する。

## What

- `chirami confirm` — Markdown 本文を表示し、下部に OK/Cancel ボタン。OK で exit 0、Cancel で exit 1
- `chirami input` — 下部にテキスト入力欄と Submit ボタン。入力テキストを stdout に出力して exit 0
- `chirami select` — 下部に選択肢ボタン。選択結果を stdout に出力して exit 0
- FIFO プロトコルを拡張し、`CLOSED` に加えて `CONFIRMED` / `CANCELLED` / `RESULT:<value>` を追加
- 既存の `display` の外部仕様は変更なし

Non-goals: 複数フィードバック要素の組み合わせ（confirm + input 同時表示）、フォーム UI（複数フィールドの構造化入力）、フィードバック UI のカスタムスタイリング。

## 設計メモ

### URI ホストによるモード分岐

既存の `chirami://display` と同じパターンで `DisplayWindowManager` のルーティングを自然に拡張できる。`display?mode=confirm` のようなクエリ方式より意図が明確。

```
chirami://confirm?content=...&callback_pipe=...
chirami://input?content=...&placeholder=...&callback_pipe=...
chirami://select?content=...&options=opt1,opt2,opt3&callback_pipe=...
```

### FIFO プロトコルの拡張

FIFO メッセージを `KEY:VALUE\n` 形式に統一する。

| メッセージ | 送信タイミング | 意味 |
|-----------|--------------|------|
| `CLOSED\n` | ウィンドウ閉じ（既存） | ウィンドウが閉じられた |
| `CONFIRMED\n` | OK ボタン押下 | ユーザーが承認した |
| `CANCELLED\n` | Cancel ボタン押下 | ユーザーがキャンセルした |
| `RESULT:<value>\n` | Submit / ボタン押下 | ユーザーの入力値・選択値 |

Go CLI 側の解釈:

| コマンド | 受信メッセージ | exit code | stdout |
|---------|--------------|-----------|--------|
| confirm | `CONFIRMED` | 0 | なし |
| confirm | `CANCELLED` / `CLOSED` | 1 | なし |
| input | `RESULT:<value>` | 0 | `<value>` |
| input | `CLOSED` | 1 | なし |
| select | `RESULT:<value>` | 0 | `<value>` |
| select | `CLOSED` | 1 | なし |

後方互換性: `display --wait` は従来通り `CLOSED` で exit 0。未知のメッセージは無視して `CLOSED` を待ち続ける。

`RESULT:` の値は改行やコロンを含みうるため URL エンコードする（Swift 側 `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` → Go 側 `url.QueryUnescape`）。

### UI レイアウト

`DisplayPanel` の `contentView` を上下 2 段構成にする。上段が Markdown コンテンツ（既存の `DisplayContentView`）、下段がフィードバック UI。

```
┌─────────────────────────┐
│ 🔒 chirami          [×] │  ← タイトルバー
├─────────────────────────┤
│  Markdown コンテンツ     │  ← DisplayContentView（既存）
├─────────────────────────┤
│  [Cancel]        [OK]   │  ← FeedbackBarView（confirm）
│  [入力欄____] [Submit]  │  ← FeedbackBarView（input）
│  [opt1] [opt2] [opt3]   │  ← FeedbackBarView（select）
└─────────────────────────┘
```

`FeedbackBarView` は AppKit の NSView サブクラスとして実装する（`DisplayContentView` と統一でき、`NSPanel.contentView` に直接追加でき、キーボードショートカット割り当てが容易）。

`DisplayPanel` に `notifyResult(_ message: String)` を追加し、FIFO へ任意メッセージを書き込んでから閉じる。内部で `didNotifyClosed = true` を立てて `notifyClosed` の二重送信を防ぐ。フィードバックボタンは `notifyResult`、× や Esc は `notifyClosed` を呼ぶことで「結果を返した」と「閉じただけ」を区別する。

### キーボード操作

- confirm: Enter で OK、Esc で Cancel、× でも Cancel
- input: Cmd+Enter で Submit（単体の Enter は改行）、`--single-line` 時は Enter で Submit、Esc でキャンセル
- select: 数字キー 1-9 で選択肢を直接選択、Esc でキャンセル

### CLI インターフェース

`confirm` / `input` / `select` は常にブロッキング動作する（`--wait` は不要で暗黙的に true）。本文は `display` と同じく引数テキスト・`--file`・stdin から受け取り、常に読み取り専用で表示する。

select の選択肢は positional arguments の 2 番目以降で渡す。stdin から本文を渡す場合は `--` で区切る。

```bash
chirami select "質問文" "選択肢1" "選択肢2" "選択肢3"
echo "質問文" | chirami select -- "選択肢1" "選択肢2"
```

却下案: `--option opt1 --option opt2`（冗長）、`--options "opt1,opt2"`（選択肢にカンマを含むと壊れる）。

### Go CLI の構成（検討時点）

```
cmd/chirami/
├── main.go            // エントリーポイント・サブコマンド登録
├── common.go          // getContent, openURI, prepareFIFO, waitForResult
├── display.go         // 既存（common を利用するようリファクタ）
├── confirm.go
├── input.go
├── select.go
└── internal/
    ├── uri.go
    └── fifo.go        // WaitForResponse（RESULT/CONFIRMED/CANCELLED を解釈）
```

## Risks / Trade-offs

- フィードバックコマンドは FIFO 必須。`callback_pipe` なしで URI を直接叩くと結果が失われる（CLI がプライマリインターフェースなので許容）
- select の選択肢はウィンドウ幅に収まる数（実用上 5〜6 個程度）。多いとボタンが折り返す
- input の複数行入力は下部バーが Markdown 領域を圧迫するため、最大高さを制限する
