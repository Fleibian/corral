# Shared paths and validation for New-Project.ps1 / Start-Project.ps1.
# Dot-sourced, not a module - there is no state to manage.

$script:AgentDevRoot = Split-Path -Parent $PSCommandPath

$AgentDev = [pscustomobject]@{
    Root      = $script:AgentDevRoot
    Projects  = Join-Path $script:AgentDevRoot 'Projects'
    Sandboxes = Join-Path $script:AgentDevRoot 'Sandboxes'
    Cache     = Join-Path $script:AgentDevRoot 'Cache'
    Bootstrap = Join-Path $script:AgentDevRoot 'Bootstrap'
    Dotfiles  = Join-Path $script:AgentDevRoot 'Dotfiles\windows'
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

# Windows Sandbox permits only one running instance.
function Get-RunningSandbox {
    Get-Process -Name 'WindowsSandboxClient', 'WindowsSandbox' -ErrorAction SilentlyContinue |
        Select-Object -First 1
}
