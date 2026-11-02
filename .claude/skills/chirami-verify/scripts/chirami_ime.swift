// List input sources (no args) or select one by ID, e.g. com.google.inputmethod.Japanese.base.
// Used to drive real IME composition in Chirami tests; always switch back afterwards.
import Carbon
let args = CommandLine.arguments
let list = (TISCreateInputSourceList([kTISPropertyInputSourceIsSelectCapable: true] as CFDictionary, false).takeRetainedValue() as? [TISInputSource]) ?? []
func id(_ s: TISInputSource) -> String { Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(s, kTISPropertyInputSourceID)).takeUnretainedValue() as String }
if args.count < 2 { let cur = TISCopyCurrentKeyboardInputSource().takeRetainedValue(); print("current:", id(cur)); for s in list { print(id(s)) }; exit(0) }
if let s = list.first(where: { id($0) == args[1] }) { print(TISSelectInputSource(s)) } else { print("not found"); exit(1) }
