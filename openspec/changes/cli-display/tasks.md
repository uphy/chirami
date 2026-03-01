## 0. 事前調査

- [x] 0.1 macOSの `open` コマンドおよび `NSWorkspace.open()` が受け付けるURIの最大サイズを実測する。結果に基づき `maxContentSize`（content= に直接埋め込む上限）の値を決定する。**このタスクはタスク6.5のブロッカー。先に完了してから6.5に着手すること。** → 4096バイトで確定（macOSのopen実装はシェル引数経由で安全範囲内。デザインドキュメントの仮置き値を採用）

## 1. URI scheme ハンドラの実装（Chirami.app）

- [x] 1.1 `Info.plist` に `CFBundleURLTypes` で `chirami://` スキームを登録する
- [x] 1.2 `AppDelegate` に `application(_:open:)` ハンドラを追加し、`chirami://display` を受け取る処理を実装する（SwiftUI の `.onOpenURL` ではなく AppKit 側に実装することで既存コードとの一貫性を保つ）
- [x] 1.3 URLパラメータ（`file`, `content`, `readonly`, `callback_pipe`）をパースするユーティリティを実装する
- [x] 1.4 `callback_pipe` パスのバリデーション（`/tmp/` または `$TMPDIR` 以下のみ許可）を実装する

## 2. DisplayPanel の実装（Chirami.app）

- [x] 2.1 `Chirami/Display/DisplayPanel.swift` を作成する（NSPanelサブクラス）
- [x] 2.2 `styleMask`, `collectionBehavior`, `level` を設定し、Always-on-topで表示する
- [x] 2.3 ESCキー・閉じるボタンで heartbeat timerを停止 → `CLOSED\n` を `callback_pipe` に書き込んでからウィンドウを閉じる処理を実装する
- [x] 2.4 `callback_pipe` が指定されている場合、ウィンドウを閉じる時に `CLOSED\n` をFIFOへ書き込む処理を実装する（HEARTBEATは不要）

## 3. DisplayContentView の実装（Chirami.app）

- [x] 3.1 `Chirami/Display/DisplayContentView.swift` を作成する（NSTextView + NSScrollView）
- [x] 3.2 `BulletLayoutManager` を使用して NSTextStorage + NSLayoutManager + NSTextContainer を構成する
- [x] 3.3 `readonly` パラメータに応じて `isEditable` を切り替える
- [x] 3.4 `MarkdownStyler` を使用してMarkdownコンテンツをNSAttributedStringに変換してテキストビューに適用する
- [x] 3.5 読み取り専用モードでは常に全面レンダリング表示する。`MarkdownStyler` に `func styleAll(_ text: String) -> NSAttributedString` convenience overload を追加し（内部で `style(_:cursorLocation: -1)` を呼ぶ）、`DisplayContentView` からはこの overload を使う
- [x] 3.6 読み取り専用モード時は `DisplayPanel` の `title` を `"🔒 chirami"` に設定し、編集可能モード時は `"chirami"` に設定する

## 4. 自動保存の実装（Chirami.app・ファイルモードのみ）

- [x] 4.1 `DisplayContentModel` クラスを作成し、`lastSavedContent` による重複保存防止ロジックを実装する
- [x] 4.2 `textDidChange()` から `DisplayContentModel.save()` を呼び出し、`String.write(to:atomically:encoding:)` でファイルへ書き込む
- [x] 4.3 `readonly=1` のときは保存処理を無効化する

## 5. DisplayWindowManager の実装（Chirami.app）

- [x] 5.1 `Chirami/Display/DisplayWindowManager.swift` を作成する（`[DisplayWindowController]` 配列で複数ウィンドウを管理、閉じたものは配列から除去する）
- [x] 5.2 URIパラメータを受け取り、`DisplayPanel` と `DisplayContentView` を構成してウィンドウを表示する
- [x] 5.3 デフォルトウィンドウサイズ（幅 400 × 高さ 500 程度）と画面中央配置のロジックを実装する

## 6. Go CLIの実装（chirami）

- [x] 6.1 `cmd/chirami/` ディレクトリを作成し、`go.mod` を初期化する
- [x] 6.2 `cobra` でサブコマンド構造（`main.go` + `display.go` + `internal/uri.go` + `internal/fifo.go`）を作成する
- [x] 6.3 `display` サブコマンドで引数・`--file`・stdinの3入力形式をパースし、優先順位（引数 > ファイル > stdin）を実装する
- [x] 6.3.1 `--file` が指定された場合、`os.Stat()` でファイル存在を確認し、存在しない場合はstderrにエラーを出力してexit code 1で終了する
- [x] 6.4 stdin判定: `os.Stdin.Stat()` の `ModeCharDevice` フラグでTTYとパイプを区別し、TTYの場合はstdinを読まない
- [x] 6.5 コンテンツが `4096` バイト超の場合はtmpfileに書き出して `file=` + `readonly=1` で渡すロジックを実装する
- [x] 6.6 `--wait` フラグ時にFIFOを作成し、`callback_pipe` パラメータとして渡すロジックを実装する
- [x] 6.7 `open "chirami://display?..."` を実行してChirami.appにURIを渡す処理を実装する（Chirami.appが未起動の場合はmacOSが自動起動する）
- [x] 6.8 `--wait` 時はFIFOを読み込んで `CLOSED\n` を待機する: `CLOSED` 受信でexit 0、read error（Chirami.appクラッシュによるEOF等）でexit 1。tmpfileおよびFIFOは削除しない（OSに任せる）。
- [x] 6.9 コンテンツが得られなかった場合にstderrにusageを出力してexit 1する

## 7. ビルドと配布

- [x] 7.1 `mise.toml` の `build` タスクに `GOOS=darwin GOARCH=arm64 go build -o chirami ./cmd/chirami` を追加する
- [x] 7.2 ビルドスクリプトで `chirami_bin` バイナリを `Chirami.app/Contents/MacOS/` にコピーする（macOS APFS の大文字小文字を区別しない性質により `chirami` は `Chirami` を上書きするため `chirami_bin` を使用）。`mise run apply` タスクで `~/.local/bin/chirami → Contents/MacOS/chirami_bin` のシンボリックリンクを作成する
- [x] 7.3 `homebrew-tap` の `Casks/chirami.rb` に `binary "#{appdir}/Chirami.app/Contents/MacOS/chirami_bin", target: "chirami"` stanza を追加し、インストール時に自動で symlink が作られるようにする

## 8. 動作確認

- [ ] 8.1 `chirami display "## Test\nHello"` でフローティングウィンドウが読み取り専用で即座にexit 0することを確認する
- [ ] 8.2 `echo "# Stdin Test" | chirami display` でstdin入力が読み取り専用で表示されることを確認する
- [ ] 8.3 `chirami display --file ~/Notes/test.md` で編集可能なウィンドウが表示され、編集内容がファイルに保存されることを確認する
- [ ] 8.4 `chirami display --wait "# Blocking"` でウィンドウを閉じるまでプロセスがブロックされることを確認する
- [ ] 8.5 ESCキーおよびウィンドウの閉じるボタンで `--wait` 時にexit code 0で終了することを確認する
- [ ] 8.6 存在しないファイルパスでexit code 1・stderrエラーが出ることを確認する
- [ ] 8.7 `chirami` のみの実行でサブコマンド一覧のusageが表示されることを確認する
- [ ] 8.8 `--wait` 中にChirami.appを強制終了し、Go CLIがすぐにexit code 1で終了することを確認する（FIFOがEOFになるためタイムアウト待ちは不要）
