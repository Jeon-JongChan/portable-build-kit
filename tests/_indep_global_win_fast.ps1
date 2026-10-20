#requires -Version 5.1
# Fast global-on: go+python only, probe without rustc hang, always global-off.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('pbk-gfast-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $scratch -Force | Out-Null
Copy-Item (Join-Path $root '.build') (Join-Path $scratch '.build') -Recurse -Force
$kit = Join-Path $scratch '.build'
$marker = Join-Path $kit '_state\global-windows.json'
$globalOn = $false
try {
  & "$kit\go.ps1" -Action install
  & "$kit\python.ps1" -Action install
  Write-Host '[global] global-on...'
  & "$kit\setup.ps1" -Action configure -Mode global-on
  $globalOn = $true
  Write-Host '[global] probe new process...'
  $probe = Join-Path $scratch 'probe.ps1'
  @'
$ErrorActionPreference='Stop'
$gv = & go version
$pv = & python --version
if ($env:GOROOT -notlike '*pbk-gfast-*') { throw "GOROOT=$($env:GOROOT)" }
Write-Host "OK $gv / $pv"
Write-Host 'PROBE_PASS'
'@ | Set-Content $probe -Encoding UTF8
  $out = Join-Path $scratch 'out.txt'
  $p = Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$probe) `
    -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err') -WindowStyle Hidden
  $t = (Get-Content $out -Raw -EA SilentlyContinue) + (Get-Content ($out+'.err') -Raw -EA SilentlyContinue)
  Write-Host $t
  if ($p.ExitCode -ne 0 -or $t -notmatch 'PROBE_PASS') { throw "probe failed exit=$($p.ExitCode)" }
  & "$kit\setup.ps1" -Action configure -Mode global-off
  $globalOn = $false
  Write-Host 'INDEP Windows global-on/off+run FAST: PASS'
}
catch { Write-Host "FAIL: $_"; exit 1 }
finally {
  if ($globalOn -and (Test-Path $marker)) {
    try { & "$kit\setup.ps1" -Action configure -Mode global-off } catch { Write-Host "WARN off: $_" }
  }
  Remove-Item $scratch -Recurse -Force -EA SilentlyContinue
}
