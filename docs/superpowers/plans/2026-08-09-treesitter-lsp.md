# Tree-sitter and LSP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tree-sitter parsers with highlighting and structural folding, plus
mason-managed language servers, to this Neovim config — with Lua as the only language.

**Architecture:** Three new concern-named files in `lua/plugin/`. `treesitter.lua` owns
parsers, highlighting and folds, driven by a single `languages` list. `lsp.lua` owns the
mason/lspconfig/lazydev specs and the `LspAttach` navigation keymaps. `diagnostic.lua`
owns `vim.diagnostic.config()` and the `<leader>d` pickers, returned as a `snacks.nvim`
spec that lazy.nvim merges with the existing one in `ui.lua`. Neovim 0.12 already provides
most of the LSP surface, so all three files are deliberately thin — they fill named gaps
rather than rebuild what core ships.

**Tech Stack:** Neovim 0.12.4, lazy.nvim, `nvim-treesitter` (`main` branch),
`mason-org/mason.nvim`, `mason-org/mason-lspconfig.nvim`, `neovim/nvim-lspconfig`,
`folke/lazydev.nvim`, `folke/snacks.nvim` (already installed).

**Spec:** `docs/superpowers/specs/2026-08-09-treesitter-lsp-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Target Neovim 0.12.4.** Use modern APIs: `vim.lsp.enable`, `vim.keymap.set`, `vim.o`.
- **Linux only.** macOS is structurally handled in `install.sh` but untested. No
  Linux-only paths or GNU-only flags without saying so.
- **There is no test suite.** "Tests" in this plan are headless `nvim` assertions that
  print observable state. Run them and read the output; do not infer.
- **Lua style is enforced by the lua_ls / EmmyLua formatter via `.editorconfig`.** Do not
  add a `stylua.toml`. Specifically: **tabs**, width 4; **double quotes**; trailing comma
  on the last table field, always; max line length 120; `line_space_after_function_statement
  = fixed(2)` — exactly two blank lines after a function statement; continuous assignments
  and rectangular table fields aligned; no space before a call's paren (`require("foo")`)
  but one before a single-argument call (`print "bar"`).
- **`local` everything.** No globals except deliberate `vim.g.*`.
- **Every keymap carries a `desc`.** It is what which-key and `:map` display.
- **Every autocommand lives in a named augroup** created with `{ clear = true, }`.
- **Plugin keymaps go in the spec's `keys` field**, not `config/keymap.lua` — except
  buffer-local ones that must be set on an event, which belong in that event's autocommand.
- **Conventional Commits**: `feat:`, `fix:`, `chore:`, `docs:`.
- **Commit `lazy-lock.json` alongside any plugin change.**
- **Verified upstream facts — do not re-derive, and do not substitute:**
  - `nvim-treesitter`'s default branch is `main`; `master` is frozen and its API is
    entirely different. `main` requires Neovim 0.12.0+.
  - `nvim-treesitter` `main` needs the `tree-sitter` CLI **0.26.1+ from a package manager,
    not npm**, plus a C compiler, `tar` and `curl`.
  - `setup()` is optional for `nvim-treesitter` `main`. Do not call it.
  - mason lives at **`mason-org/`**, not `williamboman/`. mason-lspconfig requires
    `mason >= 2.0.0` and `nvim-lspconfig >= 2.0.0`.
  - `mason-lspconfig`'s `ensure_installed` takes **lspconfig** server names (`lua_ls`),
    and `automatic_enable` defaults to `true`.
  - `nvim-lspconfig`'s `lsp/lua_ls.lua` sets only `codeLens` and `hint`. It does **not**
    add the Neovim runtime to the workspace.
  - These snacks picker sources exist verbatim: `lsp_definitions`, `lsp_references`,
    `lsp_implementations`, `lsp_type_definitions`, `lsp_symbols`, `diagnostics`,
    `diagnostics_buffer`.

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `install.sh` | Modify | Toolchain entries; `-` presence-only minimum |
| `README.md` | Modify | New requirements; language-servers-are-mason note |
| `lua/plugin/treesitter.lua` | Create | Parser list, highlighting, fold wiring |
| `lua/config/vim.lua` | Modify | Two global fold options |
| `lua/plugin/lsp.lua` | Create | mason, mason-lspconfig, lspconfig, lazydev; `LspAttach` keymaps |
| `CLAUDE.md` | Modify | Amend the dependency convention for the mason split |
| `lua/plugin/diagnostic.lua` | Create | `vim.diagnostic.config()`, `<leader>d` pickers |
| `lua/plugin/keybinding.lua` | Modify | `<leader>d` which-key group |

---

### Task 1: Toolchain dependencies

Adds every external tool the new plugins need to `install.sh`, so `--check` reports them
on a new machine. Nothing in this task changes editor behaviour — it is the provisioning
gate for Task 2, which cannot compile a parser without a `tree-sitter` CLI and a compiler.

**Files:**
- Modify: `install.sh:22-32` (header comment + `BREW_DEPS` table)
- Modify: `install.sh:148-175` (the Tools loop)
- Modify: `README.md:10-15` (Requirements table)

**Interfaces:**
- Consumes: nothing.
- Produces: a `BREW_DEPS` entry format of `command|minimum|brew formula|probe` where a
  minimum of `-` means presence-only. Later tasks add no dependencies.

- [ ] **Step 1: Write the failing test**

Two separate assertions — the tools are reported, *and* `--check` still exits 0. Keep them
separate: piping into `grep` makes `$?` grep's exit code, not the script's. Save as a
scratch file, do not commit it:

```bash
# check-deps.sh
out="$(./install.sh --check 2>&1)"; status=$?
for tool in tree-sitter cc curl unzip tar gzip; do
	printf '%-12s ' "$tool"
	printf '%s\n' "$out" | grep -qE "^  . $tool " && echo reported || echo MISSING
done
echo "check_exit=$status"
```

Expected once implemented: all six `reported`, and `check_exit=0`.

- [ ] **Step 2: Run it to verify it fails**

```bash
bash check-deps.sh
```

Expected now: all six `MISSING`. `check_exit=0` already, since the script currently has
nothing to complain about.

- [ ] **Step 3: Teach the Tools loop that `-` means presence-only**

Replace the loop at `install.sh:148-175` in full. Two branches are added; everything else
is unchanged:

```bash
for entry in "${BREW_DEPS[@]}"; do
	IFS='|' read -r cmd min formula probe <<<"$entry"

	if have "$cmd"; then
		# A `-` minimum means presence is all that matters -- tools with no meaningful
		# version floor, where probing would report the useless `✓ unzip 0 (>= 0)`.
		if [ "$min" = "-" ]; then
			ok "$cmd present ($(command -v "$cmd"))"
			continue
		fi

		current="$(eval "$probe" 2>/dev/null || echo "0")"
		if version_ge "$current" "$min"; then
			ok "$cmd $current (>= $min)"
			continue
		fi
		warn "$cmd $current is older than $min"
	else
		warn "$cmd not found"
	fi

	if $CHECK_ONLY; then
		bad "$cmd needs installing (brew formula: $formula)"
		MISSING=$((MISSING + 1))
		continue
	fi

	have brew || die "Homebrew is required to install $cmd"
	brew install "$formula"

	if [ "$min" = "-" ]; then
		have "$cmd" || die "$cmd still not on PATH after installing $formula"
		ok "$cmd installed"
		continue
	fi

	current="$(eval "$probe" 2>/dev/null || echo "0")"
	version_ge "$current" "$min" \
		|| die "$cmd is $current after install, still below $min"
	ok "$cmd $current installed"
done
```

- [ ] **Step 4: Document the `-` convention in the format comment**

Replace `install.sh:23`:

```bash
# Format: command|minimum version|brew formula|shell snippet printing the version
```

with:

```bash
# Format: command|minimum version|brew formula|shell snippet printing the version
# A minimum of `-` means presence-only: no version probe, leave the probe field empty.
# Do NOT add a fifth field -- `read` gives the last variable everything remaining,
# including `|`, which is what lets the probes below contain pipes.
```

- [ ] **Step 5: Add the six entries to `BREW_DEPS`**

Append inside the `BREW_DEPS=(...)` array, after the existing `lazygit` entry:

```bash
	# nvim-treesitter compiles parsers locally with the tree-sitter CLI. Upstream is
	# explicit that it must come from a package manager and NOT npm.
	# `--version` prints `tree-sitter 0.26.3`, hence field 2.
	"tree-sitter|0.26.1|tree-sitter|tree-sitter --version | awk '{print \$2}'"
	# A C compiler for those parsers. Presence-only: on Linux `cc` comes from the distro's
	# build tools (Debian/Ubuntu: build-essential), and `brew install gcc` provides
	# `gcc-13` rather than `cc`, so the brew path here is nominal. Listed anyway so
	# --check reports it on a fresh machine, which is this script's job.
	"cc|-|gcc|"
	# mason shells out to these four to download and unpack language servers.
	"curl|-|curl|"
	"unzip|-|unzip|"
	# On Linux `tar` is already GNU tar. brew's `gnu-tar` installs `gtar`, not `tar`, so
	# as with `cc` the formula is nominal and the value is in --check reporting it.
	"tar|-|gnu-tar|"
	"gzip|-|gzip|"
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
bash check-deps.sh
./install.sh --check          # read the Tools section directly
```

Expected: all six `reported`, `check_exit=0`. In the Tools section, `tree-sitter` shows a
version (`✓ tree-sitter 0.26.3 (>= 0.26.1)`) while `cc`, `curl`, `unzip`, `tar` and `gzip`
each show `present (/path/to/it)` with no version. No `✗` lines.

Then delete the scratch file: `rm check-deps.sh`

- [ ] **Step 7: Confirm the piped probes still work**

This is the regression the format comment warns about. The existing entries have probes
containing `|`:

```bash
./install.sh --check 2>&1 | grep -E '^  . (git|node|lazygit|nvim) '
```

Expected: each shows a real version number, e.g. `✓ git 2.51.0 (>= 2.19.0)`. A bare `0`
or `(>= ...)` against an empty version means a probe got truncated.

- [ ] **Step 8: Record the new requirements in `README.md`**

Add to the Requirements table at `README.md:10-15`, after the `lazygit` row:

```markdown
| tree-sitter CLI **0.26.1+** | `nvim-treesitter` compiles parsers locally | From a package manager, **not npm** — upstream is explicit |
| A C compiler (`cc`) | Compiling those parsers | Debian/Ubuntu: `apt install build-essential` |
| `curl`, `unzip`, `tar`, `gzip` | mason downloads and unpacks language servers | Present on any base Linux except sometimes `unzip` |
```

- [ ] **Step 9: Commit**

```bash
git add install.sh README.md
git commit -m "chore: add tree-sitter and mason toolchain dependencies

install.sh gains the tree-sitter CLI, a C compiler, and the four tools
mason shells out to. Presence-only entries use a \`-\` minimum, since
unzip and gzip have no meaningful version floor.

The hint field considered during design was dropped: a fifth field would
truncate every existing piped version probe."
```

---

### Task 2: Tree-sitter highlighting and folding

**Files:**
- Delete: `~/.local/share/nvim/site/parser/`, `~/.local/share/nvim/site/parser-info/`,
  `~/.local/share/nvim/site/queries/` (outside the repo, not committed)
- Create: `lua/plugin/treesitter.lua`
- Modify: `lua/config/vim.lua` (after `opt.scrolloff = 8`)
- Modify: `lazy-lock.json` (generated)

**Interfaces:**
- Consumes: the `tree-sitter` CLI and `cc` guaranteed by Task 1.
- Produces: a local `languages` table in `lua/plugin/treesitter.lua`, the single list of
  supported languages. The augroup name `waldo_treesitter`. Task 3's `ensure_installed`
  is the LSP-side twin of this list; the two are edited together when a language is added.

**What this task does and does not prove.** Lua already highlights via
`$VIMRUNTIME/ftplugin/lua.lua`, so highlighting-for-Lua is not evidence the new machinery
works. The observable deliverables here are `foldmethod=expr` (core does not set it), the
list-driven autocommand, and a repopulated parser directory. The generalisation to other
languages gets its real test when the language list lands.

- [ ] **Step 1: Record the stale state before deleting anything**

```bash
ls ~/.local/share/nvim/site/; du -sh ~/.local/share/nvim/site/
ls ~/.local/share/nvim/site/parser | wc -l
ls ~/.local/share/nvim/site/queries | wc -l
find ~/.local/share/nvim/site -type f -printf '%T+ %p\n' | sort -r | head -3
```

Expected: `pack parser parser-info queries`, ~58M, 37 parsers, 40 query dirs, newest file
dated 2026-04-10. Confirm these before deleting — if the numbers differ materially,
stop and report rather than proceeding.

- [ ] **Step 2: Delete the three stale directories**

`nvim-treesitter` `main` installs to `stdpath("data") .. "/site"` — the same directory.
New parsers compiled beside four-month-old `master` queries fail badly, because the old
queries reference node names that no longer exist.

`pack/` is **kept**: `site/pack/core/opt` is core's own `vim.pack` directory, and it is
empty.

```bash
rm -rf ~/.local/share/nvim/site/parser \
       ~/.local/share/nvim/site/parser-info \
       ~/.local/share/nvim/site/queries
ls ~/.local/share/nvim/site/
```

Expected: `pack` only.

- [ ] **Step 3: Write the failing test**

```bash
nvim --headless "+edit lua/config/vim.lua" \
  "+lua local b = vim.api.nvim_get_current_buf() print(('highlighter=%s foldmethod=%s'):format(tostring(vim.treesitter.highlighter.active[b] ~= nil), vim.wo.foldmethod))" \
  "+qa"
```

- [ ] **Step 4: Run it to verify it fails**

Expected now: `highlighter=true foldmethod=manual`

`highlighter=true` already — that is core's Lua ftplugin, not us. **`foldmethod=manual` is
the failing half**, and it is what this task changes to `expr`.

- [ ] **Step 5: Create `lua/plugin/treesitter.lua`**

```lua
-- Tree-sitter parsers, highlighting and structural folding.
--
-- Neovim bundles parsers and queries for c, lua, markdown, markdown_inline, query, vim
-- and vimdoc, and `$VIMRUNTIME/ftplugin/lua.lua` already starts the highlighter and sets
-- `foldexpr` for Lua. This file generalises both to every other language, and adds the
-- half that ftplugin leaves out -- `foldmethod`, without which `foldexpr` is inert.
--
-- Parsers are compiled locally, so this needs the `tree-sitter` CLI (>= 0.26.1, from a
-- package manager and NOT npm) plus a C compiler. Both live in `install.sh`.

-- The single answer to "which languages does this config support". It drives both the
-- parser install and the autocommand pattern below, so adding a language is one edit
-- here -- plus its server in `lua/plugin/lsp.lua`.
local languages = {
	"lua",
}


return {
	"nvim-treesitter/nvim-treesitter",

	-- `main` is the repo default, but it is named anyway: `master` is frozen and its API
	-- is entirely different, so which branch this is matters more than most spec fields.
	branch = "main",

	-- Not deferrable. Parsers must be installable before the first file opens, and the
	-- FileType autocommand has to be registered before the first FileType fires.
	lazy = false,

	-- Parser revisions are pinned inside the plugin commit, so updating the plugin can
	-- leave a compiled parser stale. This recompiles them.
	build = ":TSUpdate",

	-- `setup()` is deliberately absent: upstream states it is not needed for default
	-- values, and the only option it takes is `install_dir`, whose default is correct.
	config = function()
		require("nvim-treesitter").install(languages)

		local group = vim.api.nvim_create_augroup("waldo_treesitter", { clear = true, })

		vim.api.nvim_create_autocmd("FileType", {
			group = group,
			pattern = languages,
			desc = "Start tree-sitter highlighting and structural folding",
			callback = function()
				-- `install()` is asynchronous, so on a cold machine a buffer can open
				-- before its parser has finished compiling. Unwrapped, `start()` throws
				-- that at the user on their very first launch.
				if not pcall(vim.treesitter.start) then
					return
				end

				-- Window-local-to-buffer, the way the runtime ftplugins set it, so these
				-- do not leak into a window later showing a file with no parser.
				vim.wo[0][0].foldmethod = "expr"
				vim.wo[0][0].foldexpr   = "v:lua.vim.treesitter.foldexpr()"
			end,
		})
	end,
}
```

- [ ] **Step 6: Add the two global fold options**

In `lua/config/vim.lua`, insert after `opt.scrolloff = 8` and before the
`-- Indentation options are deliberately absent.` comment:

```lua
-- Folding is driven by tree-sitter, which sets `foldmethod` and `foldexpr` per buffer in
-- `lua/plugin/treesitter.lua`. These two are global because they are safe whether or not
-- a buffer has a parser.
--
-- Without `foldlevelstart` every file opens with every fold closed, which is startling.
opt.foldlevelstart = 99

-- An empty `foldtext` makes Neovim render a closed fold using the line's real syntax
-- highlighting, instead of the grey `+--  12 lines:` filler. Needs 0.10+.
opt.foldtext = ""
```

- [ ] **Step 7: Install the plugin and compile the parser**

```bash
nvim --headless "+Lazy! sync" "+qa"
```

Then wait for the parser install, which is asynchronous:

```bash
nvim --headless "+lua require('nvim-treesitter').install({ 'lua' }):wait(300000)" "+qa"
ls ~/.local/share/nvim/site/parser ~/.local/share/nvim/site/queries
```

Expected: `parser/lua.so`, and a `queries/lua` directory. Only Lua — no trace of the 37
stale parsers.

- [ ] **Step 8: Run the test to verify it passes**

```bash
nvim --headless "+edit lua/config/vim.lua" \
  "+lua local b = vim.api.nvim_get_current_buf() print(('highlighter=%s foldmethod=%s'):format(tostring(vim.treesitter.highlighter.active[b] ~= nil), vim.wo.foldmethod))" \
  "+qa"
```

Expected: `highlighter=true foldmethod=expr`

- [ ] **Step 9: Assert the autocommand is list-driven**

This is what makes adding a language a one-line edit, so verify the pattern really comes
from `languages` rather than being hardcoded:

```bash
nvim --headless \
  "+lua local a = vim.api.nvim_get_autocmds({ group = 'waldo_treesitter', event = 'FileType' }) print(('count=%d pattern=%s'):format(#a, a[1] and a[1].pattern or 'none'))" \
  "+qa"
```

Expected: `count=1 pattern=lua`

- [ ] **Step 10: Confirm a clean load and healthy tree-sitter**

```bash
nvim --headless "+qa"; echo "exit=$?"
nvim --headless "+checkhealth vim.treesitter" "+qa" 2>&1 | grep -iE '(ERROR|WARNING|lua)'
```

Expected: exit 0 with no stderr. The health output lists `lua` as an installed parser and
reports no ERROR.

- [ ] **Step 11: Commit**

```bash
git add lua/plugin/treesitter.lua lua/config/vim.lua lazy-lock.json
git commit -m "feat: add tree-sitter highlighting and structural folding

nvim-treesitter on the main branch, with a single \`languages\` list driving
both the parser install and the FileType autocommand. Folding uses
vim.treesitter.foldexpr(), set window-local-to-buffer so filetypes without
a parser keep their normal fold behaviour.

Lua already highlighted via \$VIMRUNTIME/ftplugin/lua.lua; what this adds
for Lua is foldmethod=expr, and the generalisation to other languages.

Required removing ~/.local/share/nvim/site/{parser,parser-info,queries},
stale master-branch state sharing the same install_dir."
```

---

### Task 3: Language servers

**Files:**
- Create: `lua/plugin/lsp.lua`
- Modify: `CLAUDE.md:163-169` (the dependency convention bullet)
- Modify: `README.md` (new External dependencies subsection)
- Modify: `lazy-lock.json` (generated)

**Interfaces:**
- Consumes: `curl`, `unzip`, `tar`, `gzip` from Task 1. The `languages` list in
  `lua/plugin/treesitter.lua` from Task 2, whose LSP twin is `ensure_installed` here.
  `require("snacks").picker` from the existing `lua/plugin/ui.lua`.
- Produces: the augroup name `waldo_lsp_attach`. Buffer-local mappings `gd`, `grr`, `gri`,
  `grt`, `gO`. An `ensure_installed` list of lspconfig server names.

**First run downloads.** mason fetches `lua-language-server` on first start. Expect the
attach assertions to take up to a minute or two and to need network.

- [ ] **Step 1: Write the failing test**

```bash
nvim --headless "+edit lua/config/vim.lua" \
  "+lua vim.wait(120000, function() return #vim.lsp.get_clients({ bufnr = 0 }) > 0 end)
        local c = vim.lsp.get_clients({ bufnr = 0 })
        local m = vim.fn.maparg('gd', 'n', false, true)
        print(('clients=%d name=%s gd_buffer_local=%s'):format(#c, c[1] and c[1].name or 'none', tostring(m.buffer == 1)))" \
  "+qa"
```

- [ ] **Step 2: Run it to verify it fails**

Expected now: `clients=0 name=none gd_buffer_local=false`, after the full wait elapses.
To avoid waiting two minutes on the failing run, temporarily lower `120000` to `2000`.

- [ ] **Step 3: Create `lua/plugin/lsp.lua`**

```lua
-- Language servers: installation, enablement, and the navigation keymaps.
--
-- Neovim 0.12 already provides most of the LSP surface -- `grn`, `gra`, `grr`, `gri`,
-- `grt`, `grx`, `gO`, `K`, `<C-s>`, `]d`/`[d` and `gq` are all default mappings, and
-- `vim.lsp.enable()` is core. So this file is deliberately thin: it installs servers,
-- lets them enable themselves, and swaps the quickfix window for a picker.
--
-- Servers are managed by mason, NOT by `install.sh`. That is a deliberate departure from
-- this repo's usual rule, recorded in CLAUDE.md's dependency bullet. The trade is
-- reproducibility for convenience -- mason has no lockfile, so server versions float and
-- `:Mason` then `U` updates them. `install.sh` still guarantees the toolchains mason
-- shells out to. If a floating version ever bites, `ensure_installed` accepts per-server
-- pinning (`"rust_analyzer@nightly"`) without adopting a lockfile.
--
-- An array of specs rather than one table, because these four are only useful together.
return {
	{
		"mason-org/mason.nvim",

		-- Note the owner: mason moved to the `mason-org` organisation for v2. The
		-- `williamboman/*` paths are the v1 line and are not what this uses.
		opts = {},
	},

	{
		"mason-org/mason-lspconfig.nvim",

		-- mason must be set up before this runs, and nvim-lspconfig supplies the
		-- `lsp/<server>.lua` definitions that `vim.lsp.enable()` reads off the
		-- runtimepath. `dependencies` states that; relying on load order would not.
		dependencies = {
			"mason-org/mason.nvim",
			"neovim/nvim-lspconfig",
		},

		opts = {
			-- lspconfig server names, NOT mason package names -- translating between the
			-- two is precisely what this plugin exists for. `lua_ls` here is the mason
			-- package `lua-language-server`.
			--
			-- Adding a language means editing this list and the `languages` list in
			-- `lua/plugin/treesitter.lua`.
			ensure_installed = { "lua_ls", },

			-- Already the default. Stated because it is the reason no server is
			-- configured by hand anywhere in this config: mason-lspconfig calls
			-- `vim.lsp.enable()` for every installed server itself.
			automatic_enable = true,
		},
	},

	{
		"neovim/nvim-lspconfig",

		-- Buffer-local keymaps, set when a client attaches. They deliberately reuse
		-- Neovim's own key names -- nothing here is vocabulary you would have to unlearn
		-- elsewhere -- and change only the UI: core opens a quickfix window for
		-- multi-result jumps, these open the snacks picker, which previews and filters.
		--
		-- Buffer-local rather than global, so core's own global mappings remain the
		-- fallback in buffers with no client, where they explain themselves politely.
		--
		-- `gd` is the one genuinely absent mapping: core leaves go-to-definition on
		-- `<C-]>` via `tagfunc` and binds no `g`-prefixed key to it.
		init = function()
			local group = vim.api.nvim_create_augroup("waldo_lsp_attach", { clear = true, })

			vim.api.nvim_create_autocmd("LspAttach", {
				group = group,
				desc = "LSP navigation keymaps, backed by the snacks picker",
				callback = function(args)
					-- The picker is named rather than passed as a function value so the
					-- snacks picker module stays unloaded until a key is actually pressed.
					local function map(lhs, source, desc)
						vim.keymap.set("n", lhs, function()
							require("snacks").picker[source]()
						end, { buffer = args.buf, desc = desc, })
					end


					map("gd", "lsp_definitions", "Goto definition")
					map("grr", "lsp_references", "References")
					map("gri", "lsp_implementations", "Goto implementation")
					map("grt", "lsp_type_definitions", "Goto type definition")
					map("gO", "lsp_symbols", "Document symbols")
				end,
			})
		end,
	},

	{
		-- Makes lua_ls understand Neovim. nvim-lspconfig's `lsp/lua_ls.lua` sets only
		-- `codeLens` and `hint` -- it does NOT add the Neovim runtime to the workspace,
		-- so without this `vim` is reported as an undefined global in every file here.
		--
		-- It also resolves the `---@module` / `---@type` annotations this config already
		-- uses, whose types live under lazy.nvim's plugin directory rather than on the
		-- runtimepath. Hand-writing `workspace.library` fixes the undefined global but
		-- not those annotations, and loads the whole runtime eagerly rather than on
		-- demand.
		"folke/lazydev.nvim",
		ft = "lua",

		---@module "lazydev"
		---@type lazydev.Config
		opts = {
			library = {
				-- `vim.uv` types ship as a lua_ls third-party addon rather than as part
				-- of the runtime, so they need naming explicitly.
				{ path = "${3rd}/luv/library", words = { "vim%.uv", }, },
			},
		},
	},
}
```

- [ ] **Step 4: Install the plugins and let mason fetch the server**

```bash
nvim --headless "+Lazy! sync" "+qa"
nvim --headless "+lua vim.wait(300000, function() return vim.fn.executable('lua-language-server') == 1 end) print('lua-language-server=' .. vim.fn.executable('lua-language-server'))" "+qa"
```

Expected: `lua-language-server=1`. mason prepends its `bin` directory to `vim.env.PATH`,
so `executable()` finds it inside Neovim even though your shell will not.

- [ ] **Step 5: Run the test to verify it passes**

```bash
nvim --headless "+edit lua/config/vim.lua" \
  "+lua vim.wait(120000, function() return #vim.lsp.get_clients({ bufnr = 0 }) > 0 end)
        local c = vim.lsp.get_clients({ bufnr = 0 })
        local m = vim.fn.maparg('gd', 'n', false, true)
        print(('clients=%d name=%s gd_buffer_local=%s'):format(#c, c[1] and c[1].name or 'none', tostring(m.buffer == 1)))" \
  "+qa"
```

Expected: `clients=1 name=lua_ls gd_buffer_local=true`

- [ ] **Step 6: Confirm a clean load and healthy mason and LSP**

```bash
nvim --headless "+qa"; echo "exit=$?"
nvim --headless "+checkhealth mason" "+qa" 2>&1 | grep -iE '(ERROR|WARNING)'
nvim --headless "+checkhealth vim.lsp" "+qa" 2>&1 | grep -iE 'ERROR'
./install.sh --check; echo "exit=$?"
```

Expected: exit 0 from both `nvim` and `--check`. No ERROR from either health check.
`checkhealth mason` may WARN about optional toolchains for servers not installed here
(`cargo`, `go`, `python`); that is expected and is not a failure — only report an ERROR,
or a warning about `curl`/`unzip`/`tar`/`gzip`, which Task 1 was supposed to cover.

- [ ] **Step 7: Amend the dependency convention in `CLAUDE.md`**

The existing bullet names "a language server" as something that must live in `install.sh`,
which this task knowingly stops being true. Replace `CLAUDE.md:163-169`:

```markdown
- **External dependencies live in `install.sh`.** Some plugins need a toolchain that is
  not a Lua file (Rust for `blink.cmp`, the `tree-sitter` CLI for parsers, Node, a
  language server, a global npm package). Every one of those must be added to
  `install.sh`'s `BREW_DEPS` or `NPM_DEPS` table *and* to `README.md` — otherwise a
  fresh machine gets a plugin that loads but silently does nothing. `./install.sh
  --check` verifies the tables match reality and exits non-zero if not. The
  `add-nvim-plugin` skill enforces this as a step.
```

with:

```markdown
- **External dependencies live in `install.sh`.** Some plugins need a toolchain that is
  not a Lua file (Rust for `blink.cmp`, the `tree-sitter` CLI for parsers, Node, a
  global npm package). Every one of those must be added to `install.sh`'s `BREW_DEPS` or
  `NPM_DEPS` table *and* to `README.md` — otherwise a fresh machine gets a plugin that
  loads but silently does nothing. `./install.sh --check` verifies the tables match
  reality and exits non-zero if not. The `add-nvim-plugin` skill enforces this as a step.
  A `-` minimum in `BREW_DEPS` means presence-only, for tools with no version floor.
- **Language servers are the one exception: they live in mason, not `install.sh`.**
  `lua/plugin/lsp.lua`'s `ensure_installed` is the list; mason installs them into
  `~/.local/share/nvim/mason/`. `install.sh` guarantees only the *toolchains* mason shells
  out to (`curl`, `unzip`, `tar`, `gzip`), and `--check` deliberately says nothing about
  servers — so a green `--check` no longer implies a fully working editor. `:checkhealth
  mason` covers that half. The accepted cost is that mason has no lockfile, so server
  versions float where `lazy-lock.json` pins everything else; `ensure_installed` accepts
  per-server pinning (`"rust_analyzer@nightly"`) if that ever matters.
```

- [ ] **Step 8: Record the mason split in `README.md`**

Add a new subsection under `## External dependencies`, before
`### claude-agent-acp — required by lua/plugin/ai.lua`:

```markdown
### Language servers — managed by mason, not this script

`lua/plugin/lsp.lua` lists servers in `ensure_installed`, and
[mason](https://github.com/mason-org/mason.nvim) installs them into
`~/.local/share/nvim/mason/` on first start. Nothing to do by hand.

`install.sh` guarantees only the toolchains mason shells out to, so **`./install.sh
--check` says nothing about servers** — a green check does not imply a working language
server. Use `:checkhealth mason` for that, and `:Mason` (then `U`) to update them.

Unlike the rest of this config, server versions are **not pinned**: mason has no
lockfile, so a fresh machine gets whatever is current. That is a deliberate trade for
not maintaining a server list in two places.
```

- [ ] **Step 9: Commit**

```bash
git add lua/plugin/lsp.lua CLAUDE.md README.md lazy-lock.json
git commit -m "feat: add language server support via mason, starting with Lua

mason + mason-lspconfig + nvim-lspconfig, with automatic_enable doing the
vim.lsp.enable() call so no server is configured by hand. lazydev.nvim
makes lua_ls aware of the Neovim runtime -- nvim-lspconfig's lua_ls config
sets only codeLens and hint, so without it \`vim\` is an undefined global
in every file here.

Keymaps keep core's key names and only swap the UI: gd (which core leaves
unmapped) plus grr/gri/grt/gO now open the snacks picker instead of a
quickfix window, buffer-local on LspAttach.

Servers deliberately do not go in install.sh; CLAUDE.md's dependency rule
is amended to record the split and its cost."
```

---

### Task 4: Diagnostic presentation

**Files:**
- Create: `lua/plugin/diagnostic.lua`
- Modify: `lua/plugin/keybinding.lua:18-21` (which-key group spec)

**Interfaces:**
- Consumes: `require("snacks").picker` from `lua/plugin/ui.lua`. The attached client from
  Task 3 is what produces diagnostics to display.
- Produces: global mappings `<leader>dd` and `<leader>dw`.

**No `lazy-lock.json` change:** this task adds no new plugin. It contributes `keys` and an
`init` to the `folke/snacks.nvim` spec that `lua/plugin/ui.lua` already declares — lazy.nvim
merges specs for the same plugin across import files.

- [ ] **Step 1: Write the failing test**

```bash
nvim --headless \
  "+lua local c = vim.diagnostic.config()
        local leader_dd = false
        for _, m in ipairs(vim.api.nvim_get_keymap('n')) do if m.lhs == ' dd' then leader_dd = true end end
        print(('virtual_lines=%s severity_sort=%s leader_dd=%s'):format(vim.inspect(c.virtual_lines):gsub('%s+', ' '), tostring(c.severity_sort), tostring(leader_dd)))" \
  "+qa"
```

`' dd'` is `<leader>dd` with space as leader. lazy.nvim registers a stub mapping for every
`keys` entry at startup, so this is visible without snacks having loaded.

- [ ] **Step 2: Run it to verify it fails**

Expected now: `virtual_lines=false severity_sort=false leader_dd=false`

`virtual_lines=false` is the gap: a diagnostic currently shows as a squiggle and a gutter
sign with no readable message.

- [ ] **Step 3: Create `lua/plugin/diagnostic.lua`**

```lua
-- How diagnostics are presented, and how to list them.
--
-- Neovim 0.12 defaults to `signs = true` and `underline = true` but leaves BOTH
-- `virtual_text` and `virtual_lines` false -- so a diagnostic is a squiggle and a gutter
-- sign with no readable message unless you press `<C-w>d`. That is the gap here.
--
-- This returns a snacks.nvim spec. lazy.nvim merges specs for the same plugin across
-- import files, so it adds to the one in `lua/plugin/ui.lua` rather than competing with
-- it. The file is named for the concern rather than the plugin because the plugin is
-- incidental -- the presentation half is core `vim.diagnostic`, and it lives here rather
-- than in `lua/config/` only because the pickers below need snacks, which would make
-- `config/` depend on a plugin.
return {
	"folke/snacks.nvim",

	-- `init`, not `config`: this is core API that does not need snacks loaded, and the
	-- presentation should be settled before the first diagnostic is ever published.
	init = function()
		vim.diagnostic.config({
			-- Only on the line the cursor is on. Full `virtual_lines` shifts code down
			-- for every diagnostic on screen, and `virtual_text` truncates long messages
			-- and clutters. This shows the entire message exactly where you are looking,
			-- and nothing anywhere else.
			virtual_lines = { current_line = true, },

			-- So an error outranks a warning for the single sign the gutter can show.
			severity_sort = true,
		})
	end,

	-- Global rather than buffer-local on LspAttach: diagnostics are not client-scoped,
	-- they can come from any source, and snacks is loaded eagerly so the picker is
	-- always available.
	keys = {
		{
			"<leader>dd",
			function() require("snacks").picker.diagnostics_buffer() end,
			desc = "Diagnostics (buffer)",
		},
		{
			"<leader>dw",
			function() require("snacks").picker.diagnostics() end,
			desc = "Diagnostics (workspace)",
		},
	},
}
```

- [ ] **Step 4: Declare the which-key group**

In `lua/plugin/keybinding.lua`, add to the `spec` table so it reads:

```lua
		spec = {
			{ "<leader>a", group = "AI", },
			{ "<leader>d", group = "Diagnostics", },
			{ "<leader>g", group = "Git", },
		},
```

`<leader>d` is free: `a`, `g`, `s` and `?` are the taken prefixes.

- [ ] **Step 5: Run the test to verify it passes**

```bash
nvim --headless \
  "+lua local c = vim.diagnostic.config()
        local leader_dd = false
        for _, m in ipairs(vim.api.nvim_get_keymap('n')) do if m.lhs == ' dd' then leader_dd = true end end
        print(('virtual_lines=%s severity_sort=%s leader_dd=%s'):format(vim.inspect(c.virtual_lines):gsub('%s+', ' '), tostring(c.severity_sort), tostring(leader_dd)))" \
  "+qa"
```

Expected: `virtual_lines={ current_line = true } severity_sort=true leader_dd=true`

- [ ] **Step 6: Confirm snacks was merged, not duplicated**

If the merge failed, snacks would appear twice or `ui.lua`'s `vim.ui` overrides would be
lost:

```bash
nvim --headless "+lua local n = 0 for _, p in ipairs(require('lazy').plugins()) do if p.name == 'snacks.nvim' then n = n + 1 end end print(('snacks_specs=%d ui_select=%s'):format(n, tostring(vim.ui.select ~= nil)))" "+qa"
```

Expected: `snacks_specs=1 ui_select=true`

- [ ] **Step 7: Confirm a clean load**

```bash
nvim --headless "+qa"; echo "exit=$?"
nvim --headless "+checkhealth lazy" "+qa" 2>&1 | grep -iE 'ERROR'
```

Expected: exit 0, no stderr, no ERROR.

- [ ] **Step 8: Check the formatter agrees with the three new files**

Task 3 installed `lua-language-server`, which is the formatter `.editorconfig` drives. Now
it can check the files written before it existed. Open each and format:

```bash
nvim "+lua vim.lsp.buf.format()" lua/plugin/treesitter.lua
nvim "+lua vim.lsp.buf.format()" lua/plugin/lsp.lua
nvim "+lua vim.lsp.buf.format()" lua/plugin/diagnostic.lua
git diff --stat
```

Expected: no diff. If the formatter does reflow something — most likely field alignment or
the two-blank-lines-after-a-function rule — **keep the formatter's version** and commit it;
it is the source of truth per `CLAUDE.md`.

- [ ] **Step 9: Commit**

```bash
git add lua/plugin/diagnostic.lua lua/plugin/keybinding.lua
git commit -m "feat: show diagnostics on the current line, add diagnostic pickers

Neovim 0.12 leaves both virtual_text and virtual_lines off, so a
diagnostic was a squiggle with no readable message. virtual_lines with
current_line shows the full text only where the cursor is, without
permanently shifting code down the way full virtual_lines does.

<leader>dd and <leader>dw list buffer and workspace diagnostics. Returned
as a snacks.nvim spec so lazy.nvim merges it with lua/plugin/ui.lua's."
```

---

## Final verification

Run after all four tasks. Every line must pass:

```bash
nvim --headless "+qa"; echo "exit=$?"                    # expect exit=0, no stderr
./install.sh --check; echo "exit=$?"                     # expect exit=0
nvim --headless "+checkhealth vim.treesitter" "+qa" 2>&1 | grep -iE 'ERROR'
nvim --headless "+checkhealth vim.lsp" "+qa" 2>&1 | grep -iE 'ERROR'
nvim --headless "+checkhealth mason" "+qa" 2>&1 | grep -iE 'ERROR'
nvim --headless "+checkhealth lazy" "+qa" 2>&1 | grep -iE 'ERROR'
git status --short                                       # expect clean
```

Then the combined state assertion:

```bash
nvim --headless "+edit lua/config/vim.lua" \
  "+lua vim.wait(120000, function() return #vim.lsp.get_clients({ bufnr = 0 }) > 0 end)
        local b = vim.api.nvim_get_current_buf()
        print(('highlighter=%s foldmethod=%s clients=%d virtual_lines=%s'):format(
          tostring(vim.treesitter.highlighter.active[b] ~= nil),
          vim.wo.foldmethod,
          #vim.lsp.get_clients({ bufnr = 0 }),
          vim.inspect(vim.diagnostic.config().virtual_lines):gsub('%s+', ' ')))" \
  "+qa"
```

Expected: `highlighter=true foldmethod=expr clients=1 virtual_lines={ current_line = true }`

## Needs an interactive check — do not report these as passing

A clean headless load proves the config parses, not that it behaves. State plainly that
these require the user to look:

- **`vim` is no longer flagged as an undefined global.** This is lazydev's whole purpose,
  but asserting it headlessly means waiting on `lua_ls` to index and publish diagnostics —
  timing-dependent and flaky. Open `lua/plugin/lsp.lua` and look for the warning.
- **The `---@module` / `---@type` annotations in `colorscheme.lua` and `markdown.lua`
  resolve.** Same reason.
- **The current-line diagnostic renders and reads well.** Introduce a deliberate error
  (`local x = undefined_function()`), move the cursor onto the line, confirm the message
  unfolds beneath it and disappears when you move away.
- **Folding behaves.** `za` on a function in a Lua file; confirm it folds by structure
  rather than indentation, and that files open expanded rather than collapsed.
- **The five pickers work** — `gd`, `grr`, `gri`, `grt`, `gO` — and that `<leader>d` shows
  a "Diagnostics" group in which-key.

## Follow-up, out of scope here

Deferred deliberately. **Do not add any of these while implementing** — each was ruled out
in the design for a stated reason:

| Deferred | Reason |
|---|---|
| Completion (`blink.cmp` vs `vim.lsp.completion`) | Own decisions: engine, snippets, `<Tab>` conflicts |
| Formatting / format-on-save (`conform.nvim`) | `gq` already formats via LSP; non-LSP formatters are a separate concern |
| Tree-sitter `indentexpr` | Least mature part of tree-sitter, misbehaves on incomplete lines; `.editorconfig` already drives width |
| Tree-sitter text objects | A navigation feature, to be weighed against other motion plugins |
| Incremental selection | `main` dropped the module system that provided it |
| Diagnostic sign icons | Defaults kept; nerd-font availability unverified |

The language list is the next change: two edits — `languages` in `treesitter.lua`,
`ensure_installed` in `lsp.lua` — plus any new toolchain a server needs in `install.sh`
and `README.md`.
