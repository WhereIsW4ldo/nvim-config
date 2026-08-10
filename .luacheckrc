-- luacheck configuration for this repo, read by the `lua` entry in `lua/plugin/lint.lua`.
--
-- Without it every file here opens with `accessing undefined variable vim` on almost every
-- line -- `vim` is the one global a Neovim config is built out of, and luacheck has no way
-- to know that. luacheck discovers this file by walking up from the working directory, so
-- it applies to the whole config and to nothing outside it.

-- Neovim embeds LuaJIT, so the standard library is 5.1 plus the JIT extensions -- not the
-- `lua54` luacheck would otherwise assume.
std = "luajit"

-- `globals`, not `read_globals`: this config assigns through it (`vim.g.mapleader`,
-- `vim.o.*`, `vim.diagnostic.config`), and a read-only global would report every one of
-- those as setting a read-only field.
globals = {
	"vim",
}

-- Agrees with `.editorconfig`'s `max_line_length`, so the linter and the formatter cannot
-- disagree about where a line ends. Restated rather than left to luacheck's default,
-- which happens to be the same number today and is not a promise.
max_line_length = 120
