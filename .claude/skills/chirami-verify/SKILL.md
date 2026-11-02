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

## 3. レンダリングも操作も「隠してから1回出す」で足りる

レンダリング確認（表示が正しいか）と操作確認（クリック・Cmd+V・Tab・Cmd+F など）は、どちらも同じ入口から始める。ファイルを直書きしてから **ノートを隠し、`option+0` を1回押して出す**。これで再読込と key window の獲得が同時に起きる。

`option+0` は Carbon のグローバルホットキーなので focus に関係なく届き、`NoteWindowController.toggle()` が状態で分岐する：

| 押す前の状態 | 起きること |
|-------------|-----------|
| 非表示 | `show()` → `NSApp.activate` + `makeKeyAndOrderFront` = **表示 かつ key window** |
| 表示中 & key | `hide()` |

つまり非表示から1回押せば操作系も通る。**「focus を取るためにもう1回押す」ことはしない** — すでに key なので隠れてしまう。

```bash
SCRIPT=.claude/skills/chirami-verify/scripts/chirami_interact.py

# 直書き済みファイルを再読込 + key window 化してキャプチャ
python3 $SCRIPT reload /tmp/out.png

# 続けて操作できる: -o キャプチャのピクセル(px,py)をクリック
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

### 3.1 やってはいけない前面化と、成否の判定方法

**`frontmost_app()` を成否の判定に使わない。** Chirami は LSUIElement + `.nonactivatingPanel` なので、状況によってはパネルが key window でもアプリが frontmost にならず、`frontmost_app()` がターミナル（`ghostty` など）を返すことがある（2026-11 時点の環境では `option+0` 後に Chirami が frontmost になるのを確認）。これを見て「前面化に失敗した」と判断すると、実際には通っている操作を諦めることになる。

以下の前面化ルートは **すべて効かない**。macOS 14+ がバックグラウンドアプリのフォーカス奪取を拒否するため。試して時間を溶かさない。

- `osascript -e 'tell application "Chirami" to activate'`（= `activate()`）
- `tell application "System Events" to set frontmost of process "Chirami" to true`
- `NSRunningApplication.activateWithOptions_(NSApplicationActivateIgnoringOtherApps)`
- ウィンドウ上への合成クリック単体

判定は **実際に入力が入ったか** で行う。ノートのファイルを読めば分かる：

```python
type_marker = "<PROBE>"
act_paste(type_marker)
assert type_marker in open("/tmp/chirami-test.md").read()
```

### 3.2 状態判定は必ず OnScreenOnly で行う

`get_window()` は既定で `kCGWindowListOptionOnScreenOnly` を使う。`kCGWindowListOptionAll` は**隠れたウィンドウも返し**、`screencapture -l` はそれを平然とキャプチャする。全件リストで hide/show を判定すると押下回数が1つずれ、**非表示ノートの古い内容を撮って「正常に見える」** という最悪の誤検証になる。

> ⚠️ **Esc を汎用 dismiss に使わない。** Esc はノートを閉じる。さらに 2 発目の Esc が背後のアプリ（Claude Code を動かすターミナル）に抜けて**セッションを中断**させ得る。パネルを閉じたいときは `×` ボタンのクリックなど対象を特定した操作で。

### 3.3 レンダリング結果と状態は AX で文字として読む

`scripts/chirami_ax.swift` は Accessibility API で Test ノートの中身（WKWebView 内の CodeMirror まで）を読む。チェックボックスの状態・レンダリング後のテキスト・表示中かどうかは、キャプチャ画像を見るよりこちらで判定する。キャプチャは色・配置など見た目の確認に使う。

```bash
AX=.claude/skills/chirami-verify/scripts/chirami_ax.swift

swift $AX visible                      # 表示中なら exit 0、非表示なら exit 1
swift $AX dump                         # AX ツリーを出す（下の例）
swift $AX text                         # レンダリング後のエディタ全文
swift $AX press AXCheckBox "task one"  # ラベルで要素を特定して AXPress（--nth N で同名の N 番目）
```

`dump` の出力例（`- [ ] task one` / `- [x] task two` / `**bold**` / `[link](...)`）：

```
AXWindow(AXSystemDialog) label="Test" [AXRaise]
  AXTextArea value="Probe Heading\n\ntask one\ntask two\n\nSome bold text and a link.\n\n" [AXPress]
    AXStaticText value="Probe Heading"
    AXCheckBox label="task one" value="0" [AXPress]    ← 0 = 未チェック, 1 = チェック済み
    AXStaticText value="task one"
    ...
AXButton(AXCloseButton) label="close" [AXPress]
AXButton label="pin" [AXPress]
```

- チェックボックスのラベルは直後の `AXStaticText` の文字列。`press AXCheckBox "task one"` で切り替わり、`.md` にも保存される（確認済み）
- `--title <ノート名>` で Test 以外のノートも読めるが、操作は原則 Test ノートだけにする
- 非表示のノートは `AXWindows` に出ないので、`visible` は OnScreenOnly と同じ判定になる
- 閉じるボタンへの `AXPress` は成功を返すがノートは隠れない。隠すときは `option+0` を使う
- 初回は Swift のコンパイルで 1〜2 秒かかる

### 3.4 キー操作は chirami_keys.swift、カーソル位置は chirami context で見る

`scripts/chirami_keys.swift` は Test ノートにキー列を送る。各ステップの前に「Chirami が前面かつパネルにフォーカスがある」ことを確かめ、外れていたら exit 1 で止まる（ターミナルへの誤入力を防ぐ）。毎回コンパイルすると遅いので、先にバイナリ化して使う。

```bash
swiftc -O .claude/skills/chirami-verify/scripts/chirami_keys.swift -o /tmp/chirami-keys
/tmp/chirami-keys cmd+up down ctrl+e tab 'text:hello' 'clip:- x\n- y' cmd+v
/tmp/chirami-keys 'html:<ul><li>x</li></ul>|x' cmd+v     # HTML をクリップボードに入れて貼る
chirami context   # Markdown ソース上の cursor / selection（行は1始まり、列は0始まり）
```

- 合成イベントは Karabiner-Elements を通らない。emacs 風の操作は Karabiner が変換した後のキーで送る（`ctrl+n` → `down`、`ctrl+f` → `right`、mark 中の `ctrl+n` → `shift+down`、`ctrl+w` → `cmd+x`、`ctrl+y` → `cmd+v`）。`ctrl+a` / `ctrl+e` / `ctrl+k` はそのまま Chirami に届く
- 英数字・記号は実キーコード（US 配列）で送る。Unicode 文字列の注入は ctrl 系のキーの直後に WebKit に捨てられるため、日本語は `clip:` + `cmd+v` で入れる
- IME の確認は `scripts/chirami_ime.swift` で入力ソースを切り替え（例 `com.google.inputmethod.Japanese.base`）、ローマ字を `text:kaigi` で送る。切り替え直後は 0.5 秒ほど待つ。終わったら必ず元の入力ソースに戻す（`trap ... EXIT` を使う）
- コピー（`cmd+c`）やプレーン貼り付け（`cmd+shift+v`）は、直前のキーと間を空けないと取りこぼすことがある。`sleep:300` を挟む
- `option+0` で表示すると Chirami は前面アプリになる（`NSWorkspace.frontmostApplication` が Chirami を返す）

> agent-desktop（vercel-labs）は使えない。ノートの NSPanel は `.floating`（`kCGWindowLayer` 3）で、agent-desktop は layer 0 以外のウィンドウを読み飛ばすため `snapshot --app Chirami` が `WINDOW_NOT_FOUND` になる（1.0.2 で確認）。

### カスタム操作（スクリプトを直接書く場合）

`show_and_focus()` で「再読込 + key window」まで済ませてから操作を送る。

```python
import sys
sys.path.insert(0, ".claude/skills/chirami-verify/scripts")
from chirami_interact import (
    show_and_focus, click_px, act_key, act_paste, capture, get_window,
)

# 1) ファイル直書き → 隠して1回出す（再読込 + key window）
open("/tmp/chirami-test.md", "w").write("- [ ] タスク\n")
show_and_focus("Test")

# 2) 操作（この時点でローカルキーもクリックも届く）
click_px("Test", 110, 400)                 # -o 画像の px をクリック
act_key(36, 0)                             # Return
act_paste("テキスト")                       # Cmd+V でペースト

# 3) キャプチャ（-o・影なし）
w = get_window("Test")
capture(w["kCGWindowNumber"], "/tmp/out.png")
```

内容を差し替えて何度も確認する場合は、その都度 `show_and_focus()` からやり直す。編集がファイルへ反映されるまで数百 ms かかるので、`content()` を読む前に 0.5〜1.0s 待つ。

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

# 直書き済みファイルを hide→show で再読込してキャプチャ
python3 .claude/skills/chirami-verify/scripts/chirami_interact.py reload /tmp/out.png
```

確認時の注意点：

- スクロール（`CGScrollWheelEvent`）は効かないことがある。ウィンドウは内容に合わせて自動リサイズされるので、長い内容は短く分割し、**1画面に収まる単位で個別に投入**する。

## 5. 確認フローの基本パターン

1. 必要に応じて `mise run apply` でビルド・再起動
2. テストファイルを直書きし、隠して1回出す（`reload` / `show_and_focus`）→ 再読込 + key window
3. 文字・状態は `chirami_ax.swift dump` / `text` で判定し、見た目は Read ツールでキャプチャを確認
4. 操作の確認は同じ状態のまま続けて送る（クリック・Cmd+V・Tab・Cmd+F）
5. 入力が入ったかは**ノートのファイルを読んで**判定する（`frontmost_app()` では判定しない）
6. 内容を差し替えるときは 2 に戻る
