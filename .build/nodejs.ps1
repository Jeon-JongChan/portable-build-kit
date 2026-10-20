#requires -Version 5.1
<#
Node.js - 독립 실행 스크립트 (Windows x64, PowerShell 5.1+).
이 파일 하나만 프로젝트에 복사하면 되며, 도구는 스크립트 옆 nodejs\ 폴더에 설치된다.
  .\nodejs.ps1 [-Action install|verify|update|reset -Yes|env|run -CommandArgs ...]
  현재 세션에 환경 적용: . .\nodejs.ps1 -Action env   (dot-source)
#>
[CmdletBinding()]
param(
 [ValidateSet('install','verify','update','reset','env','run','vue-init')][string]$Action='install',
 [int]$NodeMajor=24, [string]$Project='',
 [switch]$Yes, [string[]]$CommandArgs=@()
)
$Lang='nodejs'
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
 if ($env:OS -ne 'Windows_NT') { throw 'Use nodejs.sh on Linux.' }
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
 [ordered]@{
  'npm_config_cache'=(Join-Path $Root 'nodejs\npm-cache'); 'npm_config_prefix'=(Join-Path $Root 'nodejs\npm-global'); 'npm_config_userconfig'=(Join-Path $Root 'nodejs\npmrc')
  'COREPACK_HOME'=(Join-Path $Root 'nodejs\corepack'); 'npm_config_update_notifier'='false'
 }
}
function EnvPaths { @('nodejs\node') | ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container } }
function Install {
 $node=Join-Path $Root 'nodejs\node\node.exe'
 if (Test-Path $node) { Log 'Node.js already present'; return }
 $list=(Invoke-WebRequest -Uri "https://nodejs.org/dist/latest-v$NodeMajor.x/SHASUMS256.txt" -UseBasicParsing).Content
 $match=[regex]::Match($list,"(?m)^([0-9a-fA-F]{64})\s+(node-v$NodeMajor\.[0-9]+\.[0-9]+-win-x64\.zip)\s*$")
 if (-not $match.Success) { throw "Node.js $NodeMajor LTS Windows archive not found" }
 $filename=$match.Groups[2].Value
 $file=Join-Path $State $filename
 Download "https://nodejs.org/dist/latest-v$NodeMajor.x/$filename" $file
 CheckSha $file $match.Groups[1].Value
 Unpack $file (Join-Path $Root 'nodejs\node'); Remove-Item $file -Force
}
function Verify {
 & (Join-Path $Root 'nodejs\node\node.exe') --version; AssertExit 'Node verification failed'
 & (Join-Path $Root 'nodejs\node\npm.cmd') --version; AssertExit 'npm verification failed'
}
function Update {
 $node=Join-Path $Root 'nodejs\node'; $exe=Join-Path $node 'node.exe'
 if (-not (Test-Path $exe)) { throw 'Install Node.js first' }
 $sums=[string](Invoke-WebRequest -Uri "https://nodejs.org/dist/latest-v$NodeMajor.x/SHASUMS256.txt" -UseBasicParsing).Content
 $matched=[regex]::Match($sums,'node-(v[0-9]+\.[0-9]+\.[0-9]+)-win-x64\.zip')
 if (-not $matched.Success) { throw 'Cannot resolve latest Node.js patch' }
 $latest=$matched.Groups[1].Value
 if ((& $exe --version) -eq $latest) { Log "Node.js already at $latest"; return }
 $backup=Join-Path $State 'update-backup-nodejs'
 if (Test-Path $backup) { throw "Incomplete previous update: $backup" }
 New-Item -ItemType Directory -Path $State -Force | Out-Null
 Move-Item -LiteralPath $node -Destination $backup
 try { Install; Remove-Item -LiteralPath $backup -Recurse -Force }
 catch { Remove-Item -LiteralPath $node -Recurse -Force -ErrorAction SilentlyContinue; Move-Item -LiteralPath $backup -Destination $node; throw }
}
# 빈 폴더(-Project, 기본: 현재 폴더)에 Vue(TypeScript) 프로젝트를 생성한다
function VueInit {
 Install; Activate
 $target=if ($Project) { $Project } else { (Get-Location).Path }
 if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Project directory not found: $target" }
 if (@(Get-ChildItem -LiteralPath $target -Force).Count -gt 0) { throw "Vue target must be an empty directory: $target" }
 Push-Location $target
 try { & npm.cmd create vue@latest '--' '--typescript' '.'; AssertExit 'Vue scaffold failed' }
 finally { Pop-Location }
}

function Extra { if ($Action -eq 'vue-init') { VueInit } else { throw "Unsupported action: $Action" } }

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
