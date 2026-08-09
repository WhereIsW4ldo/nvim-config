# Tree-sitter highlighting and LSP — design

**Date:** 2026-08-09
**Status:** approved, ready for implementation planning
**Target:** Neovim 0.12.4, Linux only

## Goal

Syntax highlighting driven by tree-sitter, and language-server support, for an explicit
list of languages. Lua is the first and only language in this change; the full list
follows in a later change and extends the same two lists.

## What is already true

Two findings from the existing setup shape the whole design.

**Lua already has tree-sitter highlighting.** `$VIMRUNTIME/ftplugin/lua.lua` calls
`vim.treesitter.start()` and sets `foldexpr`, and Neovim bundles parsers and queries for
`c`, `lua`, `markdown`, `markdown_inline`, `query`, `vim` and `vimdoc`. The gap this
change closes is every *other* language, which needs parsers and highlight queries
Neovim does not ship.

**Neovim 0.12 already provides most of the LSP surface.** Verified by dumping the
default keymaps and diagnostic config:

- Mapped by default: `grn` rename, `gra` code action, `grr` references, `gri`
  implementation, `grt` type definition, `grx` run codelens, `gO` document symbols,
  `<C-s>` signature help, `K` hover (on attach), `<C-]>` definition via `tagfunc`,
  `gq` format via `formatexpr`, `]d` / `[d` diagnostic motion.
- `vim.diagnostic.config()` defaults to `signs = true`, `underline = true`, but
  **`virtual_text = false` and `virtual_lines = false`** — so a diagnostic shows as a
  squiggle and a gutter sign with no readable message.

The consequence: this change writes far less than a typical LSP setup. It fills specific
gaps rather than rebuilding what core provides.

## Scope

**In:** tree-sitter parsers, highlighting, folding; mason-managed language servers;
diagnostic presentation; the keymap gaps; `lua_ls` configured correctly for this config.

**Out, each deferred to its own change:**

| Deferred | Why |
|---|---|
| Completion (`blink.cmp`, `vim.lsp.completion`) | Own decisions: engine, snippets, `<Tab>` conflicts |
| Formatting / format-on-save (`conform.nvim`) | `gq` already formats via LSP; non-LSP formatters are a separate concern |
| Tree-sitter text objects | A navigation feature, to be weighed against other motion plugins |
| Tree-sitter `indentexpr` | Least mature part of tree-sitter, misbehaves on incomplete lines; `.editorconfig` already drives width |
| Incremental selection | `main` dropped the module system that provided it |
| Windows support | Previously used, explicitly not a target now |

## Decisions

Each of these was chosen over named alternatives.

### Servers are managed by mason, not `install.sh`

`mason.nvim` installs servers into `~/.local/share/nvim/mason/`, listed as
`ensure_installed` in the plugin spec. Chosen over adding each server to `install.sh`'s
`BREW_DEPS` / `NPM_DEPS`.

**Accepted cost:** mason has no lockfile. Server versions float, and two machines on the
same `lazy-lock.json` commit can have different server versions. This is a deliberate
trade of reproducibility for convenience — updating is `:Mason` then `U`. If it ever
bites, `ensure_installed` accepts per-server pinning (`"rust_analyzer@nightly"`) without
adopting a lockfile.

**This departs from `CLAUDE.md`'s existing dependency rule**, so that rule is amended as
part of this change (see *Documentation* below). The new division:

- `install.sh` guarantees **toolchains** — the binaries mason shells out to.
- mason guarantees **servers**.
- `install.sh --check` never mentions a server. A green `--check` no longer implies a
  fully working editor; `:checkhealth mason` covers that half.

### Tree-sitter: `nvim-treesitter` on `main`, explicit parser list

`main` is the only viable branch: it requires Neovim 0.12.0+ (we have 0.12.4) and
`master` is frozen.

Upstream's stated requirements, verified from its README:

> `tree-sitter-cli` (0.26.1 or later, installed via your package manager, **not npm**) ·
> a C compiler in your path · `tar` and `curl` in your path

Parsers come from an explicit list, not auto-install-on-filetype. The list is the same
list the language additions will extend, it sits beside mason's `ensure_installed`, and
because parser revisions are pinned inside the `nvim-treesitter` commit, `lazy-lock.json`
reproduces them exactly. Auto-install would mean two machines on one commit having
different parsers.

**Note:** `main` has no compiler-selection option. The `compilers` setting that allowed
`zig` — the previous Windows workaround — was a `master` feature and does not exist here.

### Tree-sitter capabilities: highlighting and folding only

Folding is the one extra that is unambiguously reliable and costs two lines on top of
parsers already being installed. `indentexpr` and text objects are excluded (see *Scope*).

### Diagnostics: `virtual_lines` on the current line only

`virtual_lines = { current_line = true }` — silent until the cursor lands on the offending
line, then the full message unfolds beneath it. Chosen over `virtual_text` (truncates long
messages, clutters a screen with several errors), full `virtual_lines` (permanently shifts
code down), and the bare defaults (message invisible without `<C-w>d`).

`severity_sort = true` so an error outranks a warning in the sign column. Default signs
and underlines are kept.

### Keymaps: core's vocabulary, snacks' UI

`snacks.nvim`'s picker is already enabled in `lua/plugin/ui.lua`, and ships LSP sources.
The multi-result jumps keep their core key names but get a previewing fuzzy picker
instead of a quickfix window — so nothing learned here is config-specific.

### `lua_ls` runtime awareness: `lazydev.nvim`

Verified from `nvim-lspconfig`'s `lsp/lua_ls.lua`: it sets only `codeLens`, `hint` and
`hint.semicolon`. **It does not configure the Neovim runtime**, so out of the box
`lua_ls` flags `vim` as an undefined global in a config that is nothing but Neovim Lua.

`folke/lazydev.nvim` fills this: it adds the Neovim runtime *and* lazy.nvim plugin
sources to `lua_ls`'s library on demand, only when a file references them. Chosen over
hand-rolling `settings.workspace.library` from `nvim_get_runtime_file("", true)`, which
fixes `vim` but leaves the `---@module "catppuccin"` / `---@type CatppuccinOptions`
annotations already present in `colorscheme.lua` and `markdown.lua` unresolved — those
types live under `~/.local/share/nvim/lazy/`, off the runtime path — and which loads the
whole runtime eagerly.

lazydev works without a completion engine. The library injection is the point; its
completion source is a bonus collected in the completion change.

## Architecture

Three new files in `lua/plugin/`, each named for its concern and each under ~100 lines.

| File | Owns |
|---|---|
| `lua/plugin/treesitter.lua` | `nvim-treesitter` spec, parser list, highlighting, fold wiring |
| `lua/plugin/lsp.lua` | mason, mason-lspconfig, nvim-lspconfig, lazydev; `LspAttach` navigation keymaps |
| `lua/plugin/diagnostic.lua` | `vim.diagnostic.config()`, the `<leader>d` pickers |

Rejected: one combined `lsp.lua` (150–180 lines at this config's comment density, past the
~100-line signal in `CLAUDE.md`), and `lua/config/diagnostic.lua` (the `<leader>d` pickers
need snacks, which would make `config/` depend on a plugin — that directory's contract
forbids it).

`diagnostic.lua` returns a **`folke/snacks.nvim` spec** contributing only `keys` and an
`init`. lazy.nvim merges specs for the same repo across import files, so this coexists
with `ui.lua`'s snacks spec rather than replacing it.

### `lua/plugin/treesitter.lua`

`nvim-treesitter/nvim-treesitter`, `branch = "main"`, `lazy = false` — parsers must be
installable before the first file opens.

- A single local `languages` table drives both `require("nvim-treesitter").install(languages)`
  and the `pattern` of the `FileType` autocommand that starts highlighting. Adding a
  language is one edit in one place. Starts as `{ "lua" }`.
- `vim.treesitter.start()` is wrapped in `pcall`. `install()` is async, so on a cold
  machine a buffer can open before its parser has finished compiling, and an unwrapped
  `start()` throws an error on first launch.
- The same autocommand sets `foldmethod = "expr"` and
  `foldexpr = "v:lua.vim.treesitter.foldexpr()"` window-local-to-buffer (`vim.wo[0][0]`,
  as the runtime ftplugin does). Deliberately **not** global, so filetypes without a
  parser keep their normal fold behaviour.
- The autocommand is wrapped in a named augroup with `clear = true`, per `CLAUDE.md`.
- For Lua specifically the runtime ftplugin already sets `foldexpr` and starts the
  highlighter; this autocommand adds the missing `foldmethod` and generalises both to
  every other language.

### `lua/plugin/lsp.lua`

An array of four tightly-coupled specs, which `CLAUDE.md` permits for coupled plugins.

| Plugin | Repo | Requirements (verified) |
|---|---|---|
| mason | `mason-org/mason.nvim` | `nvim >= 0.10`; `git`, `curl`/`wget`, `unzip`, GNU `tar`, `gzip` |
| mason-lspconfig | `mason-org/mason-lspconfig.nvim` | `nvim >= 0.11`, `mason >= 2.0.0`, `nvim-lspconfig >= 2.0.0` |
| lspconfig | `neovim/nvim-lspconfig` | ships `lsp/<server>.lua` for `vim.lsp.enable()` |
| lazydev | `folke/lazydev.nvim` | `ft = "lua"` |

The owner is **`mason-org`**, not `williamboman` — mason moved orgs for v2.

- `ensure_installed = { "lua_ls" }`. These are **lspconfig** server names; translating
  them to mason package names is mason-lspconfig's job.
- `automatic_enable` defaults to `true`, so mason-lspconfig calls `vim.lsp.enable()` for
  every installed server. No per-server boilerplate is written.
- mason must load before mason-lspconfig; express this with `dependencies`, not ordering.

If this file exceeds ~100 lines, split lazydev out into `lua/plugin/lua.lua`.

### Keymaps

Buffer-local, set in an `LspAttach` autocommand, so core's global versions remain the
polite fallback in buffers with no client. Every mapping carries a `desc`.

| Key | Becomes | Replaces |
|---|---|---|
| `gd` | `Snacks.picker.lsp_definitions` | *unmapped* — only `<C-]>` existed |
| `grr` | `Snacks.picker.lsp_references` | quickfix window |
| `gri` | `Snacks.picker.lsp_implementations` | quickfix window |
| `grt` | `Snacks.picker.lsp_type_definitions` | quickfix window |
| `gO` | `Snacks.picker.lsp_symbols` | quickfix window |

Global, in `diagnostic.lua` — diagnostics are not client-scoped, and snacks is
`lazy = false` so the picker is always available:

| Key | Action |
|---|---|
| `<leader>dd` | Buffer diagnostics |
| `<leader>dw` | Workspace diagnostics |

Untouched core mappings: `grn`, `gra`, `grx`, `K`, `<C-s>`, `]d`, `[d`, `gq`.

### `lua/config/vim.lua`

Two globals, safe regardless of parser availability:

- `foldlevelstart = 99` — files open expanded. Without it, every file opens fully
  collapsed.
- `foldtext = ""` — 0.10+ renders the fold line with real syntax highlighting instead of
  grey `+--` filler.

### `lua/plugin/keybinding.lua`

`{ "<leader>d", group = "Diagnostics" }` joins the which-key spec. `<leader>d` is free:
`a`, `g`, `s` and `?` are the taken prefixes.

## Prerequisite: remove the stale parser directory

Leftover state from the pre-reset config, outside the repo and unmanaged by
`lazy-lock.json`. Newest file 2026-04-10, 58M total.

```
~/.local/share/nvim/site/parser/       37 .so files    ← delete
~/.local/share/nvim/site/parser-info/  37 .revision    ← delete (a master-branch artifact)
~/.local/share/nvim/site/queries/      40 language dirs ← delete
~/.local/share/nvim/site/pack/core/opt empty            ← KEEP: core's vim.pack directory
```

**This is a prerequisite, not housekeeping.** `nvim-treesitter` `main`'s default
`install_dir` is `stdpath("data") .. "/site"` — the same directory. New parsers would be
compiled in alongside four-month-old queries from `master`, and a mismatched
parser/query pair fails badly: the old queries reference node names that no longer exist.

A one-off manual step. `install.sh` must not do it — a provisioning script should not
delete user data.

## Dependencies

`install.sh` gains every external tool the new plugins need, strictly, per `CLAUDE.md`.
`git` is already in `BREW_DEPS`.

| Command | Minimum | Formula | Needed by |
|---|---|---|---|
| `tree-sitter` | 0.26.1 | `tree-sitter` | nvim-treesitter (**brew, not npm** — upstream is explicit) |
| `cc` | any | `gcc` | compiling parsers |
| `curl` | any | `curl` | mason downloads |
| `unzip` | any | `unzip` | mason archive extraction |
| `tar` | any | `gnu-tar` | mason archive extraction |
| `gzip` | any | `gzip` | mason archive extraction |

On this machine `tree-sitter 0.26.3` (from cargo) and `gcc 13.3.0` are already present,
so `install.sh`'s existing "do not shadow what is installed" logic finds both and skips.
Of the rest, only `unzip` is plausibly absent on a minimal Linux image.

`cc` and `tar` keep a nominal formula, and their brew path is knowingly imperfect: on
Linux `brew install gcc` provides `gcc-13` rather than `cc`, and `brew install gnu-tar`
provides `gtar` rather than `tar`, so if either were genuinely absent the script would die
with a slightly misleading message. Accepted rather than engineered around — on Linux
`tar` *is* GNU tar and both ship with the base system or the distro's build tools, so a
machine capable of running Neovim and compiling parsers already has them. The value of
these entries is that `--check` *reports* them on a new machine, which is the script's job.

### One required change to `install.sh`'s table format

**A `-` minimum means presence-only.** Five of the six new deps have no meaningful version
floor. When `min` is `-`, the loop skips the version probe and reports presence. Without
this, those entries need a fake `0` minimum and print `✓ unzip 0 (>= 0)`.

The existing four-field format `command|minimum|brew formula|probe` is otherwise unchanged.
**Do not add a fifth field after `probe`.** The loop reads

```sh
IFS='|' read -r cmd min formula probe <<<"$entry"
```

and the last variable absorbs the remainder *including* `|` characters, which is what lets
probes contain pipes. A fifth variable truncates every piped probe. Verified:

```
entry: git|2.19.0|git|git --version | awk '{print $3}'
4 vars → probe = [git --version | awk '{print $3}']              correct
5 vars → probe = [git --version ]  extra = [ awk '{print $3}']   broken
```

## Documentation

- **`README.md`** — the new dependencies under *External dependencies*, plus a note that
  language servers are managed by `:Mason` and are deliberately not covered by
  `install.sh --check`.
- **`CLAUDE.md`** — amend the dependency convention to record the mason split: toolchains
  in `install.sh`, servers in mason, `--check` silent on servers. Without this the repo
  documents a rule the code knowingly breaks.
- **`lazy-lock.json`** — committed with the change.

## Verification

Automated, and each must pass:

```sh
nvim --headless "+qa"                      # loads clean: no stderr, zero exit
nvim --headless "+checkhealth vim.treesitter" "+qa"
nvim --headless "+checkhealth vim.lsp" "+qa"
nvim --headless "+checkhealth mason" "+qa"
./install.sh --check                       # exits 0
```

Plus a scripted assertion, since loading cleanly is a weak signal — a spec can parse and
still do nothing. Open a real Lua file and assert:

- `vim.treesitter.highlighter.active[buf]` is non-nil — the highlighter is actually running
- `vim.lsp.get_clients({ bufnr = buf })` is non-empty — `lua_ls` attached
- `vim.wo.foldmethod == "expr"` and `foldexpr` is the tree-sitter one

**Requires an interactive check and will not be claimed as passing from headless runs:**

- That `vim` is no longer flagged as an undefined global. This is lazydev's whole job, but
  asserting it headlessly means waiting on `lua_ls` to index and publish diagnostics, which
  is timing-dependent and would make the check flaky. Verified by opening a config file and
  looking.
- That the current-line diagnostic message renders and reads well, that folding feels right,
  and that the five pickers behave.

## Follow-up

The language list is the next change. Adding a language is two edits — the `languages`
table in `treesitter.lua` and `ensure_installed` in `lsp.lua` — plus any toolchain the new
server needs, in `install.sh` and `README.md`.
