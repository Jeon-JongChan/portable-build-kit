#requires -Version 5.1
<#
Go - 독립 실행 스크립트 (Windows x64, PowerShell 5.1+).
이 파일 하나만 프로젝트에 복사하면 되며, 도구는 스크립트 옆 go\ 폴더에 설치된다.
  .\go.ps1 [-Action install|verify|update|reset -Yes|env|run -CommandArgs ...]
  현재 세션에 환경 적용: . .\go.ps1 -Action env   (dot-source)
#>
[CmdletBinding()]
param(
 [ValidateSet('install','verify','update','reset','env','run')][string]$Action='install',
 [string]$GoVersion='1.27.2',
 [switch]$Yes, [string[]]$CommandArgs=@()
)
$Lang='go'
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
 if ($env:OS -ne 'Windows_NT') { throw 'Use go.sh on Linux.' }
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

$script:GoVersionSpecified=$PSBoundParameters.ContainsKey('GoVersion')
function EnvMap {
 [ordered]@{
  'GOROOT'=(Join-Path $Root 'go\sdk'); 'GOPATH'=(Join-Path $Root 'go\path'); 'GOMODCACHE'=(Join-Path $Root 'go\path\pkg\mod')
  'GOCACHE'=(Join-Path $Root 'go\cache'); 'GOENV'=(Join-Path $Root 'go\goenv'); 'GOTOOLCHAIN'='local'
 }
}
function EnvPaths { @('go\sdk\bin') | ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container } }
function Install {
 $out=Join-Path $Root 'go\sdk'
 if (Test-Path (Join-Path $out 'bin\go.exe')) { Log 'Go already present'; return }
 # include=all: 기본 목록은 최신 패치만 담아 고정 버전이 새 패치 출시 즉시 사라짐
 # ForEach-Object 펼침: PS 5.1은 JSON 배열을 단일 객체로 내보내 @()가 [전체배열] 1개로 감싼다
 $releases=@(Invoke-RestMethod -Uri 'https://go.dev/dl/?mode=json&include=all' | ForEach-Object { $_ })
 $release=$releases | Where-Object { $_.version -eq "go$GoVersion" } | Select-Object -First 1
 if (-not $release) { throw "Go $GoVersion not found" }
 $pkg=$release.files | Where-Object { $_.os -eq 'windows' -and $_.arch -eq 'amd64' -and $_.kind -eq 'archive' -and $_.filename -like '*.zip' } | Select-Object -First 1
 if (-not $pkg) { throw 'Go Windows x64 zip not found' }
 $file=Join-Path $State $pkg.filename
 Download "https://go.dev/dl/$($pkg.filename)" $file; CheckSha $file $pkg.sha256
 Unpack $file $out; Remove-Item $file -Force
}
function Verify { & (Join-Path $Root 'go\sdk\bin\go.exe') version; AssertExit 'Go verification failed' }
function Update {
 $sdk=Join-Path $Root 'go\sdk'; $exe=Join-Path $sdk 'bin\go.exe'
 if (-not (Test-Path $exe)) { throw 'Install Go first' }
 if (-not $script:GoVersionSpecified) {
  $releases=@(Invoke-RestMethod -Uri 'https://go.dev/dl/?mode=json' | ForEach-Object { $_ })
  $script:GoVersion=[string]$releases[0].version -replace '^go',''
 }
 if ((& $exe version) -match ('go'+[regex]::Escape($GoVersion)+'\s')) { Log 'Go already current'; return }
 $backup=Join-Path $State 'update-backup-go'
 if (Test-Path $backup) { throw "Incomplete previous update: $backup" }
 New-Item -ItemType Directory -Path $State -Force | Out-Null
 Move-Item -LiteralPath $sdk -Destination $backup
 try { Install; Remove-Item -LiteralPath $backup -Recurse -Force }
 catch { Remove-Item -LiteralPath $sdk -Recurse -Force -ErrorAction SilentlyContinue; Move-Item -LiteralPath $backup -Destination $sdk; throw }
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
