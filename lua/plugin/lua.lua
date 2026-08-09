-- Lua-specific LSP support, split out of `lua/plugin/lsp.lua` to keep that file generic
-- and under its length limit.
return {
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
}
