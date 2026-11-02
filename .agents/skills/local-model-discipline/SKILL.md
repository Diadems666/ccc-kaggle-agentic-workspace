---
name: local-model-discipline
description: Working habits for coding tasks when the model is a mid-size local LLM (Qwen-class, ~27B). Use for any non-trivial coding, refactoring, or debugging task in this workspace.
---

# Coding with a mid-size local model

The local model is capable but slower and less forgiving than a frontier API model on a
big prompt. These habits keep it reliable.

1. **Read before editing.** Open the files you will change and the tests that cover them.
   Do not edit a file you have not read in this session.
2. **Plan in a file for anything over ~3 steps.** Write `PLAN.md` with numbered steps and tick
   them off. Re-read it after every few steps instead of relying on conversation memory.
3. **Small, verifiable diffs.** One logical change at a time, then run the relevant tests or
   a quick smoke command. Never batch five edits and test once.
4. **Tests first for bug fixes.** Reproduce the bug with a failing test, fix it, watch the
   test pass, then run the wider suite.
5. **Run it, don't guess.** If you are unsure whether something works, execute it. Report
   the actual output, not what you expect it to be.
6. **Stop when stuck.** After two failed attempts at the same fix, write down what you
   tried and what you observed, then propose a different approach rather than looping.
7. **Conventions.** Python: PEP 8, type hints, Google-style docstrings, pytest. JS/TS:
   Prettier defaults, JSDoc. Always keep `requirements.txt` / `package.json` in sync when
   adding a dependency.
8. **Never commit secrets** and never `git push` unless explicitly asked.
9. **Escalate honestly.** If the task needs a bigger model (large cross-cutting refactor,
   subtle concurrency bug), say so and suggest switching to `ccc-client` or `ccc-local-think`.
