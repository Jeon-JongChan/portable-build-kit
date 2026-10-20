#!/usr/bin/env bash
set -euo pipefail
kit_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"; trap 'rm -rf "$temp"' EXIT
cp -a "$kit_root/.build" "$temp/"
root="$temp/.build"; project="$temp/frontend"
mkdir -p "$root/nodejs/node/bin" "$root/rust/cargo/bin" "$project/src-tauri"
cat > "$root/nodejs/node/bin/node" <<'N'
#!/bin/sh
printf 'mock-node v0\n'
N
cat > "$root/nodejs/node/bin/npm" <<'N'
#!/bin/bash
set -e
case "$1" in
ci) mkdir -p node_modules/.bin; printf 'ok\n' > node_modules/.bin/dummy ;;
run) [[ -d node_modules ]] || exit 12; printf 'build ok\n' > .mock-build-ok ;;
create) printf '{"name":"example","version":"1.0.0"}\n' > package.json; printf '{"lockfileVersion":3,"packages":{}}\n' > package-lock.json ;;
*) exit 13;;
esac
N
cat > "$root/rust/cargo/bin/cargo" <<'N'
#!/bin/bash
exit 0
N
cat > "$root/rust/cargo/bin/rustc" <<'N'
#!/bin/bash
exit 0
N
chmod +x "$root/nodejs/node/bin/"* "$root/rust/cargo/bin/"*
printf '{"name":"example","version":"1.0.0"}\n' > "$project/package.json"
printf '{"lockfileVersion":3,"packages":{}}\n' > "$project/package-lock.json"
printf '[package]\nname="smoke"\nversion="0.1.0"\nedition="2021"\n' > "$project/src-tauri/Cargo.toml"
bash "$root/nodejs.sh" configure --mode prime --project "$project"
[[ -L "$project/node_modules" ]]
[[ -f "$project/.mock-build-ok" ]]
find "$root/nodejs/projects" -name dummy -type f | grep -q dummy
bash "$root/nodejs.sh" configure --mode offline-check --project "$project"
bash "$root/rust.sh" configure --feature tauri --operation install
[[ -f "$root/rust/tauri/README.txt" ]]
bash "$root/rust.sh" configure --feature tauri --operation prime --project "$project"
bash "$root/rust.sh" configure --feature tauri --operation offline-check --project "$project"
bash "$root/rust.sh" configure --feature tauri --operation remove
[[ ! -e "$root/rust/tauri/README.txt" ]]
bash "$root/nodejs.sh" reset --scope all --yes --project "$project"
[[ ! -e "$project/node_modules" ]]
[[ ! -d "$root/nodejs" ]]
echo 'Portable Node.js + Rust Tauri Facade smoke tests passed'
