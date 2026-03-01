## 1. 用語定義の追加

- [ ] 1.1 `CLAUDE.md` のプロジェクト概要セクションに Note 種別の定義（Registered Note / Ad-hoc Note / Static Note / Periodic Note）を追加

## 2. Registered Note 関連コードのコメント更新

- [ ] 2.1 `NoteStore.swift` — クラスのドキュメントコメントに「Manages Registered Notes」を明記。`loadFromConfig()` の Static Note / Periodic Note 分岐コメントを整理
- [ ] 2.2 `WindowManager.swift` — クラスのドキュメントコメントに「Manages windows for Registered Notes」を明記
- [ ] 2.3 `Note.swift` — `Note` struct と `PeriodicNoteInfo` のドキュメントコメントに Registered Note の文脈を追加
- [ ] 2.4 `ChiramiApp.swift` — `AppDelegate` 内のコメントで Registered Note / Ad-hoc Note の区別を明記

## 3. Ad-hoc Note 関連コードのコメント更新

- [ ] 3.1 `DisplayWindowManager.swift` — `DisplayWindowController` と `DisplayWindowManager` のドキュメントコメントに「Ad-hoc Note」用語を追加
- [ ] 3.2 `DisplayPanel.swift` — ドキュメントコメントに「Ad-hoc Note」用語を追加
- [ ] 3.3 `DisplayContentView.swift` — ドキュメントコメントに「Ad-hoc Note」用語を追加
- [ ] 3.4 `DisplayContentModel.swift` — ドキュメントコメントに「Ad-hoc Note」用語を追加

## 4. ドキュメントの用語補足

- [ ] 4.1 `docs/advanced.md` — 既存内容はそのまま。Registered Note の文脈が必要な箇所に用語を補足
- [ ] 4.2 `docs/configuration.md` — 既存内容はそのまま。notes セクションが Registered Note であることを補足
