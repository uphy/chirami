---
paths:
  - "editor-web/**"
---

# Parsing Policy

Minimize regex-based parsing. Regex fixes tend to be ad-hoc and brittle.

- Prefer CodeMirror's syntax tree (`syntaxTree(state)`) for parsing Markdown structure
- Use string operations only for simple, well-defined patterns
- Never use regex as a substitute for proper AST traversal

# CodeMirror Usage Policy

Prefer standard HTML tags for rendering output. Minimize HTML/CSS hacks.

- Use semantic HTML elements (`<strong>`, `<em>`, `<code>`, `<blockquote>`, etc.) wherever possible
- Avoid custom elements, non-standard attributes, or inline style overrides unless there is no alternative
- When styling is needed, prefer CSS classes over inline styles
- Avoid manipulating the DOM directly when CodeMirror's decoration or node spec APIs are sufficient
- Keep decoration logic simple: if a feature requires complex DOM surgery, reconsider the approach

# Logging Policy

UI behavior in WebView is hard to observe directly. Use logs proactively when investigating or implementing.

- Add debug logs at key points: editor initialization, state transitions, event handling, bridge calls
- When a bug is hard to reproduce visually, add logs first before attempting fixes
- Remove temporary investigation logs after the issue is resolved; keep logs that have long-term diagnostic value

## How to Log

`console.log` / `console.error` are prohibited. Use the bridge:

```typescript
import { postToSwift } from "./bridge";

postToSwift({ type: "log", level: "debug", message: "editor ready" });
```

- `level`: `"debug"` | `"info"` | `"warn"` | `"error"`
- Log messages are forwarded via `NoteWebViewBridge` and emitted through `os.Logger` with the prefix `[JS {level}]`
- They appear in the same `log stream` output as Swift logs (category: `NoteWebViewBridge`)

# Swift ↔ JS Bridge Policy

Minimize bridge usage. The bridge adds coordination complexity between Swift and JS layers.

- Implement logic in JS (CodeMirror) when it can be handled entirely within the editor
- Use the bridge only when Swift-side state or capabilities are genuinely required (file I/O, app config, native APIs)
- Avoid round-trips where a single JS-side solution would suffice
- Each new message type on the bridge is a maintenance cost — add one only when there is no JS-only alternative
