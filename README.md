# nvim-config

Personal Neovim configuration. Lua, modular, managed by
[lazy.nvim](https://github.com/folke/lazy.nvim).

See [CLAUDE.md](CLAUDE.md) for the layout, conventions, and code style.

## Requirements

| Requirement | Why | Notes |
|---|---|---|
| Neovim **0.12+** | Config targets modern APIs (`vim.lsp.config`, `vim.hl`, built-in EditorConfig) | `nvim --version` |
| Git **2.19+** | lazy.nvim uses partial clones (`--filter=blob:none`) | |
| Node **22+** | Needed by the ACP provider below | |
| lazygit **0.40+** | `lua/plugin/git.lua` wraps the lazygit TUI | 0.40.0 added the Worktrees panel |
| tree-sitter CLI **0.26.1+** | `nvim-treesitter` compiles parsers locally | From a package manager, **not npm** — upstream is explicit |
| A C compiler (`cc`) | Compiling those parsers | Debian/Ubuntu: `apt install build-essential` |
| `curl`, `unzip`, `tar`, `gzip` | mason downloads and unpacks language servers | Present on any base Linux except sometimes `unzip` |

## External dependencies

Plugins that need something installed outside Neovim. lazy.nvim will **not** install
these — a missing one means the plugin loads but silently does nothing.

### `claude-agent-acp` — required by `lua/plugin/ai.lua`

[agentic.nvim](https://github.com/carlos-algms/agentic.nvim) talks to Claude Code over
the Agent Client Protocol and deliberately does not manage provider binaries itself.

```sh
npm i -g @agentclientprotocol/claude-agent-acp
```

Needs `sudo` if your npm prefix is root-owned (check with `npm root -g`). Pinning the
version is recommended given [npm supply-chain
attacks](https://www.wiz.io/blog/shai-hulud-2-0-ongoing-supply-chain-attack):

```sh
npm i -g @agentclientprotocol/claude-agent-acp@0.66.0
```

Notes:

- Upstream recommends `pnpm` because nvm/fnm keep **per-Node-version** global
  directories, so `npm i -g` packages disappear when you switch versions. Irrelevant if
  your globals live in a shared prefix (e.g. under `n`) — plain `npm` is fine there.
- Upstream also offers a "download binary" option, but the releases carry **no binary
  assets** (checked through v0.66.0), so the npm registry is the only working route.
- Authentication reuses your existing `claude /login` session. No `ANTHROPIC_API_KEY`.

Verify:

```sh
command -v claude-agent-acp && claude-agent-acp --version
```

### `wl-clipboard` — clipboard image paste, Wayland only

agentic.nvim's image paste (`<C-v>` in insert mode, `<localleader>p` in normal) shells
out to `wl-paste`. Without it, image paste is the only thing that stops working.

```sh
brew install wl-clipboard          # or: sudo apt install wl-clipboard
```

`install.sh` handles this conditionally — it is only required on a **Linux Wayland**
session (`$WAYLAND_DISPLAY` set). An X11 session wants `xclip`/`xsel` instead, and
macOS uses the built-in `pbpaste`, so both skip it.

The distro package is lighter: Homebrew's `wl-clipboard` pulls in its own `wayland` and
`wayland-protocols`, whereas the distro one reuses system libraries. `install.sh` uses
brew only to keep itself to a single package manager.

## Terminal key support

One keybinding needs a terminal that implements the **kitty keyboard protocol**:
`<C-CR>` submits the agentic prompt, and legacy terminals cannot encode it — `Ctrl+Enter`
sends the same `0x0D` byte as plain `Enter`.

Ghostty, Kitty, WezTerm and foot support the protocol; Neovim 0.12 negotiates it
automatically. To check, press `Ctrl-V` then `Ctrl+Enter` in insert mode — a distinct
code means it works, a plain `^M` means it does not. Fall back to `<C-s>` if so.

## Install

```sh
git clone git@github.com:WhereIsW4ldo/nvim-config.git ~/.config/nvim
cd ~/.config/nvim
./install.sh
```

`install.sh` installs Homebrew if absent, then everything in the table above. It is
idempotent and **leaves alone anything that already meets the minimum version** — it
will not shadow a system `git` or a version-manager-provided `node` with a Homebrew
copy. To audit without changing anything:

```sh
./install.sh --check    # exits non-zero and names whatever is missing
```

lazy.nvim then bootstraps itself on first launch and installs plugins from
`lazy-lock.json`. Manage them with `:Lazy`.

## Platform support

Linux is the supported target. macOS is structurally handled in `install.sh` (Homebrew
prefix detection for both Apple silicon and Intel) but **untested** — it will warn and
proceed. Other platforms are refused outright.

## Verifying a change

```sh
nvim --headless "+qa"; echo "exit=$?"                            # loads clean
nvim --headless "+lua print(#require('lazy').plugins())" "+qa"   # specs registered
nvim --headless "+checkhealth lazy" "+qa"
```

A clean headless load proves the config **parses** — not that a keymap, colorscheme, or
notification behaves. Check those interactively.
