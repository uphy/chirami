# ADR 0010: Frontmatter Block

## Status

Accepted（実装・実機確認済み）

## Context

Chirami は付箋型の Markdown アプリで、限られた画面領域に情報を表示する。Markdown ファイルには Obsidian 等で付与された frontmatter（先頭の `---` … `---` で囲まれた YAML）が含まれることがある。

frontmatter に対する要求は次の通り:

- frontmatter は Markdown において**補助的な役割**であり、Chirami での優先度は高くない（product vision: 付箋の小領域を最大限に活用したい）。
- とはいえ**完全非表示にすると不便**。存在に気付けるべき。
- 見たいときに **frontmatter 全体を整形表示**できるとよい。
- 編集しようと思えば **raw（生 YAML）で編集**できるとよい。
- Chirami は **Pure Markdown / Obsidian 非破壊互換**が原則。frontmatter の内容・順序・コメントを破壊してはならない。

現状、frontmatter は特別扱いされておらず、生の YAML がそのまま編集領域に表示される（`@codemirror/lang-markdown` は frontmatter を認識しないため、先頭の `---` が hr として描画される等の問題もある）。

## Decision（決定事項）

ノート先頭の frontmatter を、既存の transcript ブロックと同型の「カーソル位置で表示が切り替わるブロック」として扱う。

### 表示モデル: 2状態（常時チップ表示）

```
[チップ表示]  本文上部に key/value チップを横並び（カーソル外・デフォルト）
     │ frontmatter にカーソルを入れる
     ▼
[生YAML]      lang-yaml ハイライト付きで編集（カーソル内）
```

- **チップ表示（デフォルト・カーソル外）**: パースした frontmatter のトップレベルを、本文の上部に **薄背景の角丸チップを横並び**（折り返しあり）で読み取り専用表示する。コンパクトなので領域圧迫は軽く、frontmatter の存在と中身が一目で分かる。
- **生YAML（frontmatter にカーソルを入れる）**: 生の YAML を lang-yaml のシンタックスハイライト付きで表示・編集する。Live Preview の哲学（カーソルのあるブロックは raw）に一致する。
- チップをクリックするとカーソルが frontmatter 内に入り、生YAML 編集へ移行する。

> **設計の変遷（経緯）**: 当初は「折りたたみ（歯車アイコン ⚙）→ クリックで整形表示 → raw」の3状態を実装したが、歯車アイコンが地味で分かりにくかったため、**折りたたみを廃止し常時チップ表示**に変更した。チップ自体がコンパクトで補助的なため「小領域・補助的」という方針は保たれ、かつ「存在に気付ける」も常時満たされる。これにより `expanded` トグル状態（`StateField`）とアイコン widget が不要になり実装も単純化された。「普段は完全非表示」よりも「常時コンパクト表示」を選んだ判断。

### 非破壊の原則

- 整形表示は**表示だけ**で、ドキュメントのバイト列を一切書き換えない。これにより Obsidian 非破壊互換を保証する。
- frontmatter の編集は raw（生 YAML）でのみ行う。整形表示から値を再シリアライズすることはしない（順序・コメント破壊を避けるため）。

### 検出と生YAMLハイライト: `yamlFrontmatter` を採用

`@codemirror/lang-yaml` の `yamlFrontmatter({ content })` ヘルパーでトップレベル言語をラップする。

```js
// 現状
markdown({ extensions: [GFM, Highlight], codeLanguages: languages })
// 変更後
yamlFrontmatter({ content: markdown({ extensions: [GFM, Highlight], codeLanguages: languages }) })
```

これにより以下が一度に得られる:

1. **生 YAML のシンタックスハイライト** — frontmatter 領域が YAML パーサで解釈され、通常の YAML 編集と同等のハイライトになる。
2. **frontmatter 検出** — `syntaxTree` に `Frontmatter` ノードが出る。自前の正規表現スキャンや「1行目限定」判定が不要になる。
3. **`---` の正しい扱い** — マーク行として扱われ、hr として誤描画されない。

> lezer-markdown には frontmatter 拡張が存在しない（exports は GFM / Table / TaskList / Strikethrough 等のみ）。素の lang-markdown + `codeLanguages` では frontmatter はコードブロックではないためハイライトされない。`yamlFrontmatter` がこの問題を解決する。

### 整形表示のオブジェクト化: `yaml` パッケージを追加

構文木からは JS オブジェクトは取れないため、整形表示用に `yaml`（eemeli/yaml）パッケージを追加し、frontmatter テキストを `parse()` する。

- 値はトップレベルのフィールドを型別に表示する:
  - scalar（string / number / bool）: そのまま1行表示。長い場合は CSS の `text-overflow: ellipsis`（`max-width: 22ch`）で省略し、全文は `title` 属性に入れる。
  - array: 中点区切りのインラインテキスト（例 `work · idea · draft`）。
  - object（ネスト）: トップレベルの key 名を波括弧で要約（例 `{ a, b, c … }`）。3 個を超えたら `…` で省略。深追いはしない。
  - null / 空値: 淡色の em-dash `—` を表示。
- **1行に収める（幅ベースの `+N`）**: 固定件数ではなく、**ウィンドウ幅で1行に収まる分だけ**チップを表示し、はみ出した分を単一の `+N` チップに集約する。`ResizeObserver` で各チップの `offsetTop` を測り、2行目に折り返すチップを隠して `+N` に置き換える（リサイズにも追従）。`+N` も含めチップをクリックすると raw 編集に入り全フィールドが見える。多数フィールドの frontmatter が小さな付箋の縦を占有しすぎるのを防ぎつつ、幅を最大限活用する（検証で 10 件 → `title` / `tags` ＋ `+8` の1行に収まることを確認）。
- パッケージサイズは ~40KB 程度で、既存の excalidraw / mermaid に比べ誤差。

### 実装方式

details.ts と同型の **StateField ベースの decoration** とする:

- decoration `StateField`（`provide: EditorView.decorations.from(field)`）で `DecorationSet` を構築
- `Decoration.replace({ widget, block: true })` で frontmatter 範囲をチップ widget に置換
- カーソルが範囲（行）内にあるかで置換の有無を切り替える（`cursorLineFromState` で判定）
- チップ描画は `WidgetType`（`FrontmatterChipsWidget`）
- 検出は `syntaxTree` の `Frontmatter` ノード（`tree.topNode.firstChild`）

> 常時チップ表示に変更したため、当初必要としていた `expanded` トグル状態（`StateField` + `StateEffect`）とアイコン widget は不要になった。rebuild トリガは docChanged / selection 変化 / external（再読込）等。

### `yamlFrontmatter` ラップの構文木への影響（検証済み）

`yamlFrontmatter` は `parseMixed` で以下の木を作る:

```
Document
├── Frontmatter（DashLine / FrontmatterContent → yamlLanguage.parser / DashLine）
└── Body → 本体 Markdown の parser
```

エディタ本体と同じ構成（`markdown({ extensions: [GFM], codeLanguages })` を `content` に）でサンプルを parse して検証した結果:

- `tree.iterate` は parseMixed のマウント木に**降りる**。本体 Markdown ノード（`ATXHeading*` / `Blockquote` / `FencedCode` / `ListItem` / `Table` / `HeaderMark` / `TableHeader` / `TableRow`）が**すべて出現**。
- それらの**絶対オフセットは不変**（例: `HeaderMark.from` = `doc.indexOf("#")`、`Table.from` = `doc.indexOf("| a")`）。
- `FrontmatterContent` 側は YAML として parse され（`BlockMapping` / `Pair` / `Key` / `FlowSequence` 等が出る）、生YAML編集にハイライトが効く。

既存プラグインの構文木アクセスは (1) `tree.iterate` による name マッチ（マウント木に降りる）、(2) マッチしたノードからの相対 `parent` / `getChild`、(3) `resolveInner(pos)` からの遡上、のいずれかで、いずれもネスト階層が1段増えても壊れない。文書ツリーのトップ構造に依存する唯一の箇所（`inlineMarkdown.ts` の `tree.topNode.firstChild`）は、エディタ文書ツリーではなく**インライン断片描画用の独立パーサ**に対するもので、本ラップの影響を受けない。

→ 設計レベルでは低リスク。残るは実装後の `/chirami-verify` による実機確認のみ。

### フォールバック

- frontmatter が無い / 空: 何も表示しない（通常の Markdown のまま）。
- YAML パース失敗（編集途中の不正 YAML など）: 整形表示にできないため raw 維持にフォールバックする。

### スタイル: テーマ変数と HTML

- チップのスタイルは **`--chirami-*` 変数を直接使う**（`--chirami-surface` / `-text` / `-muted` 等）。これらは `chirami-default.css` で定義され Swift が WKUserScript で注入する本物のテーマ変数で、付箋テーマ・ライト/ダークに追従する。
- チップ背景は `color-mix(in srgb, var(--chirami-surface) 60%, transparent)` の薄塗り、角丸 pill（`border-radius: 999px`）。key は `--chirami-muted`、value は `--chirami-text`。長い value は `text-overflow: ellipsis` で省略し全文は `title` 属性へ。
- **`--cm-*` 変数は使わない**。transcript.css / excalidraw.css が使う `--cm-border` 等はどこにも定義されておらず常に fallback 値（`#d0d0d0` 等）で描画される＝テーマ非追従の隠れた不整合。これを踏襲しない。
- 描画は CSS クラスを用い、インラインスタイルや独自要素は避ける（editor-web ルールに準拠）。

## 未決定事項（Open Questions）

設計レベルの未決定事項はすべて解消した（開閉の振る舞い・アイコンの見た目・テーマ変数・`yamlFrontmatter` ラップの影響・値レンダリングの具体形は上の「決定事項」へ反映済み）。

残る確認事項は実装フェーズのもののみ:

- **実装後の `/chirami-verify` による実機確認**（プロジェクトルール）。特に、ラップ後も livePreview / mermaid / table / excalidraw / transcript 等が無傷で動くこと、カーソルによる整形 ⇄ 生YAML 切替とアイコントグルが意図通り動くことを実機で確認する。
- 実装はまず「`yamlFrontmatter` でラップして既存機能が無傷か確認」→ 問題なければウィジェット・トグルを載せる、の順で進める（構文木検証は済んでいるが実機の最終確認として）。

## 実装複雑性の評価

- 表示トグル（整形/raw）の view 層は **transcript の実装パターンとほぼ同じ**。検出は `yamlFrontmatter` により transcript の自前スキャンより簡単になる。
- transcript に無い新規要素は1点: 言語層を `yamlFrontmatter` でラップする変更（1行。共通の構文木への影響は構文木ダンプで検証済み・低リスク）。decoration は details.ts と同型の StateField で、トグル状態すら持たない。
- **新パラダイムではない**。transcript / details の焼き直し ＋ α、という位置づけ。別ライブラリ（teratorm 等）の導入は不要。

## 関連ファイル（実装済み）

- `editor-web/src/editor.ts` — `markdown(...)` を `yamlFrontmatter({ content })` でラップ、`frontmatterExtension` を登録。
- `editor-web/src/extensions/frontmatter.ts`（新規） — 検出（`syntaxTree` の `Frontmatter` ノード）／decoration `StateField`（`provide: EditorView.decorations.from`）／`FrontmatterChipsWidget`（チップをクリックで raw 編集へ）。details.ts と同型。
- `editor-web/src/style.css` — `.cm-frontmatter-chips` / `.cm-frontmatter-chip*` スタイルを追記（`--chirami-*` 参照）。
- `editor-web/package.json` — `yaml`（^2.9.0）を追加。

> 実装上の調整: スタイルは新規 `frontmatter.css` ではなく **`style.css` に追記**した。`transcript.css` / `excalidraw.css` は実際にはどこからも import されておらずビルドに含まれない死にファイルで、バンドルされる CSS は `style.css` のみだったため。

## 実機確認結果（/chirami-verify）

- **チップ表示（デフォルト）**: 本文上部に薄背景の角丸チップが横並び（折り返しあり）。`title My Note` / `tags work · idea · draft`（配列→中点）/ `date 2026-06-13` / `nested { a, b }`（ネスト→key要約）。key 淡色＋value 通常色、テーマ追従。本文は無影響。✓
- **生YAML**: カーソル inside で frontmatter 全体が生 YAML として表示・編集可能。`---` が hr に誤描画されない。✓
- **回帰なし**: frontmatter なしの通常ノートでチップは出ず、見出し・引用・リスト・テーブル・コードブロックが正常レンダリング。✓

> 補足: クリック/キー操作系はターミナルマルチプレクサ（cmux）がフォーカスを保持し Chirami が key window になれないため、合成クリックでの「チップクリック→raw 編集」遷移は実機キャプチャできなかった。チップ表示・生YAML はレンダリングを視覚確認済み。チップクリックでカーソルを frontmatter 内へ送る挙動は details.ts のサマリクリックと同一パターンで、details は実機動作している。

## 参考

- ADR 0006: Transcript Block — 同型の「カーソル位置で表示が切り替わるブロック」の先行実装
