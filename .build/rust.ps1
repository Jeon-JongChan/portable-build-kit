#requires -Version 5.1
<#
Rust - 독립 실행 스크립트 (Windows x64, PowerShell 5.1+).
이 파일 하나만 프로젝트에 복사하면 되며, 도구는 스크립트 옆 rust\ 폴더에 설치된다.
  .\rust.ps1 [-Action install|verify|update|reset -Yes|env|run -CommandArgs ...]
  현재 세션에 환경 적용: . .\rust.ps1 -Action env   (dot-source)
#>
[CmdletBinding()]
param(
 [ValidateSet('install','verify','update','reset','env','run')][string]$Action='install',
 [ValidateSet('msvc','gnu')][string]$RustAbi='msvc',
 [switch]$Yes, [string[]]$CommandArgs=@()
)
$Lang='rust'
$Root=$PSScriptRoot
$State=Join-Path $Root "$Lang\_state"
# dot-source(env)일 때는 호출자 세션의 엄격 모드/오류 설정을 바꾸지 않는다
if ($Action -ne 'env') {
 Set-StrictMode -Version Latest
 $ErrorActionPreference='Stop'
 [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
 # PS 5.1 진행률 표시는 Invoke-WebRequest 다운로드를 수십 배 느리게 함
 $ProgressPreference='SilentlyContinue'
 if (-not [Environment]::Is64BitOperatingSystem) { throw 'A 64-bit Windows host is required.' }
 if ($env:OS -ne 'Windows_NT') { throw 'Use rust.sh on Linux.' }
}

function Log([string]$Message) { Write-Host "[build-kit] $Message" }
function AssertExit([string]$Message) { if ($LASTEXITCODE -ne 0) { throw "$Message (exit $LASTEXITCODE)" } }
function Download([string]$Url,[string]$Destination) {
 New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
 Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -MaximumRedirection 12
}
function CheckSha([string]$File,[string]$Expected) {
 if ($Expected -notmatch '^[0-9a-fA-F]{64}$') { throw "Invalid SHA256 for $File" }
 if ((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ine $Expected) { throw "SHA256 mismatch for $File" }
}
function Unpack([string]$Archive,[string]$Destination) {
 $staging=Join-Path $State ("extract-" + [Guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $staging,$Destination -Force | Out-Null
 try {
  # Windows 내장 bsdtar는 zip도 처리하며 PS 5.1 Expand-Archive(수천 파일에 수십 분)보다 훨씬 빠름
  & (Join-Path $env:SystemRoot 'System32\tar.exe') -xf $Archive -C $staging; AssertExit 'Cannot extract archive'
  $items=@(Get-ChildItem -LiteralPath $staging -Force)
  $src=$staging
  if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $src=$items[0].FullName }
  foreach ($item in (Get-ChildItem -LiteralPath $src -Force)) {
   $existing=Join-Path $Destination $item.Name
   # 같은 볼륨이므로 이동은 즉시 끝남. 기존 항목이 있으면 덮어쓰기 복사
   if (Test-Path -LiteralPath $existing) { Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force }
   else { Move-Item -LiteralPath $item.FullName -Destination $existing }
  }
 } finally { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
}

function EnvMap { [ordered]@{ 'RUSTUP_HOME'=(Join-Path $Root 'rust\rustup'); 'CARGO_HOME'=(Join-Path $Root 'rust\cargo') } }
function EnvPaths { @('rust\cargo\bin') | ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container } }
function HasMsvc {
 <# MSVC 링커 존재 여부. 일반 터미널 PATH에는 link.exe가 없으므로 rustup과 같은 vswhere 탐지도 허용 #>
 if (Get-Command link.exe -ErrorAction SilentlyContinue) { return $true }
 $vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
 if (-not (Test-Path -LiteralPath $vswhere)) { return $false }
 return [bool](& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
}
function Install {
 $cargo=Join-Path $Root 'rust\cargo\bin\cargo.exe'
 if (Test-Path $cargo) { Log 'Rust already present'; return }
 if ($RustAbi -eq 'msvc' -and -not (HasMsvc)) {
  throw 'Rust MSVC needs an existing Windows SDK/MSVC linker. Run in a Developer Command Prompt or use -RustAbi gnu for minimal standalone Rust; no system-wide Visual Studio install will be attempted.'
 }
 $base='https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe'
 $installer=Join-Path $State 'rustup-init.exe'
 Download ($base+'.sha256') ($installer+'.sha256')
 $hash=([regex]::Match((Get-Content -Raw ($installer+'.sha256')), '[0-9a-fA-F]{64}')).Value
 Download $base $installer; CheckSha $installer $hash
 Activate
 & $installer -y --no-modify-path --profile minimal --default-toolchain stable --default-host "x86_64-pc-windows-$RustAbi"
 AssertExit 'Rustup installation failed'
 Remove-Item $installer,($installer+'.sha256') -Force
 Log 'Rust installed. Windows MSVC linker/SDK is a separate host prerequisite for native Rust linking.'
}
function Verify { & (Join-Path $Root 'rust\cargo\bin\rustc.exe') --version; AssertExit 'Rust verification failed' }
function Update {
 if (-not (Test-Path (Join-Path $Root 'rust\cargo\bin\rustup.exe'))) { throw 'Install Rust first' }
 Activate; & rustup set profile minimal; AssertExit 'Rust profile failed'
 & rustup update stable; AssertExit 'Rust update failed'
}

function Extra { throw "Unsupported action: $Action" }

# 현재 프로세스에 환경변수와 PATH를 적용한다 (사용자/시스템 전역 설정은 건드리지 않음)
function Activate {
 $map=EnvMap
 foreach ($key in $map.Keys) { [Environment]::SetEnvironmentVariable($key,$map[$key],'Process') }
 # uv>=0.13 에서 UV_PYTHON_PREFERENCE 와 충돌하는 구형 플래그 제거
 Remove-Item Env:UV_MANAGED_PYTHON -ErrorAction SilentlyContinue
 $paths=@(EnvPaths)
 if ($paths.Count -gt 0) { $env:Path=($paths -join ';')+';'+$env:Path }
}
switch ($Action) {
 install { Install }
 verify { Activate; Verify }
 update { Update }
 reset {
  if (-not $Yes) { throw 'Reset deletes tools; pass -Yes after reviewing' }
  $dir=Join-Path $Root $Lang
  if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
  Log "Removed $Lang"
 }
 env { Activate; Log "$Lang environment active in this session" }
 run {
  Activate
  if ($CommandArgs.Count -eq 0) { throw 'Specify -CommandArgs' }
  $rest=@(); if ($CommandArgs.Count -gt 1) { $rest=@($CommandArgs[1..($CommandArgs.Count-1)]) }
  & $CommandArgs[0] @rest; AssertExit 'Command failed'
 }
 default { Extra }
}
