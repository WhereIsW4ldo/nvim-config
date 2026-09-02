-- Debugging: the DAP client and the UI that makes it readable.
--
-- An array of two specs, which CLAUDE.md names as the case for it -- a DAP adapter and its
-- UI are only useful together, and lazy.nvim merges the second spec into the `dependencies`
-- entry of the first, so `nvim-dap-view` is set up before `nvim-dap` finishes loading.
-- That ordering is not cosmetic: dap-view registers its `dap.listeners` inside `setup()`,
-- and `auto_toggle` below is those listeners.
--
-- ── No adapter is configured here ────────────────────────────────────────────────────
--
-- Unusually for a DAP setup, this file defines no adapter and no launch configuration.
-- `lua/plugin/dotnet.lua` does it: easy-dotnet's `debugger.auto_register_dap` writes
-- `dap.adapters["easy-dotnet"]` and the matching `dap.configurations.cs` itself, pointed
-- at the `netcoredbg` it bundles inside its own tool store. Note the name -- it is not the
-- `coreclr` adapter most .NET DAP guides tell you to write by hand, and its single
-- configuration is a `request = "attach"`: easy-dotnet's sidecar launches the process and
-- the debugger attaches to it, which is why `Dotnet debug` is the entry point rather than
-- a bare `<F5>` on a cold project. So there is nothing in `install.sh` for this either --
-- `:checkhealth easy-dotnet` reports the debugger it found under `debugger.path`.
--
-- The registration is `pcall`-guarded on `require("dap")`, which is why easy-dotnet worked
-- without this file at all and simply had no debugger. C# is currently the only language
-- here with an adapter; another one means another `lua/plugin/<language>.lua`, not an
-- addition to this file.
--
-- ── Why nvim-dap-view over nvim-dap-ui ───────────────────────────────────────────────
--
-- Two facts, neither about taste:
--
--   * Inline virtual text -- the debugged value drawn beside the variable, which is the
--     single thing that makes stepping readable -- is BUILT IN here. With nvim-dap-ui it
--     is a third plugin, `theHamsta/nvim-dap-virtual-text`, whose last push was
--     2025-05-25. dap-view ships a minimal reimplementation of exactly that plugin.
--   * nvim-dap-ui needs `nvim-neotest/nvim-nio` as a hard dependency. dap-view needs
--     nothing.
--
-- What it costs, stated plainly: easy-dotnet's live CPU and memory panels
-- (`easy-dotnet_cpu`, `easy-dotnet_mem`) are nvim-dap-ui elements -- they are registered
-- with `dapui.register_element` and with nothing else, so they do not exist here.
-- dap-view has `winbar.custom_sections`, so an equivalent is writable, but easy-dotnet
-- ships none and this config has not written one.
return {
	{
		"mfussenegger/nvim-dap",

		dependencies = { "igorlfs/nvim-dap-view", },

		-- The stepping verbs are on function keys and the rest on `<leader>x`. That split
		-- is deliberate: F5/F10/F11 are what Visual Studio, VS Code, Rider and every other
		-- debugger bind, so they are the one part of this config worth NOT making
		-- `<leader>`-idiomatic. `<leader>x` is the group for everything else -- `<leader>d`
		-- is Diagnostics and `<leader>D` is Database, so the mnemonic letter was gone
		-- twice over.
		--
		-- F5 is both "start" and "continue", as everywhere else: with no session running
		-- `dap.continue()` picks a configuration and launches it.
		keys = {
			{ "<F5>",       function() require("dap").continue() end,          desc = "Debug: start or continue", },
			{ "<F10>",      function() require("dap").step_over() end,         desc = "Debug: step over", },
			{ "<F11>",      function() require("dap").step_into() end,         desc = "Debug: step into", },
			{ "<F12>",      function() require("dap").step_out() end,          desc = "Debug: step out", },

			{ "<leader>xb", function() require("dap").toggle_breakpoint() end, desc = "Toggle breakpoint", },
			{ "<leader>xl", function() require("dap").run_last() end,          desc = "Re-run the last configuration", },
			{ "<leader>xc", function() require("dap").run_to_cursor() end,     desc = "Run to cursor", },
			{ "<leader>xj", function() require("dap").down() end,              desc = "Down a stack frame", },
			{ "<leader>xk", function() require("dap").up() end,                desc = "Up a stack frame", },

			-- Prompts for the condition. Worth its own key rather than a `dap.ui` detour:
			-- a conditional breakpoint is the cheapest way out of stepping a loop 400
			-- times, and nothing else in nvim-dap surfaces it.
			{
				"<leader>xB",
				function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end,
				desc = "Set conditional breakpoint",
			},

			-- `terminate()` ends the session; the breakpoints deliberately survive it, so
			-- the next F5 stops in the same places. Clearing them is `<leader>xX`.
			{ "<leader>xq", function() require("dap").terminate() end,         desc = "Terminate session", },
			{ "<leader>xX", function() require("dap").clear_breakpoints() end, desc = "Clear all breakpoints", },
		},

		-- A `config` rather than `opts`, because nvim-dap has no `setup()` at all -- it is
		-- configured by assigning to its module tables, and the signs are a global
		-- side effect that a table cannot express.
		config = function()
			-- Defaults are the bare letters `B`, `C`, `L` and an arrow -- a breakpoint
			-- sitting beside a git sign should not be the one thing in the gutter that
			-- reads as a stray capital.
			--
			-- Geometric Unicode rather than Nerd Font glyphs, matching `diff.lua`'s `▎`
			-- and `explorer.lua`'s `◌`: these render in any font, and nothing here is
			-- worth a hard dependency on a patched one.
			--
			-- `DapStopped` also takes `linehl`: the stopped line is the one piece of state
			-- worth seeing without looking at the gutter at all.
			local signs = {
				DapBreakpoint          = { text = "●", texthl = "DiagnosticError", },
				DapBreakpointCondition = { text = "◆", texthl = "DiagnosticWarn", },
				DapBreakpointRejected  = { text = "○", texthl = "DiagnosticHint", },
				DapLogPoint            = { text = "◈", texthl = "DiagnosticInfo", },
				DapStopped             = { text = "▶", texthl = "DiagnosticOk", linehl = "Visual", },
			}

			for name, definition in pairs(signs) do
				vim.fn.sign_define(name, definition)
			end
		end,
	},

	{
		"igorlfs/nvim-dap-view",

		-- Loaded as a dependency of nvim-dap above, so these keys are the only reason it
		-- has a `keys` field at all: they make the view reachable without a session
		-- already running, which is what `<leader>xv` is for after an accidental close.
		keys = {
			{ "<leader>xv", "<cmd>DapViewToggle<cr>", desc = "Toggle the debug view", },
			{ "<leader>xw", "<cmd>DapViewWatch<cr>",  desc = "Watch expression",      mode = { "n", "v", }, },
			{ "<leader>xh", "<cmd>DapViewHover<cr>",  desc = "Hover expression",      mode = { "n", "v", }, },
		},

		---@module "dap-view"
		---@type dapview.Config
		opts = {
			-- Upstream defaults this to `false` and warns that the view never appears on
			-- its own -- you are expected to run `:DapViewOpen` yourself. That is a step
			-- with no decision in it: a debug session with no visible scopes is not a
			-- state worth being one keypress away from. `true` opens on session start and
			-- closes when the last session ends.
			auto_toggle = true,

			virtual_text = {
				-- Also off by default, and the reason this plugin won over nvim-dap-ui --
				-- see the header. Needs Neovim 0.12+ for `inline` virtual text, which this
				-- config already requires.
				enabled = true,
			},
		},
	},
}
