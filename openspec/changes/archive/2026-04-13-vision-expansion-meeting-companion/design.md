## Context

Chiramiの基本機能は完成しており、付箋型ノートアクセスのPhase 1が達成されている。`docs/product-vision.md` と `README.md` は現在のビジョン（Obsidianユーザー向け付箋アクセス）のみを記述しており、より広い「付箋UIで日々の業務を支えるコンパニオン」という方向性が含まれていない。

## Goals / Non-Goals

**Goals:**

- `docs/product-vision.md` の Why を「作業中は常にもう一枚の画面が必要になる。Chiramiはそれをウィンドウの上に浮かせる」という本質的な価値に更新する
- `docs/product-vision.md` の How・What・Scope を新ビジョンに整合させる
- `README.md` のポジショニング文言を新ビジョンに合わせて更新する
- Obsidianとの互換性という既存の価値は維持しつつ、それが「一形態」であることを明確にする

**Non-Goals:**

- tldraw・speech-to-text など新機能の実装（別チェンジ）
- 既存機能の変更

## Decisions

**Whyの再定義**

現行のWhyは「Obsidianノートにアクセスするためのフロー維持」という具体的な課題を述べている。新Whyはそれを包含しつつ、より本質的な価値「作業画面の上に何かを浮かせて同時に使える」を前面に出す。Obsidianの言及は具体例として残す形にする。

**スコープの更新**

現行の「strictly a display and access layer」はPhase 1の制約として有効だったが、Phase 2（描画、書き起こし等）では成立しなくなる。「ファイル管理・整理はスコープ外」という原則は維持しつつ、能動的なコンテンツ作成（付箋内での作業）はスコープに含める表現に変更する。

## Risks / Trade-offs

Whyを広げることでフォーカスが希薄化するリスク → 「付箋UIで浮かせる」という具体的なHow（NSPanel）を起点に据えることで、「なんでもあり」にならないよう軸を保つ
