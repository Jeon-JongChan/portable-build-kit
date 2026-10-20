#!/usr/bin/env bash
# Resume: csharp + kotlin only (rust/python already validated this host).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cp -a "$root/.build" "$scratch/"
kit="$scratch/.build"
pass=0
ok() { echo "PASS: $*"; pass=$((pass + 1)); }
fail_msg() { echo "FAIL[$1]: $2" >&2; exit 1; }

echo '=== CSHARP ==='
bash "$kit/csharp.sh" install
bash "$kit/csharp.sh" configure --mode verify
mkdir -p "$scratch/csproj"
cat >"$scratch/csproj/pbkmod.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
EOF
printf 'Console.WriteLine("ok");\n' >"$scratch/csproj/Program.cs"
bash "$kit/csharp.sh" configure --mode prime --project "$scratch/csproj"
bash "$kit/csharp.sh" configure --mode offline-check --project "$scratch/csproj"
ok 'csharp install+verify+prime+offline'

echo '=== KOTLIN (no emulator) ==='
bash "$kit/kotlin.sh" install --accept-android-licenses
bash "$kit/kotlin.sh" configure --mode verify
[[ -x "$kit/kotlin/jdk/bin/java" ]] || fail_msg kotlin 'jdk missing'
[[ -x "$kit/kotlin/android-sdk/cmdline-tools/latest/bin/sdkmanager" ]] || fail_msg kotlin 'sdkmanager missing'
[[ -d "$kit/kotlin/android-sdk/platforms" ]] || fail_msg kotlin 'platforms missing'
[[ ! -d "$kit/kotlin/android-sdk/emulator" ]] || fail_msg kotlin 'emulator should not be installed'
ok 'kotlin install+verify no-emulator'

echo "INDEP Linux csharp+kotlin: $pass/2 passed"
