-- prompt-send.nvim
-- AI-generated, zero hand-written code. A human only directed and reviewed.
-- A Neovim Lua plugin for sending prompts with @references via tmux or external CLI.

local M = {}

-- ── Configuration ──────────────────────────────────────────────────────────

M.config = {
  via = "tmux",        -- "tmux" | "terminal" | "command"
  references = {},

  tmux = {
    pane = nil,        -- "%2" | nil (pick per send)
    enter = true,      -- append Enter
  },
  terminal = {
    enter = true,      -- append a newline
  },
  command = {
    run = nil,         -- string | fun(prompt): string|string[]
    stdin = false,     -- pass prompt via stdin instead of as the last arg
  },

  agents = {           -- names matched against pane command + title
    "opencode", "claude", "codex", "aider", "gemini", "crush", "goose",
    "cursor-agent", "openhands",
  },
}

-- Terminal buffer pinned with :PromptTerminal (deliberately not a setup option).
local terminal_buf = nil

-- ── Default References ─────────────────────────────────────────────────────

local default_refs = {}

--- @buffer : current buffer content
function default_refs.buffer()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

--- @file : current buffer's path, relative to the working directory
function default_refs.file()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    return "(no file)"
  end
  return vim.fn.fnamemodify(name, ":.")
end

--- @select : last Visual selection, read from '< and '> marks
function default_refs.select()
  local smark = vim.fn.getpos("'<")
  local emark = vim.fn.getpos("'>")
  local sl, sc = smark[2], smark[3]
  local el, ec = emark[2], emark[3]

  if sl == 0 or el == 0 then
    return "(no visual selection)"
  end

  if sl > el or (sl == el and sc > ec) then
    sl, sc, el, ec = el, ec, sl, sc
  end

  local lines = vim.api.nvim_buf_get_lines(0, sl - 1, el, false)
  if #lines == 0 then
    return ""
  end

  local vmode = vim.fn.visualmode()   -- 'v', 'V', or '\22' (block)

  if vmode == "V" then
    return table.concat(lines, "\n")
  end

  if vmode == "\22" then
    local out = {}
    for _, line in ipairs(lines) do
      table.insert(out, line:sub(sc, ec))
    end
    return table.concat(out, "\n")
  end

  if #lines == 1 then
    return lines[1]:sub(sc, ec)
  end
  lines[1] = lines[1]:sub(sc)
  lines[#lines] = lines[#lines]:sub(1, ec)
  return table.concat(lines, "\n")
end

--- @gitdiff : unstaged changes in the repository
function default_refs.gitdiff()
  local out = vim.fn.systemlist({ "git", "diff", "--no-color" })
  if vim.v.shell_error ~= 0 then
    return "(not a git repository)"
  end
  if #out == 0 then
    return "(no changes)"
  end
  return table.concat(out, "\n")
end

--- LSP severities (1..4). Kept local so we do not depend on the reverse
--- lookup of `vim.diagnostic.severity`, which older Neovim versions lack.
local DIAG_SEVERITY = { [1] = "ERROR", [2] = "WARN", [3] = "INFO", [4] = "HINT" }

--- @diagnostic : LSP diagnostics for current buffer
function default_refs.diagnostic()
  local diags = vim.diagnostic.get(0)
  if #diags == 0 then
    return "(no diagnostics)"
  end
  local lines = {}
  for _, d in ipairs(diags) do
    local sev = DIAG_SEVERITY[d.severity] or "UNKNOWN"
    table.insert(lines, string.format("[%s] %s (line %d)", sev, d.message, d.lnum + 1))
  end
  return table.concat(lines, "\n")
end

-- ── Helpers ────────────────────────────────────────────────────────────────

local function build_refs()
  local refs = vim.deepcopy(default_refs)
  for name, fn in pairs(M.config.references) do
    refs[name] = fn
  end
  return refs
end

--- Resolve @references in a prompt. `@@` yields a literal `@`.
--- @param prompt string
--- @return string resolved
--- @return string[] errors  one entry per @reference that failed
local function resolve_prompt(prompt)
  local refs = build_refs()
  local errors = {}
  local ESCAPE = "\1"   -- stands in for an escaped "@"

  local resolved = prompt:gsub("@@", ESCAPE)
  -- `@N` is reserved for a newline and is self-delimiting: `a@Nb` -> `a\nb`
  resolved = resolved:gsub("@N", "\n")
  resolved = resolved:gsub("@([%w_%-]+)", function(name)
    local fn = refs[name]
    if fn == nil then
      return "@" .. name   -- unknown names are left as-is
    end
    local ok, result = pcall(fn)
    if not ok or result == nil then
      table.insert(errors,
        string.format("@%s: %s", name, ok and "returned nil" or tostring(result)))
      return "@" .. name
    end
    return tostring(result)
  end)
  resolved = resolved:gsub(ESCAPE, "@")

  return resolved, errors
end

-- ── Tmux Pane Selection ────────────────────────────────────────────────────

local function list_tmux_panes()
  local out = vim.fn.systemlist({
    "tmux", "list-panes", "-a", "-F",
    "#{pane_id}\t#{pane_current_command}\t#{pane_title}",
  })
  local panes = {}
  for _, line in ipairs(out) do
    local id, cmd, title = line:match("^(%%%d+)\t([^\t]*)\t(.*)$")
    if id then
      table.insert(panes, { id = id, cmd = cmd, title = title })
    end
  end
  return panes
end

local function is_nvim_command(cmd)
  local base = (cmd or ""):match("([^/]+)$")
  if base == nil then
    return false
  end
  base = base:lower()
  return base == "nvim" or base == "vim" or base == "vi"
end

--- Pick a tmux pane: a pane whose command/title looks like an agent first,
--- then the first non-Neovim pane.
local function find_default_pane()
  local self_pane = vim.env.TMUX_PANE
  local fallback = nil
  for _, p in ipairs(list_tmux_panes()) do
    if p.id ~= self_pane and not is_nvim_command(p.cmd) then
      local hay = ("%s %s"):format(p.cmd or "", p.title or ""):lower()
      for _, name in ipairs(M.config.agents) do
        if hay:find(name:lower(), 1, true) then
          return p.id
        end
      end
      fallback = fallback or p.id
    end
  end
  return fallback
end

local function prompt_tmux_pane()
  local panes = list_tmux_panes()
  if #panes == 0 then
    vim.notify("prompt-send.nvim: no tmux panes found", vim.log.levels.WARN)
    return
  end

  local items = { { id = nil, cmd = "auto (prefer an agent pane)" } }
  for _, p in ipairs(panes) do
    table.insert(items, p)
  end

  vim.ui.select(items, {
    prompt = "Select tmux pane:",
    format_item = function(item)
      if item.id == nil then
        return item.cmd
      end
      return string.format("%s (%s)", item.id, item.cmd)
    end,
  }, function(choice)
    if choice == nil then return end
    if choice.id == nil then
      M.config.tmux.pane = nil
      vim.notify("prompt-send.nvim: tmux pane set to auto")
    else
      M.config.tmux.pane = choice.id
      vim.notify("prompt-send.nvim: tmux pane set to " .. choice.id)
    end
  end)
end

-- ── Sending ────────────────────────────────────────────────────────────────

--- Report a failed send. `detail` is the command's captured stderr.
local function notify_failure(detail, code)
  detail = vim.trim(detail or "")
  if detail == "" then
    detail = string.format("exited with code %d", code)
  end
  vim.notify("prompt-send.nvim: " .. detail, vim.log.levels.ERROR)
end

--- Build jobstart options that collect stderr and report it on failure.
local function job_opts(use_stdin)
  local stderr_lines = {}
  return {
    stdin = use_stdin and "pipe" or "null",
    stderr_buffered = true,
    on_stderr = function(_, data)
      if type(data) ~= "table" then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr_lines, line)
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        notify_failure(table.concat(stderr_lines, "\n"), code)
      end
    end,
  }
end

--- Turn a command spec into an argv list. A spec is a string (split on
--- whitespace) or an argv table.
--- @param spec string|string[]
--- @return string[]
local function to_argv(spec)
  local argv = {}
  if type(spec) == "table" then
    for _, v in ipairs(spec) do
      table.insert(argv, tostring(v))
    end
  elseif type(spec) == "string" then
    for word in spec:gmatch("%S+") do
      table.insert(argv, word)
    end
  end
  return argv
end

--- Run a command. A non-zero exit reports its stderr.
local function run_job(argv, text, use_stdin)
  if #argv == 0 then
    vim.notify("prompt-send.nvim: empty command", vim.log.levels.ERROR)
    return
  end
  local started, job = pcall(vim.fn.jobstart, argv, job_opts(use_stdin))
  if not started or job <= 0 then
    vim.notify("prompt-send.nvim: failed to start command", vim.log.levels.ERROR)
    return
  end
  if use_stdin then
    vim.fn.chansend(job, text)
    vim.fn.chanclose(job, "stdin")
  end
end

--- Wrap multi-line text in a bracketed paste, so the target inserts its
--- newlines instead of treating them as Enter.
local function paste_wrap(text)
  if text:find("\n") then
    return "\27[200~" .. text .. "\27[201~"
  end
  return text
end

--- tmux sender: type the prompt into a tmux pane.
local function tmux_send(text)
  local pane = M.config.tmux.pane or find_default_pane()
  if not pane then
    vim.notify("prompt-send.nvim: no non-neovim tmux pane found", vim.log.levels.ERROR)
    return
  end
  local data = paste_wrap(text) .. (M.config.tmux.enter and "\r" or "")
  -- `--` stops option parsing, so a prompt starting with `-` is not a flag.
  run_job({ "tmux", "send-keys", "-l", "-t", pane, "--", data }, text, false)
end

--- Terminal buffers that are still running a job.
local function list_terminals()
  local out = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal"
        and vim.b[buf].terminal_job_id then
      table.insert(out, buf)
    end
  end
  return out
end

local function terminal_name(buf)
  local title = vim.b[buf].term_title
  return (title and title ~= "") and title or ("buffer " .. buf)
end

--- Find a Neovim |:terminal| buffer to send into: the one pinned with
--- |:PromptTerminal|, else one whose title looks like an agent (see
--- `agents`), else the most recent one.
local function find_terminal_job()
  if terminal_buf and vim.api.nvim_buf_is_valid(terminal_buf)
      and vim.bo[terminal_buf].buftype == "terminal" then
    return vim.b[terminal_buf].terminal_job_id
  end

  local fallback = nil
  for _, buf in ipairs(list_terminals()) do
    fallback = buf   -- last one wins, i.e. the most recent
    local title = (vim.b[buf].term_title or ""):lower()
    for _, name in ipairs(M.config.agents) do
      if title:find(name:lower(), 1, true) then
        return vim.b[buf].terminal_job_id
      end
    end
  end
  return fallback and vim.b[fallback].terminal_job_id
end

--- `:PromptTerminal` with no argument: pick a terminal from a list.
local function prompt_terminal()
  local terms = list_terminals()
  if #terms == 0 then
    vim.notify("prompt-send.nvim: no terminal buffers found", vim.log.levels.WARN)
    return
  end

  local items = { { buf = nil, name = "auto (prefer a terminal matching agents)" } }
  for _, buf in ipairs(terms) do
    table.insert(items, { buf = buf, name = terminal_name(buf) })
  end

  vim.ui.select(items, {
    prompt = "Select terminal:",
    format_item = function(item) return item.name end,
  }, function(choice)
    if not choice then return end
    terminal_buf = choice.buf
    vim.notify("prompt-send.nvim: terminal set to " .. choice.name)
  end)
end

--- Send `text` into a Neovim terminal buffer (for a TUI running in |:terminal|).
local function terminal_send(text)
  local job = find_terminal_job()
  if not job then
    vim.notify("prompt-send.nvim: no terminal buffer found", vim.log.levels.ERROR)
    return
  end
  local data = paste_wrap(text) .. (M.config.terminal.enter and "\r" or "")
  local ok = pcall(vim.fn.chansend, job, data)
  if not ok then
    vim.notify("prompt-send.nvim: failed to send to terminal", vim.log.levels.ERROR)
  end
end

--- command sender: run the command in `command.run`.
local function command_send(text)
  local run = M.config.command.run
  if run == nil or run == "" then
    vim.notify("prompt-send.nvim: command.run is empty", vim.log.levels.ERROR)
    return
  end
  if type(run) ~= "string" and type(run) ~= "function" then
    vim.notify("prompt-send.nvim: command.run must be a string or function",
      vim.log.levels.ERROR)
    return
  end

  local is_fn = type(run) == "function"
  local ok, result = pcall(function()
    if is_fn then
      return run(text)
    end
    return run
  end)
  if not ok then
    vim.notify("prompt-send.nvim: command error: " .. tostring(result), vim.log.levels.ERROR)
    return
  end

  local argv = to_argv(result)
  local use_stdin = (not is_fn) and M.config.command.stdin
  if not is_fn and not use_stdin then
    table.insert(argv, text)
  end
  run_job(argv, text, use_stdin)
end

--- Send through the method chosen by `via`.
local function external_send(text)
  local via = M.config.via
  if via == "tmux" then
    return tmux_send(text)
  end
  if via == "terminal" then
    return terminal_send(text)
  end
  if via == "command" then
    return command_send(text)
  end
  vim.notify("prompt-send.nvim: unknown via: " .. tostring(via), vim.log.levels.ERROR)
end

-- ── Completion ─────────────────────────────────────────────────────────────

--- `:PromptTmuxPane` completion: `auto` plus the live tmux pane ids.
--- Command-line completion ignores non-string items, so this returns words.
local function pane_complete(arg_lead, _, _)
  local candidates = { "auto" }
  for _, p in ipairs(list_tmux_panes()) do
    table.insert(candidates, p.id)
  end

  -- `auto` first, then pane ids in numeric order
  table.sort(candidates, function(a, b)
    local na, nb = tonumber(a:match("%d+")), tonumber(b:match("%d+"))
    if na and nb then
      return na < nb
    end
    return a == "auto"
  end)

  local out = {}
  for _, w in ipairs(candidates) do
    if w:sub(1, #arg_lead) == arg_lead then
      table.insert(out, w)
    end
  end
  return out
end

local function prompt_complete(arg_lead, _, _)
  local token = arg_lead:match("@([%w_%-]*)$")
  if not token then
    return {}
  end

  local refs = build_refs()
  local candidates = {}
  for name in pairs(refs) do
    if name:sub(1, #token) == token then
      table.insert(candidates, "@" .. name)
    end
  end
  table.sort(candidates)
  return candidates
end

-- ── Public interface ───────────────────────────────────────────────────────

--- Where `:PromptSend` sends prompts. Cheap: never spawns a process, so it is
--- safe to call on every redraw (e.g. from a statusline).
--- @return string  a pane id (e.g. "%0"), "auto", or "command"
function M.target()
  local via = M.config.via
  if via == "terminal" then
    return "terminal"
  end
  if via == "command" then
    return "command"
  end
  return M.config.tmux.pane or "auto"
end

-- ── Setup ──────────────────────────────────────────────────────────────────

--- Check a `setup` options table, returning a list of problems.
local function validate_setup(opts)
  local errs = {}
  local function err(fmt, ...)
    table.insert(errs, string.format(fmt, ...))
  end

  for k in pairs(opts) do
    if not vim.tbl_contains(
      { "via", "tmux", "terminal", "command", "agents", "references" }, k) then
      err("unknown option %q", tostring(k))
    end
  end

  if opts.via ~= nil
      and not vim.tbl_contains({ "tmux", "terminal", "command" }, opts.via) then
    err("via: expected 'tmux', 'terminal' or 'command', got %s", vim.inspect(opts.via))
  end

  local nested = {
    tmux = { "pane", "enter" },
    terminal = { "enter" },
    command = { "run", "stdin" },
  }
  for name, allowed in pairs(nested) do
    local t = opts[name]
    if t ~= nil and type(t) ~= "table" then
      err("%s: expected a table, got %s", name, type(t))
    elseif type(t) == "table" then
      for k in pairs(t) do
        if not vim.tbl_contains(allowed, k) then
          err("%s: unknown option %q", name, tostring(k))
        end
      end
    end
  end

  local function want_bool(tbl, key, where)
    if type(tbl) == "table" and tbl[key] ~= nil and type(tbl[key]) ~= "boolean" then
      err("%s.%s: expected a boolean", where, key)
    end
  end
  want_bool(opts.tmux, "enter", "tmux")
  want_bool(opts.terminal, "enter", "terminal")
  want_bool(opts.command, "stdin", "command")

  if type(opts.tmux) == "table" and opts.tmux.pane ~= nil
      and type(opts.tmux.pane) ~= "string" then
    err("tmux.pane: expected a string (a pane id) or nil")
  end
  if type(opts.command) == "table" and opts.command.run ~= nil
      and type(opts.command.run) ~= "string"
      and type(opts.command.run) ~= "function" then
    err("command.run: expected a string, a function, or nil")
  end
  if opts.agents ~= nil and type(opts.agents) ~= "table" then
    err("agents: expected a table")
  elseif type(opts.agents) == "table" then
    for i, name in ipairs(opts.agents) do
      if type(name) ~= "string" then
        err("agents[%d]: expected a string, got %s", i, type(name))
      end
    end
  end
  if opts.references ~= nil and type(opts.references) ~= "table" then
    err("references: expected a table")
  elseif type(opts.references) == "table" then
    for name, fn in pairs(opts.references) do
      if type(name) ~= "string" then
        err("references: keys must be strings, got %s", type(name))
      elseif type(fn) ~= "function" then
        err("references[%s]: expected a function, got %s", name, type(fn))
      end
    end
  end

  return errs
end

function M.setup(opts)
  opts = opts or {}
  local errs = validate_setup(opts)
  if #errs > 0 then
    vim.notify("prompt-send.nvim: " .. table.concat(errs, "; "), vim.log.levels.ERROR)
    return
  end
  if opts.via ~= nil then M.config.via = opts.via end
  if opts.references ~= nil then M.config.references = opts.references end
  if opts.agents ~= nil then M.config.agents = opts.agents end
  if opts.tmux ~= nil then
    if opts.tmux.pane ~= nil then
      M.config.tmux.pane = (opts.tmux.pane ~= "auto") and opts.tmux.pane or nil
    end
    if opts.tmux.enter ~= nil then M.config.tmux.enter = opts.tmux.enter end
  end
  if opts.terminal ~= nil and opts.terminal.enter ~= nil then
    M.config.terminal.enter = opts.terminal.enter
  end
  if opts.command ~= nil then
    if opts.command.run ~= nil then M.config.command.run = opts.command.run end
    if opts.command.stdin ~= nil then M.config.command.stdin = opts.command.stdin end
  end

  vim.api.nvim_create_user_command("PromptSend", function(args)
    local prompt = args.args
    if prompt == "" then
      vim.notify("prompt-send.nvim: empty prompt", vim.log.levels.WARN)
      return
    end
    local resolved, errors = resolve_prompt(prompt)
    if #errors > 0 then
      vim.notify("prompt-send.nvim: " .. table.concat(errors, "; "), vim.log.levels.ERROR)
      return   -- do not send a prompt with a broken reference
    end
    external_send(resolved)
  end, {
    nargs = "+",
    range = true,
    complete = prompt_complete,
    desc = "Send a prompt with @references",
  })

  vim.api.nvim_create_user_command("PromptTerminal", function(args)
    local arg = vim.trim(args.args)
    if arg == "" then
      prompt_terminal()   -- no argument: open the picker
      return
    end
    if arg == "auto" then
      terminal_buf = nil
      vim.notify("prompt-send.nvim: terminal set to auto")
      return
    end
    for _, buf in ipairs(list_terminals()) do
      local title = vim.b[buf].term_title or ""
      if title:lower():find(arg:lower(), 1, true) then
        terminal_buf = buf
        vim.notify("prompt-send.nvim: terminal set to " .. title)
        return
      end
    end
    vim.notify("prompt-send.nvim: no terminal matching " .. arg, vim.log.levels.WARN)
  end, {
    nargs = "?",
    desc = "Select or set the Neovim terminal that receives prompts",
  })

  vim.api.nvim_create_user_command("PromptTmuxPane", function(args)
    local arg = vim.trim(args.args)
    if arg == "" then
      prompt_tmux_pane()   -- no argument: open the picker
      return
    end
    if arg == "auto" then
      M.config.tmux.pane = nil
    else
      M.config.tmux.pane = arg
    end
    vim.notify("prompt-send.nvim: tmux pane set to " .. arg)
  end, {
    nargs = "?",
    complete = pane_complete,
    desc = "Select or set the tmux pane for prompt sending",
  })
end

M.setup()

return M
