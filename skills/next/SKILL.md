---
name: next
description: Advance to next phase or feature
user_invocable: true
---

# /devblock:next — Advance phase or feature

Run:
```bash
bash .devblock/devblock-ctl.sh next
```

The controller handles everything:
- RED → runs tests, validates they FAIL, moves to GREEN
- GREEN → runs tests, validates they PASS, auto-commits, moves to next feature in RED (or completes)

If the command fails, read the error message — it tells you exactly what to fix.
