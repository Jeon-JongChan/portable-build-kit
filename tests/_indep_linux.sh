#!/usr/bin/env bash
# Independent Linux checks (not the shipped smoke suite).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cp -a "$root/.build" "$scratch/"
kit="$scratch/.build"
pass=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; pass=$((pass + 1)); }
expect_fail() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then fail "expected fail: $name"; else ok "expect-fail $name"; fi
}

expect_fail go+emulator bash "$kit/go.sh" configure --feature emulator --operation install --accept-android-licenses
expect_fail kotlin+tauri bash "$kit/kotlin.sh" configure --feature tauri --operation install
expect_fail go+vue bash "$kit/go.sh" configure --feature vue --operation init
expect_fail rust-vue-init bash "$kit/rust.sh" vue-init
expect_fail nodejs-tauri bash "$kit/nodejs.sh" tauri-install
expect_fail prime-no-gomod bash "$kit/go.sh" configure --mode prime
expect_fail offline-no-gomod bash "$kit/go.sh" configure --mode offline-check
expect_fail verify-no-go bash "$kit/go.sh" configure --mode verify
expect_fail reset-no-yes bash "$kit/go.sh" reset --scope tools
expect_fail prime-all bash "$kit/setup.sh" prime --language all
expect_fail offline-all bash "$kit/setup.sh" offline-check --language all

[[ -f "$kit/env.sh" ]] || fail 'env.sh missing'
bash -c 'source "$1/env.sh"; [[ "$GOROOT" == "$1/go/sdk" ]]' _ "$kit" || fail 'env.sh GOROOT'
ok 'env.sh GOROOT'

out="$(bash "$kit/setup.sh" configure --mode list)"
printf '%s\n' "$out" | grep -q '^go ' || fail 'list format'
ok 'list format'

proj="$scratch/tinygo"
mkdir -p "$proj"
printf 'module example.com/tiny\ngo 1.22\n' >"$proj/go.mod"
printf 'package main\nfunc main(){}\n' >"$proj/main.go"
expect_fail prime-no-binary bash "$kit/go.sh" configure --mode prime --project "$proj"

a="$(bash "$kit/go.sh" configure --mode list)"
b="$(bash "$kit/setup.sh" configure --language go --mode list)"
[[ "$a" == "$b" ]] || fail 'adapter/setup list mismatch'
ok 'adapter-setup list match'

mkdir -p "$kit/go/sdk" "$kit/rust/keep"
echo x >"$kit/go/sdk/x"
bash "$kit/go.sh" reset --scope tools --yes >/dev/null
[[ ! -e "$kit/go/sdk/x" && -d "$kit/rust/keep" ]] || fail 'reset scope'
ok 'reset scope isolation'

# install all excludes nodejs
grep -q "echo 'go rust kotlin csharp python'" "$kit/setup.sh" || fail 'langs() should exclude nodejs from all'
ok 'install-all excludes nodejs'

# bash -n syntax
bash -n "$kit/setup.sh"
for lang in go rust kotlin csharp python nodejs; do bash -n "$kit/$lang.sh"; done
ok 'bash -n all sh'

echo "INDEP Linux boundary: $pass checks passed"
