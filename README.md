# nvim-config

Personal Neovim configuration. Lua, modular, managed by
[lazy.nvim](https://github.com/folke/lazy.nvim).

See [CLAUDE.md](CLAUDE.md) for the layout, conventions, and code style.

## Requirements

| Requirement | Why | Notes |
|---|---|---|
| Neovim **0.12+** | Config targets modern APIs (`vim.lsp.config`, `vim.hl`, built-in EditorConfig) | `nvim --version` |
| Git **2.19+** | lazy.nvim uses partial clones (`--filter=blob:none`) | |
| Node **22+** | The global npm packages below | |
| lazygit **0.40+** | `lua/plugin/git.lua` wraps the lazygit TUI | 0.40.0 added the Worktrees panel |
| tree-sitter CLI **0.26.1+** | `nvim-treesitter` compiles parsers locally | From a package manager, **not npm** — upstream is explicit |
| A C compiler (`cc`) | Compiling those parsers | Debian/Ubuntu: `apt install build-essential`; Windows: MinGW or Visual Studio Build Tools |
| .NET SDK **10+** | Everything in `lua/plugin/dotnet.lua`: the `EasyDotnet` global tool, the Roslyn server it manages, and the `dotnet` verbs themselves | `dotnet --version` |
| A Rust toolchain (`cargo`) | `rust_analyzer` loads a workspace with `cargo metadata` | `rustup` or `brew install rust` |
| `curl`, `unzip`, `tar`, `gzip` | mason downloads and unpacks language servers; `curl` + `git` also fetch `blink.cmp`'s prebuilt fuzzy matcher | Linux uses these Unix tools; Windows uses PowerShell, Git, GNU tar, and 7-Zip-compatible extraction (covered by `install.ps1`) |

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

**C# is not in that list.** It used to be — `roslyn_ls`, installed by mason from NuGet —
and it now comes from easy-dotnet instead, which drives the *same* Roslyn server through
its own sidecar and adds Roslynator, Razor and a test runner on top. See
[.NET tooling](#net-tooling--required-by-luaplugindotnetlua) below.

#### Which server, and why

| Language | Server | Chosen over |
|---|---|---|
| Terraform | `terraformls` | HashiCorp's own. `terraform_lsp` is the community alternative and is unmaintained. |
| Markdown | `marksman` | — |
| Vue + TypeScript | `vue_ls` + `vtsls` | `ts_ls`. Since Vue language server v3 there is no takeover mode, and both upstreams point at `vtsls`; lspconfig warns against enabling `ts_ls` alongside it. |
| Docker | `docker_language_server` | `dockerls` + `docker_compose_language_service`, which take two servers to cover the same ground. Docker's own binary also handles Bake. |
| Rust | `rust_analyzer` | — |

Two of them need a toolchain `install.sh` installs: **`cargo`**, because `rust_analyzer`
shells out to `cargo metadata` and knows nothing about a project without it; and
**`terraform`**, because HCL formatting goes through the CLI rather than the server — see
below. (**`dotnet`** is a third such toolchain, but it belongs to easy-dotnet rather than
to mason now — see [.NET tooling](#net-tooling--required-by-luaplugindotnetlua).)

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

One more gap worth knowing about:

- **Compose files need a filetype Neovim does not detect.** `docker_language_server`
  attaches on `yaml.docker-compose`, so `lua/plugin/docker.lua` registers the patterns.
  A Compose file under a name neither `compose*.yaml` nor `docker-compose*.yaml` matches
  will open as plain `yaml` and get no server.

### .NET tooling — required by `lua/plugin/dotnet.lua`

C# is the one language here whose server does **not** come from mason. It used to:
`roslyn_ls` was in `ensure_installed`, mason pulled the NuGet package, and that was the
whole of the .NET story — a language server and nothing else. `lua/plugin/dotnet.lua` now
runs [easy-dotnet.nvim](https://github.com/GustavEikaas/easy-dotnet.nvim), which starts the
*same* server (Microsoft.CodeAnalysis.LanguageServer, the engine behind the VS Code C#
extension) and adds the parts mason's copy could not:

| | mason's `roslyn_ls` | easy-dotnet |
|---|---|---|
| Roslyn LSP | ✅ | ✅ same server |
| Roslynator analysers | ❌ | ✅ bundled, on by default |
| Solution-wide project graph | nearest `.csproj` | walks up for `.sln`/`.slnx` first |
| Razor / `.cshtml` | ❌ | ✅ |
| Test runner | ❌ | ✅ Rider-style, with gutter signs |
| `run` / `watch` / `build` / launch profiles | ❌ | ✅ `:Dotnet` |
| User secrets, NuGet add/outdated | ❌ | ✅ |

The two must never both be enabled — `mason-lspconfig`'s `automatic_enable` would attach a
second Roslyn to every `cs` buffer, doubling diagnostics and completion and running two
solution indexes side by side. That is why C# is absent from `ensure_installed`.

`omnisharp` (the Mono-era predecessor) and `csharp_ls` (community, lighter, less complete)
remain the alternatives not taken, on the same grounds as before.

#### `dotnet-easydotnet` — the sidecar

Not a Lua file and not optional. The test runner, the workspace diagnostics, the NuGet
completion in `.csproj` buffers and the launch of the Roslyn server itself are all RPC
calls into a .NET global tool:

```sh
dotnet tool install -g EasyDotnet
```

The plugin will run that install itself on first load if the binary is missing — but the
shim lands in `~/.dotnet/tools`, and `dotnet` does not put that directory on `PATH` for
you. Installed-but-not-on-`PATH` looks exactly like never-installed, so `install.sh` owns
both halves: it installs the tool from `DOTNET_TOOL_DEPS` and warns separately when the
directory is missing from `PATH`.

It is the one entry in `install.sh` that is **not pinned**. Plugin and sidecar are
versioned together and the plugin warns when the sidecar falls behind; a number here would
only go stale against a `lazy-lock.json` that already pins the plugin. Update with:

```sh
dotnet-easydotnet -v          # what is installed
```

then `:Dotnet _server update` from inside Neovim.

**`roslyn-language-server` is deliberately not listed anywhere.** The sidecar downloads and
manages it (`dotnet tool install --global roslyn-language-server --prerelease`), which is
also why `./install.sh --check` is silent about the C# server just as it is about mason's.
`:checkhealth easy-dotnet` is what covers it.

#### `vscode-html-language-server` — Razor markup

Razor and `.cshtml` open through Roslyn on their own, but the markup half of the file —
HTML completion, hover, formatting, document symbols — is bridged to VS Code's standalone
HTML server, which easy-dotnet neither bundles nor installs:

```sh
npm i -g vscode-langservers-extracted@4.10.0
```

Only that one binary of the five in the package is used; the JSON, CSS, ESLint and Markdown
servers it also ships are inert here, since nothing in `lua/plugin/lsp.lua` starts them.
Without it, Razor files still open and still get C# support — the markup-backed requests
just return empty.

#### File watching, on Linux

Roslyn learns about on-disk changes from one of two watchers, and on Linux easy-dotnet
picks the weaker one on purpose. Neovim's own watcher (`workspace/didChangeWatchedFiles`)
is backed by inotify and registers one instance per directory, so a large solution
exhausts `fs.inotify.max_user_instances` and the file descriptor limit and watching stops
altogether. The in-process watcher keeps an untuned machine working.

This config leaves that default alone rather than shipping an `lsp/easy_dotnet.lua` whose
correctness depends on sysctl values that are not in this repo. `:checkhealth easy-dotnet`
reports which side is currently watching. To switch:

```sh
sudo sysctl fs.inotify.max_user_instances=1024
sudo sysctl fs.inotify.max_user_watches=524288
ulimit -n 4096
```

then advertise the capability from `lsp/easy_dotnet.lua`, which is merged on top of
easy-dotnet's defaults.

#### The debugger

`lua/plugin/debug.lua` supplies it — see [Debugging](#debugging) below. Nothing needs
installing for it: easy-dotnet bundles `netcoredbg` inside its own tool store and writes
the `coreclr` adapter and the `cs` launch configurations itself, from
`debugger.auto_register_dap`. `:checkhealth easy-dotnet` reports the binary it found under
`debugger.path`.

That registration is `pcall`-guarded on `require("dap")`, which is why easy-dotnet worked
before `nvim-dap` existed here and simply had no debugger. `lua/plugin/dotnet.lua` names
`mfussenegger/nvim-dap` in its `dependencies` so the order is a fact rather than a
coincidence: dap is loaded before easy-dotnet's `setup()` runs, so the adapter is always
registered.

### `prettierd` — required by `lua/plugin/format.lua`

[conform.nvim](https://github.com/stevearc/conform.nvim) runs a CLI formatter only where
one beats the language server. That is prettier, for markdown (`marksman` implements no
formatting at all) and for the Vue/TypeScript family plus the JSON/YAML/CSS files around
them (`vtsls` formats with tsserver's formatter, which is not prettier's style and ignores
a project's `.prettierrc`). Terraform is a separate case, on latency rather than style —
see below. Everything else — Lua, C#, Rust, SQL, Dockerfiles — falls through to its server
and needs nothing here.

.NET project files (`.csproj`, `.fsproj`, `.vbproj`, `.props`, `.targets`, `.slnx`) are the
one exception to that fallback: they are `xml` buffers with no CLI formatter, so the
fallback was easy-dotnet's ProjX server, which strips the blank lines between `<ItemGroup>`s
and respaces self-closing tags on every write. `lua/plugin/dotnet.lua` sets conform's own
`disable_autoformat` on those buffers and pins them to two-space indent, overriding
`.editorconfig` — `<leader>F` still formats one on demand.

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

**C# and Rust are deliberately absent.** The server easy-dotnet starts *is* Roslyn, the
same engine the standalone C# analysers call — with Roslynator's rules bundled on top —
and `clippy` is a `rust_analyzer` setting rather than a second process worth spawning
beside it. Adding either would duplicate work the server already does.

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
  `~/.config/sqlfluff/.sqlfluff` — it cannot live in the repo, because sqlfluff resolves
  config by walking up from the file it is handed, and SQL buffers may live outside the
  repository.

  **`install.sh` writes that file**, so a fresh machine is not left half-configured. It is
  the one thing in the script that is a config file rather than a binary, which is why it
  has its own section instead of a table entry. If the file already exists it is reported
  and **left alone** — never rewritten, since it may have been customised deliberately —
  with a warning naming any of the three expected settings it does not set. That case is a
  warning and not a failure: `./install.sh --check` exits non-zero when the file is
  *missing*, not when it is merely different from this one.

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

  `AM04` is excluded in the same file. The rule is fair for a checked-in query and pure
  noise for ad-hoc querying, where `SELECT *` is the point — and it was also the violation
  that most often made `sqlfluff fix` exit non-zero:

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

### `claude` — required by `lua/plugin/ai.lua`

[claudecode.nvim](https://github.com/coder/claudecode.nvim) is pure Lua and installs
nothing itself. It stands up a WebSocket server, writes `~/.claude/ide/<port>.lock`, and
launches the Claude Code CLI pointed at it — the same discovery handshake Anthropic's own
VS Code and JetBrains extensions use. The CLI is therefore the *only* external dependency,
and without it `:ClaudeCode` opens a terminal that immediately exits.

Use Anthropic's native installer:

```sh
curl -fsSL https://claude.ai/install.sh | bash
```

On Windows, `install.ps1` checks for `claude` and, when it is missing, runs Anthropic's
official native installer:

```powershell
irm https://claude.ai/install.ps1 | iex
```

The native installers are the current upstream recommendation; npm installation is
deprecated. An existing `claude` on `PATH` is left untouched.

Notes:

- Authentication reuses your existing `claude /login` session. No `ANTHROPIC_API_KEY`.
- `claude doctor` reports installation and PATH problems.

Verify:

```sh
command -v claude && claude --version
```

On Windows, use `Get-Command claude` and `claude --version`.

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

## Debugging

`lua/plugin/debug.lua` holds [nvim-dap](https://github.com/mfussenegger/nvim-dap) and
[nvim-dap-view](https://github.com/igorlfs/nvim-dap-view). It is in this README rather than
under "External dependencies" because it needs **nothing installed** — the only adapter
configured today is .NET's, and easy-dotnet bundles `netcoredbg` and registers the adapter
itself.

No adapter or launch configuration is written by hand anywhere. easy-dotnet registers
`dap.adapters["easy-dotnet"]` and a single `dap.configurations.cs` entry — note the name:
it is *not* the `coreclr` adapter most .NET DAP guides have you write yourself, and it is a
`request = "attach"`, because the sidecar starts the process and the debugger attaches to
it. That is why `<leader>cd` is the way in on a cold project rather than a bare `<F5>`.

Adding a second debugged language means a `lua/plugin/<language>.lua` that registers its
own adapter, not an edit to `debug.lua`.

### Why `nvim-dap-view` and not `nvim-dap-ui`

`rcarriga/nvim-dap-ui` is the better-known option and was the alternative considered. Two
facts decided it, neither about taste:

- **Inline virtual text is built in.** The debugged value drawn beside the variable is the
  thing that makes stepping readable, and dap-view ships a minimal reimplementation of
  `theHamsta/nvim-dap-virtual-text` — whose own last push was **2025-05-25**. With
  nvim-dap-ui that plugin is a third install, and a stale one.
- **No extra dependency.** nvim-dap-ui requires `nvim-neotest/nvim-nio`; dap-view requires
  nothing.

What it costs, stated plainly: easy-dotnet's live CPU and memory panels are **nvim-dap-ui
elements** — `sys_monitor_dap_ui.lua` registers `easy-dotnet_cpu` and `easy-dotnet_mem`
through `dapui.register_element` and through nothing else, so they do not exist here.
dap-view has `winbar.custom_sections` and an equivalent is writable, but easy-dotnet ships
none and this config has not written one. That is the whole of the difference.

Two defaults are overridden, both off upstream:

| Option | Default | Here | Why |
|---|---|---|---|
| `auto_toggle` | `false` | `true` | Upstream expects you to run `:DapViewOpen` yourself. A debug session with no visible scopes is not a state worth being one keypress away from. |
| `virtual_text.enabled` | `false` | `true` | The reason this plugin won. Needs Neovim 0.12+ for `inline` virtual text, which this config already requires. |

### Keys

The stepping verbs are on function keys because F5/F10/F11 are what Visual Studio, VS Code
and Rider all bind — the one part of this config deliberately *not* made
`<leader>`-idiomatic. Everything else is the `<leader>x` group ("Debug"); `<leader>d` and
`<leader>D` were already Diagnostics and Database.

| Key | Action |
|---|---|
| `<F5>` | Start, or continue a running session |
| `<F10>` / `<F11>` / `<F12>` | Step over / into / out |
| `<leader>xb` / `<leader>xB` | Toggle breakpoint / set a conditional one |
| `<leader>xc` | Run to cursor |
| `<leader>xj` / `<leader>xk` | Down / up a stack frame |
| `<leader>xl` | Re-run the last configuration |
| `<leader>xq` / `<leader>xX` | Terminate session / clear all breakpoints |
| `<leader>xv` | Toggle the view (after an accidental close) |
| `<leader>xw` / `<leader>xh` | Watch / hover the expression under the cursor or selection |

Breakpoints deliberately survive `<leader>xq`, so the next `<F5>` stops in the same places;
`<leader>xX` is what clears them.

Starting a .NET session is `<leader>cd` (or `<leader>cD` for a launch profile) from the
`<leader>c` group — those pick a project, build it and launch it. Once a session is
running everything above is language-agnostic and stays that way.

Inside the view, `g?` lists the section-local keymaps, and the winbar letters switch
sections: `W` watches, `S` scopes, `B` breakpoints, `T` threads, `R` REPL, `E` exceptions.

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

On Windows, `install.ps1` does the same with Chocolatey in place of Homebrew (winget is
often disabled by Group Policy). Installing packages needs an elevated shell; `-Check` does
not. `luacheck` has no Chocolatey package and is reported for manual install, and
`sqlfluff` comes from pip.

Missing or outdated tools use `choco upgrade`, which also installs packages that are
not yet installed. Tools already meeting the minimum are left untouched.

```powershell
.\install.ps1 -Check    # exits non-zero and names whatever is missing
.\install.ps1           # from an elevated PowerShell
```

### npm certificate errors on managed Windows machines

`UNABLE_TO_GET_ISSUER_CERT_LOCALLY` means Node cannot validate the registry's TLS
certificate chain. A common cause is a corporate HTTPS-inspection proxy whose CA is
trusted by Windows but absent from Node's bundled CA certificates.

For npm installs, `install.ps1` enables Node's `--use-system-ca` when the installed
Node supports it (Node **22.15+**, or **23.9+** and later release lines). This adds
the Windows certificate store without disabling TLS verification. Existing
`NODE_OPTIONS` are preserved and restored afterwards; `-Check` does not change them.
Explicit npm `ca`/`cafile` settings still take precedence over Node's default CA
list, so an outdated custom bundle may need updating.

If the CA is not in the Windows store, or your Node version lacks this flag, obtain
the approved root/intermediate CA bundle in **PEM format** from IT and retry:

```powershell
$env:NODE_EXTRA_CA_CERTS = "C:\certs\corporate-ca.pem"
.\install.ps1
```

The file must exist before Node starts. This environment setting lasts for the
current PowerShell session and extends Node's trusted CAs. Never work around the
error with `npm config set strict-ssl false` or `NODE_TLS_REJECT_UNAUTHORIZED=0`.

lazy.nvim then bootstraps itself on first launch and installs plugins from
`lazy-lock.json`. Manage them with `:Lazy`.

## Platform support

Linux is the supported target. macOS is structurally handled in `install.sh` (Homebrew
prefix detection for both Apple silicon and Intel) but **untested** — it will warn and
proceed. Other platforms are refused outright.

## Verifying a change

Windows installer regression checks (no package installs or elevation required):

```powershell
powershell -NoProfile -File .\tests\install.Tests.ps1
pwsh -NoProfile -File .\tests\install.Tests.ps1
```

```sh
nvim --headless "+qa"; echo "exit=$?"                            # loads clean
nvim --headless "+lua print(#require('lazy').plugins())" "+qa"   # specs registered
nvim --headless "+checkhealth lazy" "+qa"
```

A clean headless load proves the config **parses** — not that a keymap, colorscheme, or
notification behaves. Check those interactively.
