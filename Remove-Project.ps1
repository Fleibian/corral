<#
.SYNOPSIS
    Destroys a project instance, by default backing its git history out first.

.DESCRIPTION
    Project files live on ext4 inside the instance, so unregistering a distro
    destroys them permanently - there is no copy on your Windows drive. The
    default is therefore to write a git bundle to
    Projects\<name>-<timestamp>.bundle and refuse to proceed if that fails.

    A bundle is a single file holding the complete repository - every branch
    and all history. Restore with: git clone <name>.bundle <name>

    For throwaway projects that should leave nothing behind, use -NoBackup.
    Nothing is written to Windows and the instance is simply destroyed. You
    are still asked to confirm, unless you also pass -Force.

.PARAMETER Name
    Project name.

.PARAMETER NoBackup
    Destroy without writing a bundle. Use for scratch and test projects you
    have no intention of keeping.

.PARAMETER Force
    Skip the confirmation prompt, and proceed even when the working tree has
    uncommitted changes. Intended for scripted teardown.

.EXAMPLE
    .\Remove-Project.ps1 invoice-service
    Backs up git history to Windows, then destroys the instance.

.EXAMPLE
    .\Remove-Project.ps1 scratch-test -NoBackup
    Destroys the instance and leaves nothing behind, after confirming.

.EXAMPLE
    .\Remove-Project.ps1 scratch-test -NoBackup -Force
    Same, with no prompt.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Name,

    [Alias('SkipBackup')]
    [switch]$NoBackup,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-ProjectName $Name | Out-Null
$distro = Get-DistroName $Name

if (-not (Test-WslDistro $distro)) {
    throw "No such project: '$Name'."
}

# Asking git what is at stake is cheap, and it is the only thing that makes an
# irreversible prompt meaningful - "destroy this?" is much easier to answer
# correctly as "destroy 12 commits and 3 uncommitted changes?".
$summary = Invoke-InDistro -DistroName $distro -AllowFailure -Command @'
cd ~/workspace 2>/dev/null || exit 0
printf '%s|%s|%s' \
  "$(git rev-list --count --all 2>/dev/null)" \
  "$(git status --porcelain 2>/dev/null | wc -l)" \
  "$(git remote 2>/dev/null | head -1)"
'@
$parts    = ("$summary" -split '\|')
$commits  = if ($parts.Count -ge 1 -and $parts[0]) { [int]$parts[0] } else { 0 }
$dirty    = if ($parts.Count -ge 2 -and $parts[1]) { [int]$parts[1] } else { 0 }
$hasRemote = ($parts.Count -ge 3 -and $parts[2])

# ------------------------------------------------------------- backup ---

if ($NoBackup) {
    Write-Host ''
    Write-Host "  '$Name' will be destroyed with no backup." -ForegroundColor Yellow
    Write-Host ("  losing    {0} commit(s), {1} uncommitted change(s)" -f $commits, $dirty) -ForegroundColor Yellow
    if (-not $hasRemote -and $commits -gt 0) {
        Write-Host '  note      no git remote is configured, so this history exists nowhere else' -ForegroundColor Yellow
    }
    Write-Host ''
} else {
    if ($dirty -gt 0 -and -not $Force) {
        $files = Invoke-InDistro -DistroName $distro -AllowFailure `
                    -Command 'cd ~/workspace 2>/dev/null && git status --porcelain 2>/dev/null | head -20'
        Write-Host ''
        Write-Warning "'$Name' has uncommitted changes. A bundle captures committed history only, so these would be lost:"
        $files | Where-Object { "$_".Trim() } | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
        throw "Commit them first, or re-run with -Force to discard them, or -NoBackup if this project is disposable."
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
        $b64  = & wsl.exe -d $distro --user dev -- bash -lc "base64 -w0 /tmp/$bundleName" 2>$null
        $exit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEap
    }

    if ($exit -ne 0 -or -not $b64) {
        throw "Could not produce a backup bundle for '$Name'. Refusing to destroy it. Pass -NoBackup if this project is disposable."
    }

    [IO.File]::WriteAllBytes($bundlePath, [Convert]::FromBase64String(($b64 -join '')))
    Write-Host ("  backup     $bundlePath ({0:N1} MB)" -f ((Get-Item $bundlePath).Length / 1MB)) -ForegroundColor Green
    Write-Host "  restore    git clone `"$bundlePath`" $Name" -ForegroundColor DarkGray
}

# ------------------------------------------------------------ destroy ---

$action = if ($NoBackup) {
    'Unregister WSL distribution and delete all its files - NO BACKUP'
} else {
    'Unregister WSL distribution and delete all its files'
}

# -Force means "do not ask" as well as "do not refuse", which is what scripted
# teardown needs. Without it an unbacked-up removal always prompts.
if (-not $Force -and -not $PSCmdlet.ShouldProcess($distro, $action)) {
    Write-Host "  Cancelled - '$Name' was not touched." -ForegroundColor DarkGray
    return
}

& wsl.exe --terminate $distro 2>&1 | Out-Null
& wsl.exe --unregister $distro
if ($LASTEXITCODE -ne 0) { throw "wsl --unregister failed (exit $LASTEXITCODE)" }

Remove-Item (Join-Path $AgentDev.Instances $Name) -Recurse -Force -ErrorAction SilentlyContinue

if ($NoBackup) {
    Write-Host "  Removed '$Name'. Nothing was kept." -ForegroundColor Green
} else {
    Write-Host "  Removed '$Name'." -ForegroundColor Green
}
