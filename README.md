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
| .NET SDK **10+** | The C# server (`roslyn_ls`) — see below | `dotnet --version` |
| A Rust toolchain (`cargo`) | `rust_analyzer` loads a workspace with `cargo metadata` | `rustup` or `brew install rust` |
| `curl`, `unzip`, `tar`, `gzip` | mason downloads and unpacks language servers | Present on any base Linux except sometimes `unzip` |

## External dependencies

Plugins that need something installed outside Neovim. lazy.nvim will **not** install
these — a missing one means the plugin loads but silently does nothing.

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

#### Which server, and why

| Language | Server | Chosen over |
|---|---|---|
| Terraform | `terraformls` | HashiCorp's own. `terraform_lsp` is the community alternative and is unmaintained. |
| C# | `roslyn_ls` | `omnisharp` (the Mono-era predecessor) and `csharp_ls` (community, lighter, less complete). This is the engine behind the VS Code C# extension. |
| Markdown | `marksman` | — |
| Vue + TypeScript | `vue_ls` + `vtsls` | `ts_ls`. Since Vue language server v3 there is no takeover mode, and both upstreams point at `vtsls`; lspconfig warns against enabling `ts_ls` alongside it. |
| Docker | `docker_language_server` | `dockerls` + `docker_compose_language_service`, which take two servers to cover the same ground. Docker's own binary also handles Bake. |
| SQL | `sqls` | `sqlls`, which is simply broken: sql-language-server 1.7.1 reaches into a `vscode-languageserver-protocol` subpath that modern Node blocks via `exports`, so it exits 1 on startup. |
| Rust | `rust_analyzer` | — |

Two of them need a toolchain `install.sh` now installs: **`dotnet`**, because
`roslyn_ls` is distributed as a NuGet package that mason installs by spawning `dotnet`,
and the server is a `net10.0` assembly; and **`cargo`**, because `rust_analyzer` shells
out to `cargo metadata` and knows nothing about a project without it.

Three gaps worth knowing about:

- **`sqls` says `no database connection` until you give it one.** It still parses, formats
  and completes keywords; table and column completion needs a connection in a `config.yml`.
- **Razor / `.cshtml` is not supported.** `roslyn_ls` reports the request and points at
  [roslyn.nvim](https://github.com/seblyng/roslyn.nvim), which is what you would add for it.
- **Compose files need a filetype Neovim does not detect.** `docker_language_server`
  attaches on `yaml.docker-compose`, so `lua/plugin/docker.lua` registers the patterns.
  A Compose file under a name neither `compose*.yaml` nor `docker-compose*.yaml` matches
  will open as plain `yaml` and get no server.

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

### `ripgrep` — required by `lua/plugin/explorer.lua`

`snacks.explorer` is a `snacks.picker` source, and the picker shells out for anything it
does not read off the filesystem itself.

```sh
brew install ripgrep               # or: sudo apt install ripgrep
```

Two paths use it, and they fail differently:

- **File finding degrades.** The finder tries `fd`, then `fdfind`, then `rg --files`,
  then plain `find`. Something always works; without `rg` or `fd` you lose gitignore
  awareness and speed, nothing more. `fd` is therefore *not* in `install.sh`.
- **Grep does not degrade.** `<leader>/` inside the explorer ("Grep in current
  directory") has `rg` hardcoded with no fallback, so a missing ripgrep makes that one
  action return nothing at all — no error, just an empty list.

### `gio` — recoverable deletes in the explorer, Linux only

`snacks.explorer` sends `d` to the system trash rather than unlinking. It probes `trash`
(trash-cli), then `gio`, then `kioclient5` / `kioclient`, and **if none of them is
executable it permanently deletes instead, without saying so.**

`gio` ships with glib and is already present on any modern Linux desktop, which is why
`install.sh` lists it as a conditional dependency rather than something you normally have
to install. On macOS the equivalent is trash-cli's `trash`; that platform is untested
here, so it is deliberately not listed.

To opt out of trash entirely and take the permanent delete on purpose, set
`explorer = { enabled = true, trash = false, }` in `lua/plugin/explorer.lua`.

## Statusline

`lua/plugin/statusline.lua` builds one **global** bar (`laststatus = 3`, set in
`lua/config/vim.lua`) out of `mini.statusline`:

```
 Normal   main ( M) 󰰎 +  init.lua  Claude 5h 47% (resets 1h09m) · 7d 5%  󰢱 lua utf-8[unix] 344B  1|12│1|1
```

`mini.nvim` is installed whole rather than the single-module `nvim-mini/mini.statusline`
mirror, because catppuccin's `auto_integrations` matches on the repo name and its map
contains `mini.nvim` — the mirror would go unthemed. Unused modules stay inert until their
own `setup()` runs, so the rest costs disk and nothing else. Three of them are set up:

- **`mini.statusline`** — the bar itself.
- **`mini.git`** — purely the data source for the branch section, which reads a
  buffer-local variable something else has to populate. It also registers a `:Git`
  command, but `lua/plugin/git.lua` remains the git porcelain.
- **`mini.icons`** — the provider `section_fileinfo` needs for its filetype icon. Without
  it that icon is silently absent, since a missing provider is not an error.

**Icons assume the terminal font carries the Nerd Font range.** They are worth about ten
columns over the `Git` / `Diag` / `LSP` word forms, and those columns matter: the Claude
section is the first thing truncation drops. Set `use_icons = false` in the spec to go
back to words.

One deliberate gap: **no diff counts.** `section_diff` needs `mini.diff`, which is not
merely a data source — it puts hunk marks in the sign column and binds hunk motions. That
is a gutter decision, not a statusline one.

Adding a plugin catppuccin knows about does **not** invalidate its compiled theme cache, so
new highlight groups keep their fallback colours until `:Catppuccin compile` is run or
`~/.cache/nvim/catppuccin` is deleted. Worth doing as the last step of any plugin change.

### The Claude plan-usage segment

`lua/config/claude-segment.lua` renders the right-aligned readout, returning
`text, highlight_group` — the same shape `MiniStatusline.section_*` uses, so the bar drops
it into a group list. It depends on no plugin, which is what lets it live in `config/`.
It dims below 70%, turns `DiagnosticWarn` at 70 and `DiagnosticError` at 90, and is the
first section dropped when the window narrows past 120 columns.

`lua/config/claude-usage.lua` supplies the numbers, from two sources, cheapest first:

1. **`~/.claude.json`'s `cachedUsageUtilization`** — what the CLI persists after its own
   fetches. Free, needs no token, available immediately at startup. But it goes stale: the
   CLI will not rewrite it more often than every 5 minutes, treats it as valid for a full
   hour, and an ACP-only session may not refresh it at all.
2. **`GET https://api.anthropic.com/api/oauth/usage`** — the endpoint the CLI's own
   `fetchUtilization` calls, authenticated with the OAuth token in
   `~/.claude/.credentials.json` (handed to `curl` over stdin via `--config -`, so it never
   appears in the process list).

The cache is adopted whenever it is ahead of what we hold, and a request is only spent when
the cache has not kept up — so no request at all while something else keeps it warm, and
otherwise a 5-minute cadence to start with, matching the CLI's own throttle.

**This endpoint is rate-limited: polling it every minute earns an HTTP 429.** It advertises
no budget, though — a 200 carries no `Retry-After` and no `anthropic-ratelimit-*` header —
so 5 minutes is an educated starting point, not a known-safe rate. Rather than trusting it,
the cadence is self-tuning: **every 429 doubles the interval for the rest of the session and
it never drops back**, up to an hour. Spring-back would just earn another 429 next cycle.
Ordinary failures — a dropped connection, an expired token — delay the next attempt without
touching the cadence, since they say nothing about the rate. `:ClaudeUsage` clears the delay
for an immediate retry and reports the interval in force.

A failed refresh never discards the last good reading — it appends `!` and dims, so a
transient 429 shows slightly old percentages rather than blanking the line. Any reading
older than 15 minutes is dimmed whatever it says.

The obvious route does not work: those percentages reach a **terminal** statusline through
the CLI's stdin payload (`rate_limits.five_hour.used_percentage`) and through nothing else.
Hook payloads carry only `session_id`, `transcript_path`, `cwd`, `prompt_id`,
`permission_mode`, `agent_id`, `agent_type` and `effort`. Sessions here run over ACP, which
never renders a statusline, so there is no payload to read.

Two things to know:

- **The endpoint is internal.** The CLI's own schema for it carries the note *"the response
  shape may change"*. When the readout goes blank or wrong, `:ClaudeUsageDebug` opens the
  raw JSON in a scratch buffer; `:ClaudeUsage` forces a refresh and echoes the parsed state.
  The response also contains codenamed windows (`tangelo`, `nimbus_quill`, …) that this
  config deliberately ignores.
- **Neovim never renews the token.** That is the refresh-token flow, and it belongs to the
  CLI. An expired token shows as `Claude HTTP 401` — or as the previous reading plus `!` —
  until the CLI renews it on its own next request.

Needs `curl`, which `install.sh` already installs.

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
