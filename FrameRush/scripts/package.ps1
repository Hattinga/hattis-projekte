# Builds the release and packs it for distribution:
#   dist\FrameRush-<version>\FrameRush.exe, install.ps1, README.md, LICENSE
#   dist\FrameRush-<version>-windows-x64.zip
#
# Usage (from the FrameRush folder):
#   powershell -ExecutionPolicy Bypass -File scripts\package.ps1
# then, to get the Start menu entry and desktop shortcut:
#   powershell -ExecutionPolicy Bypass -File scripts\install.ps1
#
# App icon: assets\framerush.rc is compiled with the Windows SDK's rc.exe and
# the .res is passed to the linker through `cargo rustc`, whose extra
# arguments reach only this crate. Deliberately no build script: that would
# be another new executable for Kaspersky to block (see below), and
# RUSTFLAGS would rebuild every dependency and its build scripts.
#
# Fallback: if the release build fails (on the development PC Kaspersky
# blocks the new build-script executables under target\release, even with
# its protection paused), the same optimized program is built in the dev
# profile instead: opt-level 3, no debug assertions or overflow checks, so it
# is a windowed app like the release build. Build scripts and proc macros
# keep their dev settings, so Cargo reuses the existing (allowed) ones in
# target\debug instead of creating new executables. Afterwards the next
# normal `cargo build` recompiles the debug build.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$version = (Select-String -Path Cargo.toml -Pattern '^version\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value

# rc.exe ships with the Windows SDK, which the MSVC toolchain needs anyway.
$rc = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\rc.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Parent.Name -as [version] } |
    Sort-Object { [version]$_.Directory.Parent.Name } | Select-Object -Last 1
if (-not $rc) { throw 'rc.exe not found (Windows SDK, part of the Visual Studio "Desktop development with C++" workload)' }
$res = Join-Path $root 'target\framerush.res'
New-Item -ItemType Directory -Force (Split-Path -Parent $res) | Out-Null
& $rc.FullName /nologo /fo $res assets\framerush.rc
if ($LASTEXITCODE -ne 0) { throw "rc.exe failed ($LASTEXITCODE)" }
# Cargo fingerprints the link argument, not the file behind it: a path that
# changes with the content makes a redrawn icon relink the exe.
$hash = (Get-FileHash $res -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
$resLinked = Join-Path $root "target\framerush-$hash.res"
Copy-Item -Force $res $resLinked
$linkIcon = "link-arg=$resLinked"

Write-Host "FrameRush ${version}: cargo rustc --release (with icon)"
cargo rustc --release --bin framerush -- -C $linkIcon
$exe = 'target\release\framerush.exe'
if ($LASTEXITCODE -ne 0) {
    Write-Warning "release build failed; building the optimized dev-profile variant instead"
    $overrides = @{
        CARGO_PROFILE_DEV_OPT_LEVEL                      = '3'
        CARGO_PROFILE_DEV_CODEGEN_UNITS                  = '16'
        CARGO_PROFILE_DEV_DEBUG                          = 'line-tables-only'
        CARGO_PROFILE_DEV_DEBUG_ASSERTIONS               = 'false'
        CARGO_PROFILE_DEV_OVERFLOW_CHECKS                = 'false'
        CARGO_PROFILE_DEV_INCREMENTAL                    = 'false'
        CARGO_PROFILE_DEV_BUILD_OVERRIDE_OPT_LEVEL       = '0'
        CARGO_PROFILE_DEV_BUILD_OVERRIDE_DEBUG_ASSERTIONS = 'true'
        CARGO_PROFILE_DEV_BUILD_OVERRIDE_OVERFLOW_CHECKS = 'true'
    }
    foreach ($key in $overrides.Keys) { Set-Item "env:$key" $overrides[$key] }
    try {
        cargo rustc --bin framerush -- -C $linkIcon
        if ($LASTEXITCODE -ne 0) { throw "optimized dev-profile build failed ($LASTEXITCODE)" }
    } finally {
        foreach ($key in $overrides.Keys) { Remove-Item "env:$key" -ErrorAction SilentlyContinue }
    }
    $exe = 'target\debug\framerush.exe'
}

$name = "FrameRush-$version"
$dist = Join-Path $root 'dist'
$dir = Join-Path $dist $name
if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
New-Item -ItemType Directory -Force $dir | Out-Null

Copy-Item $exe (Join-Path $dir 'FrameRush.exe')
Copy-Item scripts\install.ps1 $dir
Copy-Item README.md $dir
Copy-Item (Join-Path (Split-Path -Parent $root) 'LICENSE') $dir

$zip = Join-Path $dist "$name-windows-x64.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $zip

$packed = Get-Item (Join-Path $dir 'FrameRush.exe')
Write-Host ("built from {0}" -f $exe)
Write-Host ("{0}  {1:N1} MB" -f $packed.FullName, ($packed.Length / 1MB))
Write-Host ("{0}  {1:N1} MB" -f $zip, ((Get-Item $zip).Length / 1MB))
