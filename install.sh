#!/usr/bin/env bash
#
# Install everything this Neovim config needs.
#
# Idempotent: re-running is safe. Existing tools that already meet the minimum
# version are left alone -- this will not install a Homebrew copy of something you
# already have from your system package manager or a version manager like `n`.
#
#   ./install.sh            install anything missing
#   ./install.sh --check    report status only, change nothing (exit 1 if incomplete)
#
# Supported: Linux. macOS is structured for but NOT tested -- see the OS block below.
#
# ┌──────────────────────────────────────────────────────────────────────────────┐
# │ ADDING A DEPENDENCY: append to BREW_DEPS or NPM_DEPS below. That is the only  │
# │ place to edit -- everything else is driven from those two tables. Also record  │
# │ it in README.md under "External dependencies".                                │
# │ Exception: language servers live in mason, not install.sh -- see CLAUDE.md. │
# └──────────────────────────────────────────────────────────────────────────────┘

set -euo pipefail

# ── Dependency tables ────────────────────────────────────────────────────────────
# Format: command|minimum version|brew formula|shell snippet printing the version
# A minimum of `-` means presence-only: no version probe, leave the probe field empty.
# Do NOT add a fifth field -- `read` gives the last variable everything remaining,
# including `|`, which is what lets the probes below contain pipes.
BREW_DEPS=(
	"nvim|0.12.0|neovim|nvim --version | head -1 | sed 's/^NVIM v//'"
	"git|2.19.0|git|git --version | awk '{print \$3}'"
	"node|22.0.0|node|node --version | sed 's/^v//'"
	# 0.40.0 is where lazygit gained the Worktrees panel.
	# Its --version line ends with `git version=X`, so split on commas and anchor the
	# field -- a plain `.*version=` is greedy and picks up the git version instead.
	"lazygit|0.40.0|lazygit|lazygit --version | tr ',' '\\n' | sed -n 's/^ *version=\\([0-9.]*\\)\$/\\1/p'"
	# nvim-treesitter compiles parsers locally with the tree-sitter CLI. Upstream is
	# explicit that it must come from a package manager and NOT npm.
	# `--version` prints `tree-sitter 0.26.3`, hence field 2.
	"tree-sitter|0.26.1|tree-sitter|tree-sitter --version | awk '{print \$2}'"
	# A C compiler for those parsers. Presence-only: on Linux `cc` comes from the distro's
	# build tools (Debian/Ubuntu: build-essential), and `brew install gcc` provides
	# `gcc-13` rather than `cc`, so the brew path here is nominal. Listed anyway so
	# --check reports it on a fresh machine, which is this script's job.
	"cc|-|gcc|"
	# The .NET SDK, for the C# server (`roslyn_ls`). Two reasons, both hard requirements:
	# its mason package is a NuGet package, which mason installs by spawning `dotnet`, and
	# Microsoft.CodeAnalysis.LanguageServer 5.8 is a `net10.0` assembly needing the
	# matching runtime. `dotnet --version` reports the SDK, which implies the runtime.
	"dotnet|10.0.0|dotnet|dotnet --version"
	# A Rust toolchain, for `rust_analyzer`. mason ships the server as a prebuilt binary,
	# but the server itself shells out to `cargo metadata` to load a workspace -- without
	# it you get a client that attaches and then knows nothing. Presence-only: any cargo
	# new enough to build the project is new enough here. `rustup` is the better install
	# than brew's `rust` if you want per-project toolchains; either satisfies this.
	"cargo|-|rust|"
	# Terraform, for `terraformls` -- which does not format HCL itself. Its
	# `textDocument/formatting` handler builds a TerraformExecutor and runs the real
	# `terraform fmt` through it, so without this binary Terraform files are the one
	# filetype in `lua/plugin/format.lua`'s LSP-fallback group that silently formats to
	# nothing. Presence-only: `terraform fmt` predates every version anyone still runs.
	# NOT a Homebrew core formula -- core dropped it after the BUSL relicense, so this is
	# tap-qualified and `brew install` taps it on demand. `opentofu` is the core-formula
	# alternative but `terraform-ls` execs `terraform` by name, so it is not a substitute.
	"terraform|-|hashicorp/tap/terraform|"
	# snacks.explorer's search box and its `<leader>/` grep-in-directory action shell out
	# here. The file finder degrades (fd -> rg -> find), but grep does not: `rg` is
	# hardcoded in snacks' grep source with no fallback, so without this the explorer
	# opens fine and one of its actions silently returns nothing.
	# 12.0.0 is where `--max-columns-preview` landed, which snacks passes unconditionally.
	# `--version` prints `ripgrep 14.1.0` on the first line, hence field 2.
	"rg|12.0.0|ripgrep|rg --version | head -1 | awk '{print \$2}'"
	# mason shells out to these four to download and unpack language servers. `curl` earns
	# its place twice: blink.cmp downloads its prebuilt Rust fuzzy matcher with curl and
	# git when installed from a release tag, which is what keeps a Rust toolchain optional
	# for it. Without them it falls back to a slower pure-Lua matcher rather than failing.
	"curl|-|curl|"
	"unzip|-|unzip|"
	# On Linux `tar` is already GNU tar. brew's `gnu-tar` installs `gtar`, not `tar`, so
	# as with `cc` the formula is nominal and the value is in --check reporting it.
	"tar|-|gnu-tar|"
	"gzip|-|gzip|"
	# ── Linters, for `lua/plugin/lint.lua` ───────────────────────────────────────────
	# nvim-lint spawns these by name and installs none of them. A missing one warns once
	# and contributes no diagnostics, so the failure is quiet rather than loud.
	# All presence-only: nvim-lint's definitions use flags these tools have had for years,
	# and none of them is a version floor worth defending.
	# The two Node-based linters are NOT here -- see NPM_DEPS below for why.
	#
	# Lua. `lua_ls` reports types; luacheck reports unused locals and global leaks.
	# Pulls brew's `lua` (5.4) as a dependency, which is only the interpreter luacheck
	# itself runs on -- it does not have to match the LuaJIT that Neovim embeds, and the
	# `std = "luajit"` line in `.luacheckrc` is what tells it which globals to expect.
	"luacheck|-|luacheck|"
	# Terraform. As with `terraform` above, NOT a core formula -- core has no `tflint` at
	# all, so this is tap-qualified and `brew install` taps it on demand.
	"tflint|-|terraform-linters/tap/tflint|"
	# Dockerfiles, for the best-practice rules `docker_language_server` does not cover
	# (pinned base tags, `apt-get upgrade`, shell-form pitfalls).
	"hadolint|-|hadolint|"
	# SQL. Needs a dialect before it will lint anything at all -- see README.md.
	"sqlfluff|-|sqlfluff|"
	# Shell scripts, the one filetype here with no language server behind it.
	"shellcheck|-|shellcheck|"
)

# Format: command|npm package spec
# Versions are pinned deliberately. Global npm installs are a supply-chain surface
# (see https://www.wiz.io/blog/shai-hulud-2-0-ongoing-supply-chain-attack), so bump
# these consciously rather than floating on latest.
NPM_DEPS=(
	"claude-agent-acp|@agentclientprotocol/claude-agent-acp@0.66.0"
	# prettier, as a daemon, for conform.nvim -- see `lua/plugin/format.lua`. It bundles
	# its own prettier (a dependency of the package), so this one entry covers markdown,
	# Vue, TypeScript and the JSON/YAML/CSS files around them. `prettierd` is the binary
	# name; the package is scoped.
	"prettierd|@fsouza/prettierd@0.29.0"
	# The two linters from `lua/plugin/lint.lua` that are Node programs. They are here
	# rather than in BREW_DEPS on purpose: both brew formulae declare a dependency on
	# `node`, so installing them that way pulls a SECOND Node in beside the Node 22 this
	# config already requires on PATH -- exactly what the version probes above exist to
	# avoid. npm also lets them be pinned, which brew does not.
	#
	# ESLint for the TypeScript and Vue filetypes, as a daemon -- the same rules `eslint`
	# applies, without paying Node startup on every lint. nvim-lint prefers
	# `./node_modules/.bin/eslint_d` when a project has its own, so this global copy is
	# the fallback for projects that do not.
	"eslint_d|eslint_d@15.0.3"
	# Markdown style rules -- `marksman` handles links and references and has no opinion
	# on heading or list formatting. `cli2` is the current line; plain `markdownlint-cli`
	# is the older one and nvim-lint ships definitions for both.
	"markdownlint-cli2|markdownlint-cli2@0.23.2"
)

# Dependencies that only apply on some platforms or session types.
# Format: command|brew formula|guard
# Guards are resolved in needed_here() below -- add a branch there for a new one.
CONDITIONAL_DEPS=(
	"wl-paste|wl-clipboard|linux-wayland"
	# snacks.explorer sends deletions to the system trash rather than unlinking them. It
	# probes `trash` (trash-cli), then `gio`, then the two `kioclient`s, and if none is
	# executable it falls back to a permanent delete -- with no warning. So this is not a
	# dependency the plugin needs to load, it is the one that decides whether `d` in the
	# explorer is recoverable. `gio` ships with glib and is on any modern Linux desktop.
	# macOS would want trash-cli's `trash` instead; it is untested here, so it is not
	# listed rather than being listed wrongly.
	"gio|glib|linux"
)

# ── Output helpers ───────────────────────────────────────────────────────────────
if [ -t 1 ]; then
	BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
	BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi

ok()      { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$*"; }
warn()    { printf "  %s!%s %s\n" "$YELLOW" "$RESET" "$*"; }
bad()     { printf "  %s✗%s %s\n" "$RED" "$RESET" "$*"; }
heading() { printf "\n%s%s%s\n" "$BOLD" "$*" "$RESET"; }
die()     { printf "\n%serror:%s %s\n" "$RED" "$RESET" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Does a CONDITIONAL_DEPS guard apply to the machine we are running on?
# $OS is set by the platform block further down.
needed_here() {
	case "$1" in
		linux-wayland) [ "$OS" = "linux" ] && [ -n "${WAYLAND_DISPLAY:-}" ] ;;
		linux)         [ "$OS" = "linux" ] ;;
		macos)         [ "$OS" = "macos" ] ;;
		*)             die "unknown dependency guard: $1" ;;
	esac
}

# version_ge A B -> true when A >= B
version_ge() {
	[ "$1" = "$2" ] || [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]
}

CHECK_ONLY=false
case "${1:-}" in
	--check) CHECK_ONLY=true ;;
	-h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	"") ;;
	*) die "unknown argument: $1 (try --help)" ;;
esac

MISSING=0

# ── Sanity: are we in the config repo? ───────────────────────────────────────────
cd "$(dirname "$0")"
[ -f init.lua ] && [ -d lua/config ] || die "run this from the nvim config repo root"

# ── OS detection ─────────────────────────────────────────────────────────────────
heading "Platform"
case "$(uname -s)" in
	Linux)
		OS=linux
		BREW_PREFIX_DEFAULT=/home/linuxbrew/.linuxbrew
		ok "Linux (supported)"
		;;
	Darwin)
		OS=macos
		# Apple silicon uses /opt/homebrew; Intel uses /usr/local.
		if [ "$(uname -m)" = "arm64" ]; then
			BREW_PREFIX_DEFAULT=/opt/homebrew
		else
			BREW_PREFIX_DEFAULT=/usr/local
		fi
		warn "macOS detected -- structurally supported but UNTESTED. Homebrew needs the"
		warn "Xcode Command Line Tools; its installer will prompt if they are absent."
		;;
	*)
		die "unsupported OS: $(uname -s). This config targets Linux (macOS untested)."
		;;
esac

# ── Homebrew ─────────────────────────────────────────────────────────────────────
heading "Homebrew"
if have brew; then
	ok "already installed at $(brew --prefix)"
elif $CHECK_ONLY; then
	bad "not installed"
	MISSING=$((MISSING + 1))
else
	warn "not found -- installing"
	# The official installer. It uses sudo for the initial directory setup and will
	# explain what it is about to do before touching anything.
	NONINTERACTIVE=1 /bin/bash -c \
		"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

	if [ -x "$BREW_PREFIX_DEFAULT/bin/brew" ]; then
		eval "$("$BREW_PREFIX_DEFAULT/bin/brew" shellenv)"
	else
		die "Homebrew installed but not found at $BREW_PREFIX_DEFAULT/bin/brew"
	fi
	ok "installed at $(brew --prefix)"

	cat <<-EOF

	  Add Homebrew to your shell so it persists across sessions:
	    echo 'eval "\$($BREW_PREFIX_DEFAULT/bin/brew shellenv)"' >> ~/.zshrc
	EOF
fi

# ── Tools ────────────────────────────────────────────────────────────────────────
heading "Tools"
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

# ── Global npm packages ──────────────────────────────────────────────────────────
heading "Node packages"
for entry in "${NPM_DEPS[@]}"; do
	IFS='|' read -r cmd spec <<<"$entry"

	if have "$cmd"; then
		ok "$cmd present ($(command -v "$cmd"))"
		continue
	fi

	if $CHECK_ONLY; then
		bad "$cmd missing -- npm i -g $spec"
		MISSING=$((MISSING + 1))
		continue
	fi

	have npm || die "npm is required to install $spec"

	# Root-owned global prefixes (the common case for a system Node) need sudo;
	# a user-owned prefix does not, and using sudo there would create root-owned
	# files in your own tree.
	npm_root="$(npm root -g)"
	if [ -w "$npm_root" ]; then
		npm install -g "$spec"
	else
		warn "$npm_root is not writable -- using sudo"
		sudo npm install -g "$spec"
	fi

	have "$cmd" || die "$cmd still not on PATH after installing $spec"
	ok "$cmd installed"
done

# ── Platform-conditional tools ───────────────────────────────────────────────────
heading "Platform-specific tools"
for entry in "${CONDITIONAL_DEPS[@]}"; do
	IFS='|' read -r cmd formula guard <<<"$entry"

	if ! needed_here "$guard"; then
		ok "$cmd not needed here ($guard) -- skipped"
		continue
	fi

	if have "$cmd"; then
		ok "$cmd present ($(command -v "$cmd"))"
		continue
	fi

	if $CHECK_ONLY; then
		bad "$cmd missing -- brew install $formula"
		MISSING=$((MISSING + 1))
		continue
	fi

	have brew || die "Homebrew is required to install $formula"

	# Note: Homebrew's wl-clipboard pulls in its own wayland + wayland-protocols.
	# Your distro package (apt/dnf/pacman install wl-clipboard) is a lighter option
	# that reuses the system libraries -- either works, brew is used here to keep
	# this script to a single package manager.
	brew install "$formula"

	have "$cmd" || die "$cmd still not on PATH after installing $formula"
	ok "$cmd installed"
done

# ── Verify ───────────────────────────────────────────────────────────────────────
heading "Verifying the config"
if $CHECK_ONLY; then
	if [ "$MISSING" -gt 0 ]; then
		[ "$MISSING" -eq 1 ] && noun="dependency" || noun="dependencies"
		printf "\n%s%d %s missing.%s Run ./install.sh to fix.\n" \
			"$YELLOW" "$MISSING" "$noun" "$RESET"
		exit 1
	fi
	ok "all dependencies satisfied"
	exit 0
fi

# First run clones plugins, so this can take a moment.
if nvim --headless "+qa" 2>&1 | tail -5; then
	ok "config loads cleanly"
else
	die "config failed to load -- see output above"
fi

count="$(nvim --headless "+lua io.write(#require('lazy').plugins())" "+qa" 2>/dev/null || echo "?")"
ok "lazy.nvim reports $count plugin(s)"

cat <<-EOF

	${BOLD}Done.${RESET} Next:
	  - run ${BOLD}claude /login${RESET} if you have not (the ACP provider reuses that session)
	  - open ${BOLD}nvim${RESET} and check ${BOLD}:Lazy${RESET}
	  - ${BOLD}<leader>aa${RESET} toggles the Claude Code chat
EOF
