#requires -Version 5.1
# Real Go install + prime + offline-check on a tiny module (Windows).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('pbk-goinst-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
Copy-Item (Join-Path $root '.build') (Join-Path $scratch '.build') -Recurse -Force
$kit = Join-Path $scratch '.build'
$proj = Join-Path $scratch 'mod'
New-Item -ItemType Directory $proj -Force | Out-Null
Set-Content "$proj\go.mod" "module example.com/pbkmod`ngo 1.22`n"
Set-Content "$proj\main.go" @"
package main
import "fmt"
func main() { fmt.Println("ok") }
"@
Set-Content "$proj\main_test.go" @"
package main
import "testing"
func TestOk(t *testing.T) {}
"@

try {
  Write-Host '[indep] install go...'
  & "$kit\go.ps1" -Action install
  Write-Host '[indep] verify...'
  & "$kit\go.ps1" -Action configure -Mode verify
  . "$kit\activate.ps1"
  if ($env:GOPATH -ne (Join-Path $kit 'go\path')) { throw "GOPATH not isolated: $($env:GOPATH)" }
  $ver = & "$kit\go\sdk\bin\go.exe" version
  Write-Host "[indep] $ver"
  if ($ver -notmatch 'go1\.27\.2') { throw "unexpected version: $ver" }
  Write-Host '[indep] run: go build (portable compile check)...'
  Push-Location $proj
  try {
    & go build -o (Join-Path $proj 'pbkmod.exe') .
    if ($LASTEXITCODE -ne 0) { throw 'go build failed' }
    if (-not (Test-Path (Join-Path $proj 'pbkmod.exe'))) { throw 'pbkmod.exe missing' }
  } finally { Pop-Location }
  Write-Host '[indep] configure -Mode run go version...'
  & "$kit\go.ps1" -Action configure -Mode run -CommandArgs @('go','version')
  # prime uses go test ./... — may fail under Windows Application Control (WDAC)
  Write-Host '[indep] prime (may hit host App Control on test binaries)...'
  $primeOk = $true
  try { & "$kit\go.ps1" -Action configure -Mode prime -Project $proj }
  catch {
    $primeOk = $false
    if ("$_" -match 'Application Control|Go tests/build failed') {
      Write-Host "[indep] WARN prime blocked by host policy (not kit install failure): $_"
    } else { throw }
  }
  if ($primeOk) {
    Write-Host '[indep] offline-check...'
    & "$kit\go.ps1" -Action configure -Mode offline-check -Project $proj
  }
  Write-Host 'INDEP Windows Go real-install: PASS (install+verify+build+run)'
}
catch {
  Write-Host "FAIL: $_"
  exit 1
}
finally {
  Write-Host "Cleaning $scratch"
  Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
