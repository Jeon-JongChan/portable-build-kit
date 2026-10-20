#requires -Version 5.1
# Independent Windows checks (not the shipped smoke suite).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('pbk-indep-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
Copy-Item (Join-Path $root '.build') (Join-Path $scratch '.build') -Recurse -Force
$kit = Join-Path $scratch '.build'
$log = New-Object System.Collections.Generic.List[string]

function Assert([bool]$cond, [string]$msg) {
  if (-not $cond) { throw $msg }
}
function ExpectFail([scriptblock]$block, [string]$name) {
  $failed = $false
  try { & $block | Out-Null } catch { $failed = $true }
  if (-not $failed) { throw "EXPECTED FAIL but succeeded: $name" }
  $log.Add("PASS expect-fail: $name") | Out-Null
}

try {
  ExpectFail { & "$kit\go.ps1" -Action configure -Feature emulator -Operation install -AcceptAndroidLicenses } 'go+emulator'
  ExpectFail { & "$kit\kotlin.ps1" -Action configure -Feature tauri -Operation install } 'kotlin+tauri'
  ExpectFail { & "$kit\go.ps1" -Action configure -Feature vue -Operation init } 'go+vue'
  ExpectFail { & "$kit\rust.ps1" -Action vue-init } 'rust vue-init'
  ExpectFail { & "$kit\nodejs.ps1" -Action tauri-install } 'nodejs tauri-install'
  ExpectFail { & "$kit\go.ps1" -Action configure -Mode prime } 'prime without go.mod'
  ExpectFail { & "$kit\go.ps1" -Action configure -Mode offline-check } 'offline-check without go.mod'
  ExpectFail { & "$kit\go.ps1" -Action configure -Mode verify } 'verify without go'
  ExpectFail { & "$kit\go.ps1" -Action reset -Scope tools } 'reset without -Yes'
  ExpectFail { & "$kit\setup.ps1" -Action prime -Language all } 'prime language=all'
  ExpectFail { & "$kit\setup.ps1" -Action offline-check -Language all } 'offline-check language=all'
  ExpectFail { & "$kit\go.ps1" -Action configure -Mode run } 'run without CommandArgs'

  Assert (Test-Path "$kit\activate.ps1") 'activate.ps1 missing'
  Assert ((Get-Content "$kit\activate.ps1" -Raw) -match 'GOROOT') 'activate.ps1 missing GOROOT'
  $log.Add('PASS activate.ps1 GOROOT') | Out-Null

  $proj = Join-Path $scratch 'tinygo'
  New-Item -ItemType Directory $proj -Force | Out-Null
  Set-Content "$proj\go.mod" "module example.com/tiny`ngo 1.22`n"
  Set-Content "$proj\main.go" "package main`nfunc main() {}`n"
  ExpectFail { & "$kit\go.ps1" -Action configure -Mode prime -Project $proj } 'prime go.mod but no go.exe'

  # install all language set excludes nodejs
  $src = Get-Content (Join-Path $kit 'setup.ps1') -Raw
  Assert ($src -match "ListLanguages.*'go','rust','kotlin','csharp','python'") 'ListLanguages should exclude nodejs from all'
  $log.Add('PASS install-all excludes nodejs') | Out-Null

  $log | ForEach-Object { $_ }
  Write-Host "INDEP Windows boundary: $($log.Count) checks passed"
}
catch {
  Write-Host "FAIL: $_"
  $log | ForEach-Object { $_ }
  exit 1
}
finally {
  Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
