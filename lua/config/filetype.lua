-- Filetype detection Neovim does not ship. Core `vim.filetype.add`, no plugin involved,
-- which is what puts it here rather than in `lua/plugin/`.

-- Docker Compose. `docker_language_server` covers Dockerfile, Compose and Bake from one
-- binary, but it only attaches to Compose on the `yaml.docker-compose` filetype -- and
-- Neovim has no detection for it, so without this every `compose.yaml` arrives as plain
-- `yaml` and the server stays silent. The Dockerfile half works out of the box.
--
-- Dotted filetypes are a Vim feature rather than a workaround: FileType autocommands fire
-- once per component, so a `yaml.docker-compose` buffer still gets everything registered
-- for `yaml`, tree-sitter highlighting included.
--
-- These are Lua patterns and unanchored, so the `compose` forms match `docker-compose.yaml`
-- as a substring and cover both spellings Compose accepts. The second entry is for the
-- override and profile files -- `compose.override.yaml`, `docker-compose.prod.yml` --
-- which Compose reads the same way. A Compose file named anything else opens as `yaml`.
vim.filetype.add({
	pattern = {
		["[cC]ompose%.ya?ml"]     = "yaml.docker-compose",
		["[cC]ompose%..*%.ya?ml"] = "yaml.docker-compose",
	},
})
