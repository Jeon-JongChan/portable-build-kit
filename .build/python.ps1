#requires -Version 5.1
<#
Python (uv) - 독립 실행 스크립트 (Windows x64, PowerShell 5.1+).
이 파일 하나만 프로젝트에 복사하면 되며, 도구는 스크립트 옆 python\ 폴더에 설치된다.
  .\python.ps1 [-Action install|verify|update|reset -Yes|env|run -CommandArgs ...]
  현재 세션에 환경 적용: . .\python.ps1 -Action env   (dot-source)
#>
[CmdletBinding()]
param(
 [ValidateSet('install','verify','update','reset','env','run')][string]$Action='install',
 [string]$PythonVersion='3.13',
 [switch]$Yes, [string[]]$CommandArgs=@()
)
$Lang='python'
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
 if ($env:OS -ne 'Windows_NT') { throw 'Use python.sh on Linux.' }
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

function EnvMap {
 # ponytail: UV_MANAGED_PYTHON conflicts with UV_PYTHON_PREFERENCE on uv>=0.13
 [ordered]@{
  'UV_CACHE_DIR'=(Join-Path $Root 'python\cache'); 'UV_PYTHON_INSTALL_DIR'=(Join-Path $Root 'python\runtimes'); 'UV_PYTHON_BIN_DIR'=(Join-Path $Root 'python\bin')
  'UV_PYTHON_PREFERENCE'='only-managed'; 'UV_TOOL_DIR'=(Join-Path $Root 'python\tools'); 'UV_TOOL_BIN_DIR'=(Join-Path $Root 'python\bin')
  'PIP_CACHE_DIR'=(Join-Path $Root 'python\pip-cache'); 'PYTHONNOUSERSITE'='1'
 }
}
function EnvPaths { @('python\bin') | ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container } }
# uv 설치/갱신 (UV_UNMANAGED_INSTALL: PATH/프로필 수정 없이 지정 폴더에만 설치)
function UvInstall {
 New-Item -ItemType Directory (Join-Path $Root 'python\bin') -Force | Out-Null
 $installer=Join-Path $State 'uv-install.ps1'
 Download 'https://astral.sh/uv/install.ps1' $installer
 $env:UV_UNMANAGED_INSTALL=Join-Path $Root 'python\bin'
 & $installer
}
function Install {
 $uv=Join-Path $Root 'python\bin\uv.exe'
 if (-not (Test-Path $uv)) { UvInstall; if (-not (Test-Path $uv)) { throw 'uv installation failed' } }
 Activate
 & $uv python install $PythonVersion --default
 AssertExit 'Python runtime installation failed'
 $py=Join-Path $Root 'python\bin\python.exe'
 if (-not (Test-Path $py)) { throw 'Portable python.exe missing from python\bin' }
 & $py --version; AssertExit 'Portable Python binary verification failed'
}
function Verify {
 & (Join-Path $Root 'python\bin\uv.exe') python list --only-installed; AssertExit 'uv Python verification failed'
 & (Join-Path $Root 'python\bin\python.exe') --version; AssertExit 'Python verification failed'
}
function Update {
 if (-not (Test-Path (Join-Path $Root 'python\bin\uv.exe'))) { throw 'Install Python first' }
 UvInstall; AssertExit 'uv refresh failed'
 Activate; & uv python install $PythonVersion --default; AssertExit 'Python refresh failed'
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
