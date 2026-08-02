<#
.SYNOPSIS
    Creates a new isolated project and launches its sandbox.

.DESCRIPTION
    One-time entry point for a project: creates the directory, initialises git,
    seeds .gitignore and AGENTS.md, then hands off to Start-Project.ps1 to
    generate the sandbox config and launch it.

    Use Start-Project.ps1 for every launch after this one.

.PARAMETER Name
    Project directory name, created under C:\AgentDev\Projects.

.PARAMETER MemoryMB
    Memory cap for the sandbox. Defaults to all host physical memory.

.PARAMETER NoLaunch
    Create the project but do not start the sandbox.

.EXAMPLE
    .\New-Project.ps1 invoice-service
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Name,

    [int]$MemoryMB = 0,

    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-ProjectName $Name | Out-Null

$projectPath = Join-Path $AgentDev.Projects $Name
if (Test-Path $projectPath) {
    throw "Project already exists: $projectPath. Launch it with: .\Start-Project.ps1 $Name"
}

New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
Write-Host ""
Write-Host "  created   $projectPath" -ForegroundColor Green

Copy-Item (Join-Path $AgentDev.Bootstrap 'project-gitignore.txt') (Join-Path $projectPath '.gitignore')  -Force
Copy-Item (Join-Path $AgentDev.Bootstrap 'project-AGENTS.md')     (Join-Path $projectPath 'AGENTS.md')   -Force

Set-Content -Path (Join-Path $projectPath 'README.md') -Encoding utf8 -Value @"
# $Name

Created $(Get-Date -Format 'yyyy-MM-dd') by New-Project.ps1.

Launch the sandbox for this project from the host:

    C:\AgentDev\Start-Project.ps1 $Name

Inside the sandbox this directory is ``C:\Workspace`` and is the only thing
that survives the sandbox being closed.
"@

Push-Location $projectPath
try {
    & git init --quiet
    & git add -A
    # -c keeps this out of the host's global config; the sandbox gets identity
    # from the dotfiles .gitconfig.
    & git -c user.name='Windows Agent Workspace' -c user.email='noreply@localhost' `
          commit --quiet -m 'Initial commit: project scaffold'
    if ($LASTEXITCODE -eq 0) { Write-Host "  git       initialised with initial commit" -ForegroundColor Green }
} catch {
    Write-Warning "git init failed: $($_.Exception.Message)"
} finally {
    Pop-Location
}

$startArgs = @{ Name = $Name; MemoryMB = $MemoryMB }
if ($NoLaunch) { $startArgs.NoLaunch = $true }
& (Join-Path $PSScriptRoot 'Start-Project.ps1') @startArgs
