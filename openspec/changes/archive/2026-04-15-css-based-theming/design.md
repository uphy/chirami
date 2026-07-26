## Context

現在 Chirami のテーマ管理は Swift/YAML パイプラインで実装されている。

```
color_schemes.yaml → ColorSchemeRegistry → ColorSchemeCSSConverter
  → NoteWebView.setTheme() → JS bridge → theme.ts → :root CSS変数
```

ノートごとに `colorScheme`/`font`/`fontSize` を `config.yaml` で指定できるが、定義済みの色セットからしか選べず、ユーザーが独自にカスタマイズする手段がない。WebView ベースのエディタに移行済みであるため、CSS ネイティブな仕組みに置き換える余地がある。

## Goals / Non-Goals

**Goals:**

- ユーザーが CSS ファイルで外観を自由にカスタマイズできるようにする
- ビルトインテーマ（組み込み CSS）を用意し、設定なしでも動作させる
- per-note テーマ名（`data-chirami-theme` 属性）をサポートする
- `--chirami-*` CSS 変数を public API として互換性を維持する

**Non-Goals:**

- ノートごとに個別 CSS ファイルを指定する機能（グローバル + テーマ名で十分）
- CSS 変数以外のカスタマイズ（DOM 構造変更など）のサポート保証
- 既存 `config.yaml` 設定の自動マイグレーション

## Decisions

**CSS ロード方式: `WKUserContentController.addUserStyleSheet`**

WKWebView には `WKUserStyleSheet` を注入する API がある。ファイルを読み込んで文字列として渡すことで、ページ HTML を変更せずに CSS を適用できる。ビルトイン CSS と ユーザー CSS をそれぞれ別の `WKUserStyleSheet` として追加し、ユーザー CSS を後にロードすることで上書きを実現する。

代替: `<link>` タグを HTML テンプレートに埋め込む案もあるが、ファイルパスの `file://` URL 解決が複雑になる。`WKUserStyleSheet` の方がシンプル。

**テーマ切り替え: `data-chirami-theme` 属性注入**

Swift 側で `<html>` 要素に `data-chirami-theme="<name>"` を JS 経由で注入する。CSS 側は `[data-chirami-theme="monokai"] { ... }` で対応する変数を定義する。

`theme` 未指定のノートには属性を付与しない。CSS の `:root` デフォルト値が適用される。

**dark/light 対応: CSS media query に委譲**

`@media (prefers-color-scheme: dark)` を CSS 側で定義する。Swift からの `isDark` フラグ送信は廃止し、OS の dark mode 検知は WebKit に任せる。

**`--chirami-*` 変数を public API とする**

ドキュメント化した変数名のみが互換性保証の対象。その他の変数はアプリ内部で使う場合があるが非公開扱い。削除・リネームが必要な場合はメジャーリリースで行う。

現在の public 変数セット:

| 変数名 | 用途 |
|---|---|
| `--chirami-bg` | ノート背景色 |
| `--chirami-text` | 本文テキスト色 |
| `--chirami-link` | リンク色 |
| `--chirami-code` | インラインコード文字色 |
| `--chirami-code-bg` | インラインコード背景色 |
| `--chirami-selection` | テキスト選択色 |
| `--chirami-font` | フォントファミリー |
| `--chirami-font-size` | フォントサイズ |

## NSPanel 背景色の問題

付箋のタイトル部分（`NSPanel` 自体）の背景色は `colorScheme.nsColor` から取得している。WebView 内の CSS だけ変えても `NSPanel` フレームには反映されないため、WebView 背景と `NSPanel` 背景がずれるとリサイズ時や余白でちらつきが生じる。

過去にも実装難度が高かった箇所であり、実際に動かさないと判断できない部分がある。

**考えられる方向性:**

- **WebView 背景を透明にして NSPanel に合わせる** — WebView の `isOpaque = false` + `backgroundColor = .clear` にし、NSPanel 側の色を引き続き管理する。ただし WebView 透明化は macOS バージョンによって挙動が不安定になることがあり、動かない可能性がある
- **NSPanel 背景を透明にして WebView 背景に合わせる** — NSPanel を透明にし、見た目の背景は CSS 側の `--chirami-bg` のみで制御する。影や角丸など AppKit 依存の装飾が崩れる可能性がある
- **デフォルト固定色にして CSS と揃える** — NSPanel 背景をデフォルト色（例：yellow の light 値）にハードコードし、CSS 側のデフォルト値と手動で合わせる。ユーザーがカスタムCSSで背景色を変えると必ずズレが出る
- **JS → Swift コールバックで CSS 変数値を取得して NSPanel に反映** — ロード完了時に JS で `getComputedStyle` を実行し `--chirami-bg` の実値を Swift に渡して `NSPanel.backgroundColor` に適用する。動的テーマ切り替えも対応できるが bridge が増える

現時点では **「WebView 背景を透明にして NSPanel に合わせる」** 方向がシンプル。ただし透明化が動作しない場合は別のアプローチに切り替える必要がある。実装時に動作を確認してから方針を確定する。

## Risks / Trade-offs

**ユーザー CSS の読み込み失敗** → `cssFile` が存在しない or 読み込みエラーの場合はビルトイン CSS のみで動作し、warning ログを出力する。クラッシュしない。

**`WKUserStyleSheet` の動的更新** → アプリ起動中に CSS ファイルを変更してもホットリロードはしない。変更を反映するにはノートウィンドウの再起動が必要。初期実装ではこれを許容する。

**既存ユーザーの破壊的変更** → `colorScheme`/`font`/`fontSize` が `config.yaml` に残っていても無視される。エラーにはせず warning ログのみ。ただし現時点で未リリースのため実質影響なし。

**Excalidraw の白背景** → `style.css` の `.cm-excalidraw-container { background: white }` はハードコードされており、ダークテーマ時に浮く。本 change のスコープ外とし、別途対応する。

## Migration Plan

未リリースのため自動マイグレーション不要。`config.yaml` の旧フィールドは warning を出して無視する。

## Open Questions

なし
