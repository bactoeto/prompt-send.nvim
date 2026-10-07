.PHONY: test

test:
	nvim --headless -u NONE -l tests/prompt-send_spec.lua
