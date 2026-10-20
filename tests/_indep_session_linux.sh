#!/usr/bin/env bash
# Session source env.sh (not global) then run tools.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cp -a "$root/.build" "$scratch/"
kit="$scratch/.build"
bash "$kit/go.sh" install
bash "$kit/python.sh" install
bash "$kit/csharp.sh" install
# shellcheck disable=SC1091
source "$kit/env.sh"
go version
python --version
uv --version
dotnet --version
[[ "$GOROOT" == "$kit/go/sdk" ]] || { echo "GOROOT bad: $GOROOT"; exit 1; }
[[ "$DOTNET_ROOT" == "$kit/csharp/dotnet" ]] || { echo "DOTNET_ROOT bad"; exit 1; }
echo 'INDEP Linux session-env+run: PASS'
