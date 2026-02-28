## 1. プロジェクト構成

- [ ] 1.1 `ChiramiDisplay/` ディレクトリを作成する
- [ ] 1.2 `project.yml` に `ChiramiDisplay` ターゲット（type: application）を追加し、`Chirami/Editor/` を shared sources として参照する
- [ ] 1.3 `ChiramiDisplay/Info.plist` を作成する（`LSUIElement = true`, `NSPrincipalClass = NSApplication`）
- [ ] 1.4 `ChiramiDisplay/ChiramiDisplay.entitlements` を作成する（サンドボックスなし）
- [ ] 1.5 `mise run generate` でXcodeプロジェクトを再生成し、ビルドが通ることを確認する

## 2. 引数パーサーの実装

- [ ] 2.1 `ChiramiDisplay/ArgumentParser.swift` を作成し、`--file`, `--help`, 位置引数テキスト, stdin の4入力形式をパースする関数を実装する
- [ ] 2.2 入力優先順位（引数 > ファイル > stdin）のロジックを実装する
- [ ] 2.3 stdin が端末（isatty）かどうかを判定し、端末の場合はstdin読み取りをスキップするロジックを追加する
- [ ] 2.4 `--help` フラグ時にusageをstdoutに出力してexit 0する処理を実装する
- [ ] 2.5 コンテンツが得られなかった場合にstderrにusageを出力してexit 1する処理を実装する

## 3. DisplayPanel の実装

- [ ] 3.1 `ChiramiDisplay/DisplayPanel.swift` を作成する（NSPanelサブクラス）
- [ ] 3.2 ESCキーと閉じるボタンで `NSApp.terminate(nil)` を呼ぶ `sendEvent` と `performClose` を実装する
- [ ] 3.3 パネルを `.floating` レベルで初期化し、`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` を設定する

## 4. DisplayContentView の実装

- [ ] 4.1 `ChiramiDisplay/DisplayContentView.swift` を作成する（NSTextView + NSScrollView）
- [ ] 4.2 `BulletLayoutManager` を使用して NSTextStorage + NSLayoutManager + NSTextContainer を構成する
- [ ] 4.3 `NSTextView` を `isEditable = false, isSelectable = true` で設定する
- [ ] 4.4 `MarkdownStyler` を使用してMarkdownコンテンツをNSAttributedStringに変換してテキストビューに適用する
- [ ] 4.5 NSScrollView でラップしてスクロール対応にする

## 5. DisplayWindowController の実装

- [ ] 5.1 `ChiramiDisplay/DisplayWindowController.swift` を作成する（NSWindowControllerサブクラス）
- [ ] 5.2 コンストラクタでコンテンツ文字列を受け取り、DisplayPanel と DisplayContentView を構成する
- [ ] 5.3 デフォルトウィンドウサイズ（幅 400 × 高さ 500 程度）と画面中央配置のロジックを実装する

## 6. エントリーポイントの実装

- [ ] 6.1 `ChiramiDisplay/main.swift` を作成する
- [ ] 6.2 `CommandLine.arguments` をArgumentParserでパースしてコンテンツ文字列を取得する
- [ ] 6.3 `NSApplication.shared` を `.accessory` アクティベーションポリシーで設定する
- [ ] 6.4 `DisplayWindowController` を作成してウィンドウを表示する
- [ ] 6.5 `NSApplication.shared.run()` でメインループを開始しウィンドウが閉じるまでブロックする

## 7. ビルドと配布

- [ ] 7.1 `mise run build` で `ChiramiDisplay.app` がビルドされることを確認する
- [ ] 7.2 ビルドスクリプトで `chirami-display` バイナリを `Chirami.app/Contents/MacOS/` にコピーする（または `mise.toml` の build タスクを更新する）
- [ ] 7.3 `chirami-display "## Test\nHello"` を手動実行してフローティングウィンドウが表示されることを確認する
- [ ] 7.4 `echo "# Stdin Test" | chirami-display` でstdin入力が動作することを確認する
- [ ] 7.5 `chirami-display --file ~/Notes/test.md` でファイル入力が動作することを確認する
- [ ] 7.6 ESCキーおよびウィンドウの閉じるボタンでexit code 0で終了することを確認する
- [ ] 7.7 存在しないファイルパスでexit code 1・stderrエラーが出ることを確認する
