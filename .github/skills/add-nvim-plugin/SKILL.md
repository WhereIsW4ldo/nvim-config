---
name: add-nvim-plugin
description: >
  Research, choose, and install a Neovim plugin for this config. Use whenever the
  user asks to add a plugin or asks for a capability that needs one -- "add a fuzzy
  finder", "I want git signs in the gutter", "set up an LSP", "I need a statusline".
  Sources candidates from awesome-neovim, health-checks them against GitHub, presents
  a comparison for the user to choose from, then implements the winner as a
  lua/plugin/<topic>.lua spec. Do NOT pick a plugin without running this.
---

# Adding a Neovim plugin

The rule this exists to enforce: **research the field, then let the user choose.**
Reaching for the first plugin that comes to mind is the failure mode.

Read `CLAUDE.md` first — it owns the file layout and the Lua style, and this skill
does not restate them.

## 1. Map the requirement to an awesome-neovim category

Candidates come from [awesome-neovim](https://github.com/rockerBOO/awesome-neovim).
Fetch the raw list, do not scrape the rendered page:

```sh
curl -s https://raw.githubusercontent.com/rockerBOO/awesome-neovim/main/README.md
```

The section names are **not guessable** — several obvious ones do not exist. Verified
mappings:

| Looking for | Actual section |
|---|---|
| statusline, tabline, bufferline, cursorline | `## Bars and Lines` (subsections) |
| treesitter, syntax highlighting | `## Syntax` — there is **no** "Treesitter" heading |
| linters | `## LSP` — *not* `## Formatting` |
| formatters | `## Formatting` |
| DAP, debugging | `## Debugging` (`### Quickfix` nests oddly under it) |
| fuzzy finder | `## Fuzzy Finder` (singular) |
| file explorer | `## File Explorer` (singular); `## Project` is separate |
| dashboard, start screen | `## Startup` |
| which-key, hydra | `## Keybinding` |
| comments, folding | `## Editing Support` (subsections) |
| AI / coding agents | `## AI` |

`## Utility` (~56 entries) and `## AI` (~47) are catch-alls — check them when a
narrower category comes up empty. Roughly 1,400 entries total.

## 2. Fan out parallel research subagents

Launch **`Explore` agents with `model: "sonnet"`**, all in one message so they run
concurrently. Two is usually right:

- **Agent A — enumerate and health-check.** Extract every entry in the category
  verbatim, then check each against GitHub (step 3). Instruct it *not* to pick a
  winner; you want the factual landscape only.
- **Agent B — feature deep-dive.** Decompose the user's requirement into concrete
  testable capabilities and evaluate the plausible contenders against each, quoting
  their docs. Tell it to mark anything it cannot confirm as UNCONFIRMED rather than
  assuming.

Give both agents today's date, so staleness is computed against now and not against
a training cutoff.

## 3. Health-check against GitHub — mandatory

**awesome-neovim carries no maintenance annotations.** There are no archived flags,
no "unmaintained" markers, no version tags. The only tags in the whole list are
colorscheme feature flags (`[TS]`, `[LSP]`, `[L/D]`, `[Lua]`, `[Fnl]`), which say
nothing about health. Its acceptance criteria gate *new additions* only — already
listed plugins are **not** pruned when they go stale.

So presence in the list is not evidence a plugin is alive. Check every candidate:

```sh
curl -s https://api.github.com/repos/OWNER/REPO \
  | jq '{archived, pushed_at, stargazers_count, open_issues_count}'
```

Screen out, and say so explicitly:

- `archived: true`
- no push in over a year
- a README that self-declares deprecated or superseded
- 404s — the list does contain dead links
- docs telling you to wait for a rewrite, or marking the project frozen

Also check plainly good candidates that are **absent** from the list. Real gaps
exist: `folke/sidekick.nvim`, `coder/claudecode.nvim`, and `greggh/claude-code.nvim`
are all missing from `## AI`. CLAUDE.md permits an unlisted plugin as long as the
reason is stated — an absence you verified is a reason; "it was the first search
result" is not.

## 4. Stop. Present a comparison. Let the user choose.

**Never self-select.** Use `AskUserQuestion` with 2–4 real options.

- Lead with the recommendation and say why it wins.
- Give every option an honest tradeoff — a comparison where one choice has no
  downside means the research was too shallow.
- Rule candidates out on **facts** (archived, frozen, stale, no such feature), not
  taste, and show the fact.
- Use `preview` to show what the thing actually looks like in use.
- Surface architectural forks explicitly. Two plugins that nominally do the same job
  may work completely differently, and that difference is usually the real decision.

## 5. Implement

One file per concern: `lua/plugin/<topic>.lua`, named for the **capability**, not the
plugin — `search.lua`, not `telescope.lua` — so swapping the plugin later is not a
rename plus a hunt for stale references.

Per CLAUDE.md: return a lazy.nvim spec, prefer `opts` over a `config` function,
declare keymaps in the spec's `keys` field with a `desc` on each, and lazy-load on
`event`/`ft`/`cmd`/`keys` where reasonable.

Check the keymaps you pick against what already exists, and say so if you deviate
from what upstream suggests:

```sh
nvim --headless "+verbose map <leader>x" "+qa"
```

### External dependencies — do not skip this

If the plugin needs anything that is not a Lua file — a compiler, a CLI, a language
server, an npm package, `tree-sitter`, Rust for a native build — it must be recorded in
**two** places, or a fresh machine will install this config and quietly get a plugin
that loads but does nothing:

1. **`install.sh`** — append to `BREW_DEPS` (a tool available via Homebrew) or
   `NPM_DEPS` (a global npm package). Those two tables drive the whole script; nothing
   else in it needs editing. Pin npm versions rather than floating on latest.
2. **`README.md`** — add it under "External dependencies", with what needs it and why.

Then prove the script still reports the truth:

```sh
./install.sh --check     # exits 1 and names anything missing
```

A plugin whose dependency is absent from `install.sh` is not finished.

## 6. Verify, and be honest about what you verified

```sh
cd ~/.config/nvim
nvim --headless "+qa"; echo "exit=$?"                              # loads clean
nvim --headless "+lua print(#require('lazy').plugins())" "+qa"     # spec registered
nvim --headless "+checkhealth lazy" "+qa"
```

A clean headless load proves the spec **parses**. It does not prove the plugin does
what was asked. For anything user-visible — a keymap, a UI, a notification — say it
needs an interactive check rather than reporting it as working.

Commit only when asked. Include `lazy-lock.json` in any commit that changes plugins.
