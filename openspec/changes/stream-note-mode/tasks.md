## 1. 設定モデル

- [x] 1.1 `Chirami/Config/ConfigModels.swift` のノート設定に `mode` フィールド（`periodic` | `stream`、省略時 `periodic`）を追加する
- [x] 1.2 設定検証を追加する: `mode: stream` はパスに `{...}` プレースホルダを含む場合のみ有効。初版ではプレースホルダはファイル名要素のみに許可（ディレクトリ要素に含む場合は設定エラー）
- [x] 1.3 `mode: stream` と `rollover_delay` の併用時に警告ログを出す（`rollover_delay` は無視）
- [x] 1.4 既存 config.yaml（`mode` 無し）が従来どおりパースされることをユニットテストで確認する
- [x] 1.5 stream テンプレートのファイル名要素に単一の `*` ワイルドカードを許可するパース・検証を追加する（複数 `*`・ディレクトリ要素内・periodic モードでは設定エラー）

## 2. 現在ファイル解決（Latest）

- [x] 2.1 `PeriodicFileNavigator` に `latestMatchingFile()` を追加する（既存の辞書順ソート済みリストの末尾を返す）
- [x] 2.2 `PeriodicFileNavigator` の一致判定を `*`（0文字以上の任意文字列）対応にする（stream のみ）。テンプレートからの新規作成時は `*` を空文字列として解決する
- [x] 2.3 `NoteWindow` の起動時・`toggle` 時の表示ファイル解決を stream モードで latest に分岐させる
- [x] 2.4 Today ボタンを stream モードでは「Latest」に変え、`latestMatchingFile()` へ移動する動作にする
- [x] 2.5 一致ファイルが1件も無い場合、テンプレートを現在時刻で解決して新規作成する（periodic の today 不在時と同じコードパスを再利用）

## 3. ディレクトリ監視と follow

- [x] 3.1 `Chirami/Services/DirectoryWatcher.swift` を新規作成する（親ディレクトリ FD の `DispatchSource`、`.write` イベント、約200msのデバウンス）
- [x] 3.2 stream note のウィンドウに DirectoryWatcher を接続し、イベント時に一致ファイルリストを再取得して差分を検出する
- [x] 3.3 follow 動作を実装する: ウィンドウ表示中かつ latest 表示中のときのみ新 latest へ自動遷移し、それ以外はナビゲーションボタンの活性状態のみ更新する
- [x] 3.4 `WindowManager.checkRollover()` を stream note では早期 return させる
- [x] 3.5 表示中ファイルが削除された場合、残存する latest へフォールバックする（残存ゼロなら 2.4 の新規作成にフォールバック）

## 4. ホットキー

- [x] 4.1 stream モードの `toggle` が latest を開く/隠すことを確認する（2.2 の分岐で吸収されるはず）
- [x] 4.2 stream モードの `create` を「現在時刻で解決した新規ファイルを作成して開く」（クイックキャプチャ）として実装する

## 5. テスト

- [x] 5.1 `latestMatchingFile()` のユニットテスト（空ディレクトリ・1件・複数件・テンプレート不一致ファイル混在）
- [x] 5.1b ワイルドカードテンプレートのユニットテスト（スラッグ付きファイルの一致・不一致、`*` 空文字列解決での新規作成、検証エラー3種）
- [x] 5.2 DirectoryWatcher のユニットテスト（新規ファイル検知・デバウンス・不一致ファイル無視）
- [x] 5.3 follow 判定のユニットテスト（latest 表示中は遷移、過去表示中は非遷移、非表示時は非遷移）
- [x] 5.4 手動シナリオ検証: 外部スクリプトで `{yyyy-MM-dd-HHmmss}.md` を連続生成し、latest 追従・◀/▶履歴閲覧・読み返し中の非割り込みを確認する

## 6. ドキュメント

- [x] 6.1 `docs/configuration.md` の Note Settings 表に `mode` を追加する
- [x] 6.2 `docs/advanced.md` に「Stream Notes」節を追加する（用途、follow 動作、writer 契約: ゼロ埋め固定長書式・衝突時は次の秒へ繰り上げ）
- [x] 6.3 `docs/ai-integrations.md` に Claude Code Stop フック連携例（1回答=1ファイル書き出し）を追加する
