#requires -Version 5.1
# Install (go+python) → global-on → NEW process runs tools → global-off restore.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('pbk-global-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
Copy-Item (Join-Path $root '.build') (Join-Path $scratch '.build') -Recurse -Force
$kit = Join-Path $scratch '.build'
$marker = Join-Path $kit '_state\global-windows.json'
$globalOn = $false

function Assert([bool]$c, [string]$m) { if (-not $c) { throw $m } }

try {
  Write-Host '[global] install go + python + csharp + rust(gnu)...'
  & "$kit\go.ps1" -Action install
  & "$kit\python.ps1" -Action install
  & "$kit\csharp.ps1" -Action install
  & "$kit\rust.ps1" -Action install -RustAbi gnu

  Write-Host '[global] global-on (User env)...'
  & "$kit\setup.ps1" -Action configure -Mode global-on
  $globalOn = $true
  Assert (Test-Path $marker) 'global-windows.json missing'

  # Fresh process reads User-level env (current process does not).
  $probe = Join-Path $scratch 'probe.ps1'
  @'
$ErrorActionPreference='Stop'
$fails=@()
function Need($name,$cmd) {
  try {
    $out = & $cmd 2>&1 | Out-String
    if (-not $out.Trim()) { $fails += "$name empty" }
    else { Write-Host "OK $name : $($out.Trim().Split([char]10)[0])" }
  } catch { $fails += "$name : $_" }
}
Need 'go' { go version }
Need 'python' { python --version }
Need 'uv' { uv --version }
Need 'dotnet' { dotnet --version }
Need 'rustc' { rustc --version }
Need 'cargo' { cargo --version }
if ($env:GOROOT -notlike '*pbk-global-*') { $fails += "GOROOT not kit-isolated: $($env:GOROOT)" }
else { Write-Host "OK GOROOT=$env:GOROOT" }
if ($env:DOTNET_ROOT -notlike '*pbk-global-*') { $fails += "DOTNET_ROOT not kit-isolated: $($env:DOTNET_ROOT)" }
else { Write-Host "OK DOTNET_ROOT=$env:DOTNET_ROOT" }
if ($fails.Count) { throw ($fails -join '; ') }
Write-Host 'PROBE_PASS'
'@ | Set-Content -LiteralPath $probe -Encoding UTF8

  $outFile = Join-Path $scratch 'probe-out.txt'
  $p = Start-Process -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$probe) `
    -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError ($outFile + '.err') -WindowStyle Hidden
  $text = ''
  if (Test-Path $outFile) { $text += Get-Content $outFile -Raw -EA SilentlyContinue }
  if (Test-Path ($outFile + '.err')) { $text += Get-Content ($outFile + '.err') -Raw -EA SilentlyContinue }
  Write-Host $text
  Assert ($p.ExitCode -eq 0) "probe exit $($p.ExitCode)"
  Assert ($text -match 'PROBE_PASS') 'probe did not pass'

  Write-Host '[global] global-off...'
  & "$kit\setup.ps1" -Action configure -Mode global-off
  $globalOn = $false
  Assert (-not (Test-Path $marker)) 'marker remains after global-off'

  # New process must NOT see kit GOROOT from User env
  $probe2 = Join-Path $scratch 'probe2.ps1'
  @'
if ($env:GOROOT -like '*pbk-global-*') { throw "GOROOT still set after global-off: $($env:GOROOT)" }
Write-Host 'RESTORE_PASS'
'@ | Set-Content $probe2 -Encoding UTF8
  $out2 = Join-Path $scratch 'probe2-out.txt'
  $p2 = Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$probe2) `
    -Wait -PassThru -RedirectStandardOutput $out2 -RedirectStandardError ($out2+'.err') -WindowStyle Hidden
  $t2 = ''
  if (Test-Path $out2) { $t2 += Get-Content $out2 -Raw -EA SilentlyContinue }
  if (Test-Path ($out2+'.err')) { $t2 += Get-Content ($out2+'.err') -Raw -EA SilentlyContinue }
  Write-Host $t2
  Assert ($p2.ExitCode -eq 0 -and $t2 -match 'RESTORE_PASS') 'restore probe failed'

  Write-Host 'INDEP Windows global-on/off+run: PASS'
}
catch {
  Write-Host "FAIL: $_"
  exit 1
}
finally {
  if ($globalOn -and (Test-Path $marker)) {
    Write-Host '[global] SAFETY global-off...'
    try { & "$kit\setup.ps1" -Action configure -Mode global-off } catch { Write-Host "WARN global-off: $_" }
  }
  Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
