MINI_NVIM ?= $(HOME)/.local/share/nvim/site/pack/core/opt/mini.nvim

.PHONY: test doc

test:
	nvim --headless -u NONE -l tests/prompt-send_spec.lua

doc:
	nvim --headless -u NONE --cmd "set rtp+=$(MINI_NVIM)" -l scripts/minidoc.lua
