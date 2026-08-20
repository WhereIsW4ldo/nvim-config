# nvim-config

Personal Neovim configuration. Lua, modular, managed by
[lazy.nvim](https://github.com/folke/lazy.nvim).

See [CLAUDE.md](CLAUDE.md) for the layout, conventions, and code style.

## Requirements

| Requirement | Why | Notes |
|---|---|---|
| Neovim **0.12+** | Config targets modern APIs (`vim.lsp.config`, `vim.hl`, built-in EditorConfig) | `nvim --version` |
| Git **2.19+** | lazy.nvim uses partial clones (`--filter=blob:none`) | |
| Node **22+** | The global npm packages below, and the Claude Code CLI on a fresh machine | |
| lazygit **0.40+** | `lua/plugin/git.lua` wraps the lazygit TUI | 0.40.0 added the Worktrees panel |
| tree-sitter CLI **0.26.1+** | `nvim-treesitter` compiles parsers locally | From a package manager, **not npm** — upstream is explicit |
| A C compiler (`cc`) | Compiling those parsers | Debian/Ubuntu: `apt install build-essential` |
| .NET SDK **10+** | The C# server (`roslyn_ls`) — see below | `dotnet --version` |
| A Rust toolchain (`cargo`) | `rust_analyzer` loads a workspace with `cargo metadata` | `rustup` or `brew install rust` |
| `curl`, `unzip`, `tar`, `gzip` | mason downloads and unpacks language servers; `curl` + `git` also fetch `blink.cmp`'s prebuilt fuzzy matcher | Present on any base Linux except sometimes `unzip` |

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
| Rust | `rust_analyzer` | — |

Three of them need a toolchain `install.sh` now installs: **`dotnet`**, because
`roslyn_ls` is distributed as a NuGet package that mason installs by spawning `dotnet`,
and the server is a `net10.0` assembly; **`cargo`**, because `rust_analyzer` shells
out to `cargo metadata` and knows nothing about a project without it; and
**`terraform`**, because HCL formatting goes through the CLI rather than the server — see
below.

One of them needs a setting, in `lua/plugin/terraform.lua`:

- **`terraformls` indexes `.terraform/modules` and starves itself doing it.** After a
  `terraform init` the workspace root contains a vendored copy of every module the
  configuration pulls in — ~20k `.tf` files in this machine's work repos — and the server
  handles RPC serially, so indexing jobs queue in front of every real request. Measured
  against `Communication-Product/product`, `textDocument/references` took **4279ms** once
  settled and `textDocument/codeLens` never answered at all, timing out at 30s on every
  buffer enter. `init_options.indexing.ignorePaths = { ".terraform" }` brings those to
  **152ms** and **895ms**. Resource attribute completion, resource type completion, hover
  and document symbols are unchanged — provider schemas do not come from the module walker,
  and `.terraform/providers` is 1.4 GB of that 1.5 GB directory. Reach for the setting again
  if you need completion for the inputs of a *registry*-sourced remote module, which is the
  one thing it can cost. Note that `indexing.ignoreDirectoryNames` is not the knob despite
  the name: it rejects `.terraform` outright (error -32098) and the server fails to start.

**SQL deliberately has no language server.** `sqls` was installed here and has been
retired — it earned its place on nothing measurable. Probed against a live buffer it
returned **one** completion item (`SELECT`, on a bare `SEL`) and **zero** at column
positions inside a real query, because everything beyond keywords needs a database
connection it could never open for Azure: it links the deprecated `denisenkom/go-mssqldb`,
which has no Entra token path. It also contributed no diagnostics — every one of them comes
from `sqlfluff`. What it did do was format, with tabs, against `sqlfluff`'s indentation
rule, so every formatted buffer came back with four fresh `LT02` warnings. Formatting now
goes to `sqlfluff` itself (see `lua/plugin/format.lua`), so the tool that formats and the
tool that judges are the same one and cannot disagree by construction. `sqlls` was never an option:
sql-language-server 1.7.1 reaches into a `vscode-languageserver-protocol` subpath that
modern Node blocks via `exports`, so it exits 1 on startup.

Schema-aware SQL completion is not lost with it — it comes from `vim-dadbod-completion`,
and unlike `sqls` it covers the Azure connection too. See below.

Two more gaps worth knowing about:

- **Razor / `.cshtml` is not supported.** `roslyn_ls` reports the request and points at
  [roslyn.nvim](https://github.com/seblyng/roslyn.nvim), which is what you would add for it.
- **Compose files need a filetype Neovim does not detect.** `docker_language_server`
  attaches on `yaml.docker-compose`, so `lua/plugin/docker.lua` registers the patterns.
  A Compose file under a name neither `compose*.yaml` nor `docker-compose*.yaml` matches
  will open as plain `yaml` and get no server.

### `prettierd` — required by `lua/plugin/format.lua`

[conform.nvim](https://github.com/stevearc/conform.nvim) runs a CLI formatter only where
one beats the language server. That is prettier, for markdown (`marksman` implements no
formatting at all) and for the Vue/TypeScript family plus the JSON/YAML/CSS files around
them (`vtsls` formats with tsserver's formatter, which is not prettier's style and ignores
a project's `.prettierrc`). Terraform is a separate case, on latency rather than style —
see below. Everything else — Lua, C#, Rust, SQL, Dockerfiles — falls through to its server
and needs nothing here.

```sh
npm i -g @fsouza/prettierd@0.29.0
```

`prettierd` is prettier behind a daemon, so it pays its startup cost once per session
rather than once per save. It bundles its own prettier as a dependency, so this single
package covers every filetype above.

Without it, those filetypes fall back to plain `prettier` — resolved from
`node_modules/.bin` first, so a project that depends on prettier still formats. With
neither, conform warns **once per filetype per session** rather than failing silently,
which is the one place in this config a missing dependency announces itself.

Verify:

```sh
command -v prettierd && prettierd --version
```

`:ConformInfo` is the in-editor version: it lists which formatters resolved for the
current buffer and where the log file is.

### `terraform` — HCL formatting, required by `lua/plugin/format.lua`

conform calls it directly, as `terraform fmt -no-color -`, for `terraform` and
`terraform-vars` buffers. It is not on the LSP-fallback path: `terraformls` does not format
HCL itself — its `textDocument/formatting` handler builds a `TerraformExecutor` and runs
this same binary through it — but it handles RPC serially while indexing every module under
the workspace root, `.terraform/modules` included. Against a repo whose module cache is
~20k `.tf` files, the queue reaches 600+ entries and single requests take up to 9s, so
format-on-save timed out and reported `[LSP][terraformls] timeout` on every write. Calling
the CLI takes ~30ms and does not queue. Without this binary, HCL does not format at all.

Note that `indexing.ignoreDirectoryNames` is not a way to shrink that index:
`terraform-ls` rejects `.terraform` by name (`cannot ignore directory ".terraform"`, error
-32098) and fails to initialise, so the completion and hover latency is a fixed cost of
pointing the server at a large initialised workspace.

**Not a Homebrew core formula** — core dropped `terraform` after HashiCorp's BUSL
relicense, so `install.sh` uses the official tap and `brew install` taps it on demand:

```sh
brew install hashicorp/tap/terraform
```

`opentofu` *is* in Homebrew core and is the usual substitute, but not here:
`terraform-ls` execs `terraform` by name. An OpenTofu setup wants `tofu-ls` instead,
which would be a change to `ensure_installed` in `lua/plugin/lsp.lua`, not a swap here.

### Linters — required by `lua/plugin/lint.lua`

[nvim-lint](https://github.com/mfussenegger/nvim-lint) spawns these by name, parses their
output and reports it through `vim.diagnostic`. It installs none of them, and one that is
not installed is **skipped silently** on save — so an unlinted buffer looks exactly like a
clean one. `./install.sh --check` is the place that difference is visible; pressing
`<leader>l` is the other, since the manual keymap deliberately keeps the error.

(The silence is on purpose. Upstream reports a missing binary through plain `vim.notify`
rather than `notify_once`, so without the filter in `lua/plugin/lint.lua` a linter you have
not installed would raise an error on *every* save and every `InsertLeave` for the rest of
the session.)

The premise is that a language server is not a linter: `lua_ls` type-checks but never
mentions an unused local, `vtsls` knows every type and nothing about the project's ESLint
rules, `marksman` resolves Markdown links and holds no opinion on heading style.

| Filetype | Linter | What it adds over the language server |
|---|---|---|
| `lua` | `luacheck` | Unused locals, shadowing, global leaks — none of which `lua_ls` reports. |
| `terraform` | `tflint` | Provider-specific and best-practice rules; `terraformls` only validates. |
| `markdown` | `markdownlint-cli2` | Heading/list/formatting style. `marksman` is links and references only. |
| `dockerfile` | `hadolint` | Pinned base tags, `apt-get upgrade`, shell-form pitfalls. |
| `sql` | `sqlfluff` | Dialect-aware style rules. Also the formatter now that `sqls` is gone — see above. |
| `sh` | `shellcheck` | Everything — this is the one filetype here with **no** language server at all. |
| `vue`, `typescript`, `typescriptreact`, `javascript`, `javascriptreact` | `eslint_d` | The project's own rules and plugin rules (`eslint-plugin-vue`), which `vtsls` and `vue_ls` never see. |

**C# and Rust are deliberately absent.** `roslyn_ls` *is* Roslyn, the same engine the
standalone C# analysers call, and `clippy` is a `rust_analyzer` setting rather than a
second process worth spawning beside it. Adding either would duplicate work the server
already does.

Four come from Homebrew — `tflint`, like `terraform` above, is **not a core formula** (core
has no `tflint` at all), so it is tap-qualified and `brew install` taps it on demand:

```sh
brew install luacheck hadolint sqlfluff shellcheck
brew install terraform-linters/tap/tflint
```

The two Node-based linters come from npm instead, and that split is deliberate: both have
Homebrew formulae, but each declares a dependency on `node`, so installing them that way
pulls a **second Node** in beside the Node 22 this config already requires. npm also lets
them be pinned, which the `brew install` above does not.

```sh
npm i -g eslint_d@15.0.3 markdownlint-cli2@0.23.2
```

#### Three things that will bite

- **`sqlfluff` lints nothing until it has a dialect.** It defaults `dialect` to `None` and
  then requires it, so every SQL buffer fails outright until one is set. Do *not* put
  `--dialect` in the plugin spec — a CLI flag would override every project's own
  `.sqlfluff`. It belongs in config, where the *nearest* file wins.

  This machine is set up two-tier, since the usual dialect is SQL Server and personal
  projects are Postgres. The machine-wide default lives **outside this repo**, at
  `~/.config/sqlfluff/.sqlfluff`:

  ```ini
  [sqlfluff]
  dialect = tsql
  ```

  A Postgres project then overrides it with its own `.sqlfluff` in the repo root:

  ```ini
  [sqlfluff]
  dialect = postgres
  ```

  Mind the identifiers: they are **`tsql`** and **`postgres`**. `mssql` and `postgresql`
  are not sqlfluff dialects and will error. `sqlfluff dialects` lists all of them.

  The same file also sets the indent width, non-default at **two** spaces where sqlfluff
  ships four:

  ```ini
  [sqlfluff:indentation]
  tab_space_size = 2
  ```

  This is not only a lint setting. Since `sqlfluff fix` is what conform runs to *format*
  SQL, it governs the formatter too — which is the point of having retired `sqls`.

  Because it is both linter and formatter, one wrinkle needs handling in
  `lua/plugin/format.lua`: `sqlfluff fix` **exits 1 whenever any unfixable violation
  remains**, and conform discards a formatter's output on a non-zero exit. The rule that
  trips it constantly is `AM04` — *"query produces an unknown number of result columns"* —
  which fires on `SELECT *` and is unfixable by definition. So the formatter is configured
  with `exit_codes = { 0, 1 }`. That is safe rather than merely convenient: sqlfluff sends
  every diagnostic to stderr and puts only SQL on stdout — reformatted where it could fix
  something, and the input unchanged where the buffer does not parse at all.

  If the `AM04` *diagnostic* is also unwanted — it is noise for ad-hoc querying, where
  `SELECT *` is the point — exclude it machine-wide:

  ```ini
  [sqlfluff]
  exclude_rules = AM04
  ```

- **Lint-only filetypes need the inline renderer told to attach.**
  `tiny-inline-diagnostic.nvim` defaults to attaching on `LspAttach` alone, which silently
  means "only buffers with a language server". `sql` (since `sqls` was retired) and `sh`
  (which never had one) get their diagnostics from nvim-lint instead, so the plugin never
  attached and both showed a gutter sign whose message could not be read anywhere — moving
  onto the line did nothing. `lua/plugin/diagnostic.lua` sets
  `overwrite_events = { "LspAttach", "BufEnter" }` to fix it. `BufEnter` and not
  `BufReadPost`, because that has already fired for the file named on the command line by
  the time the plugin loads on `VeryLazy`.

- **`tflint` does not read the buffer.** Upstream's definition passes `--recursive` with
  `stdin = false`, so it lints the directory *as it is on disk*. Unsaved changes are
  invisible to it, and its diagnostics can name files other than the one you are in.

- **`eslint_d` only lints projects that have their own ESLint, by design.** It stores its
  daemon token beside whichever eslint it resolves. With a project-local
  `node_modules/eslint` that directory is writable and everything works. With none, it
  falls back to the copy bundled in the **root-owned** global npm prefix, cannot write
  there, and dies with `Timed out waiting for config` — on *stderr*, which nvim-lint does
  not read, and with an exit code it ignores. The result would be a TypeScript buffer that
  looks linted and clean when nothing ran.

  `lua/plugin/lint.lua` therefore sets `ESLINT_D_MISS=ignore`, which turns that case into
  a clean no-op. Nothing is lost — the bundled eslint cannot resolve a project's own
  plugins (`eslint-plugin-vue`) either way, so its verdict would be wrong rather than
  absent. It is the same project-local-or-nothing rule `format.lua` applies to prettier.

  It also means the linting you get is **the repo's own ESLint, running the repo's own
  config** — which is the point, and is also arbitrary code from a repository you just
  opened. Upstream is explicit: do not lint an untrusted repository. A `wrap_linter`
  sandbox recipe (`systemd-run`, bubblewrap) is documented for when that matters.

`.luacheckrc` in the repo root exists for the same reason: without it luacheck reports
`accessing undefined variable vim` on nearly every line of this config. It sets
`std = "luajit"` (what Neovim embeds) and declares `vim` as a writable global, since the
config assigns through it.

Verify:

```sh
./install.sh --check          # names any linter that is missing
```

`<leader>l` re-runs the linters for the current buffer, which is the quickest way to
confirm a freshly installed one is now being found.

### `sqlcmd` and `az` — required by `lua/plugin/database.lua`

[vim-dadbod](https://github.com/tpope/vim-dadbod) has no SQL Server driver of its own: its
adapter builds an argv and shells out to `sqlcmd` for every query, and again for the schema
introspection that feeds completion. Without it the drawer opens, connects to nothing, and
reports a command-not-found.

```sh
brew install sqlcmd azure-cli
```

**It has to be [`microsoft/go-sqlcmd`](https://github.com/microsoft/go-sqlcmd), the Go
rewrite — not the legacy ODBC `sqlcmd` from `mssql-tools`/`mssql-tools18`, which carries the
same command name.** Only the rewrite implements `--authentication-method`, and that one
flag is the whole reason this stack was chosen: it is what lets an Azure SQL connection
authenticate as you without a password.

The two connection shapes, added with `:DBUIAddConnection`:

```
sqlserver://sa:PASSWORD@localhost:1433/DB?trustServerCertificate=true
sqlserver://SERVER.database.windows.net/DB?authentication=ActiveDirectoryAzCli&encrypt=true
```

`trustServerCertificate=true` becomes `-C` and is not optional for a Docker instance —
go-sqlcmd negotiates encryption by default and the container's certificate is self-signed.
`authentication=ActiveDirectoryAzCli` is passed straight through to `--authentication-method`,
which resolves to `azidentity.NewAzureCLICredential` and spawns `az account get-access-token`.
That is why **`az` is a dependency too, and why `az login` has to be current** — the token is
fetched per connection and never stored. Neither URL is committed: `:DBUIAddConnection` writes
to `~/.local/share/db_ui`, outside this repository.

Verify:

```sh
sqlcmd --version     # must print v1.x — the legacy binary has no --version flag at all
az account show      # must succeed, or the Azure connection cannot authenticate
```

`:DBUILastQueryInfo` is the in-editor version: it prints the exact command that was run.

#### Result formatting, and a script that runs before every query

dadbod builds a fixed argv and passes `sqlcmd` no formatting flags, with no hook to add
any. It does not need one: go-sqlcmd reads its scripting variables from the environment
(`InitializeVariables(args.useEnvVars())`, true unless `-X` is passed, which dadbod never
does), so `lua/plugin/database.lua` sets them with `vim.env` and needs neither a `$PATH`
wrapper script nor a `g:db_adapter_sqlserver` override — the two answers the upstream
issue threads settle on.

| Variable | Set to | Default | Why |
|---|---|---|---|
| `SQLCMDMAXFIXEDTYPEWIDTH` | `30` | `0` (unlimited) | The one that matters. Governs **declared-width** types — `char(n)`, `varchar(n)`, `nvarchar(n)` — which are otherwise padded to their declared width, so a `varchar(255)` column is 255 characters wide even when no row is. |
| `SQLCMDMAXVARTYPEWIDTH` | `100` | `256` | The one whose name suggests it, and the lesser half: only the `(max)` types plus `xml`/`text`/`image`. |
| `SQLCMDINI` | `sql/preamble.sql` | unset | A script run before every query. |

`sql/preamble.sql` is in this repository, tracked, and ships commented out. Uncomment what
you want — `SET NOCOUNT ON;` to drop the `(N rows affected)` lines, or the isolation-level
and lock-timeout pair for exploring a production database without blocking anyone. Two
rules apply: it runs before **every** `sqlcmd` invocation, including the schema
introspection behind completion, and it must therefore produce **no output** — a stray
`PRINT` corrupts the table list rather than merely looking untidy.

Note `vim.env` is Neovim's whole environment, so a `sqlcmd` run by hand in the built-in
terminal inherits all three too.

Vertical (one column per line) output is **not** available: `<Plug>(DBUI_ToggleResultLayout)`
is Postgres/MySQL/BigQuery only — `autoload/db_ui/schemas.vim` gives those a `layout_flag`
and gives SQL Server none.

### `claude` — required by `lua/plugin/ai.lua`

[claudecode.nvim](https://github.com/coder/claudecode.nvim) is pure Lua and installs
nothing itself. It stands up a WebSocket server, writes `~/.claude/ide/<port>.lock`, and
launches the Claude Code CLI pointed at it — the same discovery handshake Anthropic's own
VS Code and JetBrains extensions use. The CLI is therefore the *only* external dependency,
and without it `:ClaudeCode` opens a terminal that immediately exits.

Two install routes, both fine:

```sh
curl -fsSL https://claude.ai/install.sh | bash    # Anthropic's native installer -> ~/.local/bin
npm i -g @anthropic-ai/claude-code@2.1.231        # what install.sh uses
```

`install.sh` takes the npm route because Homebrew ships `claude-code` as a **cask**, and
casks are macOS-only — `brew install claude-code` fails outright on Linux. It skips the
entry entirely when `claude` is already on `PATH`, so an existing install of either shape
is left alone rather than shadowed. The pinned version is a floor for a fresh machine, not
a ceiling: Claude Code updates itself after first run, so that number goes stale by design.

Notes:

- Authentication reuses your existing `claude /login` session. No `ANTHROPIC_API_KEY`.
- If you have run `claude migrate-installer`, the binary moves to `~/.claude/local/claude`
  and is reached through a shell alias that Neovim does not see. Set
  `terminal_cmd = "~/.claude/local/claude"` in `lua/plugin/ai.lua`'s `opts` if so.
  `claude doctor` reports which installation you have.

Verify:

```sh
command -v claude && claude --version
```

`:ClaudeCodeStatus` is the in-editor version — it reports whether the WebSocket server is
up and whether a CLI has connected to it.

#### Why not ACP

This replaced [agentic.nvim](https://github.com/carlos-algms/agentic.nvim), which drove the
same CLI over the **Agent Client Protocol**, through the
`@agentclientprotocol/claude-agent-acp` npm bridge. ACP is vendor-neutral, so it carries
roughly the intersection of what every agent does rather than everything Claude Code does,
and the bridge lags each CLI release.
agentic's own tracker shows the shape of it: restored sessions losing their mode and model
([#310](https://github.com/carlos-algms/agentic.nvim/issues/310)), and no way to surface
Claude Code's `AskUserQuestion` because ACP does not model it
([#274](https://github.com/carlos-algms/agentic.nvim/issues/274)).

Here the real CLI runs in the terminal, so there is nothing to fall behind on — mode
cycling, `/model`, skills and whatever ships next all work because none of it is
reimplemented. The npm bridge is gone rather than replaced.

What that costs, since all three were configured deliberately before:

- **One session at a time.** agentic ran several concurrently and kept them alive behind a
  closed window. `<leader>ar` picks a *different* session rather than adding one. Tracked
  upstream but unimplemented ([#187](https://github.com/coder/claudecode.nvim/issues/187),
  [#177](https://github.com/coder/claudecode.nvim/issues/177),
  [#147](https://github.com/coder/claudecode.nvim/issues/147)).
- **No Neovim-native chat buffer,** so no foldable tool calls — the CLI renders its own
  output. Diffs are the exception: those come over the protocol and open as real Neovim
  windows, accepted with `:w` and rejected with `:q`.
- **Model switching is launch-time.** `<leader>am` restarts the CLI with `--model`;
  `/model` inside the terminal is the live route.

Diagnostics are no longer pushed either, which is a change of direction rather than a loss:
Claude pulls them itself through the MCP `getDiagnostics` tool whenever it wants them.

### `wl-clipboard` — the system clipboard, Wayland only

Not a plugin dependency — an editor one. `lua/config/vim.lua` sets
`clipboard = "unnamedplus"`, so every yank and put goes through the `+` register, and on a
Wayland session `wl-copy`/`wl-paste` is the first provider Neovim looks for. Without it
Neovim falls back to the X11 tools (`xclip`, `xsel`) via XWayland if they happen to be
installed, and to nothing at all if they are not — in which case yanking silently does not
reach any other application. `:checkhealth provider` reports which one was picked.

(It was previously listed for agentic.nvim's image paste, which shelled out to `wl-paste`
directly. That plugin is gone; the clipboard reason is the one that was always underneath.)

```sh
brew install wl-clipboard          # or: sudo apt install wl-clipboard
```

`install.sh` handles this conditionally — it is only required on a **Linux Wayland**
session (`$WAYLAND_DISPLAY` set). An X11 session wants `xclip`/`xsel` instead, and
macOS uses the built-in `pbpaste`, so both skip it.

The distro package is lighter: Homebrew's `wl-clipboard` pulls in its own `wayland` and
`wayland-protocols`, whereas the distro one reuses system libraries. `install.sh` uses
brew only to keep itself to a single package manager.

### `ripgrep` — required by `lua/plugin/picker.lua` and `lua/plugin/explorer.lua`

`snacks.picker` shells out for anything it does not read off the filesystem itself, and
`snacks.explorer` is one of its sources.

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
 Normal   main ( M)  #3 +2 ~6 󰰎 +  init.lua  Claude 5h 47% (resets 1h09m) · 7d 5%  󰢱 lua utf-8[unix] 344B  1|12│1|1
```

`mini.nvim` is installed whole rather than the single-module `nvim-mini/mini.statusline`
mirror, because catppuccin's `auto_integrations` matches on the repo name and its map
contains `mini.nvim` — the mirror would go unthemed. Unused modules stay inert until their
own `setup()` runs, so the rest costs disk and nothing else. Four of them are set up:

- **`mini.statusline`** — the bar itself.
- **`mini.git`** — purely the data source for the branch section, which reads a
  buffer-local variable something else has to populate. It also registers a `:Git`
  command, but `lua/plugin/git.lua` remains the git porcelain.
- **`mini.icons`** — the provider `section_fileinfo` needs for its filetype icon. Without
  it that icon is silently absent, since a missing provider is not an error.
- **`mini.diff`** — the data source behind the `#3 +2 ~6` counts, but set up from
  `lua/plugin/diff.lua` rather than here, because its real job is the gutter. See
  **[Git hunks](#git-hunks)**.

**Icons assume the terminal font carries the Nerd Font range.** They are worth about ten
columns over the `Git` / `Diag` / `LSP` word forms, and those columns matter: the Claude
section is the first thing truncation drops. Set `use_icons = false` in the spec to go
back to words.

`section_diff` reads `vim.b.minidiff_summary_string or vim.b.gitsigns_status`, so the
counts would survive swapping mini.diff for gitsigns without touching this file.

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
   hour, and only a real CLI session ever writes it. That last point got better with the
   move off ACP: `lua/plugin/ai.lua` now launches the actual `claude` binary in a terminal,
   so an editing session keeps the cache warm where an ACP-only one might never have
   touched it.
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
`permission_mode`, `agent_id`, `agent_type` and `effort`. That payload goes to whatever
`statusLine` command is configured in Claude's own `settings.json` — a separate process,
writing to the CLI's own bar inside its terminal, with no route into Neovim's. So even now
that a real CLI session runs in a split, the numbers still have to be fetched here rather
than received.

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

## Git hunks

`lua/plugin/diff.lua` sets up **`mini.diff`** — gutter marks for changed lines, hunk
motions, and staging. It is the in-buffer half of git; `lua/plugin/git.lua` (lazygit) stays
the porcelain. No download: `mini.nvim` is already installed for the statusline.

| Key | Does |
|---|---|
| `]h` / `[h` | Next / previous hunk. Also mapped in operator-pending mode, so `d]h` works |
| `]H` / `[H` | Last / first hunk |
| `gh` | Apply — **stages** the hunk to the git index. An operator, so `ghih`, `ghj`, or `gh` over a visual selection; `.` repeats it |
| `gH` | Reset — rewrites the buffer text back to the index. Same operator shape |
| `gh` (operator-pending) | Hunk-range textobject, as in `ghgh` to stage the hunk under the cursor |
| `<leader>go` | Toggle the overlay: deleted and changed reference lines shown inline as virtual text, with word-level diff |

Chosen over **gitsigns.nvim**, the fuller plugin, and **vgit.nvim**, which needs
`plenary.nvim` plus `nvim-web-devicons` and documents neither a textobject nor
partial-hunk staging. mini.diff wins on hunk ergonomics — `]h`/`[h` are its own defaults,
and apply/reset are real `operatorfunc` operators, so `.` repeats them with no `vim-repeat`
dependency, which gitsigns does need.

What that costs, stated plainly:

- **No blame, of any kind.** gitsigns has current-line virtual text and a full-file blame
  split; this has neither.
- **No `vimdiff` against the index.** The overlay is the nearest thing, and it is a
  different shape — virtual text inside this buffer, not a second editable window.
- **It stages but cannot unstage.** Upstream calls unstaging an explicit non-goal and says
  to use a full Git client — here that is `<leader>gg`.
- `gH` never invokes git. It rewrites buffer text to match the reference.

Two settings are not the defaults, both deliberate:

- `view.style = "sign"`. mini.diff picks `"number"` whenever `'number'` is set, and it is —
  that recolours the line number instead of drawing a gutter mark.
- `signcolumn = "yes:2"` in `lua/config/vim.lua`. mini.diff's extmarks sit at priority 199
  and `vim.diagnostic` signs at 10, so in a one-cell gutter the hunk mark would hide every
  error and warning sign. The cost is one permanent column of width.

## Terminal key support

**Nothing here requires a particular terminal any more.** `<C-CR>` used to — it submitted
the agentic.nvim prompt, and legacy terminals cannot encode it, since `Ctrl+Enter` sends the
same `0x0D` byte as plain `Enter`. That prompt buffer is gone with the move to
claudecode.nvim, which types into the CLI's own TUI where plain `Enter` submits.

The one key still sensitive to the **kitty keyboard protocol** is `<C-BS>`, and it is
already handled: `lua/config/keymap.lua` binds both spellings, because protocol-speaking
terminals (ghostty here, also kitty, wezterm, foot) report `<C-BS>` while everything else
collapses it onto `0x08` and arrives as `<C-h>`. Either way the key works.

To see which kind you are in, press `Ctrl-V` then the key in insert mode — a distinct code
means the protocol is negotiated, a legacy byte means it is not. Neovim 0.12 negotiates
automatically where it can.

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
