-- Generate doc/prompt-send.txt from the mini.doc annotations in
-- lua/prompt-send.lua. Dev-only; run with `make doc`. Requires mini.nvim on
-- the runtimepath (see the `MINI_NVIM` variable in the Makefile).

if _G.MiniDoc == nil then require('mini.doc').setup() end

MiniDoc.generate(
  { 'lua/prompt-send.lua' },
  'doc/prompt-send.txt'
)
