#!/usr/bin/env bash
# Real Go install + prime + offline-check on a tiny module (Linux/WSL).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cp -a "$root/.build" "$scratch/"
kit="$scratch/.build"
proj="$scratch/mod"
mkdir -p "$proj"
cat >"$proj/go.mod" <<'EOF'
module example.com/pbkmod
go 1.22
EOF
cat >"$proj/main.go" <<'EOF'
package main
import "fmt"
func main() { fmt.Println("ok") }
EOF
cat >"$proj/main_test.go" <<'EOF'
package main
import "testing"
func TestOk(t *testing.T) {}
EOF

echo '[indep] install go...'
bash "$kit/go.sh" install
echo '[indep] verify...'
bash "$kit/go.sh" configure --mode verify
echo '[indep] prime...'
bash "$kit/go.sh" configure --mode prime --project "$proj"
echo '[indep] offline-check...'
bash "$kit/go.sh" configure --mode offline-check --project "$proj"
echo '[indep] run go version...'
bash "$kit/go.sh" configure --mode run -- go version
ver="$("$kit/go/sdk/bin/go" version)"
echo "[indep] $ver"
[[ "$ver" == *go1.27.2* ]] || { echo "unexpected version: $ver" >&2; exit 1; }
# shellcheck disable=SC1091
source "$kit/env.sh"
[[ "$GOPATH" == "$kit/go/path" ]] || { echo "GOPATH not isolated: $GOPATH" >&2; exit 1; }
echo 'INDEP Linux Go real-install: PASS'
