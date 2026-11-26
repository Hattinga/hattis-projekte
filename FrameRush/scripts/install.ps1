# Installs FrameRush for the current user (no admin rights needed):
#   %LOCALAPPDATA%\Programs\FrameRush\FrameRush.exe
#   Start menu shortcut (this is what Windows search finds) and a desktop
#   shortcut, both named "FrameRush".
#
# Usage, from the FrameRush folder after scripts\package.ps1:
#   powershell -ExecutionPolicy Bypass -File scripts\install.ps1
# or from an unpacked release zip (FrameRush.exe next to this script):
#   powershell -ExecutionPolicy Bypass -File install.ps1
# Remove the installed copy and both shortcuts:
#   powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -Uninstall
#
# Run it again after a new build to update the installed copy; the shortcuts
# keep working. Settings (%APPDATA%\FrameRush) and logs
# (%LOCALAPPDATA%\FrameRush) are never touched.
param(
    # FrameRush.exe to install. Default: next to this script, otherwise the
    # package of the current version in dist\.
    [string]$Exe,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'

$installDir = Join-Path $env:LOCALAPPDATA 'Programs\FrameRush'
$target = Join-Path $installDir 'FrameRush.exe'
# GetFolderPath, not %USERPROFILE%\Desktop: the desktop may be redirected
# (OneDrive).
$links = @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'FrameRush.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'FrameRush.lnk')
)

# A running FrameRush.exe cannot be overwritten or deleted.
$running = Get-Process -Name FrameRush -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $target }
if ($running) { throw "FrameRush is running from $installDir; close it first." }

if ($Uninstall) {
    foreach ($link in $links) {
        if (Test-Path $link) { Remove-Item -Force $link; Write-Host "removed $link" }
    }
    if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir; Write-Host "removed $installDir" }
    return
}

if (-not $Exe) {
    $beside = Join-Path $PSScriptRoot 'FrameRush.exe'
    if (Test-Path $beside) {
        $Exe = $beside
    } else {
        $root = Split-Path -Parent $PSScriptRoot
        $toml = Join-Path $root 'Cargo.toml'
        if (Test-Path $toml) {
            $version = (Select-String -Path $toml -Pattern '^version\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
            $Exe = Join-Path $root "dist\FrameRush-$version\FrameRush.exe"
        }
    }
}
if (-not $Exe -or -not (Test-Path $Exe)) {
    throw "FrameRush.exe not found ($Exe). Build it first: powershell -ExecutionPolicy Bypass -File scripts\package.ps1"
}

New-Item -ItemType Directory -Force $installDir | Out-Null
Copy-Item -Force $Exe $target
Write-Host "installed $target"

$shell = New-Object -ComObject WScript.Shell
foreach ($link in $links) {
    $shortcut = $shell.CreateShortcut($link)
    $shortcut.TargetPath = $target
    $shortcut.WorkingDirectory = $installDir
    $shortcut.IconLocation = "$target,0"
    $shortcut.Description = 'Low-latency HDMI capture viewer'
    $shortcut.Save()
    Write-Host "shortcut $link"
}
