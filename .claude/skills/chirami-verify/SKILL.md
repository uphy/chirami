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

## 3. インタラクションスクリプト

Chirami はフォーカスを失うと自動的に非表示になる。`osascript` や `cliclick` を個別に呼ぶと間に focus 切り替えが入るため、**全操作は `scripts/chirami_interact.py` で一括実行する**。

```bash
SCRIPT=.claude/skills/chirami-verify/scripts/chirami_interact.py

# Test ノートを表示してキャプチャ（内容変更なし）
python3 $SCRIPT show_test /tmp/out.png

# テキストをペーストしてキャプチャ（\n で改行、日本語も OK）
python3 $SCRIPT paste_and_capture "## 見出し\n**太字**\n- item" /tmp/out.png
```

キャプチャ後は Read ツールで画像を読み込んで視覚的に確認する。

### カスタム操作（スクリプトを直接書く場合）

```python
import sys, time
sys.path.insert(0, ".claude/skills/chirami-verify/scripts")
from chirami_interact import post_key, post_click, set_clipboard, get_window, window_center, capture
import Quartz

post_key(29, Quartz.kCGEventFlagMaskAlternate)  # option+0: Test ノート表示
time.sleep(0.8)

w = get_window("Test")
cx, cy = window_center(w)
post_click(cx, cy)
time.sleep(0.3)

post_key(36, 0)                                         # Return
post_key(51, 0)                                         # Delete
set_clipboard("テキスト")
post_key(9, Quartz.kCGEventFlagMaskCommand)             # Cmd+V

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

## 4. 確認フローの基本パターン

1. 必要に応じて `mise run apply` でビルド・再起動
2. `chirami_interact.py` で Test ノートを表示・操作・キャプチャ
3. Read ツールで結果を視覚確認
4. 必要に応じて追加操作して再確認
