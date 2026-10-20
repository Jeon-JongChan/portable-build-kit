#requires -Version 5.1
# Session activate.ps1 (not global) then run tools in THIS process.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('pbk-sess-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $scratch -Force | Out-Null
Copy-Item (Join-Path $root '.build') (Join-Path $scratch '.build') -Recurse -Force
$kit = Join-Path $scratch '.build'
try {
  & "$kit\go.ps1" -Action install
  & "$kit\python.ps1" -Action install
  & "$kit\go.ps1" -Action configure -Mode env | Out-Null
  . "$kit\activate.ps1"
  $gv = go version
  $pv = python --version 2>&1 | Out-String
  if ($env:GOROOT -ne (Join-Path $kit 'go\sdk')) { throw "GOROOT bad: $($env:GOROOT)" }
  if ($gv -notmatch 'go1\.') { throw "go bad: $gv" }
  if ($pv -notmatch 'Python 3') { throw "python bad: $pv" }
  Write-Host "OK $gv / $($pv.Trim())"
  Write-Host 'INDEP Windows session-activate+run: PASS'
}
catch { Write-Host "FAIL: $_"; exit 1 }
finally { Remove-Item $scratch -Recurse -Force -EA SilentlyContinue }
