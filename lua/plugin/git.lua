-- Git porcelain: review changes, manage branches and worktrees.
--
-- A Magit clone, replacing the `lazygit` TUI wrapper this file used to hold. That
-- wrapper's panels were plain terminal text -- no tree-sitter, no Neovim scrolling,
-- folds or search -- because they were lazygit's own screen, not a Neovim buffer.
-- Neogit's status, diff and log views are real Neovim buffers, so all of that works
-- for free, and `treesitter_diff_highlight` (on by default) highlights diff hunks with
-- the file's own syntax rather than plain +/- coloring.
--
-- Everything funnels through one buffer: `<leader>gg` opens status, and every other
-- action -- commit, log, branch, stash, push/pull, rebase, cherry-pick, worktree -- is
-- a single-letter popup from there (`c`, `l`, `b`, `Z`, `P`/`p`, `r`, `A`, `w`; `?` lists
-- them all). Nothing else needs its own top-level keymap.
--
-- Diffs are inline-only by design -- upstream calls this an explicit tradeoff and
-- offers `diffview.nvim` or `codediff.nvim` as an optional fuller diff viewer. Neither
-- is added here: the inline, tree-sitter-highlighted hunks already answer the
-- complaint about lazygit, and a second diff plugin is not worth the extra dependency
-- until inline is actually found lacking.
return {
	"NeogitOrg/neogit",

	dependencies = {
		"nvim-lua/plenary.nvim",
		"MunifTanjim/nui.nvim",
	},

	cmd = "Neogit",

	init = function()
		local group = vim.api.nvim_create_augroup("waldo_git_close", { clear = true, })

		local function is_git_view(buf)
			return vim.bo[buf].filetype:find("^Neogit") and vim.bo[buf].buftype == "nofile"
		end

		local function is_auxiliary(buf)
			local filetype = vim.bo[buf].filetype
			return is_git_view(buf) or (filetype:find("^snacks_") and filetype ~= "snacks_terminal")
		end

		vim.api.nvim_create_autocmd({ "WinClosed", "BufDelete", }, {
			group = group,
			desc  = "Close Git views when the last file is closed",
			callback = function(args)
				if args.event == "BufDelete" and is_auxiliary(args.buf) then
					return
				end

				-- Wait for window teardown / barbar's replacement buffer before checking.
				vim.schedule(function()
					local git_buffers = {}
					for _, win in ipairs(vim.api.nvim_list_wins()) do
						local buf = vim.api.nvim_win_get_buf(win)
						if is_git_view(buf) then
							git_buffers[buf] = win
						elseif args.event == "WinClosed"
							and vim.api.nvim_win_get_config(win).relative == "" and not is_auxiliary(buf) then
							return
						end
					end
					if next(git_buffers) == nil then
						return
					end

					if args.event == "BufDelete" then
						for _, buf in ipairs(vim.api.nvim_list_bufs()) do
							if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
								return
							end
							if vim.bo[buf].buftype == "terminal" and vim.api.nvim_buf_is_loaded(buf) then
								return
							end
							if (vim.bo[buf].buflisted or #vim.fn.win_findbuf(buf) > 0) and not is_auxiliary(buf) then
								-- :bdelete and BufferClose create an empty replacement.
								local empty = vim.bo[buf].buftype == ""
									and vim.api.nvim_buf_get_name(buf) == ""
									and vim.api.nvim_buf_line_count(buf) == 1
									and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
								if not empty then
									return
								end
							end
						end
					end

					-- Never force: hidden unsaved files must still block quitting.
					local ok, err = pcall(function()
						if args.event == "WinClosed" then
							vim.cmd("quitall")
						else
							for buf, win in pairs(git_buffers) do
								if vim.bo[buf].filetype == "NeogitStatus" then
									-- Clear Neogit's instance too, so pending refreshes stop.
									vim.api.nvim_win_call(win, function() require("neogit").close() end)
								elseif vim.api.nvim_buf_is_valid(buf) then
									vim.api.nvim_buf_delete(buf, { force = false, })
								end
							end
						end
					end)
					if not ok then
						local message = tostring(err):match("E%d+:.*") or tostring(err)
						vim.api.nvim_echo({ { message, "ErrorMsg", }, }, true, {})
					end
				end)
			end,
		})
	end,

	opts = {
		-- Upstream disables both by default, to keep the status buffer's own line
		-- prefixes (fold markers, section markers) uncluttered. `lua/config/vim.lua`
		-- turns both on globally for every other buffer, so leaving these at their
		-- default would make Neogit the one buffer in the editor without a gutter.
		disable_line_numbers          = false,
		disable_relative_line_numbers = false,
	},

	keys = {
		{ "<leader>gg", "<Cmd>Neogit<CR>",           desc = "Git: status", },
		{ "<leader>gf", "<Cmd>Neogit cwd=%:p:h<CR>", desc = "Git: status (current file's repo)", },
	},
}
