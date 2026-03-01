## Why

コードベース全体で Note の種類に関する用語が統一されていない。config.yaml に登録された Note と CLI から表示する Note は設計上明確に異なるが、コード・コメント・ドキュメントで呼び分けが曖昧。display-profiles の開発に先立ち、**Registered Note** と **Ad-hoc Note** という用語を定義し、コードベース全体で統一することで、今後の開発・ドキュメント・コミュニケーションの土台を整える。

## What Changes

- Note の種類に関する用語を定義:
  - **Registered Note**: config.yaml の `notes[]` に登録されたノート。Static Note と Periodic Note を含む
  - **Ad-hoc Note**: CLI (`chirami display`) から動的に作成されるノート
- Swift ソースコードのコメントを更新し、Registered Note / Ad-hoc Note の呼び分けを明記
- `DisplayWindowManager` 等の Ad-hoc Note 関連コードにコメントを追加
- `NoteStore`, `WindowManager` 等の Registered Note 関連コードにコメントを追加
- 既存ドキュメント (`docs/`) の用語を統一

## Capabilities

### New Capabilities

（なし — コード動作の変更は行わない）

### Modified Capabilities

（既存 spec なし）

## Impact

- **Swift コード**: `NoteStore.swift`, `WindowManager.swift`, `DisplayWindowManager.swift`, `NoteWindow.swift`, `DisplayPanel.swift` 等のコメント・ドキュメントコメント
- **設定モデル**: `ConfigModels.swift` の型コメント
- **ドキュメント**: `docs/advanced.md`, `CLAUDE.md` の用語
- **動作変更なし**: リファクタリングではなく、コメント・ドキュメントの用語統一のみ
