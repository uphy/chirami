#!/usr/bin/env python3
"""
Chirami GUI interaction helper.

All operations use CGEvent so no focus switches occur between steps.
Usage:
    python3 chirami_interact.py show_test <output.png>
    python3 chirami_interact.py paste_and_capture <text> <output.png>
    python3 chirami_interact.py key_and_capture <key_code> [modifiers] <output.png>
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
        CGEventPost(kCGHIDEventTap, e)
    time.sleep(0.05)


def get_window(name):
    windows = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID)
    for w in windows:
        if "Chirami" in str(w.get("kCGWindowOwnerName", "")) and w.get("kCGWindowName") == name:
            return w
    return None


def window_center(w):
    b = w["kCGWindowBounds"]
    return int(b["X"]) + int(b["Width"]) // 2, int(b["Y"]) + int(b["Height"]) // 2


def capture(window_id, output_path):
    subprocess.run(["screencapture", "-l", str(window_id), output_path], check=True)


def set_clipboard(text):
    subprocess.run(["pbcopy"], input=text.encode(), check=True)


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

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
