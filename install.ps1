# sf-agent-installer — Windows entry point
#
# Bootstraps WSL (Windows Subsystem for Linux) with Ubuntu, then runs
# install-wsl.sh inside it. Idempotent — safe to re-run.
#
# Usage (Admin PowerShell):
#     .\install.ps1
#
# If WSL is missing, the script will install it and ask you to reboot.
# After reboot, Ubuntu will open automatically and walk you through
# setting a Linux username/password. Then re-run this script.

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# ---------- output helpers ----------
function Step($msg)  {
  $script:CurrentStep = $msg
  Write-Host ""
  Write-Host "==> $msg" -ForegroundColor White
}
function Ok($msg)    { Write-Host "[ok] $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "[!]  $msg" -ForegroundColor Yellow }
function Err($msg)   { Write-Host "[x]  $msg" -ForegroundColor Red }

$script:CurrentStep = "Starting installation"

function Show-FailureBanner {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Red
    Write-Host "  INSTALLATION DID NOT FINISH" -ForegroundColor Red
    Write-Host "==================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "  The installer stopped during this step:"
    Write-Host ""
    Write-Host "      $($script:CurrentStep)" -ForegroundColor White
    Write-Host ""
    Write-Host "  The specific reason is in the error message above. Common causes:"
    Write-Host ""
    Write-Host "  1) NOT RUNNING AS ADMINISTRATOR" -ForegroundColor White
    Write-Host "     WSL install requires admin. Right-click PowerShell -> "
    Write-Host "     'Run as Administrator', then re-run this script."
    Write-Host ""
    Write-Host "  2) WINDOWS VERSION TOO OLD" -ForegroundColor White
    Write-Host "     WSL needs Windows 10 v2004 (build 19041) or Windows 11."
    Write-Host "     Update Windows via Settings -> Windows Update."
    Write-Host ""
    Write-Host "  3) VIRTUALIZATION DISABLED IN BIOS" -ForegroundColor White
    Write-Host "     Reboot into BIOS/UEFI and enable Intel VT-x or AMD-V."
    Write-Host "     Some corporate-locked machines block this — contact IT."
    Write-Host ""
    Write-Host "  4) REBOOT PENDING" -ForegroundColor White
    Write-Host "     A previous step needs a reboot before it takes effect."
    Write-Host "     Reboot and re-run this script."
    Write-Host ""
    Write-Host "  5) WSL INSTALL FAILED FOR ANOTHER REASON" -ForegroundColor White
    Write-Host "     Try the manual fallback:"
    Write-Host "       a) In an Admin PowerShell, run:  wsl --install"
    Write-Host "       b) Reboot."
    Write-Host "       c) Open Start menu -> Ubuntu, set a username/password."
    Write-Host "       d) Re-run this script."
    Write-Host ""
    Write-Host "  Re-running this installer is safe." -ForegroundColor White
    Write-Host "  Steps that already finished will skip."
    Write-Host ""
}

# Trap any terminating error and show the failure banner
trap {
    Show-FailureBanner
    exit 1
}

# ---------- 1. Windows version ----------
Step "Checking Windows version"
$ver = [System.Environment]::OSVersion.Version
if ($ver.Major -lt 10 -or ($ver.Major -eq 10 -and $ver.Build -lt 19041)) {
    Err "WSL requires Windows 10 build 19041 (v2004) or newer."
    Err "Detected: Windows $($ver.Major).$($ver.Minor) build $($ver.Build)"
    exit 1
}
Ok "Windows $($ver.Major) build $($ver.Build) detected."

# ---------- 2. Admin check ----------
Step "Checking admin privileges"
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Err "Admin privileges required to install WSL."
    Err "Right-click PowerShell -> 'Run as Administrator', cd to this folder,"
    Err "and re-run:  .\install.ps1"
    exit 1
}
Ok "Running as Administrator."

# ---------- 3. WSL state detection ----------
Step "Checking WSL state"

function Test-WslKernelInstalled {
    # `wsl --status` succeeds (exit 0) when the WSL kernel is installed, even
    # if no distro is set up. It fails with a clear message otherwise.
    try {
        $null = & wsl.exe --status 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Test-UbuntuReady {
    # Ubuntu is "ready" when we can actually exec a command inside it.
    try {
        $null = & wsl.exe -d Ubuntu -- bash -c "true" 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

$wslReady = Test-WslKernelInstalled
$ubuntuReady = $false
if ($wslReady) { $ubuntuReady = Test-UbuntuReady }

if (-not $wslReady) {
    Step "Installing WSL + Ubuntu"
    Warn "This will install WSL and Ubuntu, then ask you to reboot."
    Warn "After reboot, Ubuntu will open automatically and ask for a Linux"
    Warn "username and password. Set them, then re-run this script."
    Write-Host ""
    Read-Host "Press Enter to continue (or Ctrl+C to abort)" | Out-Null

    & wsl.exe --install -d Ubuntu
    if ($LASTEXITCODE -ne 0) {
        Err "wsl --install failed with exit code $LASTEXITCODE."
        Err "See Microsoft's WSL docs: https://learn.microsoft.com/windows/wsl/install"
        exit 1
    }

    Write-Host ""
    Ok "WSL installed."
    Warn "REBOOT REQUIRED before WSL can be used."
    Write-Host ""
    Write-Host "After reboot:" -ForegroundColor White
    Write-Host "  1. Ubuntu will open automatically and ask for a Linux username/password." -ForegroundColor White
    Write-Host "     Set them (you'll need them for sudo later)." -ForegroundColor White
    Write-Host "  2. Re-run this installer in an Admin PowerShell:  .\install.ps1" -ForegroundColor White
    Write-Host ""

    $reboot = Read-Host "Reboot now? [Y/n]"
    if ($reboot -eq "" -or $reboot -match "^[Yy]") {
        Restart-Computer -Force
    } else {
        Warn "Please reboot manually, then re-run this script."
    }
    exit 0
}

Ok "WSL kernel is installed."

if (-not $ubuntuReady) {
    Err "Ubuntu is installed but not initialized."
    Err "Open Start menu -> Ubuntu. The first launch will ask for a Linux"
    Err "username and password — set them, then re-run this script."
    exit 1
}
Ok "Ubuntu is ready."

# ---------- 4. Locate install-wsl.sh ----------
Step "Locating install-wsl.sh"
$wslScript = Join-Path $PSScriptRoot "install-wsl.sh"
if (-not (Test-Path $wslScript)) {
    Err "install-wsl.sh not found next to install.ps1"
    Err "Expected at: $wslScript"
    Err "Make sure you cloned the full sf-agent-installer repo, not just install.ps1."
    exit 1
}
Ok "Found: $wslScript"

# ---------- 5. Translate Windows path to WSL path ----------
Step "Translating script path for WSL"
# Use forward slashes so wslpath sees a consistent input
$winPath = $wslScript -replace '\\', '/'
$wslPath = & wsl.exe -d Ubuntu -- wslpath -a "$winPath"
$wslPath = $wslPath.Trim()
if ([string]::IsNullOrWhiteSpace($wslPath)) {
    Err "Could not translate Windows path to WSL path."
    Err "Tried: $winPath"
    exit 1
}
Ok "WSL path: $wslPath"

# ---------- 6. Run install-wsl.sh inside Ubuntu ----------
Step "Running Linux install inside WSL"
Write-Host "Handing off to Ubuntu — you may be asked for your Linux sudo password." -ForegroundColor White
Write-Host ""

# Run the bash script as the default Ubuntu user. The script handles its own
# success / failure banners.
& wsl.exe -d Ubuntu -- bash "$wslPath"
$bashExit = $LASTEXITCODE

if ($bashExit -ne 0) {
    Err "Linux install (install-wsl.sh) failed with exit code $bashExit."
    Err "See the failure banner from install-wsl.sh above for details."
    exit $bashExit
}

# install-wsl.sh prints its own success banner. Nothing more to do here.
exit 0
