#requires -Version 5.1
# Kotlin install without emulator (Windows license stdin via cmd).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('pbk-kt-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $scratch -Force | Out-Null
Copy-Item (Join-Path $root '.build') (Join-Path $scratch '.build') -Recurse -Force
$kit = Join-Path $scratch '.build'
try {
  & "$kit\kotlin.ps1" -Action install -AcceptAndroidLicenses
  & "$kit\kotlin.ps1" -Action configure -Mode verify
  if (-not (Test-Path (Join-Path $kit 'kotlin\android-sdk\platforms\android-36'))) { throw 'platforms missing' }
  if (-not (Test-Path (Join-Path $kit 'kotlin\android-sdk\build-tools\36.0.0'))) { throw 'build-tools missing' }
  if (Test-Path (Join-Path $kit 'kotlin\android-sdk\emulator')) { throw 'emulator should not be installed' }
  Write-Host 'INDEP Windows kotlin no-emulator: PASS'
}
catch {
  Write-Host "FAIL: $_"
  exit 1
}
finally {
  Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
