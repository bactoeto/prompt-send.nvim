# AGENTS.md

Notes for agents working on this repo.

## Git

- **Do not `git push` unless the user explicitly asks.** Commit locally and
  stop; the user will say when to push. Pushing on every change is too noisy.
- Local commits are fine at any time.

## Project

- `prompt-send.nvim` — a single-file Neovim plugin. Module: `lua/prompt-send.lua`
  (`require('prompt-send')`).
- Tests: `make test` (`nvim --headless`, no deps). CI runs it on push.

## Docs

Decide the structure first, then fill it; put each fact in the section it
belongs to — no stray notes. Two docs, two jobs:

- `README.md` — quickstart (what it is, install, basic usage). Keep it lean.
- `doc/prompt-send.txt` — full reference (`:help prompt-send`).

Do not duplicate detail between them.

Sections, in order:

- README: title · one-liner · Why · Features · Requirements · Installation ·
  Usage · Commands · References · Help · Development
- help: header · SETUP (defaults block + one section per option) · COMMANDS ·
  REFERENCES · API · STATUSLINE · RECIPES

When behavior changes, update the docs and check for stale wording.
