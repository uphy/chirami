## Context

ChiramiはAppKit+SwiftUIのハイブリッド構成のmacOSアプリ。メインのエントリーポイントは`@main ChiramiApp`（SwiftUI App）で、メニューバーアイコンとノートウィンドウを管理する。

CLIから`chirami display`を呼び出すには、メインアプリとは独立した別の実行バイナリが必要。`Chirami/Editor/`にある`MarkdownStyler`・`BulletLayoutManager`は再利用価値が高い。

## Goals / Non-Goals

**Goals:**
- `ChiramiDisplay`という新しいXcodeターゲット（アプリバンドル or ツール）を追加する
- `MarkdownStyler`・`BulletLayoutManager`をメインアプリと共有する
- シンプルな読み取り専用フローティングウィンドウを実装する
- 引数・ファイル・stdinの3入力形式をサポートする

**Non-Goals:**
- 既存の`Chirami.app`コードへの変更
- 編集機能・ファイル保存
- ウィンドウ位置・サイズの永続化
- ホットキー・Karabiner連携

## Decisions

### ターゲット構成

**決定**: `ChiramiDisplay`を独立した`application`タイプのターゲットとしてXcodeGenに追加する。

`tool`タイプ（コマンドラインツール）ではなく`application`タイプを選択する理由：NSPanelのフローティングウィンドウ表示はGUIアプリフレームワーク上でのみ動作するため。`LSUIElement = true`にすることでDock・アプリスイッチャーに表示しない。

**代替案として検討したもの:**
- メインバイナリへのサブコマンド統合: `@main`エントリーポイントの大幅な変更が必要で責務が混在する
- `tool`タイプ: `NSApplication.run()`を使えるが、アプリバンドル構造がなくentitlementsが扱いにくい

### ソース共有方法

**決定**: `project.yml`でターゲット`ChiramiDisplay`のsourcesに`Chirami/Editor/`パスを追加して共有する。

`Chirami/Views/`のコンポーネント（`NotePanel`・`LivePreviewEditor`・`MarkdownTextView`）は`AppConfig.shared`への依存があるため共有しない。代わりに`ChiramiDisplay/`に専用の軽量コンポーネントを作成する。

### ウィンドウ実装

**決定**: `NotePanel`を継承せず、`ChiramiDisplay/`に`DisplayPanel`（NSPanelサブクラス）と`DisplayContentView`（読み取り専用NSTextView）を新規作成する。

`NotePanel`は`AppConfig.shared.data.dragModifierFlags`・`warpModifierFlags`への参照があり、設定ファイルなしで動作させるには不適。

**DisplayPanel設計:**
- `NSPanel`サブクラス
- `styleMask`: `.titled, .closable, .resizable, .nonactivatingPanel`
- `collectionBehavior`: `.canJoinAllSpaces, .fullScreenAuxiliary`
- `level`: `.floating`（always-on-top）
- `LSUIElement = true`でDock非表示
- ESCキー・閉じるボタンで`NSApp.terminate(nil)`を呼ぶ

**DisplayContentView設計:**
- `NSTextView`に`MarkdownStyler`を適用した読み取り専用ビュー
- `isEditable = false, isSelectable = true`
- `BulletLayoutManager`でカスタム描画
- `NSScrollView`でラップしてスクロール対応

### 引数パース

**決定**: `swift-argument-parser`を使用せず、`CommandLine.arguments`を手動でパースする。

`--file <path>`オプション、`--help`、位置引数（テキスト）、stdinという限られたオプション数のため、外部ライブラリ不要。依存関係を最小に保つ。

### 配布形態

**決定**: `Chirami.app/Contents/MacOS/chirami-display`としてメインアプリのバンドルに含める。

ユーザーは`~/Applications/Chirami.app/Contents/MacOS/chirami-display`または`ln -s`でシンボリックリンクを作成して利用する。`mise.toml`の`build`タスクでバンドル内に配置する。

## Risks / Trade-offs

- **サンドボックス制限** → `ChiramiDisplay`ターゲットはサンドボックスなし（`ENABLE_APP_SANDBOX = NO`）。任意のファイルパスを読む必要があるため。セキュリティリスクはCLIツールとして許容範囲内
- **ソース共有の複雑さ** → `Chirami/Editor/`は両ターゲットでコンパイルされる。将来の変更が両方に影響する点に注意
- **stdinブロッキング** → stdinが端末でない場合は`isatty(STDIN_FILENO)`で判定してブロッキング読み取りを避ける
