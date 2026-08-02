# ARCHIVED - Windows Sandbox implementation. Superseded by the WSL2 scripts at
# the repository root; kept working but no longer maintained. See
# Archive\README.md.
#
# Shared paths and validation for New-Project.ps1 / Start-Project.ps1.
# Dot-sourced, not a module - there is no state to manage.

# This file lives at <root>\Archive\, so the workspace root is one level up.
$script:AgentDevRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:ArchiveRoot  = Split-Path -Parent $PSCommandPath

$AgentDev = [pscustomobject]@{
    Root      = $script:AgentDevRoot
    # Everything this implementation owns stays inside Archive\. In particular
    # its Projects directory is NOT the one at the repository root - that now
    # holds git bundle backups for the WSL2 workflow, which is a different
    # thing entirely that happens to share a name.
    Projects  = Join-Path $script:ArchiveRoot 'Projects'
    Sandboxes = Join-Path $script:ArchiveRoot 'Sandboxes'
    Cache     = Join-Path $script:ArchiveRoot 'Cache'
    Bootstrap = Join-Path $script:ArchiveRoot 'Bootstrap'
    # The Windows profile trees this implementation deploys.
    Dotfiles  = Join-Path $script:ArchiveRoot 'dotfiles-windows'
    # The shared agent policy still lives with the active implementation, so
    # there remains exactly one AGENTS.md for both. Mapped separately, because
    # mapping the whole Dotfiles root would be pointlessly broad.
    SharedDotfiles = Join-Path $script:AgentDevRoot 'Dotfiles'
}

# Windows device names are still special even with an extension, so a project
# called "con" would produce an unopenable directory.
$script:ReservedNames = @(
    'CON','PRN','AUX','NUL',
    'COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9',
    'LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9'
)

<#
.SYNOPSIS
    Rejects any project name that could escape C:\AgentDev\Projects.
.DESCRIPTION
    The isolation guarantee rests on mapping exactly one project directory, so
    the name must not be able to traverse out of Projects or resolve to
    something unexpected. Throws on anything but a plain safe name.
#>
function Assert-ProjectName {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        throw "Invalid project name '$Name'. Use 1-64 characters: letters, digits, dot, underscore or hyphen, starting with a letter or digit."
    }
    if ($Name -match '\.\.') {
        throw "Invalid project name '$Name'. Path traversal is not allowed."
    }
    if ($script:ReservedNames -contains $Name.Split('.')[0].ToUpperInvariant()) {
        throw "Invalid project name '$Name'. That is a reserved Windows device name."
    }
    return $Name
}

function Test-SandboxAvailable {
    Test-Path (Join-Path $env:WINDIR 'System32\WindowsSandbox.exe')
}

# Windows Sandbox permits only one running instance. A session spans several
# processes - WindowsSandbox, WindowsSandboxServer, WindowsSandboxRemoteSession
# and WindowsSandboxClient - and any one of them still alive blocks a new
# launch, so match the whole family rather than naming individual processes.
function Get-RunningSandbox {
    Get-Process -Name 'WindowsSandbox*' -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

<#
.SYNOPSIS
    Waits for a previous sandbox session to finish tearing down.
.DESCRIPTION
    Teardown is not instant, and it outlives the visible window - especially
    after a forced kill. Launching into that window fails silently: the new
    WindowsSandbox.exe exits immediately and nothing is reported.
#>
function Wait-SandboxShutdown {
    param([int]$TimeoutSeconds = 60)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (Get-RunningSandbox) {
        if ((Get-Date) -gt $deadline) { return $false }
        Start-Sleep -Seconds 2
    }
    return $true
}
