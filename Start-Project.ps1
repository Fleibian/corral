<#
.SYNOPSIS
    Opens a terminal in an existing project instance.

.DESCRIPTION
    The everyday command. Starting an instance takes a second or two - the
    expensive provisioning was paid once when the base image was built.

    WezTerm runs on the Windows host and attaches to the instance, rather than
    running a GUI terminal inside WSL. That keeps rendering native and avoids
    needing WSLg.

.PARAMETER Name
    Project name.

.PARAMETER NoHerdr
    Open a plain login shell instead of starting Herdr.

.PARAMETER Shell
    Attach in the current terminal instead of opening WezTerm.

.EXAMPLE
    .\Start-Project.ps1 invoice-service
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Name,

    [switch]$NoHerdr,
    [switch]$Shell
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-ProjectName $Name | Out-Null
$distro = Get-DistroName $Name

if (-not (Test-WslDistro $distro)) {
    throw "No such project: '$Name'. Create it with: .\New-Project.ps1 $Name"
}

# Herdr keeps sessions alive across detach, so re-attaching to a running
# session is the normal case rather than starting a fresh one.
$inner = if ($NoHerdr) { 'exec bash -l' } else { 'command -v herdr >/dev/null && exec herdr || exec bash -l' }

if ($Shell) {
    & wsl.exe -d $distro --cd '~/workspace' -- bash -lc $inner
    return
}

$wezterm = Get-Command wezterm -ErrorAction SilentlyContinue
if ($wezterm) {
    Start-Process $wezterm.Source -ArgumentList @(
        'start', '--', 'wsl.exe', '-d', $distro, '--cd', '~/workspace', '--', 'bash', '-lc', $inner
    )
    Write-Host "  Opened '$Name' in WezTerm." -ForegroundColor Green
} else {
    Write-Warning 'wezterm not found on the host - attaching in this terminal instead.'
    & wsl.exe -d $distro --cd '~/workspace' -- bash -lc $inner
}
