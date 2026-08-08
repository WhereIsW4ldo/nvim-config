# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## What this is

A personal Neovim configuration, written entirely in Lua, living at `~/.config/nvim`.
It is deliberately structured: small single-purpose Lua modules rather than one large
`init.lua`. Plugins are managed by [lazy.nvim](https://github.com/folke/lazy.nvim).

**Current state:** the config was intentionally reset to a clean slate
(commit `36a7fc8`). Only `.editorconfig` and `.gitignore` exist. Everything below
describes the layout to build *into*, not files that already exist — check before
assuming a module is present.

Target Neovim version: **0.12.x** (`nvim --version` on this machine: 0.12.4).
Prefer the modern 0.11+/0.12 APIs (`vim.lsp.config`, `vim.lsp.enable`,
`vim.keymap.set`, `vim.hl`, `vim.o`) over their deprecated predecessors.

## Layout

```
init.lua                    -- entry point; requires config modules in order, nothing else
lua/
  config/
    vim.lua                 -- vim.opt / vim.g options, leader keys
    lazy.lua                -- lazy.nvim bootstrap + { import = "plugin" }
    keymap.lua              -- global, plugin-independent keymaps
    autocommand.lua         -- autocommands and augroups
  plugin/
    <topic>.lua             -- one file per concern, returns a lazy.nvim spec
lazy-lock.json              -- committed; lazy.nvim's lockfile
```

### `init.lua`

Only a fixed sequence of `require` calls. Order matters — leader keys must be set
before lazy.nvim loads, since plugin specs declare `<leader>` mappings at spec time:

```lua
require("config.vim")
require("config.lazy")
require("config.keymap")
require("config.autocommand")
```

### `lua/config/`

Cross-cutting setup that is not tied to any single plugin. Each module is required
for its side effects and returns nothing.

### `lua/plugin/`

Every file returns a lazy.nvim spec — a single table, or an array of tables when
plugins are tightly coupled (e.g. a DAP adapter and its UI). `lua/config/lazy.lua`
imports the whole directory, so a new file is picked up on the next start with no
registration step anywhere else.

```lua
return {
	"author/plugin-name",
	event = "VeryLazy",
	opts  = {},
	keys  = {
		{ "<leader>x", function() end, desc = "Do the thing", },
	},
}
```

Name files by **concern, not by plugin**: `completion.lua`, `lsp.lua`, `search.lua`,
`git.lua`, `statusline.lua`. This keeps a swap of the underlying plugin from turning
into a rename plus a hunt for stale references.

Guidelines for these specs:

- Prefer `opts` over a `config` function. Only write `config` when setup needs logic
  that a table cannot express.
- Declare keymaps in the spec's `keys` field, not in `config/keymap.lua`, so lazy.nvim
  can defer loading. Always give a `desc` — it is what shows up in which-key-style
  pickers and in `:map`.
- Lazy-load on `event`, `ft`, `cmd`, or `keys` wherever it is reasonable. Reserve
  eager loading for colorschemes (`lazy = false`, `priority = 1000`) and anything the
  startup screen depends on.
- One concern per file. If a file grows past ~100 lines, that is a signal to split it.

## Choosing plugins

**Source candidates from [awesome-neovim](https://github.com/rockerBOO/awesome-neovim).**
It is the curated list this config draws from — when a new capability is needed, find
the relevant category there and pick from its entries rather than reaching for whatever
plugin comes to mind first.

- Do not add a plugin that is not listed there without saying so explicitly and giving
  the reason. "It was the first search result" is not a reason.
- When the category offers several viable options, name the alternatives considered and
  why the chosen one won, rather than silently picking one.
- Prefer entries that are actively maintained and Lua-native. The list marks many
  plugins with their status — check before committing to one.

## Lua style

`.editorconfig` is the source of truth and is enforced by the **lua_ls / EmmyLua
formatter** (not stylua — do not add a `stylua.toml`; it would silently disagree).
The settings are non-default in ways that matter:

- **Tabs** for indentation, width 4 — not the 2 spaces most Neovim configs use.
- **Double quotes** for strings.
- Trailing comma on the last table field, always.
- Max line length 120; long lists break one item per line.
- Exactly two blank lines after a `function` statement.
- Continuous assignments and rectangular table fields are aligned.
- No space before a function call's opening paren, but one before a single-argument
  call: `require("foo")` and `print "bar"`.

Beyond formatting:

- `local` everything. No globals except deliberate `vim.g.*` settings.
- Use `vim.keymap.set` with a `desc` on every mapping.
- Wrap autocommands in a named `vim.api.nvim_create_augroup(..., { clear = true, })`
  so re-sourcing does not stack duplicate handlers.

## Verifying changes

There is no test suite. Verify by actually loading the config:

```sh
# Does it load cleanly? Non-zero exit or stderr output means it does not.
nvim --headless "+qa"

# Health of a specific piece
nvim --headless "+checkhealth lazy" "+qa"

# Plugin state
nvim --headless "+Lazy! sync" "+qa"
```

Loading with no errors is a weak signal — a spec can parse fine and still not do
what was asked. For anything user-visible (a keymap, a colorscheme, completion
behaviour), say plainly that it needs an interactive check rather than reporting it
as confirmed working.

## Conventions to keep

- Commit messages follow Conventional Commits: `feat:`, `fix:`, `chore:`,
  as in the existing history.
- Commit `lazy-lock.json` alongside any plugin change.
- Some plugins need external toolchains (Rust for `blink.cmp`, `tree-sitter` CLI for
  parsers, `node`, language servers via Mason). When adding one, note the requirement
  in `README.md` instead of leaving a build failure for later.
