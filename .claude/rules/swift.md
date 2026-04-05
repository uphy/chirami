---
paths:
  - "Chirami/**/*.swift"
---

# Swift Code Investigation Rules

This project has several large Swift files (300–700 lines). Follow this order when investigating:

1. **Use LSP first** — Check symbol definitions, references, and type info with LSP to identify what to read
2. **Read with offset/limit** — Never read entire files unless necessary; use offset/limit to read only relevant sections
3. **Hypothesize before reading** — Infer the likely location from the symptom, verify with LSP, then read
