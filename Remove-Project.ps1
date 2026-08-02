<#
.SYNOPSIS
    Destroys a project instance, after backing its git history out to Windows.

.DESCRIPTION
    Because project files live on ext4 inside the instance, unregistering a
    distro destroys them permanently - there is no copy on your Windows drive.
    This command therefore always writes a git bundle to
    Projects\<name>-<timestamp>.bundle first, and refuses to proceed if that
    backup cannot be produced.

    A bundle is a single file containing the complete repository - every branch
    and all history. Restore with: git clone <name>.bundle <name>

.PARAMETER Name
    Project name.

.PARAMETER Force
    Proceed even when the working tree has uncommitted changes. Those changes
    are NOT in the bundle and will be lost - only committed history is.

.PARAMETER SkipBackup
    Destroy without any backup. Requires -Force as well.

.EXAMPLE
    .\Remove-Project.ps1 invoice-service
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Name,

    [switch]$Force,
    [switch]$SkipBackup
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-ProjectName $Name | Out-Null
$distro = Get-DistroName $Name

if (-not (Test-WslDistro $distro)) {
    throw "No such project: '$Name'."
}
if ($SkipBackup -and -not $Force) {
    throw '-SkipBackup also requires -Force. Destroying a project with no backup is not something to do by accident.'
}

# ------------------------------------------------------------- safety ---

if (-not $SkipBackup) {
    $dirty = Invoke-InDistro -DistroName $distro -AllowFailure `
                -Command 'cd ~/workspace 2>/dev/null && git status --porcelain 2>/dev/null | head -20'
    $dirtyLines = @($dirty | Where-Object { "$_".Trim() })

    if ($dirtyLines.Count -gt 0 -and -not $Force) {
        Write-Host ''
        Write-Warning "'$Name' has uncommitted changes. A bundle captures committed history only, so these would be lost:"
        $dirtyLines | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
        throw 'Commit the changes first, or re-run with -Force to discard them.'
    }

    New-Item -ItemType Directory -Path $AgentDev.Projects -Force | Out-Null
    $stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bundleName = "$Name-$stamp.bundle"
    $bundlePath = Join-Path $AgentDev.Projects $bundleName

    Write-Host "  Backing up git history..." -ForegroundColor Cyan
    Invoke-InDistro -DistroName $distro -AllowFailure `
        -Command "cd ~/workspace && git bundle create /tmp/$bundleName --all" | Out-Null

    # Read the bundle out over stdout as base64. Interop is disabled inside the
    # instance, so it cannot write to a Windows path itself.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $b64 = & wsl.exe -d $distro --user dev -- bash -lc "base64 -w0 /tmp/$bundleName" 2>$null
        $exit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEap
    }

    if ($exit -ne 0 -or -not $b64) {
        throw "Could not produce a backup bundle for '$Name'. Refusing to destroy it. Use -SkipBackup -Force to override."
    }

    [IO.File]::WriteAllBytes($bundlePath, [Convert]::FromBase64String(($b64 -join '')))
    Write-Host ("  backup     $bundlePath ({0:N1} MB)" -f ((Get-Item $bundlePath).Length / 1MB)) -ForegroundColor Green
    Write-Host "  restore    git clone `"$bundlePath`" $Name" -ForegroundColor DarkGray
}

# ------------------------------------------------------------ destroy ---

if (-not $PSCmdlet.ShouldProcess($distro, 'Unregister WSL distribution and delete all its files')) {
    return
}

& wsl.exe --terminate $distro 2>&1 | Out-Null
& wsl.exe --unregister $distro
if ($LASTEXITCODE -ne 0) { throw "wsl --unregister failed (exit $LASTEXITCODE)" }

Remove-Item (Join-Path $AgentDev.Instances $Name) -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "  Removed '$Name'." -ForegroundColor Green
