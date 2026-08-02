<#
.SYNOPSIS
    Provisions a Windows Sandbox into a working agent development workspace.

.DESCRIPTION
    Runs as the sandbox LogonCommand. Installs tooling via Scoop, installs the
    coding agents via npm, copies the read-only dotfiles into the sandbox user
    profile, fans the single global AGENTS.md out to every agent, and finally
    opens WezTerm running Herdr in C:\Workspace.

    Every step is idempotent: re-running it on an already-provisioned machine
    performs no installs and reports each step as already satisfied. This
    matters because the script is also useful to run by hand after editing the
    dotfiles on the host.

    Expects these sandbox mappings (see the generated .wsb):
        C:\Workspace   the one project,  read-write
        C:\Dotfiles    read-only
        C:\Bootstrap   read-only
        C:\Cache       package caches,   read-write
#>
[CmdletBinding()]
param(
    # Skip launching the terminal. Used when re-running bootstrap by hand.
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$DotfilesRoot = 'C:\Dotfiles'
$Workspace    = 'C:\Workspace'
$CacheRoot    = 'C:\Cache'

# Log into the mapped workspace so the log survives sandbox teardown and can be
# read from the host - a log written to the sandbox's own C:\ is unreachable
# while the sandbox runs and gone once it closes. .gitignore excludes it.
$LogFile = if (Test-Path $Workspace) {
    Join-Path $Workspace '.agentdev-bootstrap.log'
} else {
    'C:\bootstrap-log.txt'
}

# ---------------------------------------------------------------- logging ---

$script:StepNumber = 0

function Write-Log {
    param([string]$Message, [ConsoleColor]$Color = 'Gray')
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $line -Encoding utf8
}

function Write-Step {
    param([string]$Message)
    $script:StepNumber++
    Write-Log ''
    Write-Log ("=== {0}. {1}" -f $script:StepNumber, $Message) 'Cyan'
}

function Write-Ok   { param([string]$m) Write-Log "    OK   $m" 'Green' }
function Write-Skip { param([string]$m) Write-Log "    --   $m (already present)" 'DarkGray' }
function Write-Warn { param([string]$m) Write-Log "    WARN $m" 'Yellow' }

# Runs a provisioning action unless $Test already reports it satisfied. Failures
# are logged and swallowed: one unavailable package must not abort the whole
# bootstrap and leave the user staring at a bare sandbox.
function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [scriptblock]$Action
    )
    try {
        if (& $Test) { Write-Skip $Name; return $true }
    } catch {
        # A throwing test just means "not satisfied".
    }
    Write-Log "    ...  installing $Name"
    try {
        & $Action | Out-Null
        Write-Ok $Name
        return $true
    } catch {
        Write-Warn "$Name failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-Cmd {
    param([string]$Name)
    [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Scoop and the npm/agent installers all mutate PATH in the registry rather
# than in this process, so re-read it before each dependent step.
function Sync-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# ------------------------------------------------------------------ start ---

Set-Content -Path $LogFile -Value "Bootstrap started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding utf8
$stopwatch = [Diagnostics.Stopwatch]::StartNew()

Write-Log ''
Write-Log '  Windows Agent Workspace - sandbox bootstrap' 'White'
Write-Log "  workspace: $Workspace" 'White'

if (-not (Test-Path $DotfilesRoot)) { Write-Warn "no dotfiles mapped at $DotfilesRoot" }
if (-not (Test-Path $Workspace))    { Write-Warn "no workspace mapped at $Workspace" }

# --------------------------------------------------------- 1. environment ---

Write-Step 'Environment'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Point the package managers at the mapped host cache so downloads survive
# sandbox teardown. Set for this process and persisted for later shells.
if (Test-Path $CacheRoot) {
    foreach ($pair in @(
        @{ Name = 'SCOOP_CACHE';      Value = "$CacheRoot\scoop" },
        @{ Name = 'npm_config_cache'; Value = "$CacheRoot\npm" }
    )) {
        New-Item -ItemType Directory -Path $pair.Value -Force | Out-Null
        Set-Item -Path "env:$($pair.Name)" -Value $pair.Value
        [Environment]::SetEnvironmentVariable($pair.Name, $pair.Value, 'User')
    }
    Write-Ok "package caches -> $CacheRoot"
} else {
    Write-Warn "no cache mapped at $CacheRoot - every install will re-download"
}

# ---------------------------------------------------------------- 2. scoop ---

Write-Step 'Scoop package manager'

# The sandbox logs in as WDAGUtilityAccount, which is a local administrator.
# Scoop's installer aborts under an elevated account unless it is given
# -RunAsAdmin explicitly, and `irm ... | iex` cannot pass parameters - so the
# installer has to be downloaded to a file and invoked with the switch.
Invoke-Step -Name 'scoop' -Test { Test-Cmd scoop } -Action {
    $installer = Join-Path $env:TEMP 'scoop-install.ps1'
    Invoke-RestMethod -Uri 'https://get.scoop.sh' -OutFile $installer
    & $installer -RunAsAdmin
    Sync-Path
}
Sync-Path

if (Test-Cmd scoop) {
    # git is a prerequisite for adding buckets, so it goes in on its own first.
    Invoke-Step -Name 'git' -Test { Test-Cmd git } -Action { scoop install git }
    Sync-Path

    Invoke-Step -Name 'extras bucket' `
        -Test   { (scoop bucket list | Select-Object -ExpandProperty Name) -contains 'extras' } `
        -Action { scoop bucket add extras }

    $mainPackages = @(
        @{ Package = 'neovim';     Command = 'nvim' },
        @{ Package = 'ripgrep';    Command = 'rg' },
        @{ Package = 'fd';         Command = 'fd' },
        @{ Package = 'fzf';        Command = 'fzf' },
        @{ Package = 'starship';   Command = 'starship' },
        @{ Package = 'nodejs-lts'; Command = 'node' },
        @{ Package = 'extras/wezterm'; Command = 'wezterm' }
    )

    foreach ($pkg in $mainPackages) {
        $name = $pkg.Package
        $cmd  = $pkg.Command
        Invoke-Step -Name $name -Test { Test-Cmd $cmd }.GetNewClosure() `
                    -Action { scoop install $name }.GetNewClosure()
        Sync-Path
    }
} else {
    Write-Warn 'scoop unavailable - skipping all Scoop packages'
}

# ---------------------------------------------------------------- 3. herdr ---

Write-Step 'Herdr session manager'

Invoke-Step -Name 'herdr' -Test { Test-Cmd herdr } -Action {
    Invoke-RestMethod -Uri 'https://herdr.dev/install.ps1' | Invoke-Expression
    Sync-Path
}
Sync-Path

# --------------------------------------------------------------- 4. agents ---

Write-Step 'Coding agents'

if (Test-Cmd npm) {
    $agents = @(
        @{ Command = 'claude'; Package = '@anthropic-ai/claude-code';        Args = @() },
        @{ Command = 'codex';  Package = '@openai/codex';                    Args = @() },
        @{ Command = 'pi';     Package = '@earendil-works/pi-coding-agent';  Args = @('--ignore-scripts') }
    )
    foreach ($agent in $agents) {
        $cmd       = $agent.Command
        $pkg       = $agent.Package
        $extraArgs = $agent.Args
        Invoke-Step -Name $cmd -Test { Test-Cmd $cmd }.GetNewClosure() -Action {
            $output = & npm install -g @extraArgs $pkg 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "npm install -g $pkg exited $LASTEXITCODE - $(($output | Select-Object -Last 3) -join ' ')"
            }
            Sync-Path
        }.GetNewClosure()
        Sync-Path
    }
} else {
    Write-Warn 'npm unavailable - skipping agent installation'
}

# ------------------------------------------------------------- 5. dotfiles ---

Write-Step 'Dotfiles'

# The dotfiles mirror the real profile layout, so deployment is a plain
# recursive copy per root rather than a source-to-target mapping table.
$dotfileTrees = @(
    @{ Source = "$DotfilesRoot\profile";        Target = $env:USERPROFILE },
    @{ Source = "$DotfilesRoot\localappdata";   Target = $env:LOCALAPPDATA },
    # Both PowerShell editions get the profile so the prompt is consistent
    # whether a tool launches pwsh or powershell.exe.
    @{ Source = "$DotfilesRoot\Documents\PowerShell"; Target = "$env:USERPROFILE\Documents\PowerShell" },
    @{ Source = "$DotfilesRoot\Documents\PowerShell"; Target = "$env:USERPROFILE\Documents\WindowsPowerShell" }
)

foreach ($tree in $dotfileTrees) {
    if (-not (Test-Path $tree.Source)) { continue }
    New-Item -ItemType Directory -Path $tree.Target -Force | Out-Null
    Copy-Item -Path "$($tree.Source)\*" -Destination $tree.Target -Recurse -Force
    Write-Ok ("{0} -> {1}" -f (Split-Path $tree.Source -Leaf), $tree.Target)
}

# The Windows PowerShell edition uses a different profile filename.
$wpsProfile = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
if (Test-Path $wpsProfile) { Write-Ok 'powershell profile installed for both editions' }

# --------------------------------------------------- 6. AGENTS.md fan-out ---

Write-Step 'AGENTS.md fan-out'

$globalAgents = "$DotfilesRoot\AGENTS.md"
if (Test-Path $globalAgents) {
    # One source of truth, three agents. Claude Code reads CLAUDE.md; Codex and
    # Pi read AGENTS.md.
    $targets = @(
        "$env:USERPROFILE\.claude\CLAUDE.md",
        "$env:USERPROFILE\.codex\AGENTS.md",
        "$env:USERPROFILE\.pi\agent\AGENTS.md"
    )
    foreach ($target in $targets) {
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item -Path $globalAgents -Destination $target -Force
        Write-Ok $target
    }
} else {
    Write-Warn "no global AGENTS.md at $globalAgents"
}

# Safety net for projects not created by New-Project.ps1. An existing project
# AGENTS.md always wins.
$projectAgents  = Join-Path $Workspace 'AGENTS.md'
$projectAgentsT = 'C:\Bootstrap\project-AGENTS.md'
if ((Test-Path $Workspace) -and -not (Test-Path $projectAgents) -and (Test-Path $projectAgentsT)) {
    Copy-Item $projectAgentsT $projectAgents -Force
    Write-Ok "$projectAgents (seeded)"
} elseif (Test-Path $projectAgents) {
    Write-Skip 'project AGENTS.md'
}

# ------------------------------------------------------------------ 7. git ---

Write-Step 'Git configuration'

if (Test-Cmd git) {
    # Mapped folders come from the host with a foreign owner SID, which trips
    # git's dubious-ownership check on every command.
    & git config --global --add safe.directory 'C:/Workspace' 2>&1 | Out-Null
    Write-Ok 'safe.directory C:/Workspace'

    if (Test-Path (Join-Path $Workspace '.git')) {
        Push-Location $Workspace
        $branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
        Pop-Location
        if ($branch) { Write-Ok "workspace repo on branch '$branch'" }
    } else {
        Write-Warn 'workspace is not a git repository'
    }
} else {
    Write-Warn 'git unavailable'
}

# ----------------------------------------------------------------- 8. done ---

$stopwatch.Stop()
Write-Step 'Ready'
Write-Log ("    provisioned in {0:N0}s" -f $stopwatch.Elapsed.TotalSeconds) 'Green'
Write-Log "    log: $LogFile" 'DarkGray'

$missing = @('git','nvim','rg','fd','fzf','starship','node','wezterm','herdr','claude','codex','pi') |
           Where-Object { -not (Test-Cmd $_) }
if ($missing) {
    Write-Warn ("not on PATH: {0}" -f ($missing -join ', '))
} else {
    Write-Ok 'all expected tools on PATH'
}

if ($NoLaunch) { return }

# --------------------------------------------------------------- 9. launch ---

Write-Step 'Launching workspace'

$launchDir = if (Test-Path $Workspace) { $Workspace } else { $env:USERPROFILE }

if ((Test-Cmd wezterm) -and (Test-Cmd herdr)) {
    Start-Process wezterm -ArgumentList @('start', '--cwd', $launchDir, '--', 'herdr')
    Write-Ok 'wezterm + herdr'
} elseif (Test-Cmd wezterm) {
    Start-Process wezterm -ArgumentList @('start', '--cwd', $launchDir)
    Write-Warn 'herdr unavailable - opened a plain wezterm shell'
} else {
    Start-Process powershell -ArgumentList @('-NoExit', '-Command', "Set-Location '$launchDir'")
    Write-Warn 'wezterm unavailable - opened powershell'
}
