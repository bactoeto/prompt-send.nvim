# prompt-send.nvim

> **AI-generated, zero hand-written code.** Every line in this repository —
> plugin, docs, config — was written by an AI coding agent. A human only
> directed and reviewed it. Treat it accordingly.

Write prompts in Neovim's `:` command line, reference Neovim content with
`@reference` (buffer, selection, LSP diagnostics, ...), and send the resolved
prompt to a tmux pane or an external CLI.

## Why

When I'm coding in Neovim, I often wish the agent could just see what's in my
buffer. That's all this plugin does. It's crude: a single file, you hand-write
the references, edit, and send. But that's enough, isn't it?

## Features

- `:PromptSend` — send a prompt, resolving `@reference`
- `:PromptTmuxPane` — choose the tmux pane that receives prompts
- Built-in references: `@buffer`, `@file`, `@select`, `@diagnostic`, `@gitdiff`
- Completion for `@reference`
- Works directly from Visual mode
- Send via tmux or any external command

## Installation

Neovim 0.7+ (developed on 0.12).

vim.pack (Neovim 0.12+):

```lua
vim.pack.add({ 'https://github.com/bactoeto/prompt-send.nvim' })
require('prompt-send').setup()
```

lazy.nvim:

```lua
{ 'bactoeto/prompt-send.nvim', opts = {} }
```

Or just drop `lua/prompt-send.lua` into your config — it is a single file
with no dependencies. With the built-in defaults it sends prompts to a tmux
pane.

No default keymaps. Bind your own:

```lua
vim.keymap.set('v', '<leader>sp', ':PromptSend ')
```

## Configuration

```lua
require('prompt-send').setup({
    send = nil,             -- nil = built-in tmux sender (see below)
    enter = true,           -- append Enter to the tmux sender
    stdin = false,          -- pass prompt via stdin
    pane = nil,             -- tmux pane to send to; nil = auto-scan
    agents = { 'opencode', 'claude', 'codex', 'aider', 'gemini', 'crush',
               'goose', 'cursor-agent', 'openhands' }, -- agent-pane hints
    references = {},        -- add or override @reference
})
```

All keys are optional.

### `send`

How the resolved prompt is sent. References are resolved first. A `send` is
one of two forms:

| Form | Meaning |
|------|---------|
| `string` | Split on whitespace into argv |
| `function(prompt)` | Receive the prompt, return a `string` or `string[]` argv |

The default (`nil`) is the built-in tmux sender — which is just a function:

```lua
send = function(prompt)
    return { 'tmux', 'send-keys', '-t', '<pane>', prompt, 'Enter' }
end
```

`<pane>` is the first tmux pane that is not Neovim, found by scanning
`tmux list-panes -a`; use `:PromptTmuxPane` to pin a specific pane, and
`enter = false` to drop the trailing `Enter`.

Override it with a string or your own function:

```lua
-- string: split on whitespace, prompt appended as the last argument
send = 'opencode run'

-- function: receives the resolved prompt and places it itself
send = function(prompt)
    return { 'opencode', 'run', prompt }
end
```

A `send` function owns the whole argv, so `stdin` does not apply to it. The
string form is split on whitespace and never invokes a shell; use the
function form for arguments containing spaces or for computed argv (for
example JSON-encoding the prompt for an HTTP API), or a wrapper script for
anything more complex (pipes, redirection, `sh -c`).

The command's `stdout` is discarded. Only `stderr` is kept, and it is shown
as an error notification when the command exits non-zero; a successful send
is silent. This plugin does not read a reply — it is send-only.

### `pane`

Which tmux pane the built-in sender types into. Defaults to `nil`, which
scans the panes on each send: it prefers one that looks like an agent (see
`agents`), and otherwise falls back to the first non-Neovim pane. Set it to a
pane id to pin one from the start — it lives in your config, so it survives
restarts:

```lua
require('prompt-send').setup({ pane = '%2' })
```

`:PromptTmuxPane` still overrides it for the current session.

### `agents`

The names used to spot an agent pane when `pane` is `nil`. Each pane's
current command (`pane_current_command`) and title (`pane_title`) are matched
against this list, and the first match wins:

```lua
require('prompt-send').setup({
    agents = { 'opencode', 'claude', 'codex', 'aider', 'gemini', 'crush', 'goose' },
})
```

It is only a hint: if nothing matches, the first non-Neovim pane is used. Set
`agents = {}` for that older, dumber behavior.

### `enter`

Whether the built-in tmux sender appends `Enter`. Set to `false` if you want
to place the text in the pane without pressing Enter. Ignored when `send` is
set.

### `stdin`

How the resolved prompt is passed to the command when `send` is a string.

| Value | Behavior |
|-------|----------|
| `false` (default) | Append the prompt as the last argument |
| `true` | Write the prompt to the command's stdin and close it |

Only applies when `send` is a string. Ignored for a `function` send (it
places the prompt itself) and for the built-in tmux sender.

### `references`

Add or override `@name` references. Custom references merge with the
built-ins; same name overrides.

```lua
require('prompt-send').setup({
    references = {
        git = function()
            return vim.fn.system('git diff')
        end,
    },
})
```

A reference is a function with no arguments that returns a string.

## Commands

### `:PromptSend {prompt}`

Send a prompt. Every `@reference` in `{prompt}` is replaced with its content
before sending.

```vim
:PromptSend check @buffer
:'<,'>PromptSend explain @select
:PromptSend what is wrong here: @select @diagnostic
```

- Can be invoked from Visual mode; the leading `'<,'>` is handled for you.
- Typing `@` completes reference names, replacing only the current `@token`
  without touching the rest of the prompt.
- `@@` escapes an `@`: `@@buffer` is sent literally as `@buffer`.
- Unknown `@name` is left as-is, but if a known reference fails (its function
  errors), nothing is sent — the error is shown instead.

### `:PromptTmuxPane [pane]`

Choose the tmux pane that receives prompts.

- No argument — open a picker listing the panes.
- `auto` — scan on each send and pick the first non-Neovim pane (default).
- A pane id, e.g. `%0` — always send there.

The argument completes: type `:PromptTmuxPane ` and press `<Tab>` to list
`auto` and the available pane ids.

## Statusline

`require('prompt-send').target()` reports where prompts will go. It only reads
in-memory state, so it is safe to call on every redraw:

| Value | Meaning |
|-------|---------|
| a pane id, e.g. `%0` | pinned with `:PromptTmuxPane` |
| `auto` | scan for the first non-Neovim pane on each send |
| `command` | a custom `send` is configured |

For example, with mini.statusline. `content.active` is all-or-nothing, so
reproduce its default sections and add `send:<target>` to the devinfo group:

```lua
require('mini.statusline').setup({
    content = {
        active = function()
            local sl = require('mini.statusline')
            local mode, mode_hl = sl.section_mode({ trunc_width = 120 })
            local git           = sl.section_git({ trunc_width = 40 })
            local diff          = sl.section_diff({ trunc_width = 75 })
            local diagnostics   = sl.section_diagnostics({ trunc_width = 75 })
            local lsp           = sl.section_lsp({ trunc_width = 75 })
            local filename      = sl.section_filename({ trunc_width = 140 })
            local fileinfo      = sl.section_fileinfo({ trunc_width = 120 })
            local location      = sl.section_location({ trunc_width = 75 })
            local search        = sl.section_searchcount({ trunc_width = 75 })

            local prompt = 'send:' .. require('prompt-send').target()

            return sl.combine_groups({
                { hl = mode_hl,                  strings = { mode } },
                { hl = 'MiniStatuslineDevinfo',  strings = { git, diff, diagnostics, lsp, prompt } },
                '%<',
                { hl = 'MiniStatuslineFilename', strings = { filename } },
                '%=',
                { hl = 'MiniStatuslineFileinfo', strings = { fileinfo } },
                { hl = mode_hl,                  strings = { search, location } },
            })
        end,
    },
})
```

## References

Built-in references:

| Name | Content |
|------|---------|
| `@buffer` | Current buffer content |
| `@file` | Current buffer's path, relative to the working directory |
| `@select` | Last Visual selection |
| `@diagnostic` | LSP diagnostics of the current buffer, as `[SEVERITY] message (line N)` |
| `@gitdiff` | Unstaged changes in the repository (`git diff --no-color`) |

`@select` reads the `'<` / `'>` marks without re-entering Visual mode, and
supports char / line / block selections. Returns `(no visual selection)` when
no valid selection exists.

See [Configuration / references](#references) for adding your own.

## Recipes

### Send to a running opencode session

opencode exposes an HTTP API from its background service, and the `opencode
api` command handles service discovery and authentication for you (a bare
`curl` to the server returns `401`). Use the `function` form of `send` to
build the request argv, so the prompt is JSON-encoded without a shell or a
wrapper script:

```lua
local session = vim.env.OPENCODE_SESSION   -- e.g. 'ses_...'

require('prompt-send').setup({
    send = function(prompt)
        return {
            'opencode', 'api', 'post',
            '/api/session/' .. session .. '/prompt',
            '--data', vim.json.encode({ text = prompt }),
        }
    end,
})
```

Pick a session with `opencode session list`, then pass its id to nvim:

```sh
OPENCODE_SESSION=ses_... nvim
```

`:PromptSend ...` now sends the resolved prompt into that session, where it
appears in whichever TUI is attached to it.

To admit the message without triggering the agent (useful as a connectivity
check), pass `resume = false` — the input then waits in the session inbox
instead of running:

```lua
vim.json.encode({ text = prompt, resume = false })
```
