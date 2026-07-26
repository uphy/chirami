#!/usr/bin/env python3
"""
Chirami GUI interaction helper.

All operations use CGEvent so no focus switches occur between steps.
Usage:
    # Write the test .md file first, then reload: this re-reads the file AND
    # leaves the note as the key window, so interaction works straight after.
    python3 chirami_interact.py reload <output.png>            # hide+show Test, capture
    python3 chirami_interact.py click <px> <py> <output.png>   # click at -o capture pixel
    python3 chirami_interact.py show_test <output.png>
    python3 chirami_interact.py paste_and_capture <text> <output.png>

Captures use `screencapture -o` (no shadow) => image is bounds x 2x, so
pixel (px, py) maps to screen point (bounds.X + px/2, bounds.Y + py/2).

NOTE: never send a bare Escape as a generic "dismiss" — Esc closes the note,
and a follow-up Esc leaks to the app behind it (can interrupt your session).
"""

import sys
import time
import subprocess
import Quartz
from Quartz import (
    CGEventCreateKeyboardEvent,
    CGEventCreateMouseEvent,
    CGEventPost,
    CGEventSetFlags,
    CGWindowListCopyWindowInfo,
    CGWindowListCreateImage,
    CGRectMake,
    kCGHIDEventTap,
    kCGWindowListOptionAll,
    kCGWindowListOptionOnScreenOnly,
    kCGNullWindowID,
    kCGEventLeftMouseDown,
    kCGEventLeftMouseUp,
    kCGMouseButtonLeft,
    kCGEventFlagMaskAlternate,
    kCGEventFlagMaskCommand,
    kCGEventFlagMaskShift,
    kCGWindowImageDefault,
)


def post_key(key_code, flags=0):
    for down in (True, False):
        e = CGEventCreateKeyboardEvent(None, key_code, down)
        CGEventSetFlags(e, flags)
        CGEventPost(kCGHIDEventTap, e)
    time.sleep(0.05)


def post_click(x, y):
    pt = (x, y)
    for etype in (kCGEventLeftMouseDown, kCGEventLeftMouseUp):
        e = CGEventCreateMouseEvent(None, etype, pt, kCGMouseButtonLeft)
        # Always clear modifier flags: a latched flag from a prior post_key
        # rides onto the click and NotePanel.sendEvent treats it as a
        # modifier+drag (default Command), swallowing the click.
        CGEventSetFlags(e, 0)
        CGEventPost(kCGHIDEventTap, e)
    time.sleep(0.05)


def get_window(name, on_screen_only=True):
    """Look up a Chirami window by title.

    Defaults to the on-screen list. The full list also reports hidden windows,
    and `screencapture -l` happily captures those — so state checks built on it
    silently produce stale screenshots of a note that is not actually visible.
    Pass on_screen_only=False only when you deliberately want hidden windows.
    """
    option = kCGWindowListOptionOnScreenOnly if on_screen_only else kCGWindowListOptionAll
    windows = CGWindowListCopyWindowInfo(option, kCGNullWindowID)
    for w in windows:
        if "Chirami" in str(w.get("kCGWindowOwnerName", "")) and w.get("kCGWindowName") == name:
            return w
    return None


def window_center(w):
    b = w["kCGWindowBounds"]
    return int(b["X"]) + int(b["Width"]) // 2, int(b["Y"]) + int(b["Height"]) // 2


def capture(window_id, output_path):
    # -o drops the window's drop shadow, so the image is exactly bounds x 2x
    # (Retina). That makes pixel->screen mapping trivial:
    #   screen_x = bounds["X"] + pixel_x / 2
    #   screen_y = bounds["Y"] + pixel_y / 2
    # Without -o the shadow padding throws off any coordinate math.
    subprocess.run(["screencapture", "-l", str(window_id), "-o", output_path], check=True)


def set_clipboard(text):
    subprocess.run(["pbcopy"], input=text.encode(), check=True)


# --- Focus & activation ---
#
# Use show_and_focus(): toggling a hidden note into view is what grants the key
# window, and local key input works from that moment on.
#
# NoteWindowController.show() calls NSApp.activate + makeKeyAndOrderFront, and
# toggle() branches on the current state:
#
#     hidden        -> show()   => visible AND key; Cmd+V / Tab / clicks land
#     visible & key -> hide()
#
# So a single option+0 press from the hidden state is all that is needed. Do
# NOT press again "to take focus" — the note is already key, and the second
# press hides it.
#
# The osascript / System Events / NSRunningApplication activation routes do
# NOT work: macOS 14+ refuses to let a background LSUIElement app pull focus,
# and `frontmost_app()` keeps reporting the terminal even while the panel is
# key. Judge success by whether input actually landed (check the note file),
# never by frontmost_app().


def activate():
    """Deprecated: kept for compatibility. macOS 14+ ignores this for a
    background LSUIElement app — use show_and_focus() instead."""
    subprocess.Popen(["osascript", "-e", 'tell application "Chirami" to activate'])
    time.sleep(0.18)


def frontmost_app():
    r = subprocess.run(
        ["osascript", "-e",
         'tell application "System Events" to get name of first process whose frontmost is true'],
        capture_output=True, text=True)
    return r.stdout.strip()


def move_mouse(x, y):
    from Quartz import CGEventCreateMouseEvent as _mk, kCGEventMouseMoved
    e = _mk(None, kCGEventMouseMoved, (x, y), kCGMouseButtonLeft)
    CGEventSetFlags(e, 0)
    CGEventPost(kCGHIDEventTap, e)
    time.sleep(0.08)


# --- Interaction actions (call show_and_focus() first; they need a key window) ---

def act_key(key_code, flags=0):
    post_key(key_code, flags)
    time.sleep(0.4)


def act_paste(text):
    set_clipboard(text)
    act_key(9, kCGEventFlagMaskCommand)  # Cmd+V


def click_px(window_name, px, py):
    """Click at pixel (px, py) of the -o capture of the named window.
    The capture is bounds x 2x, so divide by 2 to get screen points."""
    w = get_window(window_name)
    b = w["kCGWindowBounds"]
    x = b["X"] + px / 2
    y = b["Y"] + py / 2
    move_mouse(x, y)
    post_click(x, y)
    time.sleep(0.4)
    return w


# --- Focus-free reload (preferred for rendering checks) ---

def hide_window(name="Test"):
    """Press option+0 until the note is off screen."""
    for _ in range(4):
        if not get_window(name):
            return
        post_key(29, kCGEventFlagMaskAlternate)
        time.sleep(0.7)
    raise RuntimeError(f"could not hide the {name} window")


def show_and_focus(name="Test", output_path=None):
    """Hide then show via option+0 so the file is re-read AND the note becomes
    the key window. Write the test .md file first, then call this.

    One show press is enough for both: show() does makeKeyAndOrderFront, so
    local key input (Cmd+V, Tab, Cmd+F) reaches the editor right away.
    """
    hide_window(name)
    post_key(29, kCGEventFlagMaskAlternate)      # show -> reload + key window
    time.sleep(1.0)
    w = get_window(name)
    if not w:
        print(f"ERROR: {name} window not found after reload", file=sys.stderr)
        sys.exit(1)
    if output_path:
        capture(w["kCGWindowNumber"], output_path)
        print(f"Captured to {output_path}")
    return w


# Older name kept so existing call sites keep working.
reload_window = show_and_focus


# --- High-level actions ---

def show_test_window(output_path):
    """Show Test window via option+0 and capture it."""
    post_key(29, kCGEventFlagMaskAlternate)  # option+0
    time.sleep(0.8)
    w = get_window("Test")
    if not w:
        print("ERROR: Test window not found", file=sys.stderr)
        sys.exit(1)
    capture(w["kCGWindowNumber"], output_path)
    print(f"Captured to {output_path}")


def paste_and_capture(text, output_path):
    """Show Test window, click center, paste text, capture result."""
    # Show window
    post_key(29, kCGEventFlagMaskAlternate)  # option+0
    time.sleep(0.8)

    w = get_window("Test")
    if not w:
        print("ERROR: Test window not found", file=sys.stderr)
        sys.exit(1)

    cx, cy = window_center(w)
    post_click(cx, cy)
    time.sleep(0.3)

    set_clipboard(text)
    post_key(9, kCGEventFlagMaskCommand)  # Cmd+V (key code 9 = v)
    time.sleep(0.5)

    capture(w["kCGWindowNumber"], output_path)
    print(f"Captured to {output_path}")


def key_seq_and_capture(keys, output_path):
    """Show Test window, click center, send key sequence, capture.

    keys: list of (key_code, flags, text_or_None)
      - (36, 0, None)     -> Return
      - (0, 0, "hello")   -> type ASCII text via cliclick
    """
    post_key(29, kCGEventFlagMaskAlternate)
    time.sleep(0.8)

    w = get_window("Test")
    if not w:
        print("ERROR: Test window not found", file=sys.stderr)
        sys.exit(1)

    cx, cy = window_center(w)
    post_click(cx, cy)
    time.sleep(0.3)

    for key_code, flags, text in keys:
        if text is not None:
            # Type ASCII via clipboard to avoid cliclick limitation
            set_clipboard(text)
            post_key(9, kCGEventFlagMaskCommand)  # Cmd+V
            time.sleep(0.1)
        else:
            post_key(key_code, flags)
            time.sleep(0.1)

    time.sleep(0.5)
    capture(w["kCGWindowNumber"], output_path)
    print(f"Captured to {output_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "show_test":
        show_test_window(sys.argv[2])

    elif cmd == "paste_and_capture":
        text = sys.argv[2].replace("\\n", "\n")
        paste_and_capture(text, sys.argv[3])

    elif cmd == "reload":
        reload_window("Test", sys.argv[2] if len(sys.argv) > 2 else "/tmp/out.png")

    elif cmd == "click":
        w = click_px("Test", float(sys.argv[2]), float(sys.argv[3]))
        out = sys.argv[4] if len(sys.argv) > 4 else "/tmp/out.png"
        capture(w["kCGWindowNumber"], out)
        print(f"Captured to {out}")

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
