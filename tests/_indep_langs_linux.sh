#!/usr/bin/env bash
# Real install: rust, python, csharp, kotlin (no emulator). Scratch under /tmp.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cp -a "$root/.build" "$scratch/"
kit="$scratch/.build"
pass=0
fail_msg() { echo "FAIL[$1]: $2" >&2; exit 1; }
ok() { echo "PASS: $*"; pass=$((pass + 1)); }

# --- Rust ---
echo '=== RUST ==='
bash "$kit/rust.sh" install
bash "$kit/rust.sh" configure --mode verify
mkdir -p "$scratch/rustproj/src"
cat >"$scratch/rustproj/Cargo.toml" <<'EOF'
[package]
name = "pbkmod"
version = "0.1.0"
edition = "2021"
EOF
printf 'fn main() {}\n' >"$scratch/rustproj/src/main.rs"
if command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; then
  bash "$kit/rust.sh" configure --mode prime --project "$scratch/rustproj"
  bash "$kit/rust.sh" configure --mode offline-check --project "$scratch/rustproj"
  ok 'rust install+verify+prime+offline'
else
  echo 'WARN: no cc/gcc on host — rust prime skipped (install+verify only)'
  ok 'rust install+verify (prime skipped: host linker)'
fi

# --- Python ---
echo '=== PYTHON ==='
bash "$kit/python.sh" install
bash "$kit/python.sh" configure --mode verify
mkdir -p "$scratch/pyproj"
cat >"$scratch/pyproj/pyproject.toml" <<'EOF'
[project]
name = "pbkmod"
version = "0.1.0"
requires-python = ">=3.13"
dependencies = []
EOF
bash "$kit/python.sh" configure --mode prime --project "$scratch/pyproj"
bash "$kit/python.sh" configure --mode offline-check --project "$scratch/pyproj"
ok 'python install+verify+prime+offline'

# --- C# ---
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

# --- Kotlin (no emulator) ---
echo '=== KOTLIN (no emulator) ==='
bash "$kit/kotlin.sh" install --accept-android-licenses
bash "$kit/kotlin.sh" configure --mode verify
[[ -x "$kit/kotlin/jdk/bin/java" ]] || fail_msg kotlin 'jdk missing'
[[ -x "$kit/kotlin/android-sdk/cmdline-tools/latest/bin/sdkmanager" ]] || fail_msg kotlin 'sdkmanager missing'
[[ -d "$kit/kotlin/android-sdk/platforms" ]] || fail_msg kotlin 'platforms missing'
[[ ! -d "$kit/kotlin/android-sdk/emulator" ]] || fail_msg kotlin 'emulator should not be installed'
ok 'kotlin install+verify no-emulator'

echo "INDEP Linux langs: $pass/4 passed"
