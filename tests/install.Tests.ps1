#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$installer = Join-Path (Split-Path $PSScriptRoot) "install.ps1"
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors | Out-String) }

# Load only the dependency table and helpers, never the installer entry point.
$functions = $ast.FindAll({
	param($node)
	$node -is [Management.Automation.Language.FunctionDefinitionAst]
}, $false)
foreach ($function in $functions) {
	Invoke-Expression $function.Extent.Text
}
$table = $ast.Find({
	param($node)
	$node -is [Management.Automation.Language.AssignmentStatementAst] -and
	$node.Left.Extent.Text -eq '$ChocoDeps'
}, $false)
Invoke-Expression $table.Extent.Text

function Assert-Equal($Actual, $Expected, [string]$Label) {
	if ($Actual -ne $Expected) { throw "${Label}: expected '$Expected', got '$Actual'" }
	Write-Host "PASS: $Label"
}

Assert-Equal @($ChocoDeps | Where-Object { $_.Cmd -eq "sqlcmd" }).Count 0 `
	"sqlcmd is not a required Windows dependency"
$unixInstaller = Get-Content (Join-Path (Split-Path $PSScriptRoot) "install.sh") -Raw
Assert-Equal ($unixInstaller -match '(?m)^\s*"sqlcmd\|') $false `
	"sqlcmd is not a required Unix dependency"
$windowsInstaller = Get-Content $installer -Raw
Assert-Equal ($windowsInstaller -match [regex]::Escape('Invoke-RestMethod "https://claude.ai/install.ps1"')) $true `
	"Windows installer uses Anthropic's native Claude Code installer"
Assert-Equal ($windowsInstaller -match 'Bad "claude missing -- irm https://claude.ai/install.ps1 \| iex"') $true `
	"check mode reports the missing Claude Code CLI"

# Synthetic dependency for exercising version detection and the installer loop.
$sqlcmdDep = @{ Cmd = "sqlcmd"; Min = "1.5.0"; Package = "sqlcmd"; Probe = { sqlcmd --version } }
function sqlcmd {
	Assert-Equal ($args -join " ") "--version" "sqlcmd version arguments"
	"Microsoft (R) SQL Server Command Line Tool"
	""
	"Version: v1.6.0"
	""
	"Legal docs and information: aka.ms/SqlcmdLegal"
	"Third party notices: aka.ms/SqlcmdNotices"
}

Assert-Equal (Get-ProbedVersion { sqlcmd --version | Select-Object -First 1 }) $null `
	"original first-line probe reproduces failure"
$current = Get-ProbedVersion $sqlcmdDep.Probe
Assert-Equal $current "1.6.0" "sqlcmd version after banner"
Assert-Equal (Test-VersionGe $current $sqlcmdDep.Min) $true "installed sqlcmd meets minimum"
Assert-Equal (Test-VersionGe "1.4.0" $sqlcmdDep.Min) $false "outdated sqlcmd fails minimum"
Assert-Equal (Test-VersionGe "1.5.0" $sqlcmdDep.Min) $true "exact minimum passes"
Assert-Equal (Get-ProbedVersion { "v0.12.5" }) "0.12.5" "single-line version unchanged"
Assert-Equal (Get-ProbedVersion { "" }) $null "empty probe is not version zero"
Assert-Equal (Get-ProbedVersion { throw "probe failed" }) $null "probe exception is not version zero"
Assert-Equal (Get-ProbedVersion { & $env:ComSpec /c "echo 9.9.9 & exit /b 2" }) $null `
	"failed native command cannot satisfy minimum"
Assert-Equal (Get-ProbedVersion { & $env:ComSpec /c "echo 1.6.0" }) "1.6.0" `
	"successful native probe after failure"

function sqlcmd { throw "Sqlcmd: '--version': Unknown Option. (legacy ODBC tool)" }
Assert-Equal (Get-ProbedVersion $sqlcmdDep.Probe) $null "legacy sqlcmd rejected"

$script:chocoCalls = @()
$script:chocoExit = 0
$script:pathRefreshes = 0
$script:isAdmin = $true
$script:hasChoco = $true
function Find-Command {
	if ($script:hasChoco) { return [pscustomobject]@{ Source = "choco.exe" } }
	return $null
}
function Test-Admin { return $script:isAdmin }
function Update-SessionPath { $script:pathRefreshes++ }
function Die([string]$Msg) { throw $Msg }
function choco {
	$script:chocoCalls += ($args -join " ")
	$global:LASTEXITCODE = $script:chocoExit
}

Install-ChocoPackage "sqlcmd"
Assert-Equal $script:chocoCalls[0] "upgrade sqlcmd -y --no-progress" `
	"upgrade installs missing packages and updates outdated ones"
Assert-Equal $script:pathRefreshes 1 "PATH refreshed after package success"
foreach ($code in 1641, 3010) {
	$script:chocoExit = $code
	Install-ChocoPackage "sqlcmd"
}
Assert-Equal $script:pathRefreshes 3 "reboot-required success codes accepted"

$script:chocoExit = 1
$message = $null
try { Install-ChocoPackage "sqlcmd" } catch { $message = $_.Exception.Message }
Assert-Equal $message "choco upgrade sqlcmd failed (exit 1)" "Chocolatey failure reported"
Assert-Equal $script:pathRefreshes 3 "PATH not refreshed after package failure"

$script:isAdmin = $false
$message = $null
try { Install-ChocoPackage "sqlcmd" } catch { $message = $_.Exception.Message }
Assert-Equal $message "installing sqlcmd needs an elevated PowerShell -- re-run as Administrator" `
	"installation still requires elevation"
Assert-Equal $script:chocoCalls.Count 4 "no Chocolatey call without elevation"

$script:hasChoco = $false
$message = $null
try { Install-ChocoPackage "sqlcmd" } catch { $message = $_.Exception.Message }
Assert-Equal $message "Chocolatey is required to install sqlcmd" "missing Chocolatey reported"

$toolsLoop = $ast.Find({
	param($node)
	$node -is [Management.Automation.Language.ForEachStatementAst] -and
	$node.Condition.Extent.Text -eq '$ChocoDeps'
}, $false)
$ChocoDeps = @($sqlcmdDep)
$Check = $true
$Missing = 0
$Manual = @()
$script:hasChoco = $true
$script:isAdmin = $true
$script:chocoExit = 0
$script:sqlcmdVersion = "1.6.0"
function sqlcmd {
	"Microsoft (R) SQL Server Command Line Tool"
	""
	"Version: v$script:sqlcmdVersion"
}

Invoke-Expression $toolsLoop.Extent.Text
Assert-Equal $Missing 0 "check mode accepts banner-prefixed installed sqlcmd"
Assert-Equal $script:chocoCalls.Count 4 "check mode never invokes Chocolatey"

$Check = $false
Invoke-Expression $toolsLoop.Extent.Text
Assert-Equal $script:chocoCalls.Count 4 "install mode leaves compliant sqlcmd untouched"

$Check = $true
$script:sqlcmdVersion = "1.4.0"
Invoke-Expression $toolsLoop.Extent.Text
Assert-Equal $Missing 1 "check mode reports outdated sqlcmd"
Assert-Equal $script:chocoCalls.Count 4 "outdated check mode still makes no changes"

function choco {
	$script:chocoCalls += ($args -join " ")
	$script:sqlcmdVersion = "1.6.0"
	$global:LASTEXITCODE = 0
}
$Check = $false
Invoke-Expression $toolsLoop.Extent.Text
Assert-Equal $script:chocoCalls.Count 5 "outdated sqlcmd upgraded once"
Assert-Equal $script:sqlcmdVersion "1.6.0" "post-upgrade version verified"

$npmLoop = $ast.Find({
	param($node)
	$node -is [Management.Automation.Language.ForEachStatementAst] -and
	$node.Condition.Extent.Text -eq '$NpmDeps'
}, $false)
$originalOptions = $env:NODE_OPTIONS
$originalExtraCa = $env:NODE_EXTRA_CA_CERTS
$script:npmCalls = @()
$script:npmExit = 0
$script:nodeExit = 0
$script:nodeSystemCa = $true
$script:npmPresent = $true
$script:packagePresent = $false
function Find-Command([string[]]$Names) {
	if (($Names -contains "npm" -and $script:npmPresent) -or
		($Names -contains "test-formatter" -and $script:packagePresent)) {
		return [pscustomobject]@{ Source = "$($Names[0]).cmd" }
	}
	return $null
}
function node {
	Assert-Equal ($args -join " ") "--help" "Node capability probe arguments"
	$global:LASTEXITCODE = $script:nodeExit
	if ($script:nodeSystemCa) { "  --use-system-ca             use system's CA store" }
	else { "  --use-openssl-ca           use OpenSSL's CA store" }
}
function npm {
	$script:npmCalls += [pscustomobject]@{
		Arguments = $args -join " "
		Options = $env:NODE_OPTIONS
		ExtraCa = $env:NODE_EXTRA_CA_CERTS
	}
	$script:packagePresent = $script:npmExit -eq 0
	$global:LASTEXITCODE = $script:npmExit
}

try {
	$env:NODE_OPTIONS = "--max-old-space-size=4096"
	$env:NODE_EXTRA_CA_CERTS = "C:\certs\approved-ca.pem"
	Install-NpmPackage "@fsouza/prettierd@0.29.0"
	Assert-Equal $script:npmCalls[0].Arguments "install -g @fsouza/prettierd@0.29.0" "npm package pin preserved"
	Assert-Equal $script:npmCalls[0].Options "--max-old-space-size=4096 --use-system-ca" `
		"Windows trust added without replacing existing Node options"
	Assert-Equal $script:npmCalls[0].ExtraCa "C:\certs\approved-ca.pem" "extra CA configuration preserved"
	Assert-Equal $env:NODE_OPTIONS "--max-old-space-size=4096" "Node options restored after success"

	$env:NODE_OPTIONS = $null
	Install-NpmPackage "test-package@1.0.0"
	Assert-Equal $script:npmCalls[1].Options "--use-system-ca" "Windows trust works with no existing options"
	Assert-Equal ([string]$env:NODE_OPTIONS) "" "unset Node options restored"

	$env:NODE_OPTIONS = "--max-old-space-size=4096"
	$script:nodeSystemCa = $false
	Install-NpmPackage "test-package@1.0.0"
	Assert-Equal $script:npmCalls[2].Options "--max-old-space-size=4096" "older Node receives no unsupported flag"

	$script:nodeSystemCa = $true
	$script:npmExit = 1
	$message = $null
	try { Install-NpmPackage "test-package@1.0.0" } catch { $message = $_.Exception.Message }
	Assert-Equal ($message -match "failed \(exit 1\).*NODE_EXTRA_CA_CERTS.*Do not disable TLS") $true `
		"npm failure includes safe certificate remediation"
	Assert-Equal $env:NODE_OPTIONS "--max-old-space-size=4096" "Node options restored after npm failure"

	$script:nodeExit = 1
	$message = $null
	try { Install-NpmPackage "test-package@1.0.0" } catch { $message = $_.Exception.Message }
	Assert-Equal $message "node --help failed while checking certificate-store support" "failed capability probe reported"
	Assert-Equal $script:npmCalls.Count 4 "npm not invoked after failed capability probe"
	$script:nodeExit = 0

	$script:npmPresent = $false
	$message = $null
	try { Install-NpmPackage "test-package@1.0.0" } catch { $message = $_.Exception.Message }
	Assert-Equal $message "npm is required to install test-package@1.0.0" "missing npm reported"
	$script:npmPresent = $true

	$NpmDeps = @(@{ Cmd = "test-formatter"; Spec = "test-package@1.0.0" })
	$Check = $true
	$Missing = 0
	$script:packagePresent = $false
	Invoke-Expression $npmLoop.Extent.Text
	Assert-Equal $Missing 1 "check mode reports missing npm packages"
	Assert-Equal $script:npmCalls.Count 4 "check mode does not invoke npm"
	Assert-Equal $env:NODE_OPTIONS "--max-old-space-size=4096" "check mode leaves Node options unchanged"

	$Check = $false
	$script:npmExit = 0
	Invoke-Expression $npmLoop.Extent.Text
	Assert-Equal $script:npmCalls.Count 5 "npm loop uses certificate-aware helper"
	Assert-Equal $script:npmCalls[4].Options "--max-old-space-size=4096 --use-system-ca" "npm loop enables Windows trust"
	Invoke-Expression $npmLoop.Extent.Text
	Assert-Equal $script:npmCalls.Count 5 "installed npm packages left untouched"
} finally {
	$env:NODE_OPTIONS = $originalOptions
	$env:NODE_EXTRA_CA_CERTS = $originalExtraCa
}
Write-Host "All installer regression checks passed."
