# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a personal Neovim configuration using [lazy.nvim](https://github.com/folke/lazy.nvim) as the plugin manager. The configuration is written entirely in Lua and follows a modular architecture where plugins are separated into individual files.

## Dependencies

- [Rust](https://rust-lang.org/tools/install/) - Required for building native components (blink.cmp completion engine)
- [treesitter-cli](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md) - Required for syntax highlighting

## Architecture

### Entry Point
- `init.lua` - Loads the entire configuration in order:
  1. `config.vim` - Core Vim settings (tabs, line numbers, leader keys)
  2. `config.lazy` - Bootstraps lazy.nvim and imports all plugins
  3. `config.keymap` - Global keybindings
  4. `config.autocommand` - Autocommands (format on save, etc.)

### Plugin System
All plugins live in `lua/plugin/` as individual files. Each file returns a table (or array of tables) containing lazy.nvim plugin specifications. When lazy.nvim loads, it imports all files from the `plugin` directory.

**Pattern:**
```lua
return {
  "author/plugin-name",
  opts = { ... },
  config = function() ... end,
}
```

**Key plugin files:**
- `lsp.lua` - LSP configuration using Mason for automatic server installation. Includes special configuration for lua_ls (Neovim runtime awareness) and roslyn (C# with inlay hints). Mason uses both official and custom registries.
- `completion.lua` - blink.cmp completion engine (requires `cargo build --release`)
- `search.lua` - Telescope fuzzy finder with dropdown theme
- `file.lua` - Oil.nvim file explorer
- `git.lua` - LazyGit integration

### Configuration Files
- `config/vim.lua` - Sets leader keys (`<Space>` and `\`), disables netrw, configures indentation (2 spaces)
- `config/keymap.lua` - Global keymaps and plugin setup (debugger, LSP actions, Telescope, terminal)
- `config/autocommand.lua` - Includes format-on-save for all files, automatic semicolon insertion for C# files, and cleanup logic for file explorer windows

## Working with This Configuration

### Adding New Plugins
Create a new file in `lua/plugin/` (e.g., `my-plugin.lua`) that returns a lazy.nvim spec. The plugin will be automatically loaded on next Neovim start.

### Modifying Keybindings
- Global keybindings: Edit `lua/config/keymap.lua`
- Plugin-specific keybindings: Edit the relevant file in `lua/plugin/` within the plugin's `opts` or `config` function
- Leader key is `<Space>`, local leader is `\`

### LSP Servers
LSP servers are managed by Mason. To add a new language server:
1. Add it to the `ensure_installed` list in `lua/plugin/lsp.lua`
2. Server will be automatically installed on next Neovim start
3. For custom configuration, use `vim.lsp.config()` in the config function

### Testing Configuration Changes
To reload the current Lua file: `<leader>s` (sources the current file with `:so %`)

## Special Features

### C# Development
- Uses roslyn.nvim for C# LSP with file watching enabled
- Automatic semicolon insertion: When in insert mode in `.cs` files, pressing `;` will intelligently place it at the end of the expression/statement using treesitter
- Inlay hints and code lens enabled for implicit types and references

### Debugger
- DAP (Debug Adapter Protocol) configured with dapui
- Lua debugging with nlua adapter available via `<leader>dl`
- Standard debugging keybinds: F5 (continue), F10 (step over), F11 (step in), F12 (step out)

### Auto-formatting
All files are automatically formatted on save using LSP's built-in formatter (see `config/autocommand.lua`). This is synchronous to ensure formatting completes before save.
