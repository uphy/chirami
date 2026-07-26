## 1. 依存関係とプロジェクト設定

- [x] 1.1 `project.yml` と native build 設定に speech engine 依存を追加し、`xcodegen generate` で Xcode プロジェクトを再生成する
- [x] 1.2 `project.yml` の minimum deployment target を macOS 14.2 に引き上げる
- [x] 1.3 `Info.plist` に `NSMicrophoneUsageDescription` を追加する（「会議の書き起こしのためマイク音声を使用します」等）
- [x] 1.4 Core Audio Process Tap に必要な entitlement（`com.apple.security.device.audio-input` 等）を追加し、App Sandbox 設定を確認する
- [ ] 1.5 `swift build` および Xcode ビルドが通ることを確認する

## 2. 設定・状態モデル

- [x] 2.1 `Chirami/Config/ConfigModels.swift` に `TranscriptConfig` 構造体を追加する（`model`, `language`, `devices.mic`, `devices.system`, `labels.mic`, `labels.system`）
- [x] 2.2 `AppConfig` に `transcript` セクションのパースと既定値適用を実装する（セクション不在時は全デフォルト）
- [x] 2.3 `AppState` に最終使用デバイス情報（`lastMic`, `lastSystemSource`）を追加する
- [x] 2.4 YAML 読み書きが後方互換であることをユニットテストで確認する（既存 config.yaml が壊れない）

## 3. モデル管理

- [x] 3.1 `Chirami/Transcript/SherpaOnnxModelStore.swift` を新規作成し、モデル保存先 `~/.local/state/chirami/models/sherpa-onnx/<model-id>/` の解決とディレクトリ作成を実装する
- [x] 3.2 sherpa-onnx 用モデル取得をラップし、進捗をコールバックで返す `downloadModel(id:progress:)` を実装する
- [x] 3.3 絶対パス指定時はダウンロードをスキップし、パス存在チェックのみ行う分岐を実装する
- [x] 3.4 ダウンロードキャンセル（URLSessionTask の cancel）と部分ダウンロードのクリーンアップを実装する
- [x] 3.5 `SherpaOnnxModelStore` のユニットテスト（未ダウンロード判定・保存先解決・キャンセル挙動）

## 4. 音声キャプチャ層

- [x] 4.1 `Chirami/Transcript/MicrophoneCapture.swift` を新規作成し、`AVAudioEngine` ベースのマイク入力を実装する（16kHz mono float への変換含む）
- [x] 4.2 `Chirami/Transcript/SystemAudioCapture.swift` を新規作成し、`CATapDescription` を用いたプロセス音声タップを実装する
- [x] 4.3 `AudioObjectGetPropertyData` で現在音声出力中のプロセス一覧を列挙する `AudioProcessEnumerator` を実装する
- [x] 4.4 `system: all` 時の「全 active output process を束ねて capture する」選択ロジックを実装する
- [x] 4.5 マイク／システム音声それぞれに RMS ベースのレベルメーター値を提供する API を追加する
- [x] 4.6 デバイス一覧列挙（`AVCaptureDevice.devices(for: .audio)`）を `AudioDeviceEnumerator` として実装する
- [ ] 4.7 キャプチャ層のユニットテスト（モック入力での動作、開始・停止・一時停止）

## 5. 書き起こしエンジン

- [x] 5.1 `TranscriptionEngine` プロトコルを定義し、具体 engine を隠蔽する（`start(audioFormat:)`, `feed(buffer:source:)`, `stop()`, `chunks: AsyncStream`）
- [x] 5.2 `SherpaOnnxEngine` を実装し、マイクとシステム音声を別ストリームとして同時処理する
- [x] 5.3 リアルタイム発話検出と確定チャンク出力の設定を適用する
- [x] 5.4 エンジン出力を `TranscriptChunk(source: .mic | .system, timestamp: TimeInterval, text: String)` としてノーマライズする
- [x] 5.5 `SherpaOnnxEngine` のユニットテスト（サンプル音声入力 → 確定チャンク出力の検証）

## 6. セッションオーケストレーション

- [x] 6.1 `Chirami/Transcript/TranscriptSession.swift` に `actor TranscriptSession` を実装し、ブロックごとの状態（Idle/Recording/Paused/Processing/Completed/Error）を管理する
- [x] 6.2 三段フォールバックのデバイス選択ロジックを実装する（block → config → system default）
- [x] 6.3 モデル未ダウンロード時は自動的に DL → 完了後に録音開始という流れを実装する
- [x] 6.4 アプリ全体で単一のアクティブセッションしか持てないよう `TranscriptSessionRegistry` シングルトンで排他制御する
- [ ] 6.5 エラー発生時の Error 状態遷移と再試行 API を実装する
- [x] 6.6 session のユニットテスト（状態遷移の網羅）

## 7. 出力フォーマッタ

- [x] 7.1 `TranscriptChunk` を `[YYYY-MM-DD HH:MM:SS] <Label>: <text>` 行に整形する `TranscriptLineFormatter` を実装する
- [x] 7.2 タイムスタンプを壁時計時刻ベースで計算し、停止/再開や複数ソース混在でも整列可能にする
- [x] 7.3 `config.yaml` の `labels` 設定を注入できるようにする
- [x] 7.4 セッション区切り `---` 挿入ロジック（追加録音時）を実装する
- [x] 7.5 フォーマッタのユニットテスト

## 8. Swift↔JS ブリッジ

- [x] 8.1 `NoteWebViewBridge` に新規メッセージを追加する（JS→Swift: `transcriptRecordStart`, `transcriptRecordPause`, `transcriptRecordResume`, `transcriptRecordStop`, `transcriptRecordClear`, `transcriptDevicesRequest`, `transcriptDeviceSelect`）
- [x] 8.2 Swift→JS 通知を実装する（`transcriptStateChanged`, `transcriptChunk`, `transcriptLevelUpdate`, `transcriptDevicesList`, `transcriptModelDownloadProgress`, `transcriptError`）
- [x] 8.3 メッセージペイロード（ブロック ID・タイムスタンプ・レベル値等）の JSON スキーマを定義する
- [x] 8.4 `TranscriptSession` と `NoteWebView` 間のディスパッチャを `NoteWindow.swift` 周辺に配線する

## 9. CodeMirror 拡張（editor-web）

- [x] 9.1 `editor-web/src/extensions/transcript.ts` を新規作成する（`excalidraw.ts` を参照元にする）
- [x] 9.2 ` ```transcript ` フェンスの検出とウィジェットデコレーションを実装する（カーソル位置に応じて表示/非表示）
- [x] 9.3 `editor-web/src/transcript-widget.tsx` でウィジェット UI を実装する（状態バッジ、タイマー、レベルメーター、デバイス表示、コントロールボタン群）
- [x] 9.4 デバイス選択ポップオーバー UI を実装する（マイク選択プルダウン、システム音声プロセス選択）
- [x] 9.5 Swift からの `transcriptChunk` を受けてブロック末尾に append する処理を実装する（`userEvent: "input.transcript"` タグ付き、カーソル非侵襲）
- [x] 9.6 状態表示（Idle / Recording / Paused / Processing / Completed / Error）ごとの UI 切替を実装する
- [x] 9.7 追加録音時の `---` セパレータ挿入を JS 側でも実装する
- [x] 9.8 モデルダウンロード進捗表示 UI を実装する
- [x] 9.9 `mise run build:editor` で `Chirami/Resources/editor/` に成果物が出力されることを確認する

## 10. 権限・エラーハンドリング

- [x] 10.1 マイク権限ダイアログを初回録音時にのみ発火するよう制御する（起動時には発火させない）
- [ ] 10.2 マイク権限拒否時の Error 状態表示（「システム設定を開く」導線つき）を実装する
- [ ] 10.3 Core Audio Process Tap 権限の事前説明 UI をウィジェット内で表示してからシステムダイアログへ遷移する
- [ ] 10.4 Tap クラッシュ・プロセス終了を検知し `transcriptError` を発行する
- [ ] 10.5 macOS 14.2 未満で `transcript` ブロックを開いた場合の明示的エラー表示
- [ ] 10.6 モデル DL 失敗時の再試行 UI

## 11. ロギング

- [ ] 11.1 `subsystem == "io.github.uphy.Chirami"`, `category == "Transcript"` で OSLog を整備する
- [ ] 11.2 成功時（録音開始・停止・モデル DL 完了）は `info`、設定不整合は `warn`、権限拒否・タップ失敗は `error`、チャンク受信等の詳細は `debug` で出力する

## 12. 手動検証

- [ ] 12.1 実機で Zoom を起動し、`system: all` でマイクと Zoom 音声の両方が書き起こされることを確認する
- [ ] 12.2 AirPods 接続・切断切替でフォールバックが期待どおり動作することを確認する
- [ ] 12.3 60 分以上の長時間録音で CPU・メモリ・温度が許容範囲内であることを確認する
- [ ] 12.4 生成された書き起こしを Obsidian で開き、プレーン Markdown として正しく表示・編集可能であることを確認する
- [ ] 12.5 アプリ再起動時の録音中断・途中までのテキスト保存が期待通りであることを確認する
- [ ] 12.6 日本語・英語・日英混在会議での認識精度を確認する（default `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`）

## 13. ドキュメント

- [x] 13.1 `CLAUDE.md` に `transcript` ブロックのセクションを追加する（excalidraw ブロックの書き方を参考に）
- [x] 13.2 `config.yaml` のサンプル / README へ `transcript:` セクションの例を追記する
- [x] 13.3 macOS 14.2 以上が必要である旨、および初回モデルダウンロードサイズを README に明記する
