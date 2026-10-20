# Load into the current PowerShell process with: . .\.build\activate.ps1
$localRoot=$PSScriptRoot
$values=@{
 RUSTUP_HOME="$localRoot\rust\rustup"; CARGO_HOME="$localRoot\rust\cargo"
 GOROOT="$localRoot\go\sdk"; GOPATH="$localRoot\go\path"; GOMODCACHE="$localRoot\go\path\pkg\mod"; GOCACHE="$localRoot\go\cache"; GOENV="$localRoot\go\goenv"; GOTOOLCHAIN='local'
 DOTNET_ROOT="$localRoot\csharp\dotnet"; DOTNET_CLI_HOME="$localRoot\csharp\home"; NUGET_PACKAGES="$localRoot\csharp\nuget"; DOTNET_MULTILEVEL_LOOKUP='0'; DOTNET_CLI_TELEMETRY_OPTOUT='1'; DOTNET_NOLOGO='1'; DOTNET_SYSTEM_GLOBALIZATION_INVARIANT='1'
 JAVA_HOME="$localRoot\kotlin\jdk"; ANDROID_HOME="$localRoot\kotlin\android-sdk"; ANDROID_SDK_ROOT="$localRoot\kotlin\android-sdk"; GRADLE_USER_HOME="$localRoot\kotlin\gradle"; ANDROID_USER_HOME="$localRoot\kotlin\android-user"; ANDROID_PREFS_ROOT="$localRoot\kotlin\android-user"; ANDROID_EMULATOR_HOME="$localRoot\kotlin\android-user"; ANDROID_AVD_HOME="$localRoot\kotlin\android-user\avd"
 UV_CACHE_DIR="$localRoot\python\cache"; UV_PYTHON_INSTALL_DIR="$localRoot\python\runtimes"; UV_PYTHON_BIN_DIR="$localRoot\python\bin"; UV_PYTHON_PREFERENCE='only-managed'; UV_TOOL_DIR="$localRoot\python\tools"; UV_TOOL_BIN_DIR="$localRoot\python\bin"; PIP_CACHE_DIR="$localRoot\python\pip-cache"; PYTHONNOUSERSITE='1'
 npm_config_cache="$localRoot\nodejs\npm-cache"; npm_config_prefix="$localRoot\nodejs\npm-global"; npm_config_userconfig="$localRoot\nodejs\npmrc"; COREPACK_HOME="$localRoot\nodejs\corepack"; npm_config_update_notifier="false"
}
$ndkRoot="$localRoot\kotlin\android-sdk\ndk"
if (Test-Path $ndkRoot) {
 $ndk=Get-ChildItem $ndkRoot -Directory | Select-Object -First 1
 if ($ndk) { $values.NDK_HOME=$ndk.FullName; $values.ANDROID_NDK_HOME=$ndk.FullName }
}
foreach ($key in $values.Keys) { [Environment]::SetEnvironmentVariable($key,$values[$key],'Process') }
Remove-Item Env:UV_MANAGED_PYTHON -ErrorAction SilentlyContinue
$bins=@('go\sdk\bin','rust\cargo\bin','csharp\dotnet','kotlin\jdk\bin','kotlin\android-sdk\cmdline-tools\latest\bin','kotlin\android-sdk\platform-tools','kotlin\android-sdk\emulator','nodejs\node','python\bin')
foreach ($relative in $bins) {
 $bin=Join-Path $localRoot $relative
 if (Test-Path $bin) { $env:Path="$bin;$env:Path" }
}
Remove-Variable localRoot,values,ndkRoot,ndk,bins,relative,bin,key -ErrorAction SilentlyContinue
