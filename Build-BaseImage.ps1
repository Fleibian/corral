<#
.SYNOPSIS
    Builds the golden base image that every project instance is cloned from.

.DESCRIPTION
    Run once (and again whenever you want to refresh tooling). Downloads the
    Ubuntu 24.04 WSL rootfs, provisions it with the full toolchain, and exports
    the result to Cache\base\agentdev-base.tar.

    This is where all the expensive work happens. Creating a project from the
    resulting image is a tarball extraction measured in seconds, which is the
    whole point - the Windows Sandbox design paid a ~12 minute provisioning
    cost on every single launch.

.PARAMETER Force
    Rebuild even if a base image already exists.

.PARAMETER KeepBuildDistro
    Leave the temporary build distro registered for inspection instead of
    unregistering it.

.EXAMPLE
    .\Build-BaseImage.ps1
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$KeepBuildDistro
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Common.ps1')

if (-not (Test-WslAvailable)) { throw 'wsl.exe not found. Install WSL with: wsl --install' }

$RootfsUrl   = 'https://cloud-images.ubuntu.com/wsl/releases/24.04/current/ubuntu-noble-wsl-amd64-24.04lts.rootfs.tar.gz'
$rootfsPath  = Join-Path $AgentDev.Cache 'base\ubuntu-noble-rootfs.tar.gz'
$buildDistro = "${AgentDevPrefix}basebuild"
$buildDir    = Join-Path $AgentDev.Instances '_basebuild'

if ((Test-Path $AgentDev.BaseImage) -and -not $Force) {
    $size = (Get-Item $AgentDev.BaseImage).Length / 1GB
    Write-Host ("  Base image already exists ({0:N2} GB): {1}" -f $size, $AgentDev.BaseImage) -ForegroundColor Yellow
    Write-Host '  Use -Force to rebuild.' -ForegroundColor DarkGray
    return
}

New-Item -ItemType Directory -Path (Split-Path $AgentDev.BaseImage -Parent) -Force | Out-Null
New-Item -ItemType Directory -Path $AgentDev.Instances -Force | Out-Null

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
function Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }

# ------------------------------------------------------------ 1. rootfs ---

Step 'Ubuntu 24.04 rootfs'
if (Test-Path $rootfsPath) {
    Write-Host "    cached: $rootfsPath" -ForegroundColor DarkGray
} else {
    Write-Host "    downloading $RootfsUrl" -ForegroundColor DarkGray
    # The progress bar makes Invoke-WebRequest pathologically slow here.
    $previousProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $RootfsUrl -OutFile $rootfsPath
    } finally {
        $ProgressPreference = $previousProgress
    }
}
Write-Host ("    {0:N0} MB" -f ((Get-Item $rootfsPath).Length / 1MB)) -ForegroundColor DarkGray

# ------------------------------------------------------ 2. build distro ---

Step "Build distro '$buildDistro'"
if (Test-WslDistro $buildDistro) {
    Write-Host '    removing previous build distro' -ForegroundColor DarkGray
    & wsl.exe --unregister $buildDistro | Out-Null
}
Remove-Item $buildDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

& wsl.exe --import $buildDistro $buildDir $rootfsPath --version 2
if ($LASTEXITCODE -ne 0) { throw "wsl --import failed (exit $LASTEXITCODE)" }
Write-Host '    imported' -ForegroundColor DarkGray

# systemd is required for the Docker daemon. The build distro keeps automount
# and interop enabled so provisioning can read the dotfiles off the C: drive -
# project instances get the locked-down config instead.
Write-DistroFile -DistroName $buildDistro -Path '/etc/wsl.conf' -Content @'
[boot]
systemd=true

[automount]
enabled=true

[interop]
enabled=true
appendWindowsPath=false
'@

& wsl.exe --terminate $buildDistro | Out-Null
Write-Host '    systemd enabled' -ForegroundColor DarkGray

# --------------------------------------------------------- 3. provision ---

Step 'Provisioning (this is the slow part - it happens once)'

# Stage the provisioning inputs inside the distro rather than executing them
# from /mnt/c: scripts on a Windows drive carry CRLF endings and no execute
# bit, both of which break bash in confusing ways.
$driveLetter   = ($AgentDev.Dotfiles.Substring(0, 1)).ToLowerInvariant()
$dotfilesLinux = "/mnt/$driveLetter" + (($AgentDev.Dotfiles -replace '^[A-Za-z]:', '') -replace '\\', '/')
$provisionSrc  = Get-Content (Join-Path $AgentDev.Provision 'provision.sh') -Raw

Write-DistroFile -DistroName $buildDistro -Path '/tmp/provision.sh' -Content $provisionSrc

& wsl.exe -d $buildDistro --user root -- bash -lc "rm -rf /tmp/dotfiles && cp -r '$dotfilesLinux' /tmp/dotfiles && chmod +x /tmp/provision.sh"
if ($LASTEXITCODE -ne 0) { throw "Failed staging dotfiles into the build distro (exit $LASTEXITCODE)" }

# Native stderr must not be treated as failure - apt and npm both use it for
# routine progress output.
$previousEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & wsl.exe -d $buildDistro --user root -- bash -lc 'DEV_USER=dev DOTFILES_SRC=/tmp/dotfiles bash /tmp/provision.sh'
    $provisionExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousEap
}
if ($provisionExit -ne 0) { throw "Provisioning failed (exit $provisionExit). Inspect with: wsl -d $buildDistro" }

# ------------------------------------------------------------ 4. export ---

Step 'Exporting base image'
& wsl.exe -d $buildDistro --user root -- bash -lc 'rm -rf /tmp/dotfiles /tmp/provision.sh /var/lib/apt/lists/*' | Out-Null
& wsl.exe --terminate $buildDistro | Out-Null

Remove-Item $AgentDev.BaseImage -Force -ErrorAction SilentlyContinue
& wsl.exe --export $buildDistro $AgentDev.BaseImage
if ($LASTEXITCODE -ne 0) { throw "wsl --export failed (exit $LASTEXITCODE)" }

if (-not $KeepBuildDistro) {
    & wsl.exe --unregister $buildDistro | Out-Null
    Remove-Item $buildDir -Recurse -Force -ErrorAction SilentlyContinue
}

$stopwatch.Stop()
Write-Host ''
Write-Host ("  Base image built in {0:N0} min: {1} ({2:N2} GB)" -f `
    $stopwatch.Elapsed.TotalMinutes, $AgentDev.BaseImage, ((Get-Item $AgentDev.BaseImage).Length / 1GB)) -ForegroundColor Green
Write-Host '  Create a project with: .\New-Project.ps1 <name>' -ForegroundColor DarkGray
