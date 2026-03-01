## Context

ChiramiはAppKit+SwiftUIのハイブリッド構成のmacOSアプリ。メニューバー常駐型（LSUIElement）で、常に起動している前提で設計する。

CLIから`chirami`サブコマンドを呼び出すアプローチとして、独立Swiftバイナリではなく**URI scheme + Go CLI**方式を採用する。Chirami.appがURIハンドラとしてウィンドウを開き、Go CLIがブロッキングと入力前処理を担う。Go CLIはサブコマンド構造（`chirami display`, 将来は `chirami append` 等）を持ち、共通処理（URLエンコード・FIFO管理・URI構築）を一箇所に集約する。

## Goals / Non-Goals

**Goals:**
- `chirami://display` URI schemeをChirami.appに実装する
- ファイルモードでは編集可能・自動保存、テキスト/stdinモードでは読み取り専用
- FIFOを使ったコールバック機構で `--wait` フラグ時のブロッキングを実現する
- サブコマンド構造を持つ Go CLI バイナリ（`chirami`）で入力前処理を担う
- 将来の `chirami append` 等のサブコマンド追加を見越した拡張可能な構造にする
- Chirami.appが未起動の場合は自動起動して表示する

**Non-Goals:**
- ウィンドウ位置・サイズの永続化
- ホットキー・Karabiner連携

## Decisions

### アーキテクチャ: URI scheme + Go CLI

**決定**: 独立Swiftバイナリではなく、URI scheme + Go CLI方式を採用する。

```
[chirami display (Go CLI)]          [Chirami.app]
    ↓ 1. 入力を受け取る
    ↓ 2. 長いコンテンツはtmpfileに書き出す（os.CreateTemp）
    ↓ 3. --wait時: FIFOを作成する
    ↓ 4. open "chirami://display?..."  ──────────→  URIハンドラでウィンドウを開く
    ↓    --waitなし: そのままexit 0（tmpfileはOSに任せて削除しない）
    ↓    --wait時: FIFOをスキャンしてブロック
    ↓                                  ←──────────  ウィンドウ閉時にCLOSED送信
    ↓ 5. CLOSED受信 → exit 0
    ↓    read error（Chirami.appクラッシュ等によるEOF）→ exit 1
```

**独立Swiftバイナリと比べた利点:**
- 新しいXcodeターゲット・ビルド設定が不要
- `Chirami/Editor/`のソース共有の複雑さがない
- サブコマンド構造で `chirami append` 等を自然に追加できる
- URLエンコード・FIFO管理・URI構築の共通処理を一箇所に集約できる
- Chirami.appの既存ウィンドウ管理コードを再利用できる

**前提条件:** Chirami.appがメニューバーに常駐していること（プロダクトビジョンの前提と一致）

### Go CLIのサブコマンド構造

**決定**: `cobra` パッケージでサブコマンドを実装する。今回のスコープは `display` のみ。

```
cmd/chirami/
├── main.go           // エントリーポイント・サブコマンド登録
├── display.go        // display サブコマンド
└── internal/
    ├── uri.go        // URI構築・URLエンコード
    └── fifo.go       // FIFO作成・待機・クリーンアップ
```

将来 `append` サブコマンドを追加する際は `display.go` と同じ構造で `append.go` を追加するだけ。

### CPUアーキテクチャ: arm64のみ

**決定**: arm64（Apple Silicon）のみビルドする。Intel MacはRosetta 2で透過的に動作するため、ユーザー体験に影響しない。

Universal binary（`lipo`）でも3行追加するだけだが、現時点では不要な複雑さと判断する。ユーザー需要が出た時点でUniversal化する。

**ビルド:**
```bash
GOOS=darwin GOARCH=arm64 go build -o chirami ./cmd/chirami
```

### URI scheme インターフェース

```
chirami://display?file=/path/to/file.md&callback_pipe=/tmp/chirami.XXXX
chirami://display?content=URL%2Dencodedtext&callback_pipe=/tmp/chirami.XXXX
```

**パラメータ:**
- `file`: 表示するファイルの絶対パス（編集可能モード）
- `content`: URL-encodedテキスト（読み取り専用モード）
- `callback_pipe`: ウィンドウ閉時に書き込むFIFOパス（省略可能 = ノンブロッキング）

`file` と `content` が同時に指定された場合は `file` を優先する。

### Goラッパーの入力前処理

**決定**: コンテンツが一定サイズを超える場合はtmpfileに書き出して `file=` として渡す。

```go
const maxContentSize = 4096  // task 0.1 の実測結果に基づき確定する（仮置き）

if len(content) > maxContentSize {
    // tmpfileに書き出してfile=で渡す（読み取り専用モード）
    tmpPath = writeTmpFile(content)
    uriParam = "file=" + tmpPath
    isTmpFile = true
} else {
    uriParam = "content=" + url.QueryEscape(content)
}
```

tmpfileは `--wait` フラグ時のみラッパー終了時（CLOSED受信後）に削除する。ノンブロッキング時はOS（macOS）の `/tmp/` 定期クリーンアップに任せる（`os.CreateTemp("", "chirami-*")` で生成）。tmpfileをfile=で渡すときはChirami側で「tempファイルかどうか」を区別できないため、ラッパーが `readonly=1` パラメータを追加することで読み取り専用を強制する。

**パラメータの更新:**
- `readonly=1`: ファイルパスが渡されていても読み取り専用にする（stdin/引数コンテンツのtmpfile渡しに使用）

### FIFOコールバックによるブロッキング

**決定**: Named pipe（FIFO）を使ってラッパーをブロックする。FIFOは `--wait` フラグ時のみ作成し、`callback_pipe` パラメータとしてURIに含める。

セキュリティ上の理由から、callbackに任意のシェルコマンドを受け付けない。`callback_pipe` はFIFOファイルパスのみ受け付け、Chirami.appは「そのパスにopen()してwrite()する」だけ。シェルを介さないためコマンドインジェクションが不可能。

**パスのバリデーション:** `/tmp/` または `$TMPDIR` 以下のパスのみ受け付ける。

**FIFOメッセージプロトコル:**

Chirami.appはFIFOに以下のメッセージを送信する。

| メッセージ | タイミング | 意味 |
|-----------|-----------|------|
| `CLOSED\n` | ウィンドウ閉時 | 正常終了通知 |

Go CLIの動作:

- `CLOSED` 受信 → exit 0
- Chirami.appがクラッシュした場合はFIFOがEOFになるため、Go CLIはread errorを検出してexit 1

tmpfileおよびFIFOは明示的に削除しない。`/tmp/` はmacOSが定期的にクリーンアップするため許容範囲内。

**ノンブロッキング使用:**
`--wait` なし時はFIFOを作成しない。`open` コマンド発行後すぐにexit 0。

### 編集モード: ファイルモード vs 読み取り専用モード

**決定**: 入力種別によってウィンドウの編集可否を切り替える。

| 入力 | パラメータ | モード | 保存 |
|------|-----------|--------|------|
| `--file <path>` | `file=/path` | 編集可能 | キーストロークごとに自動保存 |
| テキスト引数 | `content=...` | 読み取り専用 | なし |
| stdin | `content=...` または `file=tmppath&readonly=1` | 読み取り専用 | なし |

**自動保存の実装:** 既存の`NoteContentModel.save()`と同じパターンを踏襲する。
- `textDidChange()` → `lastSavedContent`と比較 → 異なれば`String.write(to:atomically:encoding:)`
- 重複書き込みを`lastSavedContent`で防ぐ

### Chirami.app側の実装箇所

**決定**: `AppDelegate.application(_:open:)` にURIハンドラを追加し、`DisplayWindowManager`（新規）でウィンドウを管理する。SwiftUI の `.onOpenURL` ではなく AppKit の `NSApplicationDelegate.application(_:open:)` を使うことで、既存の `AppDelegate` に実装を集約し一貫性を保つ。

既存の`NotePanel`・`NoteWindowController`は`AppConfig.shared`への依存が強いため流用しない。`DisplayPanel`（軽量NSPanelサブクラス）を新規作成する。

`DisplayWindowManager` は `[DisplayWindowController]` の配列でウィンドウを保持し、URIを受け取るたびに新しいウィンドウを追加する（複数ウィンドウ対応）。閉じたウィンドウは配列から除去する。

**DisplayPanel設計:**
- `styleMask`: `.titled, .closable, .resizable, .nonactivatingPanel`
- `collectionBehavior`: `.canJoinAllSpaces, .fullScreenAuxiliary`
- `level`: `.floating`（always-on-top）
- ESCキー・閉じるボタンで heartbeat timerを停止 → `CLOSED\n` をFIFOに書き込み → `close()`

### 配布形態

**決定**: Go CLIバイナリ（`chirami`）を`Chirami.app/Contents/MacOS/`に同梱する。

`mise.toml`の`build`タスクで`GOARCH=arm64 go build`してバンドル内に配置する。Homebrew Cask の `binary` stanza でインストール時に自動的に symlink が作成されるため、ユーザーは追加の設定不要で `chirami` コマンドを使用できる。

```ruby
binary "#{appdir}/Chirami.app/Contents/MacOS/chirami"
```

### Chirami.app自動起動

**決定**: `open "chirami://display?..."` コマンドはmacOSが自動的にChirami.appを起動してからURIを渡すため、Go CLI側で追加の起動処理は不要。

macOSのURL scheme仕組みにより、`open` コマンドは:
1. Chirami.appが起動中 → URIを渡す
2. Chirami.appが未起動 → 起動してからURIを渡す

`NSApplicationDelegate.application(_:open:)` は起動完了後に呼ばれるため、URIハンドラが確実に実行される。

### stdin判定ルール

**決定**: Go CLIでは `os.Stdin.Stat()` の `ModeCharDevice` フラグでTTYとパイプを区別する。

```go
stat, _ := os.Stdin.Stat()
if (stat.Mode() & os.ModeCharDevice) == 0 {
    // stdin はパイプ → 読み込む
}
```

TTYから直接 `chirami display` を実行した場合はstdinを読まない（コンテンツなしとみなす）。

### 読み取り専用モードのレンダリング

**決定**: 読み取り専用モードでは Live Preview を使用せず、常に全面レンダリング表示する。

| モード | 表示方式 |
|--------|---------|
| 編集可能（`--file`） | Live Preview（カーソル行のみ raw Markdown） |
| 読み取り専用（引数・stdin） | 常に全面レンダリング |

Live Previewは編集体験のための機能であり、閲覧専用の一時表示には不要。AIエージェントのhookからの出力表示など、読み取り専用のユースケースでは常にレンダリング済み表示の方が自然。

**実装方法:** `MarkdownStyler.style(_:cursorLocation:)` に `cursorLocation: -1`（または範囲外の任意の負値）を渡す。`findCursorBlock` はどのブロックにも一致しない場合 `nil` を返すため、全ブロックが `applyBlockStyle`（レンダリング済み）で処理される。呼び出し側のコードに意図を示すため、`MarkdownStyler` に `func styleAll(_ text: String) -> NSAttributedString` の convenience overload を追加することを推奨する。

読み取り専用モードであることはタイトルバーの 🔒 アイコンで示す。`DisplayPanel` の `title` プロパティを `"🔒 chirami"` に設定する。編集可能モードでは `"chirami"` のみ。

## Risks / Trade-offs

- **Chirami.app初回起動の遅延** → 未起動状態からの初回起動時はウィンドウ表示まで数秒かかる場合がある。`--wait` 使用時はFIFOを作成してから `open` するため、アプリ起動前にFIFO readでブロックするが、アプリ起動後にFIFO writeが来るまで正常に待機できる
- **tmpfileの取り扱い** → tmpfileおよびFIFOは明示的に削除しない。`/tmp/`はmacOSが定期的にクリーンアップするため許容範囲内。クリーンアップロジックを持たないことで実装を簡素化する
- **FIFOパスのバリデーション** → `/tmp/`チェックのみでは不十分な場合（シンボリックリンク等）。実用上は許容範囲内
