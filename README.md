# prompt-send.nvim

Write a prompt in Neovim's `:` command line, fill it with pieces of your
editor via `@references`, and send the result to a tmux pane，a neovim terminal buffer, or any command.

> **AI-generated, zero hand-written code.** Every line in this repository —
> plugin, docs, config — was written by an AI coding agent. A human only
> directed and reviewed it. Treat it accordingly.

## Why

When I'm coding in Neovim, I often wish the agent could just see what's in my
buffer. That's all this plugin does. It's crude: a single file, you hand-write
the references, edit, and send. But that's enough, isn't it?

## Features

- Built-in `@buffer`, `@file`, `@select`, `@diagnostic`, `@gitdiff`, `@N`,
  plus your own references
- `@` completion for reference names
- Works from Visual mode
- Sends to a tmux pane, a Neovim `:terminal` buffer, or any command

## Requirements

Neovim 0.7+ (developed on 0.12).

## Installation

lazy.nvim:

```lua
{ 'bactoeto/prompt-send.nvim', opts = {} }
```

vim.pack (Neovim 0.12+):

```lua
vim.pack.add({ 'https://github.com/bactoeto/prompt-send.nvim' })
require('prompt-send').setup()
```

Or drop `lua/prompt-send.lua` into your config — one file, no dependencies.

## Usage

```vim
:PromptSend check @buffer
:'<,'>PromptSend explain @select
:PromptSend review this: @gitdiff
```

Each `@...` is replaced with the real editor content — the selection, the
diagnostics, the diff — before the prompt is sent. By default it prefers a tmux
pane that looks like an agent, and otherwise the first non-Neovim pane. Pin
one, or send somewhere else entirely:

```lua
require('prompt-send').setup({
    via = 'tmux',                 -- 'tmux' | 'terminal' | 'command'

    tmux = { pane = '%3' },       -- options for `via = 'tmux'`
    -- terminal = { enter = true },
    -- command  = { run = 'opencode run' },
})
```

## Commands

- `:PromptSend {prompt}` — send a prompt, resolving `@references`
- `:PromptTmuxPane [pane]` — choose or pin the tmux pane
- `:PromptTerminal [name]` — choose or pin the Neovim terminal

## References

| Name | Content |
|------|---------|
| `@buffer` | Current buffer content |
| `@file` | Current buffer's path |
| `@select` | Last Visual selection |
| `@diagnostic` | LSP diagnostics of the current buffer |
| `@gitdiff` | Unstaged git changes |
| `@N` | A literal newline (self-delimiting; capital `N` is reserved) |

`@@` escapes an `@` — `@@buffer` is the literal `@buffer`. Add your own with
`references = { name = function() ... end }`.

## Help

Everything else — every option, the `command.run` forms, the statusline API,
and a couple of recipes — is in `:help prompt-send`.

## Development

```sh
make test
```
