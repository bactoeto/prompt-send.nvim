-- Minimal tests for prompt-send.nvim. No dependencies, no tmux, no network.
--
--   make test
--   # or:
--   nvim --headless -u NONE -l tests/prompt-send_spec.lua

-- Load the plugin from this repo regardless of the working directory.
local this = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(this, ':h:h')
package.path = root .. '/lua/?.lua;' .. package.path
local prompt = require('prompt-send')

-- -- tiny harness ------------------------------------------------------------

local passed, failed = 0, 0

local function check(desc, ok, detail)
  if ok then
    passed = passed + 1
    io.write('PASS  ' .. desc .. '\n')
  else
    failed = failed + 1
    io.write('FAIL  ' .. desc .. '\n        ' .. (detail or '') .. '\n')
  end
end

local function eq(desc, got, want)
  check(desc, vim.deep_equal(got, want),
    'want=' .. vim.inspect(want) .. '  got=' .. vim.inspect(got))
end

-- Capture what would be sent instead of running a command.
local sent, notes
vim.notify = function(msg) table.insert(notes, msg) end

local function resolve(text, opts)
  sent, notes = nil, {}
  prompt.setup(vim.tbl_extend('force', {
    send = function(p) sent = p; return { 'true' } end,
  }, opts or {}))
  vim.cmd('PromptSend ' .. text)
  return sent, notes
end

-- -- references --------------------------------------------------------------

vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'BUF' })

eq('@buffer resolves', resolve('x=@buffer'), 'x=BUF')
eq('@@ escapes an @', resolve('a @@buffer b'), 'a @buffer b')
eq('escape and resolve can mix', resolve('@@buffer and @buffer'), '@buffer and BUF')
eq('unknown @name is left as-is', resolve('keep @nope here'), 'keep @nope here')
eq('hyphenated name resolves',
  resolve('@my-ref', { references = { ['my-ref'] = function() return 'X' end } }), 'X')
eq('@n is a newline', resolve('a@nb'), 'a\nb')
eq('@@n is a literal @n', resolve('@@n'), '@n')
eq('empty string is a success',
  resolve('@empty', { references = { empty = function() return '' end } }), '')

do
  local s, n = resolve('try @boom end',
    { references = { boom = function() error('kaboom') end } })
  eq('a failing reference sends nothing', s, nil)
  check('a failing reference notifies', #n > 0, 'notes=' .. vim.inspect(n))
end

-- -- target() ----------------------------------------------------------------

prompt.config.send = nil
eq('target: auto by default', prompt.target(), 'auto')
prompt.setup({ pane = '%2' })
eq('target: pinned pane', prompt.target(), '%2')
prompt.setup({ pane = 'auto' })
eq('target: back to auto', prompt.target(), 'auto')
prompt.setup({ send = 'some-cmd' })
eq('target: custom send', prompt.target(), 'command')

-- -- setup stores options ----------------------------------------------------

prompt.setup({ pane = '%5', agents = { 'a', 'b' } })
eq('pane is stored', prompt.config.pane, '%5')
eq('agents are stored', prompt.config.agents, { 'a', 'b' })

-- -- summary -----------------------------------------------------------------

io.write(('\n%d passed, %d failed\n'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
