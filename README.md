# prompt-send.nvim

Write a prompt in Neovim's `:` command line, fill it with pieces of your
editor via `@references`, and send the result to a tmux pane or any command.

> **AI-generated, zero hand-written code.** Every line in this repository —
> plugin, docs, config — was written by an AI coding agent. A human only
> directed and reviewed it. Treat it accordingly.

## Example

Send a prompt made of what you're looking at, without leaving Neovim:

```vim
:PromptSend review my changes: @gitdiff
:'<,'>PromptSend what's wrong with this? @select @diagnostic
```

Each `@...` is replaced with the real editor content — the diff, the
selection, the diagnostics — before the prompt is sent. It goes to a tmux pane
by default, but the agent can just as well run in a Neovim `:terminal` buffer
(`send = 'terminal'`) or behind any command you configure. Bind a key for the
Visual-mode flow:

```lua
vim.keymap.set('v', '<leader>sp', ':PromptSend ')
```

## Why

When I'm coding in Neovim, I often wish the agent could just see what's in my
buffer. That's all this plugin does. It's crude: a single file, you hand-write
the references, edit, and send. But that's enough, isn't it?

## Features

- `:PromptSend` — resolve `@references` and send the prompt
- `:PromptTmuxPane` — choose the tmux pane that receives prompts
- Built-in `@buffer`, `@file`, `@select`, `@diagnostic`, `@gitdiff`, `@N`
- `@` completion; works from Visual mode
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

By default it prefers a tmux pane that looks like an agent, and otherwise the
first non-Neovim pane. Pin one, or send somewhere else entirely:

```lua
require('prompt-send').setup({
    pane = '%3',                        -- always send to this tmux pane
    -- send = 'terminal',               -- or into a Neovim :terminal buffer
    -- send = 'opencode run',           -- or run any command
    -- send = function(prompt) ... end, -- or build the argv yourself
})
```

`send = 'terminal'` writes straight into a Neovim `:terminal` buffer — handy
when the target (e.g. an agent) runs inside Neovim rather than tmux:

```lua
require('prompt-send').setup({ send = 'terminal' })
```

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

Everything else — every option, the two `send` forms, the statusline API, and
a couple of recipes — is in `:help prompt-send`.

## Development

```sh
make test
```
