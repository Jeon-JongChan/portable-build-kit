#requires -Version 5.1
<#
Kotlin / Android (JDK + Android SDK) - 독립 실행 스크립트 (Windows x64, PowerShell 5.1+).
이 파일 하나만 프로젝트에 복사하면 되며, 도구는 스크립트 옆 kotlin\ 폴더에 설치된다.
  .\kotlin.ps1 [-Action install|verify|update|reset -Yes|env|run -CommandArgs ...]
  현재 세션에 환경 적용: . .\kotlin.ps1 -Action env   (dot-source)
#>
[CmdletBinding()]
param(
 [ValidateSet('install','verify','update','reset','env','run','emulator-install','emulator-list','emulator-start','emulator-remove')][string]$Action='install',
 [int]$AndroidApi=36, [string]$BuildTools='36.0.0', [string]$NdkVersion='27.2.12479018',
 [switch]$WithNdk, [switch]$WithAdb, [switch]$AcceptAndroidLicenses, [int]$JdkMajor=21,
 [ValidateSet('x86_64','arm64-v8a')][string]$EmulatorAbi='x86_64',
 [ValidateSet('default','google_apis')][string]$EmulatorFlavor='google_apis',
 [ValidatePattern('^[A-Za-z][A-Za-z0-9_.-]{0,63}$')][string]$AvdName='pbk_android',
 [switch]$Headless, [switch]$PurgeEmulatorPackages,
 [switch]$Yes, [string[]]$CommandArgs=@()
)
$Lang='kotlin'
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
 if ($env:OS -ne 'Windows_NT') { throw 'Use kotlin.sh on Linux.' }
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
 $e=[ordered]@{
  'JAVA_HOME'=(Join-Path $Root 'kotlin\jdk'); 'ANDROID_HOME'=(Join-Path $Root 'kotlin\android-sdk'); 'ANDROID_SDK_ROOT'=(Join-Path $Root 'kotlin\android-sdk')
  'GRADLE_USER_HOME'=(Join-Path $Root 'kotlin\gradle'); 'ANDROID_USER_HOME'=(Join-Path $Root 'kotlin\android-user'); 'ANDROID_PREFS_ROOT'=(Join-Path $Root 'kotlin\android-user')
  'ANDROID_EMULATOR_HOME'=(Join-Path $Root 'kotlin\android-user'); 'ANDROID_AVD_HOME'=(Join-Path $Root 'kotlin\android-user\avd')
 }
 $ndk=Join-Path $Root 'kotlin\android-sdk\ndk'
 if (Test-Path $ndk) {
  $dir=Get-ChildItem -LiteralPath $ndk -Directory | Select-Object -First 1
  if ($null -ne $dir) { $e['NDK_HOME']=$dir.FullName; $e['ANDROID_NDK_HOME']=$dir.FullName }
 }
 return $e
}
function EnvPaths {
 @('kotlin\jdk\bin','kotlin\android-sdk\cmdline-tools\latest\bin','kotlin\android-sdk\platform-tools','kotlin\android-sdk\emulator') |
  ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
}
function Install {
 $jdk=Join-Path $Root 'kotlin\jdk'
 $sdk=Join-Path $Root 'kotlin\android-sdk'
 if (-not (Test-Path (Join-Path $jdk 'bin\java.exe'))) {
  $api="https://api.adoptium.net/v3/assets/latest/$JdkMajor/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse"
  $release=@(Invoke-RestMethod -Uri $api | ForEach-Object { $_ })[0]
  if (-not $release.binary.package.link -or -not $release.binary.package.checksum) { throw 'Temurin JDK metadata unavailable' }
  $file=Join-Path $State 'temurin.zip'
  Download $release.binary.package.link $file
  CheckSha $file $release.binary.package.checksum
  Unpack $file $jdk; Remove-Item $file -Force
 }
 $mgr=Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
 if (-not (Test-Path $mgr)) {
  $file=Join-Path $State 'android-cli.zip'
  Download 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip' $file
  CheckSha $file '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'
  Unpack $file (Join-Path $sdk 'cmdline-tools\latest'); Remove-Item $file -Force
 }
 Activate
 if ($AcceptAndroidLicenses) {
  $answers=Join-Path $State 'android-licenses.txt'
  Set-Content -LiteralPath $answers -Value (@('y') * 80) -Encoding ASCII
  # sdkmanager.bat ignores PowerShell pipeline stdin; feed via cmd
  $licCmd = "`"$mgr`" --sdk_root=`"$sdk`" --licenses < `"$answers`""
  cmd.exe /c $licCmd | Out-Null
  AssertExit 'Android SDK license acceptance failed'
  Remove-Item $answers -Force
 } else { Log 'Android SDK licenses not auto-accepted. Rerun with -AcceptAndroidLicenses after reviewing the terms.' }
 $pkgs=@("platforms;android-$AndroidApi","build-tools;$BuildTools")
 if ($WithAdb) { $pkgs+= 'platform-tools' }
 if ($WithNdk) { $pkgs+= "ndk;$NdkVersion" }
 & $mgr "--sdk_root=$sdk" --install @pkgs
 AssertExit 'Android SDK package installation failed'
 $plat=Join-Path $sdk "platforms\android-$AndroidApi"
 $bt=Join-Path $sdk "build-tools\$BuildTools"
 if (-not (Test-Path $plat) -or -not (Test-Path $bt)) {
  throw "Android packages missing after install (licenses may be unaccepted). platforms=$plat build-tools=$bt"
 }
 Log "Installed Android API $AndroidApi + Build Tools $BuildTools only (NDK=$WithNdk, ADB=$WithAdb)."
}
function Verify {
 & (Join-Path $Root 'kotlin\jdk\bin\java.exe') -version; AssertExit 'JDK verification failed'
 & (Join-Path $Root 'kotlin\android-sdk\cmdline-tools\latest\bin\sdkmanager.bat') "--sdk_root=$env:ANDROID_HOME" --list_installed
 AssertExit 'Android SDK verification failed'
}
function Update {
 if (-not (Test-Path (Join-Path $Root 'kotlin\android-sdk\cmdline-tools\latest\bin\sdkmanager.bat'))) { throw 'Install Kotlin SDK first' }
 Install
 Log 'Requested Android SDK pins ensured. JDK/CLI upgrades require explicit tested pins.'
}
# 선택 기능: Android 에뮬레이터/AVD (기본 설치에는 포함되지 않음)
function AndroidImagePackage { return "system-images;android-$AndroidApi;$EmulatorFlavor;$EmulatorAbi" }
function AndroidEmulatorReady {
 $sdk=Join-Path $Root 'kotlin\android-sdk'
 if (-not (Test-Path (Join-Path $sdk 'cmdline-tools\latest\bin\avdmanager.bat'))) { throw 'Android tools absent: install Kotlin first' }
 Activate
 New-Item -ItemType Directory -Path $env:ANDROID_AVD_HOME,$env:ANDROID_EMULATOR_HOME -Force | Out-Null
}
function EmulatorInstall {
 Install
 AndroidEmulatorReady
 $sdk=Join-Path $Root 'kotlin\android-sdk'
 $mgr=Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
 $avd=Join-Path $sdk 'cmdline-tools\latest\bin\avdmanager.bat'
 $package=AndroidImagePackage
 & $mgr "--sdk_root=$sdk" --install 'emulator' 'platform-tools' $package
 AssertExit 'Emulator/system image download failed'
 if (-not (Test-Path (Join-Path $sdk 'emulator\emulator.exe'))) { throw 'Emulator executable missing' }
 if (Test-Path (Join-Path $env:ANDROID_AVD_HOME "$AvdName.ini")) { Log "AVD already present: $AvdName"; return }
 'no' | & $avd create avd -n $AvdName -k $package --force
 AssertExit 'AVD creation failed'
 if (-not (Test-Path (Join-Path $env:ANDROID_AVD_HOME "$AvdName.ini"))) { throw 'AVD created outside portable directory or not created' }
 Log "Emulator ready: $AvdName ($package). Requires usable host virtualization."
}
function EmulatorList {
 AndroidEmulatorReady
 & (Join-Path $Root 'kotlin\android-sdk\cmdline-tools\latest\bin\avdmanager.bat') list avd
 AssertExit 'Unable to list AVDs'
}
function EmulatorStart {
 AndroidEmulatorReady
 if (-not (Test-Path (Join-Path $env:ANDROID_AVD_HOME "$AvdName.ini"))) { throw "AVD not found: $AvdName" }
 $exe=Join-Path $Root 'kotlin\android-sdk\emulator\emulator.exe'
 if (-not (Test-Path $exe)) { throw 'Install emulator package first' }
 $arguments=@('-avd',$AvdName,'-no-snapshot')
 if ($Headless) { $arguments+=@('-no-window','-no-audio') }
 Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
 Log "Started AVD $AvdName (host hypervisor support is required)."
}
function EmulatorRemove {
 AndroidEmulatorReady
 $sdk=Join-Path $Root 'kotlin\android-sdk'
 $avd=Join-Path $sdk 'cmdline-tools\latest\bin\avdmanager.bat'
 $mgr=Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
 if (Test-Path (Join-Path $env:ANDROID_AVD_HOME "$AvdName.ini")) { & $avd delete avd -n $AvdName; AssertExit 'AVD deletion failed'; Log "Removed AVD $AvdName" }
 else { Log "AVD not found: $AvdName" }
 if ($PurgeEmulatorPackages) {
  if (@(Get-ChildItem -LiteralPath $env:ANDROID_AVD_HOME -Filter '*.ini').Count -gt 0) { throw 'Other AVDs remain; shared emulator and system image not removed' }
  & $mgr "--sdk_root=$sdk" --uninstall (AndroidImagePackage) 'emulator'
  AssertExit 'Emulator SDK package removal failed'
  Log 'Removed selected system image and emulator package; platform-tools retained.'
 }
}

function Extra { switch ($Action) { 'emulator-install' {EmulatorInstall} 'emulator-list' {EmulatorList} 'emulator-start' {EmulatorStart} 'emulator-remove' {EmulatorRemove} default { throw "Unsupported action: $Action" } } }

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
