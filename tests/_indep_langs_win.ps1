#requires -Version 5.1
# Real install: rust (gnu), python, csharp, kotlin (no emulator). Scratch under %TEMP%.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('pbk-langs-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
Copy-Item (Join-Path $root '.build') (Join-Path $scratch '.build') -Recurse -Force
$kit = Join-Path $scratch '.build'
$pass = 0

function Ok([string]$msg) { Write-Host "PASS: $msg"; $script:pass++ }
function Fail([string]$lang, [string]$msg) { throw "FAIL[$lang]: $msg" }

try {
  # --- Rust (gnu: no MSVC host dependency for install/link of hello) ---
  Write-Host '=== RUST ==='
  & "$kit\rust.ps1" -Action install -RustAbi gnu
  & "$kit\rust.ps1" -Action configure -Mode verify
  $rproj = Join-Path $scratch 'rustproj'
  New-Item -ItemType Directory (Join-Path $rproj 'src') -Force | Out-Null
  Set-Content (Join-Path $rproj 'Cargo.toml') @"
[package]
name = "pbkmod"
version = "0.1.0"
edition = "2021"
"@
  Set-Content (Join-Path $rproj 'src\main.rs') 'fn main() {}'
  & "$kit\rust.ps1" -Action configure -Mode prime -Project $rproj
  & "$kit\rust.ps1" -Action configure -Mode offline-check -Project $rproj
  Ok 'rust install+verify+prime+offline'

  # --- Python ---
  Write-Host '=== PYTHON ==='
  & "$kit\python.ps1" -Action install
  & "$kit\python.ps1" -Action configure -Mode verify
  $py = Join-Path $scratch 'pyproj'
  New-Item -ItemType Directory $py -Force | Out-Null
  Set-Content (Join-Path $py 'pyproject.toml') @"
[project]
name = "pbkmod"
version = "0.1.0"
requires-python = ">=3.13"
dependencies = []
"@
  & "$kit\python.ps1" -Action configure -Mode prime -Project $py
  & "$kit\python.ps1" -Action configure -Mode offline-check -Project $py
  Ok 'python install+verify+prime+offline'

  # --- C# ---
  Write-Host '=== CSHARP ==='
  & "$kit\csharp.ps1" -Action install
  & "$kit\csharp.ps1" -Action configure -Mode verify
  $cs = Join-Path $scratch 'csproj'
  New-Item -ItemType Directory $cs -Force | Out-Null
  Set-Content (Join-Path $cs 'pbkmod.csproj') @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
"@
  Set-Content (Join-Path $cs 'Program.cs') 'Console.WriteLine("ok");'
  & "$kit\csharp.ps1" -Action configure -Mode prime -Project $cs
  & "$kit\csharp.ps1" -Action configure -Mode offline-check -Project $cs
  Ok 'csharp install+verify+prime+offline'

  # --- Kotlin (no emulator) ---
  Write-Host '=== KOTLIN (no emulator) ==='
  & "$kit\kotlin.ps1" -Action install -AcceptAndroidLicenses
  & "$kit\kotlin.ps1" -Action configure -Mode verify
  if (-not (Test-Path (Join-Path $kit 'kotlin\jdk\bin\java.exe'))) { Fail 'kotlin' 'jdk missing' }
  if (-not (Test-Path (Join-Path $kit 'kotlin\android-sdk\cmdline-tools\latest\bin\sdkmanager.bat'))) { Fail 'kotlin' 'sdkmanager missing' }
  if (-not (Test-Path (Join-Path $kit 'kotlin\android-sdk\platforms'))) { Fail 'kotlin' 'platforms missing' }
  if (Test-Path (Join-Path $kit 'kotlin\android-sdk\emulator')) { Fail 'kotlin' 'emulator should not be installed' }
  Ok 'kotlin install+verify no-emulator'

  Write-Host "INDEP Windows langs: $pass/4 passed"
}
catch {
  Write-Host "FAIL: $_"
  exit 1
}
finally {
  Write-Host "Cleaning $scratch"
  Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
