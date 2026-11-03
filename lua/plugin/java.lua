local packages = { "jdtls", "java-debug-adapter", "java-test", }

local function run_main()
	require("jdtls.dap").fetch_main_configs({ config_overrides = { noDebug = true, }, }, function(configs)
		if #configs == 0 then
			vim.notify("No Java main class found; wait for project import and check compilation errors.",
				vim.log.levels.WARN)
			return
		end

		vim.ui.select(configs, {
			prompt = "Java main class",
			format_item = function(config) return config.name end,
		}, function(config)
			if config then
				require("dap").run(config)
			end
		end)
	end)
end


local function enable()
	local registry = require("mason-registry")

	for _, name in ipairs(packages) do
		if not registry.is_installed(name) then
			return
		end
	end

	local mason       = require("mason.settings").current.install_root_dir
	local bundles     = vim.fn.glob(mason .. "/packages/java-debug-adapter/extension/server/*.jar", true, true)
	local gradle      = vim.fn.exepath("gradle")
	local gradle_home = vim.env.GRADLE_HOME
	local java21      = vim.env.JAVA_HOME_21
	local brew        = vim.fn.exepath("brew")

	if not java21 and brew ~= "" then
		local prefix = vim.fs.dirname(vim.fs.dirname(brew))

		for _, home in ipairs({
			prefix .. "/opt/openjdk@21/libexec",
			prefix .. "/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
		}) do
			if vim.fn.executable(home .. "/bin/javac") == 1 then
				java21 = home
				break
			end
		end
	end

	if not gradle_home and gradle ~= "" then
		local home = vim.fs.dirname(vim.fs.dirname(vim.fn.resolve(gradle)))

		for _, candidate in ipairs({ home, home .. "/libexec", }) do
			if #vim.fn.glob(candidate .. "/lib/gradle-launcher-*.jar", true, true) > 0 then
				gradle_home = candidate
				break
			end
		end
	end

	for _, jar in ipairs(vim.fn.glob(mason .. "/packages/java-test/extension/server/*.jar", true, true)) do
		local name = vim.fs.basename(jar)

		if name ~= "com.microsoft.java.test.runner-jar-with-dependencies.jar" and name ~= "jacocoagent.jar" then
			bundles[#bundles + 1] = jar
		end
	end

	require("jdtls").setup_dap({ hotcodereplace = "auto", })
	vim.lsp.config("jdtls", {
		-- Hash the full root: unrelated checkouts with the same name must not share an Eclipse index.
		cmd = function(dispatchers, config)
			local root      = config.root_dir or vim.fn.getcwd()
			local workspace = vim.fn.stdpath("data") .. "/jdtls/" .. vim.fn.sha256(root):sub(1, 16)

			vim.fn.mkdir(workspace, "p")
			local cmd = {
				"jdtls",
				"-data",
				workspace,
				"--jvm-arg=-javaagent:" .. mason .. "/share/jdtls/lombok.jar",
			}

			-- nvim-jdtls's log and index-recovery commands inspect the client's launch arguments.
			config.cmd = cmd
			return vim.lsp.rpc.start(cmd, dispatchers, { cwd = root, env = config.cmd_env, })
		end,
		init_options = { bundles = bundles, },
		before_init = function(params, config)
			-- Project import runs during initialize, before Neovim sends didChangeConfiguration.
			params.initializationOptions.settings = config.settings
		end,
		settings = {
			java = {
				signatureHelp = { enabled = true, },
				inlayHints = { parameterNames = { enabled = "all", }, },
				-- Used only without a project wrapper; Eclipse's fallback Gradle can lag the installed JDK.
				import = { gradle = { home = gradle_home, java = { home = java21, }, }, },
				configuration = {
					updateBuildConfiguration = "interactive",
					runtimes = java21 and { { name = "JavaSE-21", path = java21, }, } or {},
				},
			},
		},
	})
	vim.lsp.enable("jdtls")
end


return {
	"mfussenegger/nvim-jdtls",

	ft = "java",

	dependencies = {
		"mason-org/mason.nvim",
		"neovim/nvim-lspconfig",
		"mfussenegger/nvim-dap",
	},

	keys = {
		{ "<leader>jr", run_main,                                           ft = "java", desc = "Run Java main class", },
		{ "<leader>jo", function() require("jdtls").organize_imports() end, ft = "java", desc = "Organize imports", },
		{ "<leader>jb", "<cmd>JdtCompile<cr>",                              ft = "java", desc = "Compile Java workspace", },
		{
			"<leader>ju",
			function() require("jdtls").update_project_config() end,
			ft = "java",
			desc = "Reload Java build configuration",
		},
		{
			"<leader>jt",
			function() require("jdtls").test_class({ config = { noDebug = true, }, }) end,
			ft = "java",
			desc = "Run Java test class",
		},
		{
			"<leader>jT",
			function() require("jdtls").test_class() end,
			ft = "java",
			desc = "Debug Java test class",
		},
		{
			"<leader>jn",
			function() require("jdtls").test_nearest_method({ config = { noDebug = true, }, }) end,
			ft = "java",
			desc = "Run nearest Java test",
		},
		{
			"<leader>jN",
			function() require("jdtls").test_nearest_method() end,
			ft = "java",
			desc = "Debug nearest Java test",
		},
	},

	config = function()
		local registry = require("mason-registry")

		if vim.iter(packages):all(registry.is_installed) then
			enable()
			return
		end

		registry.refresh(vim.schedule_wrap(function(success)
			if not success then
				vim.notify("Java tools: Mason registry refresh failed. Check :MasonLog.", vim.log.levels.ERROR)
				return
			end

			for _, name in ipairs(packages) do
				local package = registry.get_package(name)

				if not package:is_installed() then
					package:once("install:success", vim.schedule_wrap(enable))
					package:once("install:failed", vim.schedule_wrap(function()
						vim.notify("Failed to install " .. name .. ". Check :MasonLog, then reopen Java.",
							vim.log.levels.ERROR)
					end))
					if not package:is_installing() then
						vim.notify("Installing Java tool: " .. name)
						package:install()
					end
				end
			end
			enable()
		end))
	end,
}
