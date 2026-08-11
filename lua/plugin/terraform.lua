-- Terraform, which needs one setting to stay usable in an initialised workspace.
--
-- `terraform-ls` indexes every module it can reach under the workspace root, and after a
-- `terraform init` that root contains `.terraform/modules` -- the vendored copy of every
-- module the configuration pulls in. In this machine's work repos that is ~20k `.tf` files,
-- and the server handles RPC serially, so the indexing jobs starve every request behind
-- them. Measured in `Communication-Product/product`, before and after:
--
--   textDocument/references     4279ms  ->   152ms
--   textDocument/codeLens      >30000ms ->   895ms   (never answered at all before)
--
-- The old behaviour was not merely slow. `codeLens` timed out permanently, and because
-- `lsp/terraformls.lua` upstream turns code lenses on in its `on_attach`, Neovim re-asked on
-- every buffer enter and every change -- 125 doomed requests in one session, each one more
-- queue in front of the next real question. This is the same starvation that made
-- format-on-save time out, which `lua/plugin/format.lua` solved from the other end by
-- taking formatting off the server entirely.
--
-- What this does NOT cost, all verified against that repo rather than assumed: resource
-- attribute completion, resource type completion, hover, and document symbols are
-- byte-identical with and without the setting. Provider schemas come from the server's own
-- schema store and `.terraform/providers`, neither of which is the module walker's business
-- -- and `.terraform/providers` is 1.4 GB of that 1.5 GB directory, so this excludes far
-- less than its size suggests. Modules under `./modules/` stay indexed, being in the repo
-- rather than in the cache.
--
-- The one thing genuinely lost is completion and go-to-definition for the *inputs* of a
-- vendored remote module. That already did not work here: hover on a module input returns
-- `unknown attribute "deployment_info"` with the full index in place, because these modules
-- are `git::` sources rather than registry ones. On a registry-sourced module it may be a
-- real regression -- `indexing.ignorePaths` is the knob to reach for if so.
--
-- Note that `indexing.ignoreDirectoryNames` is NOT the setting for this, though it reads
-- like it. `terraform-ls` rejects `.terraform` there by name -- `cannot ignore directory
-- ".terraform"`, error -32098 -- and then fails to initialise, leaving no client at all.
-- `ignorePaths` takes the same value happily and resolves it against the workspace root, so
-- the relative form here needs no per-project absolute path.
--
-- The spec targets nvim-lspconfig for the reason `lua/plugin/typescript.lua` spells out:
-- lazy.nvim merges specs for one repo, but a function field is not merged -- the last
-- definition silently wins. `lsp.lua` owns `init` and `typescript.lua` owns `config`, so
-- both hooks on that plugin are already taken and a third file cannot have either. Hanging
-- this off mason-lspconfig instead sidesteps the collision: `lsp.lua` gives that plugin only
-- `opts`, leaving `init` free. `vim.lsp.config` is core and cares about nothing except
-- running before the first terraform buffer gets a client, which `init` comfortably does.
return {
	"mason-org/mason-lspconfig.nvim",

	init = function()
		vim.lsp.config("terraformls", {
			-- `init_options`, not `settings`: terraform-ls does not implement
			-- `workspace/didChangeConfiguration`, so settings have to arrive as part of the
			-- `initialize` call or not at all.
			init_options = {
				indexing = {
					ignorePaths = { ".terraform", },
				},
			},

			-- Upstream's `lsp/terraformls.lua` does exactly one thing in its own
			-- `on_attach`: `vim.lsp.codelens.enable(true, ...)`. `vim.lsp.config` merges
			-- with `force`, so defining the field here replaces that call rather than
			-- running after it -- which is the whole point, and why this is written as a
			-- disable rather than as an empty function. An empty function would read as an
			-- oversight and would silently swallow anything upstream adds to `on_attach`
			-- later; `enable(false)` says what it means and stays correct either way.
			--
			-- What is given up is the module reference count above a `module` block. What is
			-- bought is every code lens request the server never has to serialise: those
			-- refresh on buffer enter, cursor hold, insert leave and change, so a short
			-- burst of ordinary editing sent 7 of them, ~1s of server time each even with
			-- `.terraform` excluded -- and before that exclusion they never completed at all
			-- (see the header). Nothing else here asks for code lenses, so this is the only
			-- filetype affected.
			on_attach = function(_, bufnr)
				vim.lsp.codelens.enable(false, { bufnr = bufnr, })
			end,
		})
	end,
}
