-- prompt-send.nvim
-- AI-generated, zero hand-written code. A human only directed and reviewed.
-- A Neovim Lua plugin for sending prompts with @references via tmux or external CLI.

local M = {}

-- ── Configuration ──────────────────────────────────────────────────────────

M.config = {
  send = nil,          -- string | fun(prompt): string|string[]
  enter = true,
  stdin = false,       -- pass prompt via stdin instead of as the last arg
  references = {},
  pane = nil,          -- tmux pane to send to; nil / "auto" = scan
  agents = {           -- names matched against pane command + title
    "opencode", "claude", "codex", "aider", "gemini", "crush", "goose",
    "cursor-agent", "openhands",
  },
}

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
  resolved = resolved:gsub("@([%w_]+)", function(name)
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
  local base = cmd:match("([^/]+)$"):lower()
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

  local items = { { id = nil, cmd = "auto (scan for first non-neovim pane)" } }
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
      M.config.pane = nil
      vim.notify("prompt-send.nvim: tmux pane set to auto")
    else
      M.config.pane = choice.id
      vim.notify("prompt-send.nvim: tmux pane set to " .. choice.id)
    end
  end)
end

-- ── Sending ────────────────────────────────────────────────────────────────

--- Default `send`: type the prompt into a tmux pane. Just a function, like
--- any user-supplied `send`; it returns the argv to run.
--- @param prompt string
--- @return string[]
local function tmux_argv(prompt)
  local pane = M.config.pane or find_default_pane()
  if not pane then
    error("no non-neovim tmux pane found")
  end
  local argv = { "tmux", "send-keys", "-t", pane, prompt }
  if M.config.enter then
    table.insert(argv, "Enter")
  end
  return argv
end

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
--- whitespace) or, when a `send` function returns one, an argv table.
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

local function external_send(text)
  local spec = M.config.send or tmux_argv
  local is_fn = type(spec) == "function"
  if not is_fn and type(spec) ~= "string" then
    vim.notify("prompt-send.nvim: send must be a string or a function", vim.log.levels.ERROR)
    return
  end

  -- A function receives the resolved prompt and returns the complete argv,
  -- with the prompt already placed; stdin is not applied in that case.
  local ok, result = pcall(function()
    if is_fn then
      return spec(text)
    end
    return spec
  end)
  if not ok then
    vim.notify("prompt-send.nvim: send error: " .. tostring(result), vim.log.levels.ERROR)
    return
  end

  local argv = to_argv(result)
  if #argv == 0 then
    vim.notify("prompt-send.nvim: send is empty", vim.log.levels.ERROR)
    return
  end

  local use_stdin = (not is_fn) and M.config.stdin
  if not is_fn and not use_stdin then
    table.insert(argv, text)
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
  local token = arg_lead:match("@([%w_]*)$")
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
  if M.config.send ~= nil then
    return "command"
  end
  return M.config.pane or "auto"
end

-- ── Setup ──────────────────────────────────────────────────────────────────

function M.setup(opts)
  opts = opts or {}
  if opts.send ~= nil then M.config.send = opts.send end
  if opts.enter ~= nil then M.config.enter = opts.enter end
  if opts.stdin ~= nil then M.config.stdin = opts.stdin end
  if opts.references ~= nil then M.config.references = opts.references end
  if opts.pane ~= nil then
    M.config.pane = (opts.pane ~= "auto") and opts.pane or nil
  end
  if opts.agents ~= nil then M.config.agents = opts.agents end

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

  vim.api.nvim_create_user_command("PromptTmuxPane", function(args)
    local arg = vim.trim(args.args)
    if arg == "" then
      prompt_tmux_pane()   -- no argument: open the picker
      return
    end
    if arg == "auto" then
      M.config.pane = nil
    else
      M.config.pane = arg
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
