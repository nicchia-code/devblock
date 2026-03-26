---
name: devblock-next
description: Advance to next TDD phase or feature
---

# /devblock-next — Advance phase or feature

Call the `devblock_next` tool. It handles everything:

- **RED → GREEN**: runs tests, validates they FAIL, moves to GREEN
- **GREEN → done**: runs tests, validates they PASS, auto-commits, moves to next queued feature (or completes)

If tests already pass in RED, it fast-forwards through GREEN automatically.

Read the output — it tells you exactly what to do next and includes todo sync instructions.

If the command fails, the error message includes the test output and specific guidance.
