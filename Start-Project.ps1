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

# A single argument with no spaces or shell operators. Start-Process does not
# quote arguments containing spaces, so anything more complex than a bare
# command name gets split into separate tokens by the time it reaches bash.
# The launcher script (installed in the base image) holds the actual logic:
# cd to the workspace, exec herdr, fall back to a login shell.
$launcher = if ($NoHerdr) { 'bash' } else { 'agentdev-session' }

if ($Shell) {
    & wsl.exe -d $distro --cd '~/workspace' -- bash -lc $launcher
    return
}

# wezterm.exe is the CLI front-end; on Windows `wezterm start` exits 0 without
# reliably spawning anything. wezterm-gui.exe is the actual terminal process,
# so resolve that - falling back to the sibling of whatever wezterm.exe is on
# PATH, since wezterm-gui is not always added to PATH by the installer.
$guiCommand = Get-Command 'wezterm-gui' -ErrorAction SilentlyContinue
if (-not $guiCommand) {
    $cliCommand = Get-Command 'wezterm' -ErrorAction SilentlyContinue
    if ($cliCommand) {
        $sibling = Join-Path (Split-Path $cliCommand.Source -Parent) 'wezterm-gui.exe'
        if (Test-Path $sibling) { $guiCommand = [pscustomobject]@{ Source = $sibling } }
    }
}

if (-not $guiCommand) {
    Write-Warning 'wezterm-gui not found on the host - attaching in this terminal instead.'
    & wsl.exe -d $distro --cd '~/workspace' -- bash -lc $launcher
    return
}

# Run through `bash -lc` so the login profile is loaded before the launcher.
# Each element is a single space-free token, which keeps Start-Process's
# argument handling out of trouble.
$process = Start-Process -FilePath $guiCommand.Source -PassThru -ArgumentList @(
    'start', '--', 'wsl.exe', '-d', $distro, '--cd', '~/workspace', '--', 'bash', '-lc', $launcher
)

# Confirm it actually came up rather than reporting success on faith - a
# terminal that exits immediately otherwise looks identical to one that opened
# behind another window.
Start-Sleep -Milliseconds 2500
if ($process.HasExited) {
    throw "WezTerm exited immediately (code $($process.ExitCode)). Attach directly with: .\Start-Project.ps1 $Name -Shell"
}

Write-Host "  Opened '$Name' in WezTerm." -ForegroundColor Green
