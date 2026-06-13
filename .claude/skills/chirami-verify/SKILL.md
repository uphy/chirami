---
name: chirami-verify
description: Chirami の GUI 動作確認を行うスキル。ビルド・再起動、ウィンドウキャプチャ、ホットキー送信、クリック・文字入力を組み合わせて UI を検証する。「動作確認して」「確認して」「ビルドして試して」「表示を確認」「動くか見て」など、Chirami の見た目や挙動の確認が必要なとき、または開発後に UI の変更が正しく反映されているかを確かめたいときは必ずこのスキルを使う。
---

# Chirami GUI 動作確認

ユーザーが指示した確認内容に応じて以下のプリミティブを組み合わせる。

## 前提

アクセシビリティ権限が必要。失敗する場合は「システム設定 → プライバシーとセキュリティ → アクセシビリティ」に Terminal.app（または Claude Code）を追加するよう案内する。

## 1. ビルドと再起動

```bash
mise run apply        # 通常ビルド（差分）
mise run -f apply     # キャッシュ無効ビルド
```

完了後、Chirami は自動再起動される。

## 2. ホットキー一覧

| ノート | ホットキー | アクション |
|--------|-----------|-----------|
| **Test**（動作確認専用） | `option+0` | toggle |
| Scratchpad | `option+n` | toggle |
| Daily Note | `option+d` | toggle |
| Daily Note | `option+shift+d` | create |

動作確認では原則 **Test ノート（`option+0`）** を使う。Scratchpad・Daily Note はユーザーのデータを壊す可能性があるため触れない。

config.yaml が変更されている場合は `cat ~/.config/chirami/config.yaml` で確認する。

## 3. 確認の2系統：レンダリング（focus不要）と操作（key window必須）

検証には性質の異なる2系統がある。**まずレンダリング系で確認し、操作系は本当に必要なときだけ使う**。

- **レンダリング確認** … 表示が正しいかの確認。`option+0` は**グローバルホットキー**なので focus に関係なく効く。ファイルを直書きして hide→show で再読込すれば良い（セクション4）。**これが最も確実**。
- **操作確認** … クリック・ローカルキー入力（Cmd+V, Tab, チェックボックス, Cmd+F, `/` 入力 など）。これらは **Chirami が key window でないと届かない**。`activate()` で前面化してから送る。

> **key window の壁:** option+0 で表示してもウィンドウは key にならない（frontmost はターミナル等のまま）。合成クリック・ローカルキーが無言で失われたら、まずこれを疑う。ターミナル/マルチプレクサ（例 `cmux`）がフォーカスを保持し続けると activate が通らないことがある（→ セクション3.1 のフォールバック）。

```bash
SCRIPT=.claude/skills/chirami-verify/scripts/chirami_interact.py

# レンダリング: 直書き済みファイルを再読込してキャプチャ（focus不要・最優先）
python3 $SCRIPT reload /tmp/out.png

# 操作: -o キャプチャのピクセル(px,py)をクリック（activate込み）
python3 $SCRIPT click 110 400 /tmp/out.png

# 表示のみ / 追記ペースト（後者は既存内容に追記する点に注意 → セクション4）
python3 $SCRIPT show_test /tmp/out.png
python3 $SCRIPT paste_and_capture "## 見出し\n**太字**\n- item" /tmp/out.png
```

キャプチャ後は Read ツールで画像を読み込んで視覚的に確認する。

### キャプチャ座標（`-o` で影を除外）

`capture()` は `screencapture -l <id> -o` を使う。`-o` で影が消えるため **画像 = ウィンドウ bounds × 2x（Retina）** になり、座標換算が単純になる：

```
screen_x = bounds["X"] + pixel_x / 2
screen_y = bounds["Y"] + pixel_y / 2
```

クリック先は「`-o` キャプチャ画像の何 px か」を Read で見て決め、`click <px> <py>` か `click_px()` に渡す。

### 3.1 操作系のフォーカス確保とフォールバック

`activate()` は `osascript ... to activate` を Popen（非ブロッキング）で投げ ~0.18s 待つ。`act_key` / `act_paste` / `click_px` は**各アクション前に activate** するので、リトライループで複数回試すと通りやすい。

```python
import sys, time
sys.path.insert(0, ".claude/skills/chirami-verify/scripts")
from chirami_interact import act_paste, frontmost_app
# 通らない時は数回試す（毎回 activate される）
for _ in range(3):
    act_paste("text")
print(frontmost_app())   # "Chirami" でなければ前面化に失敗している
```

`frontmost_app()` が常に "Chirami" にならず操作系が一切通らない場合のフォールバック（無理に送らない）：

1. 数回リトライ（上記）。ユーザーがターミナルを操作中だと原理的に奪えないことがある。
2. **ロジックはログで確認**：`log stream --predicate 'subsystem == "io.github.uphy.Chirami"' --level debug` で bridge メッセージ（例: 検索パネル開閉、reload）を観測し、画面操作なしで挙動を裏取りする。
3. それでも画面確認が要るなら、ユーザーに「該当ノートをクリックして前面化／`/` などを入力」してもらう。

> ⚠️ **Esc を汎用 dismiss に使わない。** Esc はノートを閉じる。さらに 2 発目の Esc が背後のアプリ（Claude Code を動かすターミナル）に抜けて**セッションを中断**させ得る。パネルを閉じたいときは `×` ボタンのクリックなど対象を特定した操作で。

### カスタム操作（スクリプトを直接書く場合）

操作系は `activate()` で前面化してから送る。`act_key` / `act_paste` / `click_px` は内部で activate するのでそれらを優先する。

```python
import sys
sys.path.insert(0, ".claude/skills/chirami-verify/scripts")
from chirami_interact import (
    reload_window, click_px, act_key, act_paste, capture, get_window,
)
import Quartz

# 1) まずファイル直書き → reload で表示（focus不要）
reload_window("Test")

# 2) 操作（各 act_* / click_px が前面化してから送る）
click_px("Test", 110, 400)                 # -o 画像の px をクリック
act_key(36, 0)                             # Return
act_paste("テキスト")                       # Cmd+V でペースト

# 3) キャプチャ（-o・影なし）
w = get_window("Test")
capture(w["kCGWindowNumber"], "/tmp/out.png")
```

### キーループの注意事項

`post_key` はシステム全体にキーイベントを送る。ループ内で `time.sleep()` を挟むと、その間にフォーカスが別ウィンドウへ移って誤入力が発生する。

ループで複数回送る場合は、各回の前に Chirami ウィンドウの存在を確認してから送る：

```python
for i in range(3):
    w = get_window("Test")
    if not w:
        print(f"Window lost at iteration {i}, stopping")
        break
    post_key(24, flags)
    time.sleep(0.3)
```

### キーコード早見表

| キー | コード |
|------|--------|
| Return | 36 |
| Delete | 51 |
| Escape | 53 |
| Tab | 48 |
| v (Cmd+V) | 9 |
| a (Cmd+A) | 0 |
| z (Cmd+Z) | 6 |

## 4. レンダリング確認はファイル直書き＋トグル再読込で行う

`paste_and_capture` は既存内容に **追記** する（クリアしない）。何度も使うと過去の入力が蓄積し、新しい入力と混ざって判別不能になる。`Cmd+A`→`Delete` でのクリアは効かないことがある。

内容を入れ替えてレンダリングを確認する場合は、**テストファイルを直接書き換えてウィンドウをトグル（hide→show）して再読込する**のが確実。

まず Test ノートの実ファイルパスを config.yaml から確認する（`/tmp` 決め打ちにしない）。

```bash
# Test ノートの path を確認
grep -A1 'title: Test' ~/.config/chirami/config.yaml   # path: ... の行を読む
```

確認したパス（例 `/tmp/chirami-test.md`）に対して直書きし、トグルで再読込する。

```bash
TEST_MD=/tmp/chirami-test.md   # config.yaml で確認した実パスに置き換える

cat > "$TEST_MD" <<'EOF'
## 見出し
**太字** *斜体*
EOF

# 直書き済みファイルを hide→show で再読込してキャプチャ（focus不要）
python3 .claude/skills/chirami-verify/scripts/chirami_interact.py reload /tmp/out.png
```

確認時の注意点：

- スクロール（`CGScrollWheelEvent`）は効かないことがある。ウィンドウは内容に合わせて自動リサイズされるので、長い内容は短く分割し、**1画面に収まる単位で個別に投入**する。

## 5. 確認フローの基本パターン

1. 必要に応じて `mise run apply` でビルド・再起動（再起動で focus 状態はリセットされる）
2. **まずレンダリングの確認**（focus不要・最優先）→ セクション 4（ファイル直書き＋`reload`）
3. 操作・挙動の確認が必要なときだけ操作系へ → セクション 3（`activate` 必須）。通らなければセクション 3.1 のフォールバック
4. Read ツールで結果を視覚確認
5. 必要に応じて追加操作して再確認
