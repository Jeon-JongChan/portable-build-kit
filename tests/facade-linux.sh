#!/usr/bin/env bash
# Purely local validation of the four-action Facade and removal safety.
set -euo pipefail
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
source_kit="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cp -a "$source_kit/.build" "$scratch/"
kit="$scratch/.build"
for lang in go rust kotlin csharp python nodejs; do
  menu="$(printf '0\n' | bash "$kit/$lang.sh")"
  [[ "$(printf '%s\n' "$menu" | grep -Ec '^([1-4]|0)\. ')" -eq 5 ]]
  [[ "$(printf '%s\n' "$menu" | grep -Ec '^(5|6|7|8|9)\. ')" -eq 0 ]]
done
# Configuration remains opt-in, with feature submenus only for owners.
menu="$(printf '2\n8\n0\n' | bash "$kit/kotlin.sh")"
grep -q 'Android emulator:' <<< "$menu"
menu="$(printf '2\n8\n0\n' | bash "$kit/rust.sh")"
grep -q 'Tauri 2:' <<< "$menu"
menu="$(printf '2\n8\n0\n' | bash "$kit/nodejs.sh")"
grep -q 'Vue project:' <<< "$menu"
# The public facade configuration has deterministic noninteractive routing.
bash "$kit/go.sh" configure --mode list | grep -q '^go '
bash "$kit/python.sh" configure --mode env | grep -q 'source '
# Reset requires confirmation and only deletes the selected toolchain.
mkdir -p "$kit/go/sdk" "$kit/rust/keep"
printf 'user mock\n' > "$kit/go/sdk/dummy"
if bash "$kit/go.sh" reset --scope tools > /dev/null 2>&1; then
  echo 'Unconfirmed reset unexpectedly succeeded' >&2; exit 1
fi
[[ -f "$kit/go/sdk/dummy" ]]
bash "$kit/go.sh" reset --scope tools --yes > /dev/null
[[ ! -e "$kit/go/sdk/dummy" && -d "$kit/rust/keep" ]]
# Reset-all removes an optional Node install too, not only base five.
mkdir -p "$kit/nodejs/npm-cache" "$kit/python/cache"
bash "$kit/setup.sh" reset --language all --scope all --yes > /dev/null
[[ ! -d "$kit/rust" && ! -d "$kit/nodejs" && ! -d "$kit/python" ]]
[[ -f "$kit/setup.sh" && -f "$kit/rust.sh" ]]
echo 'Facade Linux tests passed'
