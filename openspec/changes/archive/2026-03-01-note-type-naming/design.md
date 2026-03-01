## Context

Chirami は2種類の付箋ウィンドウを持つ:

1. config.yaml の `notes[]` に登録されたノート — アプリ起動時に自動表示、hotkey で個別トグル
2. CLI (`chirami display`) から動的に作成されるノート — 一時的、使い捨て

コード上では (1) を `Note`, `NoteStore`, `NoteWindowController`, `WindowManager` で管理し、(2) を `DisplayPanel`, `DisplayWindowController`, `DisplayWindowManager` で管理している。アーキテクチャ上の分離は明確だが、コメントやドキュメントでの呼び分けが曖昧。

display-profiles の開発でこの区別がさらに重要になるため、用語を統一する。

## Goals / Non-Goals

**Goals:**

- **Registered Note** と **Ad-hoc Note** の用語定義を確立する
- Swift コードのドキュメントコメント・セクションコメントに用語を反映
- `docs/` のドキュメントで用語を統一
- `CLAUDE.md` のプロジェクト概要に用語定義を追加

**Non-Goals:**

- クラス名・変数名のリネーム（`DisplayWindowManager` → `AdHocNoteManager` 等）は行わない。既存の命名は十分に明確であり、大規模な diff を発生させる価値がない
- 新機能の追加、動作変更
- テストコードのコメント変更（テスト名・テストコメントは現状のままで十分）

## Decisions

### 1. 用語定義

| 用語 | 定義 | コード上の主要クラス |
|------|------|---------------------|
| **Registered Note** | config.yaml の `notes[]` に登録されたノート。Static Note と Periodic Note を含む | `NoteStore`, `WindowManager`, `NoteWindowController` |
| **Ad-hoc Note** | CLI (`chirami display`) から動的に作成されるノート | `DisplayWindowManager`, `DisplayWindowController` |
| **Static Note** | Registered Note のうち、固定パスのもの | — |
| **Periodic Note** | Registered Note のうち、日付テンプレートパスのもの | `PeriodicNoteInfo`, `PathTemplateResolver` |

**代替案: Managed Note / Ephemeral Note** — Registered / Ad-hoc の方が直感的で、display-profiles の design.md とも一致するため採用。

### 2. コメント追加の方針

- 各 Swift ファイルの先頭ドキュメントコメントに、そのファイルがどちらの Note 種別に関わるかを明記
- `// MARK:` セクションコメントには用語を含めない（既存のセクション分けで十分）
- 過度なコメント追加は避け、クラス・主要メソッドのドキュメントコメントのみ対象

### 3. CLAUDE.md への統合

プロジェクト概要セクションに Note 種別の定義を追加。今後の開発で AI アシスタントが正しい用語を使えるようにする。

## Risks / Trade-offs

- **コメント変更のみなので diff が多い割にコードに変化なし** → レビュー時に動作変更がないことを明示。コミットメッセージに `docs:` prefix を使う
- **用語がハードコードされコメントとずれるリスク** → display-profiles の開発時に design.md で用語を参照するフローを確立済み
