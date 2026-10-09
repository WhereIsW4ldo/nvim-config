#Requires -Version 5.1
<#
.SYNOPSIS
	Install everything this Neovim config needs, on Windows.

.DESCRIPTION
	The Windows counterpart of install.sh. Same tables, same idempotence: tools that already
	meet the minimum version are left alone, wherever they came from.

	Chocolatey stands in for Homebrew for most native tools. winget would be the obvious
	choice, but it is commonly disabled by Group Policy on managed machines. Python, npm,
	.NET and vendor-native installers are used where they are the supported route.
	Installing a Chocolatey package needs an elevated shell; -Check does not.

	The reasoning behind each dependency lives in install.sh -- this file only records what
	differs on Windows. Keep the two tables in step when adding a dependency.

	  .\install.ps1           install anything missing
	  .\install.ps1 -Check    report status only, change nothing (exit 1 if incomplete)

.PARAMETER Check
	Report status only; change nothing. Exits 1 if anything is missing.
#>
[CmdletBinding()]
param(
	[switch]$Check
)

$ErrorActionPreference = "Stop"

# ── Dependency tables ────────────────────────────────────────────────────────────
# Cmd     : command name, or an array of alternatives where any one will do
# Min     : minimum version, or $null for presence-only
# Package : Chocolatey package, or $null when there is none (see Manual)
# Probe   : scriptblock whose output contains the version
# Manual  : what to tell the user when there is no package
$ChocoDeps = @(
	@{ Cmd = "nvim";        Min = "0.12.0"; Package = "neovim";      Probe = { nvim --version | Select-Object -First 1 } }
	@{ Cmd = "git";         Min = "2.19.0"; Package = "git";         Probe = { git --version } }
	@{ Cmd = "node";        Min = "22.0.0"; Package = "nodejs-lts";  Probe = { node --version } }
	# The line ends in `git version=X`, so anchor on the field rather than the first number.
	@{ Cmd = "lazygit";     Min = "0.40.0"; Package = "lazygit";     Probe = { if ((lazygit --version) -match "(?:^|, )version=([\d.]+)") { $Matches[1] } } }
	@{ Cmd = "tree-sitter"; Min = "0.26.1"; Package = "tree-sitter"; Probe = { tree-sitter --version } }
	# Any compiler the `cc` crate can drive: MSVC's `cl`, or gcc/clang. mingw is the
	# lightest to install; Visual Studio Build Tools satisfies this just as well.
	@{ Cmd = @("cl", "gcc", "clang"); Min = $null; Package = "mingw" }
	@{ Cmd = "dotnet";      Min = "10.0.0"; Package = "dotnet-sdk";  Probe = { dotnet --version } }
	@{ Cmd = "cargo";       Min = $null;    Package = "rustup.install" }
	@{ Cmd = "terraform";   Min = $null;    Package = "terraform" }
	@{ Cmd = "rg";          Min = "12.0.0"; Package = "ripgrep";     Probe = { rg --version | Select-Object -First 1 } }
	# mason's toolchain. curl.exe and tar.exe (bsdtar) ship with Windows 10 1803+; 7-Zip
	# covers the unzip/gzip half, which Windows has no standalone binary for.
	@{ Cmd = "curl";        Min = $null;    Package = "curl" }
	@{ Cmd = "tar";         Min = $null;    Package = $null;         Manual = "ships with Windows 10 1803 and later -- update Windows" }
	@{ Cmd = "7z";          Min = $null;    Package = "7zip" }
	# Linters, for `lua/plugin/lint.lua`.
	@{ Cmd = "luacheck";    Min = $null;    Package = $null;         Manual = "no Chocolatey package -- put luacheck.exe from https://github.com/lunarmodules/luacheck/releases on PATH" }
	@{ Cmd = "tflint";      Min = $null;    Package = "tflint" }
	@{ Cmd = "hadolint";    Min = $null;    Package = "hadolint" }
	@{ Cmd = "shellcheck";  Min = $null;    Package = "shellcheck" }
	# Only for sqlfluff below. The Microsoft Store stub `python.exe` is on PATH by default
	# and prints no version, so a version floor is what tells it apart from a real Python.
	@{ Cmd = "python";      Min = "3.9.0";  Package = "python";      Probe = { python --version } }
)

# sqlfluff is a brew formula on Linux; on Windows pip is the only route.
$PipDeps = @(
	@{ Cmd = "sqlfluff"; Spec = "sqlfluff" }
)

# Pinned for the same supply-chain reason as in install.sh.
$NpmDeps = @(
	@{ Cmd = "prettierd";                   Spec = "@fsouza/prettierd@0.29.0" }
	@{ Cmd = "eslint_d";                    Spec = "eslint_d@15.0.3" }
	@{ Cmd = "markdownlint-cli2";           Spec = "markdownlint-cli2@0.23.2" }
	@{ Cmd = "vscode-html-language-server"; Spec = "vscode-langservers-extracted@4.10.0" }
)

$DotnetToolDeps = @(
	@{ Cmd = "dotnet-easydotnet"; Package = "EasyDotnet" }
)

# ── Output helpers ───────────────────────────────────────────────────────────────
function Ok([string]$Msg)      { Write-Host "  $([char]0x2713) " -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Warn([string]$Msg)    { Write-Host "  ! " -ForegroundColor Yellow -NoNewline; Write-Host $Msg }
function Bad([string]$Msg)     { Write-Host "  $([char]0x2717) " -ForegroundColor Red -NoNewline; Write-Host $Msg }
function Heading([string]$Msg) { Write-Host ""; Write-Host $Msg -ForegroundColor White }
function Die([string]$Msg)     { Write-Host ""; Write-Host "error: " -ForegroundColor Red -NoNewline; Write-Host $Msg; exit 1 }


# -CommandType Application keeps Windows PowerShell's `curl` alias from counting as curl.
function Find-Command([string[]]$Names) {
	foreach ($name in $Names) {
		$found = Get-Command $name -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
			Select-Object -First 1
		if ($found) { return $found }
	}
	return $null
}


function Get-ProbedVersion([scriptblock]$Probe) {
	$global:LASTEXITCODE = 0
	try {
		$out = (& $Probe 2>&1 | Out-String)
	} catch {
		Warn "version probe failed: $($_.Exception.Message)"
		return $null
	}
	if ($LASTEXITCODE -ne 0) {
		Warn "version probe failed (exit $LASTEXITCODE): $($out.Trim())"
		return $null
	}
	if ($out -match "(\d+(?:\.\d+){1,3})") { return $Matches[1] }
	Warn "version probe returned no version: $($out.Trim())"
	return $null
}


function Test-VersionGe([string]$Current, [string]$Min) {
	try {
		return [version]$Current -ge [version]$Min
	} catch {
		return $false
	}
}


function Test-Admin {
	$id = [Security.Principal.WindowsIdentity]::GetCurrent()
	return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
		[Security.Principal.WindowsBuiltInRole]::Administrator)
}


# Installers write PATH to the registry; this session only sees it after a reload.
function Update-SessionPath {
	$machine  = [Environment]::GetEnvironmentVariable("Path", "Machine")
	$user     = [Environment]::GetEnvironmentVariable("Path", "User")
	$env:Path = "$machine;$user"
}


function Install-ChocoPackage([string]$Package) {
	if (-not (Find-Command "choco")) { Die "Chocolatey is required to install $Package" }
	if (-not (Test-Admin)) { Die "installing $Package needs an elevated PowerShell -- re-run as Administrator" }
	# upgrade also installs missing packages; install alone leaves old versions untouched.
	choco upgrade $Package -y --no-progress
	# 3010 and 1641 are "succeeded, reboot required".
	if ($LASTEXITCODE -notin 0, 1641, 3010) { Die "choco upgrade $Package failed (exit $LASTEXITCODE)" }
	Update-SessionPath
}


function Install-NpmPackage([string]$Spec) {
	if (-not (Find-Command "npm")) { Die "npm is required to install $Spec" }

	$previousOptions = $env:NODE_OPTIONS
	try {
		$help = node --help | Out-String
		if ($LASTEXITCODE -ne 0) { Die "node --help failed while checking certificate-store support" }
		# Managed Windows machines often trust a corporate CA that Node's bundled roots lack.
		if ($help -match "(?m)^\s+--use-system-ca\b") {
			$env:NODE_OPTIONS = "$previousOptions --use-system-ca".Trim()
		} else {
			Warn "Node lacks --use-system-ca; for corporate certificates, update Node or set NODE_EXTRA_CA_CERTS to an IT-provided PEM CA bundle"
		}

		npm install -g $Spec
		if ($LASTEXITCODE -ne 0) {
			Die "npm install -g $Spec failed (exit $LASTEXITCODE). For certificate errors, ensure the corporate CA is trusted by Windows or set NODE_EXTRA_CA_CERTS to an IT-provided PEM CA bundle; see README.md. Do not disable TLS verification."
		}
	} finally {
		$env:NODE_OPTIONS = $previousOptions
	}
}


function Install-ClaudeCode {
	# Anthropic's supported Windows installer:
	# https://github.com/anthropics/claude-code#install-claude-code
	Invoke-Expression (Invoke-RestMethod "https://claude.ai/install.ps1")
	Update-SessionPath
}


$Missing = 0
$Manual  = @()

# ── Sanity: are we in the config repo? ───────────────────────────────────────────
Set-Location $PSScriptRoot
if (-not ((Test-Path "init.lua") -and (Test-Path "lua\config" -PathType Container))) {
	Die "run this from the nvim config repo root"
}

# ── Platform ─────────────────────────────────────────────────────────────────────
Heading "Platform"
if ($PSVersionTable.PSEdition -eq "Core" -and -not $IsWindows) {
	Die "this script is for Windows -- use ./install.sh on Linux and macOS"
}
Ok "Windows (PowerShell $($PSVersionTable.PSVersion))"

# ── Chocolatey ───────────────────────────────────────────────────────────────────
Heading "Chocolatey"
if (Find-Command "choco") {
	Ok "already installed ($((Find-Command "choco").Source))"
} elseif ($Check) {
	Bad "not installed"
	$Missing++
} else {
	if (-not (Test-Admin)) { Die "installing Chocolatey needs an elevated PowerShell -- re-run as Administrator" }
	Warn "not found -- installing"
	# The official installer, as documented at https://chocolatey.org/install.
	Set-ExecutionPolicy Bypass -Scope Process -Force
	[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
	Invoke-Expression ((New-Object Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))
	Update-SessionPath
	if (-not (Find-Command "choco")) { Die "Chocolatey installed but choco is not on PATH" }
	Ok "installed"
}

# ── Tools ────────────────────────────────────────────────────────────────────────
Heading "Tools"
foreach ($dep in $ChocoDeps) {
	$label = ($dep.Cmd -join "/")
	$found = Find-Command $dep.Cmd

	if ($found) {
		if (-not $dep.Min) {
			Ok "$label present ($($found.Source))"
			continue
		}
		$current = Get-ProbedVersion $dep.Probe
		if (Test-VersionGe $current $dep.Min) {
			Ok "$label $current (>= $($dep.Min))"
			continue
		}
		if ($current) {
			Warn "$label $current is older than $($dep.Min)"
		} else {
			Warn "$label version could not be determined ($($found.Source))"
		}
	} else {
		Warn "$label not found"
	}

	if (-not $dep.Package) {
		Bad "$label -- $($dep.Manual)"
		$Missing++
		$Manual += "${label}: $($dep.Manual)"
		continue
	}

	if ($Check) {
		Bad "$label needs installing (choco package: $($dep.Package))"
		$Missing++
		continue
	}

	Install-ChocoPackage $dep.Package

	$found = Find-Command $dep.Cmd
	if (-not $found) { Die "$label still not on PATH after installing $($dep.Package)" }
	if (-not $dep.Min) {
		Ok "$label installed"
		continue
	}
	$current = Get-ProbedVersion $dep.Probe
	if (-not $current) {
		Die "$label version could not be determined after install ($($found.Source)). Check Get-Command $(@($dep.Cmd)[0]) -All for a shadowing or incompatible executable."
	}
	if (-not (Test-VersionGe $current $dep.Min)) {
		Die "$label is $current after install, still below $($dep.Min) ($($found.Source)). Check PATH precedence with Get-Command $(@($dep.Cmd)[0]) -All."
	}
	Ok "$label $current installed"
}

# ── Python packages ──────────────────────────────────────────────────────────────
Heading "Python packages"
foreach ($dep in $PipDeps) {
	$found = Find-Command $dep.Cmd
	if ($found) {
		Ok "$($dep.Cmd) present ($($found.Source))"
		continue
	}

	if ($Check) {
		Bad "$($dep.Cmd) missing -- python -m pip install $($dep.Spec)"
		$Missing++
		continue
	}

	python -m pip install $dep.Spec
	if ($LASTEXITCODE -ne 0) { Die "pip install $($dep.Spec) failed" }
	Update-SessionPath

	if (Find-Command $dep.Cmd) {
		Ok "$($dep.Cmd) installed"
	} else {
		Warn "$($dep.Cmd) installed but not on PATH -- add Python's Scripts directory to PATH"
	}
}

# ── Global npm packages ──────────────────────────────────────────────────────────
Heading "Node packages"
foreach ($dep in $NpmDeps) {
	$found = Find-Command $dep.Cmd
	if ($found) {
		Ok "$($dep.Cmd) present ($($found.Source))"
		continue
	}

	if ($Check) {
		Bad "$($dep.Cmd) missing -- npm i -g $($dep.Spec)"
		$Missing++
		continue
	}

	Install-NpmPackage $dep.Spec

	if (-not (Find-Command $dep.Cmd)) { Die "$($dep.Cmd) still not on PATH after installing $($dep.Spec)" }
	Ok "$($dep.Cmd) installed"
}

# ── Claude Code ─────────────────────────────────────────────────────────────────
Heading "Claude Code"
$claude = Find-Command "claude"
if ($claude) {
	Ok "claude present ($($claude.Source))"
} elseif ($Check) {
	Bad "claude missing -- irm https://claude.ai/install.ps1 | iex"
	$Missing++
} else {
	Install-ClaudeCode
	$claude = Find-Command "claude"
	if (-not $claude) {
		Die "Claude Code installed but claude is not on PATH -- restart PowerShell and run claude doctor"
	}
	Ok "claude installed ($($claude.Source))"
}

# ── .NET global tools ────────────────────────────────────────────────────────────
Heading ".NET tools"

$DotnetToolsDir = if ($env:DOTNET_TOOLS_DIR) { $env:DOTNET_TOOLS_DIR } else { Join-Path $HOME ".dotnet\tools" }
$onPath = ($env:Path -split ";") | Where-Object { $_.TrimEnd("\") -ieq $DotnetToolsDir.TrimEnd("\") }
if ($onPath) {
	Ok "$DotnetToolsDir is on PATH"
} else {
	Warn "$DotnetToolsDir is not on PATH -- add it to your user PATH"
}

foreach ($dep in $DotnetToolDeps) {
	$found = Find-Command $dep.Cmd
	if ($found) {
		Ok "$($dep.Cmd) present ($($found.Source))"
		continue
	}

	if ($Check) {
		Bad "$($dep.Cmd) missing -- dotnet tool install -g $($dep.Package)"
		$Missing++
		continue
	}

	if (-not (Find-Command "dotnet")) { Die "the .NET SDK is required to install $($dep.Package)" }
	dotnet tool install -g $dep.Package
	if ($LASTEXITCODE -ne 0) { Die "dotnet tool install -g $($dep.Package) failed" }

	if (Find-Command $dep.Cmd) {
		Ok "$($dep.Cmd) installed"
	} elseif (Test-Path (Join-Path $DotnetToolsDir "$($dep.Cmd).exe")) {
		Warn "$($dep.Cmd) installed to $DotnetToolsDir but not on PATH -- Neovim will not find it"
	} else {
		Die "$($dep.Cmd) still not found after installing $($dep.Package)"
	}
}

# ── Tool configuration ───────────────────────────────────────────────────────────
# See install.sh for why this file must exist. sqlfluff checks ~/.config/sqlfluff before
# any platform directory, on Windows too, so the path is the same as on Linux.
$SqlfluffConfig = Join-Path $HOME ".config\sqlfluff\.sqlfluff"

Heading "Tool configuration"

if (Test-Path $SqlfluffConfig) {
	$content     = Get-Content $SqlfluffConfig -Raw
	$missingKeys = @("dialect", "exclude_rules", "tab_space_size") |
		Where-Object { $content -notmatch "(?m)^\s*$_\s*=" }

	if ($missingKeys) {
		Warn "sqlfluff config does not set: $($missingKeys -join ' ')"
		Warn "left untouched at $SqlfluffConfig -- see README.md for what is expected"
	} else {
		Ok "sqlfluff configured ($SqlfluffConfig)"
	}
} elseif ($Check) {
	Bad "sqlfluff config missing -- $SqlfluffConfig"
	$Missing++
} else {
	New-Item -ItemType Directory -Force -Path (Split-Path $SqlfluffConfig) | Out-Null

	$sqlfluffText = @'
# Machine-wide sqlfluff defaults. Written by install.ps1 in the nvim config; read by
# nvim-lint (lua/plugin/lint.lua) and by conform (lua/plugin/format.lua), which
# formats SQL with `sqlfluff fix` now that the `sqls` language server is retired.
#
# sqlfluff has no default dialect -- it sets `dialect = None` and then requires one,
# so without this every SQL buffer fails to lint at all rather than linting loosely.
#
# `tsql` is MS SQL Server (there is no `mssql` identifier). A project that uses
# something else overrides this with its own `.sqlfluff` in the repo root; the
# nearest config wins, so a personal Postgres project needs:
#
#     [sqlfluff]
#     dialect = postgres
#
[sqlfluff]
dialect = tsql

# AM04 -- "query produces an unknown number of result columns" -- fires on `SELECT *`
# and is unfixable by definition, since sqlfluff cannot know the columns. A fair rule
# for a checked-in query and pure noise for ad-hoc querying, where `SELECT *` is the
# point. Excluding it also removes the violation that most often made `sqlfluff fix`
# exit non-zero -- see lua/plugin/format.lua for why that mattered.
exclude_rules = AM04

# Two-space indentation, deliberately non-default -- sqlfluff ships 4. This governs
# both the LT02 rule that reports indentation and the `sqlfluff fix` that conform
# runs to format, so the formatter and the linter agree by construction rather than
# by luck.
[sqlfluff:indentation]
tab_space_size = 2
'@

	# No BOM: Windows PowerShell's UTF8 encoding adds one, which breaks the ini parser.
	[IO.File]::WriteAllText($SqlfluffConfig, ($sqlfluffText -replace "`r`n", "`n") + "`n",
		(New-Object Text.UTF8Encoding $false))

	Ok "sqlfluff configured ($SqlfluffConfig)"
}

# ── Verify ───────────────────────────────────────────────────────────────────────
Heading "Verifying the config"
if ($Check) {
	if ($Missing -gt 0) {
		$noun = if ($Missing -eq 1) { "dependency" } else { "dependencies" }
		Write-Host ""
		Write-Host "$Missing $noun missing." -ForegroundColor Yellow -NoNewline
		Write-Host " Run .\install.ps1 to fix."
		exit 1
	}
	Ok "all dependencies satisfied"
	exit 0
}

# First run clones plugins, so this can take a moment.
nvim --headless "+qa" 2>&1 | Select-Object -Last 5 | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { Die "config failed to load -- see output above" }
Ok "config loads cleanly"

$count = nvim --headless '+lua io.write(#require("lazy").plugins())' "+qa" 2>$null
if (-not $count) { $count = "?" }
Ok "lazy.nvim reports $count plugin(s)"

if ($Manual) {
	Heading "Needs a manual install"
	foreach ($line in $Manual) { Warn $line }
}

Write-Host ""
Write-Host "Done." -ForegroundColor White -NoNewline
Write-Host " Next:"
Write-Host "  - open nvim and check :Lazy"
