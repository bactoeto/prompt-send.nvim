# AGENTS.md

Notes for agents working on this repo.

## Git

- **Do not `git push` unless the user explicitly asks.** Commit locally and
  stop; the user will say when to push. Pushing on every change is too noisy.
- Local commits are fine at any time.

## Project

- `prompt-send.nvim` — a single-file Neovim plugin. Module: `lua/prompt-send.lua`
  (`require('prompt-send')`).
- Docs live in `README.md` (short quickstart) and `doc/prompt-send.txt`
  (`:help prompt-send`). When behavior changes, update the docs too.
- Tests: `make test` (`nvim --headless`, no deps). CI runs it on push.
